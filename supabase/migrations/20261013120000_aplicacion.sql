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
