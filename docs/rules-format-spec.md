# Rule file syntax (`docs/rules-format-spec.md`)

## Format

Each rule is stored in a gitignore-style file:

* Filename: `.dir2prompt/rules/<rule-name>.ignore`.
* Encoding: UTF-8 text.
* Line-oriented semantics compatible with `.gitignore`.

Each line is interpreted as follows:

* Empty lines are ignored.
* Lines starting with `#` are comments.
* Lines starting with `!` are **include** patterns.
* All other non-empty lines are **exclude** patterns.

The syntax and matching behaviour of patterns (globs, `**`, path separators) follow the standard gitignore rules as closely as feasible.

## Derived sets

For a given rule file `R`:

* `Inc(R)` is the set of paths matching any include pattern (`!pattern`, with the `!` removed for matching).
* `Exc(R)` is the set of paths matching any exclude pattern (non-`!` lines).

There is no implicit ordering or precedence inside a rule at the semantic level; dir2prompt treats each rule as the pair `(Inc(R), Exc(R))`.

## Examples

Pure blacklist rule:

```text
# .dir2prompt/rules/baseline.ignore
node_modules/**
.git/**
build/**
.DS_Store
```

Pure whitelist rule:

```text
# .dir2prompt/rules/tests-focus.ignore
*
!tests/integration/**
!tests/smoke/**
```

Mixed rule:

```text
# .dir2prompt/rules/design-core.ignore
docs/design/old/**
!docs/design/**
!docs/architecture/**
!README.md
!docs/ADR/**/*.md
```

## Views and rules configuration (`.dir2prompt/views.yml` schema)

### Top-level structure

The configuration file is YAML with the following shape:

```yaml
rules:
  <rule-name>:
    description: <string, optional>
    file: <string, required path to .ignore file relative to repo root>

views:
  <view-name>:
    description: <string, optional>
    rules: [<rule-name>, ...]
    follow_symlinks: <boolean, optional>
    max_depth: <integer, optional>
    max_filesize: <integer, optional, bytes>
    # future extensions: type filters etc.
```

### Rules

For each entry under `rules`:

* `<rule-name>` is a stable identifier usable from the CLI.
* `description` is free-form human text.
* `file` points to the gitignore-style rule file (typically under `.dir2prompt/rules/` but not enforced by the schema).

dir2prompt must report an error if a rule name is referenced but its `file` is missing or unreadable.

### Views

For each entry under `views`:

* `rules` is an ordered list of rule names.
* `description` is optional human text.
* `follow_symlinks`, `max_depth`, `max_filesize` are optional constraints that apply to this view by default.

Constraints may be overridden by per-target CLI options.

### Baseline view

* If there is a view named `default`, dir2prompt treats it as the baseline view when no `--view` is specified.
* If there is no `default` view, dir2prompt behaves as if a trivial view with no rules were defined, subject to `.promptignore` behaviour described later.
