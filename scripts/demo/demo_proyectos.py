# -*- coding: utf-8 -*-
"""Le pone proyectos, fases y tareas a la demostración, para que se vean los
tableros, las barras de plazo y la carga del equipo.

Los proyectos y las tareas salen de la hoja de seguimiento que lleva Luisa
(«Seguimiento tareas ESA 2026», octubre de 2026), con fechas ajustadas para que
haya de todo un lunes 19 de octubre: tareas vencidas, por vencer, en revisión y
terminadas. No trae plata, clientes ni proveedores.

Se corre después de armar.py, sobre el mismo archivo:

    python3 pruebas/app_simulada/armar.py vista.json Luisa
    python3 pruebas/app_simulada/demo_proyectos.py app/_datos.json Luisa
"""
import json, sys
from datetime import date, timedelta
from pathlib import Path

HOY = date(2026, 10, 19)
FESTIVOS = {date(2026, 11, 2), date(2026, 11, 16), date(2026, 12, 8), date(2026, 12, 25)}
SEMANAS = 8

ruta, como = Path(sys.argv[1]), (sys.argv[2] if len(sys.argv) > 2 else "Luisa")
F = json.loads(ruta.read_text(encoding="utf-8"))
gente = {p["nombre"]: p["id"] for p in F["persona"]}
if "Felipe" not in gente:
    F["persona"].insert(0, {"id": "pFelipe", "nombre": "Felipe", "rol": "socio", "correo": "felipe@ejemplo.local", "auth_user_id": "x", "profesion": {"nombre": "Arquitecto"}})
    gente["Felipe"] = "pFelipe"
ROL = {p["nombre"]: p["rol"] for p in F["persona"]}

# ---------- proyectos y fases ----------
DISENO = ["insight", "anteproyecto", "proyecto_final", "licencia", "presupuesto"]
PERITAJE = ["levantamiento", "informe", "presupuesto", "entrega_expediente"]
PROYECTOS = [
    # id, nombre, código, unidad, tipo, fases con (estado, fecha de entrega)
    ("pr1", "Las Margaritas", "LAS MARGARITAS", "interiorismo", "diseno", DISENO,
     [("cerrada", "2026-09-12"), ("cerrada", "2026-09-26"), ("en_curso", "2026-10-30"), ("pendiente", None), ("pendiente", None)]),
    ("pr2", "Casa Cabrera", "CASA CABRERA", "diseno_arquitectonico", "diseno", DISENO,
     [("cerrada", "2026-08-20"), ("cerrada", "2026-09-18"), ("en_curso", "2026-10-15"), ("pendiente", None), ("pendiente", None)]),
    ("pr3", "Casa V", "CASA V", "diseno_arquitectonico", "diseno", DISENO,
     [("cerrada", "2026-09-25"), ("en_curso", "2026-10-23"), ("pendiente", None), ("pendiente", None), ("pendiente", None)]),
    ("pr4", "Casa GO", "CASA GO", "diseno_arquitectonico", "diseno", DISENO,
     [("cerrada", "2026-08-29"), ("cerrada", "2026-09-19"), ("en_curso", "2026-10-28"), ("pendiente", None), ("pendiente", None)]),
    ("pr5", "COCOM · Alto del Nudo", "COCOM", "peritaje", "peritaje", PERITAJE,
     [("cerrada", "2026-09-25"), ("en_revision", "2026-10-16"), ("en_curso", "2026-10-26"), ("pendiente", None)]),
]
viejas = {f["fase"]: f for f in F.get("proyecto_fase", []) if f.get("proyecto_id") == "pr1"}   # las fases de pr1 que usan cierre y típicas
fases, fase_id = [], {}
for pid, nombre, cod, uni, tipo, nombres, estados in PROYECTOS:
    for orden, (fase, (estado, entrega)) in enumerate(zip(nombres, estados), 1):
        base = viejas.get(fase, {}) if pid == "pr1" else {}
        fid = base.get("id") or f"{pid}-{fase}"
        fase_id[(pid, fase)] = fid
        fases.append(dict(base, id=fid, proyecto_id=pid, fase=fase, orden=orden, estado=estado, fecha_compromiso=entrega,
                          entrega_cliente=base.get("entrega_cliente"), responsable_id=gente["Luisa"], dias_habiles_plazo=base.get("dias_habiles_plazo"),
                          horas_cotizadas=base.get("horas_cotizadas", 0), proyecto={"nombre": nombre}, exige_aprobacion_cliente=False,
                          aprobada_cliente_en=None, aprobada_cliente_texto=None))

