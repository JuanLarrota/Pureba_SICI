#!/usr/bin/env python3
"""
SICI · prueba de la base de datos contra un Postgres real que imita Supabase.

En una base temporal que se borra al terminar:
  1. Aplica las migraciones dos veces y exige que la segunda no cambie nada.
     Aplica además el paquete todo-en-uno en otra base configurada con los
     permisos automáticos de los proyectos viejos de Supabase.
  2. Revisa lo mismo que el asesor de seguridad y rendimiento de Supabase.
  3. Carga el histórico real y lo compara con el libro mayor.
  4. a 8. Prueba las reglas de control de cada módulo.
  9. Prueba los permisos con sesiones reales de cada rol, las fotos y el
     enlace de usuarios.

Si todo pasa, escribe supabase/sici_todo_en_uno.sql.
No toca Supabase ni ninguna base de la empresa.

Uso:
  python3 -m venv .venv && .venv/bin/pip install -r scripts/base/requirements.txt
  .venv/bin/python supabase/pruebas/probar_contra_postgres.py
"""

import json
import re
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

try:
    import pgserver
    import psycopg2
except ImportError:
    sys.exit("Faltan dependencias:  pip install pgserver psycopg2-binary")

RAIZ = Path(__file__).resolve().parents[2]          # la raíz del repositorio
MIGRACIONES = sorted((RAIZ / "supabase/migrations").glob("*.sql"))
SEMILLA = [RAIZ / "supabase/semilla/010_historico.sql",
           RAIZ / "supabase/semilla/020_nirvana.sql",
           RAIZ / "supabase/semilla/030_clasificacion.sql",
           RAIZ / "supabase/semilla/040_plantillas.sql",
           RAIZ / "supabase/semilla/050_obras_en_curso.sql"]
# El balance de Nirvana del 9 de octubre (etl/cargar_balance_obra.py) se aplica
# encima de la carga de agosto, como en producción: la prueba mira el antes y el después.
BALANCE_NIRVANA = RAIZ / "supabase/semilla/025_nirvana_balance.sql"
RESUMEN = RAIZ / "supabase/semilla/_resumen.txt"
STUB = RAIZ / "supabase/pruebas/stub_supabase.sql"
PAQUETE = RAIZ / "supabase/sici_todo_en_uno.sql"
PSQL = Path(pgserver.__file__).parent / "pginstall/bin/psql"

REGISTRADOR = "Carga histórica · libro mayor"

# Usuarios de prueba: nombre -> (uuid de Supabase, rol, interno)
USUARIOS = {
    "felipe":     ("00000000-0000-4000-8000-0000000000fc", "socio",       True),
    "luisa":      ("00000000-0000-4000-8000-0000000000a1", "director",    True),
    "andres":     ("00000000-0000-4000-8000-0000000000e5", "residente",   True),
    "mariana":    ("00000000-0000-4000-8000-0000000000b2", "practicante", True),
    "arquitecto": ("00000000-0000-4000-8000-0000000000c3", "arquitecto",  True),
    "alison":     ("00000000-0000-4000-8000-0000000000d4", "mercadeo",    True),
    "finanzas":   ("00000000-0000-4000-8000-0000000000f6", "financiero",  True),
    "cliente":    ("00000000-0000-4000-8000-000000000c11", "cliente",     False),
}

resultados = []


def registrar(nombre, ok, detalle=""):
    resultados.append((nombre, bool(ok), detalle))
    print(f"  {'✓' if ok else '✗'} {nombre}" + (f"  · {detalle}" if detalle else ""))


def seccion(titulo):
    print("\n" + titulo)
    print("-" * len(titulo))


def aplicar(uri, archivo):
    """Una sola transacción por archivo; se detiene al primer error."""
    # La URI va al final: el psql de Windows ignora las opciones que vengan después de ella.
    r = subprocess.run(
        [str(PSQL), "-X", "-q", "-v", "ON_ERROR_STOP=1", "-1", "-f", str(archivo), uri],
        capture_output=True, text=True,
    )
    salida = (r.stderr or "").strip()
    errores = [l for l in salida.splitlines() if "ERROR" in l]
    return r.returncode == 0, (errores[0] if errores else salida[:300])


def uno(cur, sql, params=None):
    cur.execute(sql, params)
    fila = cur.fetchone()
    if fila is None:
        return None
    return fila[0] if len(fila) == 1 else fila


def todas(cur, sql, params=None):
    cur.execute(sql, params)
    return cur.fetchall()


def espera_error(cur, sql, params, fragmento):
    try:
        cur.execute(sql, params)
    except psycopg2.Error as e:
        msg = (e.pgerror or str(e)).strip().splitlines()[0]
        return fragmento.lower() in msg.lower(), msg
    return False, "no dio error"


def sesion(uri, uid, rol="authenticated"):
    """Una sesión de la aplicación: rol sin privilegios y, si hay usuario, su token."""
    con = psycopg2.connect(uri)
    con.autocommit = True
    cur = con.cursor()
    cur.execute(f"set role {rol}")
    if uid:
        cur.execute("select set_config('request.jwt.claims', %s, false)",
                    (json.dumps({"sub": uid, "role": rol}),))
    return con, cur


def cerca(a, b, tolerancia):
    return abs(float(a) - float(b)) <= tolerancia


def otra_base(uri, nombre):
    if "/postgres?" in uri:
        return uri.replace("/postgres?", f"/{nombre}?", 1)
    return re.sub(r"/postgres$", f"/{nombre}", uri)


def inventario(cur):
    return uno(cur, """
      select (select count(*) from pg_tables where schemaname = 'public'),
             (select count(*) from pg_policies where schemaname in ('public','storage')),
             (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid
                join pg_namespace n on n.oid = c.relnamespace
               where n.nspname in ('public','auth') and not t.tgisinternal),
             (select count(*) from pg_indexes where schemaname = 'public'),
             (select count(*) from pg_views where schemaname = 'public'),
             (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname in ('public','private')),
             (select count(*) from pg_type t join pg_namespace n on n.oid = t.typnamespace
               where n.nspname = 'public' and t.typtype = 'e'),
             (select count(*) from public.parametro),
             (select count(*) from public.regla_alerta),
             (select count(*) from storage.buckets)""")


def esperado():
    t = RESUMEN.read_text(encoding="utf-8")
    n = lambda s: int(s.replace(",", ""))
    mov = re.search(r"TOTAL\s+(\d+)\s+movimientos\s+\$\s*([\d,]+)", t)
    pre = re.search(r"presupuesto\s+\$\s*([\d,]+)", t)
    adi = re.search(r"adicionales\s+\$\s*([\d,]+)", t)
    return n(mov.group(1)), n(mov.group(2)), n(pre.group(1)), n(adi.group(1))


# =============================================================================
# 1 · Migraciones
# =============================================================================
def s1_migraciones(uri, cur):
    seccion("1 · Migraciones, idempotencia y paquete todo-en-uno")
    ok, msg = aplicar(uri, STUB)
    registrar("imitación de Supabase (auth, storage, roles)", ok, "" if ok else msg)
    if not ok:
        return None

    for archivo in MIGRACIONES:
        ok, msg = aplicar(uri, archivo)
        registrar(f"{archivo.name} · primera pasada", ok, "" if ok else msg)
        if not ok:
            return None
    antes = inventario(cur)

    for archivo in MIGRACIONES:
        ok, msg = aplicar(uri, archivo)
        if not ok:
            registrar(f"{archivo.name} · segunda pasada", ok, msg)
            return None
    registrar(f"las {len(MIGRACIONES)} migraciones · segunda pasada sin error", True)
    despues = inventario(cur)
    registrar("la segunda pasada no duplica nada", antes == despues,
              f"tablas {despues[0]} · políticas {despues[1]} · disparadores {despues[2]} · "
              f"índices {despues[3]} · vistas {despues[4]} · funciones {despues[5]} · "
              f"tipos {despues[6]} · reglas de alerta {despues[8]} · depósitos {despues[9]}")

    # Paquete todo-en-uno: las mismas migraciones, en orden, en un solo archivo.
    cabecera = (
        "-- =============================================================================\n"
        "-- SICI · PAQUETE TODO-EN-UNO · generado por pruebas/probar_contra_postgres.py\n"
        f"-- {datetime.now():%Y-%m-%d %H:%M} · No editar: se regenera desde supabase/migrations/.\n"
        "-- Para pegar de una sola vez en el editor SQL de Supabase. Contiene, en orden:\n"
        + "".join(f"--   {a.name}\n" for a in MIGRACIONES)
        + "-- =============================================================================\n\n")
    cuerpo = "".join(
        f"\n\n-- >>>>>>>>>>>>>>>>>>>> {a.name} >>>>>>>>>>>>>>>>>>>>\n\n" + a.read_text(encoding="utf-8")
        for a in MIGRACIONES)
    paquete = Path(tempfile.mkdtemp(prefix="sici-paquete-")) / PAQUETE.name
    paquete.write_text(cabecera + cuerpo, encoding="utf-8")

    cur.execute("create database sici_permisos_viejos")
    uv = otra_base(uri, "sici_permisos_viejos")
    ok, msg = aplicar(uv, STUB)
    con_v = psycopg2.connect(uv)
    con_v.autocommit = True
    cv = con_v.cursor()
    cv.execute("""
      alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
      alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
      alter default privileges in schema public grant all on functions to anon, authenticated, service_role;""")
    ok, msg = aplicar(uv, paquete)
    registrar("el paquete todo-en-uno se aplica en un proyecto con los permisos automáticos viejos",
              ok, "" if ok else msg)
    if ok:
        anon = uno(cv, """select count(*) from information_schema.role_table_grants
                          where grantee = 'anon' and table_schema = 'public'""")
        borrar = [r[0] for r in todas(cv, """select table_name from information_schema.role_table_grants
                          where grantee = 'authenticated' and table_schema = 'public'
                            and privilege_type = 'DELETE' order by 1""")]
        registrar("con permisos viejos, anon igual queda sin ningún permiso", anon == 0, f"{anon} permisos")
        registrar("con permisos viejos, nadie puede borrar salvo un acceso", borrar == ["acceso_proyecto"],
                  ", ".join(borrar))
    con_v.close()
    return paquete


# =============================================================================
# 2 · Lo que revisa el asesor de Supabase
# =============================================================================
def s2_asesor(cur):
    seccion("2 · Asesor de seguridad y rendimiento de Supabase")

    sin_rls = todas(cur, """select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
                            where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity""")
    registrar("0013 · todas las tablas públicas con permisos por fila", not sin_rls, str(sin_rls)[:200])

    sin_politica = todas(cur, """select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
                                 where n.nspname = 'public' and c.relkind = 'r'
                                   and not exists (select 1 from pg_policies p
                                                   where p.schemaname = 'public' and p.tablename = c.relname)""")
    registrar("0008 · ninguna tabla con permisos por fila y sin políticas", not sin_politica, str(sin_politica)[:200])

    sin_pk = todas(cur, """select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
                           where n.nspname = 'public' and c.relkind = 'r'
                             and not exists (select 1 from pg_constraint k where k.conrelid = c.oid and k.contype = 'p')""")
    registrar("0004 · todas las tablas con llave primaria", not sin_pk, str(sin_pk)[:200])

    fk_sin_indice = todas(cur, """
      select k.conrelid::regclass::text || '.' || k.conname
      from pg_constraint k
      where k.contype = 'f' and k.connamespace = 'public'::regnamespace
        and not exists (
          select 1 from pg_index i
          where i.indrelid = k.conrelid
            and (select array_agg(x order by x)
                 from unnest((string_to_array(i.indkey::text, ' ')::int2[])[1:cardinality(k.conkey)]) x)
              = (select array_agg(x order by x) from unnest(k.conkey) x))""")
    registrar("0001 · toda llave foránea con índice", not fk_sin_indice, str(fk_sin_indice)[:300])

    vistas_definer = todas(cur, """select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
                                   where n.nspname = 'public' and c.relkind = 'v'
                                     and not coalesce(c.reloptions @> '{security_invoker=true}', false)""")
    registrar("0010 · ninguna vista se salta los permisos por fila", not vistas_definer, str(vistas_definer)[:200])

    sin_search_path = todas(cur, """select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                                    where n.nspname in ('public','private')
                                      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c
                                                      where c like 'search_path=%%')""")
    registrar("0011 · todas las funciones con search_path fijo", not sin_search_path, str(sin_search_path)[:200])

    definer_publicas = todas(cur, """select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                                     where n.nspname = 'public' and p.prosecdef""")
    registrar("0028 · 0029 · ninguna función con privilegios de dueño expuesta en la API",
              not definer_publicas, str(definer_publicas))

    duplicadas = todas(cur, """
      with p as (
        select schemaname, tablename, unnest(roles) as rol,
               unnest(case when cmd = 'ALL' then array['SELECT','INSERT','UPDATE','DELETE'] else array[cmd] end) as cmd
        from pg_policies where permissive = 'PERMISSIVE' and schemaname in ('public','storage'))
      select tablename, rol, cmd, count(*) from p group by 1, 2, 3 having count(*) > 1""")
    registrar("0006 · una sola política por tabla, rol y operación", not duplicadas, str(duplicadas)[:300])

    por_fila = []
    for tabla, nombre, qual, check in todas(cur, """select tablename, policyname, coalesce(qual, ''), coalesce(with_check, '')
                                                    from pg_policies where schemaname = 'public'"""):
        texto = qual + " " + check
        if "auth." in texto:
            por_fila.append(nombre)
        for m in re.finditer(r"private\.\w+\(\)", texto):
            if not texto[max(0, m.start() - 9):m.start()].upper().endswith("SELECT "):
                por_fila.append(nombre)
                break
    registrar("0003 · las funciones de identidad se calculan una vez por consulta, no por fila",
              not por_fila, str(por_fila)[:300])

    roles_raros = todas(cur, """select tablename, policyname, roles from pg_policies
                                where schemaname = 'public' and roles <> '{authenticated}'""")
    registrar("todas las políticas aplican solo a usuarios con sesión", not roles_raros, str(roles_raros)[:200])

    anon = todas(cur, """select table_name, privilege_type from information_schema.role_table_grants
                         where grantee = 'anon' and table_schema = 'public'""")
    anon_fn = todas(cur, """select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                            where n.nspname in ('public','private') and has_function_privilege('anon', p.oid, 'execute')""")
    registrar("anon (la llave pública sin sesión) no puede leer ni ejecutar nada",
              not anon and not anon_fn and not uno(cur, "select has_schema_privilege('anon', 'private', 'usage')"),
              f"tablas {len(anon)} · funciones {len(anon_fn)}")

    borrar = [r[0] for r in todas(cur, """select table_name from information_schema.role_table_grants
                                          where grantee = 'authenticated' and table_schema = 'public'
                                            and privilege_type = 'DELETE' order by 1""")]
    registrar("nadie puede borrar, salvo retirar un acceso a un proyecto", borrar == ["acceso_proyecto"], ", ".join(borrar))

    necesarios = uno(cur, """select has_table_privilege('authenticated', 'public.movimiento', 'INSERT')
                               and has_table_privilege('authenticated', 'public.v_balance_centro_costo', 'SELECT')
                               and has_table_privilege('authenticated', 'public.dedicacion', 'UPDATE')
                               and not has_table_privilege('authenticated', 'public.evento_auditoria', 'INSERT')
                               and has_function_privilege('authenticated', 'public.distribuir_estructura(date)', 'execute')
                               and not has_function_privilege('authenticated', 'private.generar_alertas()', 'execute')""")
    registrar("la aplicación tiene exactamente los permisos que necesita (proyectos nuevos de Supabase)", necesarios)

    en_public = todas(cur, """select e.extname from pg_extension e join pg_namespace n on n.oid = e.extnamespace
                              where n.nspname = 'public'""")
    registrar("0014 · ninguna extensión en el esquema público", not en_public, str(en_public))


# =============================================================================
# 3 · Histórico real
# =============================================================================
def s3_historico(uri, cur):
    seccion("3 · Carga del histórico real")
    for archivo in SEMILLA:
        ok, msg = aplicar(uri, archivo)
        registrar(archivo.name, ok, "" if ok else msg)
        if not ok:
            return False

    ok, msg = aplicar(uri, SEMILLA[0])
    registrar("cargar el histórico por segunda vez se rechaza", (not ok) and "ya está cargado" in msg, msg)
    ok, msg = aplicar(uri, SEMILLA[2])
    registrar("la clasificación se puede volver a correr sin efecto", ok, "" if ok else msg)
    antes = uno(cur, "select (select count(*) from plantilla_fase), (select count(*) from plantilla_tarea), (select count(*) from festivo)")
    ok, msg = aplicar(uri, SEMILLA[3])
    despues = uno(cur, "select (select count(*) from plantilla_fase), (select count(*) from plantilla_tarea), (select count(*) from festivo)")
    registrar("las plantillas se pueden volver a correr sin duplicar nada", ok and antes == despues,
              msg if not ok else f"{despues[0]} fases · {despues[1]} tareas típicas · {despues[2]} festivos")

    n_mov, v_mov, v_pre, v_adi = esperado()
    cnt, suma = uno(cur, """select count(*), coalesce(sum(m.valor), 0) from movimiento m
                            join persona p on p.id = m.registrado_por where p.nombre = %s""", (REGISTRADOR,))
    registrar("pagos cargados = pagos del libro", cnt == n_mov and cerca(suma, v_mov, 1),
              f"{cnt:,} por ${float(suma):,.0f} · el libro dice {n_mov:,} por ${v_mov:,}")
    ing = re.search(r"EN TOTAL\s+(\d+)\s+ingresos\s+\$\s*([\d,]+)", RESUMEN.read_text(encoding="utf-8"))
    if ing:
        n_ing, v_ing = int(ing.group(1)), int(ing.group(2).replace(",", ""))
        cnt, suma = uno(cur, """select count(*), coalesce(sum(i.valor), 0) from ingreso i
                                join persona p on p.id = i.registrado_por where p.nombre = %s""", (REGISTRADOR,))
        registrar("ingresos cargados = entradas del libro", cnt == n_ing and cerca(suma, v_ing, 1),
                  f"{cnt:,} por ${float(suma):,.0f} · el libro dice {n_ing:,} por ${v_ing:,}")
    registrar("los alquileres quedaron en una sola categoría",
              todas(cur, "select nombre from categoria_costo where nombre like 'ALQUILER%%' order by 1") == [("ALQUILERES Y EQUIPOS",)])

    pre = uno(cur, """select coalesce(sum(i.valor_parcial), 0) from item_presupuesto i
                      join capitulo c on c.id = i.capitulo_id join presupuesto pr on pr.id = c.presupuesto_id
                      join proyecto p on p.id = pr.proyecto_id where p.codigo = 'OBRA NIRVANA'""")
    registrar("presupuesto de Nirvana = SUBTOTAL (1) del Excel", cerca(pre, v_pre, v_pre * 0.001),
              f"${float(pre):,.2f} · Excel ${v_pre:,} · diferencia ${float(pre) - v_pre:,.2f}")

    adi = uno(cur, "select bruto, cantidad, pendientes from v_adicionales_netos where proyecto = 'OBRA NIRVANA'")
    registrar("adicionales de Nirvana = Excel", adi and cerca(adi[0], v_adi, v_adi * 0.001),
              f"${float(adi[0]):,.2f} · Excel ${v_adi:,} · diferencia ${float(adi[0]) - v_adi:,.2f}")
    registrar("los 70 adicionales entran pendientes", adi and adi[1] == 70 and adi[2] == 70,
              f"{adi[1]} adicionales, {adi[2]} pendientes")

    # ---------- el balance del 9 de octubre, encima ----------
    ok, msg = aplicar(uri, BALANCE_NIRVANA)
    registrar(BALANCE_NIRVANA.name, ok, "" if ok else msg)
    if not ok:
        return False
    contrato, final_ = (float(x) for x in re.search(
        r"if abs\(v_contrato - ([\d.]+)\).*?abs\(v_final - ([\d.]+)\)", BALANCE_NIRVANA.read_text(encoding="utf-8")).groups())
    n_mods = int(re.search(r"v_mods <> (\d+)", BALANCE_NIRVANA.read_text(encoding="utf-8")).group(1))
    adi = uno(cur, "select bruto, cantidad, pendientes from v_adicionales_netos where proyecto = 'OBRA NIRVANA'")
    retirados = uno(cur, """select count(*) from adicional a join proyecto p on p.id = a.proyecto_id
                            where p.codigo = 'OBRA NIRVANA' and a.retirado_en is not null and a.codigo like 'AD-%%'
                              and a.retirado_motivo like '%%09-10-2026%%'""")
    registrar("balance 09-10 · los 70 adicionales AD- de agosto quedan retirados, con la razón; no se borran",
              retirados == 70 and uno(cur, "select count(*) from adicional where codigo like 'AD-%%'") == 70, f"{retirados} retirados")
    registrar("balance 09-10 · las modificaciones MOD- son los adicionales vigentes, todos pendientes",
              adi and adi[1] == n_mods and adi[2] == n_mods
              and uno(cur, "select count(*) from adicional where retirado_en is null and codigo not like 'MOD-%%'") == 0,
              f"{adi[1]} vigentes, {adi[2]} pendientes")
    fin = uno(cur, """select sum(e.valor_proyectado) from ejecucion_item e join item_presupuesto i on i.id = e.item_id
                      join capitulo c on c.id = i.capitulo_id join presupuesto pr on pr.id = c.presupuesto_id and pr.vigente
                      join proyecto p on p.id = pr.proyecto_id where p.codigo = 'OBRA NIRVANA'""")
    registrar("balance 09-10 · contrato ejecutado + modificaciones = valor final del balance",
              cerca(float(fin) + float(adi[0]), final_, 2), f"${float(fin) + float(adi[0]):,.2f} · balance ${final_:,.2f}")
    registrar("balance 09-10 · el contrato no cambió", cerca(pre, contrato, 2), f"${float(pre):,.2f}")
    registrar("balance 09-10 · el valor contractual incluye el IVA sobre la utilidad",
              uno(cur, "select valor_contrato from proyecto where codigo = 'OBRA NIRVANA'") == 584947782)
    credito = uno(cur, """select coalesce(sum(greatest(i.valor_parcial - coalesce(e.valor_proyectado, 0), 0)), 0)
                          from item_presupuesto i left join ejecucion_item e on e.item_id = i.id
                          where i.id in (select reemplaza_item_id from adicional where codigo like 'MOD-%%')""")
    registrar("balance 09-10 · el crédito sale de los ítems que reemplazan las modificaciones, no de lo retirado",
              cerca(uno(cur, "select credito from v_adicionales_netos where proyecto = 'OBRA NIRVANA'"), credito, 0.01),
              f"crédito ${float(credito):,.0f}")
    registrar("balance 09-10 · cada modificación que reemplaza un ítem lo dice, con la nota del balance",
              uno(cur, """select count(*) from adicional where codigo = 'MOD-12.07' and retirado_en is null
                          and reemplaza_item_id = (select id from item_presupuesto where codigo = '12.04')
                          and motivo like 'Reemplaza el ítem 12.04%%'""") == 1)
    antes = todas(cur, """select a.codigo, a.cantidad, a.valor_unitario, a.retirado_en, e.valor_proyectado
                          from adicional a full join ejecucion_item e on false order by 1, 5""")
    audit = uno(cur, "select count(*) from evento_auditoria")
    ok, msg = aplicar(uri, BALANCE_NIRVANA)
    registrar("balance 09-10 · correrlo otra vez no cambia nada",
              ok and todas(cur, """select a.codigo, a.cantidad, a.valor_unitario, a.retirado_en, e.valor_proyectado
                                   from adicional a full join ejecucion_item e on false order by 1, 5""") == antes
              and uno(cur, "select count(*) from evento_auditoria") == audit, msg if not ok else "")

    registrar("ningún proveedor quedó como socio",
              uno(cur, "select count(*) from persona where rol = 'socio' and auth_user_id is null") == 0)
    grandes = uno(cur, "select count(*) from movimiento where conciliado and valor >= 2000000")
    pend = uno(cur, "select count(*) from movimiento where conciliado and aprobacion = 'pendiente'")
    registrar("el histórico no genera aprobaciones pendientes", grandes > 0 and pend == 0,
              f"{grandes} pagos históricos sobre el umbral, {pend} pendientes")
    registrar("todo movimiento tiene raíz de cadena",
              uno(cur, "select count(*) from movimiento where raiz_id is null") == 0)

    excluidas = uno(cur, "select count(*) from categoria_costo where excluir_de_rentabilidad")
    socios = uno(cur, "select tipo from proyecto where codigo = 'SOCIOS'")
    registrar("las cinco obras con pagos recientes quedan en curso; las demás, terminadas",
              todas(cur, "select codigo from proyecto where tipo = 'obra' and estado = 'activo' order by 1")
              == [("BODEGA SAKER",), ("BODEGA TERRANO",), ("OBRA CALI",), ("OBRA KOLIBRI",), ("OBRA NIRVANA",)])
    registrar("F5 · préstamos, socios y traslados quedan fuera de la rentabilidad",
              excluidas == 11 and socios == "interno", f"{excluidas} categorías · SOCIOS es {socios}")
    reservadas = uno(cur, "select count(*) from categoria_costo where reservada")
    registrar("F7 · préstamos, créditos y socios quedan reservados; los traslados no",
              reservadas == 10 and uno(cur, "select reservado from proyecto where codigo = 'SOCIOS'")
              and not uno(cur, "select reservada from categoria_costo where nombre = 'TRASLADO ENTRE CUENTAS'"), f"{reservadas} categorías")
    return True


# =============================================================================
# Personas y accesos de prueba
# =============================================================================
def preparar(cur):
    P = {}
    for nombre, (uid, rol, interno) in USUARIOS.items():
        correo = f"{nombre}@prueba.local"
        cur.execute("insert into auth.users (id, email, email_confirmed_at) values (%s, %s, now())", (uid, correo))
        cur.execute("""insert into persona (nombre, rol, es_interno, auth_user_id, correo, horas_semana, creado_en)
                       values (%s, %s, %s, %s, %s, %s, now() - interval '60 days') returning id""",
                    (f"PRUEBA {nombre.capitalize()}", rol, interno, uid, correo,
                     40 if rol in ("director", "arquitecto", "practicante") else 0))
        P[nombre] = cur.fetchone()[0]
    nirv = uno(cur, "select id from proyecto where codigo = 'OBRA NIRVANA'")
    cur.execute("""insert into acceso_proyecto (persona_id, proyecto_id, nivel)
                   values (%s, %s, 'registro'), (%s, %s, 'lectura')""", (P["andres"], nirv, P["cliente"], nirv))
    cur.execute("""update proyecto set residente_id = %s, responsable_id = %s,
                          fecha_inicio = private.hoy() - 20 where id = %s""", (P["andres"], P["luisa"], nirv))
    return P, nirv


