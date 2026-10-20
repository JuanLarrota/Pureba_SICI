-- =============================================================================
-- SICI · Módulo de arquitectura y diseño · etapa 2 · indicadores de impacto
--
--   D14 · Cinco indicadores por persona y dos para quien dirige. Ninguno cuenta
--         tareas: miden qué le pasó al proyecto. Cada uno se entrega como una
--         frase, y cada frase se puede abrir para ver de qué hechos sale.
--   D15 · Si un dato está mal, la persona lo señala y dirección lo resuelve.
--         Queda el rastro, y lo corregido deja de contar.
--
-- Como van a servir para evaluar (Felipe, 12-10-2026), todos salen de hechos
-- que registró otra persona o el sistema:
--   · solo cuentan las tareas que asignó otra persona; las que alguien se creó
--     a sí mismo no suman ni restan;
--   · la fecha de entrega la fija quien asignó (D10);
--   · la entrega es la hora en que se pidió la revisión, que pone el sistema;
--   · el resultado lo da quien revisa, nunca quien hizo la tarea.
--
-- Los pesos y las frases son el punto de partida acordado. Se calibran en la
-- etapa 7 con datos reales del piloto; por eso los pesos viven en "parametro"
-- y no en el código.
-- Idempotente.
-- =============================================================================

alter table public.parametro
  add column if not exists semanas_indicador           smallint not null default 4,
  add column if not exists minimo_revisadas_indicador  smallint not null default 5,
  add column if not exists peso_alta                   smallint not null default 2,
  add column if not exists peso_bloqueante             smallint not null default 3;
do $$ begin
  alter table public.parametro add constraint parametro_indicador_sano check (
    semanas_indicador between 1 and 26 and minimo_revisadas_indicador >= 1
    and peso_alta >= 1 and peso_bloqueante >= peso_alta);
exception when duplicate_object then null; end $$;


-- =============================================================================
-- 1. Solicitud de corrección (D15)
-- Aquí sí hay un campo de texto: es la excepción, y la escribe quien reclama.
-- =============================================================================

create table if not exists public.solicitud_correccion (
  id            uuid primary key default gen_random_uuid(),
  persona_id    uuid not null references public.persona(id),   -- de quién es el indicador
  indicador     text not null check (indicador in ('cumplio','primera','espera','hitos','margen')),
  tarea_id      uuid references public.tarea_diseno(id),
  fase_id       uuid references public.proyecto_fase(id),
  motivo        text not null,
  estado        text not null default 'abierta' check (estado in ('abierta','aceptada','rechazada')),
  excluir       boolean not null default false,   -- aceptada y con esto, el hecho deja de contar
  respuesta     text,
  resuelta_por  uuid references public.persona(id),
  resuelta_en   timestamptz,
  creada_en     timestamptz not null default now(),
  constraint solicitud_de_un_hecho check (num_nonnulls(tarea_id, fase_id) = 1),
  constraint solicitud_motivo_escrito check (length(trim(motivo)) >= 10),
  constraint solicitud_resuelta_completa check (
    (estado = 'abierta') = (resuelta_en is null) and (resuelta_en is null) = (resuelta_por is null)),
  constraint solicitud_con_respuesta check (estado = 'abierta' or length(trim(coalesce(respuesta, ''))) > 0),
  constraint solicitud_excluye_si_acepta check (not excluir or estado = 'aceptada')
);
create index if not exists solicitud_correccion_persona on public.solicitud_correccion (persona_id, indicador);
create index if not exists solicitud_correccion_tarea on public.solicitud_correccion (tarea_id);
create index if not exists solicitud_correccion_fase on public.solicitud_correccion (fase_id);
create index if not exists solicitud_correccion_resuelta_por on public.solicitud_correccion (resuelta_por);
create index if not exists solicitud_correccion_abiertas on public.solicitud_correccion (creada_en)
  where estado = 'abierta';

