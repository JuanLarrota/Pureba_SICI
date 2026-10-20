# -*- coding: utf-8 -*-
"""Prepara las semillas (el histórico y las clasificaciones) para cargarlas a
Supabase por el conector, que solo recibe trozos de texto sin contraseña.

010_historico.sql es una sola transacción con tablas temporales; por el
conector cada trozo es su propia transacción y una tabla temporal no llega al
siguiente. Por eso:
  · las tablas de paso pasan a ser tablas de verdad en «private» (sin acceso
    para nadie de la aplicación) y se borran al final;
  · los VALUES grandes se parten por filas;
  · los catálogos (categorías, personas, proyectos, centros de costo) son
    idempotentes y pueden ir en trozos;
  · los pagos y los ingresos van juntos en el ÚLTIMO trozo: entran todos o
    ninguno, y la guardia del principio impide cargarlos dos veces.
Las demás semillas (020, 030, 050…) van cada una en un solo trozo.

Cada trozo va envuelto con su md5, como en preparar_envios.py.

    python scripts/base/preparar_carga.py <carpeta_de_salida> [tamaño] [semillas…]
"""
import json, re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from preparar_envios import sentencias, sin_comentarios_sueltos, envolver   # noqa: E402

RAIZ = Path(__file__).resolve().parents[2]
PASO = {"movimiento_staging": "private.carga_movimiento", "ingreso_staging": "private.carga_ingreso"}


def sentencias_de(texto):
    partes, ini = [], 0
    for c in sentencias(texto):
        partes.append(texto[ini:c]); ini = c
    if texto[ini:].strip():
        partes.append(texto[ini:])
    return [p for p in (sin_comentarios_sueltos(x).strip() for x in partes) if p and p.lower() not in ("begin;", "commit;")]


def partir_values(sent, tope):
    """Un insert con muchas filas (una por línea) se vuelve varios inserts."""
    m = re.search(r"(values\n|from \(values\n)", sent)
    if not m or len(sent) <= tope:
        return [sent]
    cab = sent[:m.end()]
    resto = sent[m.end():]
    if ") as v(" in resto:
        k = resto.index("\n) as v("); filas, pie = resto[:k], resto[k:]
    elif "\non conflict" in resto:
        k = resto.index("\non conflict"); filas, pie = resto[:k], resto[k:]
    else:
        filas, pie = resto.rstrip(";"), ";"
    filas = filas.split(",\n")
    trozos, grupo, n = [], [], len(cab) + len(pie)
    for f in filas:
        if grupo and n + len(f) + 2 > tope:
            trozos.append(cab + ",\n".join(grupo) + pie); grupo, n = [], len(cab) + len(pie)
        grupo.append(f); n += len(f) + 2
    if grupo:
        trozos.append(cab + ",\n".join(grupo) + pie)
    return trozos


def filas_sql(sent):
    """Lee las tuplas de un «insert … values (…), (…);» generado por el cargador:
    cadenas entre comillas simples (con '' dentro), números y null."""
    cuerpo = sent[sent.index("values\n") + 7:].rstrip().rstrip(";")
    filas, i, n = [], 0, len(cuerpo)
    while i < n:
        if cuerpo[i] != "(":
            i += 1; continue
        i += 1; fila = []
        while True:
            while cuerpo[i] in " \n": i += 1
            if cuerpo[i] == "'":
                j, buf = i + 1, []
                while True:
                    if cuerpo[j] == "'":
                        if j + 1 < n and cuerpo[j + 1] == "'": buf.append("'"); j += 2; continue
                        break
                    buf.append(cuerpo[j]); j += 1
                fila.append("".join(buf)); i = j + 1
            else:
                j = i
                while cuerpo[j] not in ",)": j += 1
                v = cuerpo[i:j].strip(); fila.append(None if v == "null" else v); i = j
            while cuerpo[i] in " \n": i += 1
            if cuerpo[i] == ",": i += 1; continue
            if cuerpo[i] == ")": i += 1; break
        filas.append(fila)
    return filas


def compacto(mov, ing, tope):
    """Las filas de las tablas de paso, compactas: cada texto viaja una vez en un
    diccionario y cada fila es una línea con números separados por tabulador."""
    dic = {}
    k = lambda v: "" if v is None else str(dic.setdefault(v, len(dic) + 1))
    lineas = ["m\t" + "\t".join([f[0], f[1], k(f[2]), k(f[3]), k(f[4]), k(f[5]), "e" if f[6] == "efectivo" else "b"]) for f in mov]
    lineas += ["i\t" + "\t".join([f[0], f[1], k(f[2]), f[3], k(f[4]), k(f[5])]) for f in ing]
    for v in dic:
        assert "\t" not in v and "\n" not in v and "$x$" not in v, v
    sents = []
    def lote(prefijo, items, sufijo):
        grupo, n0 = [], len(prefijo) + len(sufijo)
        n = n0
        for it in items:
            if grupo and n + len(it) + 1 > tope:
                sents.append(prefijo + "\n".join(grupo) + sufijo); grupo, n = [], n0
            grupo.append(it); n += len(it) + 1
        if grupo:
            sents.append(prefijo + "\n".join(grupo) + sufijo)
    lote("insert into private.carga_dic (k, v)\nselect split_part(l, E'\\t', 1)::int, split_part(l, E'\\t', 2)\nfrom unnest(string_to_array($x$",
         [f"{i}\t{v}" for v, i in dic.items()], "$x$, E'\\n')) as l;")
    lote("insert into private.carga_fila (l)\nselect unnest(string_to_array($x$", lineas, "$x$, E'\\n'));")
    return sents