# =============================================================================
# 4 · Obra y dinero
# =============================================================================
def s4_obra(cur, P, nirv):
    seccion("4 · Obra y dinero · M-01 y M-03")

    def centro(nombre):
        cur.execute("""insert into centro_costo (proyecto_id, categoria_id)
                       select %s, id from categoria_costo where nombre = %s
                       on conflict (proyecto_id, categoria_id) do nothing""", (nirv, nombre))
        return uno(cur, """select cc.id from centro_costo cc join categoria_costo c on c.id = cc.categoria_id
                           where cc.proyecto_id = %s and c.nombre = %s""", (nirv, nombre))

    cc_contr, cc_prov = centro("CONTRATISTAS"), centro("PROVEEDORES")

    def mov(**k):
        base = dict(proyecto_id=nirv, centro_costo_id=cc_contr, estado="compromiso", valor=1000000,
                    tercero_nombre="PRUEBA", concepto="prueba", medio="no_aplica", registrado_por=P["andres"])
        base.update(k)
        cols = ", ".join(base)
        marcas = ", ".join(["%s"] * len(base))
        cur.execute(f"insert into movimiento ({cols}) values ({marcas}) returning id, aprobacion",
                    list(base.values()))
        return cur.fetchone()

    def balance(cc):
        cur.execute("select proyectado, por_pagar from v_balance_centro_costo where centro_costo_id = %s", (cc,))
        return tuple(float(x) for x in cur.fetchone())

    base_proy, base_pp = balance(cc_contr)

    m1, ap = mov(valor=8400000, tercero_nombre="Gerardo Maestro", concepto="Carpintería de madera")
    registrar("T4 · un compromiso de $8.400.000 queda pendiente de aprobación", ap == "pendiente", ap)
    _, ap = mov(valor=1480000, centro_costo_id=cc_prov, tercero_nombre="La Gran Ferretería")
    registrar("T4 · uno de $1.480.000 no pide aprobación", ap == "no_requiere", ap)

    ok, msg = espera_error(cur, "delete from movimiento where id = %s", (m1,), "no se borran")
    registrar("T3 · un movimiento no se borra", ok, msg)
    ok, msg = espera_error(cur, "update movimiento set valor = 1 where id = %s", (m1,), "no se edita")
    registrar("T3 · un movimiento no se edita: se anula", ok, msg)

    ok, msg = espera_error(cur, """insert into movimiento (proyecto_id, centro_costo_id, estado, valor, tercero_nombre,
                                   concepto, origen_id, registrado_por)
                                   values (%s, %s, 'causacion', 8000000, 'X', 'x', %s, %s)""",
                           (nirv, cc_contr, m1, P["andres"]), "espera aprobación")
    registrar("T4 · lo que espera aprobación no se causa ni se paga", ok, msg)

    ok, msg = espera_error(cur, """update movimiento set aprobacion = 'aprobado', aprobado_por = %s,
                                   aprobado_en = now() where id = %s""", (P["andres"], m1), "segregación")
    registrar("T1 · quien registra no se aprueba a sí mismo", ok, msg)

    cur.execute("update movimiento set aprobacion = 'aprobado', aprobado_por = %s, aprobado_en = now() where id = %s",
                (P["felipe"], m1))
    registrar("dirección sí aprueba", uno(cur, "select aprobacion from movimiento where id = %s", (m1,)) == "aprobado")
    ok, msg = espera_error(cur, "update movimiento set aprobacion = 'rechazado' where id = %s", (m1,), "ya se tomó")
    registrar("T4 · una decisión de aprobación no se cambia después", ok, msg)

    proy, pp = balance(cc_contr)
    registrar("balance · un compromiso cuenta aunque no se haya pagado",
              cerca(proy - base_proy, 8400000, 0.5) and cerca(pp - base_pp, 8400000, 0.5),
              f"proyectado +${proy - base_proy:,.0f}, por pagar +${pp - base_pp:,.0f}")

    caus, _ = mov(estado="causacion", valor=8000000, origen_id=m1)
    mov(estado="pago", valor=5000000, origen_id=caus, medio="banco")
    proy, pp = balance(cc_contr)
    registrar("balance · la cadena de tres estados se cuenta una sola vez",
              cerca(proy - base_proy, 8400000, 0.5) and cerca(pp - base_pp, 3400000, 0.5),
              f"proyectado +${proy - base_proy:,.0f}, por pagar +${pp - base_pp:,.0f}")

    ok, msg = espera_error(cur, """insert into movimiento (proyecto_id, centro_costo_id, estado, valor, tercero_nombre,
                                   concepto, origen_id, registrado_por)
                                   values (%s, %s, 'causacion', 100, 'X', 'x', %s, %s)""",
                           (nirv, cc_prov, m1, P["andres"]), "centro de costo dentro de su cadena")
    registrar("T2 · una cadena no cambia de centro de costo", ok, msg)

    mov(estado="causacion", naturaleza="devolucion", valor=400000, origen_id=caus,
        concepto="Devolución de material defectuoso")
    proy, pp = balance(cc_contr)
    registrar("devolución · resta del proyectado y de lo por pagar",
              cerca(proy - base_proy, 8000000, 0.5) and cerca(pp - base_pp, 3000000, 0.5),
              f"proyectado +${proy - base_proy:,.0f}, por pagar +${pp - base_pp:,.0f}")

    ok, msg = espera_error(cur, """insert into movimiento (proyecto_id, centro_costo_id, estado, naturaleza, valor,
                                   tercero_nombre, concepto, registrado_por)
                                   values (%s, %s, 'causacion', 'devolucion', 100, 'X', 'x', %s)""",
                           (nirv, cc_contr, P["andres"]), "mov_devolucion_con_origen")
    registrar("devolución · debe decir qué devuelve", ok, msg)

    c1, _ = mov(valor=1500000, centro_costo_id=cc_prov, concepto="Cemento")
    _, ap = mov(estado="causacion", valor=2500000, centro_costo_id=cc_prov, origen_id=c1, concepto="Cemento")
    registrar("T4 · un eslabón que crece por encima del umbral vuelve a pedir aprobación", ap == "pendiente", ap)

    antes = balance(cc_prov)
    a1, _ = mov(valor=700000, centro_costo_id=cc_prov, concepto="Arena lavada")
    durante = balance(cc_prov)
    ok, msg = espera_error(cur, """insert into movimiento (proyecto_id, centro_costo_id, estado, valor, tercero_nombre,
                                   concepto, anula_a, motivo_anulacion, registrado_por)
                                   values (%s, %s, 'compromiso', 600000, 'X', 'x', %s, 'error', %s)""",
                           (nirv, cc_prov, a1, P["andres"]), "debe repetir")
    registrar("T3 · el contra-registro repite los valores del original", ok, msg)
    cur.execute("""insert into movimiento (proyecto_id, centro_costo_id, estado, valor, tercero_nombre,
                   concepto, anula_a, motivo_anulacion, registrado_por)
                   values (%s, %s, 'compromiso', 700000, 'X', 'Anula arena', %s, 'Se registró dos veces', %s)""",
                (nirv, cc_prov, a1, P["andres"]))
    despues = balance(cc_prov)
    registrar("T3 · anular con contra-registro saca el gasto del balance",
              cerca(durante[0] - antes[0], 700000, 0.5) and cerca(despues[0], antes[0], 0.5),
              f"+${durante[0] - antes[0]:,.0f} y de vuelta a ${despues[0]:,.0f}")

    # ---------- caja menor ----------
    fondo = uno(cur, "insert into fondo_caja (responsable_id, entregado_por, valor) values (%s, %s, 500000) returning id",
                (P["andres"], P["luisa"]))
    g1, _ = mov(estado="pago", valor=50000, centro_costo_id=cc_prov, medio="efectivo", fondo_id=fondo,
                tercero_nombre="Fletes Pereira", concepto="Flete de arena")
    caja = uno(cur, "select entregado, gastado, saldo, gastos_sin_soporte from v_caja_menor where fondo_id = %s", (fondo,))
    registrar("caja menor · saldo y gastos sin soporte",
              caja and cerca(caja[1], 50000, 0.5) and cerca(caja[2], 450000, 0.5) and caja[3] == 1,
              f"entregado ${float(caja[0]):,.0f}, gastado ${float(caja[1]):,.0f}, "
              f"saldo ${float(caja[2]):,.0f}, sin soporte {caja[3]}")
    ok, msg = espera_error(cur, "insert into fondo_caja (responsable_id, entregado_por, valor) values (%s, %s, 300000)",
                           (P["andres"], P["luisa"]), "fondo_caja_uno_abierto")
    registrar("caja menor · no se entrega otro fondo sin legalizar el anterior", ok, msg)
    ok, msg = espera_error(cur, "insert into fondo_caja (responsable_id, entregado_por, valor) values (%s, %s, 300000)",
                           (P["luisa"], P["luisa"]), "fondo_segregacion")
    registrar("caja menor · quien entrega no es quien gasta", ok, msg)
    ok, msg = espera_error(cur, "update fondo_caja set legalizado_en = private.hoy(), legalizado_por = %s where id = %s",
                           (P["luisa"], fondo), "sin soporte")
    registrar("caja menor · no se legaliza con gastos sin soporte", ok, msg)

    evidencia = uno(cur, """insert into evidencia (movimiento_id, ruta, tipo, registrada_por)
                            values (%s, %s, 'factura', %s) returning id""", (g1, f"{nirv}/flete-arena.jpg", P["andres"]))
    cur.execute("update fondo_caja set legalizado_en = private.hoy(), legalizado_por = %s where id = %s", (P["luisa"], fondo))
    registrar("caja menor · con el soporte, se legaliza",
              uno(cur, "select legalizado_en is not null from fondo_caja where id = %s", (fondo,)))
    ok, msg = espera_error(cur, """insert into movimiento (proyecto_id, centro_costo_id, estado, valor, tercero_nombre,
                                   concepto, medio, fondo_id, registrado_por)
                                   values (%s, %s, 'pago', 20000, 'X', 'x', 'efectivo', %s, %s)""",
                           (nirv, cc_prov, fondo, P["andres"]), "ya está legalizado")
    registrar("caja menor · no se gasta contra un fondo legalizado", ok, msg)

    ok, msg = espera_error(cur, "update evidencia set tipo = 'otro' where id = %s", (evidencia,), "no se edita")
    registrar("P5 · la evidencia no se edita", ok, msg)
    otro = uno(cur, "select id from proyecto where codigo = 'OBRA OLMO'")
    ok, msg = espera_error(cur, """insert into evidencia (movimiento_id, ruta, registrada_por) values (%s, %s, %s)""",
                           (g1, f"{otro}/foto.jpg", P["andres"]), "empieza por el id")
    registrar("P5 · la foto vive en la carpeta de su proyecto", ok, msg)

    # ---------- presupuesto ----------
    ok, msg = espera_error(cur, "insert into presupuesto (proyecto_id, version, vigente, aprobado_en) values (%s, 2, false, now())",
                           (nirv,), "imprevistos")
    registrar("O8 · no se aprueba un presupuesto con imprevistos en cero", ok, msg)
    ok, msg = espera_error(cur, """insert into presupuesto (proyecto_id, version, vigente, estado, justificacion_imprevistos)
                                   values (%s, 2, false, 'emitido', 'El cliente asume los imprevistos por escrito')""",
                           (nirv,), "O10")
    registrar("O10 · con 14% de administración y utilidad no se emite sin autorización de un socio", ok, msg)
    ok, msg = espera_error(cur, """insert into presupuesto (proyecto_id, version, vigente, estado, justificacion_imprevistos,
                                   margen_autorizado_por) values (%s, 2, false, 'emitido', 'Asumidos por escrito', %s)""",
                           (nirv, P["felipe"]), "validación de un profesional")
    registrar("un presupuesto no se emite sin validación profesional", ok, msg)
    ok, msg = espera_error(cur, """insert into presupuesto (proyecto_id, version, vigente, estado, justificacion_imprevistos,
                                   margen_autorizado_por, elaborado_por, validado_por)
                                   values (%s, 2, false, 'emitido', 'Asumidos por escrito', %s, %s, %s)""",
                           (nirv, P["felipe"], P["arquitecto"], P["arquitecto"]), "quien elabora")
    registrar("quien elabora el presupuesto no lo valida", ok, msg)
    ok, msg = espera_error(cur, """insert into presupuesto (proyecto_id, version, vigente, estado, justificacion_imprevistos,
                                   margen_autorizado_por, elaborado_por, validado_por)
                                   values (%s, 2, false, 'emitido', 'Asumidos por escrito', %s, %s, %s)""",
                           (nirv, P["luisa"], P["arquitecto"], P["luisa"]), "solo un socio")
    registrar("O10 · solo un socio autoriza un margen bajo la meta", ok, msg)
    p2 = uno(cur, """insert into presupuesto (proyecto_id, version, vigente, estado, justificacion_imprevistos,
                     margen_autorizado_por, elaborado_por, validado_por)
                     values (%s, 2, false, 'emitido', 'Asumidos por escrito', %s, %s, %s) returning id""",
             (nirv, P["felipe"], P["arquitecto"], P["luisa"]))
    registrar("con justificación, autorización y validación, sí se emite", p2 is not None)
    ok, msg = espera_error(cur, "insert into capitulo (presupuesto_id, codigo, nombre) values (%s, 'C99', 'Nuevo')",
                           (p2,), "ya se emitió")
    registrar("un presupuesto emitido no se reescribe", ok, msg)

    cred = uno(cur, "select bruto, credito, neto from v_adicionales_netos where proyecto = 'OBRA NIRVANA'")
    registrar("O9 · el crédito de los ítems reemplazados sale solo",
              cred and float(cred[1]) > 0 and cerca(cred[2], float(cred[0]) - float(cred[1]), 0.5),
              f"bruto ${float(cred[0]):,.0f} · crédito ${float(cred[1]):,.0f} · neto ${float(cred[2]):,.0f}")

    # ---------- actas ----------
    item = uno(cur, """select i.id from item_presupuesto i join ejecucion_item e on e.item_id = i.id
                       join capitulo c on c.id = i.capitulo_id join presupuesto pr on pr.id = c.presupuesto_id
                       where pr.proyecto_id = %s and pr.vigente and e.cantidad_proyectada >= 4
                       order by i.codigo limit 1""", (nirv,))
    cur.execute("update ejecucion_item set pct_avance = 0.5 where item_id = %s", (item,))
    ejecutado = float(uno(cur, "select cantidad_proyectada * pct_avance from ejecucion_item where item_id = %s", (item,)))
    contratista = uno(cur, "select id from persona where rol = 'contratista' order by nombre limit 1")
    acta_p = uno(cur, """insert into acta (proyecto_id, tipo, numero, tercero_id, valor)
                         values (%s, 'pago_contratista', 'AP-01', %s, 1000000) returning id""", (nirv, contratista))
    ok, msg = espera_error(cur, "insert into acta_item (acta_id, item_id, cantidad, valor_unitario) values (%s, %s, %s, 1000)",
                           (acta_p, item, ejecutado + 1), "O6")
    registrar("O6 · un acta de pago no supera lo ejecutado", ok, msg)
    cur.execute("insert into acta_item (acta_id, item_id, cantidad, valor_unitario) values (%s, %s, %s, 1000)",
                (acta_p, item, ejecutado / 2))
    ok, msg = espera_error(cur, "insert into acta_item (acta_id, item_id, cantidad, valor_unitario) values (%s, %s, %s, 1000)",
                           (acta_p, item, ejecutado / 2 + 1), "O6")
    registrar("O6 · tampoco sumando varias actas", ok, msg)

    acta_c = uno(cur, """insert into acta (proyecto_id, tipo, numero, valor, vence_en)
                         values (%s, 'cobro_cliente', 'AC-01', 10000000, private.hoy() - 10) returning id""", (nirv,))
    ad02 = uno(cur, "select id from adicional where proyecto_id = %s and codigo = 'MOD-1.05'", (nirv,))
    ok, msg = espera_error(cur, "insert into acta_item (acta_id, adicional_id, cantidad, valor_unitario) values (%s, %s, 1, 1)",
                           (acta_c, ad02), "no ha aprobado")
    registrar("O1 · no se cobra un adicional que el cliente no ha aprobado", ok, msg)
    ok, msg = espera_error(cur, """update adicional set aprobacion = 'aprobado', aprobado_en = private.hoy(),
                                   aprobado_por_texto = 'Cliente' where proyecto_id = %s and codigo = 'MOD-1.06'""",
                           (nirv,), "por qué medio")
    registrar("O1 · la aprobación del cliente dice por qué medio llegó", ok, msg)

    # ---------- cierre de mes ----------
    ok, msg = espera_error(cur, "insert into cierre_mes (periodo, cerrado_por) values (date_trunc('month', private.hoy())::date, %s)",
                           (P["finanzas"],), "meses terminados")
    registrar("F6 · el mes en curso no se cierra", ok, msg)
    periodo = uno(cur, "select (date_trunc('month', private.hoy()) - interval '1 month')::date")
    cur.execute("insert into cierre_mes (periodo, cerrado_por) values (%s, %s)", (periodo, P["finanzas"]))
    ok, msg = espera_error(cur, """insert into movimiento (proyecto_id, centro_costo_id, estado, fecha, valor, tercero_nombre,
                                   concepto, registrado_por) values (%s, %s, 'compromiso', %s, 100000, 'X', 'x', %s)""",
                           (nirv, cc_prov, periodo, P["andres"]), "está cerrado")
    registrar("F6 · un mes cerrado no recibe movimientos", ok, msg)

    # ---------- bitácora y cambios ----------
    cur.execute("insert into bitacora (proyecto_id, fecha, avance, registrado_por) values (%s, private.hoy(), 'Enchapes', %s)",
                (nirv, P["andres"]))
    ok, msg = espera_error(cur, """insert into bitacora (proyecto_id, fecha, avance, registrado_por)
                                   values (%s, private.hoy() + 1, 'x', %s)""", (nirv, P["andres"]), "adelantado")
    registrar("O4 · la bitácora no se escribe por adelantado", ok, msg)
    faltan = uno(cur, "select count(*) from v_bitacora_faltante where proyecto_id = %s", (nirv,))
    registrar("O4 · los días sin bitácora quedan marcados", faltan > 0, f"{faltan} días en el último mes")

    cambio = uno(cur, """insert into cambio_obra (proyecto_id, descripcion, decidido_por, altera_diseno)
                         values (%s, 'Mesón recto en lugar de cocina curva', %s, true) returning id""", (nirv, P["andres"]))
    abiertos = uno(cur, "select count(*) from v_cambios_sin_reflejar where id = %s", (cambio,))
    cur.execute("update cambio_obra set reflejado_en_diseno_en = private.hoy(), reflejado_por = %s where id = %s",
                (P["luisa"], cambio))
    cerrados = uno(cur, "select count(*) from v_cambios_sin_reflejar where id = %s", (cambio,))
    registrar("un cambio en obra queda abierto hasta que diseño lo incorpora", abiertos == 1 and cerrados == 0)

    return dict(cc_contr=cc_contr, cc_prov=cc_prov, acta_c=acta_c, m_pendiente=c1)


# =============================================================================
# 5 · Comercial
# =============================================================================
def s5_comercial(cur, P):
    seccion("5 · Mercadeo, ventas y CRM · M-05")

    ok, msg = espera_error(cur, "insert into lead (nombre, telefono) values ('Sin canal', '3000000000')", None, "canal")
    registrar("M1 · ningún lead entra sin canal", ok, msg)

    lead = uno(cur, """insert into lead (canal, nombre, telefono, asignado_a)
                       values ('google_ads', 'PRUEBA Prospecto', '+57 300 123 4567', %s) returning id""", (P["alison"],))
    registrar("el teléfono queda comparable, sin el 57 ni espacios",
              uno(cur, "select telefono_normalizado from lead where id = %s", (lead,)) == "3001234567")

    def contacto(lid, direccion="saliente", respondio=False):
        cur.execute("""insert into contacto_lead (lead_id, medio, direccion, respondio, registrado_por)
                       values (%s, 'whatsapp', %s, %s, %s)""", (lid, direccion, respondio, P["alison"]))

    def estado(lid):
        return uno(cur, "select estado from lead where id = %s", (lid,))

    contacto(lead)
    registrar("el primer contacto queda medido",
              estado(lead) == "contactado"
              and uno(cur, "select primer_contacto_en is not null from lead where id = %s", (lead,)), estado(lead))
    contacto(lead)
    contacto(lead)
    registrar("regla de los tres intentos · sin respuesta pasa a nutrición", estado(lead) == "nutricion", estado(lead))
    contacto(lead, "entrante")
    registrar("6.4 · si el prospecto responde, vuelve solo al embudo",
              estado(lead) == "contactado"
              and uno(cur, "select reactivado_en is not null from lead where id = %s", (lead,)), estado(lead))
    contacto(lead)
    contacto(lead)
    contacto(lead)
    nuevo = uno(cur, "insert into lead (canal, nombre, telefono) values ('referido', 'PRUEBA Prospecto', '3001234567') returning id")
    registrar("6.4 · si escribe otra vez desde el mismo número, sale de nutrición",
              estado(lead) == "contactado"
              and uno(cur, "select lead_previo_id from lead where id = %s", (nuevo,)) == lead, estado(lead))

    op = uno(cur, """insert into oportunidad (lead_id, nombre, responsable_id)
                     values (%s, 'PRUEBA Casa campestre', %s) returning id""", (lead, P["felipe"]))
    canal, est = uno(cur, """select o.canal, l.estado from oportunidad o join lead l on l.id = o.lead_id
                             where o.id = %s""", (op,))
    registrar("M2 · la oportunidad hereda el canal del lead", canal == "google_ads" and est == "convertido",
              f"{canal} · lead {est}")
    ok, msg = espera_error(cur, "update oportunidad set etapa = 'presupuesto_detallado' where id = %s", (op,), "valor estimado")
    registrar("política 3.1 · sin valor estimado no pasa de la cita de viabilidad", ok, msg)
    ok, msg = espera_error(cur, "update oportunidad set etapa = 'perdida' where id = %s", (op,), "motivo")
    registrar("M4 · una oportunidad perdida dice por qué", ok, msg)

    cita = uno(cur, "insert into cita (oportunidad_id, programada_para) values (%s, now() - interval '30 days') returning id", (op,))
    ok, msg = espera_error(cur, "update cita set estado = 'realizada' where id = %s", (cita,), "autorizó la grabación")
    registrar("M9 · la cita realizada deja constancia del consentimiento de grabación", ok, msg)
    ok, msg = espera_error(cur, """update cita set grabacion_url = 'https://meet.google.com/x', consentimiento_grabacion = false
                                   where id = %s""", (cita,), "consentimiento")
    registrar("Ley 1581 · no se guarda una grabación sin consentimiento", ok, msg)
    cur.execute("""update cita set estado = 'realizada', consentimiento_grabacion = true,
                   realizada_en = now() - interval '30 days' where id = %s""", (cita,))

    ok, msg = espera_error(cur, """insert into cotizacion (oportunidad_id, numero, tipo, valor, estado)
                                   values (%s, 'COT-DIS-01', 'diseno', 57000000, 'emitida')""", (op,), "costo estimado")
    registrar("O10 · una cotización de diseño no se emite sin costo estimado", ok, msg)
    ok, msg = espera_error(cur, """insert into cotizacion (oportunidad_id, numero, tipo, valor, costo_estimado, estado)
                                   values (%s, 'COT-DIS-01', 'diseno', 57000000, 40000000, 'emitida')""", (op,), "O10")
    registrar("O10 · con 30% de margen no se emite sin autorización de un socio", ok, msg)
    cot = uno(cur, """insert into cotizacion (oportunidad_id, numero, tipo, valor, costo_estimado, estado)
                      values (%s, 'COT-DIS-01', 'diseno', 57000000, 30000000, 'emitida') returning id""", (op,))
    dias = uno(cur, "select vence_en - emitida_en from cotizacion where id = %s", (cot,))
    registrar("M6 · con margen sobre la meta se emite, y vence sola a los 30 días", dias == 30, f"{dias} días")

    ok, msg = espera_error(cur, "insert into experimento (nombre, estado) values ('Landing sismorresistente', 'corriendo')",
                           None, "hipótesis")
    registrar("M7 · un experimento no arranca sin hipótesis", ok, msg)

    camp = uno(cur, """insert into campana (nombre, canal, plataforma, id_externo)
                       values ('PRUEBA Casas campestres', 'google_ads', 'google_ads', 'PRUEBA-1') returning id""")
    cur.execute("insert into inversion_pauta (campana_id, fecha, valor) values (%s, private.hoy(), 2200000)", (camp,))
    lead2 = uno(cur, "insert into lead (campana_id, nombre, correo) values (%s, 'PRUEBA Inversionista', 'inv@prueba.local') returning id",
                (camp,))
    registrar("M1 · un lead de campaña toma el canal de la campaña",
              uno(cur, "select canal from lead where id = %s", (lead2,)) == "google_ads")
    op2 = uno(cur, """insert into oportunidad (lead_id, nombre, valor_estimado, etapa)
                      values (%s, 'PRUEBA Tres unidades de renta', 57000000, 'ganada') returning id""", (lead2,))
    lectura = uno(cur, "select lectura from v_retorno_pauta where campana_id = %s", (camp,))
    registrar("M3 · el retorno de la pauta se lee en pesos, sin fórmulas", lectura and "$25,91" in lectura, lectura)
    canal_proy = uno(cur, """insert into proyecto (codigo, nombre, unidad, tipo, oportunidad_id)
                             values ('PRUEBA CASA RENTA', 'Casa de renta', 'diseno_arquitectonico', 'diseno', %s)
                             returning canal""", (op2,))
    registrar("M2 · el canal viaja de la oportunidad al proyecto", canal_proy == "google_ads", canal_proy)
    embudo = uno(cur, "select lectura from v_embudo_mensual where canal = 'google_ads' order by mes desc limit 1")
    registrar("el embudo del mes se lee en una frase", bool(embudo), embudo)


# =============================================================================
# 6 · Diseño
# =============================================================================
def s6_diseno(cur, P):
    seccion("6 · Diseño: fases, dedicación y entregables · M-04")
    casa = uno(cur, """insert into proyecto (codigo, nombre, unidad, tipo, responsable_id)
                       values ('PRUEBA CASA GALERIA', 'Casa de prueba', 'diseno_arquitectonico', 'diseno', %s)
                       returning id""", (P["luisa"],))
    cur.execute("""insert into acceso_proyecto (persona_id, proyecto_id, nivel)
                   values (%s, %s, 'registro'), (%s, %s, 'registro')""", (P["mariana"], casa, P["arquitecto"], casa))
    ins = uno(cur, "insert into proyecto_fase (proyecto_id, fase, orden, horas_cotizadas) values (%s, 'insight', 1, 8) returning id",
              (casa,))
    ante = uno(cur, "insert into proyecto_fase (proyecto_id, fase, orden, horas_cotizadas) values (%s, 'anteproyecto', 2, 80) returning id",
               (casa,))
    cerrar = "update proyecto_fase set estado = 'cerrada', cerrada_por = %s where id = %s"

    ok, msg = espera_error(cur, "update proyecto_fase set estado = 'en_curso' where id = %s", (ante,), "no se abre")
    registrar("D1 · no se abre el anteproyecto con el insight sin cerrar", ok, msg)
    cur.execute("update proyecto_fase set estado = 'en_curso' where id = %s", (ins,))
    registrar("la fase en curso se refleja en el proyecto",
              uno(cur, "select fase from proyecto where id = %s", (casa,)) == "insight")

    ok, msg = espera_error(cur, cerrar, (P["luisa"], ins), "lista de chequeo")
    registrar("D1 · una fase no se cierra sin su lista de chequeo", ok, msg)
    lista = uno(cur, "insert into lista_chequeo (ambito, nombre, fase) values ('fase_diseno', 'Cierre de insight', 'insight') returning id")
    i1 = uno(cur, "insert into lista_chequeo_item (lista_id, orden, texto) values (%s, 1, 'Principios validados con el cliente') returning id",
             (lista,))
    cur.execute("insert into lista_chequeo_item (lista_id, orden, texto, obligatorio) values (%s, 2, 'Referentes archivados', false)", (lista,))
    chk = uno(cur, "insert into chequeo (lista_id, fase_id) values (%s, %s) returning id", (lista, ins))
    ok, msg = espera_error(cur, "insert into chequeo (lista_id, fase_id) values (%s, %s)", (lista, ante), "es para la fase")
    registrar("la lista del insight no sirve para el anteproyecto", ok, msg)
    cur.execute("insert into chequeo_respuesta (chequeo_id, item_id, cumple, verificado_por) values (%s, %s, true, %s)",
                (chk, i1, P["luisa"]))

    ok, msg = espera_error(cur, cerrar, (P["luisa"], ins), "no tiene dedicación")
    registrar("D2 · una fase sin dedicación registrada no se cierra", ok, msg)
    cur.execute("insert into dedicacion (persona_id, fecha, bloque, proyecto_id) values (%s, private.hoy(), 'manana', %s)",
                (P["mariana"], casa))
    fase_auto, horas = uno(cur, """select fase_id, horas from dedicacion
                                   where persona_id = %s and fecha = private.hoy() and bloque = 'manana'""", (P["mariana"],))
    registrar("D2 · en dos toques: la fase y las horas se deducen solas", fase_auto == ins and float(horas) == 4,
              f"{float(horas)} horas")
    ok, msg = espera_error(cur, cerrar, (P["luisa"], ins), "sin registrar dedicación")
    registrar("D2 · no se cierra si alguien del equipo dejó días sin registrar", ok, msg)
    cur.execute("""insert into dedicacion (persona_id, fecha, bloque, tipo, proyecto_id)
                   select %s, g::date, 'manana', 'proyecto', %s
                   from generate_series(private.hoy() - 7, private.hoy() - 1, interval '1 day') g
                   where extract(isodow from g) < 6
                   on conflict (persona_id, fecha, bloque) do nothing""", (P["mariana"], casa))
    cur.execute(cerrar, (P["luisa"], ins))
    registrar("D1 · con la lista completa y la dedicación al día, la fase se cierra",
              uno(cur, "select estado from proyecto_fase where id = %s", (ins,)) == "cerrada")
    horas_fase = uno(cur, "select sobre_dedicacion, lectura from v_fase_horas where fase_id = %s", (ins,))
    registrar("D3 · las horas reales se comparan solas con las cotizadas", horas_fase and horas_fase[0],
              horas_fase[1] if horas_fase else "")
    ok, msg = espera_error(cur, "insert into dedicacion (persona_id, fecha, bloque, proyecto_id) values (%s, private.hoy() + 1, 'tarde', %s)",
                           (P["mariana"], casa), "adelantado")
    registrar("D2 · la dedicación no se registra por adelantado", ok, msg)

    cur.execute("update proyecto_fase set estado = 'en_curso' where id = %s", (ante,))
    lista_a = uno(cur, """insert into lista_chequeo (ambito, nombre, fase)
                          values ('fase_diseno', 'Entrega de anteproyecto', 'anteproyecto') returning id""")
    ia = uno(cur, "insert into lista_chequeo_item (lista_id, texto) values (%s, 'Planos, cortes y alzados') returning id", (lista_a,))
    chk_a = uno(cur, "insert into chequeo (lista_id, fase_id) values (%s, %s) returning id", (lista_a, ante))
    cur.execute("insert into chequeo_respuesta (chequeo_id, item_id, cumple, verificado_por) values (%s, %s, true, %s)",
                (chk_a, ia, P["luisa"]))
    cur.execute("insert into dedicacion (persona_id, fecha, bloque, proyecto_id) values (%s, private.hoy(), 'tarde', %s)",
                (P["mariana"], casa))
    ok, msg = espera_error(cur, cerrar, (P["luisa"], ante), "aprobación del cliente")
    registrar("D1 · el anteproyecto no se cierra sin la aprobación del cliente", ok, msg)

    v1 = uno(cur, """insert into entregable (proyecto_id, fase_id, nombre, registrado_por)
                     values (%s, %s, 'Planta arquitectónica', %s) returning version""", (casa, ante, P["mariana"]))
    e2, v2 = uno(cur, """insert into entregable (proyecto_id, fase_id, nombre, registrado_por)
                         values (%s, %s, 'Planta arquitectónica', %s) returning id, version""", (casa, ante, P["mariana"]))
    registrar("D5 · la versión de cada entrega la pone el sistema", v1 == 1 and v2 == 2, f"versiones {v1} y {v2}")
    ok, msg = espera_error(cur, "update entregable set descripcion = 'cambiada' where id = %s", (e2,), "versión nueva")
    registrar("D5 · lo entregado no se reescribe", ok, msg)

    tarea = uno(cur, """insert into tarea_diseno (proyecto_id, fase_id, titulo, asignada_a, asignada_por)
                        values (%s, %s, 'Plano de mobiliario fijo', %s, %s) returning id""",
                (casa, ante, P["mariana"], P["luisa"]))
    ok, msg = espera_error(cur, "update tarea_diseno set estado = 'terminada' where id = %s", (tarea,), "revisión aprobada")
    registrar("una tarea no se termina sin revisión", ok, msg)
    ok, msg = espera_error(cur, "insert into revision_diseno (tarea_id, revisor_id, resultado) values (%s, %s, 'aprobada')",
                           (tarea, P["mariana"]), "distinto")
    registrar("la revisión la hace alguien distinto de quien hizo la tarea", ok, msg)
    ok, msg = espera_error(cur, "insert into revision_diseno (tarea_id, revisor_id, resultado) values (%s, %s, 'aprobada')",
                           (tarea, P["luisa"]), "pidió revisión")
    registrar("D11 · no se revisa lo que no ha pedido revisión", ok, msg)
    cur.execute("update tarea_diseno set estado = 'en_revision' where id = %s", (tarea,))
    cur.execute("""insert into revision_diseno (tarea_id, revisor_id, resultado, observaciones)
                   values (%s, %s, 'con_observaciones', 'La nomenclatura M-06 no coincide con la lámina')""",
                (tarea, P["luisa"]))
    registrar("con observaciones, la tarea vuelve a quien la hizo",
              uno(cur, "select estado from tarea_diseno where id = %s", (tarea,)) == "con_observaciones")
    ok, msg = espera_error(cur, "update tarea_diseno set estado = 'terminada' where id = %s", (tarea,), "revisión aprobada")
    registrar("D11 · una revisión que devolvió no sirve para terminar la tarea", ok, msg)
    cur.execute("update tarea_diseno set estado = 'en_revision' where id = %s", (tarea,))
    cur.execute("insert into revision_diseno (tarea_id, revisor_id, resultado) values (%s, %s, 'aprobada')", (tarea, P["luisa"]))
    registrar("D11 · aprobar termina la tarea: nadie tiene que marcarla después",
              uno(cur, "select estado from tarea_diseno where id = %s", (tarea,)) == "terminada")

    capacidad = uno(cur, "select horas_disponibles, lectura from v_capacidad_13_semanas")
    registrar("D4 · la capacidad del equipo se lee en una frase", capacidad and float(capacidad[0]) > 0,
              capacidad[1] if capacidad else "")
    return casa


