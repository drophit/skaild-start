"""SessionStart hook — plugin check + swanky session banner.

Emits BOTH:
  * systemMessage                         → visible colored banner for the dev
  * hookSpecificOutput.additionalContext  → silent directive so Claude auto-runs /start

Both outputs are intentional: the banner surfaces real-time status to the human
while the additionalContext directive ensures /start auto-runs before any response.
"""
import json
import os
import pathlib
import re
import subprocess
import sys
from datetime import datetime

# Force UTF-8 stdout so unicode box characters survive on Windows (cp1252 default).
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

# ---------- Ship bundled workflows into the project ------------------------
# Plugins cannot register named workflows, so on session start we copy any
# workflows this plugin bundles (${CLAUDE_PLUGIN_ROOT}/workflows/*.js) into the
# project's .claude/workflows/, where the Workflow tool can resolve them by name.
# Idempotent: copies only when the destination is missing or the plugin's copy is
# newer — a user's local edits win, because editing bumps the destination mtime.
def _sync_bundled_workflows():
    try:
        import shutil
        root = os.environ.get("CLAUDE_PLUGIN_ROOT")
        proj = os.environ.get("CLAUDE_PROJECT_DIR")
        if not root or not proj:
            return
        src_dir = pathlib.Path(root) / "workflows"
        if not src_dir.is_dir():
            return
        dst_dir = pathlib.Path(proj) / ".claude" / "workflows"
        dst_dir.mkdir(parents=True, exist_ok=True)
        for src in src_dir.glob("*.js"):
            dst = dst_dir / src.name
            if not dst.exists() or src.stat().st_mtime > dst.stat().st_mtime:
                shutil.copy2(src, dst)
    except Exception:
        # Never let workflow-sync break the session banner.
        pass

_sync_bundled_workflows()

