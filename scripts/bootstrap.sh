#!/usr/bin/env bash
set -euo pipefail

RUST_TARGET_VERSION="1.90"
NODE_TARGET_VERSION="20.12.2"
PNPM_TARGET_VERSION="9.1.0"
PLAYWRIGHT_TARGET_VERSION="1.48.2"
PLAYWRIGHT_BROWSER="chromium"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
prefix=/usr
HAS_MISE=0
HAS_EGET=0
HAS_DX=0
HAS_NODE=0

function command_exists {
    command="$1"
    command -v "$command" >/dev/null 2>&1
}

function check_mise {
    if command_exists mise; then
        HAS_MISE=1
    fi
    echo "HAS_MISE=$HAS_MISE"
}

function check_eget {
    if command_exists eget; then
        HAS_EGET=1
    fi
    echo "HAS_EGET=$HAS_EGET"
}

function check_dx {
    if command_exists dx; then
        HAS_DX=1
    fi
    echo "HAS_DX=$HAS_DX"
}

function check_node {
    if command_exists node; then
        HAS_NODE=1
    fi
    echo "HAS_NODE=$HAS_NODE"
}

# If mise is available, ensure it's activated in .bashrc
# if (( HAS_MISE )); then
#     BASHRC="$HOME/.bashrc"
#     MISE_ACTIVATE='eval "$(mise activate bash)"'
#     if ! grep -q "$MISE_ACTIVATE" "$BASHRC"; then
#         echo "$MISE_ACTIVATE" >> "$BASHRC"
#         echo "Added mise activation to $BASHRC"
#     else
#         echo "mise activation already present in $BASHRC"
#     fi
# fi

function maybe_install_rust_toolchain {
    if command_exists rustc; then
        if ! rustc --version | grep -q "$RUST_TARGET_VERSION"; then
            echo "Rust version does not match target $RUST_TARGET_VERSION. Updating..."
            if (( HAS_MISE )); then
                mise use rust@$RUST_TARGET_VERSION
            else
                # Robust update for non-mise envs: uninstall existing stable to avoid rename conflicts, then install/set target
                rustup toolchain uninstall stable || true
                rustup install $RUST_TARGET_VERSION
                rustup default $RUST_TARGET_VERSION
            fi
        else
            echo "Rust version matches target $RUST_TARGET_VERSION."
        fi
    else
        echo "rustc not found in PATH. Skipping Rust version check."
    fi
}

function maybe_install_wasm_target {
    if command_exists rustup; then
        if ! rustup target list --installed | grep -q '^wasm32-unknown-unknown$'; then
            echo "Installing wasm32-unknown-unknown target"
            rustup target add wasm32-unknown-unknown
        else
            echo "wasm32-unknown-unknown target already installed"
        fi
    else
        echo "rustup not found; skipping wasm target installation"
    fi
}

function maybe_install_eget {
    if (( !HAS_EGET )); then
        # Eget
        #   Easily install prebuilt binaries from GitHub
        #   https://github.com/zyedidia/eget
        curl https://zyedidia.github.io/eget.sh | sh && { f=eget; sudo install $f ${prefix}/bin && rm $f; }
        HAS_EGET=1
    fi
}

function maybe_install_fd {
    if command -v fd >/dev/null 2>&1; then
        echo "fd is already installed"
    else
        if (( HAS_MISE )); then
            echo "Installing fd using mise..."
            mise use fd
        else
            echo "Installing fd using eget..."
            # Fd
            #   A simple, fast and user-friendly alternative to 'find'
            #   https://github.com/sharkdp/fd
            #   Config:
            eget -a amd64 -a musl -a .deb sharkdp/fd  && p="$(ls *.deb|head -1)" && sudo dpkg -i "${p}" && rm "${p}"
        fi
    fi
}

function maybe_install_just {
    if command_exists just; then
        out="$(just --version)"
        echo "$out is already installed"
    else
        if (( HAS_MISE )); then
            echo "Installing just using mise..."
            mise use just
        else
            echo "Installing just using eget..."
            # Just
            #   Just a command runner
            #   https://github.com/casey/just
            #   Config: no
            sudo eget -a x86_64 -a musl casey/just --to=/usr/local/bin
        fi
    fi
}

