"use client";
// Las tareas típicas de una fase: al abrirla, la base propone lo que siempre se
// hace en ella, con su propósito, su fecha y el trabajo que suele pedir. Quien
// dirige solo escoge a quién se le entrega cada una.
import { useState } from "react";
import Link from "next/link";
import { sb } from "@/lib/supabase/cliente";
import { bien, pedir, pedirUno } from "@/lib/pedir";
import { useSesion } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { asignables, ordenarPorEspacio } from "@/lib/consultas";
import { R } from "@/lib/rutas";
import { SEMANAS } from "@/lib/config";
import { hoyIso } from "@/lib/dominio/fechas";
import { enDias, ESFUERZO, lista, nFase } from "@/lib/dominio/texto";
import { cargaPorPersona, libres, type Carga as CargaSemana } from "@/lib/dominio/plazo";
import type { TareaTipica } from "@/lib/supabase/vistas";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Formulario, Opciones } from "@/componentes/formularios/Formulario";
import { Nota, Vacio } from "@/componentes/ui/piezas";
import { Pista } from "./Pista";
import { conRevision, SelectResponsable, SelectRevision, type Reparto } from "./revision";

export function Tipicas({ faseId }: { faseId: string }) {
  const { ir } = useSesion();
  const [espaciosTexto, setEspaciosTexto] = useState("");   // lo que antes era espaciosDe[faseId]
  const estado = useDatos(async () => {
    const f = await pedirUno(sb().from("proyecto_fase").select("id,fase,estado,proyecto_id,proyecto(nombre)").eq("id", faseId).maybeSingle());
    if (!f) return null;
    const espacios = espaciosTexto.split(",").map((x) => x.trim()).filter(Boolean);
    const [prop, gente, carga, ya] = await Promise.all([
      pedir(sb().rpc("tareas_tipicas", { p_fase: faseId, p_espacios: espacios }).overrideTypes<TareaTipica[], { merge: false }>()),
      asignables(f.proyecto_id),
      pedir(sb().rpc("carga_semanal", { p_semanas: SEMANAS }).overrideTypes<CargaSemana[], { merge: false }>()),
      pedir(sb().from("tarea_diseno").select("plantilla_tarea_id,espacio").eq("fase_id", faseId)),
    ]);
    const repartida = (x: TareaTipica) => ya.some((y) => y.plantilla_tarea_id === x.plantilla_tarea_id && (y.espacio || null) === (x.espacio || null));
    const nuevas = prop.filter((x) => !repartida(x)), porEspacio = prop.some((x) => x.por_espacio);
    const porPersona = cargaPorPersona(carga), espacio = (id: string) => (porPersona.has(id) ? libres(porPersona.get(id)![0]) : null);
    const reparto: Reparto = { opciones: ordenarPorEspacio(gente, espacio), porPersona, espacio, revisores: [...gente].sort((a, b) => a[1].localeCompare(b[1])) };
    return { f, prop, nuevas, porEspacio, reparto, espacios };
  }, [faseId, espaciosTexto]);

  return (
    <Carga estado={estado} atras={R.proyectos}>
      {(d) => {
        if (!d) return <Pantalla titulo="Tareas de la fase" atras={R.proyectos}><Vacio>Esa fase no existe o no es de sus proyectos.</Vacio></Pantalla>;
        const { f, prop, nuevas, porEspacio, reparto, espacios } = d;
        const atras = R.proyecto(f.proyecto_id), proyecto = f.proyecto as unknown as { nombre: string } | null;
        const titulo = `Tareas de ${nFase(f.fase).toLowerCase()}`;
        if (!prop.length) {
          return (
            <Pantalla titulo={titulo} sobre={proyecto?.nombre} atras={atras}>
              <Vacio>Esta fase todavía no tiene tareas típicas. Dirección las define una vez en el centro de mando, en el flujo de este tipo de proyecto.</Vacio>
              <Link className="btn claro" href={R.nueva(f.proyecto_id)}>Repartir tareas a mano</Link>
            </Pantalla>
          );
        }
        const repartidas = prop.length - nuevas.length;
        return (
          <Pantalla titulo={titulo} sobre={proyecto?.nombre} atras={atras}>
            {porEspacio ? (
              <Formulario onEnviar={(fd) => { setEspaciosTexto(fd.espacios); }}>
                <label htmlFor="esp">Espacios del proyecto, separados por coma</label>
                <input id="esp" name="espacios" defaultValue={espaciosTexto} placeholder="Cocina, Baño principal, Sala" autoComplete="off" />
                <button className="btn claro">{espacios.length ? "Volver a proponer con estos espacios" : "Proponer una tarea por cada espacio"}</button>
              </Formulario>
            ) : null}
            {repartidas ? <Nota>{repartidas === 1 ? "Una de las tareas típicas ya está repartida" : `${repartidas} de las tareas típicas ya están repartidas`}: no se vuelve{repartidas === 1 ? "" : "n"} a proponer.</Nota> : null}
            {nuevas.length ? (
              <FormularioTipicas key={espaciosTexto} nuevas={nuevas} reparto={reparto} faseId={faseId} proyectoId={f.proyecto_id} ir={ir} />
            ) : <Vacio>Todas las tareas típicas de esta fase ya están repartidas.</Vacio>}
            <Link className="btn claro" href={atras}>{nuevas.length ? "Ahora no" : "Volver al proyecto"}</Link>
          </Pantalla>
        );
      }}
    </Carga>
  );
}

