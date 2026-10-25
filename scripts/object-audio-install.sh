#!/usr/bin/env bash
# object-audio-install.sh: installs the Omniphony player stack and the `mpv-object-audio` command, completely independent of the existing
# mpv-atmos (own mpv build, own engine, own bridges, own mpv config folder).
#
#   object-audio-install.sh              install or update (safe to re-run; each run takes the latest releases and the latest mpv-omniphony)
#   object-audio-install.sh status       what is installed, which versions, whether the engine and bridges load
#   object-audio-install.sh remove       delete the install, the command and the menu entries (keeps ~/.config/mpv-object-audio)
#   object-audio-install.sh deps         print the apt line for the one thing that is built from source (mpv)
#
# Where each piece comes from:
#   engine   liborender      PREBUILT: the latest release of mgth/Omniphony, asset liborender-<tag>-linux-x86_64.zip
#   bridges  3 .so files     PREBUILT: the latest release of harletty/harletty-bridge, asset harletty-bridge-<tag>-linux-x86_64.zip
#   player   mpv-omniphony   BUILT FROM SOURCE (it publishes no releases): main of mgth/mpv-omniphony, which pins the mpv fork tag
#                            (stable track, mpv 0.41.x plus the ad_orender patches); needs no engine at build time, loads it at runtime.
# The engine and the bridge must be a matching pair (bridge_api). The latest releases of the two are normally one: the script plays a test tone
# through the new mpv and refuses to install the command when the engine or the bridges do not load.
#
# Environment: OA_HOME (default ~/.local/opt/mpv-object-audio), OA_OMNIPHONY_TAG / OA_BRIDGE_TAG (pin a release instead of the latest),
# OA_JOBS (default: all cores). Needs curl, unzip, python3, git (plus the build dependencies for mpv). Nothing here touches mpv-atmos,
# ~/.config/mpv, ~/.local/share/omniphony or the CamillaDSP/router setup.
set -euo pipefail

OA_HOME="${OA_HOME:-$HOME/.local/opt/mpv-object-audio}"
OA_JOBS="${OA_JOBS:-$(nproc 2>/dev/null || echo 4)}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
APPS="$HOME/.local/share/applications"
SVC="$HOME/.local/share/kio/servicemenus"
CONF="$HOME/.config/mpv-object-audio"
SRC="$OA_HOME/src"
LOG="$OA_HOME/build.log"
URL_MPV=https://github.com/mgth/mpv-omniphony.git
REPO_OMNI=mgth/Omniphony
REPO_BRIDGE=harletty/harletty-bridge
MIME="video/x-matroska;video/mp4;video/webm;video/quicktime;video/x-msvideo;video/mpeg;video/mp2t;audio/x-matroska;audio/mpeg;audio/flac;audio/x-flac;audio/mp4;audio/ac3;audio/eac3;audio/vnd.dts;audio/vnd.dts.hd;audio/x-wav;audio/ogg;inode/directory;"

say() { printf '\n>> %s\n' "$*"; }
die() { printf '\n!! %s\n' "$*" >&2; exit 1; }

# Build dependencies of mpv (the only thing built here) plus the tools this script uses. libopus0 is the IAMF bridge's runtime need.
DEPS_APT="build-essential git curl unzip python3 pkg-config meson ninja-build libopus0 \
libavcodec-dev libavformat-dev libavfilter-dev libavdevice-dev libswscale-dev libswresample-dev libplacebo-dev libass-dev libluajit-5.1-dev \
libvulkan-dev libva-dev libdrm-dev libwayland-dev wayland-protocols libxkbcommon-dev libx11-dev libxext-dev libxrandr-dev libxpresent-dev \
libegl1-mesa-dev libgl1-mesa-dev libpipewire-0.3-dev libasound2-dev libuchardet-dev zlib1g-dev socat ffmpeg"

preflight() {
    local missing=()
    for t in git curl unzip python3 meson ninja pkg-config cc; do command -v "$t" >/dev/null 2>&1 || missing+=("$t"); done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "missing tools: ${missing[*]}"
        echo "install the dependencies first:   $0 deps    (prints the apt line)"
        exit 1
    fi
    mkdir -p "$(dirname "$OA_HOME")"
}

# latest_asset REPO TAG-OR-EMPTY NAME-REGEX -> prints "tag<TAB>download-url" of the matching asset of the latest (or the given) release.
latest_asset() {
    local repo="$1" tag="$2" rx="$3" api
    if [ -n "$tag" ]; then api="https://api.github.com/repos/$repo/releases/tags/$tag"; else api="https://api.github.com/repos/$repo/releases/latest"; fi
    curl -fsSL -H 'Accept: application/vnd.github+json' ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} "$api" | python3 -c '
