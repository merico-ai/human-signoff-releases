#!/usr/bin/env bash
set -euo pipefail

# Human Signoff CLI Installer
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/merico-ai/human-signoff-releases/main/install.sh)

RELEASES_REPO="merico-ai/human-signoff-releases"
DOWNLOADS_BASE_URL="${SIGNOFF_DOWNLOADS_BASE_URL:-https://downloads.signoff.bio}"
HERMES_PLUGIN_REPO="merico-ai/hermes-plugin-human-signoff-approval"
OPENCLAW_PLUGIN_REPO="merico-ai/openclaw-human-signoff"
HERMES_PLUGIN_DIR_NAME="hermes-plugin-human-signoff-approval"
OPENCLAW_PLUGIN_DIR="${HOME}/.openclaw/extensions/human-signoff-approval"
BINARY_NAME="signoff"
CLAUDE_WRAPPER_NAME="signoff-claude"
INSTALL_DIR="/usr/local/bin"
CACHE_DIR="${HOME}/.cache/signoff"

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
  printf "  Fetching latest release info from github.com... " >&2
  local tag
  tag=$(curl -fsSL --connect-timeout 10 --max-time 30 \
    "https://api.github.com/repos/${RELEASES_REPO}/releases/latest" \
    | grep '"tag_name"' | head -n 1 | sed 's/.*"tag_name": "\(.*\)",/\1/') || {
    printf "FAILED\n" >&2
    return 1
  }
  if [[ -z "$tag" ]]; then
    printf "FAILED\n" >&2
    return 1
  fi
  printf "${GREEN}${tag}${NC}\n" >&2
  echo "$tag"
}

get_latest_tag_from_mirror() {
  printf "  Fetching latest release info from ${DOWNLOADS_BASE_URL}... " >&2
  local tag
  tag=$(curl -fsSL --connect-timeout 10 --max-time 30 \
    "${DOWNLOADS_BASE_URL}/releases/latest.txt" | tr -d '[:space:]') || {
    printf "FAILED\n" >&2
    return 1
  }
  if [[ -z "$tag" ]]; then
    printf "FAILED\n" >&2
    return 1
  fi
  printf "${GREEN}${tag}${NC}\n" >&2
  echo "$tag"
}

fetch_latest_tag() {
  get_latest_tag || get_latest_tag_from_mirror
}

download_file() {
  local label="$1"
  local destination="$2"
  shift 2

  local url
  local tmp_destination="${destination}.tmp"
  rm -f "$tmp_destination"
  for url in "$@"; do
    printf "  Downloading %s from %s ... " "$label" "$url"
    if curl -fsSL --connect-timeout 10 --max-time 120 "$url" -o "$tmp_destination"; then
      mv "$tmp_destination" "$destination"
      printf "${GREEN}done${NC}\n"
      return 0
    fi
    printf "${YELLOW}FAILED${NC}\n"
    rm -f "$tmp_destination"
  done
  return 1
}

verify_archive_checksum() {
  local checksum_path="$1"
  local zip_path="$2"
  local zip_name="$3"

  local expected
  expected="$(awk -v file="$zip_name" '$2 == file { print $1 }' "$checksum_path" | head -n 1)"
  if [[ -z "$expected" ]]; then
    warn "Checksum entry not found for ${zip_name}"
    return 1
  fi

  local actual
  if command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$zip_path" | awk '{ print $1 }')"
  elif command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$zip_path" | awk '{ print $1 }')"
  else
    warn "Neither shasum nor sha256sum is available for checksum verification."
    return 1
  fi

  [[ "$actual" == "$expected" ]]
}

download_verified_archive() {
  local label="$1"
  local destination="$2"
  local checksum_path="$3"
  shift 3

  local url
  local tmp_destination="${destination}.tmp"
  rm -f "$tmp_destination"
  for url in "$@"; do
    printf "  Downloading %s from %s ... " "$label" "$url"
    if curl -fsSL --connect-timeout 10 --max-time 120 "$url" -o "$tmp_destination"; then
      mv "$tmp_destination" "$destination"
      printf "${GREEN}done${NC}\n"
      printf "  Verifying checksum... "
      if verify_archive_checksum "$checksum_path" "$destination" "$label"; then
        printf "${GREEN}done${NC}\n"
        return 0
      fi
      printf "${YELLOW}FAILED${NC}\n"
      warn "Downloaded ${label} failed checksum verification."
      rm -f "$destination"
    else
      printf "${YELLOW}FAILED${NC}\n"
      rm -f "$tmp_destination"
    fi
  done
  return 1
}

