#!/usr/bin/env bash
# skAIld status line — portable core (de-yobo'd; no database, no credentials).
#
# Row 1: skAIld█                (brand wordmark)
# Row 2: <git branch>  <cwd basename>  [wt:<worktree>]  [prod <version>]
# Row 3: <model>  ctx <rem %>  ◆<effort>  5h <n>% · 7d <n>%  $<cost>  +A/-R  PR#<n>
#
# Hard requirements: NEVER hang, NEVER error to stdout, degrade silently when
# any dependency (node, git, the prod-version cache) is unavailable. Never
# print the literal string "undefined". Exactly one node process per render.
#
# JSON is parsed with node (guaranteed present — Claude Code runs on it); jq is
# NOT assumed. 16-colour ANSI only (doubles as the C64 palette; truecolor is
# not relied on).

input=$(cat)

# --- 16-colour ANSI palette (also the C64 palette; no truecolor) ---
RESET=$'\033[0m'
BOLD=$'\033[1m'
MAGENTA=$'\033[35m'
CYAN=$'\033[36m'
BOLD_MAGENTA=$'\033[1;35m'
BOLD_CYAN=$'\033[1;36m'
GREEN=$'\033[32m'
RED=$'\033[31m'
DIM_CYAN=$'\033[2;36m'
DIM_MAGENTA=$'\033[2;35m'
DIM_YELLOW=$'\033[2;33m'
DIM_GREEN=$'\033[2;32m'
DIM_GRAY=$'\033[2;37m'

# Field separator for the single node parse. A non-whitespace control byte (US,
# 0x1f) is used instead of TAB so that empty fields (null/missing values) are
# preserved positionally — bash `read` collapses runs of whitespace IFS.
US=$'\x1f'

# Extended globs power the ANSI-stripping in the width helpers below.
shopt -s extglob 2>/dev/null

# vis_len <str> — visible width in Unicode codepoints. ANSI SGR escapes and
# UTF-8 continuation bytes are not counted. Pure bash (no subprocess), so it is
# cheap to call repeatedly on the per-render shedding path.
vis_len() {
  local LC_ALL=C
  local x=${1//$'\033['*([0-9;])m/}
  local nc=${x//[$'\x80'-$'\xbf']/}
  printf '%s' "${#nc}"
}

# vis_trunc <str> <maxcols> — last resort: strip ANSI and cut to <maxcols>
# codepoints (respecting UTF-8 boundaries), re-wrapped dim. Guards against wrap
# when even a lone mandatory segment overflows the terminal.
vis_trunc() {
  local LC_ALL=C
  local x=${1//$'\033['*([0-9;])m/}
  local max=$2 out="" cp=0 i=0 len=${#x} ch
  [ "$max" -lt 1 ] && { printf '%s' ""; return; }
  while [ $i -lt $len ] && [ $cp -lt $max ]; do
    ch=${x:$i:1}; i=$((i + 1))
    case "$ch" in
      [$'\x80'-$'\xbf']) ;;          # continuation byte: same codepoint
      *) cp=$((cp + 1));;
    esac
    out="$out$ch"
  done
  while [ $i -lt $len ]; do            # absorb the last codepoint's tail bytes
    ch=${x:$i:1}
    case "$ch" in [$'\x80'-$'\xbf']) out="$out$ch"; i=$((i + 1));; *) break;; esac
  done
  printf '%s' "${DIM_GRAY}${out}${RESET}"
}

