#!/usr/bin/env python3
"""
SICI · ¿las pruebas vigilan de verdad cada regla?

Una prueba que nunca falla no prueba nada. Este archivo siembra un error a la
vez en una copia de las migraciones de la etapa 2 (afloja una regla, quita un
filtro, borra una condición), corre la batería completa contra esa copia y
exige que al menos una prueba se dé cuenta. Si un error sembrado pasa en
limpio, esa regla está sin vigilancia.

No toca los archivos reales ni ninguna base de la empresa.

Uso (desde sici/, con el mismo entorno de probar_contra_postgres.py):
  .venv/bin/python supabase/pruebas/sembrar_errores.py [cuántas a la vez]
"""

import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
MIGRACIONES = ["supabase/migrations/20261012120100_modulo_diseno.sql",
               "supabase/migrations/20261012120200_indicadores.sql",
               "supabase/migrations/20261012120300_mensajes.sql",
               "supabase/migrations/20261014120000_carga_semanal.sql",
               "supabase/migrations/20261015120000_flujo_por_fase.sql",
               "supabase/migrations/20261016120000_tareas_tipicas.sql",
               "supabase/migrations/20261017120000_cierre_de_fase.sql",
               "supabase/migrations/20261018120000_embudo_de_ventas.sql",
               "supabase/migrations/20261019120000_modulo_obra.sql",
               "supabase/migrations/20261020120000_prestamos_y_socios.sql",
               "supabase/migrations/20261021120000_adicional_retirado.sql",
               "supabase/migrations/20261022120000_revision_y_papeles.sql"]


def a_aviso(fragmento):
    """La regla deja de impedir: su 'raise exception' se vuelve un aviso."""
    return ("raise exception '" + fragmento, "raise notice '" + fragmento)


