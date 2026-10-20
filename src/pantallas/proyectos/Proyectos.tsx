"use client";
// Proyectos: cada uno con su tira de fases y su avance.
import Link from "next/link";
import { sb } from "@/lib/supabase/cliente";
import { pedir } from "@/lib/pedir";
import { useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import { UNIDAD } from "@/lib/dominio/catalogos";
import { hoyIso } from "@/lib/dominio/fechas";
import { nFase, uno } from "@/lib/dominio/texto";
import { avanceTotal, type AvanceFase } from "@/lib/dominio/plazo";
import type { VFaseAvance } from "@/lib/supabase/vistas";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { BarraAvance, TiraFases, Vacio } from "@/componentes/ui/piezas";

type Avance = Pick<VFaseAvance, "fase_id" | "proyecto_id" | "tareas" | "terminadas">;

export function Proyectos() {
  const yo = useYo();
  const estado = useDatos(async () => {
    const ps = await pedir(sb().from("proyecto").select("id,codigo,nombre,tipo,unidad,fase,estado").eq("estado", "activo").order("nombre"));
    const ids = ps.map((p) => p.id);
    const [fases, avance, abiertas] = ids.length ? await Promise.all([
      pedir(sb().from("proyecto_fase").select("id,proyecto_id,fase,orden,estado,fecha_compromiso").in("proyecto_id", ids).order("orden")),
      pedir(sb().from("v_fase_avance").select("fase_id,proyecto_id,tareas,terminadas").overrideTypes<Avance[], { merge: false }>()),
      pedir(sb().from("tarea_diseno").select("id,proyecto_id,estado,fecha_compromiso").in("proyecto_id", ids).neq("estado", "terminada")),
    ]) : [[], [] as Avance[], []];
    return { ps, fases, avance, abiertas };
  }, [yo.persona_id]);

  return (
    <Carga estado={estado}>
      {({ ps, fases, avance, abiertas }) => {
        const av = new Map<string, AvanceFase>(avance.map((a) => [a.fase_id, a])), hoy = hoyIso();
        return (
          <Pantalla titulo="Proyectos" pie={R.proyectos}>
            {ps.length ? ps.map((p) => {
              const fs = fases.filter((f) => f.proyecto_id === p.id), { tot, pct } = avanceTotal(avance.filter((a) => a.proyecto_id === p.id));
              const ts = abiertas.filter((t) => t.proyecto_id === p.id), v = ts.filter((t) => t.fecha_compromiso && t.fecha_compromiso < hoy && t.estado !== "en_revision").length;
              const act = fs.find((f) => f.estado === "en_curso" || f.estado === "en_revision");
              return (
                <Link key={p.id} className="pr" href={R.proyecto(p.id)}>
                  <b>{p.nombre}</b>
                  <span>
                    {UNIDAD[p.unidad] || p.unidad}{act ? ` · en ${nFase(act.fase).toLowerCase()}` : ""} · {ts.length ? uno(ts.length, "una tarea abierta", "tareas abiertas") : "sin tareas abiertas"}
                    {v ? <> · <em>{uno(v, "una vencida", "vencidas")}</em></> : null}
                  </span>
                  {fs.length ? <TiraFases fases={fs} av={av} hoy={hoy} /> : null}
                  {tot ? <BarraAvance pct={pct} /> : null}
                </Link>
              );
            }) : <Vacio>{yo.es_direccion ? "Todavía no hay proyectos. Abra el primero con el botón de abajo." : "Todavía no hace parte de ningún proyecto."}</Vacio>}
            {yo.es_direccion ? <Link className="btn" href={R.nuevoProyecto()}>Crear proyecto nuevo</Link> : null}
          </Pantalla>
        );
      }}
    </Carga>
  );
}
