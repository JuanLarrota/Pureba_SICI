# SICI · la base de datos (guía técnica larga)

> Era el README del repositorio hasta el 19-10-2026. Las rutas de carpetas que
> menciona son las de entonces (`pruebas/`, `etl/`, `marca/`); la estructura actual
> está en el `README.md` de la raíz. Las cifras de estado son de septiembre y octubre.

> **El estado al día y las reglas de trabajo están en [`CLAUDE.md`](CLAUDE.md)** y
> en [`docs/contexto/`](docs/contexto/LEAME.md). Este README es la guía técnica
> larga de la base; sus cifras de estado son de septiembre y octubre, y no se
> actualizaron con cada migración.

ESA Arquitectura S.A.S. · Base de datos para Supabase, módulos **M-00 a M-08**.

**Estado al 14 de septiembre de 2026:** las 11 migraciones y las 3 semillas están ejecutadas contra
Postgres 16.2 con una imitación de Supabase. **212 de 212 pruebas correctas**, dos veces seguidas.
Falta crear los proyectos en Supabase y aplicarlas allí.

Documento de arquitectura: https://claude.ai/code/artifact/31687724-e196-4c74-a2b2-ce8ade9e841a
Prototipo de la plataforma: https://claude.ai/code/artifact/9cdddee0-6593-4b33-8650-61f634e8ba32

---

## Qué hay aquí

```
sici/
├── supabase/
│   ├── migrations/                          lo que se aplica a Supabase, en este orden
│   │   ├── 20260914120000_esquema_inicial.sql   tipos, 62 tablas, funciones, disparadores, 24 vistas, alertas
│   │   ├── 20260914120100_rls_nucleo.sql         políticas · núcleo y alertas
│   │   ├── 20260914120200_rls_comercial.sql      políticas · mercadeo, ventas y CRM
│   │   ├── 20260914120300_rls_diseno.sql         políticas · diseño
│   │   ├── 20260914120400_rls_presupuestos.sql   políticas · presupuestos y APU
│   │   ├── 20260914120500_rls_obra.sql           políticas · obra, bitácora, actas y portal
│   │   ├── 20260914120600_rls_reclamaciones.sql  políticas · reclamaciones y listas de chequeo
│   │   ├── 20260914120700_rls_finanzas.sql       políticas · finanzas
│   │   ├── 20260914120800_permisos_api.sql       qué puede intentar cada rol de Supabase
│   │   ├── 20260914120900_almacenamiento.sql     depósitos privados de fotos y documentos
│   │   └── 20260914121000_vinculo_usuarios.sql   enlaza cada usuario con su ficha
│   ├── sici_todo_en_uno.sql                 las 11 anteriores en un archivo · lo genera la prueba
│   └── semilla/
│       ├── 010_historico.sql                catálogos + 2.980 pagos reales · NO va a GitHub
│       ├── 020_nirvana.sql                  Obra Nirvana: presupuesto y adicionales · NO va a GitHub
│       ├── 030_clasificacion.sql            qué no cuenta como costo de proyecto · POR CONFIRMAR
│       └── _resumen.txt                     qué se cargó y qué se descartó, con cifras
├── pruebas/
│   ├── stub_supabase.sql                    imita auth, storage y roles · NUNCA en Supabase
│   └── probar_contra_postgres.py            470 pruebas contra un Postgres temporal
├── etl/
│   └── cargar_historico.py                  regenera 010 y 020 desde los Excel originales
└── _version_anterior/                       lo del 13 de septiembre · solo en disco, NO va a GitHub
```

---

## Qué contiene la base

