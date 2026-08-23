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
# lightdm-pantheon-greeter is ignored: it depends on mutter46, which conflicts
# with the regular mutter that gala itself needs. Known upstream packaging
# lag (wingpanel/gala get temporarily pinned to older mutter each cycle).
# We use lightdm-gtk-greeter instead -- same login manager, different greeter UI.
sudo pacman -S --needed --noconfirm --ignore lightdm-pantheon-greeter \
  pantheon lightdm-gtk-greeter network-manager-applet polkit-gnome openssh \
  sound-theme-elementary elementary-icon-theme elementary-wallpapers \
  pantheon-default-settings networkmanager

echo "==> Installing optional Pantheon apps"
sudo pacman -S --needed --noconfirm \
  pantheon-files pantheon-terminal pantheon-screenshot \
  gnome-keyring gvfs file-roller xdg-user-dirs xdg-utils
xdg-user-dirs-update

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

echo "==> Installing tweaks panel from AUR"
yay -S --needed --noconfirm switchboard-plug-pantheon-tweaks-git

echo "==> Installing Btrfs snapshot tools"
sudo pacman -S --needed --noconfirm snapper grub-btrfs inotify-tools
yay -S --needed --noconfirm snap-pac

echo "==> Configuring Snapper for root subvolume"
if [ -d /.snapshots ]; then
  sudo umount /.snapshots || true
  sudo rm -rf /.snapshots
fi
sudo snapper -c root create-config /
sudo btrfs subvolume delete /.snapshots || true
sudo mkdir -p /.snapshots
sudo mount -a
sudo chmod 750 /.snapshots

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
