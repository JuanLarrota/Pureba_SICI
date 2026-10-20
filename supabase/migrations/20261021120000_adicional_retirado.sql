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
