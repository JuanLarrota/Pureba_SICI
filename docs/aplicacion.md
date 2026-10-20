# SICI · la aplicación del equipo en Next.js y TypeScript

La misma aplicación que vivía en `legado/app/` (una sola página sin compilación), con
las mismas pantallas, los mismos textos y el mismo sistema visual, reescrita en
Next.js 16 con TypeScript estricto para tener orden: una carpeta por pantalla,
tipos de la base generados, pruebas y verificación automática.

Sigue siendo **una aplicación de navegador**: toda regla vive en la base
(RLS, disparadores, funciones y vistas que escriben frases). La pantalla solo
decide qué mostrar. Por eso se exporta como sitio estático (`output: "export"`)
y se sirve desde cualquier host de archivos, sin servidor de Node.

## Cómo se corre

Hace falta Node 24 (solo para desarrollar; para usar la aplicación publicada no
hace falta nada). Todo se corre desde la raíz del repositorio.

```bash
npm install
npm run dev          # http://localhost:3000 contra el Supabase de producción (pide sesión)
npm run demo         # http://localhost:3100 con un Supabase de mentira; no guarda nada
npm run verificar    # tipos + estilo + pruebas unitarias + exportación + recorridos
```

Para la demo primero hay que armar los datos de ejemplo (ningún nombre es real):

```bash
python scripts/demo/datos_ejemplo.py /tmp/demo.json                 # un proyecto de ejemplo y el embudo de ventas
python scripts/demo/armar.py /tmp/demo.json Luisa --web          # o Mariana / Carlos / Teo / Allison
python scripts/demo/demo_proyectos.py public/demo/datos.json Luisa  # los proyectos y tareas de la hoja de Luisa, con fechas ajustadas
```

Eso escribe `public/demo/datos.json` (no va a GitHub). `npm run demo`
arranca con `NEXT_PUBLIC_MODO=demo`; otro puerto: `PUERTO=3177 npm run demo`.

## Dónde está cada cosa

```
(raíz del repositorio)
├── src/app/                  las rutas. Cada page.tsx es fino: lee ?id= y pinta la pantalla
│   ├── layout.tsx            fuentes (Jost, Work Sans), sesión, marco
│   ├── page.tsx              Mi día
│   ├── tarea/ nueva/ revisar/ proyectos/ proyecto/ nuevo-proyecto/ tipicas/ cierre/ registro/
│   ├── equipo/ personas/ mando/ impacto/ yo/
│   ├── ventas/ embudo/ oportunidad/ reporte/ contacto/ contacto-nuevo/ tarifas/
│   └── obras/ obra/
├── src/pantallas/            una carpeta por módulo, un archivo por pantalla
│   ├── sesion/               Entrar, SinFicha
│   ├── dia/                  MiDia
│   ├── tareas/               Tarea, Nueva (+Pista), Tipicas, Registro, Cierre
│   ├── proyectos/            Proyectos, Proyecto (Tablero, Lista, Cronograma, Ficha), NuevoProyecto, Revisar
│   ├── equipo/               Equipo (+carga), Personas, Impacto
│   ├── mando/                Centro de mando
│   ├── ventas/               Ventas, Embudo, Oportunidad, Reporte, Contacto, ContactoNuevo, Tarifas
│   ├── obras/                Obras, Obra (Resumen, Gastos, Flujo, Documentos, Pendientes, Sitio)
│   └── cuenta/               Yo
├── src/componentes/
│   ├── marco/                Pantalla (cabecera, aviso, pie, botón +), Marco (sesión), Carga
│   ├── formularios/          Formulario (envía y muestra el error), Boton (acción), Opciones
│   ├── ui/piezas.tsx         BarraPlazo, BarraCapacidad, TiraFases, Avatar, Pastilla, Marca, Kpis, Cifra, Fila…
│   └── Drive.tsx             la carpeta de Drive con la cuenta de Google de cada quien
├── src/lib/
│   ├── config.ts             URL y llave publicable de Supabase, Google, modo demo
│   ├── supabase/cliente.ts   el único cliente (real o simulado)
│   ├── supabase/tipos.ts     GENERADO desde las migraciones (scripts/base/generar_tipos.py)
│   ├── supabase/vistas.ts    lo que garantizan las vistas y las funciones que escriben frases
│   ├── supabase/simulado.ts  el Supabase de mentira de la demo
│   ├── sesion.tsx            usuario, ficha (mi_sesion), aviso de una vez, ir(), recargar()
│   ├── useDatos.ts           lo que una pantalla le pide a la base al abrirse
│   ├── pedir.ts              pedir() lanza el error de la base; decir() lo traduce a frase
│   ├── rutas.ts              R.tarea(id), R.proyecto(id, vista)… en un solo lugar
│   ├── consultas.ts          asignables, gente, nombresDe
│   ├── drive.ts              Google Drive
│   └── dominio/              fechas, texto, catálogos (códigos → palabras), plazo (barras y resúmenes)
├── src/pruebas/              Vitest: las reglas que la pantalla calcula sola
├── e2e/                      Playwright: abre cada pantalla en modo demo y guarda una captura
├── public/                   iconos, logo, manifest, sw.js, demo/datos.json (ignorado)
├── scripts/demo/demo.mjs     arranca la demo
└── scripts/base/generar_tipos.py  regenera src/lib/supabase/tipos.ts desde las migraciones
```

