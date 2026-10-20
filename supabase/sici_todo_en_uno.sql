-- =============================================================================
-- SICI · PAQUETE TODO-EN-UNO · generado por pruebas/probar_contra_postgres.py
-- 2026-10-19 15:16 · No editar: se regenera desde supabase/migrations/.
-- Para pegar de una sola vez en el editor SQL de Supabase. Contiene, en orden:
--   20260914120000_esquema_inicial.sql
--   20260914120100_rls_nucleo.sql
--   20260914120200_rls_comercial.sql
--   20260914120300_rls_diseno.sql
--   20260914120400_rls_presupuestos.sql
--   20260914120500_rls_obra.sql
--   20260914120600_rls_reclamaciones.sql
--   20260914120700_rls_finanzas.sql
--   20260914120800_permisos_api.sql
--   20260914120900_almacenamiento.sql
--   20260914121000_vinculo_usuarios.sql
--   20261012120000_fases_por_tipo.sql
--   20261012120100_modulo_diseno.sql
--   20261012120200_indicadores.sql
--   20261012120300_mensajes.sql
--   20261013120000_aplicacion.sql
--   20261014120000_carga_semanal.sql
--   20261015120000_flujo_por_fase.sql
--   20261016120000_tareas_tipicas.sql
--   20261017120000_cierre_de_fase.sql
--   20261018120000_embudo_de_ventas.sql
--   20261019120000_modulo_obra.sql
--   20261020120000_prestamos_y_socios.sql
--   20261021120000_adicional_retirado.sql
--   20261022120000_revision_y_papeles.sql
-- =============================================================================



-- >>>>>>>>>>>>>>>>>>>> 20260914120000_esquema_inicial.sql >>>>>>>>>>>>>>>>>>>>

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


-- >>>>>>>>>>>>>>>>>>>> 20260914120100_rls_nucleo.sql >>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- SICI · Políticas de acceso por fila · M-00 Núcleo y alertas
--
-- Cómo leer estas políticas:
--   · Una política por tabla y por operación (lectura, alta, edición, retiro).
--     Así lo pide el asesor de Supabase y así se entiende quién hace qué.
--   · Todas aplican solo a "authenticated": sin sesión no se ve nada.
--   · Las funciones de identidad van entre paréntesis con select: Postgres
--     las calcula una vez por consulta y no una vez por fila.
--   · Nadie borra: salvo retirar un acceso, no existe política de retiro.
--
-- Idempotente: cada política se borra antes de crearse.
-- =============================================================================

-- ---------- parametro · el umbral y los márgenes solo los cambia un socio ----------
drop policy if exists parametro_lectura on public.parametro;
create policy parametro_lectura on public.parametro for select to authenticated
  using ((select private.es_interno()));

drop policy if exists parametro_edicion on public.parametro;
create policy parametro_edicion on public.parametro for update to authenticated
  using ((select private.tiene_rol('{socio}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio}'::public.rol_persona[])));

-- ---------- persona · el equipo ve el directorio; un externo, solo su ficha ----------
drop policy if exists persona_lectura on public.persona;
create policy persona_lectura on public.persona for select to authenticated
  using ((select private.es_interno()) or id = (select private.persona_actual()));

drop policy if exists persona_alta on public.persona;
create policy persona_alta on public.persona for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists persona_edicion on public.persona;
create policy persona_edicion on public.persona for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- cliente ----------
drop policy if exists cliente_lectura on public.cliente;
create policy cliente_lectura on public.cliente for select to authenticated
  using ((select private.es_interno()));

drop policy if exists cliente_alta on public.cliente;
create policy cliente_alta on public.cliente for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists cliente_edicion on public.cliente;
create policy cliente_edicion on public.cliente for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

-- ---------- categoria_costo ----------
drop policy if exists categoria_costo_lectura on public.categoria_costo;
create policy categoria_costo_lectura on public.categoria_costo for select to authenticated
  using ((select private.es_interno()));

drop policy if exists categoria_costo_alta on public.categoria_costo;
create policy categoria_costo_alta on public.categoria_costo for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists categoria_costo_edicion on public.categoria_costo;
create policy categoria_costo_edicion on public.categoria_costo for update to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

-- ---------- cuenta · bancos y cajas: dirección y finanzas ----------
drop policy if exists cuenta_lectura on public.cuenta;
create policy cuenta_lectura on public.cuenta for select to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists cuenta_alta on public.cuenta;
create policy cuenta_alta on public.cuenta for insert to authenticated
  with check ((select private.tiene_rol('{socio,financiero}'::public.rol_persona[])));

drop policy if exists cuenta_edicion on public.cuenta;
create policy cuenta_edicion on public.cuenta for update to authenticated
  using ((select private.tiene_rol('{socio,financiero}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,financiero}'::public.rol_persona[])));

-- ---------- proyecto · lo asignado, o el portal del cliente ----------
drop policy if exists proyecto_lectura on public.proyecto;
create policy proyecto_lectura on public.proyecto for select to authenticated
  using (id in (select private.proyectos_visibles()) or id in (select private.proyectos_portal()));

drop policy if exists proyecto_alta on public.proyecto;
create policy proyecto_alta on public.proyecto for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists proyecto_edicion on public.proyecto;
create policy proyecto_edicion on public.proyecto for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- centro_costo ----------
drop policy if exists centro_costo_lectura on public.centro_costo;
create policy centro_costo_lectura on public.centro_costo for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));

drop policy if exists centro_costo_alta on public.centro_costo;
create policy centro_costo_alta on public.centro_costo for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists centro_costo_edicion on public.centro_costo;
create policy centro_costo_edicion on public.centro_costo for update to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

-- ---------- acceso_proyecto · el único retiro permitido: quitar un acceso ----------
drop policy if exists acceso_proyecto_lectura on public.acceso_proyecto;
create policy acceso_proyecto_lectura on public.acceso_proyecto for select to authenticated
  using ((select private.es_direccion()) or persona_id = (select private.persona_actual()));

drop policy if exists acceso_proyecto_alta on public.acceso_proyecto;
create policy acceso_proyecto_alta on public.acceso_proyecto for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists acceso_proyecto_edicion on public.acceso_proyecto;
create policy acceso_proyecto_edicion on public.acceso_proyecto for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

drop policy if exists acceso_proyecto_retiro on public.acceso_proyecto;
create policy acceso_proyecto_retiro on public.acceso_proyecto for delete to authenticated
  using ((select private.es_direccion()));

-- ---------- evento_auditoria · solo se lee; la escribe el sistema ----------
drop policy if exists evento_auditoria_lectura on public.evento_auditoria;
create policy evento_auditoria_lectura on public.evento_auditoria for select to authenticated
  using ((select private.es_direccion()));

-- ---------- regla_alerta ----------
drop policy if exists regla_alerta_lectura on public.regla_alerta;
create policy regla_alerta_lectura on public.regla_alerta for select to authenticated
  using ((select private.es_interno()));

drop policy if exists regla_alerta_alta on public.regla_alerta;
create policy regla_alerta_alta on public.regla_alerta for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists regla_alerta_edicion on public.regla_alerta;
create policy regla_alerta_edicion on public.regla_alerta for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- alerta · la ve y la resuelve a quien le llegó ----------
drop policy if exists alerta_lectura on public.alerta;
create policy alerta_lectura on public.alerta for select to authenticated
  using ((select private.es_direccion()) or (select private.persona_actual()) = any (destinatarios));

drop policy if exists alerta_edicion on public.alerta;
create policy alerta_edicion on public.alerta for update to authenticated
  using ((select private.es_direccion()) or (select private.persona_actual()) = any (destinatarios))
  with check ((select private.es_direccion()) or (select private.persona_actual()) = any (destinatarios));

-- ---------- aviso · bandeja de salida; la escribe el sistema ----------
drop policy if exists aviso_lectura on public.aviso;
create policy aviso_lectura on public.aviso for select to authenticated
  using ((select private.es_direccion()) or persona_id = (select private.persona_actual()));

-- ---------- objetivo · los abre dirección; los ve el equipo ----------
-- Un objetivo de la empresa lo ve todo el mundo adentro. Uno de proyecto, quien
-- tiene acceso a ese proyecto. Uno de persona, esa persona y dirección.
drop policy if exists objetivo_lectura on public.objetivo;
create policy objetivo_lectura on public.objetivo for select to authenticated
  using ((select private.es_interno())
         and (ambito = 'empresa'
              or proyecto_id in (select private.proyectos_visibles())
              or persona_id = (select private.persona_actual())
              or responsable_id = (select private.persona_actual())));

drop policy if exists objetivo_alta on public.objetivo;
create policy objetivo_alta on public.objetivo for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists objetivo_edicion on public.objetivo;
create policy objetivo_edicion on public.objetivo for update to authenticated
  using ((select private.es_direccion()) or responsable_id = (select private.persona_actual()))
  with check ((select private.es_direccion()) or responsable_id = (select private.persona_actual()));


-- >>>>>>>>>>>>>>>>>>>> 20260914120200_rls_comercial.sql >>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- SICI · Políticas de acceso por fila · M-05 Comercial: mercadeo, ventas y CRM
--
-- El embudo lo trabajan mercadeo (Alison) y dirección (Felipe cierra ventas).
-- Finanzas lee la inversión en pauta y las cotizaciones para el flujo de caja.
-- Ni obra ni diseño ven los datos personales de los prospectos.
-- =============================================================================

-- ---------- experimento ----------
drop policy if exists experimento_lectura on public.experimento;
create policy experimento_lectura on public.experimento for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists experimento_alta on public.experimento;
create policy experimento_alta on public.experimento for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists experimento_edicion on public.experimento;
create policy experimento_edicion on public.experimento for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

-- ---------- campana ----------
drop policy if exists campana_lectura on public.campana;
create policy campana_lectura on public.campana for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo,financiero}'::public.rol_persona[])));

drop policy if exists campana_alta on public.campana;
create policy campana_alta on public.campana for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists campana_edicion on public.campana;
create policy campana_edicion on public.campana for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

-- ---------- inversion_pauta ----------
drop policy if exists inversion_pauta_lectura on public.inversion_pauta;
create policy inversion_pauta_lectura on public.inversion_pauta for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo,financiero}'::public.rol_persona[])));

drop policy if exists inversion_pauta_alta on public.inversion_pauta;
create policy inversion_pauta_alta on public.inversion_pauta for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists inversion_pauta_edicion on public.inversion_pauta;
create policy inversion_pauta_edicion on public.inversion_pauta for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

-- ---------- lead ----------
drop policy if exists lead_lectura on public.lead;
create policy lead_lectura on public.lead for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists lead_alta on public.lead;
create policy lead_alta on public.lead for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists lead_edicion on public.lead;
create policy lead_edicion on public.lead for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

-- ---------- contacto_lead ----------
drop policy if exists contacto_lead_lectura on public.contacto_lead;
create policy contacto_lead_lectura on public.contacto_lead for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists contacto_lead_alta on public.contacto_lead;
create policy contacto_lead_alta on public.contacto_lead for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[]))
              and registrado_por = (select private.persona_actual()));

drop policy if exists contacto_lead_edicion on public.contacto_lead;
create policy contacto_lead_edicion on public.contacto_lead for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- oportunidad ----------
drop policy if exists oportunidad_lectura on public.oportunidad;
create policy oportunidad_lectura on public.oportunidad for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists oportunidad_alta on public.oportunidad;
create policy oportunidad_alta on public.oportunidad for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists oportunidad_edicion on public.oportunidad;
create policy oportunidad_edicion on public.oportunidad for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

-- ---------- calificacion · la ficha de 6 campos ----------
drop policy if exists calificacion_lectura on public.calificacion;
create policy calificacion_lectura on public.calificacion for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists calificacion_alta on public.calificacion;
create policy calificacion_alta on public.calificacion for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists calificacion_edicion on public.calificacion;
create policy calificacion_edicion on public.calificacion for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

-- ---------- cita ----------
drop policy if exists cita_lectura on public.cita;
create policy cita_lectura on public.cita for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists cita_alta on public.cita;
create policy cita_alta on public.cita for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists cita_edicion on public.cita;
create policy cita_edicion on public.cita for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

