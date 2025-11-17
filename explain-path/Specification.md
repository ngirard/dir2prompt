# Specification: dir2prompt explain-path

This document specifies the `dir2prompt explain-path` feature.

The goal of `explain-path` is to give humans and LLMs a precise, inspectable explanation of **why a given path is included or excluded** from a `dir2prompt` snapshot under a particular configuration (views, rules, ignore files, and CLI flags).

The specification assumes the selection system described in:

- `docs/selection-system-spec.md`
- `docs/selection-algorithm-spec.md`
- `docs/rules-format-spec.md`
- `docs/manifest-spec.md`
- `docs/llm-manifest-spec.md`

It must be possible for an LLM agent, given only this specification and the existing code, to implement `explain-path` correctly and safely.


## Background and motivation

dir2prompt already has a rich selection system:

- Baseline ignores from `.promptignore` and `.ripgreprc`.
- Named rules backed by gitignore-style files.
- Views that combine rules and optional constraints.
- CLI layering with `--view`, `--add-rule`, `--drop-rule`, `--add-rule-file`.
- Constraints like `--type`, `--max-depth`, `--max-filesize`.
- A manifest, including `--manifest=llm`, that summarizes how a **snapshot** was produced.

However, there is still a major usability gap:

- The manifest explains **how the snapshot as a whole** was assembled.
- It does **not** explain, for a single path, why it is present or absent.

For a human (or an LLM agent) trying to curate “perfect context” for a given topic (for example, “only production backend code but not migrations” or “only high-level docs and ADRs”), the feedback loop currently looks like this:

1. Edit views/rules or tweak CLI flags.
2. Run `dir2prompt`.
3. Inspect a long tree and contents listing.
4. Guess why some file is missing or unexpectedly included.
5. Repeat steps 1–4 until it “feels right”.

This is slow and brittle, especially for LLM-driven agents that cannot easily infer the full rule system from a snapshot alone.

The `explain-path` feature addresses this by providing **path-level introspection**:

- For any given path (file or directory) under a target, explain where it dropped out in the pipeline:
  - Was it never in the initial universe?
  - Did `.promptignore` or `.ripgreprc` remove it?
  - Was it excluded because no include rule matched?
  - Was it removed by a specific exclude pattern?
  - Was it filtered out by depth, type, or size?
- Where possible, reference **concrete patterns and rule names**.
- Provide a concise, narrative explanation suitable to prepend to an LLM conversation.
- Optionally, provide a machine-readable JSON structure that can drive automation.

The feature must be usable both by humans on a terminal and as a building block for LLM agents that iterate on views and rules.


## Scope and non-goals

### In scope

- A new top-level subcommand: `dir2prompt explain-path`.
- Single-target analysis (one root directory per invocation) with support for the same selection options as the main command:
  - `--view`, `--add-rule`, `--drop-rule`, `--add-rule-file`
  - `--ignore-file`
  - `--type`, `--max-depth`, `--max-filesize`
  - `--follow-symlinks`, `--no-follow-symlinks`
- Explanation of why each requested path is **included** or **excluded** from the final selection.
- Identification of the **phase** where a path drops out:
  - Universe (`fd`).
  - Baseline filters (`.promptignore`, `.ripgreprc`).
  - View and named rules.
  - Ephemeral rules and `--ignore-file` overlays.
  - CLI constraints (type, depth, size).
- Human-readable text output.
- Optional JSON output with a stable schema.
- Integration with the existing selection pipeline and metadata (especially `build_final_selection` and `DIR2PROMPT_LAST_SELECTION_META`).
- Clear error handling and exit codes.
- Requirements for tests and documentation updates.

### Explicit non-goals (v1)

- Multi-target explain-path (supporting `--target` blocks) is out of scope for v1.
- Interactive or “watch” modes are out of scope.
- A dedicated LLM-oriented manifest mode for explain-path (for example, `--explain-path-llm`) is not required; the existing `--manifest=llm` already covers snapshot-level meta-context.
- Reverse-engineering `fd`’s internal ignore logic beyond what can be inferred from existing helpers is not required.


## Terminology recap

This feature uses the same terminology as the selection specs:

- **Universe (`U`)**: the set of candidate files enumerated by `fd` before any rule-based filtering.
- **Baseline filters**: `.promptignore` and `.ripgreprc`-derived patterns (if any).
- **Rules**: named include/exclude pattern sets stored in `.dir2prompt/rules/*.ignore`.
- **View**: a named combination of rules plus optional constraints.
- **Ephemeral rules**: files from `--add-rule-file` that apply only to a single invocation.
- **CLI overlays**: `--ignore-file` rules and direct constraints (`--type`, `--max-depth`, `--max-filesize`, symlink flags).
- **Final selection (`F`)**: the sorted list of files that appear in the snapshot.

