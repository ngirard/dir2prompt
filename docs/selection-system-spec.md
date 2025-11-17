# Specification overview (`docs/selection-system-spec.md`)

## Goals

This specification defines:

* How dir2prompt selects files using `fd` instead of `rg` for discovery.
* How selections are expressed as composable, semantic rule sets backed by gitignore-style files.
* How named views are defined as combinations of rules.
* How the `rules` subcommand ingests gitignore syntax and updates the configuration.
* How progressive refinement is enabled via the CLI.

The manifest that describes selection is defined as an optional feature and is disabled by default.

## Non-goals

This specification does not:

* Change the directory tree and contents output format beyond the optional manifest.
* Change the meaning of existing options unless explicitly stated.
* Require users to adopt rules or views; the legacy behaviour remains available when no configuration exists.

---

# Terminology (`docs/selection-system-spec.md`)

* **Rule**: a named set of include and exclude patterns written in gitignore syntax, with an optional description.
* **View**: a named combination of one or more rules that defines a reusable selection slice for dir2prompt.
* **Ephemeral rule**: a rule loaded from a file or stdin for a single invocation, not persisted in configuration.
* **Baseline view**: the default view used when no `--view` is specified (by default, `default` when defined).
* **Universe**: the set of all files that `fd` considers in a target directory before rule application.

---

# File layout (`.dir2prompt` directory layout)

Configuration files and rule files live under a dedicated directory at the project root:

* Primary configuration file:

  * `.dir2prompt/views.yml` (or `.dir2prompt/views.yaml`)
* Rule files:

  * `.dir2prompt/rules/<rule-name>.ignore`

The `.dir2prompt` directory is optional. When it is absent, dir2prompt behaves as today (with `fd` replacing `rg` for file discovery, subject to compatibility requirements).