# ---------- tareas (de la hoja de Luisa) ----------
# proyecto, fase, título, quién, inicio, entrega, estado, días que pide, prioridad
T = [
    ("pr1", "anteproyecto", "Modelo de la habitación principal", "Mariana", "2026-09-21", "2026-09-21", "terminada", 1, "normal"),
    ("pr1", "anteproyecto", "Renders, quince vistas", "Mariana", "2026-09-22", "2026-09-23", "terminada", 2, "normal"),
    ("pr1", "anteproyecto", "Presentación al cliente", "Mariana", "2026-09-24", "2026-09-24", "terminada", 1, "alta"),
    ("pr1", "proyecto_final", "Incluir la sala de té en la habitación principal", "Mariana", "2026-09-29", "2026-10-01", "terminada", 2, "normal"),
    ("pr1", "proyecto_final", "Diseño del walking closet", "Mariana", "2026-09-29", "2026-10-01", "terminada", 2, "normal"),
    ("pr1", "proyecto_final", "Render del baño principal", "Mariana", "2026-09-29", "2026-10-07", "terminada", 2, "normal"),
    ("pr1", "proyecto_final", "Organizar la presentación", "Mariana", "2026-10-05", "2026-10-07", "terminada", 1, "normal"),
    ("pr1", "proyecto_final", "Plano arquitectónico en AutoCAD", "Mariana", "2026-10-13", "2026-10-16", "en_curso", 3, "alta"),
    ("pr1", "proyecto_final", "Plano eléctrico", "Luisa", "2026-10-15", "2026-10-16", "en_curso", 2, "normal"),
    ("pr1", "proyecto_final", "Presupuesto del proyecto", "Luisa", "2026-10-15", "2026-10-23", "en_curso", 2, "normal"),
    ("pr1", "proyecto_final", "Enviar la información a Taller 7", "Mariana", "2026-10-19", "2026-10-19", "asignada", 0.5, "normal"),
    ("pr1", "proyecto_final", "Enviar los planos a Utopía para cotizar", "Mariana", "2026-10-19", "2026-10-21", "asignada", 0.5, "normal"),
    ("pr1", "proyecto_final", "Enviar la factura", "Luisa", "2026-10-16", "2026-10-16", "terminada", 0.3, "normal"),
    ("pr2", "proyecto_final", "Diseño de baños y muebles fijos", "Mariana", "2026-10-06", "2026-10-10", "en_revision", 3, "normal"),
    ("pr2", "proyecto_final", "Diseño de la cocina", "Mariana", "2026-10-06", "2026-10-13", "en_revision", 3, "normal"),
    ("pr2", "proyecto_final", "Planos de mobiliario", "Carlos", "2026-10-08", "2026-10-14", "en_revision", 3, "normal"),
    ("pr2", "proyecto_final", "Corregir los planos generales de la cocina", "Mariana", "2026-10-14", "2026-10-17", "con_observaciones", 1, "alta"),
    ("pr2", "proyecto_final", "Corregir la mancheta y enviarla a los diseñadores", "Luisa", "2026-10-16", "2026-10-20", "en_curso", 1, "bloqueante"),
    ("pr2", "proyecto_final", "Pedir las correcciones del hidrosanitario", "Luisa", "2026-10-19", "2026-10-22", "asignada", 0.5, "normal"),
    ("pr2", "proyecto_final", "Plano del muro de contención con mancheta", "Luisa", "2026-10-20", "2026-10-26", "asignada", 1, "normal"),
    ("pr2", "anteproyecto", "Planta y fachadas aprobadas", "Mariana", "2026-09-01", "2026-09-18", "terminada", 5, "normal"),
    ("pr3", "anteproyecto", "Modificar el plano para reducir áreas", "Carlos", "2026-09-28", "2026-09-29", "terminada", 2, "normal"),
    ("pr3", "anteproyecto", "Modelo 3D de las modificaciones", "Carlos", "2026-10-05", "2026-10-06", "terminada", 2, "normal"),
    ("pr3", "anteproyecto", "Habitación principal", "Carlos", "2026-10-05", "2026-10-07", "terminada", 2, "normal"),
    ("pr3", "anteproyecto", "Render de la cocina y espacios sociales", "Carlos", "2026-10-05", "2026-10-07", "terminada", 2, "normal"),
    ("pr3", "anteproyecto", "BBQ", "Carlos", "2026-10-14", "2026-10-16", "en_curso", 1, "normal"),
    ("pr3", "anteproyecto", "Sala de cine", "Carlos", "2026-10-15", "2026-10-20", "en_curso", 2, "normal"),
    ("pr3", "anteproyecto", "Turco", "Carlos", "2026-10-20", "2026-10-22", "asignada", 1, "normal"),
    ("pr3", "anteproyecto", "Modelo 3D del oratorio", "Carlos", "2026-10-21", "2026-10-23", "asignada", 2, "alta"),
    ("pr4", "proyecto_final", "Detalle de la escalera", "Carlos", "2026-09-23", "2026-09-23", "terminada", 1, "normal"),
    ("pr4", "proyecto_final", "Urbanismo del frente y posterior", "Carlos", "2026-09-25", "2026-09-25", "terminada", 1, "normal"),
    ("pr4", "proyecto_final", "Plano del ladrillo a la vista", "Teo", "2026-09-25", "2026-09-25", "terminada", 0.5, "normal"),
    ("pr4", "proyecto_final", "Detalle del baño principal con ventana y nichos", "Carlos", "2026-10-14", "2026-10-14", "asignada", 1, "alta"),
    ("pr4", "proyecto_final", "Diseño de la escalera del apartamento", "Carlos", "2026-10-14", "2026-10-16", "asignada", 2, "normal"),
    ("pr4", "proyecto_final", "Cuadro de áreas para la curaduría", "Mariana", "2026-10-22", "2026-10-28", "asignada", 1, "normal"),
    ("pr5", "levantamiento", "Levantamiento del predio", "Carlos", "2026-09-22", "2026-09-23", "terminada", 2, "normal"),
    ("pr5", "levantamiento", "Documentación fotográfica", "Carlos", "2026-09-22", "2026-09-24", "terminada", 1, "normal"),
    ("pr5", "informe", "Informe preliminar del estado actual", "Carlos", "2026-10-06", "2026-10-16", "en_revision", 3, "alta"),
    ("pr5", "informe", "Georreferenciar las fotos y los planos", "Teo", "2026-10-15", "2026-10-21", "en_curso", 1, "normal"),
    ("pr5", "presupuesto", "Presupuesto base con cantidades reales", "Daniel", "2026-10-13", "2026-10-24", "en_curso", 4, "normal"),
    ("pr5", "presupuesto", "Cotización del estudio de vulnerabilidad", "Felipe", "2026-10-20", "2026-10-22", "asignada", 1, "normal"),
]
nombre_de = {pid: n for pid, n, *_ in PROYECTOS}
tareas = []
for i, (pid, fase, tit, quien, ini, fin, est, dias, prio) in enumerate(T, 1):
    tareas.append({"id": f"t{i:02d}", "titulo": tit, "descripcion": None, "estado": est, "prioridad": prio, "fecha_inicio": ini, "fecha_compromiso": fin,
                   "creada_en": ini + "T13:00:00Z", "terminada_en": fin + "T22:00:00Z" if est == "terminada" else None, "dias_estimados": dias,
                   "proyecto_id": pid, "fase_id": fase_id[(pid, fase)], "asignada_a": gente[quien], "asignada_por": gente["Luisa"], "bloqueada_por": None,
                   "proyecto": {"nombre": nombre_de[pid]}, "tiene": {"nombre": quien}, "asigno": {"nombre": "Luisa"}, "fase": {"fase": fase}})

