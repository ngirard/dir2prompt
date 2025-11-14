# Set the environment file to automatically load
set dotenv-load := true
set dotenv-filename := "ci_env"
set export := true

# Get version number from `version` file
VERSION := `cat version`

# Define a command variable for just with the current justfile specified
just := 'just --justfile "'+justfile()+'"'

# Installation prefix - CI uses ~/.local, system uses /usr/local
PREREQ_PREFIX := if env_var_or_default("CI", "") != "" { env_var("HOME") + "/.local" } else { "/usr/local" }

# Sudo command - empty in CI, sudo otherwise
SUDO := if env_var_or_default("CI", "") != "" { "" } else { "sudo" }

# Default recipe
_default:
    @just --list --unsorted

# Ensure Eget is installed, and install it if not
_ensure_eget:
    #!/usr/bin/env bash
    if command -v "eget" >/dev/null 2>&1; then
        exit 0
    fi
    printf "Installing Eget...\n"
    
    # Download eget
    curl https://zyedidia.github.io/eget.sh | sh
    
    # Install to PREREQ_PREFIX
    mkdir -p "{{PREREQ_PREFIX}}/bin"
    {{SUDO}} install eget "{{PREREQ_PREFIX}}/bin"
    rm -f eget
    
    # Add to PATH in CI
    if [[ -n "${CI}" ]]; then
        echo "{{PREREQ_PREFIX}}/bin" >> $GITHUB_PATH
    fi

# Ensure Nfpm is installed, and install it if not
_ensure_nfpm: _ensure_eget
    #!/usr/bin/env bash
    if command -v "nfpm" >/dev/null 2>&1; then
        exit 0
    fi
    printf "Installing Nfpm...\n"
    
    # Use eget to install directly to PREREQ_PREFIX
    eget --to="{{PREREQ_PREFIX}}/bin" -a ^sbom goreleaser/nfpm
    
    # Make executable (sudo not needed as eget creates it executable)
    if [[ -z "${CI}" ]] && [[ "{{PREREQ_PREFIX}}" == "/usr/local" ]]; then
        {{SUDO}} chmod +x "{{PREREQ_PREFIX}}/bin/nfpm"
    fi

# Clean up the project
clean:
    #!/usr/bin/env bash
    if ! [[ -d "${BUILD_DIR}" ]]; then
        exit 0
    fi
    printf "Cleaning up...\n"
    rm -f "${BUILD_DIR}"/* 

# Build and prepare configuration and executable scripts with substituted environment variables for deployment.
build: clean
    #!/usr/bin/env bash
    if ! [[ -d "${BUILD_DIR}" ]]; then
        mkdir "${BUILD_DIR}"
    fi
    export RELEASE_DATE="$(date +%Y-%m-%d)"
    envsubst '${MAINTAINER},${RELEASE_DATE},${VERSION}' \
        < src/${PROGRAM_NAME}.sh \
        > "${BUILD_DIR}/${PROGRAM_NAME}.sh"
    chmod +x "${BUILD_DIR}/${PROGRAM_NAME}.sh"

# Package project
package: build _ensure_nfpm
    #!/usr/bin/env bash
    if ! [[ -d "${BUILD_DIR}" ]]; then
        mkdir "${BUILD_DIR}"
    fi
    for packager in apk archlinux deb rpm; do
        nfpm pkg --packager "${packager}" --config nfpm.yaml --target "${BUILD_DIR}"
    done

# Generate checksums for all packages
checksums:
    #!/usr/bin/env bash
    cd "${BUILD_DIR}"
    if ls *.{deb,rpm,apk} *.pkg.tar.zst 2>/dev/null | head -1 > /dev/null; then
        sha256sum *.{deb,rpm,apk} *.pkg.tar.zst 2>/dev/null > SHA256SUMS
        echo "Checksums generated in ${BUILD_DIR}/SHA256SUMS"
    else
        echo "No packages found to checksum"
        exit 1
    fi

# Bump version (major, minor, or patch)
bump-version TYPE:
    #!/usr/bin/env bash
    current=$(cat version)
    IFS='.' read -r major minor patch <<< "$current"
    case "{{TYPE}}" in
        major) new="$((major+1)).0.0" ;;
        minor) new="${major}.$((minor+1)).0" ;;
        patch) new="${major}.${minor}.$((patch+1))" ;;
        *) echo "Usage: just bump-version [major|minor|patch]"; exit 1 ;;
    esac
    echo "$new" > version
    echo "Version bumped: $current → $new"
    echo ""
    echo "Next steps:"
    echo "  1. Update CHANGELOG.md with changes for v$new"
    echo "  2. git add version CHANGELOG.md"
    echo "  3. git commit -m 'Release v$new'"
    echo "  4. git tag -a v$new -m 'Release v$new'"
    echo "  5. git push && git push --tags"

release:
    @ci/release.sh

# --- For local development ---

# Generate a directory snapshot for the project
snapshot:
    #!/usr/bin/env bash
    project_name="$(basename "${PWD%.git}")"
    snapshot_filename="prompts/.${project_name}_repo_snapshot.md"
    dir2prompt > "${snapshot_filename}"
    wc -c "${snapshot_filename}"
