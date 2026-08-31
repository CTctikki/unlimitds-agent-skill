#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'UnlimitDS 配置失败：%s\n' "$1" >&2
  exit 1
}

json_escape() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  printf '%s' "$value"
}

mode="${1:-}"
case "$mode" in
  standard) model='deepseek-v4-pro' ;;
  jailbreak) model='deepseek-v4-pro_jailbreak' ;;
  *) die '模式必须是 standard 或 jailbreak。' ;;
esac

test_mode=false
if [[ "${UNLIMITDS_SETUP_TEST_MODE:-}" == '1' ]]; then
  test_mode=true
fi

if [[ -n "${UNLIMITDS_API_KEY_INPUT:-}" ]]; then
  api_key="${UNLIMITDS_API_KEY_INPUT}"
else
  printf '请输入 UnlimitDS API Key：' >&2
  IFS= read -rs api_key
  printf '\n' >&2
fi

if [[ ! "$api_key" =~ ^uds_[A-Za-z0-9_-]{20,}$ ]]; then
  die 'API Key 格式不正确，应以 uds_ 开头。'
fi

home_path="$HOME"
if $test_mode && [[ -n "${UNLIMITDS_SETUP_HOME:-}" ]]; then
  home_path="$UNLIMITDS_SETUP_HOME"
fi

api_check='passed'
if $test_mode && [[ "${UNLIMITDS_SETUP_SKIP_API_CHECK:-}" == '1' ]]; then
  api_check='skipped-test-only'
else
  response_file="$(mktemp)"
  trap 'rm -f -- "${response_file:-}"' EXIT
  set +e
  http_code="$(curl --silent --show-error --output "$response_file" --write-out '%{http_code}' \
    --header "Authorization: Bearer $api_key" \
    --connect-timeout 15 --max-time 30 \
    'https://unlimitds.chat/v1/models')"
  curl_status=$?
  set -e
  if [[ $curl_status -ne 0 ]]; then
    die '无法连接 UnlimitDS API，请检查网络后重试。'
  fi
  case "$http_code" in
    200) ;;
    401) die 'API Key 无效或已失效（HTTP 401）。' ;;
    429) die '账户额度已用完或受到频率限制（HTTP 429）。' ;;
    *) die "UnlimitDS API 返回异常状态（HTTP $http_code）。" ;;
  esac
  rm -f -- "$response_file"
  trap - EXIT
fi

clients=()
if $test_mode && [[ -n "${UNLIMITDS_SETUP_CLIENTS:-}" ]]; then
  client_override="$(printf '%s' "$UNLIMITDS_SETUP_CLIENTS" | tr '[:upper:]' '[:lower:]')"
  case "$client_override" in
    both) clients=('codex' 'claude') ;;
    codex) clients=('codex') ;;
    claude) clients=('claude') ;;
    none) clients=() ;;
    *) die '测试客户端覆盖值无效。' ;;
  esac
else
  if command -v codex >/dev/null 2>&1 || [[ -d "$home_path/.codex" ]]; then
    clients+=('codex')
  fi
  if command -v claude >/dev/null 2>&1 || [[ -d "$home_path/.claude" ]]; then
    clients+=('claude')
  fi
fi

