resource "google_service_account" "vm" {
  count        = var.enable_vm ? 1 : 0
  account_id   = var.vm_service_account_id
  display_name = var.vm_service_account_display_name
  project      = var.project_id
}

resource "google_compute_firewall" "app_ingress" {
  count   = var.enable_vm ? 1 : 0
  name    = "${var.vm_name}-ingress"
  project = var.project_id
  network = "default"

  allow {
    protocol = "tcp"
    ports    = [for p in var.app_ports : tostring(p)]
  }

  source_ranges = var.app_source_ranges
  target_tags   = [var.vm_network_tag]

  depends_on = [google_project_service.compute]
}

resource "google_compute_instance" "app_vm" {
  count               = var.enable_vm ? 1 : 0
  name                = var.vm_name
  project             = var.project_id
  zone                = var.vm_zone
  machine_type        = var.vm_machine_type
  tags                = [var.vm_network_tag]
  deletion_protection = false

  boot_disk {
    initialize_params {
      image = var.vm_boot_image
      size  = var.vm_boot_disk_size_gb
      type  = var.vm_boot_disk_type
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  service_account {
    email  = google_service_account.vm[0].email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata_startup_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    exec > >(tee -a /var/log/startup-script.log) 2>&1
    echo "Startup script begin: $(date -Is)"
    export DEBIAN_FRONTEND=noninteractive
    export APT_LISTCHANGES_FRONTEND=none

    apt-get update -y
    apt-get install -y --no-install-recommends ca-certificates curl gnupg python3
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    ARCH="$(dpkg --print-architecture)"
    . /etc/os-release
    echo "deb [arch=$${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable docker
    systemctl start docker

    mkdir -p /opt/app

    COMPOSE_BUCKET="${local.effective_bundle_bucket}"
    COMPOSE_OBJECT="${local.compose_object_name}"
    APP_BUNDLE_OBJECT="${local.app_bundle_object_name}"
    PROJECT_ID="${var.project_id}"
    SQL_INSTANCE_NAME="${var.db_instance_name}"
    ENABLE_SQL="${var.enable_sql}"
    SQL_CONNECTION_NAME="${var.project_id}:${var.location}:${var.db_instance_name}"

    if [[ -n "${local.effective_bundle_bucket}" ]]; then
      gcs_token() {
        curl -s -H "Metadata-Flavor: Google" \
          "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" \
          | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])"
      }

      gcs_object_url() {
        local bucket="$1"
        local object="$2"
        local encoded
        encoded="$(python3 - "$${object}" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
)"
        echo "https://storage.googleapis.com/storage/v1/b/$${bucket}/o/$${encoded}"
      }

      gcs_object_exists() {
        local bucket="$1"
        local object="$2"
        local token
        local url
        token="$(gcs_token)"
        url="$(gcs_object_url "$${bucket}" "$${object}")"
        curl -sf -H "Authorization: Bearer $${token}" "$${url}" >/dev/null
      }

      gcs_object_status() {
        local bucket="$1"
        local object="$2"
        local token
        local url
        token="$(gcs_token)"
        url="$(gcs_object_url "$${bucket}" "$${object}")"
        curl -s -o /dev/null -w "%%{http_code}" -H "Authorization: Bearer $${token}" "$${url}"
      }

      gcs_download() {
        local bucket="$1"
        local object="$2"
        local dest="$3"
        local token
        local url
        token="$(gcs_token)"
        url="$(gcs_object_url "$${bucket}" "$${object}")?alt=media"
        curl -fL -H "Authorization: Bearer $${token}" "$${url}" -o "$${dest}"
      }

      secret_access() {
        local secret_name="$1"
        local token
        local url
        token="$(gcs_token)"
        url="https://secretmanager.googleapis.com/v1/projects/${var.project_id}/secrets/$${secret_name}/versions/latest:access"
        curl -s -H "Authorization: Bearer $${token}" "$${url}" \
          | python3 -c "import sys, json, base64; print(base64.b64decode(json.load(sys.stdin)['payload']['data']).decode())"
      }

      secret_try() {
        local secret_name="$1"
        local out
        set +e
        out="$(secret_access "$${secret_name}" 2>/dev/null)"
        local rc=$?
        set -e
        if [[ $${rc} -ne 0 || -z "$${out}" ]]; then
          return 1
        fi
        printf '%s' "$${out}"
        return 0
      }

      wait_for_object() {
        local object_path="$1"
        local attempts=90
        local delay=10
        for ((i=1; i<=attempts; i++)); do
          status="$(gcs_object_status "${local.effective_bundle_bucket}" "$${object_path}")"
          if [[ "$${status}" == "200" ]]; then
            echo "Found $object_path"
            return 0
          fi
          echo "Waiting for $object_path ($i/$attempts), status=$${status}"
          sleep "$delay"
        done
        echo "ERROR: Timed out waiting for $object_path" >&2
        return 1
      }

      if [[ -n "${local.app_bundle_source_path}" ]]; then
        wait_for_object "${local.app_bundle_object_name}"
        mkdir -p /opt/app/src
        gcs_download "${local.effective_bundle_bucket}" "${local.app_bundle_object_name}" /opt/app/app_bundle.tar.gz
        tar -xzf /opt/app/app_bundle.tar.gz -C /opt/app/src
        mkdir -p /opt/app/src/storage
        cd /opt/app/src
        ENV_RUNTIME=".env.runtime"
        if [[ -f .env.develop ]]; then
          grep -vE '^(DATABASE_URL=|docker compose )' .env.develop > "$${ENV_RUNTIME}"
        else
          : > "$${ENV_RUNTIME}"
        fi
        # Sanitize .env.runtime (remove invalid env lines, multiline secrets, CRLF)
        python3 - "$${ENV_RUNTIME}" <<'PY'
import re
import sys

path = sys.argv[1]
lines = []
with open(path, "rb") as fh:
    raw = fh.read().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
for line in raw.split(b"\n"):
    if not line:
        continue
    try:
        text = line.decode("utf-8", "ignore")
    except Exception:
        continue
    # Only keep KEY=VALUE with safe key names
    if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=.*$", text):
        lines.append(text)
with open(path, "w", encoding="utf-8") as out:
    out.write("\n".join(lines) + "\n")
PY
        # Drop CLOUD_SQL_CREDENTIALS if the file doesn't exist on the VM
        NO_SQL_CRED="false"
        if grep -q '^CLOUD_SQL_CREDENTIALS=' "$${ENV_RUNTIME}"; then
          cred_path="$$(grep -m1 '^CLOUD_SQL_CREDENTIALS=' "$${ENV_RUNTIME}" | cut -d= -f2-)"
          if [[ -z "$${cred_path}" || ! -f "$${cred_path}" ]]; then
            sed -i '/^CLOUD_SQL_CREDENTIALS=/d' "$${ENV_RUNTIME}"
            NO_SQL_CRED="true"
            echo "CLOUD_SQL_CREDENTIALS not found on VM; using instance service account"
          fi
        else
          NO_SQL_CRED="true"
        fi
        if [[ -n "${local.app_secret_names}" ]]; then
          for secret_name in ${local.app_secret_names}; do
            case "$${secret_name}" in
              VAST_SSH_KEY)
                # Do not write multiline secrets into .env.runtime
                continue
                ;;
            esac
            secret_value="$(secret_access "$${secret_name}")"
            if [[ "$${secret_name}" == "VAST_API_KEY" ]]; then
              # Strip UTF-8 BOM and surrounding whitespace to avoid latin-1 encoding errors
              secret_value="$(printf '%s' "$${secret_value}" | python3 -c "import sys; s=sys.stdin.read(); s=s.lstrip('\\ufeff').strip(); print(s, end='')")"
            elif [[ "$${secret_name}" == "GCP_SA_B64" ]]; then
              # Keep GCP_SA_B64 single-line for env file (strip BOM/whitespace/newlines)
              secret_value="$(printf '%s' "$${secret_value}" | python3 -c "import sys; s=sys.stdin.read(); s=s.lstrip('\\ufeff'); s=''.join(s.split()); print(s, end='')")"
            fi
            printf '%s=%s\n' "$${secret_name}" "$${secret_value}" >> "$${ENV_RUNTIME}"
          done
        fi
        mkdir -p /opt/app/secrets
        gcp_secret_url="https://secretmanager.googleapis.com/v1/projects/${var.project_id}/secrets/GCP_SA_B64/versions/latest:access"
        gcp_secret_tmp="/tmp/gcp_sa_b64.json"
        gcp_http_code="$(curl -s -o "$${gcp_secret_tmp}" -w "%%{http_code}" -H "Authorization: Bearer $(gcs_token)" "$${gcp_secret_url}")"
        if [[ "$${gcp_http_code}" != "200" ]]; then
          echo "ERROR: GCP_SA_B64 fetch failed HTTP $${gcp_http_code}" >&2
          echo "Response:" >&2
          head -c 400 "$${gcp_secret_tmp}" >&2 || true
          exit 1
        fi
        if python3 - "$${gcp_secret_tmp}" > /opt/app/secrets/gcp.json <<'PY'
