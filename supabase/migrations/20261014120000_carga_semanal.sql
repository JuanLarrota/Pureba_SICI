-- =============================================================================
-- SICI · La carga del equipo por semana (D17 · 14-10-2026)
--
--   · Cada tarea dice cuántos días de trabajo pide. Lo pone quien la asigna,
--     con un selector; quien la hace no llena nada.
--   · carga_semanal(): por persona y por semana, cuántos días hábiles tiene y
--     cuántos ya tiene ocupados. Con eso se ve quién está libre antes de
--     entregarle otra tarea.
--
-- El trabajo de una tarea se reparte parejo entre los días hábiles que hay de
-- su inicio a su entrega. Lo vencido cae entero en el primer día: es lo que
-- la persona debe antes de recibir algo más. Lo que ya está en revisión no
-- cuenta: ya no depende de ella.
--
-- No toca las migraciones anteriores. Idempotente.
-- =============================================================================

alter table public.tarea_diseno add column if not exists dias_estimados numeric(4,1);
do $$ begin
  alter table public.tarea_diseno add constraint tarea_estimado_sano
    check (dias_estimados is null or dias_estimados between 0.1 and 120);
exception when duplicate_object then null; end $$;
comment on column public.tarea_diseno.dias_estimados is
  'Días de trabajo que pide la tarea. Lo pone quien la asigna. Sin este dato la tarea se ve en el calendario pero no suma carga.';

-- Quien dirige o asigna ve a todo el equipo, con el total de cada persona
-- aunque parte de su trabajo sea de proyectos ajenos: sin eso no se sabe quién
-- está libre. Salen solo números, nunca los títulos. Los demás ven su fila.
create or replace function private.carga_semanal_de(p_desde date, p_semanas integer)
returns table (
  persona_id     uuid,
  nombre         text,
  semana         date,
  dias_habiles   numeric,
  dias_ocupados  numeric,
  tareas         integer,
  sin_estimar    integer,
  vencidas       integer)
language sql stable security definer set search_path = '' as $$
  with lim as (
    select p_desde as hoy,
           -- En fin de semana, la primera semana es la que viene.
           date_trunc('week', p_desde + case when extract(isodow from p_desde) >= 6 then 2 else 0 end)::date as lunes0,
           least(greatest(coalesce(p_semanas, 8), 1), 26) as n
  ),
  semanas as (
    select lim.lunes0 + 7 * i as semana from lim, generate_series(0, lim.n - 1) i
  ),
  dias as (
    select g.dia::date as dia, date_trunc('week', g.dia)::date as semana
    from lim, generate_series(lim.hoy, lim.lunes0 + lim.n * 7 - 1, interval '1 day') g(dia)
    where private.es_habil(g.dia::date)
  ),
  capacidad as (
    select d.semana, count(*) as habiles from dias d group by d.semana
  ),
  ve_todo as (
    select (select private.es_direccion())
        or (select private.tiene_rol('{arquitecto}'::public.rol_persona[]))
        or exists (select 1 from private.proyectos_que_dirige()) as si
  ),
  quien as (
    select p.id, p.nombre, coalesce(nullif(p.horas_semana, 0), 40) / 40.0 as jornada
    from public.persona p, ve_todo v
    where p.activo and p.es_interno
      and (p.id = (select private.persona_actual())
           or (v.si and (p.rol::text in ('director','arquitecto','practicante','director_proyecto')
                         or exists (select 1 from public.tarea_diseno t
                                    where t.asignada_a = p.id and t.estado <> 'terminada'))))
  ),
  trabajo as (
    select t.asignada_a, t.dias_estimados,
           coalesce(t.fecha_compromiso < lim.hoy, false) as vencida,
           case when t.fecha_compromiso < lim.hoy then lim.hoy
                else least(coalesce(t.fecha_inicio, (t.creada_en at time zone 'America/Bogota')::date),
                           coalesce(t.fecha_compromiso, lim.hoy)) end as desde,
           greatest(coalesce(t.fecha_compromiso, lim.hoy), lim.hoy) as hasta
    from public.tarea_diseno t, lim
    where t.estado in ('asignada','en_curso','con_observaciones')
  ),
  tramo as (
    select w.*, (select count(*) from generate_series(w.desde, w.hasta, interval '1 day') g(dia)
                 where private.es_habil(g.dia::date)) as n
    from trabajo w
  ),
  -- Un tramo sin un solo día hábil (se entrega un domingo) pasa al hábil siguiente.
  ajustado as (
    select x.asignada_a, x.dias_estimados, x.vencida, greatest(x.n, 1) as n,
           case when x.n = 0 then private.sumar_habiles(x.hasta, 1) else x.desde end as desde,
           case when x.n = 0 then private.sumar_habiles(x.hasta, 1) else x.hasta end as hasta
    from tramo x
  ),
  reparto as (
    select a.asignada_a, d.semana, sum(a.dias_estimados / a.n) as ocupados
    from ajustado a join dias d on d.dia between a.desde and a.hasta
    group by a.asignada_a, d.semana
  ),
  conteo as (
    select a.asignada_a, s.semana,
           count(*) as tareas,
           count(*) filter (where a.dias_estimados is null) as sin_estimar,
           count(*) filter (where a.vencida) as vencidas
    from ajustado a cross join lim
    join semanas s on a.desde <= s.semana + 4 and a.hasta >= greatest(s.semana, lim.hoy)
    group by a.asignada_a, s.semana
  )
  select q.id, q.nombre, s.semana,
         round(coalesce(c.habiles, 0) * q.jornada, 1),
         round(coalesce(r.ocupados, 0), 1),
         coalesce(k.tareas, 0)::integer,
         coalesce(k.sin_estimar, 0)::integer,
         coalesce(k.vencidas, 0)::integer
  from quien q
  cross join semanas s
  left join capacidad c on c.semana = s.semana
  left join reparto r on r.asignada_a = q.id and r.semana = s.semana
  left join conteo k on k.asignada_a = q.id and k.semana = s.semana
  order by q.nombre, s.semana
$$;

create or replace function public.carga_semanal(p_semanas integer default 8, p_desde date default null)
returns table (
  persona_id     uuid,
  nombre         text,
  semana         date,
  dias_habiles   numeric,
  dias_ocupados  numeric,
  tareas         integer,
  sin_estimar    integer,
  vencidas       integer)
language sql stable set search_path = '' as $$
  select c.persona_id, c.nombre, c.semana, c.dias_habiles, c.dias_ocupados, c.tareas, c.sin_estimar, c.vencidas
  from private.carga_semanal_de(coalesce(p_desde, private.hoy()), p_semanas) c
$$;

revoke all on all functions in schema public  from public, anon;
revoke all on all functions in schema private from public, anon;
-- La privada que se otorga revisa por dentro quién la llama.
grant execute on function
  public.carga_semanal(integer, date),
  private.carga_semanal_de(date, integer)
to authenticated;
grant execute on all functions in schema public to service_role;
grant execute on all functions in schema private to service_role;
