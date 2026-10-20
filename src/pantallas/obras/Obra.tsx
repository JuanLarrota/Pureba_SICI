"use client";
// La ficha de una obra, con sus espacios en pestañas. Quién registra y quién
// aprueba lo decide la base: el residente registra en su obra, dirección aprueba.
import Link from "next/link";
import { useEffect, type ReactNode } from "react";
import { sb } from "@/lib/supabase/cliente";
import { decir, pedirUno } from "@/lib/pedir";
import { useSesion, useYo } from "@/lib/sesion";
import { useDatos, type Estado } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import { SECCION_OBRA } from "@/lib/dominio/catalogos";
import type { VObraTablero } from "@/lib/supabase/vistas";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Boton } from "@/componentes/formularios/Boton";
import { Vacio } from "@/componentes/ui/piezas";
import { Resumen } from "./Resumen";
import { Gastos } from "./Gastos";
import { Flujo } from "./Flujo";
import { Documentos } from "./Documentos";
import { Pendientes } from "./Pendientes";
import { Sitio } from "./Sitio";

export interface PropsSeccion { o: VObraTablero; registra: boolean }

const SECCIONES: Record<string, (p: PropsSeccion) => ReactNode> = { resumen: Resumen, gastos: Gastos, flujo: Flujo, documentos: Documentos, pendientes: Pendientes, sitio: Sitio };

export function Obra({ id, seccion }: { id: string; seccion: string | null }) {
  const yo = useYo();
  const sec = seccion && SECCIONES[seccion] ? seccion : "resumen";
  const estado = useDatos(() => pedirUno(sb().from("v_obra_tablero").select("*").eq("id", id).maybeSingle().overrideTypes<VObraTablero, { merge: false }>()), [id]);
  useEffect(() => {
    document.querySelector('.pestanas [aria-current="page"]')?.scrollIntoView({ inline: "center", block: "nearest" });
  }, [sec, estado.cargando]);
  return (
    <Carga estado={estado} atras={R.obras}>
      {(o) => {
        if (!o) return <Pantalla titulo="Obra" atras={R.obras} pie={R.obras}><Vacio>Esa obra no existe, ya terminó o usted no hace parte de ella.</Vacio></Pantalla>;
        const Seccion = SECCIONES[sec];
        return (
          <Pantalla titulo={o.nombre} sobre={`Obra · ${o.codigo}`} atras={R.obras} pie={R.obras} pestanas={
            <nav className="pestanas" aria-label="Espacios de la obra">
              <div>
                {SECCION_OBRA.map(([k, n]) => <Link key={k} href={R.obra(id, k)} aria-current={k === sec ? "page" : undefined}>{n}</Link>)}
              </div>
            </nav>}>
            <Seccion key={sec} o={o} registra={yo.registra.includes(id)} />
          </Pantalla>
        );
      }}
    </Carga>
  );
}

/** Lo que una sección le pide a la base: «Abriendo…», el error con su botón, o el contenido. Sin cabecera propia: la pone la obra. */
export function CargaSeccion<T>({ estado, children }: { estado: Estado<T>; children: (datos: T) => ReactNode }) {
  const { recargar } = useSesion();
  if (estado.cargando) return <p className="espera">Abriendo…</p>;
  if (estado.datos === undefined) {
    return (
      <>
        <div className="error">{decir(estado.error)}</div>
        <Boton className="btn claro" accion={recargar}>Intentar de nuevo</Boton>
      </>
    );
  }
  return <>{children(estado.datos)}</>;
}
