# Strategy: implementing the `dir2prompt explain-path` feature

This document describes the step-by-step strategy for implementing the `dir2prompt explain-path` feature specified in `Specification.md`.

It is written for an LLM agent that has access to the repository, including `src/dir2prompt.sh` and the existing specification documents, but should be understandable to a human maintainer as well.


## Mission preamble

Your mission is to implement a new `dir2prompt explain-path` subcommand that explains, for one or more paths, why each is included or excluded from a snapshot under a given selection configuration.

You must:

- Reuse the existing selection system (views, rules, baseline ignores, CLI overlays).
- Provide human-readable explanations and optional JSON output.
- Keep tests separate from the main code (a Bats test harness already exists).
- Update the user-facing documentation (`README.md` and CLI helper strings) accordingly.


## Context: the pain point and brainstorming

### The pain point

dir2prompt already helps users and LLMs construct rich repository snapshots. A typical workflow for a “perfect context” looks like:

1. The user wants a specific slice, such as:
   - “Everything needed to debug the HTTP handlers, but not migrations or front-end assets.”
   - “Only architecture docs and ADRs.”
   - “Only fast, high-level tests.”
2. They tweak `.promptignore`, `.dir2prompt` views, rules, or CLI flags.
3. They run `dir2prompt` and get:
   - A tree of selected files.
   - Contents of non-binary files.
   - Optional manifest (including `--manifest=llm`).

What is missing is **fine-grained feedback**:

- When a file they care about is missing, they do not know why.
- When an unwanted file appears, they do not know which rule or constraint failed to filter it.
- The LLM cannot easily tell whether a context is “missing pieces” or how to refine the selection rules.

For humans, this leads to trial and error. For LLM agents trying to systematically build a good view of a repository, it is worse: they cannot introspect on the selection pipeline and so struggle to improve it.

### Brainstormed solution directions

During design, several ideas naturally come up:

1. **Beef up the manifest** so that it includes per-file explanations.
   - Problem: the manifest is already a snapshot-level object; per-file explanations would explode its size and complexity.
   - It is also harder to integrate into interactive or tooling workflows where you only care about a handful of files.

2. **Add a debug mode to `dir2prompt`** that prints trace information while building the selection.
   - Problem: this is noisy and hard to parse, and it does not compose well with LLM tooling.

3. **Provide a dedicated explain mode** that focuses only on paths of interest.
   - You feed it a path and config; it tells you why that path does or does not make it into the snapshot.
   - This aligns well with how humans and LLMs think: “why is this file missing?” or “why is this test included?”.

The third option is the most promising. It separates concerns cleanly:

- Snapshots: “which files are in the context?”
- Manifests: “how was the context as a whole constructed?”
- Explain-path: “why is this particular file in or out of the context?”


## High-level approach

The `explain-path` feature should be implemented as:

