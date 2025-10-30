# Plan para instalar y ejecutar Ollama en local con Docker (Windows)

Este documento describe el plan (sin código aún) para levantar Ollama localmente usando Docker y/o Docker Compose en Windows. Incluye supuestos, requisitos, decisiones de diseño, opciones de despliegue (CPU/GPU), persistencia de modelos, seguridad, health checks, flujo para descargar modelos y pasos de prueba y solución de problemas.

## Objetivo

- Ejecutar el servidor de Ollama localmente, exponiendo su API en el puerto 11434.
- Usar contenedores para simplificar la instalación y el ciclo de vida.
- Permitir dos variantes de despliegue:
  1) con Docker Compose (recomendado para desarrollo local y multi-servicio),
  2) con un Dockerfile (para construir una imagen personalizada que automatice pulls de modelos u otras necesidades).
- Mantener persistencia de modelos entre reinicios.
- Opcional: habilitar GPU (NVIDIA/WSL2) cuando esté disponible para acelerar inferencia.

## Supuestos

- Sistema operativo: Windows 10/11 con Docker Desktop instalado y motor WSL 2 habilitado.
- Se utilizará la imagen oficial de Ollama desde un registro público (Docker Hub). Versiones se fijarán posteriormente (pinned tags) para reproducibilidad.
- Directorio de trabajo: este repositorio (`local-copilot`).
- Puerto API por defecto de Ollama: 11434 (expuesto únicamente a localhost a menos que se requiera lo contrario).
- Persistencia: los modelos se almacenan en un volumen/named volume o en una ruta del host mapeada al contenedor.

## Requisitos previos

- Docker Desktop para Windows (con WSL 2 activado).
- (Opcional GPU NVIDIA) Drivers NVIDIA actualizados con soporte CUDA, y soporte de GPU en Docker Desktop para WSL 2.
- Conectividad a internet para descargar la imagen e inicializar modelos.

## Decisiones de diseño

- Imagen base: usar la imagen oficial `ollama/ollama` (tag concreto a definir). Evitar latest sin fijar.
- Exposición de puertos: mapear 11434:11434, preferiblemente a 127.0.0.1 para evitar exposición no intencionada.
- Persistencia de datos:
  - Opción A: named volume de Docker (simple y portable).
  - Opción B: bind mount a una carpeta del host (p. ej. `C:\Users\\<usuario>\\.ollama` → `/root/.ollama`). En Windows, preferir rutas relativas del proyecto cuando sea posible para evitar problemas de permisos y path.
- Gestión de modelos: dos estrategias no excluyentes:
  - Pull manual bajo demanda (comandos ad-hoc contra el contenedor).
  - Inicialización automática: servicio/tarea que realize `ollama pull <modelo>` tras verificar que el servidor está listo (mediante health check o dependencia entre servicios en Compose).
- Compatibilidad GPU: habilitar `--gpus all`/dispositivo GPU en Compose solo si está disponible para no bloquear escenarios CPU-only.

## Opción 1: Docker Compose (recomendada)

Qué contendrá `docker-compose.yml` (a definir luego, sin escribir código ahora):

- Servicio `ollama` basado en la imagen oficial.
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

## Opción 2: Dockerfile (imagen personalizada)

Qué contendrá `Dockerfile` (a definir luego, sin escribir código ahora):

- FROM de la imagen oficial `ollama/ollama:<tag>` para heredar binarios y configuración.
- (Opcional) Scripts/entrypoint que:
  - Arranquen el daemon `ollama serve` y, una vez disponible, ejecuten pulls de modelos definidos por variables de entorno (p. ej. `OLLAMA_MODELS="llama3:8b,mistral:7b"`).
  - Implementen reintentos/backoff para el pull y logs claros.
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

- Named volumes evitan fricción con rutas Windows. Recomendado si no se necesita inspeccionar los archivos fuera del contenedor.
- Bind mounts funcionan, pero hay que cuidar:
  - Rutas con espacios o caracteres especiales.
  - Permisos entre Windows/WSL2.
  - Performance de IO (en general aceptable para este caso, pero considerar named volume si hay problemas).

## Puertos y seguridad

- Puerto API: 11434. Mantener mapeo a localhost (127.0.0.1) para evitar exposición externa.
- Si se necesita acceso remoto, considerar reverse proxy con autenticación/TLS en otro servicio y políticas de firewall.

## GPU (opcional, NVIDIA/WSL2)

- Requisitos:
  - GPU NVIDIA compatible, drivers actualizados en Windows.
  - Docker Desktop con soporte WSL 2 y acceso a GPU habilitado.
- En Compose, se declarará el uso de GPU de forma opcional. En equipos sin GPU, se podrá desactivar sin romper el despliegue.
- Verificar que la imagen de Ollama soporta CUDA/ROCm correspondiente. En caso de AMD, considerar notas específicas de soporte ROCm.

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

1) Generar `docker-compose.yml` con:
   - Servicio `ollama` con puertos, volumen, health check, y GPU opcional.
   - (Opcional) Servicio `model-init` que haga pulls tras la disponibilidad del API.
2) Alternativa o complemento: crear `Dockerfile` que automatice pulls mediante entrypoint.
3) Añadir un pequeño script PowerShell (`scripts/`) con atajos: up/down, pull de modelos, verificación de salud.
4) Documentar comandos de uso rápido y ejemplos de pruebas (curl/PowerShell).
5) Pin de versiones (imagen, modelos) y notas de compatibilidad GPU (CUDA/ROCm) según hardware.

---

Si te parece bien este enfoque, en el siguiente paso genero los archivos (`docker-compose.yml` y/o `Dockerfile`) con las piezas descritas y añadimos los scripts de conveniencia para Windows PowerShell.
