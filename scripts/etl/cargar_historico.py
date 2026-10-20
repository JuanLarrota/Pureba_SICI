#!/usr/bin/env python3
"""
SICI · ESA Arquitectura
Carga el histórico real de la empresa al esquema del SICI.

Lee:
  - RELACION INGRESOS Y GASTOS ESA <año> - CONSOLIDADO*.xlsx  (2024, 2025, 2026;
    de 2026, el corte más reciente que haya en la carpeta)
  - BALANCE 27 DE AGOSTO 2026 + AD.xlsx                       (Obra Nirvana)

Escribe:
  supabase/semilla/010_historico.sql   catálogos, centros de costo y pagos históricos
  supabase/semilla/020_nirvana.sql     presupuesto, capítulos, ítems, ejecución, adicionales
  supabase/semilla/_resumen.txt        qué se cargó y qué se descartó, con cifras

030_clasificacion.sql no lo genera este script: está escrito a mano.

No inventa datos. Lo que no se puede mapear queda reportado en el resumen,
no se rellena con supuestos.

Uso:  python3 cargar_historico.py [--salida DIR]
"""

from __future__ import annotations
import argparse, re, sys, unicodedata
from collections import Counter, defaultdict
from datetime import date, datetime
from pathlib import Path

try:
    import openpyxl
except ImportError:
    sys.exit("Falta openpyxl.  pip install openpyxl")

# --------------------------------------------------------------------------
# Rutas de los archivos fuente
# --------------------------------------------------------------------------
DRIVE = Path.home() / "Library/CloudStorage"
FIN = DRIVE / "GoogleDrive-esa.documentos@gmail.com/Mi unidad/03 Contabilidad/01 FINANANZAS"
EST = DRIVE / "GoogleDrive-estudio.esa.arquitectura@gmail.com/Mi unidad"

LIBROS = {
    2024: FIN / "RELACIÓN INGRESOS Y GASTOS 2024/12_31 ESA CONSOLIDADO 2024.xlsx",
    2025: FIN / "FINANCIERO 2025/RELACION INGRESOS Y GASTOS ESA 2025 - CONSOLIDADO.xlsx",
    # Sergio guarda un corte nuevo cada tanto (7 JULIO, 22 SEPTIEMBRE…): se toma el más reciente.
    2026: max((FIN / "FINANCIERO 2026").glob("RELACION INGRESOS Y GASTOS ESA 2026 - CONSOLIDADO*.xlsx"),
              key=lambda r: r.stat().st_mtime, default=FIN / "FINANCIERO 2026/sin corte consolidado.xlsx"),
}
BALANCE_NIRVANA = EST / "04_2026/04_26 Obra Nirvana/03_Presupuesto/balances/BALANCE 27 DE AGOSTO 2026 + AD.xlsx"

HOJA_BALANCE = "BALANCE 3 de Julio"

# El formato del libro cambia de un año a otro: la hoja se llama distinto, el
# encabezado no está en la misma fila y las columnas cambian de nombre. En vez
# de fijar una estructura, se detecta.
PISTAS_HOJA = ("RELACION PAGOS", "RELACION DE PAGOS", "PAGOS CONSOLIDADO")

SINONIMOS = {
    "fecha":      ("FECHA",),
    "valor":      ("SALIDA", "PAGO", "VALOR", "VLR"),
    "proyecto":   ("CENTROS DE COSTOS", "CENTRO DE COSTOS", "CENTRO DE COSTO"),
    "categoria":  ("CATEGORIA PAGOS", "CATEGORIA", "CATEGORÍA"),
    "tipo_gasto": ("TIPO DE GASTO", "TIPO GASTO"),
    "tercero":    ("NOMBRE", "TERCERO", "BENEFICIARIO"),
    "concepto":   ("CONCEPTO", "TEXTO", "DETALLE"),
    "medio":      ("BANCO", "MEDIO", "FORMA DE PAGO"),
    "entrada":    ("ENTRADA",),
    "linea":      ("CATEGORIA INGRESOS",),
}

# Categorías que el libro escribe de varias maneras y son la misma.
# Decisión de Felipe (18-10-2026): los alquileres quedan en una sola.
CATEGORIA_CANON = {
    "ALQUILER DE EQUIPOS":   "ALQUILERES Y EQUIPOS",
    "ALQUILERES DE EQUIPOS": "ALQUILERES Y EQUIPOS",
}