import base64
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    payload = json.load(handle).get("payload", {}).get("data")
if not payload:
    raise SystemExit("ERROR: GCP_SA_B64 payload missing or empty.")

first = base64.b64decode(payload).decode("utf-8")
compact = "".join(first.split())
decoded = base64.b64decode(compact).decode("utf-8")
json.loads(decoded)
print(decoded)
PY
        then
          chmod 600 /opt/app/secrets/gcp.json
          if [[ "$${NO_SQL_CRED}" == "true" && ! -f /opt/app/secrets/cloudsql.json ]]; then
            cp /opt/app/secrets/gcp.json /opt/app/secrets/cloudsql.json
            chmod 600 /opt/app/secrets/cloudsql.json
          fi
          if [[ "$${NO_SQL_CRED}" == "true" ]]; then
            mkdir -p /opt/app/src/secrets
            cp /opt/app/secrets/gcp.json /opt/app/src/secrets/cloudsql.json
            chown 65532:65532 /opt/app/src/secrets/cloudsql.json
            chmod 644 /opt/app/src/secrets/cloudsql.json
          fi
        else
          echo "ERROR: Failed to fetch or decode GCP_SA_B64 from Secret Manager." >&2
          exit 1
        fi
        if [[ "$${ENABLE_SQL}" == "true" ]]; then
          printf 'DB_HOST=%s\n' "cloud-sql-proxy" >> "$${ENV_RUNTIME}"
          printf 'DB_PORT=%s\n' "5432" >> "$${ENV_RUNTIME}"
          printf 'CLOUD_SQL_INSTANCE=%s\n' "$${SQL_CONNECTION_NAME}" >> "$${ENV_RUNTIME}"
        fi
        if grep -q '^VAST_API_KEY=' "$${ENV_RUNTIME}"; then
          mkdir -p /opt/app/secrets
          vast_secret_url="https://secretmanager.googleapis.com/v1/projects/${var.project_id}/secrets/VAST_SSH_KEY/versions/latest:access"
          vast_secret_tmp="/tmp/vast_ssh_key.json"
          vast_http_code="$(curl -s -o "$${vast_secret_tmp}" -w "%%{http_code}" -H "Authorization: Bearer $(gcs_token)" "$${vast_secret_url}")"
          if [[ "$${vast_http_code}" != "200" ]]; then
            echo "ERROR: VAST_SSH_KEY fetch failed HTTP $${vast_http_code}" >&2
            echo "Response:" >&2
            head -c 400 "$${vast_secret_tmp}" >&2 || true
            exit 1
          fi
          if python3 - "$${vast_secret_tmp}" > /opt/app/secrets/vast_ed25519 <<'PY'
