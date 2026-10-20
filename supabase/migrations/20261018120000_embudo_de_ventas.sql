-- =============================================================================
-- SICI · El embudo de ventas (V1 a V4 · 18-10-2026)
--
-- Sale de leer, el 13 de octubre de 2026, las 124 cotizaciones de 2025 y 2026,
-- el financiero, el calendario de Felipe y 128 transcripciones de citas:
--
--   · Los cuatro clientes que firmaron tuvieron dos reuniones: la cita de
--     viabilidad y, días después, la presentación de la cotización. De los que
--     solo tuvieron una reunión no firmó ninguno.
--   · Las ofertas se quedan quietas porque nadie tiene el siguiente paso.
--   · El diseño abre la obra (Apto Cali: $4,5 M de interiorismo, luego $40 M
--     de obra), y esa venta no tenía dueño.
--
-- Lo que agrega:
--   · V1 · Toda oportunidad abierta tiene su siguiente paso, con fecha y con
--     quién lo da. Si nadie lo escribe, el sistema lo propone según la etapa.
--   · V2 · Ninguna cotización se emite sin la reunión de presentación agendada.
--   · V3 · Antes de cotizar va el reporte de la cita: si estaba quien decide,
--     si tiene lote, cuándo tiene el recurso y para qué es.
--   · V4 · Al ganar un diseño o un interiorismo nace sola la oportunidad de
--     obra, con el mismo canal y el mismo cliente, a nombre de quien responde
--     por las obras.
--   · nuevo_contacto(), agendar_cita_de_lead() y reporte_de_cita(): cada paso
--     del embudo en una sola operación.
--   · v_ventas_hoy, v_embudo_ventas y v_ritmo_ventas: qué hacer hoy, dónde está
--     cada oportunidad y cuántas citas hacen falta para la meta.
--   · tarifa_diseno: el valor sugerido por rango de área. Va vacía: los precios
--     los escribe dirección, no el código.
--
-- Decisiones tomadas sin preguntar, para que se puedan revisar:
--   · Las etapas siguen siendo las de la base; en pantalla se llaman cita de
--     viabilidad, cotización en preparación, cotización presentada y contrato y
--     anticipo. Cambiar la lista de etapas rompería las migraciones aplicadas.
--   · Las reglas aplican a quien trabaja desde la aplicación. Las cargas del
--     sistema (la importación de Pipedrive) no se frenan.
--   · Una cotización que nace sin oportunidad (adicionales de una obra) no pide
--     reunión de presentación.
--
-- No toca las migraciones anteriores. Idempotente.
-- =============================================================================

-- ---------- Estructura ----------

alter table public.oportunidad add column if not exists siguiente_paso        text;
alter table public.oportunidad add column if not exists siguiente_paso_en     date;
alter table public.oportunidad add column if not exists siguiente_paso_por    uuid references public.persona(id);
alter table public.oportunidad add column if not exists etapa_desde           timestamptz not null default now();
alter table public.oportunidad add column if not exists origen_oportunidad_id uuid references public.oportunidad(id);
alter table public.oportunidad add column if not exists origen_proyecto_id    uuid references public.proyecto(id);
create index if not exists oportunidad_siguiente_paso_por on public.oportunidad (siguiente_paso_por);
create index if not exists oportunidad_origen on public.oportunidad (origen_oportunidad_id);
create index if not exists oportunidad_origen_proyecto on public.oportunidad (origen_proyecto_id);
create index if not exists oportunidad_por_hacer on public.oportunidad (siguiente_paso_en) where etapa not in ('ganada','perdida');
comment on column public.oportunidad.siguiente_paso is
  'V1 · Lo próximo que hay que hacer con esta oportunidad. Si nadie lo escribe, el sistema lo propone según la etapa.';
comment on column public.oportunidad.origen_oportunidad_id is
  'V4 · La venta de diseño de la que nació esta oportunidad de obra. El canal viaja con el cliente.';