# CATEGORIA INGRESOS del libro → línea de servicio del SICI.
LINEA_INGRESO = {
    "CONSULTORIA": "consultoria", "ARQUITECTURA": "arquitectura", "OBRA CIVIL": "obra_civil",
    "INTERIORISMO": "interiorismo", "OTROS INGRESOS": "otros_ingresos",
    "TRASLADO ENTRE CUENTAS": "traslado_entre_cuentas", "CREDITOS BANCARIOS": "credito_bancario",
    "CREDITO BANCARIO": "credito_bancario",
}
# Estas líneas no son de ningún proyecto: pueden entrar sin él.
SIN_PROYECTO = {"traslado_entre_cuentas", "credito_bancario", "otros_ingresos"}

TIPO_GASTO_CANON = {
    "GASTOS": "GASTOS ADMINISTRATIVOS",
    "GASTO": "GASTOS ADMINISTRATIVOS",
    "GASTOS ADMINISTRATIVOS": "GASTOS ADMINISTRATIVOS",
    "COSTOS OPERATIVOS": "COSTOS OPERATIVOS",
    "COSTO OPERATIVO": "COSTOS OPERATIVOS",
}

# Filas del balance que no son ítems sino totales
NO_ITEMS = {
    "ADMINISTRACIÓN", "ADMINISTRACION", "UTILIDAD", "IMPREVISTOS",
    "IVA SOBRE UTILIDAD", "SUBTOTAL (1)", "TOTAL OBRA    (2)",
}

# Cómo se clasifica cada proyecto del libro mayor
UNIDAD_POR_PREFIJO = [
    ("ADMINISTRACION", "administracion", "interno"),
    ("OBRA ",          "obra_propia",    "obra"),
    ("BODEGA ",        "obra_propia",    "obra"),
    ("LOCAL ",         "obra_propia",    "obra"),
    ("INTERIORISMO ",  "interiorismo",   "diseno"),
    ("ESCALERAS ",     "obra_propia",    "obra"),
    ("PH ",            "interiorismo",   "diseno"),
    ("APTO ",          "interiorismo",   "diseno"),
    ("CASA ",          "diseno_arquitectonico", "diseno"),
    ("CABAÑA ",        "diseno_arquitectonico", "diseno"),
    ("GETAWAY",        "diseno_arquitectonico", "diseno"),
]

# Rol de un tercero según las categorías en que se le ha pagado, en orden de
# prioridad. La categoría SOCIOS no significa que el tercero sea socio: es el
# gasto de los socios pagado por la empresa (una droguería, un pediatra). Lo
# que no se puede deducir queda 'sin_clasificar'; no se inventa.
ROL_POR_PRIORIDAD = [
    ("CONTRATISTAS", "contratista"),
    ("PROVEEDORES", "proveedor"),
    ("HONORARIOS", "profesional_externo"),
]

# Quien figura como registrador de los pagos históricos. No es una persona.
REGISTRADOR_HISTORICO = "Carga histórica · libro mayor"


# --------------------------------------------------------------------------
# Utilidades
# --------------------------------------------------------------------------
def esc(v) -> str:
    """Literal SQL seguro."""
    if v is None or v == "":
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(round(v, 4) if isinstance(v, float) else v)
    if isinstance(v, (date, datetime)):
        return f"'{v.date() if isinstance(v, datetime) else v}'"
    return "'" + str(v).replace("'", "''").strip() + "'"


def limpio(v) -> str:
    return re.sub(r"\s+", " ", str(v)).strip() if v is not None else ""


def clave(v: str) -> str:
    """Normaliza para comparar: sin tildes, mayúsculas, sin espacios dobles."""
    s = unicodedata.normalize("NFKD", limpio(v).upper())
    return "".join(c for c in s if not unicodedata.combining(c))


def num(v):
    return v if isinstance(v, (int, float)) and not isinstance(v, bool) else None


def clasificar(codigo: str) -> tuple[str, str]:
    k = clave(codigo)
    for pref, unidad, tipo in UNIDAD_POR_PREFIJO:
        if k.startswith(clave(pref)):
            return unidad, tipo
    return "diseno_arquitectonico", "diseno"


