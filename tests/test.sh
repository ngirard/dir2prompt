#!/usr/bin/env bash
# Test harness for dir2prompt

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
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
CONFIG_FIXTURE="$(cd "$SCRIPT_DIR/fixtures/project_with_rules" && pwd)"
DIR2PROMPT="$BUILD_DIR/dir2prompt.sh"

# Build the script if needed
if [[ ! -f "$DIR2PROMPT" || "$PROJECT_ROOT/src/dir2prompt.sh" -nt "$DIR2PROMPT" ]]; then
    echo "Building dir2prompt..."
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
    if echo "$output" | grep -F -q "$expected"; then
        return 0
    else
        return 1
    fi
}

function assert_not_contains {
    local output="$1"
    local expected="$2"
    if echo "$output" | grep -F -q "$expected"; then
        return 1
    else
        return 0
    fi
}

function assert_line_count {
    local output="$1"
    local expected="$2"
    local actual
    actual=$(echo "$output" | wc -l)
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

# Test 39: Finder backend parity for tree output
test_start "fd backend matches rg tree output on fixture"
rg_output=$(DIR2PROMPT_FINDER=rg "$DIR2PROMPT" --tree-only "$FIXTURES_DIR" 2>&1)
fd_output=$(DIR2PROMPT_FINDER=fd "$DIR2PROMPT" --tree-only "$FIXTURES_DIR" 2>&1)
if [[ "$rg_output" == "$fd_output" ]]; then
    test_pass
else
    test_fail "fd backend tree output should match rg backend"
fi

# Test 40: Config dump exposes parsed view metadata
test_start "Config debug dump shows parsed views"
output=$(DIR2PROMPT_DEBUG_CONFIG_DUMP=1 "$DIR2PROMPT" --tree-only "$CONFIG_FIXTURE" 2>&1)
if assert_contains "$output" "[[DIR2PROMPT-CONFIG dir=\"$CONFIG_FIXTURE\"]]" && \
   assert_contains "$output" "baseline_view=default" && \
   assert_contains "$output" "VIEW docs-deep" && \
   assert_contains "$output" "rules=baseline, docs" && \
   assert_contains "$output" "follow_symlinks=true"; then
    test_pass
else
    test_fail "Config dump should include baseline view metadata"
fi

# Test 41: Config dump includes rule include/exclude sets
test_start "Config dump lists rule includes and excludes"
output=$(DIR2PROMPT_DEBUG_CONFIG_DUMP=1 "$DIR2PROMPT" --tree-only "$CONFIG_FIXTURE" 2>&1)
if assert_contains "$output" "RULE docs" && \
   assert_contains "$output" "includes=README.md, docs/**" && \
   assert_contains "$output" "  excludes="; then
    test_pass
else
    test_fail "Rule details should expose includes and excludes"
fi

# Test 42: Debug dump disabled by default
test_start "Config dump stays silent without env var"
output=$("$DIR2PROMPT" --tree-only "$CONFIG_FIXTURE" 2>&1)
if assert_not_contains "$output" "[[DIR2PROMPT-CONFIG"; then
    test_pass
else
    test_fail "Config dump should only appear when explicitly requested"
fi

# Test 43: Target debug dump captures CLI metadata (simple mode)
test_start "Target debug dump captures CLI metadata"
tmp_rule_rel="tests/tmp-rule-$RANDOM.ignore"
tmp_rule_path="$PROJECT_ROOT/$tmp_rule_rel"
echo "# temporary" > "$tmp_rule_path"
expected_rule_path="$tmp_rule_path"
output=$(DIR2PROMPT_DEBUG_TARGETS=1 "$DIR2PROMPT" --tree-only --view docs-deep --add-rule focus --drop-rule baseline --add-rule-file "$tmp_rule_rel" --follow-symlinks "$CONFIG_FIXTURE" 2>&1)
rm -f "$tmp_rule_path"
if assert_contains "$output" "[[DIR2PROMPT-TARGET dir=\"$CONFIG_FIXTURE\"]]" && \
    assert_contains "$output" "view=docs-deep" && \
    assert_contains "$output" "add_rules=focus" && \
    assert_contains "$output" "drop_rules=baseline" && \
   assert_contains "$output" "add_rule_files=$expected_rule_path" && \
   assert_contains "$output" "symlinks=follow"; then
    test_pass
else
    test_fail "Debug target dump should reflect CLI metadata"
fi

# Test 44: Advanced mode target metadata
test_start "Advanced mode target metadata tracks overrides"
multi_tmp=$(mktemp -d)
pushd "$multi_tmp" >/dev/null
mkdir -p dir1 dir2
echo "first target" > dir1/a
echo "second target" > dir2/b
cp -R "$CONFIG_FIXTURE/.dir2prompt" dir1/.dir2prompt
cp -R "$CONFIG_FIXTURE/.dir2prompt" dir2/.dir2prompt
echo "# global" > global-rules.ignore
echo "# second" > second-rules.ignore
output=$(DIR2PROMPT_DEBUG_TARGETS=1 "$DIR2PROMPT" --view default --add-rule docs --add-rule-file global-rules.ignore \
    --target first --dir dir1 --drop-rule docs \
    --target second --dir dir2 --view focus-only --add-rule focus --add-rule-file second-rules.ignore --no-follow-symlinks 2>&1)
global_rule_path="$multi_tmp/global-rules.ignore"
second_rule_path="$multi_tmp/second-rules.ignore"
popd >/dev/null
rm -rf "$multi_tmp"
if assert_contains "$output" "[[DIR2PROMPT-TARGET dir=\"dir1\"]]" && \
    assert_contains "$output" "view=default" && \
    assert_contains "$output" "add_rules=docs" && \
    assert_contains "$output" "drop_rules=docs" && \
   assert_contains "$output" "add_rule_files=$global_rule_path" && \
   assert_contains "$output" "symlinks=inherit" && \
    assert_contains "$output" "[[DIR2PROMPT-TARGET dir=\"dir2\"]]" && \
    assert_contains "$output" "view=focus-only" && \
    assert_contains "$output" "add_rules=docs|focus" && \
    assert_contains "$output" "add_rule_files=$global_rule_path|$second_rule_path" && \
   assert_contains "$output" "symlinks=nofollow"; then
    test_pass
else
    test_fail "Advanced mode metadata should track per-target overrides"
fi

# Test 45: Contradictory symlink flags fail fast
test_start "Contradictory symlink flags are rejected"
set +e
output=$("$DIR2PROMPT" --tree-only --follow-symlinks --no-follow-symlinks "$FIXTURES_DIR" 2>&1)
status=$?
set -e
if [[ "$status" -ne 0 ]] && assert_contains "$output" "Contradictory symlink options"; then
    test_pass
else
    test_fail "Conflicting symlink flags should fail (status=$status)"
fi

# Test 46: rules add creates rule and view
test_start "rules add writes rule file and default view"
rules_tmp=$(mktemp -d)
pushd "$rules_tmp" >/dev/null
cat <<'EOF' > baseline.ignore
!README.md
EOF
"$DIR2PROMPT" rules add baseline --description "Baseline scope" --from-file baseline.ignore --view default >/dev/null
view_file="$rules_tmp/.dir2prompt/views.yml"
rule_file="$rules_tmp/.dir2prompt/rules/baseline.ignore"
view_contents=$(cat "$view_file")
rule_contents=$(cat "$rule_file")
popd >/dev/null
if assert_contains "$view_contents" "baseline" && \
     assert_contains "$view_contents" "default" && \
     assert_contains "$rule_contents" "!README.md"; then
        test_pass
else
        test_fail "rules add should create config and rule files"
fi
rm -rf "$rules_tmp"

# Test 47: rules add with base view refreshes existing view
test_start "rules add --base-view refreshes target view"
rules_tmp=$(mktemp -d)
cp -R "$CONFIG_FIXTURE/." "$rules_tmp"
pushd "$rules_tmp" >/dev/null
"$DIR2PROMPT" rules add docs-focus --view docs-deep --base-view default <<'EOF' >/dev/null
!docs/**
EOF
list_output=$("$DIR2PROMPT" rules list)
popd >/dev/null
if assert_contains "$list_output" "docs-focus" && \
    assert_contains "$list_output" "rules: baseline, docs-focus"; then
                test_pass
else
                test_fail "rules add --base-view should replace a view's rule list"
fi
rm -rf "$rules_tmp"

# Test 48: rules show displays rule contents
test_start "rules show prints rule file contents"
pushd "$CONFIG_FIXTURE" >/dev/null
output=$("$DIR2PROMPT" rules show docs 2>&1)
popd >/dev/null
if assert_contains "$output" "Rule: docs" && \
     assert_contains "$output" ".dir2prompt/rules/docs-only.ignore" && \
     assert_contains "$output" "!docs/**"; then
        test_pass
else
        test_fail "rules show should print the selected rule"
fi

# Test 49: Views drive selection output
test_start "--view docs-deep focuses on docs slice"
output=$("$DIR2PROMPT" --tree-only --view docs-deep "$CONFIG_FIXTURE" 2>&1)
if assert_contains "$output" "README.md" && \
   assert_contains "$output" "guide.md" && \
   assert_contains "$output" "todo.md" && \
   assert_not_contains "$output" "main.py"; then
    test_pass
else
    test_fail "docs-deep view should limit output to docs and README"
fi

# Test 50: Focus view keeps source slice only
test_start "--view focus-only shows source focus"
output=$("$DIR2PROMPT" --tree-only --view focus-only "$CONFIG_FIXTURE" 2>&1)
if assert_contains "$output" "README.md" && \
   assert_contains "$output" "main.py" && \
   assert_not_contains "$output" "guide.md"; then
    test_pass
else
    test_fail "focus-only view should highlight README and src while hiding docs"
fi

# Test 51: Dropping a rule reverts to baseline
test_start "Dropping docs rule restores broader view"
output=$("$DIR2PROMPT" --tree-only --view docs-deep --drop-rule docs "$CONFIG_FIXTURE" 2>&1)
if assert_contains "$output" "main.py" && \
   assert_contains "$output" "guide.md"; then
    test_pass
else
    test_fail "Dropping docs rule should allow source files back into the selection"
fi

# Test 52: CLI add-rule layers additional slices
test_start "Adding docs rule to focus view merges slices"
output=$("$DIR2PROMPT" --tree-only --view focus-only --add-rule docs "$CONFIG_FIXTURE" 2>&1)
if assert_contains "$output" "main.py" && \
   assert_contains "$output" "guide.md" && \
   assert_contains "$output" "README.md"; then
    test_pass
else
    test_fail "Adding docs rule should merge docs into the focus view"
fi

# Test 53: Ephemeral rule files apply even without config
test_start "Ephemeral add-rule-file filters current target"
tmp_rule=$(mktemp)
echo "README.md" > "$tmp_rule"
output=$("$DIR2PROMPT" --tree-only --add-rule-file "$tmp_rule" "$FIXTURES_DIR" 2>&1)
rm -f "$tmp_rule"
if assert_not_contains "$output" "README.md"; then
    test_pass
else
    test_fail "Ephemeral rule file should exclude README.md from the snapshot"
fi

# Test 54: Manifest summary highlights rule provenance
test_start "--manifest summary lists active rules"
output=$("$DIR2PROMPT" --manifest --tree-only --view docs-deep "$CONFIG_FIXTURE" 2>&1)
if assert_contains "$output" "### Manifest for" && \
   assert_contains "$output" "Manifest mode: summary" && \
   assert_contains "$output" "View: docs-deep" && \
   assert_contains "$output" "baseline: Core repository hygiene" && \
   assert_contains "$output" "docs: Focus on documentation and guides" && \
   assert_contains "$output" "Counts:"; then
    test_pass
else
    test_fail "--manifest should emit view and rule context"
fi

# Test 55: Manifest full mode enumerates selection files
test_start "--manifest=full includes selection listing"
output=$("$DIR2PROMPT" --manifest=full --contents-only --view docs-deep "$CONFIG_FIXTURE" 2>&1)
if assert_contains "$output" "Manifest mode: full" && \
   assert_contains "$output" "Selection files" && \
   assert_contains "$output" "README.md" && \
   assert_contains "$output" "Contents of the non-binary files"; then
    test_pass
else
    test_fail "--manifest=full should list the files in the manifest"
fi

# Test 56: Manifest counts differentiate universe vs selection
test_start "--manifest counts reflect filtering"
output=$("$DIR2PROMPT" --manifest --tree-only --view docs-deep "$CONFIG_FIXTURE" 2>&1)
if assert_contains "$output" "  - Universe: 4" && \
   assert_contains "$output" "  - Selection: 3"; then
    test_pass
else
    test_fail "Manifest counts should show total candidates and filtered selection"
fi

# Test 57: Manifest counts include .promptignore baseline
test_start "Manifest counts reflect .promptignore exclusions"
output=$("$DIR2PROMPT" --manifest --tree-only "$FIXTURES_DIR" 2>&1)
if assert_contains "$output" "  - Universe: 6" && \
   assert_contains "$output" "  - Selection: 5"; then
    test_pass
else
    test_fail "Universe should include files hidden by .promptignore"
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