-- ---------- cotizacion ----------
drop policy if exists cotizacion_lectura on public.cotizacion;
create policy cotizacion_lectura on public.cotizacion for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo,financiero}'::public.rol_persona[])));

drop policy if exists cotizacion_alta on public.cotizacion;
create policy cotizacion_alta on public.cotizacion for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists cotizacion_edicion on public.cotizacion;
create policy cotizacion_edicion on public.cotizacion for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));


-- >>>>>>>>>>>>>>>>>>>> 20260914120300_rls_diseno.sql >>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- SICI · Políticas de acceso por fila · M-04 Diseño y producción arquitectónica
--
-- La fase la abre y la cierra dirección (Luisa). Las tareas las asigna quien
-- dirige el proyecto y las mueve quien las hace. La dedicación es de cada
-- quien: nadie registra horas a nombre de otro, y cada persona ve solo las
-- suyas salvo dirección y finanzas (que las necesita para repartir la
-- estructura).
-- =============================================================================

-- ---------- proyecto_fase · el cliente ve en qué fase va su proyecto ----------
drop policy if exists proyecto_fase_lectura on public.proyecto_fase;
create policy proyecto_fase_lectura on public.proyecto_fase for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles())
         or proyecto_id in (select private.proyectos_portal()));

drop policy if exists proyecto_fase_alta on public.proyecto_fase;
create policy proyecto_fase_alta on public.proyecto_fase for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists proyecto_fase_edicion on public.proyecto_fase;
create policy proyecto_fase_edicion on public.proyecto_fase for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- elemento_diseno · la nomenclatura M-05, M-06... ----------
drop policy if exists elemento_diseno_lectura on public.elemento_diseno;
create policy elemento_diseno_lectura on public.elemento_diseno for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));

drop policy if exists elemento_diseno_alta on public.elemento_diseno;
create policy elemento_diseno_alta on public.elemento_diseno for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,arquitecto,practicante}'::public.rol_persona[])));

drop policy if exists elemento_diseno_edicion on public.elemento_diseno;
create policy elemento_diseno_edicion on public.elemento_diseno for update to authenticated
  using (proyecto_id in (select private.proyectos_registro())
         and (select private.tiene_rol('{socio,director,arquitecto,practicante}'::public.rol_persona[])))
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,arquitecto,practicante}'::public.rol_persona[])));

-- ---------- tarea_diseno ----------
drop policy if exists tarea_diseno_lectura on public.tarea_diseno;
create policy tarea_diseno_lectura on public.tarea_diseno for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));

drop policy if exists tarea_diseno_alta on public.tarea_diseno;
create policy tarea_diseno_alta on public.tarea_diseno for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

drop policy if exists tarea_diseno_edicion on public.tarea_diseno;
create policy tarea_diseno_edicion on public.tarea_diseno for update to authenticated
  using (proyecto_id in (select private.proyectos_registro())
         and ((select private.es_direccion())
              or asignada_a = (select private.persona_actual())
              or asignada_por = (select private.persona_actual())))
  with check (proyecto_id in (select private.proyectos_registro())
              and ((select private.es_direccion())
                   or asignada_a = (select private.persona_actual())
                   or asignada_por = (select private.persona_actual())));

-- ---------- revision_diseno · la revisión la registra quien revisa ----------
drop policy if exists revision_diseno_lectura on public.revision_diseno;
create policy revision_diseno_lectura on public.revision_diseno for select to authenticated
  using (exists (select 1 from public.tarea_diseno t where t.id = revision_diseno.tarea_id));

drop policy if exists revision_diseno_alta on public.revision_diseno;
create policy revision_diseno_alta on public.revision_diseno for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[]))
              and exists (select 1 from public.tarea_diseno t
                          where t.id = revision_diseno.tarea_id
                            and t.proyecto_id in (select private.proyectos_registro())));

-- ---------- dedicacion · cada quien la suya ----------
drop policy if exists dedicacion_lectura on public.dedicacion;
create policy dedicacion_lectura on public.dedicacion for select to authenticated
  using (persona_id = (select private.persona_actual())
         or (select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists dedicacion_alta on public.dedicacion;
create policy dedicacion_alta on public.dedicacion for insert to authenticated
  with check ((select private.es_interno())
              and persona_id = (select private.persona_actual())
              and (proyecto_id is null or proyecto_id in (select private.proyectos_visibles())));

drop policy if exists dedicacion_edicion on public.dedicacion;
create policy dedicacion_edicion on public.dedicacion for update to authenticated
  using (persona_id = (select private.persona_actual()) or (select private.es_direccion()))
  with check ((persona_id = (select private.persona_actual()) or (select private.es_direccion()))
              and (proyecto_id is null or proyecto_id in (select private.proyectos_visibles())));

-- ---------- entregable · el cliente ve lo que se le entregó ----------
drop policy if exists entregable_lectura on public.entregable;
create policy entregable_lectura on public.entregable for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles())
         or proyecto_id in (select private.proyectos_portal()));

drop policy if exists entregable_alta on public.entregable;
create policy entregable_alta on public.entregable for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,arquitecto,practicante}'::public.rol_persona[])));

drop policy if exists entregable_edicion on public.entregable;
create policy entregable_edicion on public.entregable for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- entregable_archivo ----------
drop policy if exists entregable_archivo_lectura on public.entregable_archivo;
create policy entregable_archivo_lectura on public.entregable_archivo for select to authenticated
  using (exists (select 1 from public.entregable e where e.id = entregable_archivo.entregable_id));

drop policy if exists entregable_archivo_alta on public.entregable_archivo;
create policy entregable_archivo_alta on public.entregable_archivo for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,arquitecto,practicante}'::public.rol_persona[]))
              and exists (select 1 from public.entregable e
                          where e.id = entregable_archivo.entregable_id
                            and e.proyecto_id in (select private.proyectos_registro())));

-- ---------- complementario ----------
drop policy if exists complementario_lectura on public.complementario;
create policy complementario_lectura on public.complementario for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));

drop policy if exists complementario_alta on public.complementario;
create policy complementario_alta on public.complementario for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists complementario_edicion on public.complementario;
create policy complementario_edicion on public.complementario for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- radicacion_licencia ----------
drop policy if exists radicacion_licencia_lectura on public.radicacion_licencia;
create policy radicacion_licencia_lectura on public.radicacion_licencia for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));

drop policy if exists radicacion_licencia_alta on public.radicacion_licencia;
create policy radicacion_licencia_alta on public.radicacion_licencia for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

drop policy if exists radicacion_licencia_edicion on public.radicacion_licencia;
create policy radicacion_licencia_edicion on public.radicacion_licencia for update to authenticated
  using (proyecto_id in (select private.proyectos_registro())
         and (select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])))
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));


-- >>>>>>>>>>>>>>>>>>>> 20260914120400_rls_presupuestos.sql >>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- SICI · Políticas de acceso por fila · M-06 Presupuestos, APU y cronograma
--
-- La base de precios y los APU son conocimiento de la empresa: los ve el
-- equipo interno y los editan los profesionales. El cliente ve el presupuesto
-- vigente de su obra y su avance, que es lo que hoy recibe en el balance; nunca
-- los APU ni los precios de insumos.
-- Capítulos, ítems y avance heredan la visibilidad de su presupuesto.
-- =============================================================================

-- ---------- insumo ----------
drop policy if exists insumo_lectura on public.insumo;
create policy insumo_lectura on public.insumo for select to authenticated
  using ((select private.es_interno()));

drop policy if exists insumo_alta on public.insumo;
create policy insumo_alta on public.insumo for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

drop policy if exists insumo_edicion on public.insumo;
create policy insumo_edicion on public.insumo for update to authenticated
  using ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

-- ---------- apu ----------
drop policy if exists apu_lectura on public.apu;
create policy apu_lectura on public.apu for select to authenticated
  using ((select private.es_interno()));

drop policy if exists apu_alta on public.apu;
create policy apu_alta on public.apu for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

drop policy if exists apu_edicion on public.apu;
create policy apu_edicion on public.apu for update to authenticated
  using ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

-- ---------- apu_componente ----------
drop policy if exists apu_componente_lectura on public.apu_componente;
create policy apu_componente_lectura on public.apu_componente for select to authenticated
  using ((select private.es_interno()));

drop policy if exists apu_componente_alta on public.apu_componente;
create policy apu_componente_alta on public.apu_componente for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

drop policy if exists apu_componente_edicion on public.apu_componente;
create policy apu_componente_edicion on public.apu_componente for update to authenticated
  using ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

-- ---------- presupuesto ----------
drop policy if exists presupuesto_lectura on public.presupuesto;
create policy presupuesto_lectura on public.presupuesto for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles())
         or (vigente and proyecto_id in (select private.proyectos_portal())));

drop policy if exists presupuesto_alta on public.presupuesto;
create policy presupuesto_alta on public.presupuesto for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

drop policy if exists presupuesto_edicion on public.presupuesto;
create policy presupuesto_edicion on public.presupuesto for update to authenticated
  using (proyecto_id in (select private.proyectos_registro())
         and (select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])))
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

-- ---------- capitulo ----------
drop policy if exists capitulo_lectura on public.capitulo;
create policy capitulo_lectura on public.capitulo for select to authenticated
  using (exists (select 1 from public.presupuesto pr where pr.id = capitulo.presupuesto_id));

drop policy if exists capitulo_alta on public.capitulo;
create policy capitulo_alta on public.capitulo for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[]))
              and exists (select 1 from public.presupuesto pr
                          where pr.id = capitulo.presupuesto_id
                            and pr.proyecto_id in (select private.proyectos_registro())));

drop policy if exists capitulo_edicion on public.capitulo;
create policy capitulo_edicion on public.capitulo for update to authenticated
  using ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[]))
         and exists (select 1 from public.presupuesto pr
                     where pr.id = capitulo.presupuesto_id
                       and pr.proyecto_id in (select private.proyectos_registro())))
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[]))
              and exists (select 1 from public.presupuesto pr
                          where pr.id = capitulo.presupuesto_id
                            and pr.proyecto_id in (select private.proyectos_registro())));

-- ---------- item_presupuesto ----------
drop policy if exists item_presupuesto_lectura on public.item_presupuesto;
create policy item_presupuesto_lectura on public.item_presupuesto for select to authenticated
  using (exists (select 1 from public.capitulo c where c.id = item_presupuesto.capitulo_id));

drop policy if exists item_presupuesto_alta on public.item_presupuesto;
create policy item_presupuesto_alta on public.item_presupuesto for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[]))
              and exists (select 1 from public.capitulo c
                          join public.presupuesto pr on pr.id = c.presupuesto_id
                          where c.id = item_presupuesto.capitulo_id
                            and pr.proyecto_id in (select private.proyectos_registro())));

drop policy if exists item_presupuesto_edicion on public.item_presupuesto;
create policy item_presupuesto_edicion on public.item_presupuesto for update to authenticated
  using ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[]))
         and exists (select 1 from public.capitulo c
                     join public.presupuesto pr on pr.id = c.presupuesto_id
                     where c.id = item_presupuesto.capitulo_id
                       and pr.proyecto_id in (select private.proyectos_registro())))
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[]))
              and exists (select 1 from public.capitulo c
                          join public.presupuesto pr on pr.id = c.presupuesto_id
                          where c.id = item_presupuesto.capitulo_id
                            and pr.proyecto_id in (select private.proyectos_registro())));

-- ---------- ejecucion_item · el avance lo registra quien está en la obra ----------
drop policy if exists ejecucion_item_lectura on public.ejecucion_item;
create policy ejecucion_item_lectura on public.ejecucion_item for select to authenticated
  using (exists (select 1 from public.item_presupuesto i where i.id = ejecucion_item.item_id));

drop policy if exists ejecucion_item_alta on public.ejecucion_item;
create policy ejecucion_item_alta on public.ejecucion_item for insert to authenticated
  with check (exists (select 1 from public.item_presupuesto i
                      join public.capitulo c on c.id = i.capitulo_id
                      join public.presupuesto pr on pr.id = c.presupuesto_id
                      where i.id = ejecucion_item.item_id
                        and pr.proyecto_id in (select private.proyectos_registro())));

