# skAIld · start

> **Vibes ship bugs. Discipline ships code.**

skAIld is a set of continuously-updated **Claude Code plugins** that give your AI pair-programmer a real workflow — disciplined planning, clean PRs, and pre-deploy gates — so you stop shipping bugs and start shipping code.

**`skaild-start` is the free foundation.** Every Claude Code session, on every project, gets:

| Command | What it does |
|---|---|
| `/start` | Session banner + a workflow menu so Claude knows where to begin |
| `karpathy-guidelines` | Four coding guardrails: think first, simplicity, surgical changes, goal-driven |
| `/whats-new` | Auto-generates a changelog from your git history |

## Install

```
/plugin marketplace add drophit/skaild-marketplace
/plugin install skaild-start@skaild
```

No credit card. Installs in about 30 seconds — it's the on-ramp to the whole loop.

Each plugin ships three model-tuned branches (`v4.6` / `v4.7` / `v4.8`); `@skaild` installs the latest by default. Dependencies (`superpowers`, `commit-commands`) auto-install.

## The full loop

`Plan → Build → Ship`, one disciplined loop. Each phase hands off cleanly to the next.

| Plugin | Adds |
|---|---|
| `skaild-start` | the foundation (start · guidelines · changelog) _(you have this)_ |
| `skaild-plan` | `/start-planning`, `/quick-plan` |
| `skaild-build` | `/start-coding`, `/serve-worktree`, `/review-pr N`, `/team-review`, `/create-pr`, `/merge-approved` |
| `skaild-ship` | `/light-deploy`, `/pre-deploy`, `/hotfix`, `/handoff`, `/close-session` |
| **The Complete Bundle** | all three phases — cheaper than buying separately |

**You're on the free tier.** Add a phase when you need it, or get the whole loop and save.

Pricing → **[skaild.com/#pricing](https://skaild.com/#pricing)**

### 👉 Give Claude Code a workflow it can't skip — **[skaild.com](https://skaild.com)**

---

<sub>**skAIld** — disciplined AI dev workflows for Claude Code. Monthly billing, cancel anytime — keep what you've installed.</sub>
