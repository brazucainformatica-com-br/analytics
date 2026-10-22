"""
LineaSuite BI — configuração do Apache Superset 6.1 para o srv1.

Todos os segredos vêm de variáveis de ambiente (arquivo .env, permissão 600),
nunca deste arquivo. O tema visual fica em theme_brazuca.py.
"""
import os
from datetime import timedelta

from celery.schedules import crontab

from theme_brazuca import (  # noqa: E402  (arquivo no mesmo diretório /app/pythonpath)
    BRAZUCA_CATEGORICAL,
    BRAZUCA_SEQUENTIAL,
    THEME_DARK_BRAZUCA,
    THEME_DEFAULT_BRAZUCA,
)


def env(name: str, default: str | None = None) -> str | None:
    value = os.environ.get(name, default)
    return value if value not in ("", None) else default


def env_bool(name: str, default: bool = False) -> bool:
    return str(env(name, str(default))).lower() in ("1", "true", "yes", "sim")


PUBLIC_URL = env("BI_PUBLIC_URL", "https://bi.lineasuite.com.br").rstrip("/")

# ---------------------------------------------------------------------------
# Segurança básica
# ---------------------------------------------------------------------------
SECRET_KEY = env("SUPERSET_SECRET_KEY")
if not SECRET_KEY:
    raise RuntimeError("SUPERSET_SECRET_KEY não definida no .env")

SQLALCHEMY_DATABASE_URI = (
    f"postgresql+psycopg2://superset:{env('POSTGRES_PASSWORD')}@db:5432/superset"
)

# Atrás do Apache (proxy reverso com TLS)
ENABLE_PROXY_FIX = True
PROXY_FIX_CONFIG = {"x_for": 1, "x_proto": 1, "x_host": 1, "x_port": 0, "x_prefix": 1}
PREFERRED_URL_SCHEME = "https"

SESSION_COOKIE_SECURE = True
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "None" if env_bool("BI_EMBED_ENABLED", True) else "Lax"
PERMANENT_SESSION_LIFETIME = timedelta(hours=int(env("BI_SESSION_HOURS", "8")))

# Senhas fortes para usuários locais (ISO/IEC 27001:2022 A.5.17)
FAB_PASSWORD_COMPLEXITY_ENABLED = True
AUTH_RATE_LIMITED = True
AUTH_RATE_LIMIT = "5 per second"

# Bloqueia conexões a SQLite e outros bancos inseguros pela interface
PREVENT_UNSAFE_DB_CONNECTIONS = True

# ---------------------------------------------------------------------------
# Identidade, idioma e fuso
# ---------------------------------------------------------------------------
APP_NAME = env("BI_APP_NAME", "Analytics")
APP_ICON = "/static/assets/brazuca/logo.png"
LOGO_TARGET_PATH = "/"
LOGO_TOOLTIP = APP_NAME
FAVICONS = [
    {"href": "/static/assets/brazuca/favicon.png", "sizes": "32x32", "type": "image/png"},
    {"href": "/static/assets/brazuca/apple-touch-icon.png", "rel": "apple-touch-icon"},
]

BABEL_DEFAULT_LOCALE = "pt_BR"
LANGUAGES = {
    "pt_BR": {"flag": "br", "name": "Português (Brasil)"},
    "en": {"flag": "us", "name": "English"},
}

D3_FORMAT = {
    "decimal": ",",
    "thousands": ".",
    "grouping": [3],
    "currency": ["R$ ", ""],
}
CURRENCIES = ["BRL", "USD", "EUR"]

# ---------------------------------------------------------------------------
# Tema (Power BI-like com a identidade Brazuca)
# ---------------------------------------------------------------------------
THEME_DEFAULT = THEME_DEFAULT_BRAZUCA
THEME_DARK = THEME_DARK_BRAZUCA
ENABLE_UI_THEME_ADMINISTRATION = True
EXTRA_CATEGORICAL_COLOR_SCHEMES = BRAZUCA_CATEGORICAL
EXTRA_SEQUENTIAL_COLOR_SCHEMES = BRAZUCA_SEQUENTIAL

# ---------------------------------------------------------------------------
# Cache e filas (Redis interno)
# ---------------------------------------------------------------------------
REDIS_URL = "redis://redis:6379"

CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_DEFAULT_TIMEOUT": 300,
    "CACHE_KEY_PREFIX": "bi_meta_",
    "CACHE_REDIS_URL": f"{REDIS_URL}/1",
}
DATA_CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_DEFAULT_TIMEOUT": int(env("BI_DATA_CACHE_SECONDS", "600")),
    "CACHE_KEY_PREFIX": "bi_data_",
    "CACHE_REDIS_URL": f"{REDIS_URL}/2",
}
FILTER_STATE_CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_DEFAULT_TIMEOUT": 86400,
    "CACHE_KEY_PREFIX": "bi_filter_",
    "CACHE_REDIS_URL": f"{REDIS_URL}/3",
}
EXPLORE_FORM_DATA_CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_DEFAULT_TIMEOUT": 86400,
    "CACHE_KEY_PREFIX": "bi_explore_",
    "CACHE_REDIS_URL": f"{REDIS_URL}/4",
}
THUMBNAIL_CACHE_CONFIG = {
    "CACHE_TYPE": "RedisCache",
    "CACHE_DEFAULT_TIMEOUT": 86400 * 7,
    "CACHE_KEY_PREFIX": "bi_thumb_",
    "CACHE_REDIS_URL": f"{REDIS_URL}/5",
}


class CeleryConfig:
    broker_url = f"{REDIS_URL}/0"
    result_backend = f"{REDIS_URL}/0"
    imports = (
        "superset.sql_lab",
        "superset.tasks.scheduler",
        "superset.tasks.thumbnails",
        "superset.tasks.cache",
    )
    worker_prefetch_multiplier = 1
    task_acks_late = False
    beat_schedule = {
        "reports.scheduler": {
            "task": "reports.scheduler",
            "schedule": crontab(minute="*", hour="*"),
        },
        "reports.prune_log": {
            "task": "reports.prune_log",
            "schedule": crontab(minute=10, hour=0),
        },
    }


CELERY_CONFIG = CeleryConfig

# ---------------------------------------------------------------------------
# Recursos habilitados (equivalentes aos "premium" de outras ferramentas)
# ---------------------------------------------------------------------------
FEATURE_FLAGS = {
    # Relatórios e alertas agendados por e-mail, com PDF/PNG do painel
    "ALERT_REPORTS": True,
    "ALERTS_ATTACH_REPORTS": True,
    "PLAYWRIGHT_REPORTS_AND_THUMBNAILS": True,
    "THUMBNAILS": True,
    "ENABLE_DASHBOARD_SCREENSHOT_ENDPOINTS": True,
    "ENABLE_DASHBOARD_DOWNLOAD_WEBDRIVER_SCREENSHOT": True,
    # Incorporação no LineaSuite com token de convidado e RLS por cliente
    "EMBEDDED_SUPERSET": env_bool("BI_EMBED_ENABLED", True),
    "DISABLE_EMBEDDED_SUPERSET_LOGOUT": True,
    # Governança de acesso
    "DASHBOARD_RBAC": True,
    "RLS_IN_SQLLAB": True,
    "TAGGING_SYSTEM": True,
    # Análise
    "DRILL_BY": True,
    "DRILL_TO_DETAIL": True,
    "DATE_RANGE_TIMESHIFTS_ENABLED": True,
    "DATASET_FOLDERS": True,
    "ENABLE_TEMPLATE_PROCESSING": True,
    "ALLOW_FULL_CSV_EXPORT": True,
    "CSS_TEMPLATES": True,
}

# ---------------------------------------------------------------------------
# Relatórios por e-mail
# Enquanto o SMTP não estiver configurado, os envios ficam em modo de teste (dry run).
# ---------------------------------------------------------------------------
WEBDRIVER_BASEURL = "http://superset:8088/"
WEBDRIVER_BASEURL_USER_FRIENDLY = f"{PUBLIC_URL}/"
EMAIL_REPORTS_SUBJECT_PREFIX = f"[{APP_NAME}] "
EMAIL_REPORTS_CTA = f"Abrir no {APP_NAME}"

SMTP_HOST = env("SMTP_HOST", "localhost")
SMTP_PORT = int(env("SMTP_PORT", "587"))
SMTP_STARTTLS = env_bool("SMTP_STARTTLS", True)
SMTP_SSL = env_bool("SMTP_SSL", False)
SMTP_USER = env("SMTP_USER", "")
SMTP_PASSWORD = env("SMTP_PASSWORD", "")
SMTP_MAIL_FROM = env("SMTP_MAIL_FROM", "bi@lineasuite.com.br")
ALERT_REPORTS_NOTIFICATION_DRY_RUN = not env("SMTP_USER")

