#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/open-webui}"
DATA_DIR="${DATA_DIR:-${APP_DIR}/data}"
CONTAINER_NAME="${CONTAINER_NAME:-open-webui-hai}"
HEALTH_CHECK_ATTEMPTS="${HEALTH_CHECK_ATTEMPTS:-180}"
HEALTH_CHECK_DELAY_SECONDS="${HEALTH_CHECK_DELAY_SECONDS:-5}"

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

deploy_open_webui() {
  cd "$APP_DIR"
  set -a
  . "$APP_DIR/.env"
  set +a

  pull_image
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "${OPEN_WEBUI_PORT:-3000}:8080" \
    --env-file "$APP_DIR/.env.hai" \
    --env-file "$APP_DIR/.env" \
    -v "$DATA_DIR:/app/backend/data" \
    "$OPEN_WEBUI_IMAGE"

  for _ in $(seq 1 "$HEALTH_CHECK_ATTEMPTS"); do
    if curl --silent --fail "http://127.0.0.1:${OPEN_WEBUI_PORT:-3000}/health" >/dev/null; then
      docker ps --filter "name=${CONTAINER_NAME}"
      return 0
    fi
    sleep "$HEALTH_CHECK_DELAY_SECONDS"
  done

  docker logs --tail=200 "$CONTAINER_NAME"
  return 1
}

pull_image() {
  local attempt

  for attempt in $(seq 1 5); do
    if docker pull "$OPEN_WEBUI_IMAGE"; then
      return 0
    fi

    echo "Image pull failed on attempt $attempt, retrying..." >&2
    sleep $((attempt * 15))
  done

  echo "Image pull failed after 5 attempts." >&2
  return 1
}

main() {
  umask 077
  mkdir -p "$APP_DIR" /root/.docker

  wait_for_file "$APP_DIR/docker-compose.yml"
  wait_for_file "$APP_DIR/.env"
  wait_for_file "$APP_DIR/.env.hai"
  wait_for_file "/root/.docker/config.json"

  chmod 600 "$APP_DIR/.env" "$APP_DIR/.env.hai" /root/.docker/config.json
  install_container_runtime
  mount_data_disk
  deploy_open_webui
}

main "$@"
