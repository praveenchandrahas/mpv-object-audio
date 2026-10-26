#!/usr/bin/env bash
# Installs the on-screen status panel and control menu (theater_status.lua) into the mpv config folders.
#   ./install-theater-status.sh            copy the script into ~/.config/mpv and ~/.config/mpv-object-audio (whichever exist)
#   ./install-theater-status.sh --bindings also add the two keys (F9 panel, F10 menu) to each input.conf, once
#   ./install-theater-status.sh remove     take the script out again (and the two input.conf lines, if it added them)
# It never edits input.conf unless you pass --bindings. The status page for the browser is separate: linux-theater-dsp/scripts/install-ctld.sh.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/theater_status.lua"
MARK="# theater_status (added by install-theater-status.sh)"
LINES=$'F9 script-binding theater_status/toggle\nF10 script-binding theater_status/menu'
[ -f "$SRC" ] || { echo "theater_status.lua must be next to this script."; exit 1; }
found=0
for CONF in "$HOME/.config/mpv" "$HOME/.config/mpv-object-audio"; do
  [ -d "$CONF" ] || continue
  found=1
  if [ "${1:-}" = remove ]; then
    rm -f "$CONF/scripts/theater_status.lua"
    if [ -f "$CONF/input.conf" ] && grep -qF "$MARK" "$CONF/input.conf"; then
      python3 - "$CONF/input.conf" "$MARK" <<'PY'
import sys
p, mark = sys.argv[1], sys.argv[2]
lines = open(p).read().split("\n"); out = []; skip = 0
for l in lines:
    if skip:
        skip -= 1; continue
    if l.strip() == mark: skip = 2; continue
    out.append(l)
open(p, "w").write("\n".join(out))
PY
    fi
    echo "removed from $CONF"
    continue
  fi
  mkdir -p "$CONF/scripts"
  install -m 644 "$SRC" "$CONF/scripts/theater_status.lua"
  echo "installed: $CONF/scripts/theater_status.lua"
  if [ "${1:-}" = --bindings ]; then
    if grep -qF "$MARK" "$CONF/input.conf" 2>/dev/null; then echo "  keys already in $CONF/input.conf"
    else
      for k in F9 F10; do grep -qE "^[[:space:]]*$k[[:space:]]" "$CONF/input.conf" 2>/dev/null && echo "  NOTE: $k is already bound in $CONF/input.conf; the new binding comes later in the file and wins. Edit it there if you prefer other keys."; done
      printf '\n%s\n%s\n' "$MARK" "$LINES" >> "$CONF/input.conf"
      echo "  keys added to $CONF/input.conf"
    fi
  fi
done
[ "$found" = 1 ] || { echo "No mpv config folder found (~/.config/mpv or ~/.config/mpv-object-audio)."; exit 1; }
if [ "${1:-}" != remove ] && [ "${1:-}" != --bindings ]; then
  echo
  echo "Add these two lines to input.conf in the same folder(s), or re-run with --bindings to do it for you:"
  echo "$LINES" | sed 's/^/  /'
fi