function FormularioTipicas({ nuevas, reparto, faseId, proyectoId, ir }: { nuevas: TareaTipica[]; reparto: Reparto; faseId: string; proyectoId: string; ir: (r: string, a?: ReturnType<typeof bien>) => void }) {
  const [quitadas, setQuitadas] = useState<number[]>([]);
  const visibles = nuevas.map((x, i) => [x, i] as const).filter(([, i]) => !quitadas.includes(i));
  return (
    <Formulario onEnviar={async (f) => {
      const filas = Object.keys(f).filter((k) => k.startsWith("pt:")).map((k) => k.slice(3)).map((i) => ({
        plantilla_tarea_id: f["pt:" + i], espacio: f["ep:" + i] || null, asignada_a: f["qu:" + i],
        fecha_inicio: f["in:" + i], fecha_compromiso: f["fe:" + i], dias_estimados: Number(f["es:" + i]), ...conRevision(f, i, f["qu:" + i]) }));
      if (!filas.length) throw new Error("No quedó ninguna tarea para entregar.");
      if (filas.some((x) => x.fecha_inicio > x.fecha_compromiso)) throw new Error("Hay una tarea que empieza después de su entrega.");
      const n = await pedir(sb().rpc("crear_tareas", { p_fase: faseId, p_tareas: filas }));
      const quienes = [...new Set(filas.map((x) => (reparto.opciones.find((o) => o[0] === x.asignada_a) || [])[1]).filter((x): x is string => !!x))];
      ir(R.proyecto(proyectoId), bien(`${n === 1 ? "Tarea entregada" : n + " tareas entregadas"} a ${lista(quienes)}: ya ${n === 1 ? "está" : "están"} en su día.`));
    }}>
      <div id="tareas">
        {visibles.map(([x, i]) => (
          <BloqueTipica key={i} i={i} x={x} reparto={reparto} quitar={nuevas.length > 1 ? () => setQuitadas((q) => [...q, i]) : undefined} />
        ))}
      </div>
      <button className="btn" id="entregar">{visibles.length > 1 ? `Entregar las ${visibles.length} tareas` : "Entregar la tarea"}</button>
    </Formulario>
  );
}

/** Una tarea típica propuesta: su propósito, cuándo, cuánto trabajo pide, a quién se le entrega y si se revisa. */
function BloqueTipica({ i, x, reparto, quitar }: { i: number; x: TareaTipica; reparto: Reparto; quitar?: () => void }) {
  const hoy = hoyIso();
  const est = x.dias_estimados == null ? null : Number(x.dias_estimados);
  const [quien, setQuien] = useState(reparto.opciones.length === 1 ? reparto.opciones[0][0] : "");
  const [inicio, setInicio] = useState(hoy);
  const [entrega, setEntrega] = useState(x.fecha_sugerida || "");
  const [dias, setDias] = useState(est == null ? "" : String(est));
  const [req, setReq] = useState(true);
  const [revisor, setRevisor] = useState("");
  const opciones: [string, string][] = (est && !ESFUERZO.some((e) => e[0] === est) ? [[est, enDias(est)] as [number, string], ...ESFUERZO] : ESFUERZO).map(([v, n]) => [String(v), n]);
  return (
    <fieldset className="tarea">
      <legend>{x.titulo}</legend>
      <p style={{ margin: "14px 0 0", color: "var(--tinta-3)", fontSize: ".9rem" }}>{x.proposito}</p>
      <input type="hidden" name={`pt:${i}`} value={x.plantilla_tarea_id} readOnly />
      <input type="hidden" name={`ep:${i}`} value={x.espacio || ""} readOnly />
      <div className="dos">
        <div><label htmlFor={`in${i}`}>Empieza</label><input id={`in${i}`} name={`in:${i}`} type="date" value={inicio} required onChange={(e) => setInicio(e.target.value)} /></div>
        <div><label htmlFor={`fe${i}`}>Entrega</label><input id={`fe${i}`} name={`fe:${i}`} type="date" min={hoy} value={entrega} required onChange={(e) => setEntrega(e.target.value)} /></div>
      </div>
      <label htmlFor={`es${i}`}>Trabajo que pide</label>
      <select id={`es${i}`} name={`es:${i}`} required value={dias} onChange={(e) => setDias(e.target.value)}><Opciones de={opciones} vacia="Escoja" /></select>
      <SelectResponsable i={i} reparto={reparto} ini={inicio} fin={entrega} pide={Number(dias) || 0} quien={quien} onChange={setQuien} />
      <SelectRevision i={i} revisores={reparto.revisores} req={req} setReq={setReq} revisor={revisor} setRevisor={setRevisor} />
      <Pista reparto={reparto} quien={quien} inicio={inicio} entrega={entrega} dias={dias} />
      {quitar ? <button type="button" className="enlace" onClick={quitar}>No entregar esta ahora</button> : null}
    </fieldset>
  );
}
