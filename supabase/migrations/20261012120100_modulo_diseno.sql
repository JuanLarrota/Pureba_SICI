-- =============================================================================
-- SICI · Módulo de arquitectura y diseño · etapa 2 · 2 de 2
-- Equipo con papel, plantillas, flujo de revisión y «Mi día»
--
-- Lo que este archivo convierte en regla de la base, y de dónde sale cada una
-- (documento de requerimientos cerrado el 12 de octubre de 2026):
--
--   D10 · Equipo con papel. Quien no tiene papel en el proyecto no lo ve ni
--         recibe tareas de él. La fecha, la prioridad y el responsable de una
--         tarea los cambia quien la asignó o quien dirige, no quien la hace:
--         los indicadores van a evaluar a la persona y no pueden depender de
--         lo que ella diga de sí misma.
--   D11 · Flujo de revisión. Solo se revisa lo que pidió revisión; aprobar
--         termina la tarea y devolver exige una observación. Cada cambio de
--         estado guarda quién y cuándo, y ese rastro no se edita ni se borra.
--   D12 · Plantillas. El proyecto nace con las fases de su tipo y cada fase
--         propone sus tareas típicas con su propósito escrito.
--   D13 · Variantes de lista de chequeo según tamaño y alcance del proyecto.
--   Además: el rol de director de proyectos de construcción y la profesión de
--   cada persona, que se escoge de una lista.
--
-- No toca las once migraciones del 14 de septiembre: reemplaza funciones con
-- "create or replace" y agrega columnas. No borra ni reescribe ningún dato.
-- Idempotente.
-- =============================================================================


-- =============================================================================
-- 1. Tipos y parámetros
-- =============================================================================

-- 'observa' es quien ve el proyecto sin hacer parte del equipo que produce: el
-- cliente desde el portal, o alguien interno que solo necesita consultarlo.
do $$ begin
  create type public.papel_proyecto as enum ('dirige','produce','revisa','observa');
exception when duplicate_object then null; end $$;

-- Plazo acordado para una revisión: dos días hábiles (Luisa, 12-10-2026).
alter table public.parametro
  add column if not exists dias_habiles_revision smallint not null default 2;
do $$ begin
  alter table public.parametro
    add constraint parametro_revision_positiva check (dias_habiles_revision > 0);
exception when duplicate_object then null; end $$;


-- La profesión se escoge de una lista que dirección puede ampliar. El rol dice
-- qué hace la persona en ESA; la profesión, qué es. Un director de proyectos
-- de construcción puede ser ingeniero civil hoy y arquitecto mañana.
create table if not exists public.profesion (
  id      uuid primary key default gen_random_uuid(),
  nombre  text not null unique,
  activa  boolean not null default true,
  constraint profesion_nombre_escrito check (length(trim(nombre)) > 0)
);
alter table public.persona
  add column if not exists profesion_id uuid references public.profesion(id);
create index if not exists persona_profesion on public.persona (profesion_id);


-- =============================================================================
-- 2. Días hábiles
-- Un plazo en días hábiles no puede contar el lunes festivo. La dedicación
-- tampoco: sin esta tabla, el cierre de una fase reclamaría el registro de un
-- día que nadie trabajó.
-- =============================================================================

create table if not exists public.festivo (
  fecha   date primary key,
  nombre  text not null,
  constraint festivo_nombre_escrito check (length(trim(nombre)) > 0)
);
comment on table public.festivo is
  'Festivos de Colombia. Se cargan desde supabase/semilla/040_plantillas.sql; hay que cargar cada año nuevo antes de que empiece.';

create or replace function private.es_habil(p_fecha date) returns boolean
language sql stable security definer set search_path = '' as $$
  select extract(isodow from p_fecha) < 6
     and not exists (select 1 from public.festivo f where f.fecha = p_fecha)
$$;

-- Días hábiles transcurridos después de p_desde y hasta p_hasta, inclusive.
-- Pedida un viernes y mirada el lunes siguiente: un día hábil.
create or replace function private.dias_habiles(p_desde date, p_hasta date) returns integer
language sql stable security definer set search_path = '' as $$
  select count(*)::integer
  from generate_series(p_desde + 1, p_hasta, interval '1 day') g(dia)
  where extract(isodow from g.dia) < 6
    and not exists (select 1 from public.festivo f where f.fecha = g.dia::date)
$$;

-- "3 días hábiles", "un día hábil".
create or replace function private.en_dias(p_n integer, p_habiles boolean default true) returns text
language sql immutable set search_path = '' as $$
  select case when p_n = 1 then 'un día' else p_n || ' días' end
         || case when p_habiles then case when p_n = 1 then ' hábil' else ' hábiles' end else '' end
$$;

-- La fecha que queda p_dias días hábiles después de p_desde.
create or replace function private.sumar_habiles(p_desde date, p_dias integer) returns date
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select x.dia
    from (
      select g.dia::date as dia, row_number() over (order by g.dia) as n
      from generate_series(p_desde + 1, p_desde + greatest(p_dias, 0) * 2 + 15, interval '1 day') g(dia)
      where extract(isodow from g.dia) < 6
        and not exists (select 1 from public.festivo f where f.fecha = g.dia::date)
    ) x
    where x.n = p_dias), p_desde)
$$;

-- D2 · Igual que antes, sin contar los festivos.
create or replace function private.dias_sin_dedicacion(p_persona uuid, p_desde date, p_hasta date)
returns integer
language sql stable security definer set search_path = '' as $$
  select count(*)::integer
  from generate_series(p_desde, p_hasta, interval '1 day') g(dia)
  join public.persona p on p.id = p_persona
  where extract(isodow from g.dia) < 6
    and not exists (select 1 from public.festivo f where f.fecha = g.dia::date)
    and g.dia::date >= (p.creado_en at time zone 'America/Bogota')::date
    and not exists (
      select 1 from public.dedicacion d
      where d.persona_id = p_persona and d.fecha = g.dia::date)
$$;


-- =============================================================================
-- 3. Plantillas de proyecto, de fase y de tarea (D12) y variantes de lista (D13)
-- =============================================================================

-- D13 · Las listas de chequeo cambian con el tamaño y el alcance del proyecto.
-- La variante se escoge al abrir el proyecto y cada fase toma la lista que le
-- corresponde.
create table if not exists public.variante_chequeo (
  id           uuid primary key default gen_random_uuid(),
  nombre       text not null unique,
  descripcion  text,
  activa       boolean not null default true,
  creada_en    timestamptz not null default now(),
  constraint variante_nombre_escrito check (length(trim(nombre)) > 0)
);

alter table public.lista_chequeo
  add column if not exists variante_id uuid references public.variante_chequeo(id);
create index if not exists lista_chequeo_variante on public.lista_chequeo (variante_id);
comment on column public.lista_chequeo.variante_id is
  'Vacío: la lista sirve para cualquier variante. Con valor: solo para los proyectos de esa variante.';

-- D12 · Una plantilla por manera de recorrer el trabajo. El tipo de proyecto lo
-- pone la plantilla; la unidad de negocio se escoge aparte.
create table if not exists public.plantilla_proyecto (
  id           uuid primary key default gen_random_uuid(),
  nombre       text not null unique,
  tipo         public.tipo_proyecto not null,
  descripcion  text,
  activa       boolean not null default true,
  creada_en    timestamptz not null default now(),
  constraint plantilla_nombre_escrito check (length(trim(nombre)) > 0)
);

