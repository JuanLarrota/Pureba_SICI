"use client";
import { Obra } from "@/pantallas/obras/Obra";
import { useParametro } from "@/lib/useParametro";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Vacio } from "@/componentes/ui/piezas";
import { R } from "@/lib/rutas";

export default function Pagina() {
  const id = useParametro("id"), seccion = useParametro("seccion");
  if (!id) return <Pantalla titulo="Obra" atras={R.obras} pie={R.obras}><Vacio>Falta saber qué obra abrir.</Vacio></Pantalla>;
  return <Obra key={id} id={id} seccion={seccion} />;
}
