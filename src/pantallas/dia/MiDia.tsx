"use client";
// Mi día: la semana de un vistazo y las tareas por tramo de tiempo, como las
// listas de Trello. La base ya las trae en su orden de importancia.
import { Fragment } from "react";
import { sb } from "@/lib/supabase/cliente";
import { pedir } from "@/lib/pedir";
import { useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import { fecha, hoyIso } from "@/lib/dominio/fechas";
import { nFase, titulo, uno } from "@/lib/dominio/texto";
import { tramo, TRAMOS, type Carga, type Tramo } from "@/lib/dominio/plazo";
import type { VColaRevision, VDedicacionPendiente, VFaseAvance, VMiDia, VVentasHoy } from "@/lib/supabase/vistas";
import { Carga as CargaDatos } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { BarraCapacidad, BarraPlazo, Fila, Grupo, Marca, Vacio } from "@/componentes/ui/piezas";

export function MiDia() {
  const yo = useYo();
  const estado = useDatos(async () => {
    const [dia, cola, listas, sinRegistrar, ventas, carga] = await Promise.all([
      pedir(sb().from("v_mi_dia").select("*").order("orden").order("fecha_compromiso", { nullsFirst: false }).overrideTypes<VMiDia[], { merge: false }>()),
      yo.revisa.length ? pedir(sb().from("v_cola_revision").select("tarea_id").overrideTypes<Pick<VColaRevision, "tarea_id">[], { merge: false }>()) : [],
      yo.dirige.length ? pedir(sb().from("v_fase_avance").select("fase_id,proyecto_id,fase").eq("trabajo_terminado", true).overrideTypes<Pick<VFaseAvance, "fase_id" | "proyecto_id" | "fase">[], { merge: false }>()) : [],
      pedir(sb().from("v_dedicacion_pendiente").select("fecha").eq("persona_id", yo.persona_id).overrideTypes<Pick<VDedicacionPendiente, "fecha">[], { merge: false }>()),
      yo.vende ? pedir(sb().from("v_ventas_hoy").select("persona_id,urgente").overrideTypes<Pick<VVentasHoy, "persona_id" | "urgente">[], { merge: false }>()) : [],
      pedir(sb().rpc("carga_semanal", { p_semanas: 1 }).overrideTypes<Carga[], { merge: false }>()).catch(() => [] as Carga[]),
    ]);
    // Para dibujar el plazo hace falta el día en que empezó cada tarea de diseño.
    const ids = dia.filter((t) => t.origen === "diseno").map((t) => t.id);
    const inicio = new Map(ids.length ? (await pedir(sb().from("tarea_diseno").select("id,fecha_inicio,creada_en").in("id", ids))).map((x) => [x.id, x]) : []);
    // Fases que ya terminaron su trabajo en los proyectos que dirijo: falta decidir el cierre.
    const mias = listas.filter((a) => yo.dirige.includes(a.proyecto_id));
    const nombres = new Map(mias.length ? (await pedir(sb().from("proyecto").select("id,nombre").in("id", mias.map((a) => a.proyecto_id)))).map((x) => [x.id, x.nombre]) : []);
    return { dia, cola, mias, sinRegistrar, ventas, carga, inicio, nombres };
  }, [yo.persona_id]);

  return (
    <CargaDatos estado={estado}>
      {({ dia, cola, mias, sinRegistrar, ventas, carga, inicio, nombres }) => {
        const hoy = hoyIso();
        const por = new Map<Tramo, VMiDia[]>(TRAMOS.map(([k]) => [k, []]));
        for (const t of dia) por.get(tramo(t, hoy))!.push(t);
        const n = (k: Tramo) => por.get(k)!.length;
        // Quien vende ve aquí cuánto le toca hoy del embudo; el detalle está en Ventas.
        const deVentas = ventas.filter((x) => !x.persona_id || x.persona_id === yo.persona_id), urgente = deVentas.some((x) => x.urgente);
        // Mi semana: cuánto tengo encima y cuántas cosas vencen.
        const mia = carga.find((c) => c.persona_id === yo.persona_id && c.semana <= hoy);
        const hayLista = TRAMOS.some(([k]) => n(k));
        return (
          <Pantalla titulo="Mi día" sobre={fecha(hoy)} pie={R.dia} porRevisar={cola.length} mas={{ ruta: R.nueva(), nombre: "Nueva tarea" }}>
            {dia.length || mia ? (
              <section className="semana" aria-label="Mi semana">
                <Grupo style={{ marginTop: 0 }}>Mi semana</Grupo>
                <BarraCapacidad c={mia} />
                <div className="cuenta">
                  <div className={n("vencidas") ? "c" : ""}><b>{n("vencidas")}</b><small>Vencidas</small></div>
                  <div className={n("hoy") ? "a" : ""}><b>{n("hoy")}</b><small>Para hoy</small></div>
                  <div><b>{n("semana")}</b><small>Esta semana</small></div>
                </div>
              </section>
            ) : null}
            {/* El tiempo se registra escogiendo, dos veces al día. Sin eso una fase no cierra. */}
            <Fila href={R.registro}>
              <b>Registrar mi día</b>
              <span>{sinRegistrar.length ? <em>Le {sinRegistrar.length === 1 ? "falta un día" : `faltan ${sinRegistrar.length} días`} por registrar</em> : "En qué trabajó hoy, mañana y tarde"}</span>
            </Fila>
            {yo.vende ? (
              <Fila href={R.ventas}>
                <b>Ventas para hoy</b>
                <span>{deVentas.length ? (urgente ? <em>{uno(deVentas.length, "Una cosa", "cosas")} del embudo</em> : `${uno(deVentas.length, "Una cosa", "cosas")} del embudo`) : "Nada del embudo para hoy"}</span>
              </Fila>
            ) : null}
            {mias.length ? (
              <>
                <Grupo>Para decidir</Grupo>
                {mias.map((a) => (
                  <Fila key={a.fase_id} href={R.cierre(a.fase_id)}>
                    <b>{nFase(a.fase)} de {nombres.get(a.proyecto_id) || "un proyecto"}</b>
                    <span>Terminó todas sus tareas: está lista para el cierre.</span>
                  </Fila>
                ))}
              </>
            ) : null}
            {TRAMOS.filter(([k]) => n(k)).map(([k, nombre, c]) => (
              <Fragment key={k}>
                <Grupo tono={c}>{nombre} · {n(k)}</Grupo>
                {por.get(k)!.map((t) => {
                  const espera = /^La espera /.test(t.lectura || "") ? <span className="espera-tag">{t.lectura.split(" · ")[0]}</span> : null;
                  const cuerpo = (
                    <>
                      <b>{t.titulo}<Marca prioridad={t.prioridad} />{espera}</b>
                      <span>{titulo(t.proyecto)}{t.origen === "diseno" ? "" : " · pendiente de obra"}</span>
                      <BarraPlazo t={{ ...t, ...inicio.get(t.id) }} hoy={hoy} />
                    </>
                  );
                  return t.origen === "diseno"
                    ? <Fila key={t.id} href={R.tarea(t.id)}>{cuerpo}</Fila>
                    : <Fila key={t.id} href={R.obra(t.proyecto_id, "pendientes")}>{cuerpo}</Fila>;
                })}
              </Fragment>
            ))}
            {!hayLista && !mias.length ? <Vacio>Nada pendiente. Cuando le asignen algo, aparece aquí.</Vacio> : null}
          </Pantalla>
        );
      }}
    </CargaDatos>
  );
}