create table if not exists public.plantilla_fase (
  id                        uuid primary key default gen_random_uuid(),
  plantilla_id              uuid not null references public.plantilla_proyecto(id),
  fase                      public.fase_proyecto not null,
  orden                     smallint not null,
  entrega_cliente           text,                 -- qué recibe el cliente al cerrarla
  opcional                  boolean not null default false,   -- "licencia, si aplica"
  exige_chequeo             boolean not null default true,
  exige_aprobacion_cliente  boolean not null default false,
  exige_dedicacion          boolean not null default true,
  unique (plantilla_id, fase),
  unique (plantilla_id, orden)
);

-- Las tareas que siempre se repiten en una fase. "proposito" es la frase que
-- lee quien recibe la tarea: para qué sirve en el proyecto. Se escribe una vez
-- aquí y nadie la vuelve a escribir.
create table if not exists public.plantilla_tarea (
  id                 uuid primary key default gen_random_uuid(),
  plantilla_fase_id  uuid not null references public.plantilla_fase(id),
  orden              smallint not null default 100,
  titulo             text not null,
  proposito          text not null,
  por_espacio        boolean not null default false,  -- se repite por cada espacio del proyecto
  prioridad          public.prioridad_pendiente not null default 'normal',
  dias_plazo         smallint,                         -- días hábiles desde que se propone
  depende_de         uuid references public.plantilla_tarea(id),
  activa             boolean not null default true,
  constraint plantilla_tarea_titulo_escrito check (length(trim(titulo)) >= 4),
  constraint plantilla_tarea_proposito_escrito check (length(trim(proposito)) >= 12),
  constraint plantilla_tarea_plazo_sano check (dias_plazo is null or dias_plazo between 0 and 120),
  constraint plantilla_tarea_no_depende_de_si check (depende_de is distinct from id)
);
create index if not exists plantilla_tarea_fase on public.plantilla_tarea (plantilla_fase_id, orden);
create index if not exists plantilla_tarea_depende_de on public.plantilla_tarea (depende_de);

alter table public.proyecto
  add column if not exists plantilla_id uuid references public.plantilla_proyecto(id);
alter table public.proyecto
  add column if not exists variante_chequeo_id uuid references public.variante_chequeo(id);
create index if not exists proyecto_plantilla on public.proyecto (plantilla_id);
create index if not exists proyecto_variante_chequeo on public.proyecto (variante_chequeo_id);

-- Lo que exige el cierre de cada fase viaja con la fase: cambiar la plantilla
-- mañana no cambia las reglas de un proyecto que ya está andando.
do $$ begin
  if not exists (
       select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'proyecto_fase'
         and column_name = 'exige_aprobacion_cliente') then
    alter table public.proyecto_fase
      add column exige_chequeo            boolean not null default true,
      add column exige_aprobacion_cliente boolean not null default false,
      add column exige_dedicacion         boolean not null default true,
      add column entrega_cliente          text;
    -- La regla que ya existía: el anteproyecto no cierra sin el cliente.
    update public.proyecto_fase set exige_aprobacion_cliente = true where fase = 'anteproyecto';
  end if;
end $$;


-- =============================================================================
-- 4. Equipo del proyecto con papel (D10)
-- =============================================================================

alter table public.acceso_proyecto
  add column if not exists papel public.papel_proyecto;

update public.acceso_proyecto a
   set papel = (case when p.es_interno then 'produce' else 'observa' end)::public.papel_proyecto
  from public.persona p
 where p.id = a.persona_id and a.papel is null;

alter table public.acceso_proyecto alter column papel set not null;
create index if not exists acceso_proyecto_papel on public.acceso_proyecto (proyecto_id, papel);
comment on column public.acceso_proyecto.papel is
  'dirige: asigna y revisa. produce: recibe tareas. revisa: el delegado de dirección para revisar. observa: ve sin recibir tareas (cliente en el portal). El papel se queda y la persona cambia: los practicantes rotan cada seis meses.';


-- =============================================================================
-- 5. Tareas: prioridad, propósito y rastro de cada cambio (D10 y D11)
-- =============================================================================

alter table public.tarea_diseno
  add column if not exists prioridad public.prioridad_pendiente not null default 'normal';
alter table public.tarea_diseno
  add column if not exists plantilla_tarea_id uuid references public.plantilla_tarea(id);
alter table public.tarea_diseno add column if not exists proposito text;
alter table public.tarea_diseno add column if not exists espacio text;
alter table public.tarea_diseno add column if not exists revision_pedida_en timestamptz;
create index if not exists tarea_diseno_plantilla_tarea on public.tarea_diseno (plantilla_tarea_id);
create index if not exists tarea_diseno_en_revision on public.tarea_diseno (revision_pedida_en)
  where estado = 'en_revision';
comment on column public.tarea_diseno.revision_pedida_en is
  'La pone el sistema cuando la tarea pasa a revisión. De aquí sale cuánto espera una revisión y si la entrega fue a tiempo.';

-- D11 · El rastro. Una fila por cada cosa que cambió, con quién y cuándo. De
-- aquí salen los indicadores; por eso no se edita ni se borra.
create table if not exists public.tarea_evento (
  id          bigint primary key generated always as identity,
  tarea_id    uuid not null references public.tarea_diseno(id),
  tipo        text not null check (tipo in ('creada','estado','reasignada','fecha','prioridad')),
  de          text,
  a           text,
  persona_id  uuid references public.persona(id),   -- quién lo hizo; vacío si fue una carga
  ocurrio_en  timestamptz not null default clock_timestamp()
);
create index if not exists tarea_evento_tarea on public.tarea_evento (tarea_id, ocurrio_en);
create index if not exists tarea_evento_persona on public.tarea_evento (persona_id);


-- =============================================================================
-- 6. Funciones de identidad
-- =============================================================================

-- El director de proyectos de construcción puede todo lo que puede un
-- arquitecto: asignar, presupuestar, validar. Se resuelve aquí, en un solo
-- sitio, y las políticas que ya nombraban al arquitecto lo incluyen solas.
-- No es dirección de la empresa: dirige las obras donde se le dé ese papel.
-- Se compara como texto porque Postgres no deja usar un valor recién agregado
-- a una lista dentro de la misma transacción (el paquete todo-en-uno es una sola).
create or replace function private.tiene_rol(p_roles public.rol_persona[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select p.rol = any (p_roles)
           or (p.rol::text = 'director_proyecto' and 'arquitecto' = any (p_roles))
    from public.persona p
    where p.auth_user_id = auth.uid() and p.activo and p.es_interno
    limit 1), false)
$$;

-- Proyectos donde la persona de la sesión asigna: dirección en todos, y quien
-- tenga el papel de dirigir en los suyos.
create or replace function private.proyectos_que_dirige() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select pr.id from public.proyecto pr
  where (select private.es_direccion())
  union
  select a.proyecto_id from public.acceso_proyecto a
  join public.persona p on p.id = a.persona_id
  where p.auth_user_id = auth.uid() and p.activo and p.es_interno and a.papel = 'dirige'
$$;

-- Proyectos donde puede revisar: dirección, quien dirige y quien dirección
-- haya designado para revisar. La designación no se limita a arquitectos.
create or replace function private.proyectos_que_revisa() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select pr.id from public.proyecto pr
  where (select private.es_direccion())
  union
  select a.proyecto_id from public.acceso_proyecto a
  join public.persona p on p.id = a.persona_id
  where p.auth_user_id = auth.uid() and p.activo and p.es_interno and a.papel in ('dirige','revisa')
