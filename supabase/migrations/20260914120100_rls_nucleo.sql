-- =============================================================================
-- SICI · Políticas de acceso por fila · M-00 Núcleo y alertas
--
-- Cómo leer estas políticas:
--   · Una política por tabla y por operación (lectura, alta, edición, retiro).
--     Así lo pide el asesor de Supabase y así se entiende quién hace qué.
--   · Todas aplican solo a "authenticated": sin sesión no se ve nada.
--   · Las funciones de identidad van entre paréntesis con select: Postgres
--     las calcula una vez por consulta y no una vez por fila.
--   · Nadie borra: salvo retirar un acceso, no existe política de retiro.
--
-- Idempotente: cada política se borra antes de crearse.
-- =============================================================================

-- ---------- parametro · el umbral y los márgenes solo los cambia un socio ----------
drop policy if exists parametro_lectura on public.parametro;
create policy parametro_lectura on public.parametro for select to authenticated
  using ((select private.es_interno()));

drop policy if exists parametro_edicion on public.parametro;
create policy parametro_edicion on public.parametro for update to authenticated
  using ((select private.tiene_rol('{socio}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio}'::public.rol_persona[])));

-- ---------- persona · el equipo ve el directorio; un externo, solo su ficha ----------
drop policy if exists persona_lectura on public.persona;
create policy persona_lectura on public.persona for select to authenticated
  using ((select private.es_interno()) or id = (select private.persona_actual()));

drop policy if exists persona_alta on public.persona;
create policy persona_alta on public.persona for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists persona_edicion on public.persona;
create policy persona_edicion on public.persona for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- cliente ----------
drop policy if exists cliente_lectura on public.cliente;
create policy cliente_lectura on public.cliente for select to authenticated
  using ((select private.es_interno()));

drop policy if exists cliente_alta on public.cliente;
create policy cliente_alta on public.cliente for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists cliente_edicion on public.cliente;
create policy cliente_edicion on public.cliente for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

-- ---------- categoria_costo ----------
drop policy if exists categoria_costo_lectura on public.categoria_costo;
create policy categoria_costo_lectura on public.categoria_costo for select to authenticated
  using ((select private.es_interno()));

drop policy if exists categoria_costo_alta on public.categoria_costo;
create policy categoria_costo_alta on public.categoria_costo for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists categoria_costo_edicion on public.categoria_costo;
create policy categoria_costo_edicion on public.categoria_costo for update to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

-- ---------- cuenta · bancos y cajas: dirección y finanzas ----------
drop policy if exists cuenta_lectura on public.cuenta;
create policy cuenta_lectura on public.cuenta for select to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists cuenta_alta on public.cuenta;
create policy cuenta_alta on public.cuenta for insert to authenticated
  with check ((select private.tiene_rol('{socio,financiero}'::public.rol_persona[])));

drop policy if exists cuenta_edicion on public.cuenta;
create policy cuenta_edicion on public.cuenta for update to authenticated
  using ((select private.tiene_rol('{socio,financiero}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,financiero}'::public.rol_persona[])));

-- ---------- proyecto · lo asignado, o el portal del cliente ----------
drop policy if exists proyecto_lectura on public.proyecto;
create policy proyecto_lectura on public.proyecto for select to authenticated
  using (id in (select private.proyectos_visibles()) or id in (select private.proyectos_portal()));

drop policy if exists proyecto_alta on public.proyecto;
create policy proyecto_alta on public.proyecto for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists proyecto_edicion on public.proyecto;
create policy proyecto_edicion on public.proyecto for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- centro_costo ----------
drop policy if exists centro_costo_lectura on public.centro_costo;
create policy centro_costo_lectura on public.centro_costo for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));

drop policy if exists centro_costo_alta on public.centro_costo;
create policy centro_costo_alta on public.centro_costo for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists centro_costo_edicion on public.centro_costo;
create policy centro_costo_edicion on public.centro_costo for update to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

-- ---------- acceso_proyecto · el único retiro permitido: quitar un acceso ----------
drop policy if exists acceso_proyecto_lectura on public.acceso_proyecto;
create policy acceso_proyecto_lectura on public.acceso_proyecto for select to authenticated
  using ((select private.es_direccion()) or persona_id = (select private.persona_actual()));

drop policy if exists acceso_proyecto_alta on public.acceso_proyecto;
create policy acceso_proyecto_alta on public.acceso_proyecto for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists acceso_proyecto_edicion on public.acceso_proyecto;
create policy acceso_proyecto_edicion on public.acceso_proyecto for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

drop policy if exists acceso_proyecto_retiro on public.acceso_proyecto;
create policy acceso_proyecto_retiro on public.acceso_proyecto for delete to authenticated
  using ((select private.es_direccion()));

-- ---------- evento_auditoria · solo se lee; la escribe el sistema ----------
drop policy if exists evento_auditoria_lectura on public.evento_auditoria;
create policy evento_auditoria_lectura on public.evento_auditoria for select to authenticated
  using ((select private.es_direccion()));

-- ---------- regla_alerta ----------
drop policy if exists regla_alerta_lectura on public.regla_alerta;
create policy regla_alerta_lectura on public.regla_alerta for select to authenticated
  using ((select private.es_interno()));

drop policy if exists regla_alerta_alta on public.regla_alerta;
create policy regla_alerta_alta on public.regla_alerta for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists regla_alerta_edicion on public.regla_alerta;
create policy regla_alerta_edicion on public.regla_alerta for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- alerta · la ve y la resuelve a quien le llegó ----------
drop policy if exists alerta_lectura on public.alerta;
create policy alerta_lectura on public.alerta for select to authenticated
  using ((select private.es_direccion()) or (select private.persona_actual()) = any (destinatarios));

drop policy if exists alerta_edicion on public.alerta;
create policy alerta_edicion on public.alerta for update to authenticated
  using ((select private.es_direccion()) or (select private.persona_actual()) = any (destinatarios))
  with check ((select private.es_direccion()) or (select private.persona_actual()) = any (destinatarios));

-- ---------- aviso · bandeja de salida; la escribe el sistema ----------
drop policy if exists aviso_lectura on public.aviso;
create policy aviso_lectura on public.aviso for select to authenticated
  using ((select private.es_direccion()) or persona_id = (select private.persona_actual()));

-- ---------- objetivo · los abre dirección; los ve el equipo ----------
-- Un objetivo de la empresa lo ve todo el mundo adentro. Uno de proyecto, quien
-- tiene acceso a ese proyecto. Uno de persona, esa persona y dirección.
drop policy if exists objetivo_lectura on public.objetivo;
create policy objetivo_lectura on public.objetivo for select to authenticated
  using ((select private.es_interno())
         and (ambito = 'empresa'
              or proyecto_id in (select private.proyectos_visibles())
              or persona_id = (select private.persona_actual())
              or responsable_id = (select private.persona_actual())));

drop policy if exists objetivo_alta on public.objetivo;
create policy objetivo_alta on public.objetivo for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists objetivo_edicion on public.objetivo;
create policy objetivo_edicion on public.objetivo for update to authenticated
  using ((select private.es_direccion()) or responsable_id = (select private.persona_actual()))
  with check ((select private.es_direccion()) or responsable_id = (select private.persona_actual()));
