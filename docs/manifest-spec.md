# Optional manifest specification (`docs/manifest-spec.md`)

The manifest is optional and is emitted only when explicitly requested via `--manifest`. For the purposes of this specification it is enough to define its high-level content; exact formatting and modes may evolve.

## Content

For each target, the manifest may include:

* Target directory path.
* Name of the view used (if any).
* List of active rule names and their descriptions.
* List of ephemeral rule files, if any.
* Whether symlinks are followed.
* Effective constraints:

  * Maximum depth.
  * Maximum file size.
  * Type filters.
* Optional counts:

  * Number of files in the universe `U`.
  * Number of files in the final selection `F`.

Manifest sections should precede the tree and contents sections when present. `--manifest` enables the summary view described above, while `--manifest=full` additionally enumerates every file selected for the target to aid deterministic diffing or downstream tooling. `--manifest=llm` switches to the narrative format defined in [`docs/llm-manifest-spec.md`](./llm-manifest-spec.md), emitting a Markdown blockquote that explains how the snapshot was assembled (true universe, baseline filters, view/rule intent, CLI overrides, and final scope) so that downstream LLMs can reason about omissions.

## Default

* If `--manifest` is absent, no manifest is printed.
* The manifest relies on the fd-based selection engine. When forcing `DIR2PROMPT_FINDER=rg`, the flag is rejected to avoid divergent behaviour.
* `--manifest=full` is optional but reserved for workflows that need a complete file listing. Today it emits a plaintext bullet list matching the selection order.
* `--manifest=llm` follows the same dependency restrictions as the other modes but renders narrative prose per the dedicated [`llm-manifest` specification](./llm-manifest-spec.md).
