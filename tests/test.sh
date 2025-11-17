#!/usr/bin/env bash
# Test harness for dir2prompt

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
FIXTURES_DIR="$SCRIPT_DIR/fixtures/simple_project"
DIR2PROMPT="$BUILD_DIR/dir2prompt.sh"

# Build the script if needed
if [[ ! -f "$DIR2PROMPT" ]]; then
    echo "Building dir2prompt..."
    cd "$PROJECT_ROOT"
    export VERSION=$(cat version)
    export MAINTAINER='Nicolas Girard <girard.nicolas@gmail.com>'
    export RELEASE_DATE=$(date +%Y-%m-%d)
    mkdir -p "$BUILD_DIR"
    envsubst '${MAINTAINER},${RELEASE_DATE},${VERSION}' < src/dir2prompt.sh > "$DIR2PROMPT"
    chmod +x "$DIR2PROMPT"
fi

# Test helper functions
function test_start {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -n "Test $TESTS_RUN: $1 ... "
}

function test_pass {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}PASS${NC}"
}

function test_fail {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}FAIL${NC}"
    echo "  $1"
}

function assert_contains {
    local output="$1"
    local expected="$2"
    if echo "$output" | grep -q "$expected"; then
        return 0
    else
        return 1
    fi
}

function assert_not_contains {
    local output="$1"
    local expected="$2"
    if echo "$output" | grep -q "$expected"; then
        return 1
    else
        return 0
    fi
}

function assert_line_count {
    local output="$1"
    local expected="$2"
    local actual=$(echo "$output" | wc -l)
    if [[ "$actual" -eq "$expected" ]]; then
        return 0
    else
        echo "Expected $expected lines, got $actual"
        return 1
    fi
}

# ============================================================================
# Test Suite
# ============================================================================

echo "Running dir2prompt test suite"
echo "=============================="
echo ""

# Test 1: --tree-only mode
test_start "--tree-only displays tree but not contents"
output=$("$DIR2PROMPT" --tree-only "$FIXTURES_DIR" 2>&1)
if assert_contains "$output" "Directory contents in a tree‐like format" && \
   assert_not_contains "$output" "Contents of the non-binary files"; then
    test_pass
else
    test_fail "Tree-only mode should show tree but not contents"
fi

# Test 2: --contents-only mode
test_start "--contents-only displays contents but not tree"
output=$("$DIR2PROMPT" --contents-only "$FIXTURES_DIR" 2>&1)
if assert_contains "$output" "Contents of the non-binary files" && \
   assert_not_contains "$output" "Directory contents in a tree‐like format"; then
    test_pass
else
    test_fail "Contents-only mode should show contents but not tree"
fi

# Test 3: --type filters by file type (Python)
test_start "--type py filters to Python files only"
output=$("$DIR2PROMPT" --type py "$FIXTURES_DIR" 2>&1)
if assert_contains "$output" "main.py" && \
   assert_not_contains "$output" "app.js" && \
   assert_not_contains "$output" "helper.js"; then
    test_pass
else
    test_fail "--type py should only show Python files"
fi

# Test 4: --type filters by file type (JavaScript)
test_start "--type js filters to JavaScript files only"
output=$("$DIR2PROMPT" --type js "$FIXTURES_DIR" 2>&1)
if assert_contains "$output" "app.js" && \
   assert_contains "$output" "helper.js" && \
   assert_not_contains "$output" "main.py" && \
   assert_not_contains "$output" "README.md"; then
    test_pass
else
    test_fail "--type js should only show JavaScript files"
fi

# Test 5: --max-depth limits traversal depth
test_start "--max-depth 1 limits to top-level files"
output=$("$DIR2PROMPT" --max-depth 1 "$FIXTURES_DIR" 2>&1)
if assert_contains "$output" "app.js" && \
   assert_contains "$output" "main.py" && \
   assert_not_contains "$output" "helper.js" && \
   assert_not_contains "$output" "deep.js"; then
    test_pass
else
    test_fail "--max-depth 1 should only show files at depth 1"
fi

# Test 6: --max-depth 2 shows two levels
test_start "--max-depth 2 shows files up to depth 2"
output=$("$DIR2PROMPT" --max-depth 2 "$FIXTURES_DIR" 2>&1)
if assert_contains "$output" "app.js" && \
   assert_contains "$output" "helper.js" && \
   assert_not_contains "$output" "deep.js"; then
    test_pass
