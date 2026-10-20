// «Ver como»: la ficha que tendría alguien con cada papel, calculada con las mismas
// reglas que la función mi_sesion de la base (supabase/migrations/…prestamos_y_socios).
// Solo cambia lo que la pantalla muestra; los permisos de la base siguen siendo los de
// quien entró, así que sirve para ver cómo lo ve cada quien, no para probar permisos.
import type { Yo } from "@/lib/sesion";

export const VISTAS: { rol: string; nombre: string }[] = [
  { rol: "socio", nombre: "Socio" },
  { rol: "director", nombre: "Dirección" },
  { rol: "arquitecto", nombre: "Arquitecto" },
  { rol: "practicante", nombre: "Practicante" },
  { rol: "residente", nombre: "Residente de obra" },
  { rol: "mercadeo", nombre: "Mercadeo" },
  { rol: "financiero", nombre: "Financiero" },
];

const esta = (rol: string, lista: string[]) => lista.includes(rol);

/** La ficha de quien entró, vista con el papel `rol`. Las listas por proyecto quedan vacías. */
export function comoRol(real: Yo, rol: string): Yo {
  const direccion = esta(rol, ["socio", "director"]);
  return {
    ...real,
    nombre: VISTAS.find((v) => v.rol === rol)?.nombre ?? rol,
    rol,
    es_direccion: direccion,
    es_socio: rol === "socio",
    asigna: direccion || rol === "arquitecto",
    dirige: [],
    revisa: [],
    registra: [],
    vende: esta(rol, ["socio", "director", "mercadeo"]),
    obras: esta(rol, ["socio", "director", "financiero", "residente"]),
    ve_dinero: esta(rol, ["socio", "director", "financiero"]),
    ve_reservado: rol === "socio",
  };
}
