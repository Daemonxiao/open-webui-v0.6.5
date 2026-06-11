#!/usr/bin/env bash
set -euo pipefail

TIKA_CONTAINER_NAME="${TIKA_CONTAINER_NAME:-tika}"
TIKA_NETWORK="${TIKA_NETWORK:-open-webui}"
TIKA_MEMORY="${TIKA_MEMORY:-1536m}"
TIKA_CPUS="${TIKA_CPUS:-1.0}"
TIKA_JAVA_OPTS="${TIKA_JAVA_OPTS:--Xms256m -Xmx1024m}"
TIKA_HEALTH_CHECK_ATTEMPTS="${TIKA_HEALTH_CHECK_ATTEMPTS:-60}"
TIKA_HEALTH_CHECK_DELAY_SECONDS="${TIKA_HEALTH_CHECK_DELAY_SECONDS:-5}"

required_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required environment variable: $name" >&2
    return 1
  fi
}

install_container_runtime() {
  if command -v docker >/dev/null 2>&1; then
    return 0
  fi

  if command -v dnf >/dev/null 2>&1; then
    dnf install -y docker curl
  elif command -v yum >/dev/null 2>&1; then
    yum install -y docker curl
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io curl
  else
    echo "No supported package manager found for Docker installation." >&2
    return 1
  fi
}

start_container_runtime() {
  if docker version >/dev/null 2>&1; then
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now docker.service >/dev/null 2>&1 || systemctl enable --now podman.socket
  elif command -v service >/dev/null 2>&1; then
    service docker start
  fi

  docker version >/dev/null
}

ensure_container_restart_service() {
  if command -v systemctl >/dev/null 2>&1 && docker version 2>&1 | grep -qi podman; then
    systemctl enable --now podman-restart.service >/dev/null 2>&1 || true
  fi
}

ensure_network() {
  docker network inspect "$TIKA_NETWORK" >/dev/null 2>&1 || docker network create "$TIKA_NETWORK"
}

run_tika() {
  local image="$1"

  docker run -d \
    --name "$TIKA_CONTAINER_NAME" \
    --restart unless-stopped \
    --network "$TIKA_NETWORK" \
    --network-alias tika \
    --memory "$TIKA_MEMORY" \
    --cpus "$TIKA_CPUS" \
    -e "JAVA_TOOL_OPTIONS=$TIKA_JAVA_OPTS" \
    "$image"
}

wait_for_tika() {
  local container_ip

  for _ in $(seq 1 "$TIKA_HEALTH_CHECK_ATTEMPTS"); do
    if ! docker inspect -f '{{.State.Running}}' "$TIKA_CONTAINER_NAME" 2>/dev/null | grep -Fxq true; then
      docker logs --tail=200 "$TIKA_CONTAINER_NAME" || true
      return 1
    fi

    container_ip="$(docker inspect -f "{{with index .NetworkSettings.Networks \"$TIKA_NETWORK\"}}{{.IPAddress}}{{end}}" "$TIKA_CONTAINER_NAME")"
    if [ -n "$container_ip" ] && curl --silent --fail "http://${container_ip}:9998/tika" >/dev/null; then
      if docker inspect open-webui-hai >/dev/null 2>&1; then
        if ! docker exec open-webui-hai curl --silent --fail http://tika:9998/tika >/dev/null; then
          sleep "$TIKA_HEALTH_CHECK_DELAY_SECONDS"
          continue
        fi
      fi
      docker ps --filter "name=${TIKA_CONTAINER_NAME}"
      return 0
    fi

    sleep "$TIKA_HEALTH_CHECK_DELAY_SECONDS"
  done

  docker logs --tail=200 "$TIKA_CONTAINER_NAME" || true
  return 1
}

main() {
  required_env TIKA_IMAGE
  install_container_runtime
  start_container_runtime
  ensure_container_restart_service
  ensure_network

  local previous_image
  previous_image="$(docker inspect -f '{{.Image}}' "$TIKA_CONTAINER_NAME" 2>/dev/null || true)"

  docker pull "$TIKA_IMAGE"
  docker rm -f "$TIKA_CONTAINER_NAME" >/dev/null 2>&1 || true
  run_tika "$TIKA_IMAGE"

  if wait_for_tika; then
    docker image prune -f || true
    return 0
  fi

  docker rm -f "$TIKA_CONTAINER_NAME" >/dev/null 2>&1 || true
  if [ -n "$previous_image" ]; then
    echo "Tika health check failed; rolling back to $previous_image" >&2
    run_tika "$previous_image"
    wait_for_tika
  fi
  return 1
}

main "$@"
