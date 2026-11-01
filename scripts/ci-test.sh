#!/usr/bin/env bash
# The repository's test suite (shell syntax of the scripts), the same command in CI and on your machine.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
bash tests/run.sh
