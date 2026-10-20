# Propuesta: llevar la aplicación a Next.js con TypeScript

Evaluación hecha el 19 de octubre de 2026 sobre el repositorio tal como está
(sin commitear el rediseño del 19-10). Es una propuesta: no se movió ningún
archivo. Las decisiones marcadas «Felipe» son suyas.

---

## 1. Lo que hay hoy (verdad de base)

| Pieza | Estado comprobado |
|---|---|
| Aplicación | `legado/app/`: una página sin compilación. `app.js` de 189 KB y ~1740 líneas, enrutador por `#/ruta`, `supabase-js` 2.45.4 desde CDN (jsdelivr), PWA con `sw.js`. Habla con 45 tablas o vistas y 16 funciones RPC de la base. |
| Base | Supabase, 24 migraciones SQL aplicadas. Todas las reglas viven en la base (RLS, disparadores, vistas que escriben frases). La pantalla solo pinta. |
| Python | 12 archivos, 5616 líneas, en `etl/`, `herramientas/` y `pruebas/`. Dependencias: `pgserver`, `psycopg2-binary`, `openpyxl`. **No hay `requirements.txt` ni `pyproject.toml`.** |
| Pruebas | Solo de la base: 537 pruebas en `probar_contra_postgres.py` y 161 errores sembrados. **La aplicación no tiene ninguna prueba automática.** |
| Integración continua | No hay `.github/`. No hay `package.json` ni archivo de bloqueo de versiones. |
| Entorno | Esta máquina (Windows) tiene Node 24.16, npm 11.13 y Python 3.11.7. `pgserver` 0.1.4 tiene instalador para Windows (comprobado con `pip --dry-run`). Las semillas reales (`010`, `020`, `025`) no están aquí: la sección 3 de la prueba fallará hasta traerlas de la Mac de Felipe. |
| Git | Dos commits. El rediseño del 19-10 (389 líneas en 6 archivos y un archivo nuevo) está sin commitear. |
| Rutas locales | `.claude/launch.json` apunta a `/Users/felipecuartas/...`. Los ETL apuntan al Drive sincronizado de la Mac. |

**Tensión que hay que decir en voz alta.** `CLAUDE.md` fija «sin compilación
porque Felipe no tiene Node» y recomienda publicar en GitHub Pages. Next.js
rompe esa premisa. Se sostiene solo si Felipe nunca compila: el despliegue lo
hace un servicio al hacer push, y en su Mac solo abre la URL publicada. Esa es
una decisión suya (publicar y, según el servicio, plata).

---

## 2. Los archivos Python, uno por uno

La regla para decidir: **lo que sirve a la base se queda en Python; lo que
existía solo porque la aplicación no se compilaba se reemplaza en TypeScript;
lo del prototipo viejo se archiva.**

### Se mantienen (infraestructura de la base, independientes de la pantalla)

