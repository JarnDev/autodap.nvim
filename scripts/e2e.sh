#!/usr/bin/env bash
# End-to-end check: drive real debug sessions from a clean Neovim config.
#
# Everything happens in a throwaway directory:
#   - a sample Python project (pyproject.toml, a virtualenv, one source file), a
#     sample Node project (package.json with a script, one source file) and a
#     sample C++ project (Makefile, one source file, built with -g)
#   - a Neovim config whose only plugins are nvim-dap and autodap (tests/e2e/init.lua)
#   - debugpy, downloaded as the pure-python wheel and exposed as `debugpy-adapter`,
#     js-debug, downloaded and exposed as `js-debug-adapter`, and codelldb,
#     unpacked from its release .vsix and exposed as `codelldb` — the same binary
#     names mason installs (no pip, no system changes)
#
# Then tests/e2e/run.lua sets a breakpoint, presses <F5>, and asserts each session
# stops on the right line, exposes locals, and runs to completion.
#
# A language whose toolchain is missing is skipped with a reason rather than
# failing: node needs `node`, C/C++ needs a compiler and `make`.
#
# Usage: make test-e2e   (or scripts/e2e.sh)
set -euo pipefail

DEBUGPY_VERSION="${DEBUGPY_VERSION:-1.8.22}"
JS_DEBUG_VERSION="${JS_DEBUG_VERSION:-v1.140.0}"
CODELLDB_VERSION="${CODELLDB_VERSION:-v1.12.3}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# codelldb is a ~55 MB download, so it is cached outside the throwaway directory
# and reused across runs. Resolved before the XDG_* overrides below so it lands
# in the real cache dir, not the temporary one. CI caches this same path.
E2E_CACHE="${AUTODAP_E2E_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/autodap-e2e}"

command -v nvim >/dev/null || { echo "e2e: neovim is required" >&2; exit 1; }
command -v git >/dev/null || { echo "e2e: git is required" >&2; exit 1; }
PYTHON="${PYTHON:-python3}"
command -v "$PYTHON" >/dev/null || { echo "e2e: python3 is required" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo "e2e: working in $WORK"

# ---- sample project ---------------------------------------------------------
PROJ="$WORK/sample-project"
mkdir -p "$PROJ/src"
cat > "$PROJ/pyproject.toml" <<'EOF'
[project]
name = "autodap-e2e-sample"
version = "0.1.0"
EOF
cat > "$PROJ/src/main.py" <<'EOF'
def add(a, b):
    total = a + b
    return total


if __name__ == "__main__":
    print(add(2, 3))
EOF
# --without-pip keeps this working on systems that ship no ensurepip. autodap
# only has to *find* this interpreter; debugpy is injected by the adapter.
"$PYTHON" -m venv --without-pip "$PROJ/.venv"
"$PROJ/.venv/bin/python" -c 'import sys; sys.exit(0)'

# ---- debug adapter ----------------------------------------------------------
# Reuse an installed adapter when there is one; otherwise fetch the pure-python
# debugpy wheel and wrap it in the `debugpy-adapter` shim mason would provide.
mkdir -p "$WORK/bin"
if command -v debugpy-adapter >/dev/null; then
  echo "e2e: using debugpy-adapter from PATH"
else
  echo "e2e: fetching debugpy $DEBUGPY_VERSION"
  DEBUGPY_VERSION="$DEBUGPY_VERSION" DEST="$WORK/debugpy-lib" "$PYTHON" - <<'PY'
import io, json, os, urllib.request, zipfile

version = os.environ["DEBUGPY_VERSION"]
meta = json.load(urllib.request.urlopen(f"https://pypi.org/pypi/debugpy/{version}/json"))
url = next(f["url"] for f in meta["urls"] if f["filename"].endswith("py2.py3-none-any.whl"))
zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(url).read())).extractall(os.environ["DEST"])
PY
  cat > "$WORK/bin/debugpy-adapter" <<EOF
