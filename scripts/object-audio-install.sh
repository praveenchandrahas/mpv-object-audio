#!/usr/bin/env bash
# object-audio-install.sh: builds the Omniphony player stack FROM SOURCE into its own folder and installs `mpv-object-audio`,
# a player command that is completely independent of the existing mpv-atmos (own mpv build, own engine, own bridges, own mpv config folder).
#
#   object-audio-install.sh              install or update (safe to re-run; each run fetches the latest of everything)
#   object-audio-install.sh status       what is installed, which commits, whether the bridges load
#   object-audio-install.sh remove       delete the build, the command and the menu entries (keeps ~/.config/mpv-object-audio)
#   object-audio-install.sh deps         print the apt line for the build dependencies
#
# What "latest" means (everything is cloned fresh and built here, nothing is downloaded as a binary):
#   mpv-omniphony   main of mgth/mpv-omniphony; it pins the mpv fork tag (stable track, mpv 0.41.x + the ad_orender patches)
#   Omniphony       main of mgth/Omniphony (engine: liborender + orender); override with OA_OMNIPHONY_REF=<tag|sha>
#   harletty-bridge main of harletty/harletty-bridge, built against the SAME Omniphony checkout as the engine, so bridge_api matches
# After the build the script loads the bridges the way the player would (orender check-bridges) and plays one second of a test tone through
# the new mpv; it refuses to install the command when either fails.
#
# Environment: OA_HOME (default ~/.local/opt/mpv-object-audio), OA_OMNIPHONY_REF (default main), OA_JOBS (default: all cores).
# Nothing here touches mpv-atmos, ~/.config/mpv, ~/.local/share/omniphony or the CamillaDSP/router setup.
set -euo pipefail

OA_HOME="${OA_HOME:-$HOME/.local/opt/mpv-object-audio}"
OA_OMNIPHONY_REF="${OA_OMNIPHONY_REF:-main}"
OA_JOBS="${OA_JOBS:-$(nproc 2>/dev/null || echo 4)}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
APPS="$HOME/.local/share/applications"
SVC="$HOME/.local/share/kio/servicemenus"
CONF="$HOME/.config/mpv-object-audio"
SRC="$OA_HOME/src"
LOG="$OA_HOME/build.log"
URL_MPV=https://github.com/mgth/mpv-omniphony.git
URL_OMNI=https://github.com/mgth/Omniphony.git
URL_BRIDGE=https://github.com/harletty/harletty-bridge.git
MIME="video/x-matroska;video/mp4;video/webm;video/quicktime;video/x-msvideo;video/mpeg;video/mp2t;audio/x-matroska;audio/mpeg;audio/flac;audio/x-flac;audio/mp4;audio/ac3;audio/eac3;audio/vnd.dts;audio/vnd.dts.hd;audio/x-wav;audio/ogg;inode/directory;"

say() { printf '\n>> %s\n' "$*"; }
die() { printf '\n!! %s\n' "$*" >&2; exit 1; }

DEPS_APT="build-essential git pkg-config meson ninja-build clang libclang-dev libpipewire-0.3-dev libopus-dev libasound2-dev \
libavcodec-dev libavformat-dev libavfilter-dev libavdevice-dev libswscale-dev libswresample-dev libplacebo-dev libass-dev libluajit-5.1-dev \
libvulkan-dev libva-dev libdrm-dev libwayland-dev wayland-protocols libxkbcommon-dev libx11-dev libxext-dev libxrandr-dev libxpresent-dev \
libegl1-mesa-dev libgl1-mesa-dev libsdl2-dev libuchardet-dev zlib1g-dev python3 socat ffmpeg"

rust_ok() {
    command -v cargo >/dev/null 2>&1 || return 1
    local v; v=$(cargo --version | awk '{print $2}')
    [ "$(printf '%s\n1.89.0\n' "$v" | sort -V | head -1)" = "1.89.0" ]
}

