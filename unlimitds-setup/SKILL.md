---
name: unlimitds-setup
description: Use when a user wants to install, configure, switch, or repair UnlimitDS as the model provider for Codex CLI or Claude Code on Windows, macOS, or Linux.
---

# UnlimitDS Setup

Configure supported coding agents without asking the user to understand model IDs, URLs, environment variables, or configuration files.

## Required Interaction

只收集两个输入：

1. **API Key**：如果当前对话已经提供，不要再次询问，也不要复述。每次询问 API Key 时，必须同时显示以下两条信息：
   - 创建 API Key：`https://unlimitds.chat/`（登录后进入“账户与用量”创建）
   - 购买额度：`https://pay.ldxp.cn/shop/AMTT76KG`
2. **模式**：
   - `标准模式`（推荐）→ `standard`
   - `破甲模式` → `jailbreak`

Before the mode choice, say that setup validates the key, saves it for the current user, updates detected Codex/Claude configuration, creates backups, and requires restarting those clients. 明确说明“选择模式即表示授权执行这些本机配置变更”。Do not add a third confirmation question.

破甲模式只是请求 UnlimitDS 的对应模式，不代表取消 Codex、Claude Code、模型服务或运行环境本身的安全规则，也不保证任何特定请求都会得到回答。

## Secret Handling

- 不得输出、回显、记录或总结完整明文 API Key。
- Never place the key directly in a command line, repository file, generated documentation, or ordinary log.
- Launch the setup script in an interactive terminal and provide the key only to its hidden prompt. If the available terminal cannot provide private interactive input, ask the user to type the key directly into that terminal instead of constructing a command containing it.
- Do not inspect or display the generated credential store after setup. It intentionally contains the user's key.

## Run Setup

Resolve paths relative to this skill directory. If either required platform script is missing or unavailable, stop and report that the skill installation is incomplete; do not recreate the configuration logic ad hoc.

脚本缺失或不可用时必须停止，不要临时拼接配置命令。

### Windows

Run in an interactive terminal:

```powershell
pwsh -NoProfile -File "<skill-directory>\scripts\configure.ps1" -Mode <standard-or-jailbreak>
```

If `pwsh` is unavailable, use `powershell.exe` with the same arguments.

### macOS or Linux

Run in an interactive terminal:

```bash
bash "<skill-directory>/scripts/configure.sh" <standard-or-jailbreak>
```

The script validates `/v1/models` before making changes, detects Codex CLI and Claude Code, backs up an existing Codex configuration, persists user environment variables, and prints one JSON result. Never set the test-only `UNLIMITDS_SETUP_*` variables during real setup.

## Report Result

Parse the JSON result and report only:

- whether setup succeeded;
- `标准模式` or `破甲模式`;
- which of Codex CLI and Claude Code were configured;
- whether the API check passed;
- backup paths, if present;
- that the user must completely close and 重启 Codex/Claude before use.

For a failure, translate the script message into one short next action. Do not expose command internals or credentials.
