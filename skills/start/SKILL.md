---
name: start
description: Session entry point — check environment, surface available workflows, guide the dev to the next step
---

# Start Session

Run this at the beginning of every new Claude Code session. It checks the environment and guides you to the right workflow.

## Step 1: Check Environment

Verify the basics are in place:

1. **Git status**: Run `git status` and `git branch --show-current`
   - If on the default branch: clean state, ready for new work
   - If on a feature branch: resuming work — show recent commits on this branch
   - If dirty working tree: warn about uncommitted changes

2. **Check for worktrees**: Run `git worktree list` — if any worktrees exist, show them so the dev knows what's in progress

## Step 2: Review Project Context (parallel with Step 1)

1. `CLAUDE.md` and any memory files are already loaded into conversation context automatically — review them in-context, don't re-read the files
2. If a `HANDOFF.md` exists in the project memory directory, read it for previous-session context and resume steps
3. If there are open worktrees from Step 1, check their branch names for open PRs

## Step 3: Present Status & Options (after all above complete)

Show a clean status summary, then the workflow menu below. Only the workflows in **Available** are installed in this plugin — invoke those. The **Locked** entries belong to other skAIld tiers; mention them only if the dev asks for that capability, and point them at the upgrade URL.

```
## Session Ready

**Branch**: main (clean)
**Active worktrees**: 0
**Open PRs**: none

## What would you like to do?
```

### Available in this plugin

- (this plugin ships the base skills only)

### Locked — other skAIld tiers

- 🔒 `/start-planning` — unlock with **skaild-plan**
- 🔒 `/quick-plan` — unlock with **skaild-plan**
- 🔒 `/start-coding` — unlock with **skaild-build**
- 🔒 `/serve-worktree` — unlock with **skaild-build**
- 🔒 `/review-pr N` — unlock with **skaild-build**
- 🔒 `/team-review` — unlock with **skaild-build**
- 🔒 `/create-pr` — unlock with **skaild-build**
- 🔒 `/merge-approved` — unlock with **skaild-build**
- 🔒 `/light-deploy` — unlock with **skaild-ship**
- 🔒 `/pre-deploy` — unlock with **skaild-ship**
- 🔒 `/hotfix` — unlock with **skaild-ship**
- 🔒 `/handoff` — unlock with **skaild-ship**
- 🔒 `/close-session` — unlock with **skaild-ship**

> **You're on the free tier.** Unlock Plan / Build / Ship workflows at https://skaild.com.

Adapt the status and options based on what you found. If they're on a feature branch with uncommitted work, emphasize resuming. If everything is clean, emphasize new work. Never instruct the dev to run a Locked command — those aren't installed here.