`explain-path` must report, for each path, how it travels through this pipeline.


## CLI interface

### Command synopsis

```bash
dir2prompt explain-path [SELECTION_OPTIONS] [--dir ROOT] PATH [PATH...]
````

* `ROOT` defaults to the current directory (`.`) when `--dir` is omitted.
* Each `PATH` may be absolute or relative:

  * Relative paths are resolved relative to `ROOT`.
  * Absolute paths must lie under `ROOT` (after resolving symlinks); otherwise an error is reported.

The command does **not** generate a tree or contents snapshot. It only prints explanations for the requested paths.

### Selection options

`explain-path` must accept the same selection options as a single-target `dir2prompt` invocation (excluding subcommands and manifest flags):

* View and rules:

  * `--view <NAME>`
  * `--add-rule <NAME>` (repeatable)
  * `--drop-rule <NAME>` (repeatable)
  * `--add-rule-file <PATH>` (repeatable, resolved relative to the original working directory, as in the main CLI)
* Ignore files:

  * `--ignore-file <FILE>` (repeatable; overrides `.promptignore` detection exactly as in the main CLI)
* Constraints:

  * `--type <TYPE>` (repeatable; interpreted as extensions in fd-based selection)
  * `--max-depth <NUM>`
  * `--max-filesize <NUM>` (same semantics as in `build_final_selection`, including numeric values or `kb`, `mb`, `gb` suffixes)
* Symlinks:

  * `--follow-symlinks`
  * `--no-follow-symlinks`

The semantics and precedence of these options must match the main command:

1. CLI flags (`--ignore-file`, `--add-rule`, `--drop-rule`, `--add-rule-file`).
2. Selected view (`--view`) or default view from `.dir2prompt`.
3. `.promptignore` from target directory or git root.
4. `fd`’s built-in ignores.

The `--manifest` flag and modes (`summary`, `full`, `llm`) are **not** part of `explain-path` in v1.

### Output format options

Add a global flag for `explain-path`:

```bash
  --format <MODE>   Output format for explanations: text (default), json, or both.
