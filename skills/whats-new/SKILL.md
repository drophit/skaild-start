---
name: whats-new
description: Generate a What's New / changelog from git history into your project's changelog file
effort: high
---

# Generate What's New

Turn recent git commits into human-readable release notes. Each run only adds genuinely new entries.

## Config (`project.config.json` -> `whats_new`)
- `format`: `markdown` (default, append to `target_path`) | `json` (write a JSON array to `target_path`) | `custom` (pipe the generated entries to `target_cmd`).
- `target_path`: file to write (default `WHATS_NEW.md`).
- `target_cmd`: shell command to receive entries on stdin when `format` is `custom`.
If no config is present, default to appending Markdown to `WHATS_NEW.md`.

## Steps
1. Read the last processed commit from `.skaild/whats-new-last.txt` (if absent, default to the last 30 commits).
2. `git log <last>..HEAD --no-merges --pretty=...` — collect commits since then.
3. Drop noise (merges, WIP, docs-only, pure tooling).
4. Cluster commits into feature buckets and write one concise bullet per bucket.
5. Deduplicate against entries already present in `target_path`.
6. Emit per `format`; then write the new HEAD sha to `.skaild/whats-new-last.txt` (gitignored).
7. Report what was added.

## Notes
- Never rewrites existing entries — append-only.
- `.skaild/whats-new-last.txt` makes runs idempotent; add `.skaild/` to `.gitignore`.
