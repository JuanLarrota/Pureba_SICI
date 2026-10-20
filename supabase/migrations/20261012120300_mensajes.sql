-- =============================================================================
-- SICI · Módulo de arquitectura y diseño · etapa 2 · mensajes
--
--   D16 · El sistema le escribe a cada persona para que no tenga que acordarse
--         de abrirlo. Cada mensaje dice una sola cosa y lleva la tarea exacta
--         de la que habla.
--
-- Una alerta es un estado que ve quien dirige ("hay un capítulo desviado") y se
-- resuelve sola. Un mensaje es un aviso puntual a una persona. Por eso van en
-- tablas distintas.
--
-- Los límites, decididos el 12 de octubre de 2026:
--   · máximo dos al día por persona, fuera del de registrar el día; lo que no
--     cabe se junta en uno solo a la mañana siguiente;
--   · solo en días hábiles, de 7:30 a. m. a 5:00 p. m.;
--   · quien marcó ausencia no recibe nada ese día;
--   · una tarea vencida avisa el primer día hábil, vuelve al tercero y al
--     quinto sube a quien dirige; no se repite a diario;
--   · nunca se compara a una persona con otra;
--   · los mensajes de una persona los lee ella y nadie más.
--
-- Aquí queda la bandeja y quién decide qué sale y cuándo. El envío real
-- (notificación y correo) es la etapa 5: lee lo que esté en 'listo'.
-- Idempotente.
-- =============================================================================

alter table public.parametro
  add column if not exists mensajes_max_dia   smallint not null default 2,
  add column if not exists mensajes_desde     time     not null default '07:30',
  add column if not exists mensajes_hasta     time     not null default '17:00',
  add column if not exists hora_registro_dia  time     not null default '16:30',
  add column if not exists hora_tu_semana     time     not null default '15:00';
do $$ begin
  alter table public.parametro add constraint parametro_mensajes_sanos check (
    mensajes_max_dia >= 1 and mensajes_desde < mensajes_hasta
    and hora_registro_dia between mensajes_desde and mensajes_hasta
    and hora_tu_semana between mensajes_desde and mensajes_hasta);
exception when duplicate_object then null; end $$;

-- Cada tipo de mensaje: qué tan urgente es (1 sale primero) y si gasta cupo.
create table if not exists public.regla_mensaje (
  tipo               text primary key,
  descripcion        text not null,
  prioridad          smallint not null default 5,
  cuenta_en_limite   boolean not null default true,
  canales            public.canal_aviso[] not null default '{plataforma,correo}',
  activa             boolean not null default true
);

insert into public.regla_mensaje (tipo, descripcion, prioridad, cuenta_en_limite, canales) values
  ('tarea_devuelta',      'Te devolvieron una tarea',                         1, true,  '{plataforma,correo}'),
  ('alguien_espera',      'Alguien espera por una tarea tuya',                2, true,  '{plataforma,correo}'),
  ('tarea_vencida',       'Una tarea pasó su fecha de entrega',               3, true,  '{plataforma,correo}'),
  ('revision_pendiente',  'Hay algo para revisar',                            3, true,  '{plataforma,correo}'),
  ('entrega_manana',      'Se acerca una entrega',                            4, true,  '{plataforma}'),
  ('reconocimiento',      'Se aprobó algo que pesaba, o se cerró una fase',   5, true,  '{plataforma,correo}'),
  ('tu_semana',           'Tus frases de impacto de la semana',               6, true,  '{plataforma,correo}'),
  ('resumen',             'Lo que no cupo ayer, junto en un solo mensaje',    2, true,  '{plataforma,correo}'),
  ('falta_registrar_dia', 'Falta registrar el día',                           9, false, '{plataforma}')
on conflict (tipo) do nothing;

