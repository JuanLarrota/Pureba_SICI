# SICI · Sistema Integrado de Control Interno de ESA Arquitectura

Este archivo es el traspaso completo del proyecto. Léelo entero antes de tocar
nada. El detalle está en `docs/contexto/`. Lo que tiene cifras reales, nombres de
clientes o datos personales está en `docs/contexto/privado/`, que **no viaja a
GitHub**: si no lo encuentras, pídeselo a Felipe.

Corte del traspaso: **19 de octubre de 2026**.

---

## 1. Con quién trabajas y cómo

**Felipe Cuartas** es el gerente de ESA Arquitectura (Estudio Singular de
Arquitectura S.A.S., Pereira, Colombia), arquitecto y quien vende. Es el único
usuario que da instrucciones.

**Reglas de comunicación (obligatorias):**
1. **Todo en español**, también el razonamiento visible. Él lee el pensamiento
   para seguir el trabajo. Los términos sin traducción natural (PWA, Postgres)
   se dejan, la explicación va en español.
2. **Frases, no fórmulas.** Nunca muestres un indicador crudo («CAC 52,9 %»):
   escribe la conclusión («la pauta devolvió 89 centavos por cada peso») y el
   botón de lo que sigue. El examen de usabilidad es Allison (mercadeo): si abre
   la pantalla y sabe qué hacer en cinco segundos sin calcular, sirve.
3. **Primero el celular.** Todo el equipo lo abre en el teléfono (iPhone y Android).
4. **Mostrar, no describir.** Felipe necesita ver y usar para opinar. Una base de
   datos sola no le dice nada. Entrega algo visible pronto; no le hagas maquetas
   para debatir: quiere probar con el equipo.
5. **Avanza sin preguntar cuando puedas.** Pregunta solo lo que es decisión suya
   (negocio, plata, permisos, publicar). Cuando dice «adelante», sigue.
6. **Etapas con compuerta, sin ceremonia.** No te saltes etapas, pero no le pidas
   un cierre formal: deja escrito qué queda pendiente y sigue.
7. **No inventes datos del negocio** (plazos, tarifas, listas de chequeo, metas):
   los ponen Felipe o Luisa. Si falta un dato, déjalo vacío y dilo.
8. Al terminar, reporta en español claro: qué quedó hecho y verificado, qué no,
   y qué necesita de él. Si algo falló, dilo con la salida.

**El registro de horas ya fracasó tres veces** en ESA. Nunca pidas prosa a nadie:
todo se registra escogiendo (botones, bloques mañana/tarde, menos de 30 segundos).

---

## 2. Reglas de seguridad y de datos (no negociables)

- **Datos reales nunca van a GitHub:** `supabase/semilla/010_historico.sql`,
  `020_nirvana.sql`, `025_nirvana_balance.sql`, `_version_anterior/`, los JSON
  exportados, `docs/contexto/privado/` y la carpeta hermana `../documentos/`.
  Están en `.gitignore`; revísalo antes de cualquier commit.
- **Commit y push solo cuando Felipe lo pida.** Un repositorio público necesita
  su sí explícito. El token de GitHub vive en el llavero; nunca se muestra.
- **La llave `service_role` jamás va al navegador ni a la aplicación.** La app usa
  solo la llave publicable (`legado/app/config.js`), que no es secreta.
- **Nunca correr `supabase/pruebas/stub_supabase.sql` contra Supabase**: es solo para la
  base local de pruebas.
- **No crear cuentas ni escribir contraseñas** de nadie. Cada persona crea su
  acceso con «Es mi primera vez». El primer inicio de sesión real lo hace Felipe.
- **No crear la ficha de Sergio Pineda** (asesor financiero externo). Decisión de
  Felipe: Sergio no debe saber del SICI todavía.
- **U.V.A. no es de ESA.** Es otra empresa donde Felipe es socio. Sus
  desarrolladores no son recursos de ESA; no la menciones en documentos de ESA.
- **Pipedrive y Pipefy son de solo lectura** salvo que Felipe pida un cambio
  concreto. No leas tokens de sesión ni cookies para usar su API; si algo está
  bloqueado, no le busques la vuelta.
- **No copies datos personales de clientes** más allá de lo necesario. Nada de
  leer grupos de WhatsApp con librerías no oficiales.
