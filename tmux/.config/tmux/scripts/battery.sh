#!/usr/bin/env bash
#
# Battery segments for the tmux status bar.
#
# Portable across machines by design: it enumerates whatever the kernel
# exposes rather than assuming a laptop or a particular peripheral. System
# batteries come first, then peripherals, capped at MAX_SHOWN.
#
# ── Why devices are labelled from a table rather than detected ────────────
#
# Classifying a peripheral automatically does not work. udev reports this
# machine's Logitech PRO X2 as BOTH:
#
#     ID_INPUT_MOUSE=1
#     ID_INPUT_KEYBOARD=1
#
# Combo devices are the norm — wireless keyboards expose a mouse endpoint
# for media keys — so any "guess the icon from the device class" logic is a
# coin flip. What IS reliable is POWER_SUPPLY_SCOPE, which cleanly separates
# a system battery from a peripheral one. Everything past that comes from
# the table below, which is the part meant to be edited.

set -o nounset

readonly MAX_SHOWN=3

# ── Edit here ─────────────────────────────────────────────────────────────
# Matched case-insensitively as a substring of the device's model_name.
# First match wins; order matters. Anything unmatched gets a generic icon
# and the first word of its model name.
declare -ra DEVICE_ICONS=(
    'superstrike:󰌌'
    'keyboard:󰌌'
    'keys:󰌌'
    'mouse:󰍽'
    'mx master:󰍽'
    'headset:󰋋'
    'headphone:󰋋'
    'buds:󰋋'
    'controller:󰊴'
    'gamepad:󰊴'
    'pen:󰏪'
    'tablet:󰓶'
)

# ── Palette (gruvbox, matching tmux.conf) ─────────────────────────────────
#
# The bar is flat, so these are foreground colours only. GRAY is the normal
# state; yellow and red appear solely when a charge is actually low. Colour
# means "attention" everywhere in this bar, and a healthy battery is not
# asking for any.
readonly GRAY='#928374'
readonly RED='#cc241d'
readonly YELLOW='#d79921'

# System battery glyphs by charge, so the icon itself carries the reading.
battery::system_icon() {
    local pct="$1" status="$2"
    [[ "$status" == "Charging" || "$status" == "Full" ]] && { printf '󰂄'; return; }
    if   (( pct >= 90 )); then printf '󰁹'
    elif (( pct >= 70 )); then printf '󰂁'
    elif (( pct >= 50 )); then printf '󰁿'
    elif (( pct >= 30 )); then printf '󰁽'
    elif (( pct >= 15 )); then printf '󰁻'
    else                       printf '󰁺'
    fi
}

battery::device_icon() {
    local model="${1,,}" entry key
    for entry in "${DEVICE_ICONS[@]}"; do
        key="${entry%%:*}"
        [[ "$model" == *"$key"* ]] && { printf '%s' "${entry#*:}"; return; }
    done
    printf '󰥉'   # unknown peripheral
}

battery::colour() {
    local pct="$1"
    if   (( pct < 15 )); then printf '%s' "$RED"
    elif (( pct < 35 )); then printf '%s' "$YELLOW"
    else                      printf '%s' "$GRAY"
    fi
}

# One bare reading per line. No separator: status-right.sh collects these
# alongside the other widgets and puts separators only between the ones that
# turned out to be non-empty.
battery::render() {
    local icon="$1" pct="$2" colour
    colour="$(battery::colour "$pct")"

    printf '#[fg=%s]%s %s%%\n' "$colour" "$icon" "$pct"
}

# ── Collect ───────────────────────────────────────────────────────────────
# Two passes so system batteries always lead, regardless of sysfs ordering.

declare -a system_segments=() device_segments=()

for supply in /sys/class/power_supply/*/; do
    [[ -r "$supply/type" && -r "$supply/capacity" ]] || continue
    [[ "$(<"$supply/type")" == "Battery" ]] || continue

    capacity="$(<"$supply/capacity")"
    [[ "$capacity" =~ ^[0-9]+$ ]] || continue

    # A sleeping or unpaired receiver reports 0. That is absence, not an
    # empty battery, and showing a red 0% for a mouse in a drawer is noise.
    (( capacity > 0 )) || continue

    scope=''
    [[ -r "$supply/scope" ]] && scope="$(<"$supply/scope")"

    if [[ "$scope" == "Device" ]]; then
        model=''
        [[ -r "$supply/model_name" ]] && model="$(<"$supply/model_name")"
        device_segments+=("$(battery::render "$(battery::device_icon "$model")" "$capacity")")
    else
        status=''
        [[ -r "$supply/status" ]] && status="$(<"$supply/status")"
        system_segments+=("$(battery::render "$(battery::system_icon "$capacity" "$status")" "$capacity")")
    fi
done

shown=0
for segment in "${system_segments[@]:-}" "${device_segments[@]:-}"; do
    [[ -n "$segment" ]] || continue
    (( shown < MAX_SHOWN )) || break
    printf '%s\n' "${segment%$'\n'}"
    (( shown++ ))
done
