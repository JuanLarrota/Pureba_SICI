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
