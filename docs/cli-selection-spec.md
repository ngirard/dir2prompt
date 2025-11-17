# CLI extensions for views and rules (`docs/cli-selection-spec.md`)

This section describes new CLI options and the `rules` subcommand. Names are suggestions and can be adjusted.

## Core dir2prompt options (main command)

The existing `dir2prompt` interface is extended with the following options, in both simple and per-target modes.

### View selection

* `--view <NAME>`
  Selects a named view from `.dir2prompt/views.yml` for this invocation.

  * In simple multi-directory mode, the same view applies to all target directories.
  * In target mode, `--view` can be specified per target.

If `--view` is not provided, and a `default` view exists, it is used. If no views exist, selection falls back to baseline behaviour.

### Rule layering (progressive refinement)

These options enable progressive refinement on top of a base view:

* `--add-rule <NAME>`
  Activates an additional named rule for this target, in addition to those specified by the view.

* `--drop-rule <NAME>`
  Deactivates a named rule that would otherwise be active via the view.

* `--add-rule-file <PATH>`
  Loads patterns from a gitignore-style file for this invocation only as an ephemeral rule. The file is not added to `.dir2prompt/views.yml`. The rule is anonymous and has no name, but its patterns contribute to the overall include and exclude sets.

These options are interpreted per target. In target mode they can appear after each `--target` block.

### Symlink behaviour

* `--follow-symlinks`
  Enables following symbolic links for this target. When active, dir2prompt passes `--follow` to `fd`.

* `--no-follow-symlinks`
  Explicitly disables following symbolic links, overriding any view-level `follow_symlinks: true`.

If neither flag is provided and the view has no explicit `follow_symlinks`, the default is not to follow symlinks.

### Interaction with existing options

* `--max-depth`, `--max-filesize` continue to exist and can appear globally or per target.

  * When both view-level and CLI-level constraints are present, the CLI-level values take precedence.
* `--type` remains supported, now interpreted in terms of `fd`’s types rather than `rg`’s type system.

  * The mapping is implementation-defined but must be documented in the README.

### Optional manifest

* `--manifest[=MODE]` (optional feature)
  When provided, dir2prompt emits a human- and machine-readable manifest describing the selection.

  * Possible modes (to be refined later): `summary` (default), `full`, `off`.
  * If `--manifest` is absent, no manifest is printed and the output format matches the current behaviour.

Manifest details are not required for core functionality and can be implemented in a later phase.

## `rules` subcommand (`dir2prompt rules`)

The `rules` subcommand manages rules and views using gitignore syntax as input.

Suggested syntax:

```bash
dir2prompt rules add <RULE_NAME> [OPTIONS]
dir2prompt rules list
dir2prompt rules show <RULE_NAME>
```

### `rules add`

Usage:

```bash
dir2prompt rules add <RULE_NAME> \
  [--description <TEXT>] \
  [--from-file <PATH>] \
  [--view <VIEW_NAME>] \
  [--base-view <BASE_VIEW_NAME>]
```

Semantics:

* If `--from-file` is provided:

  * Read gitignore patterns from `<PATH>`.

* If `--from-file` is omitted:

  * Read gitignore patterns from stdin until EOF.

* Write the patterns into `.dir2prompt/rules/<RULE_NAME>.ignore`, overwriting any existing file with the same name.

* Ensure `.dir2prompt/views.yml` exists, creating it if necessary.

* Under `rules`, create or update the entry:

  ```yaml
  rules:
    <RULE_NAME>:
      description: <TEXT if provided>
      file: ".dir2prompt/rules/<RULE_NAME>.ignore"
  ```

* If `--view <VIEW_NAME>` is provided:

  * Ensure `views.<VIEW_NAME>` exists.
  * If `--base-view <BASE_VIEW_NAME>` is provided:

    * If `<VIEW_NAME>` does not exist, create it with `rules` equal to `views.<BASE_VIEW_NAME>.rules + [<RULE_NAME>]`.
    * If `<VIEW_NAME>` exists, update its `rules` to `views.<BASE_VIEW_NAME>.rules + [<RULE_NAME>]`, replacing any previous list.
  * If `--base-view` is omitted:

    * If `<VIEW_NAME>` does not exist, create it with `rules: [<RULE_NAME>]`.
    * If `<VIEW_NAME>` exists, append `<RULE_NAME>` to its `rules` list if not already present.

`rules add` returns a non-zero exit code if:

* `<RULE_NAME>` is invalid (for example, contains path separators), or
* `--base-view` is specified but the base view does not exist, or
* the configuration file is present but malformed.

### `rules list`

Usage:

```bash
dir2prompt rules list
```

Output:

* A human-readable list of known rules and views, for example:

  ```text
  Rules:
    baseline        Default project slice for general understanding.
    design-core     Most important design docs.
    tests-smoke     Only high-level, fast tests.

  Views:
    default         Rules: baseline
    design          Rules: baseline, design-core
    tests-focused   Rules: baseline, tests-smoke
  ```

The exact formatting is at the implementation’s discretion.

### `rules show`

Usage:

```bash
dir2prompt rules show <RULE_NAME>
```

Output:

* The path to the rule file and its current contents:

  ```text
  Rule: design-core
  File: .dir2prompt/rules/design-core.ignore

  # contents follow
  !docs/design/**
  !docs/architecture/**
  !README.md
  !docs/ADR/**/*.md
  docs/design/old/**
  ```

This command is purely for inspection and does not modify anything.

