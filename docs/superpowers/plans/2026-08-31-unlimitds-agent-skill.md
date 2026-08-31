# UnlimitDS Agent Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and publish a zero-knowledge, cross-platform Agent Skill that configures Codex CLI and Claude Code to use UnlimitDS after asking only for an API key and standard or jailbreak mode.

**Architecture:** The repository exposes one portable `unlimitds-setup` skill and deterministic PowerShell/Bash configuration scripts. The skill owns the two-question interaction and invokes the matching local script; each script validates the key before making changes, detects supported clients, backs up and updates user configuration, persists environment variables, and emits a redacted summary. Shell-native contract tests run against isolated fake home directories, while repository-level checks validate skill metadata, secret hygiene, installation, and the live API.

**Tech Stack:** Agent Skills (`SKILL.md`, `agents/openai.yaml`), PowerShell 7/Windows PowerShell, POSIX Bash, TOML text transformation, `curl`/`Invoke-RestMethod`, GitHub CLI.

---

## File Map

- `unlimitds-setup/SKILL.md`: Agent-facing two-question workflow, platform dispatch, safe handling, and completion reporting.
- `unlimitds-setup/agents/openai.yaml`: Codex UI name, description, and default prompt metadata.
- `unlimitds-setup/scripts/configure.ps1`: Windows setup, API validation, user environment persistence, Codex TOML update, backups, and JSON result.
- `unlimitds-setup/scripts/configure.sh`: macOS/Linux equivalent, including shell startup loading.
- `tests/configure.ps1.tests.ps1`: Dependency-free PowerShell behavioral tests using isolated homes and test-only environment overrides.
- `tests/configure.sh.test.sh`: Dependency-free Bash behavioral tests using isolated homes and fake client commands.
- `tests/repository.tests.ps1`: Skill contract, secret scan, documentation, and installation-layout tests.
- `README.md`: Extremely short novice instructions plus troubleshooting and manual fallback.
- `LICENSE`: MIT license for public reuse.
- `.gitignore`: Test output and local secret exclusions.

### Task 1: Establish PowerShell Contract Tests

**Files:**
- Create: `tests/configure.ps1.tests.ps1`

- [ ] **Step 1: Write the failing standard-mode test**

Create a dependency-free test runner that creates a temporary home containing an existing `.codex/config.toml`, sets `UNLIMITDS_SETUP_TEST_MODE=1`, `UNLIMITDS_SETUP_HOME=<temp>`, `UNLIMITDS_SETUP_CLIENTS=both`, `UNLIMITDS_SETUP_SKIP_API_CHECK=1`, and `UNLIMITDS_API_KEY_INPUT=uds_test_key_12345678`, then invokes:

```powershell
& "$PSScriptRoot/../unlimitds-setup/scripts/configure.ps1" -Mode standard
```

Assert exit code zero, preserved unrelated TOML content, exactly one `model_provider = "unlimitds"`, model `deepseek-v4-pro`, provider `base_url`, `env_key`, and `wire_api`, plus a timestamped backup and a JSON summary that never contains the full test key.

- [ ] **Step 2: Run the test to verify RED**

Run: `pwsh -NoProfile -File tests/configure.ps1.tests.ps1`

Expected: FAIL because `unlimitds-setup/scripts/configure.ps1` does not exist.

- [ ] **Step 3: Add jailbreak, idempotency, and invalid-key cases**

Add tests that run the script twice with `-Mode jailbreak` and assert one provider section with model `deepseek-v4-pro_jailbreak`, then run with `UNLIMITDS_API_KEY_INPUT=bad-key` and assert a nonzero exit before configuration changes.

- [ ] **Step 4: Re-run to confirm all cases remain RED**

Run: `pwsh -NoProfile -File tests/configure.ps1.tests.ps1`

Expected: FAIL only because the production script is absent.

- [ ] **Step 5: Commit the failing tests**

```bash
git add tests/configure.ps1.tests.ps1
git commit -m "test: define PowerShell setup behavior"
```

### Task 2: Implement Windows Configuration

**Files:**
- Create: `unlimitds-setup/scripts/configure.ps1`
- Test: `tests/configure.ps1.tests.ps1`

