#!/usr/bin/env bash
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script_path="$repo_root/unlimitds-setup/scripts/configure.sh"
test_key='uds_test_key_12345678901234567890'
failures=0

fail() {
  printf 'FAIL %s: %s\n' "$1" "$2"
  failures=$((failures + 1))
}

pass() {
  printf 'PASS %s\n' "$1"
}

assert_contains() {
  local haystack="$1" needle="$2" message="$3"
  [[ "$haystack" == *"$needle"* ]] || return 1
}

new_test_home() {
  local home_path
  home_path="$(mktemp -d)"
  mkdir -p "$home_path/.codex" "$home_path/bin"
  cat > "$home_path/.codex/config.toml" <<'EOF'
model = "old-model"
model_provider = "openai"
approval_policy = "never"

[features]
multi_agent = true

[model_providers.other]
name = "Other"
base_url = "https://example.com/v1"

[model_providers.unlimitds]
name = "Old UnlimitDS"
base_url = "https://old.invalid/v1"

[projects."/tmp/demo"]
trust_level = "trusted"
EOF
  printf '#!/usr/bin/env bash\nexit 0\n' > "$home_path/bin/codex"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$home_path/bin/claude"
  chmod +x "$home_path/bin/codex" "$home_path/bin/claude"
  printf '%s\n' "$home_path"
}

run_setup() {
  local home_path="$1" mode="$2" api_key="${3:-$test_key}"
  HOME="$home_path" \
  SHELL='/bin/bash' \
  PATH="$home_path/bin:$PATH" \
  UNLIMITDS_SETUP_TEST_MODE=1 \
  UNLIMITDS_SETUP_HOME="$home_path" \
  UNLIMITDS_SETUP_CLIENTS=both \
  UNLIMITDS_SETUP_SKIP_API_CHECK=1 \
  UNLIMITDS_API_KEY_INPUT="$api_key" \
    bash "$script_path" "$mode" 2>&1
}

test_standard_mode() {
  local name='standard mode preserves configuration and writes environment'
  local home_path output status content provider_count source_count permissions
  home_path="$(new_test_home)"
  output="$(run_setup "$home_path" standard)"
  status=$?
  if [[ $status -ne 0 ]]; then
    fail "$name" "$output"
    rm -rf -- "$home_path"
    return
  fi

  content="$(cat "$home_path/.codex/config.toml")"
  provider_count="$(grep -c '^\[model_providers\.unlimitds\]$' "$home_path/.codex/config.toml")"
  source_count="$(grep -c '^# >>> unlimitds setup >>>$' "$home_path/.bashrc")"
  permissions="$(stat -c '%a' "$home_path/.unlimitds/env")"

  if ! assert_contains "$content" 'model = "deepseek-v4-pro"' ''; then fail "$name" 'standard model missing';
  elif [[ "$provider_count" != '1' ]]; then fail "$name" 'provider table count is wrong';
  elif ! assert_contains "$content" 'approval_policy = "never"' ''; then fail "$name" 'unrelated setting removed';
  elif ! assert_contains "$content" '[model_providers.other]' ''; then fail "$name" 'other provider removed';
  elif ! assert_contains "$content" '[projects."/tmp/demo"]' ''; then fail "$name" 'project setting removed';
  elif [[ "$(find "$home_path/.codex" -maxdepth 1 -name 'config.toml.unlimitds-backup-*' | wc -l | tr -d ' ')" != '1' ]]; then fail "$name" 'backup missing';
  elif ! grep -Fq "export ANTHROPIC_MODEL='deepseek-v4-pro'" "$home_path/.unlimitds/env"; then fail "$name" 'Claude model missing';
  elif [[ "$source_count" != '1' ]]; then fail "$name" 'startup source block count is wrong';
  elif [[ "$permissions" != '600' ]]; then fail "$name" "environment file mode is $permissions";
  elif [[ "$output" == *"$test_key"* ]]; then fail "$name" 'output leaked API key';
  else pass "$name"; fi
  rm -rf -- "$home_path"
}

test_jailbreak_idempotency() {
  local name='jailbreak mode is idempotent'
  local home_path first second content provider_count source_count
  home_path="$(new_test_home)"
  first="$(run_setup "$home_path" jailbreak)" || { fail "$name" "$first"; rm -rf -- "$home_path"; return; }
  second="$(run_setup "$home_path" jailbreak)" || { fail "$name" "$second"; rm -rf -- "$home_path"; return; }
  content="$(cat "$home_path/.codex/config.toml")"
  provider_count="$(grep -c '^\[model_providers\.unlimitds\]$' "$home_path/.codex/config.toml")"
  source_count="$(grep -c '^# >>> unlimitds setup >>>$' "$home_path/.bashrc")"
  if [[ "$(grep -c '^model = "deepseek-v4-pro_jailbreak"$' "$home_path/.codex/config.toml")" != '1' ]]; then fail "$name" 'jailbreak model count is wrong';
  elif [[ "$provider_count" != '1' ]]; then fail "$name" 'provider table duplicated';
  elif [[ "$source_count" != '1' ]]; then fail "$name" 'startup source block duplicated';
  elif ! grep -Fq "export ANTHROPIC_MODEL='deepseek-v4-pro_jailbreak'" "$home_path/.unlimitds/env"; then fail "$name" 'Claude jailbreak model missing';
  elif [[ "$second" == *"$test_key"* ]]; then fail "$name" 'output leaked API key';
  else pass "$name"; fi
  rm -rf -- "$home_path"
}

test_invalid_input() {
  local name='invalid mode and key stop before mutation'
  local home_path before output status after
  home_path="$(new_test_home)"
  before="$(cat "$home_path/.codex/config.toml")"

  output="$(run_setup "$home_path" unknown)"
  status=$?
  after="$(cat "$home_path/.codex/config.toml")"
  if [[ $status -eq 0 ]]; then fail "$name" 'invalid mode succeeded'; rm -rf -- "$home_path"; return; fi
  if [[ "$before" != "$after" ]]; then fail "$name" 'invalid mode changed configuration'; rm -rf -- "$home_path"; return; fi

  output="$(run_setup "$home_path" standard 'bad-key')"
  status=$?
  after="$(cat "$home_path/.codex/config.toml")"
  if [[ $status -eq 0 ]]; then fail "$name" 'invalid key succeeded';
  elif [[ "$before" != "$after" ]]; then fail "$name" 'invalid key changed configuration';
  elif [[ -e "$home_path/.unlimitds/env" ]]; then fail "$name" 'invalid key wrote environment file';
  elif [[ "$output" == *'bad-key'* ]]; then fail "$name" 'error leaked invalid key';
  else pass "$name"; fi
  rm -rf -- "$home_path"
}

test_standard_mode
test_jailbreak_idempotency
test_invalid_input

if [[ $failures -ne 0 ]]; then
  printf '%s Bash setup test(s) failed.\n' "$failures" >&2
  exit 1
fi

printf 'All Bash setup tests passed.\n'
