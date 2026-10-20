-- =============================================================================
-- SICI · Revisión por tarea y varios papeles por persona · R1–R3 y D10
--
-- Lo pidió Felipe el 19-10-2026 comentando la demostración de la aplicación:
--   · «pon un campo que defina si requiere de revisión y otro a quién se le
--     delega la revisión», justo después del responsable.
--   · «crea la posibilidad de seleccionar dos roles, ya que alguien que produce
--     también puede llegar a revisar».
--
-- Reglas:
--   · R1 · Una tarea puede delegar su revisión en una persona: alguien del
--     equipo del proyecto (o dirección), distinto de quien la hace.
--   · R2 · Una tarea puede no requerir revisión: quien la tiene la entrega y
--     queda terminada. No se le pide revisión. La hora de la entrega es la que
--     miden los indicadores.
--   · R3 · Si la revisión se delegó, solo esa persona la aprueba o la devuelve,
--     y solo a ella le aparece en «Revisar».
--   · Lo que ya existía no cambia: toda tarea nace requiriendo revisión y, sin
--     revisor delegado, la revisa quien dirige o tiene el papel de revisar.
--   · D10 · Una persona puede tener varios papeles en un proyecto (produce y
--     revisa, por ejemplo): la llave de acceso_proyecto pasa a ser persona,
--     proyecto y papel. Quitarle un papel no la saca del equipo si le queda
--     otro con el que trabaja.
--   · Quien hace la tarea no cambia si requiere revisión ni quién la revisa:
--     eso es de quien la asignó o dirige (la regla D10 de siempre).
--
-- No toca las migraciones anteriores. Idempotente.
-- =============================================================================

-- ---------- Varios papeles por persona en un proyecto ----------
do $$
begin
  if not exists (select 1 from pg_constraint c
                 where c.conrelid = 'public.acceso_proyecto'::regclass and c.contype = 'p'
                   and cardinality(c.conkey) = 3) then
    alter table public.acceso_proyecto drop constraint acceso_proyecto_pkey;
    alter table public.acceso_proyecto add constraint acceso_proyecto_pkey primary key (persona_id, proyecto_id, papel);
  end if;
end $$;
create index if not exists acceso_proyecto_persona_proyecto on public.acceso_proyecto (persona_id, proyecto_id);

create or replace function private.validar_acceso() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_interno  boolean;
  v_abiertas integer;
begin
  select p.es_interno into v_interno from public.persona p where p.id = new.persona_id;
  if new.papel is null then
    new.papel := case when v_interno then 'produce' else 'observa' end;
  end if;
  if not coalesce(v_interno, false) and new.papel <> 'observa' then
    raise exception 'D10 · Una persona externa no tiene papel en el equipo: solo observa su proyecto';
  end if;
  -- Con varios papeles por persona, solo frena si no le queda otro papel de trabajo.
  if tg_op = 'UPDATE' and new.papel = 'observa' and old.papel <> 'observa'
     and not exists (select 1 from public.acceso_proyecto a
                     where a.persona_id = old.persona_id and a.proyecto_id = old.proyecto_id
                       and a.papel <> 'observa' and a.papel <> old.papel) then
    select count(*) into v_abiertas from public.tarea_diseno t
    where t.proyecto_id = old.proyecto_id and t.asignada_a = old.persona_id and t.estado <> 'terminada';
    if v_abiertas > 0 then
      raise exception 'D10 · Tiene % tarea(s) abierta(s) en este proyecto: reasígnelas antes de dejarla solo como observadora', v_abiertas;
    end if;
  end if;
  return new;
end $$;

create or replace function private.validar_retiro_acceso() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_abiertas integer;
begin
  -- Quitarle un papel no la saca del equipo si le queda otro con el que trabaja.
  if old.papel <> 'observa' and exists (
       select 1 from public.acceso_proyecto a
       where a.persona_id = old.persona_id and a.proyecto_id = old.proyecto_id
         and a.papel <> 'observa' and a.papel <> old.papel) then
    return old;
  end if;
  select count(*) into v_abiertas
  from public.tarea_diseno t
  join public.persona p on p.id = t.asignada_a
  where t.proyecto_id = old.proyecto_id and t.asignada_a = old.persona_id
    and t.estado <> 'terminada' and p.rol not in ('socio','director');
  if v_abiertas > 0 then
    raise exception 'D10 · Tiene % tarea(s) abierta(s) en este proyecto: reasígnelas antes de retirarla del equipo', v_abiertas;
  end if;
  return old;
end $$;