# --------------------------------------------------------------------------
# 1 · Libro mayor
# --------------------------------------------------------------------------
def _localizar(ws, max_scan=25):
    """Encuentra la fila de encabezado y el índice de cada columna conocida."""
    for fila in range(1, max_scan + 1):
        celdas = [limpio(c.value).upper() for c in
                  next(ws.iter_rows(min_row=fila, max_row=fila), ())]
        if not celdas:
            continue
        idx = {}
        for campo, nombres in SINONIMOS.items():
            for i, c in enumerate(celdas):
                if c in nombres:
                    idx[campo] = i
                    break
        if all(k in idx for k in ("fecha", "valor", "proyecto", "categoria")):
            return fila, idx
    return None, None


def _hoja_libro(wb):
    for n in wb.sheetnames:
        k = clave(n)
        if any(p in k for p in PISTAS_HOJA):
            return n
    return None


def leer_libros():
    filas, ingresos, notas = [], [], Counter()
    for anio, ruta in LIBROS.items():
        if not ruta.exists():
            notas[f"libro {anio}: archivo no encontrado"] += 1
            continue
        wb = openpyxl.load_workbook(ruta, data_only=True)
        hoja = _hoja_libro(wb)
        if hoja is None:
            notas[f"libro {anio}: sin hoja de relación de pagos"] += 1
            wb.close(); continue
        ws = wb[hoja]
        fila_enc, idx = _localizar(ws)
        if idx is None:
            notas[f"libro {anio}: no se reconoció el encabezado"] += 1
            wb.close(); continue

        for r in ws.iter_rows(min_row=fila_enc + 1, values_only=True):
            g = lambda c: r[idx[c]] if c in idx and idx[c] < len(r) else None
            valor = num(g("valor"))
            fecha = g("fecha")
            proy, cat = limpio(g("proyecto")), limpio(g("categoria"))
            cat = CATEGORIA_CANON.get(clave(cat), cat)
            entrada = num(g("entrada"))
            if entrada and entrada > 0:
                linea = LINEA_INGRESO.get(clave(g("linea")))
                if not isinstance(fecha, (date, datetime)):
                    notas["ingreso descartado: sin fecha válida"] += 1
                elif linea is None:
                    notas["ingreso descartado: sin categoría de ingreso"] += 1
                elif not proy and linea not in SIN_PROYECTO:
                    notas["ingreso descartado: sin proyecto"] += 1
                else:
                    ingresos.append({
                        "anio": anio, "fecha": fecha.date() if isinstance(fecha, datetime) else fecha,
                        "valor": round(float(entrada), 2), "proyecto": proy or None, "linea": linea,
                        "tercero": limpio(g("tercero")), "concepto": limpio(g("concepto")) or "Sin concepto",
                    })
            if not (valor and valor > 0):
                notas["fila sin valor de pago"] += 1; continue
            if not proy:
                notas["descartada: sin centro de costo"] += 1; continue
            if not cat:
                notas["descartada: sin categoría"] += 1; continue
            if not isinstance(fecha, (date, datetime)):
                notas["descartada: sin fecha válida"] += 1; continue

            filas.append({
                "anio": anio,
                "fecha": fecha.date() if isinstance(fecha, datetime) else fecha,
                "valor": round(float(valor), 2),
                "proyecto": proy,
                "categoria": cat,
                "tipo_gasto": TIPO_GASTO_CANON.get(clave(g("tipo_gasto")), "COSTOS OPERATIVOS"),
                "tercero": limpio(g("tercero")),
                "concepto": limpio(g("concepto")) or "Sin concepto",
                "medio": "efectivo" if "EFECTIVO" in clave(g("medio")) else "banco",
            })
        notas[f"libro {anio}: {ruta.name} · hoja '{hoja}', encabezado fila {fila_enc}"] += 1
        if "entrada" not in idx:
            notas[f"libro {anio}: sin columna de entradas, no se cargan sus ingresos"] += 1
        wb.close()
    return filas, ingresos, notas


