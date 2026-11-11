#!/usr/bin/env bash
# bootstrap.sh — clone to a green `make check` with no manual exports.
#
# WHY THIS EXISTS
# A green run needs three things that are not on a normal developer's PATH: the
# exact Task-Spec 3.10.0 commit (3.9.x writes absolute _state.yaml paths and is
# rejected), the exact Seamwise 0.3.0 commit, and a Python that can import
# jsonschema. Before this script those were three README paragraphs, so the
# honest onboarding cost was "read carefully, then assemble it yourself."
#
# Everything lands under .engines/ and .venv/, both gitignored. The Makefile
# prefers them automatically, so after this runs `make check` needs no arguments.
# Idempotent: re-running re-uses what is already correct.
#
# Token: BOOTSTRAP=OK | BOOTSTRAP=FAIL
# bash 3.2 safe. Deps: git, python3.

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SELF_DIR/.." && pwd)"
cd "$REPO" || { echo "cannot enter repo"; echo "BOOTSTRAP=FAIL"; exit 1; }

# The release pairing. These are the same commits .github/workflows/ci.yml pins.
TASKSPEC_REPO="https://github.com/PedroZotelli/task-specLuan.git"
TASKSPEC_COMMIT="d5121f8c870448e3864eb7cb22160f0b720d7d36"
TASKSPEC_VERSION="3.10.0"
SEAMWISE_REPO="https://github.com/PedroZotelli/seamwiseLuan.git"
SEAMWISE_COMMIT="862a90ad38a37a250af2d96c0fc2c3c2f8149519"
SEAMWISE_VERSION="0.3.0"
JSONSCHEMA_PIN="jsonschema==4.26.0"

ENGINES="$REPO/.engines"
VENV="$REPO/.venv"
# A Windows virtualenv keeps its programs in Scripts/ and names them *.exe.
VENV_BIN="$VENV/bin"; EXE=""
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) VENV_BIN="$VENV/Scripts"; EXE=".exe" ;; esac
FAILED=0

step() { printf '\n[%s] %s\n' "$1" "$2"; }
ok()   { printf '  ok   — %s\n' "$1"; }
bad()  { printf '  FAIL — %s\n' "$1"; FAILED=$((FAILED + 1)); }

echo "=================================================================="
echo "bootstrap — assembling the pinned release pairing"
echo "=================================================================="

step 1 "python virtualenv with jsonschema"
if [ ! -x "$VENV_BIN/python$EXE" ]; then
  python3 -m venv "$VENV" || bad "could not create $VENV"
fi
if [ -x "$VENV_BIN/python$EXE" ]; then
  if "$VENV_BIN/python$EXE" -c "import jsonschema" 2>/dev/null; then
    ok "jsonschema already present"
  else
    "$VENV_BIN/pip$EXE" install -q --disable-pip-version-check "$JSONSCHEMA_PIN" \
      && ok "installed $JSONSCHEMA_PIN" \
      || bad "could not install $JSONSCHEMA_PIN"
  fi
fi

# clone_engine <name> <repo> <commit> -> $ENGINES/<name> at that exact commit
clone_engine() {
  name="$1"; repo="$2"; commit="$3"
  dir="$ENGINES/$name"
  mkdir -p "$ENGINES"
  if [ -d "$dir/.git" ]; then
    if [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$commit" ]; then
      ok "$name already at $commit"
      return 0
    fi
    git -C "$dir" fetch --quiet origin "$commit" 2>/dev/null || git -C "$dir" fetch --quiet origin
  else
    git clone --quiet "$repo" "$dir" || { bad "could not clone $name from $repo"; return 1; }
  fi
  git -C "$dir" checkout --quiet --detach "$commit" \
    && ok "$name checked out at $commit" \
    || { bad "could not check out $name at $commit"; return 1; }
}

step 2 "Task-Spec $TASKSPEC_VERSION"
if clone_engine task-spec "$TASKSPEC_REPO" "$TASKSPEC_COMMIT"; then
  got="$("$ENGINES/task-spec/bin/taskspec" --version 2>/dev/null | tr -d '[:space:]')"
  [ "$got" = "$TASKSPEC_VERSION" ] \
    && ok "reports $got" \
    || bad "expected $TASKSPEC_VERSION, got '${got:-nothing}'"
fi

step 3 "Seamwise $SEAMWISE_VERSION"
if clone_engine seamwise "$SEAMWISE_REPO" "$SEAMWISE_COMMIT"; then
  if [ -x "$VENV_BIN/pip$EXE" ]; then
    "$VENV_BIN/pip$EXE" install -q --disable-pip-version-check "$ENGINES/seamwise" \
      || bad "could not install seamwise into the venv"
    got="$("$VENV_BIN/seamwise$EXE" --version 2>/dev/null)"
    case "$got" in
      *"$SEAMWISE_VERSION"*) ok "reports $got" ;;
      *) bad "expected $SEAMWISE_VERSION, got '${got:-nothing}'" ;;
    esac
  fi
fi

echo
echo "=================================================================="
if [ "$FAILED" -ne 0 ]; then
  echo "failed: $FAILED"
  echo "BOOTSTRAP=FAIL"
  exit 1
fi
echo "failed: 0 — the Makefile now finds these automatically."
echo
echo "  make check"
echo
echo "BOOTSTRAP=OK"
exit 0
