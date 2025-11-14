# Release Process

This document describes the release process for this project.

## Prerequisites

- Ensure all tests pass: `just test`
- Ensure code is linted: `just lint`
- All changes are committed to the main branch

## Creating a Release

### Automated Method (Recommended)

1. Update the version in the `version` file
2. Run the release script:
   ```bash
   just release
   ```
   Or directly:
   ```bash
   ./ci/release.sh
   ```

The script will:
- Validate that only the version file has changed
- Check that the version file exists and is not empty
- Verify the tag doesn't already exist
- Commit the version change
- Create a git tag (v{version})
- Push the commit and tag to GitHub

### Dry-Run Mode

To preview what the release script would do without making changes:
```bash
DRY_RUN=1 ./ci/release.sh
```

### Manual Method

If you need to create a release manually:

1. Update the version in the `version` file
2. Commit the change:
   ```bash
   git add version
   git commit -m "Release X.Y.Z"
   ```
3. Create and push the tag:
   ```bash
   git tag -a "vX.Y.Z" -m "Release vX.Y.Z"
   git push origin main
   git push origin "vX.Y.Z"
   ```

## Automated Build Process

Once a tag is pushed, GitHub Actions will automatically:
1. Build DEB, RPM, and Arch Linux packages using nfpm
2. Create a GitHub release
3. Upload all package artifacts to the release

The workflow is defined in `.github/workflows/release.yml`.

## Version Numbering

This project follows [Semantic Versioning](https://semver.org/):
- MAJOR.MINOR.PATCH (e.g., 1.2.3)
- Increment MAJOR for breaking changes
- Increment MINOR for new features
- Increment PATCH for bug fixes

## Troubleshooting

### Tag Already Exists
If you get an error that the tag already exists:
```bash
git tag -d vX.Y.Z  # Delete local tag
git push origin :vX.Y.Z  # Delete remote tag
```
Then update the version and try again.

### Build Failures
Check the GitHub Actions workflow run at:
https://github.com/ngirard/dir2prompt/actions