alter table public.cita add column if not exists tipo text not null default 'viabilidad';
alter table public.cita add column if not exists transcripcion_url text;
do $$ begin
  alter table public.cita add constraint cita_tipo_conocido check (tipo in ('viabilidad','presentacion','seguimiento'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.cita add constraint cita_transcripcion_es_enlace check (transcripcion_url is null or transcripcion_url ~ '^https://');
exception when duplicate_object then null; end $$;
create index if not exists cita_presentacion on public.cita (oportunidad_id) where tipo = 'presentacion';
comment on column public.cita.tipo is
  'viabilidad: la primera conversación. presentacion: la reunión donde se presenta la cotización, que es donde se vende. seguimiento: cualquier otra.';

alter table public.calificacion add column if not exists decisor_presente boolean;
alter table public.calificacion add column if not exists cita_id uuid references public.cita(id);
create index if not exists calificacion_cita on public.calificacion (cita_id);
comment on column public.calificacion.decisor_presente is
  '¿Estaba en la cita quien decide? Una pérdida de 2026 fue dos meses de seguimiento a la persona que no decidía.';

alter table public.parametro add column if not exists responsable_obra_id   uuid references public.persona(id);
alter table public.parametro add column if not exists dias_oferta_obra      smallint not null default 30;
alter table public.parametro add column if not exists dias_entre_intentos   smallint not null default 2;
alter table public.parametro add column if not exists meta_ventas_diseno_mes numeric(16,2);
create index if not exists parametro_responsable_obra on public.parametro (responsable_obra_id);
do $$ begin
  alter table public.parametro add constraint parametro_ventas_sanos
    check (dias_oferta_obra between 1 and 365 and dias_entre_intentos between 1 and 30
           and (meta_ventas_diseno_mes is null or meta_ventas_diseno_mes > 0));
exception when duplicate_object then null; end $$;
comment on column public.parametro.responsable_obra_id is
  'V4 · Quien recibe la oportunidad de obra que nace de cada diseño ganado. Vacío: la recibe quien vendió el diseño.';

create table if not exists public.tarifa_diseno (
  id          uuid primary key default gen_random_uuid(),
  unidad      public.unidad_negocio not null,
  area_desde  numeric(10,2) not null check (area_desde >= 0),
  area_hasta  numeric(10,2) not null,
  valor       numeric(16,2) not null check (valor > 0),
  alcance     text,
  activa      boolean not null default true,
  creada_por  uuid references public.persona(id),
  creada_en   timestamptz not null default now(),
  constraint tarifa_rango_sano check (area_hasta > area_desde)
);
create index if not exists tarifa_diseno_creada_por on public.tarifa_diseno (creada_por);
create index if not exists tarifa_diseno_busqueda on public.tarifa_diseno (unidad, area_desde) where activa;
comment on table public.tarifa_diseno is
  'Valor de diseño por rango de área. Lo escribe dirección; el reporte de la cita lo usa para sugerir el valor estimado.';
alter table public.tarifa_diseno enable row level security;

drop policy if exists tarifa_lectura on public.tarifa_diseno;
create policy tarifa_lectura on public.tarifa_diseno for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));
drop policy if exists tarifa_alta on public.tarifa_diseno;
create policy tarifa_alta on public.tarifa_diseno for insert to authenticated
  with check ((select private.es_direccion()));
drop policy if exists tarifa_edicion on public.tarifa_diseno;
create policy tarifa_edicion on public.tarifa_diseno for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- Quien responde por una oportunidad la ve y le cambia el siguiente paso,
-- aunque no sea de ventas: así recibe Daniel Daza las de obra.
-- Una sola política por operación: se amplían las de ventas.
drop policy if exists oportunidad_lectura on public.oportunidad;
create policy oportunidad_lectura on public.oportunidad for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[]))
         or responsable_id = (select private.persona_actual())
         or siguiente_paso_por = (select private.persona_actual()));
drop policy if exists oportunidad_edicion on public.oportunidad;
create policy oportunidad_edicion on public.oportunidad for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[]))
         or responsable_id = (select private.persona_actual())
         or siguiente_paso_por = (select private.persona_actual()))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[]))
              or responsable_id = (select private.persona_actual())
              or siguiente_paso_por = (select private.persona_actual()));


-- ---------- Auxiliares ----------

-- «Hace un momento», «hace 40 minutos», «hace 5 horas», «hace 3 días».
create or replace function private.hace(p_desde timestamptz) returns text
language sql stable set search_path = '' as $$
  select case
    when m < 1    then 'un momento'
    when m < 60   then case when m = 1 then 'un minuto' else m || ' minutos' end
    when m < 2880 then case when m / 60 = 1 then 'una hora' else (m / 60) || ' horas' end
    else case when m / 1440 = 1 then 'un día' else (m / 1440) || ' días' end
  end
  from (select greatest(0, floor(extract(epoch from now() - p_desde) / 60))::bigint as m) x
$$;

-- La aplicación manda la hora como se ve en Colombia, sin zona.
create or replace function private.hora_local(p_texto text) returns timestamptz
language sql stable set search_path = '' as $$
  select case when nullif(trim(p_texto), '') is null then null
              else (trim(p_texto)::timestamp at time zone 'America/Bogota') end
$$;

create or replace function private.a_las(p_momento timestamptz) returns text
language sql stable set search_path = '' as $$
  select to_char(p_momento at time zone 'America/Bogota', 'FMHH12:MI')
         || case when extract(hour from p_momento at time zone 'America/Bogota') < 12 then ' a. m.' else ' p. m.' end
$$;

create or replace function private.dia_corto(p_dia date) returns text
language sql immutable set search_path = '' as $$
  select extract(day from p_dia)::int || ' de '
         || (array['enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'])[extract(month from p_dia)::int]
$$;

-- V2 · ¿Esta oportunidad tiene agendada la presentación de su cotización?
create or replace function private.tiene_presentacion(p_oportunidad uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.cita c
    where c.oportunidad_id = p_oportunidad and c.tipo = 'presentacion'
      and c.estado in ('agendada','realizada'))
$$;


-- ---------- V1 y V3 · cada oportunidad, antes de guardarse ----------

create or replace function private.ventas_oportunidad() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_hoy    date := private.hoy();
  v_sesion boolean := auth.uid() is not null;
  v_paso   text;
  v_dias   integer;
