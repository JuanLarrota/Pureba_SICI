# -*- coding: utf-8 -*-
"""Arma un proyecto de ejemplo en una base temporal y exporta lo que la base le
entregaría a la aplicación: «Mi día», la cola de revisión, la carga del equipo,
los indicadores con su detalle y los mensajes.

Sirve para ver las frases reales antes de que exista la aplicación. Los datos
son de ejemplo; las reglas y las frases son las de las migraciones.

    .venv/bin/python scripts/base/exportar_vista_previa.py salida.json
"""
import json
import sys
import tempfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(RAIZ / "supabase/pruebas"))
import probar_contra_postgres as P   # noqa: E402
import pgserver                       # noqa: E402
import psycopg2                       # noqa: E402

GENTE = {  # nombre -> (rol, profesión)
    "Felipe": ("socio", "Arquitecto"), "Luisa": ("director", "Arquitecto"),
    "Mariana": ("practicante", "Estudiante en práctica"), "Carlos": ("practicante", "Estudiante en práctica"),
    "Teo": ("practicante", "Estudiante en práctica"), "Daniel": ("director_proyecto", "Ingeniero civil"),
}


def filas(cur, sql, params=None):
    cur.execute(sql, params)
    cols = [c.name for c in cur.description]
    return [dict(zip(cols, r)) for r in cur.fetchall()]