# =============================================================================
# 7 · Reclamaciones
# =============================================================================
def s7_reclamaciones(cur, P):
    seccion("7 · Reclamaciones y pólizas · M-02")
    aseg = uno(cur, "insert into persona (nombre, rol) values ('PRUEBA Aseguradora', 'aseguradora') returning id")
    otra_aseg = uno(cur, "insert into persona (nombre, rol) values ('PRUEBA Otra aseguradora', 'aseguradora') returning id")
    ingeniero = uno(cur, "insert into persona (nombre, rol) values ('PRUEBA Ingeniero estructural', 'profesional_externo') returning id")
    proy = uno(cur, """insert into proyecto (codigo, nombre, unidad, tipo, es_reclamacion, responsable_id)
                       values ('PRUEBA LOCAL RECLAMACION', 'Local de prueba', 'obra_propia', 'obra', true, %s)
                       returning id""", (P["luisa"],))
    rec = uno(cur, """insert into reclamacion (proyecto_id, aseguradora_id, numero_poliza, fecha_limite)
                      values (%s, %s, 'POL-123', private.hoy() + 10) returning id""", (proy, aseg))
    eventos = lambda: uno(cur, "select count(*) from reclamacion_evento where reclamacion_id = %s", (rec,))
    registrar("P3 · la reclamación abre su historial sola", eventos() == 1)

    ok, msg = espera_error(cur, "update reclamacion set estado = 'aprobada' where id = %s", (rec,), "no pasa de")
    registrar("P3 · la cascada de cobro no se salta pasos", ok, msg)
    ok, msg = espera_error(cur, "update reclamacion set estado = 'conciliada' where id = %s", (rec,), "P1")
    registrar("P1 · no se concilia sin la lista de la póliza completa", ok, msg)

    lista = uno(cur, "insert into lista_chequeo (ambito, nombre, aseguradora_id) values ('reclamacion', 'Póliza de prueba', %s) returning id",
                (aseg,))
    punto = uno(cur, """insert into lista_chequeo_item (lista_id, texto, requiere_evidencia)
                        values (%s, 'Registro fotográfico georreferenciado', true) returning id""", (lista,))
    lista_otra = uno(cur, "insert into lista_chequeo (ambito, nombre, aseguradora_id) values ('reclamacion', 'Póliza ajena', %s) returning id",
                     (otra_aseg,))
    ok, msg = espera_error(cur, "insert into chequeo (lista_id, reclamacion_id) values (%s, %s)", (lista_otra, rec), "otra aseguradora")
    registrar("P1 · la lista de chequeo es la de su aseguradora", ok, msg)
    chk = uno(cur, "insert into chequeo (lista_id, reclamacion_id) values (%s, %s) returning id", (lista, rec))
    ok, msg = espera_error(cur, "insert into chequeo_respuesta (chequeo_id, item_id, cumple, verificado_por) values (%s, %s, true, %s)",
                           (chk, punto, P["luisa"]), "exige evidencia")
    registrar("P5 · un punto que exige evidencia no se marca sin ella", ok, msg)
    cur.execute("""insert into chequeo_respuesta (chequeo_id, item_id, cumple, evidencia_ruta, verificado_por)
                   values (%s, %s, true, %s, %s)""", (chk, punto, f"{proy}/fachada.jpg", P["luisa"]))

    ok, msg = espera_error(cur, "update reclamacion set estado = 'conciliada' where id = %s", (rec,), "P6")
    registrar("P6 · no se concilia sin el aval del ingeniero especialista", ok, msg)
    ok, msg = espera_error(cur, """update reclamacion set estado = 'conciliada', aval_estructural_por = %s,
                                   aval_estructural_en = private.hoy() where id = %s""", (ingeniero, rec), "P2")
    registrar("P2 · la conciliación con los abogados queda con fecha y nombre", ok, msg)
    cur.execute("""update reclamacion set estado = 'conciliada', aval_estructural_por = %s, aval_estructural_en = private.hoy(),
                   conciliada_en = private.hoy(), conciliada_por_texto = 'Abogado de prueba' where id = %s""", (ingeniero, rec))
    fila = uno(cur, "select estado, checklist_completo, dias_para_vencer from v_reclamaciones where id = %s", (rec,))
    registrar("P3 y P4 · se ve en qué eslabón va y cuánto falta para que venza la póliza",
              fila and fila[0] == "conciliada" and fila[1] and fila[2] == 10 and eventos() == 2,
              f"{fila[0]} · lista completa {fila[1]} · vence en {fila[2]} días · {eventos()} eventos")


# =============================================================================
# 8 · Finanzas y alertas
# =============================================================================
def s8_finanzas(cur, P, nirv, obra):
    seccion("8 · Finanzas y alertas · M-07")
    cuenta = uno(cur, """insert into cuenta (nombre, tipo, banco, ultimos4)
                         values ('PRUEBA Corriente', 'banco', 'Banco de prueba', '1234') returning id""")
    cur.execute("insert into saldo_cuenta (cuenta_id, fecha, saldo) values (%s, private.hoy(), 5000000)", (cuenta,))

    cartera = uno(cur, "select saldo, antiguedad from v_cartera where acta_id = %s", (obra["acta_c"],))
    registrar("F3 · un acta de cobro entra a cartera con su antigüedad",
              cartera and cerca(cartera[0], 10000000, 0.5) and cartera[1] == "1_a_30",
              f"${float(cartera[0]):,.0f} · {cartera[1]}")
    ingreso = uno(cur, """insert into ingreso (proyecto_id, acta_id, cuenta_id, valor, linea, concepto, registrado_por)
                          values (%s, %s, %s, 4000000, 'obra_civil', 'Abono al acta 1', %s) returning id""",
                  (nirv, obra["acta_c"], cuenta, P["finanzas"]))
    registrar("F3 · lo recaudado baja el saldo por cobrar",
              cerca(uno(cur, "select saldo from v_cartera where acta_id = %s", (obra["acta_c"],)), 6000000, 0.5))
    ok, msg = espera_error(cur, "update ingreso set valor = 1 where id = %s", (ingreso,), "no se edita")
    registrar("un ingreso no se edita: se anula", ok, msg)

    flujo = todas(cur, "select semana, entradas, salidas, saldo_final, bajo_minimo from v_flujo_13_semanas order by semana")
    registrar("F4 · el flujo proyecta 13 semanas desde el saldo real del banco",
              len(flujo) == 13 and flujo[0][4],
              f"semana 1: entra ${float(flujo[0][1]):,.0f}, sale ${float(flujo[0][2]):,.0f}, "
              f"queda ${float(flujo[0][3]):,.0f}")

    filas = uno(cur, "select public.distribuir_estructura(private.hoy())")
    suma = uno(cur, "select sum(pct) from distribucion_estructura where periodo = date_trunc('month', private.hoy())::date")
    registrar("F2 · la estructura se reparte entre los proyectos por horas dedicadas",
              filas and filas >= 1 and cerca(suma, 1, 0.001), f"{filas} proyecto(s) · suma {float(suma):.4f}")
    lectura = uno(cur, "select lectura from v_rentabilidad_proyecto where codigo = 'OBRA NIRVANA'")
    registrar("la rentabilidad de cada proyecto se lee en una frase", lectura and lectura.startswith("De cada $100"), lectura)

    nuevas = uno(cur, "select private.generar_alertas()")
    tipos = dict(todas(cur, "select tipo, count(*) from alerta where not resuelta group by tipo"))
    esperados = ("aprobacion_pendiente", "desviacion_capitulo", "bitacora_faltante", "cartera",
                 "caja_bajo_minimo", "poliza_por_vencer", "cita_sin_desenlace")
    faltan = [t for t in esperados if t not in tipos]
    registrar("F7 · el generador crea las alertas de cada módulo", nuevas > 0 and not faltan,
              f"{nuevas} nuevas · faltan {faltan}" if faltan else f"{nuevas} nuevas · {', '.join(sorted(tipos))}")
    al_socio = uno(cur, "select bool_and(%s = any (destinatarios)) from alerta where tipo = 'aprobacion_pendiente' and not resuelta",
                   (P["felipe"],))
    al_residente = uno(cur, """select destinatarios = array[%s]::uuid[] from alerta
                               where tipo = 'bitacora_faltante' and proyecto_id = %s and not resuelta""", (P["andres"], nirv))
    registrar("F8 · cada alerta le llega a quien corresponde, no a todos", al_socio and al_residente,
              f"aprobación al socio {al_socio} · bitácora solo al residente {al_residente}")
    avisos = dict(todas(cur, "select canal::text, count(*) from aviso group by canal"))
    registrar("el correo y el mensaje de texto quedan en la bandeja de salida",
              avisos.get("correo", 0) > 0 and avisos.get("sms", 0) > 0, str(avisos))
    otra = uno(cur, "select private.generar_alertas()")
    registrar("correr el generador otra vez no duplica alertas", otra == 0, f"{otra} nuevas")

    pendiente = uno(cur, "select id from movimiento where aprobacion = 'pendiente' order by registrado_en limit 1")
    cur.execute("update movimiento set aprobacion = 'aprobado', aprobado_por = %s, aprobado_en = now() where id = %s",
                (P["felipe"], pendiente))
    uno(cur, "select private.generar_alertas()")
    registrar("una alerta se resuelve sola cuando la condición desaparece",
              uno(cur, "select bool_and(resuelta) from alerta where clave = %s", (f"aprobacion_pendiente:{pendiente}",)) is True)
    ok, msg = espera_error(cur, "insert into alerta (tipo, titulo, destinatarios) values ('manual', 'x', '{}')", None,
                           "alerta_con_destinatario")
    registrar("F8 · no existe una alerta sin destinatario", ok, msg)


# =============================================================================
# 10 · Objetivos y pendientes de obra · lo que vivía revuelto en el Excel
# =============================================================================
def s10_equipo(cur, P, nirv, casa):
    seccion("10 · Objetivos y pendientes de obra · O11 y D8")

    carpintero = uno(cur, """insert into persona (nombre, rol, es_interno)
                             values ('PRUEBA Carpintero', 'contratista', false) returning id""")
    gasto = uno(cur, "select id from movimiento where proyecto_id = %s limit 1", (nirv,))

    # ---------- pendientes de obra ----------
    rem = uno(cur, """insert into pendiente_obra
                        (proyecto_id, titulo, ubicacion, responsable_id, ejecutor_id, creado_por,
                         fecha_compromiso)
                      values (%s, 'Instalar puerta en madera', 'PH', %s, %s, %s, private.hoy() - 6)
                      returning id""", (nirv, P["andres"], carpintero, P["andres"]))
    registrar("O11 · un remate de obra se registra con responsable y con quién lo ejecuta",
              uno(cur, "select estado from pendiente_obra where id = %s", (rem,)) == "abierto")

    ok, msg = espera_error(cur, "update pendiente_obra set estado = 'cerrado' where id = %s", (rem,),
                           "sin que alguien verifique")
    registrar("O11 · un remate no se cierra porque alguien lo diga", ok, msg)

    ok, msg = espera_error(cur, """update pendiente_obra set estado = 'cerrado', verificado_por = %s
                                   where id = %s""", (carpintero, rem), "distinto de quien la ejecutó")
    registrar("O11 · no lo verifica el mismo que lo hizo", ok, msg)

    cur.execute("update pendiente_obra set verificado_por = %s where id = %s", (P["andres"], rem))
    registrar("O11 · al verificarlo queda cerrado solo: el estado sale del hecho",
              uno(cur, "select estado from pendiente_obra where id = %s", (rem,)) == "cerrado")

    # ---------- la plata vive en obra, no en la lista de tareas ----------
    compra = uno(cur, """insert into pendiente_obra
                           (proyecto_id, tipo, titulo, responsable_id, creado_por, fecha_compromiso)
                         values (%s, 'compra', 'Comprar teja shingle', %s, %s, private.hoy() + 3)
                         returning id""", (nirv, P["andres"], P["luisa"]))
    ok, msg = espera_error(cur, "update pendiente_obra set estado = 'cerrado', verificado_por = %s where id = %s",
                           (P["luisa"], compra), "cuelgue el gasto")
    registrar("O11 · una compra no se cierra sin el gasto con su valor y su aprobación", ok, msg)
    cur.execute("update pendiente_obra set movimiento_id = %s, verificado_por = %s where id = %s",
                (gasto, P["luisa"], compra))
    registrar("O11 · con el gasto colgado, la compra se cierra y el valor queda en obra",
              uno(cur, "select d.estado, d.movimiento_id is not null from pendiente_obra d where d.id = %s",
                  (compra,)) == ("cerrado", True))

    ok, msg = espera_error(cur, """insert into pendiente_obra (proyecto_id, titulo, responsable_id, creado_por, movimiento_id)
                                   values (%s, 'Pagar al eléctrico', %s, %s, %s)""",
                           (casa, P["luisa"], P["luisa"], gasto), "no es del proyecto")
    registrar("O11 · un gasto de otra obra no se cuelga de este pendiente", ok, msg)

    # ---------- dependencias: lo que en el Excel era «hablar con Felipe» ----------
    previo = uno(cur, """insert into pendiente_obra (proyecto_id, titulo, responsable_id, creado_por, fecha_compromiso)
                         values (%s, 'Definir con el cliente si se usa el enchape existente', %s, %s, private.hoy() + 1)
                         returning id""", (nirv, P["luisa"], P["luisa"]))
    depende = uno(cur, """insert into pendiente_obra
                            (proyecto_id, titulo, responsable_id, creado_por, bloqueado_por, fecha_compromiso)
                          values (%s, 'Comprar enchape de muros y pisos', %s, %s, %s, private.hoy() + 2)
                          returning id""", (nirv, P["andres"], P["luisa"], previo))
    ok, msg = espera_error(cur, "update pendiente_obra set verificado_por = %s where id = %s",
                           (P["luisa"], depende), "espera a que se cierre")
    registrar("O11 · lo que depende de otra cosa no se cierra antes que ella", ok, msg)
    lectura = uno(cur, "select lectura from v_pendientes_obra where id = %s", (depende,))
    registrar("O11 · el tablero lo dice en una frase, no en una fórmula",
              lectura is not None and lectura.startswith("Espera a que se cierre"), lectura)

    # ---------- las fechas al revés del Excel ----------
    ok, msg = espera_error(cur, """insert into tarea_diseno
                                     (proyecto_id, titulo, asignada_a, asignada_por, fecha_inicio, fecha_compromiso)
                                   values (%s, 'Render de cocina', %s, %s, private.hoy(), private.hoy() - 28)""",
                           (casa, P["mariana"], P["luisa"]), "tarea_fechas_en_orden")
    registrar("D9 · una tarea no puede terminar antes de empezar (las cuatro de Casa V)", ok, msg)

    # ---------- objetivos ----------
    obj = uno(cur, """insert into objetivo (ambito, proyecto_id, titulo, fecha_limite, responsable_id, creado_por)
                      values ('proyecto', %s, 'Cerrar el anteproyecto con el cliente', private.hoy() + 4, %s, %s)
                      returning id""", (casa, P["luisa"], P["luisa"]))
    t1 = uno(cur, """insert into tarea_diseno (proyecto_id, objetivo_id, titulo, asignada_a, asignada_por,
                                               fecha_inicio, fecha_compromiso)
                     values (%s, %s, 'Render de habitación principal', %s, %s, private.hoy() - 7, private.hoy() - 3)
                     returning id""", (casa, obj, P["mariana"], P["luisa"]))
    t2 = uno(cur, """insert into tarea_diseno (proyecto_id, objetivo_id, titulo, asignada_a, asignada_por)
                     values (%s, %s, 'Organizar la presentación', %s, %s) returning id""",
             (casa, obj, P["mariana"], P["luisa"]))
    registrar("D8 · el objetivo no tiene columna de avance: se cuenta",
              uno(cur, "select total, hechas from v_objetivos where id = %s", (obj,)) == (2, 0))

    ok, msg = espera_error(cur, "update objetivo set estado = 'logrado' where id = %s", (obj,), "sin cerrar")
    registrar("D8 · un objetivo no se declara logrado con trabajo abierto", ok, msg)
    lectura = uno(cur, "select lectura from v_objetivos where id = %s", (obj,))
    registrar("D8 · el objetivo se lee en una frase", lectura is not None and "va tarde" in lectura, lectura)

    ok, msg = espera_error(cur, """insert into tarea_diseno (proyecto_id, objetivo_id, titulo, asignada_a, asignada_por)
                                   values (%s, %s, 'Balance de obra', %s, %s)""",
                           (nirv, obj, P["andres"], P["luisa"]), "otro proyecto")
    registrar("D8 · un objetivo de un proyecto no recibe tareas de otro", ok, msg)

    for t in (t1, t2):
        cur.execute("update tarea_diseno set estado = 'en_revision' where id = %s", (t,))
        cur.execute("""insert into revision_diseno (tarea_id, revisor_id, resultado)
                       values (%s, %s, 'aprobada')""", (t, P["luisa"]))
    cur.execute("update objetivo set estado = 'logrado' where id = %s", (obj,))
    estado, cerrado = uno(cur, "select estado, cerrado_en is not null from objetivo where id = %s", (obj,))
    registrar("D8 · cerrado el trabajo, el objetivo se puede dar por logrado", estado == "logrado" and cerrado)

    # ---------- las alertas que faltaban ----------
    enriesgo = uno(cur, """insert into objetivo (ambito, proyecto_id, titulo, fecha_limite, responsable_id, creado_por)
                           values ('proyecto', %s, 'Entregar el proyecto a la curaduría', private.hoy() + 3, %s, %s)
                           returning id""", (casa, P["luisa"], P["luisa"]))
    vencida = uno(cur, """insert into tarea_diseno
                            (proyecto_id, objetivo_id, titulo, asignada_a, asignada_por, fecha_compromiso)
                          values (%s, %s, 'Actualizar renders de fachada', %s, %s, private.hoy() - 10)
                          returning id""", (casa, enriesgo, P["mariana"], P["luisa"]))
    cur.execute("""insert into pendiente_obra (proyecto_id, titulo, responsable_id, creado_por)
                   values (%s, 'Bajar líneas de vida', %s, %s)""", (nirv, P["andres"], P["luisa"]))
    cur.execute("update pendiente_obra set fecha_compromiso = private.hoy() - 6 where id = %s", (previo,))

    nuevas = uno(cur, "select private.generar_alertas()")
    tipos = dict(todas(cur, "select tipo, count(*) from alerta where not resuelta group by tipo"))
    faltan = [t for t in ("tarea_vencida", "pendiente_vencido", "trabajo_sin_fecha", "objetivo_en_riesgo")
              if t not in tipos]
    registrar("las cuatro alertas nuevas salen solas", nuevas > 0 and not faltan,
              f"{nuevas} nuevas · faltan {faltan}" if faltan else
              f"vencidas {tipos.get('tarea_vencida')} · remates {tipos.get('pendiente_vencido')} · "
              f"sin fecha {tipos.get('trabajo_sin_fecha')} · objetivos {tipos.get('objetivo_en_riesgo')}")

    titulo, dest = uno(cur, """select titulo, destinatarios from alerta
                               where clave = %s and not resuelta""", (f"tarea_vencida:{vencida}",))
    registrar("D9 · la tarea vencida le llega a quien la tiene y a quien la asignó",
              P["mariana"] in dest and P["luisa"] in dest, titulo)
    registrar("D9 · el aviso dice los días en palabras, no en número de serie",
              "lleva 10 días" in titulo, titulo)

    riesgo = uno(cur, "select titulo, detalle from alerta where clave = %s and not resuelta",
                 (f"objetivo_en_riesgo:{enriesgo}",))
    registrar("D8 · el objetivo con la fecha encima avisa antes de que se incumpla",
              riesgo is not None, " · ".join(riesgo) if riesgo else "")

    sin_fecha = uno(cur, "select titulo from alerta where tipo = 'trabajo_sin_fecha' and not resuelta limit 1")
    registrar("lo que no tiene fecha deja de ser invisible", sin_fecha is not None, sin_fecha)

    otra = uno(cur, "select private.generar_alertas()")
    registrar("correr el generador otra vez no duplica las nuevas", otra == 0, f"{otra} nuevas")

    cur.execute("update tarea_diseno set fecha_compromiso = private.hoy() + 5 where id = %s", (vencida,))
    uno(cur, "select private.generar_alertas()")
    registrar("movida la fecha, la alerta se resuelve sola",
              uno(cur, "select resuelta from alerta where clave = %s", (f"tarea_vencida:{vencida}",)) is True)

# =============================================================================
# 9 · Permisos con sesiones reales
# =============================================================================
def s9_permisos(uri, cur, P, nirv, casa):
    seccion("9 · Permisos por fila, con sesiones reales de cada rol")
    total = uno(cur, "select count(*) from proyecto")
    umbral = uno(cur, "select umbral_aprobacion from parametro")
    cc_prov = uno(cur, """select cc.id from centro_costo cc join categoria_costo c on c.id = cc.categoria_id
                          where cc.proyecto_id = %s and c.nombre = 'PROVEEDORES'""", (nirv,))
    olmo = uno(cur, "select id from proyecto where codigo = 'OBRA OLMO'")
    cc_olmo = uno(cur, "select id from centro_costo where proyecto_id = %s limit 1", (olmo,))
    cur.execute("insert into fondo_caja (responsable_id, entregado_por, valor) values (%s, %s, 100000)", (P["mariana"], P["luisa"]))
    cur.execute("insert into dedicacion (persona_id, fecha, bloque, proyecto_id) values (%s, private.hoy(), 'manana', %s)",
                (P["arquitecto"], casa))
    insertar = """insert into movimiento (proyecto_id, centro_costo_id, estado, valor, tercero_nombre, concepto, registrado_por)
                  values (%s, %s, 'compromiso', 300000, 'Ferrecenter', 'Cemento', %s)"""

    # ---------- residente ----------
    con, a = sesion(uri, USUARIOS["andres"][0])
    visibles = uno(a, "select count(*) from proyecto")
    registrar("residente · ve solo su obra", visibles == 1, f"ve {visibles} de {total}")
    registrar("residente · no ve movimientos de otras obras",
              uno(a, "select count(*) from movimiento where proyecto_id <> %s", (nirv,)) == 0)
    registrar("residente · las vistas respetan sus permisos",
              uno(a, "select count(distinct proyecto_id) from v_balance_centro_costo") == 1
              and uno(a, "select count(*) from v_proyecto_resumen") == 1)
    a.execute("update parametro set umbral_aprobacion = 0")
    registrar("residente · no puede bajar el umbral de aprobación",
              a.rowcount == 0 and uno(cur, "select umbral_aprobacion from parametro") == umbral, f"filas afectadas {a.rowcount}")
    ok, msg = espera_error(a, "delete from evento_auditoria", None, "permission denied")
    registrar("residente · no puede borrar la auditoría", ok, msg)
    ok, msg = espera_error(a, """insert into movimiento (proyecto_id, centro_costo_id, estado, valor, tercero_nombre,
                                 concepto, aprobacion, aprobado_por, aprobado_en, registrado_por)
                                 values (%s, %s, 'compromiso', 9000000, 'X', 'x', 'aprobado', %s, now(), %s)""",
                           (nirv, cc_prov, P["felipe"], P["andres"]), "solo dirección")
    registrar("residente · no se autoaprueba al registrar", ok, msg)
    ok, msg = espera_error(a, insertar, (nirv, cc_prov, P["felipe"]), "row-level security")
    registrar("residente · no registra a nombre de otro", ok, msg)
    ok, msg = espera_error(a, insertar, (olmo, cc_olmo, P["andres"]), "row-level security")
    registrar("residente · no registra en una obra que no es suya", ok, msg)
    try:
        a.execute(insertar + " returning aprobacion", (nirv, cc_prov, P["andres"]))
        registrar("residente · sí registra su propio gasto", a.fetchone()[0] == "no_requiere")
    except psycopg2.Error as e:
        registrar("residente · sí registra su propio gasto", False, (e.pgerror or str(e)).splitlines()[0])
    fondos = uno(a, "select count(*) from fondo_caja")
    registrar("residente · ve solo sus fondos de caja menor",
              fondos == uno(cur, "select count(*) from fondo_caja where responsable_id = %s", (P["andres"],))
              and fondos < uno(cur, "select count(*) from fondo_caja"),
              f"ve {fondos} de {uno(cur, 'select count(*) from fondo_caja')}")
    registrar("residente · no ve el embudo comercial, las cuentas ni los ingresos",
              uno(a, "select count(*) from lead") == 0 and uno(a, "select count(*) from cuenta") == 0
              and uno(a, "select count(*) from ingreso") == 0)
    ok, msg = espera_error(a, "update evidencia set tipo = 'otro'", None, "permission denied")
    registrar("residente · la evidencia no se puede editar desde la aplicación", ok, msg)

    # ---------- O11 · la lista de remates, con sesiones reales ----------
    abrir = """insert into pendiente_obra (proyecto_id, titulo, responsable_id, creado_por)
               values (%s, 'Remate de prueba desde sesión', %s, %s)"""
    try:
        a.execute(abrir, (nirv, P["andres"], P["andres"]))
        registrar("residente · abre pendientes en su obra", True)
    except psycopg2.Error as e:
        registrar("residente · abre pendientes en su obra", False, (e.pgerror or str(e)).splitlines()[0])
    ok, msg = espera_error(a, abrir, (olmo, P["andres"], P["andres"]), "row-level security")
    registrar("residente · no abre pendientes en una obra que no es suya", ok, msg)
    ok, msg = espera_error(a, """insert into objetivo (ambito, titulo, fecha_limite, responsable_id, creado_por)
                                 values ('empresa', 'Objetivo colado por un residente', private.hoy() + 10, %s, %s)""",
                           (P["andres"], P["andres"]), "row-level security")
    registrar("residente · los objetivos los fija dirección, no él", ok, msg)

    _cm, mar = sesion(uri, USUARIOS["mariana"][0])
    propios = uno(mar, "select count(*) from v_trabajo_abierto where persona_id = %s", (P["mariana"],))
    ajenos = uno(mar, "select count(*) from v_trabajo_abierto where persona_id <> %s", (P["mariana"],))
    registrar("practicante · en el tablero ve su trabajo y no el de las obras ajenas",
              propios > 0 and ajenos == 0, f"propias {propios} · ajenas {ajenos}")
    _cc, cli = sesion(uri, USUARIOS["cliente"][0])
    registrar("cliente · no ve la lista de remates ni los objetivos del estudio",
              uno(cli, "select count(*) from pendiente_obra") == 0
              and uno(cli, "select count(*) from objetivo") == 0)

    try:
        a.execute("insert into storage.objects (bucket_id, name) values ('evidencias', %s)", (f"{nirv}/bitacora/foto-1.jpg",))
        registrar("fotos · el residente sube fotos a su obra", True)
    except psycopg2.Error as e:
        registrar("fotos · el residente sube fotos a su obra", False, (e.pgerror or str(e)).splitlines()[0])
    ok, msg = espera_error(a, "insert into storage.objects (bucket_id, name) values ('evidencias', %s)",
                           (f"{olmo}/foto.jpg",), "row-level security")
    registrar("fotos · no sube a una obra ajena", ok, msg)
    ok, msg = espera_error(a, "insert into storage.objects (bucket_id, name) values ('evidencias', 'sin-carpeta.jpg')",
                           None, "row-level security")
    registrar("fotos · un archivo fuera de la carpeta de un proyecto se rechaza", ok, msg)
    cur.execute("insert into storage.objects (bucket_id, name) values ('evidencias', %s)", (f"{olmo}/ajena.jpg",))
    registrar("fotos · el residente no ve las fotos de otras obras",
              uno(a, "select count(*) from storage.objects") == 1)
    con.close()

    # ---------- dirección ----------
    con, f = sesion(uri, USUARIOS["felipe"][0])
    registrar("dirección · ve todos los proyectos", uno(f, "select count(*) from proyecto") == total)
    registrar("dirección · ve el embudo comercial", uno(f, "select count(*) from lead") > 0)
    nuevo = uno(cur, """insert into movimiento (proyecto_id, centro_costo_id, estado, valor, tercero_nombre, concepto, registrado_por)
                        values (%s, %s, 'compromiso', 3000000, 'X', 'Estructura metálica', %s) returning id""",
                (nirv, cc_prov, P["andres"]))
    ok, msg = espera_error(f, "update movimiento set aprobacion = 'aprobado', aprobado_por = %s, aprobado_en = now() where id = %s",
                           (P["luisa"], nuevo), "a nombre de quien aprueba")
    registrar("dirección · la aprobación queda a nombre de quien aprueba", ok, msg)
    f.execute("update movimiento set aprobacion = 'aprobado', aprobado_por = %s, aprobado_en = now() where id = %s",
              (P["felipe"], nuevo))
    registrar("dirección · aprueba desde su sesión",
              uno(cur, "select aprobacion from movimiento where id = %s", (nuevo,)) == "aprobado")
    con.close()

    # ---------- finanzas ----------
    con, s = sesion(uri, USUARIOS["finanzas"][0])
    registrar("finanzas · ve el dinero de todas las obras",
              uno(s, "select count(distinct proyecto_id) from movimiento") > 1)
    s.execute("update movimiento set conciliado = true, conciliado_en = private.hoy() where id = %s", (nuevo,))
    registrar("finanzas · concilia", s.rowcount == 1 and uno(cur, "select conciliado from movimiento where id = %s", (nuevo,)))
    ok, msg = espera_error(s, "update movimiento set concepto = 'otro' where id = %s", (nuevo,), "solo marca la conciliación")
    registrar("finanzas · no corrige ni aprueba: solo concilia", ok, msg)
    registrar("finanzas · no ve el embudo comercial", uno(s, "select count(*) from lead") == 0)
    con.close()

    # ---------- mercadeo ----------
    con, m = sesion(uri, USUARIOS["alison"][0])
    registrar("mercadeo · trabaja el embudo", uno(m, "select count(*) from lead") > 0)
    try:
        m.execute("""insert into lead (canal, nombre, telefono, asignado_a)
                     values ('instagram_organico', 'PRUEBA Desde Instagram', '3110000000', %s)""", (P["alison"],))
        registrar("mercadeo · registra leads", True)
    except psycopg2.Error as e:
        registrar("mercadeo · registra leads", False, (e.pgerror or str(e)).splitlines()[0])
    registrar("mercadeo · no ve la contabilidad",
              uno(m, "select count(*) from movimiento") == 0 and uno(m, "select count(*) from v_balance_centro_costo") == 0)
    con.close()

    # ---------- practicante ----------
    con, p = sesion(uri, USUARIOS["mariana"][0])
    try:
        p.execute("insert into dedicacion (fecha, bloque, tipo) values (private.hoy() - 1, 'tarde', 'estructura')")
        registrar("practicante · registra su dedicación sin escribir nada", True)
    except psycopg2.Error as e:
        registrar("practicante · registra su dedicación sin escribir nada", False, (e.pgerror or str(e)).splitlines()[0])
    ok, msg = espera_error(p, "insert into dedicacion (persona_id, fecha, bloque, tipo) values (%s, private.hoy(), 'tarde', 'estructura')",
                           (P["arquitecto"],), "row-level security")
    registrar("practicante · no registra horas a nombre de otro", ok, msg)
    ok, msg = espera_error(p, "insert into dedicacion (fecha, bloque, tipo) values (private.hoy() - 10, 'tarde', 'estructura')",
                           None, "pasados")
    registrar("practicante · pasados 7 días, la dedicación la corrige dirección", ok, msg)
    registrar("practicante · ve solo su dedicación",
              uno(p, "select count(*) from dedicacion where persona_id <> %s", (P["mariana"],)) == 0
              and uno(cur, "select count(*) from dedicacion where persona_id <> %s", (P["mariana"],)) > 0)
    registrar("practicante · ve su proyecto de diseño y no la contabilidad",
              uno(p, "select count(*) from proyecto") == 1 and uno(p, "select count(*) from movimiento") == 0)
    con.close()

    # ---------- cliente en el portal ----------
    con, c = sesion(uri, USUARIOS["cliente"][0])
    registrar("cliente · ve solo su proyecto", uno(c, "select count(*) from proyecto") == 1)
    registrar("cliente · ve sus adicionales y el crédito a su favor",
              uno(c, "select count(*) from adicional where retirado_en is null") == 88
              and float(uno(c, "select coalesce(max(credito), 0) from v_adicionales_netos")) > 0)
    registrar("cliente · ve el presupuesto vigente y su avance",
              uno(c, "select count(*) from item_presupuesto") == 93 and uno(c, "select count(*) from ejecucion_item") > 0)
    registrar("cliente · no ve movimientos, centros de costo, precios de insumos ni el directorio",
              uno(c, "select count(*) from movimiento") == 0 and uno(c, "select count(*) from centro_costo") == 0
              and uno(c, "select count(*) from insumo") == 0 and uno(c, "select count(*) from persona") == 1)
    ad01 = uno(cur, "select id from adicional where proyecto_id = %s and codigo = 'MOD-2.09'", (nirv,))
    try:
        c.execute("insert into aprobacion_cliente (adicional_id, decision, comentario) values (%s, 'aprobado', 'De acuerdo')", (ad01,))
    except psycopg2.Error as e:
        registrar("cliente · aprueba un adicional desde el portal", False, (e.pgerror or str(e)).splitlines()[0])
    fila = uno(cur, "select aprobacion, medio_aprobacion from adicional where id = %s", (ad01,))
    registrar("M-08 · el cliente aprueba un adicional y la decisión queda en el origen",
              fila and fila[0] == "aprobado" and fila[1] == "portal", str(fila))
    ok, msg = espera_error(c, "insert into aprobacion_cliente (adicional_id, decision) values (%s, 'rechazado')", (ad01,),
                           "ya tiene decisión")
    registrar("cliente · una decisión tomada no se cambia", ok, msg)
    c.execute("update adicional set aprobacion = 'aprobado' where codigo = 'MOD-2.10'")
    registrar("cliente · no puede tocar un adicional directamente", c.rowcount == 0, f"filas afectadas {c.rowcount}")
    con.close()

    # ---------- sin sesión y sin ficha ----------
    con, n = sesion(uri, None, rol="anon")
    ok, msg = espera_error(n, "select count(*) from proyecto", None, "permission denied")
    registrar("sin sesión (solo la llave pública) no se ve nada", ok, msg)
    con.close()
    con, x = sesion(uri, "00000000-0000-4000-8000-00000000dead")
    registrar("un usuario con sesión pero sin ficha no ve nada",
              uno(x, "select count(*) from proyecto") == 0 and uno(x, "select count(*) from persona") == 0)
    con.close()

    # ---------- enlace de usuarios ----------
    persona = uno(cur, """insert into persona (nombre, rol, es_interno, correo)
                          values ('PRUEBA Segundo residente', 'residente', true, 'segundo@prueba.local') returning id""")
    uid = "00000000-0000-4000-8000-00000000abcd"
    con, au = sesion(uri, None, rol="supabase_auth_admin")
    au.execute("insert into auth.users (id, email) values (%s, 'Segundo@Prueba.local')", (uid,))
    antes = uno(cur, "select auth_user_id from persona where id = %s", (persona,))
    au.execute("update auth.users set email_confirmed_at = now() where id = %s", (uid,))
    despues = uno(cur, "select auth_user_id from persona where id = %s", (persona,))
    con.close()
    registrar("usuarios · sin correo confirmado no se enlaza nada", antes is None)
    registrar("usuarios · al confirmar el correo, el usuario queda enlazado a su ficha", despues == uid, str(despues))


