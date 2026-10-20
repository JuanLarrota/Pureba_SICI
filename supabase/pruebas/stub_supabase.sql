-- =============================================================================
-- SOLO PARA PRUEBAS LOCALES. NUNCA EJECUTAR EN SUPABASE.
--
-- Supabase ya trae los esquemas "auth" y "storage", las funciones auth.uid()
-- y auth.jwt(), la tabla auth.users, storage.foldername() y los roles anon,
-- authenticated y service_role. Este archivo imita esas piezas en un Postgres
-- vacío para probar las migraciones y los permisos fuera de Supabase.
-- Imita lo mínimo que usa el SICI; no es una copia de Supabase.
-- =============================================================================

-- ---------- Roles ----------
do $$ begin create role anon nologin noinherit;
exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin noinherit;
exception when duplicate_object then null; end $$;
do $$ begin create role service_role nologin noinherit bypassrls;
exception when duplicate_object then null; end $$;
do $$ begin create role supabase_auth_admin nologin noinherit;
exception when duplicate_object then null; end $$;

grant usage on schema public to anon, authenticated, service_role;

-- ---------- auth ----------
create schema if not exists auth;

create table if not exists auth.users (
  id                  uuid primary key default gen_random_uuid(),
  email               text,
  email_confirmed_at  timestamptz,
  created_at          timestamptz not null default now()
);

-- Igual que en Supabase: el usuario sale del token de la sesión.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

create or replace function auth.jwt() returns jsonb
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')
  )::jsonb
$$;

grant usage on schema auth to anon, authenticated, service_role, supabase_auth_admin;
grant execute on function auth.uid(), auth.jwt() to anon, authenticated, service_role;
grant select, insert, update on auth.users to supabase_auth_admin;

-- ---------- storage ----------
create schema if not exists storage;

create table if not exists storage.buckets (
  id                  text primary key,
  name                text not null unique,
  owner               uuid,
  public              boolean default false,
  file_size_limit     bigint,
  allowed_mime_types  text[],
  created_at          timestamptz default now(),
  updated_at          timestamptz default now()
);

create table if not exists storage.objects (
  id          uuid primary key default gen_random_uuid(),
  bucket_id   text references storage.buckets(id),
  name        text,
  owner       uuid,
  owner_id    text,
  metadata    jsonb,
  created_at  timestamptz default now(),
  updated_at  timestamptz default now(),
  unique (bucket_id, name)
);
alter table storage.objects enable row level security;

-- La misma definición que usa Supabase: las carpetas de la ruta, sin el archivo.
create or replace function storage.foldername(name text) returns text[]
language plpgsql immutable as $$
declare _parts text[];
begin
  select string_to_array(name, '/') into _parts;
  return _parts[1:array_length(_parts, 1) - 1];
end $$;

grant usage on schema storage to anon, authenticated, service_role;
grant select, insert, update, delete on storage.objects to authenticated, service_role;
grant select on storage.buckets to anon, authenticated, service_role;
grant execute on function storage.foldername(text) to anon, authenticated, service_role;
