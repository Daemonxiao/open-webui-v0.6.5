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
  required_env NEW_API_DATABASE_URL
  required_env NEW_API_SESSION_SECRET
  required_env NEW_API_CRYPTO_SECRET

  local new_api_image="${NEW_API_IMAGE:-calciumion/new-api:v1.0.0-rc.8}"
  local new_api_port="${NEW_API_PORT:-3001}"
  local compose_env="$TMP_DIR/compose.env"
  local env_new_api="$TMP_DIR/.env.new-api"
  local docker_config="$TMP_DIR/config.json"
  local prepare_script="$TMP_DIR/prepare.sh"
  local run_response
  local invoke_id

  mask_value "$NEW_API_DATABASE_URL"
  mask_value "$NEW_API_SESSION_SECRET"
  mask_value "$NEW_API_CRYPTO_SECRET"

  {
    printf 'NEW_API_IMAGE=%s\n' "$new_api_image"
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
  jq -n '{auths: {}}' > "$docker_config"
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