def main():
    servidor = pgserver.get_server(Path(tempfile.mkdtemp(prefix="sici-vista-")), cleanup_mode="delete")
    uri = servidor.get_uri()
    con = psycopg2.connect(uri); con.autocommit = True
    cur = con.cursor()
    for archivo in [P.STUB] + P.MIGRACIONES + [RAIZ / "supabase/semilla/040_plantillas.sql"]:
        ok, msg = P.aplicar(uri, archivo)
        assert ok, (archivo.name, msg)

    Q, S = {}, {}
    for n, (nombre, (rol, prof)) in enumerate(GENTE.items(), 1):
        uid = f"00000000-0000-4000-8000-{n:012d}"
        cur.execute("insert into auth.users (id, email, email_confirmed_at) values (%s, %s, now())", (uid, f"{nombre.lower()}@ejemplo.local"))
        Q[nombre] = P.uno(cur, """insert into persona (nombre, rol, es_interno, auth_user_id, correo, horas_semana, profesion_id, creado_en)
                                  select %s, %s, true, %s, %s, 40, pf.id, now() - interval '90 days'
                                  from profesion pf where pf.nombre = %s returning id""",
                          (nombre, rol, uid, f"{nombre.lower()}@ejemplo.local", prof))
        S[nombre] = P.sesion(uri, uid)[1]
    lu = S["Luisa"]

    lista = P.uno(cur, "insert into lista_chequeo (ambito, nombre, fase) values ('fase_diseno', 'EJEMPLO insight', 'insight') returning id")
    cur.execute("insert into lista_chequeo_item (lista_id, orden, texto) values (%s, 1, 'Principios validados con el cliente')", (lista,))

    plantilla = dict(P.todas(cur, "select nombre, id from plantilla_proyecto"))
    # Lista de cierre de EJEMPLO para insight de Diseño: puntos que se marcan y puntos que piden un dato.
    pf_ins = P.uno(cur, "select id from plantilla_fase where plantilla_id = %s and fase = 'insight'", (plantilla["Diseño"],))
    for texto, tipo, opciones, obligatorio in (("El cliente validó los principios del proyecto", "casilla", None, True),
                                               ("Cómo validó el cliente", "opcion", ["En reunión", "Por correo", "Por WhatsApp"], True),
                                               ("Fecha de la validación", "fecha", None, True),
                                               ("Área del proyecto en metros cuadrados", "numero", None, True),
                                               ("Carpeta con los referentes", "enlace", None, True),
                                               ("Se tomaron fotos del estado actual", "casilla", None, False)):
        lu.execute("select punto_de_cierre(%s, %s, %s, %s, %s)", (pf_ins, texto, tipo, opciones, obligatorio))
    # Plazos de EJEMPLO para ver el flujo: los reales los define dirección en la aplicación.
    for fase_ej, dias_ej in (("insight", 10), ("anteproyecto", 20), ("proyecto_final", 30), ("licencia", 15)):
        cur.execute("update plantilla_fase set dias_habiles_plazo = %s where plantilla_id = %s and fase = %s", (dias_ej, plantilla["Diseño"], fase_ej))
    marg = P.uno(lu, """select abrir_proyecto('LAS MARGARITAS', 'Las Margaritas', %s, 'interiorismo'::unidad_negocio,
                                              '{"insight": 40, "anteproyecto": 80, "proyecto_final": 120, "presupuesto": 24}'::jsonb,
                                              %s::jsonb, null, '{licencia}'::fase_proyecto[])""",
                 (plantilla["Diseño"], json.dumps([{"persona_id": Q[n], "papel": "produce"} for n in ("Mariana", "Carlos", "Teo")])))
    P.uno(lu, "select abrir_proyecto('OBRA KOLIBRI', 'Kolibri', %s, 'obra_colega'::unidad_negocio, '{}'::jsonb, %s::jsonb)",
          (plantilla["Obra"], json.dumps([{"persona_id": Q["Daniel"], "papel": "dirige"}])))
    ins, ante = [P.uno(cur, "select id from proyecto_fase where proyecto_id = %s and fase = %s", (marg, f)) for f in ("insight", "anteproyecto")]
    lu.execute("update proyecto_fase set estado = 'en_curso', fecha_compromiso = private.hoy() + 4 where id = %s", (ins,))

    # ---------- lo que ya pasó: tres semanas de trabajo de Mariana ----------
    def hecha(titulo, compromiso, entregada, prioridad="normal", devuelta=None, quien="Mariana"):
        tid = P.uno(cur, """insert into tarea_diseno (proyecto_id, fase_id, titulo, asignada_a, asignada_por, fecha_compromiso, prioridad)
                            values (%s, %s, %s, %s, %s, private.hoy() - %s, %s) returning id""",
                    (marg, ins, titulo, Q[quien], Q["Luisa"], compromiso, prioridad))
        return tid, entregada, devuelta

    def cerrar(tid, entregada, devuelta):
        cur.execute("update tarea_diseno set estado = 'en_revision' where id = %s", (tid,))
        if devuelta:
            cur.execute("insert into revision_diseno (tarea_id, revisor_id, resultado, observaciones) values (%s, %s, 'con_observaciones', %s)",
                        (tid, Q["Luisa"], devuelta))
            cur.execute("update tarea_diseno set estado = 'en_revision' where id = %s", (tid,))
        cur.execute("insert into revision_diseno (tarea_id, revisor_id, resultado) values (%s, %s, 'aprobada')", (tid, Q["Luisa"]))
        cur.execute("""update tarea_diseno set revision_pedida_en = now() - make_interval(days => %s),
                              terminada_en = now() - make_interval(days => %s) where id = %s""", (entregada, max(entregada - 1, 0), tid))

    lev = hecha("Levantamiento del apartamento", 15, 16, "bloqueante")
    ref = hecha("Tablero de referentes", 12, 12)
    dis = hecha("Planta de distribución", 9, 10, "alta")
    cor = hecha("Corte por la cocina", 9, 4, devuelta="El mesón no coincide con la planta")
    are = hecha("Cuadro de áreas", 4, 4)
    alz = hecha("Alzado de la sala", 2, 3)
    cur.execute("""insert into tarea_diseno (proyecto_id, fase_id, titulo, asignada_a, asignada_por, fecha_compromiso, bloqueada_por)
                   values (%s, %s, 'Planta de estado actual', %s, %s, private.hoy() - 11, %s),
                          (%s, %s, 'Imagen de la cocina para el taller', %s, %s, private.hoy() + 2, %s)""",
                (marg, ins, Q["Carlos"], Q["Luisa"], lev[0], marg, ins, Q["Carlos"], Q["Luisa"], cor[0]))
    for t in (lev, ref, dis, cor, are, alz):
        cerrar(*t)
    for nombre, dias in (("Mariana", (1, 2, 3, 4, 5, 6)), ("Carlos", (1, 2, 3)), ("Teo", (1, 2))):
        for d in dias:
            cur.execute("""insert into dedicacion (persona_id, fecha, bloque, proyecto_id, fase_id)
                           select %s, f, 'manana', %s, %s
                           from (select (private.hoy() - %s) as f) x where private.es_habil(f)
                           on conflict do nothing""", (Q[nombre], marg, ins, d + 1))

    # Lo que la historia dejó en la cola de mensajes ya pasó: no se muestra como de hoy.
    cur.execute("update mensaje set estado = 'descartado' where estado = 'en_cola' and texto not like 'Se aprobó «Levantamiento%'")

    # ---------- lo de hoy ----------
    prop = filas(lu, "select * from proponer_tareas(%s, %s)", (ante, ["Cocina", "Baño principal", "Sala"]))
    envio = [{"plantilla_tarea_id": str(p["plantilla_tarea_id"]), "espacio": p["espacio"], "fecha_compromiso": str(p["fecha_sugerida"]),
              "asignada_a": Q["Carlos"] if p["titulo"].startswith("Renders") else Q["Teo"] if p["titulo"].startswith("Planos") else Q["Mariana"]}
             for p in prop]
    lu.execute("select crear_tareas(%s, %s::jsonb)", (ante, json.dumps(envio)))
    # Fechas en días hábiles: n = 0 es hoy; negativo, tantos días hábiles atrás.
    suelta = """insert into tarea_diseno (id, proyecto_id, fase_id, titulo, asignada_a, asignada_por, fecha_compromiso, prioridad)
                select %s, %s, %s, %s, %s, %s,
                       case when %s < 0 then (select max(g::date) from generate_series(private.hoy() - 10, private.hoy() - 1, interval '1 day') g
                                              where private.es_habil(g::date))
                            when %s = 0 then private.hoy() else private.sumar_habiles(private.hoy(), %s) end, %s"""
    import uuid
    def nueva(c, titulo, quien, n, prioridad="normal"):
        tid = str(uuid.uuid4())
        c.execute(suelta, (tid, marg, ins, titulo, Q[quien], Q["Luisa"], n, n, n, prioridad))
        return tid
    nueva(cur, "Ajustar la planta con lo que pidió el cliente", "Mariana", -1, "alta")
    nueva(cur, "Enviar las medidas del mesón", "Mariana", 0)
    sala = P.uno(cur, "select id from tarea_diseno where titulo = 'Modelo · Sala'")
    cur.execute("update tarea_diseno set estado = 'en_revision' where id = %s", (sala,))
    cur.execute("update tarea_diseno set revision_pedida_en = now() - interval '6 days' where id = %s", (sala,))
    planos = P.uno(cur, "select id from tarea_diseno where titulo = 'Planos, cortes y alzados'")
    S["Teo"].execute("update tarea_diseno set estado = 'en_revision' where id = %s", (planos,))
    mueble = nueva(lu, "Detalle del mueble de televisión", "Carlos", 3)
    S["Carlos"].execute("update tarea_diseno set estado = 'en_revision' where id = %s", (mueble,))
    lu.execute("insert into revision_diseno (tarea_id, revisor_id, resultado, observaciones) values (%s, %s, 'con_observaciones', %s)",
               (mueble, Q["Luisa"], "Falta la altura de los entrepaños"))

    # ---------- el trabajo de las próximas semanas, con su estimado: lo que alimenta la carga ----------
    futura = """insert into tarea_diseno (proyecto_id, fase_id, titulo, asignada_a, asignada_por, fecha_inicio, fecha_compromiso, dias_estimados)
                values (%s, %s, %s, %s, %s, private.sumar_habiles(private.hoy(), %s), private.sumar_habiles(private.hoy(), %s), %s)"""
    for titulo_t, quien, a, b, dias in (("Planos de carpintería", "Mariana", 4, 12, 6), ("Cuadro de cantidades", "Mariana", 13, 20, 4),
                                        ("Imágenes para la presentación", "Carlos", 6, 9, 3), ("Presupuesto de acabados", "Teo", 10, 18, 5),
                                        ("Presentación al cliente", "Luisa", 8, 9, 1.5)):
        cur.execute(futura, (marg, ante, titulo_t, Q[quien], Q["Luisa"], a, b, dias))
    # Las que ya estaban abiertas reciben su estimado; una se queda sin medir, como pasará con las viejas.
    cur.execute("""update tarea_diseno
                      set dias_estimados = (array[0.5, 1, 2, 3])[1 + abs(hashtext(titulo)) % 4],
                          fecha_inicio = coalesce(fecha_inicio, fecha_compromiso - 4)
                    where estado <> 'terminada' and dias_estimados is null and titulo <> 'Enviar las medidas del mesón'""")

    cur.execute("update proyecto_fase set fecha_compromiso = private.sumar_habiles(private.hoy(), 9) where id = %s", (ante,))

    # Trabajo típico de EJEMPLO para las tareas de anteproyecto.
    cur.execute("update plantilla_tarea set dias_estimados = (array[3, 2, 4, 0.5])[least(orden / 10, 4)] where dias_estimados is null")

    # ---------- los mensajes del siguiente día hábil, a las 10 ----------
    dia = str(P.uno(cur, "select case when private.es_habil(private.hoy()) then private.hoy() else private.sumar_habiles(private.hoy(), 1) end"))
    cur.execute("select private.generar_mensajes(%s::timestamptz)", (f"{dia} 10:00:00-05",))
    cur.execute("select private.despachar_mensajes(%s::timestamptz)", (f"{dia} 10:00:00-05",))

    # La hoja de cierre de insight, a medio llenar.
    hoja = str(P.uno(S["Mariana"], "select abrir_chequeo(%s)", (ins,)))
    for texto, valor in (("El cliente validó los principios del proyecto", None), ("Cómo validó el cliente", "En reunión")):
        S["Mariana"].execute("""insert into chequeo_respuesta (chequeo_id, item_id, cumple, valor, verificado_por)
                                select %s, i.id, true, %s, %s from lista_chequeo_item i join chequeo c on c.lista_id = i.lista_id
                                where c.id = %s and i.texto = %s""", (hoja, valor, Q["Mariana"], hoja, texto))

    # ---------- lo que vería cada quien ----------
    modelo = P.uno(cur, "select id from tarea_diseno where titulo = 'Modelo · Cocina'")
    datos = {
        "hoy": str(P.uno(cur, "select private.hoy()")), "dia_mensajes": dia,
        "plantillas": filas(cur, """select pl.nombre, pl.descripcion,
                                           coalesce(array_agg(replace(pf.fase::text, '_', ' ') || case when pf.opcional then ' (si aplica)' else '' end
                                                              order by pf.orden) filter (where pf.id is not null), '{}') as fases
                                    from plantilla_proyecto pl left join plantilla_fase pf on pf.plantilla_id = pl.id
                                    group by pl.id order by min(pl.creada_en), pl.nombre"""),
        "proyecto": {"nombre": "Las Margaritas",
                     "fases": filas(cur, """select replace(fase::text, '_', ' ') as fase, horas_cotizadas::int as horas, estado::text,
                                                   entrega_cliente, exige_aprobacion_cliente
                                            from proyecto_fase where proyecto_id = %s order by orden""", (marg,)),
                     "equipo": filas(cur, """select p.nombre, a.papel::text, pf.nombre as profesion from acceso_proyecto a
                                             join persona p on p.id = a.persona_id left join profesion pf on pf.id = p.profesion_id
                                             where a.proyecto_id = %s order by p.nombre""", (marg,))},
        "propuesta": [{"titulo": p["titulo"], "proposito": p["proposito"], "prioridad": p["prioridad"],
                       "fecha": str(p["fecha_sugerida"])} for p in prop],
        "mi_dia": {n: filas(S[n], "select id::text, proyecto, titulo, estado, prioridad::text, grupo, orden, lectura, para_que "
                                  "from v_mi_dia order by orden, fecha_compromiso, titulo") for n in ("Mariana", "Carlos", "Teo")},
        "contexto": {str(r["tarea_id"]): r["para_que"] for r in filas(cur, "select tarea_id, para_que from v_tarea_contexto where proyecto_id = %s", (marg,))},
        "rastro": filas(cur, """select e.tipo, e.de, e.a, coalesce(p.nombre, 'el sistema') as quien,
                                       to_char(e.ocurrio_en at time zone 'America/Bogota', 'DD/MM HH24:MI') as cuando
                                from tarea_evento e left join persona p on p.id = e.persona_id
                                where e.tarea_id = %s order by e.ocurrio_en, e.id""", (mueble,)),
        "rastro_titulo": "Detalle del mueble de televisión",
        "cola": filas(lu, "select titulo, proyecto, persona, prioridad::text, fuera_de_plazo, devoluciones, lectura from v_cola_revision "
                          "order by fuera_de_plazo desc, revision_pedida_en"),
        "carga": filas(lu, "select nombre, rol::text, abiertas, vencidas, sin_fecha, esta_semana, esperando_revision, lectura "
                           "from v_carga_equipo order by vencidas desc, abiertas desc"),
        "indicadores": {"Mariana": filas(S["Mariana"], "select indicador, titulo, frase, suficiente from indicadores()"),
                        "Mariana_vista_por_Luisa": filas(lu, "select indicador, titulo, frase, suficiente from indicadores(%s)", (Q["Mariana"],)),
                        "Carlos": filas(S["Carlos"], "select indicador, titulo, frase, suficiente from indicadores()"),
                        "Luisa": filas(lu, "select indicador, titulo, frase, suficiente from indicadores()")},
        "detalle": {i: filas(S["Mariana"], "select proyecto, titulo, hecho, a_favor, excluida from indicador_detalle(%s)", (i,))
                    for i in ("cumplio", "primera", "espera", "hitos", "margen")},
        "detalle_luisa": filas(lu, "select proyecto, titulo, hecho, a_favor, excluida from indicador_detalle('revisiones')"),
        "mensajes": {n: filas(S[n], "select tipo, texto from mensaje order by liberado_en, creado_en") for n in ("Mariana", "Carlos", "Teo", "Luisa")},
        "personas": {n: str(i) for n, i in Q.items()},
        "carga_semanal": filas(lu, "select persona_id::text, nombre, semana, dias_habiles::float, dias_ocupados::float, tareas, sin_estimar, vencidas from carga_semanal(8)"),
        "carga_semanal_mariana": filas(S["Mariana"], "select persona_id::text, nombre, semana, dias_habiles::float, dias_ocupados::float, tareas, sin_estimar, vencidas from carga_semanal(8)"),
        "abiertas": filas(lu, """select t.id::text, t.titulo, t.estado::text, t.prioridad::text, t.fecha_inicio, t.fecha_compromiso, t.creada_en, t.terminada_en,
                                        t.dias_estimados::float, t.asignada_a::text, p.nombre as persona, pr.nombre as proyecto, f.fase::text as fase
                                 from tarea_diseno t join persona p on p.id = t.asignada_a join proyecto pr on pr.id = t.proyecto_id
                                 left join proyecto_fase f on f.id = t.fase_id
                                 where pr.id = %s and (t.estado <> 'terminada' or t.terminada_en >= now() - interval '14 days') order by t.fecha_compromiso""", (marg,)),
        "fases_mando": filas(cur, """select id::text, fase::text, orden, estado::text, fecha_compromiso, entrega_cliente, responsable_id::text, dias_habiles_plazo
                                     from proyecto_fase where proyecto_id = %s order by orden""", (marg,)),
        "listas_cierre": filas(cur, """select l.id::text, l.plantilla_id::text, l.fase::text, l.version,
                                              coalesce((select json_agg(json_build_object('id', i.id, 'orden', i.orden, 'texto', i.texto, 'tipo', i.tipo, 'opciones', i.opciones,
                                                         'obligatorio', i.obligatorio, 'activo', i.activo, 'requiere_evidencia', i.requiere_evidencia) order by i.orden)
                                                        from lista_chequeo_item i where i.lista_id = l.id), '[]'::json) as lista_chequeo_item
                                       from lista_chequeo l where l.ambito = 'fase_diseno' and l.activa"""),
        "hoja": hoja, "respuestas": filas(cur, "select item_id::text, cumple, valor from chequeo_respuesta where chequeo_id = %s", (hoja,)),
        "falta": filas(lu, "select orden, que, listo, bloquea, detalle from falta_para_cerrar(%s)", (ins,)),
        "sin_registrar": {n: filas(S[n], "select fecha from v_dedicacion_pendiente where persona_id = %s order by fecha desc", (Q[n],)) for n in ("Luisa", "Mariana")},
        "tipicas": filas(lu, """select plantilla_tarea_id::text, orden, titulo, espacio, proposito, prioridad::text, fecha_sugerida, depende_de::text,
                                       dias_estimados::float, por_espacio from tareas_tipicas(%s, %s)""", (ante, ["Comedor", "Estudio"])),
        "avance": filas(cur, "select fase_id::text, fase::text, tareas, terminadas, trabajo_terminado from v_fase_avance where proyecto_id = %s", (marg,)),
        "flujo": filas(cur, """select pl.id::text, pl.nombre, pl.tipo::text, pl.descripcion, pl.activa,
                                      coalesce((select json_agg(json_build_object('id', pf.id, 'fase', pf.fase, 'orden', pf.orden, 'opcional', pf.opcional,
                                                 'entrega_cliente', pf.entrega_cliente, 'exige_chequeo', pf.exige_chequeo,
                                                 'exige_aprobacion_cliente', pf.exige_aprobacion_cliente, 'exige_dedicacion', pf.exige_dedicacion,
                                                 'dias_habiles_plazo', pf.dias_habiles_plazo, 'responsable_papel', pf.responsable_papel,
                                                 'plantilla_tarea', coalesce((select json_agg(json_build_object('id', pt.id, 'titulo', pt.titulo, 'orden', pt.orden, 'activa', pt.activa, 'por_espacio', pt.por_espacio,
                                                                                                             'dias_plazo', pt.dias_plazo, 'dias_estimados', pt.dias_estimados))
                                                                              from plantilla_tarea pt where pt.plantilla_fase_id = pf.id), '[]'::json)) order by pf.orden)
                                                from plantilla_fase pf where pf.plantilla_id = pl.id), '[]'::json) as plantilla_fase
                               from plantilla_proyecto pl"""),
        "accesos": filas(cur, "select persona_id::text, papel::text from acceso_proyecto where proyecto_id = %s", (marg,)),
        "indicadores_de": {n: filas(lu, "select indicador, titulo, frase, suficiente from indicadores(%s)", (Q[n],)) for n in ("Mariana", "Carlos", "Teo", "Luisa", "Daniel")},
        "en_cola": {n: P.uno(cur, "select count(*) from mensaje where persona_id = %s and estado = 'en_cola'", (Q[n],)) for n in ("Mariana", "Carlos", "Teo", "Luisa")},
    }
    Path(sys.argv[1]).write_text(json.dumps(datos, ensure_ascii=False, indent=1, default=str), encoding="utf-8")
    print("escrito", sys.argv[1])


if __name__ == "__main__":
    main()
