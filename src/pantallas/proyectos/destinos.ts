// A qué columnas puede llevar cada persona una tarea del tablero. Arrastrar una
// tarjeta es lo mismo que oprimir el botón en la tarea, con las mismas reglas:
// quien la tiene la empieza o la entrega; quien la revisa la aprueba o la devuelve.
import type { Yo } from "@/lib/sesion";

export interface TareaMovible { estado: string; asignada_a: string; requiere_revision?: boolean | null; revisor_id?: string | null }

export function destinos(t: TareaMovible, pid: string, yo: Yo): string[] {
  const mia = t.asignada_a === yo.persona_id, sinRevision = t.requiere_revision === false, entrega = sinRevision ? "terminada" : "en_revision";
  const reviso = !mia && !sinRevision && (t.revisor_id ? t.revisor_id === yo.persona_id : yo.revisa.includes(pid));
  // Dirección mueve todas las tareas (Felipe, 19-10-2026). Lo único que no salta es la
  // revisión que se fijó al crear la tarea: a «Terminadas» llega sola si no requiere
  // revisión; si la requiere, la aprueba quien la revisa (si es quien dirige, al soltarla aquí).
  if (yo.es_direccion || (pid && yo.dirige.includes(pid))) {
    if (t.estado === "terminada" && !yo.es_direccion) return [];   // reabrir una terminada es de dirección
    const a = ["asignada", "en_curso"];
    if (!sinRevision) a.push("en_revision");
    if (sinRevision || (reviso && t.estado === "en_revision")) a.push("terminada");
    if (reviso && t.estado === "en_revision") a.push("con_observaciones");
    return a.filter((e) => e !== t.estado);
  }
  if (mia) return ({ asignada: ["en_curso", entrega], en_curso: ["asignada", entrega], con_observaciones: [entrega], en_revision: ["en_curso"] } as Record<string, string[]>)[t.estado] || [];
  if (reviso && t.estado === "en_revision") return ["terminada", "con_observaciones"];
  return [];
}
