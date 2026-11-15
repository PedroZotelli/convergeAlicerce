#!/usr/bin/env bash
# test-workflows.sh — the workflows are code nobody runs until release day.
#
# WHY THIS EXISTS
# The publish job of release.yml read the version with `cat VERSION` in a job
# that never checks the repository out: it only downloads the built assets. The
# verify and build jobs would pass, and `gh release create "v"` would then fail
# on the first real tag. Nothing exercised that path before the tag, so the
# defect sat there. The same file also called two actions by a moving tag
# (`@v7`, `@v8`) while every other action in the repository is pinned to a commit.
#
# WHAT IT CHECKS (static; no network, no workflow is triggered)
#   1. Every `uses:` names a full 40-hex commit (local `./` actions excepted).
#   2. A job that reads a repository file (`cat VERSION`) checks the repository out.
#   3. Every `needs.<job>.outputs.<name>` is declared by that job, the reading job
#      lists it under `needs`, and the declaration points at a step that exists.
#
# Token: WORKFLOWS=PASS | WORKFLOWS=FAIL
# bash 3.2 safe. Deps: python3 (standard library only).

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SELF_DIR/.." && pwd)"
cd "$REPO" || { echo "cannot enter repo"; echo "WORKFLOWS=FAIL"; exit 1; }

echo "=================================================================="
echo "test-workflows.sh — pinned actions and versions that reach every job"
echo "=================================================================="

PYTHON_BIN="${PYTHON:-python3}"
"$PYTHON_BIN" - "${WORKFLOWS_DIR:-.github/workflows}" <<'PY'
import re
import sys
from pathlib import Path

for stream in (sys.stdout, sys.stderr):  # the dash below must survive a Windows console
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8")

root = Path(sys.argv[1])
files =sorted(root.glob("*.yml")) + sorted(root.glob("*.yaml"))
failures = []
checked = 0


def jobs_of(text):
    """Split a workflow into {job id: [(line number, line)]} without a YAML parser."""
    jobs, current, inside = {}, None, False
    for number, line in enumerate(text.splitlines(), 1):
        if re.match(r"^jobs:\s*$", line):
            inside = True
            continue
        if not inside:
            continue
        if line and not line.startswith((" ", "#")):
            inside = False
            continue
        found = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line)
        if found:
            current = found.group(1)
            jobs[current] = []
        elif current is not None:
            jobs[current].append((number, line))
    return jobs


def needs_of(lines):
    names = set()
    for index, (_, line) in enumerate(lines):
        found = re.match(r"^    needs:\s*(.*)$", line)
        if not found:
            continue
        value = found.group(1).strip()
        if value:
            names.update(re.findall(r"[A-Za-z0-9_-]+", value))
        else:
            for _, item in lines[index + 1:]:
                entry = re.match(r"^      -\s*([A-Za-z0-9_-]+)", item)
                if not entry:
                    break
                names.add(entry.group(1))
    return names


def outputs_of(lines):
    """Job-level outputs: {name: step id it reads from (or None)}."""
    declared = {}
    for index, (_, line) in enumerate(lines):
        if not re.match(r"^    outputs:\s*$", line):
            continue
        for _, item in lines[index + 1:]:
            entry = re.match(r"^      ([A-Za-z0-9_-]+):\s*(.*)$", item)
            if not entry:
                break
            step = re.search(r"steps\.([A-Za-z0-9_-]+)\.outputs\.", entry.group(2))
            declared[entry.group(1)] = step.group(1) if step else None
    return declared


for path in files:
    text = path.read_text(encoding="utf-8")
    jobs = jobs_of(text)
    for number, line in enumerate(text.splitlines(), 1):
        used = re.match(r"^\s*(?:-\s*)?uses:\s*([^\s#]+)", line)
        if not used:
            continue
        checked += 1
        target = used.group(1).strip("\"'")
        if target.startswith("./"):
            continue
        if not re.search(r"@[0-9a-f]{40}$", target):
            failures.append(f"{path.as_posix()}:{number}: `{target}` is not pinned to a full commit SHA")
    for job, lines in jobs.items():
        body = "\n".join(line for _, line in lines)
        has_checkout = re.search(r"uses:\s*actions/checkout@", body) is not None
        for number, line in lines:
            if re.search(r"\bcat\s+VERSION\b|<\s*VERSION\b", line) and not has_checkout:
                failures.append(
                    f"{path.as_posix()}:{number}: job `{job}` reads the VERSION file but never checks the repository out"
                )
        needs = needs_of(lines)
        step_ids = set(re.findall(r"^\s+(?:-\s*)?id:\s*([A-Za-z0-9_-]+)", body, flags=re.M))
        for name, step in outputs_of(lines).items():
            checked += 1
            if step is not None and step not in step_ids:
                failures.append(f"{path.as_posix()}: job `{job}` output `{name}` reads step `{step}`, which does not exist")
        for number, line in lines:
            for source, name in re.findall(r"needs\.([A-Za-z0-9_-]+)\.outputs\.([A-Za-z0-9_-]+)", line):
                checked += 1
                if source not in jobs:
                    failures.append(f"{path.as_posix()}:{number}: job `{job}` reads an output of unknown job `{source}`")
                elif source not in needs:
                    failures.append(f"{path.as_posix()}:{number}: job `{job}` reads `{source}` outputs without `needs: {source}`")
                elif name not in outputs_of(jobs[source]):
                    failures.append(f"{path.as_posix()}:{number}: job `{source}` does not declare output `{name}`")

if not files:
    failures.append(f"no workflow found under {root}")

print()
print(f"workflows: {len(files)}   references checked: {checked}")
for failure in failures:
    print(f"  FAIL — {failure}")
if failures:
    print()
    print("WORKFLOWS=FAIL")
    sys.exit(1)
print("  ok — every action is pinned to a commit")
print("  ok — no job reads a repository file without a checkout")
print("  ok — every cross-job output is declared and reachable")
print()
print("WORKFLOWS=PASS")
PY