| Módulo | Tablas | Controles que se cumplen en la base |
|---|---|---|
| **M-00 Núcleo** | parametro, persona, cliente, categoria_costo, cuenta, proyecto, centro_costo, acceso_proyecto, evento_auditoria | T2 centro de costo del mismo proyecto · T3 auditoría de todo cambio y nada se borra |
| **M-01 Gasto de obra** | movimiento, fondo_caja, cambio_obra, adicional, evidencia | T1 segregación · T3 anular con contra-registro · T4 umbral de $2.000.000 · caja menor · O1 · O2 · O9 · P5 |
| **M-02 Reclamaciones** | reclamacion, reclamacion_evento, lista_chequeo, lista_chequeo_item, chequeo, chequeo_respuesta | P1 lista por póliza · P2 conciliación con abogados · P3 cascada sin saltos · P4 vencimiento · P6 aval estructural |
| **M-03 Bitácora y actas** | bitacora, bitacora_cuadrilla, acta, acta_item, pendiente_obra | O4 días sin bitácora · O5 memoria de cantidades · O6 el acta no paga más de lo ejecutado · O11 el remate lo verifica otro, y si mueve plata se cuelga del gasto |
| **M-04 Diseño** | proyecto_fase, tarea_diseno, revision_diseno, dedicacion, entregable, entregable_archivo, complementario, radicacion_licencia, elemento_diseno, objetivo | D1 compuerta de fase · D2 dedicación sin prosa · D3 · D4 · D5 versiones · D6 · D7 curaduría · D8 el objetivo se cuenta, no se declara · D9 la tarea vencida avisa y no termina antes de empezar |
| **M-05 Comercial** | experimento, campana, inversion_pauta, lead, contacto_lead, oportunidad, calificacion, cita, cotizacion, tarifa_diseno | M1 canal obligatorio · M2 canal hasta el margen · M3 · M4 · M5 · M6 · M7 · M8 · M9 · regla de 3 intentos · tiempo de primera respuesta · V1 siguiente paso · V2 presentación antes de cotizar · V3 reporte de la cita · V4 el diseño abre la obra |
| **M-06 Presupuestos** | insumo, apu, apu_componente, presupuesto, capitulo, item_presupuesto, ejecucion_item, actividad_cronograma | O8 imprevistos · O10 margen bajo la meta · validación profesional · presupuesto emitido no se reescribe · O7 calibración |
| **M-07 Finanzas** | saldo_cuenta, ingreso, extracto_linea, partida_abierta, cierre_mes, distribucion_estructura, regla_alerta, alerta, aviso | F1 · F2 · F3 cartera · F4 flujo a 13 semanas · F5 · F6 cierre sellado · F7 · F8 cada alerta con dueño |
| **M-08 Portal** | aprobacion_cliente | el cliente aprueba adicionales en línea; ve lo suyo y nunca un costo |

Inventario: 62 tablas · 38 tipos · 55 funciones · 98 disparadores · 24 vistas · 175 políticas ·
272 índices · 2 depósitos · 18 reglas de alerta.

Las vistas que terminan en `lectura` traen la conclusión escrita, no el indicador:
«Cada peso invertido trajo $25,91 en ventas», «Van 24 de 8 horas cotizadas».

---

## Puesta en marcha

### 1. Dos proyectos en Supabase

`sici-pruebas` y `sici-produccion`. Todo se aplica y se prueba primero en `sici-pruebas`.
Crear la cuenta y la contraseña de la base le corresponde a quien administra la empresa; la
contraseña va a un gestor de contraseñas, nunca a un archivo de este proyecto.

### 2. Cerrar el registro abierto

Authentication → Sign In / Providers → desactivar **Allow new users to sign up**. Al SICI se entra
por invitación.

### 3. Aplicar las migraciones

**Opción A · desde el navegador.** SQL Editor → pegar `supabase/sici_todo_en_uno.sql` → Run.
Una sola vez. Si se corta, se vuelve a correr completo: todo es idempotente.

**Opción B · con la CLI de Supabase.** `supabase link --project-ref <ref>` y `supabase db push`.
Aplica las 11 migraciones en orden y lleva el registro de cuáles ya corrieron.

### 4. Cargar los datos, en este orden