| Archivo | Qué hace | Por qué se queda |
|---|---|---|
| `supabase/pruebas/probar_contra_postgres.py` (2946 líneas) | Levanta un Postgres 16 embebido, aplica las migraciones dos veces, carga el histórico, prueba las reglas de cada módulo con sesiones de cada rol, y genera `sici_todo_en_uno.sql`. | Es el activo de pruebas más valioso del proyecto. Prueba SQL, no pantalla; reescribirlo en TS no aporta nada y `pgserver` es Python. |
| `supabase/pruebas/sembrar_errores.py` | Afloja una regla a la vez en una copia de las migraciones y exige que alguna prueba lo detecte (pruebas de mutación). | Mismo motivo. Es lo que garantiza que las 537 pruebas vigilan de verdad. |
| `supabase/pruebas/stub_supabase.sql` | Imita `auth`, `storage` y los roles de Supabase en la base local. | Lo usa la batería. Nunca va a Supabase. |
| `scripts/base/preparar_envios.py` | Parte cada migración en trozos con su md5 para aplicarla a producción por el conector, sin contraseña de la base. | Es el procedimiento de despliegue de la base. No depende de la aplicación. |
| `scripts/base/preparar_carga.py` | Lo mismo para las semillas, con tablas de paso en `private.carga_*`. | Ídem. |
| `scripts/etl/cargar_historico.py` (633 líneas) | Lee los Excel reales del Drive (libro mayor 2024-2026 y balance de Nirvana) y escribe las semillas `010` y `020`. | ETL con `openpyxl`; solo corre en la Mac de Felipe, donde están los Excel. Nada que ver con la pantalla. |
| `scripts/etl/cargar_balance_obra.py` | Lee el balance más reciente de una obra y escribe `025_nirvana_balance.sql`, idempotente y sin borrar nada. | Ídem. |
| `scripts/base/exportar_vista_previa.py` | Arma un proyecto de ejemplo en Postgres temporal y exporta en JSON lo que la base le entregaría a la aplicación (Mi día, cola de revisión, carga, indicadores, mensajes). | Se queda en Python porque depende de `pgserver`, pero **cambia de destino**: su JSON pasa a ser el fixture versionado que usan la demo y las pruebas de componentes del front. Es el puente entre las frases reales de la base y TypeScript. |

### Se reemplazan en TypeScript (muletas del «sin compilación»)

| Archivo | Qué hace hoy | Qué lo reemplaza |
|---|---|---|
| `legado/servir_app.py` | Servidor estático en `localhost:3000` sin caché. | `next dev`. Se borra cuando `legado/app/` se retire. |
| `scripts/demo/armar.py` + `supabase_falso.js` | Genera `_prueba.html` con un Supabase de mentira que lee la persona guardada en el navegador. | Un cliente simulado en TS (`web/lib/supabase/simulado.ts`) activado por `NEXT_PUBLIC_MODO=demo`, con la misma interfaz que el cliente real. Sirve para la demo publicada y para Playwright. |
| `scripts/demo/demo_proyectos.py` | Datos de ejemplo: seis proyectos, ~40 tareas, fechas relativas a hoy. | Fixtures en TS (`web/pruebas/fixtures/demo.ts`) con las mismas reglas de fechas. Así la demo y las pruebas comparten datos y el cálculo de plazos se prueba con Vitest. |

### Se archivan (del prototipo anterior al MVP)

| Archivo | Qué hace | Decisión |
|---|---|---|
| `scripts/prototipo/armar_plataforma.py` | Inyecta módulos en `documentos/sici-plataforma.html`, el prototipo visual que vive fuera del repo. | Mover a `scripts/prototipo/`. No borrar sin el sí de Felipe: el prototipo es su referencia. |
| `scripts/prototipo/exportar_obras.py` | Exporta resúmenes de obras para ese prototipo. | Ídem. |
| `scripts/prototipo/*_plataforma.txt` (3 archivos) | Plantillas HTML del prototipo. | Ídem. |

Pendiente que no es de Next.js pero sale de este inventario:
- Crear `scripts/base/requirements.txt` con versiones fijas (`pgserver==0.1.4`,
  `psycopg2-binary==2.9.13`, `openpyxl==3.1.5`, las que resolvió pip hoy).
- `CLAUDE.md` dice `python3`; en Windows ese alias abre la tienda de Microsoft.
  Documentar `python` para Windows.
- Arreglar `.claude/launch.json`, que tiene la ruta absoluta de la Mac.

---

## 3. Estructura propuesta

> Nota del 19-10, más tarde: la estructura final no es esta. Juan Miguel pidió la
> aplicación en la raíz del repositorio, como en su otro proyecto; quedó así (§9).

Next.js vive en una carpeta hermana de lo que ya existe. Nada de la base, del
ETL ni de las pruebas se mueve.

