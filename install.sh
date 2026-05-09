#!/usr/bin/env bash
set -euo pipefail

# Human Signoff CLI Installer
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/merico-ai/human-signoff-releases/main/install.sh)

RELEASES_REPO="merico-ai/human-signoff-releases"
HERMES_PLUGIN_REPO="merico-ai/hermes-plugin-human-signoff-approval"
OPENCLAW_PLUGIN_REPO="merico-ai/openclaw-human-signoff"
BINARY_NAME="signoff"
INSTALL_DIR="/usr/local/bin"

# ─── Colors ──────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}⚠${NC} %s\n" "$*"; }
error() { printf "${YELLOW}✗${NC} %s\n" "$*"; exit 1; }
header() { printf "\n${CYAN}══ %s ══${NC}\n" "$*"; }

# ─── Platform detection ──────────────────────────────────────────────────
detect_platform() {
  case "$(uname -s)" in
    Linux)  GOOS="linux" ;;
    Darwin) GOOS="darwin" ;;
    *)      error "Unsupported OS: $(uname -s)" ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) GOARCH="amd64" ;;
    arm64|aarch64) GOARCH="arm64" ;;
    *) error "Unsupported architecture: $(uname -m)" ;;
  esac
}

# ─── Get latest release tag from public repo ────────────────────────────
get_latest_tag() {
  curl -fsSL --connect-timeout 10 --max-time 30 \
    "https://api.github.com/repos/${RELEASES_REPO}/releases/latest" \
    | grep '"tag_name"' | head -n 1 | sed 's/.*"tag_name": "\(.*\)",/\1/'
}

# ─── Resolve install directory ───────────────────────────────────────────
resolve_install_dir() {
  if [[ -d "$INSTALL_DIR" ]]; then
    return 0
  fi
  printf "Target directory ${INSTALL_DIR} does not exist.\n"
  printf "  1) Create ${INSTALL_DIR} (requires sudo)\n"
  printf "  2) Use ${HOME}/.local/bin\n"
  printf "  3) Use current directory (${PWD})\n"
  printf "Choose [1/2/3] (default: 1): "
  local answer
  read -r answer
  case "${answer:-1}" in
    2)
      INSTALL_DIR="${HOME}/.local/bin"
      mkdir -p "$INSTALL_DIR"
      info "Using ${INSTALL_DIR}"
      ;;
    3)
      INSTALL_DIR="${PWD}"
      info "Using ${INSTALL_DIR}"
      ;;
    *)
      sudo mkdir -p "$INSTALL_DIR"
      info "Created ${INSTALL_DIR}"
      ;;
  esac
}

# ─── Download and install binary ─────────────────────────────────────────
install_binary() {
  local tag="$1"

  resolve_install_dir

  local tmp_dir
  tmp_dir="$(mktemp -d)"

  info "Downloading signoff-cli-${tag}-${GOOS}-${GOARCH}.zip ..."
  curl -fsSL --connect-timeout 10 --max-time 120 \
    "https://github.com/${RELEASES_REPO}/releases/download/${tag}/signoff-cli-${tag}-${GOOS}-${GOARCH}.zip" \
    -o "${tmp_dir}/signoff-cli.zip"

  info "Extracting..."
  unzip -qo "${tmp_dir}/signoff-cli.zip" -d "${tmp_dir}/extracted"

  local binary_src
  binary_src="$(find "${tmp_dir}/extracted" -name "${BINARY_NAME}" -type f | head -n 1)"
  if [[ -z "$binary_src" ]]; then
    error "Binary not found in the downloaded package."
  fi

  chmod +x "$binary_src"

  if [[ -x "${INSTALL_DIR}/${BINARY_NAME}" ]]; then
    printf "signoff already installed at ${INSTALL_DIR}/${BINARY_NAME}. Upgrade? [Y/n] "
  else
    printf "Install to ${INSTALL_DIR}/${BINARY_NAME}? [Y/n] "
  fi
  local answer
  read -r answer

  if [[ -z "$answer" || "$answer" =~ ^[Yy] ]]; then
    if [[ -w "$INSTALL_DIR" ]]; then
      cp "$binary_src" "${INSTALL_DIR}/${BINARY_NAME}"
    else
      sudo cp "$binary_src" "${INSTALL_DIR}/${BINARY_NAME}"
    fi
    info "Installed ${INSTALL_DIR}/${BINARY_NAME}"
  else
    cp "$binary_src" "./${BINARY_NAME}"
    info "Binary saved to ${PWD}/${BINARY_NAME}"
    warn "Install later: sudo cp ${PWD}/${BINARY_NAME} ${INSTALL_DIR}/${BINARY_NAME}"
  fi

  rm -rf "$tmp_dir"
}

