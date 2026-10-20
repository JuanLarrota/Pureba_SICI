-- =============================================================================
-- SICI · Sistema Integrado de Control Interno · ESA Arquitectura S.A.S.
-- Migración inicial para Supabase (Postgres 15 o superior)
--
-- Todo lo estructural del sistema, módulos M-00 a M-08:
--    0. Esquemas y utilidades
--    1. Tipos
--    2. M-00 Núcleo I       parámetros, personas, clientes, categorías, cuentas
--    3. M-05 Comercial      experimentos, campañas, pauta, leads, oportunidades, citas
--    4. M-00 Núcleo II      proyecto, centro de costo, accesos, auditoría, alertas
--    5. M-04 Diseño         fases, tareas, revisión, dedicación, entregables,
--                           complementarios, licencia, nomenclatura de elementos
--    6. M-06 Presupuestos   insumos, APU, presupuesto, capítulos, ítems, cronograma
--    7. M-01/M-03 Obra      caja menor, cambios, adicionales, bitácora, actas,
--                           movimientos, aprobación del cliente (M-08)
--    8. M-02 Reclamaciones  reclamación, historial y listas de chequeo
--    9. Evidencia
--   10. M-07 Finanzas       saldos, ingresos, extractos, partidas, cierre, estructura
--   11. Funciones de identidad (las usan las políticas de acceso)
--   12. Reglas de negocio y disparadores
--   13. Vistas
--   14. Alertas: reglas por defecto y generador
--   15. Cerrado por defecto: permisos por fila activos en todas las tablas
--
-- Las políticas de acceso van en las migraciones rls_*; los permisos de la API
-- en permisos_api; las fotos y documentos en almacenamiento.
--
-- Idempotente: se puede ejecutar dos veces seguidas sin error y sin duplicar
-- nada. Si una ejecución se corta, se vuelve a correr completa. Un cambio a
-- una tabla ya creada va en una migración nueva, nunca editando esta.
--
-- Convenciones:
--   · Todo nombre va calificado con su esquema (public., private.).
--   · Las funciones fijan search_path = '' (lo exige el asesor de Supabase).
--   · Las funciones que validan leen con los privilegios de su dueño: una
--     regla no puede dejar de ver una fila por los permisos de quien registra.
--   · «Sin sesión» significa editor SQL, carga de datos o tarea programada.
--     Las reglas de QUÉ se puede hacer aplican siempre; las de QUIÉN lo hace,
--     solo cuando hay un usuario de la aplicación.
-- =============================================================================


-- =============================================================================
-- 0. Esquemas y utilidades
-- =============================================================================

-- gen_random_uuid() es nativo desde Postgres 13: no hace falta ninguna extensión.

create schema if not exists private;
comment on schema private is
  'Funciones internas del SICI. No se expone por la API de Supabase: nada de aquí se puede llamar desde el navegador.';

-- Hoy en Colombia. El servidor de Supabase vive en UTC: a las 7 p. m. en
-- Pereira allá ya es mañana, y la bitácora quedaría con la fecha equivocada.
create or replace function private.hoy() returns date
language sql stable set search_path = '' as $$
  select (now() at time zone 'America/Bogota')::date
$$;

-- Pesos colombianos para leer: $2.000.000. Las alertas hablan como la empresa.
create or replace function private.pesos(p_valor numeric) returns text
language sql immutable set search_path = '' as $$
  select case
    when p_valor is null then null
    else case when p_valor < 0 then '-' else '' end || '$'
         || replace(to_char(abs(round(p_valor)), 'FM999,999,999,999,990'), ',', '.')
  end
$$;

-- Un texto que debería ser un uuid (la carpeta de una foto). Si no lo es,
-- devuelve null en vez de romper la consulta.
create or replace function private.uuid_seguro(p_texto text) returns uuid
language plpgsql immutable set search_path = '' as $$
begin
  return p_texto::uuid;
exception when others then
  return null;
end $$;


-- =============================================================================
-- 1. Tipos
-- "create type" no admite "if not exists": se protege con un bloque.
-- Para agregar un valor más adelante: alter type ... add value if not exists.
-- =============================================================================

