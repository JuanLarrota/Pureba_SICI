# Rediseño visual: cada proyecto como un tablero (pedido en curso)

Pedido de Felipe del **19-10-2026**, tras revisar la demostración publicada
(https://claude.ai/artifact/9b3QGprwnwjbxWxamhhFAF).

**Estado (19-10-2026, noche): primera versión hecha y publicada** en la misma
demostración (versión 2) y en GitHub Pages. Las secciones 1 a 5 del plan están
construidas en `legado/app/app.js` y `legado/app/estilos.css` (la versión que
Felipe revisó y comentó) y portadas a la aplicación nueva (`src/`). La
demostración se arma con `datos_ejemplo.py`, `armar.py --web` y `demo_proyectos.py`.

Felipe decidió el 19-10 que **las fases de diseño se quedan en las cinco del
sistema** y que **dirección mueve todas las tareas**, respetando la revisión
fijada al crear la tarea. Falta la opinión de Luisa y probarla con datos reales.

> Nota: esa misma tarde hubo una segunda versión del rediseño hecha en paralelo en
> otra sesión, con las diferencias que se listan abajo. Al traer los commits de
> GitHub se adoptó la versión de Felipe; estas notas quedan como historia.
- El avance general de un proyecto es el **promedio de sus fases** (cerrada 100,
  en curso lo que lleven sus tareas, por abrir 0), como en la matriz del Excel; no
  la razón de tareas terminadas, que dejaba en 0 % un proyecto con cuatro fases
  cerradas.
- En Mi día los grupos por fecha reemplazan a los de la base en pantalla, pero lo
  que la base dice (devuelta, alguien la espera, la espera a alguien) va como marca
  en cada tarjeta, y su frase se conserva.
- Los datos de demostración ya no salen de la base de pruebas sino de
  `scripts/demo/demo_proyectos.py` (sin Postgres), y `armar.py` acepta
  varios proyectos. `exportar_vista_previa.py` sigue funcionando.
- En pantalla grande, el tablero, la lista y el cronograma usan todo el ancho,
  como el centro de mando.

**Pendiente de Felipe y Luisa:**
1. Verlo en el celular y opinar (tablero, lista, cronograma, Mi día, Mando).
2. Las fases del Excel de Luisa («01 Concepto e ideas … 06 Supervisión de obra»)
   no son las de la base (insight, anteproyecto, proyecto final, licencia,
   presupuesto). Si quieren las suyas, es una decisión de negocio y lleva migración.
3. ~~Regenerar la demostración publicada~~ Hecho: quedó en una URL nueva,
   https://claude.ai/artifact/KaQbuyPHVPQFWC1E8hbYSz, porque la anterior la publicó
   otra cuenta. Es privada hasta que Felipe la comparta desde su menú.

## Lo que pidió (sus palabras, resumidas)

- **Cada proyecto se maneja como un tablero de Trello**, con varias maneras de
  verlo: el estado, el avance y a quién está asignada cada tarea.
- **Según quién lo mire:** cada persona ve los objetivos que debe cumplir en el
  día o en la semana.
- **Desde el tablero del director de proyecto:** el avance por cada fase del
  proyecto, las fases ya cumplidas y las que faltan.
- **Mantener el aspecto gráfico actual** (ver la sección 4 del `CLAUDE.md`), pero
  con la información muy gráfica. «En este momento tienes demasiado texto»: hoy,
  para saber cuánto tiempo libre tiene una persona en la semana hay que leer.
- **Barritas:** si a Mariana le faltan 2 días para una entrega, una barrita lo
  muestra a punto de vencer. Si una tarea está vencida o por vencerse, la barra
  lo dice con un color llamativo. Dentro de la paleta, eso es tierra para vencida
  y ocre para por vencer; el sistema visual prohíbe el semáforo saturado.
- El Excel de Luisa es la referencia **de orden**, no gráfica: cómo espera ella
  ver la información. Las imágenes son referencia de los **tipos de diagrama**.

## Referencias (en `referencias-visuales/`)

**1. `excel-de-luisa-Seguimiento_Proyectos_Arquitectura.xlsx`, con tres hojas:**
- **Seguimiento.**
  - Columnas: ID · Proyecto · Fase actual · Tarea/Entregable · Responsable ·
    Inicio · Fin · Duración · % Avance · Estado · Falta por ejecutar.
  - Un **cronograma por semanas** a la derecha: celda llena (1) en las semanas
    que toca la tarea, en azul.
  - Estados con color: No iniciado (gris), En progreso (azul), En revisión
    (amarillo), Completado (verde), Retrasado (rojo).
- **Dashboard.**
  - Cuatro cifras arriba: total de tareas, en progreso, completadas, retrasadas.
  - Un resumen por estado.
  - **«Matriz de control: estado de fases por proyecto»**: una fila por proyecto,
    con su avance general (promedio del % de sus tareas) y una columna por fase.
    Cada celda dice «En curso» si alguna tarea de esa fase va en progreso o en
    revisión, «Retrasado» si alguna va retrasada y «Completado» si están
    completadas; si no hay tareas, queda vacía.
- **Configuración.**
  - Fases: 01 Concepto e ideas · 02 Anteproyecto · 03 Proyecto arquitectónico ·
    04 Proyecto ejecutivo · 05 Licencias y permisos · 06 Supervisión de obra.
  - Responsables por cargo, no por nombre.
  - **Ojo:** esas fases no son las de la base (insight, anteproyecto, proyecto
    final, licencia, presupuesto). No las cambies sin decisión de Felipe o Luisa;
    pregúntalo cuando muestres el rediseño.

**2. `monday-tabla-por-fases.png`:**
- La tabla agrupada por fase (Planificación, Ejecución), cada grupo con su color
  en el borde.
- Columnas: tarea, responsable con avatar, fecha, estado como celda de color y
  cronograma como barra de avance.
- Pestañas de vista arriba: Tabla principal · Kanban · Gantt.

**3. `momentum-tablero-cronograma-cifras.webp`:**
- **Kanban** con columnas por estado (Backlog, In progress, Review, Done) y su
  contador.
- Tarjetas con etiqueta de fase, avatar, fecha y barra de avance.
- Debajo, el **cronograma por semanas**, agrupado por fase, con la línea de hoy.
- Abajo, cifras: total, en curso, completadas, vencidas y avance %.

**4. `cronograma-por-fases.png`:**
- Gantt por fases, cada fase con su rango de fechas y su equipo, y las tareas
  como barras.
- Barras con dos tonos: la parte hecha más oscura.
- Dependencias dibujadas como flechas.

**5. Trello** (cuenta de Felipe, «Mi tablero de Trello»; se miró solo, sin cambiar nada):
- Listas **Hoy · Esta semana · Más tarde** y una bandeja de entrada.
- Un planificador por día al costado.
- Vistas: Tablero, Tabla, Calendario, Panel, Cronograma y Mapa.
- Las tarjetas llevan el avatar del miembro y la fecha. La fecha se pinta
  distinto si vence pronto o ya venció.

## Plan acordado conmigo mismo (propuesta; Felipe aún no lo vio)

Todo en la aplicación (`legado/app/app.js` + `legado/app/estilos.css`), **sin migración**: los
datos ya existen en `tarea_diseno` (inicio, entrega, estado, responsable, fase,
`dias_estimados`), `proyecto_fase`, `v_fase_avance` y `carga_semanal()`.

### 1. Componentes visuales nuevos (reutilizables)

- **Barra de plazo** de una tarea: va del inicio a la entrega y se llena con lo
  que ya pasó. Colores:
  - salvia si va a tiempo;
  - ocre si faltan 2 días hábiles o menos;
  - tierra si está vencida, llena del todo y con el exceso marcado;
  - gris si está terminada o en revisión.
  Al lado, el texto corto: «faltan 2 d», «vence hoy», «vencida 3 d». Va en todas
  las tarjetas y filas.
- **Barra de capacidad semanal** de una persona: días ocupados contra días
  hábiles, en salvia, ocre si queda menos de medio día y tierra si está pasada.
  Reemplaza frases como «Le quedan 2 días esta semana» en Equipo, en Mando y en
  Repartir tareas, debajo del selector de responsable.
- **Tira de fases** de un proyecto: un segmento por fase, en orden:
  - cerrada: negro lleno;
  - en curso: con su avance (terminadas sobre tareas, de `v_fase_avance`);
  - con fecha vencida: tierra;
  - por abrir: solo contorno.
  Cada segmento lleva su nombre corto.
- **Avatar**: un cuadrado negro con las iniciales, del mismo estilo que el botón
  «yo» de la cabecera.
- **Pastilla de estado** con los semánticos desaturados:
  - por empezar: gris;
  - en curso: tinta;
  - en revisión: ocre;
  - devuelta: tierra;
  - terminada: salvia.

### 2. Proyecto como tablero (`#/proyecto/<id>/<vista>`)

- **Cabecera:**
  - nombre del proyecto;
  - tira de fases;
  - cifras: total, en curso, en revisión, terminadas, vencidas y avance %. Una
    sola cifra manda: el avance o las vencidas, si hay.
- **Pestañas:** Tablero · Lista · Cronograma · Ficha. La primera es la que se abre.
- **Tablero:** columnas Por empezar · En curso · En revisión · Devuelta ·
  Terminada, con su contador. En el celular, las columnas se deslizan de lado,
  una a la vez. Cada tarjeta lleva título, etiqueta de fase, avatar, fecha y
  barra de plazo, y abre la tarea.
- **Lista:** agrupada por fase, al estilo monday y del Excel de Luisa. Cada fase
  lleva su borde de color según su estado y una fila por tarea: título, avatar,
  fecha, pastilla de estado y barra de plazo.
- **Cronograma:** un Gantt por semanas agrupado por fase, con la línea de hoy.
  - Barras del inicio a la entrega, en dos tonos (lo pasado y lo que falta).
  - Las vencidas se extienden hasta hoy en tierra.
  - Se desliza de lado si no cabe.
- **Ficha:** lo que hoy muestra la pantalla del proyecto (fases con fecha y
  responsable, equipo, documentos y Drive), sin la lista de tareas.

### 3. Mi día por persona: objetivos del día y de la semana

- Arriba, la barra de capacidad de su semana y tres cifras: vencidas, para hoy y
  esta semana.
- Las tareas se agrupan como en Trello: **Vencidas · Hoy · Esta semana · Más
  adelante · Sin fecha**.
- Cada tarjeta lleva la barra de plazo. Cuando alguien espera la tarea, va una
  marca «La espera Carlos»; hoy eso es un grupo de la base.
- `v_mi_dia` trae `fecha_compromiso`, `grupo`, `lectura` y `prioridad`. Para la
  barra hace falta `fecha_inicio`: se consulta `tarea_diseno` con `.in("id", ids)`.

### 4. Vista de quien dirige

- **Proyectos** (`#/proyectos`): cada proyecto con su tira de fases, la barra de
  avance general y sus contadores (abiertas, vencidas).
- **Centro de mando:** arriba de «Cada proyecto», la **matriz de fases por
  proyecto** del Excel de Luisa: una fila por proyecto, su avance general y una
  celda por fase con el estado de color.
- **Equipo:** en cada persona, la barra de capacidad en vez de la frase. La frase
  queda solo como texto accesible (`aria-label`).

### 5. Datos de la demostración

El `datos.json` de la demostración no trae tareas (`tarea_diseno` vacío): así no
se ven ni los tableros ni las barras. Hay que armar un constructor
(`scripts/demo/demo_proyectos.py`) que agregue lo siguiente:

- **Proyectos y fases**, a partir de la hoja real de Luisa (cuyas tareas abiertas
  están anotadas en `privado/memoria/esa-seguimiento-tareas-excel.md`): Las
  Margaritas, Casa Cabrera, Casa V, Casa GO, COCOM y Terrano, con sus fases.
- **Tareas** con todos los campos que pide `vistaTarea`: `tiene`, `asigno`,
  `proyecto` y `fase` embebidos.
- **Lo calculado:** `v_fase_avance`, `v_mi_dia` de la persona,
  `v_cola_revision`, `carga_semanal` (5 días hábiles por semana; 4 en las
  semanas con festivo) y los accesos.

El Supabase simulado filtra solo por las columnas que traen las filas. Luego hay
que regenerar el artifact de demostración: los archivos del artifact no pueden
empezar por «_» (ver cómo se armó en `CLAUDE.md`, sección 5).

### 6. Verificación

1. Correr la batería; no debería cambiar nada, porque no hay migración.
2. Recorrer en el celular (375 px) como Luisa, Mariana y Allison: tablero, lista,
   cronograma, Mi día y Mando.
3. Revisar los temas claro y oscuro.
4. Publicar la demostración en la **misma** URL para que Felipe y Luisa comenten.
