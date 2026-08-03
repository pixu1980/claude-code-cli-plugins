#!/usr/bin/env bash
# Claude Code status line — responsive, width-aware, re-evaluated on every render.
#
# Adapts to the CURRENT terminal width, which Claude Code exports as $COLUMNS before each
# invocation (v2.1.153+); stdout is piped, so tput / isatty width detection does NOT work.
# On resize the TUI redraws and re-runs this script, so the tier recomputes live.
#
# Degradation ladder (richest first — the first form that fits $COLUMNS wins):
#   1  P: Projects/my-app › B: main S: !1 › M: Opus 4.8 (1M context) E: xHigh › C: 150k/1M (15%)
#   2  P: my-app › B: main S: !1 › M: Opus 4.8 E: xHigh › C: 150k/1M (15%)
#   3  my-app | main !1 | Opus 4.8 - xHigh | 150k/1M (15%)
#   4  my-app | main | Opus 4.8 - xHigh | 150k/1M (15%)
#   5  my-app | Opus 4.8 | 150k/1M (15%)          (floor)
#
# Reads the Claude Code JSON payload on stdin (schema: https://code.claude.com/docs/en/statusline.md).

input=$(cat)

RESET=$'\033[0m'
DIM=$'\033[2m'
CYAN=$'\033[1;36m'      # directory
YELLOW=$'\033[1;33m'    # branch
WHITE=$'\033[1;37m'     # git status
MAGENTA=$'\033[1;35m'   # model
BLUE=$'\033[1;34m'      # effort

jqr() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

# Format a raw token count as 60k / 1.5M / 1M etc.
fmt_tokens() {
  awk -v n="$1" 'BEGIN {
    if (n >= 1000000)   { v = n / 1000000; if (v == int(v)) printf "%dM", v; else printf "%.1fM", v }
    else if (n >= 1000) { v = n / 1000;    if (v == int(v)) printf "%dk", v; else printf "%.0fk", v }
    else                { printf "%d", n }
  }'
}

# 24-bit gradient: green (0%) → yellow (50%) → red (100%). Prints "R;G;B".
grad_rgb() {
  awk -v p="$1" 'BEGIN {
    if (p < 0) p = 0; if (p > 100) p = 100;
    h = 120 * (1 - p / 100); s = 0.85; l = 0.5;
    c = (1 - (2*l-1 < 0 ? -(2*l-1) : 2*l-1)) * s;
    hp = h / 60;
    t = hp - 2 * int(hp / 2);
    x = c * (1 - (t-1 < 0 ? -(t-1) : t-1));
    if (hp < 1) { r = c; g = x } else { r = x; g = c }
    m = l - c/2;
    printf "%d;%d;%d", int((r+m)*255+0.5), int((g+m)*255+0.5), int((0+m)*255+0.5);
  }'
}

