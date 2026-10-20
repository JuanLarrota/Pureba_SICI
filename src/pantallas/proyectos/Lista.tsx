"use client";
// Lista agrupada por fase: el borde de cada grupo dice cómo va la fase.
import Link from "next/link";
import { R } from "@/lib/rutas";
import { FASE } from "@/lib/dominio/catalogos";
import { fecha } from "@/lib/dominio/fechas";
import { nFase, uno } from "@/lib/dominio/texto";
import { Avatar, BarraPlazo, ChipEstado, Etiqueta, Marca } from "@/componentes/ui/piezas";
import { quienDe, type FaseP, type TareaP, type VistaProps } from "./tipos";

export function Lista({ fases, tareas, av, hoy, yo, repartir }: VistaProps) {
  const fase = new Map(fases.map((f) => [f.id, f]));
  const sinFase: [FaseP | null, TareaP[]] = [null, tareas.filter((t) => !fase.has(t.fase_id ?? ""))];
  const grupos = [...fases.map((f): [FaseP | null, TareaP[]] => [f, tareas.filter((t) => t.fase_id === f.id)]), sinFase]
    .filter(([f, l]) => l.length || (f && (f.estado === "en_curso" || f.estado === "en_revision")));
  return (
    <>
      {grupos.map(([f, l]) => {
        const abierta = !!f && (f.estado === "en_curso" || f.estado === "en_revision"), tarde = abierta && !!f?.fecha_compromiso && f.fecha_compromiso < hoy;
        const a = f ? av.get(f.id) : undefined;
        return (
          <section key={f?.id ?? "sin-fase"} className={`ls-g ${f?.estado === "cerrada" ? "cerrada" : tarde ? "tarde" : abierta ? "curso" : ""}`}>
            <header>
              <b>{f ? nFase(f.fase) : "Sin fase"}</b>
              {f ? <Etiqueta tono={FASE[f.estado][1]}>{FASE[f.estado][0]}</Etiqueta> : null}
              <span>
                {a?.tareas ? `${a.terminadas} de ${a.tareas} terminadas` : uno(l.length, "una tarea", "tareas")}
                {f?.fecha_compromiso ? <> · {tarde ? <em style={{ fontStyle: "normal", color: "var(--critico)" }}>se entrega el {fecha(f.fecha_compromiso)}</em> : `se entrega el ${fecha(f.fecha_compromiso)}`}</> : null}
              </span>
            </header>
            {l.length ? l.map((t) => (
              <Link key={t.id} className="ls-t" href={R.tarea(t.id)}>
                <b>{t.titulo}<Marca prioridad={t.prioridad} /></b>
                <span className="q"><Avatar nombre={quienDe(t)} otro={t.asignada_a !== yo.persona_id} /><ChipEstado estado={t.estado} /></span>
                <BarraPlazo t={t} hoy={hoy} />
              </Link>
            )) : <p className="kb-nada">Sin tareas todavía.</p>}
          </section>
        );
      })}
      {repartir}
    </>
  );
}