#!/bin/sh
PYTHONPATH="$WORK/debugpy-lib" exec "$PYTHON" -m debugpy.adapter "\$@"
EOF
  chmod +x "$WORK/bin/debugpy-adapter"
  PATH="$WORK/bin:$PATH"
  export PATH
fi

# ---- sample node project + adapter (skipped when node is unavailable) --------
NODE_PROJ=""
if command -v node >/dev/null; then
  NODE_PROJ="$WORK/nodeproj"
  mkdir -p "$NODE_PROJ/src"
  cat > "$NODE_PROJ/package.json" <<'EOF'
{ "name": "autodap-e2e-node", "version": "1.0.0", "scripts": { "start": "node src/index.js" } }
EOF
  cat > "$NODE_PROJ/src/index.js" <<'EOF'
function add(a, b) {
  const total = a + b;
  return total;
}

console.log(add(2, 3));
EOF
  if command -v js-debug-adapter >/dev/null; then
    echo "e2e: using js-debug-adapter from PATH"
  else
    echo "e2e: fetching js-debug $JS_DEBUG_VERSION"
    if curl -fsSL -o "$WORK/js-debug.tar.gz" \
      "https://github.com/microsoft/vscode-js-debug/releases/download/$JS_DEBUG_VERSION/js-debug-dap-$JS_DEBUG_VERSION.tar.gz"
    then
      tar -xzf "$WORK/js-debug.tar.gz" -C "$WORK"
      cat > "$WORK/bin/js-debug-adapter" <<EOF
#!/bin/sh
exec node "$WORK/js-debug/src/dapDebugServer.js" "\$@"
EOF
      chmod +x "$WORK/bin/js-debug-adapter"
      PATH="$WORK/bin:$PATH"
      export PATH
    else
      echo "e2e: could not fetch js-debug — skipping the node session" >&2
      NODE_PROJ=""
    fi
  fi
else
  echo "e2e: node not installed — skipping the node session"
fi

# ---- sample c++ project + codelldb (skipped without a compiler) -------------
# Two shapes, because autodap resolves the program differently for each:
#   cppproj/  a built tree with compile_commands.json — autodap discovers build/app
#   lonec/    a single .c file with no build system — autodap compiles it itself
# Only a compiler is needed: the sample is compiled here, not by cmake or make.
CPP_PROJ=""
CPP_LONE=""
CPP_SKIP=""

CXX_BIN="${CXX:-}"
if [ -z "$CXX_BIN" ]; then
  for c in c++ g++ clang++; do
    if command -v "$c" >/dev/null; then CXX_BIN="$c"; break; fi
  done
fi
if [ -z "$CXX_BIN" ]; then
  CPP_SKIP="no C++ compiler on PATH (looked for c++, g++, clang++)"
fi

# The .vsix is a zip; python unpacks it so no `unzip` is needed, and the mode
# bits have to be restored by hand because zipfile drops them.
extract_vsix() {
  SRC="$1" DEST="$2" "$PYTHON" - <<'PY'
import os, zipfile

src, dest = os.environ["SRC"], os.environ["DEST"]
with zipfile.ZipFile(src) as z:
    for info in z.infolist():
        path = z.extract(info, dest)
        mode = (info.external_attr >> 16) & 0o7777
        if mode:
            os.chmod(path, mode)
PY
}

