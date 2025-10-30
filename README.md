# Plan para instalar y ejecutar Ollama en local con Docker (Windows)

Este documento describe el plan (sin código aún) para levantar Ollama localmente usando Docker y/o Docker Compose en Windows. Incluye supuestos, requisitos, decisiones de diseño, opciones de despliegue (CPU/GPU), persistencia de modelos, seguridad, health checks, flujo para descargar modelos y pasos de prueba y solución de problemas.

## Objetivo

- Ejecutar el servidor de Ollama localmente, exponiendo su API en el puerto 11434.
- Usar contenedores para simplificar la instalación y el ciclo de vida.
- Usar un Dockerfile para la base (imagen personalizada y lógica de inicialización) y Docker Compose únicamente para levantar/gestionar el contenedor.
- Mantener persistencia de modelos entre reinicios dentro de este proyecto (carpeta `llm-data/`).
- Opcional: habilitar GPU (NVIDIA/WSL2) cuando esté disponible para acelerar inferencia.

## Supuestos

- Sistema operativo: Windows 10/11 con Docker Desktop instalado y motor WSL 2 habilitado.
- Se utilizará la imagen oficial de Ollama desde un registro público (Docker Hub). Versiones se fijarán posteriormente (pinned tags) para reproducibilidad.
- Directorio de trabajo: este repositorio (`local-copilot`).
- Puerto API por defecto de Ollama: 11434 (expuesto únicamente a localhost a menos que se requiera lo contrario).
- Persistencia: los modelos se almacenarán en una carpeta del proyecto `./llm-data` mapeada al contenedor (en lugar de una ruta del usuario o named volume) para facilitar portabilidad.

## Requisitos previos

- Docker Desktop para Windows (con WSL 2 activado).
- (Opcional GPU NVIDIA) Drivers NVIDIA actualizados con soporte CUDA, y soporte de GPU en Docker Desktop para WSL 2.
- Conectividad a internet para descargar la imagen e inicializar modelos.

## Decisiones de diseño

- Imagen base: usar la imagen oficial `ollama/ollama` (tag concreto a definir). Evitar latest sin fijar.
- Exposición de puertos: mapear 11434:11434, preferiblemente a 127.0.0.1 para evitar exposición no intencionada.
- Persistencia de datos: bind mount a carpeta del proyecto `./llm-data` mapeada a `/root/.ollama` dentro del contenedor.
- Gestión de modelos: dos estrategias no excluyentes:
  - Pull manual bajo demanda (comandos ad-hoc contra el contenedor).
  - Inicialización automática: el entrypoint o un servicio auxiliar realiza `ollama pull <modelo>` cuando el servidor esté listo (health check/espera).
- Compatibilidad GPU: habilitar `--gpus all`/device requests en Compose solo si está disponible para no bloquear escenarios CPU-only.
- Configuración externa: mantener un JSON (`config/ollama.config.json`) con opciones estáticas (lista de modelos a preparar, flags de GPU, puertos, etc.). El Dockerfile/entrypoint podrá leer este archivo en tiempo de arranque.

Notas de hardware (para orientar el baseline):

- Equipo objetivo: 32 GB RAM + GPU NVIDIA RTX 4070.
- Modelo inicial recomendado para pruebas: `llama3:8b-instruct` (baseline razonable con 8B). Más adelante afinaremos variantes/quantización según rendimiento y VRAM disponible.

## Opción 1: Docker Compose (recomendada para levantar)

Qué contendrá `docker-compose.yml` (a definir luego, sin escribir código ahora):

- Servicio `ollama` basado en la imagen personalizada construida por nuestro Dockerfile (o, opcionalmente, en la imagen oficial si no se requiere personalización).
- Puertos: `11434:11434` (idealmente ligado a 127.0.0.1 para acceso local).
- Volumen persistente para `/root/.ollama` (o el path que use la imagen) para conservar modelos.
- Variables de entorno relevantes (p. ej. `OLLAMA_HOST=0.0.0.0` si se necesita bind explícito dentro del contenedor; se evaluará según la imagen).
- Health check: consulta `GET /api/tags` para detectar disponibilidad.
- (Opcional) Soporte GPU: sección para solicitar GPU cuando esté disponible y documentación para habilitarla en Docker Desktop.
- (Opcional) Servicio auxiliar `model-init` o paso post-arranque que haga `ollama pull <modelo>` depende del health check de `ollama`.

