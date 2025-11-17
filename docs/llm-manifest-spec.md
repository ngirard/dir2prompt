# LLM Manifest Specification (`docs/llm-manifest-spec.md`)

This document specifies the `--manifest=llm` mode, a feature designed to generate a natural language summary of the snapshot creation process. This summary is intended to be prepended to the main snapshot output to provide essential meta-context for a Large Language Model (LLM).

## Goals

*   To provide a concise, human-readable summary of the file selection logic.
*   To inform the LLM about the scope and intent of the provided context (e.g., is it a full project view, a focused slice on documentation, or a debug session?).
*   To reduce LLM ambiguity and hallucination by making it aware of what is *not* included in the snapshot.
*   To be robust enough to describe all major filtering scenarios, from simple ignores to complex, layered views.

## CLI Invocation

The feature is activated by passing `--manifest=llm` as a global option:

```bash
dir2prompt --manifest=llm [OPTIONS] [DIRECTORY...]
```

When used, this mode replaces the `summary` or `full` manifest output with a prose-based summary. It should appear at the very beginning of the output, before the tree or contents sections.

## Output Format and Logic

The LLM manifest is a single block of text, formatted as a Markdown blockquote. Its content is dynamically generated based on the selection parameters for each target.

The prose follows a narrative structure, explaining the filtering pipeline step-by-step.

### Content Breakdown

1.  **Preamble:** A standard opening that identifies the target directory and optional target name.
2.  **Universe:** States the total number of files found before any filtering was applied.
3.  **Baseline Filtering:** Describes the impact of baseline ignore files (`.promptignore`, `.ripgreprc`). This section is omitted if no baseline files are active or if they don't exclude any files.
4.  **View & Rule Filtering:** Describes the active view and rules.
    *   If a view is used, it names the view and its purpose (from its description).
    *   It summarizes the net effect of the rules (e.g., "focusing the context on X files").
    *   This section is omitted if no view or rules are used.
5.  **CLI Overrides:** Mentions any progressive refinements made via CLI flags (`--add-rule`, `--drop-rule`, `--add-rule-file`). This highlights the ad-hoc nature of the query.
6.  **Constraint Filtering:** Describes the impact of constraints like `--type`, `--max-depth`, and `--max-filesize`.
7.  **Final Summary:** Provides the final count of selected files and a qualitative assessment of the snapshot's scope. The qualitative assessment is key:
    *   **"a complete and unfiltered view"**: If selection count equals universe count.
    *   **"a broad overview"**: If baseline ignores are active but no other specific rules are.
    *   **"a focused slice"**: If specific include rules or type filters were used to create a narrow selection.
    *   **"a custom-defined context"**: If many ad-hoc CLI rules were layered on top.

### Example Scenarios

#### Scenario 1: Simple, Unfiltered Snapshot

*   **Command:** `dir2prompt --manifest=llm` (in a repo with 7 files and no ignore files)
*   **Output:**
    ```
    > **Context Summary for directory `.`**:
    > This snapshot was generated from a universe of 7 files. No filters were applied, resulting in a final selection of 7 files. The following context represents a complete and unfiltered view of the repository.
    ```

#### Scenario 2: Snapshot with `.promptignore`

*   **Command:** `dir2prompt --manifest=llm` (in a repo with 50 files, `.promptignore` excludes 20)
*   **Output:**
    ```
    > **Context Summary for directory `.`**:
    > This snapshot was generated from a universe of 50 files. The baseline `.promptignore` file excluded 20 build artifacts and temporary files, leaving 30 files. No other filters were applied. The following context represents a broad overview of the project's primary source files.
    ```

#### Scenario 3: Complex View with Constraints

*   **Command:** `dir2prompt --manifest=llm --view docs-deep --type md`
*   **Repo State:** 100 files total. `.promptignore` excludes 30. The `docs-deep` view has rules that select only files in the `docs/` and `README.md` files (15 files), but the `--type md` filter narrows it down to 12.
*   **Output:**
    ```
    > **Context Summary for directory `.`**:
    > This snapshot was generated from a universe of 100 files. The baseline `.promptignore` first narrowed the scope to 70 files.
    > 
    > The selection was then guided by the 'docs-deep' view ("In-depth project documentation"), which focused the context on 15 documentation files. Finally, a command-line filter for file type 'md' was applied, resulting in a final selection of 12 files. The following context represents a focused slice of the repository, specifically targeting Markdown documentation.
    ```

#### Scenario 4: View with CLI Overrides

*   **Command:** `dir2prompt --manifest=llm --view backend --add-rule-file ./temp.ignore`
*   **Repo State:** 200 files. The `backend` view selects 40 files. The `temp.ignore` file adds 2 more specific files.
*   **Output:**
    ```
    > **Context Summary for directory `.`**:
    > This snapshot was generated from a universe of 200 files, first filtered by the baseline `.promptignore`.
    > 
    > The selection was guided by the 'backend' view and then progressively refined with 1 ephemeral rule file provided on the command line. This resulted in a final selection of 42 files. The following context represents a custom-defined context for a specific task.
    ```
