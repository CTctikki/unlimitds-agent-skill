# UnlimitDS Agent Skill 设计

## 目标

创建一个公开 GitHub 仓库，让零基础用户把一段固定提示发送给 Codex 或 Claude 等支持 Agent Skills 的代理后，由代理自动安装技能。安装完成后，用户只需提供自己的 UnlimitDS API Key，并选择“标准模式”或“破甲模式”，即可自动配置 Codex CLI 与 Claude Code 使用 UnlimitDS。

## 支持范围

- 操作系统：Windows、macOS、Linux。
- 客户端：Codex CLI、Claude Code。
- 配置对象：当前用户级配置，不修改系统级配置。
- 模型：默认使用 `deepseek-v4-pro`；破甲模式通过模型后缀 `_jailbreak` 启用。
- 密钥：持久保存到当前用户环境，不写入 Git 仓库或技能文件。

## 用户体验

用户向 Agent 发送仓库提供的安装提示。Agent 安装技能后执行以下流程：

1. 询问 UnlimitDS API Key。
2. 让用户选择“标准模式”或“破甲模式”。
3. 检测本机是否安装 Codex CLI、Claude Code。
4. 对已安装的客户端写入用户级配置；两个客户端都存在时全部配置。
5. 修改现有配置前创建带时间戳的备份。
6. 使用 `/v1/models` 验证 API Key 与网络连通性。
7. 隐去密钥，只报告已配置客户端、所选模式、测试结果和重启提示。

除 API Key 与模式外，不要求用户理解或填写 Base URL、模型 ID、环境变量名或配置文件路径。

## 仓库结构

```text
unlimitds-agent-skill/
|-- README.md
|-- LICENSE
|-- unlimitds-setup/
|   |-- SKILL.md
|   |-- agents/
|   |   `-- openai.yaml
|   `-- scripts/
|       |-- configure.ps1
|       `-- configure.sh
`-- docs/
    `-- superpowers/specs/
```

`SKILL.md` 负责识别配置意图、收集两个输入、选择平台脚本和安全报告结果。脚本负责确定性地验证密钥、保存用户环境变量、备份和更新客户端配置。

## 配置设计

### Codex CLI

更新用户目录下的 `.codex/config.toml`：

```toml
model = "deepseek-v4-pro"
model_provider = "unlimitds"

[model_providers.unlimitds]
name = "UnlimitDS"
base_url = "https://unlimitds.chat/v1"
env_key = "UNLIMITDS_API_KEY"
wire_api = "responses"
```

破甲模式将顶层 `model` 设置为 `deepseek-v4-pro_jailbreak`。脚本只更新相关键和 `unlimitds` provider，尽量保留用户的其他 Codex 配置。

### Claude Code

持久化以下用户环境变量：

- `ANTHROPIC_BASE_URL=https://unlimitds.chat`
- `ANTHROPIC_AUTH_TOKEN=<用户 API Key>`
- `ANTHROPIC_MODEL=deepseek-v4-pro`，破甲模式为 `deepseek-v4-pro_jailbreak`

同时持久化 `UNLIMITDS_API_KEY`，供 Codex 使用。Windows 写入用户级环境变量；macOS/Linux 写入专用环境文件，并在用户现有 shell 启动文件中加入可重复执行且不会重复插入的加载片段。

## 安全与错误处理

- API Key 仅通过参数或安全输入传给本地脚本，不写入仓库内容。
- 输出只显示掩码后的密钥。
- 写配置前先验证 Key；验证失败时不修改配置。
- 写入采用临时文件替换，降低中断导致配置损坏的风险。
- 现有配置在首次修改前创建带时间戳的备份。
- 找不到任何受支持客户端时，不写客户端配置，并给出安装提示。
- API 返回 `401` 时提示 Key 无效；`429` 提示额度或限制；网络与其他状态码保留可操作的简短错误。
- 脚本不会自动启动客户端，也不会上传或记录用户密钥。

## 安装方式

README 提供一段可直接复制给 Agent 的提示，要求它使用自身的 Skill 安装机制从公开 GitHub 仓库安装 `unlimitds-setup`，随后运行该技能完成配置。另提供人工安装命令作为兜底，但不作为小白主路径。

## 验证标准

- Skill 目录通过官方 `quick_validate.py`。
- PowerShell 脚本在隔离临时用户目录中完成标准与破甲配置测试。
- Bash 脚本至少通过语法检查，并在可用的 Bash 环境中完成隔离配置测试。
- 使用真实 API Key 验证 `/v1/models`，日志中不出现完整 Key。
- 安装脚本从最终公开 GitHub URL 下载技能到临时技能目录，并验证文件结构。
- GitHub 仓库为 public，README 可匿名访问。

## 非目标

- 不内置、分发或提交任何 API Key。
- 不绕过 Codex、Claude Code 或模型提供方自身的安全策略。
- 不保证破甲模式对任何特定内容一定产生不同回答；只保证按 UnlimitDS 文档显式启用该模式。
- 不支持 OpenCode、图形化聊天客户端或系统级代理设置。
