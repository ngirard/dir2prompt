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

```
Usage: dir2prompt [OPTIONS] [DIRECTORY]
Options:
  --tree-only          Display only the directory tree.
  --contents-only      Display only the contents of non-binary files.
  --type <TYPE>        Limit search to files matching the given type.
  --max-depth <NUM>    Limit the depth of directory traversal.
   --max-filesize <NUM> Ignore files larger than NUM in size.
   --ignore-file <FILE> Specify one or more custom ignore files (repeatable).
  --help               Display this help message.

If no directory is specified, the current directory is used.
```

## Examples

1. Generate a snapshot of the current directory:

   ```
   dir2prompt
   ```

2. Display only the directory tree for a specific folder:

   ```
   dir2prompt --tree-only /path/to/your/project
   ```

3. Show contents of only Python files, limited to a depth of 2:

   ```
   dir2prompt --type py --max-depth 2
   ```

4. Use a custom ignore file:

   ```
   dir2prompt --ignore-file /path/to/custom/ignorefile
   ```

## Ignoring Files

`dir2prompt` supports a layered ignore strategy so you can swap between a default view of a project and bespoke queries without editing files in place:

1. **Explicit `--ignore-file` flags take precedence.** When you pass one or more `--ignore-file <FILE>` options (the flag is repeatable), only those files are honored and the automatic `.promptignore` detection is skipped. This makes it possible to describe alternate “queries” for the same repository without having to touch the canonical `.promptignore`.
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

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

Nicolas Girard <girard.nicolas@gmail.com>

## Acknowledgments

- The `tree` command for directory structure visualization
- `ripgrep` (rg) for efficient file searching
