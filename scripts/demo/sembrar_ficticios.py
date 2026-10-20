"""Datos FICTICIOS para una base de pruebas del SICI (nombres, clientes y cifras inventados).

Uso (solo contra una base de pruebas; se niega a correr contra la de producción):
    SICI_DB=postgresql://... SICI_PRUEBAS=<id del proyecto de pruebas> python scripts/demo/sembrar_ficticios.py
Cada sección va en su propio punto de control: si una regla de la base la rechaza,
se dice cuál y las demás siguen.
"""
import os, sys, json, datetime as dt, psycopg2

dsn, pruebas = os.environ["SICI_DB"], os.environ["SICI_PRUEBAS"]
assert pruebas and pruebas in dsn, "La cadena de conexión no es la base de pruebas"
c = psycopg2.connect(dsn, connect_timeout=15); cur = c.cursor()
HOY = dt.date.today()
d = lambda n: HOY + dt.timedelta(days=n)

def uno(sql, *a):
    cur.execute(sql, a); r = cur.fetchone(); return r[0] if r else None

def seccion(nombre):
    def deco(f):
        cur.execute("savepoint s")
        try: f(); cur.execute("release savepoint s"); print("OK   ", nombre)
        except Exception as e:
            cur.execute("rollback to savepoint s"); print("FALLA", nombre, "->", str(e).strip().splitlines()[0][:300])
        return f
    return deco

# Las reglas de la base miran quién escribe: se actúa como el socio de pruebas.
yo = uno("select auth_user_id from public.persona where rol='socio' and auth_user_id is not null limit 1")
yo_p = uno("select id from public.persona where rol='socio' and auth_user_id is not null limit 1")
assert yo, "Primero crea la ficha del socio"
cur.execute("select set_config('request.jwt.claims', %s, false)", (json.dumps({"sub": str(yo), "role": "authenticated"}),))
cur.execute("select set_config('request.jwt.claim.sub', %s, false)", (str(yo),))
# Para dejar proyectos ya avanzados (fases cerradas, tareas terminadas) se apagan, solo durante
# la siembra y dentro de la misma transacción, las validaciones del flujo. Se reactivan al final.
VALIDACIONES = [("proyecto_fase", "tr_proyecto_fase_validar"), ("proyecto_fase", "tr_proyecto_fase_flujo"),
                ("tarea_diseno", "tr_tarea_diseno_validar"), ("oportunidad", "tr_oportunidad_validar"), ("oportunidad", "tr_oportunidad_ventas"), ("presupuesto", "tr_presupuesto_validar")]
for t, g in VALIDACIONES: cur.execute(f"alter table public.{t} disable trigger {g}")
P = {}
CAT = {}

@seccion("personas")
def _():
    gente = [("Laura Restrepo", "director", "laura.restrepo", 40), ("Camilo Ortiz", "director_proyecto", "camilo.ortiz", 40),
             ("Sofía Marín", "practicante", "sofia.marin", 30), ("Mateo Salazar", "practicante", "mateo.salazar", 30),
             ("Andrés Vélez", "residente", "andres.velez", 44), ("Valentina Giraldo", "mercadeo", "valentina.giraldo", 40),
             ("Daniela Cardona", "arquitecto", "daniela.cardona", 40)]
    for n, r, m, h in gente:
        cur.execute("insert into public.persona (nombre,rol,correo,es_interno,horas_semana) values (%s,%s,%s,true,%s) returning id", (n, r, f"{m}@ejemplo.test", h))
        P[n.split()[0]] = cur.fetchone()[0]
    for n, r in [("Constructora Los Pinos S.A.S.", "contratista"), ("Ferretería El Tornillo", "proveedor"), ("Estructuras Andina Ltda.", "profesional_externo"),
                 ("Eléctricos del Eje", "contratista"), ("Maderas y Acabados La Selva", "proveedor")]:
        cur.execute("insert into public.persona (nombre,rol,es_interno) values (%s,%s,false) returning id", (n, r)); P[n.split()[0]] = cur.fetchone()[0]
P["Juan"] = yo_p

