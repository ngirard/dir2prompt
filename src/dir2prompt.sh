#!/usr/bin/env bash
# Bash script to create a snapshot of a directory's structure and contents for LLM prompts.

# Usage function to display help message
function usage {
    cat <<-EoN
	Usage: ${PROGRAM} [OPTIONS] [DIRECTORY...]
	       ${PROGRAM} [GLOBAL_OPTIONS] --target NAME --dir PATH [TARGET_OPTIONS]...
	
	Global Options:
	  --contents-only        Display only the contents of non-binary files.
	  --help                 Display this help message.
	  --output <FILE>        Write output to FILE instead of stdout.
	  --tree-only            Display only the directory tree.
	
	Target Options (can be global defaults or per-target):
	  --ignore-file <FILE>   Repeatable. Use custom ignore file(s) and skip automatic .promptignore detection.
	                         Relative paths are resolved from the directory where dir2prompt is invoked.
	  --max-depth <NUM>      Limit the depth of directory traversal.
	  --max-filesize <NUM>   Ignore files larger than NUM in size.
	  --type <TYPE>          Limit search to files matching the given type.
	
	Simple Multi-Directory Mode:
	  dir2prompt [OPTIONS] dir1 dir2 dir3
	  All directories share the same target options.
	
	Advanced Per-Target Mode:
	  dir2prompt --target name1 --dir path1 [TARGET_OPTIONS] --target name2 --dir path2 [TARGET_OPTIONS]
	  Each target can have its own configuration.
	  Global target options before the first --target become defaults.
	
	Notes:
	  - If no directory is specified, the current directory is used.
	  - Cannot mix positional directories with --target mode.
EoN
} # End of function usage

# Unofficial bash Strict Mode?
set -euo pipefail