1. A new subcommand:

   ```bash
   dir2prompt explain-path [SELECTION_OPTIONS] [--dir ROOT] PATH [PATH...]
   ````

2. A thin CLI layer that:

   * Reuses as much of the existing selection parsing as possible (to avoid having two separate parsers).
   * Resolves `ROOT` and paths.
   * Determines which selection configuration to simulate.

3. A reusable **analysis core** that, given:

   * A root directory.
   * A selection configuration (view, rules, ignore files, constraints, symlink behaviour).
   * One or more paths.

   returns structured per-path explanations based on the same semantics as `build_final_selection`.

4. Two renderers:

   * A text renderer that produces Markdown output per path.
   * A JSON renderer that produces a machine-readable document.

Tests will validate behaviour end-to-end using fixtures and the existing Bats harness.

Documentation must be updated to teach users (and LLMs) how to use this feature as part of their “iteratively refine the view” workflow.

## Implementation plan

### Step 1: understand and respect existing selection semantics

Before writing code, you should re-familiarize yourself with:

* `docs/selection-algorithm-spec.md`
* `docs/selection-system-spec.md`
* `docs/rules-format-spec.md`
* `docs/manifest-spec.md`
* `docs/llm-manifest-spec.md`
* `build_final_selection` in `src/dir2prompt.sh`
* `_enumerate_true_universe`, `apply_pattern_filters`, and related helpers.

Key points to keep in mind:

* The universe `U` is computed using `_enumerate_true_universe` with fd-based selection.
* Baseline filters (`.promptignore`, `.ripgreprc`) are applied first.
* View and rule combinations are translated into include and exclude pattern sets, then applied via `apply_pattern_filters`.
* Ephemeral rules and CLI ignore files are folded into the same include and exclude pattern sets.
* CLI constraints (type, depth, size, symlink behaviour) are applied at universe enumeration time.
* `DIR2PROMPT_LAST_SELECTION_META` already stores useful aggregate metadata for manifest generation.

Explain-path must **reuse these semantics exactly** so that explanations match the actual snapshot behaviour.

### Step 2: factor out a reusable “selection context” abstraction

To avoid duplicating logic between `build_final_selection` and `explain-path`, you should introduce a small internal abstraction that captures the **selection context** for a single target:

* Effective root directory.
* Effective `types` (serialized).
* Effective `max_depth` and `max_filesize`.
* Resolved ignore files:

  * Active ignore files (including CLI and baseline).
  * Baseline-only ignore files.
* Active view and rules, including:

  * Resolved `view_name`.
  * Active rule names after `--add-rule` and `--drop-rule`.
* Ephemeral rule files and CLI ignore files.
* Ripgrep configuration (`.ripgreprc`) and its derived include/exclude globs.
* Effective symlink behaviour.

You do **not** need a full-blown struct or class (this is Bash), but you can represent it with:

* A small set of local variables.
* One or two helper functions that:

  ```bash
  # Given dir + CLI args, fills out local variables describing the context.
  build_selection_context_for_dir ...
  ```

Then:

* `build_final_selection` calls this function and uses the resulting context to:

  * Enumerate `U`.
  * Build the final selection.
  * Populate `DIR2PROMPT_LAST_SELECTION_META`.

* `explain-path` calls the same function to obtain a context that it can analyze per path.

This refactoring step should be done with care:

* After the change, all existing tests must still pass.
* The behaviour of `build_final_selection` must remain unchanged (including metadata fields).
* You can split `build_final_selection` into:

  * A context-building part.
  * The actual selection-building part.

This step is critical because it sets up explain-path as a “consumer” of the existing selection logic, not a separate system.

### Step 3: introduce an internal per-path analysis helper

Implement an internal helper function, for example:

```bash
# Analyze the fate of a single candidate path under a selection context.
# Arguments:
#   1: absolute root directory
#   2: relative path under root (as used in selection arrays)
#   3+: additional context (for example, arrays of patterns and rules)
#
# The function should populate an associative array (passed by name) with:
#   - final_status: "included" or "excluded"
#   - final_reason: textual label
#   - phase_*: structured annotations per phase
analyze_path_fate ...
```

Because Bash is awkward for rich data structures, you can use:

* Associative arrays for the per-path result (for example, `declare -A PATH_ANALYSIS`).
* Small serialized lists using the same `LIST_SEPARATOR` idiom as elsewhere.

The helper should follow the same phases as `build_final_selection`:

1. **Universe**:

   * It may use the already computed `universe` array when called from a context that has it.
   * Alternatively, it may call `_enumerate_true_universe` once and keep the result in a local cache.
   * Determine whether the relative path is in `U`, whether it exists on disk, and whether it appears to be excluded by constraints.

2. **Baseline filters**:

   * Use baseline include and exclude patterns precomputed from `.promptignore` and `.ripgreprc`.
   * Call `apply_pattern_filters` with a one-element array `[path]` and these patterns.
   * Capture matching include and exclude patterns.

3. **View and named rules**:

   * Use the already precomputed rule includes and excludes from `DIR2PROMPT_RULE_INCLUDES` and `DIR2PROMPT_RULE_EXCLUDES`.
   * For each active rule:

     * Determine whether the path matches any include or exclude pattern.
   * Compute whether global `Inc` and `Exc` admit or remove the path.

4. **Ephemeral rules and CLI ignore files**:

   * For each ephemeral rule file and each CLI ignore file:

     * Parse includes and excludes on demand (or reuse the parse results from `build_final_selection` if they are available).
     * Determine whether the path matches any of their patterns.

5. **Constraints**:

   * Determine the path’s depth relative to ROOT.
   * Determine its extension and size.
   * Compare against `types`, `max_depth`, and `max_filesize`.

The helper must return enough information for both the text and JSON renderers to build detailed explanations without recomputing selection logic.

You should **not** try to reconstruct every intermediate set (for example, `S = U ∩ Inc`) for all files. Instead, focus on the single candidate path and simulate the pipeline for it.

### Step 4: wire in the `explain-path` subcommand

Add a new subcommand to the CLI:

1. Extend the subcommand dispatch near the bottom of `src/dir2prompt.sh`:

   ```bash
   if [[ "${1:-}" == "rules" ]]; then
       ...
   fi

   if [[ "${1:-}" == "explain-path" ]]; then
       shift
       handle_explain_path_subcommand "$@"
       exit 0
   fi
   ```

2. Implement `handle_explain_path_subcommand`:

   * It should:

     * Accept the selection-related flags from the specification.
     * Accept an optional `--dir ROOT`.
     * Accept `PATH` arguments at the end.
     * Validate that at least one `PATH` is provided.
   * It can reuse parts of `parse_arguments` logic by:

     * Either refactoring shared pieces into smaller helpers.
     * Or duplicating a minimal subset of parsing for this subcommand (acceptable if kept well-contained and consistent).

3. For this subcommand, do **not** call `parse_arguments` and `main`. Instead:

   * Resolve `ROOT`.
   * Build a selection context for ROOT using the same logic that `process_target` uses today.
   * For each requested `PATH`:

     * Resolve it to absolute and relative forms.
     * Run `analyze_path_fate` with the selection context.
   * Collect the per-path results into a small in-memory structure that both renderers can consume.

4. Implement `--format` handling:

   * Add `--format text|json|both` parsing.
   * If an unknown format is provided, return an error.
   * Decide whether to run text first, then JSON, or only one renderer, based on the format.

### Step 5: implement the text renderer

Implement a function, for example:

```bash
render_explain_path_text() {
    local root="$1"
    shift
    # remaining arguments can be serialized per-path analysis results
}
```

For each path analysis:

* Print the heading.
* Print the final status line.
* Print a short summary paragraph (you can derive this from `final_status` and `final_reason`).
* Print per-phase sections with bullet lists.

Important stylistic considerations:

* Use sentence case for headings and prose.
* Use backticks for paths and patterns where appropriate.
* Avoid telegraphic bullet points; use short explanatory sentences.
* Ensure the output is easy to read in a terminal and also easy to paste into an LLM prompt.

You do not need to be verbose for trivial cases; you can omit entire sections (for example, “view and named rules”) when there are no views or rules involved.

### Step 6: implement the JSON renderer

Implement a function, for example:

```bash
render_explain_path_json() {
    local root="$1"
    shift
    # serialize the per-path analysis results into the schema defined in Specification.md
}
```

Because you are in Bash, constructing JSON is somewhat painful. However, the schema is relatively simple per path and per phase, so you can:

* Escape strings carefully.
* Use consistent ordering of keys.
* Construct the JSON document as a series of `printf` statements.

You do not need a dependency on `jq` or similar tools.

The JSON renderer must:

* Emit a single JSON object at top-level.
* Include the root and options summary.
* Include a `paths` array with one object per analyzed path.

If both renderers are requested (`--format both`), call the text renderer first, print a blank line, then call the JSON renderer.

### Step 7: add tests (separate from code)

All tests for this feature must be placed under `tests/` and must **not** be mixed with production code.

You should:

1. Create a new test file, for example:

   ```text
   tests/test_explain_path.bats
   ```

2. Follow the patterns of existing Bats tests in the repository (test naming, fixture setup, assertions).

3. Add fixtures as needed under the existing test fixture directories; do not embed large fixtures in the test file itself if avoidable.

The test suite must cover at least:

* Inclusion and exclusion in a simple repository with no `.promptignore`.
* Exclusion by `.promptignore`.
* Inclusion by a view’s include rules.
* Exclusion due to lack of include matches when includes exist.
* Exclusion by an explicit exclude rule.
* Exclusion by `--type`.
* Exclusion by `--max-depth`.
* Exclusion by `--max-filesize`.
* Paths outside ROOT.
* `--format text`, `--format json`, and `--format both`.

For each test, assert both:

* The command’s exit status.
* Presence of key phrases in the output indicating the correct path and reason.

If there is an existing “test harness” (helper scripts, fixtures, or helper functions in Bats), reuse them rather than reinventing common patterns such as setting up a temporary fixture repo.

### Step 8: update documentation and helper strings

After the code and tests work, you must update the documentation.

1. **README.md**

   * In the Usage section, add a new subsection:

     ````markdown
     ### Explaining why a path is included or excluded

     The `explain-path` subcommand lets you debug why a given file appears (or does not appear) in a snapshot.

     ```bash
     # Explain why a single file is in or out of the default view
     dir2prompt explain-path src/server/http_handler.py

     # Explain why a file is excluded when using a specific view and type filter
     dir2prompt explain-path --view backend --type py --dir . src/server/http_handler.py

     # Get machine-readable output for tooling
     dir2prompt explain-path --view docs-deep --format json docs/cli-selection-spec.md
     ````

     ```
     ```
   * Mention briefly that `explain-path` is a good companion to `--manifest=llm` when iteratively refining rules and views.

