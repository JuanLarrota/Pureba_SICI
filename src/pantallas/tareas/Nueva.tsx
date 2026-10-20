"use client";
// Repartir tareas: quien dirige arma una o varias tareas y se las entrega a su
// responsable. Primero el cuándo y el cuánto; con eso se ve quién tiene espacio
// en ese tramo. Cada tarea dice si pasa por revisión y quién la revisa.
import { useState } from "react";
import { sb } from "@/lib/supabase/cliente";
import { bien, pedir } from "@/lib/pedir";
import { useSesion, useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { asignables, ordenarPorEspacio } from "@/lib/consultas";
import { R } from "@/lib/rutas";
import { SEMANAS } from "@/lib/config";
import { PRIORIDAD } from "@/lib/dominio/catalogos";
import { hoyIso } from "@/lib/dominio/fechas";
import { ESFUERZO, lista, titulo } from "@/lib/dominio/texto";
import { cargaPorPersona, libres, type Carga as CargaSemana } from "@/lib/dominio/plazo";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Formulario, Opciones } from "@/componentes/formularios/Formulario";
import { Vacio } from "@/componentes/ui/piezas";
import { Pista } from "./Pista";
import { conRevision, SelectResponsable, SelectRevision, type Reparto } from "./revision";

export function Nueva({ proyectoId, personaId }: { proyectoId: string | null; personaId: string | null }) {
  const yo = useYo();
  const { ir } = useSesion();
  const estado = useDatos(async () => {
    const proyectos = (await pedir(sb().from("proyecto").select("id,nombre").eq("estado", "activo").order("nombre"))).filter((p) => yo.registra.includes(p.id));
    if (!proyectos.length) return null;
    const pid = proyectos.some((p) => p.id === proyectoId) ? proyectoId! : proyectos[0].id;
    const [gente, abiertas, fases, carga] = await Promise.all([
      asignables(pid),
      pedir(sb().from("tarea_diseno").select("id,titulo").eq("proyecto_id", pid).neq("estado", "terminada").order("titulo")),
      pedir(sb().from("proyecto_fase").select("id,fase,estado").eq("proyecto_id", pid).order("orden")),
      pedir(sb().rpc("carga_semanal", { p_semanas: SEMANAS }).overrideTypes<CargaSemana[], { merge: false }>()),
    ]);
    const puedeAsignar = yo.asigna || yo.dirige.includes(pid), porPersona = cargaPorPersona(carga);
    const espacio = (id: string) => (porPersona.has(id) ? libres(porPersona.get(id)![0]) : null);
    // Primero quien más espacio tiene esta semana.
    const opciones: [string, string][] = puedeAsignar ? ordenarPorEspacio(gente, espacio) : [[yo.persona_id, yo.nombre]];
    const persona = opciones.some((o) => o[0] === personaId) ? personaId : null;
    const reparto: Reparto = { opciones, porPersona, espacio, persona, revisores: [...gente].sort((a, b) => a[1].localeCompare(b[1])) };
    return { proyectos, pid, abiertas, fases, puedeAsignar, reparto, persona };
  }, [proyectoId, personaId, yo.persona_id]);

  return (
    <Carga estado={estado}>
      {(d) => {
        if (!d) return <Pantalla titulo="Nueva tarea" atras={R.dia}><Vacio>Todavía no hace parte del equipo de ningún proyecto. Dirección lo agrega desde la ficha del proyecto.</Vacio></Pantalla>;
        return <FormularioNueva key={d.pid} {...d} ir={ir} yoId={yo.persona_id} />;
      }}
    </Carga>
  );
}

interface DatosNueva {
  proyectos: { id: string; nombre: string }[];
  pid: string;
  abiertas: { id: string; titulo: string }[];
  fases: { id: string; fase: string; estado: string }[];
  puedeAsignar: boolean;
  reparto: Reparto;
  persona: string | null;
}

