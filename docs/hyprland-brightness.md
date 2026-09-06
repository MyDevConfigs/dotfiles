# Hyprland brightness keys do nothing (Lenovo Yoga Pro 9i)

A runbook for a fix that is **not tracked by stow**. `Brightness.sh` and the
waybar `Modules` file belong to KoolDots, which reinstalls them from upstream.
Reinstall the desktop and this fix is gone — reapply it from here.

Hardware this was written for: **Lenovo Yoga Pro 9 16IMH9** (`83DN`), Intel
Meteor Lake iGPU + NVIDIA RTX 4070 Max-Q, panel `LEN160-3.2K` (CSOT, 3200x2000
@165Hz, Mini-LED), Ubuntu 26.04, kernel 7.0.

---

## Symptom

The `Fn` brightness keys do nothing. The screen never changes. Depending on
the config you may still see the OSD notification, stuck at 100%, or the
waybar backlight icon frozen at full.

Hyprland is **not** the problem. The keybinds fire correctly — verify with
`hyprctl binds | grep -i brightness`, which lists the `XF86MonBrightnessUp`
and `XF86MonBrightnessDown` binds. The failure is one layer down.

---

## Root cause

This laptop exposes **two** backlight devices:

```console
$ ls /sys/class/backlight/
intel_backlight   nvidia_0
```

Only one of them is real:

| Device | Max | Backing hardware | Effect |
| --- | --- | --- | --- |
| `intel_backlight` | 1200 | `card1` / i915 / PCI `00:02.0` — drives panel `eDP-1` | **the real one** |
| `nvidia_0` | 100 | `nvidia_modeset` on the dGPU, which has **no display attached** | writes succeed, nothing happens |

The panel hangs off the Intel iGPU. Confirm it:

```bash
readlink -f /sys/class/backlight/intel_backlight
# /sys/devices/pci0000:00/0000:00:02.0/drm/card1/card1-eDP-1/intel_backlight
#                          ^^^^^^^^ Intel Arc (Meteor Lake), driver i915

for c in /sys/class/drm/card*-*/; do
  [ "$(cat "$c/status" 2>/dev/null)" = connected ] && basename "$c"
done
# card1-eDP-1     <- the only connected output, and it is Intel's
```

`nvidia_0` is a phantom. `nvidia_modeset` registers a backlight for the
discrete GPU whether or not anything is plugged into it, and it sits pinned at
`100/100`.

**The trap:** `brightnessctl` with no `-d` picks the *first* entry in
`/sys/class/backlight`, and `nvidia_0` sorts first here.

```console
$ brightnessctl -m
nvidia_0,backlight,100,100%,100     # <- the wrong default
```

KoolDots' `Brightness.sh` calls `brightnessctl` without `-d`, so every keypress
reads and writes the phantom. No error is raised — the write genuinely
succeeds, it just controls nothing.

### Things that are *not* the cause

Rule these out so you don't chase them:

- **Permissions.** `/usr/bin/brightnessctl` is `-rwsr-sr-x root root` (setuid
  root), so it writes regardless of group. You do **not** need to add yourself
  to the `video` group; on this machine the user is not in it and the fix works
  anyway. Check with `ls -l /usr/bin/brightnessctl`.
- **`acpi_backlight=` kernel parameters.** Not needed. There is no
  `acpi_video0` device competing here; the cmdline carries no backlight flag.
- **Hyprland binds.** They fire. See above.
- **udev rules.** `/usr/lib/udev/rules.d/90-brightnessctl.rules` is present and
  correct.

---

## Detect before you patch

Do not hardcode `intel_backlight` blindly — on a different machine the real
device may be `amdgpu_bl0`, `acpi_video0`, or `nvidia_wmi_ec_backlight`. Find
the device that backs the connected panel:

```bash
for d in /sys/class/backlight/*/; do
  dev=$(basename "$d")
  printf '%-28s max=%-6s path=%s\n' \
    "$dev" "$(cat "$d/max_brightness")" "$(readlink -f "$d" | sed 's|/sys/devices||')"
done
```

Pick the one whose path contains the PCI address of the GPU driving the
connected `eDP` connector. A `max_brightness` of exactly `100` on an NVIDIA
path is a strong phantom tell; a real panel is usually a PWM range in the
hundreds or thousands.

If there is only one device, this machine does not have the bug.

---

## Files touched

Both live in `~/.config`, both are owned by KoolDots, **neither is stowed**.

| File | Change |
| --- | --- |
| `~/.config/hypr/scripts/Brightness.sh` | pin `brightnessctl` to `intel_backlight`; absolute minimum floor |
| `~/.config/waybar/Modules` | add `"device"` to the `backlight` module |

---

## Patch 1 — `~/.config/hypr/scripts/Brightness.sh`

Three edits. The first two are the actual bug fix; the third is a preference.

### 1a. Pin the read

```bash
# before
    brightnessctl -m | cut -d, -f4 | tr -d '%'
# after
    brightnessctl -d intel_backlight -m | cut -d, -f4 | tr -d '%'
```

