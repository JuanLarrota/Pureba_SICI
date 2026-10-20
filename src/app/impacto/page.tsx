"use client";
import { Impacto } from "@/pantallas/equipo/Impacto";
import { useParametro } from "@/lib/useParametro";

export default function Pagina() {
  const abierto = useParametro("abierto");
  return <Impacto key={abierto ?? ""} abierto={abierto} />;
}