-- ---------- Núcleo ----------
do $$ begin
  create type public.unidad_negocio as enum (
    'diseno_arquitectonico',
    'interiorismo',
    'consultoria',
    'obra_propia',        -- diseñamos y construimos
    'obra_colega',        -- construimos el diseño de otro
    'peritaje',           -- caracterización postsísmica y expediente de póliza
    'administracion'      -- estructura, no facturable
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tipo_proyecto as enum ('diseno','obra','consultoria','peritaje','interno');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_proyecto as enum ('prospecto','activo','pausado','terminado','cancelado');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.fase_proyecto as enum (
    'insight','anteproyecto','proyecto_final','licencia','presupuesto','obra','cierre'
  );
exception when duplicate_object then null; end $$;

-- 'sin_clasificar' existe para no inventar: el libro mayor no dice qué es un
-- tercero, solo en qué categoría se le pagó.
do $$ begin
  create type public.rol_persona as enum (
    'socio','director','arquitecto','practicante','residente','mercadeo','financiero',
    'contratista','proveedor','cliente','profesional_externo','aseguradora','abogado',
    'sin_clasificar'
  );
exception when duplicate_object then null; end $$;

-- 'cliente_recurrente' y 'asistente_ia' vienen de la propuesta de mercadeo y
-- ventas: el identificador de clic de Google no ve a quien llegó recomendado
-- ni a quien le preguntó a un asistente de IA qué arquitecto contratar.
do $$ begin
  create type public.canal_origen as enum (
    'google_ads','referido','cliente_recurrente','instagram_organico','meta_ads',
    'youtube','linkedin','web_organico','asistente_ia','whatsapp_directo','otro'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.nivel_acceso as enum ('lectura','registro','aprobacion','total');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tipo_cuenta as enum ('banco','efectivo','tarjeta_credito');
exception when duplicate_object then null; end $$;

-- ---------- Comercial ----------
do $$ begin
  create type public.estado_lead as enum
    ('nuevo','contactado','calificado','nutricion','descartado','convertido');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.medio_contacto as enum
    ('whatsapp','llamada','correo','formulario_web','presencial','otro');
exception when duplicate_object then null; end $$;

-- El orden importa: las reglas comparan etapas ("más allá de la cita").
-- Los nombres son los que ya usa el equipo de ventas.
do $$ begin
  create type public.etapa_oportunidad as enum
    ('cita_viabilidad','presupuesto_detallado','cotizacion_enviada','negociacion','ganada','perdida');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.motivo_perdida as enum
    ('precio','tiempo','competencia','desaparecio','sin_capacidad_pago','no_calificado','aplazado','otro');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_cita as enum ('agendada','realizada','no_show','reprogramada','cancelada');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_cotizacion as enum
    ('borrador','emitida','aceptada','rechazada','vencida','reemplazada');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_experimento as enum ('planeado','corriendo','cerrado');
exception when duplicate_object then null; end $$;

-- ---------- Diseño ----------
do $$ begin
  create type public.estado_fase as enum ('pendiente','en_curso','en_revision','cerrada');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_tarea as enum
    ('asignada','en_curso','en_revision','con_observaciones','terminada');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.bloque_dia as enum ('manana','tarde');
exception when duplicate_object then null; end $$;

-- O11 · Un pendiente de obra se abre, se ejecuta, se verifica y se cierra. El
-- descarte existe porque en obra hay cosas que dejan de tener sentido.
do $$ begin
  create type public.estado_pendiente as enum
    ('abierto','en_ejecucion','por_verificar','cerrado','descartado');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tipo_pendiente as enum ('ejecucion','tramite','revision','compra');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.prioridad_pendiente as enum ('normal','alta','bloqueante');
exception when duplicate_object then null; end $$;

-- D8 · Un objetivo es de la empresa, de un proyecto o de una persona.
do $$ begin
  create type public.ambito_objetivo as enum ('empresa','proyecto','persona');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_objetivo as enum ('en_curso','logrado','no_logrado','cancelado');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.especialidad as enum
    ('estructural','hidrosanitario','electrico','suelos','topografia','otro');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_complementario as enum
    ('por_contratar','contratado','en_curso','entregado','aprobado');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_radicacion as enum
    ('preparacion','radicada','con_observaciones','aprobada','negada');
exception when duplicate_object then null; end $$;

-- ---------- Presupuestos ----------
do $$ begin
  create type public.tipo_insumo as enum ('material','mano_obra','equipo','transporte','subcontrato');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_presupuesto as enum
    ('borrador','en_validacion','validado','emitido','aprobado_cliente','reemplazado');
exception when duplicate_object then null; end $$;

-- ---------- Obra ----------
do $$ begin
  create type public.estado_dinero as enum ('compromiso','causacion','pago');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.medio_pago as enum ('banco','efectivo','tarjeta','credito','no_aplica');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_aprobacion as enum ('no_requiere','pendiente','aprobado','rechazado');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.tipo_acta as enum ('cobro_cliente','pago_contratista');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.severidad as enum ('critico','alerta','informativo');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.canal_aviso as enum ('plataforma','correo','sms');
exception when duplicate_object then null; end $$;

-- ---------- Reclamaciones ----------
-- La cascada de cobro: la empresa asegurada cobra la póliza con los abogados,
-- y de ahí se le paga a los abogados y a ESA.
do $$ begin
  create type public.estado_reclamacion as enum (
    'en_expediente','conciliada','radicada','objetada','aprobada',
    'pagada_a_asegurado','pagada_a_abogados','pagada_a_esa','negada','desistida'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.ambito_chequeo as enum
    ('fase_diseno','radicacion_licencia','reclamacion','presupuesto');
exception when duplicate_object then null; end $$;

-- ---------- Finanzas ----------
-- Son los valores de CATEGORIA INGRESOS del libro mayor: líneas de servicio,
-- no canales.
do $$ begin
  create type public.linea_servicio as enum (
    'consultoria','arquitectura','obra_civil','interiorismo','peritaje',
    'otros_ingresos','traslado_entre_cuentas','credito_bancario'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.estado_aviso as enum ('pendiente','enviado','fallido','descartado');
exception when duplicate_object then null; end $$;


-- =============================================================================
-- 2. M-00 Núcleo I
-- =============================================================================

-- Parámetros de control. Una sola fila; se edita, no se duplica. Cambiar un
-- umbral no exige tocar código.
create table if not exists public.parametro (
  id                         boolean primary key default true,
  umbral_aprobacion          numeric(16,2) not null default 2000000,
  margen_meta_obra           numeric(5,4)  not null default 0.20,
  margen_meta_diseno         numeric(5,4)  not null default 0.45,
  imprevistos_minimo         numeric(5,4)  not null default 0.05,
  caja_minima                numeric(16,2) not null default 12000000,
  vigencia_cotizacion_dias   smallint      not null default 30,
  intentos_contacto_max      smallint      not null default 3,
  minutos_primera_respuesta  smallint      not null default 30,
  dias_sin_desenlace         smallint      not null default 21,
  horas_por_bloque           numeric(4,2)  not null default 4,
  dias_edicion_dedicacion    smallint      not null default 7,
  dias_legalizar_caja        smallint      not null default 15,
  dias_aviso_poliza          smallint      not null default 30,
  dias_pago_estimado         smallint      not null default 8,
  actualizado_en             timestamptz   not null default now(),
  constraint parametro_fila_unica check (id),
  constraint parametro_pct_sanos check (
    margen_meta_obra between 0 and 1 and margen_meta_diseno between 0 and 1
    and imprevistos_minimo between 0 and 1),
  constraint parametro_positivos check (
    umbral_aprobacion > 0 and caja_minima >= 0 and vigencia_cotizacion_dias > 0
    and intentos_contacto_max > 0 and horas_por_bloque > 0 and dias_edicion_dedicacion >= 0)
);
comment on table public.parametro is
  'Parámetros de control. Umbral de $2.000.000 y márgenes meta (obra 20%, diseño 45%) fijados por Felipe el 2026-08-28.';

insert into public.parametro (id) values (true) on conflict do nothing;

-- Personas. Internas y externas en la misma tabla: un contratista, un cliente
-- o una aseguradora también son personas, y algunos tendrán acceso al portal.
create table if not exists public.persona (
  id              uuid primary key default gen_random_uuid(),
  nombre          text not null,
  rol             public.rol_persona not null,
  documento       text,
  nit             text,
  correo          text,
  telefono        text,
  es_interno      boolean not null default false,
  auth_user_id    uuid unique references auth.users(id) on delete set null,
  horas_semana    numeric(5,2) not null default 0,   -- capacidad del equipo (D4)
  activo          boolean not null default true,
  notas           text,
  creado_en       timestamptz not null default now(),
  constraint persona_nombre_no_vacio check (length(trim(nombre)) > 0),
  constraint persona_horas_sanas check (horas_semana between 0 and 60)
);
create index if not exists persona_rol_activo on public.persona (rol) where activo;
create unique index if not exists persona_correo_unico on public.persona (lower(correo)) where correo is not null;
comment on column public.persona.auth_user_id is
  'Usuario de Supabase. Se enlaza solo cuando la persona confirma el correo que dirección registró en su ficha.';

create table if not exists public.cliente (
  id           uuid primary key default gen_random_uuid(),
  nombre       text not null,
  tipo         text not null default 'persona_natural' check (tipo in ('persona_natural','empresa')),
  nit          text,
  contacto_id  uuid references public.persona(id),
  telefono     text,
  correo       text,
  ciudad       text,
  creado_en    timestamptz not null default now()
);
create index if not exists cliente_contacto on public.cliente (contacto_id);

-- Categorías de costo: la columna CATEGORIA PAGOS del libro mayor, con los
-- nombres textuales. El sistema habla el idioma de la empresa.
create table if not exists public.categoria_costo (
  id                        smallint primary key generated always as identity,
  nombre                    text not null unique,
  tipo_gasto                text not null check (tipo_gasto in ('COSTOS OPERATIVOS','GASTOS ADMINISTRATIVOS')),
  es_directo                boolean not null default true,
  excluir_de_rentabilidad   boolean not null default false,
  orden                     smallint not null default 100,
  activo                    boolean not null default true
);
comment on column public.categoria_costo.excluir_de_rentabilidad is
  'F5 · Préstamos, movimientos de socios y traslados: pasan por la caja pero no son costo de ningún proyecto.';

create table if not exists public.cuenta (
  id          uuid primary key default gen_random_uuid(),
  nombre      text not null unique,
  tipo        public.tipo_cuenta not null,
  banco       text,
  ultimos4    text check (ultimos4 ~ '^[0-9]{4}$'),
  activa      boolean not null default true,
  creada_en   timestamptz not null default now()
);
comment on column public.cuenta.ultimos4 is 'Solo los últimos cuatro dígitos. El número completo no se guarda aquí.';


-- =============================================================================
-- 3. M-05 Comercial: mercadeo, ventas y CRM
-- Reemplaza Pipedrive. Controles M1 a M9 y las políticas del equipo de ventas.
-- =============================================================================

-- M7 · Cada estrategia se registra con hipótesis y métrica antes de arrancar.
create table if not exists public.experimento (
  id                  uuid primary key default gen_random_uuid(),
  nombre              text not null,
  hipotesis           text,
  metrica_exito       text,
  umbral_exito        text,
  inversion_prevista  numeric(16,2) not null default 0,
  estado              public.estado_experimento not null default 'planeado',
  inicio              date,
  fin                 date,
  resultado           text,
  aprendizaje         text,
  responsable_id      uuid references public.persona(id),
  creado_en           timestamptz not null default now(),
  constraint experimento_fechas check (fin is null or inicio is null or fin >= inicio)
);
create index if not exists experimento_responsable on public.experimento (responsable_id);

create table if not exists public.campana (
  id              uuid primary key default gen_random_uuid(),
  nombre          text not null,
  canal           public.canal_origen not null,
  plataforma      text check (plataforma in ('google_ads','meta','youtube','linkedin','otra')),
  id_externo      text,                       -- id de la campaña en la plataforma
  landing         text,
  experimento_id  uuid references public.experimento(id),
  inicio          date,
  fin             date,
  activa          boolean not null default true,
  creada_en       timestamptz not null default now(),
  unique (plataforma, id_externo)
);
create index if not exists campana_experimento on public.campana (experimento_id);

-- Inversión diaria o mensual por campaña. La llenan a mano o la importación
-- de Google Ads, Meta y YouTube (con la llave de servicio, nunca desde el navegador).
create table if not exists public.inversion_pauta (
  id             uuid primary key default gen_random_uuid(),
  campana_id     uuid not null references public.campana(id),
  fecha          date not null,
  valor          numeric(16,2) not null check (valor >= 0),
  impresiones    integer check (impresiones >= 0),
  clics          integer check (clics >= 0),
  conversiones   numeric(10,2),
  fuente         text not null default 'manual' check (fuente in ('manual','google_ads','meta','youtube')),
  importado_en   timestamptz not null default now(),
  unique (campana_id, fecha, fuente)
);

-- M1 · Ningún lead entra sin canal.
create table if not exists public.lead (
  id                    uuid primary key default gen_random_uuid(),
  creado_en             timestamptz not null default now(),
  canal                 public.canal_origen not null,
  campana_id            uuid references public.campana(id),
  como_nos_encontro     public.canal_origen,     -- lo que dice el cliente, no el clic
  gclid                 text,
  utm_source            text,
  utm_medium            text,
  utm_campaign          text,
  landing               text,
  nombre                text,
  telefono              text,
  telefono_normalizado  text,                    -- lo fija el disparador
  correo                text,
  ciudad                text,
  mensaje_inicial       text,
  estado                public.estado_lead not null default 'nuevo',
  motivo_descarte       text,
  puntaje               smallint check (puntaje between 0 and 100),
  asignado_a            uuid references public.persona(id),
  primer_contacto_en    timestamptz,
  reactivado_en         timestamptz,
  lead_previo_id        uuid references public.lead(id),
  referido_por          text,
  id_pipedrive          text unique,
  constraint lead_identificable check (nombre is not null or telefono is not null or correo is not null),
  constraint lead_descarte_con_motivo check (
    estado <> 'descartado' or length(trim(coalesce(motivo_descarte, ''))) > 0)
);
create index if not exists lead_campana on public.lead (campana_id);
create index if not exists lead_asignado on public.lead (asignado_a);
create index if not exists lead_previo on public.lead (lead_previo_id);
create index if not exists lead_telefono on public.lead (telefono_normalizado) where telefono_normalizado is not null;
create index if not exists lead_estado_fecha on public.lead (estado, creado_en desc);
comment on column public.lead.primer_contacto_en is
  'Tiempo de primera respuesta: la diferencia con creado_en. Barato de medir y de alto impacto.';

create table if not exists public.contacto_lead (
  id              uuid primary key default gen_random_uuid(),
  lead_id         uuid not null references public.lead(id),
  fecha           timestamptz not null default now(),
  medio           public.medio_contacto not null,
  direccion       text not null check (direccion in ('saliente','entrante')),
  respondio       boolean not null default false,
  nota            text,
  registrado_por  uuid references public.persona(id)
);
create index if not exists contacto_lead_lead on public.contacto_lead (lead_id, fecha desc);
create index if not exists contacto_lead_registrado on public.contacto_lead (registrado_por);
comment on table public.contacto_lead is
  'Regla de los tres intentos: tres salientes seguidos sin respuesta pasan el lead a nutrición; una respuesta lo reactiva.';

create table if not exists public.oportunidad (
  id                     uuid primary key default gen_random_uuid(),
  lead_id                uuid references public.lead(id),
  cliente_id             uuid references public.cliente(id),
  nombre                 text not null,
  unidad                 public.unidad_negocio,
  canal                  public.canal_origen not null,      -- M2 · viene del lead
  etapa                  public.etapa_oportunidad not null default 'cita_viabilidad',
  valor_estimado         numeric(16,2) check (valor_estimado >= 0),
  area_m2                numeric(10,2),
  ciudad                 text,
  responsable_id         uuid references public.persona(id),
  motivo_perdida         public.motivo_perdida,
  detalle_perdida        text,
  desenlace_en           timestamptz,                        -- M8
  conversion_enviada_en  timestamptz,                        -- valor enviado a Google Ads
  id_pipedrive           text unique,
  creada_en              timestamptz not null default now(),
  actualizada_en         timestamptz not null default now()
);
create index if not exists oportunidad_lead on public.oportunidad (lead_id);
create index if not exists oportunidad_cliente on public.oportunidad (cliente_id);
create index if not exists oportunidad_responsable on public.oportunidad (responsable_id);
create index if not exists oportunidad_abiertas on public.oportunidad (etapa) where etapa not in ('ganada','perdida');

-- M5 · Ficha de calificación: sale del guion de Felipe en sus propias citas.
create table if not exists public.calificacion (
  id                     uuid primary key default gen_random_uuid(),
  oportunidad_id         uuid not null unique references public.oportunidad(id),
  tiene_lote             text check (tiene_lote in ('si','no','en_proceso')),
  conoce_techo           boolean,
  techo_presupuestal     numeric(16,2),
  recurso_disponible     text check (recurso_disponible in ('inmediato','0_3_meses','3_12_meses','mas_12_meses','no_sabe')),
  proposito              text check (proposito in ('vivienda','inversion','mixto','comercial')),
  primera_cotizacion     boolean,
  decisores              smallint check (decisores >= 1),
  area_inicial_m2        numeric(10,2),
  area_reencuadrada_m2   numeric(10,2),
  reaccion_costo         text check (reaccion_costo in ('positiva','dudosa','negativa')),
  registrada_por         uuid references public.persona(id),
  registrada_en          timestamptz not null default now()
);
create index if not exists calificacion_registrada_por on public.calificacion (registrada_por);

-- M9 · La cita es un estado, no un archivo de grabación.
create table if not exists public.cita (
  id                        uuid primary key default gen_random_uuid(),
  oportunidad_id            uuid not null references public.oportunidad(id),
  programada_para           timestamptz not null,
  modalidad                 text not null default 'videollamada'
                            check (modalidad in ('presencial','videollamada','llamada')),
  estado                    public.estado_cita not null default 'agendada',
  consentimiento_grabacion  boolean,      -- Ley 1581 de 2012
  grabacion_url             text,
  realizada_en              timestamptz,
  duracion_min              smallint check (duracion_min >= 0),
  reprogramada_a            uuid references public.cita(id),
  notas                     text,
  creada_en                 timestamptz not null default now()
);
create index if not exists cita_oportunidad on public.cita (oportunidad_id);
create index if not exists cita_reprogramada on public.cita (reprogramada_a);
create index if not exists cita_agenda on public.cita (programada_para) where estado = 'agendada';


-- =============================================================================
-- 4. M-00 Núcleo II
-- =============================================================================

-- Proyecto: la columna CENTROS DE COSTOS del libro mayor, que en realidad
-- nombra proyectos (OBRA NIRVANA, CASA GO, ADMINISTRACION...).
create table if not exists public.proyecto (
  id                 uuid primary key default gen_random_uuid(),
  codigo             text not null unique,        -- 'OBRA NIRVANA', tal como en el Excel
  nombre             text not null,
  unidad             public.unidad_negocio not null,
  tipo               public.tipo_proyecto not null,
  estado             public.estado_proyecto not null default 'activo',
  fase               public.fase_proyecto,        -- fase en curso; la mueve M-04
  cliente_id         uuid references public.cliente(id),
  oportunidad_id     uuid references public.oportunidad(id),
  responsable_id     uuid references public.persona(id),
  residente_id       uuid references public.persona(id),
  canal              public.canal_origen,         -- M2 · viaja del lead hasta el margen
  valor_contrato     numeric(16,2),
  pct_administracion numeric(5,4) default 0.10,
  pct_utilidad       numeric(5,4) default 0.04,
  pct_imprevistos    numeric(5,4) default 0.00,
  area_m2            numeric(10,2),
  ciudad             text,
  fecha_inicio       date,
  fecha_fin_prevista date,
  es_reclamacion     boolean not null default false,
  creado_en          timestamptz not null default now(),
  constraint proyecto_pct_sanos check (
    coalesce(pct_administracion,0) between 0 and 1
    and coalesce(pct_utilidad,0) between 0 and 1
    and coalesce(pct_imprevistos,0) between 0 and 1)
);
create index if not exists proyecto_activos on public.proyecto (estado) where estado = 'activo';
create index if not exists proyecto_unidad on public.proyecto (unidad);
create index if not exists proyecto_canal on public.proyecto (canal) where canal is not null;
create index if not exists proyecto_cliente on public.proyecto (cliente_id);
create index if not exists proyecto_oportunidad on public.proyecto (oportunidad_id);
create index if not exists proyecto_responsable on public.proyecto (responsable_id);
create index if not exists proyecto_residente on public.proyecto (residente_id);
comment on column public.proyecto.pct_imprevistos is
  'Nirvana se contrató con 0%: toda sorpresa se volvió adicional. Ver control O8.';

-- Centro de costo = proyecto × categoría. El cruce que en el Excel es
-- implícito y aquí es explícito: donde vive el presupuesto y el control.
create table if not exists public.centro_costo (
  id            uuid primary key default gen_random_uuid(),
  proyecto_id   uuid not null references public.proyecto(id),
  categoria_id  smallint not null references public.categoria_costo(id),
  presupuesto   numeric(16,2) not null default 0,
  activo        boolean not null default true,
  unique (proyecto_id, categoria_id)
);
create index if not exists centro_costo_categoria on public.centro_costo (categoria_id);

-- Qué proyectos ve cada persona. Socios, directores y finanzas ven todo por su
-- rol; los demás, solo lo asignado aquí. Un cliente o contratista con acceso
-- entra por el portal y ve mucho menos.
create table if not exists public.acceso_proyecto (
  persona_id   uuid not null references public.persona(id),
  proyecto_id  uuid not null references public.proyecto(id),
  nivel        public.nivel_acceso not null default 'registro',
  otorgado_en  timestamptz not null default now(),
  primary key (persona_id, proyecto_id)
);
create index if not exists acceso_proyecto_proyecto on public.acceso_proyecto (proyecto_id);

-- T3 · Nada se borra, todo deja rastro.
create table if not exists public.evento_auditoria (
  id          bigint primary key generated always as identity,
  tabla       text not null,
  fila_id     text not null,
  operacion   text not null check (operacion in ('INSERT','UPDATE','DELETE')),
  actor       uuid,          -- usuario de Supabase; null si fue una carga o tarea
  persona_id  uuid,          -- su ficha, si la tiene
  antes       jsonb,
  despues     jsonb,
  ocurrio_en  timestamptz not null default now()
);
create index if not exists evento_auditoria_fila on public.evento_auditoria (tabla, fila_id);
create index if not exists evento_auditoria_fecha on public.evento_auditoria (ocurrio_en desc);

-- F8 · Cada tipo de alerta sabe a quién le llega. Nunca "a todos".
create table if not exists public.regla_alerta (
  tipo                  text primary key,
  descripcion           text not null,
  severidad             public.severidad not null default 'alerta',
  roles                 public.rol_persona[] not null default '{}',
  incluir_residente     boolean not null default false,
  incluir_responsable   boolean not null default false,
  canales               public.canal_aviso[] not null default '{plataforma}',
  activa                boolean not null default true
);

create table if not exists public.alerta (
  id            uuid primary key default gen_random_uuid(),
  tipo          text not null,
  clave         text,                         -- evita repetir la misma alerta abierta
  severidad     public.severidad not null default 'alerta',
  proyecto_id   uuid references public.proyecto(id),
  titulo        text not null,
  detalle       text,
  destinatarios uuid[] not null,
  canales       public.canal_aviso[] not null default '{plataforma}',
  resuelta      boolean not null default false,
  resuelta_por  uuid references public.persona(id),
  resuelta_en   timestamptz,
  creada_en     timestamptz not null default now(),
  constraint alerta_con_destinatario check (cardinality(destinatarios) >= 1)
);
create index if not exists alerta_abiertas on public.alerta (resuelta, severidad) where not resuelta;
create index if not exists alerta_proyecto on public.alerta (proyecto_id);
create index if not exists alerta_resuelta_por on public.alerta (resuelta_por);
create index if not exists alerta_destinatarios on public.alerta using gin (destinatarios);
create unique index if not exists alerta_clave_abierta on public.alerta (clave) where not resuelta;

-- Bandeja de salida de correo y mensaje de texto. La lee una función de
-- Supabase con la llave de servicio y marca cada envío.
create table if not exists public.aviso (
  id          uuid primary key default gen_random_uuid(),
  alerta_id   uuid not null references public.alerta(id),
  persona_id  uuid not null references public.persona(id),
  canal       public.canal_aviso not null check (canal <> 'plataforma'),
  estado      public.estado_aviso not null default 'pendiente',
  intentos    smallint not null default 0,
  enviado_en  timestamptz,
  error       text,
  creado_en   timestamptz not null default now(),
  unique (alerta_id, persona_id, canal)
);
create index if not exists aviso_persona on public.aviso (persona_id);
create index if not exists aviso_pendientes on public.aviso (creado_en) where estado = 'pendiente';

-- M6 · Toda cotización tiene vencimiento y estado. O10 · margen bajo la meta
-- no se emite sin autorización de un socio.
create table if not exists public.cotizacion (
  id                     uuid primary key default gen_random_uuid(),
  oportunidad_id         uuid references public.oportunidad(id),
  proyecto_id            uuid references public.proyecto(id),
  numero                 text not null,
  version                smallint not null default 1,
  tipo                   public.tipo_proyecto not null check (tipo <> 'interno'),
  unidad                 public.unidad_negocio,
  valor                  numeric(16,2) not null check (valor > 0),
  costo_estimado         numeric(16,2) check (costo_estimado >= 0),
  horas_estimadas        numeric(8,2) check (horas_estimadas >= 0),
  estado                 public.estado_cotizacion not null default 'borrador',
  emitida_en             date,
  vence_en               date,
  respondida_en          date,
  margen_autorizado_por  uuid references public.persona(id),
  margen_autorizado_en   timestamptz,
  ruta_documento         text,
  creada_en              timestamptz not null default now(),
  unique (numero, version),
  constraint cotizacion_de_algo check (oportunidad_id is not null or proyecto_id is not null)
);
create index if not exists cotizacion_oportunidad on public.cotizacion (oportunidad_id);
create index if not exists cotizacion_proyecto on public.cotizacion (proyecto_id);
create index if not exists cotizacion_autorizada_por on public.cotizacion (margen_autorizado_por);
create index if not exists cotizacion_por_vencer on public.cotizacion (vence_en) where estado = 'emitida';


-- D8 · Objetivos. Una lista de tareas no dice para qué son. El objetivo las
-- agrupa y se mide contándolas: nadie escribe un porcentaje ni una narración.
create table if not exists public.objetivo (
  id             uuid primary key default gen_random_uuid(),
  ambito         public.ambito_objetivo not null,
  proyecto_id    uuid references public.proyecto(id),
  persona_id     uuid references public.persona(id),
  titulo         text not null,
  fecha_limite   date not null,
  responsable_id uuid not null references public.persona(id),
  estado         public.estado_objetivo not null default 'en_curso',
  cerrado_en     timestamptz,
  cerrado_por    uuid references public.persona(id),
  creado_en      timestamptz not null default now(),
  creado_por     uuid not null references public.persona(id),
  constraint objetivo_ambito_coherente check (
    (ambito = 'proyecto') = (proyecto_id is not null)
    and (ambito = 'persona') = (persona_id is not null)),
  constraint objetivo_cierre_completo check ((cerrado_en is null) = (cerrado_por is null)),
  constraint objetivo_cerrado_con_fecha check (estado = 'en_curso' or cerrado_en is not null),
  constraint objetivo_titulo_escrito check (length(trim(titulo)) >= 8)
);
create index if not exists objetivo_proyecto on public.objetivo (proyecto_id);
create index if not exists objetivo_persona on public.objetivo (persona_id);
create index if not exists objetivo_responsable on public.objetivo (responsable_id);
create index if not exists objetivo_cerrado_por on public.objetivo (cerrado_por);
create index if not exists objetivo_creado_por on public.objetivo (creado_por);
create index if not exists objetivo_en_curso on public.objetivo (fecha_limite) where estado = 'en_curso';
comment on table public.objetivo is
  'El avance sale de contar las tareas y los pendientes colgados del objetivo. No hay columna de porcentaje porque nadie la llenaría bien.';

-- =============================================================================
-- 5. M-04 Diseño y producción arquitectónica
-- La fase la gobiernan Felipe y Luisa; la tarea la vive el equipo; el registro
-- sale de la tarea sin pedirle a nadie que traduzca. Controles D1 a D7.
-- =============================================================================

-- D1 · Cada fase del proyecto, con horas cotizadas y compuerta de cierre.
create table if not exists public.proyecto_fase (
  id                      uuid primary key default gen_random_uuid(),
  proyecto_id             uuid not null references public.proyecto(id),
  fase                    public.fase_proyecto not null,
  orden                   smallint not null,
  estado                  public.estado_fase not null default 'pendiente',
  horas_cotizadas         numeric(8,2) not null default 0 check (horas_cotizadas >= 0),
  fecha_inicio            date,
  fecha_compromiso        date,
  aprobada_cliente_en     date,
  aprobada_cliente_texto  text,       -- quién aprobó del lado del cliente y por qué medio
  cerrada_en              timestamptz,
  cerrada_por             uuid references public.persona(id),
  creada_en               timestamptz not null default now(),
  unique (proyecto_id, fase),
  unique (proyecto_id, orden),
  constraint fase_cierre_completo check ((cerrada_en is null) = (cerrada_por is null)),
  constraint fase_cerrada_con_fecha check (estado <> 'cerrada' or cerrada_en is not null),
  constraint fase_aprobacion_completa check (
    (aprobada_cliente_en is null) = (aprobada_cliente_texto is null))
);
create index if not exists proyecto_fase_cerrada_por on public.proyecto_fase (cerrada_por);

-- La nomenclatura del estudio (M-05, M-06, P01...). Es la llave natural entre
-- lo que diseña el estudio y lo que presupuesta y cobra la obra.
create table if not exists public.elemento_diseno (
  id              uuid primary key default gen_random_uuid(),
  proyecto_id     uuid not null references public.proyecto(id),
  codigo          text not null,
  nombre          text not null,
  tipo            text not null default 'mobiliario'
                  check (tipo in ('mobiliario','puerta','ventana','acabado','equipo','otro')),
  especificacion  text,
  creado_en       timestamptz not null default now(),
  unique (proyecto_id, codigo)
);

create table if not exists public.tarea_diseno (
  id                uuid primary key default gen_random_uuid(),
  proyecto_id       uuid not null references public.proyecto(id),
  fase_id           uuid references public.proyecto_fase(id),
  titulo            text not null,
  descripcion       text,
  asignada_a        uuid not null references public.persona(id),
  asignada_por      uuid not null references public.persona(id),
  objetivo_id       uuid references public.objetivo(id),
  bloqueada_por     uuid references public.tarea_diseno(id),
  estado            public.estado_tarea not null default 'asignada',
  fecha_inicio      date,
  fecha_compromiso  date,
  terminada_en      timestamptz,
  creada_en         timestamptz not null default now(),
  -- En el Excel había cuatro tareas que empezaban después de su fecha de
  -- entrega, y la columna de duración decía menos veintisiete días.
  constraint tarea_fechas_en_orden check (
    fecha_inicio is null or fecha_compromiso is null or fecha_compromiso >= fecha_inicio),
  constraint tarea_no_se_bloquea_sola check (bloqueada_por is distinct from id)
);
create index if not exists tarea_diseno_proyecto on public.tarea_diseno (proyecto_id);
create index if not exists tarea_diseno_fase on public.tarea_diseno (fase_id);
create index if not exists tarea_diseno_asignada_a on public.tarea_diseno (asignada_a) where estado <> 'terminada';
create index if not exists tarea_diseno_asignada_por on public.tarea_diseno (asignada_por);
create index if not exists tarea_diseno_objetivo on public.tarea_diseno (objetivo_id);
create index if not exists tarea_diseno_bloqueada_por on public.tarea_diseno (bloqueada_por);
create index if not exists tarea_diseno_compromiso on public.tarea_diseno (fecha_compromiso)
  where estado <> 'terminada';

-- La revisión del jefe de diseño: el único control formal del proceso escrito
-- por el equipo (actividad 23). La hace alguien distinto de quien hizo la tarea.
create table if not exists public.revision_diseno (
  id             uuid primary key default gen_random_uuid(),
  tarea_id       uuid not null references public.tarea_diseno(id),
  revisor_id     uuid not null references public.persona(id),
  resultado      text not null check (resultado in ('aprobada','con_observaciones')),
  observaciones  text,
  revisada_en    timestamptz not null default now(),
  constraint revision_observaciones_escritas check (
    resultado = 'aprobada' or length(trim(coalesce(observaciones, ''))) > 0)
);
create index if not exists revision_diseno_tarea on public.revision_diseno (tarea_id);
create index if not exists revision_diseno_revisor on public.revision_diseno (revisor_id);

-- D2 · Dedicación. Asignar, nunca narrar: medio día a un proyecto, sin texto.
-- Ya falló tres veces pidiendo prosa; aquí no hay un solo campo de texto.
create table if not exists public.dedicacion (
  id             uuid primary key default gen_random_uuid(),
  persona_id     uuid not null references public.persona(id),
  fecha          date not null,
  bloque         public.bloque_dia not null,
  tipo           text not null default 'proyecto' check (tipo in ('proyecto','estructura','ausencia')),
  proyecto_id    uuid references public.proyecto(id),
  fase_id        uuid references public.proyecto_fase(id),
  tarea_id       uuid references public.tarea_diseno(id),
  horas          numeric(4,2) not null check (horas > 0 and horas <= 12),
  registrada_en  timestamptz not null default now(),
  unique (persona_id, fecha, bloque),
  constraint dedicacion_proyecto_coherente check ((tipo = 'proyecto') = (proyecto_id is not null))
);
create index if not exists dedicacion_proyecto_fecha on public.dedicacion (proyecto_id, fecha);
create index if not exists dedicacion_fase on public.dedicacion (fase_id);
create index if not exists dedicacion_tarea on public.dedicacion (tarea_id);
create index if not exists dedicacion_fecha on public.dedicacion (fecha);
comment on table public.dedicacion is
  'Un registro por persona, día y bloque (mañana o tarde). Las horas salen de parametro.horas_por_bloque. Ausencias y trabajo de estructura también cuentan como día registrado.';

-- D5 · Cada entrega al cliente con versión, fecha y qué se entregó.
create table if not exists public.entregable (
  id                   uuid primary key default gen_random_uuid(),
  proyecto_id          uuid not null references public.proyecto(id),
  fase_id              uuid references public.proyecto_fase(id),
  nombre               text not null,
  version              smallint not null default 0,     -- la fija el disparador
  descripcion          text,
  entregado_en         date not null default ((now() at time zone 'America/Bogota')::date),
  entregado_a          text,
  aprobado_cliente_en  date,
  aprobado_por_texto   text,
  registrado_por       uuid not null references public.persona(id),
  creado_en            timestamptz not null default now(),
  unique (proyecto_id, nombre, version)
);
create index if not exists entregable_fase on public.entregable (fase_id);
create index if not exists entregable_registrado_por on public.entregable (registrado_por);

-- Los cuatro formatos de una misma versión (.dwg, .skp, .layout, .pdf).
create table if not exists public.entregable_archivo (
  id             uuid primary key default gen_random_uuid(),
  entregable_id  uuid not null references public.entregable(id),
  formato        text not null check (formato in ('dwg','skp','layout','pdf','xlsx','docx','otro')),
  ruta           text not null,        -- enlace de Drive o ruta en el almacenamiento
  unique (entregable_id, formato, ruta)
);

-- D6 · Estructural, hidrosanitario, eléctrico, suelos y topografía. ESA los
-- contrata cuando van en los honorarios: son costo del proyecto.
create table if not exists public.complementario (
  id                uuid primary key default gen_random_uuid(),
  proyecto_id       uuid not null references public.proyecto(id),
  especialidad      public.especialidad not null,
  profesional_id    uuid references public.persona(id),
  valor_contratado  numeric(16,2) check (valor_contratado >= 0),
  pct_anticipo      numeric(5,4) not null default 0.50 check (pct_anticipo between 0 and 1),
  fecha_compromiso  date,
  entregado_en      date,
  estado            public.estado_complementario not null default 'por_contratar',
  notas             text,
  creado_en         timestamptz not null default now()
);
create index if not exists complementario_proyecto on public.complementario (proyecto_id);
create index if not exists complementario_profesional on public.complementario (profesional_id);

-- D7 · Radicación ante curaduría, con lo que devolvieron: la lista mejora con
-- cada radicación.
create table if not exists public.radicacion_licencia (
  id               uuid primary key default gen_random_uuid(),
  proyecto_id      uuid not null references public.proyecto(id),
  curaduria        text not null,
  municipio        text not null,
  estado           public.estado_radicacion not null default 'preparacion',
  numero_radicado  text,
  radicada_en      date,
  observaciones    text,
  resuelta_en      date,
  creada_en        timestamptz not null default now()
);
create index if not exists radicacion_licencia_proyecto on public.radicacion_licencia (proyecto_id);


-- =============================================================================
-- 6. M-06 Presupuestos, APU y cronograma
-- La verdad vive en la base; el Excel y el PDF se generan desde aquí.
-- =============================================================================

create table if not exists public.insumo (
  id              uuid primary key default gen_random_uuid(),
  codigo          text unique,
  descripcion     text not null,
  unidad          text not null,
  tipo            public.tipo_insumo not null,
  precio          numeric(16,2) not null default 0 check (precio >= 0),
  proveedor_id    uuid references public.persona(id),
  actualizado_en  timestamptz not null default now(),
  activo          boolean not null default true
);
create index if not exists insumo_proveedor on public.insumo (proveedor_id);

create table if not exists public.apu (
  id              uuid primary key default gen_random_uuid(),
  codigo          text not null unique,
  descripcion     text not null,
  unidad          text not null,
  notas           text,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now()
);

create table if not exists public.apu_componente (
  id           uuid primary key default gen_random_uuid(),
  apu_id       uuid not null references public.apu(id),
  insumo_id    uuid not null references public.insumo(id),
  cantidad     numeric(14,6) not null check (cantidad > 0),   -- por unidad del APU
  desperdicio  numeric(5,4) not null default 0 check (desperdicio between 0 and 1),
  unique (apu_id, insumo_id)
);
create index if not exists apu_componente_insumo on public.apu_componente (insumo_id);

create table if not exists public.presupuesto (
  id                         uuid primary key default gen_random_uuid(),
  proyecto_id                uuid not null references public.proyecto(id),
  version                    smallint not null default 1,
  vigente                    boolean not null default true,
  estado                     public.estado_presupuesto not null default 'borrador',
  elaborado_por              uuid references public.persona(id),
  validado_por               uuid references public.persona(id),    -- validación profesional
  validado_en                timestamptz,
  aprobado_por               uuid references public.persona(id),
  aprobado_en                timestamptz,
  justificacion_imprevistos  text,                                  -- O8
  margen_autorizado_por      uuid references public.persona(id),    -- O10
  margen_autorizado_en       timestamptz,
  notas                      text,
  creado_en                  timestamptz not null default now(),
  unique (proyecto_id, version)
);
create unique index if not exists presupuesto_uno_vigente on public.presupuesto (proyecto_id) where vigente;
create index if not exists presupuesto_elaborado_por on public.presupuesto (elaborado_por);
create index if not exists presupuesto_validado_por on public.presupuesto (validado_por);
create index if not exists presupuesto_aprobado_por on public.presupuesto (aprobado_por);
create index if not exists presupuesto_margen_autorizado_por on public.presupuesto (margen_autorizado_por);

create table if not exists public.capitulo (
  id              uuid primary key default gen_random_uuid(),
  presupuesto_id  uuid not null references public.presupuesto(id),
  codigo          text not null,
  nombre          text not null,
  orden           smallint not null default 100,
  unique (presupuesto_id, codigo)
);

create table if not exists public.item_presupuesto (
  id             uuid primary key default gen_random_uuid(),
  capitulo_id    uuid not null references public.capitulo(id),
  codigo         text not null,
  descripcion    text not null,
  unidad         text,
  cantidad       numeric(14,4) not null default 0,
  valor_unitario numeric(16,2) not null default 0,
  valor_parcial  numeric(16,2) generated always as (round(cantidad * valor_unitario, 2)) stored,
  apu_id         uuid references public.apu(id),
  elemento_id    uuid references public.elemento_diseno(id),
  unique (capitulo_id, codigo)
);
create index if not exists item_presupuesto_apu on public.item_presupuesto (apu_id);
create index if not exists item_presupuesto_elemento on public.item_presupuesto (elemento_id);

-- Espejo de las columnas H, I y K del balance de obra.
create table if not exists public.ejecucion_item (
  id                  uuid primary key default gen_random_uuid(),
  item_id             uuid not null unique references public.item_presupuesto(id),
  cantidad_proyectada numeric(14,4) not null default 0,
  valor_proyectado    numeric(16,2) not null default 0,
  pct_avance          numeric(5,4)  not null default 0,
  valor_avance        numeric(16,2) generated always as (round(valor_proyectado * pct_avance, 2)) stored,
  memoria_cantidades  text,                                     -- O5
  actualizado_por     uuid references public.persona(id),
  actualizado_en      timestamptz not null default now(),
  constraint ejecucion_pct check (pct_avance between 0 and 1)
);
create index if not exists ejecucion_item_actualizado_por on public.ejecucion_item (actualizado_por);
comment on table public.ejecucion_item is
  'Cantidad y valor TOTAL a ejecutar según la revisión de cantidades (no lo ejecutado a la fecha) y porcentaje de avance. Lo ejecutado es cantidad_proyectada × pct_avance. Un ítem con valor_proyectado = 0 es obra que ya no se hará: crédito al cliente.';

-- El cronograma como reflejo del presupuesto.
create table if not exists public.actividad_cronograma (
  id              uuid primary key default gen_random_uuid(),
  presupuesto_id  uuid not null references public.presupuesto(id),
  capitulo_id     uuid references public.capitulo(id),
  nombre          text not null,
  inicio          date not null,
  fin             date not null,
  predecesora_id  uuid references public.actividad_cronograma(id),
  pct_avance      numeric(5,4) not null default 0 check (pct_avance between 0 and 1),
  orden           smallint not null default 100,
  constraint cronograma_fechas check (fin >= inicio)
);
create index if not exists actividad_cronograma_presupuesto on public.actividad_cronograma (presupuesto_id);
create index if not exists actividad_cronograma_capitulo on public.actividad_cronograma (capitulo_id);
create index if not exists actividad_cronograma_predecesora on public.actividad_cronograma (predecesora_id);


-- =============================================================================
-- 7. M-01 y M-03 Obra: gasto, caja menor, adicionales, bitácora y actas
-- =============================================================================

-- Caja menor. Del proceso del residente: «fondo de efectivo suministrado por
-- Luisa para gastos menores, imprevistos y logística diaria». No se entrega un
-- fondo nuevo sin legalizar el anterior, y quien entrega no gasta ni legaliza.
create table if not exists public.fondo_caja (
  id              uuid primary key default gen_random_uuid(),
  responsable_id  uuid not null references public.persona(id),
  entregado_por   uuid not null references public.persona(id),
  valor           numeric(16,2) not null,
  fecha_entrega   date not null default ((now() at time zone 'America/Bogota')::date),
  legalizado_en   date,
  legalizado_por  uuid references public.persona(id),
  notas           text,
  creado_en       timestamptz not null default now(),
  constraint fondo_valor_positivo check (valor > 0),
  constraint fondo_segregacion check (responsable_id <> entregado_por),
  constraint fondo_legalizacion_completa check ((legalizado_en is null) = (legalizado_por is null)),
  constraint fondo_legaliza_otro check (legalizado_por is null or legalizado_por <> responsable_id)
);
create unique index if not exists fondo_caja_uno_abierto on public.fondo_caja (responsable_id)
  where legalizado_en is null;
create index if not exists fondo_caja_responsable on public.fondo_caja (responsable_id);
create index if not exists fondo_caja_entregado_por on public.fondo_caja (entregado_por);
create index if not exists fondo_caja_legalizado_por on public.fondo_caja (legalizado_por);

-- Cambios decididos en obra. Quedan abiertos hasta que diseño confirma que los
-- incorporó al modelo 3D o a la planimetría.
create table if not exists public.cambio_obra (
  id                      uuid primary key default gen_random_uuid(),
  proyecto_id             uuid not null references public.proyecto(id),
  fecha                   date not null default ((now() at time zone 'America/Bogota')::date),
  descripcion             text not null,
  motivo                  text,
  decidido_por            uuid not null references public.persona(id),
  altera_diseno           boolean not null default false,
  reflejado_en_diseno_en  date,
  reflejado_por           uuid references public.persona(id),
  genera_adicional        boolean not null default false,
  creado_en               timestamptz not null default now(),
  constraint cambio_descripcion check (length(trim(descripcion)) > 0),
  constraint cambio_reflejo_completo check ((reflejado_en_diseno_en is null) = (reflejado_por is null))
);
create index if not exists cambio_obra_sin_reflejar on public.cambio_obra (proyecto_id)
  where altera_diseno and reflejado_en_diseno_en is null;
create index if not exists cambio_obra_decidido_por on public.cambio_obra (decidido_por);
create index if not exists cambio_obra_reflejado_por on public.cambio_obra (reflejado_por);

-- O1 · Ningún adicional sin estado de aprobación del CLIENTE.
-- O2 · Lo que paga el cliente y lo que absorbe ESA, en cubetas separadas.
-- O9 · Si reemplaza un ítem del contrato, el crédito es automático.
create table if not exists public.adicional (
  id                 uuid primary key default gen_random_uuid(),
  proyecto_id        uuid not null references public.proyecto(id),
  codigo             text not null,             -- 'AD-46'
  capitulo_nombre    text,
  descripcion        text not null,
  unidad             text,
  cantidad           numeric(14,4) not null default 0,
  valor_unitario     numeric(16,2) not null default 0,
  valor              numeric(16,2) generated always as (round(cantidad * valor_unitario, 2)) stored,
  asume              text not null default 'cliente' check (asume in ('cliente','esa')),
  aprobacion         public.estado_aprobacion not null default 'pendiente',
  aprobado_por_texto text,                      -- quién del lado del cliente
  aprobado_por_id    uuid references public.persona(id),
  aprobado_en        date,
  medio_aprobacion   text check (medio_aprobacion in ('acta','portal','correo','whatsapp')),
  acta_referencia    text,
  reemplaza_item_id  uuid references public.item_presupuesto(id),
  elemento_id        uuid references public.elemento_diseno(id),
  cambio_obra_id     uuid references public.cambio_obra(id),
  motivo             text,
  creado_en          timestamptz not null default now(),
  unique (proyecto_id, codigo),
  constraint adicional_aprobado_completo check (
    aprobacion <> 'aprobado'
    or (aprobado_en is not null and length(trim(coalesce(aprobado_por_texto, ''))) > 0))
);
create index if not exists adicional_proyecto_aprobacion on public.adicional (proyecto_id, aprobacion);
create index if not exists adicional_aprobado_por on public.adicional (aprobado_por_id);
create index if not exists adicional_reemplaza on public.adicional (reemplaza_item_id);
create index if not exists adicional_elemento on public.adicional (elemento_id);
create index if not exists adicional_cambio_obra on public.adicional (cambio_obra_id);
comment on table public.adicional is
  'Al 2026-08-28 Nirvana tenía 70 adicionales, ninguno aprobado y sin campo donde registrarlo. Ese hallazgo originó M-01.';

-- O4 · Bitácora diaria. Un día sin bitácora queda marcado (v_bitacora_faltante).
create table if not exists public.bitacora (
  id              uuid primary key default gen_random_uuid(),
  proyecto_id     uuid not null references public.proyecto(id),
  fecha           date not null,
  personal_sitio  smallint check (personal_sitio >= 0),
  frente_trabajo  text,
  avance          text,
  novedad         text,
  clima           text,
  registrado_por  uuid not null references public.persona(id),
  registrado_en   timestamptz not null default now(),
  unique (proyecto_id, fecha)
);
create index if not exists bitacora_registrado_por on public.bitacora (registrado_por);

-- Reporte diario por cuadrilla.
create table if not exists public.bitacora_cuadrilla (
  id              uuid primary key default gen_random_uuid(),
  bitacora_id     uuid not null references public.bitacora(id),
  contratista_id  uuid references public.persona(id),
  cuadrilla       text,
  personas        smallint check (personas >= 0),
  actividad       text not null,
  capitulo_id     uuid references public.capitulo(id)
);
create index if not exists bitacora_cuadrilla_bitacora on public.bitacora_cuadrilla (bitacora_id);
create index if not exists bitacora_cuadrilla_contratista on public.bitacora_cuadrilla (contratista_id);
create index if not exists bitacora_cuadrilla_capitulo on public.bitacora_cuadrilla (capitulo_id);

-- Actas de cobro al cliente (alimentan la cartera) y de pago a contratistas.
create table if not exists public.acta (
  id                uuid primary key default gen_random_uuid(),
  proyecto_id       uuid not null references public.proyecto(id),
  tipo              public.tipo_acta not null,
  numero            text not null,
  tercero_id        uuid references public.persona(id),
  corte_desde       date,
  corte_hasta       date,
  valor             numeric(16,2) not null,
  valor_retenido    numeric(16,2) not null default 0,     -- retegarantía u otras retenciones
  emitida_en        date not null default ((now() at time zone 'America/Bogota')::date),
  vence_en          date,
  aprobada_por      uuid references public.persona(id),
  anulada           boolean not null default false,
  motivo_anulacion  text,
  observaciones     text,
  creada_en         timestamptz not null default now(),
  unique (proyecto_id, tipo, numero),
  constraint acta_valor_positivo check (valor > 0),
  constraint acta_retencion_sana check (valor_retenido >= 0 and valor_retenido <= valor),
  constraint acta_corte check (corte_hasta is null or corte_desde is null or corte_hasta >= corte_desde),
  constraint acta_anulada_con_motivo check (not anulada or length(trim(coalesce(motivo_anulacion, ''))) > 0)
);
create index if not exists acta_tercero on public.acta (tercero_id);
create index if not exists acta_aprobada_por on public.acta (aprobada_por);
create index if not exists acta_por_vencer on public.acta (vence_en) where not anulada and tipo = 'cobro_cliente';

-- O6 · Lo que paga un acta no supera lo ejecutado (lo impide un disparador).
create table if not exists public.acta_item (
  id              uuid primary key default gen_random_uuid(),
  acta_id         uuid not null references public.acta(id),
  item_id         uuid references public.item_presupuesto(id),
  adicional_id    uuid references public.adicional(id),
  descripcion     text,
  unidad          text,
  cantidad        numeric(14,4) not null check (cantidad > 0),
  valor_unitario  numeric(16,2) not null check (valor_unitario >= 0),
  valor           numeric(16,2) generated always as (round(cantidad * valor_unitario, 2)) stored,
  constraint acta_item_un_origen check (num_nonnulls(item_id, adicional_id) <= 1)
);
create index if not exists acta_item_acta on public.acta_item (acta_id);
create index if not exists acta_item_item on public.acta_item (item_id);
create index if not exists acta_item_adicional on public.acta_item (adicional_id);

-- Movimiento. El corazón del control.
--   compromiso -> ya se acordó, la plata todavía no sale
--   causacion  -> llegó el material o se ejecutó, hay soporte
--   pago       -> salió del banco o de la caja
-- Cada eslabón apunta al anterior (origen_id) y todos comparten raiz_id.
-- Una devolución es un movimiento de naturaleza 'devolucion' que resta.
-- T2 · sin centro de costo no entra. T3 · no se borra ni se edita: un error se
-- anula con un contra-registro (anula_a) que repite sus valores.
create table if not exists public.movimiento (
  id                  uuid primary key default gen_random_uuid(),
  consecutivo         bigint generated always as identity,
  proyecto_id         uuid not null references public.proyecto(id),
  centro_costo_id     uuid not null references public.centro_costo(id),
  estado              public.estado_dinero not null,
  naturaleza          text not null default 'cargo',
  fecha               date not null default ((now() at time zone 'America/Bogota')::date),
  valor               numeric(16,2) not null,
  tercero_id          uuid references public.persona(id),
  tercero_nombre      text,
  concepto            text not null,
  medio               public.medio_pago not null default 'no_aplica',
  cuenta_id           uuid references public.cuenta(id),
  capitulo_id         uuid references public.capitulo(id),
  adicional_id        uuid references public.adicional(id),
  acta_id             uuid references public.acta(id),
  fondo_id            uuid references public.fondo_caja(id),
  origen_id           uuid references public.movimiento(id),
  raiz_id             uuid,                               -- lo fija el disparador
  fecha_prevista_pago date,                               -- alimenta el flujo a 13 semanas
  aprobacion          public.estado_aprobacion not null default 'no_requiere',
  aprobado_por        uuid references public.persona(id),
  aprobado_en         timestamptz,
  anula_a             uuid unique references public.movimiento(id),
  motivo_anulacion    text,
  registrado_por      uuid not null references public.persona(id),
  registrado_en       timestamptz not null default now(),
  sincronizado_en     timestamptz,                        -- llegó desde la PWA sin señal
  conciliado          boolean not null default false,     -- cuadrado contra banco o caja
  conciliado_en       date,

  constraint mov_valor_positivo check (valor > 0),
  constraint mov_naturaleza check (naturaleza in ('cargo','devolucion')),
  constraint mov_devolucion_con_origen check (naturaleza <> 'devolucion' or origen_id is not null),
  constraint mov_concepto check (length(trim(concepto)) > 0),
  constraint mov_tercero check (tercero_id is not null or length(trim(coalesce(tercero_nombre, ''))) > 0),
  constraint mov_anulacion_con_motivo check (
    (anula_a is null and motivo_anulacion is null)
    or (anula_a is not null and length(trim(coalesce(motivo_anulacion, ''))) > 0)),
  constraint mov_anulacion_sin_origen check (anula_a is null or origen_id is null),
  constraint mov_aprobado_completo check (
    aprobacion <> 'aprobado' or (aprobado_por is not null and aprobado_en is not null)),
  constraint mov_medio_coherente check (estado <> 'pago' or medio <> 'no_aplica'),
  constraint mov_fondo_en_efectivo check (fondo_id is null or medio in ('efectivo','no_aplica')),
  constraint mov_conciliacion_completa check (not conciliado or conciliado_en is not null)
);
create index if not exists movimiento_proyecto_estado on public.movimiento (proyecto_id, estado);
create index if not exists movimiento_centro_costo on public.movimiento (centro_costo_id);
create index if not exists movimiento_raiz on public.movimiento (raiz_id);
create index if not exists movimiento_fecha on public.movimiento (fecha desc);
create index if not exists movimiento_pendientes on public.movimiento (aprobacion) where aprobacion = 'pendiente';
create index if not exists movimiento_origen on public.movimiento (origen_id);
create index if not exists movimiento_fondo on public.movimiento (fondo_id);
create index if not exists movimiento_tercero on public.movimiento (tercero_id);
create index if not exists movimiento_cuenta on public.movimiento (cuenta_id);
create index if not exists movimiento_capitulo on public.movimiento (capitulo_id);
create index if not exists movimiento_adicional on public.movimiento (adicional_id);
create index if not exists movimiento_acta on public.movimiento (acta_id);
create index if not exists movimiento_aprobado_por on public.movimiento (aprobado_por);
create index if not exists movimiento_registrado_por on public.movimiento (registrado_por);
create index if not exists movimiento_sin_conciliar on public.movimiento (conciliado) where estado = 'pago' and not conciliado;
comment on table public.movimiento is
  'Un gasto pasa por hasta tres eslabones encadenados: compromiso -> causacion -> pago. El banco solo conoce el tercero; por eso el balance de hoy llega con ocho días de rezago.';

-- M-08 · El cliente aprueba o rechaza un adicional desde el portal. La decisión
-- queda registrada en el origen, no en un mensaje de WhatsApp.
create table if not exists public.aprobacion_cliente (
  id            uuid primary key default gen_random_uuid(),
  adicional_id  uuid not null references public.adicional(id),
  persona_id    uuid not null references public.persona(id),
  decision      public.estado_aprobacion not null check (decision in ('aprobado','rechazado')),
  comentario    text,
  decidido_en   timestamptz not null default now()
);
create index if not exists aprobacion_cliente_adicional on public.aprobacion_cliente (adicional_id);
create index if not exists aprobacion_cliente_persona on public.aprobacion_cliente (persona_id);


-- O11 · Pendientes de obra: remates, instalaciones, trámites y compras de
-- sitio. Es la lista que recorre el residente; la bitácora es el diario y no
-- sirve para esto. Un pendiente no lleva valor en pesos: cuando implica plata
-- se cuelga del movimiento, que sí tiene valor, cuenta y aprobación.
create table if not exists public.pendiente_obra (
  id                uuid primary key default gen_random_uuid(),
  proyecto_id       uuid not null references public.proyecto(id),
  fase_id           uuid references public.proyecto_fase(id),
  objetivo_id       uuid references public.objetivo(id),
  elemento_id       uuid references public.elemento_diseno(id),
  tipo              public.tipo_pendiente not null default 'ejecucion',
  prioridad         public.prioridad_pendiente not null default 'normal',
  titulo            text not null,
  ubicacion         text,                      -- 'PH', 'baño cerros', 'cocina'
  descripcion       text,
  responsable_id    uuid not null references public.persona(id),   -- quién responde
  ejecutor_id       uuid references public.persona(id),            -- quién lo hace
  bloqueado_por     uuid references public.pendiente_obra(id),
  movimiento_id     uuid references public.movimiento(id),         -- la plata vive aquí
  estado            public.estado_pendiente not null default 'abierto',
  fecha_compromiso  date,
  verificado_en     timestamptz,
  verificado_por    uuid references public.persona(id),
  descartado_porque text,
  creado_en         timestamptz not null default now(),
  creado_por        uuid not null references public.persona(id),
  constraint pendiente_verificacion_completa check (
    (verificado_en is null) = (verificado_por is null)),
  constraint pendiente_cerrado_verificado check (
    estado <> 'cerrado' or verificado_en is not null),
  constraint pendiente_descarte_con_razon check (
    (estado = 'descartado') = (descartado_porque is not null)),
  constraint pendiente_no_se_bloquea_solo check (bloqueado_por is distinct from id),
  constraint pendiente_titulo_escrito check (length(trim(titulo)) >= 4)
);
create index if not exists pendiente_proyecto on public.pendiente_obra (proyecto_id);
create index if not exists pendiente_fase on public.pendiente_obra (fase_id);
create index if not exists pendiente_objetivo on public.pendiente_obra (objetivo_id);
create index if not exists pendiente_elemento on public.pendiente_obra (elemento_id);
create index if not exists pendiente_responsable on public.pendiente_obra (responsable_id)
  where estado not in ('cerrado','descartado');
create index if not exists pendiente_ejecutor on public.pendiente_obra (ejecutor_id);
create index if not exists pendiente_bloqueado_por on public.pendiente_obra (bloqueado_por);
create index if not exists pendiente_movimiento on public.pendiente_obra (movimiento_id);
create index if not exists pendiente_verificado_por on public.pendiente_obra (verificado_por);
create index if not exists pendiente_creado_por on public.pendiente_obra (creado_por);
create index if not exists pendiente_compromiso on public.pendiente_obra (fecha_compromiso)
  where estado not in ('cerrado','descartado');
comment on table public.pendiente_obra is
  'El ejecutor puede ser el contratista. Separar responsable de ejecutor evita lo que pasaba en el Excel, donde la celda decía "Teo-carpintero" y no se sabía a quién reclamarle.';

-- =============================================================================
-- 8. M-02 Reclamaciones y listas de chequeo
-- Tres partes cobran en cascada: la empresa asegurada, los abogados y ESA.
-- El pagador de ESA es la empresa asegurada: el riesgo es de cartera.
-- =============================================================================

create table if not exists public.reclamacion (
  id                     uuid primary key default gen_random_uuid(),
  proyecto_id            uuid not null unique references public.proyecto(id),
  aseguradora_id         uuid references public.persona(id),
  oficina_abogados_id    uuid references public.persona(id),
  numero_poliza          text,
  numero_siniestro       text,
  fecha_siniestro        date,
  fecha_limite           date,                        -- P4
  valor_reclamado        numeric(16,2),
  valor_aprobado         numeric(16,2),
  estado                 public.estado_reclamacion not null default 'en_expediente',
  conciliada_en          date,                        -- P2
  conciliada_por_texto   text,
  aval_estructural_por   uuid references public.persona(id),   -- P6
  aval_estructural_en    date,
  radicada_en            date,
  notas                  text,
  creada_en              timestamptz not null default now(),
  constraint reclamacion_conciliacion_completa check ((conciliada_en is null) = (conciliada_por_texto is null)),
  constraint reclamacion_aval_completo check ((aval_estructural_por is null) = (aval_estructural_en is null))
);
create index if not exists reclamacion_aseguradora on public.reclamacion (aseguradora_id);
create index if not exists reclamacion_abogados on public.reclamacion (oficina_abogados_id);
create index if not exists reclamacion_aval on public.reclamacion (aval_estructural_por);
create index if not exists reclamacion_vencimiento on public.reclamacion (fecha_limite)
  where estado not in ('pagada_a_esa','negada','desistida');

-- P3 · El historial de la cascada lo escribe un disparador: nadie lo edita.
create table if not exists public.reclamacion_evento (
  id               bigint primary key generated always as identity,
  reclamacion_id   uuid not null references public.reclamacion(id),
  estado_anterior  public.estado_reclamacion,
  estado_nuevo     public.estado_reclamacion not null,
  persona_id       uuid references public.persona(id),
  ocurrio_en       timestamptz not null default now()
);
create index if not exists reclamacion_evento_reclamacion on public.reclamacion_evento (reclamacion_id, ocurrio_en desc);
create index if not exists reclamacion_evento_persona on public.reclamacion_evento (persona_id);

-- Listas de chequeo: un solo mecanismo para las compuertas de fase (D1), la
-- radicación en curaduría (D7), la póliza (P1) y el presupuesto. La plantilla
-- se define una vez; cada proyecto la responde.
create table if not exists public.lista_chequeo (
  id              uuid primary key default gen_random_uuid(),
  ambito          public.ambito_chequeo not null,
  nombre          text not null,
  fase            public.fase_proyecto,                         -- para ámbito fase_diseno
  aseguradora_id  uuid references public.persona(id),           -- P1 · por póliza
  version         smallint not null default 1,
  activa          boolean not null default true,
  creada_en       timestamptz not null default now(),
  unique (ambito, nombre, version)
);
create index if not exists lista_chequeo_aseguradora on public.lista_chequeo (aseguradora_id);

create table if not exists public.lista_chequeo_item (
  id                  uuid primary key default gen_random_uuid(),
  lista_id            uuid not null references public.lista_chequeo(id),
  orden               smallint not null default 100,
  texto               text not null,
  obligatorio         boolean not null default true,
  requiere_evidencia  boolean not null default false
);
create index if not exists lista_chequeo_item_lista on public.lista_chequeo_item (lista_id, orden);

create table if not exists public.chequeo (
  id              uuid primary key default gen_random_uuid(),
  lista_id        uuid not null references public.lista_chequeo(id),
  proyecto_id     uuid not null references public.proyecto(id),   -- lo fija el disparador
  fase_id         uuid references public.proyecto_fase(id),
  radicacion_id   uuid references public.radicacion_licencia(id),
  reclamacion_id  uuid references public.reclamacion(id),
  presupuesto_id  uuid references public.presupuesto(id),
  creado_en       timestamptz not null default now(),
  constraint chequeo_un_objetivo check (num_nonnulls(fase_id, radicacion_id, reclamacion_id, presupuesto_id) = 1)
);
create index if not exists chequeo_lista on public.chequeo (lista_id);
create index if not exists chequeo_proyecto on public.chequeo (proyecto_id);
create index if not exists chequeo_fase on public.chequeo (fase_id);
create index if not exists chequeo_radicacion on public.chequeo (radicacion_id);
create index if not exists chequeo_reclamacion on public.chequeo (reclamacion_id);
create index if not exists chequeo_presupuesto on public.chequeo (presupuesto_id);

create table if not exists public.chequeo_respuesta (
  id              uuid primary key default gen_random_uuid(),
  chequeo_id      uuid not null references public.chequeo(id),
  item_id         uuid not null references public.lista_chequeo_item(id),
  cumple          boolean not null,
  nota            text,
  evidencia_ruta  text,
  verificado_por  uuid not null references public.persona(id),
  verificado_en   timestamptz not null default now(),
  unique (chequeo_id, item_id)
);
create index if not exists chequeo_respuesta_item on public.chequeo_respuesta (item_id);
create index if not exists chequeo_respuesta_verificado_por on public.chequeo_respuesta (verificado_por);


-- =============================================================================
-- 9. Evidencia
-- P5 · Foto con coordenada y fecha, no editable. La ruta en el almacenamiento
-- empieza por el id del proyecto: así los permisos de las fotos son los mismos
-- del proyecto.
-- =============================================================================

create table if not exists public.evidencia (
  id              uuid primary key default gen_random_uuid(),
  proyecto_id     uuid not null references public.proyecto(id),   -- lo fija el disparador
  movimiento_id   uuid references public.movimiento(id),
  bitacora_id     uuid references public.bitacora(id),
  cambio_obra_id  uuid references public.cambio_obra(id),
  adicional_id    uuid references public.adicional(id),
  reclamacion_id  uuid references public.reclamacion(id),
  pendiente_id    uuid references public.pendiente_obra(id),
  bucket          text not null default 'evidencias' check (bucket in ('evidencias','documentos')),
  ruta            text not null,                                  -- '<proyecto_id>/<archivo>'
  tipo            text not null default 'foto' check (tipo in ('foto','factura','remision','acta','poliza','informe','otro')),
  lat             numeric(9,6),
  lng             numeric(9,6),
  tomada_en       timestamptz,
  hash_sha256     text,
  registrada_por  uuid not null references public.persona(id),
  subida_en       timestamptz not null default now(),
  unique (bucket, ruta),
  constraint evidencia_de_algo check (
    num_nonnulls(movimiento_id, bitacora_id, cambio_obra_id, adicional_id, reclamacion_id,
                 pendiente_id) >= 1)
);
create index if not exists evidencia_proyecto on public.evidencia (proyecto_id);
create index if not exists evidencia_movimiento on public.evidencia (movimiento_id);
create index if not exists evidencia_bitacora on public.evidencia (bitacora_id);
create index if not exists evidencia_cambio_obra on public.evidencia (cambio_obra_id);
create index if not exists evidencia_adicional on public.evidencia (adicional_id);
create index if not exists evidencia_reclamacion on public.evidencia (reclamacion_id);
create index if not exists evidencia_pendiente on public.evidencia (pendiente_id);
create index if not exists evidencia_registrada_por on public.evidencia (registrada_por);


-- =============================================================================
-- 10. M-07 Finanzas
-- =============================================================================

-- El saldo real de cada cuenta en una fecha, tomado del extracto o del arqueo.
-- Es el punto de partida del flujo a 13 semanas.
create table if not exists public.saldo_cuenta (
  id              uuid primary key default gen_random_uuid(),
  cuenta_id       uuid not null references public.cuenta(id),
  fecha           date not null,
  saldo           numeric(16,2) not null,
  fuente          text not null default 'extracto' check (fuente in ('extracto','arqueo','manual')),
  registrado_por  uuid references public.persona(id),
  registrado_en   timestamptz not null default now(),
  unique (cuenta_id, fecha)
);
create index if not exists saldo_cuenta_registrado_por on public.saldo_cuenta (registrado_por);

-- Ingresos. Igual que el gasto: no se borran ni se editan; se anulan.
create table if not exists public.ingreso (
  id                uuid primary key default gen_random_uuid(),
  proyecto_id       uuid references public.proyecto(id),
  acta_id           uuid references public.acta(id),
  cuenta_id         uuid references public.cuenta(id),
  fecha             date not null default ((now() at time zone 'America/Bogota')::date),
  valor             numeric(16,2) not null check (valor > 0),
  linea             public.linea_servicio not null,
  es_anticipo       boolean not null default false,
  tercero_id        uuid references public.persona(id),
  tercero_nombre    text,
  concepto          text not null,
  anula_a           uuid unique references public.ingreso(id),
  motivo_anulacion  text,
  registrado_por    uuid not null references public.persona(id),
  registrado_en     timestamptz not null default now(),
  conciliado        boolean not null default false,
  conciliado_en     date,
  constraint ingreso_con_proyecto check (
    proyecto_id is not null or linea in ('traslado_entre_cuentas','credito_bancario','otros_ingresos')),
  constraint ingreso_anulacion_con_motivo check (
    (anula_a is null and motivo_anulacion is null)
    or (anula_a is not null and length(trim(coalesce(motivo_anulacion, ''))) > 0)),
  constraint ingreso_conciliacion_completa check (not conciliado or conciliado_en is not null)
);
create index if not exists ingreso_proyecto on public.ingreso (proyecto_id);
create index if not exists ingreso_acta on public.ingreso (acta_id);
create index if not exists ingreso_cuenta on public.ingreso (cuenta_id);
create index if not exists ingreso_tercero on public.ingreso (tercero_id);
create index if not exists ingreso_registrado_por on public.ingreso (registrado_por);
create index if not exists ingreso_fecha on public.ingreso (fecha desc);

-- F1 · Cada línea del extracto se cruza con un movimiento o un ingreso.
create table if not exists public.extracto_linea (
  id              uuid primary key default gen_random_uuid(),
  cuenta_id       uuid not null references public.cuenta(id),
  fecha           date not null,
  valor           numeric(16,2) not null,       -- negativo = salida
  descripcion     text,
  referencia      text,
  huella          text not null unique,         -- evita importar dos veces la misma línea
  movimiento_id   uuid references public.movimiento(id),
  ingreso_id      uuid references public.ingreso(id),
  conciliada_en   timestamptz,
  conciliada_por  uuid references public.persona(id),
  importada_en    timestamptz not null default now(),
  constraint extracto_un_cruce check (num_nonnulls(movimiento_id, ingreso_id) <= 1)
);
create index if not exists extracto_linea_cuenta on public.extracto_linea (cuenta_id, fecha);
create index if not exists extracto_linea_movimiento on public.extracto_linea (movimiento_id);
create index if not exists extracto_linea_ingreso on public.extracto_linea (ingreso_id);
create index if not exists extracto_linea_conciliada_por on public.extracto_linea (conciliada_por);

-- F1 · Lo que no cuadra queda abierto, con dueño y antigüedad. Ninguna se cierra sola.
create table if not exists public.partida_abierta (
  id                 uuid primary key default gen_random_uuid(),
  cuenta_id          uuid not null references public.cuenta(id),
  extracto_linea_id  uuid references public.extracto_linea(id),
  fecha              date not null,
  valor              numeric(16,2) not null,
  descripcion        text not null,
  responsable_id     uuid not null references public.persona(id),
  abierta_en         timestamptz not null default now(),
  resuelta_en        timestamptz,
  resuelta_por       uuid references public.persona(id),
  resolucion         text,
  constraint partida_resolucion_completa check (
    (resuelta_en is null and resuelta_por is null and resolucion is null)
    or (resuelta_en is not null and resuelta_por is not null and length(trim(coalesce(resolucion, ''))) > 0))
);
create index if not exists partida_abierta_cuenta on public.partida_abierta (cuenta_id);
create index if not exists partida_abierta_extracto on public.partida_abierta (extracto_linea_id);
create index if not exists partida_abierta_responsable on public.partida_abierta (responsable_id);
create index if not exists partida_abierta_resuelta_por on public.partida_abierta (resuelta_por);

-- F6 · Cerrado el mes, no se modifica: los ajustes van al mes siguiente.
create table if not exists public.cierre_mes (
  id                 uuid primary key default gen_random_uuid(),
  periodo            date not null unique check (extract(day from periodo) = 1),
  cerrado_por        uuid not null references public.persona(id),
  cerrado_en         timestamptz not null default now(),
  reabierto_en       timestamptz,
  reabierto_por      uuid references public.persona(id),
  motivo_reapertura  text,
  constraint cierre_reapertura_completa check (
    (reabierto_en is null and reabierto_por is null and motivo_reapertura is null)
    or (reabierto_en is not null and reabierto_por is not null and length(trim(coalesce(motivo_reapertura, ''))) > 0))
);
create index if not exists cierre_mes_cerrado_por on public.cierre_mes (cerrado_por);
create index if not exists cierre_mes_reabierto_por on public.cierre_mes (reabierto_por);

-- F2 · La estructura (ADMINISTRACION) repartida a los proyectos por una regla
-- explícita. Convierte el margen bruto en rentabilidad.
create table if not exists public.distribucion_estructura (
  id            uuid primary key default gen_random_uuid(),
  periodo       date not null check (extract(day from periodo) = 1),
  proyecto_id   uuid not null references public.proyecto(id),
  horas         numeric(10,2) not null default 0,
  pct           numeric(9,6) not null default 0,
  valor         numeric(16,2) not null default 0,
  regla         text not null default 'horas_dedicadas',
  calculado_en  timestamptz not null default now(),
  unique (periodo, proyecto_id)
);
create index if not exists distribucion_estructura_proyecto on public.distribucion_estructura (proyecto_id);


-- =============================================================================
-- 11. Funciones de identidad
-- Las usan las políticas de acceso. Viven en "private" y leen con los
-- privilegios de su dueño: así una política no se llama a sí misma en círculo.
-- =============================================================================

-- La ficha de quien tiene la sesión abierta (interna o externa).
create or replace function private.persona_actual() returns uuid
language sql stable security definer set search_path = '' as $$
  select p.id from public.persona p
  where p.auth_user_id = auth.uid() and p.activo
  limit 1
$$;

create or replace function private.es_interno() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.persona p
    where p.auth_user_id = auth.uid() and p.activo and p.es_interno)
$$;

-- ¿La persona interna de la sesión tiene alguno de estos roles?
create or replace function private.tiene_rol(p_roles public.rol_persona[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select p.rol = any (p_roles) from public.persona p
    where p.auth_user_id = auth.uid() and p.activo and p.es_interno
    limit 1), false)
$$;

-- Socios y directores.
create or replace function private.es_direccion() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.tiene_rol('{socio,director}'::public.rol_persona[])
$$;

-- Proyectos que la persona interna puede ver. Dirección y finanzas, todos.
create or replace function private.proyectos_visibles() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select pr.id from public.proyecto pr
  where (select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[]))
  union
  select a.proyecto_id from public.acceso_proyecto a
  join public.persona p on p.id = a.persona_id
  where p.auth_user_id = auth.uid() and p.activo and p.es_interno
$$;

-- Proyectos donde la persona interna puede registrar (gasto, bitácora, avance).
create or replace function private.proyectos_registro() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select pr.id from public.proyecto pr
  where (select private.es_direccion())
  union
  select a.proyecto_id from public.acceso_proyecto a
  join public.persona p on p.id = a.persona_id
  where p.auth_user_id = auth.uid() and p.activo and p.es_interno
    and a.nivel in ('registro','aprobacion','total')
$$;

-- Proyectos que un cliente o contratista ve desde el portal (M-08).
create or replace function private.proyectos_portal() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select a.proyecto_id from public.acceso_proyecto a
  join public.persona p on p.id = a.persona_id
  where p.auth_user_id = auth.uid() and p.activo and not p.es_interno
$$;

-- F6 · ¿El mes de esta fecha está cerrado?
create or replace function private.mes_cerrado(p_fecha date) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.cierre_mes c
    where c.periodo = date_trunc('month', p_fecha)::date and c.reabierto_en is null)
$$;

-- D2 · Días hábiles (lunes a viernes) sin ningún registro de dedicación.
-- No cuenta los días anteriores a que la persona existiera en el sistema.
create or replace function private.dias_sin_dedicacion(p_persona uuid, p_desde date, p_hasta date)
returns integer
language sql stable security definer set search_path = '' as $$
  select count(*)::integer
  from generate_series(p_desde, p_hasta, interval '1 day') g(dia)
  join public.persona p on p.id = p_persona
  where extract(isodow from g.dia) < 6
    and g.dia::date >= (p.creado_en at time zone 'America/Bogota')::date
    and not exists (
      select 1 from public.dedicacion d
      where d.persona_id = p_persona and d.fecha = g.dia::date)
$$;

-- ¿Una lista de chequeo respondida tiene todos sus puntos obligatorios en "cumple"?
create or replace function private.chequeo_completo(p_chequeo uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.chequeo c where c.id = p_chequeo)
     and not exists (
       select 1
       from public.chequeo c
       join public.lista_chequeo_item i on i.lista_id = c.lista_id
       where c.id = p_chequeo and i.obligatorio
         and not exists (
           select 1 from public.chequeo_respuesta r
           where r.chequeo_id = c.id and r.item_id = i.id and r.cumple))
$$;


-- =============================================================================
-- 12. Reglas de negocio y disparadores
-- =============================================================================

-- ---------- Transversales ----------

-- T3 · Todo cambio deja rastro: quién, cuándo, antes y después.
create or replace function private.auditar() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_fila jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
begin
  if tg_op = 'UPDATE' and to_jsonb(old) = to_jsonb(new) then
    return null;
  end if;
  insert into public.evento_auditoria (tabla, fila_id, operacion, actor, persona_id, antes, despues)
  values (
    tg_table_name,
    coalesce(v_fila->>'id', v_fila->>'tipo', concat_ws('/', v_fila->>'persona_id', v_fila->>'proyecto_id')),
    tg_op,
    auth.uid(),
    private.persona_actual(),
    case when tg_op <> 'INSERT' then to_jsonb(old) end,
    case when tg_op <> 'DELETE' then to_jsonb(new) end);
  return null;
end $$;

-- T3 · Nada se borra.
create or replace function private.prohibir_borrado() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'Los registros de % no se borran: se anulan o se cierran, y queda el rastro.', tg_table_name;
end $$;

-- Lo que se registra una vez y queda como constancia.
create or replace function private.prohibir_edicion() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'Los registros de % no se editan: son constancia. Registre uno nuevo.', tg_table_name;
end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'parametro','persona','categoria_costo','cuenta','proyecto','centro_costo','acceso_proyecto',
    'regla_alerta','oportunidad','cotizacion','proyecto_fase','entregable','presupuesto',
    'ejecucion_item','fondo_caja','cambio_obra','adicional','acta','movimiento',
    'aprobacion_cliente','reclamacion','lista_chequeo','chequeo_respuesta','cierre_mes',
    'ingreso','partida_abierta','saldo_cuenta','objetivo','pendiente_obra'
  ] loop
    execute format('drop trigger if exists tr_%1$s_auditar on public.%1$I', t);
    execute format('create trigger tr_%1$s_auditar after insert or update or delete on public.%1$I '
                   'for each row execute function private.auditar()', t);
  end loop;

  foreach t in array array[
    'persona','proyecto','centro_costo','lead','oportunidad','cotizacion','proyecto_fase',
    'revision_diseno','entregable','entregable_archivo','presupuesto','fondo_caja','cambio_obra',
    'adicional','bitacora','acta','acta_item','movimiento','aprobacion_cliente','reclamacion',
    'reclamacion_evento','chequeo_respuesta','evidencia','ingreso','cierre_mes','evento_auditoria',
    'objetivo','pendiente_obra'
  ] loop
    execute format('drop trigger if exists tr_%1$s_no_borrar on public.%1$I', t);
    execute format('create trigger tr_%1$s_no_borrar before delete on public.%1$I '
                   'for each row execute function private.prohibir_borrado()', t);
  end loop;
