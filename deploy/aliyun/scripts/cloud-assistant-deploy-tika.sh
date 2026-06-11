#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP_DIR="$(mktemp -d)"
ALIYUN_REGION="${ALIYUN_REGION:-}"
ECS_INSTANCE_ID="${ECS_INSTANCE_ID:-}"
ACR_REGISTRY="${ACR_REGISTRY:-}"
TIKA_IMAGE="${TIKA_IMAGE:-}"

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

  local response
  local args
  args=(cr GetAuthorizationToken --RegionId "$ALIYUN_REGION" --endpoint "cr.${ALIYUN_REGION}.aliyuncs.com")
  if [ -n "${ACR_INSTANCE_ID:-}" ]; then
    args+=(--InstanceId "$ACR_INSTANCE_ID")
  fi

  if ! response="$(aliyun "${args[@]}")"; then
    echo "Could not get an ACR temporary token. Set ACR_USERNAME and ACR_PASSWORD if needed." >&2
    return 1
  fi

  ACR_LOGIN_USERNAME="$(jq -r '.TempUsername // .tempUsername // empty' <<< "$response")"
  ACR_LOGIN_PASSWORD="$(jq -r '.AuthorizationToken // .authorizationToken // empty' <<< "$response")"
  if [ -z "$ACR_LOGIN_USERNAME" ] || [ -z "$ACR_LOGIN_PASSWORD" ]; then
    echo "ACR token response did not contain pull credentials." >&2
    return 1
  fi

  mask_value "$ACR_LOGIN_USERNAME"
  mask_value "$ACR_LOGIN_PASSWORD"
}

resolve_acr_pull_image() {
  local pull_registry="$ACR_REGISTRY"

  if [ -n "${ACR_PULL_REGISTRY:-}" ]; then
    pull_registry="$ACR_PULL_REGISTRY"
  elif [[ "$ACR_REGISTRY" =~ ^(crpi-[^.]+)\.(cn-[^.]+)\.personal\.cr\.aliyuncs\.com$ ]]; then
    pull_registry="${BASH_REMATCH[1]}-vpc.${BASH_REMATCH[2]}.personal.cr.aliyuncs.com"
  elif [[ "$ACR_REGISTRY" =~ ^registry\.(cn-[^.]+)\.aliyuncs\.com$ ]]; then
    pull_registry="registry-vpc.${BASH_REMATCH[1]}.aliyuncs.com"
  fi

  if [ "$pull_registry" != "$ACR_REGISTRY" ] && [[ "$TIKA_IMAGE" == "$ACR_REGISTRY/"* ]]; then
    TIKA_PULL_IMAGE="${pull_registry}/${TIKA_IMAGE#"$ACR_REGISTRY/"}"
  else
    TIKA_PULL_IMAGE="$TIKA_IMAGE"
  fi
  ACR_PULL_REGISTRY_RESOLVED="$pull_registry"
}

file_to_base64() {
  base64 < "$1" | tr -d '\n'
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
  local attempts="${2:-180}"
  local result
  local status
  local exit_code
  local output

  for _ in $(seq 1 "$attempts"); do
    result="$(aliyun ecs DescribeInvocationResults --RegionId "$ALIYUN_REGION" --InvokeId "$invoke_id")"
    status="$(jq -r 'first(.. | objects | select(has("InvocationStatus")) | .InvocationStatus) // empty' <<< "$result")"
    exit_code="$(jq -r 'first(.. | objects | select(has("ExitCode")) | .ExitCode) // empty' <<< "$result")"
    output="$(jq -r 'first(.. | objects | select(has("Output")) | .Output) // empty' <<< "$result")"

    case "$status" in
      Success)
        decode_maybe_base64 "$output"
        [ -z "$exit_code" ] || [ "$exit_code" = "0" ]
        return
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
  required_env TIKA_IMAGE

  local docker_config="$TMP_DIR/config.json"
  local remote_script="$TMP_DIR/deploy-tika.sh"
  local docker_auth
  local response
  local invoke_id

  resolve_acr_pull_image
  resolve_acr_credentials
  docker_auth="$(printf '%s:%s' "$ACR_LOGIN_USERNAME" "$ACR_LOGIN_PASSWORD" | base64 | tr -d '\n')"

  if [ "$ACR_PULL_REGISTRY_RESOLVED" != "$ACR_REGISTRY" ]; then
    jq -n \
      --arg push_registry "$ACR_REGISTRY" \
      --arg pull_registry "$ACR_PULL_REGISTRY_RESOLVED" \
      --arg auth "$docker_auth" \
      '{auths: {($push_registry): {auth: $auth}, ($pull_registry): {auth: $auth}}}' > "$docker_config"
  else
    jq -n --arg registry "$ACR_REGISTRY" --arg auth "$docker_auth" \
      '{auths: {($registry): {auth: $auth}}}' > "$docker_config"
  fi

  {
    printf 'export TIKA_IMAGE=%q\n' "$TIKA_PULL_IMAGE"
    printf 'export TIKA_MEMORY=%q\n' "${TIKA_MEMORY:-1536m}"
    printf 'export TIKA_CPUS=%q\n' "${TIKA_CPUS:-1.0}"
    printf 'export TIKA_JAVA_OPTS=%q\n' "${TIKA_JAVA_OPTS:--Xms256m -Xmx1024m}"
    cat "$REPO_ROOT/deploy/aliyun/scripts/ecs-deploy-tika.sh"
  } > "$remote_script"

  response="$(aliyun ecs RunCommand \
    --RegionId "$ALIYUN_REGION" \
    --InstanceId.1 "$ECS_INSTANCE_ID" \
    --Type RunShellScript \
    --CommandContent "$(printf '%s' 'mkdir -p /root/.docker && chmod 700 /root/.docker' | base64 | tr -d '\n')" \
    --ContentEncoding Base64 \
    --Name "tika-prepare-${GITHUB_RUN_ID:-manual}" \
    --Timeout 300 \
    --WorkingDir "/root")"
  invoke_id="$(jq -r '.InvokeId // .invokeId // empty' <<< "$response")"
  if [ -z "$invoke_id" ]; then
    echo "RunCommand did not return InvokeId for prepare step: $response" >&2
    return 1
  fi
  wait_for_command "$invoke_id" 60

  response="$(aliyun ecs SendFile \
    --RegionId "$ALIYUN_REGION" \
    --InstanceId.1 "$ECS_INSTANCE_ID" \
    --Name "config.json" \
    --TargetDir "/root/.docker" \
    --ContentType Base64 \
    --Content "$(file_to_base64 "$docker_config")" \
    --FileMode "0600" \
    --Overwrite true)"
  invoke_id="$(jq -r '.InvokeId // .invokeId // empty' <<< "$response")"
  if [ -z "$invoke_id" ]; then
    echo "SendFile did not return InvokeId: $response" >&2
    return 1
  fi
  wait_for_command "$invoke_id" 60

  response="$(aliyun ecs RunCommand \
    --RegionId "$ALIYUN_REGION" \
    --InstanceId.1 "$ECS_INSTANCE_ID" \
    --Type RunShellScript \
    --CommandContent "$(file_to_base64 "$remote_script")" \
    --ContentEncoding Base64 \
    --Name "tika-deploy-${GITHUB_RUN_ID:-manual}" \
    --Timeout 1200 \
    --WorkingDir "/root")"

  invoke_id="$(jq -r '.InvokeId // .invokeId // empty' <<< "$response")"
  if [ -z "$invoke_id" ]; then
    echo "RunCommand did not return InvokeId: $response" >&2
    return 1
  fi

  wait_for_command "$invoke_id" 120
}

main "$@"