import base64
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    payload = json.load(handle).get("payload", {}).get("data")
if not payload:
    raise SystemExit("ERROR: VAST_SSH_KEY payload missing or empty.")

text = base64.b64decode(payload).decode("utf-8").strip()
if not text:
    raise SystemExit("ERROR: VAST_SSH_KEY decoded is empty.")

if "BEGIN OPENSSH PRIVATE KEY" in text:
    key = text
else:
    key = base64.b64decode("".join(text.split())).decode("utf-8")
if "BEGIN OPENSSH PRIVATE KEY" not in key:
    raise SystemExit("ERROR: VAST_SSH_KEY is not valid OpenSSH key.")

if not key.endswith("\n"):
    key += "\n"
print(key)
PY
          then
            chmod 600 /opt/app/secrets/vast_ed25519
            if ! ssh-keygen -yf /opt/app/secrets/vast_ed25519 >/dev/null 2>&1; then
              echo "ERROR: VAST_SSH_KEY failed ssh-keygen validation." >&2
              exit 1
            fi
            ssh-keyscan -p 22 ssh5.vast.ai > /opt/app/secrets/known_hosts || true
            chmod 644 /opt/app/secrets/known_hosts
          else
            echo "ERROR: Failed to fetch or decode VAST_SSH_KEY from Secret Manager." >&2
            exit 1
          fi
        fi
        cat > /opt/app/src/infra/docker/docker-compose.override.yml <<'YAML'