- [ ] **Step 1: Implement input and validation helpers**

Add a validated `-Mode` parameter (`standard` or `jailbreak`), read the key from `UNLIMITDS_API_KEY_INPUT` or `Read-Host -AsSecureString`, require the `uds_` prefix and a reasonable minimum length, derive the mode model, and validate `GET https://unlimitds.chat/v1/models` unless the test-only skip flag is set together with test mode. Map 401, 429, and network failures to concise messages without printing the key.

- [ ] **Step 2: Implement isolated client detection**

Detect Codex by command or `.codex` directory and Claude by command or `.claude` directory. In test mode only, accept `UNLIMITDS_SETUP_HOME` and `UNLIMITDS_SETUP_CLIENTS`; outside test mode always use the actual user profile and detection results. Exit before mutation if neither client is found.

- [ ] **Step 3: Implement safe Codex TOML update**

Read the existing file, remove only top-level `model`/`model_provider` keys and the complete `[model_providers.unlimitds]` table, preserve all unrelated lines and sections, prepend the selected model/provider, append the canonical provider block, create one timestamped backup per invocation when the file exists, and replace through a temporary file.

- [ ] **Step 4: Persist Windows user variables**

Use `[Environment]::SetEnvironmentVariable(..., 'User')` for `UNLIMITDS_API_KEY`; for detected Claude also set `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, and `ANTHROPIC_MODEL`. Set the same variables in the current process so child processes can use them immediately, but tell users to restart the current Agent.

- [ ] **Step 5: Emit a stable redacted JSON result**

Return fields `ok`, `mode`, `model`, `configured_clients`, `api_check`, `backup_paths`, and `restart_required`. Never include the full key or authorization header.

- [ ] **Step 6: Run PowerShell tests to verify GREEN**

Run: `pwsh -NoProfile -File tests/configure.ps1.tests.ps1`

Expected: all cases PASS and exit code 0.

- [ ] **Step 7: Commit Windows implementation**

```bash
git add unlimitds-setup/scripts/configure.ps1 tests/configure.ps1.tests.ps1
git commit -m "feat: configure UnlimitDS on Windows"
```

### Task 3: Establish Bash Contract Tests

**Files:**
- Create: `tests/configure.sh.test.sh`

- [ ] **Step 1: Write failing standard and jailbreak tests**

Create a Bash test runner that uses `mktemp -d`, writes an existing `.codex/config.toml`, creates fake `codex` and `claude` executables on a temporary `PATH`, exports the same test-only variables as the PowerShell suite, and invokes:

```bash
bash "$repo_root/unlimitds-setup/scripts/configure.sh" standard
bash "$repo_root/unlimitds-setup/scripts/configure.sh" jailbreak
```

Assert preserved unrelated TOML, exact provider count, selected model, backup creation, mode-specific environment file values, startup-file source block idempotency, file mode `600`, and redacted output.

- [ ] **Step 2: Add invalid mode and invalid key cases**

Assert unsupported mode and malformed key both exit nonzero without writing `.codex/config.toml` or `.unlimitds/env`.

- [ ] **Step 3: Run tests to verify RED**

Run: `bash tests/configure.sh.test.sh`

Expected: FAIL because `unlimitds-setup/scripts/configure.sh` does not exist.

- [ ] **Step 4: Commit failing Bash tests**

```bash
git add tests/configure.sh.test.sh
git commit -m "test: define Unix setup behavior"
```

### Task 4: Implement macOS/Linux Configuration

**Files:**
- Create: `unlimitds-setup/scripts/configure.sh`
- Test: `tests/configure.sh.test.sh`

- [ ] **Step 1: Implement strict input and API validation**

Use `set -euo pipefail`, accept one mode argument, securely prompt with `read -rs` when `UNLIMITDS_API_KEY_INPUT` is absent, validate key shape, and use `curl --fail-with-body --silent --show-error` against `/v1/models` before mutation. Preserve HTTP status for actionable 401/429 errors and redact all output.

- [ ] **Step 2: Implement client detection and TOML update**

Mirror the PowerShell detection semantics. Use `awk` to remove only the two top-level keys and target provider table, preserve unrelated content, write the canonical block to a temporary file, back up existing configuration, and atomically move the result.

- [ ] **Step 3: Persist Unix environment safely**

Write shell-quoted exports to `~/.unlimitds/env`, set mode `600`, and add one marked source block to existing `.zshrc`, `.bashrc`, and `.profile`; if none exists, create the startup file appropriate for `$SHELL`. Do not duplicate the block on repeated runs.

- [ ] **Step 4: Emit matching redacted JSON**

Keep result fields and meanings aligned with the PowerShell implementation so the skill can summarize either platform uniformly.

- [ ] **Step 5: Run syntax and behavior tests to verify GREEN**

Run: `bash -n unlimitds-setup/scripts/configure.sh && bash tests/configure.sh.test.sh`

Expected: syntax check and all cases PASS.

- [ ] **Step 6: Commit Unix implementation**

```bash
git add unlimitds-setup/scripts/configure.sh tests/configure.sh.test.sh
git commit -m "feat: configure UnlimitDS on macOS and Linux"
```

### Task 5: Define and Validate the Agent Skill

**Files:**
- Create: `tests/repository.tests.ps1`
- Create: `unlimitds-setup/SKILL.md`
- Create: `unlimitds-setup/agents/openai.yaml`

- [ ] **Step 1: Write failing skill contract tests**

Test that frontmatter name equals `unlimitds-setup`, description starts with `Use when`, the body asks for exactly API key and mode, supports only standard/jailbreak, dispatches to the OS-specific script, requires confirmation before writing user configuration, prohibits echoing/logging the key, and references restart behavior. Test metadata contains a display name and default prompt.

- [ ] **Step 2: Run contract tests to verify RED**

Run: `pwsh -NoProfile -File tests/repository.tests.ps1`

Expected: FAIL because skill files are absent.

- [ ] **Step 3: Write minimal SKILL.md**

Use concise progressive disclosure: collect a missing key without repeating it, present `标准模式` and `破甲模式` with standard recommended, state the exact files/environment that will change, obtain authorization immediately before mutation, pass the key through a child-process environment variable, invoke `configure.ps1 -Mode <mode>` or `configure.sh <mode>`, parse JSON, and report configured clients plus restart requirement. If scripts are unavailable, stop instead of recreating configuration logic ad hoc.

- [ ] **Step 4: Add Codex UI metadata**

Create `agents/openai.yaml` with a novice-friendly Chinese display name, short description, and a default prompt that invokes `$unlimitds-setup` without embedding credentials.

- [ ] **Step 5: Run contract and official validation**

Run:

```powershell
pwsh -NoProfile -File tests/repository.tests.ps1
python "$env:USERPROFILE/.codex/skills/.system/skill-creator/scripts/quick_validate.py" unlimitds-setup
```

Expected: repository tests PASS and validator reports a valid skill.

- [ ] **Step 6: Commit the skill**

```bash
git add unlimitds-setup/SKILL.md unlimitds-setup/agents/openai.yaml tests/repository.tests.ps1
git commit -m "feat: add novice UnlimitDS setup skill"
```

### Task 6: Add Public Installation and Novice Documentation

**Files:**
- Create: `README.md`
- Create: `LICENSE`
- Create: `.gitignore`
- Modify: `tests/repository.tests.ps1`

- [ ] **Step 1: Extend tests for public-repository hygiene**

Assert README contains one copy-paste Agent prompt with the final GitHub URL placeholder isolated in one constant, Codex and Claude skill destinations, the two user choices, restart instruction, API-key creation link, and no real `uds_` secret. Scan tracked candidate files for `uds_[A-Za-z0-9_-]{20,}` and fail if found.

- [ ] **Step 2: Run tests to verify RED**

Run: `pwsh -NoProfile -File tests/repository.tests.ps1`

Expected: FAIL because README, license, and ignore file are absent.

- [ ] **Step 3: Write README for a novice**

Lead with a three-step Chinese guide: copy one prompt into Codex/Claude, paste the API key only when asked, choose standard or jailbreak and restart. Put technical details and manual installation below a collapsed or clearly secondary section. State that the project is unofficial and that users should treat API keys as passwords.

- [ ] **Step 4: Add license and ignores**

Use the MIT license and ignore `.env`, `.unlimitds/`, test temp output, editor files, and OS metadata without ignoring the skill itself.

- [ ] **Step 5: Run repository tests to verify GREEN**

Run: `pwsh -NoProfile -File tests/repository.tests.ps1`

Expected: all repository and secret-hygiene checks PASS.

- [ ] **Step 6: Commit public documentation**

```bash
git add README.md LICENSE .gitignore tests/repository.tests.ps1
git commit -m "docs: add one-click installation guide"
```

### Task 7: Verify Live API and End-to-End Installation

**Files:**
- Modify only if a test reveals a defect in files above.

- [ ] **Step 1: Run all local tests**

```powershell
pwsh -NoProfile -File tests/configure.ps1.tests.ps1
pwsh -NoProfile -File tests/repository.tests.ps1
bash -n unlimitds-setup/scripts/configure.sh
bash tests/configure.sh.test.sh
```

Expected: all tests PASS with no full API key in output.

- [ ] **Step 2: Validate both live API modes without touching real user config**

Run each script against a temporary home with `UNLIMITDS_SETUP_TEST_MODE=1` and explicit clients, but without `UNLIMITDS_SETUP_SKIP_API_CHECK`; provide the real key only through the process environment. Verify `/v1/models` succeeds, standard writes `deepseek-v4-pro`, jailbreak writes `deepseek-v4-pro_jailbreak`, and captured logs do not contain the key.

- [ ] **Step 3: Verify the Codex Responses endpoint**

Call `POST https://unlimitds.chat/v1/responses` with model `deepseek-v4-pro` and then `deepseek-v4-pro_jailbreak`, a harmless one-word response request, and confirm both return HTTP 200. This proves the protocol used by Codex works, not only Chat Completions.

