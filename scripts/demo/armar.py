# -*- coding: utf-8 -*-
"""Deja en app/ una página de prueba (_prueba.html) que abre la aplicación real
con un Supabase de mentira. Sirve para recorrer todas las pantallas sin sesión.

    python3 scripts/demo/armar.py datos_de_exportar_vista_previa.json [Luisa|Mariana]
    python3 legado/servir_app.py   →  http://localhost:3000/_prueba.html
    python3 scripts/demo/armar.py --quitar

Con «--web» escribe solo los datos en public/demo/datos.json, para la
aplicación de Next.js en modo demo (NEXT_PUBLIC_MODO=demo), y no toca legado/app/.
"""
import json, sys
from pathlib import Path
AQUI = Path(__file__).resolve().parent; RAIZ = AQUI.parents[1]; APP = RAIZ / "legado/app"
WEB = "--web" in sys.argv; sys.argv = [a for a in sys.argv if a != "--web"]
if sys.argv[1] == "--quitar":
    for f in ("_prueba.html", "_supabase_falso.js", "_datos.json"): (APP / f).unlink(missing_ok=True)
    sys.exit()
D = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
dia = D["mi_dia"]["Mariana"]; t0 = dia[-1]["id"]
ID = dict(D["personas"], Allison="pAllison")
como = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] != "cierre" else "Luisa"   # con quién se entra: Luisa (dirige), Mariana (produce) o Allison (vende)
# Con varios proyectos (demo_proyectos.py) cada fila trae su proyecto_id; con uno solo (exportar_vista_previa.py) todo es de pr1.
VARIOS = "proyectos" in D
pid_de = lambda fila: fila.get("proyecto_id", "pr1")
accesos_de = lambda nombre: [a for a in D["accesos"] if a["persona_id"] == ID.get(nombre) and a["papel"] != "observa"]
mis_proyectos = [pid_de(a) for a in accesos_de(como)] if VARIOS else ["pr1"]
dirijo = [pid_de(a) for a in accesos_de(como) if a["papel"] == "dirige"] if VARIOS else (["pr1"] if como == "Luisa" else [])
nombre_proyecto = {p["id"]: p["nombre"] for p in D.get("proyectos", [])} or {"pr1": "Las Margaritas"}
gente = [{"id": ID[n], "nombre": n, "rol": r, "correo": n.lower() + "@ejemplo.local", "auth_user_id": "x" if n != "Teo" else None,
          "profesion": {"nombre": p}} for n, r, p in (("Luisa", "director", "Arquitecto"), ("Mariana", "practicante", "Estudiante en práctica"),
          ("Carlos", "practicante", "Estudiante en práctica"), ("Teo", "practicante", "Estudiante en práctica"), ("Daniel", "director_proyecto", "Ingeniero civil"),
          ("Allison", "mercadeo", "Mercadeo"))]