services:
  training-service:
    env_file:
      - ../../.env.runtime
      - ../../.env.develop
    volumes:
      - /opt/app/secrets/gcp.json:/root/gcp.json:ro
  training-worker:
    env_file:
      - ../../.env.runtime
      - ../../.env.develop
    volumes:
      - /opt/app/secrets/gcp.json:/root/gcp.json:ro
YAML
        if [[ "${var.enable_observability}" == "true" ]]; then
          mkdir -p /opt/app/obs
          cat > /opt/app/obs/promtail-config.yml <<'YAML'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: ${local.obs_loki_url}

scrape_configs:
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      - target_label: host
        replacement: cv-app-vm
      - source_labels: [__meta_docker_container_name]
        regex: "/(.*)"
        target_label: container
        replacement: "$1"
      - source_labels: [__meta_docker_container_label_com_docker_compose_service]
        target_label: service
      - source_labels: [__meta_docker_container_label_com_docker_compose_project]
        target_label: compose_project
      - source_labels: [__meta_docker_container_id]
        target_label: container_id
      - source_labels: [__meta_docker_container_log_path]
        target_label: filename
      - source_labels: [__meta_docker_container_log_path]
        target_label: __path__
    pipeline_stages:
      - docker: {}
YAML
          cat >> /opt/app/src/infra/docker/docker-compose.override.yml <<'YAML'
  promtail:
    image: grafana/promtail:3.0.0
    command: -config.file=/etc/promtail/config.yml
    volumes:
      - /opt/app/obs/promtail-config.yml:/etc/promtail/config.yml:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /var/log:/var/log:ro
    restart: unless-stopped
YAML
        fi
        if [[ "$${NO_SQL_CRED}" == "true" ]]; then
          if ! grep -q '^CLOUD_SQL_CREDENTIALS=' "$${ENV_RUNTIME}"; then
            printf 'CLOUD_SQL_CREDENTIALS=%s\n' "/opt/app/secrets/cloudsql.json" >> "$${ENV_RUNTIME}"
          fi
        fi
        chmod 0644 "$${ENV_RUNTIME}"
        ENV_FILE_FLAG="--env-file $${ENV_RUNTIME}"
        if [[ "$${NO_SQL_CRED}" == "true" ]]; then
          cat >> /opt/app/src/infra/docker/docker-compose.override.yml <<'YAML'
  cloud-sql-proxy:
    command:
      - "--address=0.0.0.0"
      - "--port=5432"
      - "$${CLOUD_SQL_INSTANCE}"
    volumes: []
YAML
        fi
        docker compose $${ENV_FILE_FLAG} -f infra/docker/docker-compose.local.yml -f infra/docker/docker-compose.override.yml up --build -d
        if [[ "$${ENABLE_SQL}" == "true" ]]; then
          docker compose $${ENV_FILE_FLAG} -f infra/docker/docker-compose.local.yml -f infra/docker/docker-compose.override.yml up -d cloud-sql-proxy
          MIGRATION_URL="postgresql+psycopg2://${var.db_user}:${var.db_password}@cloud-sql-proxy:5432/${var.db_name}"
          for ((i=1; i<=10; i++)); do
            docker run --rm --network docker_default \
              -v /opt/app/src:/app -w /app \
              -e DATABASE_URL="$${MIGRATION_URL}" \
              python:3.11-slim \
              bash -lc "python -c 'import socket; socket.gethostbyname(\"cloud-sql-proxy\"); print(\"dns_ok\")' && pip install -q alembic psycopg2-binary && alembic -c /app/infra/db/alembic.ini upgrade head" \
              && break
            echo "Waiting for DB/migrations ($i/10)"
            sleep 10
          done
        fi
      else
        wait_for_object "${local.compose_object_name}"
        gcs_download "${local.effective_bundle_bucket}" "${local.compose_object_name}" /opt/app/docker-compose.yml
        cd /opt/app
        docker compose up -d
      fi
    fi
    echo "Startup script end: $(date -Is)"
  EOT

  depends_on = [
    google_project_service.compute,
    google_storage_bucket.dataset,
    google_storage_bucket_object.compose,
    google_storage_bucket_object.app_bundle,
  ]
}