drop policy if exists ejecucion_item_edicion on public.ejecucion_item;
create policy ejecucion_item_edicion on public.ejecucion_item for update to authenticated
  using (exists (select 1 from public.item_presupuesto i
                 join public.capitulo c on c.id = i.capitulo_id
                 join public.presupuesto pr on pr.id = c.presupuesto_id
                 where i.id = ejecucion_item.item_id
                   and pr.proyecto_id in (select private.proyectos_registro())))
  with check (exists (select 1 from public.item_presupuesto i
                      join public.capitulo c on c.id = i.capitulo_id
                      join public.presupuesto pr on pr.id = c.presupuesto_id
                      where i.id = ejecucion_item.item_id
                        and pr.proyecto_id in (select private.proyectos_registro())));

-- ---------- actividad_cronograma ----------
drop policy if exists actividad_cronograma_lectura on public.actividad_cronograma;
create policy actividad_cronograma_lectura on public.actividad_cronograma for select to authenticated
  using (exists (select 1 from public.presupuesto pr where pr.id = actividad_cronograma.presupuesto_id));

drop policy if exists actividad_cronograma_alta on public.actividad_cronograma;
create policy actividad_cronograma_alta on public.actividad_cronograma for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[]))
              and exists (select 1 from public.presupuesto pr
                          where pr.id = actividad_cronograma.presupuesto_id
                            and pr.proyecto_id in (select private.proyectos_registro())));

drop policy if exists actividad_cronograma_edicion on public.actividad_cronograma;
create policy actividad_cronograma_edicion on public.actividad_cronograma for update to authenticated
  using (exists (select 1 from public.presupuesto pr
                 where pr.id = actividad_cronograma.presupuesto_id
                   and pr.proyecto_id in (select private.proyectos_registro())))
  with check (exists (select 1 from public.presupuesto pr
                      where pr.id = actividad_cronograma.presupuesto_id
                        and pr.proyecto_id in (select private.proyectos_registro())));


-- >>>>>>>>>>>>>>>>>>>> 20260914120500_rls_obra.sql >>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- SICI · Políticas de acceso por fila · M-01 Gasto de obra, M-03 Bitácora y
-- actas, M-08 Portal de cliente y contratista
--
-- El residente registra en sus obras a su propio nombre; aprueba, concilia y
-- corrige dirección (y finanzas solo concilia). El cliente ve desde el portal
-- sus adicionales, sus actas de cobro y la bitácora, y decide sobre los
-- adicionales; nunca ve un movimiento, un costo ni un proveedor. El
-- contratista ve solo sus actas de pago.
-- =============================================================================

-- ---------- fondo_caja · la ve quien la tiene a cargo ----------
drop policy if exists fondo_caja_lectura on public.fondo_caja;
create policy fondo_caja_lectura on public.fondo_caja for select to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[]))
         or responsable_id = (select private.persona_actual()));

drop policy if exists fondo_caja_alta on public.fondo_caja;
create policy fondo_caja_alta on public.fondo_caja for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists fondo_caja_edicion on public.fondo_caja;
create policy fondo_caja_edicion on public.fondo_caja for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- cambio_obra · lo registra la obra; lo cierra diseño ----------
drop policy if exists cambio_obra_lectura on public.cambio_obra;
create policy cambio_obra_lectura on public.cambio_obra for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));

drop policy if exists cambio_obra_alta on public.cambio_obra;
create policy cambio_obra_alta on public.cambio_obra for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and decidido_por = (select private.persona_actual()));

drop policy if exists cambio_obra_edicion on public.cambio_obra;
create policy cambio_obra_edicion on public.cambio_obra for update to authenticated
  using ((select private.es_direccion())
         or (proyecto_id in (select private.proyectos_registro())
             and (select private.tiene_rol('{arquitecto,practicante}'::public.rol_persona[]))))
  with check ((select private.es_direccion())
              or (proyecto_id in (select private.proyectos_registro())
                  and (select private.tiene_rol('{arquitecto,practicante}'::public.rol_persona[]))));

-- ---------- adicional · lo propone la obra; la decisión es del cliente ----------
drop policy if exists adicional_lectura on public.adicional;
create policy adicional_lectura on public.adicional for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles())
         or proyecto_id in (select private.proyectos_portal()));

drop policy if exists adicional_alta on public.adicional;
create policy adicional_alta on public.adicional for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro()));

drop policy if exists adicional_edicion on public.adicional;
create policy adicional_edicion on public.adicional for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- bitacora ----------
drop policy if exists bitacora_lectura on public.bitacora;
create policy bitacora_lectura on public.bitacora for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles())
         or proyecto_id in (select private.proyectos_portal()));

drop policy if exists bitacora_alta on public.bitacora;
create policy bitacora_alta on public.bitacora for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and registrado_por = (select private.persona_actual()));

drop policy if exists bitacora_edicion on public.bitacora;
create policy bitacora_edicion on public.bitacora for update to authenticated
  using (proyecto_id in (select private.proyectos_registro())
         and registrado_por = (select private.persona_actual()))
  with check (proyecto_id in (select private.proyectos_registro())
              and registrado_por = (select private.persona_actual()));

-- ---------- bitacora_cuadrilla · hereda de su bitácora ----------
drop policy if exists bitacora_cuadrilla_lectura on public.bitacora_cuadrilla;
create policy bitacora_cuadrilla_lectura on public.bitacora_cuadrilla for select to authenticated
  using (exists (select 1 from public.bitacora b where b.id = bitacora_cuadrilla.bitacora_id));

drop policy if exists bitacora_cuadrilla_alta on public.bitacora_cuadrilla;
create policy bitacora_cuadrilla_alta on public.bitacora_cuadrilla for insert to authenticated
  with check (exists (select 1 from public.bitacora b
                      where b.id = bitacora_cuadrilla.bitacora_id
                        and b.proyecto_id in (select private.proyectos_registro())
                        and (b.registrado_por = (select private.persona_actual())
                             or (select private.es_direccion()))));

drop policy if exists bitacora_cuadrilla_edicion on public.bitacora_cuadrilla;
create policy bitacora_cuadrilla_edicion on public.bitacora_cuadrilla for update to authenticated
  using (exists (select 1 from public.bitacora b
                 where b.id = bitacora_cuadrilla.bitacora_id
                   and b.proyecto_id in (select private.proyectos_registro())
                   and (b.registrado_por = (select private.persona_actual())
                        or (select private.es_direccion()))))
  with check (exists (select 1 from public.bitacora b
                      where b.id = bitacora_cuadrilla.bitacora_id
                        and b.proyecto_id in (select private.proyectos_registro())
                        and (b.registrado_por = (select private.persona_actual())
                             or (select private.es_direccion()))));

-- ---------- acta · de cobro para el cliente, de pago para su contratista ----------
drop policy if exists acta_lectura on public.acta;
create policy acta_lectura on public.acta for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles())
         or (tipo = 'cobro_cliente' and proyecto_id in (select private.proyectos_portal()))
         or (tipo = 'pago_contratista' and tercero_id = (select private.persona_actual())));

drop policy if exists acta_alta on public.acta;
create policy acta_alta on public.acta for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,residente,financiero}'::public.rol_persona[])));

drop policy if exists acta_edicion on public.acta;
create policy acta_edicion on public.acta for update to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

-- ---------- acta_item · hereda de su acta; es constancia, no se edita ----------
drop policy if exists acta_item_lectura on public.acta_item;
create policy acta_item_lectura on public.acta_item for select to authenticated
  using (exists (select 1 from public.acta a where a.id = acta_item.acta_id));

drop policy if exists acta_item_alta on public.acta_item;
create policy acta_item_alta on public.acta_item for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,residente,financiero}'::public.rol_persona[]))
              and exists (select 1 from public.acta a
                          where a.id = acta_item.acta_id
                            and a.proyecto_id in (select private.proyectos_registro())));

-- ---------- movimiento · el dinero: solo equipo interno ----------
drop policy if exists movimiento_lectura on public.movimiento;
create policy movimiento_lectura on public.movimiento for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));

drop policy if exists movimiento_alta on public.movimiento;
create policy movimiento_alta on public.movimiento for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and registrado_por = (select private.persona_actual()));

-- Aprueba y corrige dirección; finanzas solo concilia (lo vigila el disparador).
drop policy if exists movimiento_edicion on public.movimiento;
create policy movimiento_edicion on public.movimiento for update to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

-- ---------- aprobacion_cliente · la decisión del cliente en el portal ----------
drop policy if exists aprobacion_cliente_lectura on public.aprobacion_cliente;
create policy aprobacion_cliente_lectura on public.aprobacion_cliente for select to authenticated
  using (persona_id = (select private.persona_actual())
         or exists (select 1 from public.adicional a
                    where a.id = aprobacion_cliente.adicional_id
                      and a.proyecto_id in (select private.proyectos_visibles())));

drop policy if exists aprobacion_cliente_alta on public.aprobacion_cliente;
create policy aprobacion_cliente_alta on public.aprobacion_cliente for insert to authenticated
  with check (persona_id = (select private.persona_actual())
              and exists (select 1 from public.adicional a
                          where a.id = aprobacion_cliente.adicional_id
                            and a.proyecto_id in (select private.proyectos_portal())));

-- ---------- evidencia · la sube quien está en la obra; nadie la edita ----------
drop policy if exists evidencia_lectura on public.evidencia;
create policy evidencia_lectura on public.evidencia for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));

drop policy if exists evidencia_alta on public.evidencia;
create policy evidencia_alta on public.evidencia for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and registrada_por = (select private.persona_actual()));

-- ---------- pendiente_obra · la lista de remates del residente ----------
-- El contratista ve lo que tiene que hacer y puede marcarlo como hecho, pero
-- la verificación la hace otro: eso lo impide el disparador, no la política.
drop policy if exists pendiente_obra_lectura on public.pendiente_obra;
create policy pendiente_obra_lectura on public.pendiente_obra for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles())
         or ejecutor_id = (select private.persona_actual()));

drop policy if exists pendiente_obra_alta on public.pendiente_obra;
create policy pendiente_obra_alta on public.pendiente_obra for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,residente,arquitecto}'::public.rol_persona[])));

drop policy if exists pendiente_obra_edicion on public.pendiente_obra;
create policy pendiente_obra_edicion on public.pendiente_obra for update to authenticated
  using ((select private.es_direccion())
         or (proyecto_id in (select private.proyectos_registro())
             and (responsable_id = (select private.persona_actual())
                  or creado_por = (select private.persona_actual())))
         or ejecutor_id = (select private.persona_actual()))
  with check ((select private.es_direccion())
              or (proyecto_id in (select private.proyectos_registro())
                  and (responsable_id = (select private.persona_actual())
                       or creado_por = (select private.persona_actual())))
              or ejecutor_id = (select private.persona_actual()));


-- >>>>>>>>>>>>>>>>>>>> 20260914120600_rls_reclamaciones.sql >>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- SICI · Políticas de acceso por fila · M-02 Reclamaciones y listas de chequeo
--
-- La reclamación la gobierna dirección. Las plantillas de listas de chequeo
-- (fases, curaduría, pólizas, presupuesto) las define dirección y las ve todo
-- el equipo. Responder una lista es de quien registra en ese proyecto.
-- El historial de la cascada lo escribe el sistema y solo se lee.
-- =============================================================================

-- ---------- reclamacion ----------
drop policy if exists reclamacion_lectura on public.reclamacion;
create policy reclamacion_lectura on public.reclamacion for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));

drop policy if exists reclamacion_alta on public.reclamacion;
create policy reclamacion_alta on public.reclamacion for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists reclamacion_edicion on public.reclamacion;
create policy reclamacion_edicion on public.reclamacion for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- reclamacion_evento · solo lectura ----------
drop policy if exists reclamacion_evento_lectura on public.reclamacion_evento;
create policy reclamacion_evento_lectura on public.reclamacion_evento for select to authenticated
  using (exists (select 1 from public.reclamacion r where r.id = reclamacion_evento.reclamacion_id));