# --------------------------------------------------------------------------
def leer_nirvana() -> tuple[list[dict], list[dict], dict]:
    items, adicionales, notas = [], [], Counter()
    if not BALANCE_NIRVANA.exists():
        notas["balance de Nirvana no encontrado"] += 1
        return items, adicionales, notas

    wb = openpyxl.load_workbook(BALANCE_NIRVANA, data_only=True, read_only=True)
    ws = wb[HOJA_BALANCE]
    for r in ws.iter_rows(min_row=4, max_col=13, values_only=True):
        cod, cap, desc = limpio(r[0]), limpio(r[1]), limpio(r[2])
        if not desc or clave(desc) in {clave(x) for x in NO_ITEMS}:
            continue
        unidad = limpio(r[3]) or None
        cant, vu, vp = num(r[4]), num(r[5]), num(r[6])
        cant_e, vp_e = num(r[7]), num(r[8])
        pct = num(r[10])                      # columna K: % de avance
        if isinstance(r[9], str) and "REF" in r[9]:
            notas["celda #REF! en columna de saldo"] += 1

        if cod.upper().startswith("AD-"):
            adicionales.append({
                "codigo": cod.upper(), "capitulo": cap, "descripcion": desc,
                "unidad": unidad, "cantidad": cant_e or 0, "valor_unitario": vu or 0,
                "valor": vp_e or 0,
            })
        elif cant is not None and vp:
            items.append({
                "codigo": cod, "capitulo": cap or "SIN CAPÍTULO", "descripcion": desc,
                "unidad": unidad, "cantidad": cant, "valor_unitario": vu or 0,
                "valor_parcial": vp, "cantidad_real": cant_e, "valor_real": vp_e or 0,
                "pct_avance": pct if pct is not None and 0 <= pct <= 1 else None,
            })
    wb.close()
    return items, adicionales, notas


# --------------------------------------------------------------------------
# 3 · Detección de adicionales que ya estaban en el contrato (control O9)
# --------------------------------------------------------------------------
def cruzar_adicionales(items, adicionales) -> list[tuple[str, str, float]]:
    import difflib
    sin_ejecutar = [i for i in items if i["valor_parcial"] > 0 and not i["valor_real"]]
    pares = []
    for a in adicionales:
        na = clave(a["descripcion"])
        mejor, punt = None, 0.0
        for b in sin_ejecutar:
            nb = clave(b["descripcion"])
            ta = {w for w in na.split() if len(w) > 4}
            tb = {w for w in nb.split() if len(w) > 4}
            s = max(difflib.SequenceMatcher(None, na, nb).ratio(),
                    len(ta & tb) / max(1, len(ta | tb)))
            if s > punt:
                mejor, punt = b, s
        if mejor and punt >= 0.80:
            pares.append((a["codigo"], mejor["codigo"], punt))
    return pares


# --------------------------------------------------------------------------
# Generación de SQL
# --------------------------------------------------------------------------
CAB = """-- Generado por etl/cargar_historico.py · {ts}
-- Datos reales de ESA Arquitectura. No editar a mano: volver a generar.
begin;
"""
PIE = "\ncommit;\n"


