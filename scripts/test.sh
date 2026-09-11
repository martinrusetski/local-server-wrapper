#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="${LSW_TEST_ROOT:-$ROOT/.build/tests}"
FLAGS=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= MACOSX_DEPLOYMENT_TARGET=13.5)
xcodebuild -project "$ROOT/LocalServerWrapper/LocalServerWrapper.xcodeproj" -scheme LocalServerWrapper \
    -derivedDataPath "$TEST_ROOT/manager" -disableAutomaticPackageResolution -destination 'platform=macOS' \
    -only-testing:LocalServerWrapperTests -parallel-testing-enabled NO \
    -test-timeouts-enabled YES -maximum-test-execution-time-allowance 60 test "${FLAGS[@]}"
xcodebuild -project "$ROOT/ServerAppBundle/ServerAppBundle.xcodeproj" -scheme ServerAppBundle \
    -derivedDataPath "$TEST_ROOT/runtime" -destination 'platform=macOS' \
    -only-testing:ServerRuntimeTests \
    -parallel-testing-enabled NO -test-timeouts-enabled YES -maximum-test-execution-time-allowance 60 \
    clean test "${FLAGS[@]}"