-- ---------- lista_chequeo · plantillas ----------
drop policy if exists lista_chequeo_lectura on public.lista_chequeo;
create policy lista_chequeo_lectura on public.lista_chequeo for select to authenticated
  using ((select private.es_interno()));

drop policy if exists lista_chequeo_alta on public.lista_chequeo;
create policy lista_chequeo_alta on public.lista_chequeo for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists lista_chequeo_edicion on public.lista_chequeo;
create policy lista_chequeo_edicion on public.lista_chequeo for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- lista_chequeo_item ----------
drop policy if exists lista_chequeo_item_lectura on public.lista_chequeo_item;
create policy lista_chequeo_item_lectura on public.lista_chequeo_item for select to authenticated
  using ((select private.es_interno()));

drop policy if exists lista_chequeo_item_alta on public.lista_chequeo_item;
create policy lista_chequeo_item_alta on public.lista_chequeo_item for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists lista_chequeo_item_edicion on public.lista_chequeo_item;
create policy lista_chequeo_item_edicion on public.lista_chequeo_item for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- chequeo · una lista aplicada a una fase, radicación, póliza o presupuesto ----------
drop policy if exists chequeo_lectura on public.chequeo;
create policy chequeo_lectura on public.chequeo for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));

drop policy if exists chequeo_alta on public.chequeo;
create policy chequeo_alta on public.chequeo for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro()));

-- ---------- chequeo_respuesta ----------
drop policy if exists chequeo_respuesta_lectura on public.chequeo_respuesta;
create policy chequeo_respuesta_lectura on public.chequeo_respuesta for select to authenticated
  using (exists (select 1 from public.chequeo c where c.id = chequeo_respuesta.chequeo_id));

drop policy if exists chequeo_respuesta_alta on public.chequeo_respuesta;
create policy chequeo_respuesta_alta on public.chequeo_respuesta for insert to authenticated
  with check (verificado_por = (select private.persona_actual())
              and exists (select 1 from public.chequeo c
                          where c.id = chequeo_respuesta.chequeo_id
                            and c.proyecto_id in (select private.proyectos_registro())));

drop policy if exists chequeo_respuesta_edicion on public.chequeo_respuesta;
create policy chequeo_respuesta_edicion on public.chequeo_respuesta for update to authenticated
  using (exists (select 1 from public.chequeo c
                 where c.id = chequeo_respuesta.chequeo_id
                   and c.proyecto_id in (select private.proyectos_registro())))
  with check (verificado_por = (select private.persona_actual())
              and exists (select 1 from public.chequeo c
                          where c.id = chequeo_respuesta.chequeo_id
                            and c.proyecto_id in (select private.proyectos_registro())));


-- >>>>>>>>>>>>>>>>>>>> 20260914120700_rls_finanzas.sql >>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- SICI · Políticas de acceso por fila · M-07 Finanzas
--
-- Saldos, ingresos, extractos, cierres y distribución de estructura: socios,
-- dirección y finanzas. Una partida abierta la ve y la resuelve también la
-- persona a la que se le asignó (F1: cada diferencia tiene dueño).
-- Cerrar un mes es de finanzas o de un socio; reabrirlo, solo de un socio
-- (lo vigila el disparador).
-- =============================================================================

-- ---------- saldo_cuenta ----------
drop policy if exists saldo_cuenta_lectura on public.saldo_cuenta;
create policy saldo_cuenta_lectura on public.saldo_cuenta for select to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists saldo_cuenta_alta on public.saldo_cuenta;
create policy saldo_cuenta_alta on public.saldo_cuenta for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists saldo_cuenta_edicion on public.saldo_cuenta;
create policy saldo_cuenta_edicion on public.saldo_cuenta for update to authenticated
  using ((select private.tiene_rol('{socio,financiero}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,financiero}'::public.rol_persona[])));

-- ---------- ingreso ----------
drop policy if exists ingreso_lectura on public.ingreso;
create policy ingreso_lectura on public.ingreso for select to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists ingreso_alta on public.ingreso;
create policy ingreso_alta on public.ingreso for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[]))
              and registrado_por = (select private.persona_actual()));

drop policy if exists ingreso_edicion on public.ingreso;
create policy ingreso_edicion on public.ingreso for update to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

-- ---------- extracto_linea ----------
drop policy if exists extracto_linea_lectura on public.extracto_linea;
create policy extracto_linea_lectura on public.extracto_linea for select to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists extracto_linea_alta on public.extracto_linea;
create policy extracto_linea_alta on public.extracto_linea for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists extracto_linea_edicion on public.extracto_linea;
create policy extracto_linea_edicion on public.extracto_linea for update to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

-- ---------- partida_abierta ----------
drop policy if exists partida_abierta_lectura on public.partida_abierta;
create policy partida_abierta_lectura on public.partida_abierta for select to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[]))
         or responsable_id = (select private.persona_actual()));

drop policy if exists partida_abierta_alta on public.partida_abierta;
create policy partida_abierta_alta on public.partida_abierta for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists partida_abierta_edicion on public.partida_abierta;
create policy partida_abierta_edicion on public.partida_abierta for update to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[]))
         or responsable_id = (select private.persona_actual()))
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[]))
              or responsable_id = (select private.persona_actual()));

-- ---------- cierre_mes ----------
drop policy if exists cierre_mes_lectura on public.cierre_mes;
create policy cierre_mes_lectura on public.cierre_mes for select to authenticated
  using ((select private.es_interno()));

drop policy if exists cierre_mes_alta on public.cierre_mes;
create policy cierre_mes_alta on public.cierre_mes for insert to authenticated
  with check ((select private.tiene_rol('{socio,financiero}'::public.rol_persona[])));

drop policy if exists cierre_mes_edicion on public.cierre_mes;
create policy cierre_mes_edicion on public.cierre_mes for update to authenticated
  using ((select private.tiene_rol('{socio}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio}'::public.rol_persona[])));

-- ---------- distribucion_estructura ----------
drop policy if exists distribucion_estructura_lectura on public.distribucion_estructura;
create policy distribucion_estructura_lectura on public.distribucion_estructura for select to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists distribucion_estructura_alta on public.distribucion_estructura;
create policy distribucion_estructura_alta on public.distribucion_estructura for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists distribucion_estructura_edicion on public.distribucion_estructura;
create policy distribucion_estructura_edicion on public.distribucion_estructura for update to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));


-- >>>>>>>>>>>>>>>>>>>> 20260914120800_permisos_api.sql >>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- SICI · Permisos de la API de Supabase
--
-- Desde el 30 de mayo de 2026 los proyectos nuevos de Supabase ya no dan
-- permisos automáticos sobre las tablas nuevas, y desde el 30 de octubre de
-- 2026 aplica a todos. Sin este archivo la aplicación no podría leer nada.
-- Los proyectos más viejos, al revés, dan todo a todos, incluido "anon". Por
-- eso aquí primero se retira todo y después se otorga exactamente lo necesario:
-- el resultado es el mismo con cualquiera de las dos configuraciones.
--
-- Dos capas, las dos necesarias:
--   1. Estos permisos dicen qué operación puede intentar cada rol.
--   2. Las políticas rls_* dicen sobre qué filas.
--
-- Roles de Supabase:
--   anon           cualquiera con la llave pública, sin sesión: nada.
--   authenticated  usuarios con sesión: lo necesario, filtrado por políticas.
--   service_role   tareas del servidor (alertas, importación de pauta): todo.
--                  Su llave nunca va en el navegador ni en la PWA.
--
-- Nadie tiene permiso de borrar, salvo retirar un acceso a un proyecto.
-- Idempotente.
-- =============================================================================

-- ---------- 1. Retirar todo ----------
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
revoke all on schema private from public, anon;
revoke all on all functions in schema private from public, anon, authenticated;

-- Lo que se cree después en "public" tampoco nace abierto para "anon".
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;

-- ---------- 2. authenticated: tablas ----------

-- Se consultan, se crean y se actualizan (las políticas dicen qué filas).
grant select, insert, update on
  public.persona, public.cliente, public.categoria_costo, public.cuenta,
  public.proyecto, public.centro_costo, public.regla_alerta,
  public.experimento, public.campana, public.inversion_pauta, public.lead, public.contacto_lead,
  public.oportunidad, public.calificacion, public.cita, public.cotizacion,
  public.proyecto_fase, public.elemento_diseno, public.tarea_diseno, public.dedicacion,
  public.entregable, public.complementario, public.radicacion_licencia,
  public.insumo, public.apu, public.apu_componente, public.presupuesto, public.capitulo,
  public.item_presupuesto, public.ejecucion_item, public.actividad_cronograma,
  public.fondo_caja, public.cambio_obra, public.adicional, public.bitacora, public.bitacora_cuadrilla,
  public.acta, public.movimiento,
  public.reclamacion, public.lista_chequeo, public.lista_chequeo_item, public.chequeo_respuesta,
  public.saldo_cuenta, public.ingreso, public.extracto_linea, public.partida_abierta,
  public.cierre_mes, public.distribucion_estructura,
  public.objetivo, public.pendiente_obra
to authenticated;

-- Constancias: se crean y se consultan, nunca se editan.
grant select, insert on
  public.revision_diseno, public.entregable_archivo, public.acta_item,
  public.aprobacion_cliente, public.chequeo, public.evidencia
to authenticated;

-- Una sola fila que se ajusta; alertas que se marcan como resueltas.
grant select, update on public.parametro, public.alerta to authenticated;

-- Las escribe el sistema.
grant select on public.evento_auditoria, public.reclamacion_evento, public.aviso to authenticated;

-- El único retiro permitido.
grant select, insert, update, delete on public.acceso_proyecto to authenticated;

-- ---------- 3. authenticated: vistas ----------
grant select on
  public.v_movimiento_vigente, public.v_balance_centro_costo, public.v_adicionales_netos,
  public.v_desviacion_capitulo, public.v_caja_menor, public.v_cambios_sin_reflejar,
  public.v_proyecto_resumen, public.v_bitacora_faltante, public.v_cartera,
  public.v_flujo_13_semanas, public.v_rentabilidad_proyecto, public.v_partidas_abiertas,
  public.v_fase_horas, public.v_dedicacion_pendiente, public.v_capacidad_13_semanas,
  public.v_complementarios_atrasados, public.v_reclamaciones, public.v_embudo_mensual,
  public.v_retorno_pauta, public.v_calibracion_capitulo, public.v_apu_costo,
  public.v_pendientes_obra, public.v_trabajo_abierto, public.v_objetivos
to authenticated;

-- ---------- 4. authenticated: secuencias y funciones ----------
grant usage, select on all sequences in schema public to authenticated;

grant execute on function public.distribuir_estructura(date) to authenticated;

-- Las políticas y las vistas llaman estas funciones con los permisos de quien
-- consulta. El resto de "private" (reglas, generador de alertas) no se otorga.
grant usage on schema private to authenticated;
grant execute on function
  private.hoy(),
  private.pesos(numeric),
  private.uuid_seguro(text),
  private.persona_actual(),
  private.es_interno(),
  private.tiene_rol(public.rol_persona[]),
  private.es_direccion(),
  private.proyectos_visibles(),
  private.proyectos_registro(),
  private.proyectos_portal(),
  private.mes_cerrado(date)
to authenticated;

-- ---------- 5. service_role ----------
grant usage on schema public, private to service_role;
grant select, insert, update, delete on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;
grant execute on all functions in schema private to service_role;


