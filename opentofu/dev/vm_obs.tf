resource "google_compute_firewall" "obs_grafana_ingress" {
  count   = var.enable_observability ? 1 : 0
  name    = "${var.obs_vm_name}-grafana-ingress"
  project = var.project_id
  network = "default"

  allow {
    protocol = "tcp"
    ports    = [tostring(var.obs_grafana_port)]
  }

  source_ranges = var.obs_grafana_source_ranges
  target_tags   = [var.obs_vm_network_tag]

  depends_on = [google_project_service.compute]
}

data "google_compute_subnetwork" "default" {
  count   = var.enable_observability ? 1 : 0
  name    = "default"
  project = var.project_id
  region  = var.location
}

resource "google_compute_address" "obs_internal_ip" {
  count        = var.enable_observability ? 1 : 0
  name         = "${var.obs_vm_name}-internal-ip"
  project      = var.project_id
  region       = var.location
  address_type = "INTERNAL"
  subnetwork   = data.google_compute_subnetwork.default[0].self_link
}

resource "google_compute_instance" "obs_vm" {
  count               = var.enable_observability ? 1 : 0
  name                = var.obs_vm_name
  project             = var.project_id
  zone                = var.obs_vm_zone
  machine_type        = var.obs_vm_machine_type
  tags                = [var.obs_vm_network_tag]
  deletion_protection = false

  boot_disk {
    initialize_params {
      image = var.obs_vm_boot_image
      size  = var.obs_vm_boot_disk_size_gb
      type  = var.obs_vm_boot_disk_type
    }
  }

  network_interface {
    network    = "default"
    subnetwork = data.google_compute_subnetwork.default[0].self_link
    network_ip = google_compute_address.obs_internal_ip[0].address
    access_config {}
  }

  metadata_startup_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    exec > >(tee -a /var/log/obs-startup.log) 2>&1
    echo "Observability startup begin: $(date -Is)"
    export DEBIAN_FRONTEND=noninteractive
    export APT_LISTCHANGES_FRONTEND=none

    apt-get update -y
    apt-get install -y --no-install-recommends ca-certificates curl gnupg
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

    mkdir -p /opt/obs
    mkdir -p /opt/obs/loki-data
    cat > /opt/obs/prometheus.yml <<'YAML'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ['prometheus:9090']
  - job_name: node
    static_configs:
      - targets: ['node-exporter:9100']
  - job_name: cadvisor
    static_configs:
      - targets: ['cadvisor:8080']
YAML

    cat > /opt/obs/loki-config.yml <<'YAML'
auth_enabled: false

server:
  http_listen_port: 3100

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  volume_enabled: true
YAML

    mkdir -p /opt/obs/grafana/provisioning/datasources
    mkdir -p /opt/obs/grafana/provisioning/dashboards
    mkdir -p /opt/obs/grafana/dashboards

    cat > /opt/obs/grafana/provisioning/datasources/datasource.yaml <<'YAML'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    uid: prometheus
    url: http://prometheus:9090
    isDefault: true
  - name: Loki
    type: loki
    access: proxy
    uid: loki
    url: http://loki:3100
    isDefault: false
YAML

    cat > /opt/obs/grafana/provisioning/dashboards/provider.yaml <<'YAML'
apiVersion: 1
providers:
  - name: default
    orgId: 1
    folder: ""
    type: file
    disableDeletion: true
    editable: false
    options:
      path: /var/lib/grafana/dashboards
YAML

    curl -fsSL "https://grafana.com/api/dashboards/1860/revisions/latest/download" \
      -o /opt/obs/grafana/dashboards/node-exporter.json
    curl -fsSL "https://grafana.com/api/dashboards/893/revisions/latest/download" \
      -o /opt/obs/grafana/dashboards/cadvisor.json
    python3 - /opt/obs/grafana/dashboards/node-exporter.json /opt/obs/grafana/dashboards/cadvisor.json <<'PY'
import json
import sys

def fix(path):
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    # Replace datasource variables commonly used in grafana.com dashboards
    def walk(obj):
        if isinstance(obj, dict):
            for k, v in list(obj.items()):
                if k == "datasource":
                    if isinstance(v, str) and v in ("$${DS_PROMETHEUS}", "$${DS_PROMETHEUS}", "$DS_PROMETHEUS"):
                        obj[k] = {"type": "prometheus", "uid": "prometheus"}
                    elif isinstance(v, dict) and v.get("type") == "prometheus":
                        obj[k].setdefault("uid", "prometheus")
                else:
                    walk(v)
        elif isinstance(obj, list):
            for item in obj:
                walk(item)
    walk(data)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh)

for p in sys.argv[1:]:
    fix(p)