-- La bandeja. en_cola: espera su turno. listo: ya puede salir. enviado: salió
-- (lo marca el servicio de envío). agrupado: salió dentro de un resumen.
-- descartado: dejó de tener sentido antes de salir.
create table if not exists public.mensaje (
  id           uuid primary key default gen_random_uuid(),
  persona_id   uuid not null references public.persona(id),
  tipo         text not null references public.regla_mensaje(tipo),
  clave        text not null,            -- evita decir dos veces lo mismo
  texto        text not null,
  proyecto_id  uuid references public.proyecto(id),
  tarea_id     uuid references public.tarea_diseno(id),
  fase_id      uuid references public.proyecto_fase(id),
  estado       text not null default 'en_cola'
               check (estado in ('en_cola','listo','enviado','agrupado','descartado')),
  agrupado_en  uuid references public.mensaje(id),
  creado_en    timestamptz not null default now(),
  liberado_en  timestamptz,
  enviado_en   timestamptz,
  leido_en     timestamptz,
  unique (persona_id, clave),
  constraint mensaje_texto_escrito check (length(trim(texto)) > 0)
);
create index if not exists mensaje_persona_estado on public.mensaje (persona_id, estado);
create index if not exists mensaje_tipo on public.mensaje (tipo);
create index if not exists mensaje_proyecto on public.mensaje (proyecto_id);
create index if not exists mensaje_tarea on public.mensaje (tarea_id);
create index if not exists mensaje_fase on public.mensaje (fase_id);
create index if not exists mensaje_agrupado_en on public.mensaje (agrupado_en);
create index if not exists mensaje_por_salir on public.mensaje (liberado_en) where estado = 'listo';

drop trigger if exists tr_mensaje_no_borrar on public.mensaje;
create trigger tr_mensaje_no_borrar
  before delete on public.mensaje
  for each row execute function private.prohibir_borrado();


-- =============================================================================
-- 1. A quién le llega
-- =============================================================================

-- Quien revisa en un proyecto: los designados y quien lo dirige; si no hay
-- nadie designado, los directores.
create or replace function private.revisores(p_proyecto uuid) returns setof uuid
language sql stable security definer set search_path = '' as $$
  with designados as (
    select a.persona_id
    from public.acceso_proyecto a
    join public.persona p on p.id = a.persona_id
    where a.proyecto_id = p_proyecto and a.papel in ('revisa','dirige') and p.activo and p.es_interno
  )
  select d.persona_id from designados d
  union all
  select p.id from public.persona p
  where p.rol = 'director' and p.activo and p.es_interno
    and not exists (select 1 from designados)
$$;

create or replace function private.quien_dirige(p_proyecto uuid) returns setof uuid
language sql stable security definer set search_path = '' as $$
  with designados as (
    select a.persona_id
    from public.acceso_proyecto a
    join public.persona p on p.id = a.persona_id
    where a.proyecto_id = p_proyecto and a.papel = 'dirige' and p.activo and p.es_interno
  )
  select d.persona_id from designados d
  union all
  select p.id from public.persona p
  where p.rol = 'director' and p.activo and p.es_interno
    and not exists (select 1 from designados)
$$;

-- Deja un mensaje en la cola. Solo para personas activas con usuario, y solo
-- si la regla está activa. Si ya existe y sigue en cola, actualiza el texto.
create or replace function private.encolar(
  p_persona uuid, p_tipo text, p_clave text, p_texto text,
  p_proyecto uuid default null, p_tarea uuid default null, p_fase uuid default null)
returns void
language sql security definer set search_path = '' as $$
  insert into public.mensaje (persona_id, tipo, clave, texto, proyecto_id, tarea_id, fase_id)
  select p.id, r.tipo, p_clave, p_texto, p_proyecto, p_tarea, p_fase
  from public.persona p
  join public.regla_mensaje r on r.tipo = p_tipo and r.activa
  where p.id = p_persona and p.activo and p.es_interno and p.auth_user_id is not null
    and p_texto is not null
  on conflict (persona_id, clave) do update
    set texto = excluded.texto, tarea_id = excluded.tarea_id
    where public.mensaje.estado = 'en_cola' and public.mensaje.texto is distinct from excluded.texto
