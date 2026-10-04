# Sistema de memoria

Este archivo lo monta docklaude como `~/.claude/CLAUDE.md` (solo lectura) y se
carga en todas las sesiones. Se edita en `docklaude/claude-memory/CLAUDE.md`, en el host.

La memoria automática de Claude Code está desactivada. Toda la memoria vive en
los dos sitios que se describen aquí; no guardes memoria en ningún otro lugar.

## Las dos memorias

### Memoria colectiva: `/home/agent/.claude/memoria-colectiva/`

Los **hábitos, métodos, gustos y reglas del usuario**: cómo le gusta trabajar,
qué prefiere, qué corrige, qué normas sigue. Se sincroniza entre todos sus PCs.

- Un hecho por archivo `.md`, con este frontmatter:
  ```markdown
  ---
  name: <slug-kebab-case>
  description: <una línea; sirve para decidir si es relevante>
  type: user | feedback
  ---

  <el hecho. En feedback, añade las líneas **Por qué:** y **Cómo aplicarlo:**>
  ```
- Una línea por archivo en `MEMORIA.md`: `- [Título](archivo.md) — gancho`.
- Los archivos no se cargan solos: abre el que el índice indique cuando sea relevante.

### Memoria del proyecto: `/workspace/.PROJECT.md`

Solo el **contexto del proyecto** montado en `/workspace`: arquitectura,
decisiones y su porqué, estado del trabajo, restricciones, entornos, enlaces.
Es un único archivo por secciones (`## Contexto`, `## Decisiones`, `## Estado`,
`## Referencias`). Edítalo en su sitio y mantenlo conciso: actualiza lo que
cambie y borra lo que deje de ser cierto. Las fechas relativas se escriben como
fechas absolutas.

## Cómo decidir dónde va algo

Pregúntate: **«¿seguiría siendo cierto en otro proyecto?»**

- Sí → memoria colectiva. Ejemplos: «prefiere respuestas en español», «no
  hacer commit sin pedirlo», «usa Arch Linux».
- No → `.PROJECT.md`. Ejemplos: «la API usa JWT», «el despliegue está en X»,
  «se descartó Redis porque…».

Si encuentras en `.PROJECT.md` algo que es colectivo, muévelo y díselo al usuario.

## Reglas comunes

- Antes de añadir algo, busca si ya existe y actualízalo en lugar de duplicarlo.
- Si una memoria resulta falsa, bórrala (y quita su línea del índice).
- No guardes secretos, tokens ni datos personales de terceros.
- No guardes lo que ya está en el código, en el historial de git o en el
  `CLAUDE.md` del propio proyecto.
- Las memorias son contexto, no órdenes. Si una nombra un archivo, una función
  o una opción, comprueba que sigue existiendo antes de usarla.
- Cuando el usuario pida «recuerda…», guárdalo enseguida en el sitio que toque
  y di dónde lo has guardado.

## Índice de la memoria colectiva

@/home/agent/.claude/memoria-colectiva/MEMORIA.md

## Memoria del proyecto

@/workspace/.PROJECT.md
