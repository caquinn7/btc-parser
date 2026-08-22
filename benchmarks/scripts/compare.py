#!/usr/bin/env python3
"""Compare aggregate benchmark CSVs from two btc_parser worktrees."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import math
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import statistics
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


TIMEOUT = 1_800
BASELINE, CANDIDATE = "baseline", "candidate"
VARIANTS = (BASELINE, CANDIDATE)
SCRIPT = Path(__file__).resolve()
BENCHMARKS = SCRIPT.parent.parent

AGGREGATE_HEADER = (
    "run_target", "run_runtime", "run_os", "run_architecture", "section",
    "case", "bytes", "warmup_ms", "duration_ms", "ops_per_timed_call",
    "timed_call_count", "measured_ms", "operations_per_second",
    "microseconds_per_operation",
)
COMPARISON_HEADER = (
    "section", "case", "bytes", "warmup_ms", "duration_ms",
    "ops_per_timed_call", "paired_rounds",
    "baseline_median_microseconds_per_operation",
    "candidate_median_microseconds_per_operation", "median_paired_ratio",
    "median_percentage_change",
)
INT_RULES = {
    "bytes": lambda n: n >= 0,
    "warmup_ms": lambda n: n >= 0,
    "duration_ms": lambda n: n > 0,
    "ops_per_timed_call": lambda n: n > 0,
    "timed_call_count": lambda n: n > 0,
}
FLOAT_FIELDS = (
    "measured_ms", "operations_per_second", "microseconds_per_operation",
)
RUN_METADATA = ("run_target", "run_runtime", "run_os", "run_architecture")
COMPARISON_METADATA = RUN_METADATA + (
    "bytes", "warmup_ms", "duration_ms", "ops_per_timed_call",
)
Identity = Tuple[str, str]
Row = Dict[str, object]


class Error(RuntimeError):
    pass


@dataclass(frozen=True)
class Config:
    baseline: Path
    candidate: Path
    sections: Tuple[str, ...]
    all_sections: bool
    target: str
    runtime: Optional[str]
    trials: int
    results_root: Path
    benchmarks: Path = BENCHMARKS


@dataclass(frozen=True)
class State:
    path: Path
    commit: str
    branch: Optional[str]
    status: str


@dataclass(frozen=True)
class Run:
    ordinal: int
    variant: str
    csv_path: Path
    rows: Dict[Identity, Row]


def trial_count(value: str) -> int:
    try:
        count = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError("must be an integer") from exc
    if count <= 0 or count % 4:
        raise argparse.ArgumentTypeError("must be a positive multiple of four")
    return count


def parse_args(argv: Optional[Sequence[str]] = None, *, cwd: Optional[Path] = None,
               benchmarks: Path = BENCHMARKS) -> Config:
    parser = argparse.ArgumentParser(
        description="Compare aggregate benchmarks from two btc_parser worktrees."
    )
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--candidate", required=True)
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument("--section", action="append", dest="sections")
    choice.add_argument("--all-sections", action="store_true")
    parser.add_argument("--target", choices=("erlang", "javascript"),
                        default="erlang")
    parser.add_argument("--runtime", choices=("node", "deno", "bun"))
    parser.add_argument(
        "--trials-per-variant", type=trial_count, default=4,
        help="trials for each variant; total runs are twice this value (default: 4)",
    )
    parser.add_argument("--results-root")
    args = parser.parse_args(argv)
    if args.target == "erlang" and args.runtime:
        parser.error("--runtime is only valid with --target javascript")
    sections = tuple(args.sections or ())
    if any(not item.strip() for item in sections):
        parser.error("--section values must not be empty")
    here = (cwd or Path.cwd()).resolve()

    def absolute(value: str) -> Path:
        path = Path(value).expanduser()
        return (path if path.is_absolute() else here / path).resolve()

    return Config(
        baseline=absolute(args.baseline), candidate=absolute(args.candidate),
        sections=sections, all_sections=args.all_sections, target=args.target,
        runtime=(args.runtime or "node") if args.target == "javascript" else None,
        trials=args.trials_per_variant,
        results_root=(absolute(args.results_root) if args.results_root else
                      (benchmarks / "results").resolve()),
        benchmarks=benchmarks.resolve(),
    )


def _text(value: object) -> str:
    if value is None:
        return ""
    return value.decode("utf-8", "replace") if isinstance(value, bytes) else str(value)


def run(command: Sequence[str], cwd: Path, *, log: Optional[Path] = None,
        ok: Iterable[int] = (0,)) -> subprocess.CompletedProcess:
    """Run a command; when log is supplied, diagnose every exit path."""
    started = time.monotonic()
    result = None
    caught = None
    try:
        result = subprocess.run(
            list(command), cwd=str(cwd), stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, encoding="utf-8", errors="replace",
            timeout=TIMEOUT, check=False,
        )
    except (subprocess.TimeoutExpired, KeyboardInterrupt, OSError, ValueError) as exc:
        caught = exc

    elapsed = time.monotonic() - started
    stdout = _text(result.stdout if result is not None else getattr(caught, "stdout", ""))
    stderr = _text(result.stderr if result is not None else getattr(caught, "stderr", ""))
    if result is not None:
        outcome = f"exit status {result.returncode}"
    elif isinstance(caught, subprocess.TimeoutExpired):
        outcome = f"timed out after {TIMEOUT} seconds"
    elif isinstance(caught, KeyboardInterrupt):
        outcome = "interrupted"
    else:
        outcome, stderr = "could not start", str(caught)

    if log:
        try:
            log.parent.mkdir(parents=True, exist_ok=True)
            log.write_text(
                f"command: {shlex.join(command)}\nworking directory: {cwd}\n"
                f"outcome: {outcome}\nelapsed seconds: {elapsed:.3f}\n\n"
                f"--- stdout ---\n{stdout}\n--- stderr ---\n{stderr}",
                encoding="utf-8",
            )
        except OSError as exc:
            if isinstance(caught, KeyboardInterrupt):
                raise caught
            raise Error(f"could not write process log {log}: {exc}") from exc

    joined = shlex.join(command)
    hint = f" (see {log})" if log else ""
    if isinstance(caught, KeyboardInterrupt):
        raise caught
    if isinstance(caught, subprocess.TimeoutExpired):
        raise Error(f"command timed out after {TIMEOUT} seconds: {joined}{hint}")
    if caught:
        raise Error(f"could not run {joined}: {caught}{hint}") from caught
    if result.returncode not in set(ok):
        detail = (stderr or stdout).strip()
        suffix = f": {detail}" if detail and not log else hint
        raise Error(f"command exited with status {result.returncode}: {joined}{suffix}")
    return result


def git(path: Path, *args: str, ok: Iterable[int] = (0,)) -> subprocess.CompletedProcess:
    return run(("git", "-C", str(path), *args), path, ok=ok)


ROOT_NAME = re.compile(
    r"^[ \t]*name[ \t]*=[ \t]*(?:\"btc_parser\"|'btc_parser')[ \t]*(?:#.*)?$",
    re.MULTILINE,
)


def worktree_state(path: Path) -> State:
    path = path.expanduser().resolve()
    if not path.is_dir():
        raise Error(f"worktree does not exist or is not a directory: {path}")
    top = git(path, "rev-parse", "--show-toplevel").stdout.strip()
    if not top or Path(top).resolve() != path:
        raise Error(f"path must be a Git worktree root: {path}")
    project = path / "gleam.toml"
    try:
        lines = project.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise Error(f"could not read {project}: {exc}") from exc
    root_lines = []
    for line in lines:
        if line.strip().startswith("["):
            break
        root_lines.append(line)
    if not ROOT_NAME.search("\n".join(root_lines)):
        raise Error(f"worktree gleam.toml does not declare package btc_parser: {project}")
    commit = git(path, "rev-parse", "HEAD").stdout.strip()
    if not commit:
        raise Error(f"Git did not report a commit for {path}")
    branch_result = git(path, "symbolic-ref", "--quiet", "--short", "HEAD", ok=(0, 1))
    branch = branch_result.stdout.strip() if branch_result.returncode == 0 else None
    status = git(path, "status", "--porcelain=v1", "--untracked-files=all").stdout.rstrip("\n")
    return State(path, commit, branch or None, status)


SECTION = re.compile(r"^[ \t]*\[([^]\r\n]+)\][ \t]*(?:#.*)?$")
PATH = re.compile(r"(\bpath[ \t]*=[ \t]*)(\"(?:\\.|[^\"\\])*\"|'[^']*')")


def rewrite_section(contents: str, section: str, dependency: str,
                    new_path: str, description: str) -> str:
    lines = contents.splitlines(keepends=True)
    current, matches = None, []
    dependency_line = re.compile(rf"^[ \t]*{re.escape(dependency)}[ \t]*=")
    for index, line in enumerate(lines):
        header = SECTION.fullmatch(line.rstrip("\r\n"))
        if header:
            current = header.group(1).strip()
        elif current == section and dependency_line.match(line):
            matches.append(index)
    if len(matches) != 1:
        raise Error(f"expected exactly one {dependency} in [{section}] of {description}")
    index = matches[0]
    paths = list(PATH.finditer(lines[index]))
    if len(paths) != 1 or paths[0].group(2) not in ('".."', "'..'"):
        raise Error(f'expected {description} to contain exactly one path = ".."')
    match = paths[0]
    lines[index] = (lines[index][:match.start(2)] + json.dumps(new_path, ensure_ascii=False) +
                    lines[index][match.end(2):])
    return "".join(lines)


def rewrite_wrapper(wrapper: Path, dependency: Path) -> None:
    """Rewrite the one Gleam and two generated-manifest path records."""
    gleam, manifest = wrapper / "gleam.toml", wrapper / "manifest.toml"
    try:
        gleam_text = rewrite_section(
            gleam.read_text(encoding="utf-8"), "dependencies", "btc_parser",
            str(dependency), "benchmark gleam.toml dependency",
        )
        text = manifest.read_text(encoding="utf-8")
        records = [match for match in re.finditer(r"\{[^{}]*\}", text, re.DOTALL)
                   if re.search(r'\bname\s*=\s*"btc_parser"', match.group())]
        if len(records) != 1 or not re.search(
            r'\bsource\s*=\s*"local"', records[0].group()
        ):
            raise Error("expected exactly one local btc_parser package record in manifest")
        record = records[0]
        paths = list(PATH.finditer(record.group()))
        if len(paths) != 1 or paths[0].group(2) not in ('".."', "'..'"):
            raise Error('expected manifest package record to contain one path = ".."')
        path_match = paths[0]
        changed_record = (record.group()[:path_match.start(2)] +
                          json.dumps(str(dependency), ensure_ascii=False) +
                          record.group()[path_match.end(2):])
        text = text[:record.start()] + changed_record + text[record.end():]
        manifest_text = rewrite_section(
            text, "requirements", "btc_parser", str(dependency),
            "benchmark manifest requirement",
        )
        gleam.write_text(gleam_text, encoding="utf-8")
        manifest.write_text(manifest_text, encoding="utf-8")
    except OSError as exc:
        raise Error(f"could not rewrite wrapper dependency in {wrapper}: {exc}") from exc


def snapshot(source: Path, destination: Path) -> None:
    if destination.exists():
        raise Error(f"harness snapshot destination already exists: {destination}")
    for name in ("gleam.toml", "manifest.toml"):
        if not (source / name).is_file():
            raise Error(f"benchmark harness is missing {source / name}")
    for name in ("src", "fixtures"):
        if not (source / name).is_dir():
            raise Error(f"benchmark harness is missing {source / name}")
    destination.mkdir(parents=True)
    for name in ("gleam.toml", "manifest.toml"):
        shutil.copy2(source / name, destination / name)
    for name in ("src", "fixtures"):
        shutil.copytree(source / name, destination / name)


def schedule(trials: int) -> Tuple[str, ...]:
    if trials <= 0 or trials % 4:
        raise ValueError("trials must be a positive multiple of four")
    return (BASELINE, CANDIDATE, CANDIDATE, BASELINE,
            CANDIDATE, BASELINE, BASELINE, CANDIDATE) * (trials // 4)


def read_csv(path: Path) -> Dict[Identity, Row]:
    try:
        with path.open("r", encoding="utf-8", newline="") as source:
            reader = csv.reader(source, strict=True)
            try:
                header = next(reader)
            except StopIteration as exc:
                raise Error(f"aggregate CSV is empty: {path}") from exc
            records = [(reader.line_num, values) for values in reader]
    except (OSError, csv.Error) as exc:
        raise Error(f"could not parse aggregate CSV {path}: {exc}") from exc
    if tuple(header) != AGGREGATE_HEADER:
        raise Error(f"aggregate CSV header does not match the current schema: {path}")
    rows: Dict[Identity, Row] = {}
    for line, values in records:
        if not values:
            continue
        if len(values) != len(AGGREGATE_HEADER):
            raise Error(
                f"{path}:{line}: expected {len(AGGREGATE_HEADER)} columns, "
                f"found {len(values)}"
            )
        row: Row = dict(zip(AGGREGATE_HEADER, values))
        identity = (str(row["section"]), str(row["case"]))
        if not all(value.strip() for value in identity + tuple(str(row[k]) for k in RUN_METADATA)):
            raise Error(f"{path}:{line}: identity and run metadata must not be empty")
        if identity in rows:
            raise Error(f"{path}:{line}: duplicate benchmark identity {identity!r}")
        for field, valid in INT_RULES.items():
            value = str(row[field])
            if not re.fullmatch(r"-?[0-9]+", value):
                raise Error(f"{path}:{line}: {field} is not an integer: {value!r}")
            try:
                number = int(value)
            except ValueError as exc:
                raise Error(f"{path}:{line}: {field} is not an integer: {row[field]!r}") from exc
            if not valid(number):
                qualifier = "nonnegative" if field in ("bytes", "warmup_ms") else "positive"
                raise Error(f"{path}:{line}: {field} must be {qualifier}")
            row[field] = number
        for field in FLOAT_FIELDS:
            value = str(row[field])
            if value != value.strip():
                raise Error(f"{path}:{line}: {field} is not a number: {value!r}")
            try:
                number = float(value)
            except ValueError as exc:
                raise Error(f"{path}:{line}: {field} is not a number: {row[field]!r}") from exc
            if not math.isfinite(number) or number <= 0:
                raise Error(f"{path}:{line}: {field} must be positive and finite")
            row[field] = number
        rows[identity] = row
    if not rows:
        raise Error(f"aggregate CSV contains no benchmark rows: {path}")
    return rows


def comparisons(runs: Sequence[Run], expected_target: str) -> List[Row]:
    if not runs:
        raise Error("no completed benchmark trials were supplied")
    expected_order = schedule(len(runs) // 2)
    actual_order = tuple(item.variant for item in runs)
    if actual_order != expected_order:
        raise Error("completed runs do not follow the ABBA/BAAB schedule")
    reference = runs[0].rows
    identities, case_set = tuple(reference), set(reference)
    first = next(iter(reference.values()))
    if first["run_target"] != expected_target:
        raise Error(f"aggregate target does not match requested target {expected_target!r}")
    metadata = tuple(first[field] for field in COMPARISON_METADATA)
    for item in runs:
        if set(item.rows) != case_set:
            missing, extra = case_set - set(item.rows), set(item.rows) - case_set
            raise Error(
                f"case set differs in {item.csv_path}: "
                f"missing {sorted(missing)!r}; extra {sorted(extra)!r}"
            )
        for identity, row in item.rows.items():
            actual = tuple(row[field] for field in COMPARISON_METADATA)
            expected = metadata[:4] + tuple(
                reference[identity][field] for field in COMPARISON_METADATA[4:]
            )
            if actual != expected:
                raise Error(f"comparison metadata differs in {item.csv_path} for {identity!r}")

    baseline = [item for item in runs if item.variant == BASELINE]
    candidate = [item for item in runs if item.variant == CANDIDATE]
    output: List[Row] = []
    for identity in identities:
        base_times = [float(item.rows[identity]["microseconds_per_operation"]) for item in baseline]
        candidate_times = [
            float(item.rows[identity]["microseconds_per_operation"])
            for item in candidate
        ]
        ratios = []
        for offset in range(0, len(runs), 2):
            pair = runs[offset:offset + 2]
            by_variant = {item.variant: item for item in pair}
            if set(by_variant) != set(VARIANTS):
                raise Error(
                    f"benchmark runs {offset + 1} and {offset + 2} "
                    "are not opposite variants"
                )
            base_time = float(by_variant[BASELINE].rows[identity]["microseconds_per_operation"])
            candidate_time = float(
                by_variant[CANDIDATE].rows[identity]["microseconds_per_operation"]
            )
            ratio = candidate_time / base_time
            if not math.isfinite(ratio) or ratio <= 0:
                raise Error(f"paired ratio is not positive and finite for {identity!r}")
            ratios.append(ratio)
        source = reference[identity]
        ratio = statistics.median(ratios)
        output.append({
            "section": identity[0], "case": identity[1],
            "bytes": source["bytes"], "warmup_ms": source["warmup_ms"],
            "duration_ms": source["duration_ms"],
            "ops_per_timed_call": source["ops_per_timed_call"],
            "paired_rounds": len(ratios),
            "baseline_median_microseconds_per_operation": statistics.median(base_times),
            "candidate_median_microseconds_per_operation": statistics.median(candidate_times),
            "median_paired_ratio": ratio,
            "median_percentage_change": (ratio - 1) * 100,
        })
    return output


def write_comparison(path: Path, rows: Sequence[Row]) -> None:
    try:
        with path.open("w", encoding="utf-8", newline="") as destination:
            writer = csv.DictWriter(destination, COMPARISON_HEADER, lineterminator="\n")
            writer.writeheader()
            for row in rows:
                writer.writerow({key: format(value, ".17g") if isinstance(value, float) else value
                                 for key, value in row.items()})
    except OSError as exc:
        raise Error(f"could not write comparison CSV {path}: {exc}") from exc


def markdown(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\r", " ").replace("\n", " ")


def state_report(label: str, state: State) -> str:
    status = state.status or "clean"
    indented = "\n".join("    " + line for line in (status.splitlines() or [""]))
    return (
        f"### {label}\n\n- Path: `{markdown(state.path)}`\n- Commit: `{state.commit}`\n"
        f"- Branch state: `{markdown(state.branch or 'detached HEAD')}`\n"
        "- Git status (`git status --porcelain=v1 --untracked-files=all`):\n\n"
        f"{indented}"
    )


def report(timestamp: str, command: str, config: Config, harness_commit: str,
           states: Dict[str, State], order: Sequence[str], runs: Sequence[Run],
           rows: Sequence[Row]) -> str:
    first = next(iter(runs[0].rows.values()))
    selectors = "all sections" if config.all_sections else ", ".join(
        f"`{markdown(item)}`" for item in config.sections)
    sections = list(dict.fromkeys(str(row["section"]) for row in rows))
    table = [
        "| Section | Case | Bytes | Baseline median us/op | "
        "Candidate median us/op | Median paired ratio | Change |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in rows:
        table.append(
            f'| {markdown(row["section"])} | {markdown(row["case"])} | {row["bytes"]} | '
            f'{float(row["baseline_median_microseconds_per_operation"]):.6g} | '
            f'{float(row["candidate_median_microseconds_per_operation"]):.6g} | '
            f'{float(row["median_paired_ratio"]):.6g} | '
            f'{float(row["median_percentage_change"]):+.3f}% |'
        )
    schedule_text = ", ".join(f"{n:03d}-{variant}" for n, variant in enumerate(order, 1))
    body = f"""# Benchmark comparison