function maybe_install_rg {
    if command_exists rg; then
        echo "rg is already installed"
    else
        if (( HAS_MISE )); then
            echo "Installing rg using mise..."
            mise use rg
        else
            echo "Installing fd using apt..."
            # Ripgrep
            #   https://github.com/BurntSushi/ripgrep
            # eget --asset=.deb BurntSushi/ripgrep && p="$(ls *.deb|head -1)" && sudo dpkg -i "${p}" && rm "${p}"
            sudo apt update; sudo apt install -y ripgrep
        fi
    fi
}

function maybe_install_sd {
    if command_exists sd; then
        echo "sd is already installed"
    else
        if (( HAS_MISE )); then
            echo "Installing sd using mise..."
            mise use sd
        else
            echo "Installing sd using eget..."
            # Sd
            #   Intuitive find & replace CLI (sed alternative)
            #   https://github.com/chmln/sd
            sudo eget -a gnu chmln/sd --to=${prefix}/bin
        fi
    fi
}

function maybe_install_mdsplice {
    if command_exists md-splice; then
        echo "md-splice is already installed"
    else
        echo "Installing md-splice using eget..."
        # Md-splice
        #   A command-line tool for precise, AST-aware insertion, replacement, deletion, and retrieval of content within Markdown files.
        #   https://github.com/ngirard/md-splice
        sudo eget --pre-release ngirard/md-splice --to=${prefix}/bin
    fi
}

function ensure_pip {
    if ! command_exists python3; then
        echo "python3 not found; skipping Python package provisioning"
        return 1
    fi

    if ! python3 -m pip --version >/dev/null 2>&1; then
        echo "pip not found for python3; bootstrapping with ensurepip"
        python3 -m ensurepip --upgrade
        python3 -m pip install --upgrade pip
    fi

    return 0
}

function maybe_install_python_packages {
    if ! ensure_pip; then
        return
    fi

    local packages=("PyYAML" "jsonschema")
    for package in "${packages[@]}"; do
        if python3 -m pip show "$package" >/dev/null 2>&1; then
            echo "Python package ${package} already installed"
        else
            echo "Installing Python package ${package}"
            python3 -m pip install --user "$package"
        fi
    done
}

# Install the requested Node.js version from the official tarball so CI and
# local agents share the same LTS toolchain without depending on system
# packages that may drift between environments.
function install_node_tarball {
    local version
    version="$1"
    local tarball
    tarball="node-v${version}-linux-x64.tar.xz"
    local url
    url="https://nodejs.org/dist/v${version}/${tarball}"
    local destination
    destination="/usr/local/lib/nodejs"

    echo "Installing Node.js ${version} from ${url}"
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    curl -fsSL "${url}" -o "${tmp_dir}/${tarball}"
    sudo mkdir -p "${destination}"
    sudo tar -xJf "${tmp_dir}/${tarball}" -C "${destination}"
    sudo ln -sf "${destination}/node-v${version}-linux-x64/bin/node" /usr/local/bin/node
    sudo ln -sf "${destination}/node-v${version}-linux-x64/bin/npm" /usr/local/bin/npm
    sudo ln -sf "${destination}/node-v${version}-linux-x64/bin/npx" /usr/local/bin/npx
    sudo ln -sf "${destination}/node-v${version}-linux-x64/bin/corepack" /usr/local/bin/corepack
    rm -rf "${tmp_dir}"
}

function maybe_install_node_tooling {
    local target
    target="${NODE_TARGET_VERSION}"
    if command_exists node; then
        local current
        current="$(node --version | sed 's/^v//')"
        if [[ "${current}" != "${target}" ]]; then
            echo "Detected Node.js ${current}; installing Node.js ${target}"
            if (( HAS_MISE )); then
                mise use --global "node@${target}"
            else
                install_node_tarball "${target}"
            fi
        else
            echo "Node.js v${target} is already installed"
        fi
    else
        if (( HAS_MISE )); then
            echo "Installing Node.js ${target} using mise..."
            mise use --global "node@${target}"
        else
            install_node_tarball "${target}"
        fi
    fi

    if command_exists node; then
        HAS_NODE=1
    fi

    if command_exists corepack; then
        echo "Enabling corepack shims"
        corepack enable
        echo "Preparing pnpm@${PNPM_TARGET_VERSION} via corepack"
        corepack prepare "pnpm@${PNPM_TARGET_VERSION}" --activate
    else
        echo "corepack not available; pnpm installation cannot be managed deterministically"
    fi
}

