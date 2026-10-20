# Estado técnico al 19 de octubre de 2026 (noche)

## Migraciones (las 25 aplicadas en producción; ninguna se edita)

| Versión | Qué trae |
|---|---|
| `20260914120000_esquema_inicial` | 62 tablas, tipos, funciones, disparadores, vistas y reglas de alerta de los módulos M-00 a M-08 |
| `…120100` a `…120700_rls_*` | Las políticas por fila de cada módulo: núcleo, comercial, diseño, presupuestos, obra (con el portal del cliente), reclamaciones y finanzas |
| `…120800_permisos_api` | Cierra los permisos por defecto de Supabase; la API solo da lo que conceden las políticas |
| `…120900_almacenamiento` | Dos depósitos privados |
| `…121000_vinculo_usuarios` | Enlaza la cuenta de Supabase con la ficha por correo |
| `20261012120000_fases_por_tipo` | Fases según el tipo de proyecto; rol `director_proyecto`; profesión |
| `20261012120100_modulo_diseno` | Equipo con papel, plantillas, flujo de revisión y «Mi día» |
| `20261012120200_indicadores` | Indicadores de impacto por persona, sacados de hechos |
| `20261012120300_mensajes` | Mensajes con límites y horario (falta `pg_cron` para enviarlos) |
| `20261013120000_aplicacion` | `mi_sesion()`, carpeta de Drive por proyecto |
| `20261014120000_carga_semanal` | `dias_estimados` y `carga_semanal()` |
| `20261015120000_flujo_por_fase` | Plazo y responsable por fase |
| `20261016120000_tareas_tipicas` | Tareas típicas al abrir una fase; aviso de fase terminada |
| `20261017120000_cierre_de_fase` | Listas de chequeo con tipo, registro del día, cierre de fase |
| `20261018120000_embudo_de_ventas` | Reglas V1–V4, citas, reporte, tarifas |
| `20261019120000_modulo_obra` | O12–O15: factura, documentos, `registrar_gasto`, tablero de obras |
| `20261020120000_prestamos_y_socios` | F7: lo reservado |
| `20261021120000_adicional_retirado` | Retiro de adicionales con razón |
| `20261022120000_revision_y_papeles` | R1–R3: revisión opcional por tarea y revisión delegada en una persona; D10: varios papeles por persona en un proyecto (la llave de `acceso_proyecto` incluye el papel) |

## Semillas (`supabase/semilla/`)

| Archivo | Qué es | ¿Va a GitHub? |
|---|---|---|
| `010_historico.sql` | Libro mayor 2024–2026: catálogos, 3340 movimientos, 174 ingresos | **No** (datos reales) |
| `020_nirvana.sql` | Presupuesto, ejecución y adicionales de Nirvana según el balance del 27-08 (congelado) | **No** |
| `025_nirvana_balance.sql` | El balance del 09-10 encima del anterior (`scripts/etl/cargar_balance_obra.py`) | **No** |
| `030_clasificacion.sql` | Clasificación hecha a mano: exclusiones, reservados, ADMINISTRATIVO | Sí |
| `040_plantillas.sql` | Plantillas de proyecto, fases, tareas típicas, festivos | Sí |
| `050_obras_en_curso.sql` | Las cinco obras que quedan activas | Sí |
| `_resumen.txt` | Qué se cargó y qué se descartó, con cifras | Sí (revísalo antes) |

La prueba aplica, en orden: las migraciones, luego 010, 020, 025 y 030–050. Sin
los archivos reales en disco, la sección 3 de la prueba falla: en una copia sin
datos reales hay que traerlos de la Mac de Felipe.

## Pruebas

- `supabase/pruebas/probar_contra_postgres.py`: 23 secciones y 551 pruebas.
  - Cubre idempotencia, el asesor de Supabase contra el catálogo y el histórico
    cuadrado al peso.
  - Cubre las reglas de cada módulo y sesiones reales de todos los roles,
    incluido el portal del cliente.
  - Si todo pasa, genera `supabase/sici_todo_en_uno.sql`.
- `supabase/pruebas/sembrar_errores.py`: siembra un error a la vez (afloja una regla) y
  exige que alguna prueba se dé cuenta. Son 170.
- `scripts/demo/`: un Supabase de mentira para recorrer las pantallas sin
  sesión (`armar.py`).

## Producción (Supabase `khbmraaiprcjocmprzkb`)

- Plan gratuito: se pausa tras 7 días sin uso y no tiene copias automáticas.
- Asesor de seguridad: solo el aviso de contraseñas filtradas (lo activa Felipe).
- Personas: Felipe y las fichas del equipo (19-10), más la persona inactiva «Carga histórica · libro mayor».
- 24 tareas y 4 pendientes de obra cargados el 19-10 desde la hoja de Luisa; las fichas del equipo existen desde ese día.

## La aplicación (`src/`, en la raíz del repositorio, desde el 19-10)

Next.js 16 con TypeScript, exportada estática. Una carpeta por pantalla en
`src/pantallas/`, rutas finas en `src/app/`. Mismas pantallas que `legado/app/`,
con el identificador en la consulta: `/tarea/?id=…`, `/proyecto/?id=…&vista=lista`,
`/obra/?id=…&seccion=gastos`. Tipos de la base generados (`scripts/base/generar_tipos.py`).
`npm run verificar` corre tipos, lint, pruebas unitarias, exportación y 34 recorridos
en modo demo. Guía: `docs/aplicacion.md`. No probada aún contra el Supabase real; no publicada.

## La aplicación anterior (`legado/app/`, congelada)

Rutas principales: `#/` Mi día, `#/tarea/<id>`, `#/nueva/<proyecto>/<persona>`
(Repartir tareas), `#/revisar`, `#/proyectos`, `#/proyecto/<id>`, `#/equipo`
(Gantt de carga), `#/mando` (centro de mando), `#/registro`, `#/cierre/<fase>`,
`#/tipicas/<fase>`, `#/ventas`, `#/oportunidad/<id>`, `#/obras`,
`#/obra/<id>/<espacio>`, `#/personas`, `#/yo`.

Reglas del código: las frases las escribe la base, la pantalla las pinta;
`pedir()` lanza el error de la base; `decir()` lo traduce a frase; las acciones
van por `data-accion` y los formularios por `data-form`.