# =============================================================================
# 11 · Módulo de diseño: plantillas, equipo con papel, revisión y «Mi día»
# =============================================================================
def s11_modulo_diseno(uri, cur):
    seccion("11 · Módulo de diseño: plantillas, equipo, revisión y «Mi día» · etapa 2")
    RLS = "row-level security"

    # Personas propias de esta sección, creadas hoy: no arrastran días sin registrar.
    extra = {"teo": ("00000000-0000-4000-8000-00000000007e", "practicante"),
             "dani": ("00000000-0000-4000-8000-0000000000da", "arquitecto")}
    Q = {}
    for nombre, (uid, rol) in extra.items():
        cur.execute("insert into auth.users (id, email, email_confirmed_at) values (%s, %s, now())",
                    (uid, f"{nombre}@prueba.local"))
        Q[nombre] = uno(cur, """insert into persona (nombre, rol, es_interno, auth_user_id, correo, horas_semana)
                                values (%s, %s, true, %s, %s, 40) returning id""",
                        (f"PRUEBA {nombre.capitalize()}", rol, uid, f"{nombre}@prueba.local"))
    for nombre in ("felipe", "luisa", "mariana", "andres", "cliente"):
        Q[nombre] = uno(cur, "select id from persona where auth_user_id = %s", (USUARIOS[nombre][0],))

    plantilla = dict(todas(cur, "select nombre, id from plantilla_proyecto"))
    v_peq = uno(cur, "insert into variante_chequeo (nombre) values ('EJEMPLO · vivienda pequeña') returning id")
    v_com = uno(cur, "insert into variante_chequeo (nombre) values ('EJEMPLO · alcance completo') returning id")

    def lista(nombre, fase, variante, puntos):
        lid = uno(cur, """insert into lista_chequeo (ambito, nombre, fase, variante_id)
                          values ('fase_diseno', %s, %s, %s) returning id""", (nombre, fase, variante))
        for n, texto in enumerate(puntos, 1):
            cur.execute("insert into lista_chequeo_item (lista_id, orden, texto) values (%s, %s, %s)", (lid, n, texto))
        return lid

    # Listas de EJEMPLO: las reales las suministra el estudio.
    cur.execute("update lista_chequeo set activa = false where ambito = 'fase_diseno'")
    l_ins = lista("EJEMPLO insight", "insight", None, ["Principios validados con el cliente"])
    l_peq = lista("EJEMPLO anteproyecto pequeño", "anteproyecto", v_peq, ["Planta y un corte"])
    l_com = lista("EJEMPLO anteproyecto completo", "anteproyecto", v_com,
                  ["Plantas", "Cortes y alzados", "Modelo y renders de cada espacio"])

    _, lu = sesion(uri, USUARIOS["luisa"][0])
    _, fe = sesion(uri, USUARIOS["felipe"][0])
    _, ma = sesion(uri, USUARIOS["mariana"][0])
    _, an = sesion(uri, USUARIOS["andres"][0])
    _, cl = sesion(uri, USUARIOS["cliente"][0])
    _, te = sesion(uri, extra["teo"][0])
    _, da = sesion(uri, extra["dani"][0])

    abrir = """select abrir_proyecto(%s, %s, %s, %s::unidad_negocio, %s::jsonb, %s::jsonb, %s,
                                     %s::fase_proyecto[])"""
    horas = {"insight": 8, "anteproyecto": 80, "proyecto_final": 120, "presupuesto": 24}
    equipo = [{"persona_id": Q["teo"], "papel": "produce"},
              {"persona_id": Q["mariana"], "papel": "produce"},
              {"persona_id": Q["dani"], "papel": "revisa"}]

    # ---------- D12 · abrir un proyecto desde su plantilla ----------
    ok, msg = espera_error(ma, abrir, ("PRUEBA NO", "No debe abrirse", plantilla["Diseño"], "diseno_arquitectonico",
                                       json.dumps(horas), "[]", None, []), RLS)
    registrar("D12 · quien no dirige no abre un proyecto", ok, msg)

    ok, msg = espera_error(lu, abrir, ("PRUEBA MAL", "Con fase ajena", plantilla["Diseño"], "diseno_arquitectonico",
                                       json.dumps({"ejecucion": 10}), "[]", None, []), "no son de la plantilla")
    registrar("D12 · no se cotizan horas a una fase que la plantilla no tiene", ok, msg)
    ok, msg = espera_error(lu, abrir, ("PRUEBA MAL", "Omite lo obligatorio", plantilla["Diseño"], "diseno_arquitectonico",
                                       "{}", "[]", None, ["anteproyecto"]), "no se pueden omitir")
    registrar("D12 · solo se omite una fase opcional", ok, msg)
    ok, msg = espera_error(lu, abrir, ("PRUEBA MAL", "Equipo mal armado", plantilla["Diseño"], "diseno_arquitectonico",
                                       json.dumps(horas), json.dumps([{"persona_id": Q["cliente"], "papel": "produce"}]),
                                       None, []), "persona externa")
    registrar("D10 · un externo no entra al equipo con papel de producir", ok, msg)
    registrar("D12 · si algo falla al abrir, no queda medio proyecto",
              uno(cur, "select count(*) from proyecto where codigo = 'PRUEBA MAL'") == 0)

    marg = uno(lu, abrir, ("PRUEBA MARGARITAS", "Las Margaritas", plantilla["Diseño"], "diseno_arquitectonico",
                           json.dumps(horas), json.dumps(equipo), v_peq, ["licencia"]))
    fases = todas(cur, "select fase::text, orden, horas_cotizadas::int from proyecto_fase where proyecto_id = %s order by orden", (marg,))
    registrar("D12 · el proyecto nace con sus fases, en orden y con las horas cotizadas",
              fases == [("insight", 1, 8), ("anteproyecto", 2, 80), ("proyecto_final", 3, 120), ("presupuesto", 5, 24)],
              " · ".join(f"{f} {h} h" for f, _, h in fases))
    registrar("D12 · «licencia, si aplica»: se omitió sin tocar las demás",
              "licencia" not in [f for f, _, _ in fases])
    registrar("D12 · el tipo lo pone la plantilla",
              uno(cur, "select tipo::text, variante_chequeo_id from proyecto where id = %s", (marg,)) == ("diseno", v_peq))
    registrar("D12 · el anteproyecto nace exigiendo la aprobación del cliente",
              uno(cur, """select exige_aprobacion_cliente, entrega_cliente from proyecto_fase
                          where proyecto_id = %s and fase = 'anteproyecto'""", (marg,))
              == (True, "Planos, cortes, alzados, modelo y renders"))
    ok, msg = espera_error(lu, "select aplicar_plantilla(%s, %s)", (marg, plantilla["Diseño"]), "una sola vez")
    registrar("D12 · la plantilla se aplica una sola vez", ok, msg)

    obra = uno(lu, abrir, ("PRUEBA OBRA KOLIBRI", "Obra de prueba", plantilla["Obra"], "obra_colega", "{}", "[]", None, []))
    f_obra = todas(cur, "select fase::text, exige_dedicacion from proyecto_fase where proyecto_id = %s order by orden", (obra,))
    registrar("D12 · una obra recorre preconstrucción, ejecución y cierre",
              f_obra == [("preconstruccion", False), ("ejecucion", False), ("cierre", False)], str(f_obra))
    peri = uno(lu, abrir, ("PRUEBA PERITAJE", "Peritaje de prueba", plantilla["Peritaje"], "peritaje", "{}", "[]", None, []))
    f_peri = [r[0] for r in todas(cur, "select fase::text from proyecto_fase where proyecto_id = %s order by orden", (peri,))]
    registrar("D12 · un peritaje recorre levantamiento, informe, presupuesto y entrega del expediente",
              f_peri == ["levantamiento", "informe", "presupuesto", "entrega_expediente"], ", ".join(f_peri))
    mont = uno(lu, abrir, ("PRUEBA MONTAJE", "Montaje de prueba", plantilla["Montaje de interiores"], "interiorismo",
                           "{}", "[]", None, []))
    registrar("D12 · un montaje de interiores no tiene fases",
              uno(cur, "select count(*) from proyecto_fase where proyecto_id = %s", (mont,)) == 0)
    ok, msg = espera_error(lu, "update proyecto_fase set exige_chequeo = false where proyecto_id = %s", (marg,), "solo lo cambia un socio")
    registrar("D12 · lo que exige el cierre no lo afloja quien cierra", ok, msg)

    # ---------- D10 · equipo con papel ----------
    registrar("D10 · quien no tiene papel en el proyecto no lo ve",
              uno(an, "select count(*) from proyecto where id = %s", (marg,)) == 0
              and uno(te, "select count(*) from proyecto where id = %s", (marg,)) == 1)
    ins, ante = [uno(cur, "select id from proyecto_fase where proyecto_id = %s and fase = %s", (marg, f))
                 for f in ("insight", "anteproyecto")]
    suelta = """insert into tarea_diseno (proyecto_id, titulo, asignada_a, asignada_por, fecha_compromiso)
                values (%s, %s, %s, %s, %s)"""
    ok, msg = espera_error(lu, suelta, (marg, "Levantamiento de medidas", Q["andres"], Q["luisa"], "2026-12-01"),
                           "no hace parte del equipo")
    registrar("D10 · quien no tiene papel en el proyecto no recibe tareas de él", ok, msg)
    ok, msg = espera_error(lu, suelta, (marg, "Levantamiento de medidas", Q["teo"], Q["luisa"], None), "sin fecha de entrega")
    registrar("D10 · una tarea no se guarda sin fecha de entrega", ok, msg)
    ok, msg = espera_error(lu, "insert into tarea_diseno (proyecto_id, titulo, asignada_por, fecha_compromiso) values (%s, 'Sin dueño', %s, '2026-12-01')",
                           (marg, Q["luisa"]), "sin persona")
    registrar("D10 · una tarea no se guarda sin persona", ok, msg)
    ok, msg = espera_error(ma, suelta, (marg, "Tarea para otro", Q["teo"], Q["mariana"], "2026-12-01"), RLS)
    registrar("D10 · una practicante no le asigna tareas a otra persona", ok, msg)
    ma.execute(suelta, (marg, "Ordenar la biblioteca de materiales", Q["mariana"], Q["mariana"], "2026-12-01"))
    registrar("D10 · cualquiera del equipo se crea una tarea propia en su proyecto", ma.rowcount == 1)
    ok, msg = espera_error(ma, "update tarea_diseno set asignada_a = %s where proyecto_id = %s and titulo = 'Ordenar la biblioteca de materiales'",
                           (Q["teo"], marg), "la reasigna quien dirige")
    registrar("D10 · y no se la pasa a otro: eso sería asignar por la puerta de atrás", ok, msg)
    cur.execute("insert into acceso_proyecto (persona_id, proyecto_id) values (%s, %s)", (Q["cliente"], marg))
    registrar("D10 · el cliente entra como observador, no como equipo",
              uno(cur, "select papel::text from acceso_proyecto where persona_id = %s and proyecto_id = %s",
                  (Q["cliente"], marg)) == "observa")
    registrar("D10 · cada quien ve con quién trabaja; el cliente solo se ve a sí mismo",
              uno(te, "select count(*) from acceso_proyecto where proyecto_id = %s", (marg,)) == 4
              and uno(cl, "select count(*) from acceso_proyecto where proyecto_id = %s", (marg,)) == 1)

    # ---------- D12 · las tareas típicas de la fase ----------
    prop = todas(lu, "select plantilla_tarea_id, titulo, espacio, fecha_sugerida, prioridad::text from proponer_tareas(%s, %s)",
                 (ante, ["Cocina", "Baño principal"]))
    registrar("D12 · abrir el anteproyecto propone sus tareas típicas, una por espacio donde toca",
              len(prop) == 6 and sum(1 for p in prop if p[2] == "Cocina") == 2,
              " · ".join(p[1] for p in prop))
    registrar("D12 · la fecha propuesta nunca cae en fin de semana ni en festivo",
              all(uno(cur, "select private.es_habil(%s)", (p[3],)) for p in prop))
    registrar("los días hábiles no cuentan el lunes festivo",
              uno(cur, "select private.dias_habiles('2026-10-09', '2026-10-13')") == 1
              and str(uno(cur, "select private.sumar_habiles('2026-10-09', 2)")) == "2026-10-14")

    envio = []
    for pid, titulo, espacio, fecha, _ in prop:
        quien = Q["teo"] if titulo.startswith(("Modelo", "Planos")) else Q["mariana"]
        envio.append({"plantilla_tarea_id": pid, "espacio": espacio, "asignada_a": quien, "fecha_compromiso": str(fecha)})
    creadas = uno(lu, "select crear_tareas(%s, %s::jsonb)", (ante, json.dumps(envio)))
    registrar("D12 · quien dirige las ajusta y las asigna todas de una vez", creadas == 6, f"{creadas} tareas")
    ok, msg = espera_error(lu, "select crear_tareas(%s, %s::jsonb)",
                           (ante, json.dumps(envio[:1] + [{"titulo": "Sin dueño", "fecha_compromiso": "2026-12-01"}])),
                           "no tiene a quién")
    registrar("D12 · si una tarea del lote está mal, no se crea ninguna",
              ok and uno(cur, "select count(*) from tarea_diseno where proyecto_id = %s and fase_id = %s", (marg, ante)) == 6, msg)

    def tarea(titulo):
        return uno(cur, "select id from tarea_diseno where proyecto_id = %s and titulo = %s", (marg, titulo))
    modelo, render, planos = tarea("Modelo · Cocina"), tarea("Renders · Cocina"), tarea("Planos, cortes y alzados")
    registrar("D12 · el render de cada espacio queda esperando el modelo de ese mismo espacio",
              uno(cur, "select bloqueada_por from tarea_diseno where id = %s", (render,)) == modelo)
    ctx = uno(te, "select para_que from v_tarea_contexto where tarea_id = %s", (modelo,))
    registrar("la tarea dice para qué sirve, sin que nadie lo escriba cada vez",
              ctx is not None and "el cliente ve el espacio" in ctx and "Hace parte de anteproyecto" in ctx
              and "el cliente recibe planos" in ctx and "La espera PRUEBA Mariana" in ctx, ctx)

    # ---------- «Mi día» ----------
    cur.execute("update tarea_diseno set fecha_compromiso = private.hoy() - 2 where id = %s", (planos,))
    dia = todas(te, "select titulo, orden, grupo, lectura from v_mi_dia order by orden, fecha_compromiso")
    registrar("«Mi día» · primero lo vencido, después lo que frena a otros",
              dia and dia[0][0] == "Planos, cortes y alzados" and dia[0][2] == "Vencido"
              and [d[2] for d in dia] == sorted([d[2] for d in dia], key=["Vencido", "Para hoy", "Alguien espera por ti",
                                                 "Te lo devolvieron", "Lo que sigue", "En manos de quien revisa"].index),
              " → ".join(f"{d[2]}: {d[0]}" for d in dia))
    frena = [d for d in dia if d[0] == "Modelo · Cocina"]
    registrar("«Mi día» · dice quién espera por la tarea",
              frena and frena[0][2] == "Alguien espera por ti" and "La espera PRUEBA Mariana" in frena[0][3], frena[0][3] if frena else "")
    espera = uno(ma, "select lectura from v_mi_dia where id = %s", (render,))
    registrar("«Mi día» · y a quien espera, le dice a quién", espera is not None and espera.startswith("Esperas a PRUEBA Teo"), espera)
    registrar("«Mi día» · cada quien ve solo lo suyo",
              uno(te, "select count(*) from v_mi_dia where titulo like 'Renders%%'") == 0
              and uno(an, "select count(*) from v_mi_dia where proyecto_id = %s", (marg,)) == 0)

    # ---------- D10 · quien hace la tarea no cambia su fecha ----------
    ok, msg = espera_error(te, "update tarea_diseno set fecha_compromiso = private.hoy() + 30 where id = %s", (planos,),
                           "los cambia quien la asignó")
    registrar("D10 · quien hace la tarea no se corre su propia fecha", ok, msg)
    ok, msg = espera_error(te, "update tarea_diseno set prioridad = 'normal' where id = %s", (modelo,), "los cambia quien la asignó")
    registrar("D10 · ni le baja la prioridad", ok, msg)
    lu.execute("update tarea_diseno set fecha_compromiso = private.hoy() + 3 where id = %s", (planos,))
    registrar("D10 · la fecha la mueve quien la asignó, y queda el rastro",
              uno(cur, "select count(*) from tarea_evento where tarea_id = %s and tipo = 'fecha' and persona_id = %s",
                  (planos, Q["luisa"])) == 1)

    # ---------- D11 · el flujo de revisión ----------
    ok, msg = espera_error(ma, "update tarea_diseno set estado = 'en_revision' where id = %s", (render,), "no puede pedir revisión")
    registrar("D9 · lo que espera a otra tarea no pide revisión antes que ella", ok, msg)
    te.execute("update tarea_diseno set estado = 'en_curso' where id = %s", (modelo,))
    ok, msg = espera_error(te, "update tarea_diseno set estado = 'terminada' where id = %s", (modelo,), "revisión aprobada")
    registrar("D11 · nadie da por terminada su propia tarea", ok, msg)
    ok, msg = espera_error(te, "update tarea_diseno set estado = 'con_observaciones' where id = %s", (modelo,), "quien revisa la devuelve")
    registrar("D11 · ni la marca como devuelta", ok, msg)
    te.execute("update tarea_diseno set estado = 'en_revision', revision_pedida_en = now() - interval '9 days' where id = %s", (modelo,))
    pedida = uno(cur, "select revision_pedida_en > now() - interval '1 minute' from tarea_diseno where id = %s", (modelo,))
    registrar("D11 · pedir revisión son dos toques, y la hora la pone el sistema", pedida is True)
    registrar("«Mi día» · lo que ya está en revisión pasa al final",
              uno(te, "select grupo from v_mi_dia where id = %s", (modelo,)) == "En manos de quien revisa")

    revisar = "insert into revision_diseno (tarea_id, revisor_id, resultado, observaciones) values (%s, %s, %s, %s)"
    ok, msg = espera_error(te, revisar, (modelo, Q["teo"], "aprobada", None), "distinto de quien hizo")
    registrar("D11 · quien hizo la tarea no se la revisa", ok, msg)
    ok, msg = espera_error(ma, revisar, (modelo, Q["mariana"], "aprobada", None), RLS)
    registrar("D11 · una compañera sin el papel de revisar tampoco", ok, msg)
    cola = uno(da, "select titulo, lectura, fuera_de_plazo from v_cola_revision where tarea_id = %s", (modelo,))
    registrar("D11 · la persona que dirección designó ve la tarea en su cola",
              cola is not None and cola[1] == "PRUEBA Teo la dejó hoy" and cola[2] is False, cola[1] if cola else "")
    registrar("D11 · la cola es de quien revisa, no de todo el equipo",
              uno(ma, "select count(*) from v_cola_revision") == 0)
    ok, msg = espera_error(da, revisar, (modelo, Q["dani"], "con_observaciones", None), "revision_observaciones_escritas")
    registrar("D11 · devolver exige una observación escrita", ok, msg)
    da.execute(revisar, (modelo, Q["dani"], "con_observaciones", "El mesón no coincide con la planta"))
    registrar("D11 · devuelta, vuelve sola a quien la hizo",
              uno(te, "select grupo from v_mi_dia where id = %s", (modelo,)) == "Alguien espera por ti"
              and uno(cur, "select estado::text from tarea_diseno where id = %s", (modelo,)) == "con_observaciones")
    te.execute("update tarea_diseno set estado = 'en_revision' where id = %s", (modelo,))
    da.execute(revisar, (modelo, Q["dani"], "aprobada", None))
    estado, cerrada = uno(cur, "select estado::text, terminada_en is not null from tarea_diseno where id = %s", (modelo,))
    registrar("D11 · aprobar termina la tarea en el mismo toque", estado == "terminada" and cerrada)
    registrar("D9 · terminado el modelo, el render ya puede avanzar",
              uno(ma, "select lectura from v_mi_dia where id = %s", (render,)).startswith("Se entrega"))

    rastro = todas(cur, """select e.tipo, e.de, e.a, p.nombre from tarea_evento e
                           left join persona p on p.id = e.persona_id
                           where e.tarea_id = %s and e.tipo in ('creada', 'estado') order by e.ocurrio_en, e.id""", (modelo,))
    registrar("D11 · cada cambio de estado guarda quién y cuándo",
              [(r[1], r[2]) for r in rastro] == [(None, "asignada"), ("asignada", "en_curso"), ("en_curso", "en_revision"),
                                                 ("en_revision", "con_observaciones"), ("con_observaciones", "en_revision"),
                                                 ("en_revision", "terminada")]
              and rastro[0][3] == "PRUEBA Luisa" and rastro[2][3] == "PRUEBA Teo" and rastro[-1][3] == "PRUEBA Dani",
              " → ".join(f"{r[2]} ({(r[3] or 'carga').replace('PRUEBA ', '')})" for r in rastro))
    ok1, msg = espera_error(cur, "update tarea_evento set a = 'terminada' where tarea_id = %s", (modelo,), "no se editan")
    ok2, _ = espera_error(cur, "delete from tarea_evento where tarea_id = %s", (modelo,), "no se borran")
    ok3, _ = espera_error(lu, "insert into tarea_evento (tarea_id, tipo, a) values (%s, 'estado', 'terminada')", (modelo,), "permission denied")
    ok4, _ = espera_error(cur, "delete from tarea_diseno where id = %s", (modelo,), "no se borran")
    registrar("el rastro no se edita, no se borra y nadie lo escribe a mano", ok1 and ok2 and ok3 and ok4, msg)
    ok, msg = espera_error(te, "update tarea_diseno set estado = 'en_curso' where id = %s", (modelo,), "solo la reabre dirección")
    registrar("D11 · una tarea terminada solo la reabre dirección", ok, msg)
    lu.execute("update tarea_diseno set estado = 'en_curso' where id = %s", (modelo,))
    te.execute("update tarea_diseno set estado = 'en_revision' where id = %s", (modelo,))
    ok, msg = espera_error(te, "update tarea_diseno set estado = 'terminada' where id = %s", (modelo,), "revisión aprobada")
    registrar("D11 · reabierta, la aprobación anterior ya no sirve: se revisa otra vez", ok, msg)
    antes = uno(cur, "select revision_pedida_en from tarea_diseno where id = %s", (modelo,))
    te.execute("update tarea_diseno set revision_pedida_en = now() - interval '30 days' where id = %s", (modelo,))
    registrar("D11 · la hora en que se pidió la revisión no se retoca",
              uno(cur, "select revision_pedida_en from tarea_diseno where id = %s", (modelo,)) == antes)
    da.execute(revisar, (modelo, Q["dani"], "aprobada", None))

    ok, msg = espera_error(te, """insert into tarea_diseno (proyecto_id, titulo, asignada_a, asignada_por, fecha_compromiso, estado)
                                  values (%s, 'Tarea que nace entregada', %s, %s, '2026-12-01', 'en_revision')""",
                           (marg, Q["teo"], Q["teo"]), "nace asignada")
    registrar("D11 · una tarea no nace ya entregada", ok, msg)
    da.execute(suelta, (marg, "Detalle de carpintería", Q["mariana"], Q["dani"], "2026-12-01"))
    ok, msg = espera_error(da, "update tarea_diseno set estado = 'en_revision' where proyecto_id = %s and titulo = 'Detalle de carpintería'",
                           (marg,), "la pide quien tiene la tarea")
    registrar("D11 · quien asignó no entrega la tarea por quien la hace", ok, msg)

    # El plazo acordado: dos días hábiles.
    te.execute("update tarea_diseno set estado = 'en_revision' where id = %s", (planos,))
    cur.execute("update tarea_diseno set revision_pedida_en = now() - interval '9 days' where id = %s", (planos,))
    tarde = uno(da, "select fuera_de_plazo, dias_habiles_esperando, lectura from v_cola_revision where tarea_id = %s", (planos,))
    registrar("D11 · una revisión que pasa de dos días hábiles se ve fuera de plazo",
              tarde is not None and tarde[0] is True and tarde[1] > 2 and "el acuerdo son 2" in tarde[2], tarde[2] if tarde else "")

    # ---------- D13 · la lista de chequeo según la variante ----------
    lu.execute("update proyecto_fase set estado = 'en_curso' where id = %s", (ins,))
    chk = uno(cur, "select id, lista_id from chequeo where fase_id = %s", (ins,))
    registrar("D13 · al abrirse, la fase queda con su lista de chequeo", chk is not None and chk[1] == l_ins)
    item = uno(cur, "select id from lista_chequeo_item where lista_id = %s", (l_ins,))
    lu.execute("insert into chequeo_respuesta (chequeo_id, item_id, cumple, verificado_por) values (%s, %s, true, %s)",
               (chk[0], item, Q["luisa"]))
    te.execute("insert into dedicacion (persona_id, fecha, bloque, proyecto_id) values (%s, private.hoy(), 'manana', %s)",
               (Q["teo"], marg))
    lu.execute("update proyecto_fase set estado = 'cerrada' where id = %s", (ins,))
    lu.execute("update proyecto_fase set estado = 'en_curso' where id = %s", (ante,))
    registrar("D13 · el anteproyecto toma la lista de la variante del proyecto, no la otra",
              uno(cur, "select lista_id from chequeo where fase_id = %s", (ante,)) == l_peq)
    ok, msg = espera_error(lu, "insert into chequeo (lista_id, fase_id) values (%s, %s)", (l_com, ante), "otra variante")
    registrar("D13 · la lista de otra variante no sirve para este proyecto", ok, msg)

    # ---------- D10 · los practicantes rotan ----------
    ok, msg = espera_error(lu, "delete from acceso_proyecto where persona_id = %s and proyecto_id = %s", (Q["teo"], marg),
                           "reasígnelas antes")
    registrar("D10 · no se retira del equipo a quien tiene trabajo abierto", ok, msg)
    ajenas = uno(te, "select reasignar_tareas(%s, %s, %s)", (Q["mariana"], Q["teo"], marg))
    registrar("D10 · quien no dirige no reasigna el trabajo de nadie",
              ajenas == 0 and uno(cur, "select count(*) from tarea_evento where tipo = 'reasignada'") == 0, f"{ajenas} tareas")
    ok, msg = espera_error(lu, "update acceso_proyecto set papel = 'observa' where persona_id = %s and proyecto_id = %s",
                           (Q["teo"], marg), "solo como observadora")
    registrar("D10 · tampoco se le quita el papel dejándole el trabajo", ok, msg)
    movidas = uno(lu, "select reasignar_tareas(%s, %s, %s)", (Q["teo"], Q["mariana"], marg))
    lu.execute("delete from acceso_proyecto where persona_id = %s and proyecto_id = %s", (Q["teo"], marg))
    registrar("D10 · su trabajo abierto pasa a otra persona en un solo paso, y entonces sí sale",
              movidas == 2 and lu.rowcount == 1
              and uno(cur, "select count(*) from tarea_evento where tipo = 'reasignada' and persona_id = %s", (Q["luisa"],)) == 2
              and uno(te, "select count(*) from proyecto where id = %s", (marg,)) == 0, f"{movidas} tareas")

    # ---------- el tablero de quien dirige ----------
    carga = uno(lu, "select abiertas, lectura from v_carga_equipo where persona_id = %s", (Q["mariana"],))
    registrar("el tablero dice la carga de cada persona en una frase", carga is not None and carga[0] >= 7, carga[1] if carga else "")
    registrar("el tablero completo es de dirección: los demás ven solo sus proyectos",
              uno(lu, "select count(*) from v_carga_equipo") > uno(cl, "select count(*) from v_carga_equipo"))

    # ---------- el director de proyectos de construcción ----------
    cur.execute("insert into auth.users (id, email, email_confirmed_at) values ('00000000-0000-4000-8000-0000000000dd', 'daniel@prueba.local', now())")
    daniel = uno(cur, """insert into persona (nombre, rol, es_interno, auth_user_id, correo, profesion_id)
                         select 'PRUEBA Daniel', 'director_proyecto', true, '00000000-0000-4000-8000-0000000000dd',
                                'daniel@prueba.local', pf.id from profesion pf where pf.nombre = 'Ingeniero civil' returning id""")
    _, dn = sesion(uri, "00000000-0000-4000-8000-0000000000dd")
    registrar("el director de proyecto no es dirección: sin papel no ve ninguna obra",
              uno(dn, "select count(*) from proyecto") == 0)
    lu.execute("insert into acceso_proyecto (persona_id, proyecto_id, papel) values (%s, %s, 'dirige'), (%s, %s, 'produce')",
               (daniel, obra, Q["mariana"], obra))
    dn.execute(suelta, (obra, "Cantidades de mampostería", Q["mariana"], daniel, "2026-12-01"))
    registrar("con el papel de dirigir, ve su obra y asigna en ella",
              uno(dn, "select count(*) from proyecto") == 1 and dn.rowcount == 1)
    lu.execute("insert into acceso_proyecto (persona_id, proyecto_id, papel) values (%s, %s, 'produce')", (daniel, marg))
    dn.execute(suelta, (marg, "Cantidades de acabados", Q["mariana"], daniel, "2026-12-01"))
    registrar("donde solo produce, puede lo mismo que un arquitecto: asignar", dn.rowcount == 1)
    pres = uno(cur, "insert into presupuesto (proyecto_id, elaborado_por) values (%s, %s) returning id", (obra, Q["mariana"]))
    cur.execute("update presupuesto set validado_por = %s where id = %s", (daniel, pres))
    ok, msg = espera_error(cur, "update presupuesto set validado_por = %s where id = %s", (Q["andres"], pres), "la firma un profesional")
    registrar("valida presupuestos como profesional; un residente no",
              ok and uno(cur, "select validado_por from presupuesto where id = %s", (pres,)) == daniel, msg)
    registrar("la profesión se escoge de una lista, aparte del rol",
              uno(cur, """select pf.nombre from persona p join profesion pf on pf.id = p.profesion_id where p.id = %s""",
                  (daniel,)) == "Ingeniero civil"
              and uno(lu, "select count(*) from profesion") >= 8)
    dn.connection.close()

    permisos = uno(cur, """select has_function_privilege('authenticated', 'public.crear_tareas(uuid, jsonb)', 'execute')
                             and not has_function_privilege('authenticated', 'private.registrar_tarea_evento()', 'execute')
                             and not has_function_privilege('anon', 'public.abrir_proyecto(text, text, uuid, public.unidad_negocio, jsonb, jsonb, uuid, public.fase_proyecto[], uuid, uuid)', 'execute')
                             and not has_table_privilege('authenticated', 'public.tarea_evento', 'INSERT')
                             and not has_table_privilege('authenticated', 'public.plantilla_tarea', 'DELETE')""")
    registrar("lo nuevo nace cerrado: solo se abre lo que la aplicación necesita", permisos)
    for c in (lu, fe, ma, an, cl, te, da):
        c.connection.close()


