# Kitty on WSL2 / Windows 11 with WSLg, Wayland, and D3D12

This guide installs and configures a recent upstream version of `kitty` on Ubuntu running under WSL2 on Windows 11, using WSLg with Wayland and accelerated OpenGL via D3D12.

It also fixes common issues such as:

- `Error: couldn't open display 10.x.x.x:0`
- `Wayland: Failed to connect to display`
- `GLFW initialization failed`
- `No such interface "org.freedesktop.portal.Settings"`
- `MESA: error: ZINK: failed to choose pdev`
- `Ignoring unknown config key: cursor_trail`

## Target environment

This guide assumes:

- Windows 11
- WSL2
- Ubuntu 24.04 or similar
- WSLg enabled
- `zsh` as the interactive shell
- User wants to run Linux `kitty` inside WSLg

## Important limitations

Some kitty features may still not work under WSLg even after a correct setup.

In particular:

- `background_opacity` may work.
- `background_blur` usually does **not** work under WSLg because WSLg's Wayland compositor does not expose the blur/background-effect protocol expected by kitty.
- `cursor_trail` requires kitty `0.37` or newer. Ubuntu's apt version may be too old.

---

# 1. Initial diagnostics

Run:

```bash
printf 'DISPLAY=%s\n' "$DISPLAY"
printf 'WAYLAND_DISPLAY=%s\n' "$WAYLAND_DISPLAY"
printf 'XDG_RUNTIME_DIR=%s\n' "$XDG_RUNTIME_DIR"
printf 'WSL_DISTRO_NAME=%s\n' "$WSL_DISTRO_NAME"
printf 'WSL_INTEROP=%s\n' "$WSL_INTEROP"
```

Expected WSLg-related values are usually:

```bash
DISPLAY=:0
WAYLAND_DISPLAY=wayland-0
```

However, with systemd enabled in WSL, `XDG_RUNTIME_DIR` may be:

```bash
/run/user/1000/
```

while the actual WSLg Wayland socket is located at:

```bash
/mnt/wslg/runtime-dir/wayland-0
```

Check both locations:

```bash
ls -la "$XDG_RUNTIME_DIR" 2>&1
ls -la /mnt/wslg 2>&1
ls -la /mnt/wslg/runtime-dir 2>&1
```

---

# 2. Fix DISPLAY for WSLg

If `DISPLAY` points to something like:

```bash
10.x.x.x:0
```

that is usually a Windows 10 / external X server style configuration.

For Windows 11 + WSLg, use:

```bash
unset LIBGL_ALWAYS_INDIRECT
export DISPLAY=:0
```

Test:

```bash
glxgears
```

If this works, remove old `DISPLAY` overrides from shell startup files:

```bash
grep -R "DISPLAY=\|LIBGL_ALWAYS_INDIRECT" ~/.bashrc ~/.zshrc ~/.profile /etc/profile /etc/profile.d/* 2>/dev/null
```

Remove or comment lines such as:

```bash
export DISPLAY=$(awk '/nameserver / {print $2; exit}' /etc/resolv.conf 2>/dev/null):0
export LIBGL_ALWAYS_INDIRECT=0
```

---

# 3. Install required packages

Install the packages needed for diagnostics, Wayland, EGL, DBus user sessions, and xdg-desktop-portal:

```bash
sudo apt update
sudo apt install -y \
  dbus-user-session \
  xdg-desktop-portal \
  xdg-desktop-portal-gtk \
  mesa-utils \
  mesa-utils-extra \
  wayland-utils \
  curl
```

If `apt update` shows unrelated GPG errors for third-party repositories, fix them separately. They are not usually related to kitty or WSLg.

---

# 4. Configure xdg-desktop-portal

Create a portal configuration that forces the GTK portal backend:

```bash
mkdir -p ~/.config/xdg-desktop-portal

cat > ~/.config/xdg-desktop-portal/portals.conf <<'EOF'
[preferred]
default=gtk
org.freedesktop.impl.portal.Settings=gtk
EOF
```

Restart portal services:

```bash
systemctl --user daemon-reload
systemctl --user restart xdg-desktop-portal.service xdg-desktop-portal-gtk.service
```

Verify that the Settings portal is available:

```bash
busctl --user introspect org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop | grep -F "org.freedesktop.portal.Settings" || true
```

Expected output should include:

```text
org.freedesktop.portal.Settings
```

---

# 5. Fix Wayland socket location for systemd-based WSL sessions

In some WSL setups, especially when systemd is enabled, applications look for Wayland at:

```bash
$XDG_RUNTIME_DIR/wayland-0
```

but WSLg provides it at:

```bash
/mnt/wslg/runtime-dir/wayland-0
```

Create symlinks:

```bash
rm -f "$XDG_RUNTIME_DIR/wayland-0" "$XDG_RUNTIME_DIR/wayland-0.lock"

ln -s /mnt/wslg/runtime-dir/wayland-0 "$XDG_RUNTIME_DIR/wayland-0"
ln -s /mnt/wslg/runtime-dir/wayland-0.lock "$XDG_RUNTIME_DIR/wayland-0.lock"

export WAYLAND_DISPLAY=wayland-0
```

Verify:

```bash
ls -l "$XDG_RUNTIME_DIR"/wayland-0*
```

Expected output:

```text
/run/user/1000/wayland-0 -> /mnt/wslg/runtime-dir/wayland-0
/run/user/1000/wayland-0.lock -> /mnt/wslg/runtime-dir/wayland-0.lock
```

---

# 6. Add the user to the render group

Check GPU device permissions:

```bash
ls -la /dev/dri 2>&1
ls -l /dev/dri/renderD128 2>&1
id
getent group render
getent group video
```

If `/dev/dri/renderD128` belongs to group `render`, make sure the user is in that group:

```bash
sudo usermod -aG render "$USER"
```

Then fully restart WSL.

From PowerShell on Windows:

```powershell
wsl --shutdown
```

Then reopen Ubuntu/WSL.

Check:

```bash
id
```

Expected output should include:

```text
render
```

Do **not** rely on `newgrp render` for final testing. It can cause portal permission issues such as:

```text
Portal operation not allowed: Unable to open /proc/.../root
```

A clean WSL restart is preferred.

---

# 7. Force Mesa to use D3D12 under WSLg

Check current OpenGL renderer:

```bash
glxinfo -B | grep -E 'Device|Accelerated|renderer'
```

If it shows:

```text
llvmpipe
Accelerated: no
```

test D3D12 explicitly:

```bash
GALLIUM_DRIVER=d3d12 glxinfo -B | grep -E 'Device|Accelerated|renderer'
```

Expected output should include something similar to:

```text
Device: D3D12 (...)
Accelerated: yes
OpenGL renderer string: D3D12 (...)
```

If this works, make it permanent in `~/.zshrc`.

---

# 8. Make the WSLg fixes persistent

Append this to `~/.zshrc`:

```bash
cat >> ~/.zshrc <<'EOF'

# WSLg Wayland socket for apps using XDG_RUNTIME_DIR=/run/user/$UID
if [ -d /mnt/wslg/runtime-dir ] && [ -n "$XDG_RUNTIME_DIR" ]; then
  if [ ! -S "$XDG_RUNTIME_DIR/wayland-0" ] && [ -S /mnt/wslg/runtime-dir/wayland-0 ]; then
    rm -f "$XDG_RUNTIME_DIR/wayland-0" "$XDG_RUNTIME_DIR/wayland-0.lock"
    ln -s /mnt/wslg/runtime-dir/wayland-0 "$XDG_RUNTIME_DIR/wayland-0"
    ln -s /mnt/wslg/runtime-dir/wayland-0.lock "$XDG_RUNTIME_DIR/wayland-0.lock"
  fi

  export WAYLAND_DISPLAY=wayland-0
fi

# Prefer WSLg accelerated OpenGL through D3D12
export GALLIUM_DRIVER=d3d12
EOF
```

Reload:

```bash
source ~/.zshrc
hash -r
rehash 2>/dev/null || true
```

Test:

```bash
glxinfo -B | grep -E 'Device|Accelerated|renderer'
```

Expected:

```text
Device: D3D12 (...)
Accelerated: yes
OpenGL renderer string: D3D12 (...)
```

---

# 9. Remove old apt kitty

Ubuntu's apt package may be old and may not support modern options such as `cursor_trail`.

Check installed version:

```bash
kitty --version 2>/dev/null || true
which kitty 2>/dev/null || true
apt policy kitty 2>/dev/null || true
```

Remove the apt version:

```bash
sudo apt remove -y kitty kitty-doc
```

Optional cleanup:

```bash
sudo apt autoremove -y
```

---

# 10. Install the latest upstream kitty

Install kitty using the official upstream installer:

```bash
curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n
```

Create symlinks:

```bash
mkdir -p ~/.local/bin
ln -sf ~/.local/kitty.app/bin/kitty ~/.local/bin/kitty
ln -sf ~/.local/kitty.app/bin/kitten ~/.local/bin/kitten
```

Ensure `~/.local/bin` is before system paths:

```bash
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc ;;
esac
```

Reload shell config:

```bash
source ~/.zshrc
hash -r
rehash 2>/dev/null || true
```

Verify:

```bash
type -a kitty
kitty --version
```

Expected first path:

```text
kitty is /home/<user>/.local/bin/kitty
```

The version should be newer than the Ubuntu apt package version.

---

# 11. Configure kitty for Wayland

Edit:

```bash
~/.config/kitty/kitty.conf
```

Recommended relevant settings:

```conf
linux_display_server wayland

background_opacity 0.8
background_blur 32

cursor_trail 3
```

If the installed kitty version is older than `0.37`, comment out `cursor_trail`:

```conf
# cursor_trail 3
```

With the upstream version, `cursor_trail` should be accepted.

To update automatically:

```bash
mkdir -p ~/.config/kitty

touch ~/.config/kitty/kitty.conf

grep -q '^linux_display_server ' ~/.config/kitty/kitty.conf \
  && sed -i 's/^linux_display_server .*/linux_display_server wayland/' ~/.config/kitty/kitty.conf \
  || echo 'linux_display_server wayland' >> ~/.config/kitty/kitty.conf
```

---

# 12. Test kitty

Run:

```bash
kitty
```

Or force Wayland explicitly:

```bash
kitty -o linux_display_server=wayland
```

If kitty opens and only prints Mesa warnings like:

```text
libEGL warning: failed to get driver name for fd -1
libEGL warning: MESA-LOADER: failed to retrieve device information
```

but the window opens, the setup is usable.

---

# 13. Verify Wayland compositor blur support

To check whether the WSLg compositor exposes any blur-related Wayland protocols:

```bash
wayland-info | grep -Ei 'blur|background|effect|kde|alpha|transluc|opacity'
```

Also try:

```bash
wayland-info | grep -Ei 'ext-background|background-effect|blur|kde_blur'
```

If both commands return nothing, `background_blur` is not supported by the current compositor.

In that case, kitty cannot force blur by itself.

Expected result under many WSLg setups:

```text
# no output
```

Meaning:

- Wayland works.
- Kitty works.
- D3D12 acceleration works.
- Background blur is not available because WSLg's compositor does not expose the required protocol.

---

# 14. Troubleshooting

## Problem: `Error: couldn't open display 10.x.x.x:0`

Cause: old Windows 10 / external X server style `DISPLAY`.

Fix:

```bash
unset LIBGL_ALWAYS_INDIRECT
export DISPLAY=:0
```

Remove old `DISPLAY` overrides from shell config files.

---

## Problem: `Wayland: Failed to connect to display`

Cause: `WAYLAND_DISPLAY=wayland-0`, but the socket is not present under `$XDG_RUNTIME_DIR`.

Fix:

```bash
rm -f "$XDG_RUNTIME_DIR/wayland-0" "$XDG_RUNTIME_DIR/wayland-0.lock"

ln -s /mnt/wslg/runtime-dir/wayland-0 "$XDG_RUNTIME_DIR/wayland-0"
ln -s /mnt/wslg/runtime-dir/wayland-0.lock "$XDG_RUNTIME_DIR/wayland-0.lock"

export WAYLAND_DISPLAY=wayland-0
```

