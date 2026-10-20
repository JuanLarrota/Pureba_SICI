"use client";
// Mientras la base responde, «Abriendo…»; si falla, la pantalla de error con
// el botón de intentar de nuevo; si no, lo que la pantalla pinta con los datos.
import type { ReactNode } from "react";
import type { Estado } from "@/lib/useDatos";
import { useSesion } from "@/lib/sesion";
import { decir } from "@/lib/pedir";
import { R } from "@/lib/rutas";
import { Pantalla } from "./Pantalla";
import { Boton } from "@/componentes/formularios/Boton";

export function Carga<T>({ estado, atras = R.dia, children }: { estado: Estado<T>; atras?: string; children: (datos: T) => ReactNode }) {
  const { recargar } = useSesion();
  if (estado.cargando) return <p className="espera">Abriendo…</p>;
  if (estado.datos === undefined) {
    return (
      <Pantalla titulo="No se pudo abrir" atras={atras}>
        <div className="error">{decir(estado.error)}</div>
        <Boton className="btn claro" accion={recargar}>Intentar de nuevo</Boton>
      </Pantalla>
    );
  }
  return <>{children(estado.datos)}</>;
}
