// Las rutas de la aplicación, en un solo lugar. Como el sitio se exporta
// estático, los identificadores van en la consulta (?id=) y no en la ruta.
const q = (pares: Record<string, string | null | undefined>) => {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries(pares)) if (v) p.set(k, v);
  const s = p.toString();
  return s ? `?${s}` : "";
};

export const R = {
  dia: "/",
  tarea: (id: string) => `/tarea/${q({ id })}`,
  nueva: (proyecto?: string | null, persona?: string | null) => `/nueva/${q({ proyecto, persona })}`,
  revisar: "/revisar/",
  proyectos: "/proyectos/",
  proyecto: (id: string, vista?: string | null) => `/proyecto/${q({ id, vista })}`,
  nuevoProyecto: (tipo?: string | null) => `/nuevo-proyecto/${q({ tipo })}`,
  obras: "/obras/",
  obra: (id: string, seccion?: string | null) => `/obra/${q({ id, seccion })}`,
  equipo: "/equipo/",
  personas: "/personas/",
  mando: "/mando/",
  tipicas: (fase: string) => `/tipicas/${q({ fase })}`,
  cierre: (fase: string) => `/cierre/${q({ fase })}`,
  registro: "/registro/",
  impacto: (abierto?: string | null) => `/impacto/${q({ abierto })}`,
  ventas: "/ventas/",
  embudo: (linea: string, etapa: string) => `/embudo/${q({ linea, etapa })}`,
  oportunidad: (id: string) => `/oportunidad/${q({ id })}`,
  reporte: (cita: string) => `/reporte/${q({ cita })}`,
  contacto: (id: string) => `/contacto/${q({ id })}`,
  contactoNuevo: "/contacto-nuevo/",
  tarifas: "/tarifas/",
  yo: "/yo/",
  clave: "/clave/",
};

/** La misma ruta escrita siempre igual, para saber si dos rutas son la misma pantalla. */
export const clave = (ruta: string) => {
  const [path, search = ""] = ruta.split("?");
  const p = path.replace(/\/+$/, "") || "/";
  return search ? `${p}?${search}` : p;
};
