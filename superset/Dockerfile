# Imagem de produção do LineaSuite BI, derivada da imagem "lean" oficial do Apache Superset.
# A imagem lean não traz drivers de banco nem navegador: aqui adicionamos o necessário
# para MariaDB (ERP), PostgreSQL (metadados), relatórios agendados (Playwright/Chromium)
# e as traduções pt-BR já compiladas.
ARG SUPERSET_IMAGE=apache/superset:6.1.0
ARG SUPERSET_VERSION=6.1.0

# ---------------------------------------------------------------------------
# Traduções pt_BR compiladas (o pacote PyPI publicado já traz .mo e .json)
# ---------------------------------------------------------------------------
FROM python:3.11-slim AS translations
ARG SUPERSET_VERSION
RUN pip download --no-deps --no-cache-dir "apache_superset==${SUPERSET_VERSION}" -d /tmp/whl \
 && python -c "import glob,zipfile; z=zipfile.ZipFile(glob.glob('/tmp/whl/apache_superset-*.whl')[0]); [z.extract(n,'/out') for n in z.namelist() if n.startswith('superset/translations/pt_BR/LC_MESSAGES/') and n.endswith(('.mo','.json'))]" \
 && ls -l /out/superset/translations/pt_BR/LC_MESSAGES/

# ---------------------------------------------------------------------------
# Imagem final
# ---------------------------------------------------------------------------
FROM ${SUPERSET_IMAGE}
USER root
ENV PLAYWRIGHT_BROWSERS_PATH=/usr/local/share/playwright-browsers

RUN . /app/.venv/bin/activate \
 && uv pip install --no-cache \
      psycopg2-binary \
      pymysql \
      Authlib \
      openpyxl \
      Pillow \
      playwright \
 && playwright install-deps chromium \
 && playwright install chromium \
 && rm -rf /var/lib/apt/lists/*

# Traduções pt_BR (backend .mo e pacote de idioma do frontend .json)
COPY --from=translations /out/superset/translations/pt_BR /app/superset/translations/pt_BR

USER superset
CMD ["/app/docker/entrypoints/run-server.sh"]