def sql_catalogos(filas, out: Path, ingresos=()) -> dict:
    cats, proys, nombres, cats_tercero = {}, {}, {}, defaultdict(set)
    for i in ingresos:   # un proyecto que solo ha cobrado también existe
        if i["proyecto"]:
            proys.setdefault(clave(i["proyecto"]), i["proyecto"])
    for f in filas:
        cats.setdefault(clave(f["categoria"]), (f["categoria"], f["tipo_gasto"]))
        proys.setdefault(clave(f["proyecto"]), f["proyecto"])
        if f["tercero"]:
            k = clave(f["tercero"])
            nombres.setdefault(k, f["tercero"])
            cats_tercero[k].add(clave(f["categoria"]))
    terceros = {}
    for k, nombre in nombres.items():
        rol = next((r for c, r in ROL_POR_PRIORIDAD if c in cats_tercero[k]), "sin_clasificar")
        terceros[k] = (nombre, rol)

    L = [CAB.format(ts=datetime.now().isoformat(timespec="seconds"))]

    L.append("\n-- Categorías de costo · columna CATEGORIA PAGOS del libro mayor")
    L.append("insert into categoria_costo (nombre, tipo_gasto, es_directo) values")
    fil = [f"  ({esc(n)}, {esc(t)}, {esc(t == 'COSTOS OPERATIVOS')})" for n, t in sorted(cats.values())]
    L.append(",\n".join(fil) + "\non conflict (nombre) do nothing;")

    L.append("\n-- Quien registra el histórico. No es una persona: es el libro mayor.")
    # Inactiva: no es nadie del equipo y no debe salir en ninguna lista para escoger.
    L.append(f"""insert into persona (nombre, rol, es_interno, activo, notas)
select {esc(REGISTRADOR_HISTORICO)}, 'financiero', true, false,
       'Registra los pagos importados de los libros de 2024 a 2026. No corresponde a ninguna persona.'
where not exists (select 1 from persona where nombre = {esc(REGISTRADOR_HISTORICO)});""")

    L.append("\n-- Personas · terceros que aparecen en el libro, sin duplicar")
    L.append("insert into persona (nombre, rol, es_interno)\nselect v.nombre, v.rol::rol_persona, false\nfrom (values")
    fil = [f"  ({esc(n)}, {esc(r)})" for n, r in sorted(terceros.values())]
    L.append(",\n".join(fil) + "\n) as v(nombre, rol)\nwhere not exists (select 1 from persona p where upper(p.nombre) = upper(v.nombre));")

    L.append("\n-- Proyectos · columna CENTROS DE COSTOS del libro mayor")
    L.append("insert into proyecto (codigo, nombre, unidad, tipo, estado) values")
    fil = []
    for cod in sorted(proys.values()):
        unidad, tipo = clasificar(cod)
        fil.append(f"  ({esc(cod)}, {esc(cod.title())}, {esc(unidad)}, {esc(tipo)}, 'terminado')")
    L.append(",\n".join(fil) + "\non conflict (codigo) do nothing;")

    L.append("""
-- Centro de costo = proyecto × categoría, solo para las combinaciones que
-- realmente ocurrieron. Nada de producto cartesiano.
insert into centro_costo (proyecto_id, categoria_id)
select distinct p.id, c.id
from proyecto p
join movimiento_staging s on s.proyecto = p.codigo
join categoria_costo c    on c.nombre   = s.categoria
on conflict (proyecto_id, categoria_id) do nothing;""")

    out.write_text("\n".join(L) + PIE, encoding="utf-8")
    return {"categorias": len(cats), "proyectos": len(proys), "personas": len(terceros)}


def sql_movimientos(filas, out: Path) -> dict:
    L = [CAB.format(ts=datetime.now().isoformat(timespec="seconds"))]
    L.append("""
-- Tabla puente: el libro mayor solo conoce el PAGO (el tercer estado del
-- dinero). Compromiso y causación empiezan a existir cuando la obra registra
-- en la PWA. Este histórico entra completo como 'pago' y ya conciliado.
create temporary table movimiento_staging (
  fecha date, valor numeric(16,2), proyecto text, categoria text,
  tercero text, concepto text, medio text
) on commit drop;

insert into movimiento_staging (fecha, valor, proyecto, categoria, tercero, concepto, medio) values""")
    fil = [
        "  ({}, {}, {}, {}, {}, {}, {})".format(
            esc(f["fecha"]), esc(f["valor"]), esc(f["proyecto"]), esc(f["categoria"]),
            esc(f["tercero"] or None), esc(f["concepto"][:300]), esc(f["medio"]))
        for f in filas
    ]
    L.append(",\n".join(fil) + ";")

    L.append("""
insert into movimiento
  (proyecto_id, centro_costo_id, estado, fecha, valor, tercero_id, tercero_nombre,
   concepto, medio, aprobacion, registrado_por, conciliado, conciliado_en)
select
  p.id, cc.id, 'pago', s.fecha, s.valor,
  t.id, case when t.id is null then coalesce(nullif(trim(s.tercero), ''), 'SIN TERCERO EN EL LIBRO') end,
  s.concepto, s.medio::medio_pago, 'no_requiere',
  (select id from persona where nombre = 'Carga histórica · libro mayor'),
  true, s.fecha
from movimiento_staging s
join proyecto p          on p.codigo = s.proyecto
join categoria_costo c   on c.nombre = s.categoria
join centro_costo cc     on cc.proyecto_id = p.id and cc.categoria_id = c.id
left join persona t      on upper(t.nombre) = upper(s.tercero);""")

    out.write_text("\n".join(L) + PIE, encoding="utf-8")
    total = sum(f["valor"] for f in filas)
    return {"movimientos": len(filas), "valor_total": total}


