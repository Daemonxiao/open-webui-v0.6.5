#!/usr/bin/env bash
set -euo pipefail

required_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required environment variable: $name" >&2
    return 1
  fi
}

mask_value() {
  local value="$1"
  if [ -n "${GITHUB_ACTIONS:-}" ] && [ -n "$value" ]; then
    echo "::add-mask::$value"
  fi
}

resolve_acr_credentials() {
  if [ -n "${ACR_USERNAME:-}" ] && [ -n "${ACR_PASSWORD:-}" ]; then
    ACR_LOGIN_USERNAME="$ACR_USERNAME"
    ACR_LOGIN_PASSWORD="$ACR_PASSWORD"
    return 0
  fi

  required_env ALIYUN_REGION

  local response
  local args
  args=(cr GetAuthorizationToken --RegionId "$ALIYUN_REGION" --endpoint "cr.${ALIYUN_REGION}.aliyuncs.com")
  if [ -n "${ACR_INSTANCE_ID:-}" ]; then
    args+=(--InstanceId "$ACR_INSTANCE_ID")
  fi

  if ! response="$(aliyun "${args[@]}")"; then
    echo "Could not get an ACR temporary token. Set ACR_USERNAME and ACR_PASSWORD if this Personal Edition instance does not support temporary tokens." >&2
    return 1
  fi

  ACR_LOGIN_USERNAME="$(jq -r '.TempUsername // .tempUsername // empty' <<< "$response")"
  ACR_LOGIN_PASSWORD="$(jq -r '.AuthorizationToken // .authorizationToken // empty' <<< "$response")"

  if [ -z "$ACR_LOGIN_USERNAME" ] || [ -z "$ACR_LOGIN_PASSWORD" ]; then
    echo "ACR token response did not contain TempUsername and AuthorizationToken." >&2
    return 1
  fi
}

main() {
  required_env ACR_REGISTRY
  resolve_acr_credentials
  mask_value "$ACR_LOGIN_USERNAME"
  mask_value "$ACR_LOGIN_PASSWORD"
  printf '%s' "$ACR_LOGIN_PASSWORD" | docker login "$ACR_REGISTRY" --username "$ACR_LOGIN_USERNAME" --password-stdin
}

main "$@"