end $$;


-- ---------- Núcleo ----------

-- M2 · El canal y el cliente viajan de la oportunidad al proyecto.
create or replace function private.preparar_proyecto() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_canal   public.canal_origen;
  v_cliente uuid;
begin
  if new.oportunidad_id is not null
     and (tg_op = 'INSERT' or new.oportunidad_id is distinct from old.oportunidad_id) then
    select o.canal, o.cliente_id into v_canal, v_cliente
    from public.oportunidad o where o.id = new.oportunidad_id;
    new.canal := coalesce(new.canal, v_canal);
    new.cliente_id := coalesce(new.cliente_id, v_cliente);
  end if;

  if tg_op = 'UPDATE' and old.canal is not null and new.canal is distinct from old.canal
     and auth.uid() is not null and not private.tiene_rol('{socio}'::public.rol_persona[]) then
    raise exception 'M2 · El canal de un proyecto no se cambia: viaja desde el lead hasta el margen. Solo un socio lo corrige.';
  end if;
  return new;
end $$;

drop trigger if exists tr_proyecto_preparar on public.proyecto;
create trigger tr_proyecto_preparar
  before insert or update on public.proyecto
  for each row execute function private.preparar_proyecto();


-- ---------- Comercial ----------

-- Teléfono comparable, canal desde la campaña y reingreso desde nutrición (6.4):
-- si alguien que estaba en nutrición vuelve a escribir, sale solo.
create or replace function private.preparar_lead() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.telefono_normalizado := nullif(regexp_replace(coalesce(new.telefono, ''), '[^0-9]', '', 'g'), '');
  if length(new.telefono_normalizado) > 10 then
    new.telefono_normalizado := right(new.telefono_normalizado, 10);   -- sin el 57
  end if;

  if tg_op = 'INSERT' then
    if new.canal is null and new.campana_id is not null then
      select c.canal into new.canal from public.campana c where c.id = new.campana_id;
    end if;
    if new.telefono_normalizado is not null then
      select l.id into new.lead_previo_id
      from public.lead l
      where l.telefono_normalizado = new.telefono_normalizado
      order by l.creado_en desc
      limit 1;

      update public.lead
         set estado = 'contactado', reactivado_en = now()
       where telefono_normalizado = new.telefono_normalizado and estado = 'nutricion';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists tr_lead_preparar on public.lead;
