"use client";
import { Contacto } from "@/pantallas/ventas/Contacto";
import { useParametro } from "@/lib/useParametro";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Vacio } from "@/componentes/ui/piezas";
import { R } from "@/lib/rutas";

export default function Pagina() {
  const id = useParametro("id");
  if (!id) return <Pantalla titulo="Contacto" atras={R.ventas}><Vacio>Falta saber qué contacto abrir.</Vacio></Pantalla>;
  return <Contacto key={id} id={id} />;
}
