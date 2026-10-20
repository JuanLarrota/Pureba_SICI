"use client";
// Equipo: la carga por semana. Una fila por persona y una columna por semana.
// El número es lo que le queda libre; las barras son sus tareas, del día en
// que empiezan al día en que se entregan. Los números los calcula la base
// (carga_semanal): aquí se pintan.
import Link from "next/link";
import type { CSSProperties } from "react";
import { sb } from "@/lib/supabase/cliente";
import { pedir } from "@/lib/pedir";
import { useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import { SEMANAS } from "@/lib/config";
import { corta, dia0, hoyIso } from "@/lib/dominio/fechas";
import { enDias } from "@/lib/dominio/texto";
import { cargaPorPersona, libres, type Carga as CargaSemana } from "@/lib/dominio/plazo";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Avatar, BarraCapacidad, Frase, Nota, Vacio } from "@/componentes/ui/piezas";
import { CeldasCarga, fraseCarga } from "./carga";

export function Equipo() {
  const yo = useYo();
  const estado = useDatos(async () => {
    const [carga, tareas] = await Promise.all([
      pedir(sb().rpc("carga_semanal", { p_semanas: SEMANAS }).overrideTypes<CargaSemana[], { merge: false }>()),
      pedir(sb().from("tarea_diseno").select("id,titulo,estado,prioridad,fecha_inicio,fecha_compromiso,creada_en,asignada_a,proyecto_id,proyecto(nombre)").neq("estado", "terminada").order("fecha_compromiso", { nullsFirst: false })),
    ]);
    const gente = [...cargaPorPersona(carga)].map(([id, sem]) => ({ id, nombre: sem[0].nombre, sem }));
    return { gente, tareas };
  }, [yo.persona_id]);

  return (
    <Carga estado={estado}>
      {({ gente, tareas }) => {
        const asigno = yo.asigna || yo.dirige.length > 0, todos = gente.length > 1 || asigno;
        if (!gente.length) {
          return (
            <Pantalla titulo="Equipo" pie={R.equipo}>
              <Vacio>Todavía no hay a quién mostrar. {yo.es_direccion ? "Agregue al equipo para ver su carga." : ""}</Vacio>
              <Link className="btn claro" href={R.personas}>Personas del equipo</Link>
            </Pantalla>
          );
        }
        const semanas = gente[0].sem.map((s) => s.semana), l0 = dia0(semanas[0]), total = 7 * semanas.length, hoy = dia0(hoyIso()), fin = l0 + total - 1;
        let sinMedir = 0;
        const filas = gente.map((p) => {
          const c0 = p.sem[0], suyas = tareas.filter((t) => t.asignada_a === p.id);
          let k = 0;
          sinMedir += p.sem.reduce((n, s) => Math.max(n, s.sin_estimar), 0);
          // Una fila por tarea: la barra va del inicio a la entrega y el nombre queda debajo, siempre legible.
          const barras = suyas.filter((t) => t.fecha_compromiso).map((t) => {
            const b0 = dia0(t.fecha_compromiso!), vencida = b0 < hoy && t.estado !== "en_revision";
            let a = Math.min(dia0(t.fecha_inicio || t.creada_en.slice(0, 10)), b0), b = vencida ? hoy : b0;
            if (b < l0 || a > fin) return null;
            a = Math.max(a, l0); b = Math.min(b, fin);
            const izq = ((a - l0) / total) * 100, der = ((fin - b) / total) * 100;
            return (
              <Link key={t.id} href={R.tarea(t.id)} className={vencida ? "v" : t.estado === "en_revision" ? "r" : t.estado === "con_observaciones" ? "d" : ""} style={{ top: `${k++ * 36}px` }}>
                <i style={{ left: `${izq.toFixed(2)}%`, right: `${der.toFixed(2)}%` }} />
                <span style={izq > 55 ? { right: `${der.toFixed(2)}%` } : { left: `${izq.toFixed(2)}%` }}>
                  {t.titulo} · {vencida ? "vencida" : t.estado === "en_revision" ? "en revisión" : t.estado === "con_observaciones" ? "devuelta" : corta(t.fecha_compromiso!)}
                </span>
              </Link>
            );
          });
          const ajenas = c0.tareas - suyas.filter((t) => t.estado !== "en_revision" && t.fecha_compromiso && Math.max(dia0(t.fecha_compromiso), hoy) <= l0 + 6).length;
          return (
            <section key={p.id} className="g-p">
              <div className="g-quien">
                <b><Avatar nombre={p.nombre} otro={p.id !== yo.persona_id} /> {p.nombre}</b>
                <BarraCapacidad c={c0} />
                <span>
                  {c0.vencidas ? <em>{c0.vencidas === 1 ? "Una vencida" : c0.vencidas + " vencidas"}</em> : null}
                  {ajenas > 0 && !suyas.length ? `${c0.vencidas ? " · " : ""}En proyectos que usted no ve` : ""}
                </span>
                {asigno ? <Link className="g-dar" href={R.nueva(null, p.id)}>Entregarle una tarea</Link> : null}
              </div>
              <div className="g-celdas"><CeldasCarga sem={p.sem} /></div>
              <div className="g-barras" style={{ height: `${k * 36}px` }}>{barras}</div>
            </section>
          );
        });
        const l = libres(gente[0].sem[0]);
        return (
          <Pantalla titulo={todos ? "Equipo" : "Mi carga"} sobre="Carga por semana" pie={R.equipo}>
            <Frase style={{ marginTop: 18 }}>
              {todos ? fraseCarga(gente, l0 <= hoy) : l < -0.05 ? `Tiene ${enDias(-l)} más de lo que cabe esta semana.` : l < 0.5 ? "Tiene la semana llena." : `Le queda${l > 1 ? "n" : ""} ${enDias(l)} esta semana.`}
            </Frase>
            {asigno ? <Link className="btn" href={R.nueva()}>Repartir tareas</Link> : null}
            <div className="gantt" style={{ "--n": semanas.length } as CSSProperties} tabIndex={0} role="group" aria-label="Carga del equipo por semana">
              <div className="g-in">
                <div className="g-sems">{semanas.map((s, i) => <span key={s}>{i === 0 && l0 <= hoy ? "Esta" : corta(s)}</span>)}</div>
                {filas}
              </div>
            </div>
            <Nota>
              El número es lo que le queda libre a cada persona en la semana, en días. Cada raya es una tarea, del día en que empieza al día en que se entrega; en rojo, las vencidas.
              {sinMedir ? ` Hay ${sinMedir === 1 ? "una tarea" : sinMedir + " tareas"} sin estimar: se ${sinMedir === 1 ? "ve" : "ven"} en el calendario pero no ${sinMedir === 1 ? "suma" : "suman"} carga.` : ""}
            </Nota>
            <Link className="btn claro" href={R.personas}>Personas del equipo</Link>
          </Pantalla>
        );
      }}
    </Carga>
  );
}
