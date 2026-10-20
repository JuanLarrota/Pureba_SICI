-- =============================================================================
-- SICI · Plantillas de proyecto y festivos
--
-- Configuración, no datos de la empresa: se puede subir al repositorio y
-- volver a correr sin efecto. Va después de las migraciones porque usa las
-- fases que agrega 20261012120000_fases_por_tipo.sql.
--
-- Qué viene decidido y qué es propuesta:
--   · Las fases de cada tipo de proyecto: decididas por Felipe y Luisa el
--     12 de octubre de 2026.
--   · Lo que exige el cierre de cada fase de diseño: lo que ya exigía la base.
--   · Lo que exige el cierre en peritaje, consultoría y obra: PROPUESTA. Se
--     dejó la lista de chequeo y se quitó la dedicación en obra, porque el
--     residente lleva bitácora y no medio día de estudio.
--   · Las tareas típicas del anteproyecto: PROPUESTA sacada de lo que se
--     repitió en Las Margaritas (modelo y render por espacio, presentación).
--     Luisa las corrige; las demás fases todavía no tienen tareas típicas.
--   · Las listas de chequeo y sus variantes NO van aquí: las suministra el
--     estudio.
-- =============================================================================

-- ---------- Profesiones (la lista la amplía dirección desde la aplicación) ----------
insert into public.profesion (nombre) values
  ('Arquitecto'), ('Ingeniero civil'), ('Ingeniero estructural'), ('Diseñador de interiores'),
  ('Tecnólogo en construcción'), ('Maestro de obra'), ('Estudiante en práctica'),
  ('Administrador'), ('Contador'), ('Otra')
on conflict (nombre) do nothing;

-- ---------- Plantillas de proyecto ----------
insert into public.plantilla_proyecto (nombre, tipo, descripcion) values
  ('Diseño',                'diseno',      'Diseño arquitectónico e interiorismo en su etapa de diseño'),
  ('Peritaje',              'peritaje',    'Caracterización de daños y expediente de póliza'),
  ('Consultoría',           'consultoria', 'Informe técnico con presupuesto'),
  ('Obra',                  'obra',        'Construcción: de la preconstrucción al cierre'),
  ('Montaje de interiores', 'obra',        'Compras e instalaciones, sin fases'),
  ('Interno',               'interno',     'Trabajo de estructura, sin fases')
on conflict (nombre) do nothing;

-- ---------- Fases de cada plantilla ----------
insert into public.plantilla_fase
  (plantilla_id, fase, orden, entrega_cliente, opcional, exige_chequeo, exige_aprobacion_cliente, exige_dedicacion)
select pl.id, v.fase::public.fase_proyecto, v.orden, v.entrega, v.opcional, v.chequeo, v.aprobacion, v.dedicacion
from (values
  ('Diseño',      'insight',            1, 'Los principios del proyecto',                    false, true, false, true),
  ('Diseño',      'anteproyecto',       2, 'Planos, cortes, alzados, modelo y renders',      false, true, true,  true),
  ('Diseño',      'proyecto_final',     3, 'Planos constructivos, detalles y mobiliario',    false, true, false, true),
  ('Diseño',      'licencia',           4, 'La radicación en curaduría',                     true,  true, false, true),
  ('Diseño',      'presupuesto',        5, 'El presupuesto y el cronograma de obra',         false, true, false, true),
  ('Peritaje',    'levantamiento',      1, null,                                             false, true, false, true),
  ('Peritaje',    'informe',            2, null,                                             false, true, false, true),
  ('Peritaje',    'presupuesto',        3, null,                                             false, true, false, true),
  ('Peritaje',    'entrega_expediente', 4, null,                                             false, true, false, true),
  ('Consultoría', 'levantamiento',      1, null,                                             false, true, false, true),
  ('Consultoría', 'informe',            2, null,                                             false, true, false, true),
  ('Consultoría', 'presupuesto',        3, null,                                             false, true, false, true),
  ('Consultoría', 'entrega_expediente', 4, null,                                             false, true, false, true),
  ('Obra',        'preconstruccion',    1, null,                                             false, true, false, false),
  ('Obra',        'ejecucion',          2, null,                                             false, true, false, false),
  ('Obra',        'cierre',             3, null,                                             false, true, false, false)
) as v(plantilla, fase, orden, entrega, opcional, chequeo, aprobacion, dedicacion)
join public.plantilla_proyecto pl on pl.nombre = v.plantilla
on conflict (plantilla_id, fase) do nothing;