create or replace function private.validar_solicitud() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_yo uuid := private.persona_actual();
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null then
      new.persona_id := v_yo;
      new.estado := 'abierta';
      new.excluir := false;
      new.respuesta := null;
      new.resuelta_por := null;
      new.resuelta_en := null;
    end if;
    if new.tarea_id is not null and not exists (
         select 1 from public.tarea_diseno t where t.id = new.tarea_id and t.asignada_a = new.persona_id) then
      raise exception 'D15 · Solo se pide corregir un dato de una tarea propia';
    end if;
    if new.fase_id is not null and not exists (
         select 1 from public.dedicacion d where d.fase_id = new.fase_id and d.persona_id = new.persona_id) then
      raise exception 'D15 · Solo se pide corregir un dato de una fase en la que se trabajó';
    end if;
    return new;
  end if;

  if old.estado <> 'abierta' then
    raise exception 'D15 · Una solicitud resuelta no se cambia: queda como constancia';
  end if;
  if (to_jsonb(new) - '{estado,excluir,respuesta,resuelta_por,resuelta_en}'::text[])
       <> (to_jsonb(old) - '{estado,excluir,respuesta,resuelta_por,resuelta_en}'::text[]) then
    raise exception 'D15 · De una solicitud solo se registra su respuesta';
  end if;
  if new.estado <> 'abierta' then
    if auth.uid() is not null then
      if not private.es_direccion() then
        raise exception 'D15 · Las solicitudes de corrección las resuelve dirección';
      end if;
      new.resuelta_por := v_yo;
    end if;
    if new.resuelta_por = old.persona_id then
      raise exception 'D15 · Nadie resuelve la corrección de su propio indicador';
    end if;
    new.resuelta_en := now();
  end if;
  return new;
end $$;

drop trigger if exists tr_solicitud_correccion_validar on public.solicitud_correccion;
create trigger tr_solicitud_correccion_validar
  before insert or update on public.solicitud_correccion
  for each row execute function private.validar_solicitud();

drop trigger if exists tr_solicitud_correccion_auditar on public.solicitud_correccion;
create trigger tr_solicitud_correccion_auditar
  after insert or update or delete on public.solicitud_correccion
  for each row execute function private.auditar();

drop trigger if exists tr_solicitud_correccion_no_borrar on public.solicitud_correccion;
create trigger tr_solicitud_correccion_no_borrar
  before delete on public.solicitud_correccion
  for each row execute function private.prohibir_borrado();


-- =============================================================================
-- 2. Los hechos
-- Una fila por tarea y una por fase, con lo que pasó dentro de la ventana. Los
-- indicadores y su detalle salen de aquí: lo que dice la frase y lo que se ve
-- al abrirla no pueden contradecirse porque son la misma consulta.
-- Leen sin permisos por fila porque necesitan las horas de toda la fase; quién
-- puede pedirlas lo controla indicadores_de().
-- =============================================================================

create or replace function private.hechos_tarea(p_persona uuid, p_desde date, p_hasta date)
returns table (
  tarea_id          uuid,
  proyecto          text,
  titulo            text,
  estado            public.estado_tarea,
  peso              integer,
  fecha_compromiso  date,
  entregada_el      date,
  terminada_el      date,
  debia             boolean,   -- se entregaba dentro de la ventana
  a_tiempo          boolean,
  cerrada           boolean,   -- se terminó dentro de la ventana
  devoluciones      integer,
  revisada          boolean,   -- tuvo alguna revisión dentro de la ventana
  frenaba           boolean,   -- otra persona dependía de ella
  dias_espera       integer,   -- días hábiles que otros esperaron por ella, vencida
  quien_espero      text,
  excluida_de       text[])
