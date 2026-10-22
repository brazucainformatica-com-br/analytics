#!/usr/bin/env bash
# Camada de leitura do ERP para o LineaSuite BI (Superset).
#
# Cria/atualiza o schema erp_bi com uma view por tabela do ERP, SEM filtrar por empresa,
# mas garantindo a coluna company_id em todas as views. O isolamento entre clientes é feito
# no Superset por RLS (regra "company_id = <id>"), e não por schema separado.
#
#   erp_bi                schema só de views (SQL SECURITY DEFINER com mb_ro_erp)
#   bi_ro@localhost       usuário MariaDB com SELECT apenas em erp_bi (acesso pelo socket Unix)
#
# Fora das views: tabelas de credenciais/sessões/configuração e colunas com segredos.
# Uso (root no srv1):  bash erp-bi-views.sh [--new-user]
#   --new-user  cria o usuário bi_ro e grava a senha em /root/bi-erp-credenciais.txt (modo 600)
# Rodar de novo após atualizações do ERP recria as views (idempotente).
set -euo pipefail

NEW_USER="${1:-}"
SRC="erp_lineasuite"
DST="erp_bi"
DEFINER='`mb_ro_erp`@`127.0.0.1`'
SQL="$(mktemp)"; trap 'rm -f "$SQL"' EXIT

EXCLUDE="asaas_config audit_log company_licenses lgpd_requests login_attempts mail_accounts nfse_config password_resets settings user_sessions user_totp_codes wa_link_codes wa_sessions license_plans roles task_runs companies users"
SECRET_RX='password|passwd|secret|(^|_)token($|_)|api_?key|private|totp|_hash$|^hash$|webhook'

# Tabelas filhas sem company_id: tabela -> coluna de ligação:tabela pai
declare -A CHILD=(
  [bom_items]="bom_id:boms" [ctr_revision_items]="revision_id:ctr_revisions"
  [fiscal_doc_items]="doc_id:fiscal_docs" [fiscal_events]="doc_id:fiscal_docs"
  [inv_divergences]="campaign_id:inv_campaigns" [inv_items]="campaign_id:inv_campaigns"
  [inv_readings]="campaign_id:inv_campaigns" [maint_plan_tasks]="plan_id:maint_plans"
  [nfe_inbound_items]="inbound_id:nfe_inbound" [production_order_items]="order_id:production_orders"
  [purchase_order_items]="order_id:purchase_orders" [quote_items]="quote_id:quotes"
  [sales_order_items]="order_id:sales_orders" [service_team_members]="team_id:service_teams"
  [ticket_events]="ticket_id:tickets" [work_order_labor]="work_order_id:work_orders"
  [work_order_parts]="work_order_id:work_orders" [work_order_tasks]="work_order_id:work_orders"
)
# Tabelas de referência globais (tabelas fiscais): recebem company_id nulo e ficam fora do RLS
GLOBAL="rt_aliquotas rt_class_trib rt_cst"

q() { mysql -N -B -e "$1"; }

cols_of() {  # colunas permitidas, com crase e prefixo t.
  q "SELECT GROUP_CONCAT(CONCAT('t.\`',column_name,'\`') ORDER BY ordinal_position)
     FROM information_schema.columns
     WHERE table_schema='$SRC' AND table_name='$1' AND column_name NOT REGEXP '$SECRET_RX'"
}

skipped=()
{
  echo "CREATE DATABASE IF NOT EXISTS \`$DST\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  q "SELECT CONCAT('DROP VIEW IF EXISTS \`$DST\`.\`',table_name,'\`;') FROM information_schema.views WHERE table_schema='$DST'"

  for t in $(q "SELECT table_name FROM information_schema.tables WHERE table_schema='$SRC' AND table_type='BASE TABLE' ORDER BY table_name"); do
    [[ " $EXCLUDE " == *" $t "* ]] && continue
    head="CREATE OR REPLACE ALGORITHM=MERGE DEFINER=$DEFINER SQL SECURITY DEFINER VIEW \`$DST\`.\`$t\` AS SELECT"
    has_cid=$(q "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='$SRC' AND table_name='$t' AND column_name='company_id'")
    if [[ "$has_cid" == 1 ]]; then
      echo "$head $(cols_of "$t") FROM \`$SRC\`.\`$t\` t;"
    elif [[ -n "${CHILD[$t]:-}" ]]; then
      fk="${CHILD[$t]%%:*}"; parent="${CHILD[$t]##*:}"
      echo "$head $(cols_of "$t"), p.company_id AS company_id FROM \`$SRC\`.\`$t\` t JOIN \`$SRC\`.\`$parent\` p ON p.id=t.\`$fk\`;"
    elif [[ " $GLOBAL " == *" $t "* ]]; then
      echo "$head $(cols_of "$t"), CAST(NULL AS UNSIGNED) AS company_id FROM \`$SRC\`.\`$t\` t;"
    else
      echo "-- ignorada (sem company_id e sem regra): $t" >&2
    fi
  done

  echo "CREATE OR REPLACE DEFINER=$DEFINER SQL SECURITY DEFINER VIEW \`$DST\`.\`companies\` AS SELECT t.id, t.id AS company_id, t.name, t.trade_name, t.document, t.city, t.state FROM \`$SRC\`.\`companies\` t;"
  echo "CREATE OR REPLACE DEFINER=$DEFINER SQL SECURITY DEFINER VIEW \`$DST\`.\`users\` AS SELECT t.id, t.name, t.company_id FROM \`$SRC\`.\`users\` t;"

  if [[ "$NEW_USER" == "--new-user" ]]; then
    PW="$(openssl rand -hex 24)"
    echo "CREATE USER IF NOT EXISTS 'bi_ro'@'localhost' IDENTIFIED BY '$PW';"
    echo "ALTER USER 'bi_ro'@'localhost' IDENTIFIED BY '$PW';"
    ( umask 077; printf 'Usuario: bi_ro@localhost (socket /run/mysqld/mysqld.sock)\nBanco: %s\nSenha: %s\n' "$DST" "$PW" > /root/bi-erp-credenciais.txt )
  fi
  echo "GRANT SELECT, SHOW VIEW ON \`$DST\`.* TO 'bi_ro'@'localhost';"
  echo "FLUSH PRIVILEGES;"
} > "$SQL"

mysql < "$SQL"
echo "schema $DST: $(q "SELECT COUNT(*) FROM information_schema.views WHERE table_schema='$DST'") views"
echo "views sem company_id (deveria ser 0): $(q "SELECT COUNT(*) FROM information_schema.views v WHERE v.table_schema='$DST' AND NOT EXISTS (SELECT 1 FROM information_schema.columns c WHERE c.table_schema=v.table_schema AND c.table_name=v.table_name AND c.column_name='company_id')")"
[[ "$NEW_USER" == "--new-user" ]] && echo "credenciais em /root/bi-erp-credenciais.txt"
exit 0