@seccion("categorías de costo")
def _():
    cats = [("Materiales de obra", "COSTOS OPERATIVOS", True), ("Mano de obra", "COSTOS OPERATIVOS", True), ("Subcontratos", "COSTOS OPERATIVOS", True),
            ("Honorarios de diseño", "COSTOS OPERATIVOS", True), ("Transporte y fletes", "COSTOS OPERATIVOS", True), ("Equipos y herramienta", "COSTOS OPERATIVOS", True),
            ("Nómina administrativa", "GASTOS ADMINISTRATIVOS", False), ("Arriendo de oficina", "GASTOS ADMINISTRATIVOS", False),
            ("Publicidad y pauta", "GASTOS ADMINISTRATIVOS", False), ("Software y licencias", "GASTOS ADMINISTRATIVOS", False)]
    for i, (n, t, dire) in enumerate(cats, 1):
        cur.execute("insert into public.categoria_costo (nombre,tipo_gasto,es_directo,orden) values (%s,%s,%s,%s) returning id", (n, t, dire, i)); CAT[n] = cur.fetchone()[0]

@seccion("clientes")
def _():
    for n, t, ciu in [("Familia Henao Duque", "persona_natural", "Pereira"), ("Inversiones Bahía S.A.S.", "empresa", "Cali"), ("Carlos Mejía", "persona_natural", "Manizales"),
                      ("Café Origen S.A.S.", "empresa", "Pereira"), ("Familia Bedoya Ríos", "persona_natural", "Armenia"), ("Logística Cumbre S.A.S.", "empresa", "Pereira")]:
        cur.execute("insert into public.cliente (nombre,tipo,ciudad) values (%s,%s,%s) returning id", (n, t, ciu)); P[n.split()[0] + n.split()[1]] = cur.fetchone()[0]

PL = {t: uno("select id from public.plantilla_proyecto where tipo=%s and activa and nombre <> 'Montaje de interiores' order by nombre limit 1", t) for t in ("diseno", "obra", "consultoria", "peritaje")}
PROY = {}
@seccion("proyectos")
def _():
    filas = [("D-101", "Casa Los Almendros", "diseno_arquitectonico", "diseno", "anteproyecto", "FamiliaHenao", "Camilo", 480e6, 320, "Pereira", -60, 120),
             ("D-102", "Apartamento Torre Alba", "interiorismo", "diseno", "proyecto_final", "CarlosMejía", "Daniela", 95e6, 110, "Manizales", -90, 30),
             ("D-103", "Centro Médico Pinar", "diseno_arquitectonico", "diseno", "insight", "InversionesBahía", "Camilo", 760e6, 900, "Cali", -10, 200),
             ("O-201", "Bodega La Cumbre", "obra_propia", "obra", "ejecucion", "LogísticaCumbre", "Camilo", 1350e6, 1400, "Pereira", -120, 90),
             ("O-202", "Local Café Origen", "obra_propia", "obra", "ejecucion", "CaféOrigen", "Daniela", 310e6, 140, "Pereira", -45, 60),
             ("C-301", "Diagnóstico estructural Edificio Mirador", "consultoria", "consultoria", "informe", "FamiliaBedoya", "Daniela", 38e6, 600, "Armenia", -20, 25)]
    for cod, nom, uni, tip, fase, cli, resp, val, area, ciu, ini, fin in filas:
        cur.execute("""insert into public.proyecto (codigo,nombre,unidad,tipo,fase,cliente_id,responsable_id,residente_id,valor_contrato,area_m2,ciudad,fecha_inicio,fecha_fin_prevista,plantilla_id,canal,pct_administracion,pct_utilidad,pct_imprevistos)
                       values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'referido',0.08,0.12,0.05) returning id""",
                    (cod, nom, uni, tip, fase, P.get(cli), P[resp], P["Andrés"] if tip == "obra" else None, val, area, ciu, d(ini), d(fin), PL.get(tip)))
        PROY[cod] = cur.fetchone()[0]


@seccion("fases de cada proyecto")
def _():
    for cod, pid in PROY.items():
        tipo = uno("select tipo from public.proyecto where id=%s", pid)
        cur.execute("select public.aplicar_plantilla(%s,%s,'{}'::jsonb)", (pid, PL[tipo]))
        # la fase actual del proyecto queda en curso y las anteriores cerradas
        fase = uno("select fase from public.proyecto where id=%s", pid)
        ord_ = uno("select orden from public.proyecto_fase where proyecto_id=%s and fase=%s", pid, fase)
        if ord_ is not None:
            cur.execute("update public.proyecto_fase set estado='cerrada', cerrada_en=now(), cerrada_por=%s where proyecto_id=%s and orden<%s", (P['Camilo'], pid, ord_))
            cur.execute("update public.proyecto_fase set estado='en_curso', fecha_inicio=%s, fecha_compromiso=%s where proyecto_id=%s and orden=%s", (d(-15), d(20), pid, ord_))

