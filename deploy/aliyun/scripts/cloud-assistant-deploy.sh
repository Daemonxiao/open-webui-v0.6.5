#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

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

  mask_value "$ACR_LOGIN_USERNAME"
  mask_value "$ACR_LOGIN_PASSWORD"
}

resolve_acr_pull_registry() {
  if [ -n "${ACR_PULL_REGISTRY:-}" ]; then
    return 0
  fi

  ACR_PULL_REGISTRY="$ACR_REGISTRY"

  if [[ "$ACR_REGISTRY" =~ ^(crpi-[^.]+)\.(cn-[^.]+)\.personal\.cr\.aliyuncs\.com$ ]]; then
    ACR_PULL_REGISTRY="${BASH_REMATCH[1]}-vpc.${BASH_REMATCH[2]}.personal.cr.aliyuncs.com"
  elif [[ "$ACR_REGISTRY" =~ ^registry\.(cn-[^.]+)\.aliyuncs\.com$ ]]; then
    ACR_PULL_REGISTRY="registry-vpc.${BASH_REMATCH[1]}.aliyuncs.com"
  fi
}

resolve_open_webui_pull_image() {
  resolve_acr_pull_registry

  if [ "$ACR_PULL_REGISTRY" != "$ACR_REGISTRY" ] && [[ "$OPEN_WEBUI_IMAGE" == "$ACR_REGISTRY/"* ]]; then
    OPEN_WEBUI_PULL_IMAGE="${ACR_PULL_REGISTRY}/${OPEN_WEBUI_IMAGE#"$ACR_REGISTRY/"}"
  else
    OPEN_WEBUI_PULL_IMAGE="$OPEN_WEBUI_IMAGE"
  fi
}

file_to_base64() {
  base64 < "$1" | tr -d '\n'
}

send_file() {
  local source_file="$1"
  local remote_name="$2"
  local remote_dir="$3"
  local mode="$4"
  local content
  local response
  local invoke_id

  content="$(file_to_base64 "$source_file")"
  response="$(aliyun ecs SendFile \
    --RegionId "$ALIYUN_REGION" \
    --InstanceId.1 "$ECS_INSTANCE_ID" \
    --Name "$remote_name" \
    --TargetDir "$remote_dir" \
    --ContentType Base64 \
    --Content "$content" \
    --FileMode "$mode" \
    --Overwrite true)"

  invoke_id="$(jq -r '.InvokeId // .invokeId // empty' <<< "$response")"
  echo "Sent $remote_dir/$remote_name${invoke_id:+ (invoke $invoke_id)}"
}

decode_maybe_base64() {
  local value="$1"
  local decoded_file="$TMP_DIR/command-output.txt"

  if [ -z "$value" ] || [ "$value" = "null" ]; then
    return 0
  fi

  if printf '%s' "$value" | base64 -d > "$decoded_file" 2>/dev/null; then
    cat "$decoded_file"
  else
    printf '%s\n' "$value"
  fi
}

wait_for_command() {
  local invoke_id="$1"
  local attempts="${2:-240}"
  local result
  local status
  local exit_code
  local output

  for _ in $(seq 1 "$attempts"); do
    result="$(aliyun ecs DescribeInvocationResults \
      --RegionId "$ALIYUN_REGION" \
      --InvokeId "$invoke_id")"

    status="$(jq -r 'first(.. | objects | select(has("InvocationStatus")) | .InvocationStatus) // empty' <<< "$result")"
    exit_code="$(jq -r 'first(.. | objects | select(has("ExitCode")) | .ExitCode) // empty' <<< "$result")"
    output="$(jq -r 'first(.. | objects | select(has("Output")) | .Output) // empty' <<< "$result")"

    case "$status" in
      Success)
        decode_maybe_base64 "$output"
        if [ -z "$exit_code" ] || [ "$exit_code" = "0" ]; then
          return 0
        fi
        echo "Cloud Assistant command exited with code $exit_code." >&2
        return "$exit_code"
        ;;
      Failed|Stopped|Timeout)
        decode_maybe_base64 "$output"
        echo "Cloud Assistant command failed with status $status." >&2
        return 1
        ;;
      *)
        sleep 10
        ;;
    esac
  done

  echo "Timed out waiting for Cloud Assistant invocation $invoke_id after $((attempts * 10)) seconds." >&2
  return 1
}

