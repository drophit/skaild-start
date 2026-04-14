# skaild-start

Session entry point with the skAIld banner. Part of the [skAIld plugin suite](https://skaild.com).

**Status:** v0.0.1 scaffold — content lands in Phase 2.

## Install

```
/plugin marketplace add drophit/skaild-start
/plugin install skaild-start@skaild-start
```

## What you get

- **`/skaild-start:start`** — session entry skill: env check, git status, migration run, plugin detection, workflow menu
- **SessionStart hook** — the skAIld banner displayed at the start of every session (cyan box + magenta branding + status lines)

## Configuration

Create `.claude/project.config.json` at your project root. See `templates/project.config.example.json` for the full schema.

Minimum required keys for `skaild-start`:
- `project.memory_dir` — where `HANDOFF.md` lives
- `migrations.runner_cmd` — command to run pending DB migrations
- `generated_dirs` — directories containing auto-regenerated files to silently discard on session start

## Requirements

- Python 3 (for the SessionStart hook)
- `git` on PATH

## License

TBD
