# SICI · la aplicación del equipo (MVP)

> **Desde el 19-10 la aplicación vive en `src/`, en la raíz del repositorio** (Next.js y TypeScript, mismas
> pantallas y textos). Esta carpeta queda congelada como referencia hasta que Felipe
> pruebe la aplicación nueva; entonces se retira. Guía nueva: `docs/aplicacion.md`.

Una sola página, sin compilación: HTML, CSS y JavaScript que hablan directo con
Supabase. Todo lo que una persona puede o no puede hacer lo decide la base.

## Qué hace hoy

- **Entrar** con correo y contraseña, o con un enlace que llega al correo.
- **Mi día**: lo que tengo, en el orden en que hay que atenderlo.
- **Repartir tareas**: quien dirige arma una o varias tareas de un proyecto y se las
  entrega a su responsable: qué hay que entregar, quién, cuándo empieza, cuándo se
  entrega, cuánto trabajo pide y la prioridad. Al escoger a la persona, la pantalla
  dice cuánto le queda libre esa semana. Quien no dirige solo se crea tareas propias.
- **Cambiar una tarea**: responsable, fechas, trabajo que pide y prioridad. Queda en el rastro.
- **Avanzar una tarea**: empezar, pedir revisión, retirar la entrega.
- **Revisar**: aprobar (la tarea queda terminada) o devolver con una observación.
- **Proyectos**: abrir uno desde su plantilla con fases, horas y equipo; ver sus
  tareas, sus fases, su equipo y su carpeta de Drive.
- **Equipo**: la carga por semana, tipo Gantt. Una fila por persona y una columna por
  semana (ocho); el número es lo que le queda libre, en días, y cada raya es una
  tarea, de su inicio a su entrega. Arriba, una frase dice quién tiene espacio. Quien
  dirige o asigna ve a todos; los demás, su propia carga.
- **Centro de mando** (pestaña «Mando», para quien dirige o asigna): lo que se proyecta
  en el comité de arquitectura y diseño. Arriba, una frase con lo que pesa. Después el
  proceso entero por etapa (por empezar, en curso, en revisión, devueltas, terminadas en
  14 días). Luego cada persona, que se despliega: su función, sus entregables con
  fechas, su carga de ocho semanas y su impacto. Y cada proyecto: fases, entregable al
  cliente, fecha y equipo. No registra nada, solo lee. En pantalla grande usa todo el ancho.
  El impacto de los demás solo lo ve dirección; quien dirige conserva el suyo en «Mi
  cuenta → Mi impacto».
- **El flujo de cada tipo de proyecto** (al final del centro de mando): una columna por
  fase con lo que se le entrega al cliente, el tiempo máximo en días hábiles, quién
  responde, lo que hace falta para cerrarla y sus tareas típicas. Dirección escribe ahí
  el tiempo máximo y escoge quién responde; se guarda al cambiar el dato.
- **Tareas típicas de cada fase**: dirección las define una vez en el flujo (qué hay que
  entregar, para qué sirve, si se repite por espacio, en cuántos días se entrega y
  cuánto trabajo pide). Al abrir una fase, la aplicación las propone ya armadas y
  quien dirige solo escoge a quién se le entrega cada una. También se llega desde la
  ficha del proyecto, en «Repartir sus tareas típicas». Lo que ya se repartió no se
  vuelve a proponer.
- **Registrar mi día** (primera línea de «Mi día»): por cada día, en qué estuvo la mañana
  y en qué la tarde: una fase abierta de sus proyectos, trabajo interno o «no trabajé».
  Si fue todo el día en lo mismo, se escoge la mañana y la tarde se llena sola. Lo que
  pasó hace más de una semana lo corrige dirección. Sin esto una fase no cierra.
- **Lista de chequeo de cada fase**: dirección la define en el flujo, por tipo de
  proyecto. Cada punto se marca o pide un dato (una opción, un número, una fecha o un
  enlace), y puede ser obligatorio u opcional. Un punto nuevo se pide también en los
  proyectos que ya tienen esa fase abierta; uno que se quita deja de pedirse.
- **Cerrar una fase** (desde la ficha del proyecto, «Lista de chequeo y cierre»): arriba,
  lo que hace falta, contado por la base: lista de chequeo, aprobación del cliente
  cuando aplica, dedicación del equipo y tareas abiertas. Luego la lista, que la llena
  cualquiera que trabaje en el proyecto y se guarda punto por punto. Al final, la
  aprobación del cliente y el botón de cerrar, que solo ve dirección y solo se activa
  cuando no falta nada de lo que la base exige. Las tareas abiertas se avisan pero no
  impiden el cierre.