language sql stable security definer set search_path = '' as $$
  with par as (
    select p.peso_alta, p.peso_bloqueante from public.parametro p where p.id
  ),
  t as (
    select t.id, t.titulo, t.estado, t.prioridad, t.fecha_compromiso, pr.nombre as proyecto,
           (coalesce(t.revision_pedida_en, t.terminada_en) at time zone 'America/Bogota')::date as entregada_el,
           (t.terminada_en at time zone 'America/Bogota')::date                               as terminada_el
    from public.tarea_diseno t
    join public.proyecto pr on pr.id = t.proyecto_id
    where t.asignada_a = p_persona and t.asignada_por <> t.asignada_a
  ),
  dep as (
    select t.id,
           sum(x.dias)::integer                                                as dias,
           string_agg(dp.nombre, ', ' order by dp.nombre) filter (where x.dias > 0) as quien
    from t
    join lateral (
      select distinct d.asignada_a
      from public.tarea_diseno d
      where d.bloqueada_por = t.id and d.asignada_a <> p_persona
    ) e on true
    join public.persona dp on dp.id = e.asignada_a
    cross join lateral (
      select case when t.fecha_compromiso is null then 0
                  else greatest(private.dias_habiles(
                         greatest(t.fecha_compromiso, p_desde - 1),
                         least(coalesce(t.terminada_el, p_hasta), p_hasta)), 0) end as dias
    ) x
    group by t.id
  ),
  rev as (
    select r.tarea_id,
           count(*) filter (where r.resultado = 'con_observaciones')::integer as devoluciones,
           bool_or((r.revisada_en at time zone 'America/Bogota')::date between p_desde and p_hasta) as en_ventana
    from public.revision_diseno r
    where r.tarea_id in (select t.id from t)
    group by r.tarea_id
  )
  select t.id, t.proyecto, t.titulo, t.estado,
         (case t.prioridad when 'bloqueante' then par.peso_bloqueante
                           when 'alta' then par.peso_alta else 1 end)::integer,
         t.fecha_compromiso, t.entregada_el, t.terminada_el,
         -- La que vence hoy y sigue abierta todavía no cuenta: el día no ha terminado.
         coalesce(t.fecha_compromiso between p_desde and p_hasta
                  and (t.fecha_compromiso < p_hasta or t.estado in ('en_revision','terminada')), false),
         coalesce(t.estado in ('en_revision','terminada') and t.entregada_el <= t.fecha_compromiso, false),
         coalesce(t.estado = 'terminada' and t.terminada_el between p_desde and p_hasta, false),
         coalesce(rev.devoluciones, 0),
         coalesce(rev.en_ventana, false),
         (t.prioridad = 'bloqueante' or dep.id is not null),
         coalesce(dep.dias, 0),
         dep.quien,
         coalesce((select array_agg(distinct s.indicador)
                     from public.solicitud_correccion s
                    where s.tarea_id = t.id and s.persona_id = p_persona
                      and s.estado = 'aceptada' and s.excluir), '{}'::text[])
  from t
  cross join par
  left join dep on dep.id = t.id
  left join rev on rev.tarea_id = t.id
  where coalesce(t.fecha_compromiso between p_desde and p_hasta, false)
     or coalesce(t.estado = 'terminada' and t.terminada_el between p_desde and p_hasta, false)
     or coalesce(dep.dias, 0) > 0
     or coalesce(rev.en_ventana, false)
$$;

create or replace function private.hechos_fase(p_persona uuid, p_desde date, p_hasta date)
returns table (
  fase_id            uuid,
  proyecto           text,
  fase               text,
  horas_persona      numeric,
  horas_fase         numeric,
  horas_cotizadas    numeric,
  cerrada_el         date,
  cerro_en_ventana   boolean,
  dias_tarde         integer,   -- vacío si la fase no tenía fecha de compromiso
  aprobada_cliente   boolean,
  trabajo_en_ventana boolean,
  excluida_de        text[])
language sql stable security definer set search_path = '' as $$
  select f.id, p.nombre, replace(f.fase::text, '_', ' '),
         sum(d.horas) filter (where d.persona_id = p_persona),
         sum(d.horas),
         f.horas_cotizadas,
         c.cerrada_el,
         coalesce(f.estado = 'cerrada' and c.cerrada_el between p_desde and p_hasta, false),
         case when f.estado = 'cerrada' and f.fecha_compromiso is not null
              then greatest(c.cerrada_el - f.fecha_compromiso, 0) end,
         f.aprobada_cliente_en is not null,
         coalesce(bool_or(d.persona_id = p_persona and d.fecha between p_desde and p_hasta), false),
         coalesce((select array_agg(distinct s.indicador)
                     from public.solicitud_correccion s
                    where s.fase_id = f.id and s.persona_id = p_persona
                      and s.estado = 'aceptada' and s.excluir), '{}'::text[])
  from public.proyecto_fase f
  join public.proyecto p   on p.id = f.proyecto_id
  join public.dedicacion d on d.fase_id = f.id and d.fecha <= p_hasta
  cross join lateral (select (f.cerrada_en at time zone 'America/Bogota')::date as cerrada_el) c
  group by f.id, p.nombre, c.cerrada_el
  having coalesce(sum(d.horas) filter (where d.persona_id = p_persona), 0) > 0
$$;

