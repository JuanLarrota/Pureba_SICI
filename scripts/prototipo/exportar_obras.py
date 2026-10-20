# -*- coding: utf-8 -*-
"""Exporta lo que la base sabe de cada obra en construcción, para el módulo de
obra del prototipo de la plataforma: pagos por categoría, por mes y por tercero.

Carga el histórico real en una base temporal (supabase/semilla/010 y 020, que no
están en el repositorio) y saca los resúmenes. El archivo que escribe contiene
datos reales de la empresa: no va al repositorio.

    .venv/bin/python scripts/prototipo/exportar_obras.py obras.json
"""
import json, sys, tempfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(RAIZ / "supabase/pruebas"))
import probar_contra_postgres as P   # noqa: E402
import pgserver, psycopg2            # noqa: E402


def main():
    srv = pgserver.get_server(Path(tempfile.mkdtemp(prefix="sici-obras-")), cleanup_mode="delete")
    uri = srv.get_uri()
    for a in [P.STUB] + P.MIGRACIONES + P.SEMILLA:
        ok, msg = P.aplicar(uri, a)
        assert ok, (a.name, msg)
    cur = psycopg2.connect(uri).cursor()

    def filas(sql, params=None):
        cur.execute(sql, params)
        cols = [c.name for c in cur.description]
        return [dict(zip(cols, r)) for r in cur.fetchall()]

    corte = filas("select max(fecha) as f from movimiento")[0]["f"]
    # En construcción: obras con pagos en los 90 días anteriores al corte del libro.
    obras = filas("""
      select p.id::text, p.codigo, p.valor_contrato::float as contrato,
             count(m.id) as pagos, sum(m.valor)::float as pagado,
             sum(m.valor) filter (where m.fecha >= date_trunc('year', %s::date))::float as pagado_anio,
             min(m.fecha) as primer_pago, max(m.fecha) as ultimo_pago
      from proyecto p join movimiento m on m.proyecto_id = p.id
      where p.tipo = 'obra'
      group by p.id having max(m.fecha) >= %s::date - 90
      order by sum(m.valor) desc""", (corte, corte))
    for o in obras:
        pid = o.pop("id")
        o["categorias"] = filas("""select c.nombre, sum(m.valor)::float as valor, count(*) as pagos
                                   from movimiento m join centro_costo cc on cc.id = m.centro_costo_id
                                   join categoria_costo c on c.id = cc.categoria_id
                                   where m.proyecto_id = %s group by 1 order by 2 desc""", (pid,))
        o["meses"] = filas("""select to_char(date_trunc('month', m.fecha), 'YYYY-MM') as mes, sum(m.valor)::float as egresos, count(*) as pagos
                              from movimiento m where m.proyecto_id = %s group by 1 order by 1""", (pid,))
        o["terceros"] = filas("""select coalesce(t.nombre, m.tercero_nombre, 'Sin tercero') as nombre, sum(m.valor)::float as valor, count(*) as pagos
                                 from movimiento m left join persona t on t.id = m.tercero_id
                                 where m.proyecto_id = %s group by 1 order by 2 desc limit 5""", (pid,))
        o["ultimos"] = filas("""select m.fecha, coalesce(t.nombre, m.tercero_nombre, 'Sin tercero') as tercero, m.concepto, m.valor::float as valor,
                                       c.nombre as categoria,
                                       exists (select 1 from evidencia e where e.movimiento_id = m.id) as con_soporte
                                from movimiento m left join persona t on t.id = m.tercero_id
                                join centro_costo cc on cc.id = m.centro_costo_id join categoria_costo c on c.id = cc.categoria_id
                                where m.proyecto_id = %s order by m.fecha desc, m.valor desc limit 8""", (pid,))
        o["cobros"] = filas("select count(*) as n, coalesce(sum(valor), 0)::float as valor from ingreso where proyecto_id = %s", (pid,))[0]
        o["documentos"] = filas("select count(*) as n from evidencia where proyecto_id = %s", (pid,))[0]["n"]
        o["bitacoras"] = filas("select count(*) as n from bitacora where proyecto_id = %s", (pid,))[0]["n"]
        o["pendientes"] = filas("select count(*) as n from pendiente_obra where proyecto_id = %s", (pid,))[0]["n"]
    Path(sys.argv[1]).write_text(json.dumps({"corte": corte, "obras": obras}, ensure_ascii=False, indent=1, default=str), encoding="utf-8")
    print("escrito", sys.argv[1], "·", len(obras), "obras · corte", corte)


if __name__ == "__main__":
    main()