# ─── Resolve install directory ───────────────────────────────────────────
resolve_install_dir() {
  local existing_signoff_path=""
  local existing_signoff_dir=""
  existing_signoff_path="$(which "${BINARY_NAME}" 2>/dev/null || true)"
  if [[ -n "$existing_signoff_path" && -x "$existing_signoff_path" ]]; then
    existing_signoff_dir="$(dirname "$existing_signoff_path")"
    printf "Detected existing signoff: %s\n" "$existing_signoff_path"
    printf "Reference install directory: %s\n" "$existing_signoff_dir"
    if [[ "$existing_signoff_dir" != "$INSTALL_DIR" ]]; then
      warn "Choosing a different directory may leave duplicate signoff binaries."
    fi
  fi

  if [[ -d "$INSTALL_DIR" ]]; then
    printf "Default install directory: ${INSTALL_DIR}\n"
    printf "  1) Use ${INSTALL_DIR}\n"
  else
    printf "Target directory ${INSTALL_DIR} does not exist.\n"
    printf "  1) Create ${INSTALL_DIR} (requires sudo)\n"
  fi
  printf "  2) Use ${HOME}/.local/bin\n"
  printf "  3) Use current directory (${PWD})\n"
  printf "  4) Enter custom directory\n"
  printf "Choose [1/2/3/4] (default: 1): "
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
    4)
      printf "Enter install directory path: "
      local custom_dir
      read -r custom_dir
      if [[ -z "$custom_dir" ]]; then
        error "Custom directory cannot be empty."
      fi
      if [[ "$custom_dir" == "~/"* ]]; then
        custom_dir="${HOME}/${custom_dir#~/}"
      elif [[ "$custom_dir" == "~" ]]; then
        custom_dir="${HOME}"
      fi
      INSTALL_DIR="$custom_dir"
      if mkdir -p "$INSTALL_DIR" 2>/dev/null; then
        info "Using ${INSTALL_DIR}"
      else
        sudo mkdir -p "$INSTALL_DIR"
        info "Using ${INSTALL_DIR}"
      fi
      ;;
    *)
      if [[ -d "$INSTALL_DIR" ]]; then
        info "Using ${INSTALL_DIR}"
      else
        sudo mkdir -p "$INSTALL_DIR"
        info "Created ${INSTALL_DIR}"
      fi
      ;;
  esac

  if [[ ":${PATH}:" != *":${INSTALL_DIR}:"* ]]; then
    warn "Selected install directory is not in PATH: ${INSTALL_DIR}"
    warn "signoff may not be found by OpenClaw/Hermes Gateway unless this directory is in PATH."
    printf "Add it to PATH, for example:\n"
    printf "  export PATH=\"%s:\$PATH\"\n" "${INSTALL_DIR}"
  fi
}

# ─── Ensure running signoff service is stopped before install ────────────
find_signoff_binary() {
  if [[ -x "${INSTALL_DIR}/${BINARY_NAME}" ]]; then
    echo "${INSTALL_DIR}/${BINARY_NAME}"
    return 0
  fi
  if command -v "${BINARY_NAME}" &>/dev/null; then
    command -v "${BINARY_NAME}"
    return 0
  fi
  return 1
}

detect_signoff_service_state() {
  local signoff_bin="$1"
  local output
  local state

  output="$("${signoff_bin}" status --json 2>/dev/null || true)"
  if [[ -n "$output" ]]; then
    state="$(sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<< "$output" | head -n 1)"
    if [[ -n "$state" ]]; then
      echo "$state"
      return 0
    fi
  fi

  output="$("${signoff_bin}" status 2>/dev/null || true)"
  if grep -qi "is unhealthy" <<< "$output"; then
    echo "unhealthy"
    return 0
  fi
  if grep -qi "is already running\|is running" <<< "$output"; then
    echo "running"
    return 0
  fi
  if grep -qi "is not running" <<< "$output"; then
    echo "stopped"
    return 0
  fi

  return 1
}