# ─── Check Hermes plugin installed ───────────────────────────────────────
is_hermes_plugin_installed() {
  if command -v hermes &>/dev/null; then
    if hermes plugins list 2>/dev/null | grep -q "human-signoff-approval"; then
      return 0
    fi
  fi
  if [[ -f "${HOME}/.hermes/plugins/human-signoff-approval/plugin.yaml" ]]; then
    return 0
  fi
  return 1
}

# ─── Check OpenClaw plugin installed ─────────────────────────────────────
is_openclaw_plugin_installed() {
  if command -v openclaw &>/dev/null; then
    if openclaw plugins list 2>/dev/null | grep -q "human-signoff-approval"; then
      return 0
    fi
  fi
  if [[ -f "${HOME}/.openclaw/plugins/human-signoff-approval/openclaw.plugin.json" ]]; then
    return 0
  fi
  return 1
}

# ─── Install agent plugin via CLI ────────────────────────────────────────
install_plugin_via_cli() {
  local repo="$1"
  local name="$2"
  local tmp_dir

  tmp_dir="$(mktemp -d)"
  curl -fsSL --connect-timeout 10 --max-time 60 \
    "https://github.com/${repo}/archive/refs/heads/main.tar.gz" \
    | tar xz -C "$tmp_dir" --strip-components=1

  local exit_code=0
  (
    cd "$tmp_dir"
    if [[ "$name" == "hermes" ]]; then
      hermes plugins install . --yes
    else
      openclaw plugins install .
    fi
  ) || exit_code=$?
  rm -rf "$tmp_dir"
  return $exit_code
}

# ══════════════════════════════════════════════════════════════════════════
# Main
# ══════════════════════════════════════════════════════════════════════════

printf "\n"
printf "${CYAN}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${CYAN}║         Human Signoff CLI Installer                 ║${NC}\n"
printf "${CYAN}╚══════════════════════════════════════════════════════╝${NC}\n"

detect_platform
info "Detected platform: ${GOOS}/${GOARCH}"

# ─── Step 1: Get latest release tag ──────────────────────────────────────
header "Downloading Signoff CLI"

TAG=""
printf "Enter release tag (leave blank for latest): "
local tag_input
read -r tag_input
if [[ -n "$tag_input" ]]; then
  TAG="$tag_input"
else
  TAG="$(get_latest_tag)"
  if [[ -z "$TAG" ]]; then
    error "Could not determine latest release. Re-run and specify a tag manually."
  fi
  info "Latest release: ${TAG}"
fi

install_binary "$TAG"

# ─── Step 2: Optional Hermes plugin ──────────────────────────────────────
header "Hermes Approval Plugin"

if ! command -v hermes &>/dev/null; then
  warn "Hermes not found. To install the Hermes plugin, install Hermes first."
elif is_hermes_plugin_installed; then
  info "Hermes approval plugin already installed"
else
  printf "Install Hermes approval plugin? [y/N] "
  local answer
  read -r answer
  if [[ "$answer" =~ ^[Yy] ]]; then
    if install_plugin_via_cli "$HERMES_PLUGIN_REPO" "hermes"; then
      info "Hermes approval plugin installed"
    else
      error "Hermes plugin installation failed"
    fi
  fi
fi

# ─── Step 3: Optional OpenClaw plugin ────────────────────────────────────
header "OpenClaw Approval Plugin"

if ! command -v openclaw &>/dev/null; then
  warn "OpenClaw not found. To install the OpenClaw plugin, install OpenClaw first."
elif is_openclaw_plugin_installed; then
  info "OpenClaw approval plugin already installed"
else
  printf "Install OpenClaw approval plugin? [y/N] "
  local answer
  read -r answer
  if [[ "$answer" =~ ^[Yy] ]]; then
    if install_plugin_via_cli "$OPENCLAW_PLUGIN_REPO" "openclaw"; then
      info "OpenClaw approval plugin installed"
    else
      error "OpenClaw plugin installation failed"
    fi
  fi
fi

# ─── Done ────────────────────────────────────────────────────────────────
printf "\n${GREEN}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${GREEN}║       Installation complete!                         ║${NC}\n"
printf "${GREEN}╚══════════════════════════════════════════════════════╝${NC}\n"
printf "\nNext steps:\n"
printf "  1. ${CYAN}signoff config set server_url https://your-server.com${NC}\n"
printf "  2. ${CYAN}signoff login${NC}\n"
printf "  3. ${CYAN}sudo signoff install-ca${NC}\n"
printf "  4. ${CYAN}signoff run${NC}\n"
printf "\nFor more: ${CYAN}https://github.com/${RELEASES_REPO}${NC}\n"
