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
    echo "Could not get an ACR temporary token. Set ACR_USERNAME and ACR_PASSWORD if this ACR instance does not support temporary tokens." >&2
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

resolve_new_api_pull_image() {
  resolve_acr_pull_registry

  if [ "$ACR_PULL_REGISTRY" != "$ACR_REGISTRY" ] && [[ "$NEW_API_IMAGE" == "$ACR_REGISTRY/"* ]]; then
    NEW_API_PULL_IMAGE="${ACR_PULL_REGISTRY}/${NEW_API_IMAGE#"$ACR_REGISTRY/"}"
  else
    NEW_API_PULL_IMAGE="$NEW_API_IMAGE"
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
  local result
  local status
  local exit_code
  local output

  for _ in $(seq 1 120); do
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

  echo "Timed out waiting for Cloud Assistant invocation $invoke_id." >&2
  return 1
}

main() {
  required_env ALIYUN_REGION
  required_env ECS_INSTANCE_ID
  required_env ACR_REGISTRY
  required_env NEW_API_IMAGE
  required_env NEW_API_DATABASE_URL
  required_env NEW_API_SESSION_SECRET
  required_env NEW_API_CRYPTO_SECRET

  local new_api_port="${NEW_API_PORT:-3001}"
  local compose_env="$TMP_DIR/compose.env"
  local env_new_api="$TMP_DIR/.env.new-api"
  local docker_config="$TMP_DIR/config.json"
  local prepare_script="$TMP_DIR/prepare.sh"
  local docker_auth
  local run_response
  local invoke_id

  mask_value "$NEW_API_DATABASE_URL"
  mask_value "$NEW_API_SESSION_SECRET"
  mask_value "$NEW_API_CRYPTO_SECRET"
  resolve_new_api_pull_image

  {
    printf 'NEW_API_IMAGE=%s\n' "$NEW_API_PULL_IMAGE"
    printf 'NEW_API_PORT=%s\n' "$new_api_port"
    printf 'DEPLOY_TARGET=new-api\n'
  } > "$compose_env"
  {
    printf 'PORT=3000\n'
    printf 'TZ=Asia/Shanghai\n'
    printf 'SQL_DSN=%s\n' "$NEW_API_DATABASE_URL"
    printf 'SESSION_SECRET=%s\n' "$NEW_API_SESSION_SECRET"
    printf 'CRYPTO_SECRET=%s\n' "$NEW_API_CRYPTO_SECRET"
    printf 'MEMORY_CACHE_ENABLED=true\n'
    printf 'BATCH_UPDATE_ENABLED=true\n'
  } > "$env_new_api"

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

  cat > "$prepare_script" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p /opt/open-webui /root/.docker
chmod 700 /opt/open-webui /root/.docker
SCRIPT

  run_response="$(aliyun ecs RunCommand \
    --RegionId "$ALIYUN_REGION" \
    --InstanceId.1 "$ECS_INSTANCE_ID" \
    --Type RunShellScript \
    --CommandContent "$(file_to_base64 "$prepare_script")" \
    --ContentEncoding Base64 \
    --Name "new-api-prepare-${GITHUB_RUN_ID:-manual}" \
    --Timeout 300 \
    --WorkingDir "/root")"

  invoke_id="$(jq -r '.InvokeId // .invokeId // empty' <<< "$run_response")"
  if [ -z "$invoke_id" ]; then
    echo "RunCommand did not return InvokeId for prepare step: $run_response" >&2
    return 1
  fi
  wait_for_command "$invoke_id"

  send_file "$REPO_ROOT/deploy/aliyun/docker-compose.new-api.yml" "docker-compose.new-api.yml" "/opt/open-webui" "0600"
  send_file "$compose_env" ".env" "/opt/open-webui" "0600"
  send_file "$env_new_api" ".env.new-api" "/opt/open-webui" "0600"
  send_file "$docker_config" "config.json" "/root/.docker" "0600"

  run_response="$(aliyun ecs RunCommand \
    --RegionId "$ALIYUN_REGION" \
    --InstanceId.1 "$ECS_INSTANCE_ID" \
    --Type RunShellScript \
    --CommandContent "$(file_to_base64 "$REPO_ROOT/deploy/aliyun/scripts/ecs-deploy.sh")" \
    --ContentEncoding Base64 \
    --Name "new-api-deploy-${GITHUB_RUN_ID:-manual}" \
    --Timeout 1800 \
    --WorkingDir "/opt/open-webui")"

  invoke_id="$(jq -r '.InvokeId // .invokeId // empty' <<< "$run_response")"
  if [ -z "$invoke_id" ]; then
    echo "RunCommand did not return InvokeId: $run_response" >&2
    return 1
  fi

  wait_for_command "$invoke_id"
}

main "$@"