def sql_ingresos(ingresos) -> str:
    """Las entradas del libro: cobros a clientes, créditos y traslados. Entran
    conciliadas, a nombre del libro mayor; el pagador queda como texto (no se
    crean personas para los clientes)."""
    if not ingresos:
        return ""
    fil = ["  ({}, {}, {}, {}, {}, {})".format(esc(i["fecha"]), esc(i["valor"]), esc(i["proyecto"]),
                                              esc(i["linea"]), esc(i["tercero"] or None), esc(i["concepto"][:300]))
           for i in ingresos]
    return ("""
-- Ingresos · columnas ENTRADA y CATEGORIA INGRESOS del libro mayor
create temporary table ingreso_staging (
  fecha date, valor numeric(16,2), proyecto text, linea text, tercero text, concepto text
) on commit drop;

insert into ingreso_staging (fecha, valor, proyecto, linea, tercero, concepto) values
""" + ",\n".join(fil) + """;

insert into ingreso (proyecto_id, fecha, valor, linea, tercero_nombre, concepto, registrado_por, conciliado, conciliado_en)
select p.id, s.fecha, s.valor, s.linea::linea_servicio, nullif(trim(s.tercero), ''), s.concepto,
       (select id from persona where nombre = 'Carga histórica · libro mayor'), true, s.fecha
from ingreso_staging s
left join proyecto p on p.codigo = s.proyecto;
""")