-- >>>>>>>>>>>>>>>>>>>> 20260914120900_almacenamiento.sql >>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- SICI · Almacenamiento de fotos y documentos
--
-- Dos depósitos privados. Nada se publica con enlace abierto.
--   evidencias   fotos de obra y de peritaje, soportes de gasto
--   documentos   actas, pólizas, informes, entregables en PDF
--
-- Regla de rutas: todo archivo vive en una carpeta con el id del proyecto,
-- '<proyecto_id>/<archivo>'. Así ver o subir un archivo exige los mismos
-- permisos que ver o registrar en ese proyecto.
--
-- No hay políticas de edición ni de borrado: un archivo subido no se reemplaza
-- (P5). Por eso la aplicación nunca debe subir con "upsert".
-- Idempotente.
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('evidencias', 'evidencias', false, 15 * 1024 * 1024,
   array['image/jpeg','image/png','image/heic','image/heif','image/webp','application/pdf']),
  ('documentos', 'documentos', false, 50 * 1024 * 1024,
   array['application/pdf','image/jpeg','image/png',
         'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
         'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict (id) do nothing;

drop policy if exists sici_objetos_lectura on storage.objects;
create policy sici_objetos_lectura on storage.objects for select to authenticated
  using (bucket_id in ('evidencias','documentos')
         and private.uuid_seguro((storage.foldername(name))[1]) in (select private.proyectos_visibles()));

drop policy if exists sici_objetos_alta on storage.objects;
create policy sici_objetos_alta on storage.objects for insert to authenticated
  with check (bucket_id in ('evidencias','documentos')
              and private.uuid_seguro((storage.foldername(name))[1]) in (select private.proyectos_registro()));


-- >>>>>>>>>>>>>>>>>>>> 20260914121000_vinculo_usuarios.sql >>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- SICI · Enlace entre usuarios de Supabase y fichas de persona
--
-- Cómo se da acceso a alguien:
--   1. Dirección crea su ficha en "persona", con su correo.
--   2. En Supabase, Authentication → Users → Invite user, con ese mismo correo.
--   3. Cuando la persona acepta la invitación y confirma el correo, este
--      disparador enlaza su usuario con su ficha. Sin correo confirmado no
--      enlaza nada: nadie toma la ficha de otro registrándose con su correo.
--
-- Recomendado en Supabase: Authentication → Sign In / Providers → desactivar
-- "Allow new users to sign up". Al SICI se entra por invitación.
--
-- Va en una migración aparte porque toca el esquema auth de Supabase, donde
-- solo se permite crear disparadores. Si falla, lo demás ya quedó aplicado y
-- el enlace se hace a mano:
--   update persona set auth_user_id = '<uuid del usuario>' where correo = '<correo>';
-- Idempotente.
-- =============================================================================

create or replace trigger sici_vincular_persona
  after insert or update of email, email_confirmed_at on auth.users
  for each row execute function private.vincular_persona_auth();

-- El servicio de autenticación de Supabase dispara la función con su propio rol.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    grant usage on schema private to supabase_auth_admin;
    grant execute on function private.vincular_persona_auth() to supabase_auth_admin;
  end if;
end $$;


-- >>>>>>>>>>>>>>>>>>>> 20261012120000_fases_por_tipo.sql >>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- SICI · Módulo de arquitectura y diseño · etapa 2 · 1 de 2
-- Fases por tipo de proyecto y rol de director de proyectos de construcción
--
-- Decisión de Felipe del 12 de octubre de 2026: los peritajes, las consultorías
-- y las obras entran como proyectos, cada tipo con sus fases propias.
--
--   Peritaje y consultoría: levantamiento, informe, presupuesto, entrega del
--                           expediente.
--   Obra:                   preconstrucción, ejecución, cierre.
--
-- 'presupuesto' y 'cierre' ya existían. Aquí solo se agregan las que faltan.
--
-- Va en un archivo aparte a propósito: Postgres no deja usar un valor nuevo de
-- una lista en la misma transacción que lo crea. Por eso las plantillas que
-- usan estas fases se cargan después, desde supabase/semilla/040_plantillas.sql.
--
-- Agregar una fase más adelante es otra línea como estas en una migración nueva.
-- Idempotente.
-- =============================================================================

alter type public.fase_proyecto add value if not exists 'levantamiento';
alter type public.fase_proyecto add value if not exists 'informe';
alter type public.fase_proyecto add value if not exists 'entrega_expediente';
alter type public.fase_proyecto add value if not exists 'preconstruccion';
alter type public.fase_proyecto add value if not exists 'ejecucion';

-- Director de proyectos de construcción (Felipe, 12-10-2026). Hoy es un
-- ingeniero civil; la profesión se escoge aparte, en la ficha de la persona.
alter type public.rol_persona add value if not exists 'director_proyecto';


-- >>>>>>>>>>>>>>>>>>>> 20261012120100_modulo_diseno.sql >>>>>>>>>>>>>>>>>>>>

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


-- >>>>>>>>>>>>>>>>>>>> 20261012120200_indicadores.sql >>>>>>>>>>>>>>>>>>>>

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


-- >>>>>>>>>>>>>>>>>>>> 20261012120300_mensajes.sql >>>>>>>>>>>>>>>>>>>>

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


-- >>>>>>>>>>>>>>>>>>>> 20261013120000_aplicacion.sql >>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- SICI · Lo que la aplicación necesita para arrancar (MVP del 13-10-2026)
--
--   · La carpeta de Drive de cada proyecto: la aplicación lee lo que hay ahí.
--   · mi_sesion(): quién soy y en qué proyectos puedo asignar, revisar o
--     registrar. Con eso la aplicación sabe qué botones mostrar; lo que la
--     persona no puede hacer lo sigue impidiendo la base.
--   · El enlace con la ficha también funciona si la persona se registró antes
--     de que dirección creara su ficha.
--
-- No toca las migraciones anteriores. Idempotente.
-- =============================================================================

alter table public.proyecto add column if not exists carpeta_drive text;
do $$ begin
  alter table public.proyecto add constraint proyecto_carpeta_es_de_drive
    check (carpeta_drive is null or carpeta_drive ~ '^https://drive\.google\.com/');
exception when duplicate_object then null; end $$;
comment on column public.proyecto.carpeta_drive is
  'Enlace de la carpeta de Drive del proyecto. La aplicación lista lo que hay dentro con la cuenta de Google de quien la abre: cada quien ve solo lo que Drive le deja ver.';

-- Quien se registró primero y recibió la ficha después también queda enlazado.
-- Igual que en el otro sentido, solo con el correo confirmado.
create or replace function private.vincular_persona_existente() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.auth_user_id is null and new.activo and new.correo is not null then
    select u.id into new.auth_user_id
    from auth.users u
    where lower(u.email) = lower(new.correo) and u.email_confirmed_at is not null
      and not exists (select 1 from public.persona o where o.auth_user_id = u.id)
    limit 1;
  end if;
  return new;
exception when others then
  raise warning 'SICI: no se pudo buscar el usuario de %: %', new.correo, sqlerrm;
  return new;
end $$;

drop trigger if exists tr_persona_vincular on public.persona;
create trigger tr_persona_vincular
  before insert or update of correo, activo on public.persona
  for each row execute function private.vincular_persona_existente();

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
    'registra',     coalesce((select jsonb_agg(g) from private.proyectos_registro() g), '[]'::jsonb))
  from public.persona p
  where p.id = (select private.persona_actual())
$$;

revoke all on all functions in schema public  from public, anon;
revoke all on all functions in schema private from public, anon;
revoke all on function private.vincular_persona_existente() from authenticated;
grant execute on function public.mi_sesion() to authenticated;
grant execute on all functions in schema public to service_role;
grant execute on all functions in schema private to service_role;


-- >>>>>>>>>>>>>>>>>>>> 20261014120000_carga_semanal.sql >>>>>>>>>>>>>>>>>>>>

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


-- >>>>>>>>>>>>>>>>>>>> 20261015120000_flujo_por_fase.sql >>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- SICI · El flujo de cada tipo de proyecto (D18 · 15-10-2026)
--
--   · Cada fase de una plantilla dice cuánto puede durar, en días hábiles, y
--     qué papel responde por ella. Se define una vez, en la plantilla.
--   · Al abrir la fase en un proyecto, el sistema le pone su fecha de entrega
--     y su responsable. Nadie tiene que acordarse.
--
-- El plazo se copia al proyecto cuando nace la fase: cambiar la plantilla
-- después no mueve los proyectos que ya están andando. Una fecha o un
-- responsable puestos a mano no se pisan.
--
-- No toca las migraciones anteriores. Idempotente.
-- =============================================================================

alter table public.plantilla_fase add column if not exists dias_habiles_plazo smallint;
alter table public.plantilla_fase add column if not exists responsable_papel public.papel_proyecto not null default 'dirige';
alter table public.proyecto_fase add column if not exists dias_habiles_plazo smallint;
alter table public.proyecto_fase add column if not exists responsable_id uuid references public.persona(id);
create index if not exists proyecto_fase_responsable on public.proyecto_fase (responsable_id);

do $$ begin
  alter table public.plantilla_fase add constraint plantilla_fase_plazo_sano
    check (dias_habiles_plazo is null or dias_habiles_plazo between 1 and 400);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.plantilla_fase add constraint plantilla_fase_responde_quien_trabaja
    check (responsable_papel <> 'observa');
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.proyecto_fase add constraint fase_plazo_sano
    check (dias_habiles_plazo is null or dias_habiles_plazo between 1 and 400);
exception when duplicate_object then null; end $$;

comment on column public.plantilla_fase.dias_habiles_plazo is
  'Días hábiles que puede durar la fase desde que se abre. Vacío: sin plazo, la fecha se pone a mano.';
comment on column public.plantilla_fase.responsable_papel is
  'Papel que responde por la fase. Al abrirla, si en el proyecto hay una sola persona con ese papel, queda de responsable.';

create or replace function private.flujo_de_fase() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_plazo   smallint;
  v_papel   public.papel_proyecto := 'dirige';
  v_quienes uuid[];
  v_nombre  text;
begin
  select pf.dias_habiles_plazo, pf.responsable_papel into v_plazo, v_papel
  from public.plantilla_fase pf
  join public.proyecto p on p.plantilla_id = pf.plantilla_id
  where p.id = new.proyecto_id and pf.fase = new.fase;

  if tg_op = 'INSERT' then
    new.dias_habiles_plazo := coalesce(new.dias_habiles_plazo, v_plazo);
  end if;

  -- Al abrir la fase: quién responde y para cuándo.
  if new.estado <> 'pendiente' and (tg_op = 'INSERT' or old.estado = 'pendiente') then
    if new.responsable_id is null then
      select array_agg(a.persona_id) into v_quienes
      from public.acceso_proyecto a
      join public.persona p on p.id = a.persona_id
      where a.proyecto_id = new.proyecto_id and a.papel = coalesce(v_papel, 'dirige')
        and p.activo and p.es_interno;
      -- Con dos personas en el mismo papel no se adivina: escoge dirección.
      if cardinality(v_quienes) = 1 then
        new.responsable_id := v_quienes[1];
      end if;
    end if;
    if new.fecha_compromiso is null and new.dias_habiles_plazo is not null then
      new.fecha_compromiso := private.sumar_habiles(private.hoy(), new.dias_habiles_plazo);
    end if;
  end if;

  if new.responsable_id is not null
     and (tg_op = 'INSERT' or new.responsable_id is distinct from old.responsable_id)
     and not exists (
       select 1 from public.persona p
       where p.id = new.responsable_id and p.es_interno and p.activo
         and (p.rol in ('socio','director')
              or exists (select 1 from public.acceso_proyecto a
                         where a.persona_id = p.id and a.proyecto_id = new.proyecto_id
                           and a.papel <> 'observa'))) then
    select p.nombre into v_nombre from public.persona p where p.id = new.responsable_id;
    raise exception 'D18 · % no hace parte del equipo de este proyecto: primero se le da un papel',
      coalesce(v_nombre, 'Esa persona');
  end if;
  return new;
end $$;

drop trigger if exists tr_proyecto_fase_flujo on public.proyecto_fase;
create trigger tr_proyecto_fase_flujo
  before insert or update on public.proyecto_fase
  for each row execute function private.flujo_de_fase();

revoke all on all functions in schema public  from public, anon;
revoke all on all functions in schema private from public, anon;
revoke all on function private.flujo_de_fase() from authenticated;
grant execute on all functions in schema public to service_role;
grant execute on all functions in schema private to service_role;


-- >>>>>>>>>>>>>>>>>>>> 20261016120000_tareas_tipicas.sql >>>>>>>>>>>>>>>>>>>>

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


-- >>>>>>>>>>>>>>>>>>>> 20261017120000_cierre_de_fase.sql >>>>>>>>>>>>>>>>>>>>

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


-- >>>>>>>>>>>>>>>>>>>> 20261018120000_embudo_de_ventas.sql >>>>>>>>>>>>>>>>>>>>

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


-- >>>>>>>>>>>>>>>>>>>> 20261019120000_modulo_obra.sql >>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- SICI · El módulo de obra en la aplicación · O12 a O15
--
-- Felipe pidió el 2026-10-13, comentando la plataforma: «que en Obra exista
-- toda la información de cada obra y un tablero que resuma todos los proyectos
-- en construcción, con la gestión documental asociada a las carpetas de Drive,
-- facturas y flujo de caja». La base ya tenía el dinero (movimiento, ingreso),
-- la bitácora y los pendientes; aquí se agrega lo que faltaba para usarlo
-- desde el teléfono:
--   O12 · el número de la factura en el gasto;
--   O13 · el índice de documentos de la obra que no nacen de un gasto;
--   O14 · registrar un gasto desde la obra sin conocer los centros de costo;
--   O15 · el tablero de obras y el flujo de cada una, ya leídos en frases.
-- =============================================================================

-- ---------- O12 · La factura del gasto ----------
alter table public.movimiento add column if not exists numero_factura text;
alter table public.movimiento drop constraint if exists mov_factura_escrita;
alter table public.movimiento add constraint mov_factura_escrita
  check (numero_factura is null or length(trim(numero_factura)) between 1 and 60);
comment on column public.movimiento.numero_factura is
  'O12 · El número que trae la factura del proveedor. Con él se cruza el gasto contra la factura en Drive.';
-- La vista de lo vigente fijó sus columnas al crearse: se vuelve a crear para
-- que traiga la factura (la columna nueva queda al final, como exige Postgres).
create or replace view public.v_movimiento_vigente with (security_invoker = true) as
select m.*
from public.movimiento m
where m.anula_a is null
  and m.aprobacion <> 'rechazado'
  and not exists (select 1 from public.movimiento x where x.anula_a = m.id);


-- ---------- O13 · Los documentos de la obra ----------
-- Contrato, presupuesto, planos, licencia, pólizas y actas viven en Drive. Aquí
-- queda el índice: qué es, dónde está y quién lo puso. No se borra: se retira.
create table if not exists public.documento_obra (
  id              uuid primary key default gen_random_uuid(),
  proyecto_id     uuid not null references public.proyecto(id),
  tipo            text not null default 'otro' check (tipo in
                    ('contrato','presupuesto','planos','licencia','poliza','acta','factura','informe','otro')),
  titulo          text not null,
  enlace          text not null,
  fecha           date,
  registrado_por  uuid not null references public.persona(id),
  registrado_en   timestamptz not null default now(),
  retirado_en     timestamptz,
  retirado_por    uuid references public.persona(id),
  constraint documento_titulo_escrito check (length(trim(titulo)) >= 3),
  constraint documento_enlace_web check (enlace ~ '^https://'),
  constraint documento_retiro_completo check ((retirado_en is null) = (retirado_por is null))
);
create index if not exists documento_obra_proyecto on public.documento_obra (proyecto_id) where retirado_en is null;
create index if not exists documento_obra_registrado_por on public.documento_obra (registrado_por);
create index if not exists documento_obra_retirado_por on public.documento_obra (retirado_por);
comment on table public.documento_obra is
  'O13 · Índice de los documentos de una obra que no nacen de un gasto. El archivo vive en Drive; aquí queda el enlace y quién lo puso.';

create or replace function private.validar_documento() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null then
      new.registrado_por := coalesce(private.persona_actual(), new.registrado_por);
    end if;
    new.retirado_en := null; new.retirado_por := null;
    return new;
  end if;
  -- Lo único que cambia es el retiro, y queda a nombre de quien retira.
  if (to_jsonb(new) - '{retirado_en,retirado_por}'::text[]) <> (to_jsonb(old) - '{retirado_en,retirado_por}'::text[]) then
    raise exception 'O13 · Un documento registrado no se edita: retírelo y registre el correcto';
  end if;
  if old.retirado_en is not null then
    raise exception 'O13 · Ese documento ya estaba retirado';
  end if;
  if new.retirado_en is not null and auth.uid() is not null then
    new.retirado_por := private.persona_actual();
  end if;
  return new;
end $$;

drop trigger if exists tr_documento_obra_validar on public.documento_obra;
create trigger tr_documento_obra_validar
  before insert or update on public.documento_obra
  for each row execute function private.validar_documento();
drop trigger if exists tr_documento_obra_auditar on public.documento_obra;
create trigger tr_documento_obra_auditar after insert or update or delete on public.documento_obra
  for each row execute function private.auditar();
drop trigger if exists tr_documento_obra_no_borrar on public.documento_obra;
create trigger tr_documento_obra_no_borrar before delete on public.documento_obra
  for each row execute function private.prohibir_borrado();

alter table public.documento_obra enable row level security;
drop policy if exists documento_obra_lectura on public.documento_obra;
create policy documento_obra_lectura on public.documento_obra for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));
drop policy if exists documento_obra_alta on public.documento_obra;
create policy documento_obra_alta on public.documento_obra for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and registrado_por = (select private.persona_actual()));
-- Retira dirección o quien lo registró.
drop policy if exists documento_obra_retiro on public.documento_obra;
create policy documento_obra_retiro on public.documento_obra for update to authenticated
  using (proyecto_id in (select private.proyectos_registro())
         and ((select private.es_direccion()) or registrado_por = (select private.persona_actual())))
  with check (proyecto_id in (select private.proyectos_registro()));