def ventas():
    """El embudo de ventas con datos inventados: ningún nombre es de un cliente real."""
    yo, lu, da = ID[como], ID["Luisa"], ID["Daniel"]
    ops = [
        {"id": "o1", "nombre": "Casa en Cerritos · familia Ríos", "etapa": "presupuesto_detallado", "unidad": "diseno_arquitectonico", "canal": "google_ads",
         "valor_estimado": 36800000, "area_m2": 140, "ciudad": "Pereira", "siguiente_paso": "Preparar la cotización para presentarla el 16 de octubre a las 10:00 a. m.",
         "siguiente_paso_en": "2026-10-15", "siguiente_paso_por": lu, "responsable_id": lu, "lead_id": "l1", "origen_oportunidad_id": None},
        {"id": "o2", "nombre": "Cabañas en Salento", "etapa": "cita_viabilidad", "unidad": "diseno_arquitectonico", "canal": "meta_ads",
         "valor_estimado": None, "area_m2": None, "ciudad": "Salento", "siguiente_paso": "Hacer la cita de viabilidad el 14 de octubre a las 3:00 p. m.",
         "siguiente_paso_en": "2026-10-14", "siguiente_paso_por": lu, "responsable_id": lu, "lead_id": "l2", "origen_oportunidad_id": None},
        {"id": "o3", "nombre": "Apartamento en Pinares · interiorismo", "etapa": "cotizacion_enviada", "unidad": "interiorismo", "canal": "referido",
         "valor_estimado": 5500000, "area_m2": 90, "ciudad": "Pereira", "siguiente_paso": "Saber qué decidió el cliente sobre la cotización",
         "siguiente_paso_en": "2026-10-10", "siguiente_paso_por": yo, "responsable_id": lu, "lead_id": "l3", "origen_oportunidad_id": None},
        {"id": "o4", "nombre": "Obra · Casa en La Florida", "etapa": "cita_viabilidad", "unidad": "obra_propia", "canal": "google_ads",
         "valor_estimado": None, "area_m2": 180, "ciudad": "Pereira", "siguiente_paso": "Ofrecer el presupuesto de obra",
         "siguiente_paso_en": "2026-11-13", "siguiente_paso_por": da, "responsable_id": da, "lead_id": None, "origen_oportunidad_id": "o9"},
        {"id": "o5", "nombre": "Edificio de cuatro pisos en Dosquebradas", "etapa": "negociacion", "unidad": "diseno_arquitectonico", "canal": "asistente_ia",
         "valor_estimado": 38200000, "area_m2": 280, "ciudad": "Dosquebradas", "siguiente_paso": "Firmar el contrato y recibir el anticipo",
         "siguiente_paso_en": "2026-10-16", "siguiente_paso_por": lu, "responsable_id": lu, "lead_id": "l5", "origen_oportunidad_id": None},
    ]
    citas = [
        {"id": "c1", "oportunidad_id": "o1", "tipo": "viabilidad", "estado": "realizada", "programada_para": "2026-10-09T20:00:00Z", "modalidad": "videollamada",
         "transcripcion_url": "https://docs.google.com/document/d/EJEMPLO"},
        {"id": "c2", "oportunidad_id": "o1", "tipo": "presentacion", "estado": "agendada", "programada_para": "2026-10-16T15:00:00Z", "modalidad": "videollamada"},
        {"id": "c3", "oportunidad_id": "o2", "tipo": "viabilidad", "estado": "agendada", "programada_para": "2026-10-13T20:00:00Z", "modalidad": "videollamada"},
        {"id": "c4", "oportunidad_id": "o3", "tipo": "presentacion", "estado": "realizada", "programada_para": "2026-10-03T14:00:00Z", "modalidad": "presencial"},
    ]
    nombre = {o["id"]: o for o in ops}
    for c in citas:
        o = nombre[c["oportunidad_id"]]
        c["oportunidad"] = {k: o[k] for k in ("nombre", "unidad", "valor_estimado", "area_m2")}
    return {
        "oportunidad": ops, "cita": citas,
        "lead": [{"id": "l1", "nombre": "Andrea Ríos", "telefono": "3001112233", "correo": "andrea@ejemplo.local", "canal": "google_ads", "como_nos_encontro": "asistente_ia",
                  "mensaje_inicial": "Tenemos un lote en Cerritos y queremos una casa de un piso."},
                 {"id": "l2", "nombre": "Jorge Salazar", "telefono": "3104445566", "canal": "meta_ads", "como_nos_encontro": "meta_ads", "mensaje_inicial": "Quiero tres cabañas para alquilar."},
                 {"id": "l3", "nombre": "Paula Gómez", "telefono": "3157778899", "canal": "referido", "como_nos_encontro": "referido"},
                 {"id": "l5", "nombre": "Constructora del Eje", "telefono": "3189990011", "canal": "asistente_ia", "como_nos_encontro": "asistente_ia"},
                 {"id": "l7", "nombre": "Mónica Herrera", "telefono": "3112223344", "ciudad": "Armenia", "canal": "google_ads", "como_nos_encontro": None,
                  "mensaje_inicial": "¿Cuánto cuesta el diseño de una casa de 200 m²?", "estado": "nuevo", "creado_en": "2026-10-14T13:20:00Z",
                  "primer_contacto_en": None, "motivo_descarte": None}],
        "contacto_lead": [],
        "calificacion": [{"oportunidad_id": "o1", "decisor_presente": True, "tiene_lote": "si", "recurso_disponible": "0_3_meses", "proposito": "vivienda",
                          "primera_cotizacion": False, "area_inicial_m2": 140}],
        "cotizacion": [{"id": "z3", "oportunidad_id": "o3", "numero": "31_26", "valor": 5500000, "estado": "emitida", "emitida_en": "2026-10-03", "vence_en": "2026-11-02"},
                       {"id": "z5", "oportunidad_id": "o5", "numero": "16_26", "valor": 38200000, "estado": "aceptada", "emitida_en": "2026-09-28", "vence_en": "2026-10-28"}],
        "v_ventas_hoy": [
            {"persona_id": None if como != "Allison" else yo, "orden": 1, "que": "primer_contacto", "lead_id": "l7", "oportunidad_id": None, "cita_id": None,
             "nombre": "Mónica Herrera", "lectura": "Escribió hace 2 horas y nadie le ha respondido", "urgente": True},
            {"persona_id": lu, "orden": 2, "que": "reporte_cita", "lead_id": None, "oportunidad_id": "o2", "cita_id": "c3", "nombre": "Cabañas en Salento",
             "lectura": "La cita de viabilidad fue el 13 de octubre y falta su reporte", "urgente": True},
            {"persona_id": lu, "orden": 4, "que": "siguiente_paso", "lead_id": None, "oportunidad_id": "o2", "cita_id": None, "nombre": "Cabañas en Salento",
             "lectura": "Hacer la cita de viabilidad el 14 de octubre a las 3:00 p. m.", "urgente": False},
            {"persona_id": yo if como != "Luisa" else ID["Allison"], "orden": 4, "que": "siguiente_paso", "lead_id": None, "oportunidad_id": "o3", "cita_id": None,
             "nombre": "Apartamento en Pinares · interiorismo", "lectura": "Saber qué decidió el cliente sobre la cotización · iba para el 10 de octubre", "urgente": True}],
        "v_embudo_ventas": [
            {"linea": "diseno", "etapa": "cita_viabilidad", "oportunidades": 1, "valor": 0, "atrasadas": 0, "dias_promedio": 2},
            {"linea": "diseno", "etapa": "presupuesto_detallado", "oportunidades": 1, "valor": 36800000, "atrasadas": 0, "dias_promedio": 5},
            {"linea": "diseno", "etapa": "cotizacion_enviada", "oportunidades": 1, "valor": 5500000, "atrasadas": 1, "dias_promedio": 11},
            {"linea": "diseno", "etapa": "negociacion", "oportunidades": 1, "valor": 38200000, "atrasadas": 0, "dias_promedio": 3},
            {"linea": "obra", "etapa": "cita_viabilidad", "oportunidades": 1, "valor": 0, "atrasadas": 0, "dias_promedio": 1}],
        "v_ritmo_ventas": [{"lectura": "En los últimos 90 días hubo 41 citas de viabilidad (y 9 no llegaron), 6 presentaciones de cotización y 2 ventas de diseño por $40.300.000: "
                                      "una venta por cada 20,5 citas. Para vender $60.000.000 al mes hacen falta unas 61 citas al mes; van 13,7."}],
        "tarifa_diseno": [{"id": "t1", "unidad": "diseno_arquitectonico", "area_desde": 110, "area_hasta": 150, "valor": 36800000, "alcance": "Arquitectónico y complementarios", "activa": True}],
        "rpc:nuevo_contacto": {"lead_id": "l7"}, "rpc:agendar_cita_de_lead": {"oportunidad_id": "o2", "cita_id": "c3"},
        "rpc:reporte_de_cita": "c2", "rpc:valor_sugerido": 36800000,
    }