preflight() {
    local missing=()
    for t in git meson ninja pkg-config cc clang python3; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "missing tools: ${missing[*]}"
        echo "install the build dependencies first:   $0 deps    (prints the apt line)"
        exit 1
    fi
    rust_ok || die "Rust 1.89 or newer is needed (found: $(cargo --version 2>/dev/null || echo none)). Ubuntu 24.04's apt Rust is too old: install rustup (https://rustup.rs) and re-run."
    pkg-config --exists libpipewire-0.3 || die "libpipewire-0.3-dev is missing (see: $0 deps)"
    pkg-config --exists opus || die "libopus-dev is missing: the IAMF bridge links it (see: $0 deps)"
    [ -w "$(dirname "$OA_HOME")" ] || mkdir -p "$(dirname "$OA_HOME")"
}

# clone or fast-forward DIR from URL at REF (a branch, tag or sha). Fetches the ref, checks it out detached, cleans untracked files.
sync_repo() {
    local dir="$1" url="$2" ref="$3"
    if [ ! -d "$dir/.git" ]; then git init --quiet "$dir"; fi
    git -C "$dir" remote get-url origin >/dev/null 2>&1 && git -C "$dir" remote set-url origin "$url" || git -C "$dir" remote add origin "$url"
    git -C "$dir" fetch --quiet --tags --force origin "$ref" 2>/dev/null || git -C "$dir" fetch --quiet --tags --force origin \
        || die "could not fetch $ref from $url"
    git -C "$dir" checkout --quiet --force --detach FETCH_HEAD 2>/dev/null || git -C "$dir" checkout --quiet --force --detach "$ref"
    git -C "$dir" clean -fdxq -e target -e build
    echo "   $(basename "$dir") $(git -C "$dir" rev-parse --short=10 HEAD) ($ref)"
}

