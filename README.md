# dir2prompt

Generate a prompt string for your shell based on the current directory structure and contents.

## Description

`dir2prompt` is a command-line tool that creates a snapshot of a directory's structure and contents, suitable for use in Large Language Model (LLM) prompts. It provides a concise way to represent your project's structure and file contents, making it easier to discuss code or project layouts with AI assistants.

## Features

- Generate a tree-like representation of directory structure
- Display contents of non-binary files
- Customizable file type filtering
- Limit directory traversal depth
- Ignore files larger than a specified size
- Use custom ignore files to exclude certain files or directories

## Dependencies

- `rg` (ripgrep): Required for efficient file searching
- `tree`: Required for directory tree visualization

## Installation

```bash
# Install dependencies
# On Ubuntu/Debian:
sudo apt-get install ripgrep tree

# On macOS with Homebrew:
brew install ripgrep tree

# On Fedora/RHEL:
sudo dnf install ripgrep tree

# For other systems, please refer to the ripgrep and tree installation guides

# Clone the repository
git clone https://github.com/yourusername/dir2prompt.git

# Navigate to the project directory
cd dir2prompt

# Build the project (requires 'just' command)
just build

# Install the executable (may require sudo)
# The build step produces build/dir2prompt.sh; install it under the name "dir2prompt"
sudo install -m 0755 build/dir2prompt.sh /usr/local/bin/dir2prompt
```

Binary packages built with nfpm follow the same convention and place the script on your PATH as `dir2prompt` (without the `.sh` suffix).

## Usage

### Basic Usage

```
Usage: dir2prompt [OPTIONS] [DIRECTORY...]
       dir2prompt [GLOBAL_OPTIONS] --target NAME --dir PATH [TARGET_OPTIONS]...

Global Options:
  --contents-only        Display only the contents of non-binary files.
  --help                 Display this help message.
  --output <FILE>        Write output to FILE instead of stdout.
  --tree-only            Display only the directory tree.

Target Options (can be global defaults or per-target):
  --ignore-file <FILE>   Repeatable. Use custom ignore file(s) and skip automatic .promptignore detection.
                         Relative paths are resolved from the directory where dir2prompt is invoked.
  --max-depth <NUM>      Limit the depth of directory traversal.
  --max-filesize <NUM>   Ignore files larger than NUM in size.
  --type <TYPE>          Limit search to files matching the given type.

If no directory is specified, the current directory is used.
```

### Multi-Directory Support

`dir2prompt` supports two modes for processing multiple directories:

#### Simple Multi-Directory Mode

Process multiple directories with the same options:

```bash
dir2prompt [OPTIONS] dir1 dir2 dir3
```

All directories share the same target options (--type, --max-depth, --max-filesize, --ignore-file).

#### Advanced Per-Target Mode

Process multiple directories with different options for each:

```bash
dir2prompt [GLOBAL_OPTIONS] \
  --target NAME --dir PATH [TARGET_OPTIONS] \
  --target NAME --dir PATH [TARGET_OPTIONS]
```

- Each `--target NAME --dir PATH` block defines a separate target
- Target options following each block apply only to that target
- Global target options before the first `--target` become defaults for all targets
- Per-target options override defaults for that specific target

**Note:** You cannot mix positional directories with `--target` mode.

## Examples

### Basic Examples

1. Generate a snapshot of the current directory:

   ```bash
   dir2prompt
   ```

2. Display only the directory tree for a specific folder:

   ```bash
   dir2prompt --tree-only /path/to/your/project
   ```

3. Show contents of only Python files, limited to a depth of 2:

   ```bash
   dir2prompt --type py --max-depth 2
   ```

4. Use a custom ignore file:

   ```bash
   dir2prompt --ignore-file /path/to/custom/ignorefile
   ```

5. Reuse an ignore file stored in your project root while inspecting a subdirectory:

   ```bash
   # Run from the project root
   dir2prompt --ignore-file testignore.txt ./docs
   ```

### Multi-Directory Examples

6. Process multiple directories with shared options:

   ```bash
   # Snapshot both src and tests directories
   dir2prompt src tests
   ```

7. Process multiple directories with a shared type filter:

   ```bash
   # Show only Python files from multiple directories
   dir2prompt --type py src tests examples
   ```

8. Advanced mode with per-target configuration:

   ```bash
   # Different filters for different directories
   dir2prompt \
     --target src_code --dir src --type py \
     --target docs --dir docs --type md \
     --target tests --dir tests --max-depth 2
   ```

9. Using default options with per-target overrides:

   ```bash
   # All targets use --type py by default, but tests directory overrides it
   dir2prompt --type py \
     --target main --dir src \
     --target test --dir tests --type pytest
   ```

10. Write multi-directory output to a file:

    ```bash
    dir2prompt --output snapshot.txt src docs tests
    ```

## Ignoring files

`dir2prompt` supports a layered ignore strategy so you can swap between a default view of a project and bespoke queries without editing files in place:

1. **Explicit `--ignore-file` flags take precedence.** When you pass one or more `--ignore-file <FILE>` options (the flag is repeatable), only those files are honored and the automatic `.promptignore` detection is skipped. Relative paths are interpreted from the directory where you invoke `dir2prompt`, so you can keep ignore files (for example `testignore.txt`) at the repository root and reuse them while snapshotting nested folders such as `dir2prompt --ignore-file testignore.txt ./docs`. This makes it possible to describe alternate “queries” for the same repository without having to touch the canonical `.promptignore`.
2. **Project defaults live in `.promptignore`.** If no `--ignore-file` flag is provided, `dir2prompt` first checks the target directory for `.promptignore`.
3. **Git root fallback.** Still no match? `dir2prompt` will try to locate the Git root of the target directory and reuse `${git_root}/.promptignore` when it exists. This lets you keep a single default view at the repository level even when running the tool from a nested folder.

Why this precedence? `.promptignore` captures the shared “baseline” for discussing a repository. When you need a different slice of the tree (for example to focus on tests or docs), providing your own ignore files only works if the baseline is bypassed, hence the explicit override behavior.

Example `.promptignore`:

```
*.log
node_modules/
.git/
```

Example of stacking custom ignore files:

```
dir2prompt --ignore-file prompts/base.ignore --ignore-file prompts/docs.ignore
```

## Ripgrep configuration

`dir2prompt` automatically respects ripgrep configuration files (`.ripgreprc`) located at the git repository root. When a `.ripgreprc` file is found, it is automatically loaded by setting the `RIPGREP_CONFIG_PATH` environment variable before invoking ripgrep.

This allows you to configure ripgrep behavior for your entire project, such as following symlinks, setting custom type definitions, or adjusting search behavior. For detailed information about ripgrep configuration files, see the [ripgrep configuration documentation](https://github.com/BurntSushi/ripgrep/blob/master/GUIDE.md#configuration-file).

Example `.ripgreprc`:

```
# Follow symbolic links
--follow

# Add custom type for shell scripts
--type-add
shell:*.{sh,bash,zsh}
```

**Note:** Ripgrep does not automatically discover configuration files; it requires the `RIPGREP_CONFIG_PATH` environment variable to be set. `dir2prompt` handles this automatically when it finds a `.ripgreprc` file at your git repository root.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

Nicolas Girard <girard.nicolas@gmail.com>

## Acknowledgments

- The `tree` command for directory structure visualization
- `ripgrep` (rg) for efficient file searching
