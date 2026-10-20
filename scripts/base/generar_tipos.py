# -*- coding: utf-8 -*-
"""Genera los tipos TypeScript de la base para la aplicación (src/).

Levanta un Postgres temporal con pgserver, aplica el stub de Supabase y las
migraciones (lo mismo que hace la batería de pruebas, sin las semillas reales)
y escribe el tipo `Database` que entiende supabase-js, leyendo el catálogo de
Postgres directamente. La CLI de Supabase haría lo mismo, pero contra una base
local exige Docker, y la Mac de Felipe y esta máquina no lo tienen.

No toca Supabase ni ninguna base de la empresa.

    .venv/Scripts/python scripts/base/generar_tipos.py            # Windows
    .venv/bin/python scripts/base/generar_tipos.py                # Mac

Escribe src/lib/supabase/tipos.ts. Hay que volver a correrlo cada vez que
se agregue una migración: un cambio de columna rompe la compilación, no la
pantalla en el celular.
"""
import sys, tempfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(RAIZ / "supabase/pruebas"))
import probar_contra_postgres as P   # noqa: E402
import pgserver, psycopg2             # noqa: E402

SALIDA = RAIZ / "src/lib/supabase/tipos.ts"
ESQUEMA = "public"

ESCALARES = {
    "text": "string", "varchar": "string", "bpchar": "string", "char": "string", "name": "string", "citext": "string", "uuid": "string",
    "date": "string", "time": "string", "timetz": "string", "timestamp": "string", "timestamptz": "string", "interval": "string",
    "int2": "number", "int4": "number", "int8": "number", "float4": "number", "float8": "number", "numeric": "number", "money": "number", "oid": "number",
    "bool": "boolean", "json": "Json", "jsonb": "Json", "bytea": "string", "inet": "string", "cidr": "string", "macaddr": "string",
    "tsvector": "unknown", "tsquery": "unknown", "record": "Record<string, unknown>", "void": "undefined", "trigger": "unknown", "event_trigger": "unknown",
}


def ts(cur, tipo_oid, enums, tablas):
    """El tipo TypeScript de un tipo de Postgres (por oid)."""
    cur.execute("select t.typname, t.typtype, t.typcategory, t.typelem, n.nspname, t.typrelid from pg_type t join pg_namespace n on n.oid = t.typnamespace where t.oid = %s", (tipo_oid,))
    nombre, clase, categoria, elem, esquema, relid = cur.fetchone()
    if categoria == "A" and elem:
        return ts(cur, elem, enums, tablas) + "[]"
    if clase == "e":
        return f'Database["{ESQUEMA}"]["Enums"]["{nombre}"]' if esquema == ESQUEMA else "string"
    if clase == "d":   # dominio: su tipo base
        cur.execute("select typbasetype from pg_type where oid = %s", (tipo_oid,))
        return ts(cur, cur.fetchone()[0], enums, tablas)
    if clase == "c" and relid:
        if esquema == ESQUEMA and nombre in tablas:
            return f'Database["{ESQUEMA}"]["Tables"]["{nombre}"]["Row"]'
        if esquema == ESQUEMA and nombre in tablas.get("_vistas", ()):
            return f'Database["{ESQUEMA}"]["Views"]["{nombre}"]["Row"]'
        return "Record<string, unknown>"
    return ESCALARES.get(nombre, "unknown")


def columnas(cur, relid, enums, tablas):
    cur.execute("""select a.attname, a.atttypid, a.attnotnull, a.atthasdef, a.attidentity <> '', a.attgenerated <> ''
                     from pg_attribute a where a.attrelid = %s and a.attnum > 0 and not a.attisdropped order by a.attnum""", (relid,))
    return [(n, ts(cur, t, enums, tablas), nn, hd, ident, gen) for n, t, nn, hd, ident, gen in cur.fetchall()]


