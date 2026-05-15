# Human Signoff CLI

[English](./README.md) | [简体中文](./README.zh-CN.md)

Human Signoff provides a local Signoff service that protects sensitive API calls (e.g., git push, PR merge, production deployment) by requiring **human approval via Passkey** before the request proceeds. It acts as a safety gate between AI agents (OpenClaw, Hermes, Claude Code) and your production infrastructure.

Follow the steps below to go from zero to your first approved request.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Register & Configure](#register--configure)
- [Install CLI](#install-cli)
- [First Approval](#first-approval)
- [Mobile Approval (Optional)](#mobile-approval-optional)
- [Service Logs Explained](#service-logs-explained)
- [Commands](#commands)

---

## Prerequisites

- Supported platforms: macOS (amd64 / arm64) and Linux (amd64).
- If you plan to use OpenClaw or Hermes integration, ensure the corresponding Gateway is already configured and running before continuing.
- If you only use Claude Code, you can continue with the steps below without this prerequisite.

## Register & Configure

### 1. Register an Account

Open the registration page in your browser:

```
https://demo.signoff.bio/#/register
```

Enter your email, password, and display name, then submit. After registration, you'll be logged in automatically.

### 2. Add a Passkey

Passkey (WebAuthn) is used to cryptographically confirm approval actions. Go to the **Account** page:

```
https://demo.signoff.bio/#/account
```

In the **Authenticators** section, click **Add Passkey**, enter a label (e.g., "My MacBook"), and complete the system prompt (Touch ID / Face ID / system password).

If you use multiple browsers or browser profiles, you may need to register a Passkey in each one where approvals are performed. If your credential provider syncs passkeys across browsers/devices, it may already be available without re-registration.

After adding, you should see the authenticator in the list with its usage count and creation time.

### 3. Configure an Approval Rule

Rules define which API requests require Signoff approval before they proceed. Go to the **Rules** page:

```
https://demo.signoff.bio/#/rules
```

Click **Add rule** → **Create from scratch**, then fill these required fields for a low-friction verification rule (no extra token required):

| Field | Example | Description |
|---|---|---|
| Rule name | `GitHub PR Query Check` | A recognizable name |
| Platform | `github` | The platform this rule targets |
| Hosts | `api.github.com` | Target hostnames (one per line) |
| Path regex pattern | `^/repos/[^/]+/[^/]+/pulls$` | Match pull request list queries (regex) |
| HTTP Methods | `GET` | HTTP methods covered by this rule (one per line) |

Click **Save** when done. After you start the local Signoff service, it will pick up new rules within 10 seconds.

## Install CLI

### 4. Install the signoff CLI

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/merico-ai/human-signoff-releases/main/install.sh && bash install.sh
```

The installer will guide you through:

- Binary installation (installer-selected path: `/usr/local/bin/signoff`, `~/.local/bin/signoff`, `./signoff`, or a custom directory you enter)
- CA certificate installation for protected HTTPS requests in HTTP proxy mode (optional)
- AI agent plugin installation (optional)

Important: install `signoff` to a directory that is already in your `PATH` (recommended: `/usr/local/bin` or `~/.local/bin`). If the install directory is not in `PATH`, commands and Gateway integrations (OpenClaw/Hermes) may not find `signoff`.

Verify installation:

```bash
signoff --help
```

If `signoff` is not found, add the install directory to `PATH` or reinstall to a `PATH` directory.

## First Approval

### 5. Login from CLI

```bash
signoff login
```

This opens your browser for OAuth authorization. Complete the login in the browser, then return to the terminal. The CLI will display a success message with your email.

Check login status:

```bash
signoff whoami
```

### 6. Start the Signoff Service

```bash
signoff run
```

The local Signoff service listens on `127.0.0.1:17771` by default. You'll see:

```
Signoff service started
PID: 12345
Listen: 127.0.0.1:17771
Log: /Users/.../signoff-cli/logs/signoff-20260510-153012-12345.log
```

Signoff runs as a background local service. Use `signoff stop` to stop it, `signoff logs` to view logs, and `signoff status` to check if it's running.

Check service status:

```bash
signoff status
```

Print startup logs and check for errors:

```bash
signoff logs
```

The startup log should not show obvious fatal issues (for example: panic stacks, fatal exits, or repeated crash/restart messages).

### 7. Verify a Protected Request

Set the HTTP proxy environment variables and send a harmless test request covered by the approval rule:

```bash
export HTTP_PROXY=http://127.0.0.1:17771
export HTTPS_PROXY=http://127.0.0.1:17771

curl -sv "https://api.github.com/repos/octocat/Hello-World/pulls?state=open" 2>&1
```

Expected result: Signoff pauses the request for approval and returns a `403` response containing an `approval_url`:

```json
{"error":{"code":"APPROVAL_PENDING","message":"This command requires human approval..."},"approval_url":"https://demo.signoff.bio/#/requests/pap_xxx","approval_request_id":"pap_xxx","status":"pending"}
```

The response may include additional fields (for example `approval_status_url`, retry guidance, and polling hints).

Check the service logs to confirm:

```bash
signoff logs
```

The current implementation uses HTTP proxy mode, so log event names may include `proxy_*`:

```
proxy_request method=GET host=api.github.com path=/repos/octocat/Hello-World/pulls query=state=open
proxy_block fingerprint=... status=pending reason=APPROVAL_PENDING path=/repos/octocat/Hello-World/pulls
```

### 8. Approve in Browser

1. Open the `approval_url` from the pending approval response in your browser
2. If you land on the requests list page first, click **Open** on that request to enter the detail page
3. Review the request details — resource, action, and timing
4. Click **Approve with Passkey**
5. Complete the system Passkey prompt (Touch ID / Face ID / system password)

After approval, the original request can proceed.

### 9. Retry the Command

Re-run the same curl command. Now that the approval is granted, the request proceeds:

```
proxy_allow fingerprint=... path=/repos/octocat/Hello-World/pulls
```

Note: this verification example queries a public repository endpoint, so no GitHub token is required. Signoff success is indicated by `proxy_allow` and the absence of `APPROVAL_PENDING` on retry.

> [!TIP]
> **In practice**: The manual test above verifies that protected requests wait for approval. During normal use, protected requests from OpenClaw, Hermes, or Claude Code are handled automatically by the local Signoff service. You only need to approve them in the browser when prompted.

## Mobile Approval (Optional)

If you're not always at your computer, you can configure an external IM notification channel (e.g., Slack, Telegram) in OpenClaw or Hermes to push approval requests to your phone.

Refer to the corresponding agent documentation for IM plugin/channel configuration.

> [!WARNING]
> **Important notes**:
> - Approval links must be opened in a browser that supports WebAuthn (Chrome, Safari, etc.). In-app browsers in WeChat, Lark, and similar apps do not support Passkey signing.
> - You must log in to the Signoff service on your phone before your first mobile approval (subsequent approvals do not require re-login).
> - You must register a Passkey on the mobile device (see [Step 2](#2-add-a-passkey)) before your first mobile approval, or signing will fail.

## Service Logs Explained

All requests handled by the local Signoff service are logged. The current implementation uses HTTP proxy mode, so technical log event names may include `proxy_*`:

```
proxy_connect host=<host>:<port> target_host=<host> action=tunnel|mitm
proxy_request method=<method> host=<host> path=<path> query=<query> from=<client_ip> content_length=<size> user_agent="<ua>"
proxy_allow|proxy_block fingerprint=<id> status=<status> path=<path>
background_refresh_tick|background_refresh_ok|background_refresh_failed
```

Use `signoff logs` to view the logs.

## Commands

| Command | Description |
|---|---|
| `signoff login` | Authenticate via browser OAuth |
| `signoff whoami` | Show current login status |
| `signoff run` | Start the local Signoff service |
| `signoff stop` | Stop the local Signoff service |
| `signoff status` | Check service status (PID, listen address, uptime) |
| `signoff logs` | View service logs |
| `signoff install-ca` | Install CA certificate (requires sudo) |
| `signoff uninstall-ca` | Remove CA certificate |
| `signoff config set <key> <value>` | Set configuration |
| `signoff config list` | Show current configuration |

## Releases

Pre-built binaries for Linux (amd64) and macOS (amd64/arm64) are uploaded to each release as `.zip` archives.
