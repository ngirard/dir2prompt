#!/usr/bin/env bash
# Bash script to create a snapshot of a directory's structure and contents for LLM prompts.

# Usage function to display help message
function usage {
    cat <<-EoN
    Usage: ${PROGRAM} [OPTIONS] [DIRECTORY...]
           ${PROGRAM} [GLOBAL_OPTIONS] --target NAME --dir PATH [TARGET_OPTIONS]...
           ${PROGRAM} rules <add|list|show|init> [...]
	
	Global Options:
	  --contents-only        Display only the contents of non-binary files.
	  --help                 Display this help message.
      --manifest[=MODE]      Emit a manifest section (modes: summary, full).
      --output <FILE>        Write output to FILE instead of stdout.
	  --tree-only            Display only the directory tree.
	
	Target Options (can be global defaults or per-target):
	  --ignore-file <FILE>   Repeatable. Use custom ignore file(s) and skip automatic .promptignore detection.
	                         Relative paths are resolved from the directory where dir2prompt is invoked.
	  --max-depth <NUM>      Limit the depth of directory traversal.
	  --max-filesize <NUM>   Ignore files larger than NUM in size.
	  --type <TYPE>          Limit search to files matching the given type.
      --view <NAME>          Select a configured view to seed rule selection.
      --add-rule <NAME>      Repeatable. Layer additional named rules on top of the view.
      --drop-rule <NAME>     Repeatable. Remove named rules from the selected view.
      --add-rule-file <FILE> Repeatable. Load ephemeral gitignore rules from FILE.
      --follow-symlinks      Follow symlinks while traversing.
      --no-follow-symlinks   Do not follow symlinks (overrides follow).
	
	Simple Multi-Directory Mode:
	  dir2prompt [OPTIONS] dir1 dir2 dir3
	  All directories share the same target options.
	
	Advanced Per-Target Mode:
	  dir2prompt --target name1 --dir path1 [TARGET_OPTIONS] --target name2 --dir path2 [TARGET_OPTIONS]
	  Each target can have its own configuration.
	  Global target options before the first --target become defaults.
	
    Key Concepts:
      RULE: A named set of gitignore-style patterns (include/exclude) stored in 
            .dir2prompt/rules/<name>.ignore. Rules are reusable building blocks.
            
      VIEW: A named combination of multiple rules that creates a specific repository
            snapshot perspective (e.g., 'docs-only', 'backend-logic', 'full-context').
            Views are defined in .dir2prompt/views.yml.
    
    File Selection Precedence (most specific to least specific):
      1. CLI flags (--ignore-file, --add-rule, --drop-rule, --add-rule-file)
      2. Selected view (--view NAME) or default view (if configured)
      3. .promptignore file (in target directory or git root)
      4. fd's built-in ignores (.gitignore, .ignore, etc.)
      
      Note: CLI flags override view selections, enabling progressive refinement.

    Notes:
      - If no directory is specified, the current directory is used.
      - Cannot mix positional directories with --target mode.
      - Use '${PROGRAM} rules init' to bootstrap configuration for your first time.

    Subcommands:
      rules add <RULE> [OPTIONS]   Create or update .dir2prompt rules and optional views.
      rules list                   Show a summary of configured rules and views.
      rules show <RULE>            Display the gitignore patterns for a rule.
      rules init                   Initialize .dir2prompt configuration with examples.
      
    Use '${PROGRAM} rules --help' for detailed information about the rules subcommand.
EoN
} # End of function usage

# Help for the rules subcommand
function rules_usage {
    cat <<-'EoN'
	Usage: dir2prompt rules <SUBCOMMAND> [OPTIONS]
	
	The rules system allows you to create reusable, composable file selection profiles
	for your repository snapshots. This is more powerful and maintainable than ad-hoc
	filtering with --ignore-file or --type flags.
	
	Key Concepts:
	  RULE  - A named set of gitignore-style patterns (include/exclude) stored in 
	          .dir2prompt/rules/<name>.ignore. Rules are the building blocks.
	          
	  VIEW  - A named combination of multiple rules that creates a specific snapshot
	          perspective (e.g., 'docs-only', 'backend-logic', 'full-context').
	          Views are defined in .dir2prompt/views.yml.
	
	Configuration Location:
	  All configuration lives in .dir2prompt/ at your project root:
	    .dir2prompt/views.yml           - Defines views and their rule combinations
	    .dir2prompt/rules/*.ignore      - Individual rule files (gitignore syntax)
	
	Subcommands:
	  init                Initialize .dir2prompt with a working example configuration
	  add <RULE>          Create or update a rule (and optionally attach to a view)
	  list                Display all configured rules and views
	  show <RULE>         Print the gitignore patterns for a specific rule
	
	Selection Precedence (most specific to least specific):
	  1. CLI flags (--ignore-file, --add-rule, --drop-rule, --add-rule-file)
	  2. Selected view (--view) or default view
	  3. .promptignore file (in target directory or git root)
	  4. fd's built-in ignores (.gitignore, .ignore, etc.)
	
	Examples:
	  # Start with a baseline configuration
	  dir2prompt rules init
	  
	  # Create a rule from your .gitignore and add to a 'default' view
	  dir2prompt rules add baseline --from-file .gitignore --view default
	  
	  # Create a docs-focused view
	  dir2prompt rules add docs-only --view docs --description "Documentation files only"
	  echo '!*.md' | dir2prompt rules add docs-include --view docs
	  
	  # Use a view to generate a snapshot
	  dir2prompt --view docs
	  
	  # Temporarily layer additional rules on top of a view
	  dir2prompt --view default --add-rule extra-excludes
	
	For detailed help on each subcommand:
	  dir2prompt rules add --help
	  dir2prompt rules list --help
	  dir2prompt rules show --help
	  dir2prompt rules init --help
EoN
}

# Help for rules add
function rules_add_usage {
    cat <<-'EoN'
	Usage: dir2prompt rules add <RULE_NAME> [OPTIONS]
	
	Create or update a rule file with gitignore-style patterns. Rules can be used
	independently or composed into views for reusable snapshot configurations.
	
	Arguments:
	  RULE_NAME              Name for the rule (alphanumeric, hyphens, underscores)
	
	Options:
	  --description <TEXT>   Human-readable description of the rule's purpose
	  --from-file <PATH>     Read patterns from a file instead of stdin
	  --view <VIEW_NAME>     Add this rule to the specified view (creates view if new)
	  --base-view <BASE>     When creating a view, inherit rules from BASE view first
	                         (requires --view)
	
	Input:
	  Patterns are gitignore-style:
	    pattern        - Exclude files matching pattern
	    !pattern       - Include (negate previous exclusions)
	    /pattern       - Match only at root level
	    dir/           - Match directories
	    *.ext          - Match by extension
	    **/pattern     - Match at any depth
	
	  If --from-file is provided, patterns are read from that file.
	  Otherwise, patterns are read from stdin until EOF.
	
	Output:
	  The rule is written to .dir2prompt/rules/<RULE_NAME>.ignore
	  If --view is specified, .dir2prompt/views.yml is updated.
	
	Examples:
	  # Create rule from existing .gitignore
	  dir2prompt rules add baseline --from-file .gitignore --description "Standard ignores"
	  
	  # Create rule from stdin
	  echo -e '*.log\n*.tmp\nbuild/' | dir2prompt rules add temp-files
	  
	  # Create rule and add to a view
	  dir2prompt rules add docs-only --view documentation --description "Docs snapshot"
	  
	  # Create a view that extends another
	  dir2prompt rules add extra --view extended --base-view default --description "Default + extra"
	  
	  # Update existing rule (preserves description unless --description given)
	  cat new-patterns.txt | dir2prompt rules add baseline
EoN
}

# Help for rules list
function rules_list_usage {
    cat <<-'EoN'
	Usage: dir2prompt rules list
	
	Display a summary of all configured rules and views in the current repository.
	
	Output includes:
	  - All defined rules with their file paths and descriptions
	  - All defined views with their descriptions and associated rules
	
	If no configuration exists, guidance is provided on how to create your first rule.
	
	Examples:
	  dir2prompt rules list
EoN
}

# Help for rules show
function rules_show_usage {
    cat <<-'EoN'
	Usage: dir2prompt rules show <RULE_NAME>
	
	Display the gitignore-style patterns contained in a specific rule.
	
	Arguments:
	  RULE_NAME              Name of the rule to display
	
	Output:
	  Prints the rule name, file path, and complete contents of the rule file.
	
	Examples:
	  dir2prompt rules show baseline
	  dir2prompt rules show docs-only
EoN
}

# Help for rules init
function rules_init_usage {
    cat <<-'EoN'
	Usage: dir2prompt rules init [OPTIONS]
	
	Initialize a .dir2prompt configuration directory with example rules and views.
	This provides a working starting point for creating tailored repository snapshots.
	
	Options:
	  --from-gitignore       Create baseline rule from .gitignore (if present)
	  --minimal              Create minimal configuration (no example rules)
	
	What gets created:
	  .dir2prompt/                    - Configuration directory
	  .dir2prompt/views.yml           - View definitions file
	  .dir2prompt/rules/baseline.ignore - Example baseline rule
	
	If --from-gitignore is specified and .gitignore exists, the baseline rule will
	be populated with your existing .gitignore patterns. Otherwise, sensible defaults
	are provided.
	
	Examples:
	  # Initialize with example configuration
	  dir2prompt rules init
	  
	  # Initialize using existing .gitignore
	  dir2prompt rules init --from-gitignore
	  
	  # Create minimal configuration
	  dir2prompt rules init --minimal
EoN
}


# Unofficial bash Strict Mode?
set -euo pipefail