### 1b. Pin the write

```bash
# before
    brightnessctl set "${new}%"
# after
    brightnessctl -d intel_backlight set "${new}%"
```

Those two alone restore working brightness keys. Stop here if you don't care
about the floor.

### 1c. Absolute minimum floor (optional)

Upstream clamps at 5%, which on a 1200-step panel is 60. To floor at a specific
**raw** value instead, add next to `step=10` near the top:

```bash
step=10  # INCREASE/DECREASE BY THIS VALUE
min_raw=20  # absolute floor on the device scale (0-max_brightness), NOT a percentage
```

and replace the clamp block inside `change_brightness()`:

```bash
# before
    local current new icon

    current=$(get_brightness)
    new=$((current + delta))

    # Clamp between 5 and 100
    (( new < 5 )) && new=5
    (( new > 100 )) && new=100

    brightnessctl -d intel_backlight set "${new}%"
```

```bash
# after
    local current new icon max

    current=$(get_brightness)
    new=$((current + delta))

    (( new > 100 )) && new=100
    (( new < 0 )) && new=0

    # Floor is absolute, not percentage: 20/1200 is not a whole percent
    max=$(brightnessctl -d intel_backlight -m | cut -d, -f5)
    if (( new * max / 100 < min_raw )); then
        brightnessctl -d intel_backlight set "$min_raw"
        new=$(( (min_raw * 100 + max / 2) / max ))
    else
        brightnessctl -d intel_backlight set "${new}%"
    fi
```

**Why the floor has to be absolute.** The script does integer-percent
arithmetic, and 20/1200 = 1.67% is not a whole percent — 1% is 12 and 2% is 24,
neither of which is 20. Clamping in percent cannot express the value. `max` is
read from the device rather than hardcoded to 1200, so the floor stays correct
on a different panel.

**Known rough edge.** With a floor this low, the first press *up* jumps from 20
to 144 (2% → 12%), because a step is 10 percentage points = 120 raw. Coming off
the floor also shifts the grid by 2 (22%, 32%, 42%…) until you reach 100%.
Measured behaviour:

```
down from 50%:  480(40%) 360(30%) 240(20%) 120(10%) 20(2%) 20 20 20
up from 20:     144(12%) 264(22%) 384(32%) 504(42%) 624(52%)
```

Fixing that properly means non-linear steps (small below 20%, 10 above), which
upstream does not do. Left alone deliberately.

---

## Patch 2 — `~/.config/waybar/Modules`

The `"backlight"` module has no `"device"` key, so it reads the phantom and the
icon never moves. Add one line:

```jsonc
// before
"backlight": {
	"interval": 2,

// after
"backlight": {
	"device": "intel_backlight",
	"interval": 2,
```

Note the file already contains a `"backlight#2"` block that has `"device":
"intel_backlight"` set correctly — but the default laptop config
(`~/.config/waybar/configs/TOP-Default-Laptop`) uses the plain `"backlight"`
module, so that one is the one that matters. Leave `#2` alone.

Reload waybar in place:

```bash
killall -SIGUSR2 waybar
```

Hyprland needs no reload — the keybinds exec the script fresh on every press.

---

## Verify

```bash
# 1. the device the tool defaults to (should now be irrelevant, but confirms the bug)
brightnessctl -m
# nvidia_0,backlight,100,100%,100

# 2. the real device responds
brightnessctl -d intel_backlight set 30%    # screen must visibly dim
brightnessctl -d intel_backlight set 600    # back to 50% of 1200

# 3. the script drives the real device
~/.config/hypr/scripts/Brightness.sh --dec
brightnessctl -d intel_backlight -m | cut -d, -f3,4

# 4. the floor holds
for i in $(seq 1 8); do ~/.config/hypr/scripts/Brightness.sh --dec >/dev/null; done
brightnessctl -d intel_backlight -m | cut -d, -f3,4
# 20,2%

brightnessctl -d intel_backlight set 600
```

Then press the physical `Fn` brightness keys — that is the only step none of
the above actually covers.

### Panel floor, measured

`20/1200` is still readable on this panel. `bl_power` stays `0` (backlight on)
and the kernel exposes no minimum: `scale` reads `unknown` and there is no
`min_brightness` attribute, so the usable floor is a property of the panel that
can only be found by looking at the screen. Below roughly this point a Mini-LED
backlight goes dark rather than dim.

---

## If it comes back after a KoolDots update

Reapply both patches. To find whether upstream has reverted them:

```bash
grep -n 'brightnessctl' ~/.config/hypr/scripts/Brightness.sh | grep -v '\-d '
grep -n -A2 '"backlight": {' ~/.config/waybar/Modules
```

Any `brightnessctl` call in `Brightness.sh` without `-d` is a reverted line.
The `kbd_backlight` calls in `BrightnessKbd.sh` already carry
`-d '*::kbd_backlight'` and are fine — leave that file alone.
