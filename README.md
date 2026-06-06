# OpenTofu — GCS Computer Vision Infra

Módulo OpenTofu que crea y despliega toda la infraestructura GCP necesaria para la plataforma de visión por computadora.

## Infraestructura provisionada

- **GCS bucket** — datasets y artefactos del modelo
- **Cloud SQL Postgres** — base de datos de la plataforma
- **Service Accounts** — permisos granulares para cada componente
- **Secret Manager** — `GCP_SA_B64`, `VAST_SSH_KEY`, `VAST_API_KEY`, `DB_PASSWORD`
- **VM de aplicación** — startup script que levanta los servicios con Docker Compose
- **CI/CD** — Workload Identity Federation para GitHub Actions (sin SA keys en el repo)

## Arquitectura del proyecto

![Diagrama de arquitectura](image.png)

## Requisitos

- OpenTofu >= 1.6
- `gcloud` CLI autenticado en el proyecto GCP
- Acceso a Vast.ai (API key + SSH key)
- Dataset `taco.tar.gz` disponible en `dataset/`

## Deploy completo (paso a paso)

### 1. Clave SSH para Vast.ai (una sola vez)

```powershell
.\opentofu\dev\scripts\vast_ssh_setup.ps1 -Project unlu-genai-serranodavid
```

La clave pública resultante debe cargarse manualmente en **Vast.ai → Account → SSH Keys** (paso manual único, no se repite en cada deploy).

### 2. Crear Secrets en GCP Secret Manager

#### VAST_API_KEY

```powershell
$apiKey = Read-Host "Ingresá tu Vast.ai API Key" -AsSecureString
$plain  = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($apiKey))
$tmp = New-TemporaryFile
$plain | Set-Content -NoNewline $tmp
gcloud secrets create VAST_API_KEY --replication-policy=automatic --project unlu-genai-serranodavid 2>$null
gcloud secrets versions add VAST_API_KEY --data-file $tmp --project unlu-genai-serranodavid
Remove-Item $tmp
```

#### DB_PASSWORD

```powershell
$dbPass = Read-Host "Ingresá la contraseña de la BD" -AsSecureString
$plain  = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($dbPass))
$tmp = New-TemporaryFile
$plain | Set-Content -NoNewline $tmp
gcloud secrets create DB_PASSWORD --replication-policy=automatic --project unlu-genai-serranodavid 2>$null
gcloud secrets versions add DB_PASSWORD --data-file $tmp --project unlu-genai-serranodavid
Remove-Item $tmp
```

> `GCP_SA_B64` se crea automáticamente por OpenTofu.

### 3. Bundle de la app

```powershell
# Desde la raíz del monorepo (d:\Diplomatura-IA\TpFinal4)
tar -czf app_bundle.tar.gz cv-cloudgpu-platform/
```

### 4. Aplicar OpenTofu

```bash
cd opentofu/dev
tofu init      # primera vez
tofu apply
```

### 5. Verificar startup de la VM

```bash
# Conectarse por SSH a la VM de aplicación
gcloud compute ssh cv-app-vm --project unlu-genai-serranodavid --zone us-central1-a

# Revisar el log de startup
sudo tail -n 200 /var/log/startup-script.log
```

## Validaciones rápidas en la VM

```bash
# Secret GCP presente
sudo ls -l /opt/app/secrets/gcp.json
sudo head -c 30 /opt/app/secrets/gcp.json

# Clave SSH de Vast.ai válida
sudo ssh-keygen -yf /opt/app/secrets/vast_ed25519 >/dev/null && echo HOST_OK || echo HOST_FAIL

# Clave SSH dentro del container training-worker
cd /opt/app/src
docker compose -f infra/docker/docker-compose.local.yml -f infra/docker/docker-compose.override.yml \
  exec -T training-worker sh -lc 'ssh-keygen -yf /root/.ssh/id_ed25519 >/dev/null && echo CT_OK || echo CT_FAIL'
```

## Secrets en runtime

| Secret | Cómo se usa |
|--------|-------------|
| `GCP_SA_B64` | OpenTofu lo crea; se transforma en `/opt/app/secrets/gcp.json` en la VM |
| `VAST_SSH_KEY` | Se escribe en `/opt/app/secrets/vast_ed25519` |
| `VAST_API_KEY` | Se inyecta como variable de entorno al runtime |
| `DB_PASSWORD` | Se lee en runtime para construir `DATABASE_URL` y ejecutar migraciones |

## Cambios en el código de la app

```bash
# 1. Regenerar el bundle
tar -czf app_bundle.tar.gz cv-cloudgpu-platform/

# 2. Re-aplicar para que la VM descargue el nuevo bundle
cd opentofu/dev
tofu apply
```

## Observabilidad

El stack Grafana + Loki + Prometheus corre **dentro del cluster Kubernetes** (no en una VM separada).
Ver la sección Observabilidad en el [README de cv-cloudgpu-platform](../cv-cloudgpu-platform/README.md).

## Conectar a Cloud SQL desde pgAdmin

1. Ir a **Cloud SQL → Instancia → Conexiones** → Agregar tu IP pública en "Redes autorizadas".
2. En pgAdmin usar:
   - Host: IP pública de la instancia Cloud SQL
   - Puerto: `5432`
   - DB: `computer-vision`
   - Usuario: valor de `db_user` en `terraform.tfvars`
   - Password: secreto `DB_PASSWORD` en Secret Manager

## CI/CD — Workload Identity Federation

GitHub Actions usa Workload Identity Federation para autenticarse en GCP **sin SA keys en el repositorio**. El workflow `.github/workflows/opentofu-destroy.yml` usa `google-github-actions/auth` con el provider y service account creados por OpenTofu.

## Destruir toda la infraestructura

```bash
# Preservar el secreto GCP_SA_B64 (evita perder el SA key)
tofu state rm -- \
  google_secret_manager_secret.gcp_sa_b64[0] \
  google_secret_manager_secret_version.gcp_sa_b64[0]

tofu destroy
```