def relaciones(cur, relid):
    cur.execute("""select c.conname, c.conkey, c.confkey, c.confrelid::regclass::text,
                          exists (select 1 from pg_constraint u where u.conrelid = c.conrelid and u.contype in ('p','u') and u.conkey = c.conkey)
                     from pg_constraint c where c.contype = 'f' and c.conrelid = %s order by c.conname""", (relid,))
    out = []
    for nombre, conkey, confkey, destino, uno in cur.fetchall():
        cur.execute("select attname from pg_attribute where attrelid = %s and attnum = any(%s) order by array_position(%s, attnum)", (relid, conkey, conkey))
        cols = [r[0] for r in cur.fetchall()]
        cur.execute("select attname from pg_attribute where attrelid = %s::regclass and attnum = any(%s) order by array_position(%s, attnum)", (destino, confkey, confkey))
        refs = [r[0] for r in cur.fetchall()]
        destino = destino.split(".")[-1].strip('"')
        out.append(f'          {{ foreignKeyName: "{nombre}"; columns: {lista(cols)}; isOneToOne: {"true" if uno else "false"}; referencedRelation: "{destino}"; referencedColumns: {lista(refs)} }}')
    return out


def lista(xs):
    return "[" + ", ".join(f'"{x}"' for x in xs) + "]"


def bloque(filas, sangria, modo="row"):
    """Las columnas de una fila. En «row» todas vienen; en «insert» sobra lo que
    tiene valor por defecto; en «update» todo es opcional."""
    out = []
    for n, t, nn, hd, ident, gen in filas:
        if gen and modo != "row":
            out.append(f"{sangria}{n}?: never")
            continue
        nulo = "" if nn else " | null"
        opc = "?" if (modo == "update" or (modo == "insert" and (not nn or hd or ident))) else ""
        out.append(f"{sangria}{n}{opc}: {t}{nulo}")
    return "\n".join(out) if out else f"{sangria}[_ in never]: never"