```
ESA-CONTROL-DE-MANDO/
├── web/                         ← Next.js 15 (App Router) + TypeScript estricto
│   ├── app/                     ← rutas (ver tabla)
│   │   ├── (sesion)/entrar/
│   │   ├── (app)/dia/  tarea/[id]/  nueva/[proyecto]/[persona]/  revisar/
│   │   │   proyectos/  proyecto/[id]/[vista]/  equipo/  mando/  registro/
│   │   │   cierre/[fase]/  tipicas/[fase]/  ventas/  oportunidad/[id]/
│   │   │   obras/  obra/[id]/[espacio]/  personas/  yo/
│   │   ├── layout.tsx  manifest.ts  not-found.tsx
│   ├── components/
│   │   ├── ui/                  ← Cabecera, Pie, BarraPlazo, TiraFases, BarraCapacidad, Avatar, Pastilla, Cifra
│   │   └── <modulo>/            ← diseno/, obra/, ventas/, mando/
│   ├── lib/
│   │   ├── supabase/            ← cliente.ts (navegador), simulado.ts (demo), tipos.ts (GENERADO)
│   │   ├── consultas/           ← una función tipada por consulta: tareas.ts, proyectos.ts, obras.ts…
│   │   └── dominio/             ← plazo(), habiles(), fechas, frases: TS puro, con pruebas
│   ├── pruebas/
│   │   ├── unidad/              ← Vitest sobre lib/dominio y componentes
│   │   ├── recorridos/          ← Playwright en modo demo, viewport iPhone y Android
│   │   └── fixtures/            ← demo.ts + vista_previa.json (lo que exporta el script Python)
│   ├── public/                  ← iconos, logo, manifest
│   ├── .env.example             ← NEXT_PUBLIC_SUPABASE_URL, NEXT_PUBLIC_SUPABASE_KEY, NEXT_PUBLIC_GOOGLE_CLIENT_ID, NEXT_PUBLIC_MODO
│   ├── package.json  package-lock.json  tsconfig.json  next.config.ts  eslint.config.mjs
├── supabase/                    ← igual
├── etl/                         ← igual (Python)
├── pruebas/                     ← probar_contra_postgres.py, sembrar_errores.py, stub_supabase.sql
├── herramientas/                ← preparar_envios.py, preparar_carga.py, exportar_vista_previa.py, huella_catalogo.sql, requirements.txt
│   └── _prototipo/              ← armar_plataforma.py, exportar_obras.py, *_plataforma.txt
├── app/                         ← la PWA actual: CONGELADA hasta que web/ la iguale; se retira en un commit propio
├── .github/workflows/ci.yml     ← typecheck + lint + vitest + playwright (demo) en cada push
├── marca/  docs/  CLAUDE.md  README.md
```

### Decisiones técnicas y su razón

1. **Casi todo son componentes de cliente.** La seguridad y las reglas ya
   están en RLS y en las funciones de la base. Meter un servidor Next entre la
   pantalla y Supabase no agrega control y sí latencia y costo. Se usa
   `@supabase/ssr` solo para que la sesión sobreviva a la navegación y para
   el middleware que manda a `/entrar` sin sesión.
2. **Tipos generados desde la base**, no escritos a mano:
   `supabase gen types typescript --db-url <pgserver local>` contra la base
   temporal que levanta la batería Python. Así las 45 tablas/vistas y 16 RPC
   quedan tipadas y un cambio de columna rompe la compilación, no la pantalla
   en el celular. Es el primer puente Python → TypeScript y no toca producción.
3. **CSS propio, sin Tailwind ni librería de componentes.** El sistema visual
   está fijado (Jost + Work Sans, hueso, taupe, tierra, ocre, salvia; líneas y
   aire, nada que parezca plantilla). Se portan los 25 KB de `estilos.css` a
   variables globales + CSS Modules por componente. Cambiar a Tailwind sería
   rehacer el diseño que Felipe aún no aprobó.
4. **Las frases las sigue escribiendo la base.** Se conserva la regla del
   código actual: `pedir()` lanza el error de la base y `decir()` lo traduce.
   En TS son `lib/supabase/pedir.ts` y `lib/dominio/decir.ts`, con pruebas.
