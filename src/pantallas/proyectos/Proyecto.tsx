"use client";
// Cada proyecto es un tablero: arriba cómo va (fases y cifras) y cuatro maneras
// de verlo. Tablero por estado, lista por fase, cronograma por semanas y la ficha.
import Link from "next/link";
import { sb } from "@/lib/supabase/cliente";
import { pedir, pedirUno } from "@/lib/pedir";
import { useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { asignables } from "@/lib/consultas";
import { R } from "@/lib/rutas";
import { UNIDAD } from "@/lib/dominio/catalogos";
import { hoyIso } from "@/lib/dominio/fechas";
import { uno } from "@/lib/dominio/texto";
import { plazo, type AvanceFase } from "@/lib/dominio/plazo";
import type { VFaseAvance } from "@/lib/supabase/vistas";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { TiraFases, Vacio } from "@/componentes/ui/piezas";
import { Tablero } from "./Tablero";
import { Lista } from "./Lista";
import { Cronograma } from "./Cronograma";
import { Ficha } from "./Ficha";
import { VISTAS_PROYECTO, type MiembroP, type TareaP } from "./tipos";

export function Proyecto({ id, vista: vistaPedida }: { id: string; vista: string | null }) {
  const yo = useYo();
  const vista = VISTAS_PROYECTO.some((v) => v[0] === vistaPedida) ? vistaPedida! : "tablero";
  const ficha = vista === "ficha";
  const estado = useDatos(async () => {
    const [p, fases, accesos, filas, personas, avance] = await Promise.all([
      pedirUno(sb().from("proyecto").select("id,codigo,nombre,tipo,unidad,carpeta_drive").eq("id", id).maybeSingle()),
      pedir(sb().from("proyecto_fase").select("id,fase,orden,estado,horas_cotizadas,entrega_cliente,fecha_compromiso,responsable_id").eq("proyecto_id", id).order("orden")),
      pedir(sb().from("acceso_proyecto").select("papel,persona(id,nombre,rol)").eq("proyecto_id", id)),
      pedir(sb().from("tarea_diseno").select("id,titulo,estado,prioridad,fecha_inicio,fecha_compromiso,creada_en,terminada_en,dias_estimados,fase_id,asignada_a,requiere_revision,revisor_id,tiene:persona!tarea_diseno_asignada_a_fkey(nombre)").eq("proyecto_id", id).order("fecha_compromiso", { nullsFirst: false })),
      yo.es_direccion && ficha ? pedir(sb().from("persona").select("id,nombre").eq("es_interno", true).eq("activo", true).order("nombre")) : [],
      pedir(sb().from("v_fase_avance").select("fase_id,tareas,terminadas,trabajo_terminado").eq("proyecto_id", id).overrideTypes<Pick<VFaseAvance, "fase_id" | "tareas" | "terminadas" | "trabajo_terminado">[], { merge: false }>()),
    ]);
    if (!p) return null;
    // Las relaciones embebidas, en campos planos.
    const tareas: TareaP[] = filas.map((t) => ({ ...t, quien: (t.tiene as unknown as { nombre: string } | null)?.nombre ?? null }));
    const equipo: MiembroP[] = accesos.flatMap((e) => { const q = e.persona as unknown as { id: string; nombre: string; rol: string } | null; return q ? [{ ...q, papel: e.papel }] : []; });
    const responden: [string, string][] = yo.es_direccion && ficha ? [...(await asignables(id))].sort((a, b) => a[1].localeCompare(b[1])) : [];
    return { p, fases, equipo, tareas, personas, avance, responden };
  }, [id, yo.persona_id, ficha]);

  return (
    <Carga estado={estado} atras={R.proyectos}>
      {(d) => {
        if (!d) return <Pantalla titulo="Proyecto" atras={R.proyectos}><Vacio>Ese proyecto no existe o usted no hace parte de su equipo.</Vacio></Pantalla>;
        const { p, fases, equipo, tareas, personas, avance, responden } = d;
        const av = new Map<string, AvanceFase>(avance.map((a) => [a.fase_id, a])), hoy = hoyIso();
        const abiertas = tareas.filter((t) => t.estado !== "terminada"), vencidas = abiertas.filter((t) => plazo(t, hoy).k === "c");
        const hechas = tareas.length - abiertas.length, pct = tareas.length ? (hechas / tareas.length) * 100 : 0;
        const cuenta = (e: string) => tareas.filter((t) => t.estado === e).length;
        const dirijo = yo.dirige.includes(id);
        const repartir = yo.registra.includes(id) ? <Link className="btn claro" href={R.nueva(id)}>{dirijo || yo.asigna ? "Repartir tareas de este proyecto" : "Nueva tarea en este proyecto"}</Link> : null;
        const props = { id, p, fases, tareas, av, hoy, yo, dirijo, repartir };
        return (
          <Pantalla titulo={p.nombre} sobre={`${UNIDAD[p.unidad] || p.unidad} · ${p.codigo}`} atras={R.proyectos} pie={R.proyectos}>
            <section className="p-cab">
              {fases.length ? <TiraFases fases={fases} av={av} hoy={hoy} enlace={R.proyecto(id, "lista")} /> : null}
              <div className={`p-avance ${vencidas.length ? "c" : ""}`}>
                {vencidas.length
                  ? <><b>{vencidas.length}</b><span>{vencidas.length === 1 ? "tarea vencida" : "tareas vencidas"} · avance {pct.toFixed(0)} %</span></>
                  : <><b>{pct.toFixed(0)}<small style={{ fontSize: ".4em" }}> %</small></b><span>de avance · {uno(hechas, "una tarea terminada", "terminadas")} de {tareas.length}</span></>}
              </div>
              <div className="kp">
                <div><b>{cuenta("asignada")}</b><small>Por empezar</small></div>
                <div><b>{cuenta("en_curso") + cuenta("con_observaciones")}</b><small>En curso</small></div>
                <div><b>{cuenta("en_revision")}</b><small>En revisión</small></div>
                <div className={vencidas.length ? "c" : ""}><b>{vencidas.length}</b><small>Vencidas</small></div>
              </div>
            </section>
            <nav className="pestanas p-tabs" aria-label="Vistas del proyecto">
              <div>{VISTAS_PROYECTO.map(([v, n]) => <Link key={v} href={R.proyecto(id, v)} aria-current={v === vista ? "page" : undefined}>{n}</Link>)}</div>
            </nav>
            {vista === "tablero" ? <Tablero {...props} /> : vista === "lista" ? <Lista {...props} /> : vista === "cronograma" ? <Cronograma {...props} />
              : <Ficha {...props} equipo={equipo} personas={personas} responden={responden} />}
          </Pantalla>
        );
      }}
    </Carga>
  );
}
