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

This runs pandoc in Docker (no local pandoc needed) and produces output
byte-identical to what CI checks. Commit `doc/autodap.txt` (and `doc/tags`)
alongside the README change — CI fails when the committed vimdoc is stale.

### No "Last change" date in the header

panvimdoc normally stamps the generation date into the title line, which would
make the generated file depend on the clock rather than only on `README.md`:
a README change generated one day would fail `docs-check` the next, on that one
line, with an error telling you to run `make docs` (which would "fix" it until
tomorrow). So the date is switched off — `nodate` in
`.github/workflows/panvimdoc.yml`, `--metadata=nodate:true` in the `Makefile`.
Vim's `help-writing` calls that part of the header optional, and `git log` is a
better answer for when the docs last changed.

Both invocations have to carry the flag. `make docs` and the workflow are two
separate copies of the same panvimdoc call, and a flag set on one side but not
the other does not make the check pass — it makes it fail differently. Any
panvimdoc option you change belongs in both places, or neither.

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