else
    test_fail "--max-depth 2 should show files up to depth 2"
fi

# Test 7: .promptignore is honored
test_start ".promptignore excludes specified files"
output=$("$DIR2PROMPT" "$FIXTURES_DIR" 2>&1)
if assert_not_contains "$output" "test.log"; then
    test_pass
else
    test_fail ".promptignore should exclude *.log files"
fi

# Test 8: --ignore-file with custom file
test_start "--ignore-file uses custom ignore file"
custom_ignore=$(mktemp)
echo "*.js" > "$custom_ignore"
output=$("$DIR2PROMPT" --ignore-file "$custom_ignore" "$FIXTURES_DIR" 2>&1)
rm "$custom_ignore"
if assert_contains "$output" "main.py" && \
   assert_not_contains "$output" "app.js" && \
   assert_not_contains "$output" "helper.js"; then
    test_pass
else
    test_fail "--ignore-file should use custom ignore patterns"
fi

# Test 9: Both modes work (default)
test_start "Default mode shows both tree and contents"
output=$("$DIR2PROMPT" "$FIXTURES_DIR" 2>&1)
if assert_contains "$output" "Directory contents in a tree‐like format" && \
   assert_contains "$output" "Contents of the non-binary files"; then
    test_pass
else
    test_fail "Default mode should show both tree and contents"
fi

# Test 10: Combining --type and --max-depth
test_start "Combining --type js and --max-depth 1 works"
output=$("$DIR2PROMPT" --type js --max-depth 1 "$FIXTURES_DIR" 2>&1)
if assert_contains "$output" "app.js" && \
   assert_not_contains "$output" "main.py" && \
   assert_not_contains "$output" "helper.js" && \
   assert_not_contains "$output" "deep.js"; then
    test_pass
else
    test_fail "Multiple filter options should work together"
fi

# Test 11: --max-filesize filters large files
test_start "--max-filesize excludes files over limit"
# Create a large file for testing
large_file="$FIXTURES_DIR/large.txt"
dd if=/dev/zero of="$large_file" bs=1024 count=2 2>/dev/null
output=$("$DIR2PROMPT" --max-filesize 1K "$FIXTURES_DIR" 2>&1)
rm "$large_file"
if assert_not_contains "$output" "large.txt"; then
    test_pass
else
    test_fail "--max-filesize should exclude files over the size limit"
fi

# Test 12: Multiple --ignore-file options work
test_start "Multiple --ignore-file options work together"
ignore1=$(mktemp)
ignore2=$(mktemp)
echo "*.py" > "$ignore1"
echo "*.md" > "$ignore2"
output=$("$DIR2PROMPT" --ignore-file "$ignore1" --ignore-file "$ignore2" "$FIXTURES_DIR" 2>&1)
rm "$ignore1" "$ignore2"
if assert_contains "$output" "app.js" && \
   assert_not_contains "$output" "main.py" && \
   assert_not_contains "$output" "README.md"; then
    test_pass
else
    test_fail "Multiple --ignore-file options should combine patterns"
fi

# Test 13: --ignore-file overrides default .promptignore
test_start "Explicit --ignore-file bypasses .promptignore"
override_ignore=$(mktemp)
output=$("$DIR2PROMPT" --ignore-file "$override_ignore" "$FIXTURES_DIR" 2>&1)
rm "$override_ignore"
if assert_contains "$output" "test.log"; then
    test_pass
else
    test_fail "Providing --ignore-file should ignore the directory's .promptignore"
fi

# Test 14: Git root .promptignore is respected for nested directories
test_start "Git root .promptignore applies when nested directory has none"
git_tmp=$(mktemp -d)
pushd "$git_tmp" >/dev/null
git init -q
cat <<'EOF' > .promptignore
secret.txt
EOF
mkdir -p nested
echo "visible" > nested/visible.txt
echo "hidden" > nested/secret.txt
output=$("$DIR2PROMPT" "$git_tmp/nested" 2>&1)
popd >/dev/null
rm -rf "$git_tmp"
if assert_contains "$output" "visible.txt" && \
   assert_not_contains "$output" "secret.txt"; then
    test_pass