# =============================================================================
# 12 · Indicadores de impacto y solicitudes de corrección
# =============================================================================
def s12_indicadores(uri, cur):
    seccion("12 · Indicadores de impacto por persona · etapa 2")
    # Una persona sin historia: lo que hicieron los demás en las secciones anteriores no se le mezcla.
    cur.execute("insert into auth.users (id, email, email_confirmed_at) values ('00000000-0000-4000-8000-00000000ca20', 'caro@prueba.local', now())")
    cur.execute("""insert into persona (nombre, rol, es_interno, auth_user_id, correo, horas_semana)
                   values ('PRUEBA Caro', 'practicante', true, '00000000-0000-4000-8000-00000000ca20', 'caro@prueba.local', 40)""")
    Q = {n: uno(cur, "select id from persona where correo = %s", (f"{n}@prueba.local",))
         for n in ("felipe", "luisa", "mariana", "caro", "dani")}
    uid = {n: uno(cur, "select auth_user_id::text from persona where id = %s", (Q[n],)) for n in Q}
    _, lu = sesion(uri, uid["luisa"])
    _, fe = sesion(uri, uid["felipe"])
    _, ma = sesion(uri, uid["mariana"])
    _, te = sesion(uri, uid["caro"])

    plantilla = uno(cur, "select id from plantilla_proyecto where nombre = 'Diseño'")
    proy = uno(lu, """select abrir_proyecto('PRUEBA INDICADORES', 'Casa Indicadores', %s, 'diseno_arquitectonico'::unidad_negocio,
                                            '{"insight": 8}'::jsonb, %s::jsonb, null, '{licencia}'::fase_proyecto[])""",
               (plantilla, json.dumps([{"persona_id": Q["caro"], "papel": "produce"},
                                       {"persona_id": Q["mariana"], "papel": "produce"},
                                       {"persona_id": Q["dani"], "papel": "revisa"}])))
    ins = uno(cur, "select id from proyecto_fase where proyecto_id = %s and fase = 'insight'", (proy,))

    def hecha(titulo, compromiso, entregada, prioridad="normal", devuelta=False, quien="caro", por="luisa"):
        """Una tarea que recorrió todo el flujo; después se le ponen las fechas del caso (días antes de hoy)."""
        tid = uno(cur, """insert into tarea_diseno (proyecto_id, titulo, asignada_a, asignada_por, fecha_compromiso, prioridad)
                          values (%s, %s, %s, %s, private.hoy() - %s, %s) returning id""",
                  (proy, titulo, Q[quien], Q[por], compromiso, prioridad))
        if entregada is None:
            return tid
        cur.execute("update tarea_diseno set estado = 'en_revision' where id = %s", (tid,))
        if devuelta:
            cur.execute("""insert into revision_diseno (tarea_id, revisor_id, resultado, observaciones)
                           values (%s, %s, 'con_observaciones', 'Falta la cota del mesón')""", (tid, Q["dani"]))
            cur.execute("update tarea_diseno set estado = 'en_revision' where id = %s", (tid,))
        cur.execute("insert into revision_diseno (tarea_id, revisor_id, resultado) values (%s, %s, 'aprobada')", (tid, Q["dani"]))
        cur.execute("""update tarea_diseno
                          set revision_pedida_en = now() - make_interval(days => %s),
                              terminada_en = now() - make_interval(days => %s)
                        where id = %s""", (entregada, max(entregada - 1, 0), tid))
        return tid

    a = hecha("Levantamiento del lote", 14, 15, "bloqueante")
    b = hecha("Plano de redes", 12, 6, devuelta=True)
    cur.execute("""insert into tarea_diseno (proyecto_id, titulo, asignada_a, asignada_por, fecha_compromiso, bloqueada_por)
                   values (%s, 'Presupuesto de redes', %s, %s, private.hoy() + 5, %s)""", (proy, Q["mariana"], Q["luisa"], b))
    hecha("Fachada principal", 3, 4, "alta")
    hecha("Cuadro de áreas", 2, 3)
    hecha("Detalle de escalera", 1, None)
    hecha("Ordenar mis archivos", 5, None, por="caro")

    ind = lambda c, *p: {r[0]: r[1:] for r in todas(c, "select indicador, numerador, denominador, suficiente, frase from indicadores(%s, %s)" if p
                                                    else "select indicador, numerador, denominador, suficiente, frase from indicadores()", p or None)}
    pocos = ind(te)
    registrar("D14 · con menos de cinco tareas revisadas no se dice nada: una frase con pocos datos miente",
              list(pocos) == ["sin_datos"] and pocos["sin_datos"][2] is False
              and "van 4 tareas revisadas de las 5" in pocos["sin_datos"][3], pocos.get("sin_datos", ("", "", "", ""))[3])

    hecha("Planta de cubiertas", 1, 2)
    hecha("Detalle de ventana", 0, None)
    yo = ind(te)
    registrar("D14 · la que vence hoy y sigue abierta todavía no cuenta en contra: el día no ha terminado",
              uno(te, "select count(*) from indicador_detalle('cumplio') where titulo = 'Detalle de ventana'") == 0)
    registrar("D14 · «Cumplió lo que pesaba» dice cuántas llegaron a tiempo y qué pasó con las que frenaban a otros",
              yo["cumplio"][3] == "Entregaste a tiempo 4 de 6, y de las 2 que frenaban a otros una llegó tarde", yo["cumplio"][3])
    registrar("D14 · lo crítico pesa más: la que frena a otros vale tres y la de prioridad alta, dos",
              (yo["cumplio"][0], yo["cumplio"][1]) == (7, 9), f"{yo['cumplio'][0]} de {yo['cumplio'][1]} puntos")
    registrar("D14 · la tarea que alguien se creó a sí mismo no suma ni resta",
              uno(te, "select count(*) from indicador_detalle('cumplio') where titulo = 'Ordenar mis archivos'") == 0
              and uno(te, "select count(*) from indicador_detalle('cumplio')") == 6)
    registrar("D14 · «Bien a la primera» cuenta lo que pasó la revisión sin devolverse",
              yo["primera"][3] == "4 de 5 pasaron la revisión sin correcciones", yo["primera"][3])
    dias = uno(cur, "select private.dias_habiles(private.hoy() - 12, private.hoy() - 5)")
    espero = "un día hábil" if dias == 1 else f"{dias} días hábiles"
    registrar("D14 · «Nadie esperó por ti» nombra a quien esperó, cuánto y por qué tarea",
              dias > 0 and yo["espera"][3] == f"PRUEBA Mariana esperó {espero} por «Plano de redes»", yo["espera"][3])
    registrar("D14 · ningún indicador cuenta tareas hechas ni horas trabajadas como mérito",
              set(yo) == {"cumplio", "primera", "espera", "hitos", "margen"})

    # Aporte a los hitos y cuidado del margen: salen de la dedicación y del cierre de la fase.
    lu.execute("update proyecto_fase set estado = 'en_curso', fecha_compromiso = private.hoy() + 2 where id = %s", (ins,))
    te.execute("insert into dedicacion (persona_id, fecha, bloque, proyecto_id) values (%s, private.hoy(), 'tarde', %s)", (Q["caro"], proy))
    cur.execute("insert into dedicacion (persona_id, fecha, bloque, proyecto_id, fase_id) values (%s, private.hoy(), 'manana', %s, %s)",
                (Q["dani"], proy, ins))
    registrar("D14 · «Cuidó el margen» compara las horas de la fase con las cotizadas y dice cuántas son suyas",
              ind(te)["margen"][3] == "Insight de Casa Indicadores lleva 8 de 8 horas cotizadas; 4 son tuyas", ind(te)["margen"][3])
    chk = uno(cur, "select id from chequeo where fase_id = %s", (ins,))
    lu.execute("""insert into chequeo_respuesta (chequeo_id, item_id, cumple, verificado_por)
                  select %s, i.id, true, %s from lista_chequeo_item i join chequeo c on c.lista_id = i.lista_id where c.id = %s""",
               (chk, Q["luisa"], chk))
    lu.execute("update proyecto_fase set estado = 'cerrada' where id = %s", (ins,))
    registrar("D14 · «Aporte a los hitos» dice qué parte de la fase cerrada puso la persona",
              ind(te)["hitos"][3] == "Pusiste más de una cuarta parte de las horas de insight de Casa Indicadores, que se cerró a tiempo",
              ind(te)["hitos"][3])

    # Quién ve qué.
    ok, msg = espera_error(ma, "select * from indicadores(%s)", (Q["caro"],), "solo los ve dirección")
    registrar("D14 · nadie ve los indicadores de un compañero", ok, msg)
    ok, msg = espera_error(ma, "select * from indicador_detalle('cumplio', %s)", (Q["caro"],), "solo los ve dirección")
    registrar("D14 · ni el detalle del que salen", ok, msg)
    direccion = ind(lu, Q["caro"], None)
    registrar("D14 · dirección ve los de todos, y la frase habla de la persona, no le habla a ella",
              direccion["cumplio"][3].startswith("PRUEBA entregó a tiempo 4 de 6"), direccion["cumplio"][3])
    ok, msg = espera_error(te, "select * from private.hechos_tarea(%s, private.hoy() - 30, private.hoy())", (Q["mariana"],), "permission denied")
    registrar("D14 · los hechos de otro no se alcanzan por la puerta de atrás", ok, msg)

    # Lo que revisa quien revisa.
    cur.execute("update revision_diseno set revisada_en = now() + interval '8 days' where tarea_id = %s and resultado = 'aprobada'", (a,))
    rev = uno(lu, "select frase, numerador, denominador from indicadores(%s, private.hoy() + 8) where indicador = 'revisiones'", (Q["dani"],))
    n = uno(cur, "select count(*) from revision_diseno where revisor_id = %s", (Q["dani"],))
    registrar("D14 · quien revisa tiene el suyo: cuántas entregas esperaron más de lo acordado",
              rev is not None and rev[0] == f"PRUEBA revisó {n} entregas; una esperó más de 2 días hábiles"
              and (rev[1], rev[2]) == (n - 1, n), rev[0] if rev else "")
    cur.execute("update revision_diseno set revisada_en = now() where tarea_id = %s and resultado = 'aprobada'", (a,))
    mio = ind(lu)
    registrar("D14 · quien dirige tiene además el de las tareas que asignó sin fecha, y no le salen frases vacías",
              set(mio) == {"revisiones", "sin_fecha"} and "sin_fecha" not in yo, mio.get("sin_fecha", ("", "", "", ""))[3])

    # ---------- D15 · abrir la frase y pedir que se corrija un dato ----------
    detalle = todas(te, "select titulo, hecho, a_favor, excluida from indicador_detalle('cumplio') order by titulo")
    redes = [d for d in detalle if d[0] == "Plano de redes"][0]
    registrar("D15 · cada frase se abre y muestra las tareas y fechas de las que sale",
              len(detalle) == 6 and redes[2] is False and "6 días después" in redes[1] and "otra persona dependía de ella" in redes[1],
              redes[1])
    pedir = "insert into solicitud_correccion (persona_id, indicador, tarea_id, motivo) values (%s, 'cumplio', %s, %s)"
    ok, msg = espera_error(ma, pedir, (Q["mariana"], b, "Esa tarea no debería contarle a Caro"), "tarea propia")
    registrar("D15 · solo se pide corregir un dato propio", ok, msg)
    te.execute(pedir, (Q["caro"], b, "La fecha se movió por un cambio que pidió el cliente el día anterior"))
    sol = uno(cur, "select id from solicitud_correccion where tarea_id = %s", (b,))
    try:
        te.execute("update solicitud_correccion set estado = 'aceptada', excluir = true, respuesta = 'Me la acepto' where id = %s", (sol,))
        alcanzo = te.rowcount
    except psycopg2.Error:
        alcanzo = 1      # la vio y solo la detuvo la segunda barrera
    registrar("D15 · quien la pide no se la resuelve: ni siquiera la alcanza",
              alcanzo == 0 and uno(cur, "select estado from solicitud_correccion where id = %s", (sol,)) == "abierta")
    registrar("D15 · mientras nadie la resuelva, el dato sigue contando", ind(te)["cumplio"][3] == yo["cumplio"][3])
    lu.execute("""update solicitud_correccion set estado = 'aceptada', excluir = true,
                         respuesta = 'El cliente cambió el alcance el día anterior' where id = %s""", (sol,))
    despues = ind(te)
    registrar("D15 · dirección la acepta y ese dato deja de contar",
              despues["cumplio"][3] == "Entregaste a tiempo 4 de 5, incluida la que frenaba a otros", despues["cumplio"][3])
    registrar("D15 · y al abrir la frase se ve cuál se excluyó",
              uno(te, "select excluida from indicador_detalle('cumplio') where titulo = 'Plano de redes'") is True
              and uno(cur, "select resuelta_por from solicitud_correccion where id = %s", (sol,)) == Q["luisa"])
    ok1, msg = espera_error(lu, "update solicitud_correccion set respuesta = 'Mejor no' where id = %s", (sol,), "no se cambia")
    ok2, _ = espera_error(cur, "delete from solicitud_correccion where id = %s", (sol,), "no se borran")
    registrar("D15 · la corrección deja rastro: resuelta, no se cambia ni se borra",
              ok1 and ok2 and uno(cur, "select count(*) from evento_auditoria where tabla = 'solicitud_correccion' and fila_id = %s",
                                  (str(sol),)) == 2, msg)
    propia = uno(fe, """insert into tarea_diseno (proyecto_id, titulo, asignada_a, asignada_por, fecha_compromiso)
                        values (%s, 'Revisar el contrato', %s, %s, private.hoy() + 3) returning id""", (proy, Q["luisa"], Q["felipe"]))
    lu.execute(pedir, (Q["luisa"], propia, "La fecha de esta tarea quedó mal desde el principio"))
    ok, msg = espera_error(lu, """update solicitud_correccion set estado = 'aceptada', excluir = true, respuesta = 'Aceptada'
                                  where tarea_id = %s""", (propia,), "su propio indicador")
    registrar("D15 · ni siquiera en dirección alguien resuelve la corrección de su propio indicador", ok, msg)
    for c in (lu, fe, ma, te):
        c.connection.close()


# =============================================================================
# 13 · Mensajes: qué sale, a quién, cuántos al día y a qué horas
# =============================================================================
def s13_mensajes(uri, cur):
    seccion("13 · Mensajes a cada persona, con límites y horario · etapa 2")
    # El reloj se le pasa a la base: martes 6 de octubre de 2026, una semana sin festivos.
    MAR_10, MAR_6AM, MAR_7PM, MAR_1635 = ("2026-10-06 10:00:00-05", "2026-10-06 06:00:00-05",
                                          "2026-10-06 19:00:00-05", "2026-10-06 16:35:00-05")
    MIE_8, MIE_10, JUE_10, SAB_10 = ("2026-10-07 08:00:00-05", "2026-10-07 10:00:00-05",
                                     "2026-10-08 10:00:00-05", "2026-10-10 10:00:00-05")
    Q, uid = {}, {}
    for n, (nombre, rol, cola) in {"sara": ("Sara Prueba", "practicante", "5a"), "nico": ("Nico Prueba", "practicante", "1c"),
                                   "vero": ("Vero Prueba", "arquitecto", "7e")}.items():
        uid[n] = f"00000000-0000-4000-8000-0000000013{cola}"
        cur.execute("insert into auth.users (id, email, email_confirmed_at) values (%s, %s, now())", (uid[n], f"{n}@prueba.local"))
        Q[n] = uno(cur, """insert into persona (nombre, rol, es_interno, auth_user_id, correo)
                           values (%s, %s, true, %s, %s) returning id""", (nombre, rol, uid[n], f"{n}@prueba.local"))
    Q["luisa"] = uno(cur, "select id from persona where correo = 'luisa@prueba.local'")
    Q["caro"] = uno(cur, "select id from persona where correo = 'caro@prueba.local'")
    _, lu = sesion(uri, USUARIOS["luisa"][0])
    _, sa = sesion(uri, uid["sara"])
    _, ni = sesion(uri, uid["nico"])

    proy = uno(lu, """select abrir_proyecto('PRUEBA MENSAJES', 'Casa Mensajes', (select id from plantilla_proyecto where nombre = 'Diseño'),
                                            'diseno_arquitectonico'::unidad_negocio, '{"insight": 8}'::jsonb, %s::jsonb)""",
               (json.dumps([{"persona_id": Q["sara"], "papel": "produce"}, {"persona_id": Q["nico"], "papel": "produce"},
                            {"persona_id": Q["vero"], "papel": "revisa"}]),))
    ins = uno(cur, "select id from proyecto_fase where proyecto_id = %s and fase = 'insight'", (proy,))

    def tarea(titulo, quien, compromiso, prioridad="normal", fase=None, espera=None, estado=None):
        tid = uno(cur, """insert into tarea_diseno (proyecto_id, fase_id, titulo, asignada_a, asignada_por, fecha_compromiso, prioridad, bloqueada_por)
                          values (%s, %s, %s, %s, %s, %s, %s, %s) returning id""",
                  (proy, fase, titulo, Q[quien], Q["luisa"], compromiso, prioridad, espera))
        if estado:
            cur.execute("update tarea_diseno set estado = %s where id = %s", (estado, tid))
        return tid

    tarea("Planta de primer piso", "sara", "2026-10-07")
    corte = tarea("Corte longitudinal", "sara", "2026-10-05")
    tarea("Cuadro de acabados", "sara", "2026-09-29")
    niveles = tarea("Levantamiento de niveles", "sara", "2026-10-08", "bloqueante", fase=ins)
    tarea("Planta de cimentación", "nico", "2026-10-09", espera=niveles)
    fachada = tarea("Fachada posterior", "sara", "2026-10-12", estado="en_revision")
    bano = tarea("Detalle de baño", "nico", "2026-10-12", estado="en_revision")
    tarea("Detalle de cocina", "nico", "2026-10-12", estado="en_revision")
    puertas = tarea("Cuadro de puertas", "nico", "2026-10-05")
    cur.execute("insert into dedicacion (persona_id, fecha, bloque, tipo) values (%s, '2026-10-06', 'manana', 'ausencia')", (Q["nico"],))

    gen = lambda cuando: uno(cur, "select private.generar_mensajes(%s::timestamptz)", (cuando,))
    desp = lambda cuando: uno(cur, "select private.despachar_mensajes(%s::timestamptz)", (cuando,))
    textos = lambda quien, extra="": [r[0] for r in todas(cur, f"select texto from mensaje where persona_id = %s {extra} order by creado_en, id", (Q[quien],))]
    cuantos = lambda quien, extra: uno(cur, f"select count(*) from mensaje where persona_id = %s and {extra}", (Q[quien],))

    gen(MAR_10)
    de_sara = textos("sara")
    registrar("D16 · se acerca una entrega: avisa el día anterior",
              "Mañana entregas «Planta de primer piso» de Casa Mensajes" in de_sara, " | ".join(de_sara)[:200])
    registrar("D16 · tarea vencida: le llega a quien la tiene y a quien la asignó, con la tarea exacta",
              "«Corte longitudinal» de Casa Mensajes se entregaba el 05/10 y sigue abierta" in de_sara
              and "Sara tenía «Corte longitudinal» de Casa Mensajes para el 05/10 y sigue abierta" in textos("luisa")
              and uno(cur, "select tarea_id from mensaje where persona_id = %s and clave like %s", (Q["sara"], f"vencida:{corte}:%")) == corte)
    registrar("D16 · alguien espera por ti: dice quién, qué no puede hacer y por cuál tarea",
              "Nico no puede avanzar con «Planta de cimentación» hasta que cierres «Levantamiento de niveles»" in de_sara)
    registrar("D16 · hay algo para revisar: varias piezas de la misma persona llegan en un solo mensaje",
              textos("vero", "and tipo = 'revision_pendiente'")
              == ["Sara te dejó «Fachada posterior» de Casa Mensajes para revisar", "Nico te dejó 2 piezas de Casa Mensajes para revisar"]
              or sorted(textos("vero", "and tipo = 'revision_pendiente'"))
              == sorted(["Sara te dejó «Fachada posterior» de Casa Mensajes para revisar", "Nico te dejó 2 piezas de Casa Mensajes para revisar"]),
              " | ".join(textos("vero")))
    registrar("D16 · al quinto día hábil de atraso sube a quien dirige; antes no",
              "Sara lleva 5 días hábiles de atraso con «Cuadro de acabados» de Casa Mensajes" in textos("luisa")
              and uno(cur, "select count(*) from mensaje where proyecto_id = %s and clave like '%%:sube'", (proy,)) == 1)
    registrar("D16 · correr el generador otra vez no repite nada", gen(MAR_10) == 0)
    registrar("D16 · antes de las 4:30 nadie pregunta por el registro del día",
              uno(cur, "select count(*) from mensaje where tipo = 'falta_registrar_dia'") == 0)

    # ---------- horario ----------
    registrar("D16 · nada sale antes de las 7:30 ni después de las 5",
              desp(MAR_6AM) == 0 and desp(MAR_7PM) == 0 and uno(cur, "select count(*) from mensaje where estado = 'listo'") == 0)
    registrar("D16 · el sábado no se genera ni sale nada",
              gen(SAB_10) == 0 and desp(SAB_10) == 0 and uno(cur, "select count(*) from mensaje where estado = 'listo'") == 0)

    # ---------- máximo dos al día ----------
    desp(MAR_10)
    listos = todas(cur, "select tipo, texto from mensaje where persona_id = %s and estado = 'listo' order by tipo", (Q["sara"],))
    registrar("D16 · máximo dos mensajes al día: sale el más urgente y los demás van juntos en uno",
              [l[0] for l in listos] == ["alguien_espera", "resumen"] and listos[1][1].startswith("Tienes 3 avisos más:")
              and "Mañana entregas" in listos[1][1] and cuantos("sara", "estado = 'agrupado'") == 3 and cuantos("sara", "estado = 'en_cola'") == 0,
              listos[1][1].replace("\n", " ") if len(listos) > 1 else str(listos))
    registrar("D16 · quien marcó ausencia no recibe nada ese día",
              cuantos("nico", "estado = 'listo'") == 0 and cuantos("nico", "estado = 'en_cola'") >= 1)

    # ---------- al momento ----------
    devolver = "insert into revision_diseno (tarea_id, revisor_id, resultado, observaciones) values (%s, %s, 'con_observaciones', 'Falta acotar')"
    cur.execute(devolver, (fachada, Q["vero"]))
    cur.execute(devolver, (bano, Q["vero"]))
    registrar("D16 · te devolvieron una tarea: queda escrito al momento",
              "Vero devolvió «Fachada posterior» con una observación" in textos("sara", "and estado = 'en_cola'"))
    desp("2026-10-06 11:00:00-05")
    registrar("D16 · con el cupo del día gastado, el tercero espera a mañana",
              cuantos("sara", "estado = 'listo'") == 2 and cuantos("sara", "estado = 'en_cola' and tipo = 'tarea_devuelta'") == 1)

    # ---------- registrar el día ----------
    gen(MAR_1635); desp(MAR_1635)
    registrar("D16 · a las 4:30, a quien no ha registrado el día; no gasta cupo y no molesta al ausente",
              cuantos("sara", "tipo = 'falta_registrar_dia' and estado = 'listo'") == 1
              and cuantos("sara", "estado = 'listo'") == 3 and cuantos("nico", "tipo = 'falta_registrar_dia'") == 0,
              textos("sara", "and tipo = 'falta_registrar_dia'")[0])

    # ---------- al día siguiente ----------
    cur.execute("update tarea_diseno set estado = 'en_revision' where id = %s", (puertas,))
    desp(MIE_8)
    registrar("D16 · a la mañana siguiente sale lo que quedó esperando",
              cuantos("sara", "tipo = 'tarea_devuelta' and estado = 'listo'") == 1
              and cuantos("nico", "tipo = 'tarea_devuelta' and estado = 'listo'") == 1)
    registrar("D16 · lo que dejó de tener sentido no sale tarde: la vencida que ya se entregó se descarta",
              uno(cur, "select estado from mensaje where persona_id = %s and clave like %s", (Q["nico"], f"vencida:{puertas}:%")) == "descartado")
    gen(MIE_10)
    registrar("D16 · una tarea vencida no se repite a diario, ni avisa dos veces de lo mismo",
              uno(cur, "select count(*) from mensaje where persona_id = %s and clave like %s", (Q["sara"], f"vencida:{corte}:%")) == 1
              and cuantos("sara", "texto like '«Cuadro de acabados»%%'") == 1)
    gen(JUE_10)
    registrar("D16 · vuelve al tercer día hábil de atraso",
              "«Corte longitudinal» de Casa Mensajes lleva 3 días hábiles de atraso" in textos("sara"))

    # ---------- reconocimiento ----------
    cur.execute("update tarea_diseno set estado = 'en_revision' where id = %s", (niveles,))
    cur.execute("insert into revision_diseno (tarea_id, revisor_id, resultado) values (%s, %s, 'aprobada')", (niveles, Q["vero"]))
    registrar("D16 · reconocimiento: se aprobó lo que frenaba a otro, y dice a quién destrabó",
              "Se aprobó «Levantamiento de niveles» a la primera. Nico ya puede seguir" in textos("sara", "and tipo = 'reconocimiento'"),
              " | ".join(textos("sara", "and tipo = 'reconocimiento'")))
    lu.execute("update proyecto_fase set estado = 'en_curso' where id = %s", (ins,))
    sa.execute("insert into dedicacion (persona_id, fecha, bloque, proyecto_id) values (%s, private.hoy(), 'manana', %s)", (Q["sara"], proy))
    chk = uno(cur, "select id from chequeo where fase_id = %s", (ins,))
    lu.execute("""insert into chequeo_respuesta (chequeo_id, item_id, cumple, verificado_por)
                  select c.id, i.id, true, %s from chequeo c join lista_chequeo_item i on i.lista_id = c.lista_id where c.id = %s""",
               (Q["luisa"], chk))
    lu.execute("update proyecto_fase set estado = 'cerrada' where id = %s", (ins,))
    registrar("D16 · reconocimiento: al cerrarse la fase, a cada quien lo que puso en ella",
              "Se cerró insight de Casa Mensajes. La única pieza era tuya y pasó a la primera" in textos("sara", "and tipo = 'reconocimiento'"),
              " | ".join(textos("sara", "and tipo = 'reconocimiento'")))

    # ---------- tu semana ----------
    viernes = str(uno(cur, """select d::date from generate_series(private.hoy(), private.hoy() + 13, interval '1 day') d
                              where private.es_habil(d::date)
                                and not exists (select 1 from generate_series(d::date + 1, d::date + (5 - extract(isodow from d)::int),
                                                                              interval '1 day') g where private.es_habil(g::date))
                              order by d limit 1"""))
    gen(f"{viernes} 10:00:00-05")
    temprano = cuantos("caro", "tipo = 'tu_semana'")
    gen(f"{viernes} 15:30:00-05")
    semana = textos("caro", "and tipo = 'tu_semana'")
    registrar("D16 · tu semana: el último día hábil en la tarde, con tus frases de impacto y en segunda persona",
              temprano == 0 and len(semana) == 1 and "Entregaste a tiempo" in semana[0] and "pasaron la revisión" in semana[0],
              semana[0].replace("\n", " · ") if semana else "")
    registrar("D16 · a quien todavía no tiene datos suficientes no se le manda una frase vacía",
              cuantos("nico", "tipo = 'tu_semana'") == 0)

    # ---------- de quién son ----------
    registrar("D16 · cada quien lee sus mensajes; ni dirección ve los de otro",
              uno(sa, "select count(*) from mensaje") == cuantos("sara", "estado in ('listo', 'enviado')")
              and uno(lu, "select count(*) from mensaje where persona_id = %s", (Q["sara"],)) == 0
              and uno(ni, "select count(*) from mensaje where persona_id = %s", (Q["sara"],)) == 0)
    uno_mio = uno(sa, "select id from mensaje limit 1")
    sa.execute("update mensaje set leido_en = now() where id = %s", (uno_mio,))
    leido = sa.rowcount == 1
    ok, msg = espera_error(sa, "update mensaje set texto = 'Felicitaciones' where id = %s", (uno_mio,), "permission denied")
    registrar("D16 · la persona marca el mensaje como leído y nada más", leido and ok, msg)
    registrar("D16 · la alerta de tarea vencida sigue en el tablero pero ya no manda correo: lo lleva el mensaje",
              uno(cur, "select canales::text from regla_alerta where tipo = 'tarea_vencida'") == "{plataforma}")
    for c in (lu, sa, ni):
        c.connection.close()


