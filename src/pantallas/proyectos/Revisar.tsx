"use client";
// Lo que espera revisión de quien dirige o revisa, en el orden en que se pidió.
// Una revisión delegada en alguien solo le aparece a esa persona (R3).
import { sb } from "@/lib/supabase/cliente";
import { pedir } from "@/lib/pedir";
import { useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import { titulo } from "@/lib/dominio/texto";
import type { VColaRevision } from "@/lib/supabase/vistas";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Fila, Marca, Vacio } from "@/componentes/ui/piezas";

export function Revisar() {
  const yo = useYo();
  const estado = useDatos(async () =>
    (await pedir(sb().from("v_cola_revision").select("*").order("revision_pedida_en").overrideTypes<VColaRevision[], { merge: false }>()))
      .filter((c) => !c.revisor_id || c.revisor_id === yo.persona_id), [yo.persona_id]);
  return (
    <Carga estado={estado}>
      {(cola) => (
        <Pantalla titulo="Revisar" pie={R.revisar} porRevisar={cola.length}>
          {cola.length ? cola.map((c) => (
            <Fila key={c.tarea_id} href={R.tarea(c.tarea_id)}>
              <b>{c.titulo}<Marca prioridad={c.prioridad} /></b>
              <span>{titulo(c.proyecto)} · {c.fuera_de_plazo ? <em>{c.lectura}</em> : c.lectura}</span>
            </Fila>
          )) : <Vacio>Nada espera revisión.</Vacio>}
        </Pantalla>
      )}
    </Carga>
  );
}