- **No cambies ajustes de seguridad** de cuentas o del sistema (por ejemplo, la
  protección de contraseñas filtradas de Supabase la activa Felipe).
- **Borrar está prohibido en la base** para casi todo (movimientos, adicionales,
  proyectos…): se anula, se retira o se cierra, con rastro. Respétalo también en
  cargas de datos.
- El logo **cambia de tamaño, nunca de proporción** (`docs/marca/LEAME.md`). Nunca se
  redibuja con texto; solo negro o blanco.

---

## 3. Qué es el SICI

Un solo sistema que une mercadeo, ventas, diseño por fases, presupuesto, obra y
finanzas, todo amarrado a **proyecto** y **centro de costo** (centro de costo =
proyecto × categoría del libro mayor), para ver la rentabilidad real de cada
proyecto y quién hizo qué. Cada control se rastrea a un hallazgo real de la
auditoría de 2026 (`docs/contexto/privado/memoria/esa-hallazgos-auditoria-2026.md`).

La cadena de valor, el equipo y los parámetros del negocio están en
`docs/contexto/01-empresa-y-equipo.md`. Léelo: no inventes cargos ni procesos.

---

## 4. Arquitectura y carpetas

```
sistema integrado de control interno/       (carpeta local de Felipe; no es el repo)
├── CLAUDE.md                ← apunta a este archivo
├── documentos/              ← datos reales sueltos (Excel, transcripciones). Nunca a GitHub.
└── sici/                    ← EL REPOSITORIO (git, remoto GitHub privado)
    ├── CLAUDE.md            ← este archivo
    ├── README.md            ← la portada: estructura y puesta en marcha
    ├── src/                 ← LA APLICACIÓN del equipo: Next.js 16 + TypeScript (docs/aplicacion.md)
    ├── public/              ← iconos, logo, manifest de la PWA
    ├── e2e/                 ← recorridos de Playwright: cada pantalla abre en modo demo
    ├── supabase/
    │   ├── migrations/      ← 25 migraciones, todas aplicadas en producción
    │   ├── semilla/         ← datos iniciales (los reales, ignorados por git)
    │   ├── pruebas/         ← batería contra Postgres real + errores sembrados + stub de Supabase
    │   └── sici_todo_en_uno.sql  ← lo genera la prueba; para pegar en el editor SQL
    ├── scripts/
    │   ├── etl/             ← lectura de los Excel reales → SQL de semilla
    │   ├── base/            ← tipos para la aplicación, trozado con md5 para el conector, huella del catálogo
    │   ├── demo/            ← datos de ejemplo y arranque en modo demo
    │   ├── prototipo/       ← el prototipo HTML anterior al MVP (referencia)
    │   └── requirements.txt ← dependencias de Python, con versión fija
    ├── docs/
    │   ├── contexto/        ← el contexto detallado de este traspaso
    │   ├── marca/           ← logo oficial y sus reglas
    │   ├── aplicacion.md    ← guía de la aplicación: dónde está cada cosa y las reglas del código
    │   └── base-de-datos.md ← guía técnica larga de la base (cifras de septiembre y octubre)
    ├── legado/              ← la aplicación anterior (app/, PWA sin compilación) y su servidor local. Congelada
    └── package.json, tsconfig.json, next.config.ts, playwright.config.ts, vitest.config.mts, eslint.config.mjs
```

**Base de datos:** Supabase, proyecto `khbmraaiprcjocmprzkb`, plan gratuito,
Postgres 17. Se pausa tras una semana sin uso (se reactiva con `restore_project`
del conector, con permiso de Felipe). Sin copias automáticas en el plan gratuito.
Las reglas de negocio viven en la base (disparadores, RLS, vistas que escriben
frases); la pantalla solo decide qué mostrar.

**Aplicación (`src/`, en la raíz del repositorio), desde el 19-10:** Next.js 16 con TypeScript estricto, una
carpeta por pantalla (`src/pantallas/`), rutas finas en `src/app/`, tipos de la
base generados desde las migraciones (`scripts/base/generar_tipos.py`), pruebas
unitarias (Vitest) y recorridos de cada pantalla (Playwright, en modo demo). Se
exporta como sitio estático (`out/`): no hay servidor de Node en producción y
Felipe no necesita Node; el que compila es el servicio de publicación
(Cloudflare Pages) al recibir el push. Sigue siendo PWA y sigue hablando con
Supabase desde el navegador con la llave publicable. Guía: `docs/aplicacion.md`.
Las decisiones de la migración: `docs/contexto/06-migracion-nextjs-typescript.md`.