-- Lo que revisó la persona dentro de la ventana y cuánto esperó cada entrega.
create or replace function private.hechos_revision(p_persona uuid, p_desde date, p_hasta date)
returns table (tarea_id uuid, proyecto text, titulo text, de_quien text, revisada_el date, dias_espera integer)
language sql stable security definer set search_path = '' as $$
  select t.id, pr.nombre, t.titulo, a.nombre,
         (r.revisada_en at time zone 'America/Bogota')::date,
         private.dias_habiles(
           (coalesce(e.pedida_en, t.creada_en) at time zone 'America/Bogota')::date,
           (r.revisada_en at time zone 'America/Bogota')::date)
  from public.revision_diseno r
  join public.tarea_diseno t on t.id = r.tarea_id
  join public.proyecto pr    on pr.id = t.proyecto_id
  join public.persona a      on a.id = t.asignada_a
  left join lateral (
    select max(ev.ocurrio_en) as pedida_en
    from public.tarea_evento ev
    where ev.tarea_id = t.id and ev.tipo = 'estado' and ev.a = 'en_revision' and ev.ocurrio_en <= r.revisada_en
  ) e on true
  where r.revisor_id = p_persona
    and (r.revisada_en at time zone 'America/Bogota')::date between p_desde and p_hasta
$$;


-- =============================================================================
-- 3. Los indicadores (D14)
-- =============================================================================

-- p_tu: si la frase le habla a la persona («Entregaste») o habla de ella
-- («Mariana entregó»). Sin valor, se deduce de quién tiene la sesión; el
-- mensaje semanal lo fija porque lo arma el servidor, sin sesión.
create or replace function private.indicadores_de(p_persona uuid, p_hasta date, p_tu boolean default null)
returns table (
  orden        smallint,
  indicador    text,
  titulo       text,
  numerador    numeric,
  denominador  numeric,
  suficiente   boolean,
  frase        text)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_par      public.parametro%rowtype;
  v_desde    date;
  v_tu       boolean;      -- la frase le habla a la persona, o habla de ella
  v_nombre   text;
  v_rol      public.rol_persona;
  v_revis    integer;
  v_basta    boolean;
  v_falta    text;
  v_plazo    text;
  r          record;
  f          record;
