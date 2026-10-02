# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
