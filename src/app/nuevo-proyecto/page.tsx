"use client";
import { NuevoProyecto } from "@/pantallas/proyectos/NuevoProyecto";
import { useParametro } from "@/lib/useParametro";

export default function Pagina() {
  const tipo = useParametro("tipo");
  return <NuevoProyecto key={tipo ?? ""} tipo={tipo} />;
}