# ---------- quién está en cada proyecto ----------
papeles = {"pr1": [("Luisa", "dirige"), ("Mariana", "produce")], "pr2": [("Luisa", "dirige"), ("Mariana", "produce"), ("Carlos", "produce")],
           "pr3": [("Luisa", "dirige"), ("Carlos", "produce")], "pr4": [("Luisa", "dirige"), ("Carlos", "produce"), ("Teo", "produce"), ("Mariana", "produce")],
           "pr5": [("Luisa", "dirige"), ("Carlos", "produce"), ("Teo", "produce"), ("Daniel", "produce"), ("Felipe", "revisa")]}
accesos = [{"persona_id": gente[n], "proyecto_id": pid, "papel": pa, "persona": {"id": gente[n], "nombre": n, "rol": ROL[n]}} for pid, l in papeles.items() for n, pa in l]
mios = [pid for pid, l in papeles.items() if any(n == como for n, _ in l)] if como != "Luisa" else list(papeles)

# ---------- lo que la base calcularía ----------
def es_habil(d): return d.weekday() < 5 and d not in FESTIVOS
def habiles(a, b): return [a + timedelta(n) for n in range((b - a).days + 1) if es_habil(a + timedelta(n))]
lunes = HOY - timedelta(HOY.weekday())
semanas = [lunes + timedelta(7 * k) for k in range(SEMANAS)]
abiertas = [t for t in tareas if t["estado"] != "terminada"]

