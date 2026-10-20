"use client";
import { Tipicas } from "@/pantallas/tareas/Tipicas";
import { useParametro } from "@/lib/useParametro";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Vacio } from "@/componentes/ui/piezas";
import { R } from "@/lib/rutas";

export default function Pagina() {
  const fase = useParametro("fase");
  if (!fase) return <Pantalla titulo="Tareas de la fase" atras={R.proyectos}><Vacio>Falta saber de qué fase.</Vacio></Pantalla>;
  return <Tipicas key={fase} faseId={fase} />;
}