| Archivo | Qué hace |
|---|---|
| `supabase/semilla/010_historico.sql` | catálogos y 2.980 pagos · se niega a cargar dos veces |
| `supabase/semilla/020_nirvana.sql` | Obra Nirvana completa |
| `supabase/semilla/030_clasificacion.sql` | solo después de confirmarlo (ver abajo) |

**Nunca** ejecutar `supabase/pruebas/stub_supabase.sql` en Supabase: reemplazaría piezas de Supabase.

### 5. Comprobar

```sql
-- 2.980 pagos por $2.235.247.966
select count(*), sum(valor) from movimiento where conciliado;

-- Nirvana: 70 adicionales pendientes; bruto, crédito y neto
select cantidad, pendientes, bruto, credito, neto from v_adicionales_netos where proyecto = 'OBRA NIRVANA';

-- Ninguna tabla sin permisos por fila (debe devolver cero filas)
select relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
```

Y en Supabase: Advisors → Security Advisor y Performance Advisor.

### 6. Dar acceso a una persona

1. Crear su ficha con su correo:
   ```sql
   insert into persona (nombre, rol, es_interno, correo)
   values ('<nombre completo>', 'residente', true, '<correo>');
   ```
2. Authentication → Users → **Invite user** con ese mismo correo.
3. Cuando acepta la invitación, su usuario queda enlazado a su ficha solo.
4. Si no es socio, director ni finanzas, asignarle sus proyectos:
   ```sql
   insert into acceso_proyecto (persona_id, proyecto_id, nivel)
   select p.id, pr.id, 'registro' from persona p, proyecto pr
   where p.correo = '<correo>' and pr.codigo in ('OBRA NIRVANA');
   ```

### 7. Programar las alertas

Database → Extensions → activar `pg_cron`. Luego:

```sql
select cron.schedule('sici-alertas', '0 * * * *', 'select private.generar_alertas()');
```

Las alertas quedan en la plataforma y los envíos por correo y mensaje de texto quedan en la
tabla `aviso`. **Falta** la función de Supabase que los envía (necesita un proveedor de SMS y de
correo).

---

## Cómo funciona la seguridad

Tres capas. Las tres tienen que fallar para que alguien vea o haga lo que no debe.

1. **Permisos de la API** (`permisos_api`). `anon`, la llave pública sin sesión, no puede nada.
   `authenticated` puede intentar lo que la aplicación necesita, y nadie puede borrar, salvo
   retirar un acceso. `service_role` es para tareas del servidor; su llave nunca va en la PWA.
   Desde el 30 de mayo de 2026 Supabase ya no da estos permisos solo: sin este archivo la
   aplicación no leería nada.
2. **Políticas por fila** (`rls_*`). Dicen qué filas ve y toca cada quien.
3. **Reglas en disparadores** (migración inicial). Dicen qué se puede hacer, sin importar quién.

| Quién | Ve | Registra |
|---|---|---|
| Socio | todo | aprueba gastos, autoriza márgenes bajo la meta, cambia parámetros, reabre meses |
| Director | todo | aprueba gastos, cierra fases, gestiona personas y accesos |
| Finanzas | el dinero de todos los proyectos | ingresos, conciliación, cierre de mes; **no** aprueba ni corrige gastos |
| Residente | solo sus obras y sus fondos de caja | gastos a su nombre, bitácora, avance, cambios en obra, fotos |
| Arquitecto · practicante | solo sus proyectos; su propia dedicación | tareas, entregables, dedicación a su nombre |
| Mercadeo | el embudo comercial; nunca la contabilidad | leads, contactos, citas, campañas |
| Cliente (portal) | su proyecto, sus adicionales, su presupuesto y sus actas de cobro | aprueba o rechaza adicionales |
| Contratista (portal) | sus actas de pago | — |

Las funciones internas viven en el esquema `private`, que la API no expone.

---

## Probar sin Supabase

```bash
python3 -m venv .venv
.venv/bin/pip install pgserver psycopg2-binary openpyxl
.venv/bin/python supabase/pruebas/probar_contra_postgres.py
```

