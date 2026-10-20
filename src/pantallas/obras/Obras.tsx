"use client";
// El tablero de todas las obras. La plata, las alertas y las frases las
// calcula la base (v_obra_tablero); aquí se pintan.
import Link from "next/link";
import { sb } from "@/lib/supabase/cliente";
import { pedir } from "@/lib/pedir";
import { useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import { fecha } from "@/lib/dominio/fechas";
import { pesos, uno } from "@/lib/dominio/texto";
import type { VObraTablero } from "@/lib/supabase/vistas";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Etiqueta, Fila, Frase, Vacio } from "@/componentes/ui/piezas";

export function Obras() {
  const yo = useYo();
  const estado = useDatos(() => pedir(sb().from("v_obra_tablero").select("*").order("estado").order("nombre").overrideTypes<VObraTablero[], { merge: false }>()), []);
  return (
    <Carga estado={estado} atras={R.dia}>
      {(obras) => {
        const conAlerta = obras.filter((o) => o.alerta), activas = obras.filter((o) => o.estado === "activo").length;
        const suma = (k: "costo_proyectado" | "por_pagar") => obras.reduce((s, o) => s + Number(o[k] || 0), 0);
        const frase = !obras.length ? "" : conAlerta.length ? `${conAlerta.length === 1 ? "Una obra tiene" : conAlerta.length + " obras tienen"} algo que mover hoy.` : "Todas las obras están al día.";
        return (
          <Pantalla titulo="Obras" sobre={obras.length ? uno(activas, "Una obra en curso", "obras en curso") : ""} pie={R.obras}>
            {frase ? <Frase>{frase}</Frase> : null}
            {yo.ve_dinero && obras.length > 1 ? <p style={{ color: "var(--tinta-3)" }}>Entre todas llevan {pesos(suma("costo_proyectado"))} en gastos y deben {pesos(suma("por_pagar"))}.</p> : null}
            {obras.map((o) => (
              <Fila key={o.id} href={R.obra(o.id)}>
                <b>{o.nombre}{o.estado === "pausado" ? <Etiqueta tono="n">En pausa</Etiqueta> : null}</b>
                {o.alerta ? <span><em>{o.alerta}</em></span> : null}
                <span>{o.lectura}</span>
                <span>{o.residente ? "Residente: " + o.residente : "Sin residente"} · {o.ultima_bitacora ? "última bitácora el " + fecha(o.ultima_bitacora) : "sin bitácora"}</span>
              </Fila>
            ))}
            {obras.length ? null : <Vacio>{yo.es_direccion ? "Todavía no hay obras. Abra la primera con el botón de abajo." : "Todavía no hace parte de ninguna obra."}</Vacio>}
            {yo.es_direccion ? <Link className="btn" href={R.nuevoProyecto("obra")}>Abrir una obra</Link> : null}
          </Pantalla>
        );
      }}
    </Carga>
  );
}