$$;

-- D13 · La lista que le corresponde a una fase: primero la de la variante del
-- proyecto, si no la que sirve para cualquiera; siempre la versión más reciente.
create or replace function private.lista_para_fase(p_proyecto uuid, p_fase public.fase_proyecto)
returns uuid
language sql stable security definer set search_path = '' as $$
  select l.id
  from public.lista_chequeo l
  join public.proyecto p on p.id = p_proyecto
  where l.ambito = 'fase_diseno' and l.activa and l.fase = p_fase
    and (l.variante_id is null or l.variante_id = p.variante_chequeo_id)
  order by (l.variante_id is not null) desc, l.version desc, l.creada_en desc
  limit 1
$$;


-- =============================================================================
-- 7. Reglas
-- =============================================================================

-- ---------- Equipo ----------

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
  if tg_op = 'UPDATE' and new.papel = 'observa' and old.papel <> 'observa' then
    select count(*) into v_abiertas from public.tarea_diseno t
    where t.proyecto_id = old.proyecto_id and t.asignada_a = old.persona_id and t.estado <> 'terminada';
    if v_abiertas > 0 then
      raise exception 'D10 · Tiene % tarea(s) abierta(s) en este proyecto: reasígnelas antes de dejarla solo como observadora', v_abiertas;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists tr_acceso_proyecto_validar on public.acceso_proyecto;
create trigger tr_acceso_proyecto_validar
  before insert or update on public.acceso_proyecto
  for each row execute function private.validar_acceso();

-- Los practicantes rotan: antes de sacar a alguien del equipo, su trabajo
-- abierto pasa a otra persona. Si no, queda donde nadie lo ve.
create or replace function private.validar_retiro_acceso() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_abiertas integer;
begin
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

drop trigger if exists tr_acceso_proyecto_retiro on public.acceso_proyecto;
create trigger tr_acceso_proyecto_retiro
  before delete on public.acceso_proyecto
  for each row execute function private.validar_retiro_acceso();

-- ---------- Presupuestos ----------

-- O8 imprevistos, O10 margen de obra y validación profesional obligatoria.
-- Igual que antes; ahora también firma el director de proyectos de construcción.
create or replace function private.validar_presupuesto() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_min_imprevistos  numeric;
  v_meta_obra        numeric;
  v_proy             public.proyecto%rowtype;
  v_margen           numeric;
  v_emite            boolean;
begin
  select p.imprevistos_minimo, p.margen_meta_obra into v_min_imprevistos, v_meta_obra
  from public.parametro p where p.id;
  select * into v_proy from public.proyecto pr where pr.id = new.proyecto_id;

  v_emite := new.aprobado_en is not null or new.estado in ('emitido','aprobado_cliente');

  if new.validado_por is not null then
    if not exists (select 1 from public.persona p
                   where p.id = new.validado_por
                     and p.rol in ('socio','director','arquitecto','director_proyecto')) then
      raise exception 'La validación de un presupuesto la firma un profesional: socio, director, arquitecto o director de proyecto';
    end if;
    new.validado_en := coalesce(new.validado_en, now());
  end if;

  if new.margen_autorizado_por is not null then
    if not exists (select 1 from public.persona p where p.id = new.margen_autorizado_por and p.rol = 'socio') then
      raise exception 'O10 · Solo un socio autoriza un margen bajo la meta';
    end if;
    new.margen_autorizado_en := coalesce(new.margen_autorizado_en, now());
  end if;

  if v_emite and v_proy.tipo = 'obra' then
    if coalesce(v_proy.pct_imprevistos, 0) < v_min_imprevistos
       and length(trim(coalesce(new.justificacion_imprevistos, ''))) = 0 then
      raise exception 'O8 · Imprevistos en %, por debajo del mínimo de %. Súbalos o escriba la justificación antes de aprobar el presupuesto.',
        replace(round(coalesce(v_proy.pct_imprevistos, 0) * 100, 1)::text, '.', ',') || '%',
        replace(round(v_min_imprevistos * 100, 1)::text, '.', ',') || '%';
    end if;

    v_margen := coalesce(v_proy.pct_administracion, 0) + coalesce(v_proy.pct_utilidad, 0);
    if v_margen < v_meta_obra and new.margen_autorizado_por is null then
      raise exception 'O10 · Administración más utilidad suman %, bajo la meta de %. Necesita autorización de un socio.',
        replace(round(v_margen * 100, 1)::text, '.', ',') || '%',
        replace(round(v_meta_obra * 100, 1)::text, '.', ',') || '%';
    end if;
  end if;

  if v_emite then
    if new.validado_por is null then
      raise exception 'Un presupuesto no se emite sin la validación de un profesional';
    end if;
    if new.validado_por = new.elaborado_por then
      raise exception 'Quien elabora el presupuesto no lo valida';
    end if;
  end if;
  return new;
end $$;

-- ---------- Plantillas ----------

create or replace function private.validar_plantilla_tarea() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.depende_de is not null and not exists (
       select 1 from public.plantilla_tarea d
       where d.id = new.depende_de and d.plantilla_fase_id = new.plantilla_fase_id) then
    raise exception 'D12 · Una tarea de plantilla solo depende de otra de la misma fase';
  end if;
  return new;
end $$;

drop trigger if exists tr_plantilla_tarea_validar on public.plantilla_tarea;
create trigger tr_plantilla_tarea_validar
  before insert or update on public.plantilla_tarea
  for each row execute function private.validar_plantilla_tarea();

-- ---------- Fases ----------

-- D1 · Compuerta de fase. D2 · sin dedicación completa no hay cierre.
-- D12 · Lo que exige el cierre lo dice la plantilla, no quien crea la fase.
create or replace function private.validar_fase() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_hoy        date := private.hoy();
  v_pendiente  text;
  v_persona    record;
  v_faltan     integer;
  v_cierra     boolean;
  v_plantilla  public.plantilla_fase%rowtype;
begin
  if tg_op = 'INSERT' then
    select pf.* into v_plantilla
    from public.plantilla_fase pf
    join public.proyecto p on p.plantilla_id = pf.plantilla_id
    where p.id = new.proyecto_id and pf.fase = new.fase;
    if found then
      new.exige_chequeo := v_plantilla.exige_chequeo;
      new.exige_aprobacion_cliente := v_plantilla.exige_aprobacion_cliente;
      new.exige_dedicacion := v_plantilla.exige_dedicacion;
      new.entrega_cliente := coalesce(new.entrega_cliente, v_plantilla.entrega_cliente);
    else
      -- Sin plantilla rigen las reglas de siempre.
      new.exige_chequeo := true;
      new.exige_dedicacion := true;
      new.exige_aprobacion_cliente := (new.fase = 'anteproyecto');
    end if;
  elsif (new.exige_chequeo, new.exige_aprobacion_cliente, new.exige_dedicacion)
          is distinct from (old.exige_chequeo, old.exige_aprobacion_cliente, old.exige_dedicacion)
        and auth.uid() is not null and not private.tiene_rol('{socio}'::public.rol_persona[]) then
    raise exception 'D12 · Lo que exige el cierre de una fase solo lo cambia un socio';
  end if;

  if tg_op = 'UPDATE' and old.estado = 'cerrada' and new.estado <> 'cerrada' then
    if auth.uid() is not null and not private.tiene_rol('{socio}'::public.rol_persona[]) then
      raise exception 'D1 · Una fase cerrada solo la reabre un socio';
    end if;
    new.cerrada_en := null;
    new.cerrada_por := null;
  end if;

  -- No se abre una fase mientras las anteriores no estén cerradas.
  if new.estado <> 'pendiente' and (tg_op = 'INSERT' or old.estado = 'pendiente') then
    select string_agg(replace(f.fase::text, '_', ' '), ', ' order by f.orden) into v_pendiente
    from public.proyecto_fase f
    where f.proyecto_id = new.proyecto_id and f.orden < new.orden and f.estado <> 'cerrada';
    if v_pendiente is not null then
      raise exception 'D1 · No se abre % mientras no estén cerradas: %', replace(new.fase::text, '_', ' '), v_pendiente;
    end if;
    new.fecha_inicio := coalesce(new.fecha_inicio, v_hoy);
    update public.proyecto set fase = new.fase
     where id = new.proyecto_id and fase is distinct from new.fase;
  end if;

  -- El cierre. Una carga administrativa sin sesión puede registrar fases que
  -- ya se cerraron antes de existir el sistema; desde la aplicación, no.
  v_cierra := new.estado = 'cerrada'
              and ((tg_op = 'UPDATE' and old.estado <> 'cerrada')
                   or (tg_op = 'INSERT' and auth.uid() is not null));
  if v_cierra then
    if auth.uid() is not null and not private.es_direccion() then
      raise exception 'D1 · Solo dirección cierra una fase';
    end if;
    if new.exige_chequeo and not exists (
         select 1 from public.chequeo c where c.fase_id = new.id and private.chequeo_completo(c.id)) then
      raise exception 'D1 · La lista de chequeo de % no está completa', replace(new.fase::text, '_', ' ');
    end if;
    if new.exige_aprobacion_cliente and new.aprobada_cliente_en is null then
      raise exception 'D1 · La fase de % no se cierra sin la aprobación del cliente', replace(new.fase::text, '_', ' ');
    end if;
    if new.exige_dedicacion then
      if not exists (select 1 from public.dedicacion d where d.fase_id = new.id) then
        raise exception 'D2 · La fase % no tiene dedicación registrada', replace(new.fase::text, '_', ' ');
      end if;
      for v_persona in
        select distinct p.id, p.nombre
        from public.dedicacion d join public.persona p on p.id = d.persona_id
        where d.fase_id = new.id and p.activo
      loop
        v_faltan := private.dias_sin_dedicacion(v_persona.id, v_hoy - 7, v_hoy - 1);
        if v_faltan > 0 then
          raise exception 'D2 · % tiene % día(s) hábil(es) sin registrar dedicación en la última semana',
            v_persona.nombre, v_faltan;
        end if;
      end loop;
    end if;
    new.cerrada_en := coalesce(new.cerrada_en, now());
    if auth.uid() is not null then
      new.cerrada_por := private.persona_actual();
    end if;
  end if;
  return new;
end $$;

-- D13 · Al abrirse, la fase queda con la lista de chequeo de su variante. Si
-- todavía no hay lista para esa fase no se crea nada, y el cierre lo dirá.
create or replace function private.aplicar_fase() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_lista uuid;
begin
  if new.exige_chequeo and new.estado <> 'pendiente'
     and (tg_op = 'INSERT' or old.estado = 'pendiente')
     and not exists (select 1 from public.chequeo c where c.fase_id = new.id) then
    v_lista := private.lista_para_fase(new.proyecto_id, new.fase);
    if v_lista is not null then
      insert into public.chequeo (lista_id, fase_id) values (v_lista, new.id);
    end if;
  end if;
  return null;
end $$;

drop trigger if exists tr_proyecto_fase_aplicar on public.proyecto_fase;
create trigger tr_proyecto_fase_aplicar
  after insert or update on public.proyecto_fase
  for each row execute function private.aplicar_fase();

-- ---------- Listas de chequeo ----------

create or replace function private.validar_chequeo() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_lista     public.lista_chequeo%rowtype;
  v_proy      uuid;
  v_fase      public.fase_proyecto;
  v_aseg      uuid;
  v_ambito    public.ambito_chequeo;
  v_variante  uuid;
begin
  select * into v_lista from public.lista_chequeo l where l.id = new.lista_id;

  if new.fase_id is not null then
    select f.proyecto_id, f.fase into v_proy, v_fase from public.proyecto_fase f where f.id = new.fase_id;
    v_ambito := 'fase_diseno';
    if v_lista.fase is not null and v_lista.fase <> v_fase then
      raise exception 'Esta lista es para la fase %, no para %', v_lista.fase, v_fase;
    end if;
    select p.variante_chequeo_id into v_variante from public.proyecto p where p.id = v_proy;
    if v_lista.variante_id is not null and v_lista.variante_id is distinct from v_variante then
      raise exception 'D13 · Esta lista es de otra variante: no corresponde al tamaño y alcance de este proyecto';
    end if;
  elsif new.radicacion_id is not null then
    select r.proyecto_id into v_proy from public.radicacion_licencia r where r.id = new.radicacion_id;
    v_ambito := 'radicacion_licencia';
  elsif new.reclamacion_id is not null then
    select r.proyecto_id, r.aseguradora_id into v_proy, v_aseg from public.reclamacion r where r.id = new.reclamacion_id;
    v_ambito := 'reclamacion';
    if v_lista.aseguradora_id is not null and v_lista.aseguradora_id is distinct from v_aseg then
      raise exception 'P1 · Esta lista de chequeo es de otra aseguradora';
    end if;
  else
    select pr.proyecto_id into v_proy from public.presupuesto pr where pr.id = new.presupuesto_id;
    v_ambito := 'presupuesto';
  end if;

  if v_lista.ambito <> v_ambito then
    raise exception 'Una lista de % no sirve para %', v_lista.ambito, v_ambito;
  end if;
  if not v_lista.activa then
    raise exception 'Esa lista de chequeo ya no está activa';
  end if;
  new.proyecto_id := v_proy;
  return new;
end $$;

-- ---------- Tareas ----------

-- La tarea recorre: asignada, en curso, en revisión, y de ahí terminada o con
-- observaciones. Los dos últimos pasos solo los da una revisión.
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
    if tg_op = 'INSERT' or old.estado <> 'en_revision' or not exists (
         select 1 from public.revision_diseno r
         where r.tarea_id = new.id and r.resultado = 'aprobada'
           and r.revisor_id <> new.asignada_a and r.revisada_en >= v_desde) then
      raise exception 'Una tarea no se termina sin la revisión aprobada de alguien distinto de quien la hizo';
    end if;
    new.terminada_en := coalesce(new.terminada_en, now());
  end if;
  return new;
end $$;

create or replace function private.registrar_tarea_evento() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_yo uuid := private.persona_actual();
begin
  if tg_op = 'INSERT' then
    insert into public.tarea_evento (tarea_id, tipo, a, persona_id)
    values (new.id, 'creada', new.estado::text, v_yo);
    return null;
  end if;
  if new.estado is distinct from old.estado then
    insert into public.tarea_evento (tarea_id, tipo, de, a, persona_id)
    values (new.id, 'estado', old.estado::text, new.estado::text, v_yo);
  end if;
  if new.asignada_a is distinct from old.asignada_a then
    insert into public.tarea_evento (tarea_id, tipo, de, a, persona_id)
    values (new.id, 'reasignada', old.asignada_a::text, new.asignada_a::text, v_yo);
  end if;
  if new.fecha_compromiso is distinct from old.fecha_compromiso then
    insert into public.tarea_evento (tarea_id, tipo, de, a, persona_id)
    values (new.id, 'fecha', old.fecha_compromiso::text, new.fecha_compromiso::text, v_yo);
  end if;
  if new.prioridad is distinct from old.prioridad then
    insert into public.tarea_evento (tarea_id, tipo, de, a, persona_id)
    values (new.id, 'prioridad', old.prioridad::text, new.prioridad::text, v_yo);
  end if;
  return null;
end $$;

drop trigger if exists tr_tarea_diseno_evento on public.tarea_diseno;
create trigger tr_tarea_diseno_evento
  after insert or update on public.tarea_diseno
  for each row execute function private.registrar_tarea_evento();

drop trigger if exists tr_tarea_evento_no_editar on public.tarea_evento;
create trigger tr_tarea_evento_no_editar
  before update on public.tarea_evento
  for each row execute function private.prohibir_edicion();

-- ---------- Revisión ----------

create or replace function private.validar_revision() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_asignada uuid;
  v_estado   public.estado_tarea;
  v_titulo   text;
begin
  if auth.uid() is not null then
    new.revisor_id := private.persona_actual();
  end if;
  select t.asignada_a, t.estado, t.titulo into v_asignada, v_estado, v_titulo
  from public.tarea_diseno t where t.id = new.tarea_id;
  if new.revisor_id = v_asignada then
    raise exception 'La revisión la hace alguien distinto de quien hizo la tarea';
  end if;
  if v_estado <> 'en_revision' then
    raise exception 'D11 · Solo se revisa lo que pidió revisión: «%» está %', v_titulo, replace(v_estado::text, '_', ' ');
  end if;
  new.revisada_en := clock_timestamp();
  return new;
end $$;

-- Dos toques: aprobar termina la tarea, devolver la regresa a quien la hizo.
create or replace function private.aplicar_revision() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.tarea_diseno
     set estado = (case when new.resultado = 'aprobada' then 'terminada' else 'con_observaciones' end)::public.estado_tarea
   where id = new.tarea_id and estado = 'en_revision';
  return null;
end $$;

-- ---------- Rastro ----------

do $$
declare t text;
begin
  foreach t in array array[
    'tarea_diseno','plantilla_proyecto','plantilla_fase','plantilla_tarea','variante_chequeo'
  ] loop
    execute format('drop trigger if exists tr_%1$s_auditar on public.%1$I', t);
    execute format('create trigger tr_%1$s_auditar after insert or update or delete on public.%1$I '
                   'for each row execute function private.auditar()', t);
  end loop;

  foreach t in array array[
    'tarea_diseno','tarea_evento','plantilla_proyecto','plantilla_fase','plantilla_tarea','variante_chequeo'
  ] loop
    execute format('drop trigger if exists tr_%1$s_no_borrar on public.%1$I', t);
    execute format('create trigger tr_%1$s_no_borrar before delete on public.%1$I '
                   'for each row execute function private.prohibir_borrado()', t);
  end loop;
end $$;


-- =============================================================================
-- 8. Operaciones de un solo paso
-- Corren con los permisos de quien las llama: lo que la persona no puede hacer
-- tabla por tabla, tampoco lo puede hacer por aquí. Cada una es una sola
-- transacción: o queda todo, o no queda nada.
-- =============================================================================

-- D12 · Le pone a un proyecto las fases de su tipo, en orden y con las horas
-- cotizadas de cada una. p_horas: {"anteproyecto": 80, "proyecto_final": 120}.
-- p_omitir: las fases opcionales que no aplican (la licencia, cuando no hay).
create or replace function public.aplicar_plantilla(
  p_proyecto  uuid,
  p_plantilla uuid,
  p_horas     jsonb default '{}'::jsonb,
  p_variante  uuid default null,
  p_omitir    public.fase_proyecto[] default '{}'::public.fase_proyecto[])
returns integer
language plpgsql set search_path = '' as $$
declare
  v_tipo      public.tipo_proyecto;
  v_tipo_proy public.tipo_proyecto;
  v_sobra     text;
  v_n         integer;
begin
  select pl.tipo into v_tipo from public.plantilla_proyecto pl where pl.id = p_plantilla and pl.activa;
  if not found then
    raise exception 'D12 · Esa plantilla no existe o ya no está activa';
  end if;
  select p.tipo into v_tipo_proy from public.proyecto p where p.id = p_proyecto;
  if not found then
    raise exception 'D12 · Ese proyecto no existe o no lo puede ver';
  end if;
  if v_tipo_proy <> v_tipo then
    raise exception 'D12 · La plantilla es para proyectos de %, y este es de %', v_tipo, v_tipo_proy;
  end if;
  if exists (select 1 from public.proyecto_fase f where f.proyecto_id = p_proyecto) then
    raise exception 'D12 · Este proyecto ya tiene fases: la plantilla se aplica una sola vez';
  end if;

  select string_agg(k, ', ') into v_sobra
  from jsonb_object_keys(coalesce(p_horas, '{}'::jsonb)) k
  where k not in (select pf.fase::text from public.plantilla_fase pf where pf.plantilla_id = p_plantilla);
  if v_sobra is not null then
    raise exception 'D12 · Estas fases no son de la plantilla: %', v_sobra;
  end if;
  select string_agg(replace(o.fase::text, '_', ' '), ', ') into v_sobra
  from unnest(p_omitir) o(fase)
  where not exists (select 1 from public.plantilla_fase pf
                    where pf.plantilla_id = p_plantilla and pf.fase = o.fase and pf.opcional);
  if v_sobra is not null then
    raise exception 'D12 · Estas fases no se pueden omitir: %', v_sobra;
  end if;

  update public.proyecto
     set plantilla_id = p_plantilla,
         variante_chequeo_id = coalesce(p_variante, variante_chequeo_id)
   where id = p_proyecto;
  if not found then
    raise exception 'D12 · Solo dirección abre un proyecto';
  end if;

  insert into public.proyecto_fase (proyecto_id, fase, orden, horas_cotizadas)
  select p_proyecto, pf.fase, pf.orden, coalesce((p_horas ->> pf.fase::text)::numeric, 0)
  from public.plantilla_fase pf
  where pf.plantilla_id = p_plantilla and pf.fase <> all (p_omitir)
  order by pf.orden;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- D12 y D10 · Abre un proyecto completo: la ficha, sus fases y su equipo.
-- p_equipo: [{"persona_id": "…", "papel": "produce"}, …]
create or replace function public.abrir_proyecto(
  p_codigo      text,
  p_nombre      text,
  p_plantilla   uuid,
  p_unidad      public.unidad_negocio,
  p_horas       jsonb default '{}'::jsonb,
  p_equipo      jsonb default '[]'::jsonb,
  p_variante    uuid default null,
  p_omitir      public.fase_proyecto[] default '{}'::public.fase_proyecto[],
  p_cliente     uuid default null,
  p_responsable uuid default null)
returns uuid
language plpgsql set search_path = '' as $$
declare
  v_id   uuid := gen_random_uuid();
  v_tipo public.tipo_proyecto;