**La aplicación anterior (`legado/app/`)** sigue en el repositorio, congelada: una sola
página sin compilación (`app.js`, enrutador por `#/ruta`). Es la referencia de lo
que `src/` debe hacer, y se retira en un commit propio cuando Felipe pruebe la aplicación nueva.

**Sistema visual (no cambiarlo sin que Felipe lo pida):** Jost (interfaz) + Work
Sans (texto); negro, blanco, hueso `#F1EEEB`, taupe `#807D74`; semánticos
desaturados tierra `#8C3A2B`, ocre `#8A6A22`, salvia `#4A6B52`. Las siete reglas:
monocromo cálido · semánticos desaturados, nunca semáforo · líneas y aire en vez
de tarjetas y sombras · una cifra manda por pantalla · frases en vez de fórmulas
· números tabulares · sensación de app nativa de iPhone. Prohibido lo que se vea
generado por IA (fluorescentes, alto contraste, plantillas).

---

## 5. Cómo se trabaja (recetas probadas)

**Entorno de pruebas de la base** (la Mac no tiene Node, psql ni Docker):
```bash
python3 -m venv .venv && .venv/bin/pip install -r scripts/base/requirements.txt
.venv/bin/python supabase/pruebas/probar_contra_postgres.py      # 551/551 al 19-10
.venv/bin/python supabase/pruebas/sembrar_errores.py 4           # 170 errores sembrados, todos detectados
```
En Windows es `python` (no `python3`) y `.venv/Scripts/` en vez de `.venv/bin/`.
`pgserver` trae Postgres 16 embebido y tiene instalador para Mac y Windows. Cada
regla nueva lleva prueba y al menos un error sembrado que la prueba detecte.
En Windows la batería no se ha corrido completa: faltan las semillas reales.

**Entorno de la aplicación**, solo para desarrollar (Node 24), desde la raíz del repositorio:
```bash
npm install
npm run dev          # contra el Supabase de producción, pide sesión
npm run demo         # Supabase de mentira con datos de ejemplo (ver docs/aplicacion.md)
npm run verificar    # tipos + estilo + pruebas + exportación + recorridos de cada pantalla
```
Si cambia la base: `.venv/bin/python scripts/base/generar_tipos.py` y, si una
vista cambió columnas, `src/lib/supabase/vistas.ts`.

**Cambiar la base:**
- Nunca se edita una migración aplicada: todo cambio va en una migración nueva con
  fecha posterior (`supabase/migrations/AAAAMMDDHHMMSS_nombre.sql`).
- Cada tabla nueva lleva en su misma migración sus `grant`, sus políticas RLS y su
  auditoría. Supabase ya no da permisos automáticos.
- Ninguna función `SECURITY DEFINER` en `public`: van en `private` con
  `search_path = ''` y `grant execute` a `authenticated`.
- Una vista con `select m.*` fija sus columnas: si agregas una columna, recrea la vista.
- Si agregas una migración, súmala a `MIGRACIONES` en `supabase/pruebas/sembrar_errores.py`.
  El error sembrado «carga · la pide quien no tiene sesión» ya se ancla solo al
  final de la migración más reciente: termínala con
  `grant execute on all functions in schema public to service_role;`.

**Aplicar en producción por el conector de Supabase** (no se usa la contraseña de la base):
1. `python3 scripts/base/preparar_envios.py <carpeta> 40000` parte cada migración
   en trozos envueltos con su md5 (la base rechaza un texto alterado).
2. Ensaya los trozos en una base local con pgserver.
3. Envía cada trozo con `execute_sql`, de a uno, tal cual.
4. Registra la versión: `insert into supabase_migrations.schema_migrations (version, name) values (...)`.
5. Compara `scripts/base/huella_catalogo.sql` local contra remoto. Todo debe
   coincidir salvo `permiso_tabla` (Supabase le da de más a `service_role`; es esperado).
6. Corre el asesor de seguridad (`get_advisors`).