# ——————————
# Globals and constants
PROGRAM=${0##*/}
Maintainer="${MAINTAINER}"
Version="v${VERSION} (${RELEASE_DATE})"

DEPENDENCIES=('rg' 'tree' 'fd')

# Error messages
ERROR_MISSING_DEP="Required dependency '%s' not found. Please install it (note: some distributions package fd as 'fd-find') and try again."

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
# Configuration state (Phase 2)
LIST_SEPARATOR=$'\x1f'

declare -gA DIR2PROMPT_CONFIG_CACHE=()
declare -gA DIR2PROMPT_PROJECT_ROOT=()
declare -gA DIR2PROMPT_RULE_FILES=()
declare -gA DIR2PROMPT_RULE_DESCRIPTIONS=()
declare -gA DIR2PROMPT_RULE_INCLUDES=()
declare -gA DIR2PROMPT_RULE_EXCLUDES=()
declare -gA DIR2PROMPT_RULE_ORDERS=()
declare -gA DIR2PROMPT_VIEW_DESCRIPTIONS=()
declare -gA DIR2PROMPT_VIEW_RULES=()
declare -gA DIR2PROMPT_VIEW_SYMLINKS=()
declare -gA DIR2PROMPT_VIEW_MAX_DEPTH=()
declare -gA DIR2PROMPT_VIEW_MAX_FILESIZE=()
declare -gA DIR2PROMPT_VIEW_ORDERS=()
declare -gA DIR2PROMPT_BASELINE_VIEW=()
declare -gA DIR2PROMPT_CONFIG_DUMPED=()
declare -gA DIR2PROMPT_LAST_SELECTION_META=()

function trim_whitespace {
    local value="$1"
    value="${value#${value%%[![:space:]]*}}"
    value="${value%${value##*[![:space:]]}}"
    printf '%s' "$value"
}

function strip_surrounding_quotes {
    local value="$1"
    local length=${#value}
    if (( length >= 2 )); then
        local first="${value:0:1}"
        local last_index=$((length - 1))
        local last="${value:last_index:1}"
        if [[ ( "$first" == '"' && "$last" == '"' ) || ( "$first" == "'" && "$last" == "'" ) ]]; then
            local inner_length=$((length - 2))
            value="${value:1:inner_length}"
        fi
    fi
    printf '%s' "$value"
}

function append_to_assoc_list {
    local -n assoc_ref="$1"
    local key="$2"
    local value="$3"
    local existing="${assoc_ref[$key]:-}"
    if [[ -z "$existing" ]]; then
        assoc_ref["$key"]="$value"
    else
        assoc_ref["$key"]="$existing$LIST_SEPARATOR$value"
    fi
}

function serialize_array {
    local -n arr_ref="$1"
    if [[ "${#arr_ref[@]}" -eq 0 ]]; then
        printf ''
    else
        local IFS="$LIST_SEPARATOR"
        printf '%s' "${arr_ref[*]}"
    fi
}

function humanize_serialized_list {
    local serialized="$1"
    if [[ -z "$serialized" ]]; then
        printf ''
        return
    fi
    local delim="$LIST_SEPARATOR"
    local output="${serialized//$delim/, }"
    printf '%s' "$output"
}

function deserialize_serialized_list {
    local serialized="$1"
    local -n out_ref="$2"
    out_ref=()
    if [[ -z "$serialized" ]]; then
        return
    fi
    local delim="$LIST_SEPARATOR"
    IFS="$delim" read -ra out_ref <<< "$serialized"
    : "${out_ref[@]+_}"
}

function dir2prompt_detect_config_dir {
    local target_dir="$1"
    local candidate="$target_dir/.dir2prompt"
    if [[ -d "$candidate" ]]; then
        (cd "$candidate" && pwd)
        return 0
    fi
    local git_root
    git_root=$(git -C "$target_dir" rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n "$git_root" ]]; then
        candidate="$git_root/.dir2prompt"
        if [[ -d "$candidate" ]]; then
            (cd "$candidate" && pwd)
            return 0
        fi
    fi
    return 1
}

function dir2prompt_find_views_file {
    local config_dir="$1"
    if [[ -f "$config_dir/views.yml" ]]; then
        printf '%s\n' "$config_dir/views.yml"
        return 0
    fi
    if [[ -f "$config_dir/views.yaml" ]]; then
        printf '%s\n' "$config_dir/views.yaml"
        return 0
    fi
    return 1
}

function parse_gitignore_rule_file {
    local rule_path="$1"
    local -n includes_ref="$2"
    local -n excludes_ref="$3"

    includes_ref=()
    excludes_ref=()

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        local line="${raw_line%$'\r'}"
        local trimmed
        trimmed=$(trim_whitespace "$line")
        if [[ -z "$trimmed" ]]; then
            continue
        fi
        if [[ "${trimmed:0:1}" == '#' ]]; then
            continue
        fi
        if [[ "${trimmed:0:1}" == '!' ]]; then
            includes_ref+=("${trimmed:1}")
        else
            excludes_ref+=("$trimmed")
        fi
    done < "$rule_path"
}

function parse_ripgreprc_file {
    local config_file="$1"
    local -n include_ref="$2"
    local -n exclude_ref="$3"
    local -n follow_ref="$4"

    include_ref=()
    exclude_ref=()
    follow_ref="inherit"

    if [[ ! -f "$config_file" ]]; then
        return
    fi

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        local line="${raw_line%$'\r'}"
        line=$(trim_whitespace "$line")
        if [[ -z "$line" ]]; then
            continue
        fi
        if [[ "${line:0:1}" == '#' ]]; then
            continue
        fi
        if [[ "$line" == --glob=* ]]; then
            local value="${line#--glob=}"
            value=$(strip_surrounding_quotes "$value")
            if [[ -z "$value" ]]; then
                continue
            fi
            if [[ "${value:0:1}" == '!' ]]; then
                exclude_ref+=("${value:1}")
            else
                include_ref+=("$value")
            fi
            continue
        fi
        if [[ "$line" == "--follow" ]]; then
            follow_ref="follow"
            continue
        fi
        if [[ "$line" == "--no-follow" ]]; then
            follow_ref="nofollow"
            continue
        fi
    done < "$config_file"
}

function load_rule_file_data {
    local config_dir="$1"
    local rule_name="$2"
    local rule_path="$3"
    local key="$config_dir::$rule_name"

    if [[ -n "${DIR2PROMPT_RULE_INCLUDES[$key]+x}" || -n "${DIR2PROMPT_RULE_EXCLUDES[$key]+x}" ]]; then
        return
    fi

    if [[ ! -f "$rule_path" ]]; then
        fatal "Rule '%s' file '%s' not found" "$rule_name" "$rule_path"
    fi

    local -a includes=()
    local -a excludes=()
    parse_gitignore_rule_file "$rule_path" includes excludes

    DIR2PROMPT_RULE_INCLUDES["$key"]="$(serialize_array includes)"
    DIR2PROMPT_RULE_EXCLUDES["$key"]="$(serialize_array excludes)"
}

function parse_views_yaml_file {
    local config_dir="$1"
    local yaml_file="$2"
    local project_root="$3"

    local current_section=""
    local current_rule=""
    local current_view=""
    local view_rules_open=false
    local -a view_rules_buffer=()

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        local line="${raw_line//$'\t'/    }"
        line="${line%$'\r'}"
        local leading="${line%%[! ]*}"
        local indent=${#leading}
        local content="${line:indent}"
        content=$(trim_whitespace "$content")
        if [[ -z "$content" ]]; then
            continue
        fi
        if [[ "${content:0:1}" == '#' ]]; then
            continue
        fi

        if (( indent <= 4 )) && [[ "$view_rules_open" == true ]]; then
            DIR2PROMPT_VIEW_RULES["$config_dir::$current_view"]="$(serialize_array view_rules_buffer)"
            view_rules_buffer=()
            view_rules_open=false
        fi

        if (( indent == 0 )); then
            if [[ "$content" == "rules:" ]]; then
                current_section="rules"
                current_rule=""
                current_view=""
            elif [[ "$content" == "views:" ]]; then
                current_section="views"
                current_rule=""
                current_view=""
            else
                fatal "Unsupported top-level key '%s' in %s" "$content" "$yaml_file"
            fi
            continue
        fi

        case "$current_section" in
            rules)
                if (( indent == 2 )); then
                    current_rule="${content%:}"
                    current_rule=$(trim_whitespace "$current_rule")
                    if [[ -z "$current_rule" ]]; then
                        fatal "Invalid rule name near '%s'" "$content"
                    fi
                    append_to_assoc_list DIR2PROMPT_RULE_ORDERS "$config_dir" "$current_rule"
                    DIR2PROMPT_RULE_DESCRIPTIONS["$config_dir::$current_rule"]=""
                    DIR2PROMPT_RULE_FILES["$config_dir::$current_rule"]=""
                    continue
                fi
                if (( indent == 4 )); then
                    if [[ -z "$current_rule" ]]; then
                        fatal "Rule property '%s' defined before rule name" "$content"
                    fi
                    local key_part="${content%%:*}"
                    local value_part="${content#*:}"
                    key_part=$(trim_whitespace "$key_part")
                    value_part=$(trim_whitespace "$value_part")
                    value_part=$(strip_surrounding_quotes "$value_part")
                    case "$key_part" in
                        file)
                            if [[ -z "$value_part" ]]; then
                                fatal "Rule '%s' must define a file path" "$current_rule"
                            fi
                            if [[ "$value_part" == /* ]]; then
                                DIR2PROMPT_RULE_FILES["$config_dir::$current_rule"]="$value_part"
                            else
                                DIR2PROMPT_RULE_FILES["$config_dir::$current_rule"]="$project_root/$value_part"
                            fi
                            ;;
                        description)
                            DIR2PROMPT_RULE_DESCRIPTIONS["$config_dir::$current_rule"]="$value_part"
                            ;;
                        *)
                            fatal "Unknown rule key '%s' in %s" "$key_part" "$yaml_file"
                            ;;
                    esac
                    continue
                fi
                ;;
            views)
                if (( indent == 2 )); then
                    current_view="${content%:}"
                    current_view=$(trim_whitespace "$current_view")
                    if [[ -z "$current_view" ]]; then
                        fatal "Invalid view name near '%s'" "$content"
                    fi
                    append_to_assoc_list DIR2PROMPT_VIEW_ORDERS "$config_dir" "$current_view"
                    DIR2PROMPT_VIEW_DESCRIPTIONS["$config_dir::$current_view"]=""
                    DIR2PROMPT_VIEW_RULES["$config_dir::$current_view"]=""
                    DIR2PROMPT_VIEW_SYMLINKS["$config_dir::$current_view"]=""
                    DIR2PROMPT_VIEW_MAX_DEPTH["$config_dir::$current_view"]=""
                    DIR2PROMPT_VIEW_MAX_FILESIZE["$config_dir::$current_view"]=""
                    continue
                fi
                if (( indent == 4 )); then
                    if [[ -z "$current_view" ]]; then
                        fatal "View property '%s' defined before view name" "$content"
                    fi
                    local key_part="${content%%:*}"
                    local value_part="${content#*:}"
                    key_part=$(trim_whitespace "$key_part")
                    value_part=$(trim_whitespace "$value_part")
                    if [[ "$key_part" == rules ]]; then
                        value_part=$(strip_surrounding_quotes "$value_part")
                        if [[ -z "$value_part" ]]; then
                            view_rules_open=true
                            view_rules_buffer=()
                        elif [[ "$value_part" == "[]" ]]; then
                            DIR2PROMPT_VIEW_RULES["$config_dir::$current_view"]=""
                        elif [[ "$value_part" =~ ^\[(.*)\]$ ]]; then
                            local inner="${BASH_REMATCH[1]}"
                            inner=$(trim_whitespace "$inner")
                            if [[ -z "$inner" ]]; then
                                DIR2PROMPT_VIEW_RULES["$config_dir::$current_view"]=""
                            else
                                local -a inline_rules=()
                                IFS=',' read -ra inline_rules <<< "$inner"
                                local -a cleaned=()
                                local item
                                for item in "${inline_rules[@]}"; do
                                    item=$(trim_whitespace "$item")
                                    item=$(strip_surrounding_quotes "$item")
                                    if [[ -n "$item" ]]; then
                                        cleaned+=("$item")
                                    fi
                                done
                                DIR2PROMPT_VIEW_RULES["$config_dir::$current_view"]="$(serialize_array cleaned)"
                            fi
                        else
                            DIR2PROMPT_VIEW_RULES["$config_dir::$current_view"]="$value_part"
                        fi
                        continue
                    fi
                    value_part=$(strip_surrounding_quotes "$value_part")
                    case "$key_part" in
                        description)
                            DIR2PROMPT_VIEW_DESCRIPTIONS["$config_dir::$current_view"]="$value_part"
                            ;;
                        follow_symlinks)
                            local lowered="${value_part,,}"
                            case "$lowered" in
                                true|false)
                                    DIR2PROMPT_VIEW_SYMLINKS["$config_dir::$current_view"]="$lowered"
                                    ;;
                                *)
                                    fatal "follow_symlinks must be true or false in view '%s'" "$current_view"
                                    ;;
                            esac
                            ;;
                        max_depth)
                            if [[ -n "$value_part" && ! "$value_part" =~ ^[0-9]+$ ]]; then
                                fatal "max_depth for view '%s' must be numeric" "$current_view"
                            fi
                            DIR2PROMPT_VIEW_MAX_DEPTH["$config_dir::$current_view"]="$value_part"
                            ;;
                        max_filesize)
                            if [[ -n "$value_part" && ! "$value_part" =~ ^[0-9]+$ ]]; then
                                fatal "max_filesize for view '%s' must be numeric (bytes)" "$current_view"
                            fi
                            DIR2PROMPT_VIEW_MAX_FILESIZE["$config_dir::$current_view"]="$value_part"
                            ;;
                        *)
                            fatal "Unknown view key '%s' in %s" "$key_part" "$yaml_file"
                            ;;
                    esac
                    continue
                fi
                if (( indent >= 6 )) && [[ "$view_rules_open" == true ]]; then
                    if [[ "${content:0:1}" != '-' ]]; then
                        fatal "Expected list item under rules for view '%s'" "$current_view"
                    fi
                    local item="${content#-}"
                    item=$(trim_whitespace "$item")
                    item=$(strip_surrounding_quotes "$item")
                    if [[ -n "$item" ]]; then
                        view_rules_buffer+=("$item")
                    fi
                    continue
                fi
                ;;
            *)
                fatal "No active section when parsing %s" "$yaml_file"
                ;;
        esac
    done < "$yaml_file"

    if [[ "$view_rules_open" == true ]]; then
        DIR2PROMPT_VIEW_RULES["$config_dir::$current_view"]="$(serialize_array view_rules_buffer)"
    fi

    local view_order="${DIR2PROMPT_VIEW_ORDERS[$config_dir]:-}"
    if [[ -n "$view_order" ]]; then
        local delim="$LIST_SEPARATOR"
        IFS="$delim" read -ra view_names <<< "$view_order"
        local view_name
        for view_name in "${view_names[@]}"; do
            local key="$config_dir::$view_name"
            local rules_serialized="${DIR2PROMPT_VIEW_RULES[$key]:-}"
            if [[ -n "$rules_serialized" ]]; then
                IFS="$delim" read -ra rule_names <<< "$rules_serialized"
                local rule_name
                for rule_name in "${rule_names[@]}"; do
                    if [[ -z "${DIR2PROMPT_RULE_FILES["$config_dir::$rule_name"]+x}" ]]; then
                        fatal "View '%s' references unknown rule '%s'" "$view_name" "$rule_name"
                    fi
                done
            fi
        done
    fi

    local rule_order="${DIR2PROMPT_RULE_ORDERS[$config_dir]:-}"
    if [[ -n "$rule_order" ]]; then
        local delim="$LIST_SEPARATOR"
        IFS="$delim" read -ra rule_names <<< "$rule_order"
        local rule_name
        for rule_name in "${rule_names[@]}"; do
            local rule_path="${DIR2PROMPT_RULE_FILES["$config_dir::$rule_name"]}"
            if [[ -z "$rule_path" ]]; then
                fatal "Rule '%s' is missing a file path" "$rule_name"
            fi
            load_rule_file_data "$config_dir" "$rule_name" "$rule_path"
        done
    fi

    if [[ -n "${DIR2PROMPT_VIEW_RULES["$config_dir::default"]+x}" ]]; then
        DIR2PROMPT_BASELINE_VIEW["$config_dir"]="default"
    else
        DIR2PROMPT_BASELINE_VIEW["$config_dir"]=""
    fi

    DIR2PROMPT_PROJECT_ROOT["$config_dir"]="$project_root"
}

function ensure_dir2prompt_config_loaded {
    local target_dir="$1"
    local __result_var="$2"
    local detected_config_dir
    if ! detected_config_dir=$(dir2prompt_detect_config_dir "$target_dir"); then
        return 1
    fi
    local status="${DIR2PROMPT_CONFIG_CACHE[$detected_config_dir]:-}"
    if [[ -z "$status" ]]; then
        local views_file
        if ! views_file=$(dir2prompt_find_views_file "$detected_config_dir"); then
            DIR2PROMPT_CONFIG_CACHE["$detected_config_dir"]="none"
            return 1
        fi
        local project_root
        project_root=$(cd "$detected_config_dir/.." && pwd)
        parse_views_yaml_file "$detected_config_dir" "$views_file" "$project_root"
        DIR2PROMPT_CONFIG_CACHE["$detected_config_dir"]="loaded"
        status="loaded"
    fi
    if [[ "$status" != "loaded" ]]; then
        return 1
    fi
    printf -v "$__result_var" '%s' "$detected_config_dir"
    return 0
}

function maybe_dump_configuration {
    local config_dir="$1"
    if [[ "${DIR2PROMPT_DEBUG_CONFIG_DUMP:-}" != "1" ]]; then
        return
    fi
    if [[ -n "${DIR2PROMPT_CONFIG_DUMPED[$config_dir]+x}" ]]; then
        return
    fi
    DIR2PROMPT_CONFIG_DUMPED["$config_dir"]=1
    local project_root="${DIR2PROMPT_PROJECT_ROOT[$config_dir]}"
    printf '[[DIR2PROMPT-CONFIG dir="%s"]]\n' "$project_root"
    printf 'baseline_view=%s\n' "${DIR2PROMPT_BASELINE_VIEW[$config_dir]:-}"

    local view_order="${DIR2PROMPT_VIEW_ORDERS[$config_dir]:-}"
    if [[ -n "$view_order" ]]; then
        local delim="$LIST_SEPARATOR"
        IFS="$delim" read -ra view_names <<< "$view_order"
        local view_name
        for view_name in "${view_names[@]}"; do
            local key="$config_dir::$view_name"
            printf 'VIEW %s\n' "$view_name"
            printf '  description=%s\n' "${DIR2PROMPT_VIEW_DESCRIPTIONS[$key]:-}"
            printf '  rules=%s\n' "$(humanize_serialized_list "${DIR2PROMPT_VIEW_RULES[$key]:-}")"
            printf '  follow_symlinks=%s\n' "${DIR2PROMPT_VIEW_SYMLINKS[$key]:-}"
            printf '  max_depth=%s\n' "${DIR2PROMPT_VIEW_MAX_DEPTH[$key]:-}"
            printf '  max_filesize=%s\n' "${DIR2PROMPT_VIEW_MAX_FILESIZE[$key]:-}"
        done
    fi

    local rule_order="${DIR2PROMPT_RULE_ORDERS[$config_dir]:-}"
    if [[ -n "$rule_order" ]]; then
        local delim="$LIST_SEPARATOR"
        IFS="$delim" read -ra rule_names <<< "$rule_order"
        local rule_name
        for rule_name in "${rule_names[@]}"; do
            local key="$config_dir::$rule_name"
            printf 'RULE %s\n' "$rule_name"
            printf '  file=%s\n' "${DIR2PROMPT_RULE_FILES[$key]}"
            printf '  description=%s\n' "${DIR2PROMPT_RULE_DESCRIPTIONS[$key]:-}"
            printf '  includes=%s\n' "$(humanize_serialized_list "${DIR2PROMPT_RULE_INCLUDES[$key]:-}")"
            printf '  excludes=%s\n' "$(humanize_serialized_list "${DIR2PROMPT_RULE_EXCLUDES[$key]:-}")"
        done
    fi

    printf '[[/DIR2PROMPT-CONFIG]]\n'
}

# ——————————
# Selection helpers (Phase 5)

function gitignore_pattern_to_regex {
    local pattern="$1"
    local anchored=false
    local directory_only=false

    if [[ "$pattern" == /* ]]; then
        anchored=true
        pattern="${pattern#/}"
    fi

    if [[ "$pattern" == */ ]]; then
        directory_only=true
        pattern="${pattern%/}"
    fi

    local regex=""
    local length=${#pattern}
    local i=0
    while (( i < length )); do
        local char="${pattern:i:1}"
        if [[ "$char" == '*' ]]; then
            if (( i + 1 < length )) && [[ "${pattern:i:2}" == "**" ]]; then
                local next_index=$((i + 2))
                local next_char=""
                if (( next_index < length )); then
                    next_char="${pattern:next_index:1}"
                fi
                if [[ "$next_char" == '/' ]]; then
                    regex+='(.*/)?'
                    i=$((i + 3))
                else
                    regex+='.*'
                    i=$((i + 2))
                fi
                continue
            fi
            regex+='[^/]*'
            ((i++))
            continue
        fi
        if [[ "$char" == '?' ]]; then
            regex+='[^/]'
            ((i++))
            continue
        fi
        if [[ "$char" == '/' ]]; then
            regex+='/'
            ((i++))
            continue
        fi
        if [[ "$char" =~ [\\.^$+?()|{}\[\]] ]]; then
            regex+="\\$char"
        else
            regex+="$char"
        fi
        ((i++))
    done

    if [[ "$directory_only" == true ]]; then
        if [[ "$anchored" == true ]]; then
            printf '^%s(/.*)?$' "$regex"
        else
            printf '(^|.*/)%s(/.*)?$' "$regex"
        fi
        return
    fi

    if [[ "$anchored" == true ]]; then
        printf '^%s$' "$regex"
    else
        printf '(^|.*/)%s$' "$regex"
    fi
}

function build_regex_array {
    local -n __out_ref="$1"
    shift
    __out_ref=()
    local pattern
    for pattern in "$@"; do
        if [[ -z "$pattern" ]]; then
            continue
        fi
        __out_ref+=("$(gitignore_pattern_to_regex "$pattern")")
    done
}

function path_matches_any_regex {
    local path="$1"
    local -n __regex_ref="$2"
    local regex
    for regex in "${__regex_ref[@]}"; do
        if [[ -z "$regex" ]]; then
            continue
        fi
        if [[ "$path" =~ $regex ]]; then
            return 0
        fi
    done
    return 1
}

function enumerate_universe_with_fd {
    local dir="$1"
    local types_serialized="$2"
    local max_depth="$3"
    local max_filesize="$4"
    local active_ignore_serialized="$5"
    local follow_symlinks="$6"

    local -a types_array=()
    if [[ -n "$types_serialized" ]]; then
        IFS='|' read -ra types_array <<< "$types_serialized"
    fi

    local -a active_ignore_files=()
    if [[ -n "$active_ignore_serialized" ]]; then
        IFS='|' read -ra active_ignore_files <<< "$active_ignore_serialized"
    fi

    (
        cd "$dir" || fatal "Failed to cd into directory '%s'" "$dir"
        local -a fd_cmd=("fd" "--strip-cwd-prefix" "--color" "never" "--type" "f")
        if [[ "$follow_symlinks" == "true" ]]; then
            fd_cmd+=("--follow")
        fi
        if [[ -n "$max_depth" ]]; then
            fd_cmd+=("--max-depth" "$max_depth")
        fi
        if [[ -n "$max_filesize" ]]; then
            local normalized_size="${max_filesize,,}"
            if [[ "$normalized_size" =~ ^[0-9]+$ ]]; then
                normalized_size="${normalized_size}b"
            fi
            fd_cmd+=("--size" "-$normalized_size")
        fi
        if [[ "${#types_array[@]}" -gt 0 ]]; then
            local type
            for type in "${types_array[@]}"; do
                fd_cmd+=("--extension" "$type")
            done
        fi
        if [[ "${#active_ignore_files[@]}" -gt 0 ]]; then
            local ignore_file
            for ignore_file in "${active_ignore_files[@]}"; do
                fd_cmd+=("--ignore-file" "$ignore_file")
            done
        fi
        "${fd_cmd[@]}" | LC_ALL=C sort
    )
}

function build_final_selection {
    local -n __selection_ref="$1"
    shift
    local dir="$1"
    local types_serialized="$2"
    local cli_max_depth="$3"
    local cli_max_filesize="$4"
    local active_ignore_serialized="$5"
    local baseline_ignore_serialized="$6"
    local config_dir="$7"
    local requested_view="$8"
    local add_rules_serialized="$9"
    local drop_rules_serialized="${10}"
    local add_rule_files_serialized="${11}"
    local symlink_behavior="${12}"
    local ripgreprc_include_serialized="${13}"
    local ripgreprc_exclude_serialized="${14}"
    local ripgreprc_follow="${15}"

    DIR2PROMPT_LAST_SELECTION_META=()
    local baseline_view=""
    if [[ -n "$config_dir" ]]; then
        baseline_view="${DIR2PROMPT_BASELINE_VIEW[$config_dir]:-}"
    fi

    local resolved_view=""
    local view_source="none"
    if [[ -n "$requested_view" ]]; then
        if [[ -z "$config_dir" ]]; then
            fatal "View '%s' requested but no .dir2prompt configuration found for target '%s'" "$requested_view" "$dir"
        fi
        resolved_view="$requested_view"
        view_source="cli"
    elif [[ -n "$config_dir" ]]; then
        resolved_view="${DIR2PROMPT_BASELINE_VIEW[$config_dir]:-}"
        if [[ -n "$resolved_view" ]]; then
            view_source="baseline"
        fi
    fi

    local view_key=""
    local -a active_rules=()
    local view_follow=""
    local view_max_depth=""
    local view_max_filesize=""
    if [[ -n "$resolved_view" ]]; then
        view_key="$config_dir::$resolved_view"
        if [[ -z "${DIR2PROMPT_VIEW_RULES[$view_key]+x}" ]]; then
            fatal "View '%s' is not defined for target '%s'" "$resolved_view" "$dir"
        fi
        local rules_serialized="${DIR2PROMPT_VIEW_RULES[$view_key]:-}"
        if [[ -n "$rules_serialized" ]]; then
            deserialize_serialized_list "$rules_serialized" active_rules
        else
            active_rules=()
        fi
        view_follow="${DIR2PROMPT_VIEW_SYMLINKS[$view_key]:-}"
        view_max_depth="${DIR2PROMPT_VIEW_MAX_DEPTH[$view_key]:-}"
        view_max_filesize="${DIR2PROMPT_VIEW_MAX_FILESIZE[$view_key]:-}"
    fi

    local -a drop_rules=()
    if [[ -n "$drop_rules_serialized" ]]; then
        IFS='|' read -ra drop_rules <<< "$drop_rules_serialized"
    fi
    if [[ "${#drop_rules[@]}" -gt 0 ]]; then
        if [[ -z "$config_dir" ]]; then
            fatal "--drop-rule requires .dir2prompt configuration (target '%s')" "$dir"
        fi
        local drop
        for drop in "${drop_rules[@]}"; do
            if [[ -z "${DIR2PROMPT_RULE_FILES[$config_dir::$drop]+x}" ]]; then
                fatal "Rule '%s' referenced by --drop-rule is not defined for target '%s'" "$drop" "$dir"
            fi
            local -a filtered=()
            local rule_name
            for rule_name in "${active_rules[@]}"; do
                if [[ "$rule_name" != "$drop" ]]; then
                    filtered+=("$rule_name")
                fi
            done
            active_rules=("${filtered[@]}")
        done
    fi

    local -a add_rules=()
    if [[ -n "$add_rules_serialized" ]]; then
        IFS='|' read -ra add_rules <<< "$add_rules_serialized"
    fi
    if [[ "${#add_rules[@]}" -gt 0 ]]; then
        if [[ -z "$config_dir" ]]; then
            fatal "--add-rule requires .dir2prompt configuration (target '%s')" "$dir"
        fi
        local add
        for add in "${add_rules[@]}"; do
            if [[ -z "${DIR2PROMPT_RULE_FILES[$config_dir::$add]+x}" ]]; then
                fatal "Rule '%s' referenced by --add-rule is not defined for target '%s'" "$add" "$dir"
            fi
            local exists=false
            local existing
            for existing in "${active_rules[@]}"; do
                if [[ "$existing" == "$add" ]]; then
                    exists=true
                    break
                fi
            done
            if [[ "$exists" == false ]]; then
                active_rules+=("$add")
            fi
        done
    fi

    local -a include_patterns=()
    local -a exclude_patterns=()
    if [[ -n "$config_dir" ]]; then
        local rule_name
        for rule_name in "${active_rules[@]}"; do
            local rule_key="$config_dir::$rule_name"
            local includes_serialized="${DIR2PROMPT_RULE_INCLUDES[$rule_key]:-}"
            local excludes_serialized="${DIR2PROMPT_RULE_EXCLUDES[$rule_key]:-}"
            if [[ -n "$includes_serialized" ]]; then
                local -a tmp_includes=()
                deserialize_serialized_list "$includes_serialized" tmp_includes
                include_patterns+=("${tmp_includes[@]}")
            fi
            if [[ -n "$excludes_serialized" ]]; then
                local -a tmp_excludes=()
                deserialize_serialized_list "$excludes_serialized" tmp_excludes
                exclude_patterns+=("${tmp_excludes[@]}")
            fi
        done
    fi

    local -a add_rule_files=()
    if [[ -n "$add_rule_files_serialized" ]]; then
        IFS='|' read -ra add_rule_files <<< "$add_rule_files_serialized"
    fi
    local ephemeral_file
    for ephemeral_file in "${add_rule_files[@]}"; do
        if [[ -z "$ephemeral_file" ]]; then
            continue
        fi
        if [[ ! -f "$ephemeral_file" ]]; then
            fatal "Ephemeral rule file '%s' not found" "$ephemeral_file"
        fi
        local -a eph_includes=()
        local -a eph_excludes=()
        parse_gitignore_rule_file "$ephemeral_file" eph_includes eph_excludes
        include_patterns+=("${eph_includes[@]}")
        exclude_patterns+=("${eph_excludes[@]}")
    done

    if [[ -n "$ripgreprc_include_serialized" ]]; then
        local -a ripgreprc_includes=()
        IFS='|' read -ra ripgreprc_includes <<< "$ripgreprc_include_serialized"
        include_patterns+=("${ripgreprc_includes[@]}")
    fi
    if [[ -n "$ripgreprc_exclude_serialized" ]]; then
        local -a ripgreprc_excludes=()
        IFS='|' read -ra ripgreprc_excludes <<< "$ripgreprc_exclude_serialized"
        exclude_patterns+=("${ripgreprc_excludes[@]}")
    fi

    local manifest_enabled=false
    if [[ "${PARSED_MANIFEST_MODE:-off}" != "off" ]]; then
        manifest_enabled=true
    fi
    DIR2PROMPT_LAST_SELECTION_META=()

    local effective_max_depth="$cli_max_depth"
    if [[ -z "$effective_max_depth" && -n "$view_max_depth" ]]; then
        effective_max_depth="$view_max_depth"
    fi

    local effective_max_filesize="$cli_max_filesize"
    if [[ -z "$effective_max_filesize" && -n "$view_max_filesize" ]]; then
        effective_max_filesize="$view_max_filesize"
    fi

    local follow_flag="false"
    case "$symlink_behavior" in
        follow)
            follow_flag="true"
            ;;
        nofollow)
            follow_flag="false"
            ;;
        *)
            if [[ -n "$resolved_view" && "$view_follow" == "true" ]]; then
                follow_flag="true"
            elif [[ -n "$resolved_view" && "$view_follow" == "false" ]]; then
                follow_flag="false"
            elif [[ "$ripgreprc_follow" == "follow" ]]; then
                follow_flag="true"
            elif [[ "$ripgreprc_follow" == "nofollow" ]]; then
                follow_flag="false"
            fi
            ;;
    esac

    local -a universe=()
    mapfile -t universe < <(enumerate_universe_with_fd "$dir" "$types_serialized" "$effective_max_depth" "$effective_max_filesize" "$active_ignore_serialized" "$follow_flag")

    local manifest_universe_count="${#universe[@]}"
    if [[ "$manifest_enabled" == true && -n "$baseline_ignore_serialized" ]]; then
        local -a active_ignore_array=()
        local -a baseline_ignore_array=()
        if [[ -n "$active_ignore_serialized" ]]; then
            IFS='|' read -ra active_ignore_array <<< "$active_ignore_serialized"
        fi
        if [[ -n "$baseline_ignore_serialized" ]]; then
            IFS='|' read -ra baseline_ignore_array <<< "$baseline_ignore_serialized"
        fi
        if [[ "${#baseline_ignore_array[@]}" -gt 0 ]]; then
            local -A __dir2prompt_baseline_lookup=()
            local ignore_path
            for ignore_path in "${baseline_ignore_array[@]}"; do
                __dir2prompt_baseline_lookup["$ignore_path"]=1
            done
            local -a non_baseline_ignores=()
            if [[ "${#active_ignore_array[@]}" -gt 0 ]]; then
                for ignore_path in "${active_ignore_array[@]}"; do
                    if [[ -z "${__dir2prompt_baseline_lookup[$ignore_path]+x}" ]]; then
                        non_baseline_ignores+=("$ignore_path")
                    fi
                done
            fi
            local manifest_ignore_serialized=""
            if [[ "${#non_baseline_ignores[@]}" -gt 0 ]]; then
                manifest_ignore_serialized=$(IFS='|'; echo "${non_baseline_ignores[*]}")
            fi
            local -a manifest_universe=()
            mapfile -t manifest_universe < <(enumerate_universe_with_fd "$dir" "$types_serialized" "$effective_max_depth" "$effective_max_filesize" "$manifest_ignore_serialized" "$follow_flag")
            manifest_universe_count="${#manifest_universe[@]}"
            unset __dir2prompt_baseline_lookup
        fi
    fi

    local -a include_regexes=()
    local include_required=false
    if [[ "${#include_patterns[@]}" -gt 0 ]]; then
        include_required=true
        build_regex_array include_regexes "${include_patterns[@]}"
    fi

    local -a exclude_regexes=()
    if [[ "${#exclude_patterns[@]}" -gt 0 ]]; then
        build_regex_array exclude_regexes "${exclude_patterns[@]}"
    fi

    local -a selection_buffer=()
    local path
    for path in "${universe[@]}"; do
        local matches_include=false
        local matches_exclude=false
        if [[ "$include_required" == true ]]; then
            if path_matches_any_regex "$path" include_regexes; then
                matches_include=true
            fi
        fi
        if [[ "${#exclude_regexes[@]}" -gt 0 ]] && path_matches_any_regex "$path" exclude_regexes; then
            matches_exclude=true
        fi
        local include_pass=true
        if [[ "$include_required" == true ]]; then
            include_pass=$matches_include
        fi
        if [[ "$include_pass" == true && "$matches_exclude" == false ]]; then
            selection_buffer+=("$path")
        fi
    done

    if [[ "$manifest_enabled" == true ]]; then
        local active_rules_serialized=""
        active_rules_serialized=$(serialize_array active_rules)
        local ephemeral_serialized=""
        ephemeral_serialized=$(serialize_array add_rule_files)
        local selection_serialized=""
        selection_serialized=$(serialize_array selection_buffer)

        DIR2PROMPT_LAST_SELECTION_META["active_rules"]="$active_rules_serialized"
        DIR2PROMPT_LAST_SELECTION_META["ephemeral_rule_files"]="$ephemeral_serialized"
        DIR2PROMPT_LAST_SELECTION_META["selection_serialized"]="$selection_serialized"
        DIR2PROMPT_LAST_SELECTION_META["view"]="$resolved_view"
        DIR2PROMPT_LAST_SELECTION_META["view_source"]="$view_source"
        DIR2PROMPT_LAST_SELECTION_META["baseline_view"]="$baseline_view"
        DIR2PROMPT_LAST_SELECTION_META["types"]="$types_serialized"
        DIR2PROMPT_LAST_SELECTION_META["max_depth"]="$effective_max_depth"
        DIR2PROMPT_LAST_SELECTION_META["max_filesize"]="$effective_max_filesize"
        DIR2PROMPT_LAST_SELECTION_META["symlinks"]="$follow_flag"
        DIR2PROMPT_LAST_SELECTION_META["config_dir"]="$config_dir"
        DIR2PROMPT_LAST_SELECTION_META["universe_count"]="$manifest_universe_count"
        DIR2PROMPT_LAST_SELECTION_META["selection_count"]="${#selection_buffer[@]}"
    fi
    if [[ "${#selection_buffer[@]}" -gt 0 ]]; then
        __selection_ref=("${selection_buffer[@]}")
    else
        __selection_ref=()
    fi
}