else
    test_fail "Git root .promptignore should filter files in nested directory runs"
fi

# Test 15: .ripgreprc at git root is respected
test_start ".ripgreprc at git root is automatically loaded"
git_tmp=$(mktemp -d)
pushd "$git_tmp" >/dev/null
git init -q
# Create a .ripgreprc that adds a glob pattern to exclude .txt files
cat <<'EOF' > .ripgreprc
--glob=!*.txt
EOF
echo "included" > file.md
echo "excluded" > file.txt
output=$("$DIR2PROMPT" "$git_tmp" 2>&1)
popd >/dev/null
rm -rf "$git_tmp"
if assert_contains "$output" "file.md" && \
   assert_not_contains "$output" "file.txt"; then
    test_pass
else
    test_fail ".ripgreprc should be loaded and applied when present at git root"
fi

# Test 16: .ripgreprc with --follow flag
test_start ".ripgreprc --follow flag makes ripgrep follow symlinks"
git_tmp=$(mktemp -d)
pushd "$git_tmp" >/dev/null
git init -q
cat <<'EOF' > .ripgreprc
--follow
EOF
mkdir -p target
echo "content" > target/real.txt
ln -s target/real.txt linked.txt
output=$("$DIR2PROMPT" "$git_tmp" 2>&1)
popd >/dev/null
rm -rf "$git_tmp"
if assert_contains "$output" "linked.txt"; then
    test_pass
else
    test_fail ".ripgreprc with --follow should make ripgrep follow symlinks"
fi

# Test 17: --output writes to file instead of stdout
test_start "--output writes output to specified file"
output_file=$(mktemp)
"$DIR2PROMPT" --output "$output_file" "$FIXTURES_DIR" 2>&1
file_contents=$(cat "$output_file")
rm "$output_file"
if assert_contains "$file_contents" "Directory contents in a tree‐like format" && \
   assert_contains "$file_contents" "Contents of the non-binary files"; then
    test_pass
else
    test_fail "--output should write complete output to file"
fi

# Test 18: --output with --tree-only
test_start "--output with --tree-only writes only tree to file"
output_file=$(mktemp)
"$DIR2PROMPT" --tree-only --output "$output_file" "$FIXTURES_DIR" 2>&1
file_contents=$(cat "$output_file")
rm "$output_file"
if assert_contains "$file_contents" "Directory contents in a tree‐like format" && \
   assert_not_contains "$file_contents" "Contents of the non-binary files"; then
    test_pass
else
    test_fail "--output with --tree-only should write only tree to file"
fi

# Test 19: --output with --contents-only
test_start "--output with --contents-only writes only contents to file"
output_file=$(mktemp)
"$DIR2PROMPT" --contents-only --output "$output_file" "$FIXTURES_DIR" 2>&1
file_contents=$(cat "$output_file")
rm "$output_file"
if assert_contains "$file_contents" "Contents of the non-binary files" && \
   assert_not_contains "$file_contents" "Directory contents in a tree‐like format"; then
    test_pass
else
    test_fail "--output with --contents-only should write only contents to file"
fi

# Test 20: --output without argument shows error
test_start "--output without argument shows error"
output=$("$DIR2PROMPT" --output 2>&1 || true)
if assert_contains "$output" "Option --output requires an argument"; then
    test_pass
else
    test_fail "--output without argument should show error message"
fi

# Test 21: Relative --ignore-file resolves from invocation directory even for subdirectories
test_start "Relative --ignore-file works when targeting subdirectory"
project_tmp=$(mktemp -d)
pushd "$project_tmp" >/dev/null
mkdir -p docs
echo "keep" > docs/keepme.txt
echo "ignore" > docs/ignoreme.txt
cat <<'EOF' > testignore.txt
ignoreme.txt
EOF
output=$("$DIR2PROMPT" --ignore-file testignore.txt ./docs 2>&1)
popd >/dev/null
rm -rf "$project_tmp"
if assert_contains "$output" "keepme.txt" && \
    assert_not_contains "$output" '`ignoreme.txt`:' && \
   assert_not_contains "$output" "No such file or directory"; then
    test_pass
else
    test_fail "Relative ignore file should be resolved from invocation directory when inspecting subdirectories"
fi