begin
  select pl.tipo into v_tipo from public.plantilla_proyecto pl where pl.id = p_plantilla and pl.activa;
  if not found then
    raise exception 'D12 · Esa plantilla no existe o ya no está activa';
  end if;
  if length(trim(coalesce(p_codigo, ''))) = 0 or length(trim(coalesce(p_nombre, ''))) = 0 then
    raise exception 'D12 · El proyecto necesita código y nombre';
  end if;

  insert into public.proyecto (id, codigo, nombre, unidad, tipo, cliente_id, responsable_id)
  values (v_id, trim(p_codigo), trim(p_nombre), p_unidad, v_tipo, p_cliente,
          coalesce(p_responsable, private.persona_actual()));

  perform public.aplicar_plantilla(v_id, p_plantilla, p_horas, p_variante, p_omitir);

  insert into public.acceso_proyecto (persona_id, proyecto_id, papel)
  select (e ->> 'persona_id')::uuid, v_id, (e ->> 'papel')::public.papel_proyecto
  from jsonb_array_elements(coalesce(p_equipo, '[]'::jsonb)) e;

  return v_id;
end $$;

-- D12 · Lo que una fase propone al abrirse. No crea nada: es la lista que quien
-- dirige ajusta en una sola pantalla antes de asignar. p_espacios: los espacios
-- del proyecto, para las tareas que se repiten por cada uno.
create or replace function public.proponer_tareas(p_fase uuid, p_espacios text[] default '{}'::text[])
returns table (
  plantilla_tarea_id uuid,
  orden              smallint,
  titulo             text,
  espacio            text,
  proposito          text,
  prioridad          public.prioridad_pendiente,
  fecha_sugerida     date,
  depende_de         uuid)
language sql stable set search_path = '' as $$
  select pt.id,
         pt.orden,
         pt.titulo || coalesce(' · ' || e.espacio, ''),
         e.espacio,
         pt.proposito,
         pt.prioridad,
         case when pt.dias_plazo is not null then private.sumar_habiles(private.hoy(), pt.dias_plazo) end,
         pt.depende_de
  from public.proyecto_fase f
  join public.proyecto p         on p.id = f.proyecto_id
  join public.plantilla_fase pf  on pf.plantilla_id = p.plantilla_id and pf.fase = f.fase
  join public.plantilla_tarea pt on pt.plantilla_fase_id = pf.id and pt.activa
  left join lateral unnest(
    case when pt.por_espacio and cardinality(p_espacios) > 0 then p_espacios else array[null::text] end
  ) as e(espacio) on true
  where f.id = p_fase
  order by pt.orden, e.espacio
$$;

