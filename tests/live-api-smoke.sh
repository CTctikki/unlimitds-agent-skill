#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

printf 'UnlimitDS API Key: ' >&2
IFS= read -rs api_key
printf '\n' >&2
if [[ ! "$api_key" =~ ^uds_[A-Za-z0-9_-]{20,}$ ]]; then
  printf 'Invalid API key format.\n' >&2
  exit 1
fi

cleanup_paths=()
cleanup() {
  local path
  for path in "${cleanup_paths[@]}"; do
    if [[ -n "$path" && "$path" == /tmp/* ]]; then
      rm -rf -- "$path"
    fi
  done
}
trap cleanup EXIT

for mode in standard jailbreak; do
  home_path="$(mktemp -d)"
  cleanup_paths+=("$home_path")
  mkdir -p "$home_path/.codex"
  printf '%s\n' 'approval_policy = "never"' > "$home_path/.codex/config.toml"

  output="$(
    HOME="$home_path" \
    SHELL=/bin/bash \
    UNLIMITDS_SETUP_TEST_MODE=1 \
    UNLIMITDS_SETUP_HOME="$home_path" \
    UNLIMITDS_SETUP_CLIENTS=both \
    UNLIMITDS_API_KEY_INPUT="$api_key" \
      bash "$repo_root/unlimitds-setup/scripts/configure.sh" "$mode"
  )"

  expected_model='deepseek-v4-pro'
  [[ "$mode" == 'jailbreak' ]] && expected_model='deepseek-v4-pro_jailbreak'
  grep -Fq "model = \"$expected_model\"" "$home_path/.codex/config.toml"
  [[ "$output" == *'"api_check":"passed"'* ]]
  [[ "$output" != *"$api_key"* ]]
  printf 'PASS bash setup %s (%s)\n' "$mode" "$expected_model"
done

for model in deepseek-v4-pro deepseek-v4-pro_jailbreak; do
  response_file="$(mktemp)"
  cleanup_paths+=("$response_file")
  payload="{\"model\":\"$model\",\"input\":\"Reply with exactly OK\",\"max_output_tokens\":16}"
  http_code="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
    --header "Authorization: Bearer $api_key" \
    --header 'Content-Type: application/json' \
    --data "$payload" \
    --connect-timeout 15 --max-time 90 \
    'https://unlimitds.chat/v1/responses')"
  if [[ "$http_code" != '200' ]]; then
    printf 'Responses API failed for %s (HTTP %s).\n' "$model" "$http_code" >&2
    exit 1
  fi
  grep -Fq '"object"' "$response_file"
  printf 'PASS responses %s (HTTP %s)\n' "$model" "$http_code"
done

printf 'All live API smoke tests passed.\n'