def sql_nirvana(items, adicionales, pares, out: Path) -> dict:
    L = [CAB.format(ts=datetime.now().isoformat(timespec="seconds"))]
    L.append("""
-- Obra Nirvana · presupuesto contractual, ejecución real y adicionales.
-- Al 2026-08-28 ninguno de los adicionales estaba aprobado por el cliente,
-- así que todos entran como 'pendiente'. Ese es el estado verdadero.

insert into proyecto (codigo, nombre, unidad, tipo, estado, fase,
                      valor_contrato, pct_administracion, pct_utilidad, pct_imprevistos)
values ('OBRA NIRVANA', 'Obra Nirvana', 'obra_propia', 'obra', 'activo', 'obra',
        581073956, 0.10, 0.04, 0.00)
on conflict (codigo) do update set
  valor_contrato = excluded.valor_contrato,
  pct_administracion = excluded.pct_administracion,
  pct_utilidad = excluded.pct_utilidad,
  pct_imprevistos = excluded.pct_imprevistos,
  estado = 'activo', fase = 'obra';

insert into presupuesto (proyecto_id, version, vigente)
select id, 1, true from proyecto where codigo = 'OBRA NIRVANA'
on conflict (proyecto_id, version) do nothing;
""")

    caps = {}
    for i in items:
        caps.setdefault(clave(i["capitulo"]), i["capitulo"])
    L.append("\n-- Capítulos")
    L.append("insert into capitulo (presupuesto_id, codigo, nombre)\nselect pr.id, v.codigo, v.nombre from presupuesto pr\njoin proyecto p on p.id = pr.proyecto_id and p.codigo = 'OBRA NIRVANA'\ncross join (values")
    fil = [f"  ({esc(f'C{n:02d}')}, {esc(nom)})" for n, nom in enumerate(sorted(caps.values()), 1)]
    L.append(",\n".join(fil) + "\n) as v(codigo, nombre)\non conflict (presupuesto_id, codigo) do nothing;")

    cap_cod = {clave(nom): f"C{n:02d}" for n, nom in enumerate(sorted(caps.values()), 1)}

    L.append("\n-- Ítems del contrato")
    L.append("insert into item_presupuesto (capitulo_id, codigo, descripcion, unidad, cantidad, valor_unitario)\nselect c.id, v.codigo, v.descripcion, v.unidad, v.cantidad, v.vu\nfrom capitulo c\njoin presupuesto pr on pr.id = c.presupuesto_id\njoin proyecto p on p.id = pr.proyecto_id and p.codigo = 'OBRA NIRVANA'\njoin (values")
    fil, vistos = [], set()
    for i in items:
        cc = cap_cod[clave(i["capitulo"])]
        k = (cc, i["codigo"])
        if k in vistos:
            continue
        vistos.add(k)
        fil.append("  ({}, {}, {}, {}, {}, {})".format(
            esc(cc), esc(i["codigo"]), esc(i["descripcion"][:400]),
            esc(i["unidad"]), esc(i["cantidad"]), esc(i["valor_unitario"])))
    L.append(",\n".join(fil) + "\n) as v(cap, codigo, descripcion, unidad, cantidad, vu)\n  on v.cap = c.codigo\non conflict (capitulo_id, codigo) do nothing;")

    L.append("\n-- Total a ejecutar revisado (columnas H e I) y % de avance (K) por ítem")
    L.append("insert into ejecucion_item (item_id, cantidad_proyectada, valor_proyectado, pct_avance)\nselect i.id, coalesce(v.cant::numeric, 0), coalesce(v.valor::numeric, 0), coalesce(v.pct::numeric, 0)\nfrom item_presupuesto i\njoin capitulo c on c.id = i.capitulo_id\njoin presupuesto pr on pr.id = c.presupuesto_id\njoin proyecto p on p.id = pr.proyecto_id and p.codigo = 'OBRA NIRVANA'\njoin (values")
    fil, vistos = [], set()
    for i in items:
        cc = cap_cod[clave(i["capitulo"])]
        k = (cc, i["codigo"])
        if k in vistos:
            continue
        vistos.add(k)
        fil.append(f"  ({esc(cc)}, {esc(i['codigo'])}, {esc(i['cantidad_real'])}, {esc(i['valor_real'])}, {esc(i['pct_avance'])})")
    L.append(",\n".join(fil) + "\n) as v(cap, codigo, cant, valor, pct)\n  on v.cap = c.codigo and v.codigo = i.codigo\non conflict (item_id) do nothing;")

    mapa = {a: b for a, b, _ in pares}
    L.append("\n-- Adicionales · todos pendientes de aprobación del cliente")
    L.append("insert into adicional (proyecto_id, codigo, capitulo_nombre, descripcion, unidad,\n                       cantidad, valor_unitario, aprobacion, reemplaza_item_id, motivo)\nselect p.id, v.codigo, v.cap, v.descripcion, v.unidad, v.cantidad, v.vu, 'pendiente',\n       (select i.id from item_presupuesto i\n          join capitulo c on c.id = i.capitulo_id\n          join presupuesto pr on pr.id = c.presupuesto_id\n         where pr.proyecto_id = p.id and i.codigo = v.reemplaza limit 1),\n       v.motivo\nfrom proyecto p cross join (values")
    fil = []
    for a in adicionales:
        rp = mapa.get(a["codigo"])
        motivo = ("Coincide con un ítem del contrato sin ejecutar; el crédito es automático."
                  if rp else None)
        fil.append("  ({}, {}, {}, {}, {}, {}, {}, {})".format(
            esc(a["codigo"]), esc(a["capitulo"][:120]), esc(a["descripcion"][:400]),
            esc(a["unidad"]), esc(a["cantidad"]), esc(a["valor_unitario"]),
            esc(rp), esc(motivo)))
    L.append(",\n".join(fil) + "\n) as v(codigo, cap, descripcion, unidad, cantidad, vu, reemplaza, motivo)\nwhere p.codigo = 'OBRA NIRVANA'\non conflict (proyecto_id, codigo) do nothing;")

    out.write_text("\n".join(L) + PIE, encoding="utf-8")
    return {
        "items": len(vistos), "capitulos": len(caps), "adicionales": len(adicionales),
        "adicionales_cruzados": len(pares),
        "presupuesto": sum(i["valor_parcial"] for i in items),
        "ejecutado": sum(i["valor_real"] for i in items),
        "valor_adicionales": sum(a["valor"] for a in adicionales),
    }