-- ---------- O14 · Registrar un gasto desde la obra ----------
-- El residente no sabe qué es un centro de costo: escoge la categoría y la base
-- encuentra (o abre, con presupuesto cero) el centro de esa obra. Lo demás lo
-- vigila el disparador de siempre: el umbral pide aprobación, el mes cerrado no
-- recibe nada y lo registrado no se edita. Solo abrir el centro de costo pide
-- privilegios (lo hace finanzas); el gasto entra con los permisos de quien lo
-- registra, por la política de siempre.
create or replace function private.centro_de_costo(p_proyecto uuid, p_categoria smallint) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_cc uuid;
begin
  if p_proyecto is null or p_proyecto not in (select private.proyectos_registro()) then
    raise exception 'O14 · Usted no registra gastos en esta obra' using errcode = '42501';
  end if;
  if not exists (select 1 from public.categoria_costo c where c.id = p_categoria and c.activo) then
    raise exception 'O14 · Escoja en qué categoría va el gasto';
  end if;
  insert into public.centro_costo (proyecto_id, categoria_id)
  values (p_proyecto, p_categoria)
  on conflict (proyecto_id, categoria_id) do nothing;
  select cc.id into v_cc from public.centro_costo cc where cc.proyecto_id = p_proyecto and cc.categoria_id = p_categoria;
  return v_cc;
end $$;

create or replace function public.registrar_gasto(p_datos jsonb) returns uuid
language plpgsql security invoker set search_path = '' as $$
declare
  v_yo      uuid := private.persona_actual();
  v_proy    uuid := nullif(p_datos->>'proyecto_id', '')::uuid;
  v_cat     smallint := nullif(p_datos->>'categoria_id', '')::smallint;
  v_estado  public.estado_dinero := coalesce(nullif(p_datos->>'estado', ''), 'causacion')::public.estado_dinero;
  v_medio   public.medio_pago := coalesce(nullif(p_datos->>'medio', ''), 'no_aplica')::public.medio_pago;
  v_valor   numeric := nullif(p_datos->>'valor', '')::numeric;
  v_tercero text := nullif(trim(coalesce(p_datos->>'tercero', '')), '');
  v_concepto text := nullif(trim(coalesce(p_datos->>'concepto', '')), '');
  v_cc      uuid;
  v_id      uuid;
begin
  if v_yo is null then
    raise exception 'Entre con su cuenta para registrar un gasto' using errcode = '42501';
  end if;
  if v_valor is null or v_valor <= 0 then
    raise exception 'O14 · Escriba el valor del gasto';
  end if;
  if v_tercero is null then
    raise exception 'O14 · Escriba a quién se le paga o quién factura';
  end if;
  if v_concepto is null then
    raise exception 'O14 · Escriba qué se compró o qué trabajo fue';
  end if;
  if v_estado = 'pago' and v_medio = 'no_aplica' then
    raise exception 'O14 · Si ya se pagó, diga con qué: banco, efectivo, tarjeta o crédito';
  end if;

  v_cc := private.centro_de_costo(v_proy, v_cat);

  insert into public.movimiento (proyecto_id, centro_costo_id, estado, fecha, valor, tercero_nombre, concepto,
                                 medio, numero_factura, fecha_prevista_pago, registrado_por)
  values (v_proy, v_cc, v_estado,
          coalesce(nullif(p_datos->>'fecha', '')::date, private.hoy()),
          v_valor, v_tercero, v_concepto, v_medio,
          nullif(trim(coalesce(p_datos->>'numero_factura', '')), ''),
          nullif(p_datos->>'fecha_prevista_pago', '')::date,
          v_yo)
  returning id into v_id;
  return v_id;
end $$;
comment on function public.registrar_gasto(jsonb) is
  'O14 · El gasto de una obra desde el teléfono: categoría, valor, a quién, qué, y si ya se pagó o falta. Quien registra queda como autor.';


-- ---------- O15 · Lo que la obra debe, gasta y cobra ----------

-- Lo que falta pagar, gasto por gasto (una fila por cadena compromiso →
-- causación → pago). Es la lista de facturas por pagar.
create or replace view public.v_obra_por_pagar with (security_invoker = true) as
with cadena as (
  select
    m.raiz_id,
    greatest(
      coalesce(sum(m.valor) filter (where m.naturaleza = 'cargo' and m.estado = 'compromiso'), 0),
      coalesce(sum(m.valor) filter (where m.naturaleza = 'cargo' and m.estado = 'causacion'), 0),
      coalesce(sum(m.valor) filter (where m.naturaleza = 'cargo' and m.estado = 'pago'), 0))
    - coalesce(sum(m.valor) filter (where m.naturaleza = 'devolucion'), 0)                         as total,
    coalesce(sum(m.valor) filter (where m.naturaleza = 'cargo' and m.estado = 'pago'), 0)
    - coalesce(sum(m.valor) filter (where m.naturaleza = 'devolucion' and m.estado = 'pago'), 0)   as pagado,
    max(m.fecha_prevista_pago)                                                                     as fecha_prevista,
    max(m.numero_factura)                                                                          as numero_factura,
    bool_or(m.estado = 'causacion')                                                                as facturado
  from public.v_movimiento_vigente m
  group by m.raiz_id
)
select
  r.id                                   as raiz_id,
  r.proyecto_id,
  r.centro_costo_id,
  cat.nombre                             as categoria,
  coalesce(t.nombre, r.tercero_nombre)   as tercero,
  r.concepto,
  r.fecha,
  r.aprobacion,
  c.numero_factura,
  c.facturado,
  c.total,
  c.pagado,
  c.total - c.pagado                     as por_pagar,
  coalesce(c.fecha_prevista, r.fecha + (select pa.dias_pago_estimado from public.parametro pa where pa.id)) as fecha_prevista
from cadena c
join public.movimiento r          on r.id = c.raiz_id
join public.centro_costo cc       on cc.id = r.centro_costo_id
join public.categoria_costo cat   on cat.id = cc.categoria_id
left join public.persona t        on t.id = r.tercero_id
where c.total - c.pagado > 0;

-- El flujo de cada obra por mes: lo que salió (pagos) y lo que entró (cobros).
-- Los cobros solo los ve quien ve los ingresos (dirección y finanzas).
create or replace view public.v_obra_flujo_mes with (security_invoker = true) as
with salidas as (
  select m.proyecto_id, date_trunc('month', m.fecha)::date as mes,
         sum(case when m.naturaleza = 'devolucion' then -m.valor else m.valor end) as pagado,
         count(*) filter (where m.naturaleza = 'cargo') as pagos
  from public.v_movimiento_vigente m
  where m.estado = 'pago'
  group by 1, 2
),
entradas as (
  select i.proyecto_id, date_trunc('month', i.fecha)::date as mes, sum(i.valor) as cobrado
  from public.ingreso i
  where i.proyecto_id is not null and i.anula_a is null
    and not exists (select 1 from public.ingreso x where x.anula_a = i.id)
  group by 1, 2
)
select coalesce(s.proyecto_id, e.proyecto_id) as proyecto_id,
       coalesce(s.mes, e.mes)                 as mes,
       coalesce(s.pagado, 0)                  as pagado,
       coalesce(s.pagos, 0)                   as pagos,
       coalesce(e.cobrado, 0)                 as cobrado