main() {
  required_env ALIYUN_REGION
  required_env ECS_INSTANCE_ID
  required_env OPEN_WEBUI_IMAGE
  required_env OPEN_WEBUI_ENV_HAI_B64
  required_env DATABASE_URL
  required_env PGVECTOR_DB_URL

  local app_port="${APP_PORT:-3000}"
  local new_api_port="${NEW_API_PORT:-3001}"
  local new_api_openwebui_base_url="${NEW_API_OPENWEBUI_BASE_URL:-http://host.containers.internal:${new_api_port}/v1}"
  local compose_env="$TMP_DIR/compose.env"
  local env_hai="$TMP_DIR/.env.hai"
  local env_open_webui="$TMP_DIR/.env.open-webui"
  local docker_config="$TMP_DIR/config.json"
  local prepare_script="$TMP_DIR/prepare.sh"
  local docker_auth
  local run_response
  local invoke_id

  required_env ACR_REGISTRY
  resolve_open_webui_pull_image

  printf '%s' "$OPEN_WEBUI_ENV_HAI_B64" | base64 -d > "$env_hai"
  {
    printf 'OPEN_WEBUI_IMAGE=%s\n' "$OPEN_WEBUI_PULL_IMAGE"
    printf 'OPEN_WEBUI_PORT=%s\n' "$app_port"
    printf 'DATABASE_URL=%s\n' "$DATABASE_URL"
    printf 'PGVECTOR_DB_URL=%s\n' "$PGVECTOR_DB_URL"
    printf 'DEPLOY_TARGET=open-webui\n'
    printf 'OFFLINE_MODE=%s\n' "${OFFLINE_MODE:-true}"
    printf 'RAG_EMBEDDING_MODEL_AUTO_UPDATE=%s\n' "${RAG_EMBEDDING_MODEL_AUTO_UPDATE:-false}"
    printf 'REDIS_URL=%s\n' "${REDIS_URL:-}"
    printf 'WEBSOCKET_MANAGER=%s\n' "${WEBSOCKET_MANAGER:-}"
    printf 'WEBSOCKET_REDIS_URL=%s\n' "${WEBSOCKET_REDIS_URL:-${REDIS_URL:-}}"
  } > "$compose_env"
  if [ -n "${NEW_API_OPENWEBUI_TOKEN:-}" ]; then
    {
      printf 'ENABLE_OPENAI_API=True\n'
      printf 'OPENAI_API_BASE_URL=%s\n' "$new_api_openwebui_base_url"
      printf 'OPENAI_API_BASE_URLS=%s\n' "$new_api_openwebui_base_url"
      printf 'OPENAI_API_KEY=%s\n' "$NEW_API_OPENWEBUI_TOKEN"
      printf 'OPENAI_API_KEYS=%s\n' "$NEW_API_OPENWEBUI_TOKEN"
    } > "$env_open_webui"
  else
    : > "$env_open_webui"
  fi
  cat > "$prepare_script" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p /opt/open-webui /root/.docker
chmod 700 /opt/open-webui /root/.docker
SCRIPT

  resolve_acr_credentials
  docker_auth="$(printf '%s:%s' "$ACR_LOGIN_USERNAME" "$ACR_LOGIN_PASSWORD" | base64 | tr -d '\n')"
  if [ "$ACR_PULL_REGISTRY" != "$ACR_REGISTRY" ]; then
    jq -n \
      --arg push_registry "$ACR_REGISTRY" \
      --arg pull_registry "$ACR_PULL_REGISTRY" \
      --arg auth "$docker_auth" \
      '{auths: {($push_registry): {auth: $auth}, ($pull_registry): {auth: $auth}}}' > "$docker_config"
  else
    jq -n --arg registry "$ACR_REGISTRY" --arg auth "$docker_auth" \
      '{auths: {($registry): {auth: $auth}}}' > "$docker_config"
  fi

  run_response="$(aliyun ecs RunCommand \
    --RegionId "$ALIYUN_REGION" \
    --InstanceId.1 "$ECS_INSTANCE_ID" \
    --Type RunShellScript \
    --CommandContent "$(file_to_base64 "$prepare_script")" \
    --ContentEncoding Base64 \
    --Name "open-webui-prepare-${GITHUB_RUN_ID:-manual}" \
    --Timeout 300 \
    --WorkingDir "/root")"

  invoke_id="$(jq -r '.InvokeId // .invokeId // empty' <<< "$run_response")"
  if [ -z "$invoke_id" ]; then
    echo "RunCommand did not return InvokeId for prepare step: $run_response" >&2
    return 1
  fi
  wait_for_command "$invoke_id" 60

  send_file "$REPO_ROOT/deploy/aliyun/docker-compose.open-webui.yml" "docker-compose.open-webui.yml" "/opt/open-webui" "0600"
  send_file "$compose_env" ".env" "/opt/open-webui" "0600"
  send_file "$env_hai" ".env.hai" "/opt/open-webui" "0600"
  send_file "$env_open_webui" ".env.open-webui" "/opt/open-webui" "0600"
  send_file "$docker_config" "config.json" "/root/.docker" "0600"

  run_response="$(aliyun ecs RunCommand \
    --RegionId "$ALIYUN_REGION" \
    --InstanceId.1 "$ECS_INSTANCE_ID" \
    --Type RunShellScript \
    --CommandContent "$(file_to_base64 "$REPO_ROOT/deploy/aliyun/scripts/ecs-deploy.sh")" \
    --ContentEncoding Base64 \
    --Name "open-webui-deploy-${GITHUB_RUN_ID:-manual}" \
    --Timeout 1800 \
    --WorkingDir "/opt/open-webui")"

  invoke_id="$(jq -r '.InvokeId // .invokeId // empty' <<< "$run_response")"
  if [ -z "$invoke_id" ]; then
    echo "RunCommand did not return InvokeId: $run_response" >&2
    return 1
  fi

  wait_for_command "$invoke_id" 240
}

main "$@"
