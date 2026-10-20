-- =============================================================================
-- SICI · Las tareas típicas de cada fase y el aviso de cierre (D19 · 16-10-2026)
--
--   · Cada tarea típica dice cuánto trabajo pide. Al abrir una fase, la
--     propuesta ya trae el título, para qué sirve, la fecha sugerida y el
--     trabajo: quien dirige solo escoge a quién se le entrega.
--   · crear_tareas() guarda también cuándo empieza cada tarea y cuánto trabajo
--     pide, para que la carga del equipo las cuente desde el primer día.
--   · v_fase_avance dice cuántas tareas tiene cada fase, cuántas están
--     terminadas y si ya terminó todo su trabajo.
--
-- No toca las migraciones anteriores. Idempotente.
-- =============================================================================

alter table public.plantilla_tarea add column if not exists dias_estimados numeric(4,1);
do $$ begin
  alter table public.plantilla_tarea add constraint plantilla_tarea_estimado_sano
    check (dias_estimados is null or dias_estimados between 0.1 and 120);
exception when duplicate_object then null; end $$;
comment on column public.plantilla_tarea.dias_estimados is
  'Días de trabajo que suele pedir esta tarea. Es lo que se propone al abrir la fase; quien dirige lo puede cambiar.';

-- La propuesta de siempre (proponer_tareas) más lo que suele pedir cada tarea.
-- Va en una función nueva: cambiarle la respuesta a la anterior rompería las
-- migraciones que ya están aplicadas.
create or replace function public.tareas_tipicas(p_fase uuid, p_espacios text[] default '{}'::text[])
returns table (
  plantilla_tarea_id uuid,
  orden              smallint,
  titulo             text,
  espacio            text,
  proposito          text,
  prioridad          public.prioridad_pendiente,
  fecha_sugerida     date,
  depende_de         uuid,
  dias_estimados     numeric,
  por_espacio        boolean)
language sql stable set search_path = '' as $$
  select t.plantilla_tarea_id, t.orden, t.titulo, t.espacio, t.proposito, t.prioridad, t.fecha_sugerida, t.depende_de,
         pt.dias_estimados, pt.por_espacio
  from public.proponer_tareas(p_fase, p_espacios) t
  join public.plantilla_tarea pt on pt.id = t.plantilla_tarea_id
  order by t.orden, t.espacio
$$;

-- D12 · Crea de una vez las tareas que quien dirige dejó en la pantalla.
-- p_tareas: [{"plantilla_tarea_id": "…", "titulo": "…", "espacio": "Cocina",
--             "asignada_a": "…", "fecha_inicio": "2026-10-19", "fecha_compromiso": "2026-10-23",
--             "dias_estimados": 2, "prioridad": "alta"}, …]
-- El título, la prioridad y el trabajo se toman de la plantilla si no vienen.
-- Las dependencias de la plantilla se enlazan solas, espacio por espacio.
create or replace function public.crear_tareas(p_fase uuid, p_tareas jsonb) returns integer
language plpgsql set search_path = '' as $$
declare
  v_proyecto uuid;
  v_yo       uuid := private.persona_actual();
  v_ids      uuid[] := '{}';
  v_id       uuid;
  v_titulo   text;
  v_pt       public.plantilla_tarea%rowtype;
  e          jsonb;
begin
  select f.proyecto_id into v_proyecto from public.proyecto_fase f where f.id = p_fase;
  if not found then
    raise exception 'D12 · Esa fase no existe o no la puede ver';
  end if;
  if p_tareas is null or jsonb_typeof(p_tareas) <> 'array' or jsonb_array_length(p_tareas) = 0 then
    raise exception 'D12 · No hay tareas para crear';
  end if;

  for e in select x from jsonb_array_elements(p_tareas) x loop
    v_pt := null;
    if nullif(e ->> 'plantilla_tarea_id', '') is not null then
      select * into v_pt from public.plantilla_tarea pt where pt.id = (e ->> 'plantilla_tarea_id')::uuid;
    end if;
    v_titulo := coalesce(nullif(trim(e ->> 'titulo'), ''),
                         v_pt.titulo || coalesce(' · ' || nullif(trim(e ->> 'espacio'), ''), ''));
    if v_titulo is null then
      raise exception 'D12 · Hay una tarea sin título';
    end if;
    if nullif(e ->> 'asignada_a', '') is null then
      raise exception 'D10 · «%» no tiene a quién se le asigna', v_titulo;
    end if;
    v_id := gen_random_uuid();
    insert into public.tarea_diseno
      (id, proyecto_id, fase_id, titulo, asignada_a, asignada_por, fecha_inicio, fecha_compromiso,
       dias_estimados, prioridad, plantilla_tarea_id, proposito, espacio)
    values
      (v_id, v_proyecto, p_fase, v_titulo, (e ->> 'asignada_a')::uuid, v_yo,
       nullif(e ->> 'fecha_inicio', '')::date,
       (e ->> 'fecha_compromiso')::date,
       coalesce(nullif(e ->> 'dias_estimados', '')::numeric, v_pt.dias_estimados),
       coalesce((e ->> 'prioridad')::public.prioridad_pendiente, v_pt.prioridad, 'normal'),
       v_pt.id, v_pt.proposito, nullif(trim(e ->> 'espacio'), ''));
    v_ids := v_ids || v_id;
  end loop;

  update public.tarea_diseno t
     set bloqueada_por = (
           select d.id
           from public.tarea_diseno d
           where d.fase_id = p_fase and d.plantilla_tarea_id = pt.depende_de and d.id <> t.id
             and (d.espacio is not distinct from t.espacio or d.espacio is null)
           order by (d.id = any (v_ids)) desc, d.creada_en desc
           limit 1)
    from public.plantilla_tarea pt
   where t.id = any (v_ids) and t.plantilla_tarea_id = pt.id and pt.depende_de is not null;

  return cardinality(v_ids);
end $$;

-- Una fase terminó su trabajo cuando tiene tareas y todas están terminadas.
-- No la cierra: el cierre sigue pidiendo lo que pide la compuerta (D1).
create or replace view public.v_fase_avance with (security_invoker = true) as
select
  f.id            as fase_id,
  f.proyecto_id,
  f.fase,
  f.estado,
  count(t.id)::integer                                        as tareas,
  (count(t.id) filter (where t.estado = 'terminada'))::integer as terminadas,
  f.estado in ('en_curso','en_revision')
    and count(t.id) > 0
    and count(t.id) = count(t.id) filter (where t.estado = 'terminada') as trabajo_terminado
from public.proyecto_fase f
left join public.tarea_diseno t on t.fase_id = f.id
group by f.id;

revoke all on public.v_fase_avance from anon, authenticated;
grant select on public.v_fase_avance to authenticated;
revoke all on all functions in schema public  from public, anon;
revoke all on all functions in schema private from public, anon;
grant execute on function
  public.tareas_tipicas(uuid, text[]),
  public.crear_tareas(uuid, jsonb)
to authenticated;
grant select, insert, update, delete on all tables in schema public to service_role;
grant execute on all functions in schema public to service_role;
grant execute on all functions in schema private to service_role;