-- ---------- Tareas típicas del anteproyecto (propuesta) ----------
do $$
declare
  v_fase   uuid;
  v_modelo uuid;
begin
  select pf.id into v_fase
  from public.plantilla_fase pf
  join public.plantilla_proyecto pl on pl.id = pf.plantilla_id
  where pl.nombre = 'Diseño' and pf.fase = 'anteproyecto';

  if exists (select 1 from public.plantilla_tarea pt where pt.plantilla_fase_id = v_fase) then
    return;
  end if;

  insert into public.plantilla_tarea (plantilla_fase_id, orden, titulo, proposito, por_espacio, prioridad, dias_plazo)
  values (v_fase, 10, 'Modelo',
          'Con este modelo el cliente ve el espacio antes de construirlo y de aquí salen los renders',
          true, 'alta', 5)
  returning id into v_modelo;

  insert into public.plantilla_tarea
    (plantilla_fase_id, orden, titulo, proposito, por_espacio, prioridad, dias_plazo, depende_de)
  values
    (v_fase, 20, 'Renders',
     'Es la imagen con la que el cliente decide si aprueba el espacio',
     true, 'normal', 8, v_modelo);

  insert into public.plantilla_tarea (plantilla_fase_id, orden, titulo, proposito, por_espacio, prioridad, dias_plazo)
  values
    (v_fase, 30, 'Planos, cortes y alzados',
     'Es el dibujo que el cliente aprueba y del que parte el proyecto final',
     false, 'alta', 8),
    (v_fase, 40, 'Organizar la presentación',
     'Reúne todo lo que el cliente va a ver el día que aprueba el anteproyecto',
     false, 'bloqueante', 10);
end $$;

-- ---------- Festivos de Colombia, 2026 y 2027 ----------
-- Calculados con la Ley 51 de 1983 (traslado al lunes) y la fecha de Pascua.
-- Conviene que alguien del equipo los compare con un calendario antes del
-- piloto, y cargar 2028 antes de que termine 2027.
insert into public.festivo (fecha, nombre) values
  ('2026-01-01', 'Año Nuevo'),
  ('2026-01-12', 'Reyes Magos'),
  ('2026-03-23', 'San José'),
  ('2026-04-02', 'Jueves Santo'),
  ('2026-04-03', 'Viernes Santo'),
  ('2026-05-01', 'Día del Trabajo'),
  ('2026-05-18', 'Ascensión del Señor'),
  ('2026-06-08', 'Corpus Christi'),
  ('2026-06-15', 'Sagrado Corazón'),
  ('2026-06-29', 'San Pedro y San Pablo'),
  ('2026-07-20', 'Independencia'),
  ('2026-08-07', 'Batalla de Boyacá'),
  ('2026-08-17', 'Asunción de la Virgen'),
  ('2026-10-12', 'Día de la Raza'),
  ('2026-11-02', 'Todos los Santos'),
  ('2026-11-16', 'Independencia de Cartagena'),
  ('2026-12-08', 'Inmaculada Concepción'),
  ('2026-12-25', 'Navidad'),
  ('2027-01-01', 'Año Nuevo'),
  ('2027-01-11', 'Reyes Magos'),
  ('2027-03-22', 'San José'),
  ('2027-03-25', 'Jueves Santo'),
  ('2027-03-26', 'Viernes Santo'),
  ('2027-05-01', 'Día del Trabajo'),
  ('2027-05-10', 'Ascensión del Señor'),
  ('2027-05-31', 'Corpus Christi'),
  ('2027-06-07', 'Sagrado Corazón'),
  ('2027-07-05', 'San Pedro y San Pablo'),
  ('2027-07-20', 'Independencia'),
  ('2027-08-07', 'Batalla de Boyacá'),
  ('2027-08-16', 'Asunción de la Virgen'),
  ('2027-10-18', 'Día de la Raza'),
  ('2027-11-01', 'Todos los Santos'),
  ('2027-11-15', 'Independencia de Cartagena'),
  ('2027-12-08', 'Inmaculada Concepción'),
  ('2027-12-25', 'Navidad')
on conflict (fecha) do nothing;