create trigger tr_lead_preparar
  before insert or update on public.lead
  for each row execute function private.preparar_lead();

-- Tiempo de primera respuesta y regla de los tres intentos.
create or replace function private.registrar_contacto() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_estado          public.estado_lead;
  v_primer          timestamptz;
  v_max             smallint;
  v_sin_respuesta   integer;
begin
  select l.estado, l.primer_contacto_en into v_estado, v_primer
  from public.lead l where l.id = new.lead_id for update;

  if new.direccion = 'saliente' and v_primer is null then
    update public.lead set primer_contacto_en = new.fecha where id = new.lead_id;
  end if;

  if new.respondio or new.direccion = 'entrante' then
    if v_estado = 'nutricion' then
      update public.lead set estado = 'contactado', reactivado_en = now() where id = new.lead_id;
    elsif v_estado = 'nuevo' then
      update public.lead set estado = 'contactado' where id = new.lead_id;
    end if;
  else
    if v_estado = 'nuevo' then
      update public.lead set estado = 'contactado' where id = new.lead_id;
      v_estado := 'contactado';
    end if;

    select p.intentos_contacto_max into v_max from public.parametro p where p.id;
    select count(*) into v_sin_respuesta
    from public.contacto_lead c
    where c.lead_id = new.lead_id and c.direccion = 'saliente' and not c.respondio
      and c.fecha > coalesce((
        select max(r.fecha) from public.contacto_lead r
        where r.lead_id = new.lead_id and (r.respondio or r.direccion = 'entrante')), '-infinity');

    if v_sin_respuesta >= v_max and v_estado in ('contactado','calificado') then
      update public.lead set estado = 'nutricion' where id = new.lead_id;
    end if;
  end if;
  return null;
end $$;

drop trigger if exists tr_contacto_lead_registrar on public.contacto_lead;
create trigger tr_contacto_lead_registrar
  after insert on public.contacto_lead
  for each row execute function private.registrar_contacto();

-- Política 3.1 (valor estimado), M4 (motivo de pérdida), M8 (desenlace).
create or replace function private.validar_oportunidad() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.canal is null and new.lead_id is not null then
    select l.canal into new.canal from public.lead l where l.id = new.lead_id;
  end if;

  if new.etapa > 'cita_viabilidad' and new.etapa <> 'perdida' and coalesce(new.valor_estimado, 0) <= 0 then
    raise exception 'Sin valor estimado una oportunidad no pasa de la cita de viabilidad (política 3.1 de ventas)';
  end if;

  if new.etapa = 'perdida' and new.motivo_perdida is null then
    raise exception 'M4 · Una oportunidad perdida necesita el motivo: precio, tiempo, competencia, desapareció...';
  end if;

  if new.etapa in ('ganada','perdida') then
    new.desenlace_en := coalesce(new.desenlace_en, now());
  else
    if tg_op = 'UPDATE' and old.etapa in ('ganada','perdida')
       and auth.uid() is not null and not private.es_direccion() then
      raise exception 'M8 · Una oportunidad con desenlace solo la reabre dirección';
    end if;
    new.desenlace_en := null;
  end if;

  if new.etapa <> 'perdida' then
    new.motivo_perdida := null;
  end if;

  new.actualizada_en := now();

  if tg_op = 'INSERT' and new.lead_id is not null then
    update public.lead set estado = 'convertido' where id = new.lead_id and estado <> 'convertido';
  end if;
  return new;
end $$;

drop trigger if exists tr_oportunidad_validar on public.oportunidad;
create trigger tr_oportunidad_validar
  before insert or update on public.oportunidad
  for each row execute function private.validar_oportunidad();

-- M9 · Una cita realizada deja constancia del consentimiento de grabación.
create or replace function private.validar_cita() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.grabacion_url is not null and coalesce(new.consentimiento_grabacion, false) = false then
    raise exception 'Una cita no se graba sin consentimiento registrado (Ley 1581 de 2012)';
  end if;
  if new.estado = 'realizada' then
    if new.consentimiento_grabacion is null then
      raise exception 'M9 · Al marcar la cita como realizada, registre si el cliente autorizó la grabación';
    end if;
    new.realizada_en := coalesce(new.realizada_en, now());
  end if;
  return new;
end $$;

drop trigger if exists tr_cita_validar on public.cita;
create trigger tr_cita_validar
  before insert or update on public.cita
  for each row execute function private.validar_cita();

-- M6 · Vencimiento automático. O10 · margen de diseño bajo la meta.
create or replace function private.validar_cotizacion() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_vigencia  smallint;
  v_meta      numeric;
  v_margen    numeric;
begin
  select p.vigencia_cotizacion_dias, p.margen_meta_diseno into v_vigencia, v_meta
  from public.parametro p where p.id;

  if new.estado <> 'borrador' then
    new.emitida_en := coalesce(new.emitida_en, private.hoy());
    new.vence_en := coalesce(new.vence_en, new.emitida_en + v_vigencia);
    if new.vence_en < new.emitida_en then
      raise exception 'M6 · Una cotización no vence antes de emitirse';
    end if;
  end if;

  if new.margen_autorizado_por is not null then
    if not exists (select 1 from public.persona p where p.id = new.margen_autorizado_por and p.rol = 'socio') then
      raise exception 'O10 · Solo un socio autoriza un margen bajo la meta';
    end if;
    new.margen_autorizado_en := coalesce(new.margen_autorizado_en, now());
  end if;

  if new.estado = 'emitida' and (tg_op = 'INSERT' or old.estado is distinct from 'emitida')
     and new.tipo in ('diseno','consultoria') then
    if new.costo_estimado is null then
      raise exception 'O10 · Una cotización de % no se emite sin costo estimado: es lo que dice si deja el margen meta', new.tipo;
    end if;
    v_margen := (new.valor - new.costo_estimado) / new.valor;
    if v_margen < v_meta and new.margen_autorizado_por is null then
      raise exception 'O10 · Margen de %, bajo la meta de %. Necesita autorización de un socio para emitirse.',
        replace(round(v_margen * 100, 1)::text, '.', ',') || '%',
        replace(round(v_meta * 100, 1)::text, '.', ',') || '%';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists tr_cotizacion_validar on public.cotizacion;
create trigger tr_cotizacion_validar
  before insert or update on public.cotizacion
  for each row execute function private.validar_cotizacion();

-- M7 · Sin hipótesis no arranca; sin aprendizaje no se cierra.
create or replace function private.validar_experimento() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.estado in ('corriendo','cerrado')
     and (length(trim(coalesce(new.hipotesis, ''))) = 0 or length(trim(coalesce(new.metrica_exito, ''))) = 0) then
    raise exception 'M7 · Un experimento no arranca sin hipótesis y métrica de éxito escritas';
  end if;
  if new.estado = 'corriendo' then
    new.inicio := coalesce(new.inicio, private.hoy());
  end if;
  if new.estado = 'cerrado' then
    if length(trim(coalesce(new.resultado, ''))) = 0 or length(trim(coalesce(new.aprendizaje, ''))) = 0 then
      raise exception 'M7 · Un experimento no se cierra sin resultado y aprendizaje: es la única forma de que mercadeo aprenda';
    end if;
    new.fin := coalesce(new.fin, private.hoy());
  end if;
  return new;
end $$;

drop trigger if exists tr_experimento_validar on public.experimento;
create trigger tr_experimento_validar
  before insert or update on public.experimento
  for each row execute function private.validar_experimento();


-- ---------- Obra y dinero ----------

-- El corazón del control: T1, T2, T3, T4 y F6 sobre cada movimiento.
create or replace function private.validar_movimiento() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_uid        uuid := auth.uid();
  v_direccion  boolean := private.es_direccion();
  v_proy       uuid;
  v_umbral     numeric;
  v_origen     public.movimiento%rowtype;
  v_raiz       public.movimiento%rowtype;
  v_anulado    public.movimiento%rowtype;
begin
  -- T2 · El centro de costo pertenece al proyecto.
  select cc.proyecto_id into v_proy from public.centro_costo cc where cc.id = new.centro_costo_id;
  if v_proy is null or v_proy <> new.proyecto_id then
    raise exception 'El centro de costo no pertenece al proyecto indicado';
  end if;

  -- F6 · Un mes cerrado no recibe ni cambia movimientos.
  if private.mes_cerrado(new.fecha) or (tg_op = 'UPDATE' and private.mes_cerrado(old.fecha)) then
    raise exception 'F6 · El mes % está cerrado. Registre el ajuste en el mes siguiente.', to_char(new.fecha, 'YYYY-MM');
  end if;

  if new.acta_id is not null and not exists (
       select 1 from public.acta a
       where a.id = new.acta_id and a.proyecto_id = new.proyecto_id
         and a.tipo = 'pago_contratista' and not a.anulada) then
    raise exception 'El acta indicada no es un acta de pago vigente de este proyecto';
  end if;

  if tg_op = 'INSERT' then
    select p.umbral_aprobacion into v_umbral from public.parametro p where p.id;

    if new.anula_a is not null then
      -- T3 · Un error se anula con un contra-registro que repite sus valores.
      select * into v_anulado from public.movimiento m where m.id = new.anula_a;
      if not found then
        raise exception 'El movimiento que se quiere anular no existe';
      end if;
      if v_anulado.anula_a is not null then
        raise exception 'Un contra-registro no se anula: registre de nuevo el movimiento correcto';
      end if;
      if v_anulado.proyecto_id <> new.proyecto_id or v_anulado.centro_costo_id <> new.centro_costo_id
         or v_anulado.estado <> new.estado or v_anulado.naturaleza <> new.naturaleza
         or v_anulado.valor <> new.valor then
        raise exception 'El contra-registro debe repetir proyecto, centro de costo, estado, naturaleza y valor del movimiento que anula';
      end if;
      if exists (
           select 1 from public.movimiento h
           where h.origen_id = new.anula_a
             and not exists (select 1 from public.movimiento x where x.anula_a = h.id)) then
        raise exception 'Ese movimiento tiene eslabones posteriores vigentes: anúlelos primero';
      end if;
      new.raiz_id := v_anulado.raiz_id;
      new.aprobacion := 'no_requiere';

    elsif new.origen_id is null then
      new.raiz_id := new.id;

    else
      -- Cadena compromiso -> causación -> pago.
      select * into v_origen from public.movimiento m where m.id = new.origen_id;
      if not found then
        raise exception 'El movimiento de origen no existe';
      end if;
      if v_origen.proyecto_id <> new.proyecto_id or v_origen.centro_costo_id <> new.centro_costo_id then
        raise exception 'Un movimiento no puede cambiar de proyecto ni de centro de costo dentro de su cadena';
      end if;
      if v_origen.anula_a is not null
         or exists (select 1 from public.movimiento x where x.anula_a = v_origen.id) then
        raise exception 'El movimiento de origen está anulado';
      end if;
      new.raiz_id := v_origen.raiz_id;
      select * into v_raiz from public.movimiento m where m.id = v_origen.raiz_id;

      -- T4 · Lo que espera aprobación, o fue rechazado, no avanza.
      if 'pendiente' in (v_raiz.aprobacion, v_origen.aprobacion) then
        raise exception 'T4 · Este gasto espera aprobación: no se causa ni se paga todavía';
      end if;
      if 'rechazado' in (v_raiz.aprobacion, v_origen.aprobacion) then
        raise exception 'T4 · Este gasto fue rechazado: no se causa ni se paga';
      end if;

      -- T4 · Si un eslabón crece por encima del primero y llega al umbral,
      -- vuelve a pedir aprobación: el compromiso no se infla de a poco.
      if new.naturaleza = 'cargo' and new.valor > v_raiz.valor and new.valor >= v_umbral
         and not new.conciliado and new.aprobacion = 'no_requiere' then
        new.aprobacion := 'pendiente';
      end if;
    end if;

    -- Caja menor: no se gasta contra un fondo ya legalizado.
    if new.fondo_id is not null and exists (
         select 1 from public.fondo_caja f where f.id = new.fondo_id and f.legalizado_en is not null) then
      raise exception 'Ese fondo de caja menor ya está legalizado; abra uno nuevo';
    end if;

    -- T4 · Pide aprobación el primer eslabón de un gasto nuevo. El histórico
    -- ya conciliado y los contra-registros no la piden.
    if new.origen_id is null and new.anula_a is null and not new.conciliado
       and new.naturaleza = 'cargo' and new.valor >= v_umbral and new.aprobacion = 'no_requiere' then
      new.aprobacion := 'pendiente';
    end if;

    if v_uid is not null then
      if new.aprobacion in ('aprobado','rechazado') and not v_direccion then
        raise exception 'Solo dirección puede aprobar un movimiento';
      end if;
      if new.conciliado and not private.tiene_rol('{socio,director,financiero}'::public.rol_persona[]) then
        raise exception 'Solo finanzas o dirección concilian un movimiento';
      end if;
    end if;

  else
    -- T3 · Lo registrado no se edita.
    if new.proyecto_id <> old.proyecto_id or new.centro_costo_id <> old.centro_costo_id
       or new.estado <> old.estado or new.naturaleza <> old.naturaleza or new.valor <> old.valor
       or new.fecha <> old.fecha or new.origen_id is distinct from old.origen_id
       or new.anula_a is distinct from old.anula_a or new.raiz_id is distinct from old.raiz_id
       or new.fondo_id is distinct from old.fondo_id or new.registrado_por <> old.registrado_por
       or new.registrado_en <> old.registrado_en then
      raise exception 'Un movimiento registrado no se edita: se anula con un contra-registro y se registra de nuevo';
    end if;

    if v_uid is not null and not v_direccion
       and (to_jsonb(new) - '{conciliado,conciliado_en}'::text[])
           <> (to_jsonb(old) - '{conciliado,conciliado_en}'::text[]) then
      raise exception 'Finanzas solo marca la conciliación; lo demás lo corrige dirección';
    end if;

    if new.aprobacion <> old.aprobacion then
      if v_uid is not null and not v_direccion then
        raise exception 'Solo dirección puede aprobar un movimiento';
      end if;
      if old.aprobacion in ('aprobado','rechazado') then
        raise exception 'La decisión sobre este gasto ya se tomó. Si cambió, anúlelo y regístrelo de nuevo';
      end if;
    end if;
  end if;

  if v_uid is not null and new.aprobacion = 'aprobado'
     and (tg_op = 'INSERT' or old.aprobacion <> 'aprobado')
     and new.aprobado_por is distinct from private.persona_actual() then
    raise exception 'La aprobación queda a nombre de quien aprueba';
  end if;

  -- T1 · Quien registra no aprueba lo propio.
  if new.aprobacion = 'aprobado' and new.aprobado_por = new.registrado_por then
    raise exception 'Segregación de funciones: quien registra no puede aprobar el mismo movimiento';
  end if;

  return new;
