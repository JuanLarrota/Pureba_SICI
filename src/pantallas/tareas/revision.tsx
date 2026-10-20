"use client";
// Lo que comparten Repartir tareas, las típicas y Cambiar la tarea: el
// responsable escogido por lo que tiene libre en el tramo, y si la entrega pasa
// por revisión y a quién se le delega. Sigue a legado/app/app.js.
import type { Datos } from "@/componentes/formularios/Formulario";
import { enDias } from "@/lib/dominio/texto";
import { tramoLibre, type Carga } from "@/lib/dominio/plazo";

export interface Reparto {
  opciones: [string, string][];                 // a quién se le puede entregar
  porPersona: Map<string, Carga[]>;             // la carga de cada persona por semana
  espacio: (id: string) => number | null;       // lo que le queda libre esta semana
  revisores: [string, string][];                // a quién se le puede delegar la revisión, por nombre
  persona?: string | null;                      // con quién venía preescogido el formulario
}

type Tramo = ReturnType<typeof tramoLibre>;

/** Lo que una persona tiene libre en el tramo, al lado de su nombre. */
export const leeTramo = (t: Tramo | null, pide: number) =>
  !t ? "" : t.dias_habiles < 0.05 ? " · sin días hábiles en el tramo" : t.libre < -0.05 ? ` · ya pasada por ${enDias(-t.libre)}`
    : t.libre + 0.05 < pide ? ` · ${t.libre < 0.05 ? "sin días libres" : enDias(t.libre) + " libre" + (t.libre > 1 ? "s" : "")}, no le alcanza` : ` · ${enDias(t.libre)} libre${t.libre > 1 ? "s" : ""}`;

/** Primero el cuándo y el cuánto; con eso se ve quién tiene espacio en ese tramo. */
export function SelectResponsable({ i, reparto, ini, fin, pide, quien, onChange }: {
  i: number | string; reparto: Reparto; ini: string; fin: string; pide: number; quien: string; onChange: (id: string) => void;
}) {
  const listo = !!ini && !!fin && !!pide && ini <= fin;
  const filas = listo
    ? reparto.opciones.map(([id, n]) => [id, n, reparto.porPersona.has(id) ? tramoLibre(reparto.porPersona.get(id), ini, fin) : null] as const)
        .sort((a, b) => (b[2]?.libre ?? -99) - (a[2]?.libre ?? -99) || a[1].localeCompare(b[1]))
    : [];
  return (
    <>
      <label htmlFor={`qu${i}`}>Responsable, con sus días libres en ese tramo</label>
      {listo ? (
        <select id={`qu${i}`} name={`qu:${i}`} required value={filas.some(([id]) => id === quien) ? quien : ""} onChange={(e) => onChange(e.target.value)}>
          {reparto.opciones.length > 1 ? <option value="">Escoja</option> : null}
          {filas.map(([id, n, t]) => <option key={id} value={id}>{n + leeTramo(t, pide)}</option>)}
        </select>
      ) : (
        <select id={`qu${i}`} name={`qu:${i}`} required disabled value="" onChange={() => {}}>
          <option value="">{ini && fin && ini > fin ? "La entrega va antes del inicio" : "Primero las fechas y el trabajo que pide"}</option>
        </select>
      )}
    </>
  );
}

/** Si la entrega pasa por revisión y a quién se le delega. Sin revisión, la tarea se cierra cuando su responsable la entrega. */
export function SelectRevision({ i, revisores, req, setReq, revisor, setRevisor }: {
  i: number | string; revisores: [string, string][]; req: boolean; setReq: (v: boolean) => void; revisor: string; setRevisor: (v: string) => void;
}) {
  return (
    <div className="dos">
      <div>
        <label htmlFor={`rr${i}`}>Requiere revisión</label>
        <select id={`rr${i}`} name={`rr:${i}`} value={req ? "si" : "no"} onChange={(e) => { const no = e.target.value === "no"; setReq(!no); if (no) setRevisor(""); }}>
          <option value="si">Sí</option>
          <option value="no">No, se cierra al entregarla</option>
        </select>
      </div>
      <div>
        <label htmlFor={`rv${i}`}>Revisa</label>
        <select id={`rv${i}`} name={`rv:${i}`} required disabled={!req} value={revisor} onChange={(e) => setRevisor(e.target.value)}>
          <option value="">{req ? "Escoja" : "Nadie"}</option>
          {revisores.map(([id, n]) => <option key={id} value={id}>{n}</option>)}
        </select>
      </div>
    </div>
  );
}

/** Lo que se guarda de la revisión en la tarea, con las dos reglas que la pantalla sí puede revisar antes de ir a la base. */
export const conRevision = (f: Datos, i: number | string, quien: string | undefined) => {
  const req = f["rr:" + i] !== "no", rv = req ? f["rv:" + i] || null : null;
  if (req && !rv) throw new Error("Falta escoger quién revisa.");
  if (rv && rv === quien) throw new Error("Quien revisa no puede ser la misma persona que entrega la tarea.");
  return { requiere_revision: req, revisor_id: rv };
};