def obras():
    """Dos obras con datos inventados: ningún nombre es de un cliente ni de un proveedor real."""
    yo, da = ID[como], ID["Daniel"]
    tablero = [
        {"id": "ob1", "codigo": "OBRA LA FLORIDA", "nombre": "Casa en La Florida", "estado": "activo", "unidad": "obra_propia",
         "carpeta_drive": "https://drive.google.com/drive/folders/1ObraEjemplo", "valor_contrato": 480000000, "fecha_inicio": "2026-07-06",
         "fecha_fin_prevista": "2027-01-29", "residente_id": da, "residente": "Daniel", "costo_proyectado": 268400000, "pagado": 241900000,
         "por_pagar": 26500000, "cobrado": 300000000, "gastos_por_aprobar": 1, "valor_por_aprobar": 4800000, "pendientes_abiertos": 3,
         "pendientes_vencidos": 1, "pendientes_por_verificar": 1, "dias_sin_bitacora": 2, "ultima_bitacora": "2026-10-15", "adicionales_pendientes": 2,
         "ultimo_gasto": "2026-10-15", "documentos": 3, "pct_contrato": 56,
         "lectura": "Lleva $268.400.000 de $480.000.000 del contrato (56 %) y debe $26.500.000.",
         "alerta": "Un gasto de $4.800.000 espera la aprobación de dirección."},
        {"id": "ob2", "codigo": "OBRA LOCAL CENTRO", "nombre": "Local comercial en el Centro", "estado": "pausado", "unidad": "obra_colega",
         "carpeta_drive": None, "valor_contrato": None, "fecha_inicio": "2026-05-04", "fecha_fin_prevista": None, "residente_id": None, "residente": None,
         "costo_proyectado": 61200000, "pagado": 61200000, "por_pagar": 0, "cobrado": 55000000, "gastos_por_aprobar": 0, "valor_por_aprobar": 0,
         "pendientes_abiertos": 0, "pendientes_vencidos": 0, "pendientes_por_verificar": 0, "dias_sin_bitacora": 0, "ultima_bitacora": "2026-08-28",
         "adicionales_pendientes": 0, "ultimo_gasto": "2026-09-02", "documentos": 0, "pct_contrato": None,
         "lectura": "Lleva $61.200.000 en gastos. Falta escribir el valor del contrato.", "alerta": None}]
    mov = lambda i, f, e, v, t, c, fac=None, ap="no_requiere", nat="cargo": {"id": i, "proyecto_id": "ob1", "fecha": f, "estado": e, "naturaleza": nat, "valor": v,
        "tercero_id": None, "tercero_nombre": t, "concepto": c, "numero_factura": fac, "aprobacion": ap, "registrado_por": da, "registrado_en": f + "T15:00:00Z"}
    movs = [mov("m1", "2026-10-15", "causacion", 4800000, "Aceros del Quindío", "Acero de refuerzo para placa", "FV-2231", "pendiente"),
            mov("m2", "2026-10-14", "causacion", 3150000, "Ferretería La Esquina", "Cemento, arena y bloque", "FE-118"),
            mov("m3", "2026-10-10", "pago", 9800000, "Cuadrilla Hernández", "Mampostería segundo piso, acta 4"),
            mov("m4", "2026-10-08", "pago", 160000, "Ferretería La Esquina", "Devolución de dos bultos", nat="devolucion"),
            mov("m5", "2026-10-03", "compromiso", 18550000, "Carpintería El Roble", "Puertas y closets, anticipo pendiente")]
    por_pagar = [
        {"raiz_id": "m1", "proyecto_id": "ob1", "centro_costo_id": "cc1", "categoria": "PROVEEDORES", "tercero": "Aceros del Quindío", "concepto": "Acero de refuerzo para placa",
         "fecha": "2026-10-15", "aprobacion": "pendiente", "numero_factura": "FV-2231", "facturado": True, "total": 4800000, "pagado": 0, "por_pagar": 4800000, "fecha_prevista": "2026-10-23"},
        {"raiz_id": "m2", "proyecto_id": "ob1", "centro_costo_id": "cc1", "categoria": "PROVEEDORES", "tercero": "Ferretería La Esquina", "concepto": "Cemento, arena y bloque",
         "fecha": "2026-10-14", "aprobacion": "no_requiere", "numero_factura": "FE-118", "facturado": True, "total": 3150000, "pagado": 0, "por_pagar": 3150000, "fecha_prevista": "2026-10-13"},
        {"raiz_id": "m5", "proyecto_id": "ob1", "centro_costo_id": "cc2", "categoria": "CONTRATISTAS", "tercero": "Carpintería El Roble", "concepto": "Puertas y closets, anticipo pendiente",
         "fecha": "2026-10-03", "aprobacion": "no_requiere", "numero_factura": None, "facturado": False, "total": 18550000, "pagado": 0, "por_pagar": 18550000, "fecha_prevista": "2026-11-20"}]
    meses = [("2026-07-01", 52300000, 9, 120000000), ("2026-08-01", 78900000, 14, 0), ("2026-09-01", 71400000, 12, 100000000), ("2026-10-01", 39300000, 6, 80000000)]
    return {
        "v_obra_tablero": tablero,
        "v_balance_centro_costo": [{"proyecto_id": "ob1", "categoria": c, "presupuesto": pr, "proyectado": v, "por_pagar": pp, "excluir_de_rentabilidad": False}
                                   for c, pr, v, pp in (("CONTRATISTAS", 150000000, 131200000, 18550000), ("PROVEEDORES", 110000000, 118700000, 7950000),
                                                        ("TRANSPORTE", 6000000, 4300000, 0), ("HONORARIOS", 20000000, 14200000, 0))],
        "v_movimiento_vigente": movs, "movimiento": [{"id": "nuevo", "aprobacion": "no_requiere"}],
        "v_obra_por_pagar": por_pagar,
        "v_obra_flujo_mes": [{"proyecto_id": "ob1", "mes": m, "pagado": p, "pagos": n, "cobrado": c} for m, p, n, c in meses],
        "categoria_costo": [{"id": i, "nombre": n, "tipo_gasto": t} for i, n, t in ((1, "CONTRATISTAS", "COSTOS OPERATIVOS"), (2, "PROVEEDORES", "COSTOS OPERATIVOS"),
                            (3, "TRANSPORTE", "COSTOS OPERATIVOS"), (4, "HONORARIOS", "GASTOS ADMINISTRATIVOS"))],
        "documento_obra": [{"id": "d1", "proyecto_id": "ob1", "tipo": "contrato", "titulo": "Contrato de obra firmado", "enlace": "https://drive.google.com/file/d/EJEMPLO1",
                            "fecha": "2026-06-30", "registrado_por": yo, "registrado_en": "2026-07-01T14:00:00Z", "retirado_en": None},
                           {"id": "d2", "proyecto_id": "ob1", "tipo": "licencia", "titulo": "Licencia de construcción", "enlace": "https://drive.google.com/file/d/EJEMPLO2",
                            "fecha": "2026-06-12", "registrado_por": da, "registrado_en": "2026-07-01T14:05:00Z", "retirado_en": None},
                           {"id": "d3", "proyecto_id": "ob1", "tipo": "poliza", "titulo": "Póliza de cumplimiento", "enlace": "https://drive.google.com/file/d/EJEMPLO3",
                            "fecha": "2026-07-02", "registrado_por": da, "registrado_en": "2026-07-03T09:00:00Z", "retirado_en": None}],
        "pendiente_obra": [
            {"id": "pe1", "proyecto_id": "ob1", "titulo": "Instalar el lavamanos del baño social", "tipo": "ejecucion", "prioridad": "alta", "ubicacion": "Baño social",
             "estado": "abierto", "fecha_compromiso": "2026-10-12", "responsable_id": da, "ejecutor_id": None, "creado_por": da},
            {"id": "pe2", "proyecto_id": "ob1", "titulo": "Radicar la solicitud de disponibilidad de energía", "tipo": "tramite", "prioridad": "bloqueante", "ubicacion": None,
             "estado": "abierto", "fecha_compromiso": "2026-10-24", "responsable_id": yo, "ejecutor_id": None, "creado_por": da},
            {"id": "pe3", "proyecto_id": "ob1", "titulo": "Resanar fisura en muro de la escalera", "tipo": "ejecucion", "prioridad": "normal", "ubicacion": "Escalera",
             "estado": "por_verificar", "fecha_compromiso": "2026-10-20", "responsable_id": da, "ejecutor_id": None, "creado_por": da},
            {"id": "pe4", "proyecto_id": "ob1", "titulo": "Limpiar el lote después de la fundida", "estado": "cerrado", "verificado_en": "2026-10-09T17:00:00Z", "verificado_por": yo}],
        "bitacora": [{"id": "b1", "proyecto_id": "ob1", "fecha": "2026-10-15", "personal_sitio": 9, "frente_trabajo": "Mampostería segundo piso", "clima": "Nublado",
                      "avance": "Se levantaron los muros de las alcobas 2 y 3.", "novedad": None, "registrado_por": da},
                     {"id": "b2", "proyecto_id": "ob1", "fecha": "2026-10-14", "personal_sitio": 8, "frente_trabajo": "Mampostería segundo piso", "clima": "Lluvia en la tarde",
                      "avance": "Muros de la alcoba principal.", "novedad": "La lluvia paró el trabajo desde las 2 p. m.", "registrado_por": da}],
        "v_bitacora_faltante": [{"proyecto_id": "ob1", "fecha": "2026-10-13"}, {"proyecto_id": "ob1", "fecha": "2026-10-10"}],
        "ingreso": [], "rpc:registrar_gasto": "nuevo", "parametro": [{"umbral_aprobacion": 2000000}],
    }


