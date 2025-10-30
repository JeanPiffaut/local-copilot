#!/usr/bin/env sh
set -eu

# Configuración
CONFIG_PATH="${OLLAMA_CONFIG:-/app/config/ollama.config.json}"
API_URL="http://localhost:11434"
DATA_DIR="/root/.ollama"

mkdir -p "$DATA_DIR"

# Funciones auxiliares
log() { printf "[%s] %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

wait_for_health() {
  i=0
  max=120 # ~120s
  while [ $i -lt $max ]; do
    if curl -fsS "$API_URL/api/tags" >/dev/null 2>&1; then
      return 0
    fi
    i=$((i+1))
    sleep 1
  done
  return 1
}

# Leer configuración desde JSON si existe
PULL_ON_START="false"
MODELS_JSON="[]"
if [ -f "$CONFIG_PATH" ]; then
  log "Usando configuración: $CONFIG_PATH"
  PULL_ON_START=$(jq -r '.pullOnStart // false' "$CONFIG_PATH" 2>/dev/null || echo "false")
  MODELS_JSON=$(jq -c '.models // []' "$CONFIG_PATH" 2>/dev/null || echo "[]")
else
  log "No se encontró configuración en $CONFIG_PATH; usando valores por defecto."
fi

# Iniciar servidor en background
log "Iniciando servidor Ollama..."
ollama serve &
SERVER_PID=$!

# Asegurar limpieza al terminar
term_handler() {
  log "Recibida señal de terminación; finalizando servidor (PID=$SERVER_PID)"
  kill -TERM "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  exit 143
}
trap term_handler TERM INT

# Esperar a que el API responda
if wait_for_health; then
  log "Servidor disponible."
else
  log "Timeout esperando disponibilidad del servidor."
  kill -TERM "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
  exit 1
fi

# Pull de modelos si está habilitado
if [ "$PULL_ON_START" = "true" ]; then
  log "pullOnStart=true: preparando modelos..."
  # Iterar modelos del JSON
  echo "$MODELS_JSON" | jq -r '.[]' | while IFS= read -r MODEL; do
    if [ -n "$MODEL" ]; then
      log "Descargando modelo: $MODEL"
      # Reintentos simples
      tries=0
      until ollama pull "$MODEL"; do
        tries=$((tries+1))
        if [ $tries -ge 3 ]; then
          log "Fallo al descargar $MODEL tras $tries intentos"
          break
        fi
        log "Reintentando $MODEL ($tries) tras espera breve..."
        sleep 5
      done
    fi
  done
else
  log "pullOnStart=false: omitiendo descarga automática de modelos."
fi

# Mantener el proceso principal en foreground
wait "$SERVER_PID"
