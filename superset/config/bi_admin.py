"""
Ferramenta de administração do LineaSuite BI (roda dentro do contêiner).

  docker compose exec superset python /app/pythonpath/bi_admin.py bootstrap
  docker compose exec superset python /app/pythonpath/bi_admin.py database        # usa ERP_BI_URI do .env
  docker compose exec superset python /app/pythonpath/bi_admin.py sync-datasets
  docker compose exec superset python /app/pythonpath/bi_admin.py tenant --company-id 1 --name "B&Bartoni do Brasil"
  docker compose exec superset python /app/pythonpath/bi_admin.py status

Modelo de isolamento por cliente (RLS — segurança em nível de linha):
  * Regra BASE "tenant: negar por padrão" (cláusula 1 = 0, grupo "tenant") em todos os datasets
    do banco "ERP BI". Vale para todos, exceto os papéis Admin, Alpha e Incorporado.
  * Uma regra REGULAR por cliente (cláusula company_id = <id>, mesmo grupo "tenant"),
    ligada ao papel "Cliente - <nome>".
  * Regras do mesmo grupo são combinadas com OU: (1 = 0 OR company_id = 7) => só a empresa 7.
    Quem não tem papel de cliente nem é Admin/Alpha não enxerga nenhuma linha.
  * Painéis incorporados (papel Incorporado) recebem o filtro no token de convidado emitido
    pelo backend do LineaSuite, que DEVE sempre informar a regra "company_id = <id>".
"""
from __future__ import annotations

import argparse
import os
import sys

from superset.app import create_app

app = create_app()

DB_NAME = os.environ.get("ERP_BI_DB_NAME", "ERP BI")
DB_SCHEMA = os.environ.get("ERP_BI_SCHEMA", "erp_bi")
TENANT_GROUP = "tenant"
BASE_RULE = "tenant: negar por padrão"
EXEMPT_ROLES = ("Admin", "Alpha", "Incorporado")
GUEST_ROLE = "Incorporado"
CSS_NAME = "Brazuca — Relatório"
CSS = """
/* Cartões no estilo relatório corporativo: fundo cinza, visuais brancos com sombra suave */
.dashboard-content { background: var(--ant-color-bg-layout, #F3F2F1); }
.dashboard-component-chart-holder {
  border-radius: 8px;
  box-shadow: 0 1.6px 3.6px rgba(0,0,0,.08), 0 0.3px 0.9px rgba(0,0,0,.06);
  border: 1px solid var(--ant-color-border-secondary, #EDEBE9);
}
.dashboard-component-header .header-title { font-weight: 600; letter-spacing: .1px; }
.dashboard-markdown h1, .dashboard-markdown h2 { font-weight: 600; }
"""


def _ctx():
    from superset.extensions import db, security_manager  # noqa: WPS433

    return db, security_manager


def get_database():
    db, _ = _ctx()
    from superset.models.core import Database

    return db.session.query(Database).filter_by(database_name=DB_NAME).one_or_none()


def erp_datasets():
    db, _ = _ctx()
    from superset.connectors.sqla.models import SqlaTable

    database = get_database()
    if not database:
        return []
    return db.session.query(SqlaTable).filter_by(database_id=database.id).all()


# ---------------------------------------------------------------------------
def cmd_bootstrap(_args) -> None:
    db, sm = _ctx()
    from superset.models.core import CssTemplate

    # Papel dos painéis incorporados: mesmas permissões de leitura do Gamma
    sm.copy_role("Gamma", GUEST_ROLE, merge=True)
    db.session.commit()
    print(f"papel '{GUEST_ROLE}' sincronizado com Gamma")

    css = db.session.query(CssTemplate).filter_by(template_name=CSS_NAME).one_or_none()
    if not css:
        css = CssTemplate(template_name=CSS_NAME)
        db.session.add(css)
    css.css = CSS.strip()
    db.session.commit()
    print(f"modelo de CSS '{CSS_NAME}' pronto")

    if get_database():
        _ensure_base_rule()


def cmd_database(_args) -> None:
    db, sm = _ctx()
    from superset.models.core import Database

    uri = os.environ.get("ERP_BI_URI")
    if not uri:
        sys.exit("ERP_BI_URI não definida no .env")
    database = get_database()
    if not database:
        database = Database(database_name=DB_NAME)
        db.session.add(database)
    database.set_sqlalchemy_uri(uri)
    database.expose_in_sqllab = True
    database.allow_run_async = False
    database.allow_dml = False
    database.allow_file_upload = False
    database.allow_ctas = False
    database.allow_cvas = False
    database.cache_timeout = None
    db.session.commit()
    sm.add_permission_view_menu("database_access", database.perm)
    db.session.commit()

    # teste de conexão
    from sqlalchemy import text

    with database.get_sqla_engine() as engine:
        with engine.connect() as conn:
            n = conn.execute(
                text("SELECT COUNT(*) FROM information_schema.views WHERE table_schema = :s"),
                {"s": DB_SCHEMA},
            ).scalar()
    print(f"banco '{DB_NAME}' conectado; {n} views em {DB_SCHEMA}")