Levanta un Postgres temporal que se borra al terminar. No toca ninguna base de la empresa.

1. **Migraciones.** Las aplica dos veces y exige que la segunda no cambie nada. Aplica el paquete
   todo-en-uno en otra base configurada como los proyectos viejos de Supabase, que dan permisos a
   todos, y exige que igual quede cerrada.
2. **Asesor de Supabase.** Las mismas revisiones: permisos por fila, llaves primarias, índices de
   llaves foráneas, vistas, `search_path`, funciones expuestas, políticas duplicadas y rendimiento.
   Se comprobó sembrando 12 errores a propósito: las 12 revisiones afectadas los detectaron.
3. **Histórico.** Carga las semillas y las compara con el libro.
4. **Reglas por módulo.** Obra, ventas, diseño, reclamaciones y finanzas, con sus alertas.
5. **Objetivos y pendientes de obra.** El remate que no se cierra sin que otro lo verifique, la
   compra que no se cierra sin su gasto, la dependencia que respeta el orden, la tarea que no puede
   terminar antes de empezar y las cuatro alertas nuevas. Se comprobó sembrando 12 errores a
   propósito: los 12 fueron detectados.
6. **Permisos.** Con sesiones reales de socio, residente, finanzas, mercadeo, practicante, cliente,
   usuario sin ficha y visitante sin sesión, incluidas las fotos y el enlace de usuarios.

Si todo pasa, reescribe `supabase/sici_todo_en_uno.sql`.

---

## Qué está verificado y qué no

**Verificado contra Postgres 16.2:**
- Las 11 migraciones, dos veces seguidas, sin error y sin duplicar nada.
- Que la base queda cerrada con los permisos por defecto nuevos y con los viejos de Supabase.
- 2.980 pagos por $2.235.247.966, idénticos al libro. Presupuesto de Nirvana con $20,92 de diferencia
  por redondeo de cantidades a 4 decimales.
- Todas las reglas de control y los permisos de cada rol, con sesiones reales.

**Aplicado y verificado en Supabase el 5 de octubre de 2026** (proyecto ESA CONTROL DE MANDO,
Postgres 17.11):
- Las 11 migraciones, registradas en el historial con la misma versión que su archivo.
- El catálogo resultante se comparó con el de la prueba local: 2.325 elementos en 17 secciones.
  Dieciséis son idénticas byte a byte. La que difiere son los permisos de `service_role`, que en
  Supabase trae además TRUNCATE, REFERENCES y TRIGGER por los permisos por defecto de la plataforma.
- Asesor de seguridad de Supabase: cero avisos. Asesor de rendimiento: solo el aviso informativo de
  índices sin usar, que es lo normal en una base vacía.
- `anon` no tiene ningún permiso ni puede ejecutar ninguna función. Las 24 vistas responden y el
  generador de alertas corre.
- Los disparadores sobre `auth.users` y las políticas sobre `storage.objects` se crearon sin error.

**No verificado:**
- Las 212 pruebas de reglas corrieron contra Postgres 16.2, no contra el 17 de Supabase. La
  estructura es idéntica; el comportamiento de las reglas en 17 no se ha ejercitado con datos.
- Las semillas no están cargadas: la base está vacía, sin proyectos, personas ni pagos.
- Si el editor SQL acepta de una vez el tamaño de `010_historico.sql` (375 KB).
- El plan gratuito de Supabase no tiene copias de seguridad automáticas.
- `service_role` puede vaciar una tabla con TRUNCATE sin pasar por los disparadores que prohíben
  borrar. Su llave nunca sale del servidor; aun así conviene retirarle ese permiso en una migración.

---

## Por confirmar con Felipe

- **`030_clasificacion.sql`.** Deja fuera de la rentabilidad 11 categorías (préstamos, socios,
  créditos, traslados) y marca «SOCIOS» como cuenta interna, no como proyecto de diseño.
- **Repartir la estructura por horas dedicadas** (F2). Es la regla implementada; cambia la
  rentabilidad reportada de todos los proyectos.