@seccion("equipo de cada proyecto")
def _():
    equipo = {"D-101": ["Camilo", "Sofía", "Mateo", "Daniela"], "D-102": ["Daniela", "Mateo", "Sofía", "Camilo"], "D-103": ["Camilo", "Daniela", "Sofía"],
              "O-201": ["Camilo", "Andrés"], "O-202": ["Daniela", "Andrés"], "C-301": ["Daniela"]}
    for cod, gente in equipo.items():
        for i, n in enumerate(gente):
            papel = "dirige" if i == 0 else "produce"
            cur.execute("insert into public.acceso_proyecto (persona_id,proyecto_id,papel,nivel) values (%s,%s,%s,'registro')", (P[n], PROY[cod], papel))
        if cod in ("D-101", "D-102", "D-103") and "Camilo" in gente and gente[0] != "Camilo":
            cur.execute("insert into public.acceso_proyecto (persona_id,proyecto_id,papel,nivel) values (%s,%s,'revisa','aprobacion')", (P["Camilo"], PROY[cod]))
        elif cod in ("D-101", "D-103"):
            cur.execute("insert into public.acceso_proyecto (persona_id,proyecto_id,papel,nivel) values (%s,%s,'revisa','aprobacion')", (P["Camilo"], PROY[cod]))

