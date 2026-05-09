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
    Linux)  GOOS="linux"; IS_LINUX=true; IS_MACOS=false ;;
    Darwin) GOOS="darwin"; IS_LINUX=false; IS_MACOS=true ;;
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
  printf "  Fetching latest release info from github.com... "
  local tag
  tag=$(curl -fsSL --connect-timeout 10 --max-time 30 \
    "https://api.github.com/repos/${RELEASES_REPO}/releases/latest" \
    | grep '"tag_name"' | head -n 1 | sed 's/.*"tag_name": "\(.*\)",/\1/') || {
    printf "FAILED\n"
    return 1
  }
  if [[ -z "$tag" ]]; then
    printf "FAILED\n"
    return 1
  fi
  printf "${GREEN}${tag}${NC}\n"
  echo "$tag"
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

  printf "  Downloading signoff-cli-${tag}-${GOOS}-${GOARCH}.zip ... "
  curl -fsSL --connect-timeout 10 --max-time 120 \
    "https://github.com/${RELEASES_REPO}/releases/download/${tag}/signoff-cli-${tag}-${GOOS}-${GOARCH}.zip" \
    -o "${tmp_dir}/signoff-cli.zip" && printf "${GREEN}done${NC}\n" || {
    printf "${YELLOW}FAILED${NC}\n"
    error "Download failed. Possible causes:
    - Network cannot reach github.com
    - Release ${tag} does not exist in ${RELEASES_REPO}
    - The zip file for ${GOOS}/${GOARCH} is missing
  Try specifying a tag manually, or check https://github.com/${RELEASES_REPO}/releases"
  }

  printf "  Extracting... "
  unzip -qo "${tmp_dir}/signoff-cli.zip" -d "${tmp_dir}/extracted" && printf "${GREEN}done${NC}\n" || {
    error "Failed to extract zip. The download may be corrupted."
  }

  local binary_src
  binary_src="$(find "${tmp_dir}/extracted" -name "${BINARY_NAME}" -type f | head -n 1)"
  if [[ -z "$binary_src" ]]; then
    error "Binary '${BINARY_NAME}' not found in the downloaded package."
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
  printf "  Downloading plugin from github.com... "
  curl -fsSL --connect-timeout 10 --max-time 60 \
    "https://github.com/${repo}/archive/refs/heads/main.tar.gz" \
    | tar xz -C "$tmp_dir" --strip-components=1 && printf "${GREEN}done${NC}\n" || {
    printf "${YELLOW}FAILED${NC}\n"
    error "Failed to download plugin from ${repo}."
  }

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

# ─── Offer install-ca ────────────────────────────────────────────────────
run_install_ca() {
  if ! command -v signoff &>/dev/null && [[ ! -x "${INSTALL_DIR}/signoff" ]]; then
    return
  fi

  printf "Install CA certificate for HTTPS interception (requires sudo)? [Y/n] "
  local answer
  read -r answer
  if [[ -z "$answer" || "$answer" =~ ^[Yy] ]]; then
    local signoff_bin="${INSTALL_DIR}/signoff"
    sudo "$signoff_bin" install-ca && info "CA certificate installed" || warn "CA installation failed"
  fi
}

# ─── Configure gateway proxy ─────────────────────────────────────────────
configure_gateway_proxy() {
  local agent_name="$1"   # "Hermes" or "OpenClaw"

  printf "\n${CYAN}Configure ${agent_name} Gateway proxy settings?${NC}\n"

  if [[ "$IS_MACOS" == true ]]; then
    local plist_name
    local plist_path
    if [[ "$agent_name" == "Hermes" ]]; then
      plist_name="ai.hermes.gateway"
    else
      plist_name="ai.openclaw.gateway"
    fi
    plist_path="${HOME}/Library/LaunchAgents/${plist_name}.plist"

    if [[ ! -f "$plist_path" ]]; then
      warn "${plist_name}.plist not found at ${plist_path}"
      printf "  Start the Gateway once to generate it, then re-run this script.\n"
      return
    fi

    if /usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:HTTP_PROXY" "$plist_path" &>/dev/null \
      && [[ "$(/usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:HTTP_PROXY" "$plist_path")" == "http://127.0.0.1:17771" ]]; then
      info "${agent_name} Gateway proxy already configured"
      return
    fi

    printf "Add HTTP_PROXY/HTTPS_PROXY/NO_PROXY to ${plist_name}.plist? [Y/n] "
    local answer
    read -r answer
    if [[ -z "$answer" || "$answer" =~ ^[Yy] ]]; then
      for key in HTTP_PROXY HTTPS_PROXY; do
        /usr/libexec/PlistBuddy -c "Set :EnvironmentVariables:${key} http://127.0.0.1:17771" "$plist_path" 2>/dev/null \
          || /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:${key} string http://127.0.0.1:17771" "$plist_path"
      done
      /usr/libexec/PlistBuddy -c "Set :EnvironmentVariables:NO_PROXY localhost,127.0.0.1" "$plist_path" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:NO_PROXY string localhost,127.0.0.1" "$plist_path"

      launchctl bootout "gui/$(id -u)/${plist_name}" 2>/dev/null || true
      sleep 1
      launchctl bootstrap "gui/$(id -u)" "$plist_path" 2>/dev/null || true
      info "${agent_name} Gateway proxy configured and service reloaded"
    fi
  else
    local unit_name
    if [[ "$agent_name" == "Hermes" ]]; then
      unit_name="hermes-gateway"
    else
      unit_name="openclaw-gateway"
    fi

    if ! systemctl list-units --type=service --all 2>/dev/null | grep -q "${unit_name}"; then
      warn "${unit_name}.service not found in systemd"
      printf "  Install ${agent_name} first, then re-run this script.\n"
      return
    fi

    local dropin_dir="/etc/systemd/system/${unit_name}.service.d"
    local dropin_file="${dropin_dir}/proxy.conf"

    if [[ -f "$dropin_file" ]] && grep -q "HTTP_PROXY=http://127.0.0.1:17771" "$dropin_file" 2>/dev/null; then
      info "${agent_name} Gateway proxy already configured"
      return
    fi

    printf "Add HTTP_PROXY/HTTPS_PROXY/NO_PROXY to ${unit_name} systemd service? [Y/n] "
    local answer
    read -r answer
    if [[ -z "$answer" || "$answer" =~ ^[Yy] ]]; then
      sudo mkdir -p "$dropin_dir"
      sudo tee "$dropin_file" >/dev/null <<'EOF'
