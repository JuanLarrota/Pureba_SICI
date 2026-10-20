-- =============================================================================
-- SICI · Políticas de acceso por fila · M-01 Gasto de obra, M-03 Bitácora y
-- actas, M-08 Portal de cliente y contratista
--
-- El residente registra en sus obras a su propio nombre; aprueba, concilia y
-- corrige dirección (y finanzas solo concilia). El cliente ve desde el portal
-- sus adicionales, sus actas de cobro y la bitácora, y decide sobre los
-- adicionales; nunca ve un movimiento, un costo ni un proveedor. El
-- contratista ve solo sus actas de pago.
-- =============================================================================

-- ---------- fondo_caja · la ve quien la tiene a cargo ----------
drop policy if exists fondo_caja_lectura on public.fondo_caja;
create policy fondo_caja_lectura on public.fondo_caja for select to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[]))
         or responsable_id = (select private.persona_actual()));

drop policy if exists fondo_caja_alta on public.fondo_caja;
create policy fondo_caja_alta on public.fondo_caja for insert to authenticated
  with check ((select private.es_direccion()));

drop policy if exists fondo_caja_edicion on public.fondo_caja;
create policy fondo_caja_edicion on public.fondo_caja for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- cambio_obra · lo registra la obra; lo cierra diseño ----------
drop policy if exists cambio_obra_lectura on public.cambio_obra;
create policy cambio_obra_lectura on public.cambio_obra for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));

drop policy if exists cambio_obra_alta on public.cambio_obra;
create policy cambio_obra_alta on public.cambio_obra for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and decidido_por = (select private.persona_actual()));

drop policy if exists cambio_obra_edicion on public.cambio_obra;
create policy cambio_obra_edicion on public.cambio_obra for update to authenticated
  using ((select private.es_direccion())
         or (proyecto_id in (select private.proyectos_registro())
             and (select private.tiene_rol('{arquitecto,practicante}'::public.rol_persona[]))))
  with check ((select private.es_direccion())
              or (proyecto_id in (select private.proyectos_registro())
                  and (select private.tiene_rol('{arquitecto,practicante}'::public.rol_persona[]))));

-- ---------- adicional · lo propone la obra; la decisión es del cliente ----------
drop policy if exists adicional_lectura on public.adicional;
create policy adicional_lectura on public.adicional for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles())
         or proyecto_id in (select private.proyectos_portal()));

drop policy if exists adicional_alta on public.adicional;
create policy adicional_alta on public.adicional for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro()));

drop policy if exists adicional_edicion on public.adicional;
create policy adicional_edicion on public.adicional for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- bitacora ----------
drop policy if exists bitacora_lectura on public.bitacora;
create policy bitacora_lectura on public.bitacora for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles())
         or proyecto_id in (select private.proyectos_portal()));

drop policy if exists bitacora_alta on public.bitacora;
create policy bitacora_alta on public.bitacora for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and registrado_por = (select private.persona_actual()));

drop policy if exists bitacora_edicion on public.bitacora;
create policy bitacora_edicion on public.bitacora for update to authenticated
  using (proyecto_id in (select private.proyectos_registro())
         and registrado_por = (select private.persona_actual()))
  with check (proyecto_id in (select private.proyectos_registro())
              and registrado_por = (select private.persona_actual()));

-- ---------- bitacora_cuadrilla · hereda de su bitácora ----------
drop policy if exists bitacora_cuadrilla_lectura on public.bitacora_cuadrilla;
create policy bitacora_cuadrilla_lectura on public.bitacora_cuadrilla for select to authenticated
  using (exists (select 1 from public.bitacora b where b.id = bitacora_cuadrilla.bitacora_id));

drop policy if exists bitacora_cuadrilla_alta on public.bitacora_cuadrilla;
create policy bitacora_cuadrilla_alta on public.bitacora_cuadrilla for insert to authenticated
  with check (exists (select 1 from public.bitacora b
                      where b.id = bitacora_cuadrilla.bitacora_id
                        and b.proyecto_id in (select private.proyectos_registro())
                        and (b.registrado_por = (select private.persona_actual())
                             or (select private.es_direccion()))));

drop policy if exists bitacora_cuadrilla_edicion on public.bitacora_cuadrilla;
create policy bitacora_cuadrilla_edicion on public.bitacora_cuadrilla for update to authenticated
  using (exists (select 1 from public.bitacora b
                 where b.id = bitacora_cuadrilla.bitacora_id
                   and b.proyecto_id in (select private.proyectos_registro())
                   and (b.registrado_por = (select private.persona_actual())
                        or (select private.es_direccion()))))
  with check (exists (select 1 from public.bitacora b
                      where b.id = bitacora_cuadrilla.bitacora_id
                        and b.proyecto_id in (select private.proyectos_registro())
                        and (b.registrado_por = (select private.persona_actual())
                             or (select private.es_direccion()))));

