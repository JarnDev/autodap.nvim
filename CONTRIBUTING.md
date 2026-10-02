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

## Commit messages

Short, imperative, with a conventional-ish prefix (`feat:`, `fix:`, `docs:`,
`ci:`, `chore:`). No `Co-authored-by` trailers.
