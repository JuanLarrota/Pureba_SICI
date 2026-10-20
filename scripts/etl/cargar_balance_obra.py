#!/usr/bin/env python3
"""
SICI · ESA Arquitectura
Lleva el balance de una obra al SICI: el total a ejecutar y el avance de cada
ítem del contrato, y las modificaciones (MOD-) como adicionales pendientes.

Desde el balance del 2 de octubre de 2026, la hoja «BALANCE» ya no trae los
adicionales como «AD-» al final: cada modificación es un «MOD-» dentro de su
capítulo, y la observación del ítem que reemplaza dice cuál lo sustituye
(«MOD-12.07 Se ajusta cantidad y precio»). El bloque de la derecha
(«MODIFICACION TOTAL» y «CANTIDAD TOTAL A EJECUTAR», columnas Q a U) es el que
suma el VALOR FINAL; es el que se toma.

Lee:   BALANCE <día> DE <MES> <año>.xlsx  (el de fecha más reciente, o el que se indique)
Escribe: supabase/semilla/025_nirvana_balance.sql

El SQL no inserta el presupuesto: lo encuentra. Si un ítem del balance no
existe en el contrato cargado, o su valor parcial cambió, se detiene; si al
final la base no suma lo mismo que el balance, se detiene. Un adicional que el
cliente ya decidió no se toca. Uno pendiente que ya no aparece en el balance se
retira con la razón; no se borra. Se puede correr las veces que sea: la segunda
no cambia nada.

Uso:  python3 cargar_balance_obra.py [--balance RUTA] [--obra CODIGO] [--salida ARCHIVO]
"""

from __future__ import annotations
import argparse, difflib, re, sys
from datetime import date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cargar_historico import EST, esc, limpio, clave, num, openpyxl  # noqa: E402

CARPETA_NIRVANA = EST / "04_2026/04_26 Obra Nirvana/03_Presupuesto/balances"
HOJA = "BALANCE"
MESES = {m: i for i, m in enumerate(
    ("ENERO", "FEBRERO", "MARZO", "ABRIL", "MAYO", "JUNIO", "JULIO", "AGOSTO",
     "SEPTIEMBRE", "OCTUBRE", "NOVIEMBRE", "DICIEMBRE"), 1)}
TOLERANCIA = 2.0          # pesos: el Excel redondea distinto celda a celda


def fecha_del_nombre(ruta: Path) -> date | None:
    m = re.match(r"BALANCE (\d{1,2}) DE ([A-ZÁÉÍÓÚ]+) (\d{4})", clave(ruta.stem))
    if not m or m.group(2) not in MESES:
        return None
    return date(int(m.group(3)), MESES[m.group(2)], int(m.group(1)))


def balance_mas_reciente(carpeta: Path) -> Path:
    con_fecha = [(fecha_del_nombre(r), r) for r in carpeta.glob("BALANCE *.xlsx")
                 if not r.name.startswith("~$")]
    con_fecha = [(f, r) for f, r in con_fecha if f]
    if not con_fecha:
        sys.exit(f"No hay balances con fecha en el nombre en {carpeta}")
    return max(con_fecha)[1]


def codigo(v) -> str:
    """Los códigos vienen como número de Excel (2.0199999999999996): se guardan
    tal como los leyó la carga del 27 de agosto, para que casen con el contrato."""
    return limpio(v)


def mods_citados(texto: str) -> list[str]:
    """'MOD-16.08 A MOD-16.20 …' -> todos los del rango; 'MOD-3.07 Y MOD-3.08' -> los dos."""
    t = clave(texto)
    citados = []
    for cap, desde, hasta in re.findall(r"MOD-(\d+)\.(\d+)\s+A\s+MOD-\d+\.(\d+)", t):
        citados += [f"MOD-{cap}.{n:02d}" for n in range(int(desde), int(hasta) + 1)]
    citados += [f"MOD-{c}.{int(n):02d}" for c, n in re.findall(r"MOD-(\d+)\.(\d+)", t)]
    return list(dict.fromkeys(citados))