def carga_de(nombre):
    pid = gente[nombre]; filas = []
    for s in semanas:
        dias = habiles(s, s + timedelta(4)); ocup = 0.0; n = 0; sin = 0; venc = 0
        for t in abiertas:
            if t["asignada_a"] != pid or t["estado"] == "en_revision": continue
            ini, fin = date.fromisoformat(t["fecha_inicio"]), date.fromisoformat(t["fecha_compromiso"])
            if fin < HOY:   # lo vencido cae entero en el primer día
                if s == lunes: ocup += t["dias_estimados"] or 0; n += 1; venc += 1
                continue
            todos = habiles(max(ini, HOY), fin) or [fin]
            aqui = [d for d in todos if s <= d <= s + timedelta(6)]
            if aqui:
                n += 1
                if t["dias_estimados"] is None: sin += 1
                else: ocup += t["dias_estimados"] * len(aqui) / len(todos)
        filas.append({"persona_id": pid, "nombre": nombre, "semana": s.isoformat(), "dias_habiles": float(len(dias)), "dias_ocupados": round(ocup, 2),
                      "tareas": n, "sin_estimar": sin, "vencidas": venc})
    return filas

def corto(iso): return f"{int(iso[8:10])}/{iso[5:7]}"
def mi_dia(nombre):
    pid, filas = gente[nombre], []
    for t in abiertas:
        if t["asignada_a"] != pid: continue
        fc = t["fecha_compromiso"]
        if t["estado"] == "en_revision": g, o, l = "Esperando revisión", 6, "Pidió revisión; la tiene quien revisa"
        elif fc < HOY.isoformat(): g, o, l = "Vencido", 1, f"Se entregaba el {corto(fc)}"
        elif fc == HOY.isoformat(): g, o, l = "Para hoy", 2, "Se entrega hoy"
        else: g, o, l = "Lo que sigue", 5, f"Se entrega el {corto(fc)}"
        if t["prioridad"] == "bloqueante" and o > 1: g, o, l = "Alguien espera por ti", 3, f"La espera Mariana · se entrega el {corto(fc)}"
        filas.append({"id": t["id"], "proyecto": t["proyecto"]["nombre"].upper(), "titulo": t["titulo"], "estado": t["estado"], "prioridad": t["prioridad"],
                      "grupo": g, "orden": o, "lectura": l, "para_que": None, "origen": "diseno", "fecha_compromiso": fc, "proyecto_id": t["proyecto_id"]})
    return sorted(filas, key=lambda x: (x["orden"], x["fecha_compromiso"]))

avance = []
for f in fases:
    ts = [t for t in tareas if t["fase_id"] == f["id"]]
    hechas = sum(t["estado"] == "terminada" for t in ts)
    avance.append({"fase_id": f["id"], "proyecto_id": f["proyecto_id"], "fase": f["fase"], "tareas": len(ts), "terminadas": hechas,
                   "trabajo_terminado": bool(ts) and hechas == len(ts) and f["estado"] != "cerrada"})

cola = [{"titulo": t["titulo"], "proyecto": t["proyecto"]["nombre"].upper(), "persona": t["tiene"]["nombre"], "prioridad": t["prioridad"],
         "fuera_de_plazo": t["fecha_compromiso"] < "2026-10-15", "devoluciones": 0, "tarea_id": t["id"], "revision_pedida_en": t["fecha_compromiso"] + "T21:00:00Z",
         "lectura": f"{t['tiene']['nombre']} espera desde el {corto(t['fecha_compromiso'])}"} for t in abiertas if t["estado"] == "en_revision"]

visibles = lambda l: [x for x in l if x.get("proyecto_id") in mios]
F["proyecto"] = [{"id": pid, "codigo": cod, "nombre": n, "tipo": tipo, "unidad": uni, "fase": next((fz for fz, (e, _) in zip(nf, est) if e != "cerrada"), None),
                  "estado": "activo", "carpeta_drive": "https://drive.google.com/drive/folders/1AbCdEf" if pid == "pr1" else None}
                 for pid, n, cod, uni, tipo, nf, est in PROYECTOS if pid in mios]
F["proyecto_fase"] = visibles(fases)
F["tarea_diseno"] = visibles(tareas)
F["v_fase_avance"] = visibles(avance)
F["acceso_proyecto"] = visibles(accesos)
F["v_mi_dia"] = mi_dia(como) if como in gente else []
F["v_cola_revision"] = cola if como == "Luisa" else []
F["rpc:carga_semanal"] = [r for n in ("Luisa", "Mariana", "Carlos", "Teo", "Daniel", "Felipe") for r in carga_de(n)] if como == "Luisa" else (carga_de(como) if como in ("Mariana",) else [])
s = F["rpc:mi_sesion"]
if como == "Luisa": s.update(dirige=list(papeles), revisa=list(papeles), registra=list(papeles) + ["ob1"])
elif como in gente and como != "Allison": s.update(registra=mios)
ruta.write_text(json.dumps(F, ensure_ascii=False), encoding="utf-8")
print(f"{como}: {len(F['proyecto'])} proyectos · {len(F['tarea_diseno'])} tareas · {len(F['v_mi_dia'])} en su día · {len(F['rpc:carga_semanal'])} filas de carga")
