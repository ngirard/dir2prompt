#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
DIR2PROMPT="$BUILD_DIR/dir2prompt.sh"
SIMPLE_FIXTURE="$SCRIPT_DIR/fixtures/simple_project"
PROMPTIGNORE_FIXTURE="$SCRIPT_DIR/fixtures/promptignore_dirs"

function ensure_dir2prompt_built {
    if [[ ! -f "$DIR2PROMPT" || "$PROJECT_ROOT/src/dir2prompt.sh" -nt "$DIR2PROMPT" ]]; then
        echo "Building dir2prompt for explain-path tests..."
        cd "$PROJECT_ROOT"
        VERSION=$(cat version)
        RELEASE_DATE=$(date +%Y-%m-%d)
        export VERSION
        export MAINTAINER='Nicolas Girard <girard.nicolas@gmail.com>'
        export RELEASE_DATE
        mkdir -p "$BUILD_DIR"
        envsubst '${MAINTAINER},${RELEASE_DATE},${VERSION}' < src/dir2prompt.sh > "$DIR2PROMPT"
        chmod +x "$DIR2PROMPT"
    fi
}

function assert_contains {
    local output="$1"
    local expected="$2"
    if grep -F -q -- "$expected" <<<"$output"; then
        return 0
    fi
    echo "Expected output to contain: $expected" >&2
    return 1
}

function run_test {
    local name="$1"
    shift
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Explain-path Test $TESTS_RUN: $name ... "
    if "$@"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}PASS${NC}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}FAIL${NC}"
    fi
}

function test_included_path {
    local output
    output=$("$DIR2PROMPT" explain-path --dir "$SIMPLE_FIXTURE" main.py)
    assert_contains "$output" "Final status: **included**" && \
    assert_contains "$output" "Phase 1: universe" && \
    assert_contains "$output" "Phase 5: CLI constraints"
}

function test_promptignore_excluded {
    local output
    output=$("$DIR2PROMPT" explain-path --dir "$PROMPTIGNORE_FIXTURE" tests/spec.txt)
    assert_contains "$output" "Final status: **excluded**" && \
    assert_contains "$output" "Active .promptignore" && \
    assert_contains "$output" "baseline filters"
}

ensure_dir2prompt_built
run_test "included path" test_included_path
run_test "promptignore exclusion" test_promptignore_excluded

echo ""
echo "Explain-path tests: $TESTS_PASSED passed / $TESTS_RUN total"
if [[ "$TESTS_FAILED" -ne 0 ]]; then
    exit 1
fi
