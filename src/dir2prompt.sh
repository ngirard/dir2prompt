#!/usr/bin/env bash
# Bash script to create a snapshot of a directory's structure and contents for LLM prompts.

# Usage function to display help message
function usage {
    cat <<-EoN
	Usage: ${PROGRAM} [OPTIONS] [DIRECTORY]	
	Options:
	  --contents-only        Display only the contents of non-binary files.
	  --help                 Display this help message.
	  --ignore-file <FILE>   Specify a custom ignore file (default: .promptignore in the target directory).
	  --max-depth <NUM>      Limit the depth of directory traversal.
	  --max-filesize <NUM>   Ignore files larger than NUM in size.
	  --tree-only            Display only the directory tree.
	  --type <TYPE>          Limit search to files matching the given type.
	
	If no directory is specified, the current directory is used.
EoN
} # End of function usage

# Unofficial bash Strict Mode?
set -euo pipefail

# ——————————
# Globals and constants
PROGRAM=${0##*/}
MAINTAINER='${MAINTAINER}'
VERSION='${VERSION}'
RELEASE_DATE='${RELEASE_DATE}'
Version="v${VERSION} (${RELEASE_DATE})"

DEPENDENCIES=('rg' 'tree')

# Error messages
ERROR_MISSING_DEP='Required dependency '%s' not found. Please install it and try again.'

# ——————————
# Logging

# Logs a message to stderr.
function log {
    printf '%s\n' "$1" >&2
}

# Logs an error message to stderr and exits the program with a status of 1.
function fatal {
    if (( $# == 1 )); then
        printf '%s\n' "$1" >&2
    else
        # shellcheck disable=2059
        printf "$1\n" "${@:2}" >&2
    fi
    exit 1
}

# ——————————
# Argument parsing and dependency checking

# Parse command-line arguments
function parse_arguments {
    local dir="."
    local ignore_file=""
    local mode="both"
    local filter_options=()

    while (( $# > 0 )); do
        case "$1" in
            --tree-only)
                mode="tree"
                ;;
            --contents-only)
                mode="contents"
                ;;
            --type)
                if [[ -z "${2-}" ]]; then
                    fatal "Option --type requires an argument"
                fi
                filter_options+=("--type" "$2")
                shift
                ;;
            --max-depth)
                if [[ -z "${2-}" ]]; then
                    fatal "Option --max-depth requires an argument"
                fi
                filter_options+=("--max-depth" "$2")
                shift
                ;;
            --max-filesize)
                if [[ -z "${2-}" ]]; then
                    fatal "Option --max-filesize requires an argument"
                fi
                filter_options+=("--max-filesize" "$2")
                shift
                ;;
            --help)
                mode="help"
                ;;
            --ignore-file)
                if [[ -z "${2-}" ]]; then
                    fatal "Option --ignore-file requires an argument"
                fi
                ignore_file="$2"
                shift
                ;;
            -*)
                fatal "Unknown option: $1"
                ;;
            *)
                if [[ "$dir" != "." ]]; then
                    fatal "Only one directory can be specified"
                fi
                dir="$1"
                ;;
        esac
        shift
    done

    echo "$dir" "$mode" "$ignore_file" "${filter_options[@]+"${filter_options[@]}"}"
} # End of function parse_arguments

# Check if required dependencies are installed
function check_dependencies {
    local dep
    for dep in "${@}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            fatal "$ERROR_MISSING_DEP" "$dep"
        fi
    done
} # End of function check_dependencies

# ——————————
# Plumbing commands

# Generate directory tree
function generate_tree {
    local dir="$1"
    local filter_options=("${@:2}")
    cd "$dir" || fatal "Failed to cd into directory '%s'" "$dir"
    printf '%s\n' "### Directory contents in a tree‐like format"
    rg --files --sort path "${filter_options[@]+"${filter_options[@]}"}" | tree --fromfile --dirsfirst --noreport
    cd - >/dev/null || fatal "Failed to cd back to original directory"
} # End of function generate_tree

# Get the file list for contents generation
function get_file_list {
    local filter_options=("${@}")
    rg --files-with-matches . --sort path "${filter_options[@]+"${filter_options[@]}"}"
} # End of function get_file_list

# Visitor pattern to generate contents of a given file
function visit_file {
    local file="$1"
    local src_delimiter='````'
    # shellcheck disable=SC2016
    printf '\n`%s`:\n\n' "$file"
    printf '%s\n' "$src_delimiter"
    cat "$file"
    printf '\n%s\n' "$src_delimiter"
} # End of function visit_file

# Generate contents of non-binary files
function generate_contents {
    local dir="$1"
    local filter_options=("${@:2}")
    cd "$dir" || fatal "Failed to cd into directory '%s'" "$dir"
    printf '%s\n' "### Contents of the non-binary files of the directory"
    get_file_list "${filter_options[@]+"${filter_options[@]}"}" | while read -r file; do
        visit_file "$file"
    done
    cd - >/dev/null || fatal "Failed to cd back to original directory"
} # End of function generate_contents

# ——————————
# Porcelain commands

# Main function to generate snapshot
function main {
    local dir="$1"
    local mode="$2"
    local ignore_file="$3"
    shift 3
    local filter_options=("${@}")

    if [[ -z "$ignore_file" ]]; then
        ignore_file="$dir/.promptignore"
    fi
    if [[ -f "$dir/.promptignore" ]]; then
        filter_options+=("--ignore-file" "$dir/.promptignore")
    fi

    case "$mode" in
        help)
            usage
            log ""
            log "Maintainer: $MAINTAINER - Version: $Version"
            exit 0
            ;;
        both)
            generate_tree "$dir" "${filter_options[@]+"${filter_options[@]}"}"
            printf '\n'
            generate_contents "$dir" "${filter_options[@]+"${filter_options[@]}"}"
            ;;
        tree)
            generate_tree "$dir" "${filter_options[@]+"${filter_options[@]}"}"
            ;;
        contents)
            generate_contents "$dir" "${filter_options[@]+"${filter_options[@]}"}"
            ;;
        *)
            fatal "Invalid mode '%s'" "$mode"
            ;;
    esac
} # End of function main

# Main execution
if [ "$0" = "${BASH_SOURCE:-$0}" ]; then
    # Parse arguments
    parsed_args=$(parse_arguments "$@")
    read -r dir mode ignore_file filter_options <<< "$parsed_args"

    # Set default values if not provided
    dir=${dir:-"."}
    mode=${mode:-"both"}
    ignore_file=${ignore_file:-""}

    # Convert filter_options string back to an array
    IFS=' ' read -ra filter_options <<< "$filter_options"

    check_dependencies "${DEPENDENCIES[@]}"
    main "$dir" "$mode" "$ignore_file" "${filter_options[@]+"${filter_options[@]}"}"
fi