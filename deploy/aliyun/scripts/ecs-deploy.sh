#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/open-webui}"
DATA_DIR="${DATA_DIR:-${APP_DIR}/data}"

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

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    systemctl enable --now docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
  else
    if command -v dnf >/dev/null 2>&1; then
      dnf install -y docker curl util-linux e2fsprogs
      dnf install -y docker-compose-plugin || true
    elif command -v yum >/dev/null 2>&1; then
      yum install -y docker curl util-linux e2fsprogs
      yum install -y docker-compose-plugin || true
    elif command -v apt-get >/dev/null 2>&1; then
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io curl util-linux e2fsprogs
      DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-plugin || true
    else
      echo "No supported package manager found for Docker installation." >&2
      return 1
    fi
    systemctl enable --now docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1
  fi

  if docker compose version >/dev/null 2>&1; then
    return 0
  fi

  mkdir -p /usr/local/lib/docker/cli-plugins
  curl -fsSL "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  docker compose version >/dev/null
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

  docker compose --env-file "$APP_DIR/.env" -f "$APP_DIR/docker-compose.yml" pull
  docker compose --env-file "$APP_DIR/.env" -f "$APP_DIR/docker-compose.yml" up -d --remove-orphans

  for _ in $(seq 1 60); do
    if curl --silent --fail "http://127.0.0.1:${OPEN_WEBUI_PORT:-3000}/health" >/dev/null; then
      docker compose --env-file "$APP_DIR/.env" -f "$APP_DIR/docker-compose.yml" ps
      return 0
    fi
    sleep 5
  done

  docker compose --env-file "$APP_DIR/.env" -f "$APP_DIR/docker-compose.yml" logs --tail=200 open-webui
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
  install_docker
  mount_data_disk
  deploy_open_webui
}

main "$@"
