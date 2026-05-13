# Human Signoff CLI

[English](./README.md) | [简体中文](./README.zh-CN.md)

Human Signoff 提供一个本地代理，用于拦截敏感 API 调用（如 git push、PR merge、生产部署），并在请求继续前要求通过 **Passkey 人工审批**。它在 AI Agent（Claude Code、Hermes、OpenClaw）和你的生产基础设施之间提供一层安全闸门。

---

## 预检查（仅 Gateway 用户）

- 如果你计划使用 OpenClaw 或 Hermes 集成，请先确保对应 Gateway 已完成配置并处于运行状态，再继续后续步骤。
- 如果你只使用 Claude，可跳过这一前置条件，直接继续下面流程。

## 端到端操作指南

本指南覆盖完整初始化流程：从账号创建到完成第一次审批验证。

### 1. 安装 signoff CLI

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/merico-ai/human-signoff-releases/main/install.sh
bash install.sh
```

安装脚本会引导你完成：

- 二进制安装（由安装脚本交互选择路径：`/usr/local/bin/signoff`、`~/.local/bin/signoff`、`./signoff`，或你输入的自定义目录）
- CA 证书安装（用于 HTTPS 拦截，可选）
- AI Agent 插件安装（可选）

验证安装：

```bash
signoff --help
```

### 2. 注册账号

在浏览器打开注册页面：

```
https://demo.signoff.bio/#/register
```

输入邮箱、密码和显示名称后提交。注册完成后会自动登录。

### 3. 绑定 Passkey

Passkey（WebAuthn）用于对审批动作进行密码学确认。打开 **Account** 页面：

```
https://demo.signoff.bio/#/account
```

在 **Authenticators** 区域点击 **Add Passkey**，输入标签（如 `My MacBook`），并完成系统弹窗确认（Touch ID / Face ID / 系统密码）。

如果你使用多个浏览器或多个浏览器 profile，通常需要在执行审批的每个环境中分别绑定 Passkey。如果你的凭据提供方支持跨浏览器/跨设备同步，可能无需重复绑定即可使用。

添加完成后，你应能在列表中看到该 authenticator（含使用次数和创建时间）。

### 4. 配置拦截规则

规则用于定义哪些 API 请求需要审批。打开 **Rules** 页面：

```
https://demo.signoff.bio/#/rules
```

点击 **Add Rule**，至少填写以下字段，即可拦截 GitHub API 的任意 POST 请求：

| 字段 | 示例 | 说明 |
|---|---|---|
| Name | `GitHub POST` | 便于识别的规则名称 |
| Platform | `github` | 规则目标平台 |
| Hosts | `api.github.com` | 目标主机名（每行一个） |
| Path Pattern | `.*` | 路径匹配（正则） |
| HTTP Methods | `POST` | 需要拦截的 HTTP 方法（每行一个） |

点击 **Save** 保存。CLI 会在 10 秒内拉取到新规则。

### 5. 在 CLI 登录

```bash
signoff login
```

该命令会打开浏览器进行 OAuth 授权。完成授权后回到终端，CLI 会显示登录成功和账号邮箱。

检查登录状态：

```bash
signoff status
```

### 6. 启动代理

```bash
signoff run
```

代理默认监听在 `127.0.0.1:17771`。你会看到类似输出：

```
Signoff service started
PID: 12345
Listen: 127.0.0.1:17771
Log: /Users/.../signoff-cli/logs/signoff-20260510-153012-12345.log
```

代理以后台服务运行。可使用 `signoff stop` 停止，`signoff logs` 查看日志，`signoff status` 查看当前状态。

### 7. 验证拦截

设置代理环境变量并发送测试请求：

```bash
export HTTP_PROXY=http://127.0.0.1:17771
export HTTPS_PROXY=http://127.0.0.1:17771

curl -sv -X POST https://api.github.com/repos/owner/repo/deployments \
  -H "Content-Type: application/json" \
  -d '{"ref": "main"}' 2>&1
```

预期结果：请求被 `403` 拦截，并返回 `approval_url`：

```json
{"error":{"code":"RULE_MATCHED","message":"This command requires human approval..."},"approval_url":"https://demo.signoff.bio/..."}
```

可通过日志确认：

```bash
signoff logs
```

你应看到：

```
proxy_request method=POST host=api.github.com path=/repos/owner/repo/deployments
proxy_block fingerprint=... status=pending reason=RULE_MATCHED path=/repos/owner/repo/deployments
```

### 8. 在浏览器审批

1. 在浏览器打开拦截响应中的 `approval_url`
2. 检查请求详情（资源、动作、时间等）
3. 点击 **Approve with Passkey**
4. 完成系统 Passkey 确认（Touch ID / Face ID / 系统密码）

审批后，原请求即可继续。

### 9. 重试命令

再次执行同一条 curl 命令。审批通过后，请求会被放行：

```
proxy_allow fingerprint=... path=/repos/owner/repo/deployments
```

## 代理日志说明

所有经过代理的请求都会记录日志：

```
proxy_connect host=<host>:<port> target_host=<host> action=tunnel|mitm
proxy_request method=<method> host=<host> path=<path> query=<query> from=<client_ip> content_length=<size> user_agent="<ua>"
proxy_allow|proxy_block fingerprint=<id> status=<status> path=<path>
background_refresh_tick|background_refresh_ok|background_refresh_failed
```

使用 `signoff logs` 查看日志。

## 命令列表

| 命令 | 说明 |
|---|---|
| `signoff login` | 通过浏览器 OAuth 登录 |
| `signoff run` | 以后台服务启动代理 |
| `signoff run --foreground` | 在当前终端前台启动代理 |
| `signoff stop` | 停止后台代理服务 |
| `signoff status` | 查看代理状态（PID、监听地址、运行时长） |
| `signoff logs` | 查看代理日志 |
| `signoff install-ca` | 安装 CA 证书（需要 sudo） |
| `signoff uninstall-ca` | 卸载 CA 证书 |
| `signoff config set <key> <value>` | 设置配置 |
| `signoff config show` | 查看当前配置 |

## 发布包

每个 release 都会附带预编译二进制（`.zip`）：Linux（amd64）与 macOS（amd64/arm64）。
