#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-aliyun-hai}"
ALIYUN_REGION="${ALIYUN_REGION:-cn-beijing}"
ACR_REGISTRY="${ACR_REGISTRY:-registry.cn-beijing.aliyuncs.com}"
ACR_REPOSITORY="${ACR_REPOSITORY:-open-webui}"
ACR_INSTANCE_ID="${ACR_INSTANCE_ID:-}"
APP_PORT="${APP_PORT:-3000}"
TF_LOCK_INSTANCE="${TF_LOCK_INSTANCE:-open-webui-hai-tf-lock}"
TF_LOCK_TABLE="${TF_LOCK_TABLE:-terraform_locks}"

required_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    return 1
  fi
}

prompt_secret() {
  local name="$1"
  local value="${!name:-}"

  if [ -n "$value" ]; then
    printf '%s' "$value"
    return 0
  fi

  printf 'Enter %s: ' "$name" >&2
  IFS= read -rs value
  printf '\n' >&2
  printf '%s' "$value"
}

prompt_value() {
  local name="$1"
  local default_value="${2:-}"
  local value="${!name:-}"

  if [ -n "$value" ]; then
    printf '%s' "$value"
    return 0
  fi

  if [ -n "$default_value" ]; then
    printf 'Enter %s [%s]: ' "$name" "$default_value" >&2
  else
    printf 'Enter %s: ' "$name" >&2
  fi
  IFS= read -r value
  printf '%s' "${value:-$default_value}"
}

prompt_yes_no() {
  local name="$1"
  local default_value="${2:-n}"
  local value="${!name:-}"

  if [ -z "$value" ]; then
    printf 'Configure ACR_USERNAME and ACR_PASSWORD now? [y/N]: ' >&2
    IFS= read -r value
  fi

  value="${value:-$default_value}"
  case "$value" in
    y|Y|yes|YES|true|TRUE|1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

set_var() {
  local name="$1"
  local value="$2"
  gh variable set "$name" --env "$ENVIRONMENT_NAME" --body "$value" >/dev/null
  echo "Set GitHub environment variable: $name"
}

set_secret() {
  local name="$1"
  local value="$2"
  gh secret set "$name" --env "$ENVIRONMENT_NAME" --body "$value" >/dev/null
  echo "Set GitHub environment secret: $name"
}

main() {
  required_command gh
  gh auth status >/dev/null

  local repo
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
  gh api -X PUT "repos/${repo}/environments/${ENVIRONMENT_NAME}" >/dev/null

  local acr_namespace
  local tf_state_bucket
  acr_namespace="$(prompt_value ACR_NAMESPACE "")"
  tf_state_bucket="$(prompt_value TF_STATE_BUCKET "")"

  if [ -z "$acr_namespace" ] || [ -z "$tf_state_bucket" ]; then
    echo "ACR_NAMESPACE and TF_STATE_BUCKET are required." >&2
    return 1
  fi

  set_var ALIYUN_REGION "$ALIYUN_REGION"
  set_var ACR_REGISTRY "$ACR_REGISTRY"
  set_var ACR_NAMESPACE "$acr_namespace"
  set_var ACR_REPOSITORY "$ACR_REPOSITORY"
  if [ -n "$ACR_INSTANCE_ID" ]; then
    set_var ACR_INSTANCE_ID "$ACR_INSTANCE_ID"
  fi
  set_var APP_PORT "$APP_PORT"
  set_var TF_STATE_BUCKET "$tf_state_bucket"
  set_var TF_LOCK_INSTANCE "$TF_LOCK_INSTANCE"
  set_var TF_LOCK_TABLE "$TF_LOCK_TABLE"

  set_secret ALIYUN_ACCESS_KEY_ID "$(prompt_secret ALIYUN_ACCESS_KEY_ID)"
  set_secret ALIYUN_ACCESS_KEY_SECRET "$(prompt_secret ALIYUN_ACCESS_KEY_SECRET)"

  if [ -n "${ACR_USERNAME:-}" ] || [ -n "${ACR_PASSWORD:-}" ] || prompt_yes_no CONFIGURE_ACR_CREDENTIALS n; then
    set_secret ACR_USERNAME "$(prompt_secret ACR_USERNAME)"
    set_secret ACR_PASSWORD "$(prompt_secret ACR_PASSWORD)"
  else
    echo "Skipping ACR_USERNAME/ACR_PASSWORD. Workflows will try ACR temporary credentials from Aliyun AK/SK."
  fi

  if [ -f .env.hai ]; then
    set_secret OPEN_WEBUI_ENV_HAI_B64 "$(base64 < .env.hai | tr -d '\n')"
  else
    set_secret OPEN_WEBUI_ENV_HAI_B64 "$(prompt_secret OPEN_WEBUI_ENV_HAI_B64)"
  fi

  echo "GitHub environment ${ENVIRONMENT_NAME} is configured for ${repo}."
}

main "$@"
