# Base MVP sin GPU: imagen oficial de Ollama + utilidades mínimas
FROM ollama/ollama:latest

USER root

# Instalar utilidades necesarias para health checks y parseo de JSON
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       curl jq ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copiar entrypoint
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Ruta por defecto al archivo de configuración
ENV OLLAMA_CONFIG=/app/config/ollama.config.json

# Puerto del API de Ollama
EXPOSE 11434

# Mantener datos fuera de la imagen
VOLUME ["/root/.ollama"]

ENTRYPOINT ["/entrypoint.sh"]