# ---------------------------------------------------------------------------
# Incorporação (Embedded SDK) — tokens de convidado emitidos pelo backend do LineaSuite
# ---------------------------------------------------------------------------
GUEST_ROLE_NAME = "Incorporado"
GUEST_TOKEN_JWT_SECRET = env("GUEST_TOKEN_JWT_SECRET")
GUEST_TOKEN_JWT_ALGO = "HS256"
GUEST_TOKEN_JWT_EXP_SECONDS = 300

EMBED_ANCESTORS = [
    a.strip()
    for a in env(
        "BI_EMBED_ANCESTORS",
        "https://*.lineasuite.com https://*.lineasuite.com.br https://lineasuite.com https://lineasuite.com.br",
    ).split()
    if a.strip()
]

# ---------------------------------------------------------------------------
# Cabeçalhos de segurança (CSP) — igual ao padrão do Superset 6.1 + frame-ancestors
# ---------------------------------------------------------------------------
THEME_FONT_URL_ALLOWED_DOMAINS = ["fonts.googleapis.com", "fonts.gstatic.com"]
TALISMAN_ENABLED = True
TALISMAN_CONFIG = {
    "content_security_policy": {
        "base-uri": ["'self'"],
        "default-src": ["'self'"],
        "img-src": ["'self'", "blob:", "data:"],
        "worker-src": ["'self'", "blob:"],
        "connect-src": [
            "'self'",
            "https://tile.openstreetmap.org",
            "https://a.basemaps.cartocdn.com",
        ],
        "object-src": "'none'",
        "style-src": [
            "'self'",
            "'unsafe-inline'",
            *[f"https://{d}" for d in THEME_FONT_URL_ALLOWED_DOMAINS],
        ],
        "font-src": ["'self'", *[f"https://{d}" for d in THEME_FONT_URL_ALLOWED_DOMAINS]],
        "script-src": ["'self'", "'strict-dynamic'"],
        "frame-ancestors": ["'self'", *EMBED_ANCESTORS],
    },
    "content_security_policy_nonce_in": ["script-src"],
    "frame_options": None,
    "force_https": False,
    "session_cookie_secure": True,
}

# ---------------------------------------------------------------------------
# Limites e desempenho
# ---------------------------------------------------------------------------
ROW_LIMIT = 50000
SQL_MAX_ROW = 100000
SUPERSET_WEBSERVER_TIMEOUT = 120
SQLLAB_TIMEOUT = 120
SQLLAB_ASYNC_TIME_LIMIT_SEC = 600

# ---------------------------------------------------------------------------
# SSO com Microsoft Entra ID (opcional). Ativado só se ENTRA_CLIENT_ID estiver no .env.
# Atenção: com AUTH_OAUTH, o login por usuário e senha deixa de existir.
# ---------------------------------------------------------------------------
if env("ENTRA_CLIENT_ID"):
    from flask_appbuilder.security.manager import AUTH_OAUTH

    _tenant = env("ENTRA_TENANT_ID")
    AUTH_TYPE = AUTH_OAUTH
    AUTH_USER_REGISTRATION = True
    AUTH_USER_REGISTRATION_ROLE = env("ENTRA_DEFAULT_ROLE", "Gamma")
    AUTH_ROLES_SYNC_AT_LOGIN = False
    OAUTH_PROVIDERS = [
        {
            "name": "azure",
            "icon": "fa-windows",
            "token_key": "access_token",
            "remote_app": {
                "client_id": env("ENTRA_CLIENT_ID"),
                "client_secret": env("ENTRA_CLIENT_SECRET"),
                "api_base_url": f"https://login.microsoftonline.com/{_tenant}/oauth2",
                "client_kwargs": {"scope": "openid profile email", "verify_signature": True},
                "request_token_url": None,
                "access_token_url": f"https://login.microsoftonline.com/{_tenant}/oauth2/v2.0/token",
                "authorize_url": f"https://login.microsoftonline.com/{_tenant}/oauth2/v2.0/authorize",
                "jwks_uri": "https://login.microsoftonline.com/common/discovery/v2.0/keys",
            },
        }
    ]