## Las reglas del código

- **Las frases las escribe la base, la pantalla las pinta.** `pedir()` lanza el
  error tal como lo dijo la base; `decir()` lo vuelve frase. Nada de lógica de
  permisos en la pantalla: si la base dice que no, se muestra lo que dijo.
- **Una pantalla = `useDatos` + `Carga` + `Pantalla`.** El cargador pide todo
  junto con `Promise.all`; `Carga` muestra «Abriendo…» o el error; `Pantalla`
  pone cabecera, aviso, contenido y pie.
- **Acciones con `Boton`, formularios con `Formulario`.** Tras guardar en la
  misma pantalla: `avisar(bien("…")); recargar()`. Si se cambia de pantalla:
  `ir(R.x(…), bien("…"))`. El aviso se ve una vez y la pantalla que lo mostró
  se lo lleva al cerrarse.
- **Tipos.** `tipos.ts` se genera desde la base y no se edita. Las vistas se
  leen con `.overrideTypes<VAlgo[], { merge: false }>()` y las interfaces de
  `vistas.ts`, porque el generador no sabe qué columna de una vista es nula.
  Los campos enum se castean al literal al escribir (`estado: "en_curso" as const`).
  El texto de un `select` va en una sola cadena literal: concatenado pierde el tipo.
- **Rutas.** El sitio es estático, así que los identificadores van en la
  consulta: `/tarea/?id=…`. Todas las rutas se construyen con `R` de `rutas.ts`.
- **Sistema visual.** `globals.css` es `legado/app/estilos.css` portado sin cambiar
  nada. Jost y Work Sans se sirven con `next/font` (sin CDN). No se agregan
  librerías de componentes ni Tailwind.
- **Español en todo**, código incluido, como el resto del repositorio.

## Cuando cambia la base

1. Nueva migración en `supabase/migrations/`, como siempre.
2. `.venv/Scripts/python scripts/base/generar_tipos.py` (Mac: `.venv/bin/python`).
3. Si una vista cambió columnas, actualizar su interfaz en `src/lib/supabase/vistas.ts`.
4. `npm run typecheck`: lo que se rompió sale aquí, no en el celular.

## Publicar

Cloudflare Pages conectado al repositorio de GitHub. Carpeta raíz la del
repositorio, comando `npm run build`, carpeta de salida `out`. Cada push despliega. Luego la
URL va como *Site URL* y en *Redirect URLs* de Supabase. El detalle y las
alternativas están en `docs/contexto/06-migracion-nextjs-typescript.md`.