# Test 22: Absolute --ignore-file paths continue to work
test_start "Absolute --ignore-file path remains supported"
project_tmp=$(mktemp -d)
pushd "$project_tmp" >/dev/null
mkdir -p docs
echo "keep" > docs/keepme.txt
echo "ignore" > docs/ignoreme.txt
cat <<'EOF' > testignore.txt
ignoreme.txt
EOF
abs_ignore="$project_tmp/testignore.txt"
output=$("$DIR2PROMPT" --ignore-file "$abs_ignore" ./docs 2>&1)
popd >/dev/null
rm -rf "$project_tmp"
if assert_contains "$output" "keepme.txt" && \
    assert_not_contains "$output" '`ignoreme.txt`:'; then
    test_pass
else
    test_fail "Absolute ignore file paths should remain valid"
fi

# Test 23: Relative --ignore-file works when targeting current directory
test_start "Relative --ignore-file works for current directory"
project_tmp=$(mktemp -d)
pushd "$project_tmp" >/dev/null
echo "keep" > keepme.txt
echo "ignore" > ignoreme.txt
cat <<'EOF' > testignore.txt
ignoreme.txt
EOF
output=$("$DIR2PROMPT" --ignore-file testignore.txt 2>&1)
popd >/dev/null
rm -rf "$project_tmp"
if assert_contains "$output" "keepme.txt" && \
    assert_not_contains "$output" '`ignoreme.txt`:'; then
    test_pass
else
    test_fail "Relative ignore file should also work when targeting the invocation directory"
fi

# ============================================================================
# Multi-target tests
# ============================================================================

# Test 24: Simple multi-directory mode with two directories
test_start "Simple multi-directory mode processes both directories"
multi_tmp=$(mktemp -d)
pushd "$multi_tmp" >/dev/null
mkdir -p dir1 dir2
echo "content1" > dir1/file1.txt
echo "content2" > dir2/file2.txt
output=$("$DIR2PROMPT" dir1 dir2 2>&1)
popd >/dev/null
rm -rf "$multi_tmp"
if assert_contains "$output" "file1.txt" && \
   assert_contains "$output" "file2.txt" && \
   assert_contains "$output" "content1" && \
   assert_contains "$output" "content2"; then
    test_pass
else
    test_fail "Simple multi-directory mode should process all directories"
fi

# Test 25: Simple mode with three directories
test_start "Simple mode with three directories"
multi_tmp=$(mktemp -d)
pushd "$multi_tmp" >/dev/null
mkdir -p dir1 dir2 dir3
echo "a" > dir1/a.txt
echo "b" > dir2/b.txt
echo "c" > dir3/c.txt
output=$("$DIR2PROMPT" dir1 dir2 dir3 2>&1)
popd >/dev/null
rm -rf "$multi_tmp"
if assert_contains "$output" "a.txt" && \
   assert_contains "$output" "b.txt" && \
   assert_contains "$output" "c.txt"; then
    test_pass
else
    test_fail "Should process all three directories"
fi

# Test 26: Multi-directory with shared --type filter
test_start "Multi-directory with shared --type filter"
multi_tmp=$(mktemp -d)
pushd "$multi_tmp" >/dev/null
mkdir -p dir1 dir2
echo "py1" > dir1/file1.py
echo "js1" > dir1/file1.js
echo "py2" > dir2/file2.py
echo "js2" > dir2/file2.js
output=$("$DIR2PROMPT" --type py dir1 dir2 2>&1)
popd >/dev/null
rm -rf "$multi_tmp"
if assert_contains "$output" "file1.py" && \
   assert_contains "$output" "file2.py" && \
   assert_not_contains "$output" "file1.js" && \
   assert_not_contains "$output" "file2.js"; then
    test_pass
else
    test_fail "Shared --type filter should apply to all directories"
fi

# Test 27: Advanced target mode with --target and --dir
test_start "Advanced target mode with two targets"
multi_tmp=$(mktemp -d)
pushd "$multi_tmp" >/dev/null
mkdir -p src docs
echo "code" > src/main.py
echo "doc" > docs/README.md
output=$("$DIR2PROMPT" --target src_target --dir src --target docs_target --dir docs 2>&1)
popd >/dev/null
rm -rf "$multi_tmp"
if assert_contains "$output" "main.py" && \
   assert_contains "$output" "README.md"; then
    test_pass