def leer(ruta: Path) -> dict:
    wb = openpyxl.load_workbook(ruta, data_only=True, read_only=True)
    if HOJA not in wb.sheetnames:
        sys.exit(f"{ruta.name} no tiene la hoja «{HOJA}»")
    ws = wb[HOJA]
    filas = list(ws.iter_rows(min_row=1, max_col=26, values_only=True))
    wb.close()

    # Columnas por su encabezado, no por posición fija: se toma el último
    # bloque «CANTIDAD TOTAL A EJECUTAR» (el que suma el valor final).
    enc1 = [clave(v) for v in filas[0]]
    enc3 = [clave(v) for v in filas[2]]
    c_cant = max(i for i, v in enumerate(enc1) if v.startswith("CANTIDAD TOTAL A EJECUTAR"))
    c_valor = c_cant + 1
    c_pct = next(i for i, v in enumerate(enc1) if v.startswith("PORCENTAJE DE AVANCE"))
    c_obs = max(i for i, v in enumerate(enc3) if v.startswith("OBSERVACION"))
    assert enc3[0] == "CODIGO" and enc3[6] == "VR. PARCIAL", "El encabezado del balance cambió"

    items, mods, capitulos, resumen = [], [], {}, {}
    cap_actual = None
    for n, r in enumerate(filas[3:], 4):
        a, desc = r[0], limpio(r[2])
        if a is None:
            if desc:
                resumen[clave(desc)] = {"contrato": num(r[6]), "final": num(r[c_valor])}
            continue
        if isinstance(a, int) or (isinstance(a, float) and a == int(a) and r[1] is None):
            cap_actual = int(a)
            capitulos[cap_actual] = {"nombre": desc, "final": num(r[c_valor]) or 0, "fila": n}
            continue
        fila = {
            "fila": n, "cap": cap_actual, "capitulo": limpio(r[1]) or capitulos[cap_actual]["nombre"],
            "descripcion": desc, "unidad": limpio(r[3]) or None,
            "cantidad": num(r[4]) or 0, "vu": num(r[5]) or 0, "parcial": num(r[6]) or 0,
            "cant_final": num(r[c_cant]), "valor_final": num(r[c_valor]) or 0,
            "pct": num(r[c_pct]), "obs": limpio(r[c_obs]),
        }
        if isinstance(a, str) and a.upper().startswith("MOD-"):
            m = re.match(r"MOD-(\d+)\.(\d+)", a.upper().strip())
            fila["codigo"] = f"MOD-{m.group(1)}.{int(m.group(2)):02d}"
            mods.append(fila)
        else:
            fila["codigo"] = codigo(a)
            items.append(fila)
    return {"items": items, "mods": mods, "capitulos": capitulos, "resumen": resumen}


def cuadrar(b: dict) -> list[str]:
    """Lo que no cuadre dentro del propio balance. Vacío = cuadra."""
    malos = []
    sub = b["resumen"].get("SUBTOTAL (1)")
    if not sub:
        return ["no se encontró la fila SUBTOTAL (1)"]
    contrato = sum(i["parcial"] for i in b["items"])
    final = sum(f["valor_final"] for f in b["items"] + b["mods"])
    if abs(contrato - sub["contrato"]) > TOLERANCIA:
        malos.append(f"el contrato suma {contrato:,.2f} y el SUBTOTAL (1) dice {sub['contrato']:,.2f}")
    if abs(final - sub["final"]) > TOLERANCIA:
        malos.append(f"lo final suma {final:,.2f} y el SUBTOTAL (1) dice {sub['final']:,.2f}")
    for k, cap in b["capitulos"].items():
        s = sum(f["valor_final"] for f in b["items"] + b["mods"] if f["cap"] == k)
        if abs(s - cap["final"]) > TOLERANCIA:
            malos.append(f"capítulo {k} {cap['nombre']}: sus filas suman {s:,.2f} y el capítulo dice {cap['final']:,.2f}")
    return malos


def valor_unitario_mod(m: dict) -> tuple[float, float]:
    """El SICI calcula valor = cantidad × valor unitario. Se guarda la cantidad
    final; si el Excel no multiplicó (puso un valor a mano), el unitario se
    deduce del valor final para que la suma sea la del balance."""
    cant = m["cant_final"] or 0
    if cant and abs(cant * m["vu"] - m["valor_final"]) <= TOLERANCIA:
        return cant, m["vu"]
    if cant:
        return cant, round(m["valor_final"] / cant, 2)
    return (1, round(m["valor_final"], 2)) if m["valor_final"] else (0, m["vu"])


