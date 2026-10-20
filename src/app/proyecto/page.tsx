"use client";
import { Proyecto } from "@/pantallas/proyectos/Proyecto";
import { useParametro } from "@/lib/useParametro";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Vacio } from "@/componentes/ui/piezas";
import { R } from "@/lib/rutas";

export default function Pagina() {
  const id = useParametro("id"), vista = useParametro("vista");
  if (!id) return <Pantalla titulo="Proyecto" atras={R.proyectos}><Vacio>Falta saber qué proyecto abrir.</Vacio></Pantalla>;
  return <Proyecto key={id} id={id} vista={vista} />;
}
