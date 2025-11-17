#!/usr/bin/env bash
# Bash-based test suite for the --manifest=llm mode. The file uses the .bats
# extension to match the strategy instructions but is executed as a standard
# Bash script.

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

function ensure_dir2prompt_built {
    if [[ ! -f "$DIR2PROMPT" || "$PROJECT_ROOT/src/dir2prompt.sh" -nt "$DIR2PROMPT" ]]; then
        echo "Building dir2prompt for LLM manifest tests..."
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

TEMP_DIRS=()
TEMP_FILES=()
function make_temp_dir {
    local tmp
    tmp=$(mktemp -d)
    TEMP_DIRS+=("$tmp")
    echo "$tmp"
}

function make_temp_file {
    local tmp
    tmp=$(mktemp)
    TEMP_FILES+=("$tmp")
    echo "$tmp"
}

function cleanup_temps {
    for dir in "${TEMP_DIRS[@]}"; do
        [[ -d "$dir" ]] && rm -rf "$dir"
    done
    for file in "${TEMP_FILES[@]}"; do
        [[ -e "$file" ]] && rm -f "$file"
    done
}
trap cleanup_temps EXIT

function assert_contains {
    local output="$1"
    local expected="$2"
    if grep -F -q -- "$expected" <<<"$output"; then
        return 0
    fi
    echo "Expected output to contain: $expected" >&2
    return 1
}

function assert_occurrence_count {
    local output="$1"
    local needle="$2"
    local expected="$3"
    local actual
    actual=$(grep -F -c -- "$needle" <<<"$output")
    if [[ "$actual" -eq "$expected" ]]; then
        return 0
    fi
    echo "Expected '$needle' to appear $expected time(s) but saw $actual" >&2
    return 1
}

function run_test {
    local name="$1"
    shift
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "LLM Manifest Test $TESTS_RUN: $name ... "
    if "$@"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}PASS${NC}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}FAIL${NC}"
    fi
}

function test_llm_no_filters {
    local tmp
    tmp=$(make_temp_dir)
    touch "$tmp"/a.md "$tmp"/b.js "$tmp"/c.txt
    local output
    output=$("$DIR2PROMPT" --manifest=llm --tree-only "$tmp")
    assert_contains "$output" "Context Summary"
    assert_contains "$output" "No filters were applied"
    assert_contains "$output" "complete and unfiltered view"
}

function test_llm_baseline_promptignore {
    local tmp
    tmp=$(make_temp_dir)
    cat <<'EOF' > "$tmp/.promptignore"
*.tmp
EOF
    touch "$tmp"/keep.me "$tmp"/skip.tmp
    local output
    output=$("$DIR2PROMPT" --manifest=llm --tree-only "$tmp")
    assert_contains "$output" "`.promptignore`"
    assert_contains "$output" "removed"
    assert_contains "$output" "broad overview"
}

function test_llm_view_and_type {
    local fixture="$SCRIPT_DIR/fixtures/project_with_rules"
    local output
    output=$("$DIR2PROMPT" --manifest=llm --tree-only --view docs-deep --type md "$fixture")
    assert_contains "$output" "'docs-deep' view"
    assert_contains "$output" "file type filter"
    assert_contains "$output" "focused slice"
}

function test_llm_cli_overrides {
    local fixture="$SCRIPT_DIR/fixtures/project_with_rules"
    local extra_rules
    extra_rules=$(make_temp_file)
    echo '!README.md' > "$extra_rules"
    local output
    output=$("$DIR2PROMPT" --manifest=llm --tree-only --view focus-only --add-rule docs --drop-rule focus --add-rule-file "$extra_rules" "$fixture")
    assert_contains "$output" "progressively refined"
    assert_contains "$output" "dropping 1 named rule"
    assert_contains "$output" "ephemeral rule file"
}

function test_llm_multi_target {
    local tmp1 tmp2
    tmp1=$(make_temp_dir)
    tmp2=$(make_temp_dir)
    touch "$tmp1"/one.txt "$tmp2"/two.txt
    local output
    output=$("$DIR2PROMPT" --manifest=llm --tree-only "$tmp1" "$tmp2")
    assert_occurrence_count "$output" "Context Summary" 2
}

ensure_dir2prompt_built

run_test "no filters" test_llm_no_filters
run_test "baseline promptignore" test_llm_baseline_promptignore
run_test "view and type filters" test_llm_view_and_type
run_test "cli overrides" test_llm_cli_overrides
run_test "multi target" test_llm_multi_target

echo ""
echo "LLM manifest tests: $TESTS_PASSED passed / $TESTS_RUN total"
if [[ "$TESTS_FAILED" -ne 0 ]]; then
    exit 1
fi
```}