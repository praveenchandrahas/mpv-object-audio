# shellcheck shell=bash disable=SC2034  # sourced by build-deb.sh, which uses these variables
# Package definition for kit/build-deb.sh (sourced; see Software-Defined-Home-Theatre/packaging/kit).
PKG=mpv-object-audio
HOMEPAGE=https://github.com/praveenchandrahas/mpv-object-audio
SUMMARY="wrapper and installer for an object-audio mpv player stack"
DESCRIPTION="The mpv-object-audio command and its installer script. The command starts a
separate mpv build with the Omniphony object renderer and the harletty-bridge
decoders, installed in its own folder, with video settings tuned for a 1080p
projector; it calls eq from linux-theater-dsp before playback when that is
installed.
.
This package contains ONLY the wrapper and the installer. The player, the
renderer and the decoders are other people's software: they are not in this
package and are not redistributed by it. Running mpv-object-audio-install as
your user downloads their releases and builds mpv from source into your home
folder. The package itself does not enable or start any service and does not
write into any home folder."
DEPENDS=""
RECOMMENDS="curl, unzip, git, socat, ffmpeg"
SUGGESTS="linux-theater-dsp, roomtone, seekthumbs, mpv-shelf"
PYDIRS=

stage() {
  local L=/usr/lib/mpv-object-audio
  inst 755 scripts/mpv-object-audio /usr/bin/mpv-object-audio
  inst 755 scripts/object-audio-install.sh "$L/object-audio-install.sh"
  inst 644 scripts/mpv-atmos-overlay-off.lua "$L/mpv-atmos-overlay-off.lua"
  inst 755 packaging/mpv-object-audio-install /usr/bin/mpv-object-audio-install
  inst 755 scripts/mpv-atmos /usr/share/doc/mpv-object-audio/examples/mpv-atmos
  inst 644 docs/omniphony-debugging.md /usr/share/doc/mpv-object-audio/omniphony-debugging.md
  manpage mpv-object-audio "play films with the object-audio mpv stack (--oa-info, --oa-check)"
  manpage mpv-object-audio-install "install, update, check or remove the object-audio player stack in the home folder of one user" "Subcommands: install, status, remove, deps. Option: --dry-run (prints the plan, downloads nothing)."
}
