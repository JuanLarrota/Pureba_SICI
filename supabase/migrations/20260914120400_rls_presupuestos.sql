-- =============================================================================
-- SICI · Políticas de acceso por fila · M-06 Presupuestos, APU y cronograma
--
-- La base de precios y los APU son conocimiento de la empresa: los ve el
-- equipo interno y los editan los profesionales. El cliente ve el presupuesto
-- vigente de su obra y su avance, que es lo que hoy recibe en el balance; nunca
-- los APU ni los precios de insumos.
-- Capítulos, ítems y avance heredan la visibilidad de su presupuesto.
-- =============================================================================

-- ---------- insumo ----------
drop policy if exists insumo_lectura on public.insumo;
create policy insumo_lectura on public.insumo for select to authenticated
  using ((select private.es_interno()));

drop policy if exists insumo_alta on public.insumo;
create policy insumo_alta on public.insumo for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

drop policy if exists insumo_edicion on public.insumo;
create policy insumo_edicion on public.insumo for update to authenticated
  using ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

-- ---------- apu ----------
drop policy if exists apu_lectura on public.apu;
create policy apu_lectura on public.apu for select to authenticated
  using ((select private.es_interno()));

drop policy if exists apu_alta on public.apu;
create policy apu_alta on public.apu for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

drop policy if exists apu_edicion on public.apu;
create policy apu_edicion on public.apu for update to authenticated
  using ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

-- ---------- apu_componente ----------
drop policy if exists apu_componente_lectura on public.apu_componente;
create policy apu_componente_lectura on public.apu_componente for select to authenticated
  using ((select private.es_interno()));

drop policy if exists apu_componente_alta on public.apu_componente;
create policy apu_componente_alta on public.apu_componente for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

drop policy if exists apu_componente_edicion on public.apu_componente;
create policy apu_componente_edicion on public.apu_componente for update to authenticated
  using ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

-- ---------- presupuesto ----------
drop policy if exists presupuesto_lectura on public.presupuesto;
create policy presupuesto_lectura on public.presupuesto for select to authenticated
  using (proyecto_id in (select private.proyectos_visibles())
         or (vigente and proyecto_id in (select private.proyectos_portal())));

drop policy if exists presupuesto_alta on public.presupuesto;
create policy presupuesto_alta on public.presupuesto for insert to authenticated
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

drop policy if exists presupuesto_edicion on public.presupuesto;
create policy presupuesto_edicion on public.presupuesto for update to authenticated
  using (proyecto_id in (select private.proyectos_registro())
         and (select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])))
  with check (proyecto_id in (select private.proyectos_registro())
              and (select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[])));

-- ---------- capitulo ----------
drop policy if exists capitulo_lectura on public.capitulo;
create policy capitulo_lectura on public.capitulo for select to authenticated
  using (exists (select 1 from public.presupuesto pr where pr.id = capitulo.presupuesto_id));

drop policy if exists capitulo_alta on public.capitulo;
create policy capitulo_alta on public.capitulo for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[]))
              and exists (select 1 from public.presupuesto pr
                          where pr.id = capitulo.presupuesto_id
                            and pr.proyecto_id in (select private.proyectos_registro())));

drop policy if exists capitulo_edicion on public.capitulo;
create policy capitulo_edicion on public.capitulo for update to authenticated
  using ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[]))
         and exists (select 1 from public.presupuesto pr
                     where pr.id = capitulo.presupuesto_id
                       and pr.proyecto_id in (select private.proyectos_registro())))
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[]))
              and exists (select 1 from public.presupuesto pr
                          where pr.id = capitulo.presupuesto_id
                            and pr.proyecto_id in (select private.proyectos_registro())));

-- ---------- item_presupuesto ----------
drop policy if exists item_presupuesto_lectura on public.item_presupuesto;
create policy item_presupuesto_lectura on public.item_presupuesto for select to authenticated
  using (exists (select 1 from public.capitulo c where c.id = item_presupuesto.capitulo_id));