-- ---------- acta · de cobro para el cliente, de pago para su contratista ----------
drop policy if exists acta_lectura on public.acta;
create policy acta_lectura on public.acta for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles())
         or (tipo = 'cobro_cliente' and proyecto_id in (select private.proyectos_portal()))
         or (tipo = 'pago_contratista' and tercero_id = (select private.persona_actual())));

drop policy if exists acta_alta on public.acta;
create policy acta_alta on public.acta for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,residente,financiero}'::public.rol_persona[])));

drop policy if exists acta_edicion on public.acta;
create policy acta_edicion on public.acta for update to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

-- ---------- acta_item · hereda de su acta; es constancia, no se edita ----------
drop policy if exists acta_item_lectura on public.acta_item;
create policy acta_item_lectura on public.acta_item for select to authenticated
  using (exists (select 1 from public.acta a where a.id = acta_item.acta_id));

drop policy if exists acta_item_alta on public.acta_item;
create policy acta_item_alta on public.acta_item for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,residente,financiero}'::public.rol_persona[]))
              and exists (select 1 from public.acta a
                          where a.id = acta_item.acta_id
                            and a.proyecto_id in (select private.proyectos_registro())));

-- ---------- movimiento · el dinero: solo equipo interno ----------
drop policy if exists movimiento_lectura on public.movimiento;
create policy movimiento_lectura on public.movimiento for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));

drop policy if exists movimiento_alta on public.movimiento;
create policy movimiento_alta on public.movimiento for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and registrado_por = (select private.persona_actual()));

-- Aprueba y corrige dirección; finanzas solo concilia (lo vigila el disparador).
drop policy if exists movimiento_edicion on public.movimiento;
create policy movimiento_edicion on public.movimiento for update to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

-- ---------- aprobacion_cliente · la decisión del cliente en el portal ----------
drop policy if exists aprobacion_cliente_lectura on public.aprobacion_cliente;
create policy aprobacion_cliente_lectura on public.aprobacion_cliente for select to authenticated
  using (persona_id = (select private.persona_actual())
         or exists (select 1 from public.adicional a
                    where a.id = aprobacion_cliente.adicional_id
                      and a.proyecto_id in (select private.proyectos_visibles())));

drop policy if exists aprobacion_cliente_alta on public.aprobacion_cliente;
create policy aprobacion_cliente_alta on public.aprobacion_cliente for insert to authenticated
  with check (persona_id = (select private.persona_actual())
              and exists (select 1 from public.adicional a
                          where a.id = aprobacion_cliente.adicional_id
                            and a.proyecto_id in (select private.proyectos_portal())));

-- ---------- evidencia · la sube quien está en la obra; nadie la edita ----------
drop policy if exists evidencia_lectura on public.evidencia;
create policy evidencia_lectura on public.evidencia for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles()));

drop policy if exists evidencia_alta on public.evidencia;
create policy evidencia_alta on public.evidencia for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and registrada_por = (select private.persona_actual()));

-- ---------- pendiente_obra · la lista de remates del residente ----------
-- El contratista ve lo que tiene que hacer y puede marcarlo como hecho, pero
-- la verificación la hace otro: eso lo impide el disparador, no la política.
drop policy if exists pendiente_obra_lectura on public.pendiente_obra;
create policy pendiente_obra_lectura on public.pendiente_obra for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles())
         or ejecutor_id = (select private.persona_actual()));

drop policy if exists pendiente_obra_alta on public.pendiente_obra;
create policy pendiente_obra_alta on public.pendiente_obra for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,residente,arquitecto}'::public.rol_persona[])));

drop policy if exists pendiente_obra_edicion on public.pendiente_obra;
create policy pendiente_obra_edicion on public.pendiente_obra for update to authenticated
  using ((select private.es_direccion())
         or (proyecto_id in (select private.proyectos_registro())
             and (responsable_id = (select private.persona_actual())
                  or creado_por = (select private.persona_actual())))
         or ejecutor_id = (select private.persona_actual()))
  with check ((select private.es_direccion())
              or (proyecto_id in (select private.proyectos_registro())
                  and (responsable_id = (select private.persona_actual())
                       or creado_por = (select private.persona_actual())))
              or ejecutor_id = (select private.persona_actual()));