from salidas s
full join entradas e on e.proyecto_id = s.proyecto_id and e.mes = s.mes;

-- El tablero de obras: cada obra activa o en pausa, con su plata, sus alertas
-- y dos frases. La primera dice cómo va la plata; la segunda, lo que hay que
-- mover primero (o nada).
create or replace view public.v_obra_tablero with (security_invoker = true) as
with balance as (
  select vb.proyecto_id, sum(vb.proyectado) as proyectado, sum(vb.pagado) as pagado, sum(vb.por_pagar) as por_pagar
  from public.v_balance_centro_costo vb
  where not vb.excluir_de_rentabilidad
  group by vb.proyecto_id
),
obra as (
  select
    p.id, p.codigo, p.nombre, p.estado, p.unidad, p.carpeta_drive, p.valor_contrato,
    p.fecha_inicio, p.fecha_fin_prevista, p.residente_id,
    res.nombre                                                       as residente,
    coalesce(b.proyectado, 0)                                        as costo_proyectado,
    coalesce(b.pagado, 0)                                            as pagado,
    coalesce(b.por_pagar, 0)                                         as por_pagar,
    (select coalesce(sum(i.valor), 0) from public.ingreso i
      where i.proyecto_id = p.id and i.anula_a is null
        and not exists (select 1 from public.ingreso x where x.anula_a = i.id)) as cobrado,
    (select count(*) from public.v_movimiento_vigente m
      where m.proyecto_id = p.id and m.aprobacion = 'pendiente')     as gastos_por_aprobar,
    (select coalesce(sum(m.valor), 0) from public.v_movimiento_vigente m
      where m.proyecto_id = p.id and m.aprobacion = 'pendiente')     as valor_por_aprobar,
    (select count(*) from public.pendiente_obra po
      where po.proyecto_id = p.id and po.estado not in ('cerrado','descartado')) as pendientes_abiertos,
    (select count(*) from public.pendiente_obra po
      where po.proyecto_id = p.id and po.estado not in ('cerrado','descartado')
        and po.fecha_compromiso < private.hoy())                     as pendientes_vencidos,
    (select count(*) from public.pendiente_obra po
      where po.proyecto_id = p.id and po.estado = 'por_verificar')   as pendientes_por_verificar,
    (select count(*) from public.v_bitacora_faltante bf where bf.proyecto_id = p.id) as dias_sin_bitacora,
    (select max(bi.fecha) from public.bitacora bi where bi.proyecto_id = p.id)       as ultima_bitacora,
    (select count(*) from public.adicional a
      where a.proyecto_id = p.id and a.aprobacion = 'pendiente')     as adicionales_pendientes,
    (select max(m.fecha) from public.v_movimiento_vigente m where m.proyecto_id = p.id) as ultimo_gasto,
    (select count(*) from public.documento_obra d
      where d.proyecto_id = p.id and d.retirado_en is null)          as documentos
  from public.proyecto p
  left join public.persona res on res.id = p.residente_id
  left join balance b on b.proyecto_id = p.id
  where p.tipo = 'obra' and p.estado in ('activo','pausado')
)
select
  o.*,
  case when o.valor_contrato > 0 then round(o.costo_proyectado / o.valor_contrato * 100) end as pct_contrato,
  case
    when o.valor_contrato > 0 then
      'Lleva ' || private.pesos(o.costo_proyectado) || ' de ' || private.pesos(o.valor_contrato) || ' del contrato ('
      || round(o.costo_proyectado / o.valor_contrato * 100) || ' %)'
      || case when o.por_pagar > 0 then ' y debe ' || private.pesos(o.por_pagar) || '.' else ', sin nada por pagar.' end
    when o.costo_proyectado > 0 then
      'Lleva ' || private.pesos(o.costo_proyectado) || ' en gastos'
      || case when o.por_pagar > 0 then ' y debe ' || private.pesos(o.por_pagar) else '' end
      || '. Falta escribir el valor del contrato.'
    else 'Todavía no tiene gastos registrados.'
  end as lectura,
  case
    when o.gastos_por_aprobar > 0 then
      case when o.gastos_por_aprobar = 1 then 'Un gasto de ' || private.pesos(o.valor_por_aprobar) || ' espera'
           else o.gastos_por_aprobar || ' gastos por ' || private.pesos(o.valor_por_aprobar) || ' esperan' end
      || ' la aprobación de dirección.'
    when o.pendientes_vencidos > 0 then
      case when o.pendientes_vencidos = 1 then 'Un pendiente pasó su fecha y sigue abierto.'
           else o.pendientes_vencidos || ' pendientes pasaron su fecha y siguen abiertos.' end
    when o.estado = 'activo' and o.dias_sin_bitacora >= 3 then
      'Lleva ' || o.dias_sin_bitacora || ' días de obra sin bitácora en el último mes.'
    when o.pendientes_por_verificar > 0 then
      case when o.pendientes_por_verificar = 1 then 'Un pendiente está hecho y espera que alguien lo verifique.'
           else o.pendientes_por_verificar || ' pendientes están hechos y esperan que alguien los verifique.' end
    when o.adicionales_pendientes > 0 then
      case when o.adicionales_pendientes = 1 then 'Un adicional espera la decisión del cliente.'
           else o.adicionales_pendientes || ' adicionales esperan la decisión del cliente.' end
    when o.valor_contrato > 0 and o.costo_proyectado > o.valor_contrato then
      'El costo ya pasó el valor del contrato.'
  end as alerta
from obra o;


-- ---------- La sesión dice quién ve obras ----------
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
                                 and (o.responsable_id = p.id or o.siguiente_paso_por = p.id)),
    -- O15 · Ve obras dirección, finanzas y residencia, y quien tenga acceso a una.
    'obras',        (select private.tiene_rol('{socio,director,financiero,residente}'::public.rol_persona[]))
                    or exists (select 1 from public.proyecto pr
                               where pr.tipo = 'obra' and pr.id in (select private.proyectos_visibles())),
    've_dinero',    (select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])))
  from public.persona p
  where p.id = (select private.persona_actual())
$$;


-- ---------- Permisos ----------
revoke all on public.documento_obra from anon, authenticated;
grant select, insert, update on public.documento_obra to authenticated;
revoke all on public.v_obra_tablero, public.v_obra_por_pagar, public.v_obra_flujo_mes from anon, authenticated;
grant select on public.v_obra_tablero, public.v_obra_por_pagar, public.v_obra_flujo_mes to authenticated;
revoke all on all functions in schema public  from public, anon;
revoke all on all functions in schema private from public, anon;
revoke all on function private.validar_documento() from authenticated;
grant execute on function public.registrar_gasto(jsonb), public.mi_sesion(), private.centro_de_costo(uuid, smallint) to authenticated;
grant select, insert, update, delete on all tables in schema public to service_role;
grant execute on all functions in schema public to service_role;
grant execute on all functions in schema private to service_role;


-- >>>>>>>>>>>>>>>>>>>> 20261020120000_prestamos_y_socios.sql >>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- SICI · Préstamos y socios: se cargan, pero solo los ven Felipe y Luisa · F7
--
-- Decisión de Felipe (2026-10-18): «carga los préstamos y socios pero deja eso
-- como solo visualización de Luisa y Felipe». Son plata que pasa por la caja y
-- no es costo de ningún cliente: préstamos dados y recibidos, sus devoluciones,
-- créditos, y la cuenta de los socios (gastos personales que paga la empresa).
--
-- Quién ve:
--   · un socio, siempre;
--   · quien tenga en su ficha «ve préstamos y socios» (Luisa). Ese permiso solo
--     lo da o lo quita un socio.
-- Nadie más: ni finanzas, ni dirección sin el permiso, ni el residente. Para
-- ellos esos movimientos, sus centros de costo, sus categorías, el proyecto de
-- los socios y los créditos bancarios no existen.
--
-- Qué se marca: la categoría (categoria_costo.reservada) y el proyecto de los
-- socios (proyecto.reservado). La marca de cada nombre la pone la clasificación
-- (semilla 030), porque las categorías llegan con el histórico, después de las
-- migraciones.
-- =============================================================================

alter table public.categoria_costo add column if not exists reservada boolean not null default false;
comment on column public.categoria_costo.reservada is
  'F7 · Préstamos, créditos y la cuenta de los socios: solo los ven los socios y quien tenga ve_reservado.';
alter table public.proyecto add column if not exists reservado boolean not null default false;
comment on column public.proyecto.reservado is
  'F7 · El proyecto entero es reservado (la cuenta SOCIOS del libro mayor).';
alter table public.persona add column if not exists ve_reservado boolean not null default false;
comment on column public.persona.ve_reservado is
  'F7 · Ve préstamos y socios sin ser socio. Lo da o lo quita un socio (Felipe se lo dio a Luisa).';

-- ¿La persona de la sesión ve lo reservado?
create or replace function private.ve_reservado() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.tiene_rol('{socio}'::public.rol_persona[])
      or exists (select 1 from public.persona p
                 where p.auth_user_id = auth.uid() and p.activo and p.es_interno and p.ve_reservado)
$$;

-- Los centros de costo reservados: los de una categoría reservada o de un
-- proyecto reservado.
create or replace function private.centros_reservados() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select cc.id from public.centro_costo cc
  join public.categoria_costo c on c.id = cc.categoria_id
  join public.proyecto p        on p.id = cc.proyecto_id
  where c.reservada or p.reservado
$$;

-- El permiso lo da o lo quita un socio. Las cargas del sistema no se frenan.
create or replace function private.validar_ve_reservado() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.ve_reservado is distinct from (case when tg_op = 'UPDATE' then old.ve_reservado else false end)
     and auth.uid() is not null and not private.tiene_rol('{socio}'::public.rol_persona[]) then
    raise exception 'F7 · Ver préstamos y socios lo autoriza un socio';
  end if;
  return new;
end $$;
drop trigger if exists tr_persona_ve_reservado on public.persona;
create trigger tr_persona_ve_reservado
  before insert or update of ve_reservado on public.persona
  for each row execute function private.validar_ve_reservado();

-- Lo mismo para la marca de reservado: no la quita cualquiera de finanzas.
create or replace function private.validar_reserva() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and new.reservada is distinct from old.reservada
     and auth.uid() is not null and not private.tiene_rol('{socio}'::public.rol_persona[]) then
    raise exception 'F7 · Qué categoría es reservada lo decide un socio';
  end if;
  return new;
end $$;
drop trigger if exists tr_categoria_costo_reserva on public.categoria_costo;
create trigger tr_categoria_costo_reserva
  before update of reservada on public.categoria_costo
  for each row execute function private.validar_reserva();

create or replace function private.validar_proyecto_reservado() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.reservado is distinct from (case when tg_op = 'UPDATE' then old.reservado else false end)
     and auth.uid() is not null and not private.tiene_rol('{socio}'::public.rol_persona[]) then
    raise exception 'F7 · Qué proyecto es reservado lo decide un socio';
  end if;
  return new;
end $$;
drop trigger if exists tr_proyecto_reservado on public.proyecto;
create trigger tr_proyecto_reservado
  before insert or update of reservado on public.proyecto
  for each row execute function private.validar_proyecto_reservado();


-- ---------- Políticas: lo reservado desaparece para quien no lo ve ----------
drop policy if exists categoria_costo_lectura on public.categoria_costo;
create policy categoria_costo_lectura on public.categoria_costo for select to authenticated
  using ((select private.es_interno()) and (not reservada or (select private.ve_reservado())));

drop policy if exists proyecto_lectura on public.proyecto;
create policy proyecto_lectura on public.proyecto for select to authenticated
  using ((id in (select private.proyectos_visibles()) or id in (select private.proyectos_portal()))
         and (not reservado or (select private.ve_reservado())));