ensure_signoff_service_stopped_for_install() {
  local signoff_bin
  signoff_bin="$(find_signoff_binary || true)"
  if [[ -z "$signoff_bin" ]]; then
    return 0
  fi

  local state
  if ! state="$(detect_signoff_service_state "$signoff_bin")"; then
    warn "Could not determine existing signoff service status from ${signoff_bin}. Continuing install."
    return 0
  fi

  if [[ "$state" != "running" && "$state" != "unhealthy" ]]; then
    return 0
  fi

  warn "Detected existing signoff service state: ${state}"
  printf "Attempting graceful stop before installation... "
  if "${signoff_bin}" stop; then
    printf "${GREEN}done${NC}\n"
    info "Stopped existing signoff service"
    return 0
  fi
  printf "${YELLOW}FAILED${NC}\n"
  warn "Graceful stop failed."

  printf "Force stop with '${signoff_bin} stop --force' and continue install? [y/N] "
  local answer
  read -r answer
  if [[ "$answer" =~ ^[Yy] ]]; then
    if "${signoff_bin}" stop --force; then
      info "Force stop succeeded"
      return 0
    fi
    error "Force stop failed. Please stop signoff manually, then re-run install."
  fi

  error "Installation aborted because signoff service is still running."
}

# ─── Download and install binary ─────────────────────────────────────────
install_binary() {
  local tag="$1"

  resolve_install_dir

  local zip_name="signoff-cli-${tag}-${GOOS}-${GOARCH}.zip"
  local zip_path="${CACHE_DIR}/${zip_name}"
  local checksum_path="${CACHE_DIR}/SHA256SUMS-${tag}"
  local github_base_url="https://github.com/${RELEASES_REPO}/releases/download/${tag}"
  local downloads_base_url="${DOWNLOADS_BASE_URL}/releases/download/${tag}"

  mkdir -p "$CACHE_DIR"
  if ! download_file "SHA256SUMS" "$checksum_path" \
      "${github_base_url}/SHA256SUMS" \
      "${downloads_base_url}/SHA256SUMS"; then
    error "Could not download SHA256SUMS from GitHub or ${DOWNLOADS_BASE_URL}."
  fi

  if [[ -f "$zip_path" ]]; then
    if verify_archive_checksum "$checksum_path" "$zip_path" "$zip_name"; then
      printf "  Using cached ${zip_name}\n"
    else
      warn "Cached ${zip_name} failed checksum verification; downloading a fresh copy."
      rm -f "$zip_path"
    fi
  fi

  if [[ -f "$zip_path" ]]; then
    :
  else
    if ! download_verified_archive "$zip_name" "$zip_path" "$checksum_path" \
        "${github_base_url}/${zip_name}" \
        "${downloads_base_url}/${zip_name}"; then
      error "Download failed. Possible causes:
      - Network cannot reach github.com
      - Network cannot reach ${DOWNLOADS_BASE_URL}
      - Release ${tag} does not exist in ${RELEASES_REPO}
      - The zip file for ${GOOS}/${GOARCH} is missing
    Try specifying a tag manually, or check https://github.com/${RELEASES_REPO}/releases"
    fi
  fi

  printf "  Extracting... "
  local extract_dir
  extract_dir="$(mktemp -d)"
  unzip -qo "$zip_path" -d "$extract_dir" && printf "${GREEN}done${NC}\n" || {
    error "Failed to extract zip. The download may be corrupted."
  }

  local binary_src
  binary_src="$(find "${extract_dir}" -name "${BINARY_NAME}" -type f | head -n 1)"
  if [[ -z "$binary_src" ]]; then
    error "Binary '${BINARY_NAME}' not found in the downloaded package."
  fi

  chmod +x "$binary_src"

  if [[ -x "${INSTALL_DIR}/${BINARY_NAME}" ]]; then
    printf "signoff already installed at ${INSTALL_DIR}/${BINARY_NAME}. Upgrade? [Y/n] "
  else
    printf "Install signoff binary to ${INSTALL_DIR}/? [Y/n] "
  fi
  local answer
  read -r answer

  if [[ -z "$answer" || "$answer" =~ ^[Yy] ]]; then
    local installed_binary="${INSTALL_DIR}/${BINARY_NAME}"
    if [[ -w "$INSTALL_DIR" ]]; then
      cp "$binary_src" "$installed_binary"
    else
      sudo cp "$binary_src" "$installed_binary"
    fi
    info "Installed ${installed_binary}"
  else
    local installed_binary="${PWD}/${BINARY_NAME}"
    cp "$binary_src" "$installed_binary"
    info "Binary saved to ${installed_binary}"
    warn "Install later: sudo cp ${installed_binary} ${INSTALL_DIR}/${BINARY_NAME}"
  fi

  if [[ "$IS_MACOS" == true ]] && command -v xattr >/dev/null 2>&1; then
    if xattr -p com.apple.quarantine "$installed_binary" >/dev/null 2>&1; then
      xattr -d com.apple.quarantine "$installed_binary" 2>/dev/null \
        || sudo xattr -d com.apple.quarantine "$installed_binary" 2>/dev/null \
        || true
    fi
  fi

  printf "  Verifying installed signoff... "
  if "$installed_binary" version >/dev/null 2>&1; then
    printf "${GREEN}done${NC}\n"
  else
    printf "${YELLOW}FAILED${NC}\n"
    warn "Installed signoff could not run."
    if [[ "$IS_MACOS" == true ]]; then
      warn "Run diagnostics:"
      warn "  xattr -l \"${installed_binary}\""
      warn "  codesign --verify --strict --verbose=4 \"${installed_binary}\""
      warn "  spctl --assess --type execute --verbose=4 \"${installed_binary}\""
    fi
    rm -rf "$extract_dir"
    error "Installation aborted because the installed signoff binary failed verification."
  fi

  rm -rf "$extract_dir"
}

