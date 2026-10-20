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