# =============================================================================
# 14 · Lo que la aplicación necesita para arrancar
# =============================================================================
def s14_aplicacion(uri, cur):
    seccion("14 · La aplicación: sesión, carpeta de Drive y enlace de usuarios · MVP")
    luisa = uno(cur, "select id from persona where correo = 'luisa@prueba.local'")
    _, lu = sesion(uri, USUARIOS["luisa"][0])
    _, ma = sesion(uri, USUARIOS["mariana"][0])
    _, cl = sesion(uri, USUARIOS["cliente"][0])
    _, nadie = sesion(uri, "00000000-0000-4000-8000-00000000dead")

    s = uno(lu, "select mi_sesion()")
    total = uno(cur, "select count(*) from proyecto")
    registrar("la aplicación sabe quién entró y qué puede hacer: dirección asigna y revisa en todo",
              s["persona_id"] == luisa and s["es_direccion"] is True and s["asigna"] is True
              and len(s["dirige"]) == total and len(s["revisa"]) == total, f"{s['nombre']} · {len(s['dirige'])} proyectos")
    m = uno(ma, "select mi_sesion()")
    registrar("una practicante no dirige ni revisa, y registra solo en sus proyectos",
              m["es_direccion"] is False and m["asigna"] is False and m["dirige"] == [] and m["revisa"] == []
              and 0 < len(m["registra"]) < total, f"registra en {len(m['registra'])}")
    registrar("quien entra sin ficha no recibe nada: la aplicación le dice que pida su acceso",
              uno(nadie, "select mi_sesion()") is None)
    registrar("sin sesión no hay ficha que devolver", uno(cur, "select mi_sesion()") is None)

    marg = uno(cur, "select id from proyecto where codigo = 'PRUEBA MARGARITAS'")
    ok, msg = espera_error(lu, "update proyecto set carpeta_drive = 'https://ejemplo.com/carpeta' where id = %s", (marg,),
                           "proyecto_carpeta_es_de_drive")
    registrar("la carpeta del proyecto tiene que ser un enlace de Drive", ok, msg)
    lu.execute("update proyecto set carpeta_drive = 'https://drive.google.com/drive/folders/1AbCdEfGh' where id = %s", (marg,))
    ma.execute("update proyecto set carpeta_drive = null where id = %s", (marg,))
    registrar("la carpeta la pone dirección; el equipo la ve pero no la cambia",
              ma.rowcount == 0 and uno(ma, "select carpeta_drive from proyecto where id = %s", (marg,))
              == "https://drive.google.com/drive/folders/1AbCdEfGh")

    # Se registró antes de tener ficha: al crearle la ficha queda enlazado, pero solo con el correo confirmado.
    cur.execute("""insert into auth.users (id, email, email_confirmed_at) values
                     ('00000000-0000-4000-8000-0000000014a1', 'llego.antes@prueba.local', now()),
                     ('00000000-0000-4000-8000-0000000014a2', 'sin.confirmar@prueba.local', null)""")
    lu.execute("""insert into persona (nombre, rol, es_interno, correo) values
                    ('PRUEBA Llegó Antes', 'practicante', true, 'Llego.Antes@prueba.local'),
                    ('PRUEBA Sin Confirmar', 'practicante', true, 'sin.confirmar@prueba.local')""")
    enlaces = dict(todas(cur, "select correo, auth_user_id::text from persona where correo ilike %s or correo ilike %s",
                         ("llego.antes@%", "sin.confirmar@%")))
    registrar("quien se registró antes de tener ficha queda enlazado cuando dirección la crea",
              enlaces.get("Llego.Antes@prueba.local") == "00000000-0000-4000-8000-0000000014a1", str(enlaces))
    registrar("pero nunca con un correo sin confirmar: nadie toma la ficha de otro",
              enlaces.get("sin.confirmar@prueba.local") is None)
    permisos = uno(cur, """select has_function_privilege('authenticated', 'public.mi_sesion()', 'execute')
                             and not has_function_privilege('anon', 'public.mi_sesion()', 'execute')
                             and not has_function_privilege('authenticated', 'private.vincular_persona_existente()', 'execute')""")
    registrar("la sesión solo la pide quien tiene sesión", permisos)
    for c in (lu, ma, cl, nadie):
        c.connection.close()


def s15_carga_semanal(uri, cur):
    seccion("15 · La carga del equipo por semana · D17")
    # Tres personas sin historia. El lunes 9 de noviembre de 2026 es el «hoy» de casi todas las pruebas;
    # el lunes 16 es festivo, así que esa semana tiene cuatro días hábiles.
    gente = {"gala": ("00000000-0000-4000-8000-0000000015a1", "practicante", 40),
             "hugo": ("00000000-0000-4000-8000-0000000015a2", "practicante", 20),
             "irene": ("00000000-0000-4000-8000-0000000015a3", "director_proyecto", 0)}
    Q = {}
    for nombre, (uid, rol, horas) in gente.items():
        cur.execute("insert into auth.users (id, email, email_confirmed_at) values (%s, %s, now())", (uid, f"{nombre}@prueba.local"))
        Q[nombre] = uno(cur, """insert into persona (nombre, rol, es_interno, auth_user_id, correo, horas_semana)
                                values (%s, %s, true, %s, %s, %s) returning id""",
                        (f"PRUEBA {nombre.capitalize()}", rol, uid, f"{nombre}@prueba.local", horas))
    Q["luisa"] = uno(cur, "select id from persona where correo = 'luisa@prueba.local'")
    _, lu = sesion(uri, USUARIOS["luisa"][0])
    _, ga = sesion(uri, gente["gala"][0])
    _, ir = sesion(uri, gente["irene"][0])
    _, an = sesion(uri, None, "anon")

    plantilla = uno(cur, "select id from plantilla_proyecto where nombre = 'Diseño'")
    proy = uno(lu, """select abrir_proyecto('PRUEBA CARGA', 'Casa Carga', %s, 'diseno_arquitectonico'::unidad_negocio,
                                            '{"insight": 8}'::jsonb, %s::jsonb, null, '{licencia}'::fase_proyecto[])""",
               (plantilla, json.dumps([{"persona_id": Q["gala"], "papel": "produce"}, {"persona_id": Q["hugo"], "papel": "produce"}])))
    # Irene dirige otro proyecto: no ve las tareas de este, pero sí cuánto pesan.
    otro = uno(lu, """select abrir_proyecto('PRUEBA CARGA 2', 'Casa Carga Dos', %s, 'diseno_arquitectonico'::unidad_negocio,
                                            '{"insight": 8}'::jsonb, %s::jsonb, null, '{licencia}'::fase_proyecto[])""",
               (plantilla, json.dumps([{"persona_id": Q["irene"], "papel": "dirige"}])))

    def tarea(titulo, inicio, entrega, dias, quien="gala", estado="asignada"):
        tid = uno(cur, """insert into tarea_diseno (proyecto_id, titulo, asignada_a, asignada_por, fecha_inicio, fecha_compromiso, dias_estimados)
                          values (%s, %s, %s, %s, %s, %s, %s) returning id""", (proy, titulo, Q[quien], Q["luisa"], inicio, entrega, dias))
        if estado != "asignada":
            cur.execute("update tarea_diseno set estado = 'en_revision' where id = %s", (tid,))
        if estado == "terminada":
            cur.execute("insert into revision_diseno (tarea_id, revisor_id, resultado) values (%s, %s, 'aprobada')", (tid, Q["luisa"]))
        return tid

    t1 = tarea("Planta general", "2026-11-09", "2026-11-13", 5)
    tarea("Cortes y fachadas", "2026-11-16", "2026-11-27", 4.5)
    tarea("Cuadro de áreas", "2026-10-28", "2026-11-05", 2)
    tarea("Detalle de baños", "2026-11-30", "2026-12-02", None)
    tarea("Render de sala", "2026-11-09", "2026-11-20", 8, estado="en_revision")
    tarea("Levantamiento", "2026-11-09", "2026-11-20", 8, estado="terminada")
    tarea("Memoria descriptiva", "2026-11-10", "2026-11-12", 1.5, quien="hugo")
    tarea("Entrega en domingo", "2026-11-22", "2026-11-22", 1, quien="hugo")

    def carga(c, desde="2026-11-09", semanas=4):
        return {(r[0], str(r[1])): r[2:] for r in todas(c, """select nombre, semana, dias_habiles, dias_ocupados, tareas, sin_estimar, vencidas
                                                              from carga_semanal(%s, %s)""", (semanas, desde))}
    L = carga(lu)
    g = lambda s, d=L: tuple(float(x) for x in d[("PRUEBA Gala", s)])
    registrar("D17 · la semana tiene los días hábiles que tiene: la del festivo, cuatro",
              [g(s)[0] for s in ("2026-11-09", "2026-11-16", "2026-11-23", "2026-11-30")] == [5, 4, 5, 5], str([g(s)[0] for s in ("2026-11-09", "2026-11-16")]))
    registrar("D17 · lo vencido cae entero en el primer día: Gala está pasada esta semana",
              g("2026-11-09") == (5, 7, 2, 0, 1), str(g("2026-11-09")))
    registrar("D17 · el trabajo se reparte parejo entre los días hábiles de la tarea, sin contar el festivo",
              g("2026-11-16") == (4, 2, 1, 0, 0) and g("2026-11-23") == (5, 2.5, 1, 0, 0), f"{g('2026-11-16')} {g('2026-11-23')}")
    registrar("D17 · una tarea sin estimar se ve, pero no suma días",
              g("2026-11-30") == (5, 0, 1, 1, 0), str(g("2026-11-30")))
    h = lambda s: tuple(float(x) for x in L[("PRUEBA Hugo", s)])
    registrar("D17 · quien trabaja media jornada tiene la mitad de los días",
              h("2026-11-09") == (2.5, 1.5, 1, 0, 0) and h("2026-11-16")[0] == 2, str(h("2026-11-09")))
    registrar("D17 · lo que se entrega un domingo pesa en el hábil siguiente",
              h("2026-11-16")[1:3] == (0, 0) and h("2026-11-23")[1:3] == (1, 1), f"{h('2026-11-16')} {h('2026-11-23')}")
    registrar("D17 · sin horas registradas se asume jornada completa",
              float(L[("PRUEBA Irene", "2026-11-09")][0]) == 5 and float(L[("PRUEBA Irene", "2026-11-09")][1]) == 0)

    mie = carga(lu, "2026-11-11")
    registrar("D17 · a mitad de semana solo cuenta lo que queda de ella",
              g("2026-11-09", mie)[:2] == (3, 5), str(g("2026-11-09", mie)))
    sab = carga(lu, "2026-11-14", 2)
    registrar("D17 · en fin de semana la primera semana es la que viene",
              sorted({k[1] for k in sab}) == ["2026-11-16", "2026-11-23"], str(sorted({k[1] for k in sab})))

    G = carga(ga)
    registrar("D17 · quien no asigna ve solo su fila", {k[0] for k in G} == {"PRUEBA Gala"} and len(G) == 4, str({k[0] for k in G}))
    I = carga(ir)
    visibles = uno(ir, "select count(*) from tarea_diseno where proyecto_id = %s", (proy,))
    registrar("D17 · quien dirige un proyecto ve cuánto pesa lo de todos, sin ver las tareas ajenas",
              visibles == 0 and tuple(float(x) for x in I[("PRUEBA Gala", "2026-11-09")]) == (5, 7, 2, 0, 1), f"ve {visibles} tareas ajenas")
    registrar("D17 · sin sesión no hay carga que mostrar", todas(cur, "select * from carga_semanal(4, '2026-11-09')") == [])
    ok, msg = espera_error(an, "select * from carga_semanal()", None, "permission denied for function carga_semanal")
    registrar("D17 · la carga solo la pide quien tiene sesión", ok, msg)

    ok, msg = espera_error(lu, "update tarea_diseno set dias_estimados = 0 where id = %s", (t1,), "tarea_estimado_sano")
    registrar("D17 · el estimado es un número de días que tenga sentido", ok, msg)
    ok, msg = espera_error(ga, "update tarea_diseno set dias_estimados = 1 where id = %s", (t1,), "D10")
    registrar("D17 · el estimado lo pone quien asigna: quien hace la tarea no se lo rebaja", ok, msg)
    lu.execute("update tarea_diseno set dias_estimados = 3, asignada_a = %s where id = %s", (Q["hugo"], t1))
    L2 = carga(lu)
    registrar("D17 · al pasarle la tarea a otra persona, la carga se va con ella",
              float(L2[("PRUEBA Gala", "2026-11-09")][1]) == 2 and float(L2[("PRUEBA Hugo", "2026-11-09")][1]) == 4.5,
              f"Gala {L2[('PRUEBA Gala', '2026-11-09')][1]} · Hugo {L2[('PRUEBA Hugo', '2026-11-09')][1]}")

    # El centro de mando lee la fecha de entrega de cada fase; la pone quien dirige, desde la ficha del proyecto.
    fase = uno(cur, "select id from proyecto_fase where proyecto_id = %s and fase = 'insight'", (proy,))
    lu.execute("update proyecto_fase set fecha_compromiso = '2026-11-20' where id = %s", (fase,))
    ga.execute("update proyecto_fase set fecha_compromiso = '2027-01-15' where id = %s", (fase,))
    registrar("la fecha de entrega de una fase la pone quien dirige; quien produce la ve pero no la mueve",
              lu.rowcount == 1 and ga.rowcount == 0
              and str(uno(ga, "select fecha_compromiso from proyecto_fase where id = %s", (fase,))) == "2026-11-20")
    for c in (lu, ga, ir, an):
        c.connection.close()


def s16_flujo_por_fase(uri, cur):
    seccion("16 · El flujo de cada tipo de proyecto: plazo y responsable por fase · D18")
    Q = {n: uno(cur, "select id from persona where correo = %s", (f"{n}@prueba.local",)) for n in ("luisa", "gala", "hugo", "irene", "mariana")}
    _, lu = sesion(uri, USUARIOS["luisa"][0])
    _, ma = sesion(uri, USUARIOS["mariana"][0])
    pl = dict(todas(cur, "select nombre, id from plantilla_proyecto"))
    pf = lambda plantilla, fase: uno(cur, "select id from plantilla_fase where plantilla_id = %s and fase = %s", (pl[plantilla], fase))

    lu.execute("update plantilla_fase set dias_habiles_plazo = 10 where id = %s", (pf("Diseño", "insight"),))
    ma.execute("update plantilla_fase set dias_habiles_plazo = 99 where id = %s", (pf("Diseño", "insight"),))
    registrar("D18 · el plazo de una fase lo define dirección en la plantilla; el equipo lo lee",
              lu.rowcount == 1 and ma.rowcount == 0
              and uno(ma, "select dias_habiles_plazo from plantilla_fase where id = %s", (pf("Diseño", "insight"),)) == 10)
    ok, msg = espera_error(lu, "update plantilla_fase set dias_habiles_plazo = 0 where id = %s", (pf("Diseño", "insight"),), "plantilla_fase_plazo_sano")
    registrar("D18 · el plazo es un número de días que tenga sentido", ok, msg)
    ok, msg = espera_error(lu, "update plantilla_fase set responsable_papel = 'observa' where id = %s", (pf("Diseño", "insight"),),
                           "plantilla_fase_responde_quien_trabaja")
    registrar("D18 · por una fase no responde quien solo observa", ok, msg)

    abrir = """select abrir_proyecto(%s, %s, %s, %s::unidad_negocio, '{}'::jsonb, %s::jsonb, null, %s::fase_proyecto[])"""
    equipo = lambda *pares: json.dumps([{"persona_id": Q[n], "papel": papel} for n, papel in pares])
    proy = uno(lu, abrir, ("PRUEBA FLUJO", "Casa Flujo", pl["Diseño"], "diseno_arquitectonico",
                           equipo(("irene", "dirige"), ("gala", "produce"), ("hugo", "produce")), "{licencia}"))
    fase = lambda p, f: uno(cur, """select id, estado::text, dias_habiles_plazo, fecha_compromiso, responsable_id
                                    from proyecto_fase where proyecto_id = %s and fase = %s""", (p, f))
    ins = fase(proy, "insight")
    registrar("D18 · la fase nace con el plazo de su plantilla, y sin fecha ni responsable mientras no se abra",
              ins[1:] == ("pendiente", 10, None, None), str(ins[1:]))
    lu.execute("update proyecto_fase set estado = 'en_curso' where id = %s", (ins[0],))
    ins = fase(proy, "insight")
    espera = uno(cur, "select private.sumar_habiles(private.hoy(), 10)")
    registrar("D18 · al abrirla recibe su fecha de entrega: hoy más el plazo, en días hábiles", ins[3] == espera, f"{ins[3]} · se esperaba {espera}")
    registrar("D18 · y su responsable: quien dirige el proyecto", ins[4] == Q["irene"])

    # Cambiar la plantilla después no mueve lo que ya está andando.
    lu.execute("update plantilla_fase set dias_habiles_plazo = 30 where id = %s", (pf("Diseño", "insight"),))
    registrar("D18 · cambiar la plantilla no mueve los proyectos que ya están andando",
              fase(proy, "insight")[2:4] == (10, espera), str(fase(proy, "insight")[2:4]))

    # Lo que se puso a mano no se pisa.
    otro = uno(lu, abrir, ("PRUEBA FLUJO 2", "Casa Flujo Dos", pl["Diseño"], "diseno_arquitectonico",
                           equipo(("irene", "dirige"), ("gala", "produce")), "{licencia}"))
    lu.execute("update proyecto_fase set fecha_compromiso = '2027-03-19', responsable_id = %s where id = %s", (Q["gala"], fase(otro, "insight")[0]))
    lu.execute("update proyecto_fase set estado = 'en_curso' where id = %s", (fase(otro, "insight")[0],))
    registrar("D18 · una fecha y un responsable puestos a mano no se pisan al abrir la fase",
              str(fase(otro, "insight")[3]) == "2027-03-19" and fase(otro, "insight")[4] == Q["gala"], str(fase(otro, "insight")[3:]))

    # El papel que responde lo dice la plantilla; con dos personas en ese papel no se adivina.
    lu.execute("update plantilla_fase set responsable_papel = 'revisa', dias_habiles_plazo = null where id = %s", (pf("Peritaje", "levantamiento"),))
    per = uno(lu, abrir, ("PRUEBA FLUJO 3", "Peritaje Flujo", pl["Peritaje"], "peritaje",
                          equipo(("irene", "dirige"), ("gala", "revisa"), ("hugo", "produce")), "{}"))
    lu.execute("update proyecto_fase set estado = 'en_curso' where id = %s", (fase(per, "levantamiento")[0],))
    lev = fase(per, "levantamiento")
    registrar("D18 · si la plantilla dice que responde quien revisa, responde quien revisa", lev[4] == Q["gala"])
    registrar("D18 · una fase sin plazo se abre sin fecha: la pone dirección", lev[2] is None and lev[3] is None, str(lev[2:4]))
    dos = uno(lu, abrir, ("PRUEBA FLUJO 4", "Peritaje Flujo Dos", pl["Peritaje"], "peritaje",
                          equipo(("irene", "revisa"), ("gala", "revisa")), "{}"))
    lu.execute("update proyecto_fase set estado = 'en_curso' where id = %s", (fase(dos, "levantamiento")[0],))
    registrar("D18 · con dos personas en el mismo papel el sistema no adivina: escoge dirección",
              fase(dos, "levantamiento")[4] is None)

    ok, msg = espera_error(lu, "update proyecto_fase set responsable_id = %s where id = %s", (Q["mariana"], ins[0]), "D18")
    registrar("D18 · el responsable de una fase hace parte del equipo del proyecto", ok, msg)
    ma.execute("update proyecto_fase set responsable_id = %s where id = %s", (Q["hugo"], ins[0]))
    lu.execute("update proyecto_fase set responsable_id = %s where id = %s", (Q["hugo"], ins[0]))
    registrar("D18 · el responsable lo cambia dirección", ma.rowcount == 0 and lu.rowcount == 1 and fase(proy, "insight")[4] == Q["hugo"])
    registrar("D18 · la regla que arma el flujo no la llama nadie desde la aplicación",
              uno(cur, "select not has_function_privilege('authenticated', 'private.flujo_de_fase()', 'execute')"))
    # La plantilla vuelve a quedar como la deja la semilla.
    cur.execute("update plantilla_fase set dias_habiles_plazo = null, responsable_papel = 'dirige'")
    for c in (lu, ma):
        c.connection.close()


def s17_tareas_tipicas(uri, cur):
    seccion("17 · Las tareas típicas de cada fase y el aviso de cierre · D19")
    Q = {n: uno(cur, "select id from persona where correo = %s", (f"{n}@prueba.local",)) for n in ("luisa", "gala", "hugo", "irene", "mariana")}
    _, lu = sesion(uri, USUARIOS["luisa"][0])
    _, ga = sesion(uri, "00000000-0000-4000-8000-0000000015a1")
    _, ma = sesion(uri, USUARIOS["mariana"][0])
    diseno = uno(cur, "select id from plantilla_proyecto where nombre = 'Diseño'")
    pf = uno(cur, "select id from plantilla_fase where plantilla_id = %s and fase = 'insight'", (diseno,))

    # Dirección define las tareas típicas de la fase; el equipo no.
    tipica = """insert into plantilla_tarea (plantilla_fase_id, orden, titulo, proposito, por_espacio, dias_plazo, dias_estimados, depende_de)
                values (%s, %s, %s, %s, %s, %s, %s, %s) returning id"""
    medir = uno(lu, tipica, (pf, 10, "PRUEBA Medir", "Sin las medidas nadie puede dibujar el espacio", True, 3, 2, None))
    plano = uno(lu, tipica, (pf, 20, "PRUEBA Plano base", "Sobre este plano se montan todas las propuestas", True, 6, None, medir))
    ok, msg = espera_error(ma, tipica, (pf, 30, "PRUEBA Colada", "Una tarea que no debería poder crear", False, 1, 1, None), "row-level security")
    registrar("D19 · las tareas típicas de una fase las define dirección", ok, msg)
    ok, msg = espera_error(lu, "update plantilla_tarea set dias_estimados = 0 where id = %s", (medir,), "plantilla_tarea_estimado_sano")
    registrar("D19 · el trabajo típico es un número de días que tenga sentido", ok, msg)

    proy = uno(lu, """select abrir_proyecto('PRUEBA TIPICAS', 'Casa Típicas', %s, 'diseno_arquitectonico'::unidad_negocio, '{}'::jsonb, %s::jsonb,
                                            null, '{licencia}'::fase_proyecto[])""",
               (diseno, json.dumps([{"persona_id": Q["gala"], "papel": "produce"}, {"persona_id": Q["hugo"], "papel": "produce"}])))
    fase = uno(cur, "select id from proyecto_fase where proyecto_id = %s and fase = 'insight'", (proy,))
    lu.execute("update proyecto_fase set estado = 'en_curso' where id = %s", (fase,))

    prop = todas(lu, "select plantilla_tarea_id, titulo, espacio, dias_estimados, fecha_sugerida, por_espacio from tareas_tipicas(%s, %s)", (fase, ["Cocina", "Sala"]))
    registrar("D19 · la propuesta trae el trabajo que suele pedir cada tarea, espacio por espacio",
              [(p[1], None if p[3] is None else float(p[3])) for p in prop]
              == [("PRUEBA Medir · Cocina", 2.0), ("PRUEBA Medir · Sala", 2.0), ("PRUEBA Plano base · Cocina", None), ("PRUEBA Plano base · Sala", None)],
              str([(p[1], p[3]) for p in prop]))

    envio = [{"plantilla_tarea_id": str(p[0]), "espacio": p[2], "asignada_a": Q["gala"], "fecha_inicio": "2026-11-09", "fecha_compromiso": "2026-11-13"} for p in prop]
    envio[1]["dias_estimados"] = 4          # quien dirige lo cambió en pantalla
    envio[2]["dias_estimados"] = 1.5
    del envio[3]["fecha_inicio"]
    semana = lambda: float(uno(lu, "select dias_ocupados from carga_semanal(1, '2026-11-09') where nombre = 'PRUEBA Gala'"))
    antes = semana()
    n = uno(lu, "select crear_tareas(%s, %s::jsonb)", (fase, json.dumps(envio)))
    creadas = {r[0]: r[1:] for r in todas(cur, """select titulo, dias_estimados, fecha_inicio, bloqueada_por is not null
                                                  from tarea_diseno where fase_id = %s""", (fase,))}
    registrar("D19 · las tareas nacen con su inicio y su trabajo: el de la plantilla, o el que se cambió en pantalla",
              n == 4 and float(creadas["PRUEBA Medir · Cocina"][0]) == 2 and float(creadas["PRUEBA Medir · Sala"][0]) == 4
              and float(creadas["PRUEBA Plano base · Cocina"][0]) == 1.5 and creadas["PRUEBA Plano base · Sala"][0] is None
              and str(creadas["PRUEBA Medir · Cocina"][1]) == "2026-11-09" and creadas["PRUEBA Plano base · Sala"][1] is None,
              str({k: (v[0], str(v[1])) for k, v in creadas.items()}))
    registrar("D19 · y siguen enlazadas: el plano espera a la medición de su mismo espacio",
              creadas["PRUEBA Plano base · Cocina"][2] and creadas["PRUEBA Plano base · Sala"][2] and not creadas["PRUEBA Medir · Sala"][2])
    registrar("D19 · la carga del equipo las cuenta desde que se crean", round(semana() - antes, 1) == 7.5, f"{antes} → {semana()} días")
    ok, msg = espera_error(ga, "select crear_tareas(%s, %s::jsonb)",
                           (fase, json.dumps([{"titulo": "Para otro", "asignada_a": Q["hugo"], "fecha_compromiso": "2026-11-13"}])), "row-level security")
    registrar("D19 · repartir las tareas de una fase sigue siendo de quien dirige", ok, msg)

    avance = lambda c=cur: uno(c, "select tareas, terminadas, trabajo_terminado from v_fase_avance where fase_id = %s", (fase,))
    registrar("D19 · una fase con trabajo abierto no ha terminado", avance() == (4, 0, False), str(avance()))
    ids = [r[0] for r in todas(cur, "select id from tarea_diseno where fase_id = %s order by bloqueada_por nulls first", (fase,))]
    for k, tid in enumerate(ids):
        cur.execute("update tarea_diseno set estado = 'en_revision' where id = %s", (tid,))
        cur.execute("insert into revision_diseno (tarea_id, revisor_id, resultado) values (%s, %s, 'aprobada')", (tid, Q["luisa"]))
        if k == 2:
            registrar("D19 · con una sola tarea abierta todavía no", avance() == (4, 3, False), str(avance()))
    registrar("D19 · cuando la última queda aprobada, la fase terminó su trabajo", avance() == (4, 4, True), str(avance()))
    registrar("D19 · eso no la cierra: el cierre sigue pidiendo lo que pide la compuerta",
              uno(cur, "select estado::text from proyecto_fase where id = %s", (fase,)) == "en_curso")
    otra = uno(cur, "select id from proyecto_fase where proyecto_id = %s and fase = 'anteproyecto'", (proy,))
    # Una fase que no se ha abierto no termina, aunque su única tarea ya esté aprobada.
    suelta = uno(cur, """insert into tarea_diseno (proyecto_id, fase_id, titulo, asignada_a, asignada_por, fecha_compromiso)
                         values (%s, %s, 'PRUEBA Adelanto', %s, %s, '2026-11-20') returning id""", (proy, otra, Q["gala"], Q["luisa"]))
    cur.execute("update tarea_diseno set estado = 'en_revision' where id = %s", (suelta,))
    cur.execute("insert into revision_diseno (tarea_id, revisor_id, resultado) values (%s, %s, 'aprobada')", (suelta, Q["luisa"]))
    registrar("D19 · una fase que no se ha abierto no dice que terminó, aunque su tarea esté aprobada",
              uno(cur, "select tareas, terminadas, trabajo_terminado from v_fase_avance where fase_id = %s", (otra,)) == (1, 1, False))
    vacio = uno(lu, """select abrir_proyecto('PRUEBA TIPICAS 2', 'Casa Sin Tareas', %s, 'diseno_arquitectonico'::unidad_negocio, '{}'::jsonb, '[]'::jsonb,
                                             null, '{licencia}'::fase_proyecto[])""", (diseno,))
    lu.execute("update proyecto_fase set estado = 'en_curso' where proyecto_id = %s and fase = 'insight'", (vacio,))
    registrar("D19 · una fase abierta que todavía no tiene tareas tampoco",
              uno(cur, "select f.estado::text, a.tareas, a.trabajo_terminado from v_fase_avance a join proyecto_fase f on f.id = a.fase_id "
                       "where a.proyecto_id = %s and a.fase = 'insight'", (vacio,)) == ("en_curso", 0, False))
    registrar("D19 · el avance lo ve quien hace parte del proyecto, y nadie más",
              avance(ga) == (4, 4, True) and avance(ma) is None)
    registrar("D19 · sin sesión no se lee el avance ni se proponen tareas",
              uno(cur, """select not has_table_privilege('anon', 'public.v_fase_avance', 'select')
                             and not has_function_privilege('anon', 'public.tareas_tipicas(uuid, text[])', 'execute')
                             and has_function_privilege('authenticated', 'public.tareas_tipicas(uuid, text[])', 'execute')"""))
    # Las típicas de la prueba no se quedan en la plantilla.
    lu.execute("update plantilla_tarea set activa = false where id in (%s, %s)", (plano, medir))
    registrar("D19 · una tarea típica no se borra: se desactiva y deja de proponerse",
              lu.rowcount == 2 and todas(lu, "select 1 from tareas_tipicas(%s)", (fase,)) == [])
    for c in (lu, ga, ma):
        c.connection.close()