# ─── Download and install Claude Code wrapper ────────────────────────────
install_claude_wrapper() {
  local wrapper_ref="${SIGNOFF_WRAPPER_REF:-main}"
  local wrapper_url="${SIGNOFF_WRAPPER_URL:-https://raw.githubusercontent.com/${RELEASES_REPO}/${wrapper_ref}/wrappers/${CLAUDE_WRAPPER_NAME}}"
  local wrapper_fallback_url="https://github.com/${RELEASES_REPO}/raw/${wrapper_ref}/wrappers/${CLAUDE_WRAPPER_NAME}"
  local wrapper_downloads_url="${DOWNLOADS_BASE_URL}/wrappers/${CLAUDE_WRAPPER_NAME}"
  local wrapper_path="${INSTALL_DIR}/${CLAUDE_WRAPPER_NAME}"
  local tmp_wrapper

  if ! command -v claude &>/dev/null; then
    warn "Claude Code CLI not found. You can still install ${CLAUDE_WRAPPER_NAME} now and use it after installing Claude Code."
  fi

  if [[ -x "$wrapper_path" ]]; then
    printf "${CLAUDE_WRAPPER_NAME} already installed at ${wrapper_path}. Update from ${wrapper_ref}? [Y/n] "
  else
    printf "Install Claude Code wrapper to ${wrapper_path} from ${wrapper_ref}? [Y/n] "
  fi
  local answer
  read -r answer
  if [[ -n "$answer" && ! "$answer" =~ ^[Yy] ]]; then
    return 0
  fi

  tmp_wrapper="$(mktemp)"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local local_wrapper="${script_dir}/wrappers/${CLAUDE_WRAPPER_NAME}"

  if [[ -f "$local_wrapper" ]]; then
    printf "  Using local ${local_wrapper}\n"
    cp "$local_wrapper" "$tmp_wrapper"
  else
    printf "  Downloading ${CLAUDE_WRAPPER_NAME} from ${wrapper_url} ... "
    if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 180 "$wrapper_url" -o "$tmp_wrapper"; then
      printf "${GREEN}done${NC}\n"
    else
      printf "${YELLOW}FAILED${NC}\n"
      if [[ -z "${SIGNOFF_WRAPPER_URL:-}" ]]; then
        printf "  Retrying via ${wrapper_fallback_url} ... "
        if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 180 "$wrapper_fallback_url" -o "$tmp_wrapper"; then
          printf "${GREEN}done${NC}\n"
        elif curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 180 "$wrapper_downloads_url" -o "$tmp_wrapper"; then
          printf "${GREEN}done${NC}\n"
        else
          printf "${YELLOW}FAILED${NC}\n"
          rm -f "$tmp_wrapper"
          warn "Could not download ${CLAUDE_WRAPPER_NAME} from either:"
          warn "  ${wrapper_url}"
          warn "  ${wrapper_fallback_url}"
          warn "  ${wrapper_downloads_url}"
          printf "Continue installation without the Claude Code wrapper? [y/N] "
          local continue_answer
          read -r continue_answer
          if [[ "$continue_answer" =~ ^[Yy] ]]; then
            warn "Continuing without ${CLAUDE_WRAPPER_NAME}."
            return 0
          fi
          error "Installation aborted because ${CLAUDE_WRAPPER_NAME} could not be installed."
        fi
      else
        rm -f "$tmp_wrapper"
        warn "Could not download ${CLAUDE_WRAPPER_NAME} from ${wrapper_url}"
        printf "Continue installation without the Claude Code wrapper? [y/N] "
        local continue_answer
        read -r continue_answer
        if [[ "$continue_answer" =~ ^[Yy] ]]; then
          warn "Continuing without ${CLAUDE_WRAPPER_NAME}."
          return 0
        fi
        error "Installation aborted because ${CLAUDE_WRAPPER_NAME} could not be installed."
      fi
    fi
  fi

  chmod +x "$tmp_wrapper"
  if [[ -w "$INSTALL_DIR" ]]; then
    cp "$tmp_wrapper" "$wrapper_path"
  else
    sudo cp "$tmp_wrapper" "$wrapper_path"
  fi
  rm -f "$tmp_wrapper"
  info "Installed ${wrapper_path}"
}