# shed_fit <cols> <joiner> — consumes globals SEG[] (segments, visual order) and
# PRI[] (drop rank; 1 = drop first, 0 = mandatory) and sets RESULT to the widest
# subset that fits <cols>. Drops the lowest-positive-rank live segment until it
# fits; truncates the assembled row only when nothing droppable remains.
shed_fit() {
  local cols=$1 joiner=$2 n=${#SEG[@]}
  local i first out w best bestpri
  local -a live
  for ((i = 0; i < n; i++)); do
    if [ -n "${SEG[$i]}" ]; then live[$i]=1; else live[$i]=0; fi
  done
  while :; do
    out=""; first=1
    for ((i = 0; i < n; i++)); do
      [ "${live[$i]}" = 1 ] || continue
      if [ $first = 1 ]; then out="${SEG[$i]}"; first=0; else out="${out}${joiner}${SEG[$i]}"; fi
    done
    w=$(vis_len "$out")
    if [ "$w" -le "$cols" ]; then RESULT="$out"; return; fi
    best=-1; bestpri=0
    for ((i = 0; i < n; i++)); do
      [ "${live[$i]}" = 1 ] || continue
      [ "${PRI[$i]}" -gt 0 ] || continue
      if [ "$best" = -1 ] || [ "${PRI[$i]}" -lt "$bestpri" ]; then best=$i; bestpri=${PRI[$i]}; fi
    done
    if [ "$best" = -1 ]; then RESULT=$(vis_trunc "$out" "$cols"); return; fi
    live[$best]=0
  done
}

# --- locate node without relying solely on PATH ---
node_bin=""
if command -v node >/dev/null 2>&1; then
  node_bin="node"
elif [ -x "/c/Program Files/nodejs/node.exe" ]; then
  node_bin="/c/Program Files/nodejs/node.exe"
fi

# --- single node call: 12 fields, US-separated (empty string when null/absent) ---
model_name=""; cwd_from_json=""; remaining=""; worktree=""
five=""; seven=""; cost=""; added=""; removed=""; pr_num=""; pr_state=""; effort=""
if [ -n "$node_bin" ]; then
  node_out=$(printf '%s' "$input" | "$node_bin" -e '
    let raw = "";
    process.stdin.on("data", function (d) { raw += d; });
    process.stdin.on("end", function () {
      let j = {};
      try { j = JSON.parse(raw); } catch (e) { j = {}; }
      function g(o, path) {
        var c = o;
        for (var i = 0; i < path.length; i++) {
          if (c === null || c === undefined) return undefined;
          c = c[path[i]];
        }
        return c;
      }
      var s = function (v) { return (v === null || v === undefined) ? "" : String(v); };
      var cwd = g(j, ["workspace", "current_dir"]);
      if (cwd === null || cwd === undefined) cwd = j.cwd;
      var out = [
        s(g(j, ["model", "display_name"])),
        s(cwd),
        s(g(j, ["context_window", "remaining_percentage"])),
        s(g(j, ["workspace", "git_worktree"])),
        s(g(j, ["rate_limits", "five_hour", "used_percentage"])),
        s(g(j, ["rate_limits", "seven_day", "used_percentage"])),
        s(g(j, ["cost", "total_cost_usd"])),
        s(g(j, ["cost", "total_lines_added"])),
        s(g(j, ["cost", "total_lines_removed"])),
        s(g(j, ["pr", "number"])),
        s(g(j, ["pr", "review_state"])),
        s(g(j, ["effort", "level"]))
      ];
      process.stdout.write(out.join("\x1f"));
    });
  ' 2>/dev/null)
  if [ -n "$node_out" ]; then
    IFS="$US" read -r model_name cwd_from_json remaining worktree \
      five seven cost added removed pr_num pr_state effort <<< "$node_out"
  fi
fi

cwd_raw="$cwd_from_json"
[ -z "$cwd_raw" ] && cwd_raw="$PWD"
# Normalize Windows backslashes so basename / git -C behave (the JSON path
# arrives as a native "C:\Users\..." string).
cwd=$(printf '%s' "$cwd_raw" | tr '\\' '/')

# --- wall clock for the 1 fps animation (test override: SKAILD_STATUSLINE_NOW) ---
NOW=${SKAILD_STATUSLINE_NOW:-}
case "$NOW" in ''|*[!0-9]*) NOW=$(date +%s 2>/dev/null);; esac
case "$NOW" in ''|*[!0-9]*) NOW=0;; esac

# --- git branch (detached-HEAD/worktree safe), cached for a couple of seconds ---
# The idle 1 fps re-render must not re-spawn git every frame, so the branch is
# memoised per cwd under $HOME/.claude keyed to NOW. Best-effort: any cache
# failure silently falls through to a live read.
git_branch_live() {   # sets global `branch`
  branch=""
  if git --no-optional-locks -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git --no-optional-locks -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null)
    if [ -z "$branch" ]; then
      local sha; sha=$(git --no-optional-locks -C "$cwd" rev-parse --short HEAD 2>/dev/null)
      [ -n "$sha" ] && branch="detached@${sha}"
    fi
  fi
}

