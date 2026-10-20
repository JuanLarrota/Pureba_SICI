-- =============================================================================
-- SICI · Políticas de acceso por fila · M-05 Comercial: mercadeo, ventas y CRM
--
-- El embudo lo trabajan mercadeo (Alison) y dirección (Felipe cierra ventas).
-- Finanzas lee la inversión en pauta y las cotizaciones para el flujo de caja.
-- Ni obra ni diseño ven los datos personales de los prospectos.
-- =============================================================================

-- ---------- experimento ----------
drop policy if exists experimento_lectura on public.experimento;
create policy experimento_lectura on public.experimento for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists experimento_alta on public.experimento;
create policy experimento_alta on public.experimento for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists experimento_edicion on public.experimento;
create policy experimento_edicion on public.experimento for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

-- ---------- campana ----------
drop policy if exists campana_lectura on public.campana;
create policy campana_lectura on public.campana for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo,financiero}'::public.rol_persona[])));

drop policy if exists campana_alta on public.campana;
create policy campana_alta on public.campana for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists campana_edicion on public.campana;
create policy campana_edicion on public.campana for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

-- ---------- inversion_pauta ----------
drop policy if exists inversion_pauta_lectura on public.inversion_pauta;
create policy inversion_pauta_lectura on public.inversion_pauta for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo,financiero}'::public.rol_persona[])));

drop policy if exists inversion_pauta_alta on public.inversion_pauta;
create policy inversion_pauta_alta on public.inversion_pauta for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists inversion_pauta_edicion on public.inversion_pauta;
create policy inversion_pauta_edicion on public.inversion_pauta for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

-- ---------- lead ----------
drop policy if exists lead_lectura on public.lead;
create policy lead_lectura on public.lead for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists lead_alta on public.lead;
create policy lead_alta on public.lead for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists lead_edicion on public.lead;
create policy lead_edicion on public.lead for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

-- ---------- contacto_lead ----------
drop policy if exists contacto_lead_lectura on public.contacto_lead;
create policy contacto_lead_lectura on public.contacto_lead for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists contacto_lead_alta on public.contacto_lead;
create policy contacto_lead_alta on public.contacto_lead for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[]))
              and registrado_por = (select private.persona_actual()));

drop policy if exists contacto_lead_edicion on public.contacto_lead;
create policy contacto_lead_edicion on public.contacto_lead for update to authenticated
  using ((select private.es_direccion()))
  with check ((select private.es_direccion()));

-- ---------- oportunidad ----------
drop policy if exists oportunidad_lectura on public.oportunidad;
create policy oportunidad_lectura on public.oportunidad for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists oportunidad_alta on public.oportunidad;
create policy oportunidad_alta on public.oportunidad for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists oportunidad_edicion on public.oportunidad;
create policy oportunidad_edicion on public.oportunidad for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

-- ---------- calificacion · la ficha de 6 campos ----------
drop policy if exists calificacion_lectura on public.calificacion;
create policy calificacion_lectura on public.calificacion for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists calificacion_alta on public.calificacion;
create policy calificacion_alta on public.calificacion for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists calificacion_edicion on public.calificacion;
create policy calificacion_edicion on public.calificacion for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

-- ---------- cita ----------
drop policy if exists cita_lectura on public.cita;
create policy cita_lectura on public.cita for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists cita_alta on public.cita;
create policy cita_alta on public.cita for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists cita_edicion on public.cita;
create policy cita_edicion on public.cita for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

-- ---------- cotizacion ----------
drop policy if exists cotizacion_lectura on public.cotizacion;
create policy cotizacion_lectura on public.cotizacion for select to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo,financiero}'::public.rol_persona[])));

drop policy if exists cotizacion_alta on public.cotizacion;
create policy cotizacion_alta on public.cotizacion for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));

drop policy if exists cotizacion_edicion on public.cotizacion;
create policy cotizacion_edicion on public.cotizacion for update to authenticated
  using ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));
