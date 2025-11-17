# Selection algorithm (`docs/selection-algorithm-spec.md`)

This section defines how dir2prompt computes the file list for each target, in terms of rules, views, and `fd`.

## Universe of candidate files

For each target directory `D`:

1. Run `fd` in `D` to enumerate all candidate files:

   * `fd` is invoked with:

     * The target directory as the search root.
     * Default ignore behaviour enabled (respect `.gitignore`, `.ignore`, `.fdignore`).
     * Optional `--follow` if symlink following is enabled.
     * Optional `--max-depth` and `--size` derived from constraints.
2. Pipe the output through `LC_ALL=C sort` to obtain a deterministic, lexicographically ordered list of paths.

The result is the **universe** `U` of candidate files for that target.

## Rule and view resolution

For a given target:

1. Determine the base view:

   * If `--view <NAME>` was specified, use `<NAME>`.
   * Else, if a `default` view is defined in configuration, use `default`.
   * Else, operate as if there were no view and no configured rules for this target.

2. Load the list of rule names from the base view.

3. Apply CLI layering:

   * Remove any rules named in `--drop-rule <NAME>`.
   * Add any rules named in `--add-rule <NAME>`.
   * Add one or more ephemeral rules corresponding to each `--add-rule-file <PATH>`.

4. For each active named rule:

   * Read its rule file.
   * Parse it into `Inc(R)` and `Exc(R)` as described earlier.

5. For each ephemeral rule:

   * Read the file passed in `--add-rule-file`.
   * Parse it into `Inc(R)` and `Exc(R)`.

6. Compute the combined include and exclude sets:

   * `Inc = ⋃ Inc(Rᵢ)` over all active rules.
   * `Exc = ⋃ Exc(Rᵢ)` over all active rules.

7. Handle `.promptignore` baseline:

   * When a `.promptignore` file exists in the target directory or in the git root:

     * It may be treated as an implicit rule (for example, named `promptignore`) or may be integrated directly via `fd --ignore-file`.
   * The exact integration strategy must preserve current behaviour:

     * Files ignored by `.promptignore` in the current version of dir2prompt must continue to be excluded unless explicitly overridden in a future revision.
   * A configuration or CLI switch such as `--no-baseline-ignore` may later be introduced; it is not required for the first iteration.

## Applying patterns to the universe

Given the universe `U`, the combined include set `Inc`, and the combined exclude set `Exc`:

1. If `Inc` is non-empty:

   * The intermediate set `S` is the subset of `U` that matches at least one include pattern in `Inc`.

2. If `Inc` is empty:

   * The intermediate set `S` is equal to `U`.

3. The final selection `F` is obtained by removing all paths that match any exclude pattern in `Exc`:

   * `F = S \ Exc`.

4. Constraints from views and CLI options (`max_depth`, `max_filesize`, `--type`) are applied when building `U` via `fd` so that they are consistent with the rule-based filtering.

The ordering of `F` is the sorted order inherited from `U`.

## Mapping to `fd` options

Implementation details are flexible as long as the semantics above are respected. A typical mapping is:

* Use `fd` with multiple `--glob` patterns for includes.
* Use `fd --exclude` or negative globs for excludes.
* Use `--max-depth` and `--size` for constraints.
* Always pipe into `LC_ALL=C sort`.