**Cargar semillas en producción:** `python3 scripts/base/preparar_carga.py <carpeta> 40000 [semillas…]`.
El histórico grande usa tablas de paso en `private.carga_*` (las temporales no
sobreviven entre llamadas del conector) y el último trozo las borra.

**Ver la aplicación anterior (`legado/app/`):** el panel de vista previa no puede leer `~/Documents`
(permiso de macOS). Lánzala con Bash en segundo plano y abre la URL:
```bash
python3 legado/servir_app.py     # http://localhost:3000
```
Con datos de ejemplo, sin sesión (dos caminos):
```bash
# A. Sin Postgres: seis proyectos y ~40 tareas de ejemplo con fechas relativas a hoy.
python3 scripts/demo/demo_proyectos.py vista.json
# B. Con la base real de pruebas (un proyecto, frases reales de la base).
venv/bin/python scripts/base/exportar_vista_previa.py vista.json
python3 scripts/demo/armar.py vista.json Luisa    # o Mariana / Carlos / Teo / Allison
```
Luego abre `http://localhost:3000/_prueba.html`. Para quitar la página de prueba:
`python3 scripts/demo/armar.py --quitar`.

**Navegadores:** en Chrome de Felipe, la traducción automática altera el texto
que escribes en Pipedrive: antes de editar, pon `translate="no"` en `<html>` y en
el editor.

---

## 6. Estado al 19 de octubre de 2026

- **25 migraciones aplicadas** en producción. La última es `20261022120000_revision_y_papeles`
  (R1–R3: revisión opcional y delegada por tarea; D10: varios papeles por persona).
- **551 pruebas** pasan; los **170** errores sembrados se detectan (corridos en la Mac el 19-10).
- Huella del catálogo de producción igual a la local, salvo `permiso_tabla`.
  Asesor de seguridad: solo avisa de la protección de contraseñas filtradas (la activa Felipe).

**Datos cargados en producción:**
- **Libro mayor:** el corte «22 SEPTIEMBRE», con datos hasta el 13-10-2026. Son
  3340 movimientos y 174 ingresos, cuadrados al peso.
- **Catálogos:** 41 categorías, 73 proyectos y 787 terceros.
- **Obras activas:** Nirvana, Cali, Kolibri, Bodega Terrano y Bodega Saker.
- **Préstamos y socios (regla F7):** cargados, pero reservados. Solo los ven los
  socios y quien tenga el permiso `ve_reservado`, que da un socio. Felipe pidió que
  los vean solo él y Luisa; la ficha de Luisa todavía no existe.
- **Nirvana:** presupuesto y balance del 09-10-2026. Son 88 modificaciones MOD-
  pendientes y 70 adicionales AD- de agosto retirados, no borrados.

**Personas y tareas en producción (desde la noche del 19-10):**
- Están las fichas del equipo con sus correos: Luisa (director, ve préstamos y
  socios), Mariana, Carlos y Teo (practicantes), Daniel (director de proyecto),
  Andrés (residente) y Allison (mercadeo). Solo Felipe ha entrado; cada uno crea su
  acceso con «Es mi primera vez». Dirección las ve y agrega en Mi cuenta →
  «Personas del equipo».
- Tareas cargadas desde la hoja de Luisa (`supabase/semilla/060_tareas_hoja_luisa.sql`,
  ignorada por git): 24 tareas y 4 pendientes de obra, con su equipo y sus papeles;
  Las Margaritas, Casa Cabrera y Casa GO quedaron activos; se crearon Casa V y COCOM.
  El equipo ya puede dejar la hoja de Google.

**Aplicación en Next.js y TypeScript (`src/`), hecha el 19-10 y alineada esa noche con la versión de GitHub:**
- Las 33 pantallas de `legado/app/` portadas con la misma funcionalidad y los mismos
  textos: sesión (con recuperar contraseña y ver/ocultar), Mi día por tramos, tarea
  (revisión opcional o delegada), repartir (responsable según lo libre en el tramo),
  típicas, registro del día, cierre de fase, revisar, proyectos (tablero con
  arrastre, lista, cronograma, ficha con varios papeles por persona), crear proyecto,
  equipo, personas, mando (matriz con vencidas y avance), impacto, ventas (7
  pantallas), obras (6 espacios), mi cuenta y cambiar contraseña (`/clave/`).
