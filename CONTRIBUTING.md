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
pandoc image, the panvimdoc version, and the "Last change" date (taken from the
last commit via git, not the wall clock) — and CI runs this very same `make docs`
target and diffs the result, so the output is byte-identical by construction.
Commit `doc/autodap.txt` alongside the README change — CI fails when the
committed vimdoc is stale. (`doc/tags` is generated locally and gitignored; only
`doc/autodap.txt` is tracked.)

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

Two conventions apply to everything under `.github/workflows/`:

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

`zizmor` (via `qlty`) audits these files on any pull request that touches them.

## Commit messages

Short, imperative, with a conventional-ish prefix (`feat:`, `fix:`, `docs:`,
`ci:`, `chore:`). No `Co-authored-by` trailers.