5. **Rutas con `/` en vez de `#/`.** Mismo mapa de pantallas (está en
   `02-estado-tecnico.md`). Esto obliga a un servidor o a un host que sirva
   `index.html` para cualquier ruta; ver el punto de publicación.
6. **PWA.** `manifest.ts` de Next y un service worker con la misma política de
   hoy (red primero, caché después). No se guardan datos en el navegador.
7. **Modo demo** por variable de entorno. La demostración publicada deja de
   ser un HTML armado por Python y pasa a ser la misma aplicación con el
   cliente simulado, desplegada como vista previa.

### Publicación (decisión de Felipe)

| Opción | Pro | Contra |
|---|---|---|
| Vercel conectado a GitHub | Despliegue automático en cada push, vistas previas por rama (ideal para que Luisa pruebe desde el celular), Felipe nunca compila. | ESA es empresa: el plan gratuito es para uso no comercial, el siguiente se paga. Precio actual: **no verificado**. |
| Cloudflare Pages / Workers | Gratis también para uso comercial, despliegue automático. | Un adaptador más (`@opennextjs/cloudflare`) que mantener. |
| GitHub Pages con `output: 'export'` | Es lo que ya recomienda `CLAUDE.md`; gratis. | Las rutas dinámicas (`/tarea/[id]`) no funcionan en estático sin trucos. Obliga a volver a `#/` o a `?id=`. Pierde parte del sentido de Next. |

Recomendación: Vercel o Cloudflare. Con cualquiera, después hay que poner la
URL como *Site URL* en Supabase (ya estaba previsto).

---

## 4. Orden de trabajo (etapas con compuerta)

0. **Congelar.** Commit del rediseño del 19-10 (con el sí de Felipe, revisando
   `.gitignore`). `requirements.txt`. Arreglar `launch.json`. Esto se hace
   antes de crear una sola carpeta nueva.
1. **Andamio.** `web/` con Next 15, TS estricto, ESLint, Vitest, Playwright;
   tipos generados; tema y componentes `ui/` portados; CI que corre en cada
   push. Compuerta: una pantalla vacía con la cabecera, el pie y las fuentes
   bien, abierta en un iPhone y un Android.
2. **Núcleo del día a día.** Entrar, Mi día, tarea, repartir, revisar,
   registro del día. Compuerta: Luisa y Mariana lo usan una semana en paralelo
   con la hoja de Google.
3. **Dirección.** Proyectos (tablero, lista, cronograma, ficha), equipo, mando,
   flujo por tipo, tareas típicas, cierre de fase.
4. **Ventas y obra.** Ventas, oportunidad, reporte de cita, tarifas, obras,
   obra por espacio, personas, mi cuenta.
5. **Demo y retiro.** Modo demo publicado. Se borran `legado/app/`, `servir_app.py`,
   `scripts/demo/`. Se actualizan `CLAUDE.md`, `legado/app/LEAME.md` →
   `docs/aplicacion.md` y `README.md` (que todavía dice 11 migraciones y 212 pruebas).

Cada etapa cierra con: pruebas en verde en CI, probado en el teléfono, y una
línea en este documento con lo que quedó abierto.

---

## 5. Hallazgos que no esperan a Next.js

| Prioridad | Hallazgo | Qué hacer | Cómo se verifica |
|---|---|---|---|
| P1 | Sin integración continua ni archivo de bloqueo. `supabase-js` llega del CDN sin `integrity`; una versión nueva en jsdelivr cambia el código que corre el equipo sin que nadie lo revise. | `package-lock.json` + CI. Mientras `legado/app/` siga viva, fijar la URL del CDN con `integrity`. | El push rompe si falla typecheck, lint o pruebas. |
| P1 | Sin pruebas de la aplicación. 189 KB de lógica de pantalla sin una sola prueba. | Vitest en `lib/dominio` (plazos, días hábiles, frases) y Playwright en modo demo para los recorridos de Allison: entrar, ver el día, entregar una tarea. | Cobertura mínima en `dominio/` al 100 %; 5 recorridos en verde. |
| P1 | Dependencias Python sin fijar. Una versión nueva de `pgserver` puede cambiar la versión de Postgres embebido y la batería dejaría de imitar producción (Postgres 17). | `requirements.txt` con versiones exactas; anotar qué Postgres trae. | `pip install -r` reproducible en Mac y Windows. |
| P2 | `README.md` desactualizado (11 migraciones, 212 pruebas). | Reescribir al cerrar la etapa 1. | Coincide con `02-estado-tecnico.md`. |
| P2 | `launch.json` con ruta absoluta de la Mac. | Ruta relativa o `npm run dev`. | Abre en cualquier máquina. |
| P3 | Plan gratuito de Supabase sin copias automáticas: no es un tema de Next, pero una migración grande es el momento en que más duele perder datos. | Antes de la etapa 2, exportar un volcado con el conector y guardarlo fuera del repo. | Un `pg_dump` restaurado una vez en pgserver. |

