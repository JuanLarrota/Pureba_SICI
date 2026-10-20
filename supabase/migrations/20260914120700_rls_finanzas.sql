-- =============================================================================
-- SICI · Políticas de acceso por fila · M-07 Finanzas
--
-- Saldos, ingresos, extractos, cierres y distribución de estructura: socios,
-- dirección y finanzas. Una partida abierta la ve y la resuelve también la
-- persona a la que se le asignó (F1: cada diferencia tiene dueño).
-- Cerrar un mes es de finanzas o de un socio; reabrirlo, solo de un socio
-- (lo vigila el disparador).
-- =============================================================================

-- ---------- saldo_cuenta ----------
drop policy if exists saldo_cuenta_lectura on public.saldo_cuenta;
create policy saldo_cuenta_lectura on public.saldo_cuenta for select to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists saldo_cuenta_alta on public.saldo_cuenta;
create policy saldo_cuenta_alta on public.saldo_cuenta for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists saldo_cuenta_edicion on public.saldo_cuenta;
create policy saldo_cuenta_edicion on public.saldo_cuenta for update to authenticated
  using ((select private.tiene_rol('{socio,financiero}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,financiero}'::public.rol_persona[])));

-- ---------- ingreso ----------
drop policy if exists ingreso_lectura on public.ingreso;
create policy ingreso_lectura on public.ingreso for select to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists ingreso_alta on public.ingreso;
create policy ingreso_alta on public.ingreso for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[]))
              and registrado_por = (select private.persona_actual()));

drop policy if exists ingreso_edicion on public.ingreso;
create policy ingreso_edicion on public.ingreso for update to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

-- ---------- extracto_linea ----------
drop policy if exists extracto_linea_lectura on public.extracto_linea;
create policy extracto_linea_lectura on public.extracto_linea for select to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists extracto_linea_alta on public.extracto_linea;
create policy extracto_linea_alta on public.extracto_linea for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists extracto_linea_edicion on public.extracto_linea;
create policy extracto_linea_edicion on public.extracto_linea for update to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

-- ---------- partida_abierta ----------
drop policy if exists partida_abierta_lectura on public.partida_abierta;
create policy partida_abierta_lectura on public.partida_abierta for select to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[]))
         or responsable_id = (select private.persona_actual()));

drop policy if exists partida_abierta_alta on public.partida_abierta;
create policy partida_abierta_alta on public.partida_abierta for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists partida_abierta_edicion on public.partida_abierta;
create policy partida_abierta_edicion on public.partida_abierta for update to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[]))
         or responsable_id = (select private.persona_actual()))
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[]))
              or responsable_id = (select private.persona_actual()));

-- ---------- cierre_mes ----------
drop policy if exists cierre_mes_lectura on public.cierre_mes;
create policy cierre_mes_lectura on public.cierre_mes for select to authenticated
  using ((select private.es_interno()));

drop policy if exists cierre_mes_alta on public.cierre_mes;
create policy cierre_mes_alta on public.cierre_mes for insert to authenticated
  with check ((select private.tiene_rol('{socio,financiero}'::public.rol_persona[])));

drop policy if exists cierre_mes_edicion on public.cierre_mes;
create policy cierre_mes_edicion on public.cierre_mes for update to authenticated
  using ((select private.tiene_rol('{socio}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio}'::public.rol_persona[])));

-- ---------- distribucion_estructura ----------
drop policy if exists distribucion_estructura_lectura on public.distribucion_estructura;
create policy distribucion_estructura_lectura on public.distribucion_estructura for select to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists distribucion_estructura_alta on public.distribucion_estructura;
create policy distribucion_estructura_alta on public.distribucion_estructura for insert to authenticated
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));

drop policy if exists distribucion_estructura_edicion on public.distribucion_estructura;
create policy distribucion_estructura_edicion on public.distribucion_estructura for update to authenticated
  using ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])))
  with check ((select private.tiene_rol('{socio,director,financiero}'::public.rol_persona[])));