PY
    cat > /opt/obs/grafana/dashboards/api-gateway-logs.json <<'JSON'
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": {
          "type": "grafana",
          "uid": "-- Grafana --"
        },
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Annotations & Alerts",
        "type": "dashboard"
      }
    ]
  },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 0,
  "id": 1,
  "links": [],
  "panels": [
    {
      "datasource": {
        "type": "loki",
        "uid": "loki"
      },
      "fieldConfig": {
        "defaults": {},
        "overrides": []
      },
      "gridPos": {
        "h": 10,
        "w": 24,
        "x": 0,
        "y": 0
      },
      "id": 1,
      "options": {
        "dedupStrategy": "none",
        "enableInfiniteScrolling": false,
        "enableLogDetails": true,
        "prettifyLogMessage": true,
        "showCommonLabels": false,
        "showLabels": false,
        "showTime": true,
        "sortOrder": "Descending",
        "wrapLogMessage": true
      },
      "pluginVersion": "11.5.2",
      "targets": [
        {
          "direction": "backward",
          "editorMode": "code",
          "expr": "{host=\"cv-app-vm\", service=\"api-gateway\"}",
          "queryType": "range",
          "refId": "A"
        }
      ],
      "title": "api-gateway logs",
      "type": "logs"
    },
    {
      "datasource": {
        "type": "loki",
        "uid": "loki"
      },
      "fieldConfig": {
        "defaults": {},
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 24,
        "x": 0,
        "y": 10
      },
      "id": 3,
      "options": {
        "dedupStrategy": "none",
        "enableInfiniteScrolling": false,
        "enableLogDetails": true,
        "prettifyLogMessage": false,
        "showCommonLabels": false,
        "showLabels": false,
        "showTime": true,
        "sortOrder": "Ascending",
        "wrapLogMessage": false
      },
      "pluginVersion": "11.5.2",
      "targets": [
        {
          "datasource": {
            "type": "loki",
            "uid": "loki"
          },
          "direction": "forward",
          "editorMode": "code",
          "expr": "{host=\"cv-app-vm\", service=\"training-worker\"}",
          "queryType": "range",
          "refId": "A"
        }
      ],
      "title": "Training Worker",
      "type": "logs"
    },
    {
      "datasource": {
        "type": "loki",
        "uid": "loki"
      },
      "fieldConfig": {
        "defaults": {},
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 24,
        "x": 0,
        "y": 18
      },
      "id": 2,
      "options": {
        "dedupStrategy": "none",
        "enableInfiniteScrolling": false,
        "enableLogDetails": true,
        "prettifyLogMessage": false,
        "showCommonLabels": false,
        "showLabels": false,
        "showTime": true,
        "sortOrder": "Ascending",
        "wrapLogMessage": false
      },
      "pluginVersion": "11.5.2",
      "targets": [
        {
          "datasource": {
            "type": "loki",
            "uid": "loki"
          },
          "direction": "forward",
          "editorMode": "code",
          "expr": "{host=\"cv-app-vm\", service=\"model-serving\"}",
          "queryType": "range",
          "refId": "A"
        }
      ],
      "title": "Model Serving",
      "type": "logs"
    },
    {
      "datasource": {
        "type": "loki",
        "uid": "loki"
      },
      "fieldConfig": {
        "defaults": {},
        "overrides": []
      },
      "gridPos": {
        "h": 8,
        "w": 24,
        "x": 0,
        "y": 26
      },
      "id": 4,
      "options": {
        "dedupStrategy": "none",
        "enableInfiniteScrolling": false,
        "enableLogDetails": true,
        "prettifyLogMessage": true,
        "showCommonLabels": false,
        "showLabels": false,
        "showTime": true,
        "sortOrder": "Ascending",
        "wrapLogMessage": false
      },
      "pluginVersion": "11.5.2",
      "targets": [
        {
          "datasource": {
            "type": "loki",
            "uid": "loki"
          },
          "direction": "forward",
          "editorMode": "code",
          "expr": "{host=\"cv-app-vm\", service=\"model-registry\"}",
          "queryType": "range",
          "refId": "A"
        }
      ],
      "title": "Model Registry",
      "type": "logs"
    }
  ],
  "preload": false,
  "schemaVersion": 40,
  "tags": [
    "logs",
    "api-gateway"
  ],
  "templating": {
    "list": []
  },
  "time": {
    "from": "now-15m",
    "to": "now"
  },
  "timepicker": {},
  "timezone": "",
  "title": "API Gateway Logs",
  "uid": "api-gateway-logs",
  "version": 1,
  "weekStart": ""
}
JSON

    GRAFANA_ADMIN_PASSWORD="${var.obs_grafana_admin_password}"
    GRAFANA_PORT="${var.obs_grafana_port}"

    # Ensure Loki data directory exists with permissive ownership to avoid startup errors
    mkdir -p /opt/obs/loki-data/rules
    chmod -R 777 /opt/obs/loki-data

    cat > /opt/obs/docker-compose.yml <<YAML
services:
  prometheus:
    image: prom/prometheus:v2.54.1
    command:
      - --config.file=/etc/prometheus/prometheus.yml
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
    restart: unless-stopped

  loki:
    image: grafana/loki:3.0.0
    command:
      - -config.file=/etc/loki/config.yml
    volumes:
      - ./loki-config.yml:/etc/loki/config.yml:ro
      - ./loki-data:/loki
    ports:
      - "3100:3100"
    restart: unless-stopped

  grafana:
    image: grafana/grafana:11.5.2
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=$${GRAFANA_ADMIN_PASSWORD}
      - GF_USERS_ALLOW_SIGN_UP=false
    ports:
      - "$${GRAFANA_PORT}:3000"
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
    depends_on:
      - prometheus
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:v1.8.1
    restart: unless-stopped

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.49.1
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:rw
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    restart: unless-stopped
YAML

    cd /opt/obs
    docker compose up -d
    echo "Observability startup end: $(date -Is)"
  EOT

  depends_on = [
    google_project_service.compute,
    google_compute_firewall.obs_grafana_ingress,
  ]
}
