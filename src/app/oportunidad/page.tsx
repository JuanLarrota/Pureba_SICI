"use client";
import { Oportunidad } from "@/pantallas/ventas/Oportunidad";
import { useParametro } from "@/lib/useParametro";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Vacio } from "@/componentes/ui/piezas";
import { R } from "@/lib/rutas";

export default function Pagina() {
  const id = useParametro("id");
  if (!id) return <Pantalla titulo="Oportunidad" atras={R.ventas}><Vacio>Falta saber qué oportunidad abrir.</Vacio></Pantalla>;
  return <Oportunidad key={id} id={id} />;
}