# ─── Check plugin installed for a given agent CLI ────────────────────────
# Tries --json first (clean, unambiguous). Falls back to text output with
# warning lines filtered out, because raw `plugins list` may print a
# "Config warnings" block that references the plugin id even when it's
# uninstalled (stale config entry), which false-positives a naive grep.
is_plugin_installed_for() {
  local agent="$1"
  if ! command -v "$agent" &>/dev/null; then
    return 1
  fi

  printf "  [debug] running: %s plugins list --json\n" "$agent" >&2
  local json_output
  json_output="$("$agent" plugins list --json 2>/dev/null)"
  local json_exit=$?
  if [[ $json_exit -eq 0 && -n "$json_output" ]]; then
    # Use here-string instead of `echo | grep` to avoid SIGPIPE under
    # `set -o pipefail`: grep -q exits as soon as it matches, and the
    # upstream echo gets killed with 141, which pipefail then treats
    # as failure and falsely reports the plugin as not installed.
    if grep -Eq '"id"[[:space:]]*:[[:space:]]*"human-signoff-approval"' <<< "$json_output"; then
      return 0
    fi
    return 1
  fi

  printf "  [debug] --json unsupported (exit=%d), falling back to text parse\n" "$json_exit" >&2
  local text_output
  text_output="$("$agent" plugins list 2>&1)"
  if grep -v "plugin not found" <<< "$text_output" \
      | grep -v "stale config" \
      | grep -v "plugins\.entries\." \
      | grep -q "human-signoff-appro"; then
    return 0
  fi
  return 1
}

is_hermes_plugin_installed()   { is_plugin_installed_for hermes; }
is_openclaw_plugin_installed() { is_plugin_installed_for openclaw; }