- **Contenido de las listas de chequeo.** El mecanismo existe para fases, curaduría, pólizas y
  presupuestos, pero las listas están vacías. **Mientras Luisa no defina la de cada fase, ninguna fase
  de diseño se puede cerrar**: es la compuerta D1.
- **Costo estimado obligatorio para emitir una cotización de diseño.** Sin él, O10 no puede saber si
  la cotización deja el margen meta.
- **Los dos créditos de Nirvana.** `v_adicionales_netos` acredita solo los ítems reemplazados. La obra
  que la revisión dejó en cero sin reemplazo se ve en `v_desviacion_capitulo`.
- **Retegarantía.** `acta.valor_retenido` ya la admite; falta saber si existe en los contratos.
- **Ingresos históricos.** El libro trae la columna ENTRADA, pero la semilla solo carga los pagos.
  Hasta cargarlos, la rentabilidad de los proyectos viejos se calcula contra el valor del contrato.

---

## Cambios del 14 de octubre · el embudo de ventas

**Estado: aplicado en Supabase el 14 de octubre de 2026 y verificado.** Son 21 migraciones.

| Archivo | Qué trae |
|---|---|
| `20261018120000_embudo_de_ventas.sql` | V1 · toda oportunidad abierta tiene siguiente paso con fecha y responsable. V2 · ninguna cotización se emite sin la reunión de presentación agendada. V3 · antes de cotizar va el reporte de la cita (quien decide, lote, recurso, propósito). V4 · al ganar un diseño o un interiorismo nace la oportunidad de obra con el mismo canal. `nuevo_contacto()`, `agendar_cita_de_lead()`, `reporte_de_cita()`, `valor_sugerido()`; `v_ventas_hoy`, `v_embudo_ventas`, `v_ritmo_ventas`; tabla `tarifa_diseno` |

Sale de la evidencia del 13 de octubre: 124 cotizaciones de 2025 y 2026, el financiero, el
calendario de Felipe y 128 transcripciones de citas. Los cuatro clientes que firmaron tuvieron
la cita de viabilidad y, días después, una reunión para presentar la cotización; de los que solo
tuvieron una reunión no firmó ninguno. Las reglas aplican a quien trabaja desde la aplicación:
una carga del sistema (la importación de Pipedrive) no se frena. Las etapas siguen siendo las
de la base; en pantalla se llaman cita de viabilidad, cotización en preparación, cotización
presentada y contrato y anticipo.

**Verificado:** 470 de 470 pruebas en Postgres local (sección 19, con sesiones de cada rol);
133 de 133 errores sembrados detectados (22 nuevos del embudo); el envío ensayado sin diferencias
de catálogo; en Supabase, las 17 secciones de la huella idénticas a las locales (permisos de
tabla comparados sin `service_role`). El asesor de seguridad muestra un solo aviso, que no viene
de las migraciones: la protección contra contraseñas filtradas de Supabase Auth está apagada.

**No verificado:** ninguna sesión real; las pantallas de ventas se probaron con un Supabase
simulado y datos inventados. La tabla de tarifas y la meta mensual (`parametro.meta_ventas_diseno_mes`)
están vacías: las escribe dirección.

## Cambios del 13 de octubre · la aplicación del equipo y la carga por semana

**Estado: aplicado en Supabase el 13 de octubre de 2026 y verificado.** Con estas cinco son 20 migraciones.