drop policy if exists item_presupuesto_alta on public.item_presupuesto;
create policy item_presupuesto_alta on public.item_presupuesto for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[]))
              and exists (select 1 from public.capitulo c
                          join public.presupuesto pr on pr.id = c.presupuesto_id
                          where c.id = item_presupuesto.capitulo_id
                            and pr.proyecto_id in (select private.proyectos_registro())));

drop policy if exists item_presupuesto_edicion on public.item_presupuesto;
create policy item_presupuesto_edicion on public.item_presupuesto for update to authenticated
  using ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[]))
         and exists (select 1 from public.capitulo c
                     join public.presupuesto pr on pr.id = c.presupuesto_id
                     where c.id = item_presupuesto.capitulo_id
                       and pr.proyecto_id in (select private.proyectos_registro())))
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[]))
              and exists (select 1 from public.capitulo c
                          join public.presupuesto pr on pr.id = c.presupuesto_id
                          where c.id = item_presupuesto.capitulo_id
                            and pr.proyecto_id in (select private.proyectos_registro())));

-- ---------- ejecucion_item · el avance lo registra quien está en la obra ----------
drop policy if exists ejecucion_item_lectura on public.ejecucion_item;
create policy ejecucion_item_lectura on public.ejecucion_item for select to authenticated
  using (exists (select 1 from public.item_presupuesto i where i.id = ejecucion_item.item_id));

drop policy if exists ejecucion_item_alta on public.ejecucion_item;
create policy ejecucion_item_alta on public.ejecucion_item for insert to authenticated
  with check (exists (select 1 from public.item_presupuesto i
                      join public.capitulo c on c.id = i.capitulo_id
                      join public.presupuesto pr on pr.id = c.presupuesto_id
                      where i.id = ejecucion_item.item_id
                        and pr.proyecto_id in (select private.proyectos_registro())));

drop policy if exists ejecucion_item_edicion on public.ejecucion_item;
create policy ejecucion_item_edicion on public.ejecucion_item for update to authenticated
  using (exists (select 1 from public.item_presupuesto i
                 join public.capitulo c on c.id = i.capitulo_id
                 join public.presupuesto pr on pr.id = c.presupuesto_id
                 where i.id = ejecucion_item.item_id
                   and pr.proyecto_id in (select private.proyectos_registro())))
  with check (exists (select 1 from public.item_presupuesto i
                      join public.capitulo c on c.id = i.capitulo_id
                      join public.presupuesto pr on pr.id = c.presupuesto_id
                      where i.id = ejecucion_item.item_id
                        and pr.proyecto_id in (select private.proyectos_registro())));

-- ---------- actividad_cronograma ----------
drop policy if exists actividad_cronograma_lectura on public.actividad_cronograma;
create policy actividad_cronograma_lectura on public.actividad_cronograma for select to authenticated
  using (exists (select 1 from public.presupuesto pr where pr.id = actividad_cronograma.presupuesto_id));

drop policy if exists actividad_cronograma_alta on public.actividad_cronograma;
create policy actividad_cronograma_alta on public.actividad_cronograma for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,arquitecto}'::public.rol_persona[]))
              and exists (select 1 from public.presupuesto pr
                          where pr.id = actividad_cronograma.presupuesto_id
                            and pr.proyecto_id in (select private.proyectos_registro())));

drop policy if exists actividad_cronograma_edicion on public.actividad_cronograma;
create policy actividad_cronograma_edicion on public.actividad_cronograma for update to authenticated
  using (exists (select 1 from public.presupuesto pr
                 where pr.id = actividad_cronograma.presupuesto_id
                   and pr.proyecto_id in (select private.proyectos_registro())))
  with check (exists (select 1 from public.presupuesto pr
                      where pr.id = actividad_cronograma.presupuesto_id
                        and pr.proyecto_id in (select private.proyectos_registro())));
