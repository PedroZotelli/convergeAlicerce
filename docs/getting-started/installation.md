# Installation

Converge 0.3.0 requires Task-Spec **3.10.x** (3.8.x still works) for every install. Seamwise **0.3.x**
is required only for `cvg decompose` and `cvg compose`. Node 22 is required only
for the npm door and Cockpit.

The installer writes eleven Converge skills. It never copies a Task-Spec or
Seamwise implementation into the consumer.

## Requirements

- Git
- Bash 3.2 or newer
- Python 3
- Task-Spec 3.10.0 (`d5121f8c870448e3864eb7cb22160f0b720d7d36`)
- Seamwise 0.3.0 (`862a90ad38a37a250af2d96c0fc2c3c2f8149519`) for compose
- Node 22 only for npm / Cockpit

Task-Spec 3.9.x is rejected on purpose: `rebuild-state` writes an absolute
`path:` into `_state.yaml`.

## Install in dependency order

```bash
git clone --branch v3.10.0 https://github.com/PedroZotelli/task-specAlicerce.git
bash task-specAlicerce/install.sh --global --copy
taskspec demo

python3 -m pip install \
  "git+https://github.com/PedroZotelli/seamwiseAlicerce.git@v0.3.0"

git clone --branch v0.3.0 https://github.com/PedroZotelli/convergeAlicerce.git
bash convergeAlicerce/install.sh --target /absolute/path/to/your-project --copy
```

Other Converge doors:

```bash
npm install -g github:PedroZotelli/convergeAlicerce
cvg-install
```

```bash
CVG_REF=v0.3.0 bash -c "$(curl -fsSL \
  https://raw.githubusercontent.com/PedroZotelli/convergeAlicerce/main/install.sh)"
```

`install.sh` fails if `taskspec` is missing, 3.9.x, or outside 3.8 to 3.x. Copy mode pins
coordinator, contracts, templates, and skills into the consumer. It does not
vendor the engines.

## Pin the binaries you intend

```bash
export CVG_TASKSPEC_BIN=/absolute/path/to/task-spec/bin/taskspec
export CVG_SEAMWISE_BIN=/absolute/path/to/seamwise/bin/seamwise
```

Without the overrides, `cvg` resolves `taskspec` and `seamwise` from `PATH`.
A nested `cvg` call that forgets the override can pick a different engine on
`PATH` — prefer the absolute `CVG_*_BIN` form.

## What got installed

| Harness | Skill destination |
|---|---|
| Codex / Kimi | `.agents/skills/<skill>/` |
| Claude Code | `.claude/skills/<skill>/` |
| Grok Build | `.grok/skills/<skill>/` |

Exactly eleven Converge skills. No `skills/task-spec/`. No Seamwise sources.

For local development of this repository, `make bootstrap` clones the pinned
engine commits under gitignored `.engines/` and a `.venv`. That is a test
pairing, not a shipped dependency.
