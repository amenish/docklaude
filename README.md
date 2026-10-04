# Claude Code Sandbox

Entorno Docker aislado para ejecutar [Claude Code](https://code.claude.com/) sobre proyectos locales, con acceso de red habilitado, persistencia de configuración/autenticación y selección interactiva del directorio de trabajo.

El objetivo es permitir que Claude Code modifique un proyecto sin exponer directamente el resto del sistema de archivos del host.

> **Aviso:** este proyecto reduce la superficie de acceso del agente, pero no constituye una frontera de seguridad absoluta. Claude Code tiene acceso de escritura al workspace seleccionado y acceso de red.

## Características

- Imagen basada en Alpine Linux.
- Claude Code instalado durante la construcción de la imagen.
- Acceso de red habilitado.
- Solo el directorio de trabajo seleccionado se monta desde el host en `/workspace`.
- Configuración y autenticación persistentes mediante un único volumen Docker (`claude-code-home`).
- Sistema de archivos raíz del contenedor en modo solo lectura.
- `cap_drop: ALL`.
- `no-new-privileges` activado.
- Límites de CPU, memoria y procesos.
- `/tmp` y `/run` como `tmpfs`.
- Selección de directorio mediante `zenity`, `kdialog` o `fzf`.
- Claude se ejecuta con el UID/GID del usuario que lanza el sandbox.
- Modo verbose para inspeccionar la configuración antes del arranque.
- Memoria colectiva sincronizada entre PCs por git y memoria por proyecto en `.PROJECT.md`.
- Al salir, ofrece hacer commit y push del proyecto.
- La imagen solo se reconstruye cuando se solicita explícitamente mediante `--rebuild`.

## Requisitos

- Linux.
- Docker Engine.
- Docker Compose v2 (`docker compose`).
- Una cuenta compatible con Claude Code.
- `zenity` o `kdialog` para selección gráfica.
- `fzf` para selección interactiva en terminal.

Comprueba Docker y Compose:

```bash
docker --version
docker compose version
```

El usuario actual debe poder ejecutar Docker.

## Instalación

Clona el repositorio:

```bash
git clone https://github.com/USUARIO/docklaude.git
cd docklaude
```

Da permisos de ejecución:

```bash
chmod +x run-claude.sh memory-sync.sh project-sync.sh
```

### Fijar la versión de Claude Code

Opcionalmente, en `.env` (copia de `.env.example`):

```dotenv
CLAUDE_VERSION=2.1.XXX
```

Si no se indica una versión, se utiliza `latest`. Tras cambiarla, reconstruye con `./run-claude.sh --rebuild`. Es recomendable probar las actualizaciones en una copia del proyecto.

## Construir la imagen

La primera vez:

```bash
./run-claude.sh --rebuild /ruta/al/proyecto
```

También puedes usar:

```bash
docker compose build
```

El script normal `./run-claude.sh` **no reconstruye** la imagen. Usa `--rebuild` cuando cambies el `Dockerfile`, dependencias o versión de Claude Code.

## Primer inicio de sesión

La primera vez que ejecutes `./run-claude.sh` en un PC, Claude Code pedirá iniciar sesión (`/login`). Cada PC tiene su propio login.

La configuración y autenticación persistentes se almacenan en:

```text
claude-code-home
└── /home/agent
    └── .claude/          # incluye .credentials.json y .claude.json
```

El volumen sobrevive a la eliminación del contenedor.

No ejecutes `docker compose down -v` si quieres conservar la sesión.

## Ejecutar Claude Code

Sin argumentos:

```bash
./run-claude.sh
```

El selector se intenta en este orden:

1. `zenity`.
2. `kdialog`.
3. `fzf`.

También puedes indicar la ruta:

```bash
./run-claude.sh /home/usuario/proyecto
```

Para reconstruir:

```bash
./run-claude.sh --rebuild /home/usuario/proyecto
```

Combinado con verbose:

```bash
./run-claude.sh --rebuild --verbose /home/usuario/proyecto
```

## Modo verbose

```bash
./run-claude.sh --verbose /home/usuario/proyecto
```

Muestra la ruta, propietario y permisos del workspace, UID/GID usados dentro del contenedor, mounts, volumen persistente, red, opciones de seguridad y la configuración Compose resuelta.

## Permisos del workspace

El contenedor se ejecuta con el UID/GID del usuario que lanza `run-claude.sh`. Así, los archivos creados por Claude en `/workspace` aparecen en el host con el propietario del usuario que ejecutó el sandbox.

Comprueba:

```bash
stat -c 'path=%n uid=%u gid=%g mode=%A %a' /ruta/al/proyecto
```

El script rechaza deliberadamente workspaces cuyo propietario sea UID `0`; no ejecuta Claude como root.

Si un proyecto pertenece a `root` y debe pertenecer a tu usuario:

```bash
sudo chown -R "$(id -u):$(id -g)" /ruta/al/proyecto
```

> Que el directorio raíz sea escribible no garantiza que todos sus subdirectorios lo sean; pueden existir permisos, ACLs o propietarios diferentes.

## Aislamiento

El contenedor aplica:

```yaml
read_only: true
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
```

Además:

- Los únicos bind mounts del host son el workspace (`/workspace`) y la memoria colectiva (`claude-memory/`).
- `/home/agent` es un volumen Docker persistente, no una ruta del host.
- `/tmp` y `/run` son `tmpfs`.
- No se monta `$HOME` del host.
- No se montan `.ssh`, `.gnupg` ni `.config` del host.
- No se monta `/var/run/docker.sock`.
- No se utiliza `privileged`.
- No se utiliza `network_mode: host`.
- Existen límites de memoria, CPU y procesos.

Este diseño reduce la superficie de acceso, pero no debe considerarse una frontera de seguridad absoluta. Claude tiene acceso de escritura al workspace y acceso de red.

Para mayor seguridad, usa una copia temporal o un `git worktree` en lugar del repositorio principal.

## Red

La red está habilitada porque Claude Code necesita comunicarse con servicios externos.

La configuración actual no restringe la salida a dominios concretos. Si necesitas una política de lista blanca, coloca un proxy o firewall externo delante del contenedor.

No se concede `NET_ADMIN` al agente.

## Persistencia y mantenimiento

El volumen persistente es:

```text
claude-code-home
```

Puedes verlo:

```bash
docker volume ls | grep claude-code
```

Inspeccionarlo:

```bash
docker volume inspect claude-code-home
```

### Borrar la sesión persistente

```bash
docker volume rm claude-code-home
```

El siguiente `./run-claude.sh` volverá a pedir `/login`.

## Token OAuth opcional

Para entornos automatizados, Claude Code puede utilizar `CLAUDE_CODE_OAUTH_TOKEN` si la versión utilizada lo admite.

No incluyas tokens en el Dockerfile, `docker-compose.yml`, Git, logs ni capturas.

Para uso interactivo normal, se recomienda el login persistente mediante el volumen Docker.

## Memoria

Claude usa dos memorias, y no guarda nada en ningún otro sitio: la memoria automática de Claude Code se desactiva con `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`.

| Memoria | Qué guarda | Dónde vive | Cómo viaja |
|---|---|---|---|
| **Colectiva** | Tus hábitos, métodos, gustos y reglas | `claude-memory/` dentro de docklaude, montada en `~/.claude/memoria-colectiva` | Repo git **privado**, sincronizado por `run-claude.sh` |
| **Del proyecto** | Solo el contexto de ese proyecto | `.PROJECT.md` en la raíz del proyecto (`/workspace/.PROJECT.md`) | Con el propio directorio del proyecto; nunca en su git |

- `claude-memory/CLAUDE.md` se monta como `~/.claude/CLAUDE.md`. Se carga en cada sesión, importa las dos memorias y le indica a Claude dónde guardar cada cosa. Criterio: *«¿seguiría siendo cierto en otro proyecto?»*. Si la respuesta es sí, va a la colectiva.
- `run-claude.sh`:
  - **Antes** de arrancar el contenedor: hace `pull` de `claude-memory/` y crea `.PROJECT.md` si falta. Si el proyecto es un repo git, lo añade a su `.gitignore`.
  - **Al salir:** hace commit y `push`.
- Los dos ficheros de configuración de git (el `.gitignore` de docklaude y el de cada proyecto) excluyen la memoria. docklaude es público: quien lo clone solo recibe las plantillas genéricas de `templates/`, nunca tu memoria.
- La sincronización se hace en el host, así que las credenciales de git no entran en el contenedor. Si no hay red, se trabaja con la copia local y se sube la próxima vez.

### Qué se sincroniza y qué no

Solo la **memoria** (`claude-memory/`) viaja entre PCs. El resto de `~/.claude` se queda en el volumen `claude-code-home` de cada PC: login (`.credentials.json`), `.claude.json`, `settings.json`, skills, plugins, historial y sesiones. Así las credenciales de Claude nunca pasan por git, y cada PC hace su propio `/login`.

Como defensa extra, `claude-memory/.gitignore` excluye `.credentials.json`, `.claude.json` y `*.jsonl`, y `memory-sync.sh` se niega a subir nada si alguno de ellos aparece en el repo.

### Puesta en marcha

Crea un repo **privado** vacío (GitHub, Gitea…). En cada PC, dentro de docklaude, elige una:

```bash
# a) Clonarlo a mano
git clone git@github.com:USUARIO/claude-memory.git claude-memory

# b) Dejar que run-claude.sh lo clone la primera vez
export DOCKLAUDE_MEMORY_REMOTE=git@github.com:USUARIO/claude-memory.git
```

`memory-sync.sh init` (lo ejecuta `run-claude.sh`) crea la estructura si el repo está vacío, y el primer `push` fija el upstream solo. Si `claude-memory/` es un `git init` con `origin` pero sin commits, adopta la rama remota.

Si no hay remote, `run-claude.sh` crea un `claude-memory/` local. Funciona igual, pero no se comparte entre PCs hasta que añadas uno (`git -C claude-memory remote add origin <url>`); se subirá al salir.

### Al salir de Claude Code

`run-claude.sh` hace, en este orden:

1. **Memoria colectiva.** Commit y push de `claude-memory/`, siempre y sin preguntar.
2. **Git del proyecto** (`project-sync.sh`):
   - Si hay cambios, los muestra y pregunta si hacer commit. Pide el mensaje, con uno por defecto si lo dejas vacío.
   - Si no hay cambios pero hay commits sin subir, pregunta si hacer push.
   - Hace `pull --rebase` antes del push y se detiene si hay un conflicto.
   - Si defines `SCRIPT_DIR` y existe `$SCRIPT_DIR/git_manager.sh`, se usa ese helper en su lugar.

Los dos pasos se ejecutan aunque Claude termine con error. La memoria va primero para que quede a salvo aunque cortes las preguntas del proyecto.

### Conflictos

Son raros: cada memoria colectiva es un archivo, y el índice `MEMORIA.md` usa `merge=union`. Si dos PCs editan la misma memoria de forma distinta, `run-claude.sh` avisa y muestra el archivo. Resuélvelo en `claude-memory/` (`git status`, `git rebase --continue`) y ejecuta `./memory-sync.sh push`.

## Estructura

```text
.
├── Dockerfile
├── docker-compose.yml
├── run-claude.sh
├── memory-sync.sh
├── project-sync.sh
├── templates/            # plantillas genéricas de memoria
│   ├── CLAUDE.md
│   └── PROJECT.md
├── .env.example
├── README.md
└── claude-memory/        # tu memoria colectiva privada (ignorada por git)
```

## Seguridad de credenciales

El volumen de autenticación contiene credenciales y configuración sensibles. No lo compartas ni lo expongas deliberadamente a procesos no confiables.

El workspace seleccionado sí puede ser leído y modificado por Claude Code.

Revisa los cambios antes de incorporarlos a un repositorio importante:

```bash
git diff
```

## Solución de problemas

### `EACCES` al escribir en `/workspace`

Comprueba:

```bash
./run-claude.sh --verbose /ruta/al/proyecto
ls -ldn /ruta/al/proyecto
```

El UID/GID usado por el contenedor corresponde al usuario que ejecuta `run-claude.sh`.

Si el directorio raíz es escribible pero una ruta concreta falla, comprueba los permisos, ACLs y propietarios de esa ruta.

### Claude solicita `/login` en cada inicio

Comprueba:

```bash
docker volume ls | grep claude-code-home
```

No utilices `docker compose down -v` si quieres conservar la sesión.

Si el volumen se ha eliminado, vuelve a hacer `/login` en la siguiente sesión.

### No aparece el selector gráfico

Por ejemplo:

```bash
# Arch Linux
sudo pacman -S zenity fzf

# Ubuntu/Debian
sudo apt install zenity fzf
```

También puedes indicar directamente:

```bash
./run-claude.sh /ruta/al/proyecto
```

## Licencia

Este proyecto se propone bajo **GPL-3.0-or-later**.

La GPL permite usar, estudiar, modificar y redistribuir el proyecto. Además, cuando alguien redistribuye una versión modificada del programa bajo las condiciones de la GPL, debe proporcionar las libertades correspondientes a los destinatarios, incluyendo el código fuente de la versión modificada.

Esto encaja con el objetivo de que las mejoras permanezcan dentro del ecosistema libre del proyecto. La licencia completa debe incluirse en un fichero `LICENSE`.

## Contribuciones

Las contribuciones son bienvenidas.

Si mejoras el sandbox, corriges un problema, añades soporte para otra distribución o mejoras la documentación, abre un Pull Request para que la mejora pueda incorporarse al proyecto.

Antes de contribuir:

1. Comprueba que los cambios funcionan en un entorno Docker limpio.
2. No incluyas credenciales, tokens, configuraciones personales ni datos de proyectos.
3. Documenta cambios que afecten al aislamiento o a los permisos.
4. Si modificas la seguridad, explica qué acceso adicional concede o restringe.

## Aviso

Claude Code es un producto de Anthropic. Este proyecto no es oficial de Anthropic ni está afiliado a Anthropic salvo que se indique expresamente.