begin
  if tg_op = 'INSERT' or new.etapa is distinct from old.etapa then
    new.etapa_desde := now();
  end if;

  if new.etapa in ('ganada','perdida') then
    new.siguiente_paso := null;
    new.siguiente_paso_en := null;
    new.siguiente_paso_por := null;
    return new;
  end if;

  -- V3 · De la cita de viabilidad no se pasa sin su reporte.
  if v_sesion and tg_op = 'UPDATE' and old.etapa = 'cita_viabilidad' and new.etapa > 'cita_viabilidad'
     and not exists (
       select 1 from public.calificacion c
       where c.oportunidad_id = new.id and c.decisor_presente is not null and c.tiene_lote is not null
         and c.recurso_disponible is not null and c.proposito is not null) then
    raise exception 'V3 · Antes de cotizar va el reporte de la cita: si estaba quien decide, si tiene lote, cuándo tiene el recurso y para qué es';
  end if;

  -- V1 · El siguiente paso: el que se escribió, o el que propone la etapa.
  v_paso := case new.etapa
    when 'cita_viabilidad'       then 'Hacer la cita de viabilidad'
    when 'presupuesto_detallado' then 'Preparar la cotización para su presentación'
    when 'cotizacion_enviada'    then 'Saber qué decidió el cliente sobre la cotización'
    else 'Firmar el contrato y recibir el anticipo' end;
  v_dias := case new.etapa
    when 'cita_viabilidad' then 2 when 'presupuesto_detallado' then 5 when 'cotizacion_enviada' then 7 else 5 end;
  if tg_op = 'INSERT' then
    new.siguiente_paso := coalesce(nullif(trim(new.siguiente_paso), ''), v_paso);
    new.siguiente_paso_en := coalesce(new.siguiente_paso_en, v_hoy + v_dias);
  elsif new.etapa is distinct from old.etapa
        and new.siguiente_paso is not distinct from old.siguiente_paso
        and new.siguiente_paso_en is not distinct from old.siguiente_paso_en then
    new.siguiente_paso := v_paso;
    new.siguiente_paso_en := v_hoy + v_dias;
  end if;
  new.siguiente_paso_por := coalesce(new.siguiente_paso_por, new.responsable_id, private.persona_actual());

  if v_sesion then
    if length(trim(coalesce(new.siguiente_paso, ''))) < 4 then
      raise exception 'V1 · Una oportunidad abierta necesita su siguiente paso escrito';
    end if;
    if new.siguiente_paso_en is null then
      raise exception 'V1 · El siguiente paso necesita fecha';
    end if;
    if (tg_op = 'INSERT' or new.siguiente_paso_en is distinct from old.siguiente_paso_en) and new.siguiente_paso_en < v_hoy then
      raise exception 'V1 · El siguiente paso no puede quedar para una fecha que ya pasó';
    end if;
    if new.siguiente_paso_por is null then
      raise exception 'V1 · El siguiente paso necesita quién lo da';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists tr_oportunidad_ventas on public.oportunidad;
create trigger tr_oportunidad_ventas
  before insert or update on public.oportunidad
  for each row execute function private.ventas_oportunidad();

-- V4 · El diseño abre la obra.
create or replace function private.diseno_abre_obra() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_par   public.parametro%rowtype;
  v_quien uuid;
begin
  if new.etapa <> 'ganada' or old.etapa = 'ganada'
     or new.unidad is null or new.unidad not in ('diseno_arquitectonico','interiorismo')
     or exists (select 1 from public.oportunidad h where h.origen_oportunidad_id = new.id) then
    return null;
  end if;
  select * into v_par from public.parametro p where p.id;
  v_quien := coalesce(v_par.responsable_obra_id, new.responsable_id, old.siguiente_paso_por);
  insert into public.oportunidad
    (cliente_id, nombre, unidad, canal, etapa, ciudad, area_m2, responsable_id,
     origen_oportunidad_id, siguiente_paso, siguiente_paso_en, siguiente_paso_por)
  values
    (new.cliente_id, 'Obra · ' || new.nombre, 'obra_propia', new.canal, 'cita_viabilidad', new.ciudad, new.area_m2, v_quien,
     new.id, 'Ofrecer el presupuesto de obra', private.hoy() + v_par.dias_oferta_obra, v_quien);
  return null;
end $$;

drop trigger if exists tr_oportunidad_abre_obra on public.oportunidad;
create trigger tr_oportunidad_abre_obra
  after update on public.oportunidad
  for each row execute function private.diseno_abre_obra();


-- ---------- V2 · la cotización ----------

create or replace function private.ventas_cotizacion() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.estado = 'emitida' and (tg_op = 'INSERT' or old.estado is distinct from 'emitida')
     and new.oportunidad_id is not null and auth.uid() is not null
     and not private.tiene_presentacion(new.oportunidad_id) then
    raise exception 'V2 · Una cotización no se emite sin la reunión de presentación agendada: agéndela con el cliente primero';
  end if;
  return new;
end $$;