uninstall_hermes_plugin_for_reinstall() {
  local plugin_dir_primary="${HOME}/.hermes/plugins/${HERMES_PLUGIN_DIR_NAME}"
  local plugin_dir_by_id="${HOME}/.hermes/plugins/human-signoff-approval"
  local has_dir=false
  if [[ -d "$plugin_dir_primary" || -d "$plugin_dir_by_id" ]]; then
    has_dir=true
  fi

  if ! is_hermes_plugin_installed && [[ "$has_dir" == false ]]; then
    return 0
  fi

  info "Refreshing existing Hermes approval plugin"
  hermes plugins disable human-signoff-approval >/dev/null 2>&1 || true

  local remove_target
  local removed=false
  for remove_target in "human-signoff-approval" "${HERMES_PLUGIN_DIR_NAME}"; do
    if hermes plugins remove "$remove_target" >/dev/null 2>&1; then
      removed=true
    fi
  done

  has_dir=false
  if [[ -d "$plugin_dir_primary" || -d "$plugin_dir_by_id" ]]; then
    has_dir=true
  fi

  if is_hermes_plugin_installed || [[ "$has_dir" == true ]]; then
    if [[ "$removed" == false ]]; then
      warn "Hermes plugin remove command did not complete successfully."
    fi
    error "Failed to fully remove existing Hermes approval plugin. Try: hermes plugins remove human-signoff-approval OR hermes plugins remove ${HERMES_PLUGIN_DIR_NAME}, then rerun installer."
  fi
}

uninstall_openclaw_plugin_for_reinstall() {
  local was_installed=false
  if is_openclaw_plugin_installed; then
    was_installed=true
  fi
  if [[ "$was_installed" == false && ! -d "${OPENCLAW_PLUGIN_DIR}" ]]; then
    return 0
  fi

  info "Refreshing existing OpenClaw approval plugin"
  openclaw plugins disable human-signoff-approval >/dev/null 2>&1 || true
  if [[ "$was_installed" == true ]]; then
    openclaw plugins uninstall human-signoff-approval --force >/dev/null 2>&1 || true
  fi

  if [[ -d "${OPENCLAW_PLUGIN_DIR}" ]]; then
    rm -rf "${OPENCLAW_PLUGIN_DIR}"
  fi

  openclaw plugins registry --refresh >/dev/null 2>&1 || true
}

reinstall_plugin_via_cli() {
  local repo="$1"
  local name="$2"

  if [[ "$name" == "hermes" ]]; then
    uninstall_hermes_plugin_for_reinstall
  else
    uninstall_openclaw_plugin_for_reinstall
  fi

  install_plugin_via_cli "$repo" "$name"
}

# ─── Install agent plugin via CLI ────────────────────────────────────────
install_plugin_via_cli() {
  local repo="$1"
  local name="$2"

  if [[ "$name" == "hermes" ]]; then
    printf "  Running: hermes plugins install %s\n" "$repo" >&2
    hermes plugins install "$repo" && printf "${GREEN}done${NC}\n" || {
      printf "${YELLOW}FAILED${NC}\n"
      return 1
    }
    printf "  Running: hermes plugins enable human-signoff-approval\n" >&2
    hermes plugins enable human-signoff-approval
  else
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    printf "  Downloading plugin from github.com... "
    curl -fsSL --connect-timeout 10 --max-time 60 \
      "https://github.com/${repo}/archive/refs/heads/main.tar.gz" \
      | tar xz -C "$tmp_dir" --strip-components=1 && printf "${GREEN}done${NC}\n" || {
      printf "${YELLOW}FAILED${NC}\n"
      rm -rf "$tmp_dir"
      return 1
    }
    ( cd "$tmp_dir" && openclaw plugins install . ) || {
      rm -rf "$tmp_dir"
      return 1
    }
    rm -rf "$tmp_dir"
  fi
  return 0
}

# ─── Offer install-ca ────────────────────────────────────────────────────
run_install_ca() {
  local signoff_bin
  signoff_bin="$(find_signoff_binary || true)"
  if [[ -z "$signoff_bin" ]]; then
    warn "signoff binary not found in PATH or ${INSTALL_DIR}; skipping CA installation prompt."
    return
  fi

  printf "Install CA certificate for protected HTTPS requests in HTTP proxy mode (requires sudo)? [Y/n] "
  local answer
  read -r answer
  if [[ -z "$answer" || "$answer" =~ ^[Yy] ]]; then
    sudo "$signoff_bin" install-ca && info "CA certificate installed" || warn "CA installation failed"
    ensure_signoff_data_permissions
  fi
}