F = {
  "rpc:mi_sesion": {"persona_id": ID[como], "nombre": como, "rol": {"Luisa": "director", "Allison": "mercadeo"}.get(como, "practicante"), "es_direccion": como == "Luisa",
                    "asigna": como == "Luisa", "dirige": dirijo, "revisa": dirijo,
                    "registra": (mis_proyectos + ["ob1"] if como == "Luisa" else mis_proyectos) if como != "Allison" else [], "vende": como in ("Luisa", "Allison"),
                    "obras": como == "Luisa", "ve_dinero": como == "Luisa"},
  **ventas(),
  **obras(),
  **{"rpc:indicadores:" + ID[n]: [dict(i, orden=k) for k, i in enumerate(v, 1)] for n, v in D["indicadores_de"].items()},
  "lista_chequeo": D["listas_cierre"], "rpc:abrir_chequeo": D["hoja"], "rpc:punto_de_cierre": "nuevo",
  "chequeo": [{"id": D["hoja"], "lista_id": D["listas_cierre"][-1]["id"],
               "lista": next(l for l in D["listas_cierre"] if any(i["id"] in {r["item_id"] for r in D["respuestas"]} for i in l["lista_chequeo_item"]))}],
  "chequeo_respuesta": D["respuestas"], "rpc:falta_para_cerrar": D["falta"],
  "v_dedicacion_pendiente": D["sin_registrar"].get(como, []), "dedicacion": [],
  "rpc:tareas_tipicas": D["tipicas"], "rpc:crear_tareas": len(D["tipicas"]),
  # Con «cierre» como tercer dato, la fase en curso aparece con todo su trabajo terminado: sirve para ver ese aviso.
  "v_fase_avance": [dict(a, proyecto_id=pid_de(a), **({"terminadas": a["tareas"], "trabajo_terminado": True} if "cierre" in sys.argv and a["fase"] == "insight" else {})) for a in D["avance"]],
  "rpc:carga_semanal": D["carga_semanal"] if como == "Luisa" else D.get("carga_semanal_" + como.lower(), D["carga_semanal_mariana"]),
  "rpc:indicadores": [dict(i, orden=n) for n, i in enumerate(D["indicadores"]["Mariana"], 1)],
  "rpc:indicador_detalle": D["detalle"]["cumplio"], "rpc:abrir_proyecto": "pr1",
  "v_mi_dia": [dict(t, origen="diseno", fecha_compromiso=t.get("fecha_compromiso", "2026-10-19")) for t in D["mi_dia"].get(como, [] if como == "Allison" else dia)],   # Allison vende: no tiene tareas de diseño
  "v_cola_revision": [dict(c, tarea_id=c.get("tarea_id", t0), revision_pedida_en=c.get("revision_pedida_en", "2026-10-06T10:00:00Z")) for c in D["cola"]],
  "v_carga_equipo": D["carga"], "v_tarea_contexto": [{"para_que": D["contexto"].get(t0, "Hace parte de anteproyecto de Las Margaritas.")}],
  "proyecto": D["proyectos"] if VARIOS else [{"id": "pr1", "codigo": "LAS MARGARITAS", "nombre": "Las Margaritas", "tipo": "diseno", "unidad": "interiorismo", "fase": "anteproyecto",
                "estado": "activo", "carpeta_drive": "https://drive.google.com/drive/folders/1AbCdEf"}],
  "proyecto_fase": [dict(f, proyecto={"nombre": nombre_proyecto[f["proyecto_id"]]}, aprobada_cliente_en=None, aprobada_cliente_texto=None) for f in D["fases_mando"]] if VARIOS else
                   [dict(f, proyecto_id="pr1", horas_cotizadas=h["horas"], proyecto={"nombre": "Las Margaritas"},
                         exige_aprobacion_cliente=h["exige_aprobacion_cliente"], aprobada_cliente_en=None, aprobada_cliente_texto=None) for f, h in zip(D["fases_mando"], D["proyecto"]["fases"])],
  "acceso_proyecto": [{"persona_id": a["persona_id"], "proyecto_id": pid_de(a), "papel": a["papel"],
                       "persona": {"id": a["persona_id"], "nombre": a.get("nombre") or next(n for n, i in ID.items() if i == a["persona_id"]), "rol": a.get("rol", "practicante")}} for a in D["accesos"]],
  "persona": gente, "profesion": [{"id": "pf1", "nombre": "Arquitecto"}, {"id": "pf2", "nombre": "Ingeniero civil"}],
  # Quien no dirige ve las tareas de los proyectos en los que está, como lo hace la base.
  "tarea_diseno": [dict(a, descripcion=None, proyecto_id=pid_de(a), asignada_por=ID["Luisa"], bloqueada_por=a.get("bloqueada_por"), proyecto={"nombre": a["proyecto"]},
                         tiene={"nombre": a["persona"]}, asigno={"nombre": "Luisa"}, fase={"fase": a["fase"]} if a["fase"] else None)
                   for a in D["abiertas"] if como == "Luisa" or (pid_de(a) in mis_proyectos if VARIOS else a["persona"] == como)],
  "tarea_evento": [{"tipo": r["tipo"], "de": r["de"], "a": r["a"], "ocurrio_en": "2026-10-12T15:00:00Z", "persona": {"nombre": r["quien"]}} for r in D["rastro"]],
  "revision_diseno": [],
  "plantilla_proyecto": D["flujo"],
}
if WEB:
    salida = RAIZ / "public/demo/datos.json"; salida.parent.mkdir(parents=True, exist_ok=True)
    salida.write_text(json.dumps(F, ensure_ascii=False), encoding="utf-8")
    print("datos de la demo en", salida.relative_to(RAIZ), "· entra como", como); sys.exit()
(APP / "_datos.json").write_text(json.dumps(F, ensure_ascii=False), encoding="utf-8")
(APP / "_supabase_falso.js").write_text((AQUI / "supabase_falso.js").read_text(encoding="utf-8"), encoding="utf-8")
pagina = (APP / "index.html").read_text(encoding="utf-8").replace('<script type="module" src="app.js"></script>',
    '<script type="importmap">{"imports":{"https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm":"./_supabase_falso.js"}}</script>\n'
    '<script type="module" src="app.js"></script>')
assert "importmap" in pagina
(APP / "_prueba.html").write_text(pagina, encoding="utf-8")
print("lista: http://localhost:3000/_prueba.html · tarea de ejemplo", t0)