if [[ ${#clients[@]} -eq 0 ]]; then
  die '未检测到 Codex CLI 或 Claude Code，请先安装至少一个客户端。'
fi

has_client() {
  local wanted="$1" client
  for client in "${clients[@]}"; do
    [[ "$client" == "$wanted" ]] && return 0
  done
  return 1
}

backup_paths=()
if has_client codex; then
  codex_dir="$home_path/.codex"
  config_path="$codex_dir/config.toml"
  mkdir -p "$codex_dir"
  if [[ -f "$config_path" ]]; then
    timestamp="$(date -u '+%Y%m%d-%H%M%S')-$$-$RANDOM"
    backup_path="$config_path.unlimitds-backup-$timestamp"
    cp -- "$config_path" "$backup_path"
    backup_paths+=("$backup_path")
  fi

  preserved_file="$(mktemp "$codex_dir/.unlimitds-preserved.XXXXXX")"
  output_file="$(mktemp "$codex_dir/.unlimitds-config.XXXXXX")"
  trap 'rm -f -- "${preserved_file:-}" "${output_file:-}"' EXIT
  if [[ -f "$config_path" ]]; then
    awk '
      BEGIN { top_level = 1; skip_provider = 0 }
      /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
        if ($0 ~ /^[[:space:]]*\[model_providers\.unlimitds\][[:space:]]*$/) {
          skip_provider = 1
          top_level = 0
          next
        }
        skip_provider = 0
        top_level = 0
      }
      skip_provider { next }
      top_level && /^[[:space:]]*(model|model_provider)[[:space:]]*=/ { next }
      { print }
    ' "$config_path" > "$preserved_file"
  else
    : > "$preserved_file"
  fi

  {
    printf 'model = "%s"\n' "$model"
    printf 'model_provider = "unlimitds"\n'
    if grep -q '[^[:space:]]' "$preserved_file"; then
      printf '\n'
      cat "$preserved_file"
    fi
    printf '\n[model_providers.unlimitds]\n'
    printf 'name = "UnlimitDS"\n'
    printf 'base_url = "https://unlimitds.chat/v1"\n'
    printf 'env_key = "UNLIMITDS_API_KEY"\n'
    printf 'wire_api = "responses"\n'
  } > "$output_file"
  mv -f -- "$output_file" "$config_path"
  rm -f -- "$preserved_file"
  trap - EXIT
fi

state_dir="$home_path/.unlimitds"
env_file="$state_dir/env"
mkdir -p "$state_dir"
umask 077
{
  printf "export UNLIMITDS_API_KEY='%s'\n" "$api_key"
  if has_client claude; then
    printf "export ANTHROPIC_BASE_URL='https://unlimitds.chat'\n"
    printf "export ANTHROPIC_AUTH_TOKEN='%s'\n" "$api_key"
    printf "export ANTHROPIC_MODEL='%s'\n" "$model"
  fi
} > "$env_file"
chmod 600 "$env_file"

source_path="$(printf '%q' "$env_file")"
start_marker='# >>> unlimitds setup >>>'
end_marker='# <<< unlimitds setup <<<'
startup_files=()
for candidate in "$home_path/.zshrc" "$home_path/.bashrc" "$home_path/.profile"; do
  [[ -f "$candidate" ]] && startup_files+=("$candidate")
done
if [[ ${#startup_files[@]} -eq 0 ]]; then
  case "${SHELL:-}" in
    */zsh) startup_files+=("$home_path/.zshrc") ;;
    *) startup_files+=("$home_path/.bashrc") ;;
  esac
fi

for startup_file in "${startup_files[@]}"; do
  touch "$startup_file"
  if ! grep -Fq "$start_marker" "$startup_file"; then
    {
      printf '\n%s\n' "$start_marker"
      printf '[ -f %s ] && . %s\n' "$source_path" "$source_path"
      printf '%s\n' "$end_marker"
    } >> "$startup_file"
  fi
done

client_json=''
for client in "${clients[@]}"; do
  [[ -n "$client_json" ]] && client_json+=','
  client_json+="\"$(json_escape "$client")\""
done

backup_json=''
for backup_path in "${backup_paths[@]}"; do
  [[ -n "$backup_json" ]] && backup_json+=','
  backup_json+="\"$(json_escape "$backup_path")\""
done

printf '{"ok":true,"mode":"%s","model":"%s","configured_clients":[%s],"api_check":"%s","backup_paths":[%s],"restart_required":true}\n' \
  "$(json_escape "$mode")" "$(json_escape "$model")" "$client_json" "$(json_escape "$api_check")" "$backup_json"
