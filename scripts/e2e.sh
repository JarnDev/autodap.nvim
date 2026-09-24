#!/usr/bin/env bash
# End-to-end check: drive real debug sessions from a clean Neovim config.
#
# Everything happens in a throwaway directory:
#   - a sample Python project (pyproject.toml, a virtualenv, one source file) and
#     a sample Node project (package.json with a script, one source file)
#   - a Neovim config whose only plugins are nvim-dap and autodap (tests/e2e/init.lua)
#   - debugpy, downloaded as the pure-python wheel and exposed as `debugpy-adapter`,
#     and js-debug, downloaded and exposed as `js-debug-adapter` — the same binary
#     names mason installs (no pip, no compiler, no system changes)
#
# Then tests/e2e/run.lua sets a breakpoint, presses <F5>, and asserts each session
# stops on the right line, exposes locals, and runs to completion.
#
# Usage: make test-e2e   (or scripts/e2e.sh)
set -euo pipefail

DEBUGPY_VERSION="${DEBUGPY_VERSION:-1.8.22}"
JS_DEBUG_VERSION="${JS_DEBUG_VERSION:-v1.140.0}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

echo "e2e: installing plugins into the clean config"
nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1

echo "e2e: running the debug sessions"
cd "$PROJ"
nvim --headless -c "luafile $REPO/tests/e2e/run.lua"