No se verificó: precios actuales de Vercel y Cloudflare; si `pgserver` 0.1.4
trae Postgres 16 o 17 en Windows; comportamiento de la batería Python en
Windows (tiene instalador, pero no se corrió porque faltan las semillas
reales).

---

## 6. Cómo despliega Felipe sin tener Node (añadido el 19-10)

La aplicación actual (`legado/app/`) **ya escribe en la base de producción**: su
`config.js` apunta al Supabase real. Lo que impide que el equipo la use no es
el stack: no está publicada, solo existe la ficha de Felipe y no hay tareas.

Node lo necesita solo quien desarrolla. La compilación ocurre en la nube:

1. Commit y push del repositorio (con el sí de Felipe, revisando `.gitignore`).
2. Felipe entra a Vercel o Cloudflare Pages con su cuenta de GitHub y escoge el
   repositorio. Dos o tres clics en el navegador; no instala nada. Para la
   aplicación actual, que es estática, GitHub Pages también sirve.
3. El servicio compila y entrega una URL con https.
4. Esa URL va como *Site URL* en Supabase (el correo de confirmación vuelve ahí).
5. Cada cambio posterior es: quien tenga Node edita, hace push, y uno o dos
   minutos después el equipo recarga. El service worker ya es «red primero».

El equipo abre la URL en el celular, la añade a la pantalla de inicio y crea su
acceso con «Es mi primera vez». Todos leen la misma base: lo que Luisa asigna
le aparece a Mariana al abrir Mi día.

**Orden recomendado:** no condicionar el uso real a Next.js.
1. Publicar `legado/app/` tal cual, crear las fichas, abrir los proyectos en curso e
   importar las ~40 tareas de la hoja de Luisa. Desde ese día los datos son reales.
2. Construir `web/` en paralelo contra la misma base; cuando iguale a la actual,
   recibe la misma URL y `legado/app/` se retira.

Con datos reales del equipo pesan más dos cosas del plan gratuito de Supabase:
se pausa tras 7 días sin uso (con uso diario no pasa; Felipe lo reactiva desde
el panel) y no tiene copias automáticas (volcado periódico o plan de pago:
decisión de Felipe).

---

## 7. Dónde publicar la aplicación actual (19-10; Next.js descartado por ahora)

Verificado contra la documentación oficial el 19-10-2026. El repositorio es
**privado** y pertenece a una **empresa**; eso decide.

| Servicio | Veredicto | Motivo |
|---|---|---|
| **Cloudflare Pages** | **Recomendado** | Plan gratuito sin restricción de uso comercial; se conecta a repos privados de GitHub; despliega solo en cada push. Límites: 500 despliegues/mes, 20.000 archivos, 25 MiB por archivo, 100 dominios. La app tiene 20 archivos y 189 KB el mayor. Cloudflare empuja hacia Workers; si cierran Pages, son los mismos archivos. |
| GitHub Pages | No, salvo plan de pago | En organización con plan gratuito, Pages solo funciona con repositorio público. Hacerlo público no es opción (migraciones con la lógica del negocio, documentos con el equipo). Desde privado exige Team o superior; la documentación de GitHub no coincide en cuál. **Esto corrige la recomendación de `CLAUDE.md` §7.** |
| Vercel | No en plan gratuito | El plan Hobby es solo para uso personal no comercial; un sitio de empresa cuenta como comercial aunque no cobre, y Vercel puede pausarlo sin aviso. Exigiría plan de pago desde el día uno para servir archivos estáticos. |