# nombre -> (texto que está hoy, texto con el error sembrado)
ERRORES = {
    "equipo · recibe tareas quien no tiene papel":      a_aviso("D10 · % no hace parte del equipo"),
    "equipo · un externo con papel de producir":        a_aviso("D10 · Una persona externa no tiene papel"),
    "equipo · se retira a quien tiene trabajo abierto": a_aviso("D10 · Tiene % tarea(s) abierta(s) en este proyecto: reasígnelas antes de retirarla"),
    "equipo · se deja de observadora con trabajo":      a_aviso("D10 · Tiene % tarea(s) abierta(s) en este proyecto: reasígnelas antes de dejarla"),
    "equipo · todos ven el equipo de todos": (
        "         or proyecto_id in (select private.proyectos_visibles()));",
        "         or true);"),
    "tarea · se guarda sin fecha":                      a_aviso("D10 · Una tarea no se guarda sin fecha de entrega"),
    "tarea · se guarda sin persona":                    a_aviso("D10 · Una tarea no se guarda sin persona"),
    "tarea · quien la hace se corre la fecha":          a_aviso("D10 · La fecha, la prioridad y el responsable"),
    "tarea · la propia se le pasa a otro":              a_aviso("D10 · Una tarea la reasigna quien dirige"),
    "tarea · nace ya entregada":                        a_aviso("D11 · Una tarea nace asignada o en curso"),
    "tarea · la reabre cualquiera":                     a_aviso("D11 · Una tarea terminada solo la reabre dirección"),
    "tarea · pide revisión estando bloqueada":          a_aviso("D9 · «%» no puede pedir revisión"),
    "tarea · la entrega quien la asignó":               a_aviso("D11 · La revisión la pide quien tiene la tarea"),
    "tarea · se marca devuelta a mano":                 a_aviso("D11 · Una tarea queda con observaciones solo cuando"),
    "tarea · se termina sin revisión":                  a_aviso("Una tarea no se termina sin la revisión aprobada"),
    "tarea · sirve una aprobación vieja": (
        "           and r.revisor_id <> new.asignada_a and r.revisada_en >= v_desde) then",
        "           and r.revisor_id <> new.asignada_a) then"),
    "tarea · se retoca la hora de la revisión": (
        "    new.revision_pedida_en := case when tg_op = 'UPDATE' then old.revision_pedida_en end;",
        "    null;"),
    "tarea · cualquiera le asigna a cualquiera": (
        "                   or asignada_a = (select private.persona_actual())));\n\ndrop policy if exists tarea_diseno_edicion",
        "                   or true));\n\ndrop policy if exists tarea_diseno_edicion"),
    "revisión · se revisa lo que nadie entregó":        a_aviso("D11 · Solo se revisa lo que pidió revisión"),
    "revisión · se la revisa quien la hizo":            a_aviso("La revisión la hace alguien distinto"),
    "revisión · revisa cualquiera del equipo": (
        "                        and t.proyecto_id in (select private.proyectos_que_revisa())));",
        "                        and t.proyecto_id in (select private.proyectos_registro())));"),
    "revisión · aprobar no termina la tarea": (
        "then 'terminada' else 'con_observaciones' end)::public.estado_tarea",
        "then 'en_revision' else 'con_observaciones' end)::public.estado_tarea"),
    "rastro · no guarda quién cambió el estado": (
        "    values (new.id, 'estado', old.estado::text, new.estado::text, v_yo);",
        "    values (new.id, 'estado', old.estado::text, new.estado::text, null);"),
    "rastro · no guarda los cambios de fecha": (
        "    values (new.id, 'fecha', old.fecha_compromiso::text, new.fecha_compromiso::text, v_yo);",
        "    values (new.id, 'fecha', old.fecha_compromiso::text, new.fecha_compromiso::text, null);"),
    "rastro · se puede editar": (
        "create trigger tr_tarea_evento_no_editar\n  before update on public.tarea_evento",
        "create trigger tr_tarea_evento_no_editar\n  before update of id on public.tarea_evento"),
    "fase · nace sin exigir al cliente": (
        "      new.exige_aprobacion_cliente := v_plantilla.exige_aprobacion_cliente;",
        "      new.exige_aprobacion_cliente := false;"),
    "fase · cualquiera afloja el cierre":               a_aviso("D12 · Lo que exige el cierre de una fase solo lo cambia un socio"),
    "fase · no queda con su lista al abrirse": (
        "      insert into public.chequeo (lista_id, fase_id) values (v_lista, new.id);",
        "      null;"),
    "lista · toma la de cualquier variante": (
        "    and (l.variante_id is null or l.variante_id = p.variante_chequeo_id)\n",
        "\n"),
    "lista · sirve la de otra variante":                a_aviso("D13 · Esta lista es de otra variante"),
    "plantilla · se omite una fase obligatoria":        a_aviso("D12 · Estas fases no se pueden omitir"),
    "plantilla · horas a una fase ajena":               a_aviso("D12 · Estas fases no son de la plantilla"),
    "plantilla · se aplica dos veces":                  a_aviso("D12 · Este proyecto ya tiene fases"),
    "plantilla · el render no espera al modelo": (
        "   where t.id = any (v_ids) and t.plantilla_tarea_id = pt.id and pt.depende_de is not null;",
        "   where false and t.id = any (v_ids) and t.plantilla_tarea_id = pt.id and pt.depende_de is not null;"),
    "mi día · se ve lo de los demás": (
        "  where t.asignada_a = (select private.persona_actual()) and t.estado <> 'terminada'\n  union all",
        "  where t.estado <> 'terminada'\n  union all"),
    "cola · la ve todo el equipo": (
        "  and t.proyecto_id in (select private.proyectos_que_revisa());",
        "  and true;"),
    "días hábiles · cuentan el festivo": (
        "  from generate_series(p_desde + 1, p_hasta, interval '1 day') g(dia)\n  where extract(isodow from g.dia) < 6\n"
        "    and not exists (select 1 from public.festivo f where f.fecha = g.dia::date)\n$$;",
        "  from generate_series(p_desde + 1, p_hasta, interval '1 day') g(dia)\n  where extract(isodow from g.dia) < 6\n$$;"),
    "permisos · el equipo puede borrar plantillas": (
        "grant select, insert, update on\n  public.festivo,",
        "grant select, insert, update, delete on\n  public.festivo,"),
    "rol · el director de proyecto no puede lo que un arquitecto": (
        "           or (p.rol::text = 'director_proyecto' and 'arquitecto' = any (p_roles))\n",
        "\n"),
    "rol · el director de proyecto no firma presupuestos": (
        "                     and p.rol in ('socio','director','arquitecto','director_proyecto')) then",
        "                     and p.rol in ('socio','director','arquitecto')) then"),

    # ---------- indicadores ----------
    "indicador · cuentan las tareas que uno se creó": (
        "    where t.asignada_a = p_persona and t.asignada_por <> t.asignada_a\n",
        "    where t.asignada_a = p_persona\n"),
    "indicador · se ven los de un compañero":           a_aviso("D14 · Cada persona ve sus indicadores"),
    "indicador · habla con pocos datos": (
        "  v_basta := v_revis >= v_par.minimo_revisadas_indicador;",
        "  v_basta := true;"),
    "indicador · todo cuenta como a tiempo": (
        "t.estado in ('en_revision','terminada') and t.entregada_el <= t.fecha_compromiso, false),",
        "t.estado in ('en_revision','terminada'), false),"),
    "indicador · la que vence hoy ya cuenta en contra": (
        "                  and (t.fecha_compromiso < p_hasta or t.estado in ('en_revision','terminada')), false),",
        "                  , false),"),
    "indicador · lo crítico pesa igual": (
        "when 'bloqueante' then par.peso_bloqueante",
        "when 'bloqueante' then 1"),
    "indicador · las devoluciones no cuentan": (
        "count(*) filter (where r.resultado = 'con_observaciones')::integer as devoluciones",
        "count(*) filter (where false)::integer as devoluciones"),
    "indicador · nadie espera nunca": (
        "                         greatest(t.fecha_compromiso, p_desde - 1),",
        "                         p_hasta,"),
    "indicador · lo corregido sigue contando": (
        "  where h.debia and not ('cumplio' = any (h.excluida_de));",
        "  where h.debia;"),
    "indicador · las horas de la fase son solo las propias": (
        "         sum(d.horas) filter (where d.persona_id = p_persona),\n         sum(d.horas),",
        "         sum(d.horas) filter (where d.persona_id = p_persona),\n         sum(d.horas) filter (where d.persona_id = p_persona),"),
    "indicador · la revisión tardía no se nota": (
        "count(*) filter (where h.dias_espera > v_par.dias_habiles_revision) as tarde,",
        "count(*) filter (where false) as tarde,"),
    "corrección · se pide sobre la tarea de otro":      a_aviso("D15 · Solo se pide corregir un dato de una tarea propia"),
    "corrección · resuelta, se vuelve a cambiar":       a_aviso("D15 · Una solicitud resuelta no se cambia"),
    "corrección · uno resuelve la suya":                a_aviso("D15 · Nadie resuelve la corrección de su propio indicador"),
    # La regla tiene dos barreras: la política y, detrás, el disparador. Se siembra
    # el error en la primera; quitar solo la segunda no se nota, y está bien así.
    "corrección · la resuelve quien la pide": (
        "create policy solicitud_correccion_edicion on public.solicitud_correccion for update to authenticated\n"
        "  using ((select private.es_direccion()))\n  with check ((select private.es_direccion()));",
        "create policy solicitud_correccion_edicion on public.solicitud_correccion for update to authenticated\n"
        "  using (true)\n  with check (true);"),
    "corrección · se puede borrar": (
        "create trigger tr_solicitud_correccion_no_borrar\n  before delete on public.solicitud_correccion",
        "create trigger tr_solicitud_correccion_no_borrar\n  before update of id on public.solicitud_correccion"),

    # ---------- mensajes ----------
    "mensaje · salen más de dos al día": (
        "    select v_par.mensajes_max_dia - count(*) into v_cupo",
        "    select 99 - count(*) into v_cupo"),
    "mensaje · el resumen no ahorra ninguno": (
        "then v_cola else v_cupo - 1 end;",
        "then v_cola else v_cupo end;"),
    "mensaje · salen a cualquier hora": (
        "  if not private.es_habil(v_hoy) or v_hora < v_par.mensajes_desde or v_hora > v_par.mensajes_hasta then",
        "  if not private.es_habil(v_hoy) then"),
    "mensaje · salen el sábado": (
        "  if not private.es_habil(v_hoy) or v_hora < v_par.mensajes_desde or v_hora > v_par.mensajes_hasta then",
        "  if v_hora < v_par.mensajes_desde or v_hora > v_par.mensajes_hasta then"),
    "mensaje · se generan el sábado": (
        "  if not private.es_habil(v_hoy) then\n    return 0;\n  end if;\n  select * into v_par",
        "  select * into v_par"),
    "mensaje · le llegan al ausente": (
        "where d.persona_id = m.persona_id and d.fecha = v_hoy and d.tipo = 'ausencia')",
        "where false)"),
    "mensaje · sube a dirección el primer día": ("    if r.atraso >= 5 then", "    if r.atraso >= 1 then"),
    "mensaje · la vencida insiste antes del tercer día": ("    if r.atraso >= 3 then", "    if r.atraso >= 2 then"),
    "mensaje · el registro del día sale desde la mañana": (
        "  if v_hora >= v_par.hora_registro_dia then", "  if true then"),
    "mensaje · el registro del día gasta cupo": (
        "9, false, '{plataforma}')", "9, true, '{plataforma}')"),
    "mensaje · tu semana sale a cualquier hora": (
        "  if v_hora >= v_par.hora_tu_semana\n", "  if true\n"),
    "mensaje · tu semana habla en tercera persona": (
        "from private.indicadores_de(r.id, v_hoy, true) i", "from private.indicadores_de(r.id, v_hoy) i"),
    "mensaje · lo caduco sale tarde": (
        "  update public.mensaje m set estado = 'descartado'\n  where m.estado = 'en_cola'",
        "  update public.mensaje m set estado = 'descartado'\n  where false and m.estado = 'en_cola'"),
    "mensaje · la devolución no avisa": (
        "  after insert on public.revision_diseno\n  for each row execute function private.mensajes_de_revision();",
        "  after update on public.revision_diseno\n  for each row execute function private.mensajes_de_revision();"),
    "mensaje · el cierre de fase no reconoce a nadie": (
        "  after update on public.proyecto_fase\n  for each row execute function private.mensajes_de_fase();",
        "  after update of id on public.proyecto_fase\n  for each row execute function private.mensajes_de_fase();"),
    "mensaje · varias piezas llegan una por una": (
        "    group by rv.id, t.proyecto_id, t.asignada_a, p.nombre, a.nombre\n",
        "    group by rv.id, t.proyecto_id, t.asignada_a, p.nombre, a.nombre, t.id\n"),
    "mensaje · dirección lee los de todos": (
        "  using (persona_id = (select private.persona_actual()) and estado in ('listo','enviado'));\n\ndrop policy if exists mensaje_edicion",
        "  using ((select private.es_direccion()) or persona_id = (select private.persona_actual()));\n\ndrop policy if exists mensaje_edicion"),
    "mensaje · la persona reescribe su mensaje": (
        "grant update (leido_en) on public.mensaje to authenticated;", "grant update on public.mensaje to authenticated;"),
    "carga · cualquiera ve la de todos": (
        "           or (v.si and (p.rol::text in", "           or (true and (p.rol::text in"),
    "carga · pesa lo que ya está en revisión": (
        "    where t.estado in ('asignada','en_curso','con_observaciones')\n  ),\n  tramo", "    where t.estado <> 'terminada'\n  ),\n  tramo"),
    "carga · el festivo cuenta como día de trabajo": (
        "    where private.es_habil(g.dia::date)\n  ),\n  capacidad", "    where extract(isodow from g.dia) < 6\n  ),\n  capacidad"),
    "carga · lo vencido deja de pesar": (
        "           greatest(coalesce(t.fecha_compromiso, lim.hoy), lim.hoy) as hasta", "           coalesce(t.fecha_compromiso, lim.hoy) as hasta"),
    "carga · media jornada cuenta como entera": (
        "coalesce(nullif(p.horas_semana, 0), 40) / 40.0 as jornada", "1.0 as jornada"),
    "carga · en fin de semana muestra la semana que ya pasó": (
        "case when extract(isodow from p_desde) >= 6 then 2 else 0 end", "0"),
    "carga · lo que se entrega un domingo no pesa": (
        "           case when x.n = 0 then private.sumar_habiles(x.hasta, 1) else x.hasta end as hasta", "           x.hasta as hasta"),
    # Se siembra en la ÚLTIMA migración: cada una termina quitándole todo a anon, y eso borraría el error.
    # Al agregar una migración nueva hay que mover este texto a ella.
    # Va en la última migración: cada una vuelve a quitarle todo a anon, y tapaba el error sembrado antes.
    "carga · la pide quien no tiene sesión": (
        # Va al final de la migración más reciente: las anteriores le quitan a anon todo lo que se le dé antes.
        "grant execute on all functions in schema public to service_role;\n",
        "grant execute on all functions in schema public to service_role;\ngrant execute on function public.carga_semanal(integer, date), private.carga_semanal_de(date, integer), private.hoy() to anon;\n"),
    "flujo · la fase se abre sin fecha de entrega": (
        "      new.fecha_compromiso := private.sumar_habiles(private.hoy(), new.dias_habiles_plazo);", "      null;"),
    "flujo · pisa la fecha puesta a mano": (
        "    if new.fecha_compromiso is null and new.dias_habiles_plazo is not null then", "    if new.dias_habiles_plazo is not null then"),
    "flujo · pisa al responsable puesto a mano": (
        "    if new.responsable_id is null then\n      select array_agg", "    if true then\n      select array_agg"),
    "flujo · adivina entre dos personas del mismo papel": (
        "      if cardinality(v_quienes) = 1 then", "      if cardinality(v_quienes) >= 1 then"),
    "flujo · ignora el papel que dice la plantilla": (
        "a.papel = coalesce(v_papel, 'dirige')", "a.papel = 'dirige'"),
    "flujo · la fase nace sin el plazo de su plantilla": (
        "    new.dias_habiles_plazo := coalesce(new.dias_habiles_plazo, v_plazo);", "    null;"),
    "flujo · responde alguien que no es del equipo":    a_aviso("D18 · % no hace parte del equipo"),
    "flujo · acepta un plazo de cero días": (
        "dias_habiles_plazo between 1 and 400", "dias_habiles_plazo >= 0"),
    "flujo · responde quien solo observa": (
        "    check (responsable_papel <> 'observa');", "    check (true);"),
    "típicas · la propuesta llega sin el trabajo que pide": (
        "         pt.dias_estimados, pt.por_espacio\n  from public.proponer_tareas", "         null::numeric, pt.por_espacio\n  from public.proponer_tareas"),
    "típicas · se crean sin el trabajo de la plantilla": (
        "       coalesce(nullif(e ->> 'dias_estimados', '')::numeric, v_pt.dias_estimados),", "       nullif(e ->> 'dias_estimados', '')::numeric,"),
    "típicas · se crean sin fecha de inicio": (
        "       nullif(e ->> 'fecha_inicio', '')::date,", "       null::date,"),
    "típicas · una fase sin tareas dice que terminó": (
        "    and count(t.id) > 0\n", "\n"),
    "típicas · una fase sin abrir dice que terminó": (
        "  f.estado in ('en_curso','en_revision')\n    and count(t.id) > 0", "  true\n    and count(t.id) > 0"),
    "típicas · dice que terminó con una tarea abierta": (
        "    and count(t.id) = count(t.id) filter (where t.estado = 'terminada') as trabajo_terminado", "    and count(t.id) filter (where t.estado = 'terminada') >= 3 as trabajo_terminado"),
    "típicas · acepta un trabajo de cero días": (
        "check (dias_estimados is null or dias_estimados between 0.1 and 120);\nexception when duplicate_object then null; end $$;\ncomment on column public.plantilla_tarea",
        "check (dias_estimados is null or dias_estimados >= 0);\nexception when duplicate_object then null; end $$;\ncomment on column public.plantilla_tarea"),
    "cierre · un dato se da por cumplido con solo marcarlo": a_aviso("D20 · «%» pide un dato"),
    "cierre · donde va un número entra una palabra":       a_aviso("D20 · «%» pide un número"),
    "cierre · entra una opción que el punto no tiene":     a_aviso("D20 · «%» pide una de sus opciones"),
    "cierre · donde va un enlace entra una frase":         a_aviso("D20 · «%» pide un enlace"),
    "cierre · entra una fecha que no existe": (
        "      perform new.valor::date;", "      null;"),
    "cierre · la lista de un tipo de proyecto se le pega a otro": (
        "    and (l.plantilla_id is null or l.plantilla_id = p.plantilla_id)\n", "\n"),
    "cierre · un punto quitado sigue impidiendo el cierre": (
        "       where c.id = p_chequeo and i.obligatorio and i.activo\n", "       where c.id = p_chequeo and i.obligatorio\n"),
    "cierre · la cuenta mezcla los puntos que no son obligatorios": (
        "      where c.id = v_chequeo and i.obligatorio and i.activo;", "      where c.id = v_chequeo and i.activo;"),
    "cierre · cualquiera pregunta qué le falta a una fase ajena": (
        "  where x.id = p_fase and x.proyecto_id in (select private.proyectos_visibles());", "  where x.id = p_fase;"),
    "cierre · abre la hoja quien no es del proyecto": (
        "  where f.id = p_fase and f.proyecto_id in (select private.proyectos_registro());", "  where f.id = p_fase;"),
    "cierre · una fase termina con dos hojas": (
        "  if v_id is not null then\n    return v_id;\n  end if;\n", ""),
    "cierre · no avisa que falta la dedicación": (
        "'dedicacion'::text, false, true, 'Nadie ha registrado tiempo en esta fase'::text;", "'dedicacion'::text, true, true, 'Nadie ha registrado tiempo en esta fase'::text;"),
    "ventas · el siguiente paso queda en el pasado":      a_aviso("V1 · El siguiente paso no puede quedar para una fecha que ya pasó"),
    "ventas · una oportunidad queda sin siguiente paso":  a_aviso("V1 · Una oportunidad abierta necesita su siguiente paso escrito"),
    "ventas · la venta ganada conserva su siguiente paso": (
        "    new.siguiente_paso_por := null;\n    return new;", "    return new;"),
    "ventas · las cargas del sistema se frenan": (
        "  v_sesion boolean := auth.uid() is not null;", "  v_sesion boolean := true;"),
    "ventas · se pasa a cotizar sin el reporte de la cita": (
        "and c.recurso_disponible is not null and c.proposito is not null) then\n    raise exception 'V3",
        "and c.recurso_disponible is not null and c.proposito is not null) then\n    raise notice 'V3"),
    "ventas · el reporte no pregunta si estaba quien decide": (
        "or nullif(p_datos ->> 'proposito', '') is null) then\n      raise exception 'V3",
        "or nullif(p_datos ->> 'proposito', '') is null) then\n      raise notice 'V3"),
    "ventas · el reporte no guarda quién decide": (
        "(v_o.id, p_cita, (p_datos ->> 'decisor_presente')::boolean,", "(v_o.id, p_cita, null,"),
    "ventas · se emite sin presentación":                 a_aviso("V2 · Una cotización no se emite sin la reunión de presentación agendada"),
    "ventas · se cotiza sin agendar la presentación":     a_aviso("V2 · Para cotizar, deje agendada la reunión de presentación"),
    "ventas · una cita se reporta dos veces":             a_aviso("V3 · Esa cita ya tiene su reporte"),
    "ventas · si no sigue, se pierde sin motivo":         a_aviso("M4 · Si no sigue, falta el motivo"),
    "ventas · la hora de la cita queda en otra zona": (
        "(trim(p_texto)::timestamp at time zone 'America/Bogota')", "(trim(p_texto)::timestamp at time zone 'UTC')"),
    "ventas · la cotización emitida no mueve la oportunidad": (
        "     where o.id = new.oportunidad_id and o.etapa < 'cotizacion_enviada';", "     where false;"),
    "ventas · el diseño ganado no abre la obra": (
        "  insert into public.oportunidad\n    (cliente_id, nombre, unidad, canal, etapa", "  return null;\n  insert into public.oportunidad\n    (cliente_id, nombre, unidad, canal, etapa"),
    "ventas · la obra no lleva el canal del diseño": (
        "'obra_propia', new.canal,", "'obra_propia', 'otro',"),
    "ventas · nacen dos obras de un mismo diseño": (
        "\n     or exists (select 1 from public.oportunidad h where h.origen_oportunidad_id = new.id) then", "\n     then"),
    "ventas · quien responde por la obra no la ve": (
        "         or responsable_id = (select private.persona_actual())\n         or siguiente_paso_por = (select private.persona_actual()));\ndrop policy if exists oportunidad_edicion",
        "         );\ndrop policy if exists oportunidad_edicion"),
    "ventas · las tarifas las escribe cualquiera de ventas": (
        "  with check ((select private.es_direccion()));\ndrop policy if exists tarifa_edicion",
        "  with check ((select private.tiene_rol('{socio,director,mercadeo}'::public.rol_persona[])));\ndrop policy if exists tarifa_edicion"),
    "ventas · la tarifa sugiere fuera de su rango": (
        "and p_area > t.area_desde and p_area <= t.area_hasta", "and p_area > t.area_desde"),
    "ventas · el día no muestra el primer contacto": (
        "where l.estado = 'nuevo' and l.primer_contacto_en is null\nunion all", "where false\nunion all"),
    "ventas · el día no muestra las citas sin reporte": (
        "where c.estado in ('agendada','reprogramada') and c.programada_para < now() - interval '1 hour'", "where false"),
    "ventas · la sesión no dice quién responde por una obra": (
        "                    or exists (select 1 from public.oportunidad o\n", "                    or false and exists (select 1 from public.oportunidad o\n"),
    "obra · cualquiera registra gastos en la obra": (
        "  if p_proyecto is null or p_proyecto not in (select private.proyectos_registro()) then", "  if p_proyecto is null then"),
    "obra · el gasto pagado no dice con qué":             a_aviso("O14 · Si ya se pagó, diga con qué"),
    "obra · el gasto no dice a quién se le paga":         a_aviso("O14 · Escriba a quién se le paga o quién factura"),
    "obra · el gasto queda a nombre de otro": (
        "          v_yo)\n  returning id into v_id;", "          (select pp.id from public.persona pp where pp.rol = 'socio' limit 1))\n  returning id into v_id;"),
    "obra · la factura acepta un número vacío": (
        "check (numero_factura is null or length(trim(numero_factura)) between 1 and 60);", "check (true);"),
    "obra · un documento se edita":                       a_aviso("O13 · Un documento registrado no se edita"),
    "obra · un documento se retira dos veces":            a_aviso("O13 · Ese documento ya estaba retirado"),
    "obra · el retiro queda a nombre de otro": (
        "    new.retirado_por := private.persona_actual();\n", ""),
    "obra · cualquiera pone documentos en la obra": (
        "  with check (proyecto_id in (select private.proyectos_registro())\n              and registrado_por = (select private.persona_actual()));\n-- Retira",
        "  with check (true);\n-- Retira"),
    "obra · el enlace del documento puede ser inseguro": (
        "check (enlace ~ '^https://')", "check (enlace ~ '^https?://')"),
    "obra · el tablero no avisa el gasto por aprobar": (
        "    when o.gastos_por_aprobar > 0 then", "    when false then"),
    "obra · lo pagado sale de la lista sin pagarse": (
        "where c.total - c.pagado > 0;", "where c.total > 0 and c.pagado = 0 and false;"),
    "obra · el flujo del mes cuenta las devoluciones como pagos": (
        "sum(case when m.naturaleza = 'devolucion' then -m.valor else m.valor end) as pagado,\n         count(*) filter (where m.naturaleza = 'cargo') as pagos",
        "sum(m.valor) as pagado,\n         count(*) filter (where m.naturaleza = 'cargo') as pagos"),
    "obra · la sesión deja ver obras a cualquiera": (
        "    'obras',        (select private.tiene_rol('{socio,director,financiero,residente}'::public.rol_persona[]))",
        "    'obras',        true"),
    "reservado · finanzas ve los préstamos": (
        "         and ((select private.ve_reservado()) or centro_costo_id not in (select private.centros_reservados())));",
        "         );"),
    "reservado · todo director los ve": (
        "  select private.tiene_rol('{socio}'::public.rol_persona[])\n      or exists", "  select private.tiene_rol('{socio,director}'::public.rol_persona[])\n      or exists"),
    "reservado · cualquiera se da el permiso":        a_aviso("F7 · Ver préstamos y socios lo autoriza un socio"),
    "reservado · cualquiera cambia qué es reservado": a_aviso("F7 · Qué categoría es reservada lo decide un socio"),
    "reservado · los créditos bancarios se ven":    (
        "         and (linea <> 'credito_bancario' or (select private.ve_reservado())));", ");"),
    "reservado · el proyecto de los socios se ve": (
        "         and (not reservado or (select private.ve_reservado())));", ");"),
    "reservado · se registra un préstamo desde la obra": a_aviso("F7 · Los préstamos y la cuenta de los socios no se registran desde la obra"),
    "reservado · la categoría reservada se lista": (
        "  using ((select private.es_interno()) and (not reservada or (select private.ve_reservado())));",
        "  using ((select private.es_interno()));"),
    "retiro · un retirado se modifica o se reabre":   a_aviso("O1 · Un adicional retirado no se modifica ni se decide"),
    "retiro · se retira uno que el cliente aprobó":   a_aviso("O1 · Solo se retira un adicional que el cliente no ha decidido"),
    "retiro · se retira sin razón":                   a_aviso("O1 · Escriba por qué se retira el adicional"),
    "retiro · los netos suman lo retirado": (
        "where a.retirado_en is null\ngroup by a.proyecto_id, p.codigo;", "group by a.proyecto_id, p.codigo;"),
    "retiro · el crédito sale de lo retirado": (
        "a.aprobacion <> 'rechazado' and a.retirado_en is null\n),", "a.aprobacion <> 'rechazado'\n),"),
    "retiro · el tablero cuenta lo retirado como pendiente": (
        "a.aprobacion = 'pendiente' and a.retirado_en is null) as adicionales_pendientes",
        "a.aprobacion = 'pendiente') as adicionales_pendientes"),
    "revisión · se pide a una tarea que no la requiere": a_aviso("R2 · «%» no requiere revisión: quien la tiene la entrega"),
    "revisión · uno se revisa su propia tarea":          a_aviso("R1 · La revisa alguien distinto de quien hace la tarea"),
    "revisión · se delega en alguien de fuera":          a_aviso("R1 · % no hace parte del equipo de este proyecto: no puede revisar"),
    "revisión · otro aprueba la que se delegó":          a_aviso("R3 · «%» la revisa %: se le delegó a esa persona"),
    "revisión · la delegada le aparece a todos": (
        "  and (t.revisor_id = (select private.persona_actual())\n       or (t.revisor_id is null and t.proyecto_id in (select private.proyectos_que_revisa())));",
        "  and t.proyecto_id in (select private.proyectos_que_revisa());"),
    "revisión · sin revisión no queda la hora de entrega": (
        "      new.revision_pedida_en := coalesce(new.revision_pedida_en, clock_timestamp());\n", ""),
    "papeles · quitar un papel saca del equipo": (
        "         and a.papel <> 'observa' and a.papel <> old.papel) then\n    return old;", "         and false) then\n    return old;"),
    "papeles · un solo papel por persona": (
        "primary key (persona_id, proyecto_id, papel);", "primary key (persona_id, proyecto_id);"),
    "estimado · acepta cero días": (
        "check (dias_estimados is null or dias_estimados between 0.1 and 120);", "check (dias_estimados is null or dias_estimados >= 0);"),
}