- **Aviso de fase lista para el cierre**: cuando todas las tareas de una fase abierta
  quedan terminadas, lo dicen «Mi día» de quien dirige (grupo «Para decidir»), el
  centro de mando y la ficha del proyecto. El aviso no cierra la fase.
- **Fecha y responsable de cada fase**: al abrir una fase el sistema le pone la fecha
  (hoy más su tiempo máximo) y el responsable (la persona con el papel que dice el
  flujo, si es una sola). Dirección puede cambiarlos en la ficha del proyecto; lo que
  se puso a mano no se pisa. Cambiar el flujo no mueve los proyectos que ya andan.
- **Ventas** (pestaña para socios, dirección, mercadeo y quien responda por una
  oportunidad): arriba, una frase con el ritmo de los últimos 90 días (citas,
  presentaciones, ventas y cuántas citas lleva cada venta; con la meta escrita, cuántas
  citas al mes hacen falta). Luego «Para hoy»: los contactos sin primer contacto, las
  citas que pasaron sin reporte, las de hoy, los siguientes pasos que vencen y las
  cotizaciones por vencer. Dirección ve además lo del resto del equipo. Al final, el
  embudo por línea (diseño e interiorismo, obra, peritajes) y etapa, con valor y
  atrasos. En «Mi día», quien vende ve cuántas cosas del embudo le tocan hoy.
- **Nuevo contacto** (botón + en Ventas): quién es, por dónde llegó, cómo dice que nos
  encontró y, si ya aceptó la cita, cuándo y quién la hace. Con la cita nace la
  oportunidad.
- **Un contacto**: sus intentos («No respondió» / «Respondió»; al tercero sin respuesta
  pasa a nutrición), agendar la cita de viabilidad o descartarlo con su motivo.
- **Una oportunidad**: el contacto con su teléfono y WhatsApp, el valor, el siguiente
  paso (qué, cuándo y quién: siempre hay uno), las reuniones, lo que dejó la cita, las
  cotizaciones y el desenlace. Una cotización no se envía sin la reunión de
  presentación agendada.
- **Después de la cita** (desde «Para hoy» o la ficha): se escoge, no se escribe.
  ¿Llegó?, ¿autorizó grabarla?, enlace de la transcripción, ¿estaba quien decide?,
  ¿tiene lote?, ¿cuándo tiene el recurso?, ¿para qué es?, ¿somos la primera
  cotización?, el área y el valor (lo sugiere la tarifa si dirección la escribió) y
  cómo sigue: cotizar (con la fecha de la presentación), otra reunión, lo va a pensar
  (con el día de la llamada), firma, o no sigue (con el motivo).
- **Diseño que abre obra**: al ganar un diseño o un interiorismo nace sola la
  oportunidad de obra, con el mismo canal y cliente, a nombre de quien responde por las
  obras (`parametro.responsable_obra_id`).
- **Tarifas de diseño** (dirección, desde Ventas): valor por rango de área.
- **Obras** (pestaña para socios, dirección, finanzas, residentes y quien esté en una
  obra): todas las obras en curso o en pausa, cada una con dos frases que escribe la
  base (`v_obra_tablero`): cómo va la plata («Lleva $X de $Y del contrato (N %) y debe
  $Z») y lo primero que hay que mover (un gasto por aprobar, un pendiente vencido, días
  sin bitácora, un pendiente por verificar, un adicional esperando al cliente o el costo
  por encima del contrato). Dirección abre obras desde aquí con la plantilla de obra.
  Como la barra de abajo solo cabe seis pestañas, quien tiene Mando y Obras ve la carga
  del equipo dentro de Mando.
- **Una obra**, en seis espacios:
  - *Resumen*: contrato, gastado, pagado, por pagar; cobrado y caja de la obra solo
    para dirección y finanzas. En qué se ha ido la plata por categoría contra lo
    presupuestado. Dirección escribe el contrato, el residente (queda en el equipo con
    permiso de registrar), las fechas y el estado.
  - *Gastos y facturas*: registrar un gasto escogiendo la categoría (la base abre el
    centro de costo; `registrar_gasto`) con el número de la factura; lo que llega al
    umbral espera la aprobación de dirección, que aprueba o rechaza aquí. Lo que falta
    pagar (`v_obra_por_pagar`) se paga con un toque. Los últimos 25 movimientos.
  - *Flujo de caja*: lo que viene por pagar (vencido, próximas cuatro semanas, después)
    y mes a mes lo que salió y lo que entró, con la caja acumulada
    (`v_obra_flujo_mes`). Dirección y finanzas registran los cobros recibidos.
  - *Documentos*: el índice de lo importante (contrato, presupuesto, planos, licencia,
    pólizas, actas) con su enlace de Drive (`documento_obra`; no se borra, se retira) y
    la carpeta de Drive de la obra.
  - *Pendientes*: crear, marcar hecho y verificar (lo verifica alguien distinto de quien
    lo hizo; una compra no se cierra sin su gasto) o descartar con la razón.
  - *Registro en sitio*: la bitácora del día (personas, clima, frente, avance,
    novedades) y los días que faltan en el último mes.
