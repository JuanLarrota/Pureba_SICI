-- =============================================================================
-- SICI · El cierre de una fase, con sus datos obligatorios (D20 · 17-10-2026)
--
--   · La lista de chequeo de una fase se define por tipo de proyecto, y sus
--     puntos ya no son solo casillas: pueden pedir un dato (una opción, un
--     número, una fecha o un enlace). El punto queda cumplido cuando el dato
--     está y es válido. Así se pide escogiendo, no escribiendo.
--   · falta_para_cerrar() dice, en frases, qué le falta a una fase para
--     cerrarse. Son las mismas compuertas de siempre (D1 y D2): aquí solo se
--     cuentan antes de intentarlo.
--   · abrir_chequeo() deja lista la hoja de una fase que se abrió antes de que
--     existiera su lista.
--
-- No toca las migraciones anteriores. Idempotente.
-- =============================================================================

alter table public.lista_chequeo add column if not exists plantilla_id uuid references public.plantilla_proyecto(id);
create index if not exists lista_chequeo_plantilla on public.lista_chequeo (plantilla_id);
alter table public.lista_chequeo_item add column if not exists tipo text not null default 'casilla';
alter table public.lista_chequeo_item add column if not exists opciones text[];
alter table public.lista_chequeo_item add column if not exists activo boolean not null default true;
alter table public.chequeo_respuesta add column if not exists valor text;

