"use client";
import { Embudo } from "@/pantallas/ventas/Embudo";
import { useParametro } from "@/lib/useParametro";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Vacio } from "@/componentes/ui/piezas";
import { R } from "@/lib/rutas";

export default function Pagina() {
  const linea = useParametro("linea"), etapa = useParametro("etapa");
  if (!linea || !etapa) return <Pantalla titulo="Embudo" atras={R.ventas}><Vacio>Falta saber qué etapa abrir.</Vacio></Pantalla>;
  return <Embudo key={`${linea}|${etapa}`} linea={linea} etapa={etapa} />;
}
