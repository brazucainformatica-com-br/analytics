#!/usr/bin/env bash
# Inicialização/atualização do LineaSuite BI. Idempotente: pode rodar a cada atualização de versão.
#   docker compose --profile init run --rm superset-init
set -euo pipefail

echo "[1/4] Migrações do banco de metadados"
superset db upgrade

echo "[2/4] Papéis e permissões padrão"
superset init

echo "[3/4] Administrador"
if [[ -n "${ADMIN_PASSWORD:-}" ]]; then
  superset fab create-admin \
    --username "${ADMIN_USERNAME:-admin}" \
    --firstname "${ADMIN_FIRSTNAME:-Admin}" \
    --lastname "${ADMIN_LASTNAME:-BI}" \
    --email "${ADMIN_EMAIL:-admin@lineasuite.com.br}" \
    --password "${ADMIN_PASSWORD}" || true
else
  echo "ADMIN_PASSWORD vazio: administrador não criado nesta execução"
fi

echo "[4/4] Papéis do LineaSuite, tema e modelo de CSS"
python /app/pythonpath/bi_admin.py bootstrap

echo "Inicialização concluída."