[Service]
Environment=HTTP_PROXY=http://127.0.0.1:17771
Environment=HTTPS_PROXY=http://127.0.0.1:17771
Environment=NO_PROXY=localhost,127.0.0.1
EOF
      sudo systemctl daemon-reload
      printf "Restart ${unit_name} now? [Y/n] "
      local restart_answer
      read -r restart_answer
      if [[ -z "$restart_answer" || "$restart_answer" =~ ^[Yy] ]]; then
        sudo systemctl restart "${unit_name}" || warn "Failed to restart ${unit_name}"
      fi
      info "${agent_name} Gateway proxy configured"
    fi
  fi
}

# ══════════════════════════════════════════════════════════════════════════
# Main
# ══════════════════════════════════════════════════════════════════════════

printf "\n"
printf "${CYAN}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${CYAN}║         Human Signoff CLI Installer                 ║${NC}\n"
printf "${CYAN}╚══════════════════════════════════════════════════════╝${NC}\n"

detect_platform
IS_LINUX=${IS_LINUX:-false}
IS_MACOS=${IS_MACOS:-false}
info "Detected platform: ${GOOS}/${GOARCH}"

# ─── Step 1: Get latest release tag ──────────────────────────────────────
header "Step 1: Download Signoff CLI"

TAG=""
printf "Enter release tag (leave blank for latest): "
local tag_input
read -r tag_input
if [[ -n "$tag_input" ]]; then
  TAG="$tag_input"
  info "Using tag: ${TAG}"
else
  TAG="$(get_latest_tag)" || {
    error "Could not determine latest release. Re-run and specify a tag manually."
  }
fi

install_binary "$TAG"

# ─── Step 2: Optional Hermes plugin ──────────────────────────────────────
HERMES_INSTALLED=false
header "Step 2: Hermes Approval Plugin"

if ! command -v hermes &>/dev/null; then
  warn "Hermes not found. To install the Hermes plugin, install Hermes first."
elif is_hermes_plugin_installed; then
  info "Hermes approval plugin already installed"
  HERMES_INSTALLED=true
else
  printf "Install Hermes approval plugin? [y/N] "
  local answer
  read -r answer
  if [[ "$answer" =~ ^[Yy] ]]; then
    if install_plugin_via_cli "$HERMES_PLUGIN_REPO" "hermes"; then
      info "Hermes approval plugin installed"
      HERMES_INSTALLED=true
    else
      error "Hermes plugin installation failed"
    fi
  fi
fi

if [[ "$HERMES_INSTALLED" == true ]]; then
  configure_gateway_proxy "Hermes"
fi

# ─── Step 3: Optional OpenClaw plugin ───────────────────────────────────
OPENCLAW_INSTALLED=false
header "Step 3: OpenClaw Approval Plugin"

if ! command -v openclaw &>/dev/null; then
  warn "OpenClaw not found. To install the OpenClaw plugin, install OpenClaw first."
elif is_openclaw_plugin_installed; then
  info "OpenClaw approval plugin already installed"
  OPENCLAW_INSTALLED=true
else
  printf "Install OpenClaw approval plugin? [y/N] "
  local answer
  read -r answer
  if [[ "$answer" =~ ^[Yy] ]]; then
    if install_plugin_via_cli "$OPENCLAW_PLUGIN_REPO" "openclaw"; then
      info "OpenClaw approval plugin installed"
      OPENCLAW_INSTALLED=true
    else
      error "OpenClaw plugin installation failed"
    fi
  fi
fi

if [[ "$OPENCLAW_INSTALLED" == true ]]; then
  configure_gateway_proxy "OpenClaw"
fi

# ─── Step 4: Install CA ──────────────────────────────────────────────────
if [[ "$HERMES_INSTALLED" == true || "$OPENCLAW_INSTALLED" == true ]]; then
  header "Step 4: CA Certificate"
  run_install_ca
fi

# ─── Done ────────────────────────────────────────────────────────────────
printf "\n${GREEN}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${GREEN}║       Installation complete!                         ║${NC}\n"
printf "${GREEN}╚══════════════════════════════════════════════════════╝${NC}\n"
printf "\nQuick start:\n"
printf "  1. ${CYAN}signoff config set server_url https://your-server.com${NC}\n"
printf "  2. ${CYAN}signoff login${NC}\n"
printf "  3. ${CYAN}signoff run${NC}              (start the proxy)\n"
printf "\nFor more: ${CYAN}https://github.com/${RELEASES_REPO}${NC}\n"