drop trigger if exists tr_cotizacion_ventas on public.cotizacion;
create trigger tr_cotizacion_ventas
  before insert or update on public.cotizacion
  for each row execute function private.ventas_cotizacion();

-- Emitida, la oportunidad queda en «cotización presentada»; aceptada, en contrato.
create or replace function private.cotizacion_mueve_oportunidad() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_hoy  date := private.hoy();
  v_pres timestamptz;
begin
  if new.oportunidad_id is null or (tg_op = 'UPDATE' and new.estado is not distinct from old.estado) then
    return null;
  end if;
  if new.estado = 'emitida' then
    select min(c.programada_para) into v_pres from public.cita c
    where c.oportunidad_id = new.oportunidad_id and c.tipo = 'presentacion' and c.estado = 'agendada';
    update public.oportunidad o
       set etapa = 'cotizacion_enviada',
           valor_estimado = coalesce(nullif(o.valor_estimado, 0), new.valor),
           siguiente_paso = 'Presentar la cotización ' || new.numero
             || coalesce(' el ' || private.dia_corto((v_pres at time zone 'America/Bogota')::date) || ' a las ' || private.a_las(v_pres), ''),
           siguiente_paso_en = greatest(v_hoy, coalesce((v_pres at time zone 'America/Bogota')::date, v_hoy))
     where o.id = new.oportunidad_id and o.etapa < 'cotizacion_enviada';
  elsif new.estado = 'aceptada' then
    update public.oportunidad o
       set etapa = 'negociacion', valor_estimado = coalesce(nullif(o.valor_estimado, 0), new.valor)
     where o.id = new.oportunidad_id and o.etapa < 'negociacion';
  end if;
  return null;
end $$;

drop trigger if exists tr_cotizacion_mueve on public.cotizacion;
create trigger tr_cotizacion_mueve
  after insert or update on public.cotizacion
  for each row execute function private.cotizacion_mueve_oportunidad();


-- ---------- Cada paso del embudo en una sola operación ----------

-- El valor de diseño que sugiere la tabla de tarifas para un área.
create or replace function public.valor_sugerido(p_unidad public.unidad_negocio, p_area numeric) returns numeric
language sql stable set search_path = '' as $$
  select t.valor from public.tarifa_diseno t
  where t.activa and t.unidad = p_unidad and p_area > t.area_desde and p_area <= t.area_hasta
  order by t.creada_en desc
  limit 1
$$;