def main():
    carpeta = Path(tempfile.mkdtemp(prefix="sici-tipos-"))
    srv = pgserver.get_server(carpeta, cleanup_mode="delete")
    uri = srv.get_uri()
    for a in [P.STUB] + P.MIGRACIONES:
        ok, msg = P.aplicar(uri, a)
        if not ok:
            sys.exit(f"falló {a.name}: {msg}")
    print("base lista con", len(P.MIGRACIONES), "migraciones")
    con = psycopg2.connect(uri)
    cur = con.cursor()

    cur.execute("select t.typname, array_agg(e.enumlabel order by e.enumsortorder) from pg_type t join pg_namespace n on n.oid = t.typnamespace "
                "join pg_enum e on e.enumtypid = t.oid where n.nspname = %s group by t.typname order by t.typname", (ESQUEMA,))
    enums = dict(cur.fetchall())
    cur.execute("select c.relname, c.oid, c.relkind from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = %s and c.relkind in ('r','p','v','m') order by c.relname", (ESQUEMA,))
    rels = cur.fetchall()
    tablas = {r[0]: r[1] for r in rels if r[2] in ("r", "p")}
    tablas["_vistas"] = {r[0] for r in rels if r[2] in ("v", "m")}

    L = ["export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]", "",
         "export type Database = {", '  __InternalSupabase: { PostgrestVersion: "12" }', f"  {ESQUEMA}: {{", "    Tables: {"]
    for nombre, oid, kind in rels:
        if kind not in ("r", "p"):
            continue
        cols = columnas(cur, oid, enums, tablas)
        rel = relaciones(cur, oid)
        L += [f"      {nombre}: {{", "        Row: {", bloque(cols, "          "), "        }",
              "        Insert: {", bloque(cols, "          ", "insert"), "        }",
              "        Update: {", bloque(cols, "          ", "update"), "        }",
              "        Relationships: [" + ("\n" + ",\n".join(rel) + "\n        ]" if rel else "]"), "      }"]
    L += ["    }", "    Views: {"]
    for nombre, oid, kind in rels:
        if kind not in ("v", "m"):
            continue
        cols = [(n, t, False, True, False, False) for n, t, *_ in columnas(cur, oid, enums, tablas)]   # PostgREST no sabe si una columna de vista es nula
        L += [f"      {nombre}: {{", "        Row: {", bloque(cols, "          "), "        }", "        Relationships: []", "      }"]
    L += ["    }", "    Functions: {"]
    cur.execute("""select p.proname, p.oid, p.proargnames, p.proargmodes, p.proallargtypes, p.proargtypes::oid[], p.prorettype, p.proretset, p.pronargdefaults
                     from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = %s and p.prokind = 'f' order by p.proname, p.oid""", (ESQUEMA,))
    funciones = {}
    for nombre, oid, argnames, argmodes, alltypes, intypes, rettype, retset, ndef in cur.fetchall():
        tipos = list(alltypes) if alltypes else list(intypes)
        modos = list(argmodes) if argmodes else ["i"] * len(tipos)
        nombres = list(argnames) if argnames else [""] * len(tipos)
        entradas = [(nm, t) for nm, t, m in zip(nombres, tipos, modos) if m in ("i", "b", "v")]
        salidas = [(nm, t) for nm, t, m in zip(nombres, tipos, modos) if m in ("o", "t", "b")]
        n_in = len(entradas)
        args = [f"          {nm or 'arg' + str(i)}{'?' if i >= n_in - ndef else ''}: {ts(cur, t, enums, tablas)}" for i, (nm, t) in enumerate(entradas)]
        if salidas and (retset or len(salidas) > 1):
            ret = "{\n" + "\n".join(f"          {nm}: {ts(cur, t, enums, tablas)}" for nm, t in salidas) + "\n        }" + ("[]" if retset else "")
        else:
            ret = ts(cur, rettype, enums, tablas) + ("[]" if retset else "")
        funciones.setdefault(nombre, []).append(("{\n" + "\n".join(args) + "\n        }" if args else "Record<PropertyKey, never>", ret))
    for nombre, variantes in funciones.items():
        if len(variantes) == 1:
            a, r = variantes[0]
            L += [f"      {nombre}: {{", f"        Args: {a}", f"        Returns: {r}", "      }"]
        else:
            L += [f"      {nombre}:"] + [f"        | {{ Args: {a}; Returns: {r} }}" for a, r in variantes]
    L += ["    }", "    Enums: {"]
    for nombre, valores in enums.items():
        L.append(f"      {nombre}: " + " | ".join(f'"{v}"' for v in valores))
    L += ["    }", "    CompositeTypes: {", "      [_ in never]: never", "    }", "  }", "}", ""]
    # Los ayudantes que supabase-js y el código de la aplicación usan para nombrar filas.
    L += ['type EsquemaPublico = Database["public"]',
          'export type Tabla<T extends keyof EsquemaPublico["Tables"]> = EsquemaPublico["Tables"][T]["Row"]',
          'export type Vista<T extends keyof EsquemaPublico["Views"]> = EsquemaPublico["Views"][T]["Row"]',
          'export type Enum<T extends keyof EsquemaPublico["Enums"]> = EsquemaPublico["Enums"][T]',
          'export type Funcion<T extends keyof EsquemaPublico["Functions"]> = EsquemaPublico["Functions"][T]', ""]
    cabecera = ("// Generado por scripts/base/generar_tipos.py desde las migraciones de supabase/migrations.\n"
                "// No se edita a mano: se vuelve a generar cuando cambia la base.\n\n")
    SALIDA.parent.mkdir(parents=True, exist_ok=True)
    SALIDA.write_text(cabecera + "\n".join(L), encoding="utf-8", newline="\n")
    n_t = len(tablas) - 1
    print(f"escrito {SALIDA.relative_to(RAIZ)} · {n_t} tablas, {len(tablas['_vistas'])} vistas, {len(funciones)} funciones, {len(enums)} enums")
    con.close()
    srv.cleanup()


if __name__ == "__main__":
    main()
