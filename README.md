# UnlimitDS 一键配置 Skill

给 **Codex CLI** 和 **Claude Code** 一键配置 UnlimitDS。支持 Windows、macOS、Linux。

## 小白只做 3 步

### 1. 复制下面这段话，发给 Codex 或 Claude

```text
请从 https://github.com/CTctikki/unlimitds-agent-skill/tree/main/unlimitds-setup 安装 unlimitds-setup Skill。Codex 安装到 ~/.codex/skills/unlimitds-setup，Claude Code 安装到 ~/.claude/skills/unlimitds-setup。安装完成后立即读取 SKILL.md 并照做，只问我 API Key 和“标准模式/破甲模式”，不要让我手动修改配置。如果我没有 API Key，请提醒我可以打开 https://unlimitds.chat/，登录后进入“账户与用量”创建 Key。
```

### 2. 它问 API Key 时，粘贴你的 Key

没有 Key？打开 [UnlimitDS](https://unlimitds.chat/)，登录后进入“账户与用量”创建。

### 3. 选择模式，完成后重启

- **标准模式（推荐）**：日常编码。
- **破甲模式**：启用 UnlimitDS 提供的破甲模式。

看到“配置成功”后，**彻底关闭并重新打开 Codex/Claude**，然后正常聊天即可。

> API Key 就是密码。只发给你信任的本机 Agent，不要截图、公开或提交到 GitHub。

## 它会自动做什么

- 验证 API Key 能否使用。
- 自动检测 Codex CLI 和 Claude Code，装了哪个就配置哪个。
- 修改 Codex 配置前自动备份。
- 将 API Key 保存到当前用户环境，不写入本仓库。
- 可重复运行，用来换 Key 或切换模式。

## 手动安装（仅备用）

把仓库中的 `unlimitds-setup` 文件夹完整复制到对应目录：

- Codex：`~/.codex/skills/unlimitds-setup`
- Claude Code：`~/.claude/skills/unlimitds-setup`

然后重新打开 Agent，输入：

```text
请使用 unlimitds-setup 帮我配置 UnlimitDS。
```

## 说明

- 本项目是非官方社区工具，与 UnlimitDS、OpenAI、Anthropic 无隶属关系。
- 破甲模式不代表取消 Codex、Claude、模型服务或运行环境自身的安全规则，也不保证任何特定内容一定会被回答。
- API 接入文档：[https://unlimitds.chat/docs](https://unlimitds.chat/docs)

## License

MIT
