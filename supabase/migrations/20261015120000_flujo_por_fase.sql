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
