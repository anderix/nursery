# naked-gnome

A toolkit for keeping a Debian + GNOME install as slim as possible. Targets current Debian (13 / Trixie) but most scripts are defensive against older releases.

## Audit scripts (read-only)

| Script | What it shows |
|---|---|
| `review-installed.sh` | Manually-installed packages by size, largest first, with one-line synopses. Run as your normal user. |
| `review-autostart.sh` | `.desktop` entries in `/etc/xdg/autostart/` and `~/.config/autostart/` with effective status (ENABLED / HIDDEN / GNOME-OFF / NOT-IN-DE / EXCLUDED) per the XDG spec. |
| `review-services.sh` | Enabled systemd units (services + timers) for both system and `--user` scope, annotated with `Description=`. |
| `audit-firmware.sh` | Installed firmware/microcode packages cross-referenced against `lsmod`, `lspci -k`, and CPU vendor. Flags packages with no evidence of use. |
| `audit-disk-junk.sh` | Disk usage of common cache and state locations: user caches, trash, browser profiles, `/var/log`, journal, apt archives, temp dirs, snap, flatpak. |

## Action scripts (write)

| Script | What it does | Needs |
|---|---|---|
| `strip-gnome.sh` | Removes bloat packages: GNOME apps you don't use, Evolution, LibreOffice, printing, accessibility, scanner, etc. Reinstalls anything accidentally swept up by autoremove. | root |
| `slim-gsettings.sh` | Applies opinionated GNOME runtime tweaks: disable animations, recent-files history, automount, tracker, hot corner, etc. All reversible via `gsettings reset`. | normal user (gsettings is per-user) |
| `purge-residual.sh` | Lists and purges packages in dpkg state `rc` (config files left after removal). | root |

## Conventions

**Describe → confirm → execute.** Action scripts print a description of each section before doing anything, then ask before applying. Press Enter (or `y`) to apply, `n` to skip.

**`-y` / `--yes`.** All action scripts accept `-y` to apply every section without prompting. Useful for non-interactive runs.

**Defensive against missing packages and schemas.** `strip-gnome.sh` filters unknown package names via `apt-cache show` before reinstall. `slim-gsettings.sh` uses `gsettings writable` to check each key before writing. Both gracefully skip what isn't present.

**Read-only audit scripts make no changes.** They print findings with manual-cleanup hints; the user decides what to act on.

## Typical workflow

On a fresh Debian + GNOME install:

```
sudo ./strip-gnome.sh        # remove bloat packages
./slim-gsettings.sh          # tune runtime settings
sudo ./purge-residual.sh     # clean up rc-state configs
sudo reboot                  # let everything settle
```

Then periodically audit:

```
./review-installed.sh
./review-autostart.sh
./review-services.sh
./audit-firmware.sh
./audit-disk-junk.sh
```