def s18_cierre_de_fase(uri, cur):
    seccion("18 · El cierre de una fase, con sus datos obligatorios · D20")
    Q = {n: uno(cur, "select id from persona where correo = %s", (f"{n}@prueba.local",)) for n in ("luisa", "gala", "hugo", "mariana")}
    _, lu = sesion(uri, USUARIOS["luisa"][0])
    _, ga = sesion(uri, "00000000-0000-4000-8000-0000000015a1")
    _, ma = sesion(uri, USUARIOS["mariana"][0])
    pl = dict(todas(cur, "select nombre, id from plantilla_proyecto"))
    pf = lambda plantilla, fase: uno(cur, "select id from plantilla_fase where plantilla_id = %s and fase = %s", (pl[plantilla], fase))
    abrir = "select abrir_proyecto(%s, %s, %s, %s::unidad_negocio, '{}'::jsonb, %s::jsonb, null, %s::fase_proyecto[])"
    equipo = json.dumps([{"persona_id": Q["gala"], "papel": "produce"}, {"persona_id": Q["hugo"], "papel": "produce"}])
    fase_de = lambda p, f: uno(cur, "select id from proyecto_fase where proyecto_id = %s and fase = %s", (p, f))

    # Un proyecto que abre su fase ANTES de que exista la lista de su tipo.
    viejo = uno(lu, abrir, ("PRUEBA CIERRE 0", "Casa Anterior", pl["Peritaje"], "peritaje", equipo, "{}"))
    lev0 = fase_de(viejo, "levantamiento")
    lu.execute("update proyecto_fase set estado = 'en_curso' where id = %s", (lev0,))
    sin_lista = dict((r[0], r[1:]) for r in todas(lu, "select que, listo, bloquea, detalle from falta_para_cerrar(%s)", (lev0,)))
    registrar("D20 · sin lista de chequeo la fase lo dice, y dice quién la define",
              sin_lista["chequeo"][0] is False and "dirección la define en el flujo" in sin_lista["chequeo"][2], sin_lista["chequeo"][2])

    punto = "select punto_de_cierre(%s, %s, %s, %s, %s)"
    ok, msg = espera_error(ma, punto, (pf("Peritaje", "levantamiento"), "Una que no debería entrar", "casilla", None, True), "row-level security")
    registrar("D20 · los puntos de la lista de una fase los define dirección", ok, msg)
    P = {}
    for clave, texto, tipo, opciones, obligatorio in (
            ("casilla", "PRUEBA Fotos de todos los daños", "casilla", None, True),
            ("opcion", "PRUEBA Causa del daño", "opcion", ["Agua", "Fuego", "Golpe"], True),
            ("numero", "PRUEBA Área afectada en metros", "numero", None, True),
            ("fecha", "PRUEBA Fecha de la visita", "fecha", None, True),
            ("enlace", "PRUEBA Carpeta con el registro", "enlace", None, True),
            ("extra", "PRUEBA Croquis a mano", "casilla", None, False)):
        P[clave] = uno(lu, punto, (pf("Peritaje", "levantamiento"), texto, tipo, opciones, obligatorio))
    lista = uno(cur, "select lista_id from lista_chequeo_item where id = %s", (P["casilla"],))
    registrar("D20 · la lista se crea sola con el primer punto y queda ligada a su tipo de proyecto",
              uno(cur, "select count(*) from lista_chequeo_item where lista_id = %s", (lista,)) == 6
              and uno(cur, "select plantilla_id, fase::text, nombre from lista_chequeo where id = %s", (lista,)) == (pl["Peritaje"], "levantamiento", "Peritaje · levantamiento"))
    ok, msg = espera_error(lu, punto, (pf("Peritaje", "levantamiento"), "ab", "casilla", None, True), "necesita decir qué se verifica")
    registrar("D20 · un punto tiene que decir qué se verifica", ok, msg)
    ok, msg = espera_error(lu, punto, (pf("Peritaje", "levantamiento"), "PRUEBA Sin opciones", "opcion", ["Una sola"], True), "punto_opcion_con_opciones")
    registrar("D20 · un punto de opciones trae al menos dos", ok, msg)
    ok, msg = espera_error(lu, punto, (pf("Peritaje", "levantamiento"), "PRUEBA Tipo raro", "dibujo", None, True), "punto_tipo_conocido")
    registrar("D20 · el tipo de dato es uno de los que el sistema conoce", ok, msg)

    # La fase que ya estaba abierta recibe su hoja al pedirla; la que se abre después, al abrirse.
    ok, msg = espera_error(ma, "select abrir_chequeo(%s)", (lev0,), "usted no registra en ese proyecto")
    registrar("D20 · la hoja de una fase la abre quien trabaja en el proyecto", ok, msg)
    hoja0 = uno(ga, "select abrir_chequeo(%s)", (lev0,))
    registrar("D20 · una fase abierta antes de existir la lista recibe su hoja al pedirla, y una sola",
              hoja0 is not None and uno(ga, "select abrir_chequeo(%s)", (lev0,)) == hoja0
              and uno(cur, "select lista_id from chequeo where id = %s", (hoja0,)) == lista)
    nuevo = uno(lu, abrir, ("PRUEBA CIERRE 1", "Peritaje Cierre", pl["Peritaje"], "peritaje", equipo, "{}"))
    lev = fase_de(nuevo, "levantamiento")
    lu.execute("update proyecto_fase set estado = 'en_curso' where id = %s", (lev,))
    hoja = uno(cur, "select id from chequeo where fase_id = %s and lista_id = %s", (lev, lista))
    registrar("D20 · una fase que se abre después queda de una vez con la lista de su tipo de proyecto", hoja is not None)
    cons = uno(lu, abrir, ("PRUEBA CIERRE 2", "Consultoría Cierre", pl["Consultoría"], "consultoria", equipo, "{}"))
    lev_c = fase_de(cons, "levantamiento")
    lu.execute("update proyecto_fase set estado = 'en_curso' where id = %s", (lev_c,))
    registrar("D20 · la lista de un tipo de proyecto no se le pega a otro que tenga una fase del mismo nombre",
              uno(cur, "select count(*) from chequeo where fase_id = %s and lista_id = %s", (lev_c, lista)) == 0)

    # Los datos: se cumplen con un dato válido, no con una marca.
    resp = """insert into chequeo_respuesta (chequeo_id, item_id, cumple, valor, verificado_por) values (%s, %s, %s, %s, %s)
              on conflict (chequeo_id, item_id) do update set cumple = excluded.cumple, valor = excluded.valor"""
    for clave, valor, fragmento, nombre in (
            ("numero", None, "pide un dato", "un punto que pide un dato no se cumple con solo marcarlo"),
            ("numero", "bastante", "pide un número", "donde se pide un número no entra una palabra"),
            ("opcion", "Viento", "pide una de sus opciones", "donde se pide escoger, solo valen las opciones del punto"),
            ("fecha", "2026-13-45", "pide una fecha", "donde se pide una fecha no entra una que no existe"),
            ("enlace", "en el Drive", "pide un enlace", "donde se pide un enlace no entra una frase")):
        ok, msg = espera_error(ga, resp, (hoja, P[clave], True, valor, Q["gala"]), fragmento)
        registrar(f"D20 · {nombre}", ok, msg)

    falta = lambda c=lu, f=lev: dict((r[0], r[1:]) for r in todas(c, "select que, listo, bloquea, detalle from falta_para_cerrar(%s)", (f,)))
    cerrar = "update proyecto_fase set estado = 'cerrada' where id = %s"
    for clave, valor in (("casilla", None), ("opcion", "Agua"), ("numero", "12,5"), ("fecha", "2026-11-10")):
        ga.execute(resp, (hoja, P[clave], True, valor, Q["gala"]))
    registrar("D20 · la cuenta de lo que falta va punto por punto, sin contar los que no son obligatorios",
              falta()["chequeo"] == (False, True, "Van 4 de 5 puntos obligatorios"), falta()["chequeo"][2])
    ok, msg = espera_error(lu, cerrar, (lev,), "lista de chequeo")
    registrar("D20 · con un dato obligatorio sin llenar la fase no se cierra", ok, msg)
    ga.execute(resp, (hoja, P["enlace"], True, "https://drive.google.com/drive/folders/1AbCd", Q["gala"]))
    f1 = falta()
    registrar("D20 · con todos los datos, la lista queda cumplida y lo que sigue faltando es la dedicación",
              f1["chequeo"] == (True, True, "Los 5 puntos obligatorios están cumplidos")
              and f1["dedicacion"] == (False, True, "Nadie ha registrado tiempo en esta fase"), f"{f1['chequeo'][2]} · {f1['dedicacion'][2]}")
    ok, msg = espera_error(lu, cerrar, (lev,), "no tiene dedicación registrada")
    registrar("D20 · y la base dice lo mismo: sin dedicación no cierra", ok, msg)
    ga.execute("""insert into dedicacion (persona_id, fecha, bloque, tipo, proyecto_id, fase_id)
                  values (%s, private.hoy(), 'manana', 'proyecto', %s, %s)""", (Q["gala"], nuevo, lev))
    cur.execute("""insert into tarea_diseno (proyecto_id, fase_id, titulo, asignada_a, asignada_por, fecha_compromiso)
                   values (%s, %s, 'PRUEBA Informe de daños', %s, %s, private.hoy() + 5)""", (nuevo, lev, Q["gala"], Q["luisa"]))
    f2 = falta()
    registrar("D20 · una tarea abierta se avisa, pero no es lo que impide el cierre",
              f2["dedicacion"][0] is True and f2["tareas"] == (False, False, "Queda una tarea abierta")
              and all(v[0] for k, v in f2.items() if v[1]), str({k: v[2] for k, v in f2.items()}))
    registrar("D20 · quien produce ve lo mismo que dirección, y quien no es del proyecto no ve nada",
              falta(ga) == f2 and espera_error(ma, "select * from falta_para_cerrar(%s)", (lev,), "no la puede ver")[0])
    ga.execute(cerrar, (lev,))
    registrar("D20 · aunque todo esté listo, la fase la cierra dirección", ga.rowcount == 0)
    lu.execute(cerrar, (lev,))
    registrar("D20 · cuando la cuenta dice que no falta nada de lo que bloquea, la fase cierra",
              lu.rowcount == 1 and uno(cur, "select estado::text, cerrada_por from proyecto_fase where id = %s", (lev,)) == ("cerrada", Q["luisa"]))

    # Quitar un punto: deja de contar en las hojas que ya estaban abiertas.
    ga.execute(resp, (hoja0, P["casilla"], True, None, Q["gala"]))
    antes = falta(lu, lev0)["chequeo"][2]
    lu.execute("update lista_chequeo_item set activo = false where id in (%s, %s, %s, %s)", (P["opcion"], P["numero"], P["fecha"], P["enlace"]))
    registrar("D20 · un punto que dirección quita deja de pedirse", antes == "Van 1 de 5 puntos obligatorios"
              and falta(lu, lev0)["chequeo"] == (True, True, "El punto obligatorio está cumplido"), f"{antes} → {falta(lu, lev0)['chequeo'][2]}")

    # El registro del día, tal como lo guarda la aplicación: se escoge, y si hubo un error se vuelve a escoger.
    dia = """insert into dedicacion (persona_id, fecha, bloque, tipo, proyecto_id, fase_id) values (%s, private.hoy(), 'tarde', %s, %s, %s)
             on conflict (persona_id, fecha, bloque) do update set tipo = excluded.tipo, proyecto_id = excluded.proyecto_id, fase_id = excluded.fase_id"""
    ga.execute(dia, (Q["gala"], "proyecto", viejo, lev0))
    ga.execute(dia, (Q["gala"], "estructura", None, None))
    registrar("D2 · el día se registra escogiendo, y lo escogido se puede corregir",
              uno(cur, "select tipo, proyecto_id, horas from dedicacion where persona_id = %s and fecha = private.hoy() and bloque = 'tarde'", (Q["gala"],))
              == ("estructura", None, uno(cur, "select horas_por_bloque from parametro")))
    ok, msg = espera_error(ga, dia.replace("%s, private.hoy()", "%s, private.hoy() + 1"), (Q["gala"], "estructura", None, None), "no se registra por adelantado")
    registrar("D2 · y no se registra un día que no ha pasado", ok, msg)
    ok, msg = espera_error(ma, dia, (Q["gala"], "estructura", None, None), "row-level security")
    registrar("D2 · nadie registra el día de otra persona", ok, msg)

    ante = fase_de(uno(cur, "select id from proyecto where codigo = 'PRUEBA FLUJO'"), "anteproyecto")
    registrar("D20 · donde el cierre pide al cliente, la cuenta lo dice",
              falta(lu, ante)["cliente"] == (False, True, "Falta la aprobación del cliente"))
    registrar("D20 · sin sesión no se pregunta qué falta ni se abren hojas",
              uno(cur, """select not has_function_privilege('anon', 'public.falta_para_cerrar(uuid)', 'execute')
                             and not has_function_privilege('anon', 'public.abrir_chequeo(uuid)', 'execute')
                             and not has_function_privilege('anon', 'public.punto_de_cierre(uuid, text, text, text[], boolean)', 'execute')
                             and not has_function_privilege('authenticated', 'private.validar_dato_respuesta()', 'execute')"""))
    for c in (lu, ga, ma):
        c.connection.close()


# =============================================================================
# 19 · El embudo de ventas
# =============================================================================
def s19_embudo_ventas(uri, cur):
    seccion("19 · El embudo de ventas: siguiente paso, reporte de la cita y presentación · V1 a V4")
    Q = {n: uno(cur, "select id from persona where correo = %s", (f"{n}@prueba.local",)) for n in ("felipe", "alison", "andres", "mariana")}
    _, fe = sesion(uri, USUARIOS["felipe"][0])
    _, al = sesion(uri, USUARIOS["alison"][0])
    _, an = sesion(uri, USUARIOS["andres"][0])
    _, ma = sesion(uri, USUARIOS["mariana"][0])
    en_dias = lambda n, h="10:00": uno(cur, """select to_char((private.hoy() + %s)::timestamp + %s::time, 'YYYY-MM-DD"T"HH24:MI')""", (n, h))
    reporte = "select reporte_de_cita(%s, %s::jsonb)"

    # Un contacto que escribe queda en el día de quien lo registró.
    lead = uno(al, "select nuevo_contacto(%s::jsonb)", (json.dumps(
        {"nombre": "PRUEBA V Casa Tocaima", "telefono": "3150000001", "canal": "google_ads", "como_nos_encontro": "asistente_ia"}),))["lead_id"]
    dia = todas(al, "select que, lectura from v_ventas_hoy where lead_id = %s and persona_id = %s", (lead, Q["alison"]))
    registrar("V0 · un contacto nuevo queda en el día de quien lo registró, pidiendo el primer contacto",
              len(dia) == 1 and dia[0][0] == "primer_contacto" and "nadie le ha respondido" in dia[0][1], str(dia))
    ok, msg = espera_error(ma, "select nuevo_contacto(%s::jsonb)", (json.dumps({"nombre": "PRUEBA V Intruso", "canal": "referido"}),), "row-level security")
    registrar("V0 · quien no es de ventas no registra contactos", ok, msg)
    ok, msg = espera_error(al, "select nuevo_contacto(%s::jsonb)", (json.dumps({"nombre": "PRUEBA V Sin canal"}),), "sin canal")
    registrar("M1 · tampoco desde la aplicación entra un contacto sin canal", ok, msg)

    # Con la cita agendada nace la oportunidad.
    r = uno(al, "select agendar_cita_de_lead(%s, %s::jsonb)", (lead, json.dumps(
        {"cita": en_dias(1, "15:00"), "unidad": "diseno_arquitectonico", "responsable_id": Q["felipe"], "proyecto": "PRUEBA V Casa Tocaima"})))
    op, cita = r["oportunidad_id"], r["cita_id"]
    f = uno(cur, """select o.etapa::text, o.siguiente_paso, o.siguiente_paso_en - private.hoy(), o.siguiente_paso_por, l.estado::text,
                           l.primer_contacto_en is not null, to_char(c.programada_para at time zone 'America/Bogota', 'HH24:MI'), c.tipo
                    from oportunidad o join lead l on l.id = o.lead_id join cita c on c.id = %s where o.id = %s""", (cita, op))
    registrar("V0 · al agendar la cita nace la oportunidad, con la cita a la hora de Colombia y el primer contacto medido",
              f[0] == "cita_viabilidad" and f[4] == "convertido" and f[5] and f[6] == "15:00" and f[7] == "viabilidad", str(f))
    registrar("V1 · el siguiente paso queda escrito, para el día de la cita y a nombre de quien la hace",
              f[1].startswith("Hacer la cita de viabilidad el ") and f[2] == 1 and f[3] == Q["felipe"], f"{f[1]} · {f[2]}")
    registrar("V0 · y el contacto sale de la lista de primer contacto", uno(al, "select count(*) from v_ventas_hoy where lead_id = %s", (lead,)) == 0)

    ok, msg = espera_error(al, "update oportunidad set siguiente_paso_en = private.hoy() - 1 where id = %s", (op,), "fecha que ya pasó")
    registrar("V1 · el siguiente paso no queda para una fecha que ya pasó", ok, msg)
    ok, msg = espera_error(al, "update oportunidad set siguiente_paso = '' where id = %s", (op,), "siguiente paso escrito")
    registrar("V1 · una oportunidad abierta no se queda sin siguiente paso", ok, msg)
    ok, msg = espera_error(fe, "update oportunidad set etapa = 'presupuesto_detallado', valor_estimado = 33000000 where id = %s", (op,), "reporte de la cita")
    registrar("V3 · de la cita de viabilidad no se pasa a cotizar sin el reporte", ok, msg)
    emitir = """insert into cotizacion (oportunidad_id, numero, tipo, valor, costo_estimado, estado)
                values (%s, 'PRUEBA V-01', 'diseno', 36800000, 15000000, 'emitida')"""
    ok, msg = espera_error(fe, emitir, (op,), "reunión de presentación")
    registrar("V2 · una cotización no se emite sin la reunión de presentación agendada", ok, msg)

    # El reporte de la cita.
    base = {"grabacion": True, "transcripcion": "https://docs.google.com/document/d/PRUEBA", "tiene_lote": "si",
            "recurso_disponible": "0_3_meses", "proposito": "vivienda", "area": 140}
    ok, msg = espera_error(fe, reporte, (cita, json.dumps({**base, "sigue": "cotizar", "cuando": en_dias(1, "09:00")})), "estaba quien decide")
    registrar("V3 · el reporte pregunta si estaba quien decide", ok, msg)
    ok, msg = espera_error(fe, reporte, (cita, json.dumps({**base, "decisor_presente": True, "sigue": "cotizar"})), "reunión de presentación")
    registrar("V2 · para cotizar, el reporte deja agendada la presentación", ok, msg)
    ok, msg = espera_error(fe, reporte, (cita, json.dumps({**base, "decisor_presente": True, "sigue": "cotizar", "cuando": en_dias(1, "09:00")})), "valor estimado")
    registrar("V3 · sin valor ni tarifa para el área, el reporte pide el valor", ok, msg)
    ok, msg = espera_error(fe, reporte, (cita, json.dumps({**base, "sigue": "algo"})), "falta decir cómo sigue")
    registrar("V3 · el reporte dice cómo sigue, escogiendo", ok, msg)

    tarifa = "insert into tarifa_diseno (unidad, area_desde, area_hasta, valor, alcance, creada_por) values ('diseno_arquitectonico', 110, 150, 36800000, 'PRUEBA', %s)"
    ok, msg = espera_error(al, tarifa, (Q["alison"],), "row-level security")
    registrar("V3 · las tarifas las escribe dirección", ok, msg)
    fe.execute(tarifa, (Q["felipe"],))
    registrar("V3 · ventas lee el valor que sugiere la tarifa, y fuera del rango no sugiere nada",
              uno(al, "select valor_sugerido('diseno_arquitectonico', 140)") == 36800000
              and uno(al, "select valor_sugerido('diseno_arquitectonico', 200)") is None)

    pres = uno(fe, reporte, (cita, json.dumps({**base, "decisor_presente": True, "sigue": "cotizar", "cuando": en_dias(1, "09:00")})))
    e = uno(cur, """select o.etapa::text, o.valor_estimado, o.area_m2, o.siguiente_paso, o.siguiente_paso_en = private.hoy(),
                           c.estado::text, c.consentimiento_grabacion, k.decisor_presente, k.tiene_lote, k.cita_id = c.id, p.tipo, p.estado::text
                    from oportunidad o join cita c on c.id = %s join calificacion k on k.oportunidad_id = o.id join cita p on p.id = %s
                    where o.id = %s""", (cita, pres, op))
    registrar("V3 · el reporte deja la cita realizada, la ficha con quien decide y la oportunidad para cotizar con el valor de la tarifa",
              e[0] == "presupuesto_detallado" and e[1] == 36800000 and e[2] == 140 and e[5] == "realizada" and e[6] is True
              and e[7] is True and e[8] == "si" and e[9], str(e))
    registrar("V2 · y la presentación queda agendada, con el siguiente paso de preparar la cotización para la víspera",
              e[10] == "presentacion" and e[11] == "agendada" and e[3].startswith("Preparar la cotización para presentarla el ") and e[4], e[3])
    dia = todas(fe, "select que from v_ventas_hoy where oportunidad_id = %s and persona_id = %s", (op, Q["felipe"]))
    registrar("V1 · el siguiente paso de hoy aparece en el día de quien lo da", ("siguiente_paso",) in dia, str(dia))
    ok, msg = espera_error(fe, reporte, (cita, json.dumps({**base, "decisor_presente": True, "sigue": "pensarlo", "seguimiento": "2030-01-01"})), "ya tiene su reporte")
    registrar("V3 · una cita no se reporta dos veces", ok, msg)

    fe.execute(emitir, (op,))
    e = uno(cur, "select etapa::text, siguiente_paso from oportunidad where id = %s", (op,))
    registrar("V2 · con la presentación agendada la cotización se emite y la oportunidad avanza sola",
              e[0] == "cotizacion_enviada" and e[1].startswith("Presentar la cotización PRUEBA V-01 el "), str(e))
    uno(fe, reporte, (pres, json.dumps({"grabacion": False, "sigue": "contrato"})))
    registrar("V3 · si en la presentación el cliente acepta, la oportunidad pasa a contrato y anticipo",
              uno(cur, "select etapa::text, siguiente_paso from oportunidad where id = %s", (op,)) == ("negociacion", "Firmar el contrato y recibir el anticipo"))

    # V4 · El diseño ganado abre la obra.
    cur.execute("update parametro set responsable_obra_id = %s", (Q["andres"],))
    antes = uno(an, "select count(*) from oportunidad")
    fe.execute("update oportunidad set etapa = 'ganada' where id = %s", (op,))
    obra = uno(cur, """select id, unidad::text, canal::text, etapa::text, responsable_id, siguiente_paso, siguiente_paso_en - private.hoy()
                       from oportunidad where origen_oportunidad_id = %s""", (op,))
    registrar("V4 · al ganar el diseño nace la oportunidad de obra, con el mismo canal y a nombre de quien responde por las obras",
              obra is not None and obra[1:] == ("obra_propia", "google_ads", "cita_viabilidad", Q["andres"], "Ofrecer el presupuesto de obra", 30), str(obra))
    registrar("V4 · quien responde por las obras la ve aunque no sea de ventas, y no ve las demás",
              antes == 0 and uno(an, "select count(*) from oportunidad") == 1)
    an.execute("update oportunidad set siguiente_paso = 'PRUEBA Llamar para el presupuesto', siguiente_paso_en = private.hoy() + 3 where id = %s", (obra[0],))
    registrar("V4 · y le escribe el siguiente paso", an.rowcount == 1)
    registrar("V1 · la venta ganada ya no pide siguiente paso",
              uno(cur, "select siguiente_paso is null and siguiente_paso_en is null and siguiente_paso_por is null from oportunidad where id = %s", (op,)))
    fe.execute("update oportunidad set etapa = 'negociacion' where id = %s", (op,))
    fe.execute("update oportunidad set etapa = 'ganada' where id = %s", (op,))
    registrar("V4 · reabierta y ganada otra vez, sigue habiendo una sola oportunidad de obra",
              uno(cur, "select count(*) from oportunidad where origen_oportunidad_id = %s", (op,)) == 1)

    # Si no llegó, y si no sigue.
    r2 = uno(al, "select nuevo_contacto(%s::jsonb)", (json.dumps({"nombre": "PRUEBA V No llegó", "telefono": "3150000002", "canal": "referido", "cita": en_dias(1)}),))
    uno(fe, reporte, (r2["cita_id"], json.dumps({"llego": False})))
    registrar("V3 · si no llegó, la cita queda como no llegó y el siguiente paso es reagendarla hoy",
              uno(cur, """select c.estado::text, o.siguiente_paso, o.siguiente_paso_en = private.hoy()
                          from cita c join oportunidad o on o.id = c.oportunidad_id where c.id = %s""", (r2["cita_id"],))
              == ("no_show", "Reagendar la cita: el cliente no llegó", True))
    c3 = uno(fe, "insert into cita (oportunidad_id, programada_para) values (%s, now() - interval '3 hours') returning id", (r2["oportunidad_id"],))
    registrar("V3 · una cita que ya pasó sin reporte aparece en el día de quien responde por la oportunidad",
              todas(fe, "select que, persona_id from v_ventas_hoy where cita_id = %s", (c3,)) == [("reporte_cita", Q["alison"])])
    ok, msg = espera_error(fe, reporte, (c3, json.dumps({"sigue": "no_sigue"})), "falta el motivo")
    registrar("M4 · si no sigue, el reporte pide el motivo", ok, msg)
    uno(fe, reporte, (c3, json.dumps({"sigue": "no_sigue", "motivo": "precio", "detalle": "PRUEBA El diseño se salía del presupuesto"})))
    registrar("M4 · con el motivo, la oportunidad queda perdida y sin siguiente paso",
              uno(cur, "select etapa::text, motivo_perdida::text, siguiente_paso from oportunidad where id = %s", (r2["oportunidad_id"],)) == ("perdida", "precio", None))

    # Lo que se lee.
    emb = {(l, et): n for l, et, n in todas(fe, "select linea, etapa::text, oportunidades from v_embudo_ventas")}
    registrar("el embudo cuenta las oportunidades abiertas por línea y etapa, con la de obra que nació del diseño",
              emb.get(("obra", "cita_viabilidad"), 0) >= 1, str(emb)[:200])
    ritmo = uno(fe, "select lectura from v_ritmo_ventas")
    registrar("el ritmo de ventas se lee en una frase, con cuántas citas lleva cada venta",
              ritmo.startswith("En los últimos 90 días hubo ") and "una venta por cada" in ritmo, ritmo)
    cur.execute("update parametro set meta_ventas_diseno_mes = 60000000")
    ritmo = uno(fe, "select lectura from v_ritmo_ventas")
    registrar("con la meta escrita, la frase dice cuántas citas al mes hacen falta", "hacen falta unas" in ritmo and "citas al mes; van" in ritmo, ritmo)
    cur.execute("update parametro set meta_ventas_diseno_mes = null, responsable_obra_id = null")
    registrar("la sesión dice quién vende: ventas sí, quien responde por una obra también, el resto no",
              uno(al, "select (mi_sesion() ->> 'vende')::boolean") and uno(an, "select (mi_sesion() ->> 'vende')::boolean")
              and not uno(ma, "select (mi_sesion() ->> 'vende')::boolean"))
    imp = uno(cur, """insert into oportunidad (nombre, canal, etapa, valor_estimado)
                      values ('PRUEBA V Importada de Pipedrive', 'google_ads', 'cotizacion_enviada', 26000000) returning siguiente_paso""")
    registrar("las cargas del sistema (la importación de Pipedrive) no se frenan, y quedan con el siguiente paso de su etapa",
              imp == "Saber qué decidió el cliente sobre la cotización", imp)
    registrar("sin sesión no se registra ni se lee nada del embudo",
              uno(cur, """select not has_function_privilege('anon', 'public.nuevo_contacto(jsonb)', 'execute')
                            and not has_function_privilege('anon', 'public.reporte_de_cita(uuid, jsonb)', 'execute')
                            and not has_table_privilege('anon', 'public.v_ventas_hoy', 'select')
                            and not has_function_privilege('authenticated', 'private.ventas_oportunidad()', 'execute')
                            and not has_function_privilege('authenticated', 'private.diseno_abre_obra()', 'execute')"""))
    for c in (fe, al, an, ma):
        c.connection.close()