resolve_real_user() {
  if [[ -n "${SUDO_USER:-}" ]]; then
    echo "${SUDO_USER}"
    return 0
  fi
  local login_user
  login_user="$(logname 2>/dev/null || true)"
  if [[ -n "$login_user" ]]; then
    echo "$login_user"
    return 0
  fi
  id -un
}

ensure_signoff_dir_writable() {
  local dir="$1"
  local owner="$2"
  if [[ ! -d "$dir" ]]; then
    return 0
  fi
  if [[ -w "$dir" ]]; then
    return 0
  fi
  warn "Fixing ownership for ${dir} (not writable by current user)"
  if sudo chown -R "$owner" "$dir"; then
    info "Fixed ownership of ${dir}"
  else
    warn "Failed to fix ownership of ${dir}"
  fi
}

ensure_signoff_data_permissions() {
  local real_user
  real_user="$(resolve_real_user)"
  local data_dirs=()

  if [[ "$IS_MACOS" == true ]]; then
    data_dirs+=("${HOME}/Library/Application Support/signoff-cli")
  else
    if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
      data_dirs+=("${XDG_CONFIG_HOME}/signoff-cli")
    else
      data_dirs+=("${HOME}/.config/signoff-cli")
    fi
  fi

  local dir
  for dir in "${data_dirs[@]}"; do
    ensure_signoff_dir_writable "$dir" "$real_user"
    ensure_signoff_dir_writable "${dir}/logs" "$real_user"
  done
}

warn_signoff_data_permission_issues() {
  local real_user
  real_user="$(resolve_real_user)"
  local data_dirs=()

  if [[ "$IS_MACOS" == true ]]; then
    data_dirs+=("${HOME}/Library/Application Support/signoff-cli")
  else
    if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
      data_dirs+=("${XDG_CONFIG_HOME}/signoff-cli")
    else
      data_dirs+=("${HOME}/.config/signoff-cli")
    fi
  fi

  local dir
  for dir in "${data_dirs[@]}"; do
    if [[ -d "$dir" && ! -w "$dir" ]]; then
      warn "Directory not writable: ${dir}"
      printf "  Run to fix: sudo chown -R %s \"%s\"\n" "$real_user" "$dir"
    fi
    if [[ -d "${dir}/logs" && ! -w "${dir}/logs" ]]; then
      warn "Directory not writable: ${dir}/logs"
      printf "  Run to fix: sudo chown -R %s \"%s\"\n" "$real_user" "${dir}/logs"
    fi
  done
}