def cmd_sync_datasets(_args) -> None:
    db, _ = _ctx()
    from superset.connectors.sqla.models import SqlaTable

    database = get_database()
    if not database:
        sys.exit(f"banco '{DB_NAME}' não existe; rode o comando 'database' antes")

    names = set()
    for getter in (database.get_all_view_names_in_schema, database.get_all_table_names_in_schema):
        try:
            names |= {t[0] for t in getter(catalog=None, schema=DB_SCHEMA)}
        except Exception as ex:  # noqa: BLE001
            print(f"aviso: {ex}")

    existing = {t.table_name for t in erp_datasets() if (t.schema or "") == DB_SCHEMA}
    created = 0
    for name in sorted(names - existing):
        ds = SqlaTable(table_name=name, schema=DB_SCHEMA, database=database)
        db.session.add(ds)
        db.session.flush()
        try:
            ds.fetch_metadata()
        except Exception as ex:  # noqa: BLE001
            print(f"aviso ({name}): {ex}")
        created += 1
    db.session.commit()
    print(f"datasets: {created} criados, {len(existing)} já existiam")
    _ensure_base_rule()
    _attach_all_tenant_rules()


def _rule(name: str):
    db, _ = _ctx()
    from superset.connectors.sqla.models import RowLevelSecurityFilter

    return db.session.query(RowLevelSecurityFilter).filter_by(name=name).one_or_none()


def _ensure_base_rule() -> None:
    db, sm = _ctx()
    from superset.connectors.sqla.models import RowLevelSecurityFilter
    from superset.utils.core import RowLevelSecurityFilterType

    rule = _rule(BASE_RULE)
    if not rule:
        rule = RowLevelSecurityFilter(name=BASE_RULE)
        db.session.add(rule)
    rule.filter_type = RowLevelSecurityFilterType.BASE.value
    rule.group_key = TENANT_GROUP
    rule.clause = "1 = 0"
    rule.description = "Ninguém vê linhas do ERP sem papel de cliente (exceto Admin, Alpha e Incorporado)."
    rule.roles = [r for r in (sm.find_role(n) for n in EXEMPT_ROLES) if r]
    rule.tables = erp_datasets()
    db.session.commit()
    print(f"regra base aplicada a {len(rule.tables)} datasets")


def _attach_all_tenant_rules() -> None:
    db, _ = _ctx()
    from superset.connectors.sqla.models import RowLevelSecurityFilter

    tables = erp_datasets()
    rules = (
        db.session.query(RowLevelSecurityFilter)
        .filter(RowLevelSecurityFilter.name.like("tenant: c%"))
        .all()
    )
    for r in rules:
        r.tables = tables
    db.session.commit()
    print(f"{len(rules)} regras de cliente atualizadas")


def cmd_tenant(args) -> None:
    db, sm = _ctx()
    from superset.connectors.sqla.models import RowLevelSecurityFilter
    from superset.utils.core import RowLevelSecurityFilterType

    database = get_database()
    if not database:
        sys.exit(f"banco '{DB_NAME}' não existe; rode o comando 'database' antes")
    cid = int(args.company_id)
    role_name = f"Cliente - {args.name}"
    role = sm.add_role(role_name)
    pvm = sm.add_permission_view_menu("database_access", database.perm)
    sm.add_permission_role(role, pvm)

    name = f"tenant: c{cid}"
    rule = _rule(name)
    if not rule:
        rule = RowLevelSecurityFilter(name=name)
        db.session.add(rule)
    rule.filter_type = RowLevelSecurityFilterType.REGULAR.value
    rule.group_key = TENANT_GROUP
    rule.clause = f"company_id = {cid}"
    rule.description = f"Isolamento do cliente {args.name} (empresa {cid} no ERP)."
    rule.roles = [role]
    rule.tables = erp_datasets()
    db.session.commit()
    _ensure_base_rule()
    print(f"papel '{role_name}' e regra '{name}' prontos ({len(rule.tables)} datasets)")
    print("Para dar acesso: crie o usuário com os papéis Gamma + este papel de cliente.")


def cmd_status(_args) -> None:
    db, _ = _ctx()
    from superset.connectors.sqla.models import RowLevelSecurityFilter

    database = get_database()
    print(f"banco: {database.database_name if database else '(não configurado)'}")
    print(f"datasets do ERP: {len(erp_datasets())}")
    for r in db.session.query(RowLevelSecurityFilter).order_by(RowLevelSecurityFilter.name):
        roles = ", ".join(x.name for x in r.roles) or "-"
        print(f"  {r.filter_type:8} {r.name:32} [{r.clause}] papéis: {roles} | datasets: {len(r.tables)}")


def main() -> None:
    p = argparse.ArgumentParser(description="Administração do LineaSuite BI")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("bootstrap")
    sub.add_parser("database")
    sub.add_parser("sync-datasets")
    t = sub.add_parser("tenant")
    t.add_argument("--company-id", required=True)
    t.add_argument("--name", required=True)
    sub.add_parser("status")
    args = p.parse_args()
    handlers = {
        "bootstrap": cmd_bootstrap,
        "database": cmd_database,
        "sync-datasets": cmd_sync_datasets,
        "tenant": cmd_tenant,
        "status": cmd_status,
    }
    with app.app_context():
        handlers[args.cmd](args)


if __name__ == "__main__":
    main()