# Provision the Playwright CLI and browser binaries using the pinned pnpm
# workspace that powers the automation harness.
function maybe_install_playwright {
    if (( ! HAS_NODE )); then
        echo "Skipping Playwright setup because Node.js is unavailable"
        return
    fi

    if ! command_exists pnpm; then
        echo "pnpm was not provisioned; skipping Playwright installation"
        return
    fi

    local harness_dir
    harness_dir="${ROOT_DIR}/scripts"
    echo "Installing harness dependencies via pnpm (frozen lockfile)"
    PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}" pnpm --dir "${harness_dir}" install --frozen-lockfile
    if [[ "${PLAYWRIGHT_SKIP_BROWSER_INSTALL:-0}" == "1" ]]; then
        echo "Skipping Playwright browser installation (PLAYWRIGHT_SKIP_BROWSER_INSTALL=1)"
    else
        echo "Provisioning Playwright browsers (${PLAYWRIGHT_BROWSER})"
        PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}" pnpm --dir "${harness_dir}" exec playwright install --with-deps "${PLAYWRIGHT_BROWSER}"
    fi
    local playwright_version
    playwright_version="$(PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}" pnpm --dir "${harness_dir}" exec playwright --version | awk '{print $2}')"
    if [[ -n "${playwright_version}" && "${playwright_version}" != "${PLAYWRIGHT_TARGET_VERSION}" ]]; then
        echo "Warning: Playwright CLI version ${playwright_version} differs from expected ${PLAYWRIGHT_TARGET_VERSION}" >&2
    fi
}

function maybe_mise_activate {
    if (( HAS_MISE )); then
        eval "$(mise activate bash)"
    fi
}

function maybe_install_cargo_binstall {
    if command_exists cargo-binstall; then
        echo "cargo-binstall already installed"
        return
    else
        sudo eget -a ^.sig -a ^full -a gnu cargo-bins/cargo-binstall --to "${prefix}"/bin
    fi
}

function maybe_install_rustup_components {
    local components=("rustfmt" "clippy")
    local installed_list=$(rustup component list --installed)
    local to_install=()
    for component in "${components[@]}"; do
        if echo "$installed_list" | grep -q "^\* $component "; then
            echo "Component $component is already installed."
        else
            to_install+=("$component")
        fi
    done
    for component in "${to_install[@]}"; do
        rustup component add "$component"
    done
}

function maybe_install_dioxus_cli {
    if (( HAS_DX )); then
        echo "dioxus-cli already installed"
        return
    fi

    if command_exists cargo; then
        echo "Installing dioxus-cli 0.7.0-rc.1"
        cargo binstall --disable-telemetry --no-confirm dioxus-cli@0.7.0-rc.1 --force
    else
        echo "cargo not found; cannot install dioxus-cli"
    fi
}

function maybe_install_dioxus_deps {
    local packages=(
        libwebkit2gtk-4.1-dev
        build-essential
        curl
        wget
        file
        libxdo-dev
        libssl-dev
        libayatana-appindicator3-dev
        librsvg2-dev
    )
    local installed_packages
    local alt
    local regex
    local installed_ones
    declare -A needed
    installed_packages=$(dpkg-query -W | awk -F'\t' '{ gsub(/:[^ \t]*$/, "", $1); print $1 }')
    alt=$(IFS='|'; echo "${packages[*]}")
    regex="^($alt)$"
    installed_ones=$(echo "$installed_packages" | grep -E "$regex")
    for package in "${packages[@]}"; do
        needed["$package"]=1
        echo "Checking package $package..."
    done
    for package in $installed_ones; do
        if [[ -n ${needed[$package]} ]]; then
            echo "Package $package is already installed."
            unset needed["$package"]
        fi
    done
    local to_install=("${!needed[@]}")
    if [ ${#to_install[@]} -eq 0 ]; then
        echo "All packages are already installed."
    else
        echo "Installing missing packages: ${to_install[*]}"
        sudo apt update
        sudo apt -y install "${to_install[@]}"
    fi
}

check_mise
check_eget
#check_dx
#check_node
#maybe_install_rust_toolchain
#maybe_install_wasm_target
maybe_install_eget
maybe_install_fd
maybe_install_just
maybe_install_rg
maybe_install_sd
#maybe_install_mdsplice
#maybe_install_python_packages
#maybe_install_node_tooling
#maybe_install_playwright
#maybe_mise_activate
#maybe_install_rustup_components
#maybe_install_cargo_binstall
#maybe_install_dioxus_deps
#maybe_install_dioxus_cli
#print_clipboard_prereqs
