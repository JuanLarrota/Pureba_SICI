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