else
    test_fail "Advanced target mode should process both targets"
fi

# Test 28: Per-target --type filter overrides
test_start "Per-target --type filter in advanced mode"
multi_tmp=$(mktemp -d)
pushd "$multi_tmp" >/dev/null
mkdir -p dir1 dir2
echo "py1" > dir1/file1.py
echo "js1" > dir1/file1.js
echo "py2" > dir2/file2.py
echo "js2" > dir2/file2.js
output=$("$DIR2PROMPT" --target first --dir dir1 --type py --target second --dir dir2 --type js 2>&1)
popd >/dev/null
rm -rf "$multi_tmp"
if assert_contains "$output" "file1.py" && \
   assert_not_contains "$output" "file1.js" && \
   assert_not_contains "$output" "file2.py" && \
   assert_contains "$output" "file2.js"; then
    test_pass
else
    test_fail "Per-target --type should filter each target independently"
fi

# Test 29: Mixing positional directories with --target is rejected
test_start "Mixing positional directories with --target fails"
output=$("$DIR2PROMPT" "$FIXTURES_DIR" --target t1 --dir /tmp 2>&1 || true)
if assert_contains "$output" "Cannot mix positional directories with --target mode"; then
    test_pass
else
    test_fail "Should reject mixing positional and target modes"
fi

# Test 30: --target without --dir fails
test_start "--target without --dir shows error"
output=$("$DIR2PROMPT" --target myname 2>&1 || true)
if assert_contains "$output" "missing --dir"; then
    test_pass
else
    test_fail "--target without --dir should show error"
fi

# Test 31: Default target options before first --target
test_start "Default target options apply to all targets"
multi_tmp=$(mktemp -d)
pushd "$multi_tmp" >/dev/null
mkdir -p dir1 dir2
echo "py1" > dir1/file1.py
echo "js1" > dir1/file1.js
echo "py2" > dir2/file2.py
echo "js2" > dir2/file2.js
output=$("$DIR2PROMPT" --type py --target first --dir dir1 --target second --dir dir2 2>&1)
popd >/dev/null
rm -rf "$multi_tmp"
if assert_contains "$output" "file1.py" && \
   assert_contains "$output" "file2.py" && \
   assert_not_contains "$output" "file1.js" && \
   assert_not_contains "$output" "file2.js"; then
    test_pass
else
    test_fail "Default --type before first --target should apply to all targets"
fi

# Test 32: Per-target option overrides default
test_start "Per-target option overrides default"
multi_tmp=$(mktemp -d)
pushd "$multi_tmp" >/dev/null
mkdir -p dir1 dir2
echo "py1" > dir1/file1.py
echo "js1" > dir1/file1.js
echo "py2" > dir2/file2.py
echo "js2" > dir2/file2.js
output=$("$DIR2PROMPT" --type py --target first --dir dir1 --target second --dir dir2 --type js 2>&1)
popd >/dev/null
rm -rf "$multi_tmp"
if assert_contains "$output" "file1.py" && \
   assert_not_contains "$output" "file1.js" && \
   assert_not_contains "$output" "file2.py" && \
   assert_contains "$output" "file2.js"; then
    test_pass
else
    test_fail "Per-target --type should override default for that target"
fi

# Test 33: Multi-directory with --tree-only
test_start "Multi-directory with --tree-only"
multi_tmp=$(mktemp -d)
pushd "$multi_tmp" >/dev/null
mkdir -p dir1 dir2
echo "content1" > dir1/file1.txt
echo "content2" > dir2/file2.txt
output=$("$DIR2PROMPT" --tree-only dir1 dir2 2>&1)
popd >/dev/null
rm -rf "$multi_tmp"
if assert_contains "$output" "Directory contents in a tree‐like format" && \
   assert_not_contains "$output" "Contents of the non-binary files"; then
    test_pass
else
    test_fail "Multi-directory --tree-only should only show trees"
fi

