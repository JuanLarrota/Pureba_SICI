# Decisiones ya tomadas, por módulo

Antes de proponer algo, revisa aquí. Cada línea es una decisión de Felipe o un
diseño ya construido y probado. El código de control (M1, O9, D10, F7…) aparece
en los mensajes de error de la base y en las pruebas.

## Organización general
- **El MVP único es la aplicación** (`legado/app/`). El prototipo de la plataforma
  (artifact LNVb19AdJARLePv14xJK6H) queda como mapa visual.
- **Navegación:** un módulo por área de trabajo, con sus espacios visibles en
  cascada; nada suelto si pertenece a otro módulo. El módulo 02 se llama
  **«Arquitectura y diseño»**, nunca «Diseño y equipo».
- La barra de abajo de la aplicación muestra seis pestañas como máximo. Quien
  tiene Mando y Obras ve la carga del equipo dentro de Mando.

## Arquitectura y diseño (tareas, fases, equipo)
- Las fases dependen del tipo de proyecto (plantillas). Interiorismo usa las de diseño.
- **Reparto:** «Repartir tareas» permite varias tareas en un envío. Cada una lleva
  responsable, inicio, entrega, el trabajo que pide (`dias_estimados`, lo escoge
  quien asigna) y la prioridad.
- **Carga:** la calcula la base (`carga_semanal`). El trabajo de una tarea se reparte
  parejo entre sus días hábiles; lo vencido cae en el primer día y lo que está en
  revisión no cuenta.
- **Centro de mando** (`#/mando`), para el comité: el proceso por etapa, cada
  persona (función, entregables, carga, impacto), cada proyecto y el flujo de cada
  tipo de proyecto.
- **Tomado de Pipefy:**
  - tiempo máximo y responsable por fase;
  - tareas típicas que se proponen al abrir una fase;
  - aviso cuando una fase terminó todas sus tareas;
  - datos obligatorios como puntos con tipo de la lista de chequeo (casilla,
    opción, número, fecha, enlace).
- **Cierre de fase:** pide la lista de chequeo y la dedicación registrada.
- **Registro del día:** mañana y tarde, escogiendo.
- Una tarea muestra para qué sirve (requisito 14: el impacto en el proceso).
- **Revisión por tarea** (19-10, pedido de Felipe):
  - quien asigna decide si la tarea requiere revisión y puede delegarla en una
    persona del equipo;
  - sin revisión, quien la tiene la entrega y queda terminada;
  - si se delegó, solo esa persona la aprueba o la devuelve, ni siquiera dirección.
- **Varios papeles por persona** en un proyecto (produce y revisa, por ejemplo).
- **Arrastre en el tablero:** sigue las mismas reglas de los botones; nadie lleva a
  «Terminadas» lo que no revisó quien debía. Felipe decidió el 19-10 que dirección
  mueve todas las tareas, respetando la revisión fijada al crear la tarea.
- **Revisión por tarea** (19-10, pedido de Felipe):
  - quien asigna decide si la tarea requiere revisión y puede delegarla en una
    persona del equipo;
  - sin revisión, quien la tiene la entrega y queda terminada;
  - si se delegó, solo esa persona la aprueba o la devuelve, ni siquiera dirección.
- **Varios papeles por persona** en un proyecto (produce y revisa, por ejemplo).
- **Arrastre en el tablero:** sigue las mismas reglas de los botones; nadie lleva a
  «Terminadas» lo que no revisó quien debía. Felipe decidió el 19-10 que dirección
  mueve todas las tareas, respetando la revisión fijada al crear la tarea.

## Obra
- **Módulo de obra** (O12–O15):
  - número de factura en el gasto;
  - índice de documentos con enlace de Drive (no se borran, se retiran);
  - `registrar_gasto()`;
  - tablero de obras con dos frases: cómo va la plata y lo primero que hay que mover;
  - cuentas por pagar y flujo por mes.
- **La plata vive en obra:** pagos, compras y cotizaciones no son tareas de diseño.
  Un `pendiente_obra` de tipo compra no se cierra sin su movimiento.
- Un pendiente de obra se cierra solo si lo verifica alguien distinto de quien lo hizo.
- **Adicionales:**
  - todos nacen pendientes de la decisión del cliente;
  - un adicional decidido no se modifica;
  - si reemplaza un ítem del contrato, el crédito sale solo;
  - desde el 18-10, uno que ESA retira queda **retirado** con la razón, no se borra
    (migración `adicional_retirado`).
- **Balances de obra:** `scripts/etl/cargar_balance_obra.py` lee el balance más reciente
  (hoja «BALANCE», bloque final Q–U) y es idempotente. Se detiene si el contrato
  no coincide o si la base no cuadra.
- Un movimiento no se edita: se anula con un contra-registro.

## Finanzas
- **F5:** préstamos, socios y traslados quedan fuera de la rentabilidad.
- **F7:** préstamos, créditos y la cuenta de socios se cargan, pero solo los ven
  los socios y quien tenga `ve_reservado`, permiso que da un socio. No se registran
  desde la obra.
- Lo administrativo va en su propio proyecto interno (ADMINISTRATIVO).
- «ALQUILER DE EQUIPOS» y «ALQUILERES DE EQUIPOS» → «ALQUILERES Y EQUIPOS».
- El libro de 2026 se toma del corte consolidado más reciente de la carpeta.

## Ventas
- **El CRM es propio**, dentro del SICI. Pipedrive se migra entero, pero solo
  cuando esté resuelto cómo se trabaja el embudo.
- **Reglas:**
  - V1: siempre hay un siguiente paso;
  - V2: sin reunión de presentación no se emite cotización;
  - V3: el reporte de la cita va antes de cotizar;
  - V4: el diseño ganado abre la oportunidad de obra.
- Después de la cita registra Felipe: marca cinco o seis cosas, no escribe.
- Las etapas definitivas del embudo **no están decididas**: Felipe no quiere
  copiar las de Pipedrive ni las del SICI.
- El canal viaja con el cliente, no con el contrato (control M2).

## Personas y permisos
- Rol `director_proyecto` para Daniel: puede lo mismo que un arquitecto y firma
  presupuestos.
- La profesión es un dato aparte del rol.
- Quien se registra sin ficha entra, pero no ve nada.
- Felipe agrega a las personas desde la aplicación, con su correo.