-- Un contacto nuevo. Si ya quedó la cita, nace también la oportunidad.
-- p_datos: {"nombre","telefono","correo","ciudad","canal","como_nos_encontro","mensaje",
--           "unidad","proyecto","cita":"2026-10-20T15:00","modalidad","responsable_id","medio"}
create or replace function public.nuevo_contacto(p_datos jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_yo   uuid := private.persona_actual();
  v_lead uuid;
  v_res  jsonb;
begin
  if nullif(trim(coalesce(p_datos ->> 'nombre', p_datos ->> 'telefono', p_datos ->> 'correo', '')), '') is null then
    raise exception 'V0 · El contacto necesita al menos el nombre, el teléfono o el correo';
  end if;
  if nullif(p_datos ->> 'canal', '') is null then
    raise exception 'M1 · Falta por dónde llegó: ningún contacto entra sin canal';
  end if;
  insert into public.lead (canal, como_nos_encontro, nombre, telefono, correo, ciudad, mensaje_inicial, asignado_a)
  values ((p_datos ->> 'canal')::public.canal_origen,
          nullif(p_datos ->> 'como_nos_encontro', '')::public.canal_origen,
          nullif(trim(p_datos ->> 'nombre'), ''), nullif(trim(p_datos ->> 'telefono'), ''),
          nullif(trim(p_datos ->> 'correo'), ''), nullif(trim(p_datos ->> 'ciudad'), ''),
          nullif(trim(p_datos ->> 'mensaje'), ''), v_yo)
  returning id into v_lead;
  v_res := jsonb_build_object('lead_id', v_lead);
  if nullif(p_datos ->> 'cita', '') is not null then
    v_res := v_res || public.agendar_cita_de_lead(v_lead, p_datos);
  end if;
  return v_res;
end $$;

-- Con la cita agendada, el contacto se vuelve oportunidad.
create or replace function public.agendar_cita_de_lead(p_lead uuid, p_datos jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_yo     uuid := private.persona_actual();
  v_l      public.lead%rowtype;
  v_cuando timestamptz := private.hora_local(p_datos ->> 'cita');
  v_op     uuid;
  v_cita   uuid;
begin
  select * into v_l from public.lead l where l.id = p_lead;
  if not found then
    raise exception 'V0 · Ese contacto no existe o no lo puede ver';
  end if;
  if v_cuando is null then
    raise exception 'V0 · Falta el día y la hora de la cita';
  end if;
  if v_cuando < now() - interval '1 hour' then
    raise exception 'V0 · La cita tiene que quedar para un momento que no ha pasado';
  end if;
  if v_l.primer_contacto_en is null then
    insert into public.contacto_lead (lead_id, medio, direccion, respondio, nota, registrado_por)
    values (p_lead, coalesce(nullif(p_datos ->> 'medio', ''), 'whatsapp')::public.medio_contacto, 'saliente', true,
            'Se agendó la cita', v_yo);
  end if;
  select o.id into v_op from public.oportunidad o
  where o.lead_id = p_lead and o.etapa not in ('ganada','perdida') order by o.creada_en desc limit 1;
  if v_op is null then
    insert into public.oportunidad (lead_id, nombre, unidad, ciudad, responsable_id)
    values (p_lead,
            coalesce(nullif(trim(p_datos ->> 'proyecto'), ''), 'Proyecto de ' || coalesce(v_l.nombre, v_l.telefono, v_l.correo)),
            nullif(p_datos ->> 'unidad', '')::public.unidad_negocio, v_l.ciudad,
            coalesce(nullif(p_datos ->> 'responsable_id', '')::uuid, v_yo))
    returning id into v_op;
  end if;
  insert into public.cita (oportunidad_id, programada_para, tipo, modalidad)
  values (v_op, v_cuando, 'viabilidad', coalesce(nullif(p_datos ->> 'modalidad', ''), 'videollamada'))
  returning id into v_cita;
  update public.oportunidad
     set siguiente_paso = 'Hacer la cita de viabilidad el ' || private.dia_corto((v_cuando at time zone 'America/Bogota')::date)
                          || ' a las ' || private.a_las(v_cuando),
         siguiente_paso_en = greatest(private.hoy(), (v_cuando at time zone 'America/Bogota')::date)
   where id = v_op;
  return jsonb_build_object('oportunidad_id', v_op, 'cita_id', v_cita);
end $$;

-- V3 · El reporte después de la cita: unas marcas y cómo sigue. Devuelve la
-- próxima reunión que quedó agendada, si quedó una.
-- p_datos: {"llego":true,"grabacion":true,"transcripcion":"https://…",
--           "decisor_presente":true,"tiene_lote":"si","recurso_disponible":"0_3_meses","proposito":"vivienda",
--           "primera_cotizacion":true,"area":180,"valor":33000000,
--           "sigue":"cotizar|otra_cita|pensarlo|contrato|no_sigue",
--           "cuando":"2026-10-27T10:00","seguimiento":"2026-11-03","motivo":"precio","detalle":"…"}
create or replace function public.reporte_de_cita(p_cita uuid, p_datos jsonb) returns uuid
language plpgsql set search_path = '' as $$
declare
  v_yo     uuid := private.persona_actual();
  v_hoy    date := private.hoy();
  v_c      public.cita%rowtype;
  v_o      public.oportunidad%rowtype;
  v_sigue  text := nullif(p_datos ->> 'sigue', '');
  v_cuando timestamptz := private.hora_local(p_datos ->> 'cuando');
  v_valor  numeric := nullif(p_datos ->> 'valor', '')::numeric;
  v_area   numeric := nullif(p_datos ->> 'area', '')::numeric;
  v_nueva  uuid;
begin
  select * into v_c from public.cita c where c.id = p_cita;
  if not found then
    raise exception 'V3 · Esa cita no existe o no la puede ver';
  end if;
  if v_c.estado not in ('agendada','reprogramada') then
    raise exception 'V3 · Esa cita ya tiene su reporte';
  end if;
  select * into v_o from public.oportunidad o where o.id = v_c.oportunidad_id;

  if not coalesce((p_datos ->> 'llego')::boolean, true) then
    update public.cita set estado = 'no_show' where id = p_cita;
    update public.oportunidad set siguiente_paso = 'Reagendar la cita: el cliente no llegó', siguiente_paso_en = v_hoy
     where id = v_o.id;
    return null;
  end if;

  if v_sigue is null or v_sigue not in ('cotizar','otra_cita','pensarlo','contrato','no_sigue') then
    raise exception 'V3 · Falta decir cómo sigue: cotizar, otra reunión, lo va a pensar, firma o no sigue';
  end if;

  update public.cita
     set estado = 'realizada',
         consentimiento_grabacion = coalesce((p_datos ->> 'grabacion')::boolean, false),
         transcripcion_url = nullif(trim(p_datos ->> 'transcripcion'), '')
   where id = p_cita;

  if v_c.tipo = 'viabilidad' then
    if v_sigue = 'cotizar' and (p_datos ->> 'decisor_presente' is null or nullif(p_datos ->> 'tiene_lote', '') is null
        or nullif(p_datos ->> 'recurso_disponible', '') is null or nullif(p_datos ->> 'proposito', '') is null) then
      raise exception 'V3 · Antes de cotizar va el reporte de la cita: si estaba quien decide, si tiene lote, cuándo tiene el recurso y para qué es';
    end if;
    insert into public.calificacion
      (oportunidad_id, cita_id, decisor_presente, tiene_lote, recurso_disponible, proposito,
       primera_cotizacion, area_inicial_m2, registrada_por)
    values
      (v_o.id, p_cita, (p_datos ->> 'decisor_presente')::boolean, nullif(p_datos ->> 'tiene_lote', ''),
       nullif(p_datos ->> 'recurso_disponible', ''), nullif(p_datos ->> 'proposito', ''),
       (p_datos ->> 'primera_cotizacion')::boolean, v_area, v_yo)
    on conflict (oportunidad_id) do update set
      cita_id = excluded.cita_id,
      decisor_presente = coalesce(excluded.decisor_presente, public.calificacion.decisor_presente),
      tiene_lote = coalesce(excluded.tiene_lote, public.calificacion.tiene_lote),
      recurso_disponible = coalesce(excluded.recurso_disponible, public.calificacion.recurso_disponible),
      proposito = coalesce(excluded.proposito, public.calificacion.proposito),
      primera_cotizacion = coalesce(excluded.primera_cotizacion, public.calificacion.primera_cotizacion),
      area_inicial_m2 = coalesce(excluded.area_inicial_m2, public.calificacion.area_inicial_m2),
      registrada_por = excluded.registrada_por,
      registrada_en = now();
  end if;

  if v_sigue = 'cotizar' then
    if v_cuando is null then
      raise exception 'V2 · Para cotizar, deje agendada la reunión de presentación de la cotización';
    end if;
    if v_cuando < now() then
      raise exception 'V2 · La presentación tiene que quedar para un momento que no ha pasado';
    end if;
    v_valor := coalesce(v_valor, nullif(v_o.valor_estimado, 0),
                        public.valor_sugerido(coalesce(v_o.unidad, 'diseno_arquitectonico'), v_area));
    if v_valor is null or v_valor <= 0 then
      raise exception 'V3 · Para cotizar hace falta el valor estimado (o el área, si dirección ya escribió las tarifas)';
    end if;
    insert into public.cita (oportunidad_id, programada_para, tipo, modalidad)
    values (v_o.id, v_cuando, 'presentacion', coalesce(nullif(p_datos ->> 'modalidad', ''), v_c.modalidad))
    returning id into v_nueva;
    update public.oportunidad
       set etapa = case when etapa = 'cita_viabilidad' then 'presupuesto_detallado'::public.etapa_oportunidad else etapa end,
           valor_estimado = v_valor,
           area_m2 = coalesce(v_area, area_m2),
           siguiente_paso = 'Preparar la cotización para presentarla el '
                            || private.dia_corto((v_cuando at time zone 'America/Bogota')::date) || ' a las ' || private.a_las(v_cuando),
           siguiente_paso_en = greatest(v_hoy, (v_cuando at time zone 'America/Bogota')::date - 1)
     where id = v_o.id;
  elsif v_sigue = 'otra_cita' then
    if v_cuando is null or v_cuando < now() then
      raise exception 'V3 · Falta el día y la hora de la próxima reunión';
    end if;
    insert into public.cita (oportunidad_id, programada_para, tipo, modalidad)
    values (v_o.id, v_cuando, 'seguimiento', coalesce(nullif(p_datos ->> 'modalidad', ''), v_c.modalidad))
    returning id into v_nueva;
    update public.oportunidad
       set siguiente_paso = 'Reunión el ' || private.dia_corto((v_cuando at time zone 'America/Bogota')::date) || ' a las ' || private.a_las(v_cuando),
           siguiente_paso_en = greatest(v_hoy, (v_cuando at time zone 'America/Bogota')::date)
     where id = v_o.id;
  elsif v_sigue = 'pensarlo' then
    if nullif(p_datos ->> 'seguimiento', '') is null then
      raise exception 'V1 · Si lo va a pensar, falta el día en que se le vuelve a llamar';
    end if;
    update public.oportunidad
       set siguiente_paso = 'Llamar para saber qué decidió', siguiente_paso_en = (p_datos ->> 'seguimiento')::date
     where id = v_o.id;
  elsif v_sigue = 'contrato' then
    update public.oportunidad
       set etapa = 'negociacion', valor_estimado = coalesce(v_valor, nullif(valor_estimado, 0)),
           siguiente_paso = 'Firmar el contrato y recibir el anticipo', siguiente_paso_en = v_hoy + 2
     where id = v_o.id;
  else
    if nullif(p_datos ->> 'motivo', '') is null then
      raise exception 'M4 · Si no sigue, falta el motivo: precio, tiempo, competencia, desapareció…';
    end if;
    update public.oportunidad
       set etapa = 'perdida', motivo_perdida = (p_datos ->> 'motivo')::public.motivo_perdida,
           detalle_perdida = nullif(trim(p_datos ->> 'detalle'), '')
     where id = v_o.id;
  end if;
  return v_nueva;
end $$;


-- ---------- Lo que se lee ----------

-- Qué hacer hoy, persona por persona. persona_id vacío: no tiene dueño todavía.
create or replace view public.v_ventas_hoy with (security_invoker = true) as
with par as (select p.intentos_contacto_max, p.dias_entre_intentos from public.parametro p where p.id),
intentos as (
  select c.lead_id,
         count(*) filter (where c.direccion = 'saliente' and not c.respondio
                            and c.fecha > coalesce(r.ultima, '-infinity')) as sin_respuesta,
         max(c.fecha) as ultimo
  from public.contacto_lead c
  left join lateral (select max(x.fecha) as ultima from public.contacto_lead x
                     where x.lead_id = c.lead_id and (x.respondio or x.direccion = 'entrante')) r on true
  group by c.lead_id
)
select l.asignado_a as persona_id, 1::smallint as orden, 'primer_contacto'::text as que,
       l.id as lead_id, null::uuid as oportunidad_id, null::uuid as cita_id,
       coalesce(l.nombre, l.telefono, l.correo) as nombre,
       'Escribió hace ' || private.hace(l.creado_en) || ' y nadie le ha respondido' as lectura,
       true as urgente
from public.lead l
where l.estado = 'nuevo' and l.primer_contacto_en is null
union all
select o.responsable_id, 2, 'reporte_cita', null, o.id, c.id, o.nombre,
       case c.tipo when 'presentacion' then 'La presentación de la cotización' when 'seguimiento' then 'La reunión' else 'La cita de viabilidad' end
         || ' fue el ' || private.dia_corto((c.programada_para at time zone 'America/Bogota')::date) || ' y falta su reporte',
       true
from public.cita c
join public.oportunidad o on o.id = c.oportunidad_id
where c.estado in ('agendada','reprogramada') and c.programada_para < now() - interval '1 hour'
  and o.etapa not in ('ganada','perdida')
union all
select o.responsable_id, 3, 'cita_hoy', null, o.id, c.id, o.nombre,
       case c.tipo when 'presentacion' then 'Presentación de la cotización' when 'seguimiento' then 'Reunión' else 'Cita de viabilidad' end
         || ' a las ' || private.a_las(c.programada_para),
       false
from public.cita c
join public.oportunidad o on o.id = c.oportunidad_id
where c.estado = 'agendada' and (c.programada_para at time zone 'America/Bogota')::date = private.hoy()
  and c.programada_para >= now() - interval '1 hour'
union all
select o.siguiente_paso_por, 4, 'siguiente_paso', null, o.id, null, o.nombre,
       o.siguiente_paso || case when o.siguiente_paso_en < private.hoy()
                               then ' · iba para el ' || private.dia_corto(o.siguiente_paso_en) else '' end,
       o.siguiente_paso_en < private.hoy()
from public.oportunidad o
where o.etapa not in ('ganada','perdida') and o.siguiente_paso_en <= private.hoy()
union all
select l.asignado_a, 5, 'intento', l.id, null, null, coalesce(l.nombre, l.telefono, l.correo),
       'Intento ' || (i.sin_respuesta + 1) || ' de ' || par.intentos_contacto_max
         || ': el anterior fue hace ' || private.hace(i.ultimo) || ' y no respondió',
       false
from public.lead l
join intentos i on i.lead_id = l.id
cross join par
where l.estado in ('contactado','calificado') and i.sin_respuesta > 0
  and i.sin_respuesta < par.intentos_contacto_max
  and i.ultimo < now() - make_interval(days => par.dias_entre_intentos)
  and not exists (select 1 from public.oportunidad o where o.lead_id = l.id)
union all
select o.responsable_id, 6, 'cotizacion_vence', null, o.id, null, o.nombre,
       'La cotización ' || z.numero || case when z.vence_en < private.hoy() then ' venció el ' else ' vence el ' end
         || private.dia_corto(z.vence_en) || ' y el cliente no ha respondido',
       z.vence_en < private.hoy()
from public.cotizacion z
join public.oportunidad o on o.id = z.oportunidad_id
where z.estado in ('emitida','vencida') and z.vence_en <= private.hoy() + 3
  and o.etapa not in ('ganada','perdida');

-- Dónde está cada oportunidad abierta, por línea y etapa.
create or replace view public.v_embudo_ventas with (security_invoker = true) as
select
  case when o.unidad in ('obra_propia','obra_colega') then 'obra'
       when o.unidad = 'peritaje' then 'peritaje'
       else 'diseno' end                                                         as linea,
  o.etapa,
  count(*)::integer                                                              as oportunidades,
  coalesce(sum(o.valor_estimado), 0)                                             as valor,
  (count(*) filter (where o.siguiente_paso_en < private.hoy()))::integer         as atrasadas,
  round(avg(private.hoy() - (o.etapa_desde at time zone 'America/Bogota')::date))::integer as dias_promedio
from public.oportunidad o
where o.etapa not in ('ganada','perdida')
group by 1, 2;

-- El ritmo de los últimos 90 días y lo que hace falta para la meta de diseño.
create or replace view public.v_ritmo_ventas with (security_invoker = true) as
with desde as (select private.hoy() - 90 as d),
citas as (
  select count(*) filter (where c.tipo = 'viabilidad' and c.estado = 'realizada')   as viabilidad,
         count(*) filter (where c.tipo = 'viabilidad' and c.estado = 'no_show')     as no_llegaron,
         count(*) filter (where c.tipo = 'presentacion' and c.estado = 'realizada') as presentaciones
  from public.cita c, desde
  where (c.programada_para at time zone 'America/Bogota')::date >= desde.d
),
ganadas as (
  select count(*) as ganadas, coalesce(sum(o.valor_estimado), 0) as valor
  from public.oportunidad o, desde
  where o.etapa = 'ganada' and (o.desenlace_en at time zone 'America/Bogota')::date >= desde.d
    and coalesce(o.unidad::text, 'diseno_arquitectonico') in ('diseno_arquitectonico','interiorismo','consultoria')
),
base as (
  select ci.viabilidad, ci.no_llegaron, ci.presentaciones, g.ganadas, g.valor, p.meta_ventas_diseno_mes,
         case when g.ganadas > 0 and ci.viabilidad > 0 then ci.viabilidad::numeric / g.ganadas end as citas_por_venta,
         case when g.ganadas > 0 then g.valor / g.ganadas end                                     as valor_por_venta
  from citas ci, ganadas g, public.parametro p
  where p.id
)
select
  b.viabilidad::integer      as citas_viabilidad,
  b.no_llegaron::integer     as no_llegaron,
  b.presentaciones::integer  as presentaciones,
  b.ganadas::integer         as ventas,
  b.valor                    as valor_ventas,
  round(b.viabilidad / 3.0, 1) as citas_por_mes,
  round(b.citas_por_venta, 1)  as citas_por_venta,
  case when b.meta_ventas_diseno_mes is not null and b.valor_por_venta > 0 and b.citas_por_venta is not null
       then ceil(b.meta_ventas_diseno_mes / b.valor_por_venta * b.citas_por_venta)::integer end as citas_para_la_meta,
  'En los últimos 90 días hubo '
    || case when b.viabilidad = 1 then 'una cita de viabilidad' else b.viabilidad || ' citas de viabilidad' end
    || case when b.no_llegaron > 0 then ' (y ' || b.no_llegaron || case when b.no_llegaron = 1 then ' no llegó)' else ' no llegaron)' end else '' end
    || ', ' || case when b.presentaciones = 1 then 'una presentación de cotización' else b.presentaciones || ' presentaciones de cotización' end
    || ' y ' || case when b.ganadas = 0 then 'ninguna venta de diseño'
                     when b.ganadas = 1 then 'una venta de diseño por ' || private.pesos(b.valor)
                     else b.ganadas || ' ventas de diseño por ' || private.pesos(b.valor) end
    || case when b.citas_por_venta is not null
            then ': una venta por cada ' || replace(round(b.citas_por_venta, 1)::text, '.', ',') || ' citas.'
            else '.' end
    || case when b.meta_ventas_diseno_mes is not null and b.valor_por_venta > 0 and b.citas_por_venta is not null
            then ' Para vender ' || private.pesos(b.meta_ventas_diseno_mes) || ' al mes hacen falta unas '
                 || ceil(b.meta_ventas_diseno_mes / b.valor_por_venta * b.citas_por_venta)::integer
                 || ' citas al mes; van ' || replace(round(b.viabilidad / 3.0, 1)::text, '.', ',') || '.'
            else '' end      as lectura
from base b;


-- ---------- La sesión dice si la persona vende ----------

create or replace function public.mi_sesion() returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'persona_id',   p.id,
    'nombre',       p.nombre,
    'rol',          p.rol,
    'es_direccion', (select private.es_direccion()),
    'asigna',       (select private.es_direccion()) or (select private.tiene_rol('{arquitecto}'::public.rol_persona[])),
    'dirige',       coalesce((select jsonb_agg(d) from private.proyectos_que_dirige() d), '[]'::jsonb),
    'revisa',       coalesce((select jsonb_agg(r) from private.proyectos_que_revisa() r), '[]'::jsonb),
    'registra',     coalesce((select jsonb_agg(g) from private.proyectos_registro() g), '[]'::jsonb),
    'vende',        (select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[]))
                    or exists (select 1 from public.oportunidad o
                               where o.etapa not in ('ganada','perdida')
                                 and (o.responsable_id = p.id or o.siguiente_paso_por = p.id)))
  from public.persona p
  where p.id = (select private.persona_actual())
