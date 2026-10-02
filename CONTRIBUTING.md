# Contributing and releases

## Pull request titles

Use a [Conventional Commit](https://www.conventionalcommits.org/en/v1.0.0/)
title for every pull request. The release workflow reads the squash commit
message on `main`. Configure squash merges to use the pull request title as
the commit subject and include the branch's commit details in the body.
Scopes are optional and do not change the version bump.

| Pull request title | Library version change |
| --- | --- |
| `feat: add an accessor` | Minor |
| `fix(block): correct an offset` | Patch |
| `perf: reduce allocations` | Patch |
| `feat!:` or `fix(block)!:` followed by a description | Major |
| `docs:`, `test:`, `refactor:`, `chore:`, `ci:`, `build:`, or `style:` | None by itself |

Put `!` in the title for any breaking change, including a breaking refactor.
The default squash message includes commit details, but it does not copy the
pull request description. A `BREAKING CHANGE:` footer only in that description
is therefore not reliable release input. Keep the generated commit details
in the squash body and leave its Conventional Commit subject unchanged. If a
refactor or dependency change fixes a user-visible defect, use `fix:` instead
of its internal-work type.

A commit confined to `fuzz/`, `benchmarks/`, or `examples/` does not trigger
a library release. A commit that also touches the library, its tests, or its
documentation remains eligible according to its title. When several eligible
commits are pending, the highest SemVer bump wins.

## Repository setup

A repository administrator must:

1. Allow squash merging only and set the default squash commit message to
   **Pull request title and commit details**. The title becomes the squash
   commit subject; the branch's commit details remain in its body.
2. Require pull requests for `main` and add the
   `conventional PR title` check to its required checks. Keep the existing
   Erlang and JavaScript test checks required. The title check appears after
   this workflow has run on a pull request. It checks the pull request title;
   GitHub still allows editing the generated squash subject at merge time, so
   verify that the subject remains the checked title.
3. Add a repository secret named `RELEASE_PLEASE_TOKEN` containing a
   fine-grained token restricted to this repository, with **Contents**,
   **Pull requests**, and **Issues** read/write permissions. This token lets
   Release Please PRs run the normal CI workflows.

## Releasing

The root `gleam.toml` is the package version. Release Please also maintains
`version.txt` and `.release-please-manifest.json`; keep all three at the
same version. The standalone fuzz, benchmark, and example projects have
independent versions.

Release automation remains inactive until the first `v1.0.0` tag exists.
For the first Hex publication, finish the package and its required Erlang,
Node, Deno, and Bun tests, publish `1.0.0` from that exact commit, then tag
that commit `v1.0.0` and create its GitHub Release. Earlier commits are not
included in subsequent version calculations.

After that baseline, qualifying commits on `main` cause Release Please to
open or update a version pull request. Review and merge it when ready. The
workflow then creates the version tag and a **draft** GitHub Release. Run the
required release tests, publish the matching package from the tagged commit
to Hex, and publish the draft GitHub Release. Hex publication is manual.