import json, re, sys
try:
    r = json.load(sys.stdin)
except ValueError:
    sys.exit("GitHub returned something that is not JSON (blocked, rate-limited or offline)")
for a in r.get("assets", []):
    if re.fullmatch(sys.argv[1], a["name"]):
        print(r["tag_name"] + "\t" + a["browser_download_url"]); break
else:
    sys.exit("no asset matching " + sys.argv[1] + " in release " + r.get("tag_name", "?") + ": " + ", ".join(a["name"] for a in r.get("assets", [])))
' "$rx"
}

# fetch_zip REPO TAG REGEX DESTDIR -> downloads and unpacks the asset into DESTDIR (emptied first); prints the tag.
fetch_zip() {
    local repo="$1" tag="$2" rx="$3" dest="$4" line url t tmp
    line=$(latest_asset "$repo" "$tag" "$rx") || die "could not find a release asset of $repo (GitHub unreachable, rate-limited or renamed). Set GITHUB_TOKEN to lift the rate limit."
    t="${line%%$'\t'*}"; url="${line#*$'\t'}"
    tmp=$(mktemp -d); rm -rf "$dest"; mkdir -p "$dest"
    curl -fsSL -o "$tmp/a.zip" "$url" || die "download failed: $url"
    unzip -q -o "$tmp/a.zip" -d "$dest"; rm -rf "$tmp"
    echo "$t"
}

# clone or fast-forward DIR from URL at REF, detached, untracked files cleaned (the build folder is recreated by mpv-source.sh)
sync_repo() {
    local dir="$1" url="$2" ref="$3"
    [ -d "$dir/.git" ] || git init --quiet "$dir"
    git -C "$dir" remote get-url origin >/dev/null 2>&1 && git -C "$dir" remote set-url origin "$url" || git -C "$dir" remote add origin "$url"
    git -C "$dir" fetch --quiet --tags --force origin "$ref" || die "could not fetch $ref from $url"
    git -C "$dir" checkout --quiet --force --detach FETCH_HEAD
    git -C "$dir" clean -fdxq
    echo "   $(basename "$dir") $(git -C "$dir" rev-parse --short=10 HEAD) ($ref)"
}

bridge_list() { printf '%s:%s:%s' "$OA_HOME/lib/libharletty_dolby_bridge.so" "$OA_HOME/lib/libharletty_dts_bridge.so" "$OA_HOME/lib/libharletty_iamf_bridge.so"; }