| Archivo | Qué trae |
|---|---|
| `20261013120000_aplicacion.sql` | Lo que la aplicación necesita para arrancar: carpeta de Drive por proyecto, `mi_sesion()` y el enlace de la ficha con quien se registró antes |
| `20261017120000_cierre_de_fase.sql` | D20 · la lista de chequeo se define por tipo de proyecto y sus puntos pueden pedir un dato (opción, número, fecha, enlace); `falta_para_cerrar()` cuenta en frases lo que le falta a una fase, `abrir_chequeo()` deja lista su hoja y `punto_de_cierre()` agrega puntos |
| `20261016120000_tareas_tipicas.sql` | D19 · cada tarea típica dice cuánto trabajo pide; `tareas_tipicas()` las propone al abrir la fase, `crear_tareas()` guarda su inicio y su trabajo, y `v_fase_avance` dice cuándo una fase terminó todas sus tareas |
| `20261015120000_flujo_por_fase.sql` | D18 · cada fase de una plantilla dice cuánto puede durar y qué papel responde; al abrirla en un proyecto recibe su fecha de entrega y su responsable. La idea salió de mirar cómo Pipefy arma sus flujos |
| `20261014120000_carga_semanal.sql` | D17 · cada tarea dice cuántos días de trabajo pide (`dias_estimados`, lo pone quien asigna) y `carga_semanal()` devuelve, por persona y por semana, los días hábiles y los ocupados |

La aplicación vive en `legado/app/` (guía en `legado/app/LEAME.md`) y el logo oficial en `marca/`. Con la carga
por semana la aplicación pinta el Gantt del equipo y le dice a quien reparte cuánto le queda
libre a cada persona. El centro de mando (`#/mando`) junta todo para el comité y no necesitó
migración: lee lo que ya había.

**Verificado:** 432 de 432 pruebas en Postgres local; 111 de 111 errores sembrados detectados; el
envío ensayado en una base local igual a la de Supabase, sin diferencias de catálogo; en Supabase,
las secciones de columnas, restricciones, índices, funciones, permisos de función, disparadores y
vistas idénticas a las locales, asesor de seguridad sin avisos y `anon` sin acceso a la función.

**No verificado:** ninguna sesión real en la aplicación (el primer ingreso lo hace Felipe); las
pantallas nuevas se probaron con un Supabase simulado y datos de ejemplo. Las pruebas de reglas
corren en Postgres 16; Supabase es 17.

## Cambios del 12 de octubre · módulo de arquitectura y diseño, etapa 2

**Estado: aplicado en Supabase el 12 de octubre de 2026 y verificado.** Desde ese momento estas
cuatro migraciones tampoco se editan: cada cambio va en una migración nueva.

| Archivo | Qué trae |
|---|---|
| `20261012120000_fases_por_tipo.sql` | Las fases que faltaban (levantamiento, informe, entrega del expediente, preconstrucción, ejecución) y el rol de director de proyectos de construcción |
| `20261012120100_modulo_diseno.sql` | Equipo con papel, plantillas, flujo de revisión, rastro de cada cambio, «Mi día», cola de revisión, tablero de carga, profesión elegible |
| `20261012120200_indicadores.sql` | Los cinco indicadores de impacto, los dos de quien dirige, el detalle de cada frase y las solicitudes de corrección |
| `20261012120300_mensajes.sql` | La bandeja de mensajes a cada persona, con sus límites y su horario |
| `semilla/040_plantillas.sql` | Plantillas por tipo de proyecto, profesiones y festivos de 2026 y 2027. **Cargada en Supabase** |

Controles nuevos:

- **D10 · Equipo con papel.** Quien no tiene papel en el proyecto no lo ve ni recibe tareas. La
  fecha, la prioridad y el responsable los cambia quien asignó o quien dirige, no quien hace la tarea.
- **D11 · Flujo de revisión.** Solo se revisa lo que pidió revisión; aprobar termina la tarea,
  devolver exige una observación. `tarea_evento` guarda cada cambio con quién y cuándo.
- **D12 · Plantillas.** `abrir_proyecto()` crea la ficha, las fases y el equipo en un solo paso;
  `proponer_tareas()` y `crear_tareas()` hacen lo mismo con las tareas típicas de una fase.
- **D13 · Variantes de lista de chequeo** según tamaño y alcance; la fase toma la suya al abrirse.
- **D14 · Indicadores.** `indicadores()` devuelve una frase por indicador; `indicador_detalle()`
  muestra los hechos de los que sale. Solo cuentan las tareas que asignó otra persona, y la que
  vence hoy no cuenta en contra hasta mañana.
