"use client";
import { Nueva } from "@/pantallas/tareas/Nueva";
import { useParametro } from "@/lib/useParametro";

export default function Pagina() {
  const proyecto = useParametro("proyecto"), persona = useParametro("persona");
  return <Nueva key={`${proyecto}|${persona}`} proyectoId={proyecto} personaId={persona} />;
}