function FormularioNueva({ proyectos, pid, abiertas, fases, puedeAsignar, reparto, persona, ir, yoId }: DatosNueva & { ir: (r: string, a?: ReturnType<typeof bien>) => void; yoId: string }) {
  const [bloques, setBloques] = useState<number[]>([0]);
  const [n, setN] = useState(1);
  const enCurso = fases.find((x) => x.estado === "en_curso");
  const hoy = hoyIso();
  return (
    <Pantalla titulo={puedeAsignar ? "Repartir tareas" : "Nueva tarea"} atras={puedeAsignar ? R.equipo : R.dia}>
      <Formulario onEnviar={async (f) => {
        const filas = Object.keys(f).filter((k) => k.startsWith("ti:")).map((k) => k.slice(3)).map((i) => ({
          proyecto_id: f.proyecto, fase_id: f.fase || null, titulo: f["ti:" + i].trim(), asignada_a: f["qu:" + i], asignada_por: yoId,
          fecha_inicio: f["in:" + i], fecha_compromiso: f["fe:" + i], dias_estimados: Number(f["es:" + i]), prioridad: f["pi:" + i] as "normal", bloqueada_por: f["de:" + i] || null,
          ...conRevision(f, i, f["qu:" + i]) }));
        const torcida = filas.find((x) => x.fecha_inicio > x.fecha_compromiso);
        if (torcida) throw new Error(`«${torcida.titulo}» no puede empezar después de su entrega.`);
        await pedir(sb().from("tarea_diseno").insert(filas));
        const quienes = [...new Set(filas.map((x) => (reparto.opciones.find((o) => o[0] === x.asignada_a) || [])[1]).filter((x): x is string => !!x))];
        const propia = filas.every((x) => x.asignada_a === yoId);
        ir(puedeAsignar && !propia ? R.equipo : R.dia, bien(propia ? (filas.length > 1 ? "Tareas creadas." : "Tarea creada.")
          : `${filas.length > 1 ? filas.length + " tareas entregadas" : "Tarea entregada"} a ${lista(quienes)}: ya ${filas.length > 1 ? "están" : "está"} en su día.`));
      }}>
        <label htmlFor="pr">Proyecto</label>
        <select id="pr" name="proyecto" defaultValue={pid} onChange={(e) => ir(R.nueva(e.target.value))}>
          <Opciones de={proyectos.map((p) => [p.id, p.nombre])} />
        </select>
        {fases.length ? (
          <>
            <label htmlFor="fa">Fase</label>
            <select id="fa" name="fase" defaultValue={enCurso?.id || ""}><Opciones de={fases.map((x) => [x.id, titulo(x.fase.replace(/_/g, " "))])} vacia="Sin fase" /></select>
          </>
        ) : null}
        {puedeAsignar ? null : <p className="nota">Puede crearse tareas propias. Entregarle una tarea a otra persona es de quien dirige el proyecto.</p>}
        <div id="tareas">
          {bloques.map((i) => (
            <BloqueTarea key={i} i={i} reparto={reparto} persona={persona} abiertas={abiertas} hoy={hoy}
              quitar={i ? () => setBloques((b) => b.filter((x) => x !== i)) : undefined} />
          ))}
        </div>
        {puedeAsignar ? <button type="button" className="btn claro" onClick={() => { setBloques((b) => [...b, n]); setN(n + 1); }}>Agregar otra tarea</button> : null}
        <button className="btn" id="entregar">{puedeAsignar ? (bloques.length > 1 ? `Entregar las ${bloques.length} tareas` : "Entregar la tarea") : "Crear la tarea"}</button>
      </Formulario>
    </Pantalla>
  );
}

/** Una tarea del formulario: qué, cuándo, cuánto trabajo pide, quién, si se revisa y de qué depende. */
export function BloqueTarea({ i, reparto, persona, abiertas, hoy, quitar }: { i: number; reparto: Reparto; persona: string | null; abiertas: { id: string; titulo: string }[]; hoy: string; quitar?: () => void }) {
  const [quien, setQuien] = useState(persona || (reparto.opciones.length === 1 ? reparto.opciones[0][0] : ""));
  const [inicio, setInicio] = useState(hoy);
  const [entrega, setEntrega] = useState("");
  const [dias, setDias] = useState("");
  const [req, setReq] = useState(true);
  const [revisor, setRevisor] = useState("");
  return (
    <fieldset className="tarea">
      <legend>Tarea</legend>
      <label htmlFor={`ti${i}`}>Qué hay que entregar</label>
      <input id={`ti${i}`} name={`ti:${i}`} required minLength={4} autoComplete="off" autoFocus={i > 0} />
      <div className="dos">
        <div><label htmlFor={`in${i}`}>Empieza</label><input id={`in${i}`} name={`in:${i}`} type="date" value={inicio} required onChange={(e) => setInicio(e.target.value)} /></div>
        <div><label htmlFor={`fe${i}`}>Entrega</label><input id={`fe${i}`} name={`fe:${i}`} type="date" min={hoy} value={entrega} required onChange={(e) => setEntrega(e.target.value)} /></div>
        <div><label htmlFor={`es${i}`}>Trabajo que pide</label>
          <select id={`es${i}`} name={`es:${i}`} required value={dias} onChange={(e) => setDias(e.target.value)}><Opciones de={ESFUERZO.map(([v, n]) => [String(v), n])} vacia="Escoja" /></select></div>
        <div><label htmlFor={`pi${i}`}>Prioridad</label><select id={`pi${i}`} name={`pi:${i}`} defaultValue="normal"><Opciones de={PRIORIDAD} /></select></div>
      </div>
      <SelectResponsable i={i} reparto={reparto} ini={inicio} fin={entrega} pide={Number(dias) || 0} quien={quien} onChange={setQuien} />
      <SelectRevision i={i} revisores={reparto.revisores} req={req} setReq={setReq} revisor={revisor} setRevisor={setRevisor} />
      {abiertas.length ? (
        <>
          <label htmlFor={`de${i}`}>Depende de (opcional)</label>
          <select id={`de${i}`} name={`de:${i}`} defaultValue=""><Opciones de={abiertas.map((a) => [a.id, a.titulo])} vacia="De ninguna" /></select>
        </>
      ) : null}
      <Pista reparto={reparto} quien={quien} inicio={inicio} entrega={entrega} dias={dias} />
      {quitar ? <button type="button" className="enlace" onClick={quitar}>Quitar esta tarea</button> : null}
    </fieldset>
  );
}
