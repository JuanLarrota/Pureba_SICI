# -*- coding: utf-8 -*-
"""Arma, sin base de datos, los datos de ejemplo que armar.py convierte en la
página de prueba: seis proyectos de diseño con sus fases y unas cuarenta tareas
repartidas entre el equipo, con fechas relativas a hoy para que las barras de
plazo (vencida, por vencer, a tiempo) siempre se vean.

Reemplaza a exportar_vista_previa.py cuando no hay Postgres a la mano. Lo que
calcula la base (carga semanal, «Mi día», cola de revisión, avance por fase) se
calcula aquí con las mismas reglas, de forma simplificada: sirve para ver, no
para probar reglas. Ningún nombre es de un cliente real.

    python3 scripts/demo/demo_proyectos.py datos.json
    python3 scripts/demo/armar.py datos.json Luisa --web      # o Mariana / Carlos / Teo
"""
import json, sys
from datetime import date, timedelta
from pathlib import Path

HOY = date.today()


def es_habil(d): return d.weekday() < 5


def habiles(n, desde=HOY):
    """El día hábil n contado desde hoy: 0 es hoy, negativo hacia atrás."""
    d, paso = desde, 1 if n >= 0 else -1
    while n:
        d += timedelta(days=paso)
        if es_habil(d): n -= paso
    return d


def dias_habiles(a, b):
    """Días hábiles después de a y hasta b (negativo si b es antes)."""
    if b < a: return -dias_habiles(b, a)
    n, d = 0, a
    while d < b:
        d += timedelta(days=1)
        if es_habil(d): n += 1
    return n


def iso(d): return d.isoformat() if d else None


def lunes(d): return d - timedelta(days=d.weekday())


GENTE = {"Luisa": ("director", "Arquitecto"), "Mariana": ("practicante", "Estudiante en práctica"), "Carlos": ("practicante", "Estudiante en práctica"),
         "Teo": ("practicante", "Estudiante en práctica"), "Daniel": ("director_proyecto", "Ingeniero civil")}
ID = {n: "p" + n for n in GENTE}
FASES = ["insight", "anteproyecto", "proyecto_final", "licencia", "presupuesto"]
ENTREGA = {"insight": "Principios y referentes validados", "anteproyecto": "Planos y volumetría para aprobación", "proyecto_final": "Planos arquitectónicos completos",
           "licencia": "Licencia de construcción radicada", "presupuesto": "Presupuesto de obra"}
HORAS = {"insight": 40, "anteproyecto": 80, "proyecto_final": 120, "licencia": 24, "presupuesto": 24}

# Cada proyecto: código, nombre, unidad y el estado de cada fase (con su fecha de entrega en días hábiles desde hoy, si aplica).
PROYECTOS = [
    ("pr1", "LAS MARGARITAS", "Las Margaritas", "interiorismo", {"insight": ("cerrada", -12), "anteproyecto": ("en_curso", 9), "proyecto_final": ("pendiente", None), "presupuesto": ("pendiente", None)}),
    ("pr2", "CASA CABRERA", "Casa Cabrera", "diseno_arquitectonico", {"insight": ("cerrada", -40), "anteproyecto": ("cerrada", -15), "proyecto_final": ("en_curso", -3), "licencia": ("pendiente", None), "presupuesto": ("pendiente", None)}),
    ("pr3", "CASA V", "Casa V", "diseno_arquitectonico", {"insight": ("en_curso", 4), "anteproyecto": ("pendiente", None), "proyecto_final": ("pendiente", None), "licencia": ("pendiente", None), "presupuesto": ("pendiente", None)}),
    ("pr4", "CASA GO", "Casa GO", "diseno_arquitectonico", {"insight": ("cerrada", -60), "anteproyecto": ("cerrada", -45), "proyecto_final": ("cerrada", -20), "licencia": ("cerrada", -8), "presupuesto": ("en_curso", 18)}),
    ("pr5", "COCOM", "COCOM", "diseno_arquitectonico", {"insight": ("cerrada", -22), "anteproyecto": ("en_revision", 2), "proyecto_final": ("pendiente", None), "presupuesto": ("pendiente", None)}),
    ("pr6", "TERRANO", "Terrano", "interiorismo", {"insight": ("pendiente", None), "anteproyecto": ("pendiente", None), "proyecto_final": ("pendiente", None), "presupuesto": ("pendiente", None)}),
]
RESPONSABLE_FASE = {"pr1": "Luisa", "pr2": "Luisa", "pr3": "Luisa", "pr4": "Luisa", "pr5": "Luisa", "pr6": None}

