#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
bash -n ../scripts/object-audio-install.sh ../scripts/mpv-object-audio ../scripts/mpv-atmos && echo "PASS shell syntax"
bash -n ../scripts/install-theater-status.sh && echo "PASS shell syntax (install-theater-status.sh)"
if python3 -c "import lupa" 2>/dev/null; then python3 test_theater_status.py; else echo "SKIP theater_status.lua tests (pip install lupa)"; fi