2. **Helper strings in `src/dir2prompt.sh`**

   * Update the main `usage` function to list `explain-path` alongside existing subcommands:

     * Add a short description such as “Explain why a path is included or excluded under the current rules and views”.

   * If you introduce an `explain_path_usage` function, ensure it is reachable via both:

     * `dir2prompt explain-path --help`
     * `dir2prompt --help` (which can reference the subcommand).

3. **Specification cross-references**

   * If appropriate, add small paragraphs to `docs/selection-algorithm-spec.md` or `docs/selection-system-spec.md` explaining that `explain-path` reuses the same semantics and is the recommended tool for understanding path-level behaviour.

4. **LLM manifest spec**

   * In `docs/manifest-spec.md` or `docs/llm-manifest-spec.md`, add one or two sentences noting that `explain-path` is the per-path counterpart to the snapshot-level manifest, and that both can be combined in LLM workflows.

### Step 9: sanity checks and polishing

Before considering the feature done, perform the following checks:

* Run the full test suite (including existing tests) and ensure everything passes.
* Manually try a few scenarios:

  * Simple repo with no `.promptignore` and no `.dir2prompt`.
  * Repo with `.promptignore`.
  * Repo with `.dir2prompt` views and multiple rules.
  * Using `--ignore-file` to override `.promptignore`.
  * Using `--add-rule` and `--drop-rule`.
  * Using multiple `PATH` arguments.

