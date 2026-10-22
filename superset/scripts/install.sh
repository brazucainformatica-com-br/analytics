#!/usr/bin/env bash
# Instalação/atualização do LineaSuite BI (Apache Superset) no srv1 — Ubuntu 24.04, como root.
#
#   bash install.sh deps      # Docker + Compose + ImageMagick
#   bash install.sh config    # copia arquivos para /opt/lineasuite-bi, gera .env e logos
#   bash install.sh erp       # schema erp_bi (views do ERP) e usuário bi_ro
#   bash install.sh build     # escolhe a imagem oficial e compila a imagem própria
#   bash install.sh start     # sobe banco, Redis, inicialização e aplicação
#   bash install.sh data      # conecta o ERP e cria os datasets + regra base de RLS
#   bash install.sh backup    # agenda backup diário dos metadados
#   bash install.sh all       # tudo acima, em ordem
#
# Idempotente: pode ser executado de novo para atualizar. Nunca sobrescreve o .env existente.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="/opt/lineasuite-bi"
CRED="/root/bi-credenciais.txt"
ERP_CRED="/root/bi-erp-credenciais.txt"
SOCK="/run/mysqld/mysqld.sock"
ASSETS_SRC="https://brazucainformatica.com.br/wp-content/uploads"

say() { printf '\n\033[1;34m== %s ==\033[0m\n' "$*"; }
die() { printf '\033[1;31mERRO: %s\033[0m\n' "$*"; exit 1; }
[[ $EUID -eq 0 ]] || die "execute como root"
dc() { (cd "$APP_DIR" && docker compose "$@"); }

step_deps() {
  say "Dependências"
  export DEBIAN_FRONTEND=noninteractive
  if ! command -v docker >/dev/null; then
    apt-get update -qq
    apt-get install -y -qq docker.io docker-compose-v2 docker-buildx >/dev/null
  fi
  command -v convert >/dev/null || apt-get install -y -qq imagemagick >/dev/null
  systemctl enable --now docker >/dev/null
  docker --version; docker compose version
  [[ -S "$SOCK" ]] || die "socket da MariaDB não encontrado em $SOCK"
  echo "socket MariaDB: ok"
}

