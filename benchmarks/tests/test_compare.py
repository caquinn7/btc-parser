"""Behavior-focused tests for the aggregate benchmark comparison runner."""

from __future__ import annotations

from contextlib import redirect_stderr, redirect_stdout
import csv
import datetime as dt
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "compare.py"
SPEC = importlib.util.spec_from_file_location("btc_parser_benchmark_compare", SCRIPT)
if SPEC is None or SPEC.loader is None:  # pragma: no cover - importlib contract
    raise RuntimeError(f"could not load {SCRIPT}")
compare = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = compare
SPEC.loader.exec_module(compare)


AGGREGATE_HEADER = tuple(
    "run_target run_runtime run_os run_architecture section case bytes warmup_ms "
    "duration_ms ops_per_timed_call timed_call_count measured_ms "
    "operations_per_second microseconds_per_operation".split()
)
COMPARISON_HEADER = tuple(
    "section case bytes warmup_ms duration_ms ops_per_timed_call paired_rounds "
    "baseline_median_microseconds_per_operation "
    "candidate_median_microseconds_per_operation median_paired_ratio "
    "median_percentage_change".split()
)


def aggregate_record(**changes):
    row = {
        "run_target": "erlang", "run_runtime": "Erlang/OTP test",
        "run_os": "test-os", "run_architecture": "test-architecture",
        "section": "transaction.deserialize.fixtures",
        "case": "small legacy transaction", "bytes": "60", "warmup_ms": "250",
        "duration_ms": "1000", "ops_per_timed_call": "100",
        "timed_call_count": "25", "measured_ms": "1000.25",
        "operations_per_second": "2500.5", "microseconds_per_operation": "4.0",
    }
    row.update({key: str(value) for key, value in changes.items()})
    return row


def write_aggregate(path, records, header=AGGREGATE_HEADER):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as output:
        writer = csv.writer(output, lineterminator="\n")
        writer.writerow(header)
        for record in records:
            writer.writerow([record[column] for column in header])