# ---------- Activate the skAIld status line ---------------------------------
# Plugins cannot set `statusLine` in their own settings, and ${CLAUDE_PLUGIN_ROOT}
# does not expand inside a statusLine.command (claude-code#52079). So on session
# start we write a statusLine block into the user's ~/.claude/settings.json,
# baking an ABSOLUTE path (resolved here from CLAUDE_PLUGIN_ROOT) to the shipped
# statusline-command.sh. Idempotent, and it NEVER clobbers a user's own
# statusLine. Wrapped so it can never crash the session hook.
def ensure_statusline(settings_path=None, script_abspath=None):
    try:
        if script_abspath is None:
            root = os.environ.get("CLAUDE_PLUGIN_ROOT")
            if not root:
                return  # no plugin root in this context → can't bake an abs path
            # Forward slashes so the path is safe inside the `bash "..."` command
            # on every platform (Git Bash chokes on Windows backslashes).
            script_abspath = root.replace("\\", "/").rstrip("/") + "/statusline-command.sh"
        if settings_path is None:
            settings_path = os.path.join(os.path.expanduser("~"), ".claude", "settings.json")

        data = {}
        if os.path.exists(settings_path):
            with open(settings_path, "r", encoding="utf-8") as fh:
                data = json.load(fh)  # malformed → raises → caught below → skip
            if not isinstance(data, dict):
                return  # unexpected shape — never touch it

        if "statusLine" in data:
            return  # respect the user's existing status line; idempotent no-op

        # No refreshInterval: the line renders on activity, not on a 1 fps timer.
        # A per-second refresh (needed only for the shimmer) makes renders that
        # outlast the tick get cancelled mid-flight, orphaning the `node` child on
        # Windows/Git Bash. Static is the safe default; the shimmer is opt-in
        # (SKAILD_STATUSLINE_ANIM=shimmer + a hand-added refreshInterval).
        data["statusLine"] = {
            "type": "command",
            "command": 'bash "' + script_abspath + '"',
        }
        parent = os.path.dirname(settings_path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(settings_path, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2)
            fh.write("\n")
        sys.stderr.write("skAIld: added a status line to ~/.claude/settings.json\n")
    except Exception:
        # Never let status-line wiring break the session hook.
        pass

ensure_statusline()

# ---------- ANSI palette ----------------------------------------------------
C = {
    "reset":   "\033[0m",
    "bold":    "\033[1m",
    "dim":     "\033[2m",
    "red":     "\033[91m",
    "green":   "\033[92m",
    "yellow":  "\033[93m",
    "blue":    "\033[94m",
    "magenta": "\033[95m",
    "cyan":    "\033[96m",
    "white":   "\033[97m",
    "bg_mag":  "\033[45m",
}
if os.environ.get("NO_COLOR"):
    C = {k: "" for k in C}

# ---------- Plugin dependency check ----------------------------------------
# Derived from matrix.json `mustHaveDeps` at build time. Missing deps are framed
# as friendly install hints (not red errors) so a fresh free user isn't alarmed.
REQUIRED_PLUGINS = {
    "superpowers": "superpowers@claude-plugins-official",
    "commit-commands": "commit-commands@claude-plugins-official"
}
BUY_URL = "https://skaild.com"

plugins_file = pathlib.Path.home() / ".claude" / "plugins" / "installed_plugins.json"
missing = []
if plugins_file.exists():
    try:
        data = json.loads(plugins_file.read_text(encoding="utf-8"))
        installed = data.get("plugins", {})
        missing = [n for n, k in REQUIRED_PLUGINS.items() if k not in installed]
    except (json.JSONDecodeError, KeyError):
        missing = list(REQUIRED_PLUGINS.keys())
else:
    missing = list(REQUIRED_PLUGINS.keys())

# ---------- Git state -------------------------------------------------------
def git(*args):
    try:
        return subprocess.check_output(
            ["git", *args], text=True, stderr=subprocess.DEVNULL, timeout=1.5
        ).strip()
    except Exception:
        return ""

branch = git("branch", "--show-current") or "(detached)"
dirty = bool(git("status", "--porcelain"))
wt_lines = [l for l in git("worktree", "list").splitlines() if l.strip()]
worktree_count = max(0, len(wt_lines) - 1)  # exclude main

# ---------- Agent Teams check (only tiers shipping team-review/merge-approved) ----
# Those skills' one-window flow needs CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1. A hook can
# DETECT the flag but can't SET it for the running session (env is fixed at launch), so
# we surface status and let the directive make Claude OFFER to enable it (with consent).
SHOWS_AGENT_TEAMS = False
agent_teams_on = os.environ.get("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS") == "1"

# ---------- Banner builder --------------------------------------------------
INNER = 72
_ansi_re = re.compile(r"\x1b\[[0-9;]*m")

def vlen(s):
    # Visible width, ignoring ANSI codes. Emoji (e.g. 🔒) render two cells in
    # most terminals, so count codepoints >= U+1F300 as width 2 to keep the
    # box-drawing borders aligned.
    plain = _ansi_re.sub("", s)
    return sum(2 if ord(ch) >= 0x1F300 else 1 for ch in plain)

def truncate(s, max_vis):
    out, v, i, n = [], 0, 0, len(s)
    cut = False
    while i < n:
        if s[i] == "\x1b":
            m = _ansi_re.match(s, i)
            if m:
                out.append(m.group(0)); i = m.end(); continue
        if v >= max_vis - 1:
            cut = True; break
        out.append(s[i]); v += 1; i += 1
    res = "".join(out)
    return res + C["reset"] + "…" if cut else res

def pad(s, w=INNER):
    return s + " " * max(0, w - vlen(s))

def row(content=""):
    if vlen(content) > INNER:
        content = truncate(content, INNER)
    return f"{C['cyan']}║{C['reset']} {pad(content)} {C['cyan']}║{C['reset']}"

BAR = "═" * (INNER + 2)
top = f"{C['cyan']}╔{BAR}╗{C['reset']}"
div = f"{C['cyan']}╠{BAR}╣{C['reset']}"
bot = f"{C['cyan']}╚{BAR}╝{C['reset']}"

dot_ok   = f"{C['green']}●{C['reset']}"
dot_warn = f"{C['yellow']}●{C['reset']}"
dot_bad  = f"{C['red']}●{C['reset']}"

# --- title row
stamp = datetime.now().strftime("%a %b %-d · %H:%M") if os.name != "nt" \
        else datetime.now().strftime("%a %b %d · %H:%M")
title = (
    f"  {C['bold']}{C['magenta']}sk{C['reset']}"
    f"{C['bold']}{C['cyan']}AI{C['reset']}"
    f"{C['bold']}{C['magenta']}ld{C['reset']}"
    f"{C['bold']}{C['cyan']}█{C['reset']}"
    f"   {C['dim']}{C['cyan']}· session ready · {stamp} ·{C['reset']}"
)

# --- status rows
def label(name, value):
    return f"  {C['dim']}{name:<11}{C['reset']}{value}"

branch_val = f"{C['bold']}{C['magenta']}{branch}{C['reset']}   "
branch_val += (f"{dot_warn} {C['yellow']}dirty{C['reset']}" if dirty
               else f"{dot_ok} {C['green']}clean{C['reset']}")

wt_val = f"{C['bold']}{C['cyan']}{worktree_count}{C['reset']} {C['dim']}active{C['reset']}"

if missing:
    # Friendly hint, not a red error — a fresh user may not have these yet.
    plugin_val = (f"{dot_warn} {C['yellow']}optional: install {', '.join(missing)}"
                  f" via /plugin{C['reset']}")
else:
    plugin_val = f"{dot_ok} {C['green']}all installed{C['reset']}"

# --- workflow menu (tier-aware; generated from matrix.json)
# Workflows this plugin actually ships:
workflows = [

]
# Workflows owned by OTHER tiers — shown locked with the plugin that unlocks them:
locked_workflows = [
    ("/start-planning", "Plan complex work  (brainstorm → plan)", "skaild-plan"),
    ("/quick-plan", "Lightweight 1-3 file changes", "skaild-plan"),
    ("/start-coding", "Execute a plan  (TDD discipline)", "skaild-build"),
    ("/serve-worktree", "Serve a worktree for browser testing", "skaild-build"),
    ("/review-pr N", "Review a PR end-to-end", "skaild-build"),
    ("/team-review", "Review→fix→re-review loop via Agent Teams", "skaild-build"),
    ("/create-pr", "Full PR workflow  (test → review → merge → PR)", "skaild-build"),
    ("/merge-approved", "Batch-merge approved PRs to the main branch", "skaild-build"),
    ("/light-deploy", "Lightweight deploy gate for small batches", "skaild-ship"),
    ("/pre-deploy", "Deploy gate  (ALL tests) — run LAST", "skaild-ship"),
    ("/hotfix", "Urgent patch release off the deployed prod commit", "skaild-ship"),
    ("/handoff", "Build resume doc for next session", "skaild-ship"),
    ("/close-session", "Save memory + wrap up", "skaild-ship"),
]
# Upsell line(s) — free tier gets a prominent unlock pitch, paid tiers a soft cross-sell:
upsell_lines = [
    "You're on the FREE tier — unlock Plan/Build/Ship at https://skaild.com",
]

# --- agent-teams status row (only when this tier ships Agent-Teams skills)
status_rows = [
    row(label("branch",    branch_val)),
    row(label("worktrees", wt_val)),
    row(label("plugins",   plugin_val)),
]
if SHOWS_AGENT_TEAMS:
    if agent_teams_on:
        teams_val = f"{dot_ok} {C['green']}on{C['reset']}"
    else:
        teams_val = (f"{dot_bad} {C['red']}OFF{C['reset']} "
                     f"{C['dim']}— team-review/merge-approved fall back; I can enable it{C['reset']}")
    status_rows.append(row(label("agents", teams_val)))

# --- assemble
lines = [
    top,
    row(title),
    div,
    *status_rows,
    div,
    row(f"  {C['bold']}{C['cyan']}W O R K F L O W S{C['reset']}"),
    row(""),
]
for cmd, desc in workflows:
    lines.append(
        row(f"  {C['magenta']}{cmd:<17}{C['reset']}{C['dim']}{desc}{C['reset']}")
    )

if locked_workflows:
    lines.append(row(""))
    lines.append(row(f"  {C['dim']}🔒 locked — unlock with the tier shown{C['reset']}"))
    for cmd, desc, plug in locked_workflows:
        lines.append(
            row(f"  {C['dim']}🔒 {cmd:<16} unlock with {C['reset']}"
                f"{C['cyan']}{plug}{C['reset']}")
        )

lines.append(row(""))
for up in upsell_lines:
    lines.append(row(f"  {C['bold']}{C['magenta']}{up}{C['reset']}"))
lines.append(row(
    f"  {C['dim']}tell me what you want, or pick a workflow above{C['reset']}"
))
lines.append(bot)

banner = "\n" + "\n".join(lines)

# ---------- Silent directive for Claude ------------------------------------
# Only instructs Claude to use skills actually installed in THIS plugin. Locked
# workflows are mentioned only as an upgrade path, never as runnable commands.
directive = []
if missing:
    directive.append(
        "Optional dependencies not detected: " + ", ".join(missing)
        + ". They add code-review and quality gates. Suggest installing them via "
        "/plugin only if the user asks for that capability — do not block work."
    )
    directive.append("")
if SHOWS_AGENT_TEAMS and not agent_teams_on:
    directive.append(
        "Agent Teams is OFF (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS != 1). /team-review and "
        "/merge-approved's one-window conflict-resolution flow need it; without it they fall "
        "back to slower separate-session handoffs. PROACTIVELY OFFER (once, early) to enable it: "
        "ask the user if you should add \"env\": {\"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS\": \"1\"} "
        "to their .claude/settings.json. If yes: read that file (or ~/.claude/settings.json if "
        "they prefer all projects), MERGE the key into any existing JSON without dropping other "
        "settings (create the file as {\"env\": {...}} if absent), write it back, then tell them "
        "to RESTART Claude Code for it to take effect (the flag is read at launch). If they "
        "decline, continue normally — never set it silently."
    )
    directive.append("")
directive.append(
    "MANDATORY: Invoke the /start skill BEFORE responding to ANY user message. "
    "After /start completes, the workflows installed in THIS plugin are: "
    "the base skills only. "
    "Use ONLY these installed commands. More workflows (/start-planning, /quick-plan, /start-coding, /serve-worktree, /review-pr N, /team-review, /create-pr, /merge-approved, /light-deploy, /pre-deploy, /hotfix, /handoff, /close-session) are available by upgrading at https://skaild.com — mention this only if the user wants that capability; do NOT run those commands."
)

# ---------- Emit ------------------------------------------------------------
print(json.dumps({
    "systemMessage": banner,
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": "\n".join(directive),
    }
}))