# play one second of a tone through the installed mpv with the installed engine and bridges; prints the log lines that matter, returns 0 if loaded
smoke() {
    local out
    out=$("$OA_HOME/bin/mpv" --no-config --ao=null --vo=null --length=1 -v --ad=orender --ad-orender-library="$OA_HOME/lib/liborender.so.0" \
          --ad-orender-bridge-path="$(bridge_list)" av://lavfi:sine </dev/null 2>&1 || true)
    echo "$out" | grep -i -E "liborender|bridge" | head -12 | sed 's/^/   /'
    echo "$out" | grep -qi "loaded liborender" || { echo "$out" | tail -15; return 1; }
    echo "$out" | grep -i "bridge" | grep -qi -E "loaded|ok" || echo "   (no bridge line found in the log; the tone does not need one, so check with a Dolby or DTS film)"
}

do_install() {
    preflight
    mkdir -p "$SRC" "$OA_HOME/bin" "$OA_HOME/lib"
    : > "$LOG"
    say "build log: $LOG   (home: $OA_HOME)"

    say "1/5 engine (prebuilt release of $REPO_OMNI)"
    local d1 t1
    d1=$(mktemp -d)
    t1=$(fetch_zip "$REPO_OMNI" "${OA_OMNIPHONY_TAG:-}" 'liborender-.*-linux-x86_64\.zip' "$d1")
    [ -f "$d1/liborender.so" ] || die "the engine archive has no liborender.so at its root (layout changed?): $(ls "$d1")"
    install -m 755 "$d1/liborender.so" "$OA_HOME/lib/liborender.so.0"
    [ -f "$d1/orender.h" ] && install -m 644 "$d1/orender.h" "$OA_HOME/lib/orender.h"
    rm -rf "$d1"
    echo "   engine $t1"

    say "2/5 decoder bridges (prebuilt release of $REPO_BRIDGE)"
    local d2 t2
    d2=$(mktemp -d)
    t2=$(fetch_zip "$REPO_BRIDGE" "${OA_BRIDGE_TAG:-}" 'harletty-bridge-.*-linux-x86_64\.zip' "$d2")
    for f in dolby dts iamf; do
        [ -f "$d2/libharletty_${f}_bridge.so" ] || die "bridge archive lacks libharletty_${f}_bridge.so: $(ls "$d2")"
        install -m 755 "$d2/libharletty_${f}_bridge.so" "$OA_HOME/lib/"
    done
    rm -rf "$d2"
    echo "   bridge $t2   (the engine $t1 must accept its bridge_api: checked below; the bridge release notes say 'Requires Omniphony >= ...')"

    say "3/5 player: mpv + the pinned fork patches, built from source (meson; several minutes)"
    sync_repo "$SRC/mpv-omniphony" "$URL_MPV" main
    local tree
    tree=$( cd "$SRC/mpv-omniphony" && ./scripts/mpv-source.sh stable 2>>"$LOG" | tail -1 )
    [ -d "$tree" ] || { tail -20 "$LOG"; die "could not assemble the mpv tree"; }
    ( cd "$tree" && meson setup _b -Dorender=enabled && meson compile -C _b -j "$OA_JOBS" ) >>"$LOG" 2>&1 \
        || { tail -40 "$LOG"; die "mpv build failed (full log: $LOG). A 'dependency not found' line names the missing -dev package; see: $0 deps"; }
    install -m 755 "$tree/_b/mpv" "$OA_HOME/bin/mpv"

    say "4/5 verifying: the new mpv loads this engine and the bridges"
    smoke || die "mpv did not load the engine. Likely an ABI mismatch between this mpv fork and the engine release; try OA_OMNIPHONY_TAG=<an earlier tag> $0"

    say "5/5 installing the command and the menus"
    install_wrapper
    install_menus
    {
        echo "installed $(date -Is)"
        echo "engine (mgth/Omniphony release) $t1"
        echo "bridge (harletty-bridge release) $t2"
        echo "mpv-omniphony $(git -C "$SRC/mpv-omniphony" rev-parse HEAD)"
        "$OA_HOME/bin/mpv" --version | head -1
    } > "$OA_HOME/VERSIONS"
    sed 's/^/   /' "$OA_HOME/VERSIONS"
    cat <<EOF

Done. Try:
  mpv-object-audio film.mkv          (terminal)
  right-click a film in Dolphin  ->  "mpv-object-audio"
  mpv-object-audio --oa-info         (what it runs; plays a test tone through the engine)
mpv-atmos is untouched.
EOF
}

install_wrapper() {
    [ -f "$HERE/mpv-object-audio" ] || die "mpv-object-audio (the wrapper) must sit next to this script"
    mkdir -p "$BIN" "$CONF/scripts"
    install -m 755 "$HERE/mpv-object-audio" "$BIN/mpv-object-audio"
    [ -f "$CONF/mpv.conf" ] || printf '# mpv config for mpv-object-audio only. mpv-atmos and plain mpv read ~/.config/mpv instead.\n' > "$CONF/mpv.conf"
    # One-time snapshot of the current mpv setup (keys, the uosc on-screen UI, the overlay script) so the player feels the same. After this the two
    # folders are separate: editing one never changes the other. Nothing is overwritten on later runs.
    if [ ! -e "$CONF/.seeded" ]; then
        for f in input.conf script-opts scripts fonts; do
            if [ -e "$HOME/.config/mpv/$f" ]; then cp -an "$HOME/.config/mpv/$f" "$CONF/" 2>/dev/null || true; fi
        done
        [ -f "$CONF/scripts/mpv-atmos-overlay-off.lua" ] || { [ -f "$HERE/mpv-atmos-overlay-off.lua" ] && cp "$HERE/mpv-atmos-overlay-off.lua" "$CONF/scripts/" || true; }
        touch "$CONF/.seeded"
    fi
    return 0
}

install_menus() {
    mkdir -p "$APPS" "$SVC"
    # "Open with" entry (Dolphin, Kate, file dialogs), shown for the media types above. Not made the default handler.
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
    for f in "$BIN/mpv-object-audio" "$OA_HOME/bin/mpv" "$OA_HOME/lib/liborender.so.0" "$APPS/mpv-object-audio.desktop" "$SVC/mpv-object-audio.desktop"; do
        [ -e "$f" ] && echo "OK    $f" || echo "MISSING $f"
    done
    smoke || true
}

do_remove() {
    rm -rf "$OA_HOME"
    rm -f "$BIN/mpv-object-audio" "$APPS/mpv-object-audio.desktop" "$SVC/mpv-object-audio.desktop"
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" 2>/dev/null || true
    echo "Removed the install, the command and the menu entries. Kept $CONF (your mpv-object-audio config)."
}

case "${1:-install}" in
    install|update) do_install ;;
    status) do_status ;;
    remove) do_remove ;;
    deps) echo "sudo apt install $DEPS_APT" ;;
    *) sed -n 2,8p "$0"; exit 2 ;;
esac