- **Cada proyecto es un tablero** (`#/proyecto/<id>/<vista>`):
  - arriba, la tira de fases (cerrada llena, en curso con su avance, vencida en
    tierra, por abrir solo el borde), el avance y las vencidas;
  - **Tablero:** columnas por estado, que se deslizan de lado en el celular;
  - **Lista:** agrupada por fase;
  - **Cronograma:** por semanas, con la línea de hoy;
  - **Ficha:** fases, equipo y documentos.

  Cada tarea lleva su **barra de plazo**: salvia a tiempo, ocre si faltan dos días
  hábiles o menos, tierra si está vencida. La semana de cada persona se ve como
  **barra de capacidad**, en Mi día, Equipo, Mando y Repartir tareas. Mi día agrupa
  por tramos: vencidas, para hoy, esta semana, más adelante y esperando revisión.
  En Mando, «Fases por proyecto» es la matriz de control que usaba Luisa en Excel.
- **Personas** (dentro de Equipo): quién ya entró; dirección agrega personas. Un socio
  le da a alguien del equipo el permiso de ver préstamos y socios («Darle permiso de ver
  préstamos y socios»; `persona.ve_reservado`).

**Préstamos y socios (reservado).** Las categorías de préstamos, créditos y la cuenta de
los socios (`categoria_costo.reservada`) y el proyecto SOCIOS (`proyecto.reservado`) solo
los ven los socios y quien tenga ese permiso; para los demás no existen, ni en las listas
ni en las sumas. Los créditos bancarios que entran como ingreso se esconden igual. Desde
la obra no se registran: la base lo rechaza.
- **Impacto**: las frases de cada quien, con el detalle de dónde salen.

**Cómo se mide la carga.** El trabajo de una tarea se reparte parejo entre los días
hábiles que hay de su inicio a su entrega (sin festivos). Lo vencido cae entero en
el primer día. Lo que está en revisión no cuenta. Una tarea sin estimar se ve en el
calendario pero no suma. Quien trabaja media jornada tiene la mitad de los días. La
cuenta la hace la base (`carga_semanal`), no la pantalla.

Todavía no: adjuntar fotos o archivos como evidencia (de un punto de la lista, de un
gasto o de la bitácora), las actas de cobro y de pago, los adicionales desde la obra y
los mensajes. Los pendientes de obra de «Mi día» abren la lista de su obra.

## Probarla en este computador

    python3 herramientas/servir_app.py        →  http://localhost:3000

Ese puerto es el que Supabase usa por defecto para devolver a la persona después
de confirmar su correo.

## Dar acceso a alguien

1. Dirección lo agrega en **Equipo → Personas del equipo → Agregar a alguien**, con su correo.
2. La persona abre la aplicación, toca **Es mi primera vez** y crea su acceso con
   ese mismo correo. Confirma con el enlace que le llega.
3. Dirección lo mete al equipo de cada proyecto, con su papel.

Quien se registre sin tener ficha entra, pero no ve nada.

## Para que el equipo la use en el celular

Hay que publicar esta carpeta en un sitio con https y, en Supabase,
Authentication → URL Configuration, poner esa dirección como «Site URL».

## Para leer la carpeta de Drive dentro de la aplicación

En Google Cloud: crear un proyecto, activar «Google Drive API», configurar la
pantalla de consentimiento en modo de prueba con los correos del equipo, y crear
un «ID de cliente de OAuth» de tipo «Aplicación web» con la dirección de la
aplicación como origen autorizado. Ese ID va en `config.js`
(`GOOGLE_CLIENT_ID`). No es un secreto. Sin él, la aplicación solo muestra el
botón que abre la carpeta en Drive.

Cada persona ve lo que su propia cuenta de Google puede ver: la aplicación pide
permiso solo para leer nombres y fechas de archivos, no su contenido.

## Probar las pantallas sin sesión

    python3 pruebas/app_simulada/armar.py datos.json [Luisa|Mariana|Allison]    (datos de exportar_vista_previa.py;
                                                                             Allison entra a Ventas con datos inventados;
                                                                             Luisa ve dos obras inventadas en Obras)
    →  http://localhost:3000/_prueba.html
    python3 pruebas/app_simulada/armar.py --quitar
