#!/usr/bin/env bash
# Quick installer: Pantheon desktop + Btrfs snapshots (Snapper + GRUB rollback)
# Run this AFTER archinstall has finished and you've booted into the base system.
# Assumes: Btrfs filesystem, GRUB bootloader (both chosen in archinstall).
#
# Usage:
#   chmod +x setup.sh
#   ./setup.sh

set -euo pipefail

echo "==> Updating system"
sudo pacman -Syu --noconfirm

echo "==> Ignoring the conflicting greeter permanently"
# Keep future 'pacman -Syu' from pulling lightdm-pantheon-greeter (and its
# mutter46 conflict) back in. --ignore below only covers this one install.
if ! grep -q '^IgnorePkg.*lightdm-pantheon-greeter' /etc/pacman.conf; then
  if grep -q '^IgnorePkg' /etc/pacman.conf; then
    sudo sed -i 's/^IgnorePkg\s*=\s*/&lightdm-pantheon-greeter /' /etc/pacman.conf
  else
    sudo sed -i '/^\[options\]/a IgnorePkg = lightdm-pantheon-greeter' /etc/pacman.conf
  fi
fi

echo "==> Installing Pantheon desktop (full group, minus conflicting greeter)"
# lightdm-pantheon-greeter depends on mutter46, which conflicts with the mutter
# gala needs. We use lightdm-gtk-greeter instead -- same login manager.
# pacman's --ignore on a group member still installs it under --noconfirm (it
# auto-answers "Install anyway? [Y/n]" with Y), dragging in mutter46 -> conflict.
# So enumerate the group and drop the greeter explicitly.
#
# Also drop the wingpanel indicators that are version-skewed against wingpanel
# 8.0.4: their schemas were renamed (io.elementary.panel.* ->
# io.elementary.desktop.wingpanel.*) or aren't shipped, so loading them aborts
# the whole panel. Re-add once Arch rebuilds them. See tracking issue.
drop='^(lightdm-pantheon-greeter|wingpanel-indicator-(bluetooth|power|keyboard|network|nightlight))$'
mapfile -t pantheon_pkgs < <(pacman -Sgq pantheon | grep -vE "$drop")
sudo pacman -S --needed --noconfirm "${pantheon_pkgs[@]}" \
  lightdm-gtk-greeter network-manager-applet polkit-gnome openssh \
  sound-theme-elementary elementary-icon-theme elementary-wallpapers \
  pantheon-default-settings networkmanager

echo "==> Installing optional Pantheon apps"
sudo pacman -S --needed --noconfirm \
  pantheon-files pantheon-terminal pantheon-screenshot \
  gnome-keyring gvfs file-roller xdg-user-dirs xdg-utils
xdg-user-dirs-update

echo "==> Wiring up the Pantheon session"
# The Arch pantheon-wayland session only autostarts gala, so you land on a bare
# wallpaper with no panel or dock. The wiki's fix is XDG autostart entries.
sudo tee /etc/xdg/autostart/io.elementary.wingpanel.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Wingpanel
Exec=io.elementary.wingpanel
OnlyShowIn=Pantheon;
X-GNOME-Autostart-Phase=Panel
EOF
sudo tee /etc/xdg/autostart/plank.desktop >/dev/null <<'EOF'
[Desktop Entry]
Type=Application
Name=Plank
# plank is X11-only and refuses to start when logind reports a Wayland session.
# Force it through Xwayland: spoof the session type and pin the GDK backend.
Exec=env -u WAYLAND_DISPLAY GDK_BACKEND=x11 XDG_SESSION_TYPE=x11 plank
OnlyShowIn=Pantheon;
EOF
# Default the greeter to Pantheon (Wayland) instead of the GNOME fallback.
sudo mkdir -p /etc/lightdm/lightdm.conf.d
sudo tee /etc/lightdm/lightdm.conf.d/50-pantheon-default.conf >/dev/null <<'EOF'
[Seat:*]
user-session=pantheon-wayland
EOF
# No X11 "Classic Session": gala 8 (mutter 50) is Wayland-only -- it always
# runs as a Wayland display server and grabs KMS, so on top of Xorg it dies
# with "No GPUs found" (EBUSY). Only the Wayland Secure Session works.

echo "==> Enabling services"
sudo systemctl enable lightdm
sudo systemctl enable NetworkManager
sudo systemctl enable sshd
sudo systemctl enable --now polkit

echo "==> Installing AUR helper (yay) if missing"
if ! command -v yay &>/dev/null; then
  sudo pacman -S --needed --noconfirm git base-devel
  tmpdir=$(mktemp -d)
  git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
  (cd "$tmpdir/yay" && makepkg -si --noconfirm)
  rm -rf "$tmpdir"
fi

echo "==> Installing tweaks panel from AUR (best-effort)"
# switchboard-plug-pantheon-tweaks-git is currently stale: it wants
# libswitchboard-2.0.so, but switchboard 8.x ships libswitchboard-3.so. Skip it
# rather than abort the whole run; retry once the AUR package catches up.
yay -S --needed --noconfirm switchboard-plug-pantheon-tweaks-git \
  || echo "   skipped: tweaks plug incompatible with current switchboard"

echo "==> Installing Btrfs snapshot tools"
sudo pacman -S --needed --noconfirm snapper grub-btrfs inotify-tools
yay -S --needed --noconfirm snap-pac

echo "==> Configuring Snapper for root subvolume"
# Skip if already configured -- create-config errors when the root config exists.
if ! sudo snapper list-configs 2>/dev/null | grep -qw root; then
  if [ -d /.snapshots ]; then
    sudo umount /.snapshots 2>/dev/null || true
    sudo rm -rf /.snapshots
  fi
  sudo snapper -c root create-config /
  sudo btrfs subvolume delete /.snapshots 2>/dev/null || true
  sudo mkdir -p /.snapshots
  sudo mount -a
  sudo chmod 750 /.snapshots
fi

echo "==> Enabling automatic snapshot timers"
sudo systemctl enable --now snapper-timeline.timer
sudo systemctl enable --now snapper-cleanup.timer

echo "==> Hooking GRUB into Btrfs snapshots"
sudo systemctl enable --now grub-btrfsd.service
sudo grub-mkconfig -o /boot/grub/grub.cfg

echo "==> Installing GUI snapshot manager (optional)"
yay -S --needed --noconfirm btrfs-assistant

echo ""
echo "Done. Reboot to log into Pantheon:"
echo "  sudo reboot"
echo ""
echo "After reboot, verify snapshots with:"
echo "  sudo snapper -c root list"