def s20_modulo_obra(uri, cur):
    seccion("20 · El módulo de obra: gastos con factura, documentos y tablero · O12 a O15")
    Q = {n: uno(cur, "select id from persona where correo = %s", (f"{n}@prueba.local",)) for n in ("felipe", "luisa", "andres", "mariana", "finanzas", "alison")}
    _, fe = sesion(uri, USUARIOS["felipe"][0])
    _, lu = sesion(uri, USUARIOS["luisa"][0])
    _, an = sesion(uri, USUARIOS["andres"][0])
    _, ma = sesion(uri, USUARIOS["mariana"][0])
    _, fi = sesion(uri, USUARIOS["finanzas"][0])
    _, al = sesion(uri, USUARIOS["alison"][0])
    nirv = uno(cur, "select id from proyecto where codigo = 'OBRA NIRVANA'")
    cur.execute("update proyecto set tipo = 'obra', estado = 'activo' where id = %s", (nirv,))
    umbral = float(uno(cur, "select umbral_aprobacion from parametro"))
    prov = uno(cur, "select id from categoria_costo where nombre = 'PROVEEDORES'")
    nueva = uno(cur, """select c.id from categoria_costo c where c.activo and c.tipo_gasto = 'COSTOS OPERATIVOS'
                          and not exists (select 1 from centro_costo cc where cc.proyecto_id = %s and cc.categoria_id = c.id) limit 1""", (nirv,))
    gasto = "select registrar_gasto(%s::jsonb)"
    base = {"proyecto_id": str(nirv), "categoria_id": prov, "tercero": "PRUEBA Ferretería del Eje", "concepto": "PRUEBA Cemento y arena"}

    # O14 · El residente registra el gasto escogiendo la categoría.
    g1 = uno(an, gasto, (json.dumps({**base, "valor": 350000, "numero_factura": "FE-123", "fecha_prevista_pago": "2030-01-15"}),))
    f = uno(cur, """select m.estado::text, m.numero_factura, m.registrado_por, cc.proyecto_id, cc.categoria_id, m.aprobacion::text
                    from movimiento m join centro_costo cc on cc.id = m.centro_costo_id where m.id = %s""", (g1,))
    registrar("O14 · el residente registra un gasto con su factura, a su nombre, en el centro de costo de la categoría",
              f == ("causacion", "FE-123", Q["andres"], nirv, prov, "no_requiere"), str(f))
    if nueva:
        uno(an, gasto, (json.dumps({**base, "categoria_id": nueva, "valor": 120000}),))
        registrar("O14 · si la obra no tenía esa categoría, la base abre su centro de costo con presupuesto cero",
                  uno(cur, "select presupuesto from centro_costo where proyecto_id = %s and categoria_id = %s", (nirv, nueva)) == 0)
    ok, msg = espera_error(ma, gasto, (json.dumps({**base, "valor": 1000}),), "no registra gastos en esta obra")
    registrar("O14 · quien no está en la obra no registra gastos en ella", ok, msg)
    ok, msg = espera_error(an, gasto, (json.dumps({**base, "valor": 1000, "estado": "pago"}),), "diga con qué")
    registrar("O14 · si ya se pagó, el gasto dice con qué se pagó", ok, msg)
    ok, msg = espera_error(an, gasto, (json.dumps({**base, "valor": 1000, "tercero": " "}),), "a quién se le paga")
    registrar("O14 · el gasto dice a quién se le paga", ok, msg)
    ok, msg = espera_error(an, gasto, (json.dumps({**base, "valor": 0}),), "valor del gasto")
    registrar("O14 · y cuánto vale", ok, msg)
    ok, msg = espera_error(an, "insert into movimiento (proyecto_id, centro_costo_id, estado, valor, tercero_nombre, concepto, registrado_por, numero_factura) "
                               "select %s, cc.id, 'causacion', 1000, 'PRUEBA', 'PRUEBA', %s, '' from centro_costo cc where cc.proyecto_id = %s limit 1",
                           (nirv, Q["andres"], nirv), "mov_factura_escrita")
    registrar("O12 · el número de factura, si va, va escrito", ok, msg)

    # El umbral pide aprobación y el tablero lo dice primero.
    g2 = uno(an, gasto, (json.dumps({**base, "valor": umbral + 500000, "concepto": "PRUEBA Acero de refuerzo"}),))
    t = uno(fe, "select gastos_por_aprobar, alerta, lectura from v_obra_tablero where id = %s", (nirv,))
    registrar("T4 · un gasto desde la obra que llega al umbral espera aprobación", uno(cur, "select aprobacion::text from movimiento where id = %s", (g2,)) == "pendiente")
    registrar("O15 · el tablero de obras dice primero el gasto que espera aprobación, y cómo va la plata en una frase",
              t[0] >= 1 and "la aprobación de dirección" in (t[1] or "") and t[2].startswith("Lleva "), f"{t[1]} · {t[2]}")
    an.execute("update movimiento set aprobacion = 'aprobado', aprobado_por = %s, aprobado_en = now() where id = %s", (Q["andres"], g2))
    registrar("T1 · el residente no aprueba su propio gasto",
              an.rowcount == 0 and uno(cur, "select aprobacion::text from movimiento where id = %s", (g2,)) == "pendiente")
    lu.execute("update movimiento set aprobacion = 'aprobado', aprobado_por = %s, aprobado_en = now() where id = %s", (Q["luisa"], g2))
    t = uno(fe, "select gastos_por_aprobar, coalesce(alerta, '') from v_obra_tablero where id = %s", (nirv,))
    registrar("O15 · aprobado por dirección, el tablero deja de pedir la aprobación", t[0] == 0 and "aprobación" not in t[1], str(t))

    # O15 · Facturas por pagar y el pago.
    pp = uno(an, "select por_pagar, numero_factura, facturado, fecha_prevista from v_obra_por_pagar where raiz_id = %s", (g1,))
    registrar("O15 · la factura queda en la lista de lo que falta pagar, con su número y la fecha prevista",
              pp is not None and float(pp[0]) == 350000 and pp[1] == "FE-123" and pp[2] and str(pp[3]) == "2030-01-15", str(pp))
    an.execute("""insert into movimiento (proyecto_id, centro_costo_id, estado, origen_id, valor, tercero_nombre, concepto, medio, registrado_por)
                  select proyecto_id, centro_costo_id, 'pago', id, valor, tercero_nombre, concepto, 'banco', %s from movimiento where id = %s""", (Q["andres"], g1))
    registrar("O15 · pagada, sale de la lista", uno(an, "select count(*) from v_obra_por_pagar where raiz_id = %s", (g1,)) == 0)
    mes = uno(fe, "select pagado from v_obra_flujo_mes where proyecto_id = %s and mes = date_trunc('month', private.hoy())::date", (nirv,))
    registrar("O15 · y el pago cuenta en el flujo del mes de la obra", mes is not None and float(mes) >= 350000, str(mes))
    an.execute("""insert into movimiento (proyecto_id, centro_costo_id, estado, naturaleza, origen_id, valor, tercero_nombre, concepto, medio, registrado_por)
                  select proyecto_id, centro_costo_id, 'pago', 'devolucion', id, 50000, tercero_nombre, 'PRUEBA Devolvieron un bulto', 'banco', %s
                  from movimiento where raiz_id = %s and estado = 'pago'""", (Q["andres"], g1))
    despues = uno(fe, "select pagado from v_obra_flujo_mes where proyecto_id = %s and mes = date_trunc('month', private.hoy())::date", (nirv,))
    registrar("O15 · una devolución del proveedor resta en el flujo del mes", cerca(float(mes) - float(despues), 50000, 0.01), f"{mes} → {despues}")
    total = uno(cur, """select coalesce(sum(case when naturaleza = 'devolucion' then -valor else valor end), 0)
                        from v_movimiento_vigente where proyecto_id = %s and estado = 'pago'""", (nirv,))
    registrar("O15 · el flujo por mes suma exactamente lo pagado en la obra",
              cerca(uno(cur, "select sum(pagado) from v_obra_flujo_mes where proyecto_id = %s", (nirv,)), total, 0.01))

    # O13 · Documentos.
    doc = "insert into documento_obra (proyecto_id, tipo, titulo, enlace, registrado_por) values (%s, %s, %s, %s, %s) returning id"
    d1 = uno(an, doc, (nirv, "contrato", "PRUEBA Contrato de obra firmado", "https://drive.google.com/file/d/PRUEBA", Q["andres"]))
    registrar("O13 · quien registra en la obra pone un documento con su enlace de Drive", d1 is not None)
    ok, msg = espera_error(an, doc, (nirv, "planos", "PRUEBA Planos", "http://inseguro.local/x", Q["andres"]), "documento_enlace_web")
    registrar("O13 · el enlace es una dirección segura (https)", ok, msg)
    ok, msg = espera_error(ma, doc.replace(" returning id", ""), (nirv, "otro", "PRUEBA Ajeno", "https://drive.google.com/x", Q["mariana"]), "row-level security")
    registrar("O13 · quien no está en la obra no le pone documentos", ok, msg)
    ok, msg = espera_error(an, "update documento_obra set titulo = 'PRUEBA Otro título' where id = %s", (d1,), "no se edita")
    registrar("O13 · un documento registrado no se edita", ok, msg)
    an.execute("update documento_obra set retirado_en = now() where id = %s", (d1,))
    registrar("O13 · se retira, a nombre de quien lo retira",
              uno(cur, "select retirado_por from documento_obra where id = %s", (d1,)) == Q["andres"])
    ok, msg = espera_error(an, "update documento_obra set retirado_en = now() where id = %s", (d1,), "ya estaba retirado")
    registrar("O13 · y no se retira dos veces", ok, msg)
    ok, msg = espera_error(cur, "delete from documento_obra where id = %s", (d1,), "no se borran")
    registrar("T3 · los documentos no se borran", ok, msg)

    # Quién ve qué.
    registrar("O15 · el residente ve su obra en el tablero; quien no está en ninguna obra no ve nada",
              uno(an, "select count(*) from v_obra_tablero where id = %s", (nirv,)) == 1 and uno(al, "select count(*) from v_obra_tablero") == 0)
    cur.execute("""insert into ingreso (proyecto_id, valor, linea, concepto, registrado_por)
                   values (%s, 10000000, 'obra_civil', 'PRUEBA Anticipo', %s)""", (nirv, Q["finanzas"]))
    registrar("O15 · lo cobrado lo ve dirección y no el residente",
              float(uno(fe, "select cobrado from v_obra_tablero where id = %s", (nirv,))) >= 10000000
              and float(uno(an, "select cobrado from v_obra_tablero where id = %s", (nirv,))) == 0)
    s = {n: uno(c, "select (mi_sesion() ->> 'obras')::boolean, (mi_sesion() ->> 've_dinero')::boolean") for n, c in
         (("felipe", fe), ("andres", an), ("alison", al), ("finanzas", fi))}
    registrar("la sesión dice quién ve obras y quién ve la plata completa",
              s["felipe"] == (True, True) and s["andres"] == (True, False) and s["alison"] == (False, False) and s["finanzas"] == (True, True), str(s))
    registrar("sin sesión no se registra ni se lee nada de obra",
              uno(cur, """select not has_function_privilege('anon', 'public.registrar_gasto(jsonb)', 'execute')
                            and not has_table_privilege('anon', 'public.documento_obra', 'select')
                            and not has_table_privilege('anon', 'public.v_obra_tablero', 'select')
                            and not has_table_privilege('anon', 'public.v_obra_por_pagar', 'select')
                            and not has_function_privilege('authenticated', 'private.validar_documento()', 'execute')"""))
    for c in (fe, lu, an, ma, fi, al):
        c.connection.close()


def s21_prestamos_y_socios(uri, cur):
    seccion("21 · Préstamos y socios: cargados, pero solo los ven Felipe y Luisa · F7")
    Q = {n: uno(cur, "select id from persona where correo = %s", (f"{n}@prueba.local",)) for n in ("felipe", "luisa", "andres", "finanzas")}
    _, fe = sesion(uri, USUARIOS["felipe"][0])
    _, lu = sesion(uri, USUARIOS["luisa"][0])
    _, an = sesion(uri, USUARIOS["andres"][0])
    _, fi = sesion(uri, USUARIOS["finanzas"][0])
    # Se cuenta en el movimiento mismo: si se cruzara con la categoría o el centro de costo, que
    # también se ocultan, la prueba pasaría aunque la política del movimiento dejara ver todo.
    reservados = "select count(*) from movimiento where centro_costo_id in (select private.centros_reservados())"
    total = uno(cur, reservados)
    registrar("F7 · el histórico trae préstamos y movimientos de socios", total > 0, f"{total} movimientos")
    registrar("F7 · un socio los ve todos", uno(fe, reservados) == total)
    registrar("F7 · finanzas no los ve, aunque ve el resto del dinero",
              uno(fi, reservados) == 0 and uno(fi, "select count(*) from movimiento") > 0)
    registrar("F7 · dirección sin el permiso tampoco", uno(lu, reservados) == 0)
    registrar("F7 · ni sus categorías, ni sus centros de costo, ni el proyecto de los socios",
              uno(fi, "select count(*) from categoria_costo where reservada") == 0
              and uno(fi, "select count(*) from centro_costo where id in (select private.centros_reservados())") == 0
              and uno(fi, "select count(*) from proyecto where codigo = 'SOCIOS'") == 0
              and uno(fe, "select count(*) from proyecto where codigo = 'SOCIOS'") == 1)
    ok, msg = espera_error(lu, "update persona set ve_reservado = true where id = %s", (Q["luisa"],), "lo autoriza un socio")
    registrar("F7 · nadie se da el permiso a sí mismo: lo da un socio", ok, msg)
    fe.execute("update persona set ve_reservado = true where id = %s", (Q["luisa"],))
    registrar("F7 · con el permiso que le dio Felipe, Luisa los ve", uno(lu, reservados) == total)
    registrar("la sesión dice quién ve lo reservado",
              uno(lu, "select (mi_sesion() ->> 've_reservado')::boolean") and not uno(fi, "select (mi_sesion() ->> 've_reservado')::boolean")
              and uno(fe, "select (mi_sesion() ->> 'es_socio')::boolean") and not uno(lu, "select (mi_sesion() ->> 'es_socio')::boolean"))
    cur.execute("insert into ingreso (valor, linea, concepto, registrado_por) values (50000000, 'credito_bancario', 'PRUEBA Crédito de tesorería', %s)", (Q["finanzas"],))
    registrar("F7 · un crédito bancario que entra a la caja tampoco lo ve finanzas; Felipe y Luisa sí",
              uno(fi, "select count(*) from ingreso where linea = 'credito_bancario'") == 0
              and uno(fe, "select count(*) from ingreso where linea = 'credito_bancario'") >= 1
              and uno(lu, "select count(*) from ingreso where linea = 'credito_bancario'") >= 1
              and uno(fi, "select count(*) from ingreso where linea <> 'credito_bancario'") > 0)
    nirv = uno(cur, "select id from proyecto where codigo = 'OBRA NIRVANA'")
    cred = uno(cur, "select id from categoria_costo where nombre = 'CREDITO'")
    ok, msg = espera_error(fe, "select registrar_gasto(%s::jsonb)", (json.dumps({"proyecto_id": str(nirv), "categoria_id": cred, "valor": 1000,
                           "tercero": "PRUEBA Banco", "concepto": "PRUEBA Cuota"}),), "no se registran desde la obra")
    registrar("F7 · un préstamo no se registra desde la obra, ni siquiera un socio: es solo para ver", ok, msg)
    ok, msg = espera_error(fi, "update categoria_costo set reservada = true where nombre = 'TRANSPORTE'", None, "lo decide un socio")
    registrar("F7 · qué es reservado lo decide un socio", ok, msg)
    rent = uno(fe, "select count(*) from v_rentabilidad_proyecto")
    registrar("F5 · la rentabilidad no cambia: lo reservado ya estaba fuera", rent > 0)
    fe.execute("update persona set ve_reservado = false where id = %s", (Q["luisa"],))
    registrar("F7 · el permiso se quita y deja de verlos", uno(lu, reservados) == 0)
    for c in (fe, lu, an, fi):
        c.connection.close()


def s22_adicional_retirado(uri, cur):
    seccion("22 · Un adicional que ESA retira no se borra: queda retirado, con la razón · O1")
    _, lu = sesion(uri, USUARIOS["luisa"][0])
    _, an = sesion(uri, USUARIOS["andres"][0])
    _, cl = sesion(uri, USUARIOS["cliente"][0])
    nirv = uno(cur, "select id from proyecto where codigo = 'OBRA NIRVANA'")
    viejo = uno(cur, "select id from adicional where proyecto_id = %s and codigo = 'AD-10'", (nirv,))
    ok, msg = espera_error(lu, "update adicional set cantidad = 1 where id = %s", (viejo,), "retirado no se modifica")
    registrar("O1 · un adicional retirado no se modifica", ok, msg)
    ok, msg = espera_error(lu, "update adicional set retirado_en = null, retirado_motivo = null where id = %s", (viejo,), "retirado no se modifica")
    registrar("O1 · ni se vuelve a abrir: si vuelve, es uno nuevo", ok, msg)
    ok, msg = espera_error(cl, "insert into aprobacion_cliente (adicional_id, decision) values (%s, 'aprobado')", (viejo,), "retirado")
    registrar("O1 · el cliente no decide sobre un adicional retirado", ok, msg)
    ok, msg = espera_error(cur, "delete from adicional where id = %s", (viejo,), "no se")
    registrar("O1 · borrarlo sigue prohibido", ok, msg)

    decidido = uno(cur, "select id from adicional where proyecto_id = %s and aprobacion = 'aprobado' limit 1", (nirv,))
    ok, msg = espera_error(lu, "update adicional set retirado_en = now(), retirado_motivo = 'Ya no va' where id = %s",
                           (decidido,), "no ha decidido")
    registrar("O1 · uno que el cliente ya aprobó no se retira", ok, msg)
    vivo = uno(cur, "select id from adicional where proyecto_id = %s and codigo = 'MOD-22.03'", (nirv,))
    an.execute("update adicional set retirado_en = now(), retirado_motivo = 'Ya no va' where id = %s", (vivo,))
    registrar("O1 · el residente no retira adicionales", an.rowcount == 0, f"filas afectadas {an.rowcount}")
    ok, msg = espera_error(lu, "update adicional set retirado_en = now() where id = %s", (vivo,), "por qué")
    registrar("O1 · retirarlo pide la razón", ok and uno(cur, "select retirado_en is null from adicional where id = %s", (vivo,)), msg)

    antes = uno(cur, "select cantidad, bruto from v_adicionales_netos where proyecto_id = %s", (nirv,))
    tablero = uno(cur, "select adicionales_pendientes from v_obra_tablero where id = %s", (nirv,))
    valor = uno(cur, "select valor from adicional where id = %s", (vivo,))
    lu.execute("update adicional set retirado_en = now(), retirado_motivo = 'PRUEBA La segunda jornada de aseo la absorbe ESA' where id = %s", (vivo,))
    quien = uno(cur, "select p.correo from adicional a join persona p on p.id = a.retirado_por where a.id = %s", (vivo,))
    despues = uno(cur, "select cantidad, bruto from v_adicionales_netos where proyecto_id = %s", (nirv,))
    registrar("O1 · dirección lo retira con la razón y queda quién lo hizo", quien == "luisa@prueba.local", str(quien))
    registrar("O2 · lo retirado sale de los adicionales netos",
              despues[0] == antes[0] - 1 and cerca(despues[1], float(antes[1]) - float(valor), 0.01),
              f"{antes[0]} -> {despues[0]} · bruto ${float(antes[1]):,.0f} -> ${float(despues[1]):,.0f}")
    registrar("lo retirado no cuenta como pendiente en el tablero de obras",
              uno(cur, "select adicionales_pendientes from v_obra_tablero where id = %s", (nirv,)) == tablero - 1)
    for c in (lu, an, cl):
        c.connection.close()


def s23_revision_y_papeles(uri, cur):
    seccion("23 · Revisión por tarea y varios papeles por persona · R1–R3 y D10")
    Q = {n: uno(cur, "select id from persona where auth_user_id = %s", (USUARIOS[n][0],)) for n in ("luisa", "mariana", "arquitecto", "andres")}
    pid = uno(cur, """insert into proyecto (codigo, nombre, unidad, tipo) values ('PRUEBA REV', 'PRUEBA Revisión por tarea', 'diseno_arquitectonico', 'diseno')
                      returning id""")
    cur.execute("""insert into acceso_proyecto (persona_id, proyecto_id, papel) values (%s, %s, 'produce'), (%s, %s, 'produce'), (%s, %s, 'revisa')""",
                (Q["mariana"], pid, Q["arquitecto"], pid, Q["arquitecto"], pid))
    registrar("D10 · una persona produce y revisa en el mismo proyecto: dos papeles",
              uno(cur, "select count(*) from acceso_proyecto where persona_id = %s and proyecto_id = %s", (Q["arquitecto"], pid)) == 2)
    con_lu, lu = sesion(uri, USUARIOS["luisa"][0])
    _, ma = sesion(uri, USUARIOS["mariana"][0])
    _, ar = sesion(uri, USUARIOS["arquitecto"][0])
    nueva = lambda titulo, **k: uno(lu, f"""insert into tarea_diseno (proyecto_id, titulo, asignada_a, fecha_inicio, fecha_compromiso, dias_estimados{"".join(", " + c for c in k)})
        values (%s, %s, %s, private.hoy(), private.hoy() + 3, 1{", %s" * len(k)}) returning id""", (pid, titulo, Q["mariana"], *k.values()))
    ar.execute("select count(*) from tarea_diseno where proyecto_id = %s", (pid,))

    # ---------- R2 · sin revisión ----------
    sin = nueva("PRUEBA Enviar planos al proveedor", requiere_revision=False)
    ok, msg = espera_error(ma, "update tarea_diseno set estado = 'en_revision' where id = %s", (sin,), "no requiere revisión")
    registrar("R2 · a una tarea sin revisión no se le pide revisión", ok, msg)
    ok, msg = espera_error(ma, "update tarea_diseno set requiere_revision = true where id = %s", (sin,), "D10")
    registrar("R2 · quien hace la tarea no decide si requiere revisión", ok, msg)
    ma.execute("update tarea_diseno set estado = 'terminada' where id = %s", (sin,))
    fila = uno(cur, "select estado, terminada_en is not null, revision_pedida_en is not null from tarea_diseno where id = %s", (sin,))
    registrar("R2 · quien la tiene la entrega y queda terminada, con la hora de la entrega", fila == ("terminada", True, True), str(fila))

    # ---------- R1 · a quién se delega ----------
    ok, msg = espera_error(lu, """insert into tarea_diseno (proyecto_id, titulo, asignada_a, fecha_compromiso, revisor_id)
                                  values (%s, 'PRUEBA Se revisa sola', %s, private.hoy() + 2, %s)""", (pid, Q["mariana"], Q["mariana"]), "R1")
    registrar("R1 · quien hace la tarea no se la revisa", ok, msg)
    ok, msg = espera_error(lu, """insert into tarea_diseno (proyecto_id, titulo, asignada_a, fecha_compromiso, revisor_id)
                                  values (%s, 'PRUEBA Revisor de fuera', %s, private.hoy() + 2, %s)""", (pid, Q["mariana"], Q["andres"]), "R1")
    registrar("R1 · la revisión se delega en alguien del equipo del proyecto", ok, msg)
    ok, msg = espera_error(lu, """insert into tarea_diseno (proyecto_id, titulo, asignada_a, fecha_compromiso, requiere_revision, revisor_id)
                                  values (%s, 'PRUEBA Sin revisión y con revisor', %s, private.hoy() + 2, false, %s) returning revisor_id""", (pid, Q["mariana"], Q["arquitecto"]), "")
    sola = uno(cur, "select count(*) from tarea_diseno where titulo = 'PRUEBA Sin revisión y con revisor' and revisor_id is not null")
    registrar("R2 · sin revisión no queda nadie delegado para revisar", sola == 0, f"{sola} con revisor")

    # ---------- R3 · la revisión delegada ----------
    dele = nueva("PRUEBA Modelo de la cocina", revisor_id=Q["arquitecto"])
    normal = nueva("PRUEBA Modelo del baño")
    ma.execute("update tarea_diseno set estado = 'en_revision' where id = any(%s::uuid[])", ([str(dele), str(normal)],))
    cola_ar = {r[0] for r in todas(ar, "select tarea_id from v_cola_revision where proyecto_id = %s", (pid,))}
    cola_lu = {r[0] for r in todas(lu, "select tarea_id from v_cola_revision where proyecto_id = %s", (pid,))}
    registrar("R3 · la delegada solo le aparece a quien se le delegó", dele in cola_ar and dele not in cola_lu and normal in cola_lu,
              f"arquitecto ve {len(cola_ar)}, Luisa ve {len(cola_lu)}")
    ok, msg = espera_error(lu, "insert into revision_diseno (tarea_id, resultado) values (%s, 'aprobada')", (dele,),"R3")
    registrar("R3 · ni siquiera dirección aprueba una revisión delegada en otra persona", ok and uno(cur, "select estado from tarea_diseno where id = %s", (dele,)) == "en_revision", msg)
    ar.execute("insert into revision_diseno (tarea_id, resultado) values (%s, 'aprobada')", (dele,))
    registrar("R3 · quien recibió la delegación la aprueba y la tarea queda terminada",
              uno(cur, "select estado from tarea_diseno where id = %s", (dele,)) == "terminada")
    lu.execute("insert into revision_diseno (tarea_id, resultado, observaciones) values (%s, 'con_observaciones', 'PRUEBA Falta la cota')", (normal,))
    registrar("sin delegación, la revisa quien dirige como siempre", uno(cur, "select estado from tarea_diseno where id = %s", (normal,)) == "con_observaciones")

    # ---------- D10 · quitar un papel ----------
    abierta = uno(lu, """insert into tarea_diseno (proyecto_id, titulo, asignada_a, fecha_compromiso) values (%s, 'PRUEBA Abierta del arquitecto', %s, private.hoy() + 5)
                         returning id""", (pid, Q["arquitecto"]))
    lu.execute("delete from acceso_proyecto where persona_id = %s and proyecto_id = %s and papel = 'revisa'", (Q["arquitecto"], pid))
    registrar("D10 · se le quita un papel aunque tenga trabajo abierto, si le queda otro con el que trabaja", lu.rowcount == 1, f"filas {lu.rowcount}")
    ok, msg = espera_error(lu, "delete from acceso_proyecto where persona_id = %s and proyecto_id = %s and papel = 'produce'", (Q["arquitecto"], pid), "reasígnelas")
    registrar("D10 · sin otro papel, no sale del equipo con trabajo abierto", ok, msg)
    for c in (lu, ma, ar):
        c.connection.close()


# =============================================================================
def main():
    datos = Path(tempfile.mkdtemp(prefix="sici-pg-"))
    servidor = pgserver.get_server(datos, cleanup_mode="delete")
    uri = servidor.get_uri()
    con = psycopg2.connect(uri)
    con.autocommit = True
    cur = con.cursor()
    print("Postgres", uno(cur, "show server_version"), "· base temporal, se borra al terminar")

    paquete = s1_migraciones(uri, cur)
    if paquete is None:
        return None
    s2_asesor(cur)
    if not s3_historico(uri, cur):
        return None
    P, nirv = preparar(cur)
    obra = s4_obra(cur, P, nirv)
    s5_comercial(cur, P)
    casa = s6_diseno(cur, P)
    s7_reclamaciones(cur, P)
    s8_finanzas(cur, P, nirv, obra)
    s10_equipo(cur, P, nirv, casa)
    s9_permisos(uri, cur, P, nirv, casa)
    s11_modulo_diseno(uri, cur)
    s12_indicadores(uri, cur)
    s13_mensajes(uri, cur)
    s14_aplicacion(uri, cur)
    s15_carga_semanal(uri, cur)
    s16_flujo_por_fase(uri, cur)
    s17_tareas_tipicas(uri, cur)
    s18_cierre_de_fase(uri, cur)
    s19_embudo_ventas(uri, cur)
    s20_modulo_obra(uri, cur)
    s21_prestamos_y_socios(uri, cur)
    s22_adicional_retirado(uri, cur)
    s23_revision_y_papeles(uri, cur)
    con.close()
    return paquete


if __name__ == "__main__":
    import traceback
    paquete = None
    try:
        paquete = main()
    except Exception as e:
        traceback.print_exc()
        registrar("la prueba corrió completa sin fallas inesperadas", False, str(e).splitlines()[0])
    finally:
        malos = [r for r in resultados if not r[1]]
        print("\n" + "=" * 70)
        print(f"{len(resultados) - len(malos)} de {len(resultados)} pruebas correctas")
        for nombre, _, detalle in malos:
            print(f"  ✗ {nombre}  · {detalle}")
        if paquete and not malos and resultados:
            PAQUETE.write_text(paquete.read_text(encoding="utf-8"), encoding="utf-8")
            print(f"Paquete todo-en-uno escrito en {PAQUETE.relative_to(RAIZ)}")
        print("=" * 70)
        sys.exit(1 if malos or not resultados else 0)
