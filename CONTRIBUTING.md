# Contributing to autodap.nvim

## Development

Requirements: Neovim >= 0.10 and [nvim-dap](https://github.com/mfussenegger/nvim-dap).
Docker is used for the docs (see below).

Run the test suite:

```sh
make test
```

It clones `nvim-dap` into `tests/.deps/` on first run and exercises config
generation and target discovery headless against fixture projects — no live
debug session, so it needs no adapters installed.

Run the end-to-end check:

```sh
make test-e2e
```

`scripts/e2e.sh` builds a throwaway world in `$TMPDIR` — clean `XDG_*` dirs, a
Neovim config whose only plugins are nvim-dap and autodap (`tests/e2e/init.lua`,
installed with lazy.nvim exactly as the README documents), sample Python, Node
and C++ projects, and the three adapters: debugpy (the pure-python wheel),
js-debug, and codelldb (unpacked from its release `.vsix`), exposed under the
same `debugpy-adapter` / `js-debug-adapter` / `codelldb` names mason uses.
`tests/e2e/run.lua` then sets a breakpoint, calls
`require('autodap').continue()`, and asserts each session stops on the right
line, exposes locals, and runs to completion. It needs network and python3 — no
pip — and touches nothing outside the temp directory and the adapter cache.

Each language is gated on its toolchain and skipped with a printed reason rather
than failing:

| Language | Needs | Skipped when |
| --- | --- | --- |
| Python | `python3` | never — it is a hard requirement of the script |
| Node | `node` | node is not installed, or js-debug cannot be fetched |
| C/C++ | `c++`, `g++` or `clang++` | no compiler, or codelldb cannot be fetched |

The C/C++ half covers both shapes autodap handles: a built project with a
`compile_commands.json` (autodap finds `build/app`) and a lone `.c` file with no
build system at all (autodap compiles it with `-g` itself). Nothing but a
compiler is required — the sample is compiled directly by the script, so cmake
and make are not needed.

codelldb is a ~55 MB download, so it is cached outside `$TMPDIR` in
`$AUTODAP_E2E_CACHE` (default `${XDG_CACHE_HOME:-~/.cache}/autodap-e2e`) and
reused by later runs. Delete that directory to force a re-download. Set
`CODELLDB_VERSION` (also `DEBUGPY_VERSION`, `JS_DEBUG_VERSION`) to pin a
different release. An adapter already on `PATH` is used as-is and nothing is
downloaded.

Both suites run in CI on every push and pull request, and CI runs the C/C++ half
too: `ubuntu-latest` ships `g++`, and the workflow caches `~/.cache/autodap-e2e`
keyed on `CODELLDB_VERSION` so only the first run after a version bump pays for
the codelldb download. That version is pinned in both `.github/workflows/ci.yml`
and `scripts/e2e.sh` — bump them together, or the cache key stops matching what
is downloaded.

## Documentation

`doc/autodap.txt` (what `:help autodap` reads) is generated from `README.md`
with [panvimdoc](https://github.com/kdheepak/panvimdoc). It is committed, not
generated in CI.

After any change to `README.md`:

```sh
make docs
```

This runs pandoc in Docker (no local pandoc needed). Every input is pinned — the
pandoc image and the panvimdoc version — and CI runs this very same `make docs`
target and diffs the result, so the output is byte-identical by construction.
Commit `doc/autodap.txt` alongside the README change — CI fails when the
committed vimdoc is stale. (`doc/tags` is generated locally and gitignored; only
`doc/autodap.txt` is tracked.)

The title line carries no "Last change" date, on purpose (`nodate:true`). The
generated file has to match byte for byte on both sides, and you generate it
*before* you commit, so there is no date the two sides can agree on: the wall
clock differs by the day, `git log -1` is the commit before yours locally and
your own commit in CI, and on a pull request CI regenerates from GitHub's merge
commit, whose date moves whenever the base branch does. Dropping the stamp
leaves the output a function of `README.md` alone — the only thing that makes
the comparison meaningful. `git log -- doc/autodap.txt` answers "when did the
docs change" properly, and Vim's `help-writing` treats the date as optional.

When bumping `PANVIMDOC_REF` or `PANDOC_IMAGE`, run `make docs` and commit the
result in the same commit: a generator bump usually changes the output, and CI
compares against whatever is pinned on your branch.

## Releasing

Maintainer flow. Every commit and tag is GPG-signed by a human; CI never
creates commits or tags (that would need a private key in secrets).

1. Record user-facing changes under `## [Unreleased]` in `CHANGELOG.md` as you go.
2. Cut the release locally:
   ```sh
   make release VERSION=X.Y.Z       # bump CHANGELOG, signed commit + signed tag
   # make release-dry VERSION=X.Y.Z # preview the CHANGELOG bump, touches nothing
   ```
3. Review it: `git show vX.Y.Z`.
4. Publish: `git push origin main vX.Y.Z`.
5. The tag push triggers `.github/workflows/release.yml`, which publishes the
   GitHub Release — notes are the CHANGELOG section for that version plus the
   demo assets.

Notes:

- **Signing.** Commits and tags must be GPG-signed (`commit.gpgsign = true` and
  `git tag -s`). Never `--no-gpg-sign`; if signing fails, unlock the key and retry.
- **Workflow scope.** Pushing changes under `.github/workflows/` needs a token
  with the `workflow` scope. A normal release (tag push, no workflow edits) does not.

## Workflows

Three conventions apply to everything under `.github/workflows/`:

- **`persist-credentials: false` on every `actions/checkout`.** By default
  checkout writes the job's token into `.git/config` as an `http.extraheader`,
  where it stays for every later step and lands in anything that archives the
  workspace. None of the three jobs needs it there: `ci` and `panvimdoc` only
  read the checkout and clone their dependencies over anonymous https, and
  `release` reads `CHANGELOG.md` and the demo assets.
- **Hand the token to the one step that needs it.** `release.yml` passes it to
  `gh release create` as `GH_TOKEN: ${{ github.token }}`. Keep doing it that way
  rather than relying on a credential left in the config — if a new step needs to
  reach the remote, give it an explicit `env:` entry.
- **An explicit top-level `permissions:` block in every file.** With no block the
  token inherits the repository default, which can be write-all. `ci` and
  `panvimdoc` take `contents: read`; `release` needs `contents: write` to publish.
  Grant the narrowest scope the job actually uses.

`zizmor` (via `qlty`) audits these files on any pull request that touches them.

## Commit messages

Short, imperative, with a conventional-ish prefix (`feat:`, `fix:`, `docs:`,
`ci:`, `chore:`). No `Co-authored-by` trailers.