- **D15 · Corrección.** La persona señala el dato, dirección lo resuelve, y queda el rastro.
- **D16 · Mensajes.** Máximo dos al día por persona, solo en días hábiles de 7:30 a 5, nada para
  quien marcó ausencia. Una tarea vencida avisa el día 1, vuelve al 3 y al 5 sube a quien dirige.
  Los mensajes de una persona los lee ella y nadie más.

El **director de proyectos de construcción** (`director_proyecto`) puede todo lo que puede un
arquitecto, y firma presupuestos. No es dirección de la empresa: dirige las obras donde se le dé
el papel de dirigir. La profesión (`persona.profesion_id`) se escoge de una lista aparte del rol.

Decisiones de diseño que conviene recordar:

- **Las fases siguen siendo una lista fija de la base, ahora más larga.** Qué fases recorre cada
  tipo de proyecto lo dicen las plantillas, que son datos. Agregar una fase que no exista es una
  línea en una migración nueva. Se prefirió a convertir la lista en tabla porque eso obligaba a
  reescribir cinco vistas ya aplicadas.
- **Las plantillas van en la semilla y no en la migración**, porque Postgres no deja usar una
  fase nueva en la misma transacción que la crea. Por lo mismo el rol nuevo se compara como texto.
- **La entrega de una tarea es la hora en que se pidió la revisión**, que pone el sistema. Si la
  revisión se demora, no cuenta contra quien entregó a tiempo.
- **Una alerta es un estado que ve quien dirige; un mensaje es un aviso puntual a una persona.**
  Van en tablas distintas. El reloj de los mensajes entra como parámetro para poder probar un
  sábado o las 4:30 de la tarde sin esperar a que lleguen.

Verificado:

- **342 de 342 pruebas** en local (Postgres 16.2), dos pasadas seguidas sin duplicar nada.
- `supabase/pruebas/sembrar_errores.py` siembra 74 errores, uno a la vez, y exige que alguna prueba lo
  detecte: **74 de 74**.
- En Supabase (Postgres 17): cada envío comprobado con md5 por la propia base antes de
  ejecutarse; 21 de 22 secciones del catálogo idénticas a la base local y la restante solo
  difiere en los permisos de `service_role`, que Supabase le da por defecto; asesor de seguridad
  con 0 avisos; `anon` sin permisos sobre ninguna tabla ni función.

No verificado, o pendiente:

- Las pruebas de reglas corrieron en Postgres 16.2, no en el 17 de Supabase con datos.
- Las listas de chequeo reales no están: se probó con listas de ejemplo. Sin ellas ninguna fase
  que exija lista puede cerrar en la base real.
- Nada programa todavía `generar_mensajes()` ni `despachar_mensajes()` (falta activar pg_cron), y
  nadie envía lo que queda en 'listo': eso es la etapa 5.
- Las tareas típicas solo existen para el anteproyecto, y son propuesta.
- El plan gratuito pausó el proyecto a la semana; volverá a pasar mientras no haya uso.

`scripts/base/exportar_vista_previa.py` arma un proyecto de ejemplo en una base temporal y
exporta lo que la aplicación recibiría (frases, listas, mensajes). `scripts/prototipo/armar_plataforma.py`
mete esos datos y las pantallas de `modulo_diseno_plataforma.txt` en el prototipo de la plataforma
(`../documentos/sici-plataforma.html`), en los módulos «01 Obra» y «02 Arquitectura y diseño», y redibuja el menú en cascada. Así se ve todo junto:
hay que volver a correr los dos cada vez que cambien reglas o frases.

## Cambios del 5 de octubre · seguimiento de tareas

Vienen de analizar `SEGUIMIENTO PROYECTOS ESA 2026_.xlsx`, el Excel con el que el equipo hace
seguimiento hoy: 139 filas, 13 proyectos, 9 personas. Lo que ese archivo no podía mostrar:
24 tareas vencidas, 20 abiertas sin fecha, 8 sin responsable y una columna de avance con solo dos
valores, 100% o vacía.