$$;


-- =============================================================================
-- 2. Los que salen al momento
-- =============================================================================

-- Te devolvieron una tarea · Se aprobó algo que pesaba.
create or replace function private.mensajes_de_revision() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  t          public.tarea_diseno%rowtype;
  v_revisor  text;
  v_siguen   text;
  v_cuantos  integer;
begin
  select * into t from public.tarea_diseno x where x.id = new.tarea_id;
  select split_part(p.nombre, ' ', 1) into v_revisor from public.persona p where p.id = new.revisor_id;

  if new.resultado = 'con_observaciones' then
    perform private.encolar(t.asignada_a, 'tarea_devuelta', 'devuelta:' || new.id,
      v_revisor || ' devolvió «' || t.titulo || '» con una observación', t.proyecto_id, t.id);
    return null;
  end if;

  -- El reconocimiento es para lo que pesaba y que asignó otra persona.
  if t.asignada_por = t.asignada_a then
    return null;
  end if;
  select count(distinct d.asignada_a),
         string_agg(distinct split_part(p.nombre, ' ', 1), ' y ')
    into v_cuantos, v_siguen
  from public.tarea_diseno d
  join public.persona p on p.id = d.asignada_a
  where d.bloqueada_por = t.id and d.estado <> 'terminada' and d.asignada_a <> t.asignada_a;
  if t.prioridad <> 'bloqueante' and v_cuantos = 0 then
    return null;
  end if;
  perform private.encolar(t.asignada_a, 'reconocimiento', 'aprobada:' || new.id,
    'Se aprobó «' || t.titulo || '»'
    || case when not exists (select 1 from public.revision_diseno r
                             where r.tarea_id = t.id and r.resultado = 'con_observaciones')
            then ' a la primera' else '' end
    || case when v_cuantos = 0 then '. Era de las que no podían esperar'
            when v_cuantos = 1 then '. ' || v_siguen || ' ya puede seguir'
            else '. ' || v_siguen || ' ya pueden seguir' end,
    t.proyecto_id, t.id);
  return null;
end $$;

drop trigger if exists tr_revision_diseno_mensajes on public.revision_diseno;
create trigger tr_revision_diseno_mensajes
  after insert on public.revision_diseno
  for each row execute function private.mensajes_de_revision();

-- Se cerró una fase: a cada quien, lo que puso en ella.
create or replace function private.mensajes_de_fase() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_proyecto text;
  v_total    integer;
  r          record;
begin
  if new.estado <> 'cerrada' or old.estado = 'cerrada' then
    return null;
  end if;
  select p.nombre into v_proyecto from public.proyecto p where p.id = new.proyecto_id;
  select count(*) into v_total
  from public.tarea_diseno t where t.fase_id = new.id and t.estado = 'terminada';

  for r in
    select t.asignada_a,
           count(*) as suyas,
           count(*) filter (where not exists (
             select 1 from public.revision_diseno x
             where x.tarea_id = t.id and x.resultado = 'con_observaciones')) as primera
    from public.tarea_diseno t
    where t.fase_id = new.id and t.estado = 'terminada' and t.asignada_por <> t.asignada_a
    group by t.asignada_a
  loop
    perform private.encolar(r.asignada_a, 'reconocimiento', 'fase:' || new.id,
      case when new.aprobada_cliente_en is not null then 'El cliente aprobó ' else 'Se cerró ' end
      || replace(new.fase::text, '_', ' ') || ' de ' || v_proyecto || '. '
      || case when v_total = 1 then 'La única pieza era tuya'
              when r.suyas = v_total then 'Las ' || v_total || ' piezas eran tuyas'
              when r.suyas = 1 then 'Una de las ' || v_total || ' piezas era tuya'
              else r.suyas || ' de las ' || v_total || ' piezas eran tuyas' end
      || case when r.primera = 0 then ''
              when r.primera = r.suyas and r.suyas = 1 then ' y pasó a la primera'
              when r.primera = r.suyas then ' y todas pasaron a la primera'
              when r.primera = 1 then ', y una pasó a la primera'
              else ', y ' || r.primera || ' pasaron a la primera' end,
      new.proyecto_id, null, new.id);
  end loop;
  return null;
