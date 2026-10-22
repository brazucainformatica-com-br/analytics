# LineaSuite BI — Apache Superset 6.1

Plataforma de BI do LineaSuite publicada em `https://bi.lineasuite.com.br`, baseada no **Apache Superset 6.1** (licença Apache 2.0) com identidade visual Brazuca e linguagem visual de relatório corporativo (fundo cinza, cartões brancos, paleta institucional).

Diferente do fork do Metabase na raiz deste repositório, aqui **não há alteração no código-fonte**: tudo é feito por configuração, tema e scripts. Atualizar de versão é trocar a tag e rodar a instalação de novo.

## Recursos habilitados

| Recurso | Como está configurado |
|---|---|
| Segurança por linha por cliente (RLS) | Regra base "negar por padrão" + uma regra `company_id = <id>` por cliente (`bi_admin.py tenant`) |
| Incorporação no LineaSuite | Embedded SDK com token de convidado (JWT) e `frame-ancestors` restrito aos domínios LineaSuite |
| White-label | Nome "Analytics", logo e favicon Brazuca, tema claro e escuro próprios |
| Relatórios e alertas agendados | Celery + Playwright/Chromium; e-mail via SMTP (modo de teste enquanto o SMTP estiver vazio) |
| Exportação | CSV completo, Excel, PNG e PDF de painéis |
| Governança | Acesso a painéis por papel (Dashboard RBAC), tags, RLS também no SQL Lab |
| Análise | Drill by, drill to detail, comparação de períodos, Jinja em SQL, pastas de dataset |
| SSO (opcional) | Microsoft Entra ID por OAuth, ativado só ao preencher `ENTRA_*` no `.env` |
| Idioma e formatos | pt-BR padrão, separador decimal vírgula, moeda R$ |

## Arquitetura no srv1

```
Internet ──HTTPS──► Apache (Virtualmin, bi.lineasuite.com.br) ──► 127.0.0.1:8088
                                                                  │
   ┌──────────────────────── Docker (rede interna) ───────────────┴─────────┐
   │ bi_app (gunicorn)   bi_worker (Celery + Chromium)   bi_beat (agenda)   │
   │ bi_db (PostgreSQL 17, metadados)        bi_redis (cache e filas)       │
   └──────────────────────────────┬─────────────────────────────────────────┘
                                  │ socket /run/mysqld/mysqld.sock (sem expor a 3306)
                     MariaDB do host ─ schema erp_bi (views) ─► erp_lineasuite
```

- **Leitura do ERP:** usuário `bi_ro@localhost`, somente `SELECT` no schema `erp_bi`. As views são `SQL SECURITY DEFINER` com `mb_ro_erp`, excluem tabelas de credenciais/sessões e colunas com segredos, e expõem `company_id` em todas as views (inclusive nas tabelas filhas, por junção com a tabela pai).
- **Limites de memória:** app 2 GB, worker 2 GB, PostgreSQL 512 MB, Redis 256 MB, agendador 256 MB.

## Instalação

Como root no srv1:

```bash
git clone --depth 1 https://github.com/brazucainformatica-com-br/analytics.git /opt/analytics-src
cd /opt/analytics-src/superset
bash scripts/install.sh all          # ou etapa por etapa: deps, config, erp, build, start, data, backup
```

Senha inicial do administrador: `/root/bi-credenciais.txt`. Guarde no cofre de senhas e apague com `shred -u`.

### Publicação no Apache (Virtualmin)

1. DNS na Cloudflare: registro `A bi → 187.127.52.121`, em "DNS only" até o certificado sair.
2. Sub-servidor e certificado:
   ```bash
   virtualmin create-domain --domain bi.lineasuite.com.br --parent lineasuite.com.br --web --ssl --desc "LineaSuite BI (Superset)"
   ```
3. Proxy, mantendo `/.well-known` fora dele para renovar o Let's Encrypt:
   ```bash
   D=bi.lineasuite.com.br
   virtualmin create-proxy --domain $D --path /.well-known --no-proxy
   virtualmin create-proxy --domain $D --path / --url http://127.0.0.1:8088/
   ```
4. No bloco 443 do vhost, garantir `ProxyPreserveHost On` e `RequestHeader set X-Forwarded-Proto "https"`.

## Clientes (isolamento por empresa)

```bash
cd /opt/lineasuite-bi
docker compose exec superset python /app/pythonpath/bi_admin.py tenant --company-id 1 --name "B&Bartoni do Brasil"
docker compose exec superset python /app/pythonpath/bi_admin.py status
```

Depois, em **Configurações → Listar usuários**, crie o usuário do cliente com os papéis **Gamma** e **Cliente - <nome>**.

| Papel | Vê |
|---|---|
| Admin, Alpha | Todas as empresas |
| Gamma + Cliente - X | Só as linhas com `company_id = X` |
| Gamma sem papel de cliente | Nenhuma linha do ERP |
| Incorporado (token de convidado) | O que a regra RLS do token permitir — **o backend do LineaSuite deve sempre enviar `company_id = <id>`** |

Tabelas de referência fiscal (`rt_*`) têm `company_id` nulo e só aparecem para Admin e Alpha.

Ao criar datasets novos ou atualizar o ERP:

```bash
bash /opt/lineasuite-bi/scripts/erp-bi-views.sh
docker compose -f /opt/lineasuite-bi/docker-compose.yml exec superset python /app/pythonpath/bi_admin.py sync-datasets
```

## Incorporação no LineaSuite (resumo)

1. No painel: **… → Incorporar painel**, informar os domínios permitidos e copiar o `uuid`.
2. O backend PHP do LineaSuite pede um token de convidado em `POST /api/v1/security/guest_token/` (com usuário de serviço), informando o painel e a regra `{"clause": "company_id = <id da empresa logada>"}`.
3. O front-end usa o `@superset-ui/embedded-sdk` com esse token.

## Operação

| Tarefa | Comando (em `/opt/lineasuite-bi`) |
|---|---|
| Status | `docker compose ps` |
| Logs | `docker compose logs -f --tail 100 superset` |
| Reiniciar | `docker compose restart superset superset-worker superset-beat` |
| Backup manual | `bash scripts/backup.sh` (diário às 02:30 via `/etc/cron.d/lineasuite-bi`) |
| Atualizar versão | alterar `SUPERSET_VERSION` no `.env`, `git pull` em `/opt/analytics-src` e rodar `install.sh config build start` |

## Segurança (resumo)

- Porta 8088 só em 127.0.0.1; MariaDB acessada por socket, sem abrir a 3306.
- Segredos só no `.env` (600) e em `/root/*.txt` (600); nada versionado.
- Cookies `Secure`, CSP com `frame-ancestors` restrito, limite de tentativas de login, senhas com complexidade.
- RLS aplicada também no SQL Lab; clientes recebem só o papel Gamma (sem SQL Lab).
- Referências: ISO/IEC 27001:2022 A.5.15 (controle de acesso), A.8.3 (restrição de acesso à informação), A.8.13 (backup); LGPD art. 46.

## Licença

Apache Superset é licenciado sob a Apache License 2.0. Este diretório contém apenas configuração e scripts da Brazuca Informática.