- **`pendiente_obra`** (O11). El 42% de las filas del Excel eran remates, instalaciones y trámites de
  obra, no tareas de diseño. Un pendiente **se cierra cuando alguien distinto de quien lo ejecutó lo
  verifica**, separa quién responde de quién lo hace (en el Excel la celda decía «Teo-carpintero») y
  respeta las dependencias.
- **La plata vive en obra.** 32 filas del Excel eran pagos, compras y cotizaciones sin monto, al lado
  de un render. Un pendiente de tipo `compra` **no se cierra sin su movimiento**, que sí tiene valor,
  cuenta y aprobación.
- **`objetivo`** (D8). No tiene columna de porcentaje: el avance sale de contar las tareas y los
  pendientes colgados, y **no se declara logrado mientras quede trabajo abierto**.
- **Cuatro alertas nuevas**: `tarea_vencida`, `pendiente_vencido`, `trabajo_sin_fecha` y
  `objetivo_en_riesgo`. La primera le llega a quien la tiene y a quien la asignó.
- **Una tarea no puede terminar antes de empezar.** En el Excel, cuatro tareas de Casa V empezaban el
  5 de octubre y terminaban el 7 de septiembre, con la duración en −27 días.
- **Lo administrativo se separa a su propio proyecto interno** (decisión de Felipe): pagar la
  seguridad social o revisar el arriendo de la oficina es gasto de estructura, no costo de un cliente.

---

## Cambios frente a la versión del 13 de septiembre

- De M-00 y M-01 a **todos los módulos**, con las políticas en un script por módulo.
- **Permisos explícitos para la API**, por el cambio de Supabase del 30 de mayo de 2026.
- Funciones internas en el esquema `private`, con `search_path` fijo, como pide el asesor de Supabase.
- Un movimiento **ya no se edita ni se marca como anulado**: se anula con un contra-registro que
  repite sus valores. El histórico queda intacto y el cierre de mes puede sellarse.
- Un gasto pendiente o rechazado **no se puede causar ni pagar**, y un eslabón que crece por encima
  del umbral vuelve a pedir aprobación.
- La caja menor **no se legaliza con gastos sin soporte**.
- Rol `desarrollador` retirado. Roles `aseguradora` y `abogado` agregados.
- `validar_esquema.py` retirado: lo reemplaza la revisión del asesor contra el catálogo real.

## Decisiones que conviene recordar

- **El código vive en GitHub**, en `ESAArquitectura/ESA-CONTROL-DE-MANDO`, desde el 5 de octubre de
  2026. Salió de Google Drive, que sincronizaba mientras se editaba. La raíz del repositorio es esta
  carpeta, así que `supabase/` queda en la raíz, como lo esperan Supabase y su integración con GitHub.
- **Los datos reales no van a GitHub.** `010_historico.sql` y `020_nirvana.sql` están en
  `.gitignore`: traen 2.980 pagos con el nombre de cada tercero. Se cargan directo a Supabase desde
  el computador donde están.
- **Desde el 5 de octubre de 2026 las 11 migraciones están aplicadas en Supabase y ya no se editan.**
  Un cambio a la base va en una migración nueva, con fecha posterior, nunca editando las
  existentes. Toda tabla nueva necesita sus políticas y sus permisos en esa misma migración.
- **La semilla refleja el balance de Nirvana editado el 12 de septiembre de 2026.** Si el Excel
  cambia, se corre `scripts/etl/cargar_historico.py` antes de cargar.
- **406 de 709 terceros quedan `sin_clasificar`.** Clasificarlos es trabajo de oficina, no del sistema.
- **El histórico entra como `pago` conciliado.** Compromiso y causación empiezan a existir cuando la
  obra registre en la aplicación.
- **La aplicación nunca debe subir fotos con «upsert»**: un archivo subido no se reemplaza.