# ── Directory: subpath under ~/Projects (prefix stripped), else ~-relative; plus basename ──
cwd=$(jqr '.workspace.current_dir // .cwd // empty')
[ -z "$cwd" ] && cwd="$PWD"
case "$cwd" in
  "$HOME/Projects/"*) path_full="${cwd#"$HOME"/Projects/}" ;;
  "$HOME/Projects")   path_full="~" ;;
  "$HOME"/*)          path_full="~/${cwd#"$HOME"/}" ;;
  *)                  path_full="$cwd" ;;
esac
path_base=$(basename "$cwd")

# ── Branch + p10k-style git status ──
branch=""
gstatus=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
  if [ -z "$branch" ]; then
    sha=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
    [ -n "$sha" ] && branch="detached@${sha}"
  fi

  ahead=0; behind=0
  if git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    read -r ahead behind < <(git -C "$cwd" --no-optional-locks rev-list --left-right --count 'HEAD...@{upstream}' 2>/dev/null)
    ahead=${ahead:-0}; behind=${behind:-0}
  fi

  staged=0; modified=0; untracked=0
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    x=${line:0:1}; y=${line:1:1}
    if [ "$x$y" = "??" ]; then
      untracked=$((untracked + 1))
    else
      case "$x" in [MADRCU]) staged=$((staged + 1)) ;; esac
      case "$y" in [MDU])    modified=$((modified + 1)) ;; esac
    fi
  done < <(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)

  parts=""
  [ "$ahead"     -gt 0 ] && parts+="⇡${ahead} "
  [ "$behind"    -gt 0 ] && parts+="⇣${behind} "
  [ "$staged"    -gt 0 ] && parts+="+${staged} "
  [ "$modified"  -gt 0 ] && parts+="!${modified} "
  [ "$untracked" -gt 0 ] && parts+="?${untracked} "
  gstatus="${parts% }"
fi

# ── Model (full incl. any "(… context)" tag) + short (tag stripped) + effort ──
model_full=$(jqr '.model.display_name // empty')
model_short="${model_full%% (*}"
effort_raw=$(jqr '.effort.level // empty')
case "$effort_raw" in
  low) effort="Low";; medium) effort="Medium";; high) effort="High";;
  xhigh) effort="xHigh";; max) effort="Max";; "") effort="";; *) effort="$effort_raw";;
esac

# ── Context: used/max tokens + used% , colored on a green→red gradient ──
used_tok=$(jqr '.context_window.total_input_tokens // empty')
max_tok=$(jqr '.context_window.context_window_size // empty')
usedpct=$(jqr '.context_window.used_percentage // empty')
ctx=""; CTX_COLOR=""
if [ -n "$max_tok" ] && [ "$max_tok" != "0" ]; then
  [ -z "$used_tok" ] && used_tok=0
  if [ -z "$usedpct" ]; then
    usedpct=$(awk -v u="$used_tok" -v m="$max_tok" 'BEGIN { printf "%.0f", (m>0)?100*u/m:0 }')
  else
    usedpct=$(awk -v p="$usedpct" 'BEGIN { printf "%.0f", p }')
  fi
  ctx="$(fmt_tokens "$used_tok")/$(fmt_tokens "$max_tok") (${usedpct}%)"
  CTX_COLOR=$'\033[38;2;'"$(grad_rgb "$usedpct")"'m'
fi

# ── Build one variant. Sets COLORED (with ANSI) and PLAIN (for width measurement). ──
# Args: STYLE(lab|min)  PATH(full|base)  MODEL(full|short)  WANT_STATUS(0|1)  WANT_EFFORT(0|1)
build() {
  local style=$1 pm=$2 mm=$3 ws=$4 we=$5
  local p m c pp sepj sepp
  [ "$pm" = full ] && p="$path_full" || p="$path_base"
  [ "$mm" = full ] && m="$model_full" || m="$model_short"
  local -a C=() P=()

  if [ "$style" = lab ]; then
    sepj=" ${DIM}›${RESET} "; sepp=" > "
    C+=("${DIM}P:${RESET} ${CYAN}${p}${RESET}"); P+=("P: ${p}")
    if [ -n "$branch" ]; then
      c="${DIM}B:${RESET} ${YELLOW}${branch}${RESET}"; pp="B: ${branch}"
      if [ "$ws" = 1 ] && [ -n "$gstatus" ]; then c+=" ${DIM}S:${RESET} ${WHITE}${gstatus}${RESET}"; pp+=" S: ${gstatus}"; fi
      C+=("$c"); P+=("$pp")
    fi
    if [ -n "$m" ]; then
      c="${DIM}M:${RESET} ${MAGENTA}${m}${RESET}"; pp="M: ${m}"
      if [ "$we" = 1 ] && [ -n "$effort" ]; then c+=" ${DIM}E:${RESET} ${BLUE}${effort}${RESET}"; pp+=" E: ${effort}"; fi
      C+=("$c"); P+=("$pp")
    fi
    [ -n "$ctx" ] && { C+=("${DIM}C:${RESET} ${CTX_COLOR}${ctx}${RESET}"); P+=("C: ${ctx}"); }
  else
    sepj=" ${DIM}|${RESET} "; sepp=" | "
    C+=("${CYAN}${p}${RESET}"); P+=("${p}")
    if [ -n "$branch" ]; then
      c="${YELLOW}${branch}${RESET}"; pp="${branch}"
      if [ "$ws" = 1 ] && [ -n "$gstatus" ]; then c+=" ${WHITE}${gstatus}${RESET}"; pp+=" ${gstatus}"; fi
      C+=("$c"); P+=("$pp")
    fi
    if [ -n "$m" ]; then
      c="${MAGENTA}${m}${RESET}"; pp="${m}"
      if [ "$we" = 1 ] && [ -n "$effort" ]; then c+=" ${DIM}-${RESET} ${BLUE}${effort}${RESET}"; pp+=" - ${effort}"; fi
      C+=("$c"); P+=("$pp")
    fi
    [ -n "$ctx" ] && { C+=("${CTX_COLOR}${ctx}${RESET}"); P+=("${ctx}"); }
  fi

  COLORED="${C[0]}"; PLAIN="${P[0]}"
  local i
  for ((i = 1; i < ${#C[@]}; i++)); do COLORED+="${sepj}${C[$i]}"; PLAIN+="${sepp}${P[$i]}"; done
}

width=${COLUMNS:-80}

# Ladder, richest first: pick the first that fits $width; otherwise fall through to the floor.
best=""
for spec in \
  "lab full full 1 1" \
  "lab base short 1 1" \
  "min base short 1 1" \
  "min base short 0 1" \
  "min base short 0 0"; do
  build $spec
  best="$COLORED"
  [ "${#PLAIN}" -le "$width" ] && break
done

printf '%s\n' "$best"