SOLTAR = """insert into private.carga_movimiento (fecha, valor, proyecto, categoria, tercero, concepto, medio)
select split_part(f.l, E'\\t', 2)::date, split_part(f.l, E'\\t', 3)::numeric, p.v, c.v, t.v, k.v,
       case split_part(f.l, E'\\t', 8) when 'e' then 'efectivo' else 'banco' end
from private.carga_fila f
left join private.carga_dic p on p.k = nullif(split_part(f.l, E'\\t', 4), '')::int
left join private.carga_dic c on c.k = nullif(split_part(f.l, E'\\t', 5), '')::int
left join private.carga_dic t on t.k = nullif(split_part(f.l, E'\\t', 6), '')::int
left join private.carga_dic k on k.k = nullif(split_part(f.l, E'\\t', 7), '')::int
where split_part(f.l, E'\\t', 1) = 'm';"""
SOLTAR_ING = """insert into private.carga_ingreso (fecha, valor, proyecto, linea, tercero, concepto)
select split_part(f.l, E'\\t', 2)::date, split_part(f.l, E'\\t', 3)::numeric, p.v, split_part(f.l, E'\\t', 5), t.v, k.v
from private.carga_fila f
left join private.carga_dic p on p.k = nullif(split_part(f.l, E'\\t', 4), '')::int
left join private.carga_dic t on t.k = nullif(split_part(f.l, E'\\t', 6), '')::int
left join private.carga_dic k on k.k = nullif(split_part(f.l, E'\\t', 7), '')::int
where split_part(f.l, E'\\t', 1) = 'i';"""


def historico(texto, tope):
    for viejo, nuevo in PASO.items():
        texto = texto.replace(viejo, nuevo)
    texto = re.sub(r"create temporary table (private\.carga_\w+)", r"create table \1", texto).replace(") on commit drop;", ");")
    sents = sentencias_de(texto)
    mov = next(s for s in sents if s.startswith("insert into private.carga_movimiento"))
    ing = next((s for s in sents if s.startswith("insert into private.carga_ingreso")), None)
    previas = ["drop table if exists private.carga_movimiento;", "drop table if exists private.carga_ingreso;",
               "drop table if exists private.carga_dic;", "drop table if exists private.carga_fila;",
               "create table private.carga_dic (k int primary key, v text not null);",
               "create table private.carga_fila (l text not null);"]
    finales = []
    for s in sents:
        if s.startswith("insert into movimiento\n") or s.startswith("insert into ingreso ("):
            finales.append(s)
        elif s is mov:
            previas.extend(compacto(filas_sql(mov), filas_sql(ing) if ing else [], tope))
            previas.append(SOLTAR)
        elif s is ing:
            previas.append(SOLTAR_ING)
        else:
            previas.extend(partir_values(s, tope))
    finales += ["drop table private.carga_movimiento;", "drop table private.carga_ingreso;",
                "drop table private.carga_dic;", "drop table private.carga_fila;"]
    return previas, finales


def agrupar(sents, tope):
    trozos, actual = [], ""
    for s in sents:
        if actual and len(actual) + len(s) + 2 > tope:
            trozos.append(actual); actual = ""
        actual += s + "\n\n"
    if actual:
        trozos.append(actual)
    return trozos


def main():
    salida = Path(sys.argv[1]); salida.mkdir(parents=True, exist_ok=True)
    tope = int(sys.argv[2]) if len(sys.argv) > 2 else 24000
    semillas = sys.argv[3:] or ["010_historico.sql", "020_nirvana.sql", "030_clasificacion.sql", "050_obras_en_curso.sql"]
    manifiesto, n = [], 0
    for nombre in semillas:
        texto = (RAIZ / "supabase/semilla" / nombre).read_text(encoding="utf-8")
        if nombre.startswith("010"):
            previas, finales = historico(texto, tope)
            trozos = agrupar(previas, tope) + ["\n\n".join(finales) + "\n"]
        else:
            trozos = ["\n\n".join(sentencias_de(texto)) + "\n"]
        for k, t in enumerate(trozos, 1):
            n += 1
            env, h = envolver(t)
            destino = salida / f"{n:02d}_{nombre[:-4]}_{k:02d}.sql"
            destino.write_text(env, encoding="utf-8")
            manifiesto.append(dict(archivo=destino.name, semilla=nombre, parte=k, de=len(trozos), md5=h, envio=len(env)))
    (salida / "manifiesto.json").write_text(json.dumps(manifiesto, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"{len(manifiesto)} envíos · {sum(m['envio'] for m in manifiesto)} bytes · mayor {max(m['envio'] for m in manifiesto)}")
    for m in manifiesto:
        print(f"  {m['archivo']:<34} {m['envio']:>7}")


if __name__ == "__main__":
    main()