branch=""
cache_dir="$HOME/.claude"
cache_file="$cache_dir/.skaild_sl_branch_${cwd//[^A-Za-z0-9]/_}"
branch_cached=0
if [ -r "$cache_file" ]; then
  c_epoch=""; c_branch=""
  IFS="$US" read -r c_epoch c_branch < "$cache_file" 2>/dev/null
  case "$c_epoch" in
    ''|*[!0-9]*) ;;
    *) age=$(( NOW - c_epoch ))
       if [ "$age" -ge 0 ] && [ "$age" -le 2 ]; then branch="$c_branch"; branch_cached=1; fi;;
  esac
fi
if [ "$branch_cached" = 0 ]; then
  git_branch_live
  mkdir -p "$cache_dir" 2>/dev/null
  printf '%s%s%s' "$NOW" "$US" "$branch" > "$cache_file" 2>/dev/null || true
fi

dir_name=$(basename "$cwd")

# --- prod version: neutral cache file ONLY, blank if absent (never a live call) ---
prod_version=""
version_file="$HOME/.claude/.skaild_prod_version"
[ -f "$version_file" ] && prod_version=$(tr -d '[:space:]' < "$version_file" 2>/dev/null)

# --- numeric formatting (guarded so a missing field stays empty) ---
remaining_pct=""; [ -n "$remaining" ] && remaining_pct=$(printf '%.0f' "$remaining" 2>/dev/null)
five_pct="";      [ -n "$five" ]      && five_pct=$(printf '%.0f' "$five" 2>/dev/null)
seven_pct="";     [ -n "$seven" ]     && seven_pct=$(printf '%.0f' "$seven" 2>/dev/null)
cost_fmt="";      [ -n "$cost" ]      && cost_fmt=$(printf '%.2f' "$cost" 2>/dev/null)

# --- row 1: brand wordmark lockup ---
# skAIld with a terminal cursor block: sk / ld bold magenta, AI bold cyan, then a
# solid bold-cyan block cursor (█) flush against the d. No blink attribute: SGR 5
# blink is unsupported/inconsistent across terminals (notably the Windows console),
# so a solid block renders identically everywhere.
CURSOR=$'\033[1;36m'
wordmark_static="${BOLD_MAGENTA}sk${BOLD_CYAN}AI${BOLD_MAGENTA}ld${CURSOR}█${RESET}"

# Shimmer: a 16-colour C64 raster bar sweeps the 12 glyphs of the lockup. The
# colour of glyph c is offset by the frame index (NOW mod palette length), so
# the band advances one step per second. Only the escape bytes move — the
# visible letters never change. The frame math is pure arithmetic: no git, node,
# or other spawn rides this per-frame path.
SHIMMER=( $'\033[1;35m' $'\033[1;95m' $'\033[1;36m' $'\033[1;96m' $'\033[1;34m' $'\033[1;94m' )
WM_GLYPHS=( 's' 'k' 'A' 'I' 'l' 'd' '█' )
# Default is STATIC. The shimmer only animates under a per-second refresh
# (refreshInterval:1), and on Windows/Git Bash a render cancelled mid-flight
# orphans the `node` child spawned below — leaking processes and freezing the
# CLI. So the sweep is strictly OPT-IN (safe on macOS/Linux, where the process
# group is reaped): set SKAILD_STATUSLINE_ANIM=shimmer AND refreshInterval:1.
anim=${SKAILD_STATUSLINE_ANIM:-static}
if [ "$anim" = "static" ]; then
  wordmark="$wordmark_static"
