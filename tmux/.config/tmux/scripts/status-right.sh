#!/usr/bin/env bash
#
# Assembles the variable part of the status bar.
#
# ── Why this exists ───────────────────────────────────────────────────────
#
# Separators used to live in tmux.conf, one written before each widget. That
# is wrong whenever a widget can be empty: the widget disappears and its
# separator stays behind, so the bar shows
#
#     ◌ 55% •  • Sat 05 Sep
#              ^^^^^ nothing between two dots
#
# Weather is empty on a cold cache, with no network, or when wttr.in is
# slow; CPU and RAM are empty for the first seconds after the server starts,
# before tmux-cpu's jobs have run; batteries are empty on a desktop with no
# wireless peripherals. Every one of those left an orphan.
#
# So nothing here emits a separator. Segments are collected, the empty ones
# dropped, and the join puts a separator only BETWEEN what survived.
#
# It also costs less: one process per interval instead of four.
#
# ── Why tmux-cpu's scripts are called by path ─────────────────────────────
#
# The obvious approach — passing '#{cpu_percentage}' as an argument and
# letting tmux expand it first — does not work. tmux-cpu implements that
# format variable by REWRITING it into #(.../cpu_percentage.sh) inside
# status-right when the plugin loads. Doing it that way therefore produces
# #() nested inside #(), which tmux does not expand, and both readings come
# through empty.
#
# So the scripts are invoked directly. That couples this file to the
# plugin's install location, which is why a missing script is handled rather
# than assumed: the segment is simply dropped, exactly like any other empty
# reading.

set -o nounset

readonly GRAY='#928374'
readonly DIM='#665c54'
readonly SEP=' • '

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly CPU_PLUGIN="${here%/scripts}/plugins/tmux-cpu/scripts"

# run <script> — its output, or nothing if the plugin is not installed.
run() {
    [[ -x "$1" ]] || return 0
    "$1" 2>/dev/null
}

CPU_RAW="$(run "$CPU_PLUGIN/cpu_percentage.sh")"
RAM_RAW="$(run "$CPU_PLUGIN/ram_percentage.sh")"

declare -a segments=()

# add <value> <rendered> — keep the rendered form only if the VALUE has
# content. Testing the rendered string would be useless: it always carries a
# #[fg=...] prefix, so it is never empty even when the reading is.
add() {
    local value="$1" rendered="$2"
    [[ -n "${value//[[:space:]]/}" ]] || return 0
    segments+=("$rendered")
}

add "$CPU_RAW" "#[fg=${GRAY}]󰻠 ${CPU_RAW}"
add "$RAM_RAW" "#[fg=${GRAY}]󰍛 ${RAM_RAW}"

# battery.sh emits one bare segment per line, or nothing at all. Each line
# is already non-empty by construction, so it is its own value.
while IFS= read -r line; do
    add "$line" "$line"
done < <("$here/battery.sh")

weather="$("$here/weather.sh")"
add "$weather" "#[fg=${GRAY}]${weather}"

((${#segments[@]})) || exit 0

printf '%s' "${segments[0]}"
for (( i = 1; i < ${#segments[@]}; i++ )); do
    printf '#[fg=%s]%s%s' "$DIM" "$SEP" "${segments[i]}"
done
