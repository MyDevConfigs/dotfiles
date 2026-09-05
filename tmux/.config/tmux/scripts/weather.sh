#!/usr/bin/env bash
#
# Weather for the tmux status bar.
#
# The important property here is that this NEVER blocks. tmux runs
# status-right synchronously — a slow or hanging network call freezes the
# whole client, not just this segment. So the script only ever prints from a
# cache file, and when that cache is stale it kicks off a refresh in the
# background and prints the old value anyway. The bar updates a few seconds
# later on the next status-interval tick.
#
# wttr.in geolocates by IP. If that is not wanted, set TMUX_WEATHER_LOCATION
# to a city name and the request becomes explicit rather than inferred.

set -o nounset
set -o pipefail

_uid="$(id -u)"
readonly CACHE="${TMPDIR:-/tmp}/tmux-weather.${_uid}.cache"
readonly MAX_AGE=900   # 15 minutes; weather does not move faster than that
readonly LOCATION="${TMUX_WEATHER_LOCATION:-}"

# The condition is fetched as TEXT (%C) rather than as wttr.in's emoji (%c),
# and mapped to a Nerd Font glyph below.
#
# The emoji are the problem: they are double-width, they carry a variation
# selector, and the width is not even consistent between conditions — a sun
# and a thunderstorm occupy different numbers of cells. In a status bar that
# means everything to the right of the weather shifts when the sky changes.
# Nerd Font weather glyphs are single-width and uniform.
#
# %7C is a URL-encoded pipe, used as the separator.
readonly FORMAT='%C%7C%t'

# Condition -> glyph, from the Nerd Fonts Material Design weather set
# (nf-md-weather-*), chosen for two reasons:
#
#   . Every one is unmistakable at terminal size. The previous set used
#     nf-weather-night_clear for a clear night, which draws as a thin ring
#     and was indistinguishable from the bullet separator three characters
#     to its left -- a bug that only appeared after dark.
#   . They are the same family as the CPU and RAM glyphs, so the right-hand
#     side of the bar reads as one set rather than three.
#
# Matched case-insensitively as a substring, first hit wins, so order
# matters: "patchy rain possible" must reach 'rain' before anything vaguer,
# and 'torrential' must be tested before plain 'rain'.
weather::glyph() {
    local condition="${1,,}"
    case "$condition" in
        *thunder*|*storm*)              printf '\U000f0593' ;;   # lightning
        *blizzard*|*snow*|*sleet*|*ice*)
                                        printf '\U000f0598' ;;   # snowy
        *torrential*|*"heavy rain"*|*downpour*)
                                        printf '\U000f0596' ;;   # pouring
        *rain*|*drizzle*|*shower*)      printf '\U000f0597' ;;   # rainy
        *fog*|*mist*|*haze*|*smoke*)    printf '\U000f0591' ;;   # fog
        *wind*|*gale*)                  printf '\U000f059d' ;;   # windy
        *overcast*)                     printf '\U000f0590' ;;   # cloudy
        *partly*|*cloud*)               printf '\U000f0595' ;;   # partly cloudy
        *sunny*)                        printf '\U000f0599' ;;   # sunny
        *clear*)                        printf '\U000f0594' ;;   # clear night
        *)                              printf '\U000f0599' ;;   # fallback
    esac
}

weather::refresh() {
    local out
    out="$(curl --fail --silent --max-time 8 \
        "https://wttr.in/${LOCATION}?format=${FORMAT}" 2>/dev/null)" || return 1

    # Reject anything that smells like an error page rather than a reading.
    [[ -n "$out" && ${#out} -lt 48 && "$out" == *"|"* && "$out" != *"Unknown"* ]] || return 1

    local condition="${out%%|*}" temp="${out##*|}"
    condition="${condition%"${condition##*[![:space:]]}"}"   # trim trailing space

    # Store the rendered string, not the raw reading: the status bar should
    # never do work it can avoid, and the glyph never changes for a given
    # condition.
    printf '%b %s' "$(weather::glyph "$condition")" "$temp" \
        >"${CACHE}.tmp" && mv -f "${CACHE}.tmp" "$CACHE"
}

# Stale, or never fetched? Start a refresh, detached, and carry on.
if [[ ! -s "$CACHE" ]] || (( $(date +%s) - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0) > MAX_AGE )); then
    ( weather::refresh & ) >/dev/null 2>&1
fi

# Print whatever is cached. Empty on the very first run, which renders as an
# empty segment for a few seconds rather than as an error.
if [[ -s "$CACHE" ]]; then
    tr -d '\n' <"$CACHE"
fi