---

## Problem: `No such interface "org.freedesktop.portal.Settings"`

Cause: `xdg-desktop-portal` is installed or running, but no backend exposes the Settings portal.

Fix:

```bash
sudo apt install -y dbus-user-session xdg-desktop-portal xdg-desktop-portal-gtk

mkdir -p ~/.config/xdg-desktop-portal

cat > ~/.config/xdg-desktop-portal/portals.conf <<'EOF'
[preferred]
default=gtk
org.freedesktop.impl.portal.Settings=gtk
EOF

systemctl --user daemon-reload
systemctl --user restart xdg-desktop-portal.service xdg-desktop-portal-gtk.service
```

Verify:

```bash
busctl --user introspect org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop | grep -F "org.freedesktop.portal.Settings" || true
```

---

## Problem: `MESA: error: ZINK: failed to choose pdev`

Cause: Mesa is trying to use the wrong backend.

Fix:

```bash
export GALLIUM_DRIVER=d3d12
```

Test:

```bash
GALLIUM_DRIVER=d3d12 glxinfo -B | grep -E 'Device|Accelerated|renderer'
```

Expected:

```text
Device: D3D12 (...)
Accelerated: yes
OpenGL renderer string: D3D12 (...)
```

---

## Problem: `/dev/dri/renderD128: Permission denied`

Cause: the user is not in the `render` group.

Fix:

```bash
sudo usermod -aG render "$USER"
```

Then from Windows PowerShell:

```powershell
wsl --shutdown
```

Reopen WSL and verify:

```bash
id
```

Expected output should include:

```text
render
```

---

## Problem: `Ignoring unknown config key: cursor_trail`

Cause: kitty is too old.

Fix:

Remove apt kitty:

```bash
sudo apt remove -y kitty kitty-doc
```

Install upstream kitty:

```bash
curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n

mkdir -p ~/.local/bin
ln -sf ~/.local/kitty.app/bin/kitty ~/.local/bin/kitty
ln -sf ~/.local/kitty.app/bin/kitten ~/.local/bin/kitten
```

Ensure path:

```bash
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc ;;
esac

source ~/.zshrc
hash -r
rehash 2>/dev/null || true
```

Verify:

```bash
kitty --version
```

---

# 15. Full automated setup script

This script applies the main fixes.

It does not run `wsl --shutdown` automatically because that must be done from Windows PowerShell.

Save as:

```bash
setup-kitty-wslg.sh
```

Then run:

```bash
bash setup-kitty-wslg.sh
```

Script:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing required packages"
sudo apt update
sudo apt install -y \
  dbus-user-session \
  xdg-desktop-portal \
  xdg-desktop-portal-gtk \
  mesa-utils \
  mesa-utils-extra \
  wayland-utils \
  curl

echo "==> Configuring xdg-desktop-portal"
mkdir -p "$HOME/.config/xdg-desktop-portal"

cat > "$HOME/.config/xdg-desktop-portal/portals.conf" <<'EOF'
[preferred]
default=gtk
org.freedesktop.impl.portal.Settings=gtk
EOF

systemctl --user daemon-reload || true
systemctl --user restart xdg-desktop-portal.service xdg-desktop-portal-gtk.service || true

echo "==> Adding user to render group"
if getent group render >/dev/null 2>&1; then
  sudo usermod -aG render "$USER"
else
  echo "WARNING: group 'render' does not exist."
fi

echo "==> Removing apt kitty if installed"
sudo apt remove -y kitty kitty-doc || true

echo "==> Installing upstream kitty"
curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n

echo "==> Creating kitty symlinks"
mkdir -p "$HOME/.local/bin"
ln -sf "$HOME/.local/kitty.app/bin/kitty" "$HOME/.local/bin/kitty"
ln -sf "$HOME/.local/kitty.app/bin/kitten" "$HOME/.local/bin/kitten"