def command(*arguments, cwd):
    return subprocess.run(
        ["git", *arguments],
        cwd=str(cwd),
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def make_repository(path, package_name="btc_parser"):
    path.mkdir()
    command("init", "--quiet", cwd=path)
    (path / "gleam.toml").write_text(
        f'name = "{package_name}"\nversion = "1.0.0"\n', encoding="utf-8"
    )
    (path / "tracked.txt").write_text("original\n", encoding="utf-8")
    command("add", "gleam.toml", "tracked.txt", cwd=path)
    command(
        "-c", "user.name=Benchmark Test", "-c",
        "user.email=benchmark@example.invalid", "-c", "commit.gpgsign=false",
        "commit", "--quiet", "--no-gpg-sign", "-m", "fixture", cwd=path,
    )
    return path


def visible_files(path):
    return {
        item.relative_to(path): item.read_bytes()
        for item in path.rglob("*")
        if item.is_file() and ".git" not in item.relative_to(path).parts
    }


class TemporaryDirectoryTestCase(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)


class ArgumentTests(TemporaryDirectoryTestCase):
    def test_defaults_repeated_sections_and_path_origins(self):
        caller = self.directory / "caller"
        caller.mkdir()
        harness = self.directory / "checkout" / "benchmarks"
        config = compare.parse_args(
            [
                "--baseline", "baseline", "--candidate", "../candidate",
                "--section", "transaction.deserialize", "--section",
                "block.compute-merkle-root",
            ],
            cwd=caller,
            benchmarks=harness,
        )

        self.assertEqual(config.baseline, (caller / "baseline").resolve())
        self.assertEqual(config.candidate, (caller / "../candidate").resolve())
        self.assertEqual(
            config.sections,
            ("transaction.deserialize", "block.compute-merkle-root"),
        )
        self.assertFalse(config.all_sections)
        self.assertEqual((config.target, config.runtime, config.trials), ("erlang", None, 4))
        self.assertEqual(config.results_root, (harness / "results").resolve())
        trial = compare.trial_command(config, self.directory / "run.csv")
        self.assertEqual(trial[:4], ["gleam", "run", "--target", "erlang"])
        self.assertEqual(trial.count("--section"), 2)

    def test_javascript_options_and_invalid_argument_combinations(self):
        config = compare.parse_args(
            [
                "--baseline", "base", "--candidate", "candidate", "--all-sections",
                "--target", "javascript", "--results-root", "reports",
                "--trials-per-variant", "8",
            ],
            cwd=self.directory,
        )
        self.assertTrue(config.all_sections)
        self.assertEqual(config.sections, ())
        self.assertEqual((config.target, config.runtime, config.trials), ("javascript", "node", 8))
        self.assertEqual(config.results_root, (self.directory / "reports").resolve())
        self.assertNotIn("--section", compare.trial_command(config, self.directory / "run.csv"))

        explicit = compare.parse_args(
            [
                "--baseline", "base", "--candidate", "candidate", "--section",
                "block", "--target", "javascript", "--runtime", "bun",
            ],
            cwd=self.directory,
        )
        self.assertEqual(explicit.runtime, "bun")
        self.assertIn("bun", compare.trial_command(explicit, self.directory / "run.csv"))

        common = ["--baseline", "base", "--candidate", "candidate"]
        invalid = (
            common,
            common + ["--section", "one", "--all-sections"],
            common + ["--section", ""],
            common + ["--section", "   "],
            common + ["--section", "one", "--runtime", "node"],
            common + ["--section", "one", "--target", "native"],
            common + ["--section", "one", "--target", "javascript", "--runtime", "browser"],
            common + ["--section", "one", "--trials-per-variant", "0"],
            common + ["--section", "one", "--trials-per-variant", "2"],
            common + ["--section", "one", "--trials-per-variant", "many"],
        )
        for arguments in invalid:
            with self.subTest(arguments=arguments), redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    compare.parse_args(arguments, cwd=self.directory)
                self.assertEqual(raised.exception.code, 2)

    def test_help_explains_per_variant_and_total_trial_counts(self):
        stdout = io.StringIO()
        with redirect_stdout(stdout), self.assertRaises(SystemExit) as raised:
            compare.parse_args(["--help"], cwd=self.directory)

        self.assertEqual(raised.exception.code, 0)
        help_text = " ".join(stdout.getvalue().split())
        self.assertIn(
            "trials for each variant; total runs are twice this value",
            help_text,
        )


class WorktreeTests(TemporaryDirectoryTestCase):
    def test_dirty_and_detached_states_are_captured_without_modification(self):
        repository = make_repository(self.directory / "repository")
        (repository / "tracked.txt").write_text("changed\n", encoding="utf-8")
        (repository / "untracked.txt").write_text("new\n", encoding="utf-8")
        before_files = visible_files(repository)
        before_status = command(
            "status", "--porcelain=v1", "--untracked-files=all", cwd=repository
        ).stdout.rstrip("\n")

        state = compare.worktree_state(repository)

        self.assertEqual(state.path, repository.resolve())
        self.assertEqual(state.commit, command("rev-parse", "HEAD", cwd=repository).stdout.strip())
        self.assertTrue(state.branch)
        self.assertEqual(state.status, before_status)
        self.assertEqual(visible_files(repository), before_files)
        self.assertEqual(
            command("status", "--porcelain=v1", "--untracked-files=all", cwd=repository).stdout.rstrip("\n"),
            before_status,
        )

        command("checkout", "--quiet", "--detach", cwd=repository)
        detached_files = visible_files(repository)
        detached_status = command(
            "status", "--porcelain=v1", "--untracked-files=all", cwd=repository
        ).stdout.rstrip("\n")
        detached = compare.worktree_state(repository)
        self.assertIsNone(detached.branch)
        self.assertEqual(detached.status, detached_status)
        self.assertEqual(visible_files(repository), detached_files)

    def test_invalid_worktrees_are_rejected(self):
        valid = make_repository(self.directory / "valid")
        (valid / "subdirectory").mkdir()
        wrong_package = make_repository(self.directory / "wrong", "another_package")
        dependency_only = make_repository(self.directory / "dependency-only")
        (dependency_only / "gleam.toml").write_text(
            'name = "another_package"\n[dependencies]\nbtc_parser = { path = ".." }\n',
            encoding="utf-8",
        )
        file_path = self.directory / "file"
        file_path.write_text("not a directory", encoding="utf-8")

        for path in (
            self.directory / "missing",
            file_path,
            valid / "subdirectory",
            wrong_package,
            dependency_only,
        ):
            with self.subTest(path=path), self.assertRaises(compare.Error):
                compare.worktree_state(path)


class SnapshotTests(TemporaryDirectoryTestCase):
    def test_snapshot_and_retarget_copy_only_the_current_harness_inputs(self):
        source = compare.BENCHMARKS
        original = {
            path.relative_to(source): path.read_bytes()
            for name in ("gleam.toml", "manifest.toml", "src", "fixtures")
            for path in ((source / name).rglob("*") if (source / name).is_dir() else (source / name,))
            if path.is_file()
        }
        snapshot = self.directory / "snapshot"
        compare.snapshot(source, snapshot)
        self.assertEqual(
            {path.name for path in snapshot.iterdir()},
            {"gleam.toml", "manifest.toml", "src", "fixtures"},
        )
        copied = {
            path.relative_to(snapshot): path.read_bytes()
            for path in snapshot.rglob("*")
            if path.is_file()
        }
        self.assertEqual(copied, original)

        wrapper = self.directory / "wrapper"
        shutil.copytree(snapshot, wrapper)
        dependency = self.directory / 'candidate "quoted" 🚀 worktree'
        compare.rewrite_wrapper(wrapper, dependency)
        quoted = json.dumps(str(dependency), ensure_ascii=False)
        gleam_before = (source / "gleam.toml").read_text(encoding="utf-8")
        manifest_before = (source / "manifest.toml").read_text(encoding="utf-8")
        gleam_after = (wrapper / "gleam.toml").read_text(encoding="utf-8")
        manifest_after = (wrapper / "manifest.toml").read_text(encoding="utf-8")
        self.assertEqual(gleam_after.count(quoted), 1)
        self.assertEqual(manifest_after.count(quoted), 2)
        self.assertEqual(gleam_after.replace(quoted, '".."'), gleam_before)
        self.assertEqual(manifest_after.replace(quoted, '".."'), manifest_before)
        self.assertEqual(
            {
                path.relative_to(source): path.read_bytes()
                for name in ("gleam.toml", "manifest.toml", "src", "fixtures")
                for path in ((source / name).rglob("*") if (source / name).is_dir() else (source / name,))
                if path.is_file()
            },
            original,
        )

    def test_retarget_rejects_missing_duplicate_and_wrong_expected_records(self):
        dependency = 'btc_parser = { path = ".." }\n'
        package = '{ name = "btc_parser", source = "local", path = ".." }'
        valid_gleam = "[dependencies]\n" + dependency
        valid_manifest = f"packages = [{package}]\n[requirements]\n{dependency}"
        cases = (
            ("missing Gleam dependency", "[dependencies]\n", valid_manifest),
            ("duplicate Gleam dependency", valid_gleam + dependency, valid_manifest),
            ("wrong Gleam path", valid_gleam.replace('".."', '"../other"'), valid_manifest),
            ("missing manifest package", valid_gleam, valid_manifest.replace(package, "")),
            ("duplicate manifest package", valid_gleam, valid_manifest.replace(package, f"{package}, {package}")),
            ("non-local manifest package", valid_gleam, valid_manifest.replace('source = "local"', 'source = "hex"')),
            ("wrong manifest package path", valid_gleam, valid_manifest.replace('path = ".."', 'path = "../other"', 1)),
            ("missing manifest requirement", valid_gleam, valid_manifest.replace(dependency, "")),
            ("duplicate manifest requirement", valid_gleam, valid_manifest + dependency),
            ("wrong manifest requirement path", valid_gleam, valid_manifest.replace(dependency, 'btc_parser = { path = "../other" }\n')),
        )
        for label, gleam, manifest in cases:
            with self.subTest(label=label):
                wrapper = self.directory / label.replace(" ", "-")
                wrapper.mkdir()
                (wrapper / "gleam.toml").write_text(gleam, encoding="utf-8")
                (wrapper / "manifest.toml").write_text(manifest, encoding="utf-8")
                with self.assertRaises(compare.Error):
                    compare.rewrite_wrapper(wrapper, self.directory / "candidate")


class ScheduleTests(unittest.TestCase):
    def test_schedule_repeats_balanced_abba_baab_blocks_with_adjacent_pairs(self):
        cycle = (
            compare.BASELINE,
            compare.CANDIDATE,
            compare.CANDIDATE,
            compare.BASELINE,
            compare.CANDIDATE,
            compare.BASELINE,
            compare.BASELINE,
            compare.CANDIDATE,
        )
        self.assertEqual(compare.schedule(4), cycle)
        self.assertEqual(compare.schedule(8), cycle * 2)
        order = compare.schedule(12)
        self.assertEqual(order.count(compare.BASELINE), 12)
        self.assertEqual(order.count(compare.CANDIDATE), 12)
        for offset in range(0, len(order), 2):
            self.assertEqual(set(order[offset : offset + 2]), set(compare.VARIANTS))


class CsvAndComparisonTests(TemporaryDirectoryTestCase):
    def make_runs(self, mutation=None):
        runs = []
        for ordinal, variant in enumerate(compare.schedule(4), 1):
            records = [
                aggregate_record(section="section-a", case="case-a"),
                aggregate_record(section="section-b", case="case-b", bytes=120),
            ]
            if mutation is not None and ordinal == 2:
                mutation(records)
            path = self.directory / f"{ordinal:03d}-{variant}.csv"
            write_aggregate(path, records)
            runs.append(compare.Run(ordinal, variant, path, compare.read_csv(path)))
        return runs

    def test_csv_parsing_reordering_and_directional_paired_medians(self):
        latencies = (10.0, 20.0, 30.0, 10.0, 12.0, 8.0, 20.0, 10.0)
        runs = []
        for ordinal, (variant, latency) in enumerate(
            zip(compare.schedule(4), latencies), 1
        ):
            records = [
                aggregate_record(
                    section="section-a",
                    case="case-a",
                    timed_call_count=ordinal,
                    measured_ms=1000 + ordinal,
                    operations_per_second=2000 + ordinal,
                    microseconds_per_operation=latency,
                ),
                aggregate_record(
                    section="section-b",
                    case="case-b",
                    bytes=120,
                    timed_call_count=ordinal + 10,
                    measured_ms=2000 + ordinal,
                    operations_per_second=3000 + ordinal,
                    microseconds_per_operation=latency * 2,
                ),
            ]
            if ordinal % 2 == 0:
                records.reverse()
            path = self.directory / f"{ordinal:03d}-{variant}.csv"
            write_aggregate(path, records)
            runs.append(compare.Run(ordinal, variant, path, compare.read_csv(path)))

        rows = compare.comparisons(runs, "erlang")

        self.assertEqual([(row["section"], row["case"]) for row in rows], [
            ("section-a", "case-a"),
            ("section-b", "case-b"),
        ])
        for row, baseline, candidate in ((rows[0], 10.0, 16.0), (rows[1], 20.0, 32.0)):
            self.assertEqual(row["paired_rounds"], 4)
            self.assertEqual(row["baseline_median_microseconds_per_operation"], baseline)
            self.assertEqual(row["candidate_median_microseconds_per_operation"], candidate)
            self.assertEqual(row["median_paired_ratio"], 1.75)
            self.assertEqual(row["median_percentage_change"], 75.0)

    def test_invalid_aggregate_csvs_are_rejected(self):
        cases = {
            "header only": ([], AGGREGATE_HEADER),
            "wrong header": ([aggregate_record()], tuple(reversed(AGGREGATE_HEADER))),
            "duplicate identity": ([aggregate_record(), aggregate_record()], AGGREGATE_HEADER),
            "empty identity": ([aggregate_record(section=" ")], AGGREGATE_HEADER),
            "empty metadata": ([aggregate_record(run_runtime="")], AGGREGATE_HEADER),
            "noninteger bytes": ([aggregate_record(bytes="many")], AGGREGATE_HEADER),
            "negative bytes": ([aggregate_record(bytes=-1)], AGGREGATE_HEADER),
            "negative warmup": ([aggregate_record(warmup_ms=-1)], AGGREGATE_HEADER),
            "zero duration": ([aggregate_record(duration_ms=0)], AGGREGATE_HEADER),
            "zero operations": ([aggregate_record(ops_per_timed_call=0)], AGGREGATE_HEADER),
            "zero timed calls": ([aggregate_record(timed_call_count=0)], AGGREGATE_HEADER),
            "nonfinite measured time": ([aggregate_record(measured_ms="nan")], AGGREGATE_HEADER),
            "nonfinite throughput": ([aggregate_record(operations_per_second="inf")], AGGREGATE_HEADER),
            "zero latency": ([aggregate_record(microseconds_per_operation=0)], AGGREGATE_HEADER),
        }
        empty = self.directory / "empty.csv"
        empty.write_text("", encoding="utf-8")
        with self.assertRaises(compare.Error):
            compare.read_csv(empty)

        for index, (label, (records, header)) in enumerate(cases.items()):
            with self.subTest(label=label):
                path = self.directory / f"invalid-{index}.csv"
                write_aggregate(path, records, header)
                with self.assertRaises(compare.Error):
                    compare.read_csv(path)

        wrong_columns = self.directory / "wrong-columns.csv"
        with wrong_columns.open("w", encoding="utf-8", newline="") as output:
            writer = csv.writer(output)
            writer.writerow(AGGREGATE_HEADER)
            writer.writerow(["too", "few"])
        malformed = self.directory / "malformed.csv"
        malformed.write_text(
            ",".join(AGGREGATE_HEADER) + "\n\"erlang\"unexpected," + ",".join(
                aggregate_record()[field] for field in AGGREGATE_HEADER[1:]
            ),
            encoding="utf-8",
        )
        for path in (wrong_columns, malformed):
            with self.subTest(path=path), self.assertRaises(compare.Error):
                compare.read_csv(path)

    def test_case_sets_and_all_required_cross_run_metadata_must_match(self):
        mutations = {
            "case set": lambda rows: rows[1].update(case="replacement"),
            "target": lambda rows: rows[0].update(run_target="javascript"),
            "runtime": lambda rows: rows[0].update(run_runtime="different"),
            "OS": lambda rows: rows[0].update(run_os="different"),
            "architecture": lambda rows: rows[0].update(run_architecture="different"),
            "bytes": lambda rows: rows[0].update(bytes="61"),
            "warmup": lambda rows: rows[0].update(warmup_ms="251"),
            "duration": lambda rows: rows[0].update(duration_ms="1001"),
            "operations per call": lambda rows: rows[0].update(ops_per_timed_call="101"),
        }
        for label, mutation in mutations.items():
            with self.subTest(label=label), self.assertRaises(compare.Error):
                compare.comparisons(self.make_runs(mutation), "erlang")
        with self.assertRaises(compare.Error):
            compare.comparisons(self.make_runs(), "javascript")


class ProcessTests(TemporaryDirectoryTestCase):
    def test_commands_use_the_fixed_timeout_and_log_success_failure_timeout_and_interrupt(self):
        successful = subprocess.CompletedProcess(
            ["gleam", "build"], 0, "standard output", "standard error"
        )
        success_log = self.directory / "success.log"
        with mock.patch.object(compare.subprocess, "run", return_value=successful) as process:
            compare.run(("gleam", "build"), self.directory, log=success_log)
        self.assertEqual(process.call_args.kwargs["timeout"], 1800)
        self.assertIn("standard output", success_log.read_text(encoding="utf-8"))
        self.assertIn("standard error", success_log.read_text(encoding="utf-8"))

        failures = (
            (
                "nonzero",
                subprocess.CompletedProcess(["gleam", "run"], 23, "partial out", "failure detail"),
                compare.Error,
                ("partial out", "failure detail"),
            ),
            (
                "timeout",
                subprocess.TimeoutExpired(
                    ["gleam", "run"], 1800, output=b"partial out \xff", stderr=b"partial err"
                ),
                compare.Error,
                ("partial out \ufffd", "partial err"),
            ),
            ("start", FileNotFoundError("no gleam"), compare.Error, ("no gleam",)),
            ("interrupt", KeyboardInterrupt(), KeyboardInterrupt, ("interrupted",)),
        )
        for label, outcome, error_type, fragments in failures:
            with self.subTest(label=label):
                log = self.directory / f"{label}.log"
                behavior = {"return_value": outcome} if isinstance(
                    outcome, subprocess.CompletedProcess
                ) else {"side_effect": outcome}
                with mock.patch.object(compare.subprocess, "run", **behavior):
                    with self.assertRaises(error_type):
                        compare.run(("gleam", "run"), self.directory, log=log)
                contents = log.read_text(encoding="utf-8")
                for fragment in fragments:
                    self.assertIn(fragment, contents)


class ExecutionTests(TemporaryDirectoryTestCase):
    NOW = dt.datetime(2026, 8, 15, 17, 30, 45, tzinfo=dt.timezone.utc)

    def inputs(self, *, target="erlang", runtime=None):
        baseline = make_repository(self.directory / "baseline")
        candidate = make_repository(self.directory / "candidate")
        (baseline / "tracked.txt").write_text("dirty baseline\n", encoding="utf-8")
        (baseline / "untracked.txt").write_text("untracked\n", encoding="utf-8")
        command("checkout", "--quiet", "--detach", cwd=candidate)
        return compare.Config(
            baseline,
            candidate,
            ("transaction.deserialize.fixtures", "block.compute-merkle-root"),
            False,
            target,
            runtime,
            4,
            self.directory / "results",
            compare.BENCHMARKS,
        )

    @staticmethod
    def fake_runner(original, calls, rewritten, *, fail_trial=None, interrupt_trial=None):
        trial_number = 0

        def fake(command_line, cwd, *, log=None, ok=(0,)):
            nonlocal trial_number
            command_line = list(command_line)
            if command_line[0] == "git":
                return original(command_line, cwd, log=log, ok=ok)
            calls.append((command_line, cwd, log))
            if log:
                log.parent.mkdir(parents=True, exist_ok=True)
                log.write_text("simulated stdout\nsimulated stderr\n", encoding="utf-8")
            if command_line[:3] == ["gleam", "deps", "download"]:
                rewritten[cwd.name] = (
                    (cwd / "gleam.toml").read_text(encoding="utf-8"),
                    (cwd / "manifest.toml").read_text(encoding="utf-8"),
                )
                if cwd.name == compare.BASELINE:
                    (cwd / "src").chmod(0o500)
            if command_line[:2] == ["gleam", "run"]:
                trial_number += 1
                if trial_number == interrupt_trial:
                    raise KeyboardInterrupt
                if trial_number == fail_trial:
                    raise compare.Error("synthetic trial failure")
                output = Path(command_line[command_line.index("--out") + 1])
                target = command_line[command_line.index("--target") + 1]
                runtime = "Node test" if target == "javascript" else "Erlang/OTP test"
                latency = 1 if cwd.name == compare.BASELINE else 2
                write_aggregate(
                    output,
                    [
                        aggregate_record(
                            run_target=target,
                            run_runtime=runtime,
                            microseconds_per_operation=latency,
                        )
                    ],
                )
            return subprocess.CompletedProcess(command_line, 0, "", "")

        return fake

    def test_success_runs_fresh_balanced_processes_and_writes_complete_outputs(self):
        config = self.inputs(target="javascript", runtime="node")
        before = {
            path: (visible_files(path), command("status", "--porcelain=v1", "--untracked-files=all", cwd=path).stdout)
            for path in (config.baseline, config.candidate)
        }
        calls, rewritten = [], {}
        original = compare.run
        fake = self.fake_runner(original, calls, rewritten)
        with mock.patch.object(compare, "run", side_effect=fake):
            result = compare.execute(config, "python3 compare.py test", self.NOW)

        self.assertEqual(result, config.results_root / "20260815T173045Z")
        self.assertFalse((result / "failure.txt").exists())
        setup = [item for item in calls if item[0][:2] != ["gleam", "run"]]
        trials = [item for item in calls if item[0][:2] == ["gleam", "run"]]
        self.assertEqual(len(setup), 4)
        self.assertEqual(len(trials), 8)
        self.assertEqual([cwd.name for _, cwd, _ in trials], list(compare.schedule(4)))
        for command_line, _, _ in trials:
            self.assertIn("javascript", command_line)
            self.assertIn("node", command_line)
            self.assertEqual(command_line.count("--section"), 2)
        for _, cwd, _ in calls:
            self.assertFalse(cwd.exists())

        runs = result / "runs"
        self.assertEqual(len(list(runs.glob("[0-9][0-9][0-9]-*.csv"))), 8)
        self.assertEqual(len(list(runs.glob("[0-9][0-9][0-9]-*.log"))), 8)
        self.assertEqual(len(list(runs.glob("setup-*.log"))), 4)
        with (result / "comparison.csv").open("r", encoding="utf-8", newline="") as source:
            output = list(csv.reader(source))
        self.assertEqual(tuple(output[0]), COMPARISON_HEADER)
        self.assertEqual(output[1][6:], ["4", "1", "2", "2", "100"])

        report = (result / "report.md").read_text(encoding="utf-8")
        required = (
            "2026-08-15T17:30:45Z",
            "python3 compare.py test",
            "javascript",
            "node",
            "transaction.deserialize.fixtures",
            "block.compute-merkle-root",
            str(config.baseline),
            str(config.candidate),
            " M tracked.txt",
            "detached HEAD",
            "001-baseline, 002-candidate, 003-candidate, 004-baseline",
            "Total trial runs: `8`",
            "small legacy transaction",
            "not significance tests",
        )
        for fragment in required:
            self.assertIn(fragment, report)
        self.assertEqual(set(rewritten), set(compare.VARIANTS))
        self.assertEqual(rewritten[compare.BASELINE][0].count(str(config.baseline)), 1)
        self.assertEqual(rewritten[compare.BASELINE][1].count(str(config.baseline)), 2)
        self.assertEqual(rewritten[compare.CANDIDATE][0].count(str(config.candidate)), 1)
        self.assertEqual(rewritten[compare.CANDIDATE][1].count(str(config.candidate)), 2)
        for path, (files, status) in before.items():
            self.assertEqual(visible_files(path), files)
            self.assertEqual(
                command("status", "--porcelain=v1", "--untracked-files=all", cwd=path).stdout,
                status,
            )

    def test_mid_trial_failure_retains_diagnostics_and_cleans_wrappers(self):
        config = self.inputs()
        calls, rewritten = [], {}
        original = compare.run
        fake = self.fake_runner(original, calls, rewritten, fail_trial=3)
        with mock.patch.object(compare, "run", side_effect=fake):
            with self.assertRaises(compare.Error):
                compare.execute(config, "python3 compare.py failure", self.NOW)

        result = config.results_root / "20260815T173045Z"
        self.assertTrue((result / "runs" / "001-baseline.csv").is_file())
        self.assertTrue((result / "runs" / "002-candidate.csv").is_file())
        self.assertTrue((result / "runs" / "003-candidate.log").is_file())
        self.assertFalse((result / "comparison.csv").exists())
        self.assertFalse((result / "report.md").exists())
        failure = (result / "failure.txt").read_text(encoding="utf-8")
        self.assertIn("python3 compare.py failure", failure)
        self.assertIn("synthetic trial failure", failure)
        for _, cwd, _ in calls:
            self.assertFalse(cwd.exists())

    def test_interruption_retains_failure_diagnostics_and_cleans_wrappers(self):
        config = self.inputs()
        calls, rewritten = [], {}
        original = compare.run
        fake = self.fake_runner(original, calls, rewritten, interrupt_trial=1)
        with mock.patch.object(compare, "run", side_effect=fake):
            with self.assertRaises(KeyboardInterrupt):
                compare.execute(config, "python3 compare.py interrupted", self.NOW)

        result = config.results_root / "20260815T173045Z"
        failure = (result / "failure.txt").read_text(encoding="utf-8")
        self.assertIn("comparison interrupted", failure)
        for _, cwd, _ in calls:
            self.assertFalse(cwd.exists())

    def test_early_validation_failure_is_retained_and_main_returns_nonzero(self):
        config = compare.Config(
            self.directory / "missing-baseline",
            self.directory / "missing-candidate",
            ("block",),
            False,
            "erlang",
            None,
            4,
            self.directory / "results",
            compare.BENCHMARKS,
        )
        with mock.patch.object(
            compare, "worktree_state", side_effect=compare.Error("invalid worktree")
        ), mock.patch.object(compare.tempfile, "mkdtemp") as temporary:
            with self.assertRaises(compare.Error):
                compare.execute(config, "python3 compare.py invalid", self.NOW)
        temporary.assert_not_called()
        result = config.results_root / "20260815T173045Z"
        self.assertTrue((result / "runs").is_dir())
        self.assertIn("invalid worktree", (result / "failure.txt").read_text(encoding="utf-8"))

        with mock.patch.object(compare, "parse_args", return_value=config), mock.patch.object(
            compare, "execute", side_effect=compare.Error("failed subprocess")
        ), redirect_stderr(io.StringIO()) as stderr:
            self.assertEqual(compare.main(["arguments"]), 1)
        self.assertIn("failed subprocess", stderr.getvalue())

        with mock.patch.object(compare, "parse_args", return_value=config), mock.patch.object(
            compare, "execute", side_effect=KeyboardInterrupt
        ), redirect_stderr(io.StringIO()):
            self.assertEqual(compare.main(["arguments"]), 130)


if __name__ == "__main__":
    unittest.main()
