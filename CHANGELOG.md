# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- End-to-end suite (`make test-e2e`): drives real debugpy and js-debug sessions
  from a throwaway Neovim config — breakpoint, locals, run to completion — and
  runs in CI alongside the config-generation tests.
- The end-to-end suite now covers C/C++ with real codelldb sessions, in both
  shapes autodap handles: a built project it discovers the executable in, and a
  lone `.c` file it compiles itself. Skipped with a printed reason when no
  compiler is present; CI runs it and caches the codelldb download.
- Single-file C/C++ auto-compile honors the nearest `compile_flags.txt` (the clangd convention):
  its flags (for example `-std=c++20` or `-Iinc`) are passed to the compiler, with relative paths
  resolved from that file's directory. The `-g -O0` debug flags still come last.
- TypeScript "Launch current file" works without `tsx`/`ts-node`: when neither is found (locally,
  hoisted or on PATH) and `node` is 22.18+ or 23.6+, the file runs on plain `node`, which strips
  types natively and keeps line/column positions, so breakpoints bind without source maps. A
  project with `tsx`/`ts-node` still uses it; older Node keeps the "install tsx" hint.

### Changed
- `:help autodap` no longer shows a "Last change" date on its title line. The
  date was the generation date, so `make docs` and the CI staleness check
  compared the documentation *and* a value that changes with the day or with
  which commit CI happens to check out. The vimdoc is now a function of
  `README.md` alone. Nothing else in the help text changed; the generator
  (panvimdoc) is pinned to v6.0.0, which also drops trailing whitespace from
  blank lines inside code blocks.

### Fixed
- `continue()` and `debug_test()` no longer refuse to start when *you* registered
  the adapter: the install guard only applies to adapters autodap registered itself.
- The "installing the adapter — run again once it finishes" notice is now only
  shown when an install actually started. With `auto_install = false`, or without
  mason, autodap names the package to install by hand instead.
- `:checkhealth autodap` inspected its own report buffer, so its "current buffer"
  section never described the file you were editing. It now reports on the file
  you came from, including the test under the cursor.
- `:checkhealth autodap` reports adapters owned by your own config as such, and
  distinguishes "will install on first use" from "will never be installed".

## [0.2.1] - 2026-10-02

### Fixed
- nvim-dap-ui no longer closes automatically when the debuggee exits. It opened
  and then immediately closed on the program finishing, hiding the final scopes,
  stack and REPL output. It now stays open for inspection; close it yourself
  with `require('dapui').close()`.

## [0.2.0] - 2026-10-02

### Added
- Auto-open [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) when a debug
  session starts and close it when the session ends, if it is installed. New
  `ui` option (`'auto'` by default; `false` to leave the UI to you). autodap
  does not call `dapui.setup()` for you.

## [0.1.0] - 2026-09-17

### Added
- Zero-config debugging over nvim-dap via a config _provider_ (composes with
  `launch.json` and user configs instead of overwriting).
- Node / JS / TS, Python, and C / C++ support with monorepo-aware roots
  (nearest `package.json` / `pyproject` / `CMakeLists`; hoisted `node_modules`
  and virtualenvs).
- C/C++ target discovery via the CMake File API with a bounded scan fallback,
  and auto-compilation of a lone `.c`/`.cpp` with `-g` when there is no build system.
- Lazy, on-demand adapter installation through mason (optional).
- Debug the test under the cursor for jest, vitest, and pytest
  (`require('autodap').debug_test()` / `:AutodapTest`).
- `:checkhealth autodap`.
- `python.venv` to pin the interpreter.

[Unreleased]: https://github.com/JarnDev/autodap.nvim/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/JarnDev/autodap.nvim/releases/tag/v0.2.1
[0.2.0]: https://github.com/JarnDev/autodap.nvim/releases/tag/v0.2.0
[0.1.0]: https://github.com/JarnDev/autodap.nvim/releases/tag/v0.1.0