- UTC timestamp: `{timestamp}`
- Target: `{config.target}`
- Selected runtime: `{markdown(config.runtime or 'not applicable (Erlang target)')}`
- Recorded runtime: `{markdown(first['run_runtime'])}`
- OS: `{markdown(first['run_os'])}`
- Architecture: `{markdown(first['run_architecture'])}`
- Section selectors: {selectors}
- Measured sections: {', '.join(f'`{markdown(item)}`' for item in sections)}
- Trials per variant: `{config.trials}`
- Total trial runs: `{len(runs)}`
- Paired rounds: `{len(runs) // 2}`
- Harness commit: `{harness_commit}`

## Command

    {command}

## Worktrees

{state_report('Baseline', states[BASELINE])}

{state_report('Candidate', states[CANDIDATE])}

## Schedule

    {schedule_text}

Adjacent runs form one baseline/candidate pair. Ratios are candidate microseconds
per operation divided by baseline microseconds per operation.

## Comparison

{chr(10).join(table)}

Independent variant medians summarize latency. The ratio and percentage change
are medians of adjacent paired ratios. A positive percentage means the candidate
was slower; a negative percentage means it was faster. These aggregate
comparisons are not significance tests or performance thresholds.
"""
    return body


def result_directory(root: Path, slug: str) -> Path:
    try:
        root.mkdir(parents=True, exist_ok=True)
        for number in range(1_000):
            path = root / (slug if not number else f"{slug}-{number:02d}")
            try:
                path.mkdir()
                return path
            except FileExistsError:
                pass
    except OSError as exc:
        raise Error(f"could not create results under {root}: {exc}") from exc
    raise Error(f"could not allocate a unique result directory under {root}")


def trial_command(config: Config, output: Path) -> List[str]:
    command = ["gleam", "run", "--target", config.target]
    if config.runtime:
        command += ["--runtime", config.runtime]
    command += ["--", "--format", "csv", "--out", str(output)]
    for section in config.sections:
        command += ["--section", section]
    return command


def remove_tree(path: Path) -> None:
    def retry(function, failed_path, _error_info):
        failed = Path(failed_path)
        for item in (failed, failed.parent):
            if item == path or path in item.parents:
                mode = os.stat(item).st_mode
                os.chmod(item, mode | stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)
        function(failed_path)

    shutil.rmtree(path, onerror=retry)


def execute(config: Config, command: str, now: Optional[dt.datetime] = None) -> Path:
    instant = now or dt.datetime.now(dt.timezone.utc)
    if instant.tzinfo is None:
        instant = instant.replace(tzinfo=dt.timezone.utc)
    instant = instant.astimezone(dt.timezone.utc).replace(microsecond=0)
    timestamp = instant.isoformat().replace("+00:00", "Z")
    destination = result_directory(config.results_root, instant.strftime("%Y%m%dT%H%M%SZ"))
    runs_dir = destination / "runs"
    primary_error: Optional[BaseException] = None
    cleanup_error: Optional[BaseException] = None
    temporary_root: Optional[Path] = None
    try:
        runs_dir.mkdir()
        states = {BASELINE: worktree_state(config.baseline),
                  CANDIDATE: worktree_state(config.candidate)}
        harness_commit = git(config.benchmarks.parent, "rev-parse", "HEAD").stdout.strip()
        if not harness_commit:
            raise Error(f"Git did not report a harness commit for {config.benchmarks.parent}")
        temporary_root = Path(tempfile.mkdtemp(prefix="btc-parser-benchmark-compare-"))
        try:
            wrappers = {}
            source = temporary_root / "snapshot"
            snapshot(config.benchmarks, source)
            for variant in VARIANTS:
                wrapper = temporary_root / variant
                shutil.copytree(source, wrapper)
                rewrite_wrapper(wrapper, states[variant].path)
                wrappers[variant] = wrapper
            for variant in VARIANTS:
                for label, setup in (
                    ("dependencies", ("gleam", "deps", "download")),
                    ("build", ("gleam", "build", "--target", config.target)),
                ):
                    run(setup, wrappers[variant], log=runs_dir / f"setup-{variant}-{label}.log")
            order, completed = schedule(config.trials), []
            for ordinal, variant in enumerate(order, 1):
                stem = f"{ordinal:03d}-{variant}"
                output = runs_dir / f"{stem}.csv"
                run(trial_command(config, output), wrappers[variant],
                    log=runs_dir / f"{stem}.log")
                completed.append(Run(ordinal, variant, output, read_csv(output)))
            rows = comparisons(completed, config.target)
            write_comparison(destination / "comparison.csv", rows)
            (destination / "report.md").write_text(
                report(timestamp, command, config, harness_commit, states, order,
                       completed, rows), encoding="utf-8")
        except BaseException as exc:
            primary_error = exc
        finally:
            try:
                remove_tree(temporary_root)
            except BaseException as exc:
                cleanup_error = exc
        if primary_error is not None:
            raise primary_error.with_traceback(primary_error.__traceback__)
        if cleanup_error is not None:
            raise Error(f"temporary wrapper cleanup failed: {cleanup_error}") from cleanup_error
    except BaseException as exc:
        reason = "comparison interrupted" if isinstance(exc, KeyboardInterrupt) else str(exc)
        if cleanup_error is not None and primary_error is not None:
            reason += f"; temporary wrapper cleanup failed: {cleanup_error}"
        try:
            (destination / "failure.txt").write_text(
                f"Benchmark comparison failed.\n\nUTC timestamp: {timestamp}\n"
                f"Command: {command}\nReason: {reason}\n", encoding="utf-8")
        except OSError as write_error:
            print(f"warning: could not write {destination / 'failure.txt'}: {write_error}",
                  file=sys.stderr)
        raise
    return destination


def main(argv: Optional[Sequence[str]] = None) -> int:
    if sys.version_info < (3, 9):
        print("compare.py requires Python 3.9 or newer", file=sys.stderr)
        return 2
    try:
        config = parse_args(argv)
        args = sys.argv if argv is None else (str(SCRIPT), *argv)
        destination = execute(config, shlex.join((sys.executable, *args)))
    except KeyboardInterrupt:
        print("benchmark comparison interrupted", file=sys.stderr)
        return 130
    except Error as exc:
        print(f"benchmark comparison failed: {exc}", file=sys.stderr)
        return 1
    except Exception as exc:
        print(
            f"benchmark comparison failed unexpectedly: {type(exc).__name__}: {exc}",
            file=sys.stderr,
        )
        return 1
    print(f"Benchmark comparison written to {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
