#!/bin/sh
# Builds both editions and the test fixtures, then runs every test.
# Needs rojo 7.7+ and lune 0.11+ on PATH (or ROBLOX_TOOLS pointing at their folder).
set -eu
cd "$(dirname "$0")/.."
T="${ROBLOX_TOOLS:-}"; ROJO="${T:+$T/}rojo"; LUNE="${T:+$T/}lune"
mkdir -p build/fixtures
"$ROJO" build default.project.json -o build/ZovoBackdoorScanner.rbxm
"$ROJO" build pro.project.json -o build/ZovoBackdoorScannerPro.rbxm
"$ROJO" build tests/fixtures/infected.project.json -o build/fixtures/infected.rbxm
"$ROJO" build tests/fixtures/clean.project.json -o build/fixtures/clean.rbxm
"$LUNE" run tests/unit.luau
"$LUNE" run tests/studio_sim.luau build
"$LUNE" run scripts/selfscan.luau build/ZovoBackdoorScanner.rbxm store
"$LUNE" run scripts/selfscan.luau build/ZovoBackdoorScannerPro.rbxm store
echo "all builds and tests passed"