end $$;

drop trigger if exists tr_movimiento_validar on public.movimiento;
create trigger tr_movimiento_validar
  before insert or update on public.movimiento
  for each row execute function private.validar_movimiento();

-- Caja menor: no se legaliza con gastos sin soporte, y legalizada no cambia.
create or replace function private.validar_fondo_caja() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_sin_soporte integer;
begin
  if old.legalizado_en is not null
     and (new.valor <> old.valor or new.responsable_id <> old.responsable_id
          or new.legalizado_en is distinct from old.legalizado_en) then
    raise exception 'Un fondo de caja menor legalizado no se modifica';
  end if;

  if new.valor <> old.valor and exists (select 1 from public.movimiento m where m.fondo_id = new.id) then
    raise exception 'El valor entregado no cambia cuando ya hay gastos: entregue un fondo nuevo';
  end if;

  if old.legalizado_en is null and new.legalizado_en is not null then
    select count(*) into v_sin_soporte
    from public.movimiento m
    where m.fondo_id = new.id and m.naturaleza = 'cargo' and m.anula_a is null
      and not exists (select 1 from public.movimiento x where x.anula_a = m.id)
      and not exists (select 1 from public.evidencia e where e.movimiento_id = m.id);
    if v_sin_soporte > 0 then
      raise exception 'La caja menor no se legaliza con % gasto(s) sin soporte', v_sin_soporte;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists tr_fondo_caja_validar on public.fondo_caja;
create trigger tr_fondo_caja_validar
  before update on public.fondo_caja
  for each row execute function private.validar_fondo_caja();

-- O1 y O9 · Coherencia del adicional y de la decisión del cliente.
create or replace function private.validar_adicional() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_portal boolean;
begin
  if new.reemplaza_item_id is not null and not exists (
       select 1 from public.item_presupuesto i
       join public.capitulo c on c.id = i.capitulo_id
       join public.presupuesto pr on pr.id = c.presupuesto_id
       where i.id = new.reemplaza_item_id and pr.proyecto_id = new.proyecto_id) then
    raise exception 'O9 · El ítem que reemplaza este adicional no es de este proyecto';
  end if;
  if new.elemento_id is not null and not exists (
       select 1 from public.elemento_diseno e where e.id = new.elemento_id and e.proyecto_id = new.proyecto_id) then
    raise exception 'El elemento de diseño no es de este proyecto';
  end if;
  if new.cambio_obra_id is not null and not exists (
       select 1 from public.cambio_obra co where co.id = new.cambio_obra_id and co.proyecto_id = new.proyecto_id) then
    raise exception 'El cambio en obra no es de este proyecto';
  end if;

  if tg_op = 'UPDATE' and old.aprobacion in ('aprobado','rechazado')
     and (new.cantidad <> old.cantidad or new.valor_unitario <> old.valor_unitario
          or new.proyecto_id <> old.proyecto_id or new.aprobacion <> old.aprobacion
          or new.asume <> old.asume) then
    raise exception 'O1 · Un adicional con decisión del cliente no se modifica: registre uno nuevo';
  end if;

  if new.aprobacion in ('aprobado','rechazado')
     and (tg_op = 'INSERT' or new.aprobacion <> old.aprobacion) then
    v_portal := new.medio_aprobacion = 'portal' and exists (
      select 1 from public.aprobacion_cliente ac
      where ac.adicional_id = new.id and ac.persona_id = new.aprobado_por_id
        and ac.decision = new.aprobacion);
    if auth.uid() is not null and not private.es_direccion() and not coalesce(v_portal, false) then
      raise exception 'O1 · Solo dirección registra la decisión del cliente, o el cliente desde el portal';
    end if;
    if new.aprobacion = 'aprobado' and new.medio_aprobacion is null then
      raise exception 'O1 · Registre por qué medio aprobó el cliente: acta, portal, correo o WhatsApp';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists tr_adicional_validar on public.adicional;
create trigger tr_adicional_validar
  before insert or update on public.adicional
  for each row execute function private.validar_adicional();

-- M-08 · El cliente decide desde el portal; la decisión se copia al adicional.
create or replace function private.preparar_aprobacion_cliente() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_aprobacion public.estado_aprobacion;
begin
  if auth.uid() is not null then
    if private.es_interno() then
      raise exception 'M-08 · Esta decisión la toma el cliente desde el portal. Dirección la registra en el adicional';
    end if;
    new.persona_id := private.persona_actual();
  end if;
  new.decidido_en := now();

  select a.aprobacion into v_aprobacion from public.adicional a where a.id = new.adicional_id for update;
  if v_aprobacion is distinct from 'pendiente' then
    raise exception 'Este adicional ya tiene decisión del cliente';
  end if;
  return new;
end $$;

create or replace function private.aplicar_aprobacion_cliente() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.adicional a set
    aprobacion         = new.decision,
    aprobado_por_id    = new.persona_id,
    aprobado_por_texto = (select p.nombre from public.persona p where p.id = new.persona_id),
    aprobado_en        = (new.decidido_en at time zone 'America/Bogota')::date,
    medio_aprobacion   = 'portal'
  where a.id = new.adicional_id;
  return null;
end $$;

drop trigger if exists tr_aprobacion_cliente_preparar on public.aprobacion_cliente;
create trigger tr_aprobacion_cliente_preparar
  before insert on public.aprobacion_cliente
  for each row execute function private.preparar_aprobacion_cliente();

drop trigger if exists tr_aprobacion_cliente_aplicar on public.aprobacion_cliente;
create trigger tr_aprobacion_cliente_aplicar
  after insert on public.aprobacion_cliente
  for each row execute function private.aplicar_aprobacion_cliente();

drop trigger if exists tr_aprobacion_cliente_no_editar on public.aprobacion_cliente;
create trigger tr_aprobacion_cliente_no_editar
  before update on public.aprobacion_cliente
  for each row execute function private.prohibir_edicion();

drop trigger if exists tr_acta_item_no_editar on public.acta_item;
create trigger tr_acta_item_no_editar
  before update on public.acta_item
  for each row execute function private.prohibir_edicion();

-- O4 · La bitácora no se escribe por adelantado ni se reescribe después.
create or replace function private.validar_bitacora() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.fecha > private.hoy() then
    raise exception 'La bitácora no se registra por adelantado';
  end if;
  if tg_op = 'INSERT' and auth.uid() is not null then
    new.registrado_por := coalesce(private.persona_actual(), new.registrado_por);
  end if;
  if tg_op = 'UPDATE' then
    if new.proyecto_id <> old.proyecto_id or new.fecha <> old.fecha or new.registrado_por <> old.registrado_por then
      raise exception 'La bitácora no cambia de proyecto, de fecha ni de autor';
    end if;
    if auth.uid() is not null and (old.registrado_en at time zone 'America/Bogota')::date < private.hoy() then
      raise exception 'O4 · La bitácora de un día anterior no se edita: registre la novedad en la de hoy';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists tr_bitacora_validar on public.bitacora;
create trigger tr_bitacora_validar
  before insert or update on public.bitacora
  for each row execute function private.validar_bitacora();

-- O6 · Un acta de pago no supera lo ejecutado. O1 · no se cobra un adicional
-- que el cliente no aprobó.
create or replace function private.validar_acta_item() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_acta       public.acta%rowtype;
  v_ejecutado  numeric;
  v_acumulado  numeric;
  v_desc       text;
begin
  select * into v_acta from public.acta a where a.id = new.acta_id;
  if v_acta.anulada then
    raise exception 'El acta está anulada';
  end if;

  if new.item_id is not null then
    if not exists (
         select 1 from public.item_presupuesto i
         join public.capitulo c on c.id = i.capitulo_id
         join public.presupuesto pr on pr.id = c.presupuesto_id
         where i.id = new.item_id and pr.proyecto_id = v_acta.proyecto_id) then
      raise exception 'El ítem no es del proyecto del acta';
    end if;

    if v_acta.tipo = 'pago_contratista' then
      select coalesce(e.cantidad_proyectada * e.pct_avance, 0), i.descripcion
        into v_ejecutado, v_desc
      from public.item_presupuesto i
      left join public.ejecucion_item e on e.item_id = i.id
      where i.id = new.item_id;

      select coalesce(sum(ai.cantidad), 0) into v_acumulado
      from public.acta_item ai
      join public.acta a on a.id = ai.acta_id
      where ai.item_id = new.item_id and a.tipo = 'pago_contratista' and not a.anulada
        and ai.id <> new.id;

      if v_acumulado + new.cantidad > coalesce(v_ejecutado, 0) + 0.0001 then
        raise exception 'O6 · Las actas de pago sumarían % de «%» y lo ejecutado es %. Registre primero el avance.',
          replace(round(v_acumulado + new.cantidad, 2)::text, '.', ','), v_desc,
          replace(round(coalesce(v_ejecutado, 0), 2)::text, '.', ',');
      end if;
    end if;
  end if;

  if new.adicional_id is not null then
    if not exists (select 1 from public.adicional ad
                   where ad.id = new.adicional_id and ad.proyecto_id = v_acta.proyecto_id) then
      raise exception 'El adicional no es del proyecto del acta';
    end if;
    if v_acta.tipo = 'cobro_cliente' and not exists (
         select 1 from public.adicional ad where ad.id = new.adicional_id and ad.aprobacion = 'aprobado') then
      raise exception 'O1 · No se cobra un adicional que el cliente no ha aprobado';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists tr_acta_item_validar on public.acta_item;
create trigger tr_acta_item_validar
  before insert or update on public.acta_item
  for each row execute function private.validar_acta_item();

-- P5 · Evidencia: del mismo proyecto que lo que soporta, y nunca editable.
create or replace function private.validar_evidencia() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_proyectos uuid[];
begin
  if tg_op = 'UPDATE' then
    raise exception 'P5 · La evidencia no se edita: si hay un error, se sube una nueva';
  end if;

  select array_agg(distinct s.proyecto_id) into v_proyectos from (
    select m.proyecto_id from public.movimiento m where m.id = new.movimiento_id
    union all select b.proyecto_id from public.bitacora b where b.id = new.bitacora_id
    union all select c.proyecto_id from public.cambio_obra c where c.id = new.cambio_obra_id
    union all select a.proyecto_id from public.adicional a where a.id = new.adicional_id
    union all select r.proyecto_id from public.reclamacion r where r.id = new.reclamacion_id
    union all select d.proyecto_id from public.pendiente_obra d where d.id = new.pendiente_id
  ) s;

  if coalesce(cardinality(v_proyectos), 0) <> 1 then
    raise exception 'La evidencia debe soportar registros de un mismo proyecto';
  end if;
  new.proyecto_id := v_proyectos[1];

  if new.ruta not like new.proyecto_id::text || '/%' then
    raise exception 'La ruta de la evidencia empieza por el id del proyecto: %/...', new.proyecto_id;
  end if;
  if auth.uid() is not null then
    new.registrada_por := private.persona_actual();
  end if;
  return new;
end $$;

drop trigger if exists tr_evidencia_validar on public.evidencia;
create trigger tr_evidencia_validar
  before insert or update on public.evidencia
  for each row execute function private.validar_evidencia();



-- ---------- Objetivos y pendientes de obra ----------

-- D8 · Un objetivo no se declara logrado: se logra cuando no queda trabajo
-- abierto colgado de él. Nadie escribe un porcentaje.
create or replace function private.validar_objetivo() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_tareas     integer;
  v_pendientes integer;
begin
  if tg_op = 'INSERT' and auth.uid() is not null then
    new.creado_por := coalesce(private.persona_actual(), new.creado_por);
  end if;

  if new.ambito = 'proyecto' and not exists (
       select 1 from public.proyecto p where p.id = new.proyecto_id) then
    raise exception 'El objetivo apunta a un proyecto que no existe';
  end if;

  if new.estado = 'logrado' and (tg_op = 'INSERT' or old.estado <> 'logrado') then
    select count(*) into v_tareas
    from public.tarea_diseno t
    where t.objetivo_id = new.id and t.estado <> 'terminada';

    select count(*) into v_pendientes
    from public.pendiente_obra d
    where d.objetivo_id = new.id and d.estado not in ('cerrado','descartado');

    if v_tareas + v_pendientes > 0 then
      raise exception 'D8 · «%» todavía tiene % sin cerrar. El objetivo se logra cuando se cierra el trabajo, no cuando alguien lo declara.',
        new.titulo,
        case when v_tareas + v_pendientes = 1 then 'una cosa'
             else (v_tareas + v_pendientes)::text || ' cosas' end;
    end if;
  end if;

  if new.estado <> 'en_curso' then
    new.cerrado_en  := coalesce(new.cerrado_en, now());
    new.cerrado_por := coalesce(new.cerrado_por, private.persona_actual(), new.responsable_id);
  end if;
  return new;
end $$;

drop trigger if exists tr_objetivo_validar on public.objetivo;
create trigger tr_objetivo_validar
  before insert or update on public.objetivo
  for each row execute function private.validar_objetivo();

-- O11 · Un pendiente de obra se cierra cuando alguien distinto de quien lo
-- ejecutó confirma que quedó bien. Si mueve plata, no se cierra sin el
-- movimiento: así «comprar teja» deja de ser una línea sin monto.
create or replace function private.validar_pendiente() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_quien_ejecuto uuid := coalesce(new.ejecutor_id, new.responsable_id);
  v_bloqueador    public.pendiente_obra%rowtype;
begin
  if tg_op = 'INSERT' and auth.uid() is not null then
    new.creado_por := coalesce(private.persona_actual(), new.creado_por);
  end if;

  if new.fase_id is not null and not exists (
       select 1 from public.proyecto_fase f
       where f.id = new.fase_id and f.proyecto_id = new.proyecto_id) then
    raise exception 'La fase no es del proyecto del pendiente';
  end if;

  if new.elemento_id is not null and not exists (
       select 1 from public.elemento_diseno e
       where e.id = new.elemento_id and e.proyecto_id = new.proyecto_id) then
    raise exception 'El elemento de diseño no es del proyecto del pendiente';
  end if;

  if new.movimiento_id is not null and not exists (
       select 1 from public.movimiento m
       where m.id = new.movimiento_id and m.proyecto_id = new.proyecto_id) then
    raise exception 'El gasto no es del proyecto del pendiente';
  end if;

  if new.objetivo_id is not null and not exists (
       select 1 from public.objetivo o
       where o.id = new.objetivo_id
         and (o.ambito <> 'proyecto' or o.proyecto_id = new.proyecto_id)) then
    raise exception 'El objetivo es de otro proyecto';
  end if;

  if new.bloqueado_por is not null then
    select * into v_bloqueador from public.pendiente_obra b where b.id = new.bloqueado_por;
    if v_bloqueador.proyecto_id <> new.proyecto_id then
      raise exception 'Un pendiente solo lo bloquea otro del mismo proyecto';
    end if;
  end if;

  -- El estado sale del hecho: si alguien verificó, está cerrado.
  if new.verificado_por is not null and new.estado not in ('descartado','cerrado') then
    new.estado := 'cerrado';
  end if;

  if new.estado = 'cerrado' then
    if new.verificado_por is null then
      raise exception 'O11 · «%» no se cierra sin que alguien verifique que quedó hecho', new.titulo;
    end if;
    if new.verificado_por = v_quien_ejecuto then
      raise exception 'O11 · «%» la verifica alguien distinto de quien la ejecutó', new.titulo;
    end if;
    if new.tipo = 'compra' and new.movimiento_id is null then
      raise exception 'O11 · «%» es una compra: antes de cerrarla, cuelgue el gasto con su valor y su aprobación', new.titulo;
    end if;
    if new.bloqueado_por is not null and v_bloqueador.estado not in ('cerrado','descartado') then
      raise exception 'O11 · «%» espera a que se cierre «%»', new.titulo, v_bloqueador.titulo;
    end if;
    new.verificado_en := coalesce(new.verificado_en, now());
  end if;
  return new;
end $$;

drop trigger if exists tr_pendiente_obra_validar on public.pendiente_obra;
create trigger tr_pendiente_obra_validar
  before insert or update on public.pendiente_obra
  for each row execute function private.validar_pendiente();

-- ---------- Presupuestos ----------

-- O8 imprevistos, O10 margen de obra y validación profesional obligatoria.
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
                   where p.id = new.validado_por and p.rol in ('socio','director','arquitecto')) then
      raise exception 'La validación de un presupuesto la firma un profesional: socio, director o arquitecto';
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

drop trigger if exists tr_presupuesto_validar on public.presupuesto;
create trigger tr_presupuesto_validar
  before insert or update on public.presupuesto
  for each row execute function private.validar_presupuesto();

-- Un presupuesto emitido no se reescribe: los cambios van en una versión
-- nueva o como adicional.
create or replace function private.bloquear_presupuesto_emitido() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_presupuesto  uuid;
  v_estado       public.estado_presupuesto;
begin
  if tg_table_name = 'capitulo' then
    v_presupuesto := coalesce(new.presupuesto_id, old.presupuesto_id);
  else
    select c.presupuesto_id into v_presupuesto
    from public.capitulo c where c.id = coalesce(new.capitulo_id, old.capitulo_id);
  end if;

  select pr.estado into v_estado from public.presupuesto pr where pr.id = v_presupuesto;
  if v_estado in ('emitido','aprobado_cliente','reemplazado') then
    raise exception 'El presupuesto ya se emitió: los cambios van en una versión nueva o como adicional';
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists tr_capitulo_bloquear on public.capitulo;
create trigger tr_capitulo_bloquear
  before insert or update or delete on public.capitulo
  for each row execute function private.bloquear_presupuesto_emitido();

drop trigger if exists tr_item_presupuesto_bloquear on public.item_presupuesto;
create trigger tr_item_presupuesto_bloquear
  before insert or update or delete on public.item_presupuesto
  for each row execute function private.bloquear_presupuesto_emitido();

-- O5 · Quién movió el avance y cuándo.
create or replace function private.preparar_ejecucion() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.actualizado_en := now();
  if auth.uid() is not null then
    new.actualizado_por := private.persona_actual();
  end if;
  return new;
end $$;

drop trigger if exists tr_ejecucion_item_preparar on public.ejecucion_item;
create trigger tr_ejecucion_item_preparar
  before insert or update on public.ejecucion_item
  for each row execute function private.preparar_ejecucion();


-- ---------- Obra: cambios decididos en sitio ----------

create or replace function private.preparar_cambio_obra() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is not null then
    if tg_op = 'INSERT' then
      new.decidido_por := coalesce(private.persona_actual(), new.decidido_por);
    end if;
    if new.reflejado_en_diseno_en is not null
       and (tg_op = 'INSERT' or old.reflejado_en_diseno_en is null) then
      new.reflejado_por := private.persona_actual();
    end if;
  end if;
  if tg_op = 'UPDATE' and (new.descripcion <> old.descripcion or new.proyecto_id <> old.proyecto_id
                           or new.decidido_por <> old.decidido_por or new.fecha <> old.fecha) then
    raise exception 'Un cambio en obra registrado no se reescribe: registre uno nuevo';
  end if;
  return new;
end $$;

drop trigger if exists tr_cambio_obra_preparar on public.cambio_obra;
create trigger tr_cambio_obra_preparar
  before insert or update on public.cambio_obra
  for each row execute function private.preparar_cambio_obra();


-- ---------- Diseño ----------

-- D1 · Compuerta de fase. D2 · sin dedicación completa no hay cierre.
create or replace function private.validar_fase() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_hoy        date := private.hoy();
  v_pendiente  text;
  v_persona    record;
  v_faltan     integer;
  v_cierra     boolean;
begin
  if tg_op = 'UPDATE' and old.estado = 'cerrada' and new.estado <> 'cerrada' then
    if auth.uid() is not null and not private.tiene_rol('{socio}'::public.rol_persona[]) then
      raise exception 'D1 · Una fase cerrada solo la reabre un socio';
    end if;
    new.cerrada_en := null;
    new.cerrada_por := null;
  end if;

  -- No se abre una fase mientras las anteriores no estén cerradas.
  if new.estado <> 'pendiente' and (tg_op = 'INSERT' or old.estado = 'pendiente') then
    select string_agg(f.fase::text, ', ' order by f.orden) into v_pendiente
    from public.proyecto_fase f
    where f.proyecto_id = new.proyecto_id and f.orden < new.orden and f.estado <> 'cerrada';
    if v_pendiente is not null then
      raise exception 'D1 · No se abre % mientras no estén cerradas: %', new.fase, v_pendiente;
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
    if not exists (select 1 from public.chequeo c where c.fase_id = new.id and private.chequeo_completo(c.id)) then
      raise exception 'D1 · La lista de chequeo de % no está completa', new.fase;
    end if;
    if new.fase = 'anteproyecto' and new.aprobada_cliente_en is null then
      raise exception 'D1 · El anteproyecto no se cierra sin la aprobación del cliente';
    end if;
    if not exists (select 1 from public.dedicacion d where d.fase_id = new.id) then
      raise exception 'D2 · La fase % no tiene dedicación registrada', new.fase;
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
    new.cerrada_en := coalesce(new.cerrada_en, now());
    if auth.uid() is not null then
      new.cerrada_por := private.persona_actual();
    end if;
  end if;
  return new;
end $$;

drop trigger if exists tr_proyecto_fase_validar on public.proyecto_fase;
create trigger tr_proyecto_fase_validar
  before insert or update on public.proyecto_fase
  for each row execute function private.validar_fase();

-- D2 · Registro en dos toques: persona, horas y fase se deducen solos.
create or replace function private.validar_dedicacion() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_hoy        date := private.hoy();
  v_horas      numeric;
  v_dias       smallint;
  v_tarea_proy uuid;
  v_tarea_fase uuid;
