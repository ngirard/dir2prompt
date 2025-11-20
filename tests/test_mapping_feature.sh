#!/usr/bin/env bash
# Focused tests for the --map content mapping feature.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIR2PROMPT="$PROJECT_ROOT/src/dir2prompt.sh"

export MAINTAINER="Mapping Feature Test"
export VERSION="0.0.0"
export RELEASE_DATE="Today"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat <<'EOF' > "$TMP_DIR/basic.txt"
alpha
EOF
cat <<'EOF' > "$TMP_DIR/other.txt"
focus-other
EOF
cat <<'EOF' > "$TMP_DIR/specific.txt"
focus-specific
EOF
cat <<'EOF' > "$TMP_DIR/interp.txt"
placeholder
EOF
cat <<'EOF' > "$TMP_DIR/header.txt"
needs header annotation
EOF

tests_run=0
tests_failed=0

function assert_contains {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" == *"$needle"* ]]
}

function assert_not_contains {
    local haystack="$1"
    local needle="$2"
    if [[ "$haystack" == *"$needle"* ]]; then
        return 1
    fi
    return 0
}

function run_test {
    local description="$1"
    shift
    tests_run=$((tests_run + 1))
    if "$@"; then
        printf '[PASS] %s\n' "$description"
    else
        printf '[FAIL] %s\n' "$description"
        tests_failed=$((tests_failed + 1))
    fi
}

function test_basic_mapping {
    local output
    output=$("$DIR2PROMPT" --contents-only --map "*.txt:tr 'a-z' 'A-Z' < {}" "$TMP_DIR")
    assert_contains "$output" "ALPHA"
}

function test_precedence_rules {
    local output
    output=$("$DIR2PROMPT" --contents-only \
        --map "*.txt:echo TRANSFORMED" \
        --map "specific.txt:raw" \
        "$TMP_DIR")
    local transformed_header
    transformed_header=$(printf '`%s` (transformed via `%s`):' "other.txt" "echo TRANSFORMED")
    assert_contains "$output" "$transformed_header" && \
        assert_contains "$output" "TRANSFORMED" && \
        assert_contains "$output" "focus-specific"
}

function test_interpolation_placeholder {
    local expected_path="$TMP_DIR/interp.txt"
    local output
    output=$("$DIR2PROMPT" --contents-only --map "interp.txt:echo '{}'" "$TMP_DIR")
    assert_contains "$output" "$expected_path"
}

function test_header_annotation {
    local output
    output=$("$DIR2PROMPT" --contents-only --map "*.txt:tr 'a-z' 'A-Z' < {}" "$TMP_DIR")
    local expected_header
    expected_header=$(printf '`%s` (transformed via `%s`):' "basic.txt" "tr 'a-z' 'A-Z' < {}")
    assert_contains "$output" "$expected_header"
}

run_test "Basic mapping transforms contents" test_basic_mapping
run_test "Last-match wins with raw override" test_precedence_rules
run_test "{} placeholder is interpolated" test_interpolation_placeholder
run_test "Headers include transformation notice" test_header_annotation

printf '\n'
if (( tests_failed > 0 )); then
    printf '%d/%d mapping tests failed.\n' "$tests_failed" "$tests_run"
    exit 1
fi

printf 'All %d mapping tests passed.\n' "$tests_run"