- [ ] **Step 4: Install from a local repository clone into isolated skill homes**

Use the official Codex skill installer helper with `--repo` after publication; before publication, copy the folder into temporary `.codex/skills/unlimitds-setup` and `.claude/skills/unlimitds-setup`, then run `quick_validate.py` on each installed location.

- [ ] **Step 5: Check repository diff and secret hygiene**

Run:

```bash
git diff --check
git grep -nE 'uds_[A-Za-z0-9_-]{20,}' -- . ':!docs/superpowers/specs/*'
git status --short
```

Expected: no whitespace errors, no real keys, and only intended files.

### Task 8: Publish and Verify the Public GitHub Repository

**Files:**
- Modify: `README.md` only if the chosen repository URL differs.

- [ ] **Step 1: Confirm repository name availability**

Run: `gh repo view CTctikki/unlimitds-agent-skill`

Expected: not found before creation, or an explicitly verified empty repository owned by the authenticated account.

- [ ] **Step 2: Create and push the public repository**

Run:

```bash
gh repo create CTctikki/unlimitds-agent-skill --public --source . --remote origin --push --description "一键配置 Codex CLI 和 Claude Code 使用 UnlimitDS"
```

Expected: repository created, `origin` set, and current branch pushed.

- [ ] **Step 3: Normalize the default branch if needed**

Rename local branch to `main`, push it, and set it as GitHub default before deleting a remote `master` branch. Do not delete any branch until GitHub confirms `main` is the default.

- [ ] **Step 4: Test anonymous repository access**

Fetch `https://raw.githubusercontent.com/CTctikki/unlimitds-agent-skill/main/README.md` and `.../unlimitds-setup/SKILL.md` without credentials; expect HTTP 200.

- [ ] **Step 5: Test official Codex installation from GitHub**

Run the system `install-skill-from-github.py --repo CTctikki/unlimitds-agent-skill --path unlimitds-setup --dest <temporary-dir>`, then validate the installed folder and remove only the verified temporary destination.

- [ ] **Step 6: Run final verification and record release evidence**

Run all test suites again, `git status --short --branch`, `git log --oneline --decorate -8`, and `gh repo view --json nameWithOwner,url,visibility,defaultBranchRef`. Expected: all tests pass, clean branch tracks origin, visibility is PUBLIC, and default branch is `main`.
