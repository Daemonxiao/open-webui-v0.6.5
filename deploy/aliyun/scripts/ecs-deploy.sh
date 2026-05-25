#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/open-webui}"
DATA_DIR="${DATA_DIR:-${APP_DIR}/data}"
CONTAINER_NAME="${CONTAINER_NAME:-open-webui-hai}"
NEW_API_CONTAINER_NAME="${NEW_API_CONTAINER_NAME:-new-api-hai}"
DEPLOY_TARGET="${DEPLOY_TARGET:-open-webui}"
HEALTH_CHECK_ATTEMPTS="${HEALTH_CHECK_ATTEMPTS:-180}"
HEALTH_CHECK_DELAY_SECONDS="${HEALTH_CHECK_DELAY_SECONDS:-5}"
COMPOSE_PULL_TIMEOUT_SECONDS="${COMPOSE_PULL_TIMEOUT_SECONDS:-900}"
COMPOSE_UP_TIMEOUT_SECONDS="${COMPOSE_UP_TIMEOUT_SECONDS:-300}"

wait_for_file() {
  local path="$1"
  local i

  for i in $(seq 1 60); do
    if [ -s "$path" ]; then
      return 0
    fi
    sleep 2
  done

  echo "Required file did not arrive: $path" >&2
  return 1
}

install_container_runtime() {
  if command -v docker >/dev/null 2>&1; then
    start_container_service || true
  else
    if command -v dnf >/dev/null 2>&1; then
      dnf install -y docker curl util-linux e2fsprogs
    elif command -v yum >/dev/null 2>&1; then
      yum install -y docker curl util-linux e2fsprogs
    elif command -v apt-get >/dev/null 2>&1; then
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io curl util-linux e2fsprogs
    else
      echo "No supported package manager found for Docker installation." >&2
      return 1
    fi
    start_container_service || true
  fi

  docker version >/dev/null
  install_docker_compose
}

install_docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    return 0
  fi

  if command -v dnf >/dev/null 2>&1; then
    timeout 300 dnf install -y docker-compose-plugin || true
  elif command -v yum >/dev/null 2>&1; then
    timeout 300 yum install -y docker-compose-plugin || true
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive timeout 300 apt-get install -y docker-compose-plugin || true
  fi

  if docker compose version >/dev/null 2>&1; then
    return 0
  fi

  mkdir -p /usr/local/lib/docker/cli-plugins
  timeout 180 curl -fsSL "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-$(uname -m)" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  docker compose version >/dev/null
}

start_container_service() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now docker >/dev/null 2>&1 && return 0
    systemctl enable --now podman.socket >/dev/null 2>&1 && return 0
  fi

  if command -v service >/dev/null 2>&1; then
    service docker start >/dev/null 2>&1 && return 0
  fi

  return 1
}

find_data_device() {
  lsblk -nrpo NAME,TYPE,MOUNTPOINT | awk '
    $2 == "disk" && $3 == "" {
      if ($1 !~ /\/(vda|xvda|sda|nvme0n1)$/) {
        print $1
        exit
      }
    }
  '
}

mount_data_disk() {
  mkdir -p "$DATA_DIR"

  if findmnt -rn "$DATA_DIR" >/dev/null 2>&1; then
    return 0
  fi

  local device
  device="$(find_data_device || true)"
  if [ -z "$device" ]; then
    echo "No unattached data disk device found for $DATA_DIR." >&2
    return 1
  fi

  if ! blkid -s TYPE -o value "$device" >/dev/null 2>&1; then
    mkfs.ext4 -F "$device"
  fi

  local uuid
  uuid="$(blkid -s UUID -o value "$device")"
  if [ -z "$uuid" ]; then
    echo "Could not resolve UUID for $device." >&2
    return 1
  fi

  if ! grep -q "UUID=${uuid}" /etc/fstab; then
    printf 'UUID=%s %s ext4 defaults,nofail 0 2\n' "$uuid" "$DATA_DIR" >> /etc/fstab
  fi

  mount "$DATA_DIR"
}