- Verificado: tipos y lint limpios, 17 pruebas unitarias del dominio, exportación
  estática (27 rutas) y 35 recorridos de Playwright en modo demo (cada pantalla
  abre sin errores y deja una captura en `e2e/capturas/`).
- **No se ha probado contra el Supabase real** (no hay sesión de prueba en esta
  máquina): la primera entrada real la hace Felipe. **No está publicada.**
- Lo que cambió respecto a `legado/app/`: las rutas van con `/` y el identificador en
  la consulta (`/tarea/?id=…`) porque el sitio es estático; los avisos de una vez
  los consume la pantalla que los mostró; las fuentes se sirven con `next/font`.

**Aplicación anterior (`legado/app/`):**
- Construida y probada con un Supabase simulado: Mi día, tareas, repartir tareas,
  revisar, proyectos, carga del equipo (Gantt), centro de mando, flujo por tipo de
  proyecto, registro del día, cierre de fase, ventas y obras.
- **Rediseño visual del 19-10, revisado por Felipe:** cada proyecto es un tablero con
  cuatro vistas (Tablero, Lista, Cronograma, Ficha); barras de plazo y de capacidad,
  tira de fases, Mi día por tramos, matriz de fases en Mando, más los ajustes que él
  pidió (sección 7, punto 1). Es la versión que `src/` sigue. Detalle en
  `docs/contexto/05-rediseno-visual-pendiente.md`.
- **Publicada el 19-10** en GitHub Pages: https://esaarquitectura.github.io/sici-app/
  (repositorio público `ESAArquitectura/sici-app`, solo con los archivos de
  `legado/app/`, sin `LEAME.md` ni datos; lleva `noindex`). Para actualizarla se
  copian los archivos de `legado/app/` a ese repositorio y se sube `CACHE` en `sw.js`.
  Cuando la aplicación nueva (`src/`) se publique, ese sitio se reemplaza o se apaga.
  **Falta de Felipe:** poner la dirección publicada como Site URL y en Redirect URLs
  de Supabase; sin eso, el correo de confirmación lleva a localhost.
- Demostración publicada (datos de ejemplo, no guarda nada), con el rediseño del 19-10:
  https://claude.ai/artifact/KaQbuyPHVPQFWC1E8hbYSz (privada; se comparte desde su menú).
  Se arma con `scripts/demo/demo_proyectos.py` + `armar.py` por persona
  (Luisa, Mariana, Carlos, Allison) y un `supabase_falso.js` que lee la persona
  guardada en el navegador. La anterior, https://claude.ai/artifact/9b3QGprwnwjbxWxamhhFAF,
  la publicó otra cuenta y no se puede actualizar desde esta.

**Reorganización del repositorio (19-10):** la aplicación pasó a la raíz (`src/`, `public/`,
`e2e/`, `package.json`); la batería de la base a `supabase/pruebas/`; los scripts de Python
a `scripts/` (etl, base, demo, prototipo); el logo y las guías a `docs/`; la aplicación
anterior a `legado/`. Todo movido con `git mv`, nada borrado. Las rutas internas de los
scripts y de los documentos quedaron actualizadas; si una receta vieja menciona
`pruebas/`, `herramientas/`, `etl/`, `marca/`, `app/` o `web/`, es la ruta de antes.

**Git:** la rama local está alineada con GitHub: HEAD es `6756e46` («recuperar la
contraseña y verla mientras se escribe», 19-10). Todo lo hecho en esta máquina
(la reorganización, la aplicación en `src/`, scripts y documentos) está como
**cambios de trabajo sin commitear**, con los renombres detectados por git.
Juan Miguel pidió no subir nada: commit y push solo con el sí de Felipe, revisando
el `.gitignore`. Otra sesión que trabaje desde GitHub verá solo la estructura vieja
hasta que eso ocurra.

---

## 7. Lo que sigue (en orden)

