-- =============================================================================
-- SICI · Políticas de acceso por fila · M-04 Diseño y producción arquitectónica
--
-- La fase la abre y la cierra dirección (Luisa). Las tareas las asigna quien
-- dirige el proyecto y las mueve quien las hace. La dedicación es de cada
-- quien: nadie registra horas a nombre de otro, y cada persona ve solo las
-- suyas salvo dirección y finanzas (que las necesita para repartir la
-- estructura).
-- =============================================================================

-- ---------- proyecto_fase · el cliente ve en qué fase va su proyecto ----------
drop policy if exists proyecto_fase_lectura on public.proyecto_fase;
create policy proyecto_fase_lectura on public.proyecto_fase for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles())
         or proyecto_id in (select private.proyectos_portal()));

drop policy if exists proyecto_fase_alta on public.proyecto_fase;
create policy proyecto_fase_alta on public.proyecto_fase for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists proyecto_fase_edicion on public.proyecto_fase;
create policy proyecto_fase_edicion on public.proyecto_fase for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- elemento_diseno · la nomenclatura M-05, M-06... ----------
drop policy if exists elemento_diseno_lectura on public.elemento_diseno;
create policy elemento_diseno_lectura on public.elemento_diseno for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));

drop policy if exists elemento_diseno_alta on public.elemento_diseno;
create policy elemento_diseno_alta on public.elemento_diseno for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,arquitecto,practicante}'::public.rol_persona[])));

drop policy if exists elemento_diseno_edicion on public.elemento_diseno;
create policy elemento_diseno_edicion on public.elemento_diseno for update to authenticated
  using (proyecto_id in (select private.proyectos_registro())
         and (select private.tiene_rol('{socio,director,arquitecto,practicante}'::public.rol_persona[])))
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,arquitecto,practicante}'::public.rol_persona[])));

-- ---------- tarea_diseno ----------
drop policy if exists tarea_diseno_lectura on public.tarea_diseno;
create policy tarea_diseno_lectura on public.tarea_diseno for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));

drop policy if exists tarea_diseno_alta on public.tarea_diseno;
create policy tarea_diseno_alta on public.tarea_diseno for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

drop policy if exists tarea_diseno_edicion on public.tarea_diseno;
create policy tarea_diseno_edicion on public.tarea_diseno for update to authenticated
  using (proyecto_id in (select private.proyectos_registro())
         and ((select private.es_direccion())
              or asignada_a = (select private.persona_actual())
              or asignada_por = (select private.persona_actual())))
  with check (proyecto_id in (select private.proyectos_registro())
              and ((select private.es_direccion())
                   or asignada_a = (select private.persona_actual())
                   or asignada_por = (select private.persona_actual())));

-- ---------- revision_diseno · la revisión la registra quien revisa ----------
drop policy if exists revision_diseno_lectura on public.revision_diseno;
create policy revision_diseno_lectura on public.revision_diseno for select to authenticated
  using (exists (select 1 from public.tarea_diseno t where t.id = revision_diseno.tarea_id));

drop policy if exists revision_diseno_alta on public.revision_diseno;
create policy revision_diseno_alta on public.revision_diseno for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[]))
              and exists (select 1 from public.tarea_diseno t
                          where t.id = revision_diseno.tarea_id
                            and t.proyecto_id in (select private.proyectos_registro())));

-- ---------- dedicacion · cada quien la suya ----------
drop policy if exists dedicacion_lectura on public.dedicacion;
create policy dedicacion_lectura on public.dedicacion for select to authenticated
  using (persona_id = (select private.persona_actual())
         or (select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists dedicacion_alta on public.dedicacion;
create policy dedicacion_alta on public.dedicacion for insert to authenticated
  with check ((select private.es_interno())
              and persona_id = (select private.persona_actual())
              and (proyecto_id is null or proyecto_id in (select private.proyectos_visibles())));

drop policy if exists dedicacion_edicion on public.dedicacion;
create policy dedicacion_edicion on public.dedicacion for update to authenticated
  using (persona_id = (select private.persona_actual()) or (select private.es_direccion()))
  with check ((persona_id = (select private.persona_actual()) or (select private.es_direccion()))
              and (proyecto_id is null or proyecto_id in (select private.proyectos_visibles())));

-- ---------- entregable · el cliente ve lo que se le entregó ----------
drop policy if exists entregable_lectura on public.entregable;
create policy entregable_lectura on public.entregable for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles())
         or proyecto_id in (select private.proyectos_portal()));

drop policy if exists entregable_alta on public.entregable;
create policy entregable_alta on public.entregable for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,arquitecto,practicante}'::public.rol_persona[])));

drop policy if exists entregable_edicion on public.entregable;
create policy entregable_edicion on public.entregable for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- entregable_archivo ----------
drop policy if exists entregable_archivo_lectura on public.entregable_archivo;
create policy entregable_archivo_lectura on public.entregable_archivo for select to authenticated
  using (exists (select 1 from public.entregable e where e.id = entregable_archivo.entregable_id));

drop policy if exists entregable_archivo_alta on public.entregable_archivo;
create policy entregable_archivo_alta on public.entregable_archivo for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,arquitecto,practicante}'::public.rol_persona[]))
              and exists (select 1 from public.entregable e
                          where e.id = entregable_archivo.entregable_id
                            and e.proyecto_id in (select private.proyectos_registro())));

-- ---------- complementario ----------
drop policy if exists complementario_lectura on public.complementario;
create policy complementario_lectura on public.complementario for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));

drop policy if exists complementario_alta on public.complementario;
create policy complementario_alta on public.complementario for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists complementario_edicion on public.complementario;
create policy complementario_edicion on public.complementario for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- radicacion_licencia ----------
drop policy if exists radicacion_licencia_lectura on public.radicacion_licencia;
create policy radicacion_licencia_lectura on public.radicacion_licencia for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));

drop policy if exists radicacion_licencia_alta on public.radicacion_licencia;
create policy radicacion_licencia_alta on public.radicacion_licencia for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

drop policy if exists radicacion_licencia_edicion on public.radicacion_licencia;
create policy radicacion_licencia_edicion on public.radicacion_licencia for update to authenticated
  using (proyecto_id in (select private.proyectos_registro())
         and (select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])))
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));
