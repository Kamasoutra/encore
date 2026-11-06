#!/bin/bash
# Regenerates the map from the current code. Needs the Floorplan plugin (Claude Code). See README.md.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
map=website/how-it-works/map
tool=$(ls -d ~/.claude/plugins/cache/floorplan/floorplan/*/skills/floorplan 2>/dev/null | sort -V | tail -1)
[ -n "$tool" ] || { echo "Install the Floorplan plugin first: https://github.com/haydenschmitty/floorplan" >&2; exit 1; }
mkdir -p floorplan/descriptions
cp "$map/architecture.json" floorplan/
cp "$map"/descriptions/*.json floorplan/descriptions/
node "$tool/scripts/scan.mjs" . >/dev/null
node "$tool/scripts/build.mjs" .
node floorplan/serve.mjs --export "$map/encore-map.html" --include flows,notes
python3 website/build.py >/dev/null
node website/how-it-works/check.mjs