if [ -z "$CPP_SKIP" ]; then
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)          CODELLDB_TARGET="linux-x64" ;;
    Linux-aarch64|Linux-arm64) CODELLDB_TARGET="linux-arm64" ;;
    Darwin-x86_64)         CODELLDB_TARGET="darwin-x64" ;;
    Darwin-arm64)          CODELLDB_TARGET="darwin-arm64" ;;
    *)                     CODELLDB_TARGET="" ;;
  esac

  if command -v codelldb >/dev/null; then
    echo "e2e: using codelldb from PATH"
  elif [ -z "$CODELLDB_TARGET" ]; then
    CPP_SKIP="no codelldb release for $(uname -s)-$(uname -m)"
  else
    VSIX="$E2E_CACHE/codelldb-$CODELLDB_VERSION-$CODELLDB_TARGET.vsix"
    if [ -f "$VSIX" ]; then
      echo "e2e: using the cached codelldb $CODELLDB_VERSION download"
    else
      echo "e2e: fetching codelldb $CODELLDB_VERSION ($CODELLDB_TARGET, ~55MB — cached in $E2E_CACHE)"
      mkdir -p "$E2E_CACHE"
      if curl -fsSL -o "$VSIX.part" \
        "https://github.com/vadimcn/codelldb/releases/download/$CODELLDB_VERSION/codelldb-$CODELLDB_TARGET.vsix"
      then
        mv "$VSIX.part" "$VSIX"
      else
        rm -f "$VSIX.part"
        CPP_SKIP="could not fetch codelldb $CODELLDB_VERSION"
      fi
    fi
    if [ -z "$CPP_SKIP" ]; then
      extract_vsix "$VSIX" "$WORK/codelldb"
      cat > "$WORK/bin/codelldb" <<EOF
#!/bin/sh
exec "$WORK/codelldb/extension/adapter/codelldb" "\$@"
EOF
      chmod +x "$WORK/bin/codelldb"
      PATH="$WORK/bin:$PATH"
      export PATH
    fi
  fi
fi

if [ -z "$CPP_SKIP" ]; then
  CPP_PROJ="$WORK/cppproj"
  mkdir -p "$CPP_PROJ/src" "$CPP_PROJ/build"
  cat > "$CPP_PROJ/src/main.cpp" <<'EOF'
#include <cstdio>

int add(int a, int b) {
  int total = a + b;
  return total;
}

int main() {
  std::printf("%d\n", add(2, 3));
  return 0;
}
EOF
  echo "e2e: building the sample C++ project with $CXX_BIN"
  "$CXX_BIN" -g -O0 "$CPP_PROJ/src/main.cpp" -o "$CPP_PROJ/build/app"
  # A real compile_commands.json for that build: it is the project-root marker
  # autodap looks for first, and it needs no build system on the runner.
  PROJ_DIR="$CPP_PROJ" CXX_BIN="$CXX_BIN" "$PYTHON" - <<'PY'
import json, os

root, cxx = os.environ["PROJ_DIR"], os.environ["CXX_BIN"]
src, out = f"{root}/src/main.cpp", f"{root}/build/app"
with open(f"{root}/compile_commands.json", "w") as f:
    json.dump([{
        "directory": root,
        "file": src,
        "command": f"{cxx} -g -O0 {src} -o {out}",
    }], f, indent=2)
PY

  CPP_LONE="$WORK/lonec"
  mkdir -p "$CPP_LONE"
  cat > "$CPP_LONE/hello.c" <<'EOF'
#include <stdio.h>

int main(void) {
  int total = 2 + 3;
  printf("%d\n", total);
  return 0;
}
EOF
else
  echo "e2e: $CPP_SKIP — skipping the C/C++ sessions"
fi

# ---- clean neovim config ----------------------------------------------------
export XDG_CONFIG_HOME="$WORK/config"
export XDG_DATA_HOME="$WORK/data"
export XDG_STATE_HOME="$WORK/state"
export XDG_CACHE_HOME="$WORK/cache"
mkdir -p "$XDG_CONFIG_HOME/nvim"
cp "$REPO/tests/e2e/init.lua" "$XDG_CONFIG_HOME/nvim/init.lua"

export AUTODAP_DIR="$REPO"
export E2E_PROJ="$PROJ"
export E2E_NODE_PROJ="$NODE_PROJ"
export E2E_CPP_PROJ="$CPP_PROJ"
export E2E_CPP_LONE="$CPP_LONE"
export E2E_CPP_SKIP="$CPP_SKIP"

echo "e2e: installing plugins into the clean config"
nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1

echo "e2e: running the debug sessions"
cd "$PROJ"
nvim --headless -c "luafile $REPO/tests/e2e/run.lua"
