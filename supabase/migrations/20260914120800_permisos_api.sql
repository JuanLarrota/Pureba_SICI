-- =============================================================================
-- SICI · Permisos de la API de Supabase
--
-- Desde el 30 de mayo de 2026 los proyectos nuevos de Supabase ya no dan
-- permisos automáticos sobre las tablas nuevas, y desde el 30 de octubre de
-- 2026 aplica a todos. Sin este archivo la aplicación no podría leer nada.
-- Los proyectos más viejos, al revés, dan todo a todos, incluido "anon". Por
-- eso aquí primero se retira todo y después se otorga exactamente lo necesario:
-- el resultado es el mismo con cualquiera de las dos configuraciones.
--
-- Dos capas, las dos necesarias:
--   1. Estos permisos dicen qué operación puede intentar cada rol.
--   2. Las políticas rls_* dicen sobre qué filas.
--
-- Roles de Supabase:
--   anon           cualquiera con la llave pública, sin sesión: nada.
--   authenticated  usuarios con sesión: lo necesario, filtrado por políticas.
--   service_role   tareas del servidor (alertas, importación de pauta): todo.
--                  Su llave nunca va en el navegador ni en la PWA.
--
-- Nadie tiene permiso de borrar, salvo retirar un acceso a un proyecto.
-- Idempotente.
-- =============================================================================

-- ---------- 1. Retirar todo ----------
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
revoke all on schema private from public, anon;
revoke all on all functions in schema private from public, anon, authenticated;

-- Lo que se cree después en "public" tampoco nace abierto para "anon".
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;

-- ---------- 2. authenticated: tablas ----------

-- Se consultan, se crean y se actualizan (las políticas dicen qué filas).
grant select, insert, update on
  public.persona, public.cliente, public.categoria_costo, public.cuenta,
  public.proyecto, public.centro_costo, public.regla_alerta,
  public.experimento, public.campana, public.inversion_pauta, public.lead, public.contacto_lead,
  public.oportunidad, public.calificacion, public.cita, public.cotizacion,
  public.proyecto_fase, public.elemento_diseno, public.tarea_diseno, public.dedicacion,
  public.entregable, public.complementario, public.radicacion_licencia,
  public.insumo, public.apu, public.apu_componente, public.presupuesto, public.capitulo,
  public.item_presupuesto, public.ejecucion_item, public.actividad_cronograma,
  public.fondo_caja, public.cambio_obra, public.adicional, public.bitacora, public.bitacora_cuadrilla,
  public.acta, public.movimiento,
  public.reclamacion, public.lista_chequeo, public.lista_chequeo_item, public.chequeo_respuesta,
  public.saldo_cuenta, public.ingreso, public.extracto_linea, public.partida_abierta,
  public.cierre_mes, public.distribucion_estructura,
  public.objetivo, public.pendiente_obra
to authenticated;

-- Constancias: se crean y se consultan, nunca se editan.
grant select, insert on
  public.revision_diseno, public.entregable_archivo, public.acta_item,
  public.aprobacion_cliente, public.chequeo, public.evidencia
to authenticated;

-- Una sola fila que se ajusta; alertas que se marcan como resueltas.
grant select, update on public.parametro, public.alerta to authenticated;

-- Las escribe el sistema.
grant select on public.evento_auditoria, public.reclamacion_evento, public.aviso to authenticated;

-- El único retiro permitido.
grant select, insert, update, delete on public.acceso_proyecto to authenticated;

-- ---------- 3. authenticated: vistas ----------
grant select on
  public.v_movimiento_vigente, public.v_balance_centro_costo, public.v_adicionales_netos,
  public.v_desviacion_capitulo, public.v_caja_menor, public.v_cambios_sin_reflejar,
  public.v_proyecto_resumen, public.v_bitacora_faltante, public.v_cartera,
  public.v_flujo_13_semanas, public.v_rentabilidad_proyecto, public.v_partidas_abiertas,
  public.v_fase_horas, public.v_dedicacion_pendiente, public.v_capacidad_13_semanas,
  public.v_complementarios_atrasados, public.v_reclamaciones, public.v_embudo_mensual,
  public.v_retorno_pauta, public.v_calibracion_capitulo, public.v_apu_costo,
  public.v_pendientes_obra, public.v_trabajo_abierto, public.v_objetivos
to authenticated;

-- ---------- 4. authenticated: secuencias y funciones ----------
grant usage, select on all sequences in schema public to authenticated;

grant execute on function public.distribuir_estructura(date) to authenticated;

-- Las políticas y las vistas llaman estas funciones con los permisos de quien
-- consulta. El resto de "private" (reglas, generador de alertas) no se otorga.
grant usage on schema private to authenticated;
grant execute on function
  private.hoy(),
  private.pesos(numeric),
  private.uuid_seguro(text),
  private.persona_actual(),
  private.es_interno(),
  private.tiene_rol(public.rol_persona[]),
  private.es_direccion(),
  private.proyectos_visibles(),
  private.proyectos_registro(),
  private.proyectos_portal(),
  private.mes_cerrado(date)
to authenticated;

-- ---------- 5. service_role ----------
grant usage on schema public, private to service_role;
grant select, insert, update, delete on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;
grant execute on all functions in schema private to service_role;
