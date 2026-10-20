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
