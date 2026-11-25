#!/usr/bin/env bash
# Box/CI check: builds the Foundation-only Swift core (Sources/Core.swift + bundled hunspell) on Linux
# and runs core/tests/cases.json. Needs a Swift toolchain for Linux (swift.org) in PATH.
set -euo pipefail
cd "$(dirname "$0")/.."
T="${TMPDIR:-/tmp}/smartumswitch-swift-test"; mkdir -p "$T"
for f in vendor/hunspell/*.cxx; do o="$T/$(basename "${f%.cxx}").o"; [ -f "$o" ] || clang++ -O2 -std=c++11 -DHUNSPELL_STATIC -w -c "$f" -o "$o"; done
swiftc -swift-version 5 -O -import-objc-header Sources/Bridge.h Sources/Core.swift tests/linux/main.swift "$T"/*.o -lstdc++ -o "$T/sstest"
"$T/sstest" ../core ../core/tests/cases.json
