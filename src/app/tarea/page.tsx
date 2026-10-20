"use client";
import { Tarea } from "@/pantallas/tareas/Tarea";
import { useParametro } from "@/lib/useParametro";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Vacio } from "@/componentes/ui/piezas";
import { R } from "@/lib/rutas";

export default function Pagina() {
  const id = useParametro("id");
  if (!id) return <Pantalla titulo="Tarea" atras={R.dia}><Vacio>Falta saber qué tarea abrir.</Vacio></Pantalla>;
  return <Tarea id={id} />;
}