do $$ begin
  alter table public.lista_chequeo_item add constraint punto_tipo_conocido
    check (tipo in ('casilla','opcion','numero','fecha','enlace'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.lista_chequeo_item add constraint punto_opcion_con_opciones
    check (tipo <> 'opcion' or cardinality(opciones) >= 2);
exception when duplicate_object then null; end $$;

comment on column public.lista_chequeo.plantilla_id is
  'Tipo de proyecto al que pertenece la lista. Vacío: vale para esa fase en cualquier tipo de proyecto.';
comment on column public.lista_chequeo_item.tipo is
  'casilla: se marca. opcion, numero, fecha, enlace: pide un dato, y queda cumplido cuando el dato es válido.';

-- La lista de una fase: primero la de su tipo de proyecto, después la de su
-- variante, después la general.
create or replace function private.lista_para_fase(p_proyecto uuid, p_fase public.fase_proyecto)
returns uuid
language sql stable security definer set search_path = '' as $$
  select l.id
  from public.lista_chequeo l
  join public.proyecto p on p.id = p_proyecto
  where l.ambito = 'fase_diseno' and l.activa and l.fase = p_fase
    and (l.variante_id is null or l.variante_id = p.variante_chequeo_id)
    and (l.plantilla_id is null or l.plantilla_id = p.plantilla_id)
  order by (l.plantilla_id is not null) desc, (l.variante_id is not null) desc, l.version desc, l.creada_en desc
  limit 1
$$;

-- Un punto que se quitó deja de contar.
create or replace function private.chequeo_completo(p_chequeo uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.chequeo c where c.id = p_chequeo)
     and not exists (
       select 1
       from public.chequeo c
       join public.lista_chequeo_item i on i.lista_id = c.lista_id
       where c.id = p_chequeo and i.obligatorio and i.activo
         and not exists (
           select 1 from public.chequeo_respuesta r
           where r.chequeo_id = c.id and r.item_id = i.id and r.cumple))
$$;

-- D20 · Un punto que pide un dato no se cumple sin el dato, ni con uno que no sirve.
create or replace function private.validar_dato_respuesta() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_tipo     text;
  v_opciones text[];
  v_texto    text;
begin
  select i.tipo, i.opciones, i.texto into v_tipo, v_opciones, v_texto
  from public.lista_chequeo_item i where i.id = new.item_id;
  new.valor := nullif(trim(new.valor), '');
  if coalesce(v_tipo, 'casilla') = 'casilla' or not new.cumple then
    return new;
  end if;
  if new.valor is null then
    raise exception 'D20 · «%» pide un dato: no basta con marcarlo', v_texto;
  end if;
  if v_tipo = 'opcion' and not (new.valor = any (v_opciones)) then
    raise exception 'D20 · «%» pide una de sus opciones', v_texto;
  elsif v_tipo = 'numero' and new.valor !~ '^-?[0-9]+([.,][0-9]+)?$' then
    raise exception 'D20 · «%» pide un número', v_texto;
  elsif v_tipo = 'enlace' and new.valor !~ '^https://[^ ]+$' then
    raise exception 'D20 · «%» pide un enlace que empiece por https://', v_texto;
  elsif v_tipo = 'fecha' then
    begin
      if new.valor !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'no es fecha'; end if;
      perform new.valor::date;
    exception when others then
      raise exception 'D20 · «%» pide una fecha', v_texto;
    end;
  end if;
  return new;
end $$;

drop trigger if exists tr_chequeo_respuesta_dato on public.chequeo_respuesta;
create trigger tr_chequeo_respuesta_dato
  before insert or update on public.chequeo_respuesta
  for each row execute function private.validar_dato_respuesta();

-- D20 · Agrega un punto a la lista de una fase de un tipo de proyecto. Si la
-- lista no existe, la crea. Lo que dirección no puede, lo impiden los permisos.
create or replace function public.punto_de_cierre(
  p_plantilla_fase uuid,
  p_texto          text,
  p_tipo           text default 'casilla',
  p_opciones       text[] default null,
  p_obligatorio    boolean default true)
returns uuid
language plpgsql set search_path = '' as $$
declare
  v_plantilla uuid;
  v_fase      public.fase_proyecto;
  v_nombre    text;
  v_lista     uuid;
  v_id        uuid;
begin
  select pf.plantilla_id, pf.fase, pl.nombre into v_plantilla, v_fase, v_nombre
  from public.plantilla_fase pf join public.plantilla_proyecto pl on pl.id = pf.plantilla_id
  where pf.id = p_plantilla_fase;
  if not found then
    raise exception 'D20 · Esa fase no es de ningún tipo de proyecto';
  end if;
  if length(trim(coalesce(p_texto, ''))) < 4 then
    raise exception 'D20 · El punto necesita decir qué se verifica';
  end if;
  select l.id into v_lista
  from public.lista_chequeo l
  where l.ambito = 'fase_diseno' and l.activa and l.fase = v_fase
    and l.plantilla_id = v_plantilla and l.variante_id is null
  order by l.version desc limit 1;
  if v_lista is null then
    insert into public.lista_chequeo (ambito, nombre, fase, plantilla_id)
    values ('fase_diseno', v_nombre || ' · ' || replace(v_fase::text, '_', ' '), v_fase, v_plantilla)
    returning id into v_lista;
  end if;
  insert into public.lista_chequeo_item (lista_id, orden, texto, obligatorio, tipo, opciones)
  values (v_lista,
          coalesce((select max(i.orden) from public.lista_chequeo_item i where i.lista_id = v_lista), 0) + 10,
          trim(p_texto), coalesce(p_obligatorio, true), coalesce(p_tipo, 'casilla'),
          case when p_tipo = 'opcion' then p_opciones end)
  returning id into v_id;
  return v_id;
end $$;

-- La hoja de chequeo de una fase. Si la fase se abrió antes de que existiera
-- su lista, la crea ahora. Sin lista, no devuelve nada.
create or replace function private.abrir_chequeo_de(p_fase uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id    uuid;
  v_proy  uuid;
  v_fase  public.fase_proyecto;
  v_lista uuid;
begin
  select f.proyecto_id, f.fase into v_proy, v_fase
  from public.proyecto_fase f
  where f.id = p_fase and f.proyecto_id in (select private.proyectos_registro());
  if not found then
    raise exception 'D20 · Esa fase no existe o usted no registra en ese proyecto';
  end if;
  select c.id into v_id from public.chequeo c where c.fase_id = p_fase order by c.creado_en limit 1;
  if v_id is not null then
    return v_id;
  end if;
  v_lista := private.lista_para_fase(v_proy, v_fase);
  if v_lista is null then
    return null;
  end if;
  insert into public.chequeo (lista_id, fase_id) values (v_lista, p_fase) returning id into v_id;
  return v_id;
end $$;

create or replace function public.abrir_chequeo(p_fase uuid) returns uuid
language sql set search_path = '' as $$
  select private.abrir_chequeo_de(p_fase)
$$;

-- Lo que le falta a una fase para cerrarse, en frases. "bloquea" dice si la
-- base lo exige; las tareas abiertas se avisan, pero no impiden el cierre.
create or replace function private.falta_para_cerrar_de(p_fase uuid)
returns table (orden smallint, que text, listo boolean, bloquea boolean, detalle text)
language plpgsql stable security definer set search_path = '' as $$
declare
  f          public.proyecto_fase%rowtype;
  v_hoy      date := private.hoy();
  v_chequeo  uuid;
  v_total    integer;
  v_ok       integer;
  v_faltan   text;
  v_abiertas integer;
begin
  select * into f from public.proyecto_fase x
  where x.id = p_fase and x.proyecto_id in (select private.proyectos_visibles());
  if not found then
    raise exception 'D20 · Esa fase no existe o no la puede ver';
  end if;

  if f.exige_chequeo then
    select c.id into v_chequeo from public.chequeo c where c.fase_id = f.id order by c.creado_en limit 1;
    if v_chequeo is null then
      return query select 1::smallint, 'chequeo'::text, false, true,
        case when private.lista_para_fase(f.proyecto_id, f.fase) is null
             then 'Esta fase no tiene lista de chequeo: dirección la define en el flujo'
             else 'La lista de chequeo está sin empezar' end;
    else
      select count(*), count(*) filter (where exists (
               select 1 from public.chequeo_respuesta r
               where r.chequeo_id = v_chequeo and r.item_id = i.id and r.cumple))
        into v_total, v_ok
      from public.chequeo c
      join public.lista_chequeo_item i on i.lista_id = c.lista_id
      where c.id = v_chequeo and i.obligatorio and i.activo;
      return query select 1::smallint, 'chequeo'::text, private.chequeo_completo(v_chequeo), true,
        case when v_total = 0 then 'La lista no tiene puntos obligatorios'
             when v_ok = v_total and v_total = 1 then 'El punto obligatorio está cumplido'
             when v_ok = v_total then 'Los ' || v_total || ' puntos obligatorios están cumplidos'
             else 'Van ' || v_ok || ' de ' || v_total || ' puntos obligatorios' end;
    end if;
  end if;

  if f.exige_aprobacion_cliente then
    return query select 2::smallint, 'cliente'::text, f.aprobada_cliente_en is not null, true,
      case when f.aprobada_cliente_en is null then 'Falta la aprobación del cliente'
           else 'El cliente ya aprobó' end;
  end if;

  if f.exige_dedicacion then
    if not exists (select 1 from public.dedicacion d where d.fase_id = f.id) then
      return query select 3::smallint, 'dedicacion'::text, false, true, 'Nadie ha registrado tiempo en esta fase'::text;
    else
      select string_agg(split_part(x.nombre, ' ', 1) || ' (' || private.en_dias(x.n, true) || ')', ', ' order by x.nombre)
        into v_faltan
      from (select distinct p.id, p.nombre, private.dias_sin_dedicacion(p.id, v_hoy - 7, v_hoy - 1) as n
            from public.dedicacion d join public.persona p on p.id = d.persona_id
            where d.fase_id = f.id and p.activo) x
      where x.n > 0;
      return query select 3::smallint, 'dedicacion'::text, v_faltan is null, true,
        case when v_faltan is null then 'La dedicación del equipo está al día'
             else 'Tienen días sin registrar en la última semana: ' || v_faltan end;
    end if;
  end if;

  select count(*) into v_abiertas from public.tarea_diseno t where t.fase_id = f.id and t.estado <> 'terminada';
  return query select 4::smallint, 'tareas'::text, v_abiertas = 0, false,
    case when v_abiertas = 0 then 'No quedan tareas abiertas'
         when v_abiertas = 1 then 'Queda una tarea abierta'
         else 'Quedan ' || v_abiertas || ' tareas abiertas' end;
end $$;

create or replace function public.falta_para_cerrar(p_fase uuid)
returns table (orden smallint, que text, listo boolean, bloquea boolean, detalle text)
language sql stable set search_path = '' as $$
  select c.orden, c.que, c.listo, c.bloquea, c.detalle
  from private.falta_para_cerrar_de(p_fase) c
  order by c.orden
$$;

revoke all on all functions in schema public  from public, anon;
revoke all on all functions in schema private from public, anon;
revoke all on function private.validar_dato_respuesta() from authenticated;
-- Las dos privadas que se otorgan revisan por dentro quién las llama.
grant execute on function
  public.punto_de_cierre(uuid, text, text, text[], boolean),
  public.abrir_chequeo(uuid),
  public.falta_para_cerrar(uuid),
  private.abrir_chequeo_de(uuid),
  private.falta_para_cerrar_de(uuid)
to authenticated;
grant execute on all functions in schema public to service_role;
grant execute on all functions in schema private to service_role;