**Pasos para Felipe (sin terminal ni Node):**
1. Commit y push del repositorio (con su sí, revisando `.gitignore`).
2. Cuenta en Cloudflare → Workers y Pages → Crear → Pages → Conectar con Git →
   autorizar el repositorio privado de ESAArquitectura.
3. Comando de compilación: vacío. Carpeta de salida: `app`. Desplegar.
4. URL `<nombre>.pages.dev`; opcional dominio propio (`sici.esaarquitectura.com`).
5. Esa URL como *Site URL* y en *Redirect URLs* de Supabase.

No verificado: precios de Vercel Pro y GitHub Team; si Cloudflare exige el DNS
en su red para el dominio propio.

Fuentes: GitHub Pages limits y «Creating a GitHub Pages site» (docs.github.com);
Vercel «Fair Use Guidelines» y «Hobby plan» (vercel.com/docs); Cloudflare Pages
«Limits» (developers.cloudflare.com/pages/platform/limits).

---

## 8. Lo hecho el 19-10 (Felipe decidió: Next.js y TypeScript, misma funcionalidad)

- La aplicación existe y compila: Next.js 16.4, TypeScript estricto, React 19, supabase-js 2.118.
  Exportación estática (`output: "export"`), PWA, fuentes con `next/font`.
- Las 32 pantallas de `legado/app/` están portadas con los mismos textos, clases CSS y
  reglas (`docs/aplicacion.md` dice dónde está cada una). `legado/app/` queda congelada hasta
  que Felipe pruebe la aplicación nueva.
- Tipos de la base generados desde las migraciones con `scripts/base/generar_tipos.py`
  (74 tablas, 35 vistas, 19 funciones, 39 enums). La CLI de Supabase exige Docker
  para hacerlo contra una base local, así que el script lee el catálogo de
  Postgres directamente y escribe el mismo formato que entiende supabase-js.
- Verificación: `npm run verificar` corre tipos, lint, 15 pruebas unitarias del
  dominio, la exportación y 34 recorridos de Playwright en modo demo (cada
  pantalla abre sin errores de JavaScript y deja una captura).
- Integración continua lista en `.github/workflows/web.yml` (corre cuando haya push).
- Pendientes de este tramo:
  - Probar contra el Supabase real con la sesión de Felipe (aquí no hay sesión).
  - Publicar en Cloudflare Pages (decisión de Felipe) y poner la URL en Supabase.
  - Retirar `legado/app/`, `legado/servir_app.py` y `scripts/demo/armar.py`
    cuando la aplicación nueva esté aprobada. Los datos de la demo todavía los arma `armar.py --web`;
    pasarlos a fixtures en TypeScript sigue siendo lo propuesto en §2.
  - En Windows, la batería `probar_contra_postgres.py` todavía no se corre completa
    (faltan las semillas reales). Se corrigió que el psql de Windows ignoraba las
    opciones puestas después de la URI.

---

## 9. Reorganización del repositorio (19-10, pedida por Juan Miguel)

La aplicación pasó a la raíz, como en el otro proyecto Next.js del equipo, y lo
demás quedó en carpetas con sentido. Todo movido con `git mv`; nada borrado.