begin
  if auth.uid() is not null and p_persona is distinct from private.persona_actual()
     and not private.es_direccion() then
    raise exception 'D14 · Cada persona ve sus indicadores; los de los demás solo los ve dirección';
  end if;
  select * into v_par from public.parametro p where p.id;
  select split_part(p.nombre, ' ', 1), p.rol into v_nombre, v_rol from public.persona p where p.id = p_persona;
  if not found then
    raise exception 'D14 · Esa persona no existe';
  end if;
  v_desde := p_hasta - v_par.semanas_indicador * 7 + 1;
  v_tu := coalesce(p_tu, auth.uid() is not null and p_persona = private.persona_actual());
  v_plazo := case when v_par.semanas_indicador = 4 then 'estas cuatro semanas'
                  else 'las últimas ' || v_par.semanas_indicador || ' semanas' end;

  -- Con pocos datos una frase miente: sin el mínimo de tareas revisadas, no se dice nada.
  select count(*) into v_revis from private.hechos_tarea(p_persona, v_desde, p_hasta) h where h.revisada;
  v_basta := v_revis >= v_par.minimo_revisadas_indicador;
  v_falta := 'Todavía no hay con qué decirlo con justicia: '
             || case when v_revis = 1 then 'va una tarea revisada' else 'van ' || v_revis || ' tareas revisadas' end
             || ' de las ' || v_par.minimo_revisadas_indicador || ' que hacen falta en ' || v_plazo;

  if not v_basta then
    -- Una sola frase, no cinco iguales. Y a quien dirige y no produce, ninguna.
    if v_revis > 0 or v_rol not in ('socio','director') then
      return query select 0::smallint, 'sin_datos', 'Todavía no se puede decir',
                          null::numeric, null::numeric, false, v_falta;
    end if;
  else

  -- 1 · Cumplió lo que pesaba
  select count(*) as total,
         count(*) filter (where h.a_tiempo) as a_tiempo,
         count(*) filter (where h.frenaba) as criticas,
         count(*) filter (where h.frenaba and h.a_tiempo) as criticas_a_tiempo,
         coalesce(sum(h.peso) filter (where h.a_tiempo), 0) as peso_a_tiempo,
         coalesce(sum(h.peso), 0) as peso_total
    into r
  from private.hechos_tarea(p_persona, v_desde, p_hasta) h
  where h.debia and not ('cumplio' = any (h.excluida_de));
  return query select 1::smallint, 'cumplio', 'Cumplió lo que pesaba',
    case when v_basta then r.peso_a_tiempo::numeric end,
    case when v_basta then r.peso_total::numeric end,
    v_basta,
    case
      when r.total = 0 then case when v_tu then 'No tenías' else v_nombre || ' no tenía' end || ' entregas en ' || v_plazo
      else case when v_tu then 'Entregaste' else v_nombre || ' entregó' end
           || ' a tiempo ' || r.a_tiempo || ' de ' || r.total
           || case
                when r.criticas = 0 then ''
                when r.criticas_a_tiempo = r.criticas then
                  case when r.criticas = 1 then ', incluida la que frenaba a otros'
                       else ', incluidas las ' || r.criticas || ' que frenaban a otros' end
                when r.criticas = 1 then ', y la que frenaba a otros llegó tarde'
                else ', y de las ' || r.criticas || ' que frenaban a otros '
                     || case when r.criticas - r.criticas_a_tiempo = 1 then 'una llegó tarde'
                             else (r.criticas - r.criticas_a_tiempo) || ' llegaron tarde' end
              end
    end;

  -- 2 · Bien a la primera
  select count(*) as total, count(*) filter (where h.devoluciones = 0) as primera into r
  from private.hechos_tarea(p_persona, v_desde, p_hasta) h
  where h.cerrada and not ('primera' = any (h.excluida_de));
  return query select 2::smallint, 'primera', 'Bien a la primera',
    case when v_basta then r.primera::numeric end,
    case when v_basta then r.total::numeric end,
    v_basta,
    case
      when r.total = 0 then 'Ninguna tarea ' || case when v_tu then 'tuya' else 'de ' || v_nombre end
                            || ' se terminó en ' || v_plazo
      when r.primera = r.total then
        case when r.total = 1 then 'La única que se terminó pasó la revisión sin correcciones'
             else 'Las ' || r.total || ' que se terminaron pasaron la revisión sin correcciones' end
      else r.primera || ' de ' || r.total || case when r.primera = 1 then ' pasó' else ' pasaron' end
           || ' la revisión sin correcciones'
    end;

  -- 3 · Nadie esperó por ti
  select coalesce(sum(h.dias_espera), 0)::integer as dias, count(*) filter (where h.dias_espera > 0) as casos into r
  from private.hechos_tarea(p_persona, v_desde, p_hasta) h
  where not ('espera' = any (h.excluida_de));
  select h.quien_espero, h.dias_espera, h.titulo into f
  from private.hechos_tarea(p_persona, v_desde, p_hasta) h
  where h.dias_espera > 0 and not ('espera' = any (h.excluida_de))
  order by h.dias_espera desc, h.titulo
  limit 1;
  return query select 3::smallint, 'espera', 'Nadie esperó por ti',
    case when v_basta then r.dias::numeric end,
    null::numeric,
    v_basta,
    case
      when r.dias = 0 then 'Nadie esperó por ' || case when v_tu then 'ti' else v_nombre end || ' en ' || v_plazo
      else f.quien_espero || case when position(',' in f.quien_espero) > 0 then ' esperaron ' else ' esperó ' end
           || private.en_dias(f.dias_espera) || ' por «' || f.titulo || '»'
           || case when r.casos > 1 then ' · en total, ' || private.en_dias(r.dias) || ' de espera en ' || r.casos || ' tareas'
                   else '' end
    end;

  -- 4 · Aporte a los hitos
  select count(*) as fases into r
  from private.hechos_fase(p_persona, v_desde, p_hasta) h
  where h.cerro_en_ventana and not ('hitos' = any (h.excluida_de));
  select h.* into f
  from private.hechos_fase(p_persona, v_desde, p_hasta) h
  where h.cerro_en_ventana and not ('hitos' = any (h.excluida_de))
  order by h.horas_persona / nullif(h.horas_fase, 0) desc nulls last, h.proyecto
  limit 1;
  return query select 4::smallint, 'hitos', 'Aporte a los hitos',
    case when v_basta and r.fases > 0 then f.horas_persona end,
    case when v_basta and r.fases > 0 then f.horas_fase end,
    v_basta and r.fases > 0,
    case
      when r.fases = 0 then 'Ninguna fase en la que ' || case when v_tu then 'trabajaste' else 'trabajó ' || v_nombre end
                            || ' se cerró en ' || v_plazo
      else case when v_tu then 'Pusiste ' else v_nombre || ' puso ' end
           || case when f.horas_persona >= f.horas_fase then 'todas las horas'
                   when f.horas_persona * 2 > f.horas_fase then 'más de la mitad de las horas'
                   when f.horas_persona * 4 >= f.horas_fase then 'más de una cuarta parte de las horas'
                   else round(f.horas_persona) || ' de las ' || round(f.horas_fase) || ' horas' end
           || ' de ' || f.fase || ' de ' || f.proyecto || ', que se cerró'
           || case when f.dias_tarde is null then ''
                   when f.dias_tarde = 0 then ' a tiempo'
                   else ' ' || private.en_dias(f.dias_tarde, false) || ' tarde' end
           || case when f.aprobada_cliente then ' y con la aprobación del cliente' else '' end
    end;

  -- 5 · Cuidó el margen
  select count(*) as fases, coalesce(sum(h.horas_fase), 0) as reales, coalesce(sum(h.horas_cotizadas), 0) as cotizadas into r
  from private.hechos_fase(p_persona, v_desde, p_hasta) h
  where h.trabajo_en_ventana and not ('margen' = any (h.excluida_de));
  select h.* into f
  from private.hechos_fase(p_persona, v_desde, p_hasta) h
  where h.trabajo_en_ventana and not ('margen' = any (h.excluida_de))
  order by h.horas_persona desc, h.proyecto
  limit 1;
  return query select 5::smallint, 'margen', 'Cuidó el margen',
    case when v_basta and r.fases > 0 then r.reales end,
    case when v_basta and r.fases > 0 then r.cotizadas end,
    v_basta and r.fases > 0,
    case
      when r.fases = 0 then case when v_tu then 'No registraste' else v_nombre || ' no registró' end
                            || ' horas en ninguna fase en ' || v_plazo
      when f.horas_cotizadas = 0 then initcap(left(f.fase, 1)) || substr(f.fase, 2) || ' de ' || f.proyecto
                            || ' no tiene horas cotizadas: no hay contra qué comparar'
      else initcap(left(f.fase, 1)) || substr(f.fase, 2) || ' de ' || f.proyecto || ' lleva '
           || round(f.horas_fase) || ' de ' || round(f.horas_cotizadas) || ' horas cotizadas; '
           || round(f.horas_persona) || case when v_tu then ' son tuyas' else ' son de ' || v_nombre end
    end;

  end if;

  -- Los de quien dirige o revisa: cuánto esperan las revisiones y qué asignó sin fecha.
  if v_rol in ('socio','director')
     or exists (select 1 from public.acceso_proyecto a where a.persona_id = p_persona and a.papel in ('dirige','revisa'))
     or exists (select 1 from private.hechos_revision(p_persona, v_desde, p_hasta)) then
    select count(*) as total,
           count(*) filter (where h.dias_espera > v_par.dias_habiles_revision) as tarde,
           round(avg(h.dias_espera), 1) as promedio
      into r
    from private.hechos_revision(p_persona, v_desde, p_hasta) h;
    return query select 6::smallint, 'revisiones', 'Las revisiones no esperan',
      (r.total - r.tarde)::numeric, r.total::numeric, r.total > 0,
      case
        when r.total = 0 then case when v_tu then 'No revisaste' else v_nombre || ' no revisó' end
                              || ' ninguna entrega en ' || v_plazo
        else case when v_tu then 'Revisaste ' else v_nombre || ' revisó ' end
             || case when r.total = 1 then 'una entrega' else r.total || ' entregas' end
             || case when r.tarde = 0 then ', todas dentro del plazo de ' || private.en_dias(v_par.dias_habiles_revision)
                     when r.tarde = 1 then '; una esperó más de ' || private.en_dias(v_par.dias_habiles_revision)
                     else '; ' || r.tarde || ' esperaron más de ' || private.en_dias(v_par.dias_habiles_revision) end
      end;

    select count(*) as sin_fecha into r
    from public.tarea_diseno t
    where t.asignada_por = p_persona and t.estado <> 'terminada' and t.fecha_compromiso is null;
    return query select 7::smallint, 'sin_fecha', 'Todo lo asignado tiene fecha',
      r.sin_fecha::numeric, null::numeric, true,
      case
        when r.sin_fecha = 0 then 'Todo lo que ' || case when v_tu then 'asignaste' else 'asignó ' || v_nombre end
                                  || ' tiene fecha de entrega'
        when r.sin_fecha = 1 then case when v_tu then 'Asignaste' else v_nombre || ' asignó' end
                                  || ' una tarea que sigue sin fecha de entrega'
        else case when v_tu then 'Asignaste ' else v_nombre || ' asignó ' end
             || r.sin_fecha || ' tareas que siguen sin fecha de entrega'
      end;
  end if;