echo "==> Ensuring ~/.local/bin is in PATH"
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zshrc" 2>/dev/null; then
  cat >> "$HOME/.zshrc" <<'EOF'

# Prefer user-installed binaries
export PATH="$HOME/.local/bin:$PATH"
EOF
fi

echo "==> Adding WSLg Wayland and D3D12 configuration to ~/.zshrc"
if ! grep -q 'WSLg Wayland socket for apps using XDG_RUNTIME_DIR' "$HOME/.zshrc" 2>/dev/null; then
  cat >> "$HOME/.zshrc" <<'EOF'

# WSLg Wayland socket for apps using XDG_RUNTIME_DIR=/run/user/$UID
if [ -d /mnt/wslg/runtime-dir ] && [ -n "$XDG_RUNTIME_DIR" ]; then
  if [ ! -S "$XDG_RUNTIME_DIR/wayland-0" ] && [ -S /mnt/wslg/runtime-dir/wayland-0 ]; then
    rm -f "$XDG_RUNTIME_DIR/wayland-0" "$XDG_RUNTIME_DIR/wayland-0.lock"
    ln -s /mnt/wslg/runtime-dir/wayland-0 "$XDG_RUNTIME_DIR/wayland-0"
    ln -s /mnt/wslg/runtime-dir/wayland-0.lock "$XDG_RUNTIME_DIR/wayland-0.lock"
  fi

  export WAYLAND_DISPLAY=wayland-0
fi

# Prefer WSLg accelerated OpenGL through D3D12
export GALLIUM_DRIVER=d3d12
EOF
fi

echo "==> Configuring kitty"
mkdir -p "$HOME/.config/kitty"
touch "$HOME/.config/kitty/kitty.conf"

if grep -q '^linux_display_server ' "$HOME/.config/kitty/kitty.conf"; then
  sed -i 's/^linux_display_server .*/linux_display_server wayland/' "$HOME/.config/kitty/kitty.conf"
else
  echo 'linux_display_server wayland' >> "$HOME/.config/kitty/kitty.conf"
fi

if ! grep -q '^cursor_trail ' "$HOME/.config/kitty/kitty.conf"; then
  echo 'cursor_trail 3' >> "$HOME/.config/kitty/kitty.conf"
fi

echo
echo "==> Setup complete."
echo
echo "IMPORTANT:"
echo "1. Close all WSL terminals."
echo "2. From Windows PowerShell, run:"
echo
echo "   wsl --shutdown"
echo
echo "3. Reopen WSL."
echo "4. Run:"
echo
echo "   source ~/.zshrc"
echo "   id"
echo "   glxinfo -B | grep -E 'Device|Accelerated|renderer'"
echo "   kitty --version"
echo "   kitty"
echo
echo "Expected:"
echo "- id includes the render group"
echo "- OpenGL renderer is D3D12"
echo "- kitty version is recent"
echo "- kitty opens using Wayland"
```

---

# 16. Final validation checklist

After restarting WSL:

```bash
id
```

Should include:

```text
render
```

Then:

```bash
echo "DISPLAY=$DISPLAY"
echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
ls -l "$XDG_RUNTIME_DIR"/wayland-0* 2>&1
```

Then:

```bash
glxinfo -B | grep -E 'Device|Accelerated|renderer'
```

Expected:

```text
Device: D3D12 (...)
Accelerated: yes
OpenGL renderer string: D3D12 (...)
```

Then:

```bash
type -a kitty
kitty --version
kitty
```

Expected:

```text
/home/<user>/.local/bin/kitty
```

and kitty opens successfully.

---

# 17. Known final state

A working setup may still print warnings such as:

```text
libEGL warning: failed to get driver name for fd -1
libEGL warning: MESA-LOADER: failed to retrieve device information
```

If kitty opens, these warnings can usually be ignored.

Expected working features:

- Wayland kitty window: yes
- D3D12 acceleration: yes
- `cursor_trail`: yes, with recent kitty
- `background_opacity`: maybe
- `background_blur`: likely no under WSLg

The lack of blur is normally a compositor limitation, not a kitty configuration problem.