def correr(nombre, antes, despues):
    copia = Path(tempfile.mkdtemp(prefix="sici-error-"))
    try:
        shutil.copytree(RAIZ / "supabase", copia / "supabase")   # trae también supabase/pruebas
        # La última migración que trae el texto es la que rige: una función redefinida más adelante tapa a la anterior.
        archivo = next((copia / m for m in reversed(MIGRACIONES) if antes in (copia / m).read_text(encoding="utf-8")), None)
        if archivo is None:
            return nombre, None, "el texto a cambiar ya no está en las migraciones"
        archivo.write_text(archivo.read_text(encoding="utf-8").replace(antes, despues), encoding="utf-8")
        r = subprocess.run([sys.executable, str(copia / "supabase/pruebas/probar_contra_postgres.py")],
                           capture_output=True, text=True)
        # Un error que rompe la migración entera no demuestra nada: se descarta.
        if f"✓ {archivo.name} · primera pasada" not in r.stdout:
            return nombre, None, "el error sembrado rompió la migración: hay que sembrarlo de otra manera"
        fallas = re.findall(r"^  ✗ (.+?)(?:  · .*)?$", r.stdout.split("=" * 70)[0], flags=re.M)
        return nombre, fallas, ""
    finally:
        shutil.rmtree(copia, ignore_errors=True)


def main():
    a_la_vez = int(sys.argv[1]) if len(sys.argv) > 1 else 4
    print(f"{len(ERRORES)} errores sembrados, {a_la_vez} a la vez\n")
    sin_vigilar = []
    with ThreadPoolExecutor(a_la_vez) as grupo:
        for nombre, fallas, nota in grupo.map(lambda kv: correr(kv[0], *kv[1]), ERRORES.items()):
            if fallas is None:
                print(f"  ? {nombre}  · {nota}")
                sin_vigilar.append(nombre)
            elif not fallas:
                print(f"  ✗ {nombre}  · ninguna prueba se dio cuenta")
                sin_vigilar.append(nombre)
            else:
                print(f"  ✓ {nombre}  · lo detectó: {fallas[0]}" + (f" (y {len(fallas) - 1} más)" if len(fallas) > 1 else ""))
    print("\n" + "=" * 70)
    print(f"{len(ERRORES) - len(sin_vigilar)} de {len(ERRORES)} errores sembrados fueron detectados")
    for nombre in sin_vigilar:
        print(f"  ✗ {nombre}")
    print("=" * 70)
    sys.exit(1 if sin_vigilar else 0)


if __name__ == "__main__":
    main()