# Tareas: (proyecto, fase, título, quién, estado, inicio, entrega, estimado en días, prioridad). Inicio y entrega en días hábiles desde hoy.
TAREAS = [
    # Las Margaritas · anteproyecto en curso: lo que se está haciendo esta semana y la siguiente.
    ("pr1", "insight", "Levantamiento del apartamento", "Mariana", "terminada", -18, -14, 2, "bloqueante"),
    ("pr1", "insight", "Tablero de referentes", "Mariana", "terminada", -16, -12, 1, "normal"),
    ("pr1", "insight", "Planta de estado actual", "Carlos", "terminada", -15, -11, 2, "normal"),
    ("pr1", "anteproyecto", "Ajustar la planta con lo que pidió el cliente", "Mariana", "en_curso", -3, -1, 1, "alta"),
    ("pr1", "anteproyecto", "Enviar las medidas del mesón", "Mariana", "asignada", 0, 0, 0.3, "normal"),
    ("pr1", "anteproyecto", "Modelo · Cocina", "Mariana", "en_curso", -2, 2, 3, "normal"),
    ("pr1", "anteproyecto", "Modelo · Baño principal", "Mariana", "asignada", 3, 7, 3, "normal"),
    ("pr1", "anteproyecto", "Modelo · Sala", "Mariana", "en_revision", -6, -2, 3, "normal"),
    ("pr1", "anteproyecto", "Renders · Cocina", "Carlos", "asignada", 2, 6, 2, "normal"),
    ("pr1", "anteproyecto", "Renders · Sala", "Carlos", "asignada", 6, 9, 2, "normal"),
    ("pr1", "anteproyecto", "Detalle del mueble de televisión", "Carlos", "con_observaciones", -4, 3, 2, "normal"),
    ("pr1", "anteproyecto", "Planos, cortes y alzados", "Teo", "en_revision", -7, -1, 4, "normal"),
    ("pr1", "anteproyecto", "Imagen de la cocina para el taller", "Carlos", "asignada", 1, 2, 0.5, "normal"),
    ("pr1", "anteproyecto", "Presentación al cliente", "Luisa", "asignada", 8, 9, 1.5, "alta"),
    ("pr1", "anteproyecto", "Planos de carpintería", "Mariana", "asignada", 4, 12, 6, "normal"),
    ("pr1", "anteproyecto", "Cuadro de cantidades", "Mariana", "asignada", 13, 20, 4, "normal"),
    ("pr1", "anteproyecto", "Presupuesto de acabados", "Teo", "asignada", 10, 18, 5, "normal"),
    # Casa Cabrera · proyecto final vencido: dos tareas pasadas y una devuelta.
    ("pr2", "anteproyecto", "Fachadas y secciones", "Carlos", "terminada", -30, -17, 5, "normal"),
    ("pr2", "anteproyecto", "Volumetría de la cubierta", "Mariana", "terminada", -25, -16, 3, "normal"),
    ("pr2", "proyecto_final", "Planta de cimentación coordinada", "Carlos", "en_curso", -10, -4, 3, "bloqueante"),
    ("pr2", "proyecto_final", "Cortes por escalera", "Mariana", "asignada", -6, -2, 2, "normal"),
    ("pr2", "proyecto_final", "Detalles de carpintería metálica", "Carlos", "con_observaciones", -8, 1, 3, "normal"),
    ("pr2", "proyecto_final", "Cuadro de ventanería", "Mariana", "asignada", 1, 5, 2, "normal"),
    ("pr2", "proyecto_final", "Planos de redes básicas", "Carlos", "asignada", 3, 12, 5, "normal"),
    ("pr2", "proyecto_final", "Revisión con el ingeniero estructural", "Luisa", "asignada", 2, 2, 0.5, "alta"),
    # Casa V · insight en curso, todo a tiempo.
    ("pr3", "insight", "Reunión de principios con el cliente", "Luisa", "terminada", -5, -3, 0.5, "normal"),
    ("pr3", "insight", "Levantamiento del lote", "Mariana", "en_curso", -2, 3, 2, "normal"),
    ("pr3", "insight", "Referentes de casas de un piso", "Mariana", "asignada", 1, 4, 1, "normal"),
    ("pr3", "insight", "Análisis de normativa del lote", "Luisa", "asignada", 0, 4, 1, "normal"),
    # Casa GO · solo falta el presupuesto.
    ("pr4", "presupuesto", "Cantidades de obra", "Teo", "en_curso", -4, 8, 6, "normal"),
    ("pr4", "presupuesto", "Cotizaciones de acabados", "Teo", "asignada", 5, 15, 4, "normal"),
    ("pr4", "presupuesto", "Presupuesto consolidado", "Luisa", "asignada", 14, 18, 2, "alta"),
    # COCOM · anteproyecto en revisión: casi todo entregado.
    ("pr5", "anteproyecto", "Planta general del local", "Carlos", "terminada", -14, -8, 3, "normal"),
    ("pr5", "anteproyecto", "Imágenes del acceso", "Teo", "terminada", -9, -4, 2, "normal"),
    ("pr5", "anteproyecto", "Memoria descriptiva", "Teo", "en_revision", -5, -1, 1, "normal"),
    ("pr5", "anteproyecto", "Cuadro de áreas", "Carlos", "en_revision", -3, 0, 0.5, "normal"),
    ("pr5", "anteproyecto", "Presentación para el comité del centro comercial", "Luisa", "asignada", 1, 2, 1, "bloqueante"),
]
DEPENDE = {"Renders · Cocina": "Modelo · Cocina", "Imagen de la cocina para el taller": "Detalle del mueble de televisión", "Presupuesto consolidado": "Cotizaciones de acabados"}