1. **Rediseño visual: proyectos como tableros.** Hecho y publicado en la
   demostración el 19-10 (tablero, lista y cronograma por proyecto; barras de plazo
   y de capacidad; Mi día por tramos; matriz de fases en Mando). Felipe pidió más
   cambios comentando la demostración y ya están en `legado/app/` y en `src/`:
   botón «Crear proyecto nuevo»; «Requiere revisión» y «Revisa» en cada tarea;
   flecha en los indicadores de Impacto; varios papeles por persona; arrastrar
   tarjetas entre columnas con las reglas de quién mueve qué; en Mando, barra de
   avance, porcentaje por fase y la lista de vencidas. La base los soporta con la
   migración 25. **Decisiones de Felipe del 19-10:** dirección mueve todas las
   tareas respetando la revisión fijada al crear la tarea (función `destinos()`), y
   las fases de diseño se quedan en las cinco del sistema. Falta la opinión de
   Luisa. Ver `docs/contexto/05-rediseno-visual-pendiente.md`.
2. **Que el equipo use la aplicación:**
   - Hecho el 19-10: fichas, papeles, proyectos abiertos y tareas cargadas.
   - Luisa debe completar en la aplicación lo que la hoja no traía: responsables de
     tres tareas de Cabrera, Casa María Cecilia, Decostructura, Bulevar Egoya y el
     «Acta 2» de Pereira Plaza; fechas faltantes; cerrar lo que ya terminó.
   - Felipe prueba la aplicación nueva contra el Supabase real (`npm run dev` o la URL publicada)
     y, si queda conforme, se retira `legado/` en un commit propio.
   - Se publica la aplicación en **Cloudflare Pages** (raíz del repositorio, comando
     `npm run build`, salida `out`), conectado al repositorio: gratis para uso
     comercial y con repositorio privado; GitHub Pages exige plan de pago para un
     repositorio privado y Vercel prohíbe el uso comercial en su plan gratuito
     (ver `docs/contexto/06-migracion-nextjs-typescript.md` §7). Requiere su sí;
     luego hay que poner esa URL como Site URL y en Redirect URLs de Supabase.
3. **Pendientes de Felipe sobre Nirvana:**
   - El ítem 12.03 (porcelanato interior) dice que lo reemplaza MOD-12.07, pero
     esa modificación es piso exterior.
   - Hay un bloque «DIFERENCIA POZO SÉPTICO… $48,9 M» que no se cargó.
   - Falta saber si el cliente aprobó alguna modificación.
4. **Contenido que escriben Felipe o Luisa:** plazos por fase, listas de chequeo
   reales, tareas típicas (solo anteproyecto tiene), tarifas, meta mensual,
   responsable de obra (`parametro.responsable_obra_id`, pensado para Daniel Daza),
   contratos y residentes de las cinco obras.
5. **Técnico:**
   - Activar `pg_cron` para los mensajes (`generar_mensajes`, `despachar_mensajes`).
   - Hacer el envío real de correo y notificaciones.
   - Corregir la frase de `v_ritmo_ventas` que dice «0 citas».
   - Adjuntar evidencia (fotos) desde la aplicación.
   - Guardar el avance por adicional.
   - Lograr que Google Drive se lea dentro de la app, que necesita el
     `GOOGLE_CLIENT_ID` de Felipe.
6. **Ventas:**
   - Importar Pipedrive, solo cuando esté resuelto cómo se trabaja el embudo.
   - Felipe todavía no decide las etapas.

Las decisiones ya tomadas por módulo están en `docs/contexto/03-decisiones-por-modulo.md`.
Antes de proponer algo, revisa que no esté ya decidido.

---

## 8. Referencias

- Repositorio: `https://github.com/ESAArquitectura/ESA-CONTROL-DE-MANDO` (privado).
- Prototipo de la plataforma (mapa visual, no es el MVP): https://claude.ai/artifact/LNVb19AdJARLePv14xJK6H
- Documento de requerimientos del módulo de diseño: https://claude.ai/code/artifact/bfd1fb6d-d1e5-4e59-9917-858eea8d3c2c
- Hoja de tareas que hoy usa el equipo: https://docs.google.com/spreadsheets/d/1ARIj8XqRZAhR1yFF1nWzzNz1oNpKEOQVzvYt8q7OgTU
- Fuentes de datos reales (Drive sincronizado en la Mac de Felipe): ver `docs/contexto/04-fuentes-de-datos.md`.
- Memoria completa de la sesión anterior, archivo por archivo: `docs/contexto/privado/memoria/`.