begin
  select p.horas_por_bloque, p.dias_edicion_dedicacion into v_horas, v_dias
  from public.parametro p where p.id;

  if auth.uid() is not null then
    if tg_op = 'INSERT' and new.persona_id is null then
      new.persona_id := private.persona_actual();
    end if;
    if not private.es_direccion()
       and (new.fecha < v_hoy - v_dias or (tg_op = 'UPDATE' and old.fecha < v_hoy - v_dias)) then
      raise exception 'D2 · Pasados % días, la dedicación la corrige dirección', v_dias;
    end if;
  end if;
  if new.fecha > v_hoy then
    raise exception 'D2 · La dedicación no se registra por adelantado';
  end if;

  new.horas := coalesce(new.horas, v_horas);

  if new.tarea_id is not null then
    select t.proyecto_id, t.fase_id into v_tarea_proy, v_tarea_fase
    from public.tarea_diseno t where t.id = new.tarea_id;
    if v_tarea_proy is distinct from new.proyecto_id then
      raise exception 'La tarea no es del proyecto al que se asigna el tiempo';
    end if;
    new.fase_id := coalesce(new.fase_id, v_tarea_fase);
  end if;

  if new.proyecto_id is not null and new.fase_id is null then
    select f.id into new.fase_id
    from public.proyecto_fase f
    where f.proyecto_id = new.proyecto_id and f.estado in ('en_curso','en_revision')
    order by f.orden desc
    limit 1;
  end if;

  if new.fase_id is not null and not exists (
       select 1 from public.proyecto_fase f where f.id = new.fase_id and f.proyecto_id = new.proyecto_id) then
    raise exception 'La fase no es del proyecto al que se asigna el tiempo';
  end if;
  return new;
end $$;

drop trigger if exists tr_dedicacion_validar on public.dedicacion;
create trigger tr_dedicacion_validar
  before insert or update on public.dedicacion
  for each row execute function private.validar_dedicacion();

-- Una tarea no se termina sin la revisión aprobada de otra persona.
create or replace function private.validar_tarea() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.fase_id is not null and not exists (
       select 1 from public.proyecto_fase f where f.id = new.fase_id and f.proyecto_id = new.proyecto_id) then
    raise exception 'La fase no es del proyecto de la tarea';
  end if;
  if tg_op = 'INSERT' and auth.uid() is not null then
    new.asignada_por := coalesce(private.persona_actual(), new.asignada_por);
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
  if new.estado = 'terminada' and (tg_op = 'INSERT' or old.estado <> 'terminada') then
    if exists (select 1 from public.tarea_diseno b
               where b.id = new.bloqueada_por and b.estado <> 'terminada') then
      raise exception 'D9 · «%» espera a que se termine la tarea que la bloquea', new.titulo;
    end if;
    if not exists (
         select 1 from public.revision_diseno r
         where r.tarea_id = new.id and r.resultado = 'aprobada' and r.revisor_id <> new.asignada_a) then
      raise exception 'Una tarea no se termina sin la revisión aprobada de alguien distinto de quien la hizo';
    end if;
    new.terminada_en := coalesce(new.terminada_en, now());
  end if;
  return new;
end $$;

drop trigger if exists tr_tarea_diseno_validar on public.tarea_diseno;
create trigger tr_tarea_diseno_validar
  before insert or update on public.tarea_diseno
  for each row execute function private.validar_tarea();

create or replace function private.validar_revision() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_asignada uuid;
begin
  if auth.uid() is not null then
    new.revisor_id := private.persona_actual();
  end if;
  select t.asignada_a into v_asignada from public.tarea_diseno t where t.id = new.tarea_id;
  if new.revisor_id = v_asignada then
    raise exception 'La revisión la hace alguien distinto de quien hizo la tarea';
  end if;
  new.revisada_en := now();
  return new;
end $$;

create or replace function private.aplicar_revision() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.resultado = 'con_observaciones' then
    update public.tarea_diseno set estado = 'con_observaciones'
     where id = new.tarea_id and estado <> 'terminada';
  end if;
  return null;
end $$;

drop trigger if exists tr_revision_diseno_validar on public.revision_diseno;
create trigger tr_revision_diseno_validar
  before insert on public.revision_diseno
  for each row execute function private.validar_revision();

drop trigger if exists tr_revision_diseno_aplicar on public.revision_diseno;
create trigger tr_revision_diseno_aplicar
  after insert on public.revision_diseno
  for each row execute function private.aplicar_revision();

-- D5 · La versión la pone el sistema; lo entregado no se reescribe.
create or replace function private.validar_entregable() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    select coalesce(max(e.version), 0) + 1 into new.version
    from public.entregable e
    where e.proyecto_id = new.proyecto_id and e.nombre = new.nombre;
    if auth.uid() is not null then
      new.registrado_por := coalesce(private.persona_actual(), new.registrado_por);
    end if;
    if new.fase_id is not null and not exists (
         select 1 from public.proyecto_fase f where f.id = new.fase_id and f.proyecto_id = new.proyecto_id) then
      raise exception 'La fase no es del proyecto del entregable';
    end if;
  elsif (to_jsonb(new) - '{aprobado_cliente_en,aprobado_por_texto}'::text[])
        <> (to_jsonb(old) - '{aprobado_cliente_en,aprobado_por_texto}'::text[]) then
    raise exception 'D5 · Un entregable enviado no se modifica: se emite una versión nueva';
  end if;
  return new;
end $$;

drop trigger if exists tr_entregable_validar on public.entregable;
create trigger tr_entregable_validar
  before insert or update on public.entregable
  for each row execute function private.validar_entregable();

-- D7 · No se radica en curaduría sin la lista completa.
create or replace function private.validar_radicacion() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.estado <> 'preparacion'
     and ((tg_op = 'UPDATE' and old.estado = 'preparacion') or (tg_op = 'INSERT' and auth.uid() is not null)) then
    if not exists (select 1 from public.chequeo c where c.radicacion_id = new.id and private.chequeo_completo(c.id)) then
      raise exception 'D7 · No se radica en curaduría sin la lista de chequeo completa';
    end if;
    new.radicada_en := coalesce(new.radicada_en, private.hoy());
  end if;
  if new.estado in ('aprobada','negada') then
    new.resuelta_en := coalesce(new.resuelta_en, private.hoy());
  end if;
  return new;
end $$;

drop trigger if exists tr_radicacion_licencia_validar on public.radicacion_licencia;
create trigger tr_radicacion_licencia_validar
  before insert or update on public.radicacion_licencia
  for each row execute function private.validar_radicacion();


-- ---------- Listas de chequeo ----------

create or replace function private.validar_chequeo() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_lista   public.lista_chequeo%rowtype;
  v_proy    uuid;
  v_fase    public.fase_proyecto;
  v_aseg    uuid;
  v_ambito  public.ambito_chequeo;
begin
  select * into v_lista from public.lista_chequeo l where l.id = new.lista_id;

  if new.fase_id is not null then
    select f.proyecto_id, f.fase into v_proy, v_fase from public.proyecto_fase f where f.id = new.fase_id;
    v_ambito := 'fase_diseno';
    if v_lista.fase is not null and v_lista.fase <> v_fase then
      raise exception 'Esta lista es para la fase %, no para %', v_lista.fase, v_fase;
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

drop trigger if exists tr_chequeo_validar on public.chequeo;
create trigger tr_chequeo_validar
  before insert on public.chequeo
  for each row execute function private.validar_chequeo();

drop trigger if exists tr_chequeo_no_editar on public.chequeo;
create trigger tr_chequeo_no_editar
  before update on public.chequeo
  for each row execute function private.prohibir_edicion();

create or replace function private.validar_chequeo_respuesta() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_lista  uuid;
  v_item   public.lista_chequeo_item%rowtype;
begin
  select c.lista_id into v_lista from public.chequeo c where c.id = new.chequeo_id;
  select * into v_item from public.lista_chequeo_item i where i.id = new.item_id;
  if v_item.lista_id is distinct from v_lista then
    raise exception 'Ese punto no pertenece a esta lista de chequeo';
  end if;
  if new.cumple and v_item.requiere_evidencia and new.evidencia_ruta is null then
    raise exception 'Este punto exige evidencia para marcarse como cumplido: %', v_item.texto;
  end if;
  if auth.uid() is not null then
    new.verificado_por := private.persona_actual();
  end if;
  new.verificado_en := now();
  return new;
end $$;

drop trigger if exists tr_chequeo_respuesta_validar on public.chequeo_respuesta;
create trigger tr_chequeo_respuesta_validar
  before insert or update on public.chequeo_respuesta
  for each row execute function private.validar_chequeo_respuesta();


-- ---------- Reclamaciones ----------

-- P1, P2, P3 y P6 · La cascada solo avanza por los pasos que existen.
create or replace function private.validar_reclamacion() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_permitidas public.estado_reclamacion[];
begin
  if tg_op = 'UPDATE' and new.estado <> old.estado then
    v_permitidas := (case old.estado
      when 'en_expediente'      then '{conciliada,desistida}'
      when 'conciliada'         then '{radicada,en_expediente,desistida}'
      when 'radicada'           then '{objetada,aprobada,negada}'
      when 'objetada'           then '{radicada,aprobada,negada,desistida}'
      when 'aprobada'           then '{pagada_a_asegurado}'
      when 'pagada_a_asegurado' then '{pagada_a_abogados,pagada_a_esa}'
      when 'pagada_a_abogados'  then '{pagada_a_esa}'
      else '{}'
    end)::public.estado_reclamacion[];

    if not (new.estado = any (v_permitidas)) then
      raise exception 'P3 · Una reclamación no pasa de % a %', old.estado, new.estado;
    end if;

    if new.estado = 'conciliada' then
      if not exists (select 1 from public.chequeo c
                     where c.reclamacion_id = new.id and private.chequeo_completo(c.id)) then
        raise exception 'P1 · El expediente no se concilia con la lista de chequeo de la póliza incompleta';
      end if;
      if new.aval_estructural_en is null then
        raise exception 'P6 · El expediente no se concilia sin el aval del ingeniero especialista';
      end if;
      if new.conciliada_en is null then
        raise exception 'P2 · Registre la fecha y quién de la oficina de abogados confirmó que el expediente sirve para el cobro';
      end if;
    end if;

    if new.estado = 'radicada' then
      new.radicada_en := coalesce(new.radicada_en, private.hoy());
    end if;
  end if;
  return new;
end $$;

create or replace function private.historial_reclamacion() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' or new.estado <> old.estado then
    insert into public.reclamacion_evento (reclamacion_id, estado_anterior, estado_nuevo, persona_id)
    values (new.id, case when tg_op = 'UPDATE' then old.estado end, new.estado, private.persona_actual());
  end if;
  return null;
end $$;

drop trigger if exists tr_reclamacion_validar on public.reclamacion;
create trigger tr_reclamacion_validar
  before insert or update on public.reclamacion
  for each row execute function private.validar_reclamacion();

drop trigger if exists tr_reclamacion_historial on public.reclamacion;
create trigger tr_reclamacion_historial
  after insert or update on public.reclamacion
  for each row execute function private.historial_reclamacion();

drop trigger if exists tr_reclamacion_evento_no_editar on public.reclamacion_evento;
create trigger tr_reclamacion_evento_no_editar
  before update on public.reclamacion_evento
  for each row execute function private.prohibir_edicion();


-- ---------- Finanzas ----------

-- Igual que el gasto: F6 y T3 sobre cada ingreso.
create or replace function private.validar_ingreso() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_anulado public.ingreso%rowtype;
begin
  if private.mes_cerrado(new.fecha) or (tg_op = 'UPDATE' and private.mes_cerrado(old.fecha)) then
    raise exception 'F6 · El mes % está cerrado. Registre el ajuste en el mes siguiente.', to_char(new.fecha, 'YYYY-MM');
  end if;

  if new.acta_id is not null and not exists (
       select 1 from public.acta a
       where a.id = new.acta_id and a.proyecto_id = new.proyecto_id
         and a.tipo = 'cobro_cliente' and not a.anulada) then
    raise exception 'El acta indicada no es un acta de cobro vigente de este proyecto';
  end if;

  if tg_op = 'INSERT' then
    if new.anula_a is not null then
      select * into v_anulado from public.ingreso i where i.id = new.anula_a;
      if not found then
        raise exception 'El ingreso que se quiere anular no existe';
      end if;
      if v_anulado.anula_a is not null then
        raise exception 'Un contra-registro no se anula: registre de nuevo el ingreso correcto';
      end if;
      if v_anulado.valor <> new.valor or v_anulado.proyecto_id is distinct from new.proyecto_id
         or v_anulado.linea <> new.linea then
        raise exception 'El contra-registro debe repetir proyecto, línea y valor del ingreso que anula';
      end if;
    end if;
    if auth.uid() is not null and new.conciliado
       and not private.tiene_rol('{socio,director,financiero}'::public.rol_persona[]) then
      raise exception 'Solo finanzas o dirección concilian un ingreso';
    end if;
  elsif (to_jsonb(new) - '{conciliado,conciliado_en,concepto,cuenta_id}'::text[])
        <> (to_jsonb(old) - '{conciliado,conciliado_en,concepto,cuenta_id}'::text[]) then
    raise exception 'Un ingreso registrado no se edita: se anula con un contra-registro y se registra de nuevo';
  end if;
  return new;
end $$;

drop trigger if exists tr_ingreso_validar on public.ingreso;
create trigger tr_ingreso_validar
  before insert or update on public.ingreso
  for each row execute function private.validar_ingreso();

-- F6 · Solo meses terminados; reabrir es de un socio y deja motivo.
create or replace function private.validar_cierre_mes() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.periodo >= date_trunc('month', private.hoy())::date then
      raise exception 'F6 · Solo se cierran meses terminados';
    end if;
    if auth.uid() is not null then
      if not private.tiene_rol('{socio,financiero}'::public.rol_persona[]) then
        raise exception 'F6 · El cierre lo hace finanzas o un socio';
      end if;
      new.cerrado_por := private.persona_actual();
    end if;
  else
    if new.periodo <> old.periodo or new.cerrado_por <> old.cerrado_por or new.cerrado_en <> old.cerrado_en then
      raise exception 'F6 · Un cierre no se modifica; si hace falta, un socio reabre el mes con un motivo';
    end if;
    if new.reabierto_en is distinct from old.reabierto_en and auth.uid() is not null then
      if not private.tiene_rol('{socio}'::public.rol_persona[]) then
        raise exception 'F6 · Solo un socio reabre o vuelve a cerrar un mes';
      end if;
      if new.reabierto_en is not null then
        new.reabierto_por := private.persona_actual();
      end if;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists tr_cierre_mes_validar on public.cierre_mes;
create trigger tr_cierre_mes_validar
  before insert or update on public.cierre_mes
  for each row execute function private.validar_cierre_mes();

-- F2 · Reparte la estructura del mes entre los proyectos según las horas
-- dedicadas. Corre con los permisos de quien la llama: solo finanzas y
-- dirección ven lo necesario para calcularla y pueden escribir el resultado.
-- Regla por confirmar con Felipe (P-01): por horas dedicadas.
create or replace function public.distribuir_estructura(p_periodo date) returns integer
language plpgsql security invoker set search_path = '' as $$
declare
  v_mes     date := date_trunc('month', p_periodo)::date;
  v_hasta   date := (date_trunc('month', p_periodo) + interval '1 month')::date;
  v_costo   numeric;
  v_horas   numeric;
  v_filas   integer;
begin
  if private.mes_cerrado(v_mes) then
    raise exception 'F6 · % está cerrado: la distribución ya no se recalcula', to_char(v_mes, 'YYYY-MM');
  end if;

  select coalesce(sum(case when m.naturaleza = 'cargo' then m.valor else -m.valor end), 0) into v_costo
  from public.movimiento m
  join public.proyecto p         on p.id = m.proyecto_id
  join public.centro_costo cc    on cc.id = m.centro_costo_id
  join public.categoria_costo c  on c.id = cc.categoria_id
  where p.tipo = 'interno' and m.estado = 'pago' and not c.excluir_de_rentabilidad
    and m.anula_a is null and m.aprobacion <> 'rechazado'
    and not exists (select 1 from public.movimiento x where x.anula_a = m.id)
    and m.fecha >= v_mes and m.fecha < v_hasta;

  select coalesce(sum(d.horas), 0) into v_horas
  from public.dedicacion d
  where d.tipo = 'proyecto' and d.fecha >= v_mes and d.fecha < v_hasta;

  if v_horas = 0 then
    raise exception 'F2 · No hay dedicación a proyectos registrada en %: no hay con qué repartir la estructura',
      to_char(v_mes, 'YYYY-MM');
  end if;

  update public.distribucion_estructura
     set horas = 0, pct = 0, valor = 0, calculado_en = now()
   where periodo = v_mes;

  insert into public.distribucion_estructura (periodo, proyecto_id, horas, pct, valor, regla, calculado_en)
  select v_mes, d.proyecto_id, sum(d.horas),
         round(sum(d.horas) / v_horas, 6),
         round(v_costo * sum(d.horas) / v_horas, 2),
         'horas_dedicadas', now()
  from public.dedicacion d
  where d.tipo = 'proyecto' and d.fecha >= v_mes and d.fecha < v_hasta
  group by d.proyecto_id
  on conflict (periodo, proyecto_id) do update
    set horas = excluded.horas, pct = excluded.pct, valor = excluded.valor,
        regla = excluded.regla, calculado_en = excluded.calculado_en;

  get diagnostics v_filas = row_count;
  return v_filas;
end $$;


-- ---------- Usuarios ----------

-- Cuando alguien confirma el correo que dirección registró en su ficha, queda
-- enlazado. Si algo falla, no bloquea el ingreso: deja un aviso en el registro
-- de la base y el enlace se hace a mano. El disparador sobre auth.users se
-- crea en la migración vinculo_usuarios.
create or replace function private.vincular_persona_auth() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.email is not null and new.email_confirmed_at is not null then
    update public.persona p
       set auth_user_id = new.id
     where p.auth_user_id is null
       and p.activo
       and p.correo is not null
       and lower(p.correo) = lower(new.email)
       and not exists (select 1 from public.persona o where o.auth_user_id = new.id);
  end if;
  return new;
exception when others then
  raise warning 'SICI: no se pudo enlazar el usuario % con su ficha: %', new.id, sqlerrm;
  return new;
end $$;


-- =============================================================================
-- 13. Vistas
-- Todas con security_invoker: respetan los permisos por fila de quien consulta.
-- Las que terminan en "lectura" traen la conclusión escrita (regla U5: frases,
-- no fórmulas). Se borran y se recrean para que el archivo sea idempotente.
-- =============================================================================

do $$
declare v text;
begin
  foreach v in array array[
    'v_movimiento_vigente','v_balance_centro_costo','v_adicionales_netos','v_desviacion_capitulo',
    'v_caja_menor','v_cambios_sin_reflejar','v_proyecto_resumen','v_bitacora_faltante','v_cartera',
    'v_flujo_13_semanas','v_rentabilidad_proyecto','v_partidas_abiertas','v_fase_horas',
    'v_dedicacion_pendiente','v_capacidad_13_semanas','v_complementarios_atrasados',
    'v_reclamaciones','v_embudo_mensual','v_retorno_pauta','v_calibracion_capitulo','v_apu_costo',
    'v_pendientes_obra','v_trabajo_abierto','v_objetivos'
  ] loop
    execute format('drop view if exists public.%I cascade', v);
  end loop;
end $$;

-- ---------- Obra y dinero ----------

-- Lo que cuenta: sin contra-registros, sin lo anulado y sin lo rechazado.
create view public.v_movimiento_vigente with (security_invoker = true) as
select m.*
from public.movimiento m
where m.anula_a is null
  and m.aprobacion <> 'rechazado'
  and not exists (select 1 from public.movimiento x where x.anula_a = m.id);

-- Balance proyectivo. Por cada gasto (cadena) cuenta una sola vez el mayor de
-- sus tres estados, menos las devoluciones.
create view public.v_balance_centro_costo with (security_invoker = true) as
with por_cadena as (
  select
    m.centro_costo_id,
    m.raiz_id,
    coalesce(sum(m.valor) filter (where m.naturaleza = 'cargo' and m.estado = 'compromiso'), 0) as comp,
    coalesce(sum(m.valor) filter (where m.naturaleza = 'cargo' and m.estado = 'causacion'),  0) as caus,
    coalesce(sum(m.valor) filter (where m.naturaleza = 'cargo' and m.estado = 'pago'),       0) as pag,
    coalesce(sum(m.valor) filter (where m.naturaleza = 'devolucion'), 0)                         as dev,
    coalesce(sum(m.valor) filter (where m.naturaleza = 'devolucion' and m.estado = 'pago'), 0)   as dev_pago
  from public.v_movimiento_vigente m
  group by m.centro_costo_id, m.raiz_id
)
select
  cc.id                                                                   as centro_costo_id,
  cc.proyecto_id,
  p.codigo                                                                as proyecto,
  cat.nombre                                                              as categoria,
  cat.excluir_de_rentabilidad,
  cc.presupuesto,
  coalesce(sum(c.comp), 0)                                                as comprometido,
  coalesce(sum(c.caus), 0)                                                as causado,
  coalesce(sum(c.pag - c.dev_pago), 0)                                    as pagado,
  coalesce(sum(greatest(c.comp, c.caus, c.pag) - c.dev), 0)               as proyectado,
  coalesce(sum(greatest(c.comp, c.caus, c.pag) - c.dev - (c.pag - c.dev_pago)), 0) as por_pagar,
  cc.presupuesto - coalesce(sum(greatest(c.comp, c.caus, c.pag) - c.dev), 0)       as disponible
from public.centro_costo cc
join public.proyecto p          on p.id = cc.proyecto_id
join public.categoria_costo cat on cat.id = cc.categoria_id
left join por_cadena c          on c.centro_costo_id = cc.id
group by cc.id, cc.proyecto_id, p.codigo, cat.nombre, cat.excluir_de_rentabilidad, cc.presupuesto;

-- O2 y O9 · Adicionales netos: nunca el bruto sin el crédito al lado, y lo
-- que paga el cliente separado de lo que absorbe ESA.
create view public.v_adicionales_netos with (security_invoker = true) as
with reemplazados as (
  select distinct a.proyecto_id, a.reemplaza_item_id as item_id
  from public.adicional a
  where a.reemplaza_item_id is not null and a.aprobacion <> 'rechazado'
),
credito as (
  select r.proyecto_id,
         sum(greatest(i.valor_parcial - coalesce(e.valor_proyectado, 0), 0)) as credito
  from reemplazados r
  join public.item_presupuesto i    on i.id = r.item_id
  left join public.ejecucion_item e on e.item_id = i.id
  group by r.proyecto_id
)
select
  a.proyecto_id,
  p.codigo                                                                          as proyecto,
  count(*)                                                                          as cantidad,
  count(*) filter (where a.aprobacion = 'aprobado')                                 as aprobados,
  count(*) filter (where a.aprobacion = 'pendiente')                                as pendientes,
  count(*) filter (where a.aprobacion = 'rechazado')                                as rechazados,
  coalesce(sum(a.valor) filter (where a.aprobacion <> 'rechazado'), 0)              as bruto,
  coalesce(max(cr.credito), 0)                                                      as credito,
  coalesce(sum(a.valor) filter (where a.aprobacion <> 'rechazado'), 0)
    - coalesce(max(cr.credito), 0)                                                  as neto,
  coalesce(sum(a.valor) filter (where a.aprobacion = 'aprobado'), 0)                as bruto_aprobado,
  coalesce(sum(a.valor) filter (where a.aprobacion <> 'rechazado' and a.asume = 'cliente'), 0) as a_cargo_cliente,
  coalesce(sum(a.valor) filter (where a.aprobacion <> 'rechazado' and a.asume = 'esa'), 0)     as a_cargo_esa
from public.adicional a
join public.proyecto p      on p.id = a.proyecto_id
left join credito cr        on cr.proyecto_id = a.proyecto_id
group by a.proyecto_id, p.codigo;

-- O3 · Capítulos cuyo total a ejecutar ya supera lo presupuestado.
create view public.v_desviacion_capitulo with (security_invoker = true) as
select
  c.id                                                            as capitulo_id,
  pr.proyecto_id,
  p.codigo                                                        as proyecto,
  c.nombre                                                        as capitulo,
  sum(i.valor_parcial)                                            as presupuestado,
  coalesce(sum(e.valor_proyectado), 0)                            as proyectado,
  coalesce(sum(e.valor_proyectado), 0) - sum(i.valor_parcial)     as desviacion,
  case when sum(i.valor_parcial) > 0
       then round((coalesce(sum(e.valor_proyectado), 0) / sum(i.valor_parcial) - 1) * 100, 1)
  end                                                             as desviacion_pct,
  coalesce(sum(e.valor_avance), 0)                                as avance_valorizado
from public.capitulo c
join public.presupuesto pr        on pr.id = c.presupuesto_id and pr.vigente
join public.proyecto p            on p.id = pr.proyecto_id
join public.item_presupuesto i    on i.capitulo_id = c.id
left join public.ejecucion_item e on e.item_id = i.id
group by c.id, pr.proyecto_id, p.codigo, c.nombre;

