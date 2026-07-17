#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
make build
"build/GPTcodex_U.app/Contents/MacOS/codexU" --self-test-palettes