-- D12 · Crea de una vez las tareas que quien dirige dejó en la pantalla.
-- p_tareas: [{"plantilla_tarea_id": "…", "titulo": "…", "espacio": "Cocina",
--             "asignada_a": "…", "fecha_compromiso": "2026-10-20", "prioridad": "alta"}, …]
-- El título y la prioridad se toman de la plantilla si no vienen. Las
-- dependencias de la plantilla se enlazan solas, espacio por espacio.
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
      (id, proyecto_id, fase_id, titulo, asignada_a, asignada_por, fecha_compromiso,
       prioridad, plantilla_tarea_id, proposito, espacio)
    values
      (v_id, v_proyecto, p_fase, v_titulo, (e ->> 'asignada_a')::uuid, v_yo,
       (e ->> 'fecha_compromiso')::date,
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

-- D10 · Pasa a otra persona todo el trabajo abierto de alguien que se va, en
-- un proyecto o en todos. Devuelve cuántas tareas cambiaron de manos.
create or replace function public.reasignar_tareas(p_de uuid, p_a uuid, p_proyecto uuid default null)
returns integer
language plpgsql set search_path = '' as $$
declare v_n integer;
begin
  if p_de is null or p_a is null or p_de = p_a then
    raise exception 'D10 · Hay que decir de quién y a quién, y deben ser personas distintas';
  end if;
  update public.tarea_diseno
     set asignada_a = p_a
   where asignada_a = p_de and estado <> 'terminada'
     and (p_proyecto is null or proyecto_id = p_proyecto);
  get diagnostics v_n = row_count;
  return v_n;
end $$;


-- =============================================================================
-- 9. Vistas
-- =============================================================================

do $$
declare v text;
begin
  foreach v in array array['v_mi_dia','v_tarea_contexto','v_cola_revision','v_carga_equipo'] loop
    execute format('drop view if exists public.%I cascade', v);
  end loop;
end $$;

-- D2 · La misma de antes, sin reclamar el registro de un festivo.
create or replace view public.v_dedicacion_pendiente with (security_invoker = true) as
select
  p.id           as persona_id,
  p.nombre,
  g.dia::date    as fecha
from public.persona p
cross join lateral generate_series(
  greatest(private.hoy() - 14, (p.creado_en at time zone 'America/Bogota')::date),
  private.hoy() - 1, interval '1 day') g(dia)
where p.activo and p.es_interno and p.rol::text in ('director','arquitecto','practicante','director_proyecto')
  and extract(isodow from g.dia) < 6
  and (p.id = private.persona_actual() or private.es_direccion() or auth.uid() is null)
  and not exists (select 1 from public.dedicacion d where d.persona_id = p.id and d.fecha = g.dia::date)
  and not exists (select 1 from public.festivo f where f.fecha = g.dia::date);

-- D4 · La misma de antes; cuenta también las horas del director de proyecto.
create or replace view public.v_capacidad_13_semanas with (security_invoker = true) as
with equipo as (
  select coalesce(sum(p.horas_semana), 0) as horas_semana
  from public.persona p
  where p.activo and p.es_interno and p.rol::text in ('director','arquitecto','practicante','director_proyecto')
),
pendiente as (
  select coalesce(sum(greatest(f.horas_cotizadas - coalesce(d.horas, 0), 0)), 0) as horas
  from public.proyecto_fase f
  left join (
    select dd.fase_id, sum(dd.horas) as horas from public.dedicacion dd group by dd.fase_id
  ) d on d.fase_id = f.id
  where f.estado <> 'cerrada'
)
select
  e.horas_semana * 13                  as horas_disponibles,
  pe.horas                             as horas_comprometidas,
  e.horas_semana * 13 - pe.horas       as holgura,
  case
    when e.horas_semana = 0 then 'Falta registrar las horas semanales del equipo para medir la capacidad'
    when pe.horas > e.horas_semana * 13 then
      'El equipo tiene comprometidas ' || round(pe.horas) || ' horas y en 13 semanas dispone de '
      || round(e.horas_semana * 13) || ': un contrato más no cabe sin mover fechas'
    else 'Quedan ' || round(e.horas_semana * 13 - pe.horas) || ' horas libres en las próximas 13 semanas'
  end                                  as lectura
from equipo e cross join pendiente pe;

-- «Mi día»: todo lo que tiene la persona de la sesión, de diseño y de obra, en
-- una sola lista y en el orden en que hay que atenderlo: lo vencido, lo de
-- hoy, lo que frena a otro, lo que le devolvieron y lo demás. Lo que ya está
-- en manos de quien revisa va al final: ya no depende de ella.
create view public.v_mi_dia with (security_invoker = true) as
with mias as (
  select
    'diseno'::text                                as origen,
    t.id,
    t.proyecto_id,
    t.titulo,
    t.estado::text                                as estado,
    t.prioridad,
    t.fecha_compromiso,
    t.proposito,
    t.estado = 'en_revision'                      as en_otras_manos,
    t.estado = 'con_observaciones'                as devuelta,
    t.revision_pedida_en                          as desde,
    b.titulo                                      as espera_titulo,
    bp.nombre                                     as espera_a,
    (b.id is not null and b.estado <> 'terminada') as detenida,
    (select string_agg(distinct dp.nombre, ', ')
       from public.tarea_diseno d
       join public.persona dp on dp.id = d.asignada_a
      where d.bloqueada_por = t.id and d.estado <> 'terminada'
        and d.asignada_a <> t.asignada_a)         as frena_a
  from public.tarea_diseno t
  left join public.tarea_diseno b on b.id = t.bloqueada_por
  left join public.persona bp     on bp.id = b.asignada_a
  where t.asignada_a = (select private.persona_actual()) and t.estado <> 'terminada'
  union all
  select
    'obra'::text,
    d.id,
    d.proyecto_id,
    d.titulo,
    d.estado::text,
    d.prioridad,
    d.fecha_compromiso,
    null::text,
    d.estado = 'por_verificar',
    false,
    null::timestamptz,
    b.titulo,
    bp.nombre,
    (b.id is not null and b.estado not in ('cerrado','descartado')),
    (select string_agg(distinct xp.nombre, ', ')
       from public.pendiente_obra x
       join public.persona xp on xp.id = x.responsable_id
      where x.bloqueado_por = d.id and x.estado not in ('cerrado','descartado')
        and x.responsable_id <> d.responsable_id)
  from public.pendiente_obra d
  left join public.pendiente_obra b on b.id = d.bloqueado_por
  left join public.persona bp       on bp.id = b.responsable_id
  where d.responsable_id = (select private.persona_actual())
    and d.estado not in ('cerrado','descartado')
),
ordenadas as (
  select m.*,
         case
           when m.en_otras_manos                                    then 6
           when m.fecha_compromiso < private.hoy()                  then 1
           when m.fecha_compromiso = private.hoy()                  then 2
           when m.frena_a is not null or m.prioridad = 'bloqueante' then 3
           when m.devuelta                                          then 4
           else 5
         end as orden
  from mias m
)
select
  o.origen,
  o.id,
  o.proyecto_id,
  p.codigo                as proyecto,
  o.titulo,
  o.estado,
  o.prioridad,
  o.fecha_compromiso,
  o.orden,
  case o.orden
    when 1 then 'Vencido'
    when 2 then 'Para hoy'
    when 3 then case when o.frena_a is not null then 'Alguien espera por ti' else 'No puede esperar' end
    when 4 then 'Te lo devolvieron'
    when 5 then 'Lo que sigue'
    else 'En manos de quien revisa'
  end                     as grupo,
  o.espera_a,
  o.frena_a,
  o.proposito             as para_que,
  case
    when o.en_otras_manos and o.origen = 'obra'
      then 'Hecho, falta que alguien lo verifique'
    when o.en_otras_manos
      then 'La tiene quien revisa'
           || coalesce(' desde el ' || to_char(o.desde at time zone 'America/Bogota', 'DD/MM'), '')
    when o.detenida
      then 'Esperas a ' || coalesce(o.espera_a, 'otra persona') || ': «' || o.espera_titulo || '»'
    when o.fecha_compromiso is null
      then 'Sin fecha de entrega'
    when o.fecha_compromiso < private.hoy()
      then 'Se entregaba el ' || to_char(o.fecha_compromiso, 'DD/MM')
           || case when private.dias_habiles(o.fecha_compromiso, private.hoy()) > 0
                   then ' y lleva ' || private.en_dias(private.dias_habiles(o.fecha_compromiso, private.hoy()))
                   else '' end
           || coalesce('. ' || case when position(',' in o.frena_a) > 0 then 'La esperan ' else 'La espera ' end
                       || o.frena_a, '')
    when o.frena_a is not null
      then case when position(',' in o.frena_a) > 0 then 'La esperan ' else 'La espera ' end || o.frena_a
           || case when o.fecha_compromiso = private.hoy() then ' y se entrega hoy'
                   else ' · se entrega el ' || to_char(o.fecha_compromiso, 'DD/MM') end
    when o.fecha_compromiso = private.hoy()
      then 'Se entrega hoy'
    when o.devuelta
      then 'Te la devolvieron con una observación · se entrega el ' || to_char(o.fecha_compromiso, 'DD/MM')
    when o.prioridad = 'bloqueante'
      then 'No puede esperar · se entrega el ' || to_char(o.fecha_compromiso, 'DD/MM')
    else 'Se entrega el ' || to_char(o.fecha_compromiso, 'DD/MM')
  end                     as lectura
from ordenadas o
join public.proyecto p on p.id = o.proyecto_id;

-- Lo que se lee al abrir una tarea: para qué sirve. Sale de la plantilla de la
-- fase y de los vínculos de la tarea; nadie lo escribe cada vez.
create view public.v_tarea_contexto with (security_invoker = true) as
select
  t.id                         as tarea_id,
  t.proyecto_id,
  p.codigo                     as proyecto,
  f.fase,
  f.entrega_cliente,
  t.proposito,
  o.titulo                     as objetivo,
  b.titulo                     as espera_titulo,
  bp.nombre                    as espera_a,
  e.la_esperan,
  nullif(concat_ws(' ',
    case when t.proposito is not null
         then rtrim(trim(t.proposito), '.') || '.' end,
    case when f.id is not null
         then 'Hace parte de ' || replace(f.fase::text, '_', ' ') || ' de ' || p.nombre
              || coalesce(': el cliente recibe ' || lower(left(f.entrega_cliente, 1))
                          || substr(f.entrega_cliente, 2), '') || '.' end,
    case when o.id is not null
         then 'Cuenta para el objetivo «' || o.titulo || '».' end,
    case when e.la_esperan is not null
         then case when e.cuantas = 1 then 'La espera ' else 'La esperan ' end || e.la_esperan || '.' end,
    case when b.id is not null and b.estado <> 'terminada'
         then 'No puede cerrarse hasta que ' || coalesce(bp.nombre, 'alguien') || ' termine «' || b.titulo || '».' end
  ), '')                       as para_que
from public.tarea_diseno t
join public.proyecto p             on p.id = t.proyecto_id
left join public.proyecto_fase f   on f.id = t.fase_id
left join public.objetivo o        on o.id = t.objetivo_id
left join public.tarea_diseno b    on b.id = t.bloqueada_por
left join public.persona bp        on bp.id = b.asignada_a
left join lateral (
  select count(*)                                                        as cuantas,
         string_agg(dp.nombre || ' para «' || d.titulo || '»', ' y ' order by d.fecha_compromiso) as la_esperan
  from public.tarea_diseno d
  join public.persona dp on dp.id = d.asignada_a
  where d.bloqueada_por = t.id and d.estado <> 'terminada'
) e on true;

-- La cola de quien revisa: lo que pidió revisión en los proyectos donde revisa,
-- sin lo suyo, y cuánto lleva esperando contra el plazo acordado.
create view public.v_cola_revision with (security_invoker = true) as
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
  end                          as lectura
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
  and t.proyecto_id in (select private.proyectos_que_revisa());

-- El tablero de quien dirige: la carga de cada persona, sin que nadie la
-- actualice a mano. Es carga, no mérito: aquí sí se cuenta lo abierto.
create view public.v_carga_equipo with (security_invoker = true) as
with trabajo as (
  select w.persona_id,
         count(*)                                                        as abiertas,
         count(*) filter (where w.dias_atraso is not null
                            and w.estado not in ('en_revision','por_verificar')) as vencidas,
         count(*) filter (where w.fecha_compromiso is null)               as sin_fecha,
         count(*) filter (where w.fecha_compromiso between private.hoy() and private.hoy() + 6) as esta_semana,
         count(*) filter (where w.estado in ('en_revision','por_verificar')) as esperando_revision
  from public.v_trabajo_abierto w
  group by w.persona_id
)
select
  pe.id                          as persona_id,
  pe.nombre,
  pe.rol,
  coalesce(w.abiertas, 0)        as abiertas,
  coalesce(w.vencidas, 0)        as vencidas,
  coalesce(w.sin_fecha, 0)       as sin_fecha,
  coalesce(w.esta_semana, 0)     as esta_semana,
  coalesce(w.esperando_revision, 0) as esperando_revision,
  case
    when coalesce(w.abiertas, 0) = 0 then 'Sin trabajo abierto'
    when w.vencidas > 0
      then case when w.vencidas = 1 then 'Una vencida' else w.vencidas || ' vencidas' end
           || ' de ' || w.abiertas || case when w.abiertas = 1 then ' abierta' else ' abiertas' end
           || case when w.sin_fecha > 0 then ' y ' || w.sin_fecha || ' sin fecha' else '' end
    when w.sin_fecha > 0
      then w.abiertas || case when w.abiertas = 1 then ' abierta, ' else ' abiertas, ' end
           || w.sin_fecha || ' sin fecha de entrega'
    else w.abiertas || case when w.abiertas = 1 then ' abierta y al día' else ' abiertas y al día' end
         || case when w.esta_semana > 0 then ' · ' || w.esta_semana || ' para esta semana' else '' end
  end                            as lectura
from public.persona pe
left join trabajo w on w.persona_id = pe.id
where pe.es_interno and pe.activo
  and (w.persona_id is not null
       or exists (select 1 from public.acceso_proyecto a
                  where a.persona_id = pe.id and a.papel <> 'observa'));


-- =============================================================================
-- 10. Permisos por fila
-- =============================================================================

alter table public.festivo            enable row level security;
alter table public.profesion          enable row level security;
alter table public.variante_chequeo   enable row level security;
alter table public.plantilla_proyecto enable row level security;
alter table public.plantilla_fase     enable row level security;
alter table public.plantilla_tarea    enable row level security;
alter table public.tarea_evento       enable row level security;

-- ---------- catálogos: los lee el equipo, los mantiene dirección ----------
do $$
declare t text;
begin
  foreach t in array array['festivo','profesion','variante_chequeo','plantilla_proyecto','plantilla_fase','plantilla_tarea'] loop
    execute format('drop policy if exists %1$s_lectura on public.%1$I', t);
    execute format('create policy %1$s_lectura on public.%1$I for select to authenticated '
                   'using ((select private.es_interno()))', t);
    execute format('drop policy if exists %1$s_alta on public.%1$I', t);
    execute format('create policy %1$s_alta on public.%1$I for insert to authenticated '
                   'with check ((select private.es_direccion()))', t);
    execute format('drop policy if exists %1$s_edicion on public.%1$I', t);
    execute format('create policy %1$s_edicion on public.%1$I for update to authenticated '
                   'using ((select private.es_direccion())) with check ((select private.es_direccion()))', t);
  end loop;
end $$;

-- ---------- tarea_evento · el rastro lo lee quien ve la tarea; lo escribe el sistema ----------
drop policy if exists tarea_evento_lectura on public.tarea_evento;
create policy tarea_evento_lectura on public.tarea_evento for select to authenticated
  using (exists (select 1 from public.tarea_diseno t where t.id = tarea_evento.tarea_id));

-- ---------- acceso_proyecto · cada quien ve con quién trabaja ----------
drop policy if exists acceso_proyecto_lectura on public.acceso_proyecto;
create policy acceso_proyecto_lectura on public.acceso_proyecto for select to authenticated
  using ((select private.es_direccion())
         or persona_id = (select private.persona_actual())
         or proyecto_id in (select private.proyectos_visibles()));

-- ---------- tarea_diseno ----------
-- Asignan dirección, quien dirige el proyecto y los arquitectos. Cualquiera
-- del equipo puede crearse una tarea propia en sus proyectos (Luisa, 12-10-2026).
drop policy if exists tarea_diseno_alta on public.tarea_diseno;
create policy tarea_diseno_alta on public.tarea_diseno for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and (proyecto_id in (select private.proyectos_que_dirige())
                   or (select private.tiene_rol('{arquitecto}'::public.rol_persona[]))
                   or asignada_a = (select private.persona_actual())));