def reemplazos(b: dict) -> dict[str, str]:
    """MOD -> código del ítem del contrato que reemplaza, según las observaciones.
    Un MOD citado por un solo ítem va con ese; si lo citan varios (un rango), con
    el de descripción más parecida, procurando que cada ítem citado quede cubierto."""
    citado_por: dict[str, list[dict]] = {}
    for i in b["items"]:
        for c in mods_citados(i["obs"]):
            citado_por.setdefault(c, []).append(i)
    codigos_mod = {m["codigo"] for m in b["mods"]}
    mapa = {}
    parecido = lambda m, i: difflib.SequenceMatcher(None, clave(m["descripcion"]), clave(i["descripcion"])).ratio()
    for m in b["mods"]:
        cands = citado_por.get(m["codigo"], [])
        if len(cands) == 1:
            mapa[m["codigo"]] = cands[0]["codigo"]
        elif cands:
            # El ítem con la nota más específica primero; empate, el de descripción
            # más parecida (MOD-12.07 es piso exterior: va con 12.04, no con 12.03).
            cands.sort(key=lambda i: (len(mods_citados(i["obs"])), -parecido(m, i)))
            mapa[m["codigo"]] = cands[0]["codigo"]
    for i in b["items"]:
        citados = [c for c in mods_citados(i["obs"]) if c in codigos_mod]
        if citados and i["codigo"] not in mapa.values():
            libres = [c for c in citados if list(mapa.values()).count(mapa.get(c)) > 1]
            if libres:
                mejor = max(libres, key=lambda c: parecido(next(m for m in b["mods"] if m["codigo"] == c), i))
                mapa[mejor] = i["codigo"]
    return mapa


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--balance", type=Path)
    ap.add_argument("--obra", default="OBRA NIRVANA")
    ap.add_argument("--salida", type=Path,
                    default=Path(__file__).resolve().parents[2] / "supabase/semilla/025_nirvana_balance.sql")
    ap.add_argument("--solo-revisar", action="store_true")
    args = ap.parse_args()

    ruta = args.balance or balance_mas_reciente(CARPETA_NIRVANA)
    corte = fecha_del_nombre(ruta)
    print(f"Balance: {ruta.name} (corte {corte})")
    b = leer(ruta)
    print(f"  {len(b['items'])} filas del contrato · {len(b['mods'])} modificaciones · {len(b['capitulos'])} capítulos")
    malos = cuadrar(b)
    for m in malos:
        print("  NO CUADRA:", m)
    if malos:
        sys.exit("El balance no cuadra consigo mismo: no se genera nada.")
    sub = b["resumen"]["SUBTOTAL (1)"]
    print(f"  contrato (costo directo) {sub['contrato']:>18,.2f}")
    print(f"  final (costo directo)    {sub['final']:>18,.2f}")
    mapa = reemplazos(b)
    if args.solo_revisar:
        for m in b["mods"]:
            c, vu = valor_unitario_mod(m)
            print(f"  {m['codigo']:<10} {m['descripcion'][:46]:<46} {c:>10.3f} × {vu:>14,.2f} = {c*vu:>14,.0f}"
                  f"  (balance {m['valor_final']:>14,.0f})  reemplaza {mapa.get(m['codigo'], '')}")
        sin_cubrir = [i["codigo"] for i in b["items"]
                      if mods_citados(i["obs"]) and i["codigo"] not in mapa.values()]
        print("  ítems citados sin MOD que los reemplace:", sin_cubrir)
        for k in ("VALOR CONTRACTUAL", "VALOR FINAL", "TOTAL OBRA (2)"):
            print(f"  {k}: {b['resumen'].get(k)}")
        return
    escribir(b, mapa, ruta, corte, args.obra, args.salida)
    print(f"SQL escrito en {args.salida}")