create or replace function private.revisores(p_proyecto uuid) returns setof uuid
language sql stable security definer set search_path = '' as $$
  with designados as (
    select distinct a.persona_id
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

-- ---------- Revisión por tarea ----------
alter table public.tarea_diseno
  add column if not exists requiere_revision boolean not null default true,
  add column if not exists revisor_id uuid references public.persona(id);
create index if not exists tarea_diseno_revisor on public.tarea_diseno (revisor_id) where revisor_id is not null;
comment on column public.tarea_diseno.requiere_revision is
  'R2 · Falso: quien la tiene la entrega y queda terminada, sin revisión. Lo decide quien la asigna.';
comment on column public.tarea_diseno.revisor_id is
  'R1 y R3 · A quién se le delegó la revisión. Vacío: la revisa quien dirige o tiene el papel de revisar.';
alter table public.tarea_diseno drop constraint if exists tarea_revisor_coherente;
alter table public.tarea_diseno add constraint tarea_revisor_coherente check (
  (requiere_revision or revisor_id is null) and revisor_id is distinct from asignada_a);

create or replace function private.validar_tarea() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_yo      uuid := private.persona_actual();
  v_sesion  boolean := auth.uid() is not null;
  v_dirige  boolean := false;
  v_nombre  text;
  v_desde   timestamptz;
  -- Lo que mueve quien hace la tarea. Las dos marcas de tiempo las pone el sistema.
  v_propias text[] := '{estado,descripcion,fecha_inicio,terminada_en,revision_pedida_en}';
begin
  if new.fase_id is not null and not exists (
       select 1 from public.proyecto_fase f where f.id = new.fase_id and f.proyecto_id = new.proyecto_id) then
    raise exception 'La fase no es del proyecto de la tarea';
  end if;
  if tg_op = 'INSERT' and v_sesion then
    new.asignada_por := coalesce(v_yo, new.asignada_por);
  end if;
  if new.bloqueada_por is not null and not exists (
       select 1 from public.tarea_diseno b
       where b.id = new.bloqueada_por and b.proyecto_id = new.proyecto_id) then
    raise exception 'Una tarea solo la bloquea otra del mismo proyecto';
  end if;
  if new.objetivo_id is not null and not exists (
       select 1 from public.objetivo o
       where o.id = new.objetivo_id
         and (o.ambito <> 'proyecto' or o.proyecto_id = new.proyecto_id)) then
    raise exception 'El objetivo es de otro proyecto';
  end if;

  if v_sesion then
    v_dirige := exists (select 1 from private.proyectos_que_dirige() d(id) where d.id = new.proyecto_id);
  end if;

  -- D10 · Quien recibe la tarea hace parte del equipo del proyecto.
  if new.asignada_a is null then
    raise exception 'D10 · Una tarea no se guarda sin persona';
  end if;
  if tg_op = 'INSERT' or new.asignada_a is distinct from old.asignada_a then
    if not exists (
         select 1 from public.persona p
         where p.id = new.asignada_a and p.es_interno and p.activo
           and (p.rol in ('socio','director')
                or exists (select 1 from public.acceso_proyecto a
                           where a.persona_id = p.id and a.proyecto_id = new.proyecto_id
                             and a.papel <> 'observa'))) then
      select p.nombre into v_nombre from public.persona p where p.id = new.asignada_a;
      raise exception 'D10 · % no hace parte del equipo de este proyecto: primero se le da un papel',
        coalesce(v_nombre, 'Esa persona');
    end if;
  end if;

  -- R1 · Quien revisa la tarea, si se le delega a alguien: del equipo (o dirección)
  -- y distinto de quien la hace. Sin revisión, no hay a quién delegarla.
  if not new.requiere_revision then
    new.revisor_id := null;
  end if;
  if new.revisor_id is not null
     and (tg_op = 'INSERT' or new.revisor_id is distinct from old.revisor_id or new.asignada_a is distinct from old.asignada_a) then
    if new.revisor_id = new.asignada_a then
      raise exception 'R1 · La revisa alguien distinto de quien hace la tarea';
    end if;
    if not exists (
         select 1 from public.persona p
         where p.id = new.revisor_id and p.es_interno and p.activo
           and (p.rol in ('socio','director')
                or exists (select 1 from public.acceso_proyecto a
                           where a.persona_id = p.id and a.proyecto_id = new.proyecto_id
                             and a.papel <> 'observa'))) then
      select p.nombre into v_nombre from public.persona p where p.id = new.revisor_id;
      raise exception 'R1 · % no hace parte del equipo de este proyecto: no puede revisar la tarea', coalesce(v_nombre, 'Esa persona');
    end if;
  end if;

  -- D10 · Desde la aplicación no existe una tarea sin fecha de entrega. Las que
  -- vienen sin fecha de la hoja de seguimiento entran por carga y la alerta
  -- "trabajo sin fecha" las saca a la luz.
  if v_sesion and new.fecha_compromiso is null
     and (tg_op = 'INSERT' or old.fecha_compromiso is not null) then
    raise exception 'D10 · Una tarea no se guarda sin fecha de entrega';
  end if;

  -- D10 · Quien hace la tarea la mueve, pero no cambia su fecha, su prioridad
  -- ni a quién le toca.
  if tg_op = 'UPDATE' and v_sesion and not v_dirige and v_yo is distinct from old.asignada_por then
    if (to_jsonb(new) - v_propias) <> (to_jsonb(old) - v_propias) then
      raise exception 'D10 · La fecha, la prioridad y el responsable de una tarea los cambia quien la asignó o quien dirige el proyecto';
    end if;
  end if;

  -- D10 · Crearse una tarea propia y pasársela a otro sería asignar por la
  -- puerta de atrás: reasignar es de quien puede asignar.
  if tg_op = 'UPDATE' and v_sesion and not v_dirige
     and (new.asignada_a is distinct from old.asignada_a or new.asignada_por is distinct from old.asignada_por)
     and not private.tiene_rol('{arquitecto}'::public.rol_persona[]) then
    raise exception 'D10 · Una tarea la reasigna quien dirige el proyecto o un arquitecto';
  end if;

  -- Las marcas de tiempo no se escriben a mano.
  if v_sesion then
    new.terminada_en := case when tg_op = 'UPDATE' then old.terminada_en end;
    new.revision_pedida_en := case when tg_op = 'UPDATE' then old.revision_pedida_en end;
  end if;

  if tg_op = 'INSERT' and v_sesion and new.estado not in ('asignada','en_curso') then
    raise exception 'D11 · Una tarea nace asignada o en curso';
  end if;

  if tg_op = 'UPDATE' and old.estado = 'terminada' and new.estado <> 'terminada' then
    if v_sesion and not private.es_direccion() then
      raise exception 'D11 · Una tarea terminada solo la reabre dirección';
    end if;
    new.terminada_en := null;
  end if;

  -- Pedir revisión.
  if new.estado = 'en_revision' and (tg_op = 'INSERT' or old.estado <> 'en_revision') then
    if not new.requiere_revision then
      raise exception 'R2 · «%» no requiere revisión: quien la tiene la entrega y queda terminada', new.titulo;
    end if;
    if exists (select 1 from public.tarea_diseno b
               where b.id = new.bloqueada_por and b.estado <> 'terminada') then
      raise exception 'D9 · «%» no puede pedir revisión mientras espera la tarea que la bloquea', new.titulo;
    end if;
    if v_sesion and not v_dirige and v_yo is distinct from new.asignada_a then
      raise exception 'D11 · La revisión la pide quien tiene la tarea';
    end if;
    new.revision_pedida_en := clock_timestamp();
  elsif tg_op = 'UPDATE' and old.estado = 'en_revision' and new.estado in ('asignada','en_curso') then
    new.revision_pedida_en := null;
  end if;

  -- Devuelta: solo por una revisión posterior a la última vez que se pidió.
  if new.estado = 'con_observaciones' and (tg_op = 'INSERT' or old.estado <> 'con_observaciones') then
    if tg_op = 'INSERT' then
      if v_sesion then
        raise exception 'D11 · Una tarea queda con observaciones solo cuando quien revisa la devuelve';
      end if;
    elsif old.estado <> 'en_revision' or not exists (
            select 1 from public.revision_diseno r
            where r.tarea_id = new.id and r.resultado = 'con_observaciones'
              and r.revisada_en >= coalesce(old.revision_pedida_en, old.creada_en)) then
      raise exception 'D11 · Una tarea queda con observaciones solo cuando quien revisa la devuelve';
    end if;
  end if;

  -- Terminada: solo con la revisión aprobada de otra persona, y esa revisión
  -- tiene que ser de esta entrega, no de una anterior que se devolvió.
  if new.estado = 'terminada' and (tg_op = 'INSERT' or old.estado <> 'terminada') then
    if exists (select 1 from public.tarea_diseno b
               where b.id = new.bloqueada_por and b.estado <> 'terminada') then
      raise exception 'D9 · «%» espera a que se termine la tarea que la bloquea', new.titulo;
    end if;
    if tg_op = 'UPDATE' then
      v_desde := coalesce(old.revision_pedida_en, old.creada_en);
    end if;
    if not new.requiere_revision then
      -- R2 · Sin revisión, la entrega la hace quien tiene la tarea (o quien dirige),
      -- y esa hora es la entrega que miden los indicadores.
      if v_sesion and not v_dirige and v_yo is distinct from new.asignada_a then
        raise exception 'R2 · La entrega la hace quien tiene la tarea';
      end if;
      new.revision_pedida_en := coalesce(new.revision_pedida_en, clock_timestamp());
    elsif tg_op = 'INSERT' or old.estado <> 'en_revision' or not exists (
         select 1 from public.revision_diseno r
         where r.tarea_id = new.id and r.resultado = 'aprobada'
           and r.revisor_id <> new.asignada_a and r.revisada_en >= v_desde
           and (new.revisor_id is null or r.revisor_id = new.revisor_id)) then
      raise exception 'Una tarea no se termina sin la revisión aprobada de alguien distinto de quien la hizo';
    end if;
    new.terminada_en := coalesce(new.terminada_en, now());
  end if;
  return new;
end $$;

create or replace function private.validar_revision() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_asignada uuid;
  v_estado   public.estado_tarea;
  v_titulo   text;
  v_requiere boolean;
  v_revisor  uuid;
  v_nombre   text;
begin
  if auth.uid() is not null then
    new.revisor_id := private.persona_actual();
  end if;
  select t.asignada_a, t.estado, t.titulo, t.requiere_revision, t.revisor_id
    into v_asignada, v_estado, v_titulo, v_requiere, v_revisor
  from public.tarea_diseno t where t.id = new.tarea_id;
  if not v_requiere then
    raise exception 'R2 · «%» no requiere revisión', v_titulo;
  end if;
  -- R3 · Si se le delegó a alguien, solo esa persona la aprueba o la devuelve.
  if v_revisor is not null and new.revisor_id is distinct from v_revisor then
    select p.nombre into v_nombre from public.persona p where p.id = v_revisor;
    raise exception 'R3 · «%» la revisa %: se le delegó a esa persona', v_titulo, coalesce(v_nombre, 'otra persona');
  end if;
  if new.revisor_id = v_asignada then
    raise exception 'La revisión la hace alguien distinto de quien hizo la tarea';
  end if;
  if v_estado <> 'en_revision' then
    raise exception 'D11 · Solo se revisa lo que pidió revisión: «%» está %', v_titulo, replace(v_estado::text, '_', ' ');
  end if;
  new.revisada_en := clock_timestamp();
  return new;
end $$;

-- ---------- Quién puede escribir una revisión ----------
drop policy if exists revision_diseno_alta on public.revision_diseno;
create policy revision_diseno_alta on public.revision_diseno for insert to authenticated
  with check (exists (select 1 from public.tarea_diseno t
                      where t.id = revision_diseno.tarea_id
                        and (t.revisor_id = (select private.persona_actual())
                             or (t.revisor_id is null and t.proyecto_id in (select private.proyectos_que_revisa())))));

create or replace view public.v_cola_revision with (security_invoker = true) as
select
  t.id                         as tarea_id,
  t.proyecto_id,
  p.codigo                     as proyecto,
  t.titulo,
  t.asignada_a                 as persona_id,
  a.nombre                     as persona,
  t.prioridad,
  t.fecha_compromiso,
  t.revision_pedida_en,
  h.dias                       as dias_habiles_esperando,
  h.dias > par.dias_habiles_revision as fuera_de_plazo,
  (select count(*) from public.revision_diseno r
    where r.tarea_id = t.id and r.resultado = 'con_observaciones')::integer as devoluciones,
  case
    when h.dias > par.dias_habiles_revision
      then a.nombre || ' espera hace ' || h.dias || ' días hábiles; el acuerdo son ' || par.dias_habiles_revision
    when h.dias = 0 then a.nombre || ' la dejó hoy'
    when h.dias = 1 then a.nombre || ' la dejó hace un día hábil'
    else a.nombre || ' la dejó hace ' || h.dias || ' días hábiles'
  end                          as lectura,
  t.revisor_id
from public.tarea_diseno t
join public.proyecto p  on p.id = t.proyecto_id
join public.persona a   on a.id = t.asignada_a
cross join public.parametro par
cross join lateral (
  select private.dias_habiles(
           (coalesce(t.revision_pedida_en, t.creada_en) at time zone 'America/Bogota')::date,
           private.hoy()) as dias
) h
where t.estado = 'en_revision'
  and t.asignada_a is distinct from (select private.persona_actual())
  -- R3 · La delegada a alguien solo le aparece a esa persona.
  and (t.revisor_id = (select private.persona_actual())
       or (t.revisor_id is null and t.proyecto_id in (select private.proyectos_que_revisa())));

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
    cross join lateral (
      select t.revisor_id where t.revisor_id is not null
      union all
      select dv.id from private.revisores(t.proyecto_id) dv(id) where t.revisor_id is null
    ) rv(id)
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

revoke all on public.v_cola_revision from anon, authenticated;
grant select on public.v_cola_revision to authenticated;
revoke all on all functions in schema public  from public, anon;
revoke all on all functions in schema private from public, anon;
grant select, insert, update, delete on all tables in schema public to service_role;
grant execute on all functions in schema public to service_role;