end $$;

-- Lo que se ve al abrir una frase: los hechos de los que sale, uno por fila.
create or replace function private.detalle_de(p_indicador text, p_persona uuid, p_hasta date)
returns table (
  tarea_id   uuid,
  fase_id    uuid,
  proyecto   text,
  titulo     text,
  hecho      text,
  a_favor    boolean,
  excluida   boolean)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_par   public.parametro%rowtype;
  v_desde date;
begin
  if auth.uid() is not null and p_persona is distinct from private.persona_actual()
     and not private.es_direccion() then
    raise exception 'D14 · Cada persona ve sus indicadores; los de los demás solo los ve dirección';
  end if;
  select * into v_par from public.parametro p where p.id;
  v_desde := p_hasta - v_par.semanas_indicador * 7 + 1;

  if p_indicador = 'cumplio' then
    return query
    select h.tarea_id, null::uuid, h.proyecto, h.titulo,
           'Se entregaba el ' || to_char(h.fecha_compromiso, 'DD/MM') || ' · '
           || case when h.a_tiempo then 'pidió revisión el ' || to_char(h.entregada_el, 'DD/MM')
                   when h.estado in ('en_revision','terminada')
                     then 'pidió revisión el ' || to_char(h.entregada_el, 'DD/MM') || ', '
                          || private.en_dias(h.entregada_el - h.fecha_compromiso, false) || ' después'
                   else 'sigue abierta' end
           || case when h.frenaba then ' · otra persona dependía de ella' else '' end,
           h.a_tiempo, 'cumplio' = any (h.excluida_de)
    from private.hechos_tarea(p_persona, v_desde, p_hasta) h
    where h.debia
    order by h.fecha_compromiso, h.titulo;
  elsif p_indicador = 'primera' then
    return query
    select h.tarea_id, null::uuid, h.proyecto, h.titulo,
           case when h.devoluciones = 0 then 'Aprobada en la primera revisión'
                when h.devoluciones = 1 then 'Se devolvió una vez antes de aprobarse'
                else 'Se devolvió ' || h.devoluciones || ' veces antes de aprobarse' end,
           h.devoluciones = 0, 'primera' = any (h.excluida_de)
    from private.hechos_tarea(p_persona, v_desde, p_hasta) h
    where h.cerrada
    order by h.terminada_el, h.titulo;
  elsif p_indicador = 'espera' then
    return query
    select h.tarea_id, null::uuid, h.proyecto, h.titulo,
           h.quien_espero || case when position(',' in h.quien_espero) > 0 then ' esperaron ' else ' esperó ' end
           || private.en_dias(h.dias_espera) || ' · se entregaba el ' || to_char(h.fecha_compromiso, 'DD/MM')
           || coalesce(' y se terminó el ' || to_char(h.terminada_el, 'DD/MM'), ' y sigue abierta'),
           false, 'espera' = any (h.excluida_de)
    from private.hechos_tarea(p_persona, v_desde, p_hasta) h
    where h.dias_espera > 0
    order by h.dias_espera desc, h.titulo;
  elsif p_indicador = 'hitos' then
    return query
    select null::uuid, h.fase_id, h.proyecto, initcap(left(h.fase, 1)) || substr(h.fase, 2),
           round(h.horas_persona) || ' de ' || round(h.horas_fase) || ' horas · se cerró el ' || to_char(h.cerrada_el, 'DD/MM')
           || case when h.dias_tarde is null then '' when h.dias_tarde = 0 then ', a tiempo'
                   else ', ' || private.en_dias(h.dias_tarde, false) || ' tarde' end
           || case when h.aprobada_cliente then ' · aprobada por el cliente' else '' end,
           coalesce(h.dias_tarde, 0) = 0, 'hitos' = any (h.excluida_de)
    from private.hechos_fase(p_persona, v_desde, p_hasta) h
    where h.cerro_en_ventana
    order by h.cerrada_el, h.proyecto;
  elsif p_indicador = 'margen' then
    return query
    select null::uuid, h.fase_id, h.proyecto, initcap(left(h.fase, 1)) || substr(h.fase, 2),
           round(h.horas_fase) || ' horas de ' || round(h.horas_cotizadas) || ' cotizadas · '
           || round(h.horas_persona) || ' de esta persona',
           h.horas_cotizadas = 0 or h.horas_fase <= h.horas_cotizadas, 'margen' = any (h.excluida_de)
    from private.hechos_fase(p_persona, v_desde, p_hasta) h
    where h.trabajo_en_ventana
    order by h.horas_persona desc, h.proyecto;
  elsif p_indicador = 'revisiones' then
    return query
    select h.tarea_id, null::uuid, h.proyecto, h.titulo,
           'De ' || h.de_quien || ' · revisada el ' || to_char(h.revisada_el, 'DD/MM') || ' · '
           || case when h.dias_espera = 0 then 'el mismo día' else 'esperó ' || private.en_dias(h.dias_espera) end,
           h.dias_espera <= v_par.dias_habiles_revision, false
    from private.hechos_revision(p_persona, v_desde, p_hasta) h
    order by h.revisada_el, h.titulo;
  else
    raise exception 'D14 · No existe el indicador «%»', p_indicador;
  end if;