function render_tree_from_selection {
    local dir="$1"
    shift
    local -a files=("$@")
    cd "$dir" || fatal "Failed to cd into directory '%s'" "$dir"
    printf '%s\n' "### Directory contents in a tree‐like format"
    if [[ "${#files[@]}" -eq 0 ]]; then
        printf '' | tree --fromfile --dirsfirst --noreport
    else
        printf '%s\n' "${files[@]}" | tree --fromfile --dirsfirst --noreport
    fi
    cd - >/dev/null || fatal "Failed to cd back to original directory"
}

function is_binary_file {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    set +e
    LC_ALL=C head -c 8000 "$file" | LC_ALL=C od -An -t x1 | grep -q ' 00'
    local has_null=$?
    set -e
    if [[ "$has_null" -eq 0 ]]; then
        return 0
    fi
    return 1
}

function render_contents_from_selection {
    local dir="$1"
    shift
    local -a files=("$@")
    cd "$dir" || fatal "Failed to cd into directory '%s'" "$dir"
    printf '%s\n' "### Contents of the non-binary files of the directory"
    local file
    for file in "${files[@]}"; do
        if is_binary_file "$file"; then
            continue
        fi
        if [[ ! -f "$file" ]]; then
            continue
        fi
        visit_file "$file"
    done
    cd - >/dev/null || fatal "Failed to cd back to original directory"
}