do_install() {
    preflight
    mkdir -p "$SRC" "$OA_HOME/bin" "$OA_HOME/lib"
    : > "$LOG"
    say "build log: $LOG   (home: $OA_HOME)"

    say "1/6 fetching sources"
    # The bridge builds against ../Omniphony, so the two sit side by side with exactly these names.
    sync_repo "$SRC/Omniphony" "$URL_OMNI" "$OA_OMNIPHONY_REF"
    sync_repo "$SRC/harletty-bridge" "$URL_BRIDGE" main
    sync_repo "$SRC/mpv-omniphony" "$URL_MPV" main
    echo "   the bridge's own Omniphony pin (the commit its CI builds against): $("$SRC/harletty-bridge/scripts/omniphony-ref.sh" 2>/dev/null || echo unknown)"

    say "2/6 engine: liborender + orender (cargo, several minutes the first time)"
    # Same flags as upstream's PKGBUILD. RUSTFLAGS must not carry -flto: the vendored Lua is C and the Rust linker cannot read LTO bitcode.
    ( cd "$SRC/Omniphony/omniphony-renderer" && env -u RUSTFLAGS CARGO_BUILD_JOBS="$OA_JOBS" \
        cargo build --release -p omniphony-renderer -p orender_ffi ) >>"$LOG" 2>&1 \
        || { tail -30 "$LOG"; die "engine build failed (full log: $LOG)"; }
    local T="$SRC/Omniphony/omniphony-renderer/target/release"
    [ -f "$T/liborender.so" ] && [ -f "$T/orender" ] || die "engine artifacts not found in $T"
    install -m 755 "$T/liborender.so" "$OA_HOME/lib/liborender.so.0"
    install -m 755 "$T/orender" "$OA_HOME/bin/orender"

    say "3/6 decoder bridges: dolby, dts, iamf (cargo)"
    ( cd "$SRC/harletty-bridge" && env -u RUSTFLAGS CARGO_BUILD_JOBS="$OA_JOBS" ./build_bridge.sh ) >>"$LOG" 2>&1 \
        || { tail -30 "$LOG"; die "bridge build failed (full log: $LOG). If it complains about bridge_api, build Omniphony at the bridge's pin: OA_OMNIPHONY_REF=<pin above> $0"; }
    for f in dolby dts iamf; do
        install -m 755 "$SRC/harletty-bridge/target/release/libharletty_${f}_bridge.so" "$OA_HOME/lib/"
    done

    say "4/6 player: mpv + the pinned fork patches (meson)"
    local tree
    tree=$( cd "$SRC/mpv-omniphony" && ./scripts/mpv-source.sh stable 2>>"$LOG" | tail -1 )
    [ -d "$tree" ] || { tail -20 "$LOG"; die "could not assemble the mpv tree"; }
    ( cd "$tree" && if [ -d _b ]; then meson setup _b --reconfigure -Dorender=enabled; else meson setup _b -Dorender=enabled; fi \
        && meson compile -C _b -j "$OA_JOBS" ) >>"$LOG" 2>&1 \
        || { tail -40 "$LOG"; die "mpv build failed (full log: $LOG). A 'dependency not found' line names the missing -dev package; see: $0 deps"; }
    install -m 755 "$tree/_b/mpv" "$OA_HOME/bin/mpv"

    say "5/6 verifying: bridges load, and the new mpv loads this engine"
    ORENDER_BRIDGE_FILE="$(bridge_list)" "$OA_HOME/bin/orender" check-bridges 2>&1 | tee -a "$LOG" | sed 's/^/   /'
    local n; n=$(ORENDER_BRIDGE_FILE="$(bridge_list)" "$OA_HOME/bin/orender" check-bridges 2>&1 | grep -c '^loaded:' || true)
    [ "$n" -ge 2 ] || die "fewer than two bridges loaded: the engine and bridge do not match. Try OA_OMNIPHONY_REF=<the bridge's pin printed in step 1>."
    local out
    out=$("$OA_HOME/bin/mpv" --no-config --ao=null --vo=null --length=1 --ad=orender --ad-orender-library="$OA_HOME/lib/liborender.so.0" \
          --ad-orender-bridge-path="$(bridge_list)" av://lavfi:sine </dev/null 2>&1 || true)
    echo "$out" | grep -i "liborender" | head -3 | sed 's/^/   /'
    echo "$out" | grep -qi "loaded liborender" || { echo "$out" | tail -15; die "mpv did not load the engine (ABI mismatch between the mpv fork and liborender?)."; }

    say "6/6 installing the command and the menus"
    install_wrapper
    install_menus
    {
        echo "installed $(date -Is)"
        for d in Omniphony harletty-bridge mpv-omniphony; do echo "$d $(git -C "$SRC/$d" rev-parse HEAD)"; done
        "$OA_HOME/bin/mpv" --version | head -1
    } > "$OA_HOME/VERSIONS"
    cat "$OA_HOME/VERSIONS" | sed 's/^/   /'
    cat <<EOF

Done. Try:
  mpv-object-audio film.mkv          (terminal)
  right-click a film in Dolphin  ->  "Play with mpv-object-audio"
  mpv-object-audio --oa-info         (what it runs, which bridges loaded)
mpv-atmos is untouched. If you only want the old behaviour back, keep using mpv-atmos.
EOF
}

bridge_list() { printf '%s:%s:%s' "$OA_HOME/lib/libharletty_dolby_bridge.so" "$OA_HOME/lib/libharletty_dts_bridge.so" "$OA_HOME/lib/libharletty_iamf_bridge.so"; }

install_wrapper() {
    [ -f "$HERE/mpv-object-audio" ] || die "mpv-object-audio (the wrapper) must sit next to this script"
    mkdir -p "$BIN" "$CONF/scripts"
    install -m 755 "$HERE/mpv-object-audio" "$BIN/mpv-object-audio"
    [ -f "$CONF/mpv.conf" ] || printf '# mpv config for mpv-object-audio only. mpv-atmos and plain mpv read ~/.config/mpv instead.\n' > "$CONF/mpv.conf"
    # One-time snapshot of the current mpv setup (keys, the uosc on-screen UI, the overlay script) so the player feels the same. After this the two
    # folders are separate: editing one never changes the other. Nothing is overwritten on later runs.
    if [ ! -e "$CONF/.seeded" ]; then
        for f in input.conf script-opts scripts fonts; do
            [ -e "$HOME/.config/mpv/$f" ] && [ ! -e "$CONF/$f" -o "$f" = scripts ] && cp -an "$HOME/.config/mpv/$f" "$CONF/" 2>/dev/null || true
        done
        [ -f "$CONF/scripts/mpv-atmos-overlay-off.lua" ] || { [ -f "$HERE/mpv-atmos-overlay-off.lua" ] && cp "$HERE/mpv-atmos-overlay-off.lua" "$CONF/scripts/"; }
        touch "$CONF/.seeded"
    fi
    return 0
}

install_menus() {
    mkdir -p "$APPS" "$SVC"
    # "Open with" entry (Dolphin, Kate, file dialogs, `gtk-launch`), shown for the media types above. Not made the default handler.
    cat > "$APPS/mpv-object-audio.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=mpv-object-audio
GenericName=Object-audio media player
Comment=mpv with live Atmos/object rendering through Omniphony
Exec=$BIN/mpv-object-audio --force-window=yes -- %U
Icon=mpv
Terminal=false
Categories=AudioVideo;Player;
MimeType=$MIME
Actions=Log;

[Desktop Action Log]
Name=Play with log in a terminal
Exec=konsole --hold -e $BIN/mpv-object-audio --force-window=yes -v -- %U
EOF
    # Dolphin right-click entries. Works on Plasma 5.27 and 6; Plasma 6 only honours service menus that are executable.
    cat > "$SVC/mpv-object-audio.desktop" <<EOF
[Desktop Entry]
Type=Service
X-KDE-ServiceTypes=KonqPopupMenu/Plugin
MimeType=$MIME
Actions=oaPlay;oaFs;oaLog;oaInfo;
X-KDE-Priority=TopLevel
X-KDE-Submenu=mpv-object-audio
Icon=mpv

[Desktop Action oaPlay]
Name=Play with mpv-object-audio
Icon=media-playback-start
Exec=$BIN/mpv-object-audio --force-window=yes -- %U

[Desktop Action oaFs]
Name=Play fullscreen
Icon=view-fullscreen
Exec=$BIN/mpv-object-audio --force-window=yes --fs -- %U

[Desktop Action oaLog]
Name=Play with log in Konsole
Icon=utilities-terminal
Exec=konsole --hold -e $BIN/mpv-object-audio --force-window=yes -v -- %U

[Desktop Action oaInfo]
Name=Show audio streams (ffprobe) in Konsole
Icon=dialog-information
Exec=konsole --hold -e sh -c 'ffprobe -hide_banner "\$1" 2>&1 | grep -E "Input|Stream|Duration"' sh %f
EOF
    chmod +x "$SVC/mpv-object-audio.desktop" "$APPS/mpv-object-audio.desktop"
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" 2>/dev/null || true
    for k in kbuildsycoca6 kbuildsycoca5; do command -v "$k" >/dev/null 2>&1 && { "$k" >/dev/null 2>&1 || true; break; }; done
    echo "   command: $BIN/mpv-object-audio   (make sure $BIN is on PATH)"
    echo "   menus:   $APPS/mpv-object-audio.desktop, $SVC/mpv-object-audio.desktop"
    echo "   Dolphin picks the menu up on its next window; if not, log out and in once."
}

do_status() {
    [ -d "$OA_HOME" ] || { echo "not installed ($OA_HOME missing)"; exit 1; }
    cat "$OA_HOME/VERSIONS" 2>/dev/null || echo "no VERSIONS file: the last install did not finish"
    for f in "$BIN/mpv-object-audio" "$OA_HOME/bin/mpv" "$OA_HOME/bin/orender" "$OA_HOME/lib/liborender.so.0" "$APPS/mpv-object-audio.desktop" "$SVC/mpv-object-audio.desktop"; do
        [ -e "$f" ] && echo "OK    $f" || echo "MISSING $f"
    done
    ORENDER_BRIDGE_FILE="$(bridge_list)" "$OA_HOME/bin/orender" check-bridges 2>&1 | head -8
}

do_remove() {
    rm -rf "$OA_HOME"
    rm -f "$BIN/mpv-object-audio" "$APPS/mpv-object-audio.desktop" "$SVC/mpv-object-audio.desktop"
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" 2>/dev/null || true
    echo "Removed the build, the command and the menu entries. Kept $CONF (your mpv-object-audio config)."
}

case "${1:-install}" in
    install|update) do_install ;;
    status) do_status ;;
    remove) do_remove ;;
    deps) echo "sudo apt install $DEPS_APT"; echo "and Rust >= 1.89 via rustup (https://rustup.rs); Ubuntu 24.04's apt cargo is too old." ;;
    *) sed -n 2,12p "$0"; exit 2 ;;
esac