# --------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--salida", default=str(Path(__file__).resolve().parents[2] / "supabase/semilla"))
    args = ap.parse_args()
    salida = Path(args.salida)
    salida.mkdir(parents=True, exist_ok=True)

    print("Leyendo el libro mayor…")
    filas, ingresos, notas = leer_libros()
    print(f"  {len(filas)} movimientos utilizables · {len(ingresos)} ingresos · 2026 desde {LIBROS[2026].name}")

    print("Leyendo el balance de Nirvana…")
    items, adicionales, notas_n = leer_nirvana()
    notas.update(notas_n)
    print(f"  {len(items)} ítems · {len(adicionales)} adicionales")

    pares = cruzar_adicionales(items, adicionales)
    print(f"  {len(pares)} adicionales coinciden con un ítem del contrato")

    tmp_cat = salida / "_cat.tmp"; tmp_mov = salida / "_mov.tmp"
    r1 = sql_catalogos(filas, tmp_cat, ingresos)
    r2 = sql_movimientos(filas, tmp_mov)
    r3 = sql_nirvana(items, adicionales, pares, salida / "020_nirvana.sql")

    # Un solo archivo, una sola transacción, en el orden correcto:
    # staging -> catálogos -> centros de costo -> movimientos.
    cat = tmp_cat.read_text(encoding="utf-8")
    mov = tmp_mov.read_text(encoding="utf-8")
    despoja = lambda t: t.split("begin;", 1)[1].rsplit("commit;", 1)[0]
    cat_cuerpo, mov_cuerpo = despoja(cat), despoja(mov)
    staging, insercion = mov_cuerpo.split("insert into movimiento\n", 1)
    guardia = """
-- Si el histórico ya se cargó, se detiene aquí: cargarlo dos veces duplicaría
-- toda la contabilidad. El archivo es una sola transacción: no queda nada a medias.
do $$ begin
  if exists (select 1 from movimiento m join persona p on p.id = m.registrado_por
             where p.nombre = 'Carga histórica · libro mayor') then
    raise exception 'El histórico ya está cargado en esta base. No se vuelve a insertar.';
  end if;
end $$;
"""
    (salida / "010_historico.sql").write_text(
        CAB.format(ts=datetime.now().isoformat(timespec="seconds"))
        + guardia + staging + cat_cuerpo + "\ninsert into movimiento\n" + insercion + sql_ingresos(ingresos) + PIE,
        encoding="utf-8")
    tmp_cat.unlink(); tmp_mov.unlink()

    por_anio = Counter(f["anio"] for f in filas)
    val_anio = defaultdict(float)
    for f in filas:
        val_anio[f["anio"]] += f["valor"]

    L = ["SICI · carga del histórico",
         f"Generado {datetime.now():%Y-%m-%d %H:%M}", "",
         "CATÁLOGOS",
         f"  categorías de costo   {r1['categorias']:>8}",
         f"  proyectos             {r1['proyectos']:>8}",
         f"  personas (terceros)   {r1['personas']:>8}", "",
         "MOVIMIENTOS HISTÓRICOS (entran como 'pago', ya conciliados)"]
    for a in sorted(por_anio):
        L.append(f"  {a}  {por_anio[a]:>6} movimientos   ${val_anio[a]:>18,.0f}")
    L += [f"  TOTAL {r2['movimientos']:>6} movimientos   ${r2['valor_total']:>18,.0f}", "",
          "INGRESOS (entran conciliados, con su línea de servicio)"]
    ing_anio, ing_val = Counter(i["anio"] for i in ingresos), defaultdict(float)
    for i in ingresos:
        ing_val[i["anio"]] += i["valor"]
    for a in sorted(ing_anio):
        L.append(f"  {a}  {ing_anio[a]:>6} ingresos      ${ing_val[a]:>18,.0f}")
    L += [f"  EN TOTAL {len(ingresos):>3} ingresos      ${sum(ing_val.values()):>18,.0f}", "",
          "OBRA NIRVANA",
          f"  capítulos             {r3['capitulos']:>8}",
          f"  ítems del contrato    {r3['items']:>8}",
          f"  adicionales           {r3['adicionales']:>8}  (todos pendientes de aprobación)",
          f"  ya estaban en contrato{r3['adicionales_cruzados']:>8}",
          f"  presupuesto           ${r3['presupuesto']:>17,.0f}",
          f"  total a ejecutar      ${r3['ejecutado']:>17,.0f}",
          f"  adicionales           ${r3['valor_adicionales']:>17,.0f}", "",
          "DESCARTES Y AVISOS"]
    for k, v in notas.most_common():
        L.append(f"  {v:>6}  {k}")
    L += ["", "Orden de ejecución (cada archivo es una transacción completa):",
          "  1. supabase/migrations/  (las 11, en orden de nombre)",
          "  2. supabase/semilla/010_historico.sql",
          "  3. supabase/semilla/020_nirvana.sql",
          "  4. supabase/semilla/030_clasificacion.sql"]
    (salida / "_resumen.txt").write_text("\n".join(L), encoding="utf-8")
    print("\n".join(L[3:]))
    print(f"\nSQL escrito en {salida}")


if __name__ == "__main__":
    main()
