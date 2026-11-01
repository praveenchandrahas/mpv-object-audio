# Changelog

## [0.1.0] - 2026-11-01

First packaged pre-release. Experimental. The code on main at the time of tagging is packaged as it is.

- Debian package `mpv-object-audio` (Architecture: all): the `mpv-object-audio` wrapper and the installer script only, as `mpv-object-audio` and `mpv-object-audio-install` in /usr/bin. The package contains no player, no decoder and no third-party binary.
- `mpv-object-audio-install` runs the existing installer, which downloads other people's releases (Omniphony, harletty-bridge) and builds mpv-omniphony into ~/.local/opt/mpv-object-audio when YOU run it. `--dry-run` prints what it would do without downloading anything. The installer no longer copies the wrapper into ~/.local/bin when run from the package (a copy there would hide the packaged one).
- The package scripts never enable or start a service, never write into a home folder and never touch audio configuration.
