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

## Installation

```bash
# Install ripgrep (rg)
# On Ubuntu/Debian:
sudo apt-get install ripgrep
# On macOS with Homebrew:
brew install rg
# For other systems, please refer to the ripgrep installation guide

# Clone the repository
git clone https://github.com/yourusername/dir2prompt.git

# Navigate to the project directory
cd dir2prompt

# Build the project (requires 'just' command)
just build

# Install the executable (may require sudo)
sudo cp build/dir2prompt /usr/local/bin/
```

## Usage

```
Usage: dir2prompt [OPTIONS] [DIRECTORY] 
Options:
  --tree-only          Display only the directory tree.
  --contents-only      Display only the contents of non-binary files.
  --type <TYPE>        Limit search to files matching the given type.
  --max-depth <NUM>    Limit the depth of directory traversal.
  --max-filesize <NUM> Ignore files larger than NUM in size.
  --ignore-file <FILE> Specify a custom ignore file (default: .promptignore in the target directory).
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

By default, `dir2prompt` looks for a `.promptignore` file in the target directory. You can specify patterns in this file to exclude certain files or directories from the snapshot. The syntax is similar to `.gitignore`.

Example `.promptignore`:

```
*.log
node_modules/
.git/
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