end $$;

-- Las dos puertas de la aplicación. Sin persona: los de quien tiene la sesión.
create or replace function public.indicadores(p_persona uuid default null, p_hasta date default null)
returns table (
  orden        smallint,
  indicador    text,
  titulo       text,
  numerador    numeric,
  denominador  numeric,
  suficiente   boolean,
  frase        text)
language sql stable set search_path = '' as $$
  select i.orden, i.indicador, i.titulo, i.numerador, i.denominador, i.suficiente, i.frase
  from private.indicadores_de(coalesce(p_persona, private.persona_actual()), coalesce(p_hasta, private.hoy())) i
  order by i.orden
$$;

create or replace function public.indicador_detalle(p_indicador text, p_persona uuid default null, p_hasta date default null)
returns table (
  tarea_id   uuid,
  fase_id    uuid,
  proyecto   text,
  titulo     text,
  hecho      text,
  a_favor    boolean,
  excluida   boolean)
language sql stable set search_path = '' as $$
  select d.tarea_id, d.fase_id, d.proyecto, d.titulo, d.hecho, d.a_favor, d.excluida
  from private.detalle_de(p_indicador, coalesce(p_persona, private.persona_actual()), coalesce(p_hasta, private.hoy())) d
$$;


-- =============================================================================
-- 4. Permisos
-- =============================================================================

