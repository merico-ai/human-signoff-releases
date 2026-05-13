# Human Signoff CLI

[English](./README.md) | [简体中文](./README.zh-CN.md)

Human Signoff provides a local proxy that intercepts sensitive API calls (e.g., git push, PR merge, production deployment) and requires **human approval via Passkey** before the request proceeds. It acts as a safety gate between AI agents (Claude Code, Hermes, OpenClaw) and your production infrastructure.

---

## Preflight (Gateway Users Only)

- If you plan to use OpenClaw or Hermes integration, ensure the corresponding Gateway is already configured and running before continuing.
- If you only use Claude, you can continue with the steps below without this prerequisite.

## End-to-End Walkthrough

This guide walks through the complete setup — from creating an account to completing your first approval verification.

### 1. Install the signoff CLI

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/merico-ai/human-signoff-releases/main/install.sh && bash install.sh
```

The installer will guide you through:

- Binary installation (installer-selected path: `/usr/local/bin/signoff`, `~/.local/bin/signoff`, `./signoff`, or a custom directory you enter)
- CA certificate installation for HTTPS interception (optional)
- AI agent plugin installation (optional)

Verify installation:

```bash
signoff --help
```

### 2. Register an Account

Open the registration page in your browser:

```
https://demo.signoff.bio/#/register
```

Enter your email, password, and display name, then submit. After registration, you'll be logged in automatically.

### 3. Add a Passkey

Passkey (WebAuthn) is used to cryptographically confirm approval actions. Go to the **Account** page:

```
https://demo.signoff.bio/#/account
```

In the **Authenticators** section, click **Add Passkey**, enter a label (e.g., "My MacBook"), and complete the system prompt (Touch ID / Face ID / system password).

If you use multiple browsers or browser profiles, you may need to register a Passkey in each one where approvals are performed. If your credential provider syncs passkeys across browsers/devices, it may already be available without re-registration.

After adding, you should see the authenticator in the list with its usage count and creation time.

### 4. Configure an Interception Rule

Rules define which API requests should be intercepted for approval. Go to the **Rules** page:

```
https://demo.signoff.bio/#/rules
```

Click **Add Rule** and enter these minimum fields to intercept any POST request to GitHub API:

| Field | Example | Description |
|---|---|---|
| Name | `GitHub POST` | A recognizable name |
| Platform | `github` | The platform this rule targets |
| Hosts | `api.github.com` | Target hostnames (one per line) |
| Path Pattern | `.*` | Match all paths (regex) |
| HTTP Methods | `POST` | HTTP methods to intercept (one per line) |

Click **Save** when done. The CLI will pick up the new rules within 10 seconds.

### 5. Login from CLI

```bash
signoff login
```

This opens your browser for OAuth authorization. Complete the login in the browser, then return to the terminal. The CLI will display a success message with your email.

Check login status:

```bash
signoff status
```

### 6. Start the Proxy

```bash
signoff run
```

The proxy starts on `127.0.0.1:17771` by default. You'll see:

```
Signoff service started
PID: 12345
Listen: 127.0.0.1:17771
Log: /Users/.../signoff-cli/logs/signoff-20260510-153012-12345.log
```

The proxy runs as a background service. Use `signoff stop` to stop it, `signoff logs` to view logs, and `signoff status` to check if it's running.

### 7. Verify Interception

Set the proxy environment variables and send a test request:

```bash
export HTTP_PROXY=http://127.0.0.1:17771
export HTTPS_PROXY=http://127.0.0.1:17771

curl -sv -X POST https://api.github.com/repos/owner/repo/deployments \
  -H "Content-Type: application/json" \
  -d '{"ref": "main"}' 2>&1
```

Expected result — the request is blocked with a `403` response containing an `approval_url`:

```json
{"error":{"code":"RULE_MATCHED","message":"This command requires human approval..."},"approval_url":"https://demo.signoff.bio/..."}
```

Check the proxy logs to confirm:

```bash
signoff logs
```

You should see:

```
proxy_request method=POST host=api.github.com path=/repos/owner/repo/deployments
proxy_block fingerprint=... status=pending reason=RULE_MATCHED path=/repos/owner/repo/deployments
```

### 8. Approve in Browser

1. Open the `approval_url` from the block response in your browser
2. Review the request details — resource, action, and timing
3. Click **Approve with Passkey**
4. Complete the system Passkey prompt (Touch ID / Face ID / system password)

After approval, the original request can proceed.

### 9. Retry the Command

Re-run the same curl command. Now that the approval is granted, the request passes through:

```
proxy_allow fingerprint=... path=/repos/owner/repo/deployments
```

## Proxy Logs Explained

All requests passing through the proxy are logged:

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
| `signoff run` | Start proxy as a background service |
| `signoff run --foreground` | Start proxy in the current terminal |
| `signoff stop` | Stop the background proxy service |
| `signoff status` | Check proxy status (PID, listen address, uptime) |
| `signoff logs` | View proxy logs |
| `signoff install-ca` | Install CA certificate (requires sudo) |
| `signoff uninstall-ca` | Remove CA certificate |
| `signoff config set <key> <value>` | Set configuration |
| `signoff config show` | Show current configuration |

## Releases

Pre-built binaries for Linux (amd64) and macOS (amd64/arm64) are uploaded to each release as `.zip` archives.