print_docker_diagnostics() {
  cd "$APP_DIR"
  echo "Docker version:"
  docker version || true
  echo "Docker Compose version:"
  docker compose version || true
  echo "Docker containers:"
  docker ps -a || true
  if [ -f docker-compose.new-api.yml ]; then
    echo "New API compose status:"
    docker compose -f docker-compose.new-api.yml ps || true
  fi
  if [ -f docker-compose.open-webui.yml ]; then
    echo "Open WebUI compose status:"
    docker compose -f docker-compose.open-webui.yml ps || true
  fi
  echo "New API logs:"
  docker logs --tail=200 "$NEW_API_CONTAINER_NAME" || true
  echo "Open WebUI logs:"
  docker logs --tail=200 "$CONTAINER_NAME" || true
}

deploy_open_webui() {
  cd "$APP_DIR"
  set -a
  . "$APP_DIR/.env"
  set +a

  timeout "$COMPOSE_PULL_TIMEOUT_SECONDS" docker compose -f docker-compose.open-webui.yml pull
  timeout "$COMPOSE_UP_TIMEOUT_SECONDS" docker compose -f docker-compose.open-webui.yml up -d

  for _ in $(seq 1 "$HEALTH_CHECK_ATTEMPTS"); do
    if curl --silent --fail "http://127.0.0.1:${OPEN_WEBUI_PORT:-3000}/health" >/dev/null; then
      docker ps --filter "name=${CONTAINER_NAME}"
      return 0
    fi
    sleep "$HEALTH_CHECK_DELAY_SECONDS"
  done

  print_docker_diagnostics
  return 1
}

deploy_new_api() {
  cd "$APP_DIR"
  set -a
  . "$APP_DIR/.env"
  set +a

  timeout "$COMPOSE_PULL_TIMEOUT_SECONDS" docker compose -f docker-compose.new-api.yml pull
  timeout "$COMPOSE_UP_TIMEOUT_SECONDS" docker compose -f docker-compose.new-api.yml up -d

  for _ in $(seq 1 "$HEALTH_CHECK_ATTEMPTS"); do
    if curl --silent --fail "http://127.0.0.1:${NEW_API_PORT:-3001}/api/status" >/dev/null; then
      docker ps --filter "name=${NEW_API_CONTAINER_NAME}"
      return 0
    fi
    sleep "$HEALTH_CHECK_DELAY_SECONDS"
  done

  print_docker_diagnostics
  return 1
}

deploy_target() {
  case "$DEPLOY_TARGET" in
    new-api)
      deploy_new_api
      ;;
    open-webui)
      deploy_open_webui
      ;;
    all)
      deploy_new_api
      deploy_open_webui
      ;;
    *)
      echo "Unsupported DEPLOY_TARGET: $DEPLOY_TARGET" >&2
      return 1
      ;;
  esac
}

main() {
  umask 077
  mkdir -p "$APP_DIR" /root/.docker

  wait_for_file "$APP_DIR/.env"
  wait_for_file "/root/.docker/config.json"
  set -a
  . "$APP_DIR/.env"
  set +a

  case "$DEPLOY_TARGET" in
    new-api)
      wait_for_file "$APP_DIR/docker-compose.new-api.yml"
      wait_for_file "$APP_DIR/.env.new-api"
      ;;
    open-webui)
      wait_for_file "$APP_DIR/docker-compose.open-webui.yml"
      wait_for_file "$APP_DIR/.env.hai"
      wait_for_file "$APP_DIR/.env.open-webui"
      ;;
    all)
      wait_for_file "$APP_DIR/docker-compose.new-api.yml"
      wait_for_file "$APP_DIR/docker-compose.open-webui.yml"
      wait_for_file "$APP_DIR/.env.new-api"
      wait_for_file "$APP_DIR/.env.hai"
      wait_for_file "$APP_DIR/.env.open-webui"
      ;;
    *)
      echo "Unsupported DEPLOY_TARGET: $DEPLOY_TARGET" >&2
      return 1
      ;;
  esac

  chmod 600 "$APP_DIR"/.env* /root/.docker/config.json
  install_container_runtime
  mount_data_disk
  mkdir -p "$APP_DIR/new-api-data" "$APP_DIR/new-api-logs"
  deploy_target
}

main "$@"
