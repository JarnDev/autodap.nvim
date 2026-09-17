# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/JarnDev/autodap.nvim/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/JarnDev/autodap.nvim/releases/tag/v0.1.0
