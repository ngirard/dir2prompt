# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Multi target cli support.
- `--manifest`.
- Rules and views.
- New files selection system using `fd` instead of `rg` for discovery.

## [0.3.1] - 2025-11-17
### Fixed
- `--ignore-file` paths are now resolved relative to the directory where `dir2prompt` is invoked, preventing ripgrep errors when targeting nested directories (e.g., `dir2prompt --ignore-file testignore.txt ./docs`).

### Added
- Regression tests covering relative and absolute `--ignore-file` paths and documentation clarifying the new semantics.

## [0.3.0] - 2025-11-16
### Added
- `--output <FILE>` option: Write dir2prompt output to a file instead of stdout.
- Automatic ripgrep configuration file (`.ripgreprc`) support: `dir2prompt` now detects `.ripgreprc` at the git repository root and automatically sets the `RIPGREP_CONFIG_PATH` environment variable, allowing project-level ripgrep customization (e.g., `--follow` for symlinks, custom type definitions).
- Test coverage for explicit `--ignore-file` precedence and git-root `.promptignore` fallback.
- README guidance explaining ignore-file layering and how to combine multiple custom ignore files.
- Unit tests for `.ripgreprc` support, including tests for custom type definitions and `--follow` flag behavior.
- Unit tests for `--output` option with various modes (tree-only, contents-only, both).
### Changed
- README installation instructions now reference the generated `dir2prompt.sh` artifact and match nfpm packaging output.
- CLI usage text documents the repeatable `--ignore-file` flag and its override semantics.
### Fixed
- Fix argument passing bug that dropped all filter options.

## [0.2.4] - 2025-11-14

### Fixed
- Fixed binaries prefix in packaged artifacts.

## [0.2.3] - 2025-11-14

### Changed
- Improved ignore file handling logic:
  - When `--ignore-file` option(s) are provided, only those files are used (no automatic .promptignore detection)
  - When no `--ignore-file` is provided, automatically searches for .promptignore in current directory first, then in git repository root
  - Multiple `--ignore-file` options can now be specified

## [0.2.2] - 2025-11-14

### Changed
- GitHub CI/CD integration