```

* `text` (default): human-friendly Markdown output, one section per path.
* `json`: machine-readable JSON on stdout, one aggregate document.
* `both`: first emit the text output, then a blank line, then the JSON document.

If `--format` is provided in other subcommands, it must be rejected with a clear error.

### Exit codes

* `0`: all requested paths were processed successfully (even if some paths are excluded).
* `1`: errors in CLI arguments (unknown option, conflicting flags, invalid format, etc.).
* `2`: runtime errors (for example, missing configuration files, missing rules, missing ignore files, inability to resolve ROOT).
* `3`: some but not all paths could be processed (for example, some paths are outside ROOT or refer to missing rules), while explanations for other paths were still printed.

When exit code `3` is used, the implementation must clearly mark which paths could not be explained.

## Path resolution rules

For each requested `PATH`:

1. Resolve `ROOT`:

   * If `--dir ROOT` is specified, resolve it to an absolute path.
   * Otherwise, use the current working directory.

2. Resolve `PATH` to an absolute path:

   * If `PATH` is relative, interpret it relative to `ROOT`.
   * If `PATH` is absolute, normalize it and check that it is under `ROOT` (prefix match after resolving symlinks).

3. Compute the **relative path** as seen by the selection system:

   * Use the same semantics as `_enumerate_true_universe` (paths stripped of the ROOT prefix).
   * This relative path is what must be matched against gitignore-style patterns and what is used in selection arrays.

If a `PATH` lies outside `ROOT`, the tool must:

* Print a short explanation block for that path indicating that it is outside the analysis root.
* Skip deeper analysis.
* Contribute to a non-zero exit code (`3`).

## Behavioural semantics by phase

This section defines how explain-path must determine fate and reasons for each path.

For each path, the feature must walk through the same phases as `build_final_selection`:

1. Universe enumeration (`U`).
2. Baseline filtering (`.promptignore`, `.ripgreprc`).
3. View and named rule sets.
4. Ephemeral rules (`--add-rule-file`) and CLI ignore files.
5. CLI constraints (`--type`, `--max-depth`, `--max-filesize`).
6. Final inclusion decision.

To maximize accuracy and maintainability, explain-path must **reuse** existing helper functions whenever possible:

* `_enumerate_true_universe`
* `parse_gitignore_rule_file`
* `parse_ripgreprc_file`
* `gitignore_pattern_to_regex`
* `build_regex_array`
* `path_matches_any_regex`
* `apply_pattern_filters`
* View and rule configuration loading logic.

### Phase 1: universe membership

For each path:

* Compute the candidate’s relative path.
* Enumerate the universe `U` using `_enumerate_true_universe` with the **effective** max depth, type, size, and symlink behaviour derived exactly as in `build_final_selection`.
* Check whether the relative path is in `U`.

If the path is **not in `U`**, the explanation must say:

* That the path is not part of the initial universe of candidates for this invocation.
* Whether the path exists on disk:

  * If the file does not exist at all, say so explicitly.
  * If it exists but is not in `U`, explain that it is likely filtered by fd’s built-in ignore logic or by constraints (for example, type, size, or depth).

In the latter case, the command must still check constraints:

* If the depth exceeds `max_depth`, that fact should be mentioned.
* If the extension does not match any configured `--type`, that should be mentioned.
* If its size exceeds `max_filesize`, that should be mentioned.

If the path is not in the universe, later phases must be skipped. The final status is “excluded: not in universe”.

### Phase 2: baseline filtering

If the path is in `U`, explain-path must determine whether it survives **baseline filtering**:

* Baseline includes and excludes from `.promptignore` (target-local or git-root) and `.ripgreprc` (`--glob` patterns) must be collected exactly as in `build_final_selection`.
* Using `apply_pattern_filters` with the baseline patterns and a one-element array `[path]`, compute whether the candidate survives baseline filtering.

The explanation must state:

* Whether `.promptignore` exists for this target (and its location).
* Whether `.ripgreprc` is active and where it was loaded from.
* Whether the path is:

  * Explicitly excluded by a baseline pattern (list **all** matching exclude patterns).
  * Explicitly included by a baseline pattern (list all matching include patterns).
  * Not matched by any baseline include or exclude (for the case where include sets are empty).

If the path is removed at this phase, the final status is “excluded: removed by baseline filters”, and later phases must be skipped.

### Phase 3: view and named rules

If the path survives baseline filters, explain-path must check the **view and named rules**:

* Determine the active view and rules:

  * If `--view` is provided, use that.
  * Otherwise, use the configured `default` view if one exists.
* Collect active rules after applying `--add-rule` and `--drop-rule` overlays.

For each active rule:

* Load `Inc(R)` and `Exc(R)` from the rule’s gitignore-style file using `parse_gitignore_rule_file` and `build_regex_array`.
* Determine whether the path matches any include or exclude patterns in this rule.

The implementation must report:

* The list of rules that **contribute includes** for this path (that is, where the path matches at least one include pattern).
* The list of rules that **contribute excludes** for this path (at least one exclude pattern matches).
* Whether the **global include set** is non-empty (any rule has includes) and whether the path is in it.
* Whether the path is in the global exclude set.

The logic is still that of the selection algorithm:

* If `Inc` is non-empty, only paths in `Inc` survive; everything else is implicitly excluded.
* `Exc` is always removed last: `F = S \ Exc`.

For explanation purposes, the implementation should distinguish:

* “Excluded because no include rule matches in a configuration that defines includes.”
* “Excluded because one or more exclude rules match.”

If the path falls out at this phase, the explanation must say **which rules and which patterns** are responsible.

### Phase 4: ephemeral rules and CLI ignore files

Ephemeral rules from `--add-rule-file` and CLI ignore files from `--ignore-file` are resolved and parsed in `build_final_selection` and participate in the effective `include_patterns` and `exclude_patterns`.

For explanation:

* Treat each `--add-rule-file` as a rule-like source named by its filename (for example, `@/path/to/file.ignore` in explanations).
* Treat each `--ignore-file` similarly, but call out that these are CLI ignore files that override `.promptignore`.

For each such file:

* Determine whether the path matches any include or exclude pattern.
* Include this information in the phase summary.

The same “no include match vs explicit exclude” distinction applies.

If the path was already excluded by view rules (phase 3), this phase should still mention that none of the ephemeral or CLI ignore patterns could rescue it.

### Phase 5: CLI constraints

Finally, explain-path must check the CLI constraints:

* File types (`--type`): based on extension (as used by `_enumerate_true_universe`), not ripgrep types.
* Maximum depth (`--max-depth`): computed as the number of path components relative to ROOT.
* Maximum filesize (`--max-filesize`): as in `_enumerate_true_universe`.

Even if the path survived rules, it may be **removed** by one of these constraints. The explanation must clearly state:

* Which constraints are active.
* For each constraint, whether the path passes or fails and why.

For example:

> “The path has extension `.log`, while the active type filter only includes `py` and `md`, so it is excluded by the file type constraint.”

or

> “The path is 3.2 MiB and the active max filesize is 1 MiB, so it is excluded by the max-filesize constraint.”

If the path passes all constraints, it remains in the final selection.

## Text output format

When `--format text` (the default) is used, the output must be Markdown with a clear section per path.

### Section layout for each path

For each path, produce:

1. A level-three heading with the resolved **relative path**:

   ```markdown
   ### Explanation for path `relative/path/to/file`
   ```

   If the original path was absolute or outside ROOT, mention the original input in the body.

2. A one-line final status:

   ```markdown
   Final status: **included** in the snapshot.
   ```

   or

   ```markdown
   Final status: **excluded** – removed by baseline `.promptignore`.
   ```

3. A short human-oriented summary paragraph suitable for direct use as LLM context, for example:

   > This file is included because it survives baseline ignores, matches the include rules for the `docs` view, and passes all CLI constraints.

4. A structured breakdown by phase, using subheadings:

   ```markdown
   #### Phase 1: universe

   - The file exists on disk at `<absolute_path>`.
   - It is present in the fd universe for this invocation.

   #### Phase 2: baseline filters

   - Active `.promptignore`: `<path or "(none)">`.
   - Active `.ripgreprc`: `<path or "(none)">`.
   - Matching baseline include patterns:
     - `!docs/**`
   - Matching baseline exclude patterns:
     - *(none)*

   #### Phase 3: view and named rules

   - Active view: `docs-deep` (description if available).
   - Named rules contributing includes:
     - `docs-core`: `!docs/**/*.md`
   - Named rules contributing excludes:
     - `baseline`: `build/**`
   - Result after view and named rules: **included**.

   #### Phase 4: ephemeral and CLI ignore rules

   - Ephemeral rule files:
     - `prompts/docs.ignore` (no matching patterns for this path).
   - CLI ignore files:
     - *(none)*
   - Result after this phase: **included**.

   #### Phase 5: CLI constraints

   - Active type filters: `py`.
   - Active max depth: *(none)*.
   - Active max filesize: `1mb`.
   - Path extension: `.py` → **passes type filter**.
   - File size: `12 KiB` → **below max filesize**.
   - Result after constraints: **included**.
   ```

5. A final one-line scope hint connecting to the snapshot-level view:

   ```markdown
   This path is part of a **focused slice** defined by the current view and CLI filters.
   ```

The implementation may adjust wording slightly as long as:

* The five phases are clearly identifiable.
* The final status is unambiguous.
* Concrete rule names and patterns are mentioned where they matter.

## JSON output format

When `--format json` or `--format both` is used, the implementation must emit a single JSON document of the following shape:

```json
{
  "root": "/absolute/path/to/root",
  "options": {
    "view": "docs-deep",
    "add_rules": ["tests-only"],
    "drop_rules": [],
    "add_rule_files": ["prompts/docs.ignore"],
    "ignore_files": [".promptignore"],
    "types": ["py"],
    "max_depth": null,
    "max_filesize": "1mb",
    "follow_symlinks": false
  },
  "paths": [
    {
      "input": "docs/cli-selection-spec.md",
      "relative": "docs/cli-selection-spec.md",
      "absolute": "/absolute/path/docs/cli-selection-spec.md",
      "exists": true,
      "final_status": "included",
      "final_reason": "survives all filters and constraints",
      "phases": {
        "universe": {
          "in_universe": true,
          "notes": []
        },
        "baseline": {
          "active_promptignore": ["/repo/.promptignore"],
          "active_ripgreprc": "/repo/.ripgreprc",
          "includes": ["!docs/**"],
          "excludes": [],
          "survives": true
        },
        "rules": {
          "view": "docs-deep",
          "view_description": "In-depth project documentation",
          "named_rules": [
            {
              "name": "baseline",
              "includes": [],
              "excludes": ["build/**"],
              "matches_include": false,
              "matches_exclude": false
            },
            {
              "name": "docs-core",
              "includes": ["!docs/**/*.md"],
              "excludes": [],
              "matches_include": true,
              "matches_exclude": false
            }
          ],
          "has_global_includes": true,
          "matched_global_include": true,
          "matched_global_exclude": false,
          "survives": true
        },
        "ephemeral": {
          "ephemeral_rule_files": [
            {
              "path": "prompts/docs.ignore",
              "includes": [],
              "excludes": [],
              "matches_include": false,
              "matches_exclude": false
            }
          ],
          "cli_ignore_files": [],
          "survives": true
        },
        "constraints": {
          "types": ["py"],
          "max_depth": null,
          "max_filesize": "1mb",
          "extension": "md",
          "depth": 2,
          "size_bytes": 12345,
          "passes_type": false,
          "passes_depth": true,
          "passes_size": true,
          "survives": false
        }
      }
    }
  ]
}
```

Notes:

* `final_status` is `"included"` or `"excluded"`.
* `final_reason` is a short English phrase summarizing the dominant cause (for example, `"not in universe"`, `"excluded by baseline promptignore"`, `"excluded by type filter"`, `"no include rule matches"`).
* `notes` arrays may contain additional useful remarks but should not be depended upon by callers.
* `size_bytes` may be omitted or set to `null` if the file size cannot be determined.

The schema must be stable enough that automated tooling and LLM agents can rely on it across minor releases.

## Integration with existing internals

To avoid duplication and drift, explain-path must:

* Reuse `_enumerate_true_universe` for universe membership.
* Reuse `parse_gitignore_rule_file`, `gitignore_pattern_to_regex`, `build_regex_array`, and `path_matches_any_regex` for all pattern matching.
* Reuse the configuration loading pipeline (`ensure_dir2prompt_config_loaded`, `parse_views_yaml_file`, etc.).
* Reuse the logic that resolves effective `max_depth`, `max_filesize`, and symlink behaviour in `build_final_selection`.

It is acceptable to factor out shared logic from `build_final_selection` into smaller helpers if that simplifies explain-path, as long as:

* Behaviour of the main selection pipeline is preserved.
* Existing tests continue to pass.

## Error handling requirements

* Invalid combinations of flags (for example, conflicting symlink behaviour) must be rejected with clear messages, reusing the logic from `parse_arguments`.
* Requests for rules or views that do not exist must produce a clear error that mentions the offending name.
* If the user passes no `PATH` arguments, the tool must exit with a usage error and non-zero status.
* If `ROOT` cannot be resolved, the tool must exit with a non-zero status and print an appropriate error.
* For paths that cannot be explained (for example, outside ROOT), the tool must emit a short explanation and contribute to exit code `3`.

## Testing requirements

Implementation of `explain-path` must be accompanied by **tests that are separate from the main code**:

* All tests must live under `tests/` (for example, `tests/test_explain_path.bats`).
* The existing test harness already exists and must be reused (follow the pattern of existing Bats tests).
* No tests may be embedded inside `src/dir2prompt.sh`.

At minimum, tests must cover:

1. A file that is included by default in a simple repository with no `.promptignore` and no rules.
2. A file excluded by `.promptignore` (baseline filters).
3. A file included by a view’s include rule.
4. A file excluded because no include rule matches in a configuration where includes exist.
5. A file excluded by an explicit exclude rule.
6. A file excluded by a CLI type filter.
7. A file excluded by a max depth constraint.
8. A file excluded by a max filesize constraint.
9. A path outside `ROOT`.
10. Behaviour of `--format text`, `--format json`, and `--format both`.

Tests must assert both:

* The final status (included or excluded).
* Presence of key phrases in the explanation (for example, mentions of `.promptignore`, specific rule names, or constraint reasons).

## Documentation requirements

After implementing `explain-path`, the following documentation updates are required:

1. **README.md**

   * Add `dir2prompt explain-path` to the Usage section.
   * Add a dedicated subsection “Explaining why a path is included or excluded” with:

     * A short narrative of the feature.
     * At least two concrete examples (one included, one excluded).
     * Mention of `--format json` for automation.
   * Cross-link from any section that discusses rules and views, suggesting `explain-path` as a debugging tool.

2. **Helper strings in `src/dir2prompt.sh`**

   * Update the main `usage` function to include the `explain-path` subcommand with a concise description.
   * If there is a subcommand-specific usage function, add a dedicated `explain_path_usage` helper and wire it into the CLI.

3. **Manifest and selection documentation**

   * In `docs/manifest-spec.md`, add a short paragraph referencing `explain-path` as a finer-grained, path-level debugging tool that complements manifests.
   * In `docs/selection-algorithm-spec.md` or `docs/selection-system-spec.md`, add a brief subsection “Path-level introspection” referencing `explain-path`.

These documentation updates are part of the definition of done for this feature.
