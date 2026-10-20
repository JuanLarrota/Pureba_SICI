with h(seccion, clave, valor) as (
  select 'columna', c.table_schema || '.' || c.table_name || '.' || c.column_name,
         concat_ws('|', c.udt_name, c.is_nullable, c.column_default, c.numeric_precision, c.numeric_scale)
  from information_schema.columns c where c.table_schema in ('public','private')
  union all
  select 'restriccion', n.nspname || '.' || r.relname || '.' || k.conname, pg_get_constraintdef(k.oid)
  from pg_constraint k join pg_class r on r.oid = k.conrelid join pg_namespace n on n.oid = r.relnamespace
  where n.nspname in ('public','private')
  union all
  select 'indice', schemaname || '.' || indexname, indexdef from pg_indexes where schemaname in ('public','private')
  union all
  select 'vista', n.nspname || '.' || c.relname,
         md5(pg_get_viewdef(c.oid, true)) || '|' || coalesce(array_to_string(c.reloptions, ','), '')
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where c.relkind = 'v' and n.nspname in ('public','private')
  union all
  select 'funcion', n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
         concat_ws('|', md5(p.prosrc), p.prosecdef::text, p.provolatile::text,
                   coalesce(array_to_string(p.proconfig, ','), ''), pg_get_function_result(p.oid), l.lanname)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace join pg_language l on l.oid = p.prolang
  where n.nspname in ('public','private') and p.proname <> 'rls_auto_enable'
  union all
  select 'permiso_funcion', n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
         (select coalesce(string_agg(r.rolname, ',' order by r.rolname), '')
            from pg_roles r where r.rolname in ('anon','authenticated','service_role')
             and has_function_privilege(r.oid, p.oid, 'execute'))
         || '|publico=' || coalesce((select bool_or(a.grantee = 0) from aclexplode(p.proacl) a), true)::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public','private') and p.proname <> 'rls_auto_enable'
  union all
  select 'disparador', n.nspname || '.' || c.relname || '.' || t.tgname, pg_get_triggerdef(t.oid)
  from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
  where not t.tgisinternal and (n.nspname in ('public','private') or t.tgname like 'sici%')
  union all
  select 'politica', schemaname || '.' || tablename || '.' || policyname,
         concat_ws('|', cmd, array_to_string(roles, ','), permissive, md5(coalesce(qual, '')), md5(coalesce(with_check, '')))
  from pg_policies where schemaname = 'public' or policyname like 'sici%'
  union all
  select 'rls', n.nspname || '.' || c.relname, c.relrowsecurity::text || '|' || c.relforcerowsecurity::text
  from pg_class c join pg_namespace n on n.oid = c.relnamespace where c.relkind = 'r' and n.nspname in ('public','private')
  union all
  select 'tipo', t.typname, (select string_agg(e.enumlabel, ',' order by e.enumsortorder) from pg_enum e where e.enumtypid = t.oid)
  from pg_type t join pg_namespace n on n.oid = t.typnamespace where n.nspname = 'public' and t.typtype = 'e'
  union all
  select 'permiso_tabla', table_schema || '.' || table_name || '.' || grantee, string_agg(privilege_type, ',' order by privilege_type)
  from information_schema.role_table_grants
  where table_schema in ('public','private') and grantee in ('anon','authenticated','service_role','PUBLIC')
  group by 1, 2
  union all
  select 'comentario', c.oid::regclass::text, d.description
  from pg_description d join pg_class c on c.oid = d.objoid and d.classoid = 'pg_class'::regclass
  join pg_namespace n on n.oid = c.relnamespace where n.nspname in ('public','private') and d.objsubid = 0
  union all
  select 'comentario_funcion', p.oid::regprocedure::text, d.description
  from pg_description d join pg_proc p on p.oid = d.objoid and d.classoid = 'pg_proc'::regclass
  join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public','private')
  union all
  select 'regla_alerta', r.tipo, md5(row(r.*)::text) from public.regla_alerta r
  union all
  select 'parametro', 'filas', count(*)::text from public.parametro
  union all
  select 'deposito', b.id, concat_ws('|', b.public::text, b.file_size_limit::text) from storage.buckets b
  union all
  select 'esquema_private', n.nspname,
         has_schema_privilege('anon', n.oid, 'usage')::text || '|' || has_schema_privilege('authenticated', n.oid, 'usage')::text
  from pg_namespace n where n.nspname = 'private'
)
select seccion, count(*)::int as filas, md5(string_agg(clave || '=' || coalesce(valor, ''), E'\n' order by clave)) as huella
from h group by 1 order by 1;
