#!/usr/bin/env bash
# Baixa e prepara os arquivos de marca da Brazuca Informatica (logo, logo branco e icones)
# e grava em resources/frontend_client/app/assets/img/brazuca/ dentro do codigo do Metabase.
# Uso: scripts/fetch-assets.sh /caminho/do/codigo/metabase
set -euo pipefail

MB_DIR="${1:?informe o diretorio do codigo do Metabase}"
OUT="$MB_DIR/resources/frontend_client/app/assets/img/brazuca"
SRC="https://brazucainformatica.com.br/wp-content/uploads"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUT"
curl -fsSL -o "$TMP/logo.png"       "$SRC/2026/06/logo-1.png"
curl -fsSL -o "$TMP/logo-white.png" "$SRC/2026/07/logo-footer-branca.png"
curl -fsSL -o "$TMP/fav192.png"     "$SRC/2026/06/cropped-favicon-brazuca-192x192.png"
curl -fsSL -o "$TMP/fav180.png"     "$SRC/2026/06/cropped-favicon-brazuca-180x180.png"
curl -fsSL -o "$TMP/fav32.png"      "$SRC/2026/06/cropped-favicon-brazuca-32x32.png"

# Remove o fundo solido a partir dos quatro cantos, recorta as bordas e limita a altura a 180 px.
clean_logo() {
  local in="$1" out="$2" w h
  w=$(identify -format '%w' "$in"); h=$(identify -format '%h' "$in")
  convert "$in" -alpha set -fuzz 10% -fill none \
    -draw "color 0,0 floodfill" \
    -draw "color $((w-1)),0 floodfill" \
    -draw "color 0,$((h-1)) floodfill" \
    -draw "color $((w-1)),$((h-1)) floodfill" \
    -trim +repage -resize 'x180>' "$out"
}

clean_logo "$TMP/logo.png"       "$OUT/logo.png"
clean_logo "$TMP/logo-white.png" "$OUT/logo-white.png"
cp "$TMP/fav32.png"  "$OUT/favicon.png"
cp "$TMP/fav180.png" "$OUT/apple-touch-icon.png"
cp "$TMP/fav192.png" "$OUT/icon-192.png"
convert "$TMP/fav192.png" -resize 256x256 "$OUT/icon-256.png"

ls -l "$OUT"