drop policy if exists centro_costo_lectura on public.centro_costo;
create policy centro_costo_lectura on public.centro_costo for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles())
         and ((select private.ve_reservado()) or id not in (select private.centros_reservados())));

drop policy if exists movimiento_lectura on public.movimiento;
create policy movimiento_lectura on public.movimiento for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles())
         and ((select private.ve_reservado()) or centro_costo_id not in (select private.centros_reservados())));

-- Los créditos bancarios que entran a la caja también son préstamos.
drop policy if exists ingreso_lectura on public.ingreso;
create policy ingreso_lectura on public.ingreso for select to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[]))
         and (linea <> 'credito_bancario' or (select private.ve_reservado())));

-- Desde la obra no se registra un préstamo: es «solo visualización».
create or replace function private.centro_de_costo(p_proyecto uuid, p_categoria smallint) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_cc uuid;
begin
  if p_proyecto is null or p_proyecto not in (select private.proyectos_registro()) then
    raise exception 'O14 · Usted no registra gastos en esta obra' using errcode = '42501';
  end if;
  if not exists (select 1 from public.categoria_costo c where c.id = p_categoria and c.activo) then
    raise exception 'O14 · Escoja en qué categoría va el gasto';
  end if;
  if exists (select 1 from public.categoria_costo c where c.id = p_categoria and c.reservada)
     or exists (select 1 from public.proyecto p where p.id = p_proyecto and p.reservado) then
    raise exception 'F7 · Los préstamos y la cuenta de los socios no se registran desde la obra';
  end if;
  insert into public.centro_costo (proyecto_id, categoria_id)
  values (p_proyecto, p_categoria)
  on conflict (proyecto_id, categoria_id) do nothing;
  select cc.id into v_cc from public.centro_costo cc where cc.proyecto_id = p_proyecto and cc.categoria_id = p_categoria;
  return v_cc;
end $$;

-- La sesión dice si ve lo reservado (la pantalla de personas muestra el permiso).
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
                                 and (o.responsable_id = p.id or o.siguiente_paso_por = p.id)),
    'obras',        (select private.tiene_rol('{socio,director,financiero,residente}'::public.rol_persona[]))
                    or exists (select 1 from public.proyecto pr
                               where pr.tipo = 'obra' and pr.id in (select private.proyectos_visibles())),
    've_dinero',    (select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])),
    've_reservado', (select private.ve_reservado()),
    'es_socio',     (select private.tiene_rol('{socio}'::public.rol_persona[])))
  from public.persona p
  where p.id = (select private.persona_actual())
$$;


-- ---------- Permisos ----------
revoke all on all functions in schema public  from public, anon;
revoke all on all functions in schema private from public, anon;
revoke all on function private.validar_ve_reservado(), private.validar_reserva(), private.validar_proyecto_reservado() from authenticated;
grant execute on function private.ve_reservado(), private.centros_reservados(), public.mi_sesion(),
  private.centro_de_costo(uuid, smallint) to authenticated;
grant select, insert, update, delete on all tables in schema public to service_role;
grant execute on all functions in schema public to service_role;
grant execute on all functions in schema private to service_role;


-- >>>>>>>>>>>>>>>>>>>> 20261021120000_adicional_retirado.sql >>>>>>>>>>>>>>>>>>>>

-- =============================================================================
-- SICI · Un adicional que ESA retira no se borra: queda retirado, con la razón · O1
--
-- El balance de Nirvana del 9 de octubre de 2026 reformuló los 70 adicionales
-- «AD-» que se le habían presentado al cliente en agosto: ahora son 88
-- modificaciones «MOD-» dentro de cada capítulo, con otros códigos y precios.
-- Ninguno de los 70 lo decidió el cliente, así que no son ni aprobados ni
-- rechazados: ESA los retiró. Borrarlos está prohibido (son constancia de lo
-- que se le propuso al cliente), y dejarlos pendientes los sumaría dos veces.
--
-- Reglas:
--   · Solo se retira un adicional pendiente; uno con decisión del cliente se queda.
--   · Lo retira dirección, con la razón por escrito.
--   · Retirado no se modifica ni se vuelve a abrir, ni el cliente lo decide:
--     si vuelve, es un adicional nuevo.
--   · Lo retirado no cuenta: ni en los adicionales netos ni en los pendientes
--     del tablero de obras.
-- =============================================================================

alter table public.adicional
  add column if not exists retirado_en     timestamptz,
  add column if not exists retirado_por    uuid references public.persona(id),
  add column if not exists retirado_motivo text;
create index if not exists adicional_retirado_por on public.adicional (retirado_por);
comment on column public.adicional.retirado_en is
  'O1 · ESA lo retiró antes de que el cliente decidiera (lo reformuló, lo absorbió o ya no aplica). No se borra.';

alter table public.adicional drop constraint if exists adicional_retiro_completo;
alter table public.adicional add constraint adicional_retiro_completo check (
  retirado_en is null
  or (aprobacion = 'pendiente' and length(trim(coalesce(retirado_motivo, ''))) > 0));

-- O1 y O9 · Coherencia del adicional y de la decisión del cliente, ahora con el retiro.
create or replace function private.validar_adicional() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_portal boolean;
begin
  if tg_op = 'UPDATE' and old.retirado_en is not null then
    raise exception 'O1 · Un adicional retirado no se modifica ni se decide: si vuelve, registre uno nuevo';
  end if;
  if new.retirado_en is not null and (tg_op = 'INSERT' or old.retirado_en is null) then
    if new.aprobacion <> 'pendiente' then
      raise exception 'O1 · Solo se retira un adicional que el cliente no ha decidido';
    end if;
    if auth.uid() is not null and not private.es_direccion() then
      raise exception 'O1 · Solo dirección retira un adicional';
    end if;
    if length(trim(coalesce(new.retirado_motivo, ''))) = 0 then
      raise exception 'O1 · Escriba por qué se retira el adicional';
    end if;
    new.retirado_por := coalesce(new.retirado_por, private.persona_actual());
  end if;

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

-- O2 y O9 · Adicionales netos, sin los retirados.
create or replace view public.v_adicionales_netos with (security_invoker = true) as
with reemplazados as (
  select distinct a.proyecto_id, a.reemplaza_item_id as item_id
  from public.adicional a
  where a.reemplaza_item_id is not null and a.aprobacion <> 'rechazado' and a.retirado_en is null
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
where a.retirado_en is null
group by a.proyecto_id, p.codigo;

-- El tablero de obras: los adicionales que esperan al cliente, sin los retirados.
create or replace view public.v_obra_tablero with (security_invoker = true) as
with balance as (
  select vb.proyecto_id, sum(vb.proyectado) as proyectado, sum(vb.pagado) as pagado, sum(vb.por_pagar) as por_pagar
  from public.v_balance_centro_costo vb
  where not vb.excluir_de_rentabilidad
  group by vb.proyecto_id
),
obra as (
  select
    p.id, p.codigo, p.nombre, p.estado, p.unidad, p.carpeta_drive, p.valor_contrato,
    p.fecha_inicio, p.fecha_fin_prevista, p.residente_id,
    res.nombre                                                       as residente,
    coalesce(b.proyectado, 0)                                        as costo_proyectado,
    coalesce(b.pagado, 0)                                            as pagado,
    coalesce(b.por_pagar, 0)                                         as por_pagar,
    (select coalesce(sum(i.valor), 0) from public.ingreso i
      where i.proyecto_id = p.id and i.anula_a is null
        and not exists (select 1 from public.ingreso x where x.anula_a = i.id)) as cobrado,
    (select count(*) from public.v_movimiento_vigente m
      where m.proyecto_id = p.id and m.aprobacion = 'pendiente')     as gastos_por_aprobar,
    (select coalesce(sum(m.valor), 0) from public.v_movimiento_vigente m
      where m.proyecto_id = p.id and m.aprobacion = 'pendiente')     as valor_por_aprobar,
    (select count(*) from public.pendiente_obra po
      where po.proyecto_id = p.id and po.estado not in ('cerrado','descartado')) as pendientes_abiertos,
    (select count(*) from public.pendiente_obra po
      where po.proyecto_id = p.id and po.estado not in ('cerrado','descartado')
        and po.fecha_compromiso < private.hoy())                     as pendientes_vencidos,
    (select count(*) from public.pendiente_obra po
      where po.proyecto_id = p.id and po.estado = 'por_verificar')   as pendientes_por_verificar,
    (select count(*) from public.v_bitacora_faltante bf where bf.proyecto_id = p.id) as dias_sin_bitacora,
    (select max(bi.fecha) from public.bitacora bi where bi.proyecto_id = p.id)       as ultima_bitacora,
    (select count(*) from public.adicional a
      where a.proyecto_id = p.id and a.aprobacion = 'pendiente' and a.retirado_en is null) as adicionales_pendientes,
    (select max(m.fecha) from public.v_movimiento_vigente m where m.proyecto_id = p.id) as ultimo_gasto,
    (select count(*) from public.documento_obra d
      where d.proyecto_id = p.id and d.retirado_en is null)          as documentos
  from public.proyecto p
  left join public.persona res on res.id = p.residente_id
  left join balance b on b.proyecto_id = p.id
  where p.tipo = 'obra' and p.estado in ('activo','pausado')
)
select
  o.*,
  case when o.valor_contrato > 0 then round(o.costo_proyectado / o.valor_contrato * 100) end as pct_contrato,
  case
    when o.valor_contrato > 0 then
      'Lleva ' || private.pesos(o.costo_proyectado) || ' de ' || private.pesos(o.valor_contrato) || ' del contrato ('
      || round(o.costo_proyectado / o.valor_contrato * 100) || ' %)'
      || case when o.por_pagar > 0 then ' y debe ' || private.pesos(o.por_pagar) || '.' else ', sin nada por pagar.' end
    when o.costo_proyectado > 0 then
      'Lleva ' || private.pesos(o.costo_proyectado) || ' en gastos'
      || case when o.por_pagar > 0 then ' y debe ' || private.pesos(o.por_pagar) else '' end
      || '. Falta escribir el valor del contrato.'
    else 'Todavía no tiene gastos registrados.'
  end as lectura,
  case
    when o.gastos_por_aprobar > 0 then
      case when o.gastos_por_aprobar = 1 then 'Un gasto de ' || private.pesos(o.valor_por_aprobar) || ' espera'
           else o.gastos_por_aprobar || ' gastos por ' || private.pesos(o.valor_por_aprobar) || ' esperan' end
      || ' la aprobación de dirección.'
    when o.pendientes_vencidos > 0 then
      case when o.pendientes_vencidos = 1 then 'Un pendiente pasó su fecha y sigue abierto.'
           else o.pendientes_vencidos || ' pendientes pasaron su fecha y siguen abiertos.' end
    when o.estado = 'activo' and o.dias_sin_bitacora >= 3 then
      'Lleva ' || o.dias_sin_bitacora || ' días de obra sin bitácora en el último mes.'
    when o.pendientes_por_verificar > 0 then
      case when o.pendientes_por_verificar = 1 then 'Un pendiente está hecho y espera que alguien lo verifique.'
           else o.pendientes_por_verificar || ' pendientes están hechos y esperan que alguien los verifique.' end
    when o.adicionales_pendientes > 0 then
      case when o.adicionales_pendientes = 1 then 'Un adicional espera la decisión del cliente.'
           else o.adicionales_pendientes || ' adicionales esperan la decisión del cliente.' end
    when o.valor_contrato > 0 and o.costo_proyectado > o.valor_contrato then
      'El costo ya pasó el valor del contrato.'
  end as alerta
from obra o;

revoke all on public.v_adicionales_netos, public.v_obra_tablero from anon, authenticated;
grant select on public.v_adicionales_netos, public.v_obra_tablero to authenticated;
revoke all on all functions in schema public  from public, anon;
revoke all on all functions in schema private from public, anon;
grant select, insert, update, delete on all tables in schema public to service_role;
grant execute on all functions in schema public to service_role;


-- >>>>>>>>>>>>>>>>>>>> 20261022120000_revision_y_papeles.sql >>>>>>>>>>>>>>>>>>>>

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
