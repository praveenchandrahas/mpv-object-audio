#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
bash -n ../scripts/object-audio-install.sh ../scripts/mpv-object-audio ../scripts/mpv-atmos && echo "PASS shell syntax"
