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
git clone https://github.com/USUARIO/claude-code-sandbox.git
cd claude-code-sandbox
```

Da permisos de ejecución:

```bash
chmod +x run-claude.sh auth-init.sh
```

### Fijar la versión de Claude Code

Opcionalmente:

```bash
cp .env.example .env
# Edita CLAUDE_VERSION
```

Si no se indica una versión, se utiliza `latest`.

## Construir la imagen

La primera vez:

```bash
./run-claude.sh --rebuild /ruta/al/proyecto
```

También puedes usar:

```bash
docker compose build
```

El script normal `./run-claude.sh` **no reconstruye** la imagen. Usa `--rebuild` cuando cambies el `Dockerfile`, `entrypoint.sh`, dependencias o versión de Claude Code.

## Primer inicio de sesión

Ejecuta:

```bash
./auth-init.sh
```

El script solicita un directorio y abre Claude Code para completar el login con `/login`.

La configuración y autenticación persistentes se almacenan en:

```text
claude-code-home
└── /home/agent
    ├── .claude/
    └── .claude.json
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

- `/workspace` es el único bind mount del host.
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

La configuración actual no incluye `fix-permissions.sh`.

Para borrar la configuración y autenticación persistentes:

```bash
docker volume rm claude-code-home
```

Después:

```bash
./auth-init.sh
```

## Fijar la versión de Claude Code

En `.env`:

```dotenv
CLAUDE_VERSION=2.1.XXX
```

Después:

```bash
./run-claude.sh --rebuild /ruta/al/proyecto
```

Es recomendable probar las actualizaciones en una copia del proyecto.

## Token OAuth opcional

Para entornos automatizados, Claude Code puede utilizar `CLAUDE_CODE_OAUTH_TOKEN` si la versión utilizada lo admite.

No incluy tokens en el Dockerfile, `docker-compose.yml`, Git, logs ni capturas.

Para uso interactivo normal, se recomienda el login persistente mediante el volumen Docker.

## Estructura

```text
.
├── Dockerfile
├── docker-compose.yml
├── entrypoint.sh
├── run-claude.sh
├── auth-init.sh
├── .env.example
└── README.md
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

Si el volumen se ha eliminado:

```bash
./auth-init.sh
```

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