# ─── Configure Gateway to use Signoff ────────────────────────────────────
configure_gateway_proxy() {
  local agent_name="$1"   # "Hermes" or "OpenClaw"

  printf "\n${CYAN}Configure ${agent_name} Gateway to use the local Signoff service?${NC}\n"

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
      info "${agent_name} Gateway already uses the local Signoff service"
      return
    fi

    printf "Add local Signoff service proxy settings to ${plist_name}.plist? [Y/n] "
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
      info "${agent_name} Gateway configured for Signoff and service reloaded"
    fi
  else
    local unit_name
    if [[ "$agent_name" == "Hermes" ]]; then
      unit_name="hermes-gateway"
    else
      unit_name="openclaw-gateway"
    fi

    local user_unit_dir="${HOME}/.config/systemd/user"
    local service_file="${user_unit_dir}/${unit_name}.service"

    if [[ ! -f "$service_file" ]]; then
      warn "${unit_name}.service not found at ${service_file}"
      printf "  Install ${agent_name} first, then re-run this script.\n"
      return
    fi

    local dropin_dir="${user_unit_dir}/${unit_name}.service.d"
    local dropin_file="${dropin_dir}/proxy.conf"

    if [[ -f "$dropin_file" ]] && grep -q "HTTP_PROXY=http://127.0.0.1:17771" "$dropin_file" 2>/dev/null; then
      info "${agent_name} Gateway already uses the local Signoff service"
      return
    fi

    printf "Add local Signoff service proxy settings to ${unit_name} systemd user service? [Y/n] "
    local answer
    read -r answer
    if [[ -z "$answer" || "$answer" =~ ^[Yy] ]]; then
      mkdir -p "$dropin_dir"
      tee "$dropin_file" >/dev/null <<'EOF'
[Service]
Environment=HTTP_PROXY=http://127.0.0.1:17771
Environment=HTTPS_PROXY=http://127.0.0.1:17771
Environment=NO_PROXY=localhost,127.0.0.1
EOF
      systemctl --user daemon-reload
      printf "Restart ${unit_name} now? [Y/n] "
      local restart_answer
      read -r restart_answer
      if [[ -z "$restart_answer" || "$restart_answer" =~ ^[Yy] ]]; then
        systemctl --user restart "${unit_name}" || warn "Failed to restart ${unit_name}"
      fi
      info "${agent_name} Gateway configured for Signoff"
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

ensure_signoff_service_stopped_for_install

# ─── Step 1: Get latest release tag ──────────────────────────────────────
header "Step 1: Download Signoff CLI"

TAG=""
printf "Enter release tag (leave blank for latest): "
read -r tag_input
if [[ -n "$tag_input" ]]; then
  TAG="$tag_input"
  info "Using tag: ${TAG}"
else
  TAG="$(fetch_latest_tag)" || {
    error "Could not determine latest release. Re-run and specify a tag manually."
  }
fi

install_binary "$TAG"

# ─── Step 2: Optional Claude Code wrapper ────────────────────────────────
header "Step 2: Claude Code Wrapper"
install_claude_wrapper

# ─── Step 3: Optional Hermes plugin ──────────────────────────────────────
HERMES_INSTALLED=false
header "Step 3: Hermes Approval Plugin"

if ! command -v hermes &>/dev/null; then
  warn "Hermes not found. To install the Hermes plugin, install Hermes first."
elif is_hermes_plugin_installed; then
  info "Hermes approval plugin already installed; reinstalling to update..."
  if reinstall_plugin_via_cli "$HERMES_PLUGIN_REPO" "hermes"; then
    info "Hermes approval plugin updated"
    HERMES_INSTALLED=true
  else
    error "Hermes plugin update failed"
  fi
else
  printf "Install Hermes approval plugin? [y/N] "
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

# ─── Step 4: Optional OpenClaw plugin ───────────────────────────────────
OPENCLAW_INSTALLED=false
header "Step 4: OpenClaw Approval Plugin"

if ! command -v openclaw &>/dev/null; then
  warn "OpenClaw not found. To install the OpenClaw plugin, install OpenClaw first."
elif is_openclaw_plugin_installed; then
  info "OpenClaw approval plugin already installed; reinstalling to update..."
  if reinstall_plugin_via_cli "$OPENCLAW_PLUGIN_REPO" "openclaw"; then
    info "OpenClaw approval plugin updated"
    OPENCLAW_INSTALLED=true
  else
    error "OpenClaw plugin update failed"
  fi
else
  printf "Install OpenClaw approval plugin? [y/N] "
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

# ─── Step 5: Install CA ──────────────────────────────────────────────────
header "Step 5: CA Certificate"
run_install_ca
warn_signoff_data_permission_issues

# ─── Done ────────────────────────────────────────────────────────────────
printf "\n${GREEN}╔══════════════════════════════════════════════════════╗${NC}\n"
printf "${GREEN}║       Installation complete!                         ║${NC}\n"
printf "${GREEN}╚══════════════════════════════════════════════════════╝${NC}\n"
printf "\nQuick start:\n"
printf "  1. ${CYAN}signoff login${NC}\n"
printf "  2. ${CYAN}signoff run${NC}              (start the Signoff service)\n"
printf "  3. ${CYAN}signoff-claude${NC}           (start Claude Code through Signoff)\n"
printf "\nFor more: ${CYAN}https://github.com/${RELEASES_REPO}${NC}\n"
