#!/usr/bin/env bash
# Isolamento por cliente para o Analytics: cria (ou atualiza) um schema de views
# somente leitura do ERP LineaSuite filtrado por empresa (company_id).
#
#   erp_rpt_c<ID>          schema com uma view por tabela do ERP, filtrada pela empresa
#   mb_rpt_c<ID>@127.0.0.1 usuario MariaDB com SELECT apenas nesse schema
#
# As views usam SQL SECURITY DEFINER com o usuario somente leitura mb_ro_erp, entao
# o usuario do cliente nunca acessa erp_lineasuite diretamente.
#
# Uso (como root no servidor):  bash erp-views.sh <company_id> [--new-user]
#   --new-user  cria o usuario do cliente e grava a senha em /root/analytics-c<ID>.txt (modo 600)
# Rodar de novo apos atualizacoes do ERP recria as views (idempotente).
set -euo pipefail

CID="${1:?informe o company_id}"; [[ "$CID" =~ ^[0-9]+$ ]] || { echo "company_id invalido"; exit 1; }
NEW_USER="${2:-}"
SRC="erp_lineasuite"
DST="erp_rpt_c${CID}"
DEFINER='`mb_ro_erp`@`127.0.0.1`'
SQL="$(mktemp)"; trap 'rm -f "$SQL"' EXIT

# Tabelas que nunca entram (credenciais, sessoes, configuracoes e controles internos)
EXCLUDE="asaas_config audit_log company_licenses lgpd_requests login_attempts mail_accounts nfse_config password_resets settings user_sessions user_totp_codes wa_link_codes wa_sessions license_plans roles task_runs companies users"
# Colunas que nunca entram (segredos)
SECRET_RX='password|passwd|secret|(^|_)token($|_)|api_?key|private|totp|_hash$|^hash$|webhook'

# Tabelas filhas sem company_id: tabela -> coluna de ligacao:tabela pai
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
# Tabelas de referencia globais (tabelas fiscais, sem dados de cliente)
GLOBAL="rt_aliquotas rt_class_trib rt_cst"

q() { mysql -N -B -e "$1"; }

[[ "$(q "SELECT COUNT(*) FROM $SRC.companies WHERE id=$CID")" == 1 ]] || { echo "empresa $CID nao existe"; exit 1; }

cols_of() {  # colunas permitidas de uma tabela, ja com crase e prefixo t.
  q "SELECT GROUP_CONCAT(CONCAT('t.\`',column_name,'\`') ORDER BY ordinal_position)
     FROM information_schema.columns
     WHERE table_schema='$SRC' AND table_name='$1' AND column_name NOT REGEXP '$SECRET_RX'"
}

{
  echo "CREATE DATABASE IF NOT EXISTS \`$DST\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  # remove views antigas para refletir tabelas removidas do ERP
  q "SELECT CONCAT('DROP VIEW IF EXISTS \`$DST\`.\`',table_name,'\`;') FROM information_schema.views WHERE table_schema='$DST'"

  for t in $(q "SELECT table_name FROM information_schema.tables WHERE table_schema='$SRC' AND table_type='BASE TABLE' ORDER BY table_name"); do
    [[ " $EXCLUDE " == *" $t "* ]] && continue
    head="CREATE OR REPLACE ALGORITHM=MERGE DEFINER=$DEFINER SQL SECURITY DEFINER VIEW \`$DST\`.\`$t\` AS SELECT"
    has_cid=$(q "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema='$SRC' AND table_name='$t' AND column_name='company_id'")
    if [[ "$has_cid" == 1 ]]; then
      echo "$head $(cols_of "$t") FROM \`$SRC\`.\`$t\` t WHERE t.company_id=$CID;"
    elif [[ -n "${CHILD[$t]:-}" ]]; then
      fk="${CHILD[$t]%%:*}"; parent="${CHILD[$t]##*:}"
      echo "$head $(cols_of "$t") FROM \`$SRC\`.\`$t\` t JOIN \`$SRC\`.\`$parent\` p ON p.id=t.\`$fk\` WHERE p.company_id=$CID;"
    elif [[ " $GLOBAL " == *" $t "* ]]; then
      echo "$head $(cols_of "$t") FROM \`$SRC\`.\`$t\` t;"
    else
      echo "-- ignorada (sem company_id e sem regra): $t" >&2
    fi
  done

  # dados basicos da propria empresa e nomes de usuarios (sem e-mail, senha ou perfil)
  echo "CREATE OR REPLACE DEFINER=$DEFINER SQL SECURITY DEFINER VIEW \`$DST\`.\`companies\` AS SELECT t.id, t.name, t.trade_name, t.document, t.city, t.state FROM \`$SRC\`.\`companies\` t WHERE t.id=$CID;"
  echo "CREATE OR REPLACE DEFINER=$DEFINER SQL SECURITY DEFINER VIEW \`$DST\`.\`users\` AS SELECT t.id, t.name FROM \`$SRC\`.\`users\` t WHERE t.company_id=$CID;"

  if [[ "$NEW_USER" == "--new-user" ]]; then
    PW="$(openssl rand -hex 20)"
    echo "CREATE USER IF NOT EXISTS 'mb_rpt_c${CID}'@'127.0.0.1' IDENTIFIED BY '$PW';"
    ( umask 077; printf 'Usuario: mb_rpt_c%s\nHost: 127.0.0.1  Porta: 3306\nBanco: %s\nSenha: %s\n' "$CID" "$DST" "$PW" > "/root/analytics-c${CID}.txt" )
  fi
  echo "GRANT SELECT, SHOW VIEW ON \`$DST\`.* TO 'mb_rpt_c${CID}'@'127.0.0.1';"
  echo "FLUSH PRIVILEGES;"
} > "$SQL"

mysql < "$SQL"
echo "schema $DST: $(q "SELECT COUNT(*) FROM information_schema.views WHERE table_schema='$DST'") views"
[[ "$NEW_USER" == "--new-user" ]] && echo "credenciais em /root/analytics-c${CID}.txt"
exit 0
