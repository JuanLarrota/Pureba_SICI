"use client";
import { Reporte } from "@/pantallas/ventas/Reporte";
import { useParametro } from "@/lib/useParametro";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Vacio } from "@/componentes/ui/piezas";
import { R } from "@/lib/rutas";

export default function Pagina() {
  const cita = useParametro("cita");
  if (!cita) return <Pantalla titulo="Reporte de la cita" atras={R.ventas}><Vacio>Falta saber de qué cita es el reporte.</Vacio></Pantalla>;
  return <Reporte key={cita} citaId={cita} />;
}