end $$;

drop trigger if exists tr_proyecto_fase_mensajes on public.proyecto_fase;
create trigger tr_proyecto_fase_mensajes
  after update on public.proyecto_fase
  for each row execute function private.mensajes_de_fase();


-- =============================================================================
-- 3. Los que salen por barrido
-- El reloj entra como parámetro: así se puede probar un sábado, un festivo o
-- las 4:30 de la tarde sin esperar a que lleguen.
-- =============================================================================

create or replace function private.generar_mensajes(p_ahora timestamptz default now()) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_par     public.parametro%rowtype;
  v_hoy     date := (p_ahora at time zone 'America/Bogota')::date;
  v_hora    time := (p_ahora at time zone 'America/Bogota')::time;
  v_manana  date;
  v_antes   bigint;
  v_dias    text[] := '{lunes,martes,miércoles,jueves,viernes,sábado,domingo}';
  r         record;
begin
  if not private.es_habil(v_hoy) then
    return 0;
  end if;
  select * into v_par from public.parametro p where p.id;
  select count(*) into v_antes from public.mensaje;
  v_manana := private.sumar_habiles(v_hoy, 1);

  -- Se acerca una entrega: el día hábil anterior.
  perform private.encolar(t.asignada_a, 'entrega_manana', 'entrega:' || t.id || ':' || t.fecha_compromiso,
    case when v_manana = v_hoy + 1 then 'Mañana' else 'El ' || v_dias[extract(isodow from v_manana)::int] end
    || ' entregas «' || t.titulo || '» de ' || p.nombre, t.proyecto_id, t.id)
  from public.tarea_diseno t
  join public.proyecto p on p.id = t.proyecto_id and p.estado = 'activo'
  where t.estado in ('asignada','en_curso','con_observaciones') and t.fecha_compromiso = v_manana;

  -- Tarea vencida: el primer día hábil, el tercero, y al quinto sube.
  for r in
    select t.id, t.titulo, t.proyecto_id, t.asignada_a, t.asignada_por, t.fecha_compromiso,
           p.nombre as proyecto, split_part(a.nombre, ' ', 1) as quien,
           private.dias_habiles(t.fecha_compromiso, v_hoy) as atraso
    from public.tarea_diseno t
    join public.proyecto p on p.id = t.proyecto_id and p.estado = 'activo'
    join public.persona a  on a.id = t.asignada_a
    where t.estado in ('asignada','en_curso','con_observaciones') and t.fecha_compromiso < v_hoy
  loop
    if r.atraso >= 1 then
      -- Si ya va por el tercer día, a quien la tiene le basta el aviso de abajo.
      if r.atraso < 3 then
        perform private.encolar(r.asignada_a, 'tarea_vencida', 'vencida:' || r.id || ':' || r.fecha_compromiso || ':1',
          '«' || r.titulo || '» de ' || r.proyecto || ' se entregaba el '
          || to_char(r.fecha_compromiso, 'DD/MM') || ' y sigue abierta', r.proyecto_id, r.id);
      end if;
      -- A quien la asignó. Si ya va por el quinto día le llega el de abajo, no los dos.
      if r.asignada_por <> r.asignada_a and r.atraso < 5 then
        perform private.encolar(r.asignada_por, 'tarea_vencida', 'vencida:' || r.id || ':' || r.fecha_compromiso || ':1',
          r.quien || ' tenía «' || r.titulo || '» de ' || r.proyecto || ' para el '
          || to_char(r.fecha_compromiso, 'DD/MM') || ' y sigue abierta', r.proyecto_id, r.id);
      end if;
    end if;
    if r.atraso >= 3 then
      perform private.encolar(r.asignada_a, 'tarea_vencida', 'vencida:' || r.id || ':' || r.fecha_compromiso || ':3',
        '«' || r.titulo || '» de ' || r.proyecto || ' lleva ' || private.en_dias(r.atraso) || ' de atraso',
        r.proyecto_id, r.id);
    end if;
    if r.atraso >= 5 then
      perform private.encolar(d.id, 'tarea_vencida', 'vencida:' || r.id || ':' || r.fecha_compromiso || ':sube',
        r.quien || ' lleva ' || private.en_dias(r.atraso) || ' de atraso con «' || r.titulo || '» de ' || r.proyecto,
        r.proyecto_id, r.id)
      from (select q.id from private.quien_dirige(r.proyecto_id) q(id)
            union
            select r.asignada_por) d
      where d.id <> r.asignada_a;
    end if;
  end loop;

  -- Alguien espera por ti: la tarea que depende de la tuya ya debería andar.
  perform private.encolar(t.asignada_a, 'alguien_espera', 'espera:' || t.id || ':' || d.id,
    split_part(dp.nombre, ' ', 1) || ' no puede avanzar con «' || d.titulo || '» hasta que cierres «' || t.titulo || '»',
    t.proyecto_id, t.id)
  from public.tarea_diseno t
  join public.tarea_diseno d on d.bloqueada_por = t.id and d.estado <> 'terminada' and d.asignada_a <> t.asignada_a
  join public.persona dp     on dp.id = d.asignada_a
  join public.proyecto p     on p.id = t.proyecto_id and p.estado = 'activo'
  where t.estado in ('asignada','en_curso','con_observaciones')
    and (t.fecha_compromiso < v_hoy or d.fecha_compromiso <= private.sumar_habiles(v_hoy, 3));

  -- Hay algo para revisar: uno por persona y proyecto, aunque sean varias piezas.
  perform private.encolar(x.revisor, 'revision_pendiente',
    'revisar:' || x.proyecto_id || ':' || x.asignada_a || ':' || v_hoy,
    x.quien || ' te dejó '
    || case when x.cuantas = 1 then '«' || x.titulo || '»' else x.cuantas || ' piezas' end
    || ' de ' || x.proyecto || ' para revisar',
    x.proyecto_id, case when x.cuantas = 1 then x.tarea_id end)
  from (
    select rv.id as revisor, t.proyecto_id, t.asignada_a, p.nombre as proyecto,
           split_part(a.nombre, ' ', 1) as quien,
           count(*) as cuantas, min(t.titulo) as titulo, (array_agg(t.id))[1] as tarea_id
    from public.tarea_diseno t
    join public.proyecto p on p.id = t.proyecto_id and p.estado = 'activo'
    join public.persona a  on a.id = t.asignada_a
    cross join lateral private.revisores(t.proyecto_id) rv(id)
    where t.estado = 'en_revision' and rv.id <> t.asignada_a
    group by rv.id, t.proyecto_id, t.asignada_a, p.nombre, a.nombre
  ) x;

  -- Falta registrar el día.
  if v_hora >= v_par.hora_registro_dia then
    perform private.encolar(p.id, 'falta_registrar_dia', 'dia:' || v_hoy, '¿Dónde estuviste hoy? Son dos toques')
    from public.persona p
    where p.activo and p.es_interno
      and p.rol::text in ('director','arquitecto','practicante','director_proyecto')
      and not exists (select 1 from public.dedicacion d where d.persona_id = p.id and d.fecha = v_hoy);
  end if;

  -- Tu semana: el último día hábil de la semana, en la tarde. Solo si hay algo
  -- que decir con justicia.
  if v_hora >= v_par.hora_tu_semana
     and not exists (
       select 1 from generate_series(v_hoy + 1, v_hoy + (5 - extract(isodow from v_hoy)::int), interval '1 day') g(dia)
       where private.es_habil(g.dia::date)) then
    for r in
      select p.id from public.persona p
      where p.activo and p.es_interno and p.auth_user_id is not null
    loop
      perform private.encolar(r.id, 'tu_semana', 'semana:' || date_trunc('week', v_hoy)::date,
        (select string_agg(i.frase, E'\n' order by i.orden)
           from private.indicadores_de(r.id, v_hoy, true) i
          where i.suficiente and i.indicador in ('cumplio','primera','espera','hitos')));
    end loop;
  end if;

  return ((select count(*) from public.mensaje) - v_antes)::integer;