# Test 34: Multi-directory with --contents-only
test_start "Multi-directory with --contents-only"
multi_tmp=$(mktemp -d)
pushd "$multi_tmp" >/dev/null
mkdir -p dir1 dir2
echo "content1" > dir1/file1.txt
echo "content2" > dir2/file2.txt
output=$("$DIR2PROMPT" --contents-only dir1 dir2 2>&1)
popd >/dev/null
rm -rf "$multi_tmp"
if assert_contains "$output" "Contents of the non-binary files" && \
   assert_not_contains "$output" "Directory contents in a tree‐like format"; then
    test_pass
else
    test_fail "Multi-directory --contents-only should only show contents"
fi

# Test 35: Per-target --max-depth
test_start "Per-target --max-depth in advanced mode"
multi_tmp=$(mktemp -d)
pushd "$multi_tmp" >/dev/null
mkdir -p dir1/sub dir2/sub
echo "top1" > dir1/top.txt
echo "deep1" > dir1/sub/deep.txt
echo "top2" > dir2/top.txt
echo "deep2" > dir2/sub/deep.txt
output=$("$DIR2PROMPT" --target first --dir dir1 --max-depth 1 --target second --dir dir2 2>&1)
popd >/dev/null
rm -rf "$multi_tmp"
if assert_contains "$output" "top.txt" && \
   assert_not_contains "$output" "dir1/sub/deep.txt" && \
   assert_contains "$output" "deep2"; then
    test_pass
else
    test_fail "Per-target --max-depth should apply independently"
fi

# Test 36: Per-target --ignore-file
test_start "Per-target --ignore-file in advanced mode"
multi_tmp=$(mktemp -d)
pushd "$multi_tmp" >/dev/null
mkdir -p dir1 dir2
echo "keep1" > dir1/keep.txt
echo "ignore1" > dir1/ignore.txt
echo "keep2" > dir2/keep.txt
echo "ignore2" > dir2/ignore.txt
cat <<'EOF' > ignore1.txt
ignore.txt
EOF
output=$("$DIR2PROMPT" --target first --dir dir1 --ignore-file ignore1.txt --target second --dir dir2 2>&1)
popd >/dev/null
rm -rf "$multi_tmp"
if assert_contains "$output" "keep.txt" && \
   assert_not_contains "$output" "dir1.*ignore.txt" && \
   assert_contains "$output" "ignore2"; then
    test_pass
else
    test_fail "Per-target --ignore-file should apply only to that target"
fi

# Test 37: Multiple targets with --output
test_start "Multi-directory with --output writes all targets to file"
multi_tmp=$(mktemp -d)
output_file=$(mktemp)
pushd "$multi_tmp" >/dev/null
mkdir -p dir1 dir2
echo "content1" > dir1/file1.txt
echo "content2" > dir2/file2.txt
"$DIR2PROMPT" --output "$output_file" dir1 dir2 2>&1
file_contents=$(cat "$output_file")
popd >/dev/null
rm -rf "$multi_tmp"
rm "$output_file"
if assert_contains "$file_contents" "file1.txt" && \
   assert_contains "$file_contents" "file2.txt"; then
    test_pass
else
    test_fail "Multi-directory --output should write all targets to file"
fi

# Test 38: Per-target .ripgreprc isolation
test_start "Each target uses its own .ripgreprc independently"
rg_tmp=$(mktemp -d)
pushd "$rg_tmp" >/dev/null
mkdir -p repo1 repo2
cd repo1
git init -q
cat <<'EOF' > .ripgreprc
--glob=!*.js
EOF
echo "py1" > file.py
echo "js1" > file.js
cd ../repo2
git init -q
# No .ripgreprc here
echo "py2" > file.py
echo "js2" > file.js
cd ..
output=$("$DIR2PROMPT" --tree-only repo1 repo2 2>&1)
popd >/dev/null
rm -rf "$rg_tmp"
# Count occurrences: should see 2 file.py (one per repo) and 1 file.js (only repo2)
py_count=$(echo "$output" | grep -c "file.py" || true)
js_count=$(echo "$output" | grep -c "file.js" || true)
if [[ "$py_count" -eq 2 ]] && [[ "$js_count" -eq 1 ]]; then
    test_pass
else
    test_fail ".ripgreprc should apply independently per target (py:$py_count js:$js_count)"
fi

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "=============================="
echo "Test Results"
echo "=============================="
echo "Total tests: $TESTS_RUN"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    exit 1
else
    echo "All tests passed!"
    exit 0
fi
