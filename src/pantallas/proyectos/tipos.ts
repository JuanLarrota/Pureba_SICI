// Lo que las cuatro vistas de un proyecto reciben ya normalizado: las
// relaciones embebidas de Supabase convertidas en campos planos.
import type { Yo } from "@/lib/sesion";
import type { AvanceFase } from "@/lib/dominio/plazo";

export interface ProyectoP {
  id: string;
  codigo: string;
  nombre: string;
  tipo: string;
  unidad: string;
  carpeta_drive: string | null;
}

export interface FaseP {
  id: string;
  fase: string;
  orden: number;
  estado: string;
  horas_cotizadas: number;
  entrega_cliente: string | null;
  fecha_compromiso: string | null;
  responsable_id: string | null;
}

export interface TareaP {
  id: string;
  titulo: string;
  estado: string;
  prioridad: string;
  fecha_inicio: string | null;
  fecha_compromiso: string | null;
  creada_en: string;
  terminada_en: string | null;
  dias_estimados: number | null;
  fase_id: string | null;
  asignada_a: string;
  requiere_revision: boolean;
  revisor_id: string | null;
  quien: string | null;        // el nombre de quien la tiene
}

export interface MiembroP { id: string; nombre: string; rol: string; papel: string }

export interface VistaProps {
  id: string;
  p: ProyectoP;
  fases: FaseP[];
  tareas: TareaP[];
  av: Map<string, AvanceFase>;
  hoy: string;
  yo: Yo;
  dirijo: boolean;
  repartir: React.ReactNode;
}

export const VISTAS_PROYECTO: [string, string][] = [["tablero", "Tablero"], ["lista", "Lista"], ["cronograma", "Cronograma"], ["ficha", "Ficha"]];

/** El nombre de la fase de una tarea, o «Sin fase». */
export const nombreFaseDe = (t: TareaP, fase: Map<string, FaseP>, nFase: (f: string) => string) => (fase.get(t.fase_id ?? "") ? nFase(fase.get(t.fase_id ?? "")!.fase) : "Sin fase");
export const quienDe = (t: TareaP) => t.quien || "Sin responsable";
