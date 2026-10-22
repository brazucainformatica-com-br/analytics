# Analytics · Brazuca Informática

Plataforma de análise de dados da Brazuca Informática, publicada em `https://analytics.lineasuite.com.br`.

É uma versão modificada do **Metabase Open Source** (edição OSS, licença AGPL v3). Este repositório contém o código-fonte correspondente, conforme exige a AGPL: o patch aplicado sobre a versão oficial do Metabase e os scripts para reproduzir a compilação.

## O que foi alterado

| Área | Alteração |
|---|---|
| Nome | "Metabase" substituído por "Analytics" na interface, título das páginas e tradução pt-BR |
| Logo | Logo da Brazuca Informática na barra superior, tela de login e janela "Sobre" |
| Ícones | Favicon, ícone de atalho (Apple/Android) e manifesto web |
| Cores | Cor principal azul Brazuca `#4056D6` e paleta de gráficos institucional |
| Fonte | Inter (já incluída no Metabase) |
| Ilustrações | Removidas da tela de login e da página inicial |
| Links | Links externos para o site do Metabase ocultados |
| Licença | Janela "Sobre" informa a base AGPL e o link deste repositório |

Nenhum código da pasta `enterprise/` (licença comercial do Metabase) foi usado ou alterado, e nenhuma verificação de licença foi modificada. Recursos pagos do Metabase continuam indisponíveis nesta versão.

## Versão base

- Metabase OSS `v0.64.3.2` — https://github.com/metabase/metabase/tree/v0.64.3.2
- Patch: `patches/brazuca-v0.64.3.2.patch`

## Como compilar (Ubuntu 24.04)

```bash
# como root: ferramentas de compilacao (JDK 25, Clojure, Node 22, Bun, uv, ImageMagick)
sudo bash scripts/install-build-deps.sh

# como usuario sem privilegios
bash scripts/build.sh
# resultado: /opt/mbbuild/work/metabase/target/uberjar/metabase.jar
```

## Atualizar para uma nova versão do Metabase

1. Clonar a nova tag oficial e aplicar o patch atual com `git am -3`.
2. Resolver conflitos, se houver, e gerar `patches/brazuca-<nova-tag>.patch` com `git format-patch -1`.
3. Compilar com `MB_TAG=<nova-tag> bash scripts/build.sh`.

## Isolamento de dados por cliente (`tenancy/`)

`tenancy/erp-views.sh <company_id> [--new-user]` cria o schema `erp_rpt_c<ID>` com uma view por tabela do ERP, filtrada pela empresa, e o usuário MariaDB `mb_rpt_c<ID>` com acesso apenas a esse schema. Tabelas de credenciais, sessões e configurações internas ficam de fora, assim como colunas de senha, token, hash e chaves de API. No Analytics, cada cliente vê só a sua conexão.

## Licença

AGPL v3 — ver `LICENSE`. "Metabase" é marca registrada da Metabase, Inc.; este projeto não é afiliado nem endossado pela Metabase, Inc.