-- Caja menor: entregado, gastado, saldo y gastos sin soporte.
create view public.v_caja_menor with (security_invoker = true) as
select
  f.id                                                             as fondo_id,
  f.responsable_id,
  r.nombre                                                         as responsable,
  f.entregado_por                                                  as entregado_por_id,
  e.nombre                                                         as entregado_por,
  f.valor                                                          as entregado,
  f.fecha_entrega,
  f.legalizado_en,
  coalesce(g.gastado, 0)                                           as gastado,
  f.valor - coalesce(g.gastado, 0)                                 as saldo,
  coalesce(g.sin_soporte, 0)                                       as gastos_sin_soporte,
  coalesce(f.legalizado_en, private.hoy()) - f.fecha_entrega       as dias_abierto
from public.fondo_caja f
join public.persona r on r.id = f.responsable_id
join public.persona e on e.id = f.entregado_por
left join lateral (
  select
    sum(case when m.naturaleza = 'devolucion' then -m.valor else m.valor end) as gastado,
    count(*) filter (
      where m.naturaleza = 'cargo'
        and not exists (select 1 from public.evidencia ev where ev.movimiento_id = m.id)) as sin_soporte
  from public.v_movimiento_vigente m
  where m.fondo_id = f.id and m.estado = 'pago'
) g on true;

-- Cambios decididos en obra que diseño todavía no ha incorporado.
create view public.v_cambios_sin_reflejar with (security_invoker = true) as
select
  co.id,
  co.proyecto_id,
  p.codigo                          as proyecto,
  co.fecha,
  co.descripcion,
  d.nombre                          as decidido_por,
  private.hoy() - co.fecha          as dias_abierto,
  co.genera_adicional
from public.cambio_obra co
join public.proyecto p on p.id = co.proyecto_id
join public.persona d  on d.id = co.decidido_por
where co.altera_diseno and co.reflejado_en_diseno_en is null;

-- Resumen por proyecto para el tablero de dirección.
create view public.v_proyecto_resumen with (security_invoker = true) as
select
  p.id,
  p.codigo,
  p.nombre,
  p.unidad,
  p.tipo,
  p.estado,
  p.fase,
  p.es_reclamacion,
  p.canal,
  p.valor_contrato,
  coalesce(b.proyectado, 0)       as costo_proyectado,
  coalesce(b.por_pagar, 0)        as por_pagar,
  coalesce(d.presupuestado, 0)    as presupuesto_obra,
  coalesce(d.proyectado, 0)       as obra_proyectada,
  coalesce(ad.neto, 0)            as adicional_neto,
  coalesce(ad.pendientes, 0)      as adicionales_pendientes,
  case when p.valor_contrato > 0
       then round((coalesce(b.proyectado, 0) / p.valor_contrato - 1) * 100, 1) end as desviacion_pct,
  case when p.valor_contrato > 0
       then round((1 - coalesce(b.proyectado, 0) / p.valor_contrato) * 100, 1) end as margen_proyectado_pct
from public.proyecto p
left join (
  select vb.proyecto_id, sum(vb.proyectado) as proyectado, sum(vb.por_pagar) as por_pagar
  from public.v_balance_centro_costo vb
  where not vb.excluir_de_rentabilidad
  group by vb.proyecto_id
) b on b.proyecto_id = p.id
left join (
  select vd.proyecto_id, sum(vd.presupuestado) as presupuestado, sum(vd.proyectado) as proyectado
  from public.v_desviacion_capitulo vd group by vd.proyecto_id
) d on d.proyecto_id = p.id
left join public.v_adicionales_netos ad on ad.proyecto_id = p.id;

-- O4 · Días de obra (lunes a sábado) sin bitácora, en los últimos 30 días.
create view public.v_bitacora_faltante with (security_invoker = true) as
select
  pr.id                   as proyecto_id,
  pr.codigo               as proyecto,
  pr.residente_id,
  g.dia::date             as fecha
from public.proyecto pr
cross join lateral generate_series(
  greatest(pr.fecha_inicio, private.hoy() - 30), private.hoy() - 1, interval '1 day') g(dia)
where pr.tipo = 'obra' and pr.estado = 'activo' and pr.fecha_inicio is not null
  and extract(isodow from g.dia) < 7
  and not exists (select 1 from public.bitacora b where b.proyecto_id = pr.id and b.fecha = g.dia::date);


-- ---------- Finanzas ----------

-- F3 · Cartera con antigüedad: cada acta de cobro menos lo recaudado.
create view public.v_cartera with (security_invoker = true) as
select
  a.id                                                          as acta_id,
  a.proyecto_id,
  p.codigo                                                      as proyecto,
  cl.nombre                                                     as cliente,
  a.numero,
  a.emitida_en,
  a.vence_en,
  a.valor - a.valor_retenido                                    as valor_a_cobrar,
  a.valor_retenido,
  coalesce(r.recaudado, 0)                                      as recaudado,
  a.valor - a.valor_retenido - coalesce(r.recaudado, 0)         as saldo,
  case when a.vence_en is not null then private.hoy() - a.vence_en end as dias_vencida,
  case
    when a.valor - a.valor_retenido - coalesce(r.recaudado, 0) <= 0 then 'pagada'
    when a.vence_en is null or a.vence_en >= private.hoy()         then 'al_dia'
    when private.hoy() - a.vence_en <= 30                          then '1_a_30'
    when private.hoy() - a.vence_en <= 60                          then '31_a_60'
    when private.hoy() - a.vence_en <= 90                          then '61_a_90'
    else 'mas_de_90'
  end                                                           as antiguedad
from public.acta a
join public.proyecto p     on p.id = a.proyecto_id
left join public.cliente cl on cl.id = p.cliente_id
left join lateral (
  select sum(i.valor) as recaudado
  from public.ingreso i
  where i.acta_id = a.id and i.anula_a is null
    and not exists (select 1 from public.ingreso x where x.anula_a = i.id)
) r on true
where a.tipo = 'cobro_cliente' and not a.anulada;

-- F4 · Flujo a 13 semanas: saldo real de las cuentas, más la cartera por
-- cobrar, menos lo comprometido por pagar. Lo vencido cae en la semana 1.
create view public.v_flujo_13_semanas with (security_invoker = true) as
with base as (
  select private.hoy() - (extract(isodow from private.hoy())::integer - 1) as lunes,
         pa.caja_minima, pa.dias_pago_estimado
  from public.parametro pa where pa.id
),
semanas as (
  select n as semana, b.lunes + (n - 1) * 7 as desde
  from base b cross join generate_series(1, 13) n
),
saldo as (
  select coalesce(sum(s.saldo), 0) as saldo, max(s.fecha) as fecha
  from public.cuenta c
  join lateral (
    select sc.saldo, sc.fecha from public.saldo_cuenta sc
    where sc.cuenta_id = c.id order by sc.fecha desc limit 1
  ) s on true
  where c.activa
),
cadenas as (
  select
    m.raiz_id,
    greatest(
      coalesce(sum(m.valor) filter (where m.naturaleza = 'cargo' and m.estado = 'compromiso'), 0),
      coalesce(sum(m.valor) filter (where m.naturaleza = 'cargo' and m.estado = 'causacion'), 0),
      coalesce(sum(m.valor) filter (where m.naturaleza = 'cargo' and m.estado = 'pago'), 0))
    - coalesce(sum(m.valor) filter (where m.naturaleza = 'devolucion'), 0)
    - (coalesce(sum(m.valor) filter (where m.naturaleza = 'cargo' and m.estado = 'pago'), 0)
       - coalesce(sum(m.valor) filter (where m.naturaleza = 'devolucion' and m.estado = 'pago'), 0)) as por_pagar,
    coalesce(max(m.fecha_prevista_pago), max(m.fecha) + (select b.dias_pago_estimado from base b)) as fecha_prevista
  from public.v_movimiento_vigente m
  group by m.raiz_id
),
salidas as (
  select greatest(1, (c.fecha_prevista - b.lunes) / 7 + 1) as semana, sum(c.por_pagar) as valor
  from cadenas c cross join base b
  where c.por_pagar > 0 and c.fecha_prevista < b.lunes + 91
  group by 1
),
entradas as (
  select greatest(1, (coalesce(ca.vence_en, private.hoy()) - b.lunes) / 7 + 1) as semana, sum(ca.saldo) as valor
  from public.v_cartera ca cross join base b
  where ca.saldo > 0 and coalesce(ca.vence_en, private.hoy()) < b.lunes + 91
  group by 1
)
select
  s.semana,
  s.desde,
  s.desde + 6                                                                   as hasta,
  coalesce(e.valor, 0)                                                          as entradas,
  coalesce(o.valor, 0)                                                          as salidas,
  sa.saldo + sum(coalesce(e.valor, 0) - coalesce(o.valor, 0)) over (order by s.semana) as saldo_final,
  sa.saldo + sum(coalesce(e.valor, 0) - coalesce(o.valor, 0)) over (order by s.semana) < b.caja_minima as bajo_minimo,
  sa.fecha                                                                      as saldo_tomado_el
from semanas s
cross join base b
cross join saldo sa
left join entradas e on e.semana = s.semana
left join salidas o  on o.semana = s.semana;

-- F2 y F5 · Rentabilidad real: contrato menos costo proyectado menos la
-- estructura asignada. Préstamos, socios y traslados no son costo.
create view public.v_rentabilidad_proyecto with (security_invoker = true) as
with costos as (
  select b.proyecto_id, sum(b.pagado) as pagado, sum(b.proyectado) as proyectado
  from public.v_balance_centro_costo b
  where not b.excluir_de_rentabilidad
  group by b.proyecto_id
),
ingresos as (
  select i.proyecto_id, sum(i.valor) as valor
  from public.ingreso i
  where i.proyecto_id is not null and i.anula_a is null
    and i.linea not in ('traslado_entre_cuentas','credito_bancario')
    and not exists (select 1 from public.ingreso x where x.anula_a = i.id)
  group by i.proyecto_id
),
estructura as (
  select d.proyecto_id, sum(d.valor) as valor
  from public.distribucion_estructura d group by d.proyecto_id
),
calculo as (
  select
    p.id as proyecto_id, p.codigo, p.nombre, p.unidad, p.tipo, p.estado, p.canal, p.valor_contrato,
    coalesce(i.valor, 0)                                  as ingresos,
    coalesce(c.pagado, 0)                                 as costo_pagado,
    coalesce(c.proyectado, 0)                             as costo_proyectado,
    coalesce(e.valor, 0)                                  as estructura_asignada,
    coalesce(nullif(p.valor_contrato, 0), nullif(i.valor, 0)) as base,
    case when p.tipo = 'obra' then pa.margen_meta_obra else pa.margen_meta_diseno end as meta
  from public.proyecto p
  cross join public.parametro pa
  left join costos c     on c.proyecto_id = p.id
  left join ingresos i   on i.proyecto_id = p.id
  left join estructura e on e.proyecto_id = p.id
  where p.tipo <> 'interno'
)
select
  k.proyecto_id, k.codigo, k.nombre, k.unidad, k.tipo, k.estado, k.canal, k.valor_contrato,
  k.ingresos, k.costo_pagado, k.costo_proyectado, k.estructura_asignada, k.meta,
  k.base - k.costo_proyectado                                               as margen_bruto,
  k.base - k.costo_proyectado - k.estructura_asignada                       as margen_neto,
  case when k.base > 0
       then round((k.base - k.costo_proyectado - k.estructura_asignada) / k.base * 100, 1) end as margen_neto_pct,
  case when k.base > 0
       then (k.base - k.costo_proyectado - k.estructura_asignada) / k.base < k.meta end       as bajo_meta,
  case
    when k.base is null then 'Sin contrato ni ingresos registrados: todavía no se puede medir'
    else 'De cada $100 del contrato quedan $'
         || round((k.base - k.costo_proyectado - k.estructura_asignada) / k.base * 100)
         || ' después de costos y estructura; la meta es $' || round(k.meta * 100)
  end                                                                       as lectura
from calculo k;

-- F1 · Partidas abiertas con dueño y antigüedad.
create view public.v_partidas_abiertas with (security_invoker = true) as
select
  pa.id,
  pa.cuenta_id,
  c.nombre                                                              as cuenta,
  pa.fecha,
  pa.valor,
  pa.descripcion,
  pa.responsable_id,
  r.nombre                                                              as responsable,
  private.hoy() - (pa.abierta_en at time zone 'America/Bogota')::date   as dias_abierta
from public.partida_abierta pa
join public.cuenta c  on c.id = pa.cuenta_id
join public.persona r on r.id = pa.responsable_id
where pa.resuelta_en is null;


-- ---------- Diseño ----------

-- D3 · Horas reales contra cotizadas, por fase.
create view public.v_fase_horas with (security_invoker = true) as
select
  f.id                                   as fase_id,
  f.proyecto_id,
  p.codigo                               as proyecto,
  f.fase,
  f.estado,
  f.horas_cotizadas,
  coalesce(d.horas, 0)                   as horas_reales,
  case when f.horas_cotizadas > 0
       then round(coalesce(d.horas, 0) / f.horas_cotizadas * 100, 1) end as pct_consumido,
  (f.horas_cotizadas > 0 and coalesce(d.horas, 0) > f.horas_cotizadas)     as sobre_dedicacion,
  case
    when f.horas_cotizadas = 0 then 'Esta fase no tiene horas cotizadas: no hay contra qué comparar'
    else 'Van ' || round(coalesce(d.horas, 0)) || ' de ' || round(f.horas_cotizadas) || ' horas cotizadas'
  end                                    as lectura
from public.proyecto_fase f
join public.proyecto p on p.id = f.proyecto_id
left join (
  select dd.fase_id, sum(dd.horas) as horas from public.dedicacion dd group by dd.fase_id
) d on d.fase_id = f.id;

-- D2 · Días hábiles sin registro de las dos últimas semanas. Cada quien ve
-- los suyos; dirección ve los de todo el equipo.
create view public.v_dedicacion_pendiente with (security_invoker = true) as
select
  p.id           as persona_id,
  p.nombre,
  g.dia::date    as fecha
from public.persona p
cross join lateral generate_series(
  greatest(private.hoy() - 14, (p.creado_en at time zone 'America/Bogota')::date),
  private.hoy() - 1, interval '1 day') g(dia)
where p.activo and p.es_interno and p.rol in ('director','arquitecto','practicante')
  and extract(isodow from g.dia) < 6
  and (p.id = private.persona_actual() or private.es_direccion() or auth.uid() is null)
  and not exists (select 1 from public.dedicacion d where d.persona_id = p.id and d.fecha = g.dia::date);

-- D4 · Capacidad del equipo en las próximas 13 semanas.
create view public.v_capacidad_13_semanas with (security_invoker = true) as
with equipo as (
  select coalesce(sum(p.horas_semana), 0) as horas_semana
  from public.persona p
  where p.activo and p.es_interno and p.rol in ('director','arquitecto','practicante')
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

-- D6 · Complementarios atrasados.
create view public.v_complementarios_atrasados with (security_invoker = true) as
select
  c.id,
  c.proyecto_id,
  p.codigo                                as proyecto,
  c.especialidad,
  pe.nombre                               as profesional,
  c.fecha_compromiso,
  private.hoy() - c.fecha_compromiso      as dias_atraso,
  c.estado
from public.complementario c
join public.proyecto p       on p.id = c.proyecto_id
left join public.persona pe  on pe.id = c.profesional_id
where c.fecha_compromiso < private.hoy()
  and c.estado in ('por_contratar','contratado','en_curso');



-- ---------- Trabajo del equipo ----------

-- O11 · Los pendientes de obra que siguen vivos, con quién responde, quién lo
-- hace y cuánto llevan esperando.
create view public.v_pendientes_obra with (security_invoker = true) as
select
  d.id,
  d.proyecto_id,
  p.codigo                                   as proyecto,
  d.titulo,
  d.ubicacion,
  d.tipo,
  d.prioridad,
  d.estado,
  r.nombre                                   as responsable,
  d.responsable_id,
  e.nombre                                   as ejecutor,
  d.fecha_compromiso,
  case when d.fecha_compromiso is not null and d.fecha_compromiso < private.hoy()
       then private.hoy() - d.fecha_compromiso end  as dias_atraso,
  b.titulo                                   as espera_a,
  d.movimiento_id is not null                as tiene_gasto,
  case
    when d.bloqueado_por is not null and b.estado not in ('cerrado','descartado')
      then 'Espera a que se cierre «' || b.titulo || '»'
    when d.fecha_compromiso is null
      then 'Sin fecha de entrega: nadie lo va a reclamar'
    when d.fecha_compromiso < private.hoy()
      then 'Lleva ' || (private.hoy() - d.fecha_compromiso)
           || case when private.hoy() - d.fecha_compromiso = 1 then ' día' else ' días' end
           || ' de atraso'
    when d.estado = 'por_verificar'
      then 'Hecho, falta que alguien lo verifique'
    else 'Al día, se entrega el ' || to_char(d.fecha_compromiso, 'DD/MM')
  end                                        as lectura
from public.pendiente_obra d
join public.proyecto p             on p.id = d.proyecto_id
join public.persona r              on r.id = d.responsable_id
left join public.persona e         on e.id = d.ejecutor_id
left join public.pendiente_obra b  on b.id = d.bloqueado_por
where d.estado not in ('cerrado','descartado');

-- D9 · Todo el trabajo abierto del equipo en una sola lista: las tareas de
-- diseño y los pendientes de obra, que en el Excel vivían revueltos. Esta es
-- la consulta del tablero.
create view public.v_trabajo_abierto with (security_invoker = true) as
select
  'diseno'::text                    as origen,
  t.id,
  t.proyecto_id,
  p.codigo                          as proyecto,
  t.titulo,
  t.asignada_a                      as persona_id,
  a.nombre                          as persona,
  t.estado::text                    as estado,
  t.fecha_compromiso,
  case when t.fecha_compromiso is not null and t.fecha_compromiso < private.hoy()
       then private.hoy() - t.fecha_compromiso end as dias_atraso,
  t.objetivo_id
from public.tarea_diseno t
join public.proyecto p   on p.id = t.proyecto_id
join public.persona a    on a.id = t.asignada_a
where t.estado <> 'terminada'
union all
select
  'obra'::text,
  d.id,
  d.proyecto_id,
  p.codigo,
  d.titulo,
  d.responsable_id,
  r.nombre,
  d.estado::text,
  d.fecha_compromiso,
  case when d.fecha_compromiso is not null and d.fecha_compromiso < private.hoy()
       then private.hoy() - d.fecha_compromiso end,
  d.objetivo_id
from public.pendiente_obra d
join public.proyecto p   on p.id = d.proyecto_id
join public.persona r    on r.id = d.responsable_id
where d.estado not in ('cerrado','descartado');

-- D8 · El avance del objetivo se cuenta, no se declara.
create view public.v_objetivos with (security_invoker = true) as
with trabajo as (
  select o.id as objetivo_id,
         count(*) filter (where w.id is not null)                       as total,
         count(*) filter (where w.id is not null and w.cerrado)         as hechas,
         count(*) filter (where w.id is not null and not w.cerrado
                            and w.fecha_compromiso < private.hoy())     as atrasadas
  from public.objetivo o
  left join (
    select t.objetivo_id, t.id, t.fecha_compromiso, t.estado = 'terminada' as cerrado
    from public.tarea_diseno t where t.objetivo_id is not null
    union all
    select d.objetivo_id, d.id, d.fecha_compromiso,
           d.estado in ('cerrado','descartado')
    from public.pendiente_obra d where d.objetivo_id is not null
  ) w on w.objetivo_id = o.id
  group by o.id
)
select
  o.id,
  o.ambito,
  o.proyecto_id,
  p.codigo                        as proyecto,
  o.persona_id,
  o.titulo,
  o.estado,
  o.fecha_limite,
  r.nombre                        as responsable,
  o.responsable_id,
  w.total,
  w.hechas,
  w.atrasadas,
  private.hoy() > o.fecha_limite  as pasado_de_fecha,
  case
    when w.total = 0
      then 'Sin tareas colgadas: por ahora es una intención, no un objetivo'
    when w.hechas = w.total
      then case when w.total = 1 then 'Listo: la única tarea está cerrada'
                else 'Listo: las ' || w.total || ' tareas están cerradas' end
    when w.atrasadas > 0
      then w.hechas || ' de ' || w.total
           || case when w.total = 1 then ' lista, y ' else ' listas, y ' end
           || case when w.atrasadas = 1 then 'una va tarde' else w.atrasadas || ' van tarde' end
    else w.hechas || ' de ' || w.total
         || case when w.total = 1 then ' lista, ' else ' listas, ' end
         || case when private.hoy() > o.fecha_limite
                 then 'y la fecha ya pasó'
                 else 'faltan ' || (o.fecha_limite - private.hoy())
                      || case when o.fecha_limite - private.hoy() = 1 then ' día' else ' días' end end
  end                             as lectura
from public.objetivo o
join trabajo w             on w.objetivo_id = o.id
join public.persona r      on r.id = o.responsable_id
left join public.proyecto p on p.id = o.proyecto_id;

-- ---------- Reclamaciones ----------

-- P3 y P4 · En qué eslabón está cada reclamación, cuánto lleva ahí y cuánto
-- falta para que venza la póliza.
create view public.v_reclamaciones with (security_invoker = true) as
select
  r.id,
  r.proyecto_id,
  p.codigo                                                        as proyecto,
  cl.nombre                                                       as empresa_asegurada,
  ase.nombre                                                      as aseguradora,
  abo.nombre                                                      as oficina_abogados,
  r.numero_poliza,
  r.estado,
  r.fecha_limite,
  r.fecha_limite - private.hoy()                                  as dias_para_vencer,
  private.hoy() - coalesce((ev.desde at time zone 'America/Bogota')::date,
                           (r.creada_en at time zone 'America/Bogota')::date) as dias_en_estado,
  coalesce(chk.obligatorios, 0)                                   as puntos_obligatorios,
  coalesce(chk.cumplidos, 0)                                      as puntos_cumplidos,
  coalesce(chk.obligatorios, 0) > 0 and chk.cumplidos = chk.obligatorios as checklist_completo,
  r.conciliada_en is not null                                     as conciliada_con_abogados,
  r.aval_estructural_en is not null                               as con_aval_estructural,
  r.valor_reclamado,
  r.valor_aprobado
from public.reclamacion r
join public.proyecto p        on p.id = r.proyecto_id
left join public.cliente cl   on cl.id = p.cliente_id
left join public.persona ase  on ase.id = r.aseguradora_id
left join public.persona abo  on abo.id = r.oficina_abogados_id
left join lateral (
  select max(e.ocurrio_en) as desde from public.reclamacion_evento e where e.reclamacion_id = r.id
) ev on true
left join lateral (
  select count(*) filter (where i.obligatorio) as obligatorios,
         count(*) filter (where i.obligatorio and rs.cumple) as cumplidos
  from public.chequeo c
  join public.lista_chequeo_item i on i.lista_id = c.lista_id
  left join public.chequeo_respuesta rs on rs.chequeo_id = c.id and rs.item_id = i.id
  where c.reclamacion_id = r.id
) chk on true;


-- ---------- Comercial ----------

-- El embudo de cada mes por canal, con la conclusión escrita.
create view public.v_embudo_mensual with (security_invoker = true) as
with leads as (
  select
    date_trunc('month', l.creado_en at time zone 'America/Bogota')::date as mes,
    l.canal,
    count(*)                                                    as leads,
    count(*) filter (where l.primer_contacto_en is not null)    as contactados,
    percentile_cont(0.5) within group (
      order by extract(epoch from (l.primer_contacto_en - l.creado_en)) / 60) as minutos_mediana,
    count(*) filter (where l.estado = 'nutricion')              as en_nutricion,
    count(*) filter (where l.estado = 'descartado')             as descartados
  from public.lead l
  group by 1, 2
),
ops as (
  select
    date_trunc('month', l.creado_en at time zone 'America/Bogota')::date as mes,
    l.canal,
    count(distinct o.id)                                        as oportunidades,
    count(distinct ci.id) filter (where ci.estado = 'realizada') as citas_realizadas,
    count(distinct ci.id) filter (where ci.estado = 'no_show')  as no_shows,
    count(distinct o.id) filter (where o.etapa = 'ganada')      as ganadas,
    count(distinct o.id) filter (where o.etapa = 'perdida')     as perdidas
  from public.lead l
  join public.oportunidad o on o.lead_id = l.id
  left join public.cita ci  on ci.oportunidad_id = o.id
  group by 1, 2
)
select
  le.mes,
  le.canal,
  le.leads,
  le.contactados,
  round(le.minutos_mediana::numeric, 0)          as minutos_primera_respuesta,
  coalesce(op.oportunidades, 0)                  as oportunidades,
  coalesce(op.citas_realizadas, 0)               as citas_realizadas,
  coalesce(op.no_shows, 0)                       as no_shows,
  coalesce(op.ganadas, 0)                        as ganadas,
  coalesce(op.perdidas, 0)                       as perdidas,
  le.en_nutricion,
  le.descartados,
  'De ' || le.leads || case when le.leads = 1 then ' lead, ' else ' leads, ' end
    || coalesce(op.citas_realizadas, 0)
    || case when coalesce(op.citas_realizadas, 0) = 1 then ' llegó a cita' else ' llegaron a cita' end
    || case when coalesce(op.no_shows, 0) = 1 then ', 1 no llegó'
            when coalesce(op.no_shows, 0) > 1 then ', ' || op.no_shows || ' no llegaron'
            else '' end
    || ' y ' || coalesce(op.ganadas, 0)
    || case when coalesce(op.ganadas, 0) = 1 then ' se cerró' else ' se cerraron' end  as lectura
from leads le
left join ops op on op.mes = le.mes and op.canal = le.canal;

-- M3 · Retorno de la pauta por campaña y mes, dicho en pesos.
-- Simplificación: la venta cuenta en el mes en que se cerró.
create view public.v_retorno_pauta with (security_invoker = true) as
with inversion as (
  select ip.campana_id, date_trunc('month', ip.fecha)::date as mes, sum(ip.valor) as inversion
  from public.inversion_pauta ip
  group by 1, 2
),
ventas as (
  select
    l.campana_id,
    date_trunc('month', o.desenlace_en at time zone 'America/Bogota')::date as mes,
    count(*)                                        as ganadas,
    sum(coalesce(cz.valor, o.valor_estimado, 0))    as venta
  from public.oportunidad o
  join public.lead l on l.id = o.lead_id
  left join lateral (
    select sum(z.valor) as valor from public.cotizacion z
    where z.oportunidad_id = o.id and z.estado = 'aceptada'
  ) cz on true
  where o.etapa = 'ganada' and l.campana_id is not null
  group by 1, 2
),
llaves as (
  select campana_id, mes from inversion
  union
  select campana_id, mes from ventas
)
select
  c.id                                         as campana_id,
  c.nombre                                     as campana,
  c.canal,
  k.mes,
  coalesce(i.inversion, 0)                     as inversion,
  coalesce(v.ganadas, 0)                       as ventas_cerradas,
  coalesce(v.venta, 0)                         as venta,
  case when coalesce(i.inversion, 0) > 0
       then round(coalesce(v.venta, 0) / i.inversion, 2) end          as venta_por_peso,
  case when coalesce(v.venta, 0) > 0
       then round(coalesce(i.inversion, 0) / v.venta * 100, 1) end    as costo_adquisicion_pct,
  case
    when coalesce(i.inversion, 0) = 0 then
      'Trajo ' || private.pesos(v.venta) || ' en ventas sin inversión registrada este mes'
    when coalesce(v.venta, 0) = 0 then
      'Se invirtieron ' || private.pesos(i.inversion) || ' y todavía no hay ventas cerradas de esta campaña'
    else
      'Cada peso invertido trajo $' || replace(round(v.venta / i.inversion, 2)::text, '.', ',') || ' en ventas'
  end                                          as lectura
from llaves k
join public.campana c    on c.id = k.campana_id
left join inversion i    on i.campana_id = k.campana_id and i.mes = k.mes
left join ventas v       on v.campana_id = k.campana_id and v.mes = k.mes;


-- ---------- Presupuestos ----------

-- O7 · El bucle de calibración: cuánto se ejecuta de verdad frente a lo que
-- se presupuesta, por capítulo y a precio de contrato (mide cantidad, no precio).
-- No cuenta los ítems en cero: casi siempre son obra reemplazada por un adicional.
create view public.v_calibracion_capitulo with (security_invoker = true) as
select
  upper(c.nombre)                                                   as capitulo,
  count(distinct pr.proyecto_id)                                    as proyectos,
  count(*)                                                          as items_medidos,
  sum(i.valor_parcial)                                              as presupuestado,
  sum(round(e.cantidad_proyectada * i.valor_unitario, 2))           as a_precio_de_contrato,
  round(sum(e.cantidad_proyectada * i.valor_unitario) / nullif(sum(i.valor_parcial), 0), 2) as factor_cantidad,
  case
    when sum(e.cantidad_proyectada * i.valor_unitario) >= 1.05 * sum(i.valor_parcial) then
      'Se termina ejecutando ' || replace(round(sum(e.cantidad_proyectada * i.valor_unitario) / sum(i.valor_parcial), 1)::text, '.', ',')
      || ' veces lo presupuestado'
    when sum(e.cantidad_proyectada * i.valor_unitario) <= 0.95 * sum(i.valor_parcial) then
      'Se presupuesta de más: se ejecuta el '
      || round(sum(e.cantidad_proyectada * i.valor_unitario) / sum(i.valor_parcial) * 100) || '%'
    else 'Lo presupuestado coincide con lo ejecutado'
  end                                                               as lectura
from public.item_presupuesto i
join public.capitulo c       on c.id = i.capitulo_id
join public.presupuesto pr   on pr.id = c.presupuesto_id
join public.ejecucion_item e on e.item_id = i.id
where i.cantidad > 0 and i.valor_parcial > 0 and e.cantidad_proyectada > 0
group by upper(c.nombre);

-- Costo unitario vigente de cada APU con los precios actuales de los insumos.
create view public.v_apu_costo with (security_invoker = true) as
select
  a.id                                                                    as apu_id,
  a.codigo,
  a.descripcion,
  a.unidad,
  coalesce(sum(round(ac.cantidad * (1 + ac.desperdicio) * i.precio, 2)), 0) as costo_unitario,
  count(ac.id)                                                            as componentes,
  max(i.actualizado_en)                                                   as precio_mas_reciente
from public.apu a
left join public.apu_componente ac on ac.apu_id = a.id
left join public.insumo i          on i.id = ac.insumo_id
group by a.id, a.codigo, a.descripcion, a.unidad;


-- =============================================================================
-- 14. Alertas
-- F7 y F8 · Cada tipo de alerta con su dueño y sus canales. El generador corre
-- como tarea programada (pg_cron o una función de Supabase) y es el único que
-- crea alertas: nadie las escribe a mano.
-- =============================================================================

insert into public.regla_alerta
  (tipo, descripcion, severidad, roles, incluir_residente, incluir_responsable, canales)
values
  ('aprobacion_pendiente',     'T4 · Un gasto sobre el umbral espera aprobación',             'critico',     '{socio}',            false, false, '{plataforma,correo,sms}'),
  ('desviacion_capitulo',      'O3 · Un capítulo ya supera lo presupuestado',                 'alerta',      '{socio}',            true,  false, '{plataforma,correo}'),
  ('bitacora_faltante',        'O4 · Días de obra sin bitácora',                              'alerta',      '{}',                 true,  false, '{plataforma,sms}'),
  ('cambio_sin_reflejar',      'Un cambio decidido en obra no ha llegado a diseño',           'alerta',      '{director}',         false, true,  '{plataforma,correo}'),
  ('caja_menor_sin_legalizar', 'Caja menor abierta más días de lo permitido',                 'alerta',      '{director}',         false, false, '{plataforma,correo}'),
  ('cartera',                  'F3 · Acta de cobro vencida o a punto de vencer',              'alerta',      '{socio,financiero}', false, true,  '{plataforma,correo}'),
  ('caja_bajo_minimo',         'F7 · La caja proyectada baja del mínimo',                     'critico',     '{socio}',            false, false, '{plataforma,correo,sms}'),
  ('poliza_por_vencer',        'P4 · El plazo de la póliza está por vencer',                  'critico',     '{socio}',            false, true,  '{plataforma,correo,sms}'),
  ('cotizacion_vencida',       'M6 · Cotización vencida sin respuesta',                       'informativo', '{mercadeo}',         false, false, '{plataforma}'),
  ('lead_sin_respuesta',       'Lead sin primer contacto',                                    'alerta',      '{mercadeo}',         false, false, '{plataforma,sms}'),
  ('cita_sin_desenlace',       'M8 · Cita realizada sin desenlace',                           'alerta',      '{mercadeo,socio}',   false, false, '{plataforma,correo}'),
  ('sobre_dedicacion',         'D3 · Las horas reales superan las cotizadas',                 'alerta',      '{director}',         false, false, '{plataforma,correo}'),
  ('complementario_atrasado',  'D6 · Un complementario está atrasado',                        'alerta',      '{director}',         false, true,  '{plataforma,correo}'),
  ('margen_bajo_meta',         'O10 · Un proyecto activo proyecta margen bajo la meta',       'critico',     '{socio}',            false, false, '{plataforma,correo}'),
  ('tarea_vencida',            'D9 · Tarea de diseño que pasó su fecha de entrega',           'alerta',      '{director}',         false, false, '{plataforma,correo}'),
  ('pendiente_vencido',        'O11 · Pendiente de obra que pasó su fecha',                   'alerta',      '{}',                 true,  false, '{plataforma,sms}'),
  ('trabajo_sin_fecha',        'Trabajo abierto sin fecha de entrega: fuera del radar',       'informativo', '{director}',         false, true,  '{plataforma}'),
  ('objetivo_en_riesgo',       'D8 · Objetivo con la fecha encima y trabajo sin cerrar',      'alerta',      '{socio,director}',   false, false, '{plataforma,correo}')
on conflict (tipo) do nothing;

-- F8 · A quién le llega cada tipo de alerta. Solo personas activas con usuario.
create or replace function private.destinatarios(p_tipo text, p_proyecto uuid) returns uuid[]
language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(distinct x.id), '{}'::uuid[])
  from (
    select p.id
    from public.regla_alerta r
    join public.persona p on p.rol = any (r.roles)
    where r.tipo = p_tipo and r.activa and p.es_interno
    union
    select pr.residente_id
    from public.regla_alerta r join public.proyecto pr on pr.id = p_proyecto
    where r.tipo = p_tipo and r.activa and r.incluir_residente
    union
    select pr.responsable_id
    from public.regla_alerta r join public.proyecto pr on pr.id = p_proyecto
    where r.tipo = p_tipo and r.activa and r.incluir_responsable
  ) x
  join public.persona pe on pe.id = x.id and pe.activo and pe.auth_user_id is not null