def escribir(b, mapa, ruta, corte, obra, salida: Path):
    sub = b["resumen"]["SUBTOTAL (1)"]
    contractual = b["resumen"].get("VALOR CONTRACTUAL", {}).get("contrato")
    dia = f"{corte:%d-%m-%Y}"
    guardado = lambda c, vu: round(round(c, 4) * round(vu, 2), 2)
    contrato_guardado = sum(guardado(i["cantidad"], i["vu"]) for i in b["items"] if i["parcial"] or i["valor_final"])
    final_guardado = (sum(round(i["valor_final"], 2) for i in b["items"] if i["parcial"] or i["valor_final"])
                      + sum(guardado(*valor_unitario_mod(m)) for m in b["mods"]))
    print(f"  se guarda: contrato {contrato_guardado:,.2f} ({contrato_guardado - sub['contrato']:+,.2f} por redondeo)"
          f" · final {final_guardado:,.2f} ({final_guardado - sub['final']:+,.2f})")
    O = esc(obra)
    items = [i for i in b["items"] if i["parcial"] or i["valor_final"]]
    por_codigo = {i["codigo"]: i for i in b["items"]}
    vigente = f"""join public.capitulo c on c.id = i.capitulo_id
join public.presupuesto pr on pr.id = c.presupuesto_id and pr.vigente
join public.proyecto p on p.id = pr.proyecto_id and p.codigo = {O}"""

    L = [f"""-- Generado por etl/cargar_balance_obra.py · {datetime.now().isoformat(timespec='seconds')}
-- {obra} al {dia}, desde «{ruta.name}». Datos reales: no viaja a GitHub.
-- No editar a mano: volver a generar. Se puede correr las veces que sea.
begin;

-- El contrato del balance tiene que ser el que está cargado: mismos ítems, misma
-- cantidad (a cuatro decimales, como se guarda) y mismo precio unitario. Si no,
-- se detiene sin tocar nada.
do $$
declare v_malos text;
begin
  if not exists (select 1 from public.presupuesto pr join public.proyecto p on p.id = pr.proyecto_id
                 where p.codigo = {O} and pr.vigente) then
    raise exception 'Balance · {obra} no tiene presupuesto vigente cargado';
  end if;
  select string_agg(coalesce(v.codigo, i.codigo), ', ') into v_malos
  from (select i.codigo, i.cantidad, i.valor_unitario from public.item_presupuesto i
{vigente}) i
  full join (values"""]
    L.append(",\n".join(f"    ({esc(i['codigo'])}, {round(i['cantidad'], 4)}, {i['vu']:.2f})" for i in items))
    L.append(f"""  ) as v(codigo, cantidad, vu) on v.codigo = i.codigo
  where i.codigo is null or v.codigo is null or i.cantidad <> v.cantidad or abs(i.valor_unitario - v.vu) > 0.01;
  if v_malos is not null then
    raise exception 'Balance · el contrato del balance no es el cargado en estos ítems: %', v_malos;
  end if;
end $$;
""")
    if contractual:
        L.append(f"""-- VALOR CONTRACTUAL del balance (incluye el IVA sobre la utilidad).
update public.proyecto set valor_contrato = {round(contractual)}
 where codigo = {O} and valor_contrato is distinct from {round(contractual)};
""")
    L.append(f"""-- Total a ejecutar y avance de cada ítem del contrato (bloque final del balance).
insert into public.ejecucion_item (item_id, cantidad_proyectada, valor_proyectado, pct_avance)
select i.id, v.cant, v.valor, v.pct
from public.item_presupuesto i
{vigente}
join (values""")
    L.append(",\n".join(
        f"  ({esc(i['codigo'])}, {round(i['cant_final'] or 0, 4)}, {i['valor_final']:.2f}, "
        f"{i['pct'] if i['pct'] is not None and 0 <= i['pct'] <= 1 else 0})" for i in items))
    L.append(""") as v(codigo, cant, valor, pct) on v.codigo = i.codigo
on conflict (item_id) do update set
  cantidad_proyectada = excluded.cantidad_proyectada,
  valor_proyectado    = excluded.valor_proyectado,
  pct_avance          = excluded.pct_avance
where (public.ejecucion_item.cantidad_proyectada, public.ejecucion_item.valor_proyectado,
       public.ejecucion_item.pct_avance)
      is distinct from (excluded.cantidad_proyectada, excluded.valor_proyectado, excluded.pct_avance);
""")
    L.append(f"""-- Las modificaciones del balance son los adicionales: pendientes hasta que el
-- cliente decida. Uno ya decidido o retirado no se toca.
insert into public.adicional (proyecto_id, codigo, capitulo_nombre, descripcion, unidad,
                              cantidad, valor_unitario, aprobacion, reemplaza_item_id, motivo)
select p.id, v.codigo, v.cap, v.descripcion, v.unidad, v.cantidad, v.vu, 'pendiente', r.id, v.motivo
from public.proyecto p
cross join (values""")
    filas = []
    for m in b["mods"]:
        cant, vu = valor_unitario_mod(m)
        rp = mapa.get(m["codigo"])
        motivo = None
        if rp:
            nota = re.sub(r"^MOD-[\d.]+(\s+(Y|A)\s+MOD-[\d.]+)?\s*", "", por_codigo[rp]["obs"], flags=re.I)
            visible = f"{float(rp):.2f}" if re.fullmatch(r"[\d.]+", rp) else rp   # 2.049999999999999 -> 2.05
            motivo = (f"Reemplaza el ítem {visible} del contrato"
                      + (f": {nota[0].lower() + nota[1:]}" if nota else "") + f" (balance del {dia}).")
        filas.append("  ({}, {}, {}, {}, {}, {}, {}, {})".format(
            esc(m["codigo"]), esc(m["capitulo"][:120]), esc(m["descripcion"][:400]), esc(m["unidad"]),
            round(cant, 4), f"{vu:.2f}", esc(rp), esc(motivo)))
    L.append(",\n".join(filas))
    L.append(f""") as v(codigo, cap, descripcion, unidad, cantidad, vu, reemplaza, motivo)
left join lateral (
  select i.id from public.item_presupuesto i
  join public.capitulo c on c.id = i.capitulo_id
  join public.presupuesto pr on pr.id = c.presupuesto_id and pr.vigente
  where pr.proyecto_id = p.id and i.codigo = v.reemplaza
) r on true
where p.codigo = {O}
on conflict (proyecto_id, codigo) do update set
  capitulo_nombre   = excluded.capitulo_nombre,
  descripcion       = excluded.descripcion,
  unidad            = excluded.unidad,
  cantidad          = excluded.cantidad,
  valor_unitario    = excluded.valor_unitario,
  reemplaza_item_id = excluded.reemplaza_item_id,
  motivo            = excluded.motivo
where public.adicional.aprobacion = 'pendiente' and public.adicional.retirado_en is null
  and (public.adicional.capitulo_nombre, public.adicional.descripcion, public.adicional.unidad,
       public.adicional.cantidad, public.adicional.valor_unitario, public.adicional.reemplaza_item_id,
       public.adicional.motivo)
      is distinct from (excluded.capitulo_nombre, excluded.descripcion, excluded.unidad, excluded.cantidad,
                        excluded.valor_unitario, excluded.reemplaza_item_id, excluded.motivo);

-- Lo que ESA había propuesto y ya no está en el balance se retira, con la razón.
-- No se borra: queda la constancia de lo que se le presentó al cliente.
update public.adicional a
   set retirado_en = now(),
       retirado_motivo = 'Ya no está en el balance del {dia} («{ruta.name}»): '
                         'ESA reformuló los adicionales como modificaciones MOD- dentro de cada capítulo.'
  from public.proyecto p
 where p.id = a.proyecto_id and p.codigo = {O}
   and a.aprobacion = 'pendiente' and a.retirado_en is null
   and a.codigo not in ({", ".join(esc(m["codigo"]) for m in b["mods"])});

-- Al final la base tiene que sumar lo que se guardó, al centavo. (Con el Excel
-- difiere solo por el redondeo de las cantidades a cuatro decimales: ver arriba.)
do $$
declare v_contrato numeric; v_final numeric; v_mods int;
begin
  select coalesce(sum(i.valor_parcial), 0), coalesce(sum(e.valor_proyectado), 0)
    into v_contrato, v_final
  from public.item_presupuesto i
{vigente}
  left join public.ejecucion_item e on e.item_id = i.id;
  select v_final + coalesce(sum(a.valor), 0), count(*) into v_final, v_mods
  from public.adicional a join public.proyecto p on p.id = a.proyecto_id and p.codigo = {O}
  where a.retirado_en is null and a.aprobacion <> 'rechazado';
  if abs(v_contrato - {contrato_guardado:.2f}) > 0.05 or abs(v_final - {final_guardado:.2f}) > 0.05
     or v_mods <> {len(b['mods'])} then
    raise exception 'Balance · la base no cuadra con el balance: contrato % (se guardó {contrato_guardado:.2f}), final % (se guardó {final_guardado:.2f}), % adicionales vigentes (balance {len(b["mods"])})',
      v_contrato, v_final, v_mods;
  end if;
end $$;

commit;
""")
    salida.write_text("\n".join(L), encoding="utf-8")


if __name__ == "__main__":
    main()
