"use client";
// Mi impacto: las frases de las últimas cuatro semanas, sacadas de hechos.
// Ninguna cuenta tareas hechas ni horas: solo lo que otra persona asignó.
import { sb } from "@/lib/supabase/cliente";
import { pedir } from "@/lib/pedir";
import { useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import type { Indicador, IndicadorDetalle } from "@/lib/supabase/vistas";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Fila, Frase, Nota, Vacio } from "@/componentes/ui/piezas";

const CON_DETALLE = ["cumplio", "primera", "espera", "hitos", "margen", "revisiones"];
const ESTILO_TITULO = { margin: "0 0 4px", font: "600 .62rem var(--ui)", letterSpacing: ".2em", textTransform: "uppercase", color: "var(--taupe)" } as const;

export function Impacto({ abierto }: { abierto: string | null }) {
  const yo = useYo();
  const estado = useDatos(async () => {
    const ind = await pedir(sb().rpc("indicadores").overrideTypes<Indicador[], { merge: false }>());
    const detalle = abierto ? await pedir(sb().rpc("indicador_detalle", { p_indicador: abierto }).overrideTypes<IndicadorDetalle[], { merge: false }>()) : null;
    return { ind, detalle };
  }, [abierto, yo.persona_id]);

  return (
    <Carga estado={estado}>
      {({ ind, detalle }) => (
        <Pantalla titulo="Impacto" sobre="Últimas cuatro semanas" pie={R.impacto()}>
          {ind.length ? ind.map((i) => {
            const enlace = CON_DETALLE.includes(i.indicador) && i.suficiente;
            const cuerpo = <><span style={ESTILO_TITULO}>{i.titulo}</span><Frase>{i.frase}</Frase></>;
            return (
              <div key={i.indicador}>
                {enlace ? <Fila className="despliega" href={R.impacto(i.indicador === abierto ? null : i.indicador)} ariaExpanded={i.indicador === abierto}>{cuerpo}</Fila> : <div className="fila">{cuerpo}</div>}
                {i.indicador === abierto && detalle ? detalle.map((d, k) => (
                  <Fila key={k} style={{ paddingLeft: 16, borderLeft: "1px solid var(--tinta)" }}>
                    <b>{d.titulo}</b>
                    <span>{d.a_favor ? String(d.hecho) : <em>{String(d.hecho)}</em>}{d.excluida ? " · no cuenta: lo corrigió dirección" : ""}</span>
                  </Fila>
                )) : null}
              </div>
            );
          }) : <Vacio>Todavía no hay nada que decir.</Vacio>}
          <Nota>Ninguna frase cuenta tareas hechas ni horas trabajadas. Solo cuentan las tareas que le asignó otra persona.</Nota>
        </Pantalla>
      )}
    </Carga>
  );
}