end $$;

-- Decide qué sale ahora. Devuelve cuántos mensajes liberó.
create or replace function private.despachar_mensajes(p_ahora timestamptz default now()) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_par      public.parametro%rowtype;
  v_hoy      date := (p_ahora at time zone 'America/Bogota')::date;
  v_hora     time := (p_ahora at time zone 'America/Bogota')::time;
  v_salen    integer := 0;
  v_n        integer;
  v_cupo     integer;
  v_cola     integer;
  v_resumen  uuid;
  v_resto    uuid[];
  r          record;
begin
  select * into v_par from public.parametro p where p.id;

  -- Lo que dejó de tener sentido no sale tarde.
  update public.mensaje m set estado = 'descartado'
  where m.estado = 'en_cola'
    and ((m.tipo in ('entrega_manana','tarea_vencida','alguien_espera')
          and exists (select 1 from public.tarea_diseno t
                      where t.id = m.tarea_id and t.estado in ('en_revision','terminada')))
      or (m.tipo = 'tarea_devuelta'
          and exists (select 1 from public.tarea_diseno t
                      where t.id = m.tarea_id and t.estado <> 'con_observaciones'))
      or (m.tipo in ('entrega_manana','falta_registrar_dia','revision_pendiente')
          and (m.creado_en at time zone 'America/Bogota')::date < v_hoy)
      or (m.tipo = 'falta_registrar_dia'
          and exists (select 1 from public.dedicacion d
                      where d.persona_id = m.persona_id and d.fecha = v_hoy)));

  if not private.es_habil(v_hoy) or v_hora < v_par.mensajes_desde or v_hora > v_par.mensajes_hasta then
    return 0;
  end if;

  for r in
    select distinct m.persona_id
    from public.mensaje m
    where m.estado = 'en_cola'
      and not exists (select 1 from public.dedicacion d
                      where d.persona_id = m.persona_id and d.fecha = v_hoy and d.tipo = 'ausencia')
  loop
    -- El recordatorio de registrar el día no gasta cupo.
    update public.mensaje m set estado = 'listo', liberado_en = p_ahora
    from public.regla_mensaje g
    where g.tipo = m.tipo and not g.cuenta_en_limite
      and m.persona_id = r.persona_id and m.estado = 'en_cola';
    get diagnostics v_n = row_count;
    v_salen := v_salen + v_n;

    select v_par.mensajes_max_dia - count(*) into v_cupo
    from public.mensaje m
    join public.regla_mensaje g on g.tipo = m.tipo and g.cuenta_en_limite
    where m.persona_id = r.persona_id and m.estado in ('listo','enviado')
      and (m.liberado_en at time zone 'America/Bogota')::date = v_hoy;
    select count(*) into v_cola
    from public.mensaje m
    where m.persona_id = r.persona_id and m.estado = 'en_cola';
    continue when v_cupo <= 0 or v_cola = 0;

    -- Si no caben todos: salen los más urgentes y el resto va junto en uno.
    with orden as (
      select m.id, row_number() over (order by g.prioridad, m.creado_en, m.id) as n
      from public.mensaje m
      join public.regla_mensaje g on g.tipo = m.tipo
      where m.persona_id = r.persona_id and m.estado = 'en_cola'
    )
    update public.mensaje m set estado = 'listo', liberado_en = p_ahora
    from orden o
    where o.id = m.id and o.n <= case when v_cola <= v_cupo then v_cola else v_cupo - 1 end;
    get diagnostics v_n = row_count;
    v_salen := v_salen + v_n;

    if v_cola > v_cupo then
      select array_agg(m.id order by g.prioridad, m.creado_en, m.id) into v_resto
      from public.mensaje m
      join public.regla_mensaje g on g.tipo = m.tipo
      where m.persona_id = r.persona_id and m.estado = 'en_cola';
      v_resumen := gen_random_uuid();
      insert into public.mensaje (id, persona_id, tipo, clave, texto, estado, liberado_en)
      select v_resumen, r.persona_id, 'resumen', 'resumen:' || v_resumen,
             'Tienes ' || cardinality(v_resto) || ' avisos más:' || E'\n'
             || (select string_agg('· ' || m.texto, E'\n' order by x.n)
                   from unnest(v_resto) with ordinality x(id, n)
                   join public.mensaje m on m.id = x.id
                  where x.n <= 6)
             || case when cardinality(v_resto) > 6 then E'\n· y ' || (cardinality(v_resto) - 6) || ' más' else '' end,
             'listo', p_ahora;
      update public.mensaje m set estado = 'agrupado', agrupado_en = v_resumen, liberado_en = p_ahora
      where m.id = any (v_resto);
      v_salen := v_salen + 1;
    end if;
  end loop;
  return v_salen;
