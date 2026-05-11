# Human Signoff CLI

Human Signoff provides a local proxy that intercepts sensitive API calls (e.g., git push, PR merge, production deployment) and requires **human approval via Passkey** before the request proceeds. It acts as a safety gate between AI agents (Claude Code, Hermes, OpenClaw) and your production infrastructure.

## Quick Start

```bash
# 1. Install the CLI
curl -fsSL -o install.sh https://raw.githubusercontent.com/merico-ai/human-signoff-releases/main/install.sh
bash install.sh

# 2. Configure server URL and login
signoff config set server_url https://demo.signoff.bio
signoff login

# 3. Start the proxy
signoff run
```

Then configure your AI agent's HTTP proxy to `http://127.0.0.1:17771`.

---

## End-to-End Walkthrough

This guide walks through the complete setup — from creating an account to completing your first approval verification.

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

After adding, you should see the authenticator in the list with its usage count and creation time.

### 3. Configure an Interception Rule

Rules define which API requests should be intercepted for approval. Go to the **Rules** page:

```
https://demo.signoff.bio/#/rules
```

Click **Add Rule** and configure at minimum:

| Field | Example | Description |
|---|---|---|
| Name | `Protect production deploy` | A recognizable name |
| Platform | `github` | The platform this rule targets |
| Hosts | `api.github.com` | Target hostnames (one per line) |
| Path Pattern | `/repos/.*/deployments` | Regex pattern to match request paths |
| HTTP Methods | `POST` | HTTP methods to intercept (one per line) |

Advanced options include:

- **Query params** — Filter by specific query parameter values
- **Fingerprint mode** — Controls how requests are grouped for deduplication:
  - `Path + Query` (default) — group by path and query params
  - `Path only` — group by path only, ignore query params
  - `Path + Body` — include request body in fingerprint
  - `Path + Query + Body` — include both query and body
- **Resource type / ID** — Display information shown on the approval page
- **Action type** — Human-readable action name shown during approval

Click **Save** when done. The CLI will pick up the new rules within 10 seconds.

### 4. Install the signoff CLI

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/merico-ai/human-signoff-releases/main/install.sh
bash install.sh
```

The installer will:

1. Detect your OS and architecture
2. Download the latest binary to `/usr/local/bin/signoff`
3. Optionally install the Hermes or OpenClaw approval plugin
4. Optionally install the CA certificate for HTTPS interception

Verify installation:

```bash
signoff --help
```

### 5. Login from CLI

Configure the server URL and login:

```bash
signoff config set server_url https://demo.signoff.bio
signoff login
```

This opens your browser for OAuth authorization. Complete the login in the browser, then return to the terminal. The CLI will display a success message with your email.

Check login status:

```bash
signoff status
```

### 6. Install the CA Certificate

For the proxy to intercept HTTPS traffic (required for rule matching), install the CA certificate:

```bash
sudo signoff install-ca
```

This trusts the signoff CA on your system, allowing the proxy to decrypt and inspect HTTPS requests.

### 7. Install an Agent Plugin (Optional)

Signoff integrates with AI agent frameworks to automatically route traffic through the proxy.

#### Hermes Plugin

If you have [Hermes](https://github.com/merico-ai/hermes) installed:

```bash
hermes plugins install merico-ai/hermes-plugin-human-signoff-approval
hermes plugins enable human-signoff-approval
```

#### OpenClaw Plugin

If you have [OpenClaw](https://github.com/merico-ai/openclaw) installed:

```bash
openclaw plugins install merico-ai/openclaw-human-signoff
openclaw plugins enable human-signoff-approval
```

The installer script (`install.sh`) can also handle plugin installation for you.

### 8. Start the Proxy

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

### 9. Route Traffic Through the Proxy

Set your HTTP client's proxy to `http://127.0.0.1:17771`:

```bash
export HTTP_PROXY=http://127.0.0.1:17771
export HTTPS_PROXY=http://127.0.0.1:17771
export NO_PROXY=localhost,127.0.0.1
```

For AI agents, configure the proxy in the agent's settings. For example, Claude Code automatically works when the `HTTPS_PROXY` environment variable is set.

### 10. Trigger an Interception

Execute a command that matches one of your rules. For example, if you created a rule matching `POST api.github.com/repos/.*/deployments`:

```bash
curl -X POST https://api.github.com/repos/my-org/my-repo/deployments \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"ref": "main"}'
```

The request will be intercepted. The CLI logs show:

```
proxy_request method=POST host=api.github.com path=/repos/my-org/my-repo/deployments
proxy_block fingerprint=xxx status=pending reason=RULE_MATCHED path=/repos/my-org/my-repo/deployments
```

The client receives a `403` JSON response containing an `approval_url`.

### 11. Approve in Browser

1. Open the `approval_url` from the block response in your browser
2. Review the request details — resource, action, and timing
3. Click **Approve with Passkey**
4. Complete the system Passkey prompt (Touch ID / Face ID / system password)

After approval, the original request can proceed. The CLI detects the approval and resumes.

### 12. Retry the Command

Re-run the original command. Now that the approval is granted, the request passes through:

```
proxy_allow fingerprint=xxx path=/repos/my-org/my-repo/deployments
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