function emit_manifest_for_target {
    local dir="$1"
    local target_name="$2"
    local config_dir="$3"

    if [[ "${PARSED_MANIFEST_MODE:-off}" == "off" ]]; then
        return
    fi

    local display="$dir"
    if [[ -n "$target_name" ]]; then
        display="$target_name ($dir)"
    fi

    printf '### Manifest for %s\n' "$display"
    printf 'Manifest mode: %s\n' "$PARSED_MANIFEST_MODE"
    printf 'Target directory: %s\n' "$dir"
    
    # Add precedence explanation
    printf '\n'
    printf '# Selection Precedence (highest to lowest):\n'
    printf '# 1. CLI flags: --ignore-file, --add-rule, --drop-rule, --add-rule-file\n'
    printf '# 2. View selection: --view or default view (from .dir2prompt/views.yml)\n'
    printf '# 3. .promptignore: in target directory or git root\n'
    printf '# 4. fd defaults: .gitignore, .ignore, .fdignore, etc.\n'
    printf '#\n'
    printf '# Higher layers override lower layers. CLI flags enable progressive refinement.\n'
    printf '\n'

    local view="${DIR2PROMPT_LAST_SELECTION_META[view]:-}"
    local view_source="${DIR2PROMPT_LAST_SELECTION_META[view_source]:-none}"
    local baseline_view="${DIR2PROMPT_LAST_SELECTION_META[baseline_view]:-}"
    local view_desc=""
    if [[ -n "$config_dir" && -n "$view" ]]; then
        view_desc="${DIR2PROMPT_VIEW_DESCRIPTIONS["$config_dir::$view"]:-}"
    fi
    printf 'View: %s\n' "${view:-"(none)"}"
    printf 'View source: %s\n' "$view_source"
    if [[ -n "$baseline_view" ]]; then
        printf 'Baseline view: %s\n' "$baseline_view"
    else
        printf 'Baseline view: (none)\n'
    fi
    if [[ -n "$view_desc" ]]; then
        printf 'View description: %s\n' "$view_desc"
    fi

    printf 'Active rules:\n'
    local rules_serialized="${DIR2PROMPT_LAST_SELECTION_META[active_rules]:-}"
    local -a manifest_rules=()
    deserialize_serialized_list "$rules_serialized" manifest_rules
    if [[ "${#manifest_rules[@]}" -eq 0 ]]; then
        printf '  (none)\n'
    else
        local rule_name
        for rule_name in "${manifest_rules[@]}"; do
            local desc=""
            if [[ -n "$config_dir" ]]; then
                desc="${DIR2PROMPT_RULE_DESCRIPTIONS["$config_dir::$rule_name"]:-}"
            fi
            if [[ -n "$desc" ]]; then
                printf '  - %s: %s\n' "$rule_name" "$desc"
            else
                printf '  - %s\n' "$rule_name"
            fi
        done
    fi

    printf 'Ephemeral rule files:\n'
    local eph_serialized="${DIR2PROMPT_LAST_SELECTION_META[ephemeral_rule_files]:-}"
    local -a eph_files=()
    deserialize_serialized_list "$eph_serialized" eph_files
    if [[ "${#eph_files[@]}" -eq 0 ]]; then
        printf '  (none)\n'
    else
        local eph
        for eph in "${eph_files[@]}"; do
            printf '  - %s\n' "$eph"
        done
    fi

    local symlink_flag="${DIR2PROMPT_LAST_SELECTION_META[symlinks]:-false}"
    local symlink_text="nofollow"
    if [[ "$symlink_flag" == "true" ]]; then
        symlink_text="follow"
    fi
    printf 'Symlinks: %s\n' "$symlink_text"

    local types_raw="${DIR2PROMPT_LAST_SELECTION_META[types]:-}"
    local types_text="(any)"
    if [[ -n "$types_raw" ]]; then
        types_text="${types_raw//|/, }"
    fi
    local max_depth="${DIR2PROMPT_LAST_SELECTION_META[max_depth]:-}"
    local max_filesize="${DIR2PROMPT_LAST_SELECTION_META[max_filesize]:-}"
    if [[ -z "$max_depth" ]]; then
        max_depth="(none)"
    fi
    if [[ -z "$max_filesize" ]]; then
        max_filesize="(none)"
    fi
    printf 'Constraints:\n'
    printf '  - Types: %s\n' "$types_text"
    printf '  - Max depth: %s\n' "$max_depth"
    printf '  - Max filesize: %s\n' "$max_filesize"

    local universe_count="${DIR2PROMPT_LAST_SELECTION_META[universe_count]:-0}"
    local selection_count="${DIR2PROMPT_LAST_SELECTION_META[selection_count]:-0}"
    printf 'Counts:\n'
    printf '  - Universe: %s\n' "$universe_count"
    printf '  - Selection: %s\n' "$selection_count"
    
    # Add active layers explanation
    printf '\n'
    printf 'Active Selection Layers:\n'
    local has_cli_rules=false
    local has_view=false
    local has_promptignore=false
    
    if [[ "${#eph_files[@]}" -gt 0 ]]; then
        has_cli_rules=true
        printf '  ✓ CLI flags: %d ephemeral rule file(s) applied\n' "${#eph_files[@]}"
    fi
    
    if [[ -n "$view" ]]; then
        has_view=true
        if [[ "${#manifest_rules[@]}" -gt 0 ]]; then
            printf '  ✓ View layer: "%s" with %d rule(s) applied\n' "$view" "${#manifest_rules[@]}"
        else
            printf '  ✓ View layer: "%s" (no rules configured)\n' "$view"
        fi
    elif [[ "${#manifest_rules[@]}" -gt 0 ]]; then
        has_view=true
        printf '  ✓ Rules layer: %d rule(s) applied without a view\n' "${#manifest_rules[@]}"
    fi
    
    # Note: we can't easily detect .promptignore or fd defaults from here,
    # but we can note their potential presence
    printf '  ✓ fd defaults: .gitignore, .ignore, .fdignore (always active)\n'
    printf '\n'
    
    if [[ "$has_cli_rules" == true && "$has_view" == true ]]; then
        printf 'Note: CLI flags override view selections (progressive refinement active)\n'
        printf '\n'
    fi

    if [[ "$PARSED_MANIFEST_MODE" == "full" ]]; then
        local selection_serialized="${DIR2PROMPT_LAST_SELECTION_META[selection_serialized]:-}"
        local -a selection_files=()
        deserialize_serialized_list "$selection_serialized" selection_files
        printf 'Selection files (%d entries):\n' "${#selection_files[@]}"
        if [[ "${#selection_files[@]}" -eq 0 ]]; then
            printf '  (none)\n'
        else
            local file
            for file in "${selection_files[@]}"; do
                printf '  - %s\n' "$file"
            done
        fi
    fi

    printf '\n'
}

