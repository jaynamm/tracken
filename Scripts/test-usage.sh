#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
test_build=$(mktemp -d "${TMPDIR:-/tmp}/tracken-tests.XXXXXX")
trap 'rm -rf "$test_build"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
    -target "$(uname -m)-apple-macos26.3" \
    tracken/Models/Models.swift tracken/Services/*.swift tracken/Stores/UsageStore.swift \
    Tests/UsageRegressionTests.swift -o "$test_build/usage-tests"
"$test_build/usage-tests"