def main():
    personas = [{"nombre": n, "id": ID[n], "rol": r, "profesion": p} for n, (r, p) in GENTE.items()]
    proyectos, fases, accesos = [], [], []
    for pid, codigo, nombre, unidad, estados in PROYECTOS:
        act = next((f for f, (e, _) in estados.items() if e in ("en_curso", "en_revision")), None)
        proyectos.append({"id": pid, "codigo": codigo, "nombre": nombre, "tipo": "diseno", "unidad": unidad, "fase": act, "estado": "activo",
                          "carpeta_drive": "https://drive.google.com/drive/folders/1Ejemplo" + pid if pid in ("pr1", "pr2") else None})
        for orden, (fase, (estado, n)) in enumerate(estados.items(), 1):
            fases.append({"id": f"f_{pid}_{fase}", "proyecto_id": pid, "fase": fase, "orden": orden, "estado": estado, "fecha_compromiso": iso(habiles(n)) if n is not None else None,
                          "entrega_cliente": ENTREGA[fase], "responsable_id": ID[RESPONSABLE_FASE[pid]] if RESPONSABLE_FASE[pid] and estado != "pendiente" else None,
                          "dias_habiles_plazo": {"insight": 10, "anteproyecto": 20, "proyecto_final": 30, "licencia": 15, "presupuesto": 15}[fase],
                          "horas_cotizadas": HORAS[fase], "exige_aprobacion_cliente": fase in ("anteproyecto", "proyecto_final")})
    # Quién hace parte de cada proyecto. Luisa dirige todos; los practicantes producen en los suyos.
    equipo = {"pr1": ["Mariana", "Carlos", "Teo"], "pr2": ["Mariana", "Carlos"], "pr3": ["Mariana"], "pr4": ["Teo"], "pr5": ["Carlos", "Teo"], "pr6": ["Mariana", "Teo"]}
    for pid, quienes in equipo.items():
        accesos.append({"persona_id": ID["Luisa"], "proyecto_id": pid, "papel": "dirige", "nombre": "Luisa", "rol": "director"})
        for q in quienes: accesos.append({"persona_id": ID[q], "proyecto_id": pid, "papel": "produce", "nombre": q, "rol": GENTE[q][0]})
    nombreP = {p["id"]: p["nombre"] for p in proyectos}; codigoP = {p["id"]: p["codigo"] for p in proyectos}

    tareas, porTitulo = [], {}
    for k, (pid, fase, tit, quien, estado, a, b, est, prio) in enumerate(TAREAS, 1):
        ini, fin = habiles(a), habiles(b)
        t = {"id": f"t{k:02d}", "titulo": tit, "estado": estado, "prioridad": prio, "fecha_inicio": iso(ini), "fecha_compromiso": iso(fin),
             "creada_en": (ini - timedelta(days=1)).isoformat() + "T14:00:00Z", "terminada_en": (fin + timedelta(days=1)).isoformat() + "T16:00:00Z" if estado == "terminada" else None,
             "revision_pedida_en": (habiles(min(b, 0) - 1) if estado == "en_revision" else None), "dias_estimados": est, "asignada_a": ID[quien], "persona": quien,
             "proyecto_id": pid, "proyecto": nombreP[pid], "fase_id": f"f_{pid}_{fase}", "fase": fase, "bloqueada_por": None,
             "proposito": f"Hace parte de {fase.replace('_', ' ')} de {nombreP[pid]}."}
        if t["revision_pedida_en"]: t["revision_pedida_en"] = t["revision_pedida_en"].isoformat() + "T10:00:00Z"
        tareas.append(t); porTitulo[tit] = t
    for tit, de in DEPENDE.items(): porTitulo[tit]["bloqueada_por"] = porTitulo[de]["id"]

    # Avance por fase, como v_fase_avance.
    avance = []
    for f in fases:
        ts = [t for t in tareas if t["fase_id"] == f["id"]]; term = [t for t in ts if t["estado"] == "terminada"]
        avance.append({"fase_id": f["id"], "proyecto_id": f["proyecto_id"], "fase": f["fase"], "estado": f["estado"], "tareas": len(ts), "terminadas": len(term),
                       "trabajo_terminado": f["estado"] in ("en_curso", "en_revision") and bool(ts) and len(ts) == len(term)})

    # La carga por semana, como carga_semanal: el trabajo de cada tarea se reparte parejo entre sus días hábiles; lo vencido cae entero en hoy.
    def carga(quienes, semanas=8):
        l0 = lunes(HOY); filas = []
        for q in quienes:
            suyas = [t for t in tareas if t["asignada_a"] == ID[q] and t["estado"] not in ("terminada", "en_revision")]
            for s in range(semanas):
                ini, fin = l0 + timedelta(days=7 * s), l0 + timedelta(days=7 * s + 6)
                hab = sum(1 for d in range(7) if es_habil(ini + timedelta(days=d)))
                oc, n, sin, venc = 0.0, 0, 0, 0
                for t in suyas:
                    a, b = date.fromisoformat(t["fecha_inicio"]), date.fromisoformat(t["fecha_compromiso"])
                    if b < HOY: a = b = HOY
                    dias = [a + timedelta(days=i) for i in range((b - a).days + 1) if es_habil(a + timedelta(days=i))] or [a]
                    en = [d for d in dias if ini <= d <= fin]
                    if not en: continue
                    n += 1
                    if t["dias_estimados"] is None: sin += 1
                    else: oc += t["dias_estimados"] * len(en) / len(dias)
                    if date.fromisoformat(t["fecha_compromiso"]) < HOY: venc += 1
                filas.append({"persona_id": ID[q], "nombre": q, "semana": iso(ini), "dias_habiles": float(hab), "dias_ocupados": round(oc, 2), "tareas": n, "sin_estimar": sin, "vencidas": venc})
        return filas

    # «Mi día» de cada quien, con los mismos grupos y frases de v_mi_dia.
    def mi_dia(q):
        filas = []
        for t in tareas:
            if t["asignada_a"] != ID[q] or t["estado"] == "terminada": continue
            fc = date.fromisoformat(t["fecha_compromiso"]); b = next((x for x in tareas if x["id"] == t["bloqueada_por"]), None)
            frena = ", ".join(sorted({x["persona"] for x in tareas if x["bloqueada_por"] == t["id"] and x["estado"] != "terminada" and x["asignada_a"] != t["asignada_a"]})) or None
            detenida = b is not None and b["estado"] != "terminada"
            orden = 6 if t["estado"] == "en_revision" else 1 if fc < HOY else 2 if fc == HOY else 3 if (frena or t["prioridad"] == "bloqueante") else 4 if t["estado"] == "con_observaciones" else 5
            grupo = {1: "Vencido", 2: "Para hoy", 3: "Alguien espera por ti" if frena else "No puede esperar", 4: "Te lo devolvieron", 5: "Lo que sigue", 6: "En manos de quien revisa"}[orden]
            dh = abs(dias_habiles(fc, HOY))
            if t["estado"] == "en_revision": lectura = "La tiene quien revisa desde el " + t["revision_pedida_en"][8:10] + "/" + t["revision_pedida_en"][5:7]
            elif detenida: lectura = f"Esperas a {b['persona']}: «{b['titulo']}»"
            elif fc < HOY: lectura = f"Se entregaba el {fc.strftime('%d/%m')}" + (f" y lleva {dh} día{'s' if dh != 1 else ''}" if dh > 0 else "") + (f". La espera {frena}" if frena else "")
            elif frena: lectura = f"La espera {frena}" + (" y se entrega hoy" if fc == HOY else f" · se entrega el {fc.strftime('%d/%m')}")
            elif fc == HOY: lectura = "Se entrega hoy"
            else: lectura = f"Se entrega el {fc.strftime('%d/%m')}, en {dh} día{'s' if dh != 1 else ''} hábil{'es' if dh != 1 else ''}"
            filas.append({"origen": "diseno", "id": t["id"], "proyecto_id": t["proyecto_id"], "proyecto": codigoP[t["proyecto_id"]], "titulo": t["titulo"], "estado": t["estado"],
                          "prioridad": t["prioridad"], "fecha_compromiso": t["fecha_compromiso"], "orden": orden, "grupo": grupo, "espera_a": b["persona"] if detenida else None,
                          "frena_a": frena, "para_que": t["proposito"], "lectura": lectura})
        return sorted(filas, key=lambda x: (x["orden"], x["fecha_compromiso"], x["titulo"]))

    # La cola de revisión de Luisa: lo que está en revisión y no es suyo. El acuerdo son 3 días hábiles.
    cola = []
    for t in tareas:
        if t["estado"] != "en_revision" or t["asignada_a"] == ID["Luisa"]: continue
        d = dias_habiles(date.fromisoformat(t["revision_pedida_en"][:10]), HOY); fuera = d > 3
        cola.append({"tarea_id": t["id"], "proyecto_id": t["proyecto_id"], "proyecto": codigoP[t["proyecto_id"]], "titulo": t["titulo"], "persona_id": t["asignada_a"], "persona": t["persona"],
                     "prioridad": t["prioridad"], "fecha_compromiso": t["fecha_compromiso"], "revision_pedida_en": t["revision_pedida_en"], "dias_habiles_esperando": d, "fuera_de_plazo": fuera,
                     "devoluciones": 0, "lectura": f"{t['persona']} espera hace {d} días hábiles; el acuerdo son 3" if fuera else f"{t['persona']} la dejó hoy" if d == 0 else f"{t['persona']} la dejó hace {'un día hábil' if d == 1 else str(d) + ' días hábiles'}"})

    def indicadores(q):
        mias = [t for t in tareas if t["asignada_a"] == ID[q]]; term = [t for t in mias if t["estado"] == "terminada"]; venc = [t for t in mias if t["estado"] not in ("terminada", "en_revision") and t["fecha_compromiso"] < iso(HOY)]
        return [{"indicador": "cumplio", "titulo": "Entregas a tiempo", "frase": f"Entregó {len(term)} de {len(term) + len(venc)} a tiempo en los últimos 30 días." if term or venc else "Todavía no tiene entregas cerradas.", "suficiente": bool(term)},
                {"indicador": "espera", "titulo": "Nadie esperó por su trabajo", "frase": "Nadie ha tenido que esperar por algo suyo." if not venc else f"Hay {len(venc)} entrega{'s' if len(venc) > 1 else ''} suya{'s' if len(venc) > 1 else ''} que alguien está esperando.", "suficiente": True}]

    flujo = [{"id": "pl1", "nombre": "Diseño", "tipo": "diseno", "descripcion": "Diseño arquitectónico e interiorismo", "activa": True,
              "plantilla_fase": [{"id": f"pf_{f}", "fase": f, "orden": i, "opcional": f == "licencia", "entrega_cliente": ENTREGA[f], "exige_chequeo": True, "exige_aprobacion_cliente": f in ("anteproyecto", "proyecto_final"),
                                  "exige_dedicacion": True, "dias_habiles_plazo": {"insight": 10, "anteproyecto": 20, "proyecto_final": 30, "licencia": 15, "presupuesto": 15}[f], "responsable_papel": "dirige",
                                  "plantilla_tarea": [{"id": "pt1", "titulo": "Modelo", "orden": 10, "activa": True, "por_espacio": True, "dias_plazo": 5, "dias_estimados": 3},
                                                      {"id": "pt2", "titulo": "Renders", "orden": 20, "activa": True, "por_espacio": True, "dias_plazo": 8, "dias_estimados": 2},
                                                      {"id": "pt3", "titulo": "Planos, cortes y alzados", "orden": 30, "activa": True, "por_espacio": False, "dias_plazo": 10, "dias_estimados": 4}] if f == "anteproyecto" else []}
                                 for i, f in enumerate(FASES, 1)]},
             {"id": "pl2", "nombre": "Obra", "tipo": "obra", "descripcion": "Obra propia o de un colega", "activa": True, "plantilla_fase": []}]
    lista = {"id": "lc1", "plantilla_id": "pl1", "fase": "anteproyecto", "version": 1,
             "lista_chequeo_item": [{"id": "li1", "orden": 1, "texto": "El cliente aprobó la volumetría", "tipo": "casilla", "opciones": None, "obligatorio": True, "activo": True},
                                    {"id": "li2", "orden": 2, "texto": "Cómo aprobó el cliente", "tipo": "opcion", "opciones": ["En reunión", "Por correo", "Por WhatsApp"], "obligatorio": True, "activo": True},
                                    {"id": "li3", "orden": 3, "texto": "Carpeta con los planos entregados", "tipo": "enlace", "opciones": None, "obligatorio": True, "activo": True}]}
    mueble = porTitulo["Detalle del mueble de televisión"]
    datos = {
        "hoy": iso(HOY), "personas": ID, "proyectos": proyectos, "fases_mando": fases, "accesos": accesos, "abiertas": tareas, "avance": avance,
        "proyecto": {"nombre": "Las Margaritas", "fases": [], "equipo": []},
        "mi_dia": {q: mi_dia(q) for q in GENTE}, "cola": cola,
        "carga_semanal": carga(["Luisa", "Mariana", "Carlos", "Teo"]), **{"carga_semanal_" + q.lower(): carga([q]) for q in ("Mariana", "Carlos", "Teo")},
        "carga": [{"nombre": q, "rol": GENTE[q][0], "abiertas": sum(1 for t in tareas if t["asignada_a"] == ID[q] and t["estado"] != "terminada"), "vencidas": 0, "sin_fecha": 0, "esta_semana": 0, "esperando_revision": 0, "lectura": ""} for q in GENTE],
        "indicadores": {"Mariana": indicadores("Mariana")}, "indicadores_de": {q: indicadores(q) for q in GENTE},
        "detalle": {"cumplio": [{"proyecto": t["proyecto"], "titulo": t["titulo"], "hecho": True, "a_favor": True, "excluida": False} for t in tareas if t["asignada_a"] == ID["Mariana"] and t["estado"] == "terminada"]},
        "contexto": {t["id"]: t["proposito"] for t in tareas},
        "rastro": [{"tipo": "creada", "de": None, "a": None, "quien": "Luisa", "cuando": "12/10 09:10"}, {"tipo": "estado", "de": "asignada", "a": "en_curso", "quien": "Carlos", "cuando": "13/10 08:30"},
                   {"tipo": "estado", "de": "en_curso", "a": "en_revision", "quien": "Carlos", "cuando": "15/10 17:05"}, {"tipo": "estado", "de": "en_revision", "a": "con_observaciones", "quien": "Luisa", "cuando": "16/10 10:40"}],
        "rastro_titulo": mueble["titulo"],
        "listas_cierre": [lista], "hoja": "hoja1", "respuestas": [{"item_id": "li1", "cumple": True, "valor": None}],
        "falta": [{"orden": 1, "que": "chequeo", "listo": False, "bloquea": True, "detalle": "Faltan 2 de 3 puntos obligatorios"}, {"orden": 2, "que": "cliente", "listo": False, "bloquea": True, "detalle": "Falta la aprobación del cliente"},
                  {"orden": 3, "que": "dedicacion", "listo": True, "bloquea": True, "detalle": "El equipo registró su dedicación"}, {"orden": 4, "que": "tareas", "listo": False, "bloquea": False, "detalle": "Hay tareas abiertas"}],
        "sin_registrar": {"Luisa": [{"fecha": iso(habiles(-1))}], "Mariana": [{"fecha": iso(habiles(-1))}, {"fecha": iso(habiles(-2))}]},
        "tipicas": [{"plantilla_tarea_id": "pt1", "orden": 10, "titulo": "Modelo · Comedor", "espacio": "Comedor", "proposito": "El modelo del espacio para revisarlo con el cliente.", "prioridad": "normal", "fecha_sugerida": iso(habiles(5)), "depende_de": None, "dias_estimados": 3, "por_espacio": True},
                    {"plantilla_tarea_id": "pt2", "orden": 20, "titulo": "Renders · Comedor", "espacio": "Comedor", "proposito": "Las imágenes para la presentación.", "prioridad": "normal", "fecha_sugerida": iso(habiles(8)), "depende_de": "pt1", "dias_estimados": 2, "por_espacio": True}],
        "flujo": flujo, "plantillas": [], "propuesta": [], "mensajes": {}, "en_cola": {},
    }
    Path(sys.argv[1]).write_text(json.dumps(datos, ensure_ascii=False, indent=1, default=str), encoding="utf-8")
    print("escrito", sys.argv[1], "·", len(proyectos), "proyectos,", len(tareas), "tareas, hoy", HOY)


if __name__ == "__main__":
    main()