$$;

-- Cada alerta con correo o mensaje de texto deja su envío en la bandeja.
create or replace function private.expandir_avisos() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.aviso (alerta_id, persona_id, canal)
  select new.id, d.persona_id, c.canal
  from unnest(new.destinatarios) as d(persona_id)
  cross join unnest(new.canales) as c(canal)
  where c.canal <> 'plataforma'
    and exists (select 1 from public.persona p where p.id = d.persona_id)
  on conflict do nothing;
  return null;
end $$;

drop trigger if exists tr_alerta_avisos on public.alerta;
create trigger tr_alerta_avisos
  after insert on public.alerta
  for each row execute function private.expandir_avisos();

-- El generador. Arma la lista de condiciones que hoy se cumplen, crea las
-- alertas nuevas, actualiza el texto de las abiertas y marca como resueltas
-- las que dejaron de cumplirse (resuelta_por queda vacío: se resolvió sola).
-- Devuelve cuántas alertas nuevas creó.
create or replace function private.generar_alertas() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_par    public.parametro%rowtype;
  v_hoy    date := private.hoy();
  v_antes  bigint;
  v_despues bigint;
begin
  select * into v_par from public.parametro p where p.id;

  -- M6 · Las cotizaciones emitidas y vencidas cambian de estado solas.
  update public.cotizacion set estado = 'vencida'
   where estado = 'emitida' and vence_en < v_hoy;

  create temporary table if not exists _alerta_candidata (
    tipo text, clave text, proyecto_id uuid, titulo text, detalle text, extra uuid[]
  ) on commit drop;
  truncate pg_temp._alerta_candidata;

  -- T4
  insert into pg_temp._alerta_candidata
  select 'aprobacion_pendiente', 'aprobacion_pendiente:' || m.id, m.proyecto_id,
         'Un gasto de ' || private.pesos(m.valor) || ' espera tu aprobación',
         p.codigo || ' · ' || m.concepto || ' · ' || coalesce(t.nombre, m.tercero_nombre), null
  from public.movimiento m
  join public.proyecto p     on p.id = m.proyecto_id
  left join public.persona t on t.id = m.tercero_id
  where m.aprobacion = 'pendiente'
    and not exists (select 1 from public.movimiento x where x.anula_a = m.id);

  -- O3
  insert into pg_temp._alerta_candidata
  select 'desviacion_capitulo', 'desviacion_capitulo:' || d.capitulo_id, d.proyecto_id,
         d.proyecto || ' · ' || d.capitulo || ' va ' || replace(d.desviacion_pct::text, '.', ',')
           || '% sobre lo presupuestado',
         'Presupuestado ' || private.pesos(d.presupuestado) || ' · total a ejecutar ' || private.pesos(d.proyectado),
         null
  from public.v_desviacion_capitulo d
  join public.proyecto p on p.id = d.proyecto_id
  where p.estado = 'activo' and d.desviacion_pct > 0;

  -- O4
  insert into pg_temp._alerta_candidata
  select 'bitacora_faltante', 'bitacora_faltante:' || b.proyecto_id, b.proyecto_id,
         b.proyecto || ' tiene ' || count(*) || ' día(s) sin bitácora en el último mes',
         'El más reciente sin registro: ' || to_char(max(b.fecha), 'DD/MM/YYYY'), null
  from public.v_bitacora_faltante b
  group by b.proyecto_id, b.proyecto;

  -- Cambios en obra que no llegan a diseño
  insert into pg_temp._alerta_candidata
  select 'cambio_sin_reflejar', 'cambio_sin_reflejar:' || c.id, c.proyecto_id,
         c.proyecto || ' · un cambio decidido en obra lleva ' || c.dias_abierto || ' días sin llegar a diseño',
         c.descripcion, null
  from public.v_cambios_sin_reflejar c
  where c.dias_abierto >= 3;

  -- Caja menor
  insert into pg_temp._alerta_candidata
  select 'caja_menor_sin_legalizar', 'caja_menor_sin_legalizar:' || f.id, null,
         'La caja menor de ' || r.nombre || ' lleva ' || (v_hoy - f.fecha_entrega) || ' días sin legalizar',
         'Entregada por ' || e.nombre || ' el ' || to_char(f.fecha_entrega, 'DD/MM/YYYY') || ' · ' || private.pesos(f.valor),
         array[f.responsable_id, f.entregado_por]
  from public.fondo_caja f
  join public.persona r on r.id = f.responsable_id
  join public.persona e on e.id = f.entregado_por
  where f.legalizado_en is null and v_hoy - f.fecha_entrega > v_par.dias_legalizar_caja;

  -- F3
  insert into pg_temp._alerta_candidata
  select 'cartera', 'cartera:' || c.acta_id, c.proyecto_id,
         case when c.vence_en < v_hoy
              then c.proyecto || ' · el acta ' || c.numero || ' lleva ' || (v_hoy - c.vence_en) || ' días vencida'
              else c.proyecto || ' · el acta ' || c.numero || ' vence el ' || to_char(c.vence_en, 'DD/MM') end,
         'Saldo por cobrar ' || private.pesos(c.saldo), null
  from public.v_cartera c
  where c.saldo > 0 and c.vence_en is not null and c.vence_en <= v_hoy + 5;

  -- F7
  insert into pg_temp._alerta_candidata
  select 'caja_bajo_minimo', 'caja_bajo_minimo', null,
         'La caja proyectada baja de ' || private.pesos(v_par.caja_minima) || ' la semana del ' || to_char(f.desde, 'DD/MM'),
         'Saldo proyectado ' || private.pesos(f.saldo_final) || ' · saldo de bancos tomado el '
           || to_char(f.saldo_tomado_el, 'DD/MM/YYYY'),
         null
  from public.v_flujo_13_semanas f
  where f.bajo_minimo and f.saldo_tomado_el is not null
  order by f.semana
  limit 1;

  -- P4
  insert into pg_temp._alerta_candidata
  select 'poliza_por_vencer', 'poliza_por_vencer:' || r.id, r.proyecto_id,
         p.codigo || ' · el plazo de la póliza vence en ' || (r.fecha_limite - v_hoy) || ' días',
         'La reclamación está en: ' || replace(r.estado::text, '_', ' '), null
  from public.reclamacion r
  join public.proyecto p on p.id = r.proyecto_id
  where r.fecha_limite is not null and r.estado in ('en_expediente','conciliada','objetada')
    and r.fecha_limite - v_hoy <= v_par.dias_aviso_poliza;

  -- M6
  insert into pg_temp._alerta_candidata
  select 'cotizacion_vencida', 'cotizacion_vencida:' || z.id, z.proyecto_id,
         'La cotización ' || z.numero || ' venció el ' || to_char(z.vence_en, 'DD/MM') || ' sin respuesta',
         coalesce(o.nombre, ''), null
  from public.cotizacion z
  left join public.oportunidad o on o.id = z.oportunidad_id
  where z.estado = 'vencida' and coalesce(o.etapa::text, '') not in ('ganada','perdida');

  -- Tiempo de primera respuesta
  insert into pg_temp._alerta_candidata
  select 'lead_sin_respuesta', 'lead_sin_respuesta:' || l.id, null,
         coalesce(l.nombre, l.telefono, l.correo) || ' escribió hace '
           || round(extract(epoch from now() - l.creado_en) / 60) || ' minutos y nadie le ha respondido',
         'Canal: ' || replace(l.canal::text, '_', ' '), array[l.asignado_a]
  from public.lead l
  where l.estado = 'nuevo' and l.primer_contacto_en is null
    and l.creado_en < now() - make_interval(mins => v_par.minutos_primera_respuesta);

  -- M8
  insert into pg_temp._alerta_candidata
  select 'cita_sin_desenlace', 'cita_sin_desenlace:' || o.id, null,
         o.nombre || ' tuvo cita hace '
           || (v_hoy - max((c.realizada_en at time zone 'America/Bogota')::date)) || ' días y no tiene desenlace',
         'Registre si cerró, se perdió o sigue viva: sin eso el embudo no aprende', array[o.responsable_id]
  from public.oportunidad o
  join public.cita c on c.oportunidad_id = o.id and c.estado = 'realizada'
  where o.etapa not in ('ganada','perdida')
  group by o.id, o.nombre, o.responsable_id
  having max(c.realizada_en) < now() - make_interval(days => v_par.dias_sin_desenlace);

  -- D3
  insert into pg_temp._alerta_candidata
  select 'sobre_dedicacion', 'sobre_dedicacion:' || h.fase_id, h.proyecto_id,
         h.proyecto || ' · ' || replace(h.fase::text, '_', ' ') || ' ya consumió el '
           || round(h.pct_consumido) || '% de las horas cotizadas',
         h.lectura, null
  from public.v_fase_horas h
  where h.sobre_dedicacion and h.estado <> 'cerrada';

  -- D6
  insert into pg_temp._alerta_candidata
  select 'complementario_atrasado', 'complementario_atrasado:' || c.id, c.proyecto_id,
         c.proyecto || ' · el ' || c.especialidad || ' lleva ' || c.dias_atraso || ' días de atraso',
         coalesce('Responsable: ' || c.profesional, 'Sin profesional asignado'), null
  from public.v_complementarios_atrasados c;

  -- O10
  insert into pg_temp._alerta_candidata
  select 'margen_bajo_meta', 'margen_bajo_meta:' || r.proyecto_id, r.proyecto_id,
         r.codigo || ' proyecta ' || replace(r.margen_neto_pct::text, '.', ',')
           || '% de margen; la meta es ' || round(r.meta * 100) || '%',
         r.lectura, null
  from public.v_rentabilidad_proyecto r
  where r.estado = 'activo' and r.bajo_meta and coalesce(r.valor_contrato, 0) > 0;

  -- D9 · Tarea de diseño que pasó su fecha y sigue abierta. Le llega a quien la
  -- tiene y a quien la asignó: en el Excel nadie veía las que iban tarde.
  insert into pg_temp._alerta_candidata
  select 'tarea_vencida', 'tarea_vencida:' || t.id, t.proyecto_id,
         p.codigo || ' · «' || t.titulo || '» se entregaba el '
           || to_char(t.fecha_compromiso, 'DD/MM') || ' y lleva '
           || (v_hoy - t.fecha_compromiso)
           || case when v_hoy - t.fecha_compromiso = 1 then ' día' else ' días' end,
         'La tiene ' || a.nombre || ' · ' || replace(t.estado::text, '_', ' '),
         array[t.asignada_a, t.asignada_por]
  from public.tarea_diseno t
  join public.proyecto p on p.id = t.proyecto_id
  join public.persona a  on a.id = t.asignada_a
  where t.estado <> 'terminada'
    and t.fecha_compromiso is not null and t.fecha_compromiso < v_hoy
    and p.estado = 'activo';

  -- O11 · Pendiente de obra vencido.
  insert into pg_temp._alerta_candidata
  select 'pendiente_vencido', 'pendiente_vencido:' || d.id, d.proyecto_id,
         d.proyecto || ' · ' || d.titulo
           || coalesce(' (' || d.ubicacion || ')', '') || ': ' || d.lectura,
         'Responde ' || d.responsable || coalesce(' · lo hace ' || d.ejecutor, ''),
         array[d.responsable_id]
  from public.v_pendientes_obra d
  join public.proyecto p on p.id = d.proyecto_id
  where d.dias_atraso is not null and p.estado = 'activo';

  -- Trabajo abierto sin fecha de entrega: no está al día ni vencido, está
  -- fuera del radar. Era el caso de Cabrera entero en la hoja de seguimiento.
  insert into pg_temp._alerta_candidata
  select 'trabajo_sin_fecha', 'trabajo_sin_fecha:' || w.proyecto_id, w.proyecto_id,
         w.proyecto || ' tiene ' || count(*)
           || case when count(*) = 1 then ' tarea abierta sin fecha de entrega'
                   else ' tareas abiertas sin fecha de entrega' end,
         'Sin fecha nadie las reclama. Las tienen: ' || string_agg(distinct w.persona, ', '),
         null
  from public.v_trabajo_abierto w
  join public.proyecto p on p.id = w.proyecto_id
  where w.fecha_compromiso is null and p.estado = 'activo'
  group by w.proyecto_id, w.proyecto;

  -- D8 · Objetivo con la fecha encima y trabajo sin cerrar.
  insert into pg_temp._alerta_candidata
  select 'objetivo_en_riesgo', 'objetivo_en_riesgo:' || o.id, o.proyecto_id,
         '«' || o.titulo || '» ' || case when o.pasado_de_fecha then 'ya pasó de fecha' else 'vence el '
           || to_char(o.fecha_limite, 'DD/MM') end,
         o.lectura, array[o.responsable_id]
  from public.v_objetivos o
  where o.estado = 'en_curso'
    and o.hechas < o.total
    and o.fecha_limite - v_hoy <= 7;

  select count(*) into v_antes from public.alerta;

  insert into public.alerta (tipo, clave, severidad, proyecto_id, titulo, detalle, destinatarios, canales)
  select c.tipo, c.clave, r.severidad, c.proyecto_id, c.titulo, c.detalle, d.lista, r.canales
  from pg_temp._alerta_candidata c
  join public.regla_alerta r on r.tipo = c.tipo and r.activa
  cross join lateral (
    select array(
      select distinct x
      from unnest(private.destinatarios(c.tipo, c.proyecto_id) || coalesce(c.extra, '{}'::uuid[])) as x
      where x is not null
        and exists (select 1 from public.persona pe where pe.id = x and pe.activo and pe.auth_user_id is not null)
    ) as lista
  ) d
  where cardinality(d.lista) > 0
  on conflict (clave) where not resuelta do update
    set titulo = excluded.titulo, detalle = excluded.detalle
    where public.alerta.titulo is distinct from excluded.titulo
       or public.alerta.detalle is distinct from excluded.detalle;

  select count(*) into v_despues from public.alerta;

  -- Lo que ya no se cumple se resuelve solo.
  update public.alerta a
     set resuelta = true, resuelta_en = now()
   where not a.resuelta and a.clave is not null
     and exists (select 1 from public.regla_alerta r where r.tipo = a.tipo)
     and not exists (select 1 from pg_temp._alerta_candidata c where c.clave = a.clave);

  return (v_despues - v_antes)::integer;
end $$;

comment on function private.generar_alertas() is
  'Programar en Supabase con pg_cron, por ejemplo cada hora: select cron.schedule(''sici-alertas'', ''0 * * * *'', ''select private.generar_alertas()'');';


-- =============================================================================
-- 15. Cerrado por defecto
-- Toda tabla del esquema público nace con permisos por fila activos y sin
-- políticas: nadie ve nada hasta que las migraciones rls_* lo abren.
-- =============================================================================

do $$
declare t record;
begin
  for t in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
  loop
    execute format('alter table public.%I enable row level security', t.relname);
  end loop;
end $$;