@seccion("tareas de diseño")
def _():
    plan = [("D-101", "anteproyecto", [("Levantamiento topográfico y de arborización", "Daniela", "terminada", -40, -30), ("Programa arquitectónico por espacios", "Camilo", "terminada", -30, -20),
                                        ("Zonificación y volumetría", "Sofía", "en_revision", -18, -2), ("Planta arquitectónica primer piso", "Sofía", "en_curso", -5, 6),
                                        ("Planta arquitectónica segundo piso", "Mateo", "asignada", 2, 10), ("Fachadas y cortes", "Mateo", "asignada", 8, 16),
                                        ("Render de sala y comedor", "Sofía", "con_observaciones", -10, -1)]),
            ("D-102", "proyecto_final", [("Planos de carpintería de cocina", "Mateo", "en_curso", -6, 4), ("Especificación de acabados", "Daniela", "en_revision", -9, -1),
                                          ("Plano de iluminación", "Sofía", "asignada", 3, 12), ("Cuadro de mobiliario", "Mateo", "terminada", -20, -8)]),
            ("D-103", "insight", [("Visita al lote y registro fotográfico", "Camilo", "terminada", -9, -6), ("Normativa y usos del suelo", "Daniela", "en_curso", -5, 3),
                                   ("Referentes y lineamientos del cliente", "Sofía", "asignada", 0, 8)])]
    for cod, fase, tareas in plan:
        fid = uno("select id from public.proyecto_fase where proyecto_id=%s and fase=%s", PROY[cod], fase)
        for titulo, quien, est, a, b in tareas:
            cur.execute("""insert into public.tarea_diseno (proyecto_id,fase_id,titulo,asignada_a,asignada_por,estado,fecha_inicio,fecha_compromiso,dias_estimados,proposito,requiere_revision,revisor_id)
                           values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                        (PROY[cod], fid, titulo, P[quien], P["Juan"], "asignada", d(a), d(b), max(1, b - a), "Dato de ejemplo para recorrer la aplicación", quien != "Camilo", P["Camilo"] if quien != "Camilo" else None))
            if est != "asignada":
                cur.execute("update public.tarea_diseno set estado=%s where proyecto_id=%s and titulo=%s", (est, PROY[cod], titulo))

@seccion("ventas")
def _():
    leads = [("Marcela Quintero", "google_ads", "nuevo"), ("Julián Arboleda", "referido", "contactado"), ("Paola Jaramillo", "instagram_organico", "calificado"),
             ("Esteban Cano", "meta_ads", "descartado"), ("Ricardo Osorio", "web_organico", "nuevo")]
    for n, canal, est in leads:
        cur.execute("insert into public.lead (canal,nombre,telefono,ciudad,estado,asignado_a,mensaje_inicial,motivo_descarte) values (%s,%s,'3000000000','Pereira',%s,%s,'Quiero cotizar el diseño de mi casa',%s)", (canal, n, est, P["Valentina"], "Fuera de zona" if est == "descartado" else None))
    ops = [("Casa campestre Santa Rosa", "diseno_arquitectonico", "referido", "cita_viabilidad", 420e6), ("Remodelación apartamento Cerritos", "interiorismo", "instagram_organico", "presupuesto_detallado", 85e6),
           ("Edificio de oficinas Centro", "diseno_arquitectonico", "google_ads", "cotizacion_enviada", 640e6), ("Restaurante El Mirador", "obra_propia", "cliente_recurrente", "negociacion", 520e6),
           ("Vivienda unifamiliar Dosquebradas", "diseno_arquitectonico", "meta_ads", "perdida", 300e6)]
    for n, uni, canal, etapa, val in ops:
        cur.execute("""insert into public.oportunidad (nombre,unidad,canal,etapa,valor_estimado,ciudad,responsable_id,area_m2,siguiente_paso,siguiente_paso_en,siguiente_paso_por,motivo_perdida)
                       values (%s,%s,%s,'cita_viabilidad',%s,'Pereira',%s,200,%s,%s,%s,null) returning id""",
                    (n, uni, canal, val, P["Laura"], None if etapa == "perdida" else "Llamar para confirmar la reunión", None if etapa == "perdida" else d(2), None if etapa == "perdida" else P["Laura"]))
        oid = cur.fetchone()[0]
        if etapa != "cita_viabilidad":
            cur.execute("update public.oportunidad set etapa=%s, motivo_perdida=%s where id=%s", (etapa, "precio" if etapa == "perdida" else None, oid))

@seccion("presupuesto de obra")
def _():
    caps = {"O-201": [("01", "Preliminares", [("01.01", "Cerramiento provisional", "ml", 120, 85000), ("01.02", "Descapote y nivelación", "m2", 1400, 14000)]),
                      ("02", "Cimentación y estructura", [("02.01", "Excavación mecánica", "m3", 900, 32000), ("02.02", "Concreto zapatas", "m3", 210, 780000), ("02.03", "Estructura metálica cubierta", "kg", 42000, 9800)]),
                      ("03", "Mampostería y acabados", [("03.01", "Muro en bloque", "m2", 1100, 68000), ("03.02", "Piso industrial", "m2", 1400, 110000)])],
            "O-202": [("01", "Demoliciones", [("01.01", "Demolición de muros", "m2", 60, 42000)]),
                      ("02", "Acabados", [("02.01", "Piso porcelanato", "m2", 140, 135000), ("02.02", "Cielo raso drywall", "m2", 140, 78000), ("02.03", "Carpintería de barra", "un", 1, 14500000)])]}
    for cod, lista in caps.items():
        cur.execute("insert into public.presupuesto (proyecto_id,estado,vigente,elaborado_por) values (%s,'borrador',true,%s) returning id", (PROY[cod], P["Camilo"]))
        pid = cur.fetchone()[0]
        for i, (cc, nombre, items) in enumerate(lista):
            cur.execute("insert into public.capitulo (presupuesto_id,codigo,nombre,orden) values (%s,%s,%s,%s) returning id", (pid, cc, nombre, i))
            cap = cur.fetchone()[0]
            for ic, desc, un, cant, vu in items:
                cur.execute("insert into public.item_presupuesto (capitulo_id,codigo,descripcion,unidad,cantidad,valor_unitario) values (%s,%s,%s,%s,%s,%s)", (cap, ic, desc, un, cant, vu))
        cur.execute("update public.presupuesto set estado='aprobado_cliente', validado_por=%s, validado_en=now(), aprobado_por=%s, aprobado_en=now() where id=%s", (P["Daniela"], P["Laura"], pid))

@seccion("gastos de obra (movimientos)")
def _():
    gastos = [("O-201", "Materiales de obra", "Ferretería", "Cemento y acero de refuerzo", 48e6, "pago", -50), ("O-201", "Subcontratos", "Constructora", "Anticipo cimentación", 160e6, "pago", -80),
              ("O-201", "Mano de obra", "Eléctricos", "Instalaciones eléctricas, primer corte", 38e6, "pago", -30), ("O-201", "Materiales de obra", "Maderas", "Tableros y formaleta", 21e6, "causacion", -10),
              ("O-201", "Transporte y fletes", "Ferretería", "Fletes de acero", 6.5e6, "compromiso", 5), ("O-202", "Materiales de obra", "Maderas", "Madera para barra y muebles", 18e6, "pago", -25),
              ("O-202", "Mano de obra", "Constructora", "Obra blanca y drywall", 42e6, "pago", -15), ("O-202", "Equipos y herramienta", "Ferretería", "Alquiler de andamios", 3.2e6, "causacion", -5)]
    n = 0
    for cod, cat, ter, concepto, valor, est, dia in gastos:
        cur.execute("insert into public.centro_costo (proyecto_id,categoria_id) values (%s,%s) on conflict (proyecto_id,categoria_id) do nothing", (PROY[cod], CAT[cat]))
        cc = uno("select id from public.centro_costo where proyecto_id=%s and categoria_id=%s", PROY[cod], CAT[cat])
        n += 1
        cur.execute("""insert into public.movimiento (proyecto_id,centro_costo_id,estado,naturaleza,fecha,valor,tercero_id,concepto,medio,registrado_por)
                       values (%s,%s,%s,'cargo',%s,%s,%s,%s,%s,%s)""",
                    (PROY[cod], cc, est, d(dia), valor, P[ter], concepto, "banco" if est == "pago" else "no_aplica", P["Andrés"]))

@seccion("ingresos")
def _():
    for cod, linea, concepto, valor, dia in [("O-201", "obra_civil", "Anticipo 30 %", 405e6, -110), ("O-201", "obra_civil", "Acta de obra n.º 1", 220e6, -45),
                                              ("O-202", "obra_civil", "Anticipo 40 %", 124e6, -40), ("D-101", "arquitectura", "Primer pago de diseño", 96e6, -55),
                                              ("D-102", "interiorismo", "Anticipo de interiorismo", 38e6, -85), ("D-102", "interiorismo", "Segundo pago", 28e6, -30),
                                              ("C-301", "consultoria", "Pago del diagnóstico", 38e6, -10)]:
        cur.execute("insert into public.ingreso (proyecto_id,fecha,valor,linea,concepto,registrado_por,es_anticipo) values (%s,%s,%s,%s,%s,%s,%s)",
                    (PROY[cod], d(dia), valor, linea, concepto, P["Laura"], "Anticipo" in concepto))

@seccion("bitácora y pendientes de obra")
def _():
    for cod in ("O-201", "O-202"):
        for k, (av, nov) in enumerate([("Fundición de zapatas ejes A–D", "Lluvia por la tarde; se cubrió el concreto"), ("Armado de acero en columnas", "Llegó el acero completo"), ("Muros del primer nivel al 60 %", "Sin novedades")]):
            cur.execute("insert into public.bitacora (proyecto_id,fecha,personal_sitio,frente_trabajo,avance,novedad,clima,registrado_por) values (%s,%s,%s,%s,%s,%s,'Soleado',%s)",
                        (PROY[cod], d(-3 * (k + 1)), 14 - k, "Frente principal", av, nov, P["Andrés"]))
    for cod, titulo, prio, est in [("O-201", "Corregir nivel de la losa del eje C", "alta", "abierto"), ("O-201", "Pedir cotización de ventanería", "normal", "abierto"),
                                    ("O-201", "Resanar la fachada norte", "normal", "por_verificar"), ("O-202", "Cambiar griferías del baño", "alta", "en_ejecucion"),
                                    ("O-202", "Definir el color de la barra", "bloqueante", "abierto")]:
        cur.execute("insert into public.pendiente_obra (proyecto_id,tipo,prioridad,titulo,responsable_id,estado,fecha_compromiso,creado_por) values (%s,'ejecucion',%s,%s,%s,%s,%s,%s)",
                    (PROY[cod], prio, titulo, P["Andrés"], est, d(7), P["Camilo"]))

for t, g in VALIDACIONES: cur.execute(f"alter table public.{t} enable trigger {g}")
cur.execute("select count(*) from pg_trigger where tgenabled='D' and not tgisinternal"); assert cur.fetchone()[0] == 0, "Quedó un disparador apagado"
if "--ya" in sys.argv: c.commit(); print("GUARDADO")
else: c.rollback(); print("(prueba: se deshizo todo; usa --ya para guardar)")
