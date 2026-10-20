"use client";
// Cada proyecto de arquitectura y diseño: sus fases y entregables al cliente,
// su equipo y lo que sigue.
import Link from "next/link";
import { R } from "@/lib/rutas";
import { FASE, UNIDAD } from "@/lib/dominio/catalogos";
import { enCuanto, fecha } from "@/lib/dominio/fechas";
import { lista, nFase, uno } from "@/lib/dominio/texto";
import type { VFaseAvance } from "@/lib/supabase/vistas";
import { Grupo, TiraFases } from "@/componentes/ui/piezas";
import { FilaTarea } from "./FichaPersona";
import type { AccesoMando, Contexto, FaseMando, PersonaMando, ProyectoMando, TareaMando } from "./tipos";

interface Props {
  p: ProyectoMando;
  fases: FaseMando[];
  abiertas: TareaMando[];
  accesos: AccesoMando[];
  P: Map<string, PersonaMando>;
  av: Map<string, VFaseAvance>;
  ctx: Contexto;
  abierta: boolean;
}

export function FichaProyecto({ p, fases, abiertas, accesos, P, av, ctx, abierta }: Props) {
  const { hoy, nom, vence } = ctx;
  const fs = fases.filter((f) => f.proyecto_id === p.id), act = fs.find((f) => f.estado === "en_curso" || f.estado === "en_revision");
  const ts = abiertas.filter((t) => t.proyecto_id === p.id), v = ts.filter(vence).length;
  const eq = accesos.filter((a) => a.proyecto_id === p.id && P.has(a.persona_id) && a.papel !== "observa");
  const equipo = ["dirige", "revisa", "produce"].map((k) => {
    const q = eq.filter((a) => a.papel === k).map((a) => nom(a.persona_id));
    return q.length ? `${k === "dirige" ? "Dirige" : k === "revisa" ? "Revisa" : "Produce"}${q.length > 1 ? "n" : ""} ${lista(q)}.` : "";
  }).filter(Boolean).join(" ");
  return (
    <details className="m-p" open={abierta}>
      <summary>
        <b>{p.nombre}</b>
        <span>{UNIDAD[p.unidad] || p.unidad}{act ? ` · en ${nFase(act.fase).toLowerCase()}` : ""}</span>
        <span className="m-r">
          {act?.fecha_compromiso
            ? (act.fecha_compromiso < hoy ? <em>La fase era para el {fecha(act.fecha_compromiso)}</em> : `La fase se entrega el ${fecha(act.fecha_compromiso)}, ${enCuanto(act.fecha_compromiso)}`)
            : act ? "La fase no tiene fecha de entrega" : "Ninguna fase en curso"}
          {" · "}{ts.length ? uno(ts.length, "una tarea abierta", "tareas abiertas") : "sin tareas abiertas"}
          {v ? <> · <em>{uno(v, "una vencida", "vencidas")}</em></> : null}
        </span>
      </summary>
      <div className="m-dos">
        <div>
          {fs.length ? <TiraFases fases={fs} av={av} hoy={hoy} /> : null}
          <Grupo>Fases y entregables al cliente</Grupo>
          {fs.length ? fs.map((f) => {
            const a = av.get(f.id), tarde = f.estado !== "cerrada" && !!f.fecha_compromiso && f.fecha_compromiso < hoy;
            return (
              <div key={f.id} className="fila">
                <b>{nFase(f.fase)}<span className={`marca ${FASE[f.estado][1]}`}>{FASE[f.estado][0]}</span></b>
                <span>
                  {f.entrega_cliente ? f.entrega_cliente : "Sin entregable definido"}
                  {f.responsable_id ? ` · responde ${nom(f.responsable_id)}` : f.estado !== "pendiente" && f.estado !== "cerrada" ? <> · <em>sin responsable</em></> : null}
                  {a?.tareas ? ` · ${a.terminadas} de ${uno(a.tareas, "una tarea terminada", "tareas terminadas")}` : ""}
                  {a?.trabajo_terminado ? <> · <Link href={R.cierre(f.id)} style={{ color: "var(--ok)" }}>lista para el cierre</Link></> : null}
                  {f.fecha_compromiso ? <> · {tarde ? <em>para el {fecha(f.fecha_compromiso)}</em> : `para el ${fecha(f.fecha_compromiso)}`}</> : null}
                </span>
              </div>
            );
          }) : <p className="m-nada">Este proyecto no tiene fases.</p>}
          <Link className="g-dar" href={R.proyecto(p.id)}>Abrir la ficha del proyecto</Link>
        </div>
        <div>
          <Grupo>Equipo</Grupo>
          <p>{equipo || "Todavía no tiene equipo."}</p>
          <Grupo>Lo que sigue</Grupo>
          {ts.length ? ts.slice(0, 6).map((t) => <FilaTarea key={t.id} t={t} ctx={ctx} />) : <p className="m-nada">Nada abierto.</p>}
          {ts.length > 6 ? <p className="m-nada">Y {ts.length - 6} más en la ficha.</p> : null}
        </div>
      </div>
    </details>
  );
}