# ——————————
# Rules subcommand helpers (Phase 4)

function yaml_quote {
    local value="$1"
    value=${value//$'\n'/\\n}
    local single_quote="'"
    local double_single="''"
    value=${value//${single_quote}/${double_single}}
    printf "'%s'" "$value"
}

function make_path_relative_to_root {
    local absolute="$1"
    local project_root="$2"
    if [[ -z "$absolute" ]]; then
        printf ''
        return
    fi
    if [[ "$absolute" == "$project_root/"* ]]; then
        local relative="${absolute#$project_root/}"
        printf '%s\n' "$relative"
    else
        printf '%s\n' "$absolute"
    fi
}

function ensure_identifier_valid {
    local kind="$1"
    local value="$2"
    if [[ -z "$value" ]]; then
        fatal "%s name cannot be empty" "$kind"
    fi
    if [[ ! "$value" =~ ^[A-Za-z0-9._-]+$ ]]; then
        fatal "%s name '%s' is invalid. Use letters, numbers, dots, underscores, or dashes." "$kind" "$value"
    fi
}

function resolve_rules_config_dir {
    local start="$ORIG_CWD"
    if [[ -d "$start/.dir2prompt" ]]; then
        (cd "$start/.dir2prompt" && pwd)
        return
    fi
    local git_root
    git_root=$(git -C "$start" rev-parse --show-toplevel 2>/dev/null || true)
    if [[ -n "$git_root" ]]; then
        if [[ -d "$git_root/.dir2prompt" ]]; then
            (cd "$git_root/.dir2prompt" && pwd)
            return
        fi
        printf '%s/.dir2prompt\n' "$git_root"
        return
    fi
    printf '%s/.dir2prompt\n' "$start"
}

function ensure_serialized_list_contains {
    local current_serialized="$1"
    local value="$2"
    local -a buffer=()
    deserialize_serialized_list "$current_serialized" buffer
    local item
    for item in "${buffer[@]}"; do
        if [[ "$item" == "$value" ]]; then
            serialize_array buffer
            return
        fi
    done
    buffer+=("$value")
    serialize_array buffer
}

function write_views_yaml_document {
    local config_dir="$1"
    local views_file="$2"
    local project_root="$3"
    mkdir -p "$config_dir"
    local tmp_file
    tmp_file=$(mktemp)
    {
        printf 'rules:\n'
        local rule_order="${DIR2PROMPT_RULE_ORDERS[$config_dir]:-}"
        local -a rule_names=()
        deserialize_serialized_list "$rule_order" rule_names
        if [[ "${#rule_names[@]}" -eq 0 ]]; then
            printf '  {}\n'
        else
            local rule_name
            for rule_name in "${rule_names[@]}"; do
                local key="$config_dir::$rule_name"
                printf '  %s:\n' "$rule_name"
                local description="${DIR2PROMPT_RULE_DESCRIPTIONS[$key]:-}"
                if [[ -n "$description" ]]; then
                    printf '    description: %s\n' "$(yaml_quote "$description")"
                fi
                local file_path="${DIR2PROMPT_RULE_FILES[$key]}"
                printf '    file: %s\n' "$(make_path_relative_to_root "$file_path" "$project_root")"
            done
        fi

        printf '\nviews:\n'
        local view_order="${DIR2PROMPT_VIEW_ORDERS[$config_dir]:-}"
        local -a view_names=()
        deserialize_serialized_list "$view_order" view_names
        if [[ "${#view_names[@]}" -eq 0 ]]; then
            printf '  {}\n'
        else
            local view_name
            for view_name in "${view_names[@]}"; do
                local key="$config_dir::$view_name"
                printf '  %s:\n' "$view_name"
                local view_desc="${DIR2PROMPT_VIEW_DESCRIPTIONS[$key]:-}"
                if [[ -n "$view_desc" ]]; then
                    printf '    description: %s\n' "$(yaml_quote "$view_desc")"
                fi
                local rules_serialized="${DIR2PROMPT_VIEW_RULES[$key]:-}"
                local -a view_rules=()
                deserialize_serialized_list "$rules_serialized" view_rules
                if [[ "${#view_rules[@]}" -eq 0 ]]; then
                    printf '    rules: []\n'
                else
                    printf '    rules:\n'
                    local rule_item
                    for rule_item in "${view_rules[@]}"; do
                        printf '      - %s\n' "$rule_item"
                    done
                fi
                local follow="${DIR2PROMPT_VIEW_SYMLINKS[$key]:-}"
                if [[ -n "$follow" ]]; then
                    printf '    follow_symlinks: %s\n' "$follow"
                fi
                local view_depth="${DIR2PROMPT_VIEW_MAX_DEPTH[$key]:-}"
                if [[ -n "$view_depth" ]]; then
                    printf '    max_depth: %s\n' "$view_depth"
                fi
                local view_size="${DIR2PROMPT_VIEW_MAX_FILESIZE[$key]:-}"
                if [[ -n "$view_size" ]]; then
                    printf '    max_filesize: %s\n' "$view_size"
                fi
            done
        fi
        printf '\n'
    } > "$tmp_file"
    mv "$tmp_file" "$views_file"
}

function rules_subcommand_add {
    if [[ $# -lt 1 ]]; then
        fatal "'dir2prompt rules add' requires a rule name"
    fi
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        rules_add_usage
        exit 0
    fi
    local rule_name="$1"
    shift
    ensure_identifier_valid "Rule" "$rule_name"

    local description=""
    local description_set=false
    local from_file=""
    local view_name=""
    local base_view=""

    while (( $# > 0 )); do
        case "$1" in
            --description)
                if [[ -z "${2:-}" ]]; then
                    fatal "--description requires a value"
                fi
                description="$2"
                description_set=true
                shift 2
                continue
                ;;
            --from-file)
                if [[ -z "${2:-}" ]]; then
                    fatal "--from-file requires a path"
                fi
                from_file="$2"
                shift 2
                continue
                ;;
            --view)
                if [[ -z "${2:-}" ]]; then
                    fatal "--view requires a name"
                fi
                view_name="$2"
                shift 2
                continue
                ;;
            --base-view)
                if [[ -z "${2:-}" ]]; then
                    fatal "--base-view requires a name"
                fi
                base_view="$2"
                shift 2
                continue
                ;;
            --)
                shift
                break
                ;;
            *)
                fatal "Unknown option '%s' for 'dir2prompt rules add'" "$1"
                ;;
        esac
    done

    if [[ -n "$view_name" ]]; then
        ensure_identifier_valid "View" "$view_name"
    fi
    if [[ -n "$base_view" ]]; then
        ensure_identifier_valid "Base view" "$base_view"
    fi
    if [[ -n "$base_view" && -z "$view_name" ]]; then
        fatal "--base-view requires --view to be specified"
    fi

    local config_dir
    config_dir=$(resolve_rules_config_dir)
    mkdir -p "$config_dir/rules"
    local project_root
    project_root=$(cd "$config_dir/.." && pwd)

    local views_file
    if views_file=$(dir2prompt_find_views_file "$config_dir" 2>/dev/null); then
        parse_views_yaml_file "$config_dir" "$views_file" "$project_root"
    else
        views_file="$config_dir/views.yml"
    fi

    local rule_file_relative=".dir2prompt/rules/$rule_name.ignore"
    local rule_file_path="$project_root/$rule_file_relative"
    local rule_key="$config_dir::$rule_name"

    local current_order="${DIR2PROMPT_RULE_ORDERS[$config_dir]:-}"
    DIR2PROMPT_RULE_ORDERS["$config_dir"]="$(ensure_serialized_list_contains "$current_order" "$rule_name")"
    local rule_already_present=false
    local -a existing_rules=()
    deserialize_serialized_list "$current_order" existing_rules
    local existing_rule
    for existing_rule in "${existing_rules[@]}"; do
        if [[ "$existing_rule" == "$rule_name" ]]; then
            rule_already_present=true
            break
        fi
    done

    DIR2PROMPT_RULE_FILES["$rule_key"]="$rule_file_path"
    if [[ "$description_set" == true || "$rule_already_present" == false ]]; then
        DIR2PROMPT_RULE_DESCRIPTIONS["$rule_key"]="$description"
    fi

    if [[ -n "$from_file" ]]; then
        local resolved_file="$from_file"
        if [[ "$resolved_file" != /* ]]; then
            resolved_file="$ORIG_CWD/$resolved_file"
        fi
        if [[ ! -f "$resolved_file" ]]; then
            fatal "Source file '%s' not found" "$resolved_file"
        fi
        cat "$resolved_file" > "$rule_file_path"
    else
        cat > "$rule_file_path"
    fi

    if [[ -n "$view_name" ]]; then
        local view_key="$config_dir::$view_name"
        local view_order="${DIR2PROMPT_VIEW_ORDERS[$config_dir]:-}"
        DIR2PROMPT_VIEW_ORDERS["$config_dir"]="$(ensure_serialized_list_contains "$view_order" "$view_name")"
        local -a new_rule_list=()
        local source_serialized=""
        local view_existed=false

        if [[ -n "$base_view" ]]; then
            local base_key="$config_dir::$base_view"
            if [[ -z "${DIR2PROMPT_VIEW_RULES[$base_key]+x}" ]]; then
                fatal "Base view '%s' does not exist" "$base_view"
            fi
            source_serialized="${DIR2PROMPT_VIEW_RULES[$base_key]:-}"
        else
            source_serialized="${DIR2PROMPT_VIEW_RULES[$view_key]:-}"
            if [[ -n "${DIR2PROMPT_VIEW_RULES[$view_key]+x}" ]]; then
                view_existed=true
            fi
        fi

        deserialize_serialized_list "$source_serialized" new_rule_list
        local already_added=false
        local current
        for current in "${new_rule_list[@]}"; do
            if [[ "$current" == "$rule_name" ]]; then
                already_added=true
                break
            fi
        done
        if [[ "$already_added" == false ]]; then
            new_rule_list+=("$rule_name")
        fi
        DIR2PROMPT_VIEW_RULES["$view_key"]="$(serialize_array new_rule_list)"
        if [[ "$view_existed" == false && -z "${DIR2PROMPT_VIEW_DESCRIPTIONS[$view_key]+x}" ]]; then
            DIR2PROMPT_VIEW_DESCRIPTIONS["$view_key"]=""
        fi
    fi

    write_views_yaml_document "$config_dir" "$views_file" "$project_root"
    printf "Rule '%s' written to %s\n" "$rule_name" "$rule_file_relative"
    if [[ -n "$view_name" ]]; then
        printf "View '%s' now layers rule '%s'\n" "$view_name" "$rule_name"
    fi
}

function rules_subcommand_list {
    if [[ $# -gt 0 ]]; then
        if [[ "$1" == "--help" || "$1" == "-h" ]]; then
            rules_list_usage
            exit 0
        fi
        fatal "'dir2prompt rules list' does not take additional arguments"
    fi
    local config_dir
    config_dir=$(resolve_rules_config_dir)
    if [[ ! -d "$config_dir" ]]; then
        cat <<-EoN
	No rules or views configured for this repository.
	
	The rules and views system allows you to create reusable, semantic file
	selection profiles instead of manually filtering with --ignore-file each time.
	
	Getting started:
	
	  1. Initialize with example configuration:
	     $PROGRAM rules init
	     
	     This creates a working .dir2prompt directory with a 'default' view.
	  
	  2. Or create your first rule manually:
	     $PROGRAM rules add baseline --from-file .gitignore --view default \\
	       --description "Standard project ignores"
	     
	     This creates a 'default' view using your existing .gitignore patterns.
	  
	  3. Use your view to generate a snapshot:
	     $PROGRAM --view default
	     
	     Or just: $PROGRAM  (uses 'default' view if it exists)
	
	Learn more:
	  $PROGRAM rules --help        # Detailed documentation on rules and views
	  $PROGRAM --help              # See how views integrate with CLI options
EoN
        return
    fi
    local project_root
    project_root=$(cd "$config_dir/.." && pwd)
    local views_file
    if ! views_file=$(dir2prompt_find_views_file "$config_dir" 2>/dev/null); then
        cat <<-EoN
	Configuration directory exists but no views.yml found.
	
	Create your first rule to generate a views.yml file:
	  $PROGRAM rules add baseline --from-file .gitignore --view default \\
	    --description "Standard project ignores"
	
	Or initialize with examples:
	  $PROGRAM rules init
EoN
        return
    fi
    parse_views_yaml_file "$config_dir" "$views_file" "$project_root"
    printf "Rules:\n"
    local rule_order="${DIR2PROMPT_RULE_ORDERS[$config_dir]:-}"
    local -a rule_names=()
    deserialize_serialized_list "$rule_order" rule_names
    if [[ "${#rule_names[@]}" -eq 0 ]]; then
        printf "  (none)\n"
    else
        local rule_name
        for rule_name in "${rule_names[@]}"; do
            local key="$config_dir::$rule_name"
            local rel_path
            rel_path=$(make_path_relative_to_root "${DIR2PROMPT_RULE_FILES[$key]}" "$project_root")
            printf "  - %s\n" "$rule_name"
            printf "      file: %s\n" "$rel_path"
            local description="${DIR2PROMPT_RULE_DESCRIPTIONS[$key]:-}"
            if [[ -n "$description" ]]; then
                printf "      description: %s\n" "$description"
            fi
        done
    fi
    printf "\nViews:\n"
    local view_order="${DIR2PROMPT_VIEW_ORDERS[$config_dir]:-}"
    local -a view_names=()
    deserialize_serialized_list "$view_order" view_names
    if [[ "${#view_names[@]}" -eq 0 ]]; then
        printf "  (none)\n"
    else
        local view_name
        for view_name in "${view_names[@]}"; do
            local key="$config_dir::$view_name"
            printf "  - %s\n" "$view_name"
            local view_desc="${DIR2PROMPT_VIEW_DESCRIPTIONS[$key]:-}"
            if [[ -n "$view_desc" ]]; then
                printf "      description: %s\n" "$view_desc"
            fi
            local rules_serialized="${DIR2PROMPT_VIEW_RULES[$key]:-}"
            local human_rules
            human_rules=$(humanize_serialized_list "$rules_serialized")
            if [[ -n "$human_rules" ]]; then
                printf "      rules: %s\n" "$human_rules"
            else
                printf "      rules: (none)\n"
            fi
        done
    fi
}

function rules_subcommand_show {
    if [[ $# -lt 1 ]]; then
        fatal "'dir2prompt rules show' requires exactly one rule name"
    fi
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        rules_show_usage
        exit 0
    fi
    if [[ $# -ne 1 ]]; then
        fatal "'dir2prompt rules show' requires exactly one rule name"
    fi
    local rule_name="$1"
    ensure_identifier_valid "Rule" "$rule_name"
    local config_dir
    config_dir=$(resolve_rules_config_dir)
    if [[ ! -d "$config_dir" ]]; then
        fatal "Rule '%s' not found (no .dir2prompt directory)" "$rule_name"
    fi
    local project_root
    project_root=$(cd "$config_dir/.." && pwd)
    local views_file
    if ! views_file=$(dir2prompt_find_views_file "$config_dir" 2>/dev/null); then
        fatal "Rule '%s' not found (missing views.yml)" "$rule_name"
    fi
    parse_views_yaml_file "$config_dir" "$views_file" "$project_root"
    local rule_key="$config_dir::$rule_name"
    local rule_path="${DIR2PROMPT_RULE_FILES[$rule_key]:-}"
    if [[ -z "$rule_path" ]]; then
        fatal "Rule '%s' is not defined in views.yml" "$rule_name"
    fi
    if [[ ! -f "$rule_path" ]]; then
        fatal "Rule '%s' file '%s' is missing" "$rule_name" "$rule_path"
    fi
    local display_path
    display_path=$(make_path_relative_to_root "$rule_path" "$project_root")
    printf 'Rule: %s\n' "$rule_name"
    printf 'File: %s\n\n' "$display_path"
    cat "$rule_path"
    printf '\n'
}

function rules_subcommand_init {
    local from_gitignore=false
    local minimal=false
    
    while (( $# > 0 )); do
        case "$1" in
            --help|-h)
                rules_init_usage
                exit 0
                ;;
            --from-gitignore)
                from_gitignore=true
                shift
                ;;
            --minimal)
                minimal=true
                shift
                ;;
            *)
                fatal "Unknown option '%s' for 'dir2prompt rules init'" "$1"
                ;;
        esac
    done
    
    local config_dir
    config_dir=$(resolve_rules_config_dir)
    
    # Check if already initialized
    if [[ -d "$config_dir" ]] && [[ -f "$config_dir/views.yml" || -f "$config_dir/views.yaml" ]]; then
        log "Configuration already exists at $config_dir"
        log "To reinitialize, remove the .dir2prompt directory first."
        return 1
    fi
    
    # Create directory structure
    mkdir -p "$config_dir/rules"
    local project_root
    project_root=$(cd "$config_dir/.." && pwd)
    
    log "Initializing .dir2prompt configuration in $project_root"
    
    if [[ "$minimal" == true ]]; then
        # Create minimal configuration
        cat > "$config_dir/views.yml" <<'EOF'
rules: {}

views: {}
EOF
        log "Created minimal configuration at .dir2prompt/views.yml"
        log ""
        log "Next steps:"
        log "  1. Create your first rule:"
        log "     dir2prompt rules add baseline --description 'Standard ignores'"
        log ""
        log "  2. Add the rule to a view:"
        log "     dir2prompt rules add baseline --view default"
        log ""
        log "  3. Use the view:"
        log "     dir2prompt --view default"
        return 0
    fi
    
    # Create baseline rule
    local baseline_content
    if [[ "$from_gitignore" == true ]] && [[ -f "$project_root/.gitignore" ]]; then
        baseline_content=$(cat "$project_root/.gitignore")
        log "Using existing .gitignore for baseline rule"
    else
        # Provide sensible defaults
        baseline_content='# Common build and dependency directories
node_modules/
dist/
build/
target/
*.egg-info/
__pycache__/
.pytest_cache/
.tox/

# IDE and editor files
.vscode/
.idea/
*.swp
*.swo
*~
.DS_Store

# Environment and secrets
.env
.env.local
*.key
*.pem

# Logs and temporary files
*.log
*.tmp
.cache/

# Version control
.git/
.svn/
'
        log "Creating baseline rule with common ignore patterns"
    fi
    
    # Write baseline rule file
    printf '%s\n' "$baseline_content" > "$config_dir/rules/baseline.ignore"
    
    # Create views.yml with example configuration
    cat > "$config_dir/views.yml" <<'EOF'
rules:
  baseline:
    description: Standard ignore patterns for common build artifacts and IDE files
    file: .dir2prompt/rules/baseline.ignore

views:
  default:
    description: Default view with baseline ignores
    rules:
      - baseline
EOF
    
    log "Created configuration files:"
    log "  - .dir2prompt/views.yml (configuration file)"
    log "  - .dir2prompt/rules/baseline.ignore (baseline ignore patterns)"
    log ""
    log "Your repository is now configured with a 'default' view."
    log ""
    log "Try it out:"
    log "  dir2prompt                    # Uses 'default' view automatically"
    log "  dir2prompt --view default     # Explicitly select the default view"
    log "  dir2prompt --manifest         # See what rules are active"
    log ""
    log "Customize your configuration:"
    log "  dir2prompt rules list         # Show all rules and views"
    log "  dir2prompt rules show baseline # Display baseline rule patterns"
    log "  dir2prompt rules add <name>   # Create additional rules"
    log ""
    log "Learn more:"
    log "  dir2prompt rules --help       # Detailed rules documentation"
}

function handle_rules_subcommand {
    if [[ $# -eq 0 ]]; then
        fatal "Missing rules subcommand. Use 'add', 'list', 'show', or 'init'."
    fi
    local subcommand="$1"
    shift
    
    # Handle --help for the rules subcommand itself
    if [[ "$subcommand" == "--help" || "$subcommand" == "-h" ]]; then
        rules_usage
        exit 0
    fi
    
    case "$subcommand" in
        add)
            rules_subcommand_add "$@"
            ;;
        list)
            rules_subcommand_list "$@"
            ;;
        show)
            rules_subcommand_show "$@"
            ;;
        init)
            rules_subcommand_init "$@"
            ;;
        *)
            fatal "Unknown rules subcommand '%s'. Expected add, list, show, or init." "$subcommand"
            ;;
    esac
}

# ——————————
# Finder backend selection
FINDER_BACKEND="${DIR2PROMPT_FINDER:-fd}"

function ensure_valid_finder_backend {
    case "$FINDER_BACKEND" in
        rg|fd)
            ;;
        *)
            fatal "Unsupported finder backend '%s'. Allowed values: rg, fd." "$FINDER_BACKEND"
            ;;
    esac
}

ensure_valid_finder_backend

# ——————————
# Argument parsing and dependency checking

# Parse command-line arguments into global variables
function parse_arguments {
    # Global options
    PARSED_MODE="both"
    PARSED_OUTPUT_FILE=""
    PARSED_MANIFEST_MODE="off"
    
    # Target arrays - using parallel arrays to store target information
    TARGET_NAMES=()
    TARGET_DIRS=()
    TARGET_TYPES=()
    TARGET_MAX_DEPTHS=()
    TARGET_MAX_FILESIZES=()
    TARGET_IGNORE_FILES_SERIALIZED=()  # Serialized as "file1|file2|file3" or empty
    TARGET_VIEWS=()
    TARGET_ADD_RULES_SERIALIZED=()
    TARGET_DROP_RULES_SERIALIZED=()
    TARGET_ADD_RULE_FILES_SERIALIZED=()
    TARGET_SYMLINK_BEHAVIORS=()
    
    # Temporary state for parsing
    local positional_dirs=()
    local use_target_mode=false
    local has_positional=false
    
    # Default/global target options (before first --target in advanced mode, or global in simple mode)
    local default_types=()
    local default_max_depth=""
    local default_max_filesize=""
    local default_ignore_files=()
    local default_view=""
    local default_add_rules=()
    local default_drop_rules=()
    local default_add_rule_files=()
    local default_symlink="inherit"
    
    # Current target being built (in advanced mode)
    local current_target_name=""
    local current_target_dir=""
    local current_target_types=()
    local current_target_max_depth=""
    local current_target_max_filesize=""
    local current_target_ignore_files=()
    local current_target_has_explicit_types=false
    local current_target_has_explicit_ignore=false
    local current_target_has_explicit_symlink=false
    local current_target_view=""
    local current_target_add_rules=()
    local current_target_drop_rules=()
    local current_target_add_rule_files=()
    local current_target_symlink="inherit"
    local in_target_block=false

    function apply_symlink_flag {
        local -n ref="$1"
        local new_value="$2"
        local context="$3"
        local current="${ref:-inherit}"
        if [[ "$current" != "inherit" && "$current" != "$new_value" ]]; then
            fatal "Contradictory symlink options for %s: cannot combine --follow-symlinks and --no-follow-symlinks" "$context"
        fi
        ref="$new_value"
    }

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

        TARGET_VIEWS+=("$current_target_view")

        local add_rules_str=""
        if [[ "${#current_target_add_rules[@]}" -gt 0 ]]; then
            add_rules_str=$(IFS='|'; echo "${current_target_add_rules[*]}")
        fi
        TARGET_ADD_RULES_SERIALIZED+=("$add_rules_str")

        local drop_rules_str=""
        if [[ "${#current_target_drop_rules[@]}" -gt 0 ]]; then
            drop_rules_str=$(IFS='|'; echo "${current_target_drop_rules[*]}")
        fi
        TARGET_DROP_RULES_SERIALIZED+=("$drop_rules_str")

        local add_rule_files_str=""
        if [[ "${#current_target_add_rule_files[@]}" -gt 0 ]]; then
            add_rule_files_str=$(IFS='|'; echo "${current_target_add_rule_files[*]}")
        fi
        TARGET_ADD_RULE_FILES_SERIALIZED+=("$add_rule_files_str")

        TARGET_SYMLINK_BEHAVIORS+=("$current_target_symlink")
        
        # Reset for next target
        current_target_name=""
        current_target_dir=""
        current_target_types=()
        current_target_max_depth=""
        current_target_max_filesize=""
        current_target_ignore_files=()
        current_target_has_explicit_types=false
        current_target_has_explicit_ignore=false
    current_target_has_explicit_symlink=false
        current_target_view=""
        current_target_add_rules=()
        current_target_drop_rules=()
        current_target_add_rule_files=()
        current_target_symlink="inherit"
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
            --manifest)
                PARSED_MANIFEST_MODE="summary"
                ;;
            --manifest=*)
                local manifest_mode="${1#--manifest=}"
                if [[ -z "$manifest_mode" ]]; then
                    manifest_mode="summary"
                fi
                case "$manifest_mode" in
                    summary|full)
                        PARSED_MANIFEST_MODE="$manifest_mode"
                        ;;
                    *)
                        fatal "Unknown manifest mode '%s'. Supported modes: summary, full." "$manifest_mode"
                        ;;
                esac
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
                current_target_has_explicit_symlink=false
                current_target_view="$default_view"
                current_target_add_rules=("${default_add_rules[@]+"${default_add_rules[@]}"}")
                current_target_drop_rules=("${default_drop_rules[@]+"${default_drop_rules[@]}"}")
                current_target_add_rule_files=("${default_add_rule_files[@]+"${default_add_rule_files[@]}"}")
                current_target_symlink="$default_symlink"
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
            --view)
                if [[ -z "${2:-}" ]]; then
                    fatal "Option --view requires an argument"
                fi
                if [[ "$in_target_block" == true ]]; then
                    current_target_view="$2"
                else
                    default_view="$2"
                fi
                shift
                ;;
            --add-rule)
                if [[ -z "${2:-}" ]]; then
                    fatal "Option --add-rule requires an argument"
                fi
                if [[ "$in_target_block" == true ]]; then
                    current_target_add_rules+=("$2")
                else
                    default_add_rules+=("$2")
                fi
                shift
                ;;
            --drop-rule)
                if [[ -z "${2:-}" ]]; then
                    fatal "Option --drop-rule requires an argument"
                fi
                if [[ "$in_target_block" == true ]]; then
                    current_target_drop_rules+=("$2")
                else
                    default_drop_rules+=("$2")
                fi
                shift
                ;;
            --add-rule-file)
                if [[ -z "${2:-}" ]]; then
                    fatal "Option --add-rule-file requires an argument"
                fi
                local rule_file="$2"
                if [[ "$rule_file" != /* ]]; then
                    rule_file="$ORIG_CWD/$rule_file"
                fi
                if [[ "$in_target_block" == true ]]; then
                    current_target_add_rule_files+=("$rule_file")
                else
                    default_add_rule_files+=("$rule_file")
                fi
                shift
                ;;
            --follow-symlinks)
                if [[ "$in_target_block" == true ]]; then
                    if [[ "$current_target_has_explicit_symlink" == false ]]; then
                        current_target_symlink="follow"
                        current_target_has_explicit_symlink=true
                    elif [[ "$current_target_symlink" != "follow" ]]; then
                        local context="current target"
                        if [[ -n "$current_target_name" ]]; then
                            context="target '$current_target_name'"
                        fi
                        fatal "Contradictory symlink options for %s: cannot combine --follow-symlinks and --no-follow-symlinks" "$context"
                    fi
                else
                    apply_symlink_flag default_symlink "follow" "global options"
                fi
                ;;
            --no-follow-symlinks)
                if [[ "$in_target_block" == true ]]; then
                    if [[ "$current_target_has_explicit_symlink" == false ]]; then
                        current_target_symlink="nofollow"
                        current_target_has_explicit_symlink=true
                    elif [[ "$current_target_symlink" != "nofollow" ]]; then
                        local context="current target"
                        if [[ -n "$current_target_name" ]]; then
                            context="target '$current_target_name'"
                        fi
                        fatal "Contradictory symlink options for %s: cannot combine --follow-symlinks and --no-follow-symlinks" "$context"
                    fi
                else
                    apply_symlink_flag default_symlink "nofollow" "global options"
                fi
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

            TARGET_VIEWS+=("$default_view")

            local add_rules_str=""
            if [[ "${#default_add_rules[@]}" -gt 0 ]]; then
                add_rules_str=$(IFS='|'; echo "${default_add_rules[*]}")
            fi
            TARGET_ADD_RULES_SERIALIZED+=("$add_rules_str")

            local drop_rules_str=""
            if [[ "${#default_drop_rules[@]}" -gt 0 ]]; then
                drop_rules_str=$(IFS='|'; echo "${default_drop_rules[*]}")
            fi
            TARGET_DROP_RULES_SERIALIZED+=("$drop_rules_str")

            local add_rule_files_str=""
            if [[ "${#default_add_rule_files[@]}" -gt 0 ]]; then
                add_rule_files_str=$(IFS='|'; echo "${default_add_rule_files[*]}")
            fi
            TARGET_ADD_RULE_FILES_SERIALIZED+=("$add_rule_files_str")

            TARGET_SYMLINK_BEHAVIORS+=("$default_symlink")
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
function generate_tree_with_rg {
    local filter_options=("${@}")
    rg --files --sort path "${filter_options[@]+"${filter_options[@]}"}" | tree --fromfile --dirsfirst --noreport
}

function generate_tree_with_fd {
    local types_serialized="$1"
    local max_depth="$2"
    local max_filesize="$3"
    local active_ignore_serialized="$4"

    local -a types_array=()
    if [[ -n "$types_serialized" ]]; then
        IFS='|' read -ra types_array <<< "$types_serialized"
    fi

    local -a active_ignore_files=()
    if [[ -n "$active_ignore_serialized" ]]; then
        IFS='|' read -ra active_ignore_files <<< "$active_ignore_serialized"
    fi

    local -a fd_cmd=("fd" "--strip-cwd-prefix" "--color" "never" "--type" "f")
    if [[ -n "$max_depth" ]]; then
        fd_cmd+=("--max-depth" "$max_depth")
    fi

    if [[ -n "$max_filesize" ]]; then
        local normalized_size="${max_filesize,,}"
        fd_cmd+=("--size" "-$normalized_size")
    fi

    if [[ "${#types_array[@]}" -gt 0 ]]; then
        for type in "${types_array[@]}"; do
            fd_cmd+=("--extension" "$type")
        done
    fi

    if [[ "${#active_ignore_files[@]}" -gt 0 ]]; then
        for ignore_file in "${active_ignore_files[@]}"; do
            fd_cmd+=("--ignore-file" "$ignore_file")
        done
    fi

    "${fd_cmd[@]}" | LC_ALL=C sort | tree --fromfile --dirsfirst --noreport
}

function generate_tree {
    local dir="$1"
    local types_serialized="$2"
    local max_depth="$3"
    local max_filesize="$4"
    local active_ignore_serialized="$5"
    shift 5
    local filter_options=("${@}")

    cd "$dir" || fatal "Failed to cd into directory '%s'" "$dir"
    printf '%s\n' "### Directory contents in a tree‐like format"

    case "$FINDER_BACKEND" in
        fd)
            generate_tree_with_fd "$types_serialized" "$max_depth" "$max_filesize" "$active_ignore_serialized"
            ;;
        *)
            generate_tree_with_rg "${filter_options[@]+"${filter_options[@]}"}"
            ;;
    esac

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
    local types_serialized="$3"
    local max_depth="$4"
    local max_filesize="$5"
    local ignore_files_serialized="$6"
    local view_name="$7"
    local add_rules_serialized="$8"
    local drop_rules_serialized="$9"
    local add_rule_files_serialized="${10}"
    local symlink_behavior="${11}"
    local target_name="${12}"
    local dir_abs
    dir_abs=$(cd "$dir" && pwd) || fatal "Failed to resolve directory '%s'" "$dir"
    
    local config_dir=""
    if ensure_dir2prompt_config_loaded "$dir" config_dir; then
        maybe_dump_configuration "$config_dir"
    fi

    if [[ "${DIR2PROMPT_DEBUG_TARGETS:-}" == "1" ]]; then
        printf '[[DIR2PROMPT-TARGET dir="%s"]]\n' "$dir"
        printf '  name=%s\n' "$target_name"
        printf '  view=%s\n' "$view_name"
        printf '  add_rules=%s\n' "$add_rules_serialized"
        printf '  drop_rules=%s\n' "$drop_rules_serialized"
        printf '  add_rule_files=%s\n' "$add_rule_files_serialized"
        printf '  symlinks=%s\n' "$symlink_behavior"
        printf '[[/DIR2PROMPT-TARGET]]\n'
    fi

    # Build filter options from target configuration
    local -a filter_options=()
    local -a resolved_ignore_files=()
    local -a baseline_ignore_files=()
    
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
    local ripgreprc_follow="inherit"
    local -a ripgreprc_include_globs=()
    local -a ripgreprc_exclude_globs=()
    if [[ -n "$git_root" && -f "$git_root/.ripgreprc" ]]; then
        export RIPGREP_CONFIG_PATH="$git_root/.ripgreprc"
        parse_ripgreprc_file "$git_root/.ripgreprc" ripgreprc_include_globs ripgreprc_exclude_globs ripgreprc_follow
    else
        # Unset to avoid using config from previous target
        unset RIPGREP_CONFIG_PATH
    fi

    local ripgreprc_include_serialized=""
    if [[ "${#ripgreprc_include_globs[@]}" -gt 0 ]]; then
        ripgreprc_include_serialized=$(IFS='|'; echo "${ripgreprc_include_globs[*]}")
    fi
    local ripgreprc_exclude_serialized=""
    if [[ "${#ripgreprc_exclude_globs[@]}" -gt 0 ]]; then
        ripgreprc_exclude_serialized=$(IFS='|'; echo "${ripgreprc_exclude_globs[*]}")
    fi

    # Handle ignore files based on new logic
    if [[ "${#ignore_files[@]}" -gt 0 ]]; then
        # When the caller provides --ignore-file flags, only those files define the view.
        for ignore_file in "${ignore_files[@]}"; do
            local normalized_ignore_file="$ignore_file"
            if [[ "$normalized_ignore_file" != /* ]]; then
                normalized_ignore_file="$ORIG_CWD/$normalized_ignore_file"
            fi
            resolved_ignore_files+=("$normalized_ignore_file")
            filter_options+=("--ignore-file" "$normalized_ignore_file")
        done
    else
        # Default view: check directory-local .promptignore, then fall back to the git root.
        local promptignore_path="$dir_abs/.promptignore"
        if [[ -f "$promptignore_path" ]]; then
            resolved_ignore_files+=("$promptignore_path")
            baseline_ignore_files+=("$promptignore_path")
            filter_options+=("--ignore-file" "$promptignore_path")
        else
            # Try to find git root and check for .promptignore there
            if [[ -n "$git_root" && -f "$git_root/.promptignore" ]]; then
                resolved_ignore_files+=("$git_root/.promptignore")
                baseline_ignore_files+=("$git_root/.promptignore")
                filter_options+=("--ignore-file" "$git_root/.promptignore")
            fi
        fi
    fi

    local active_ignore_serialized=""
    if [[ "${#resolved_ignore_files[@]}" -gt 0 ]]; then
        active_ignore_serialized=$(IFS='|'; echo "${resolved_ignore_files[*]}")
    fi

    local baseline_ignore_serialized=""
    if [[ "${#baseline_ignore_files[@]}" -gt 0 ]]; then
        baseline_ignore_serialized=$(IFS='|'; echo "${baseline_ignore_files[*]}")
    fi

    if [[ "$FINDER_BACKEND" == "fd" ]]; then
    local -a final_selection=()
    build_final_selection final_selection "$dir" "$types_serialized" "$max_depth" "$max_filesize" "$active_ignore_serialized" "$baseline_ignore_serialized" "$config_dir" "$view_name" "$add_rules_serialized" "$drop_rules_serialized" "$add_rule_files_serialized" "$symlink_behavior" "$ripgreprc_include_serialized" "$ripgreprc_exclude_serialized" "$ripgreprc_follow"
        if [[ "${PARSED_MANIFEST_MODE:-off}" != "off" ]]; then
            emit_manifest_for_target "$dir" "$target_name" "$config_dir"
        fi
        case "$mode" in
            both)
                render_tree_from_selection "$dir" "${final_selection[@]}"
                printf '\n'
                render_contents_from_selection "$dir" "${final_selection[@]}"
                ;;
            tree)
                render_tree_from_selection "$dir" "${final_selection[@]}"
                ;;
            contents)
                render_contents_from_selection "$dir" "${final_selection[@]}"
                ;;
            *)
                fatal "Invalid mode '%s'" "$mode"
                ;;
        esac
    else
        case "$mode" in
            both)
                generate_tree "$dir" "$types_serialized" "$max_depth" "$max_filesize" "$active_ignore_serialized" "${filter_options[@]+"${filter_options[@]}"}"
                printf '\n'
                generate_contents "$dir" "${filter_options[@]+"${filter_options[@]}"}"
                ;;
            tree)
                generate_tree "$dir" "$types_serialized" "$max_depth" "$max_filesize" "$active_ignore_serialized" "${filter_options[@]+"${filter_options[@]}"}"
                ;;
            contents)
                generate_contents "$dir" "${filter_options[@]+"${filter_options[@]}"}"
                ;;
            *)
                fatal "Invalid mode '%s'" "$mode"
                ;;
        esac
    fi
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

    if [[ "${PARSED_MANIFEST_MODE:-off}" != "off" && "$FINDER_BACKEND" != "fd" ]]; then
        fatal "--manifest currently requires the fd selection backend. Unset DIR2PROMPT_FINDER or set it to 'fd'."
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
    local view_name="${TARGET_VIEWS[$i]}"
    local add_rules_serialized="${TARGET_ADD_RULES_SERIALIZED[$i]}"
    local drop_rules_serialized="${TARGET_DROP_RULES_SERIALIZED[$i]}"
    local add_rule_files_serialized="${TARGET_ADD_RULE_FILES_SERIALIZED[$i]}"
    local symlink_behavior="${TARGET_SYMLINK_BEHAVIORS[$i]}"
    local target_name="${TARGET_NAMES[$i]}"
        
        # Add separator between targets if there are multiple
        if [[ "$i" -gt 0 ]]; then
            printf '\n'
        fi
        
        process_target "$target_dir" "$mode" "$types_serialized" "$max_depth" "$max_filesize" "$ignore_files_serialized" "$view_name" "$add_rules_serialized" "$drop_rules_serialized" "$add_rule_files_serialized" "$symlink_behavior" "$target_name"
    done
} # End of function main

# Main execution
if [ "$0" = "${BASH_SOURCE:-$0}" ]; then
    if [[ "${1:-}" == "rules" ]]; then
        shift
        handle_rules_subcommand "$@"
        exit 0
    fi

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
