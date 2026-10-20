// Consultas que usan varias pantallas.
import { sb } from "@/lib/supabase/cliente";
import { pedir } from "@/lib/pedir";

/** El equipo de un proyecto (sin quien solo observa) más dirección: a quién se le puede entregar una tarea. */
export async function asignables(pid: string): Promise<Map<string, string>> {
  const [equipo, direccion] = await Promise.all([
    pedir(sb().from("acceso_proyecto").select("papel,persona(id,nombre)").eq("proyecto_id", pid).neq("papel", "observa")),
    pedir(sb().from("persona").select("id,nombre").in("rol", ["socio", "director"]).eq("activo", true).eq("es_interno", true)),
  ]);
  const pares: [string, string][] = [];
  for (const e of equipo) { const p = e.persona as unknown as { id: string; nombre: string } | null; if (p) pares.push([p.id, p.nombre]); }
  for (const p of direccion) pares.push([p.id, p.nombre]);
  return new Map(pares);
}

/** Las personas internas activas, por nombre. */
export async function gente(): Promise<{ id: string; nombre: string }[]> {
  return pedir(sb().from("persona").select("id,nombre").eq("es_interno", true).eq("activo", true).order("nombre"));
}

/** Los nombres de unas personas, por id. */
export async function nombresDe(ids: (string | null | undefined)[]): Promise<Map<string, string>> {
  const unicos = [...new Set(ids.filter((x): x is string => !!x))];
  if (!unicos.length) return new Map();
  const filas = await pedir(sb().from("persona").select("id,nombre").in("id", unicos));
  return new Map(filas.map((p) => [p.id, p.nombre]));
}

/** Los asignables ordenados: primero quien más espacio tiene esta semana, luego por nombre. */
export const ordenarPorEspacio = (gente: Map<string, string>, espacio: (id: string) => number | null): [string, string][] =>
  [...gente].sort((a, b) => (espacio(b[0]) ?? -99) - (espacio(a[0]) ?? -99) || a[1].localeCompare(b[1]));
