# Set the environment file to automatically load
set dotenv-load := true
set dotenv-filename := "ci_env"
set export := true

build_dir := "./build"

# Get version number from `version` file
VERSION := `cat version`
deb_file := build_dir + '/dir2prompt_' + VERSION + '.deb'

# Define a command variable for just with the current justfile specified
just := 'just --justfile "'+justfile()+'"'

# Default recipe: List all available commands
_default:
    @{{just}} --list --unsorted

# Clean up the project
clean:
    #!/usr/bin/env bash
    if ! [[ -d "{{build_dir}}" ]]; then
        exit 0
    fi
    printf "Cleaning up...\n"
    rm -f "{{build_dir}}"/* 

# Build and prepare configuration and executable scripts with substituted environment variables for deployment.
build: clean
    #!/usr/bin/env bash
    if ! [[ -d "{{build_dir}}" ]]; then
        mkdir "{{build_dir}}"
    fi
    export RELEASE_DATE="$(date +%Y-%m-%d)"
    envsubst '${MAINTAINER},${RELEASE_DATE},${VERSION}' \
        < src/${PROGRAM_NAME}.sh \
        > build/${PROGRAM_NAME}
    chmod +x build/${PROGRAM_NAME}
