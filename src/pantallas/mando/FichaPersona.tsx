"use client";
// Cada persona del comité: su función, lo que debe entregar y para cuándo, su
// carga de las próximas semanas y su impacto.
import Link from "next/link";
import type { CSSProperties } from "react";
import { sb } from "@/lib/supabase/cliente";
import { decir, pedir } from "@/lib/pedir";
import { useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import { ESTADO, PAPEL, ROL } from "@/lib/dominio/catalogos";
import { corta, enCuanto, fecha } from "@/lib/dominio/fechas";
import { esfuerzo, lista, nFase, uno } from "@/lib/dominio/texto";
import { BarraCapacidad, BarraPlazo, Grupo, Marca } from "@/componentes/ui/piezas";
import { CeldasCarga } from "@/pantallas/equipo/carga";
import type { AccesoMando, Contexto, Gente, ProyectoMando, TareaMando } from "./tipos";

// El título de la base le habla a la persona; en comité se habla de ella.
const TITULO_AJENO: Record<string, string> = { espera: "Nadie esperó por su trabajo" };

/** Una tarea en la ficha: proyecto, fase, estado y cuándo se entrega. */
export function FilaTarea({ t, ctx }: { t: TareaMando; ctx: Contexto }) {
  return (
    <Link className="fila" href={R.tarea(t.id)}>
      <b>{t.titulo}<Marca prioridad={t.prioridad} /></b>
      <BarraPlazo t={t} />
      <span>
        {t.proyecto?.nombre}{t.fase?.fase ? ` · ${nFase(t.fase.fase)}` : ""} · {ESTADO[t.estado]} · {
          !t.fecha_compromiso ? <em>sin fecha de entrega</em>
            : ctx.vence(t) ? <em>era para el {fecha(t.fecha_compromiso)}, vencida {enCuanto(t.fecha_compromiso)}</em>
            : `se entrega el ${fecha(t.fecha_compromiso)}, ${enCuanto(t.fecha_compromiso)}`}
        {t.dias_estimados != null ? ` · pide ${esfuerzo(t.dias_estimados)}` : ""}
      </span>
    </Link>
  );
}

/** El impacto de cada quien llega después, para no demorar la pantalla. */
function Impacto({ personaId, propio }: { personaId: string; propio: boolean }) {
  const yo = useYo();
  const puede = yo.es_direccion || propio;
  const estado = useDatos(async () => (puede ? pedir(sb().rpc("indicadores", { p_persona: personaId })) : []), [personaId, puede]);
  if (!puede) return <div className="m-imp"><p className="m-nada">El impacto de cada persona lo ve dirección.</p></div>;
  if (estado.cargando) return <div className="m-imp"><p className="m-nada">Leyendo…</p></div>;
  if (estado.datos === undefined) return <div className="m-imp"><p className="m-nada">{decir(estado.error)}</p></div>;
  return (
    <div className="m-imp">
      {estado.datos.length ? estado.datos.map((i) => (
        <p key={i.indicador}><small>{propio ? i.titulo : TITULO_AJENO[i.indicador] || i.titulo}</small>{i.frase}</p>
      )) : <p className="m-nada">Todavía no hay nada que decir.</p>}
    </div>
  );
}

export function FichaPersona({ p, accesos, pr, ctx, abierta }: { p: Gente; accesos: AccesoMando[]; pr: Map<string, ProyectoMando>; ctx: Contexto; abierta: boolean }) {
  const yo = useYo();
  const v = p.suyas.filter(ctx.vence).length, rev = p.suyas.filter((t) => t.estado === "en_revision").length;
  const funcion = () => {
    const g: Record<string, string[]> = {};
    for (const a of accesos) if (a.persona_id === p.id && pr.has(a.proyecto_id)) (g[a.papel] ||= []).push(pr.get(a.proyecto_id)!.nombre);
    return ["dirige", "revisa", "produce", "observa"].filter((k) => g[k]).map((k) => `${PAPEL[k]} ${lista(g[k])}.`).join(" ");
  };
  return (
    <details className="m-p" open={abierta}>
      <summary>
        <b>{p.nombre}</b>
        <span>{ROL[p.ficha?.rol || ""] || ""}{p.ficha?.profesion ? ` · ${p.ficha.profesion.nombre}` : ""}</span>
        <BarraCapacidad c={p.sem[0]} />
        <span className="m-r">
          {p.suyas.length ? uno(p.suyas.length, "Un entregable abierto", "entregables abiertos") : "Sin entregables abiertos"}
          {v ? <> · <em>{uno(v, "una vencida", "vencidas")}</em></> : null}
          {rev ? ` · ${rev} en revisión` : ""}
        </span>
      </summary>
      <div className="m-dos">
        <div>
          <Grupo>Entregables y tiempos</Grupo>
          {p.suyas.length ? p.suyas.map((t) => <FilaTarea key={t.id} t={t} ctx={ctx} />) : <p className="m-nada">No tiene nada abierto.</p>}
          {yo.asigna || yo.dirige.length ? <Link className="g-dar" href={R.nueva("-", p.id)}>Entregarle una tarea</Link> : null}
        </div>
        <div>
          <Grupo>Función</Grupo>
          <p>{funcion() || "Todavía no tiene papel en ningún proyecto."}</p>
          <Grupo>Carga de las próximas semanas</Grupo>
          <div className="gantt m-g" style={{ "--n": p.sem.length } as CSSProperties}>
            <div className="g-in">
              <div className="g-sems">{p.sem.map((s, i) => <span key={s.semana}>{i === 0 && s.semana <= ctx.hoy ? "Esta" : corta(s.semana)}</span>)}</div>
              <div className="g-celdas"><CeldasCarga sem={p.sem} /></div>
            </div>
          </div>
          <Grupo>Impacto</Grupo>
          <Impacto personaId={p.id} propio={p.id === yo.persona_id} />
        </div>
      </div>
    </details>
  );
}