end $$;

comment on function private.generar_mensajes(timestamptz) is
  'Programar junto con despachar_mensajes() cada 15 minutos en días hábiles, por ejemplo con pg_cron: select cron.schedule(''sici-mensajes'', ''*/15 12-22 * * 1-5'', ''select private.generar_mensajes(); select private.despachar_mensajes()''); (el servidor vive en UTC: 12 a 22 son las 7 a. m. a 5 p. m. de Colombia).';

-- La alerta de tarea vencida sigue en el tablero de quien dirige, pero ya no
-- manda correo: el correo lo lleva el mensaje, con su escalamiento.
update public.regla_alerta set canales = '{plataforma}'
 where tipo = 'tarea_vencida' and canales <> '{plataforma}';


-- =============================================================================
-- 4. Permisos
-- =============================================================================

alter table public.regla_mensaje enable row level security;
alter table public.mensaje       enable row level security;

drop policy if exists regla_mensaje_lectura on public.regla_mensaje;
create policy regla_mensaje_lectura on public.regla_mensaje for select to authenticated
  using ((select private.es_interno()));

drop policy if exists regla_mensaje_edicion on public.regla_mensaje;
create policy regla_mensaje_edicion on public.regla_mensaje for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- Los mensajes de una persona los lee ella. Ni dirección ve los de otro: ahí
-- van su reconocimiento y sus frases de la semana.
drop policy if exists mensaje_lectura on public.mensaje;
create policy mensaje_lectura on public.mensaje for select to authenticated
  using (persona_id = (select private.persona_actual()) and estado in ('listo','enviado'));

drop policy if exists mensaje_edicion on public.mensaje;
create policy mensaje_edicion on public.mensaje for update to authenticated
  using (persona_id = (select private.persona_actual()) and estado in ('listo','enviado'))
  with check (persona_id = (select private.persona_actual()));

revoke all on public.regla_mensaje, public.mensaje from anon, authenticated;
revoke all on all functions in schema public  from public, anon;
revoke all on all functions in schema private from public, anon;
revoke all on function
  private.revisores(uuid), private.quien_dirige(uuid),
  private.encolar(uuid, text, text, text, uuid, uuid, uuid),
  private.mensajes_de_revision(), private.mensajes_de_fase(),
  private.generar_mensajes(timestamptz), private.despachar_mensajes(timestamptz)
from authenticated;

grant select, update on public.regla_mensaje to authenticated;
grant select on public.mensaje to authenticated;
grant update (leido_en) on public.mensaje to authenticated;   -- lo único que la persona marca

grant select, insert, update, delete on all tables in schema public to service_role;
grant execute on all functions in schema public to service_role;
grant execute on all functions in schema private to service_role;
