#!/bin/sh
# =============================================================================
# litellm/entrypoint.sh
#
# LiteLLM コンテナ起動時に config.yaml.tmpl の ${SERVED_MODEL_NAME} を
# 環境変数の実値に展開してから litellm を起動する。
#
# 値の源泉: docker-compose.yml の x-served-model-name アンカー
#          (デフォルト: coco-local)
# =============================================================================
set -eu

: "${SERVED_MODEL_NAME:?SERVED_MODEL_NAME must be set (see docker-compose.yml)}"

TMPL=/app/config.yaml.tmpl
OUT=/app/config.yaml

# 単純な ${SERVED_MODEL_NAME} 1変数だけ展開する（envsubst 非依存・sed のみ）。
# config.yaml.tmpl 側で他の ${...} は使っていない前提。
sed "s|\${SERVED_MODEL_NAME}|${SERVED_MODEL_NAME}|g" "$TMPL" > "$OUT"

echo "[entrypoint] rendered $TMPL -> $OUT (SERVED_MODEL_NAME=${SERVED_MODEL_NAME})"

exec litellm --config "$OUT" --port 4000
