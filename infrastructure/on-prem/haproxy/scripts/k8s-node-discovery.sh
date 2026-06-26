#!/usr/bin/env sh
set -eu

CONSUL_HTTP_ADDR="${CONSUL_HTTP_ADDR:-http://consul:8500}"
SERVICE_NAME="${SERVICE_NAME:-traefik-nodeport}"
SERVICE_PORT="${SERVICE_PORT:-30080}"
NODE_ADDRESS_TYPE="${NODE_ADDRESS_TYPE:-InternalIP}"
DISCOVERY_INTERVAL_SECONDS="${DISCOVERY_INTERVAL_SECONDS:-15}"
CONSUL_DEREGISTER_CRITICAL_AFTER="${CONSUL_DEREGISTER_CRITICAL_AFTER:-1m}"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

need kubectl
need curl
need jq

service_id_for() {
  printf '%s-%s' "$SERVICE_NAME" "$1" | tr -c 'A-Za-z0-9_-' '-'
}

consul_put_json() {
  path="$1"
  file="$2"
  curl -fsS -X PUT --data-binary "@${file}" "${CONSUL_HTTP_ADDR}${path}" >/dev/null
}

register_node() {
  node_name="$1"
  node_ip="$2"
  service_id="$(service_id_for "$node_name")"
  payload="/tmp/${service_id}.json"

  cat > "$payload" <<EOF
{
  "ID": "${service_id}",
  "Name": "${SERVICE_NAME}",
  "Tags": ["kubernetes", "traefik", "nodeport", "auto-discovered"],
  "Address": "${node_ip}",
  "Port": ${SERVICE_PORT},
  "Meta": {
    "kubernetes_node": "${node_name}",
    "address_type": "${NODE_ADDRESS_TYPE}"
  },
  "Check": {
    "Name": "${SERVICE_NAME} ${node_name} tcp",
    "TCP": "${node_ip}:${SERVICE_PORT}",
    "Interval": "10s",
    "Timeout": "3s",
    "DeregisterCriticalServiceAfter": "${CONSUL_DEREGISTER_CRITICAL_AFTER}"
  }
}
EOF

  consul_put_json "/v1/agent/service/register" "$payload"
  rm -f "$payload"
  echo "registered ${node_name} ${node_ip}:${SERVICE_PORT}"
}

deregister_service() {
  service_id="$1"
  curl -fsS -X PUT "${CONSUL_HTTP_ADDR}/v1/agent/service/deregister/${service_id}" >/dev/null
  echo "deregistered ${service_id}"
}

while true; do
  desired_ids="/tmp/desired-${SERVICE_NAME}.txt"
  current_ids="/tmp/current-${SERVICE_NAME}.txt"
  : > "$desired_ids"

  kubectl get nodes -o json | jq -r --arg address_type "$NODE_ADDRESS_TYPE" '
    .items[]
    | {
        name: .metadata.name,
        ready: ([.status.conditions[]? | select(.type == "Ready") | .status] | last),
        address: ([.status.addresses[]? | select(.type == $address_type) | .address] | first)
      }
    | select(.ready == "True" and (.address // "") != "")
    | [.name, .address]
    | @tsv
  ' | while IFS="$(printf '\t')" read -r node_name node_ip; do
    [ -n "$node_name" ] || continue
    service_id="$(service_id_for "$node_name")"
    printf '%s\n' "$service_id" >> "$desired_ids"
    register_node "$node_name" "$node_ip"
  done

  curl -fsS "${CONSUL_HTTP_ADDR}/v1/agent/services" \
    | jq -r --arg service_name "$SERVICE_NAME" '
        to_entries[]
        | select(.value.Service == $service_name)
        | .key
      ' | sort -u > "$current_ids"

  sort -u "$desired_ids" -o "$desired_ids"

  while IFS= read -r service_id; do
    [ -n "$service_id" ] || continue
    if ! grep -Fxq "$service_id" "$desired_ids"; then
      deregister_service "$service_id"
    fi
  done < "$current_ids"

  sleep "$DISCOVERY_INTERVAL_SECONDS"
done
