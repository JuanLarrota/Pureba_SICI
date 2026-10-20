// Lo que el centro de mando le pide a la base, con sus relaciones embebidas.
import type { Carga } from "@/lib/dominio/plazo";

export interface TareaMando {
  id: string;
  titulo: string;
  estado: string;
  prioridad: string;
  fecha_inicio: string | null;
  fecha_compromiso: string | null;
  dias_estimados: number | null;
  terminada_en: string | null;
  creada_en: string;
  asignada_a: string;
  proyecto_id: string;
  proyecto: { nombre: string } | null;
  fase: { fase: string } | null;
}

export interface PersonaMando { id: string; nombre: string; rol: string; profesion: { nombre: string } | null }
export interface AccesoMando { persona_id: string; proyecto_id: string; papel: string }
export interface ProyectoMando { id: string; codigo: string; nombre: string; unidad: string; tipo: string; fase: string | null }
export interface FaseMando {
  id: string;
  proyecto_id: string;
  fase: string;
  orden: number;
  estado: string;
  fecha_compromiso: string | null;
  entrega_cliente: string | null;
  responsable_id: string | null;
  dias_habiles_plazo: number | null;
}

export interface PlantillaTareaMando { id: string; titulo: string; orden: number; activa: boolean | null; por_espacio: boolean | null; dias_plazo: number | null; dias_estimados: number | null }
export interface PlantillaFaseMando {
  id: string;
  fase: string;
  orden: number;
  opcional: boolean | null;
  entrega_cliente: string | null;
  exige_chequeo: boolean | null;
  exige_aprobacion_cliente: boolean | null;
  exige_dedicacion: boolean | null;
  dias_habiles_plazo: number | null;
  responsable_papel: string | null;
  plantilla_tarea: PlantillaTareaMando[] | null;
}
export interface PlantillaMando { id: string; nombre: string; tipo: string; descripcion: string | null; plantilla_fase: PlantillaFaseMando[] | null }

export interface ItemLista { id: string; orden: number; texto: string; tipo: string; opciones: string[] | null; obligatorio: boolean | null; activo: boolean | null }
export interface ListaCierre { id: string; plantilla_id: string | null; fase: string; version: number; lista_chequeo_item: ItemLista[] | null }

/** Una persona del equipo con su carga y lo que tiene abierto. */
export interface Gente { id: string; sem: Carga[]; nombre: string; ficha: PersonaMando | undefined; suyas: TareaMando[] }

/** Lo que una ficha necesita para nombrar y enlazar. */
export interface Contexto {
  hoy: string;
  nom: (id: string | null | undefined) => string;
  vence: (t: TareaMando) => boolean;
}
