# Human Signoff CLI

Human Signoff proxy client CLI and release assets.

## Install

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/merico-ai/human-signoff-releases/main/install.sh
bash install.sh
```

The installer will:

1. Download the `signoff` CLI binary
2. Optionally install the Hermes approval plugin
3. Optionally install the OpenClaw approval plugin
4. Optionally configure the CA certificate and gateway proxy settings

## Usage

```bash
signoff login
signoff run
```

## Releases

Pre-built binaries for Linux (amd64) and macOS (amd64/arm64) are uploaded to each release as `.zip` archives.
