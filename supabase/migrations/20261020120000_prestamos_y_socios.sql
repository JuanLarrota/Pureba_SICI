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