step_config() {
  say "Arquivos em $APP_DIR"
  mkdir -p "$APP_DIR"/{config,scripts,assets}
  [[ "$SRC_DIR" != "$APP_DIR" ]] || die "execute a partir do clone do repositório, não de $APP_DIR"
  cp "$SRC_DIR/Dockerfile" "$SRC_DIR/docker-compose.yml" "$APP_DIR/"
  cp "$SRC_DIR"/config/*.py "$SRC_DIR"/config/*.sh "$APP_DIR/config/"
  cp "$SRC_DIR"/scripts/*.sh "$APP_DIR/scripts/"
  chmod 755 "$APP_DIR/config/init.sh" "$APP_DIR"/scripts/*.sh
  chmod 644 "$APP_DIR"/config/*.py

  if [[ ! -f "$APP_DIR/.env" ]]; then
    say "Gerando .env com segredos aleatórios"
    local admin_pw; admin_pw="$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)Aa1!"
    ( umask 077; cat > "$APP_DIR/.env" <<EOF
# LineaSuite BI — gerado em $(date -Is). NÃO versionar.
SUPERSET_VERSION=6.1.0
SUPERSET_IMAGE=apache/superset:6.1.0
BI_PUBLIC_URL=https://bi.lineasuite.com.br
BI_APP_NAME=Analytics
BI_PORT=8088
BI_EMBED_ENABLED=true
BI_EMBED_ANCESTORS=https://*.lineasuite.com https://*.lineasuite.com.br https://lineasuite.com https://lineasuite.com.br
BI_SESSION_HOURS=8
BI_DATA_CACHE_SECONDS=600
TZ=America/Cuiaba

SUPERSET_SECRET_KEY=$(openssl rand -base64 48 | tr -d '\n')
GUEST_TOKEN_JWT_SECRET=$(openssl rand -hex 32)
POSTGRES_PASSWORD=$(openssl rand -hex 24)

ADMIN_USERNAME=lucas
ADMIN_FIRSTNAME=Lucas
ADMIN_LASTNAME=Fernando
ADMIN_EMAIL=lucas.fernando@brazucainformatica.com.br
ADMIN_PASSWORD=$admin_pw

# Preenchido pela etapa "erp"
ERP_BI_URI=

# Gunicorn (4 vCPU compartilhadas com ERP e sites)
SERVER_WORKER_AMOUNT=3
SERVER_THREADS_AMOUNT=20
GUNICORN_TIMEOUT=120
CELERY_CONCURRENCY=2

# SMTP para relatórios agendados (vazio = modo de teste, nada é enviado)
SMTP_HOST=smtp.office365.com
SMTP_PORT=587
SMTP_STARTTLS=true
SMTP_SSL=false
SMTP_USER=
SMTP_PASSWORD=
SMTP_MAIL_FROM=bi@lineasuite.com.br

# SSO Microsoft Entra ID (opcional; ao preencher, o login por senha é desativado)
ENTRA_TENANT_ID=
ENTRA_CLIENT_ID=
ENTRA_CLIENT_SECRET=
EOF
    )
    ( umask 077; printf 'LineaSuite BI — https://bi.lineasuite.com.br\nUsuario: lucas\nSenha inicial: %s\n' "$admin_pw" > "$CRED" )
    echo ".env criado (600). Senha inicial do administrador em $CRED"
  else
    echo ".env existente preservado"
  fi

  say "Logos e ícones da Brazuca"
  local out="$APP_DIR/assets" tmp; tmp="$(mktemp -d)"
  if [[ ! -s "$out/logo.png" ]]; then
    curl -fsSL -o "$tmp/logo.png"  "$ASSETS_SRC/2026/06/logo-1.png"
    curl -fsSL -o "$tmp/fav32.png" "$ASSETS_SRC/2026/06/cropped-favicon-brazuca-32x32.png"
    curl -fsSL -o "$tmp/fav180.png" "$ASSETS_SRC/2026/06/cropped-favicon-brazuca-180x180.png"
    local w h; w=$(identify -format '%w' "$tmp/logo.png"); h=$(identify -format '%h' "$tmp/logo.png")
    convert "$tmp/logo.png" -alpha set -fuzz 10% -fill none \
      -draw "color 0,0 floodfill" -draw "color $((w-1)),0 floodfill" \
      -draw "color 0,$((h-1)) floodfill" -draw "color $((w-1)),$((h-1)) floodfill" \
      -trim +repage -resize 'x112>' "$out/logo.png"
    cp "$tmp/fav32.png" "$out/favicon.png"
    cp "$tmp/fav180.png" "$out/apple-touch-icon.png"
  fi
  rm -rf "$tmp"
  chmod 644 "$out"/*
  ls -l "$out"
}

step_erp() {
  say "Camada de leitura do ERP (schema erp_bi)"
  if [[ -f "$ERP_CRED" ]]; then
    bash "$APP_DIR/scripts/erp-bi-views.sh"
  else
    bash "$APP_DIR/scripts/erp-bi-views.sh" --new-user
  fi
  local pw; pw="$(awk -F': ' '/^Senha/{print $2}' "$ERP_CRED")"
  [[ -n "$pw" ]] || die "senha do bi_ro não encontrada em $ERP_CRED"
  local uri="mysql+pymysql://bi_ro:${pw}@localhost/erp_bi?unix_socket=${SOCK}&charset=utf8mb4"
  sed -i "s#^ERP_BI_URI=.*#ERP_BI_URI=${uri}#" "$APP_DIR/.env"
  echo "ERP_BI_URI gravada no .env"
}

step_build() {
  say "Imagem base oficial"
  local version img chosen=""
  version="$(awk -F= '/^SUPERSET_VERSION=/{print $2}' "$APP_DIR/.env")"
  for img in "apache/superset:${version}" "apache/superset:${version}-py311"; do
    if docker manifest inspect "$img" >/dev/null 2>&1; then chosen="$img"; break; fi
    echo "indisponível: $img"
  done
  [[ -n "$chosen" ]] || die "nenhuma imagem oficial ${version} encontrada no Docker Hub"
  sed -i "s#^SUPERSET_IMAGE=.*#SUPERSET_IMAGE=${chosen}#" "$APP_DIR/.env"
  echo "base: $chosen"
  say "Compilando a imagem lineasuite-bi:${version} (5 a 15 minutos)"
  dc build --pull
  dc pull db redis
}

step_start() {
  say "Subindo banco e Redis"
  dc up -d db redis
  say "Inicialização (migrações, papéis, administrador, tema)"
  dc --profile init run --rm superset-init
  say "Subindo aplicação, worker e agendador"
  dc up -d superset superset-worker superset-beat
  echo "aguardando a aplicação responder..."
  for _ in $(seq 1 40); do
    if curl -fsS -m 5 http://127.0.0.1:8088/health >/dev/null 2>&1; then break; fi
    sleep 5
  done
  printf 'health: '; curl -fsS -m 5 http://127.0.0.1:8088/health || echo "sem resposta"
  echo; dc ps --format 'table {{.Name}}\t{{.Status}}'
}

step_data() {
  say "Conectando o ERP e criando datasets"
  grep -q '^ERP_BI_URI=mysql' "$APP_DIR/.env" || die "rode a etapa 'erp' antes"
  dc up -d superset  # recarrega o .env se a URI acabou de ser gravada
  dc exec -T superset python /app/pythonpath/bi_admin.py database
  dc exec -T superset python /app/pythonpath/bi_admin.py sync-datasets
  dc exec -T superset python /app/pythonpath/bi_admin.py status
}

step_backup() {
  say "Backup diário dos metadados"
  cat > /etc/cron.d/lineasuite-bi <<EOF
# LineaSuite BI: dump dos metadados do Superset e cópia do .env (retenção de 14 dias)
30 2 * * * root bash $APP_DIR/scripts/backup.sh >> /var/log/lineasuite-bi-backup.log 2>&1
EOF
  chmod 644 /etc/cron.d/lineasuite-bi
  bash "$APP_DIR/scripts/backup.sh"
}

case "${1:-all}" in
  deps) step_deps ;;
  config) step_config ;;
  erp) step_erp ;;
  build) step_build ;;
  start) step_start ;;
  data) step_data ;;
  backup) step_backup ;;
  all) step_deps; step_config; step_erp; step_build; step_start; step_data; step_backup ;;
  *) die "etapa desconhecida: $1" ;;
esac