# ——————————
# Globals and constants
PROGRAM=${0##*/}
Maintainer="${MAINTAINER}"
Version="v${VERSION} (${RELEASE_DATE})"

DEPENDENCIES=('rg' 'tree')

# Error messages
ERROR_MISSING_DEP='Required dependency '%s' not found. Please install it and try again.'

# Capture the directory where dir2prompt was invoked so we can resolve
# user-provided paths (e.g., --ignore-file) before changing directories.
ORIG_CWD=$(pwd)

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

# Parse command-line arguments into global variables
function parse_arguments {
    # Global options
    PARSED_MODE="both"
    PARSED_OUTPUT_FILE=""
    
    # Target arrays - using parallel arrays to store target information
    TARGET_NAMES=()
    TARGET_DIRS=()
    TARGET_TYPES=()
    TARGET_MAX_DEPTHS=()
    TARGET_MAX_FILESIZES=()
    TARGET_IGNORE_FILES_SERIALIZED=()  # Serialized as "file1|file2|file3" or empty
    
    # Temporary state for parsing
    local positional_dirs=()
    local use_target_mode=false
    local has_positional=false
    
    # Default/global target options (before first --target in advanced mode, or global in simple mode)
    local default_types=()
    local default_max_depth=""
    local default_max_filesize=""
    local default_ignore_files=()
    
    # Current target being built (in advanced mode)
    local current_target_name=""
    local current_target_dir=""
    local current_target_types=()
    local current_target_max_depth=""
    local current_target_max_filesize=""
    local current_target_ignore_files=()
    local current_target_has_explicit_types=false
    local current_target_has_explicit_ignore=false
    local in_target_block=false

    # Function to finalize current target and add to arrays
    function finalize_target {
        if [[ -z "$current_target_dir" ]]; then
            fatal "Target '%s' is missing --dir option" "$current_target_name"
        fi
        
        TARGET_NAMES+=("$current_target_name")
        TARGET_DIRS+=("$current_target_dir")
        
        # Serialize types
        local types_str=""
        if [[ "${#current_target_types[@]}" -gt 0 ]]; then
            types_str=$(IFS='|'; echo "${current_target_types[*]}")
        fi
        TARGET_TYPES+=("$types_str")
        
        TARGET_MAX_DEPTHS+=("$current_target_max_depth")
        TARGET_MAX_FILESIZES+=("$current_target_max_filesize")
        
        # Serialize ignore files
        local ignore_str=""
        if [[ "${#current_target_ignore_files[@]}" -gt 0 ]]; then
            ignore_str=$(IFS='|'; echo "${current_target_ignore_files[*]}")
        fi
        TARGET_IGNORE_FILES_SERIALIZED+=("$ignore_str")
        
        # Reset for next target
        current_target_name=""
        current_target_dir=""
        current_target_types=()
        current_target_max_depth=""
        current_target_max_filesize=""
        current_target_ignore_files=()
        current_target_has_explicit_types=false
        current_target_has_explicit_ignore=false
        in_target_block=false
    }

    while (( $# > 0 )); do
        case "$1" in
            --tree-only)
                PARSED_MODE="tree"
                ;;
            --contents-only)
                PARSED_MODE="contents"
                ;;
            --output)
                if [[ -z "${2:-}" ]]; then
                    fatal "Option --output requires an argument"
                fi
                PARSED_OUTPUT_FILE="$2"
                shift
                ;;
            --help)
                PARSED_MODE="help"
                ;;
            --target)
                if [[ -z "${2:-}" ]]; then
                    fatal "Option --target requires an argument (target name)"
                fi
                use_target_mode=true
                
                # Finalize previous target if any
                if [[ "$in_target_block" == true ]]; then
                    finalize_target
                fi
                
                # Start new target
                current_target_name="$2"
                current_target_dir=""
                # Initialize with defaults
                current_target_types=("${default_types[@]+"${default_types[@]}"}")
                current_target_max_depth="$default_max_depth"
                current_target_max_filesize="$default_max_filesize"
                current_target_ignore_files=("${default_ignore_files[@]+"${default_ignore_files[@]}"}")
                current_target_has_explicit_types=false
                current_target_has_explicit_ignore=false
                in_target_block=true
                shift
                ;;
            --dir)
                if [[ -z "${2:-}" ]]; then
                    fatal "Option --dir requires an argument"
                fi
                if [[ "$use_target_mode" != true ]]; then
                    fatal "Option --dir can only be used with --target"
                fi
                current_target_dir="$2"
                shift
                ;;
            --type)
                if [[ -z "${2:-}" ]]; then
                    fatal "Option --type requires an argument"
                fi
                if [[ "$in_target_block" == true ]]; then
                    # Per-target type - clear defaults on first explicit type
                    if [[ "$current_target_has_explicit_types" == false ]]; then
                        current_target_types=()
                        current_target_has_explicit_types=true
                    fi
                    current_target_types+=("$2")
                else
                    # Default/global type
                    default_types+=("$2")
                fi
                shift
                ;;
            --max-depth)
                if [[ -z "${2:-}" ]]; then
                    fatal "Option --max-depth requires an argument"
                fi
                if [[ "$in_target_block" == true ]]; then
                    current_target_max_depth="$2"
                else
                    default_max_depth="$2"
                fi
                shift
                ;;
            --max-filesize)
                if [[ -z "${2:-}" ]]; then
                    fatal "Option --max-filesize requires an argument"
                fi
                if [[ "$in_target_block" == true ]]; then
                    current_target_max_filesize="$2"
                else
                    default_max_filesize="$2"
                fi
                shift
                ;;
            --ignore-file)
                if [[ -z "${2:-}" ]]; then
                    fatal "Option --ignore-file requires an argument"
                fi
                if [[ "$in_target_block" == true ]]; then
                    # Per-target ignore - clear defaults on first explicit ignore file
                    if [[ "$current_target_has_explicit_ignore" == false ]]; then
                        current_target_ignore_files=()
                        current_target_has_explicit_ignore=true
                    fi
                    current_target_ignore_files+=("$2")
                else
                    default_ignore_files+=("$2")
                fi
                shift
                ;;
            -*)
                fatal "Unknown option: %s" "$1"
                ;;
            *)
                # Positional directory
                positional_dirs+=("$1")
                has_positional=true
                ;;
        esac
        shift
    done
    
    # Finalize last target if in advanced mode
    if [[ "$in_target_block" == true ]]; then
        finalize_target
    fi
    
    # Validate mode consistency
    if [[ "$use_target_mode" == true ]] && [[ "$has_positional" == true ]]; then
        fatal "Cannot mix positional directories with --target mode"
    fi
    
    # Build target list based on mode
    if [[ "$use_target_mode" == true ]]; then
        # Advanced mode - targets already built
        if [[ "${#TARGET_DIRS[@]}" -eq 0 ]]; then
            fatal "At least one --target with --dir must be specified in target mode"
        fi
    else
        # Simple mode - build targets from positional directories
        if [[ "${#positional_dirs[@]}" -eq 0 ]]; then
            positional_dirs=(".")
        fi
        
        for dir in "${positional_dirs[@]}"; do
            TARGET_NAMES+=("")  # No name in simple mode
            TARGET_DIRS+=("$dir")
            
            # Serialize default types
            local types_str=""
            if [[ "${#default_types[@]}" -gt 0 ]]; then
                types_str=$(IFS='|'; echo "${default_types[*]}")
            fi
            TARGET_TYPES+=("$types_str")
            
            TARGET_MAX_DEPTHS+=("$default_max_depth")
            TARGET_MAX_FILESIZES+=("$default_max_filesize")
            
            # Serialize default ignore files
            local ignore_str=""
            if [[ "${#default_ignore_files[@]}" -gt 0 ]]; then
                ignore_str=$(IFS='|'; echo "${default_ignore_files[*]}")
            fi
            TARGET_IGNORE_FILES_SERIALIZED+=("$ignore_str")
        done
    fi
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
# Process a single target
function process_target {
    local dir="$1"
    local mode="$2"
    shift 2
    
    # Remaining arguments are: types_serialized max_depth max_filesize ignore_files_serialized
    local types_serialized="$1"
    local max_depth="$2"
    local max_filesize="$3"
    local ignore_files_serialized="$4"
    
    # Build filter options from target configuration
    local -a filter_options=()
    
    # Add types
    if [[ -n "$types_serialized" ]]; then
        IFS='|' read -ra types_array <<< "$types_serialized"
        for type in "${types_array[@]}"; do
            filter_options+=("--type" "$type")
        done
    fi
    
    # Add max-depth
    if [[ -n "$max_depth" ]]; then
        filter_options+=("--max-depth" "$max_depth")
    fi
    
    # Add max-filesize
    if [[ -n "$max_filesize" ]]; then
        filter_options+=("--max-filesize" "$max_filesize")
    fi
    
    # Parse ignore files
    local -a ignore_files=()
    if [[ -n "$ignore_files_serialized" ]]; then
        IFS='|' read -ra ignore_files <<< "$ignore_files_serialized"
    fi

    # Handle ripgrep configuration file
    # See: https://github.com/BurntSushi/ripgrep/blob/master/GUIDE.md#configuration-file
    local git_root
    git_root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n "$git_root" && -f "$git_root/.ripgreprc" ]]; then
        export RIPGREP_CONFIG_PATH="$git_root/.ripgreprc"
    else
        # Unset to avoid using config from previous target
        unset RIPGREP_CONFIG_PATH
    fi

    # Handle ignore files based on new logic
    if [[ "${#ignore_files[@]}" -gt 0 ]]; then
        # When the caller provides --ignore-file flags, only those files define the view.
        for ignore_file in "${ignore_files[@]}"; do
            local normalized_ignore_file="$ignore_file"
            if [[ "$normalized_ignore_file" != /* ]]; then
                normalized_ignore_file="$ORIG_CWD/$normalized_ignore_file"
            fi
            filter_options+=("--ignore-file" "$normalized_ignore_file")
        done
    else
        # Default view: check directory-local .promptignore, then fall back to the git root.
        if [[ -f "$dir/.promptignore" ]]; then
            filter_options+=("--ignore-file" "$dir/.promptignore")
        else
            # Try to find git root and check for .promptignore there
            if [[ -n "$git_root" && -f "$git_root/.promptignore" ]]; then
                filter_options+=("--ignore-file" "$git_root/.promptignore")
            fi
        fi
    fi

    case "$mode" in
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
} # End of function process_target

# Main function to orchestrate processing of all targets
function main {
    local mode="$1"
    
    # Handle help mode
    if [[ "$mode" == "help" ]]; then
        usage
        log ""
        log "Maintainer: $Maintainer - Version: $Version"
        exit 0
    fi
    
    # Process each target
    local num_targets="${#TARGET_DIRS[@]}"
    local i
    for ((i=0; i<num_targets; i++)); do
        local target_dir="${TARGET_DIRS[$i]}"
        local types_serialized="${TARGET_TYPES[$i]}"
        local max_depth="${TARGET_MAX_DEPTHS[$i]}"
        local max_filesize="${TARGET_MAX_FILESIZES[$i]}"
        local ignore_files_serialized="${TARGET_IGNORE_FILES_SERIALIZED[$i]}"
        
        # Add separator between targets if there are multiple
        if [[ "$i" -gt 0 ]]; then
            printf '\n'
        fi
        
        process_target "$target_dir" "$mode" "$types_serialized" "$max_depth" "$max_filesize" "$ignore_files_serialized"
    done
} # End of function main

# Main execution
if [ "$0" = "${BASH_SOURCE:-$0}" ]; then
    check_dependencies "${DEPENDENCIES[@]}"
    parse_arguments "$@"
    
    # Handle output redirection if --output was specified
    if [[ -n "$PARSED_OUTPUT_FILE" ]]; then
        # Redirect stdout to the output file and execute main
        main "$PARSED_MODE" > "$PARSED_OUTPUT_FILE"
    else
        # Output to stdout as usual
        main "$PARSED_MODE"
    fi
fi