| Antes | Ahora |
|---|---|
| `web/src`, `web/public`, `web/package.json`… | `src/`, `public/`, `package.json`… en la raíz |
| `web/pruebas/recorridos/` | `e2e/` |
| `web/herramientas/demo.mjs`, `pruebas/app_simulada/*` | `scripts/demo/` |
| `pruebas/probar_contra_postgres.py`, `sembrar_errores.py`, `stub_supabase.sql` | `supabase/pruebas/` |
| `etl/` | `scripts/etl/` |
| `herramientas/{generar_tipos,preparar_envios,preparar_carga,exportar_vista_previa}.py`, `huella_catalogo.sql`, `requirements.txt` | `scripts/base/` |
| `herramientas/{armar_plataforma,exportar_obras}.py`, `*_plataforma.txt` | `scripts/prototipo/` |
| `app/`, `herramientas/servir_app.py` | `legado/app/`, `legado/servir_app.py` |
| `marca/` | `docs/marca/` |
| `README.md` (guía larga de la base), `web/LEAME.md` | `docs/base-de-datos.md`, `docs/aplicacion.md`; `README.md` nuevo es la portada |

Las rutas internas de los scripts (`RAIZ`, `sys.path`, salidas) y las de la
configuración (Playwright, ESLint, CI, `launch.json`) quedaron actualizadas, y la
verificación completa volvió a correr.

---

## 10. Integración de los commits de GitHub (19-10, noche)

Mientras aquí se construía `src/`, en la Mac de Felipe se subieron cinco commits
(`4c67e22` → `6756e46`): otra implementación del rediseño, los ajustes que Felipe
pidió al comentar la demostración, la **migración 25** (`revision_y_papeles`:
revisión opcional y delegada por tarea, varios papeles por persona), las fichas
del equipo y las tareas cargadas, la PWA anterior publicada en GitHub Pages
(`ESAArquitectura/sici-app`) y la recuperación de contraseña.

Cómo se integró, pieza por pieza:
- **Base y pruebas:** la migración 25, `sici_todo_en_uno.sql`, la batería (sección
  23, 551 pruebas) y los 9 errores sembrados nuevos se trajeron tal cual a
  `supabase/` y `supabase/pruebas/`, reaplicando las rutas nuevas y el arreglo del
  psql de Windows. Tipos regenerados (`requiere_revision`, `revisor_id`;
  `v_cola_revision` con `revisor_id`).
- **La aplicación anterior:** `legado/app/` pasó a ser la versión remota completa
  (la que Felipe revisó). Es la fuente de verdad de lo que `src/` debe hacer.
- **`src/`:** se alineó con esa versión, no al revés: CSS remoto portado a
  `globals.css`; piezas nuevas (barra de plazo `.pz`, capacidad por tramos `.cap`,
  tira de fases `.tf`, estado `.ch`, avance `.av-g`); Mi día por tramos; revisión
  por tarea y responsable según lo libre en el tramo (Nueva, Típicas, Tarea);
  tablero con arrastre y la regla `destinos()`; varios papeles por persona en la
  ficha y en «Crear proyecto nuevo»; matriz de Mando con vencidas y avance;
  recuperar contraseña, ver/ocultar y «Cambiar mi contraseña» (`/clave/`);
  «Personas del equipo» desde Mi cuenta y Mando; flecha en Impacto.
- **Demo:** tres pasos (`datos_ejemplo.py` → `armar.py --web` → `demo_proyectos.py`,
  que es el remoto y trae los proyectos y tareas de la hoja de Luisa). El Supabase
  simulado aplica los `update` en memoria y responde a la recuperación de contraseña.
- **Documentos:** CLAUDE.md y `docs/contexto/02`, `03`, `05` con el estado remoto
  (25 migraciones, 551 pruebas, 170 errores sembrados, fichas y tareas cargadas,
  decisiones de Felipe) encima de la estructura nueva.
- **Git:** la rama local se alineó con `origin/main` sin crear commits
  (`git reset --mixed origin/main`): HEAD es el último commit remoto y todo lo
  hecho aquí queda como cambios de trabajo, con los renombres detectados.

Verificación tras integrar: tipos y lint limpios, 17 pruebas unitarias, 27 rutas
exportadas y 35 recorridos de Playwright en verde.

Lo que no se pudo verificar aquí: la batería Python completa (faltan las semillas
reales) y la aplicación contra el Supabase real (sin sesión en esta máquina).