Flujo previsto con Compose:

1) `docker compose up -d` para levantar el servicio `ollama`.
2) Esperar a que el health check pase.
3) (Opcional) `docker compose run --rm ollama ollama pull <modelo>` para descargar modelos específicos si no se automatiza.
4) Consumir API local en `http://localhost:11434`.

Ventajas:

- Orquestación sencilla (servicios, volúmenes, health checks, dependencias).
- Fácil extensión si se agregan servicios cliente o UIs.

## Opción 2: Dockerfile (imagen personalizada base)

Qué contendrá `Dockerfile` (a definir luego, sin escribir código ahora):

- FROM de la imagen oficial `ollama/ollama:<tag>` para heredar binarios y configuración.
- Scripts/entrypoint que:
  - Arranquen el daemon `ollama serve` y, una vez disponible, ejecuten pulls de modelos definidos en `config/ollama.config.json` (y/o variables de entorno) con reintentos/backoff y logs claros.
  - Lean el JSON de configuración (ruta relativa del proyecto montada en el contenedor) para parámetros como: lista de modelos, flags GPU, puerto, etc.
- Definición de volumen para `/root/.ollama`.
- Exposición del puerto 11434.

Flujo previsto con Dockerfile:

1) Construir la imagen personalizada (tag interno del proyecto).
2) Ejecutar el contenedor con el volumen y puertos adecuados.
3) Verificar que los modelos definidos se descarguen automáticamente o realizar el pull manualmente.

Ventajas:

- Imagen autocontenida con modelos predefinidos y lógica de inicialización.
- Menos pasos manuales al iniciar.

## Persistencia y rutas en Windows

- Se usará bind mount a `./llm-data` dentro de este proyecto para la persistencia (mapeado a `/root/.ollama`).
- Consideraciones de rutas en Windows (si usáramos otras rutas):
  - Rutas con espacios o caracteres especiales.
  - Permisos entre Windows/WSL2.
  - Performance de IO (para nuestro caso, mantener datos en el proyecto ayuda a la portabilidad y evita sorpresas).

## Puertos y seguridad

- Puerto API: 11434. Mantener mapeo a localhost (127.0.0.1) para evitar exposición externa.
- Si se necesita acceso remoto, considerar reverse proxy con autenticación/TLS en otro servicio y políticas de firewall.

## GPU (opcional, NVIDIA/WSL2)

- Requisitos:
  - GPU NVIDIA compatible, drivers actualizados en Windows.
  - Docker Desktop con soporte WSL 2 y acceso a GPU habilitado.
- En Compose, se declarará el uso de GPU de forma opcional. En equipos sin GPU, se podrá desactivar sin romper el despliegue.
- Verificar que la imagen de Ollama soporta CUDA/ROCm correspondiente. En caso de AMD, considerar notas específicas de soporte ROCm.

Notas para baseline 8B con 4070:

- Se espera buen rendimiento con 8B usando GPU. Si se observan límites de memoria VRAM, consideraremos variantes cuantizadas o tamaños alternativos.

## Health check

- Endpoint: `GET http://localhost:11434/api/tags` debe responder con 200/JSON cuando el servidor esté listo.
- Compose usará este endpoint para secuenciar tareas dependientes (p. ej. pulls automáticos de modelos).

## Gestión de modelos

Estrategias compatibles:

- Pull bajo demanda:
  - Ejecutar un comando ad-hoc contra el contenedor (p. ej., `ollama pull llama3:8b`).
- Pull automático:
  - Servicio `model-init` en Compose que depende del health check de `ollama` y realiza pulls definidos en variables de entorno.
  - Alternativa: script de entrypoint en una imagen personalizada (Dockerfile) que espere a la disponibilidad del servidor y ejecute los pulls.

Consideraciones:

- Los pulls pueden ser pesados; mantenerlos fuera del path crítico de arranque del API si no es indispensable.
- Registrar logs y tiempos para diagnósticos.

Modelo inicial (propuesto para pruebas):

- `llama3:8b-instruct` como punto de partida. Más adelante podremos ajustar a otros modelos (p. ej. `mistral`, `phi`, `llama3.1`, etc.) o variantes cuantizadas si es necesario.

Configuración centralizada (JSON):

- Archivo: `config/ollama.config.json`.
- Contrato inicial (sujeto a ajuste al implementar):
  - `api.host` (string): host de bind interno (p. ej., `0.0.0.0`).
  - `api.port` (number): puerto del API (11434 por defecto).
  - `gpu.enabled` (boolean): habilitar/deshabilitar GPU.
  - `gpu.vendor` (string): `nvidia` | `amd` (para documentar variaciones futuras).
  - `storage.path` (string): ruta de persistencia en el host (por defecto `./llm-data`).
  - `models` (array de strings): lista de tags a preparar (p. ej., `['llama3:8b-instruct']`).
  - `pullOnStart` (boolean): si ejecutar `ollama pull` al arrancar.
  - `env` (objeto opcional): parámetros adicionales (p. ej., `OLLAMA_NUM_THREADS`, `OLLAMA_NUM_CTX`).

El entrypoint del contenedor leerá este JSON para orquestar pulls y parámetros.

## Pruebas funcionales (PowerShell, Windows)

- Verificar que el servicio responde:
  - `Invoke-WebRequest http://localhost:11434/api/tags` debería retornar JSON con las etiquetas/modelos.
- Flujo de generación (opcional):
  - Enviar un payload a `/api/generate` con un prompt simple y confirmar respuesta.
- Validar persistencia:
  - Reiniciar el servicio y comprobar que los modelos no se vuelven a descargar.

## Troubleshooting

- El contenedor no arranca:
  - Revisar logs del servicio (Docker Desktop/`docker compose logs`).
  - Conflicto de puertos (11434 en uso): ajustar el mapeo.
- Pull de modelos falla:
  - Problemas de red, DNS, o limitaciones del registro; reintentar y verificar conectividad.
- GPU no detectada:
  - Confirmar soporte GPU en Docker Desktop y que la distro WSL 2 tiene acceso a GPU.
  - Probar un contenedor base NVIDIA para validar que `nvidia-smi` funciona (opcional).
- Rendimiento bajo:
  - Verificar que realmente se usa GPU (si disponible) y que el modelo elegido cabe en memoria.

## Próximos pasos (cuando aprobemos este plan)

1. Definir la estructura de carpetas/archivos en este repo:

- `Dockerfile` (base personalizada con entrypoint que lee `config/ollama.config.json`).
- `docker/entrypoint.sh` (lógica de arranque, health wait y pulls condicionales).
- `docker-compose.yml` (solo levantar/gestionar, mapeo de `./llm-data`, puertos, health check, GPU opcional).
- `config/ollama.config.json` (config estática descrita arriba).
- `llm-data/` (persistencia de modelos en el proyecto).
- `scripts/build.ps1` y `scripts/run.ps1` (atajos para construir/levantar y pruebas rápidas).

1. Generar `docker-compose.yml` con servicio `ollama`, health check y GPU opcional.

1. Implementar `Dockerfile` y `docker/entrypoint.sh` con lectura del JSON y pulls controlados.

1. Añadir scripts PowerShell y documentar comandos de uso rápido y pruebas (Invoke-WebRequest).

1. Fijar versiones (imagen y modelos) y anotar compatibilidad GPU según hardware (NVIDIA 4070 con WSL2).

Nota: Si ya existen `Dockerfile`, `docker/entrypoint.sh` o scripts en este repo, en la fase de implementación alinearemos el contenido para cumplir este plan (manteniendo cambios mínimos y compatibilidad con lo ya creado).

---

Si te parece bien este enfoque, en el siguiente paso genero los archivos (`docker-compose.yml` y/o `Dockerfile`) con las piezas descritas y añadimos los scripts de conveniencia para Windows PowerShell.
