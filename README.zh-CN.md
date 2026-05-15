# Human Signoff CLI

[English](./README.md) | [简体中文](./README.zh-CN.md)

Human Signoff 提供一个本地 Signoff 服务，用于保护敏感 API 调用（如 git push、PR merge、生产部署），并在请求继续前要求通过 **Passkey 人工审批**。它在 AI Agent（OpenClaw、Hermes、Claude Code）和你的生产基础设施之间提供一层安全闸门。

按以下步骤操作，从零完成首次审批。

## 目录

- [前置条件](#前置条件)
- [注册与配置](#注册与配置)
- [安装 CLI](#安装-cli)
- [完成首次审批](#完成首次审批)
- [移动端审批（可选）](#移动端审批可选)
- [服务日志说明](#服务日志说明)
- [命令列表](#命令列表)

---

## 前置条件

- 支持平台：macOS（amd64 / arm64）与 Linux（amd64）。
- 如果你计划使用 OpenClaw 或 Hermes 集成，请先确保对应 Gateway 已完成配置并处于运行状态，再继续后续步骤。
- 如果你只使用 Claude Code，可跳过这一前置条件，直接继续下面流程。

## 注册与配置

### 1. 注册账号

在浏览器打开注册页面：

```
https://demo.signoff.bio/#/register
```

输入邮箱、密码和显示名称后提交。注册完成后会自动登录。

### 2. 绑定 Passkey

Passkey（WebAuthn）用于对审批动作进行密码学确认。打开 **Account** 页面：

```
https://demo.signoff.bio/#/account
```

在 **Authenticators** 区域点击 **Add Passkey**，输入标签（如 `My MacBook`），并完成系统弹窗确认（Touch ID / Face ID / 系统密码）。

如果你使用多个浏览器或多个浏览器 profile，通常需要在执行审批的每个环境中分别绑定 Passkey。如果你的凭据提供方支持跨浏览器/跨设备同步，可能无需重复绑定即可使用。

添加完成后，你应能在列表中看到该 authenticator（含使用次数和创建时间）。

### 3. 配置审批规则

规则用于定义哪些 API 请求在继续前需要 Signoff 审批。打开 **Rules** 页面：

```
https://demo.signoff.bio/#/rules
```

点击 **Add rule** → **Create from scratch**，然后填写以下必填字段，配置一个低门槛验证规则（无需额外 token）：

| 字段 | 示例 | 说明 |
|---|---|---|
| Rule name（规则名称） | `GitHub PR Query Check` | 便于识别的规则名称 |
| Platform | `github` | 规则目标平台 |
| Hosts | `api.github.com` | 目标主机名（每行一个） |
| Path regex pattern（路径正则） | `^/repos/[^/]+/[^/]+/pulls$` | 匹配 PR 列表查询接口（正则） |
| HTTP Methods（HTTP 方法） | `GET` | 此规则保护的 HTTP 方法（每行一个） |

点击 **Save** 保存。启动本地 Signoff 服务后，它会在 10 秒内拉取到新规则。

## 安装 CLI

### 4. 安装 signoff CLI

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/merico-ai/human-signoff-releases/main/install.sh && bash install.sh
```

安装脚本会引导你完成：

- 二进制安装（由安装脚本交互选择路径：`/usr/local/bin/signoff`、`~/.local/bin/signoff`、`./signoff`，或你输入的自定义目录）
- CA 证书安装（用于 HTTP 代理模式下受保护的 HTTPS 请求，可选）
- AI Agent 插件安装（可选）

重要：请将 `signoff` 安装到已在 `PATH` 中的目录（推荐：`/usr/local/bin` 或 `~/.local/bin`）。如果安装目录不在 `PATH` 中，命令本身以及 OpenClaw/Hermes Gateway 集成都可能找不到 `signoff`。

验证安装：

```bash
signoff --help
```

如果出现 `signoff` 未找到，请先把安装目录加入 `PATH`，或重新安装到 `PATH` 目录。

## 完成首次审批

### 5. 在 CLI 登录

```bash
signoff login
```

该命令会打开浏览器进行 OAuth 授权。完成授权后回到终端，CLI 会显示登录成功和账号邮箱。

检查登录状态：

```bash
signoff whoami
```

### 6. 启动 Signoff 服务

```bash
signoff run
```

本地 Signoff 服务默认监听在 `127.0.0.1:17771`。你会看到类似输出：

```
Signoff service started
PID: 12345
Listen: 127.0.0.1:17771
Log: /Users/.../signoff-cli/logs/signoff-20260510-153012-12345.log
```

Signoff 会作为本地后台服务运行。可使用 `signoff stop` 停止，`signoff logs` 查看日志，`signoff status` 查看当前状态。

检查服务状态：

```bash
signoff status
```

打印启动日志并检查是否有错误：

```bash
signoff logs
```

启动日志中不应出现明显致命异常（例如 panic 堆栈、fatal 退出、或反复崩溃/重启日志）。

### 7. 验证受保护请求

设置 HTTP 代理环境变量，并发送一个由审批规则覆盖的无害测试请求：

```bash
export HTTP_PROXY=http://127.0.0.1:17771
export HTTPS_PROXY=http://127.0.0.1:17771

curl -sv "https://api.github.com/repos/octocat/Hello-World/pulls?state=open" 2>&1
```

预期结果：Signoff 会让请求等待审批，并返回一个包含 `approval_url` 的 `403` 响应：

```json
{"error":{"code":"APPROVAL_PENDING","message":"This command requires human approval..."},"approval_url":"https://demo.signoff.bio/#/requests/pap_xxx","approval_request_id":"pap_xxx","status":"pending"}
```

实际响应中可能还会包含其他字段（例如 `approval_status_url`、重试建议和轮询提示）。

可通过服务日志确认：

```bash
signoff logs
```

当前实现使用 HTTP 代理模式，因此日志事件名中可能包含 `proxy_*`：

```
proxy_request method=GET host=api.github.com path=/repos/octocat/Hello-World/pulls query=state=open
proxy_block fingerprint=... status=pending reason=APPROVAL_PENDING path=/repos/octocat/Hello-World/pulls
```

### 8. 在浏览器审批

1. 在浏览器打开等待审批响应中的 `approval_url`
2. 如果先进入的是请求列表页，请先点击该请求的 **Open** 进入详情页
3. 检查请求详情（资源、动作、时间等）
4. 点击 **Approve with Passkey**
5. 完成系统 Passkey 确认（Touch ID / Face ID / 系统密码）

审批后，原请求即可继续。

### 9. 重试命令

再次执行同一条 curl 命令。审批通过后，请求会被放行：

```
proxy_allow fingerprint=... path=/repos/octocat/Hello-World/pulls
```

注意：该验证示例查询的是公共仓库接口，不需要 GitHub token。是否由 Signoff 放行应以日志中的 `proxy_allow` 以及重试时不再出现 `APPROVAL_PENDING` 为准。

> [!TIP]
> **实际使用场景**：上述手动测试仅用于验证受保护请求会等待审批。日常使用中，OpenClaw、Hermes 或 Claude Code 发起的受保护请求会由本地 Signoff 服务自动处理，你只需在浏览器中完成审批即可。

## 移动端审批（可选）

如果你不总是在电脑前，可以通过 OpenClaw 或 Hermes 配置外部 IM 通知渠道（如 微信、飞书等），将审批请求推送到手机，随时完成审批。

具体的 IM plugin/channel 配置方式请参考对应工具的文档。

> [!WARNING]
> **注意事项**：
> - 审批链接必须使用 Chrome 或 Safari 等支持 WebAuthn 的浏览器打开。微信、飞书等应用的内置浏览器不支持 Passkey 签署。
> - 首次在手机上审批前，需要先登录 Signoff 服务（后续无需重复登录）。
> - 首次在手机上审批前，需要在该设备上绑定 Passkey（即[步骤 2](#2-绑定-passkey)），否则签署会失败。

## 服务日志说明

本地 Signoff 服务处理的请求都会记录日志。当前实现使用 HTTP 代理模式，因此技术日志事件名中可能包含 `proxy_*`：

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
| `signoff whoami` | 查看当前登录状态 |
| `signoff run` | 启动本地 Signoff 服务 |
| `signoff stop` | 停止本地 Signoff 服务 |
| `signoff status` | 查看服务状态（PID、监听地址、运行时长） |
| `signoff logs` | 查看服务日志 |
| `signoff install-ca` | 安装 CA 证书（需要 sudo） |
| `signoff uninstall-ca` | 卸载 CA 证书 |
| `signoff config set <key> <value>` | 设置配置 |
| `signoff config list` | 查看当前配置 |

## 发布包

每个 release 都会附带预编译二进制（`.zip`）：Linux（amd64）与 macOS（amd64/arm64）。
