#!/usr/bin/env bash
# Compila o Analytics (Metabase OSS + patch Brazuca). Executar como o usuario mbbuild.
# Resultado: $WORK/metabase/target/uberjar/metabase.jar
set -euo pipefail

MB_TAG="${MB_TAG:-v0.64.3.2}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-/opt/mbbuild/work}"

export JAVA_HOME=/usr/lib/jvm/temurin-25-jdk-amd64
export PATH="$JAVA_HOME/bin:/usr/local/bin:$PATH"
export MB_EDITION=oss
export NODE_OPTIONS="--max-old-space-size=6144"
export CLJ_JVM_OPTS="-Xmx4g"

mkdir -p "$WORK"
cd "$WORK"
rm -rf metabase
git clone --quiet --depth 1 --branch "$MB_TAG" https://github.com/metabase/metabase.git metabase
cd metabase

git -c user.name=build -c user.email=build@localhost am --quiet "$REPO_DIR/patches/brazuca-${MB_TAG}.patch"
bash "$REPO_DIR/scripts/fetch-assets.sh" "$PWD"

echo ">> Compilacao iniciada: $(date)"
./bin/build.sh '{:edition :oss}'
echo ">> Compilacao concluida: $(date)"
ls -lh target/uberjar/metabase.jar
sha256sum target/uberjar/metabase.jar
