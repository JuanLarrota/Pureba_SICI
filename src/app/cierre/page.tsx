"use client";
import { Cierre } from "@/pantallas/tareas/Cierre";
import { useParametro } from "@/lib/useParametro";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Vacio } from "@/componentes/ui/piezas";
import { R } from "@/lib/rutas";

export default function Pagina() {
  const fase = useParametro("fase");
  if (!fase) return <Pantalla titulo="Cierre de fase" atras={R.proyectos}><Vacio>Falta saber qué fase cerrar.</Vacio></Pantalla>;
  return <Cierre key={fase} faseId={fase} />;
}