During manual testing, pay attention to:

* Whether the explanations feel clear and concise.
* Whether the final status and phase breakdown align with your expectations.
* Whether the JSON output matches the schema described in `Specification.md`.

Adjust text phrasing as needed to keep explanations readable without being overly verbose.

## Risks and mitigations

* **Risk: duplicated logic between `build_final_selection` and explain-path.**
  Mitigation: factor out shared context-building helpers early and reuse them.

* **Risk: drift between selection semantics and explain semantics.**
  Mitigation: rely on the same helper functions and pattern translation; avoid reimplementing pattern matching.

* **Risk: Bash’s limited data structures make JSON construction fragile.**
  Mitigation: keep the schema simple; escape strings carefully; write targeted tests for JSON output.

* **Risk: CLI parsing for the subcommand diverges from the main path.**
  Mitigation: reuse argument parsing utilities or share the constraint and view parsing logic where practical.

## Definition of done checklist

Use this checklist to validate completion:

* [ ] Selection context logic factored out so that both `build_final_selection` and explain-path share it.
* [ ] New `handle_explain_path_subcommand` implemented and wired into CLI dispatch.
* [ ] Per-path analysis helper implemented, covering:

  * [ ] Universe membership.
  * [ ] Baseline filters (`.promptignore`, `.ripgreprc`).
  * [ ] View and named rules.
  * [ ] Ephemeral rules and CLI ignore files.
  * [ ] CLI constraints (`--type`, `--max-depth`, `--max-filesize`).
* [ ] Text renderer implemented and produces clear, structured Markdown per path.
* [ ] JSON renderer implemented with the documented schema.
* [ ] Tests added under `tests/` (no tests inside `src/dir2prompt.sh`), covering all key scenarios.
* [ ] All existing tests continue to pass.
* [ ] README updated with the new subcommand and examples.
* [ ] Helper usage strings updated to mention `explain-path`.
* [ ] Optional cross-references added to manifest and selection docs.
* [ ] Manual smoke testing performed in representative repositories.

When all checklist items are satisfied, the `dir2prompt explain-path` feature can be considered implemented and ready for use by humans and LLM agents to iteratively refine repository snapshots.
