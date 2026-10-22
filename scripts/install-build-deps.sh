#!/usr/bin/env bash
# Instala as ferramentas de compilacao do Metabase no Ubuntu 24.04 (executar como root).
# JDK 25 (Temurin), Clojure CLI, Node.js 22, Bun, uv, git e ImageMagick.
set -euo pipefail

CLOJURE_VERSION="1.12.3.1577"
NODE_VERSION="v22.23.2"
BUN_VERSION="bun-v1.3.14"

apt-get update -qq
apt-get install -y -qq git curl unzip rlwrap build-essential imagemagick python3 temurin-25-jdk >/dev/null

if ! command -v clojure >/dev/null; then
  curl -fsSL -o /tmp/clj-install.sh "https://github.com/clojure/brew-install/releases/download/${CLOJURE_VERSION}/linux-install.sh"
  bash /tmp/clj-install.sh >/dev/null && rm -f /tmp/clj-install.sh
fi

# Usa o Node.js ja instalado no servidor (v22.x). So instala se nao houver nenhum,
# para nao sobrepor a versao usada por outros sistemas do servidor.
if ! command -v node >/dev/null; then
  curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz" \
    | tar -xJ -C /usr/local --strip-components=1
fi

if ! command -v bun >/dev/null; then
  curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash -s "$BUN_VERSION" >/dev/null
fi

if ! command -v uv >/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh >/dev/null
fi

id mbbuild >/dev/null 2>&1 || useradd -r -m -d /opt/mbbuild -s /bin/bash mbbuild

echo "java:    $(/usr/lib/jvm/temurin-25-jdk-amd64/bin/java -version 2>&1 | head -1)"
echo "clojure: $(clojure --version 2>/dev/null)"
echo "node:    $(node -v)  bun: $(bun -v)  uv: $(uv --version)"
echo "convert: $(convert -version | head -1)"