$$;


-- ---------- Permisos ----------

revoke all on public.tarifa_diseno from anon, authenticated;
grant select, insert, update on public.tarifa_diseno to authenticated;
revoke all on public.v_ventas_hoy, public.v_embudo_ventas, public.v_ritmo_ventas from anon, authenticated;
grant select on public.v_ventas_hoy, public.v_embudo_ventas, public.v_ritmo_ventas to authenticated;
revoke all on all functions in schema public  from public, anon;
revoke all on all functions in schema private from public, anon;
revoke all on function
  private.ventas_oportunidad(), private.diseno_abre_obra(),
  private.ventas_cotizacion(), private.cotizacion_mueve_oportunidad()
from authenticated;
grant execute on function
  public.valor_sugerido(public.unidad_negocio, numeric),
  public.nuevo_contacto(jsonb),
  public.agendar_cita_de_lead(uuid, jsonb),
  public.reporte_de_cita(uuid, jsonb),
  public.mi_sesion(),
  private.hace(timestamptz), private.hora_local(text), private.a_las(timestamptz),
  private.dia_corto(date), private.tiene_presentacion(uuid)
to authenticated;
grant select, insert, update, delete on all tables in schema public to service_role;
grant execute on all functions in schema public to service_role;
grant execute on all functions in schema private to service_role;