drop policy if exists tarea_diseno_edicion on public.tarea_diseno;
create policy tarea_diseno_edicion on public.tarea_diseno for update to authenticated
  using (proyecto_id in (select private.proyectos_registro())
         and (proyecto_id in (select private.proyectos_que_dirige())
              or asignada_a = (select private.persona_actual())
              or asignada_por = (select private.persona_actual())))
  with check (proyecto_id in (select private.proyectos_registro())
              and (proyecto_id in (select private.proyectos_que_dirige())
                   or asignada_a = (select private.persona_actual())
                   or asignada_por = (select private.persona_actual())));

-- ---------- revision_diseno · revisa dirección o quien dirección designe ----------
drop policy if exists revision_diseno_alta on public.revision_diseno;
create policy revision_diseno_alta on public.revision_diseno for insert to authenticated
  with check (exists (select 1 from public.tarea_diseno t
                      where t.id = revision_diseno.tarea_id
                        and t.proyecto_id in (select private.proyectos_que_revisa())));


-- =============================================================================
-- 11. Permisos de la API
-- Lo nuevo nace cerrado y se abre exactamente lo necesario, igual que en
-- 20260914120800_permisos_api.sql.
-- =============================================================================

revoke all on
  public.festivo, public.profesion, public.variante_chequeo, public.plantilla_proyecto, public.plantilla_fase,
  public.plantilla_tarea, public.tarea_evento,
  public.v_mi_dia, public.v_tarea_contexto, public.v_cola_revision, public.v_carga_equipo,
  public.v_dedicacion_pendiente, public.v_capacidad_13_semanas
from anon, authenticated;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public  from public, anon;
revoke all on all functions in schema private from public, anon;
-- Reglas internas: las dispara la base, nadie las llama.
revoke all on function
  private.validar_acceso(), private.validar_retiro_acceso(), private.validar_plantilla_tarea(),
  private.aplicar_fase(), private.registrar_tarea_evento(),
  private.lista_para_fase(uuid, public.fase_proyecto)
from authenticated;

grant select, insert, update on
  public.festivo, public.profesion, public.variante_chequeo, public.plantilla_proyecto, public.plantilla_fase,
  public.plantilla_tarea
to authenticated;

grant select on public.tarea_evento to authenticated;

grant select on
  public.v_mi_dia, public.v_tarea_contexto, public.v_cola_revision, public.v_carga_equipo,
  public.v_dedicacion_pendiente, public.v_capacidad_13_semanas
to authenticated;

grant execute on function
  public.aplicar_plantilla(uuid, uuid, jsonb, uuid, public.fase_proyecto[]),
  public.abrir_proyecto(text, text, uuid, public.unidad_negocio, jsonb, jsonb, uuid, public.fase_proyecto[], uuid, uuid),
  public.proponer_tareas(uuid, text[]),
  public.crear_tareas(uuid, jsonb),
  public.reasignar_tareas(uuid, uuid, uuid),
  private.es_habil(date),
  private.dias_habiles(date, date),
  private.sumar_habiles(date, integer),
  private.en_dias(integer, boolean),
  private.proyectos_que_dirige(),
  private.proyectos_que_revisa()
to authenticated;

grant select, insert, update, delete on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;
grant execute on all functions in schema private to service_role;