alter table public.solicitud_correccion enable row level security;

drop policy if exists solicitud_correccion_lectura on public.solicitud_correccion;
create policy solicitud_correccion_lectura on public.solicitud_correccion for select to authenticated
  using (persona_id = (select private.persona_actual()) or (select private.es_direccion()));

drop policy if exists solicitud_correccion_alta on public.solicitud_correccion;
create policy solicitud_correccion_alta on public.solicitud_correccion for insert to authenticated
  with check ((select private.es_interno()) and persona_id = (select private.persona_actual()));

drop policy if exists solicitud_correccion_edicion on public.solicitud_correccion;
create policy solicitud_correccion_edicion on public.solicitud_correccion for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

revoke all on public.solicitud_correccion from anon, authenticated;
revoke all on all functions in schema public  from public, anon;
revoke all on all functions in schema private from public, anon;
revoke all on function
  private.validar_solicitud(),
  private.hechos_tarea(uuid, date, date),
  private.hechos_fase(uuid, date, date),
  private.hechos_revision(uuid, date, date)
from authenticated;

grant select, insert, update on public.solicitud_correccion to authenticated;

-- Las dos privadas que se otorgan revisan por dentro quién las llama.
grant execute on function
  public.indicadores(uuid, date),
  public.indicador_detalle(text, uuid, date),
  private.indicadores_de(uuid, date, boolean),
  private.detalle_de(text, uuid, date)
to authenticated;

grant select, insert, update, delete on all tables in schema public to service_role;
grant execute on all functions in schema public to service_role;
grant execute on all functions in schema private to service_role;
