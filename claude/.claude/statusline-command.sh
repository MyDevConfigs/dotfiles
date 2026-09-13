#!/bin/bash
# Claude Code status line — minimal, icon-led.
#   📁 dir   ⏱ 5h usage bar   📅 7d usage bar   🔢 session tokens
# Data comes from the status-line JSON payload on stdin (no network calls).

input=$(cat)

# ---- one jq pass for everything we need -------------------------------------
mapfile -t F < <(
  printf '%s' "$input" | jq -r '
    (.workspace.current_dir // .cwd // ""),
    (.workspace.project_dir // .workspace.current_dir // .cwd // ""),
    (.transcript_path // ""),
    (.session_id // "x"),
    (.rate_limits.five_hour.used_percentage // -1),
    (.rate_limits.seven_day.used_percentage // -1),
    (.rate_limits.five_hour.resets_at // 0),
    (.rate_limits.seven_day.resets_at // 0)' 2>/dev/null
)
cur_dir=${F[0]}; proj_dir=${F[1]}; transcript=${F[2]}
sid=${F[3]:-x}; pct5=${F[4]:--1}; pct7=${F[5]:--1}
rst5=${F[6]:-0}; rst7=${F[7]:-0}

[ -z "$cur_dir" ] && cur_dir=$(pwd)
[ -z "$proj_dir" ] && proj_dir="$cur_dir"

# ---- colors -----------------------------------------------------------------
e=$'\033'
DIM="${e}[38;5;242m"; OFF="${e}[0m"
DIR="${e}[1;38;5;39m"; LBL="${e}[38;5;245m"; TRK="${e}[38;5;237m"
lvl_color() {                       # green → amber → red as the window fills
  if   [ "$1" -ge 90 ]; then printf '%s' "${e}[38;5;203m"
  elif [ "$1" -ge 75 ]; then printf '%s' "${e}[38;5;215m"
  elif [ "$1" -ge 50 ]; then printf '%s' "${e}[38;5;221m"
  else                       printf '%s' "${e}[38;5;78m"; fi
}

# ---- directory: shorten to ~/… and keep at most the last two segments -------
short_dir() {
  local p="${1/#$HOME/\~}" base parent
  case "$p" in
    "~"|/) printf '%s' "$p"; return;;
  esac
  base=${p##*/}; parent=${p%/*}
  if [ ${#p} -le 28 ] || [ -z "$parent" ]; then printf '%s' "$p"
  else printf '…/%s/%s' "${parent##*/}" "$base"; fi
}

# ---- progress bar: 10 cells, eighth-block precision -------------------------
BLOCKS=('' '▏' '▎' '▍' '▌' '▋' '▊' '▉')
bar() {
  local pct=$1 width=10 c full rem i out=''
  [ "$pct" -lt 0 ] && pct=0; [ "$pct" -gt 100 ] && pct=100
  c=$(lvl_color "$pct")
  local eighths=$(( pct * width * 8 / 100 ))
  full=$(( eighths / 8 )); rem=$(( eighths % 8 ))
  out="$c"
  for ((i=0; i<full; i++)); do out+='█'; done
  if [ $rem -gt 0 ] && [ $full -lt $width ]; then out+="${BLOCKS[$rem]}"; full=$((full+1)); fi
  out+="$TRK"
  for ((i=full; i<width; i++)); do out+='░'; done
  printf '%s%s %s%3d%%%s' "$out" "$OFF" "$c" "$pct" "$OFF"
}

# ---- session token counter (cached against transcript mtime) ----------------
human() {
  local n=$1
  if   [ "$n" -ge 1000000 ]; then awk -v n="$n" 'BEGIN{printf "%.1fM", n/1000000}'
  elif [ "$n" -ge 1000 ];    then awk -v n="$n" 'BEGIN{printf "%.1fK", n/1000}'
  else printf '%d' "$n"; fi
}
# ---- "resets in" countdown --------------------------------------------------
countdown() {                       # epoch seconds -> compact "1d22h" / "2h13m" / "47m"
  local at=$1 left now
  [ "$at" -gt 0 ] 2>/dev/null || return
  now=$(date +%s); left=$(( at - now ))
  [ $left -le 0 ] && { printf '%s' 'now'; return; }
  local d=$(( left / 86400 )) h=$(( left % 86400 / 3600 )) m=$(( left % 3600 / 60 ))
  if   [ $d -gt 0 ]; then printf '%dd%dh' "$d" "$h"
  elif [ $h -gt 0 ]; then printf '%dh%02dm' "$h" "$m"
  else printf '%dm' "$(( m > 0 ? m : 1 ))"; fi
}

tokens=0
if [ -r "$transcript" ]; then
  cache_dir="${TMPDIR:-/tmp}/claude-statusline-$UID"; mkdir -p "$cache_dir" 2>/dev/null
  cache="$cache_dir/$sid.tok"
  mtime=$(stat -c %Y "$transcript" 2>/dev/null || echo 0)
  if [ -r "$cache" ] && read -r c_mtime c_tok < "$cache" 2>/dev/null && [ "$c_mtime" = "$mtime" ]; then
    tokens=$c_tok
  else
    tokens=$(jq -n 'reduce (inputs | .message.usage? // empty) as $u (0;
        . + ($u.input_tokens//0) + ($u.output_tokens//0)
          + ($u.cache_creation_input_tokens//0) + ($u.cache_read_input_tokens//0))' \
        "$transcript" 2>/dev/null) || tokens=0
    [ -z "$tokens" ] && tokens=0
    printf '%s %s\n' "$mtime" "$tokens" > "$cache" 2>/dev/null
  fi
fi

# ---- render -----------------------------------------------------------------
sep="  ${DIM}·${OFF}  "
out="${DIM}📁${OFF} ${DIR}$(short_dir "$proj_dir")${OFF}"
reset_tag() { local t; t=$(countdown "$1"); [ -n "$t" ] && printf ' %s↻%s%s' "$DIM" "$t" "$OFF"; }
[ "$pct5" -ge 0 ] 2>/dev/null && out+="${sep}${DIM}⏱${OFF} ${LBL}5h${OFF} $(bar "$pct5")$(reset_tag "$rst5")"
[ "$pct7" -ge 0 ] 2>/dev/null && out+="${sep}${DIM}📅${OFF} ${LBL}7d${OFF} $(bar "$pct7")$(reset_tag "$rst7")"
[ "$tokens" -gt 0 ] 2>/dev/null && out+="${sep}${DIM}🔢${OFF} ${LBL}$(human "$tokens")${OFF}"
printf '%s' "$out"