else
  plen=${#SHIMMER[@]}
  frame=$(( NOW % plen ))
  wordmark=""
  for ((c = 0; c < ${#WM_GLYPHS[@]}; c++)); do
    wordmark="${wordmark}${SHIMMER[$(( (c + frame) % plen ))]}${WM_GLYPHS[$c]}"
  done
  wordmark="${wordmark}${RESET}"
fi

# --- row 2: dev context segments ---
seg_branch=""; [ -n "$branch" ]       && seg_branch="${DIM_CYAN}${branch}${RESET}"
seg_dir="${BOLD}${dir_name}${RESET}"
seg_wt="";     [ -n "$worktree" ]     && seg_wt="${DIM_CYAN}wt:${worktree}${RESET}"
seg_prod="";   [ -n "$prod_version" ] && seg_prod="${DIM_YELLOW}prod ${prod_version}${RESET}"

# --- row 3: session dashboard segments (each guarded; missing ones vanish) ---
seg_model="";  [ -n "$model_name" ]   && seg_model="${DIM_MAGENTA}${model_name}${RESET}"
seg_ctx="";    [ -n "$remaining_pct" ] && seg_ctx="${DIM_GRAY}ctx ${remaining_pct}%${RESET}"
seg_effort=""; [ -n "$effort" ]       && seg_effort="${DIM_GRAY}◆ ${effort}${RESET}"

seg_rate=""
if [ -n "$five_pct" ] && [ -n "$seven_pct" ]; then
  seg_rate="${DIM_YELLOW}5h ${five_pct}% · 7d ${seven_pct}%${RESET}"
elif [ -n "$five_pct" ]; then
  seg_rate="${DIM_YELLOW}5h ${five_pct}%${RESET}"
elif [ -n "$seven_pct" ]; then
  seg_rate="${DIM_YELLOW}7d ${seven_pct}%${RESET}"
fi

seg_cost=""; [ -n "$cost_fmt" ] && seg_cost="${DIM_GREEN}\$${cost_fmt}${RESET}"

seg_lines=""
if [ -n "$added" ] || [ -n "$removed" ]; then
  seg_lines="${GREEN}+${added:-0}${RESET}/${RED}-${removed:-0}${RESET}"
fi

seg_pr=""
if [ -n "$pr_num" ]; then
  pr_glyph=""
  case "$pr_state" in
    approved)                        pr_glyph=" ${GREEN}✓${RESET}";;
    changes_requested)               pr_glyph=" ${RED}✗${RESET}";;
    commented|pending|review_required) pr_glyph=" ${DIM_YELLOW}●${RESET}";;
  esac
  seg_pr="${DIM_CYAN}PR#${pr_num}${RESET}${pr_glyph}"
fi

# --- responsive assembly: read COLUMNS, shed right-to-left so each row fits ---
COLS=${COLUMNS:-80}
case "$COLS" in ''|*[!0-9]*) COLS=80;; esac
[ "$COLS" -lt 1 ] && COLS=80
COLLAPSE_AT=60          # below this the wordmark row folds into an inline tag

RESULT=""
rows=()
if [ "$COLS" -ge "$COLLAPSE_AT" ]; then
  # roomy: dedicated wordmark row, then dev context, then dashboard
  rows+=( "$wordmark" )
  SEG=( "$seg_branch" "$seg_dir" "$seg_wt" "$seg_prod" ); PRI=( 3 0 2 1 )
  shed_fit "$COLS" "   "; rows+=( "$RESULT" )
  SEG=( "$seg_model" "$seg_ctx" "$seg_effort" "$seg_rate" "$seg_cost" "$seg_lines" "$seg_pr" )
  PRI=( 0 6 5 4 3 2 1 )
  shed_fit "$COLS" "   "; rows+=( "$RESULT" )
else
  # narrow: collapse the wordmark to a static inline tag (no sweep) on the dev row
  budget=$(( COLS - 7 - 2 ))          # 7 = tag width (skAIld█), 2 = gutter
  if [ "$budget" -ge 1 ]; then
    SEG=( "$seg_branch" "$seg_dir" "$seg_wt" "$seg_prod" ); PRI=( 3 0 2 1 )
    shed_fit "$budget" "   "
    rows+=( "${wordmark_static}  ${RESULT}" )
  else
    rows+=( "$(vis_trunc "$wordmark_static" "$COLS")" )
  fi
  SEG=( "$seg_model" "$seg_ctx" "$seg_effort" "$seg_rate" "$seg_cost" "$seg_lines" "$seg_pr" )
  PRI=( 0 6 5 4 3 2 1 )
  shed_fit "$COLS" "   "; rows+=( "$RESULT" )
fi

# --- emit: one line per non-empty row (never a blank row) ---
for row in "${rows[@]}"; do
  [ -n "$row" ] && printf '%s\n' "$row"
done
exit 0
