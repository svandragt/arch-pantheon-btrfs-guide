# Arch Linux + Pantheon + Btrfs Snapshots

Command reference for installing Arch Linux with the Pantheon desktop
(elementary OS's DE) and openSUSE-style Btrfs snapshots via Snapper +
GRUB rollback.

## Part 1: Base System

```
iwctl
station wlan0 connect YOUR_SSID
exit
```

```
archinstall
```

In the menu: Btrfs filesystem, GRUB bootloader, no desktop environment.

## Part 2: Pantheon

```
sudo pacman -Syu
```

> **Known issue:** `lightdm-pantheon-greeter` currently depends on `mutter46`,
> which conflicts with the regular `mutter` that `gala` itself needs. This is
> an upstream packaging lag (Arch has a history of pinning gala/wingpanel to
> older mutter versions each release cycle while catching up). Until it's
> fixed, ignore that one package and use `lightdm-gtk-greeter` instead —
> same login manager, just a plainer greeter screen.

```
sudo pacman -S --needed --ignore lightdm-pantheon-greeter \
  pantheon lightdm-gtk-greeter network-manager-applet polkit-gnome openssh \
  sound-theme-elementary elementary-icon-theme elementary-wallpapers \
  pantheon-default-settings networkmanager
```

```
sudo systemctl enable lightdm
sudo systemctl enable NetworkManager
sudo systemctl enable sshd
sudo systemctl enable --now polkit
sudo reboot
```

`network-manager-applet` gives you a tray icon to manage networks,
`polkit-gnome` handles privilege-escalation prompts inside the desktop, and
`openssh` gives you an SSH fallback into the VM if the graphical session
ever breaks (handy since TTY-switching can be unreliable in QEMU/KVM —
find the VM's IP with `virsh domifaddr <vm-name>` from the host, then
`ssh youruser@<vm-ip>`).

Optional apps:

```
sudo pacman -S pantheon-files pantheon-terminal pantheon-screenshot \
  gnome-keyring gvfs file-roller xdg-user-dirs xdg-utils
xdg-user-dirs-update
```

Optional AUR helper + tweaks panel:

```
sudo pacman -S --needed git base-devel
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
```

```
yay -S switchboard-plug-pantheon-tweaks-git
```

Note: Pantheon on Wayland is less mature than X11. If Plank or
Wingpanel glitch, log out and pick the X11/"Classic" session.

## Part 3: Btrfs Snapshots (Snapper)

```
sudo pacman -S --needed snapper grub-btrfs inotify-tools
```

```
yay -S snap-pac
```

```
sudo umount /.snapshots
sudo rm -rf /.snapshots
sudo snapper -c root create-config /
sudo btrfs subvolume delete /.snapshots
sudo mkdir /.snapshots
sudo mount -a
sudo chmod 750 /.snapshots
```

```
sudo systemctl enable --now snapper-timeline.timer
sudo systemctl enable --now snapper-cleanup.timer
```

```
sudo systemctl enable --now grub-btrfsd.service
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

Test:

```
sudo pacman -S cowsay
sudo snapper -c root list
```

Rollback:

```
sudo snapper rollback <snapshot-number>
```

Optional GUI:

```
yay -S btrfs-assistant
```

## Quick Reference

| Task | Command |
|---|---|
| List snapshots | `sudo snapper -c root list` |
| Create manual snapshot | `sudo snapper -c root create -d "description"` |
| Roll back to a snapshot | `sudo snapper rollback <number>` |
| Delete a snapshot | `sudo snapper -c root delete <number>` |
| Rebuild GRUB snapshot menu | `sudo grub-mkconfig -o /boot/grub/grub.cfg` |
