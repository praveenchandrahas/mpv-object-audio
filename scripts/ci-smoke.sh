#!/usr/bin/env bash
# Smoke test of the INSTALLED mpv-object-audio package: the wrapper and installer only. It downloads and builds nothing (those are other
# people's programs), and checks that the packaged command does not copy itself into ~/.local/bin.
#   scripts/ci-smoke.sh
set -euo pipefail
H=$(mktemp -d); trap 'rm -rf "$H"' EXIT
export HOME=$H XDG_CONFIG_HOME=$H/.config SDHT_ALLOW_ROOT=1
fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }
for c in mpv-object-audio mpv-object-audio-install; do command -v "$c" >/dev/null || fail "$c is not on PATH"; done
[ "$(command -v mpv-object-audio)" = /usr/bin/mpv-object-audio ] || fail "wrapper resolves to $(command -v mpv-object-audio)"
bash -n /usr/bin/mpv-object-audio /usr/bin/mpv-object-audio-install /usr/lib/mpv-object-audio/object-audio-install.sh

echo "== the wrapper says plainly that the player is not installed"
set +e; out=$(mpv-object-audio --oa-info 2>&1); rc=$?; set -e
[ $rc -ne 0 ] && echo "$out" | grep -q "not installed" || fail "wrapper without an install: rc=$rc out=$out"
echo "$out" | head -2

echo "== installer: dry run, deps, status (no network is used)"
mpv-object-audio-install --dry-run | tee "$H/dry.txt" | head -12
grep -q "nothing is downloaded" "$H/dry.txt" || fail "dry-run text"
mpv-object-audio-install deps | head -3
set +e; mpv-object-audio-install status >"$H/status.txt" 2>&1; rc=$?; set -e
[ $rc -ne 0 ] && grep -q "not installed" "$H/status.txt" || fail "status without an install: rc=$rc"
[ -z "$(find "$H" -mindepth 1 -not -name 'dry.txt' -not -name 'status.txt' 2>/dev/null)" ] || { find "$H"; fail "something was written into the home folder"; }

echo "== the installer in packaged mode would not copy the wrapper into ~/.local/bin"
grep -q 'OA_SYSTEM_WRAPPER' /usr/lib/mpv-object-audio/object-audio-install.sh || fail "installer lacks the packaged-mode switch"
grep -q 'OA_SYSTEM_WRAPPER=/usr/bin/mpv-object-audio' /usr/bin/mpv-object-audio-install || fail "launcher does not set the switch"
echo "SMOKE OK (mpv-object-audio)"
