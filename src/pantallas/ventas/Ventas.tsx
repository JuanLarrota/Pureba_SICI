"use client";
// El embudo se trabaja en frases y escogiendo. Las reglas las pone la base:
// sin siguiente paso no hay oportunidad abierta (V1), sin reunión de
// presentación no sale una cotización (V2) y sin el reporte de la cita no se
// cotiza (V3). Esta pantalla solo muestra lo que toca hoy y deja hacerlo.
import Link from "next/link";
import { Fragment } from "react";
import { sb } from "@/lib/supabase/cliente";
import { pedir, pedirUno } from "@/lib/pedir";
import { useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import { ABIERTAS, ETAPA, LINEA } from "@/lib/dominio/catalogos";
import { fecha, hoyIso } from "@/lib/dominio/fechas";
import { pesos, uno } from "@/lib/dominio/texto";
import type { VEmbudoVentas, VRitmoVentas, VVentasHoy } from "@/lib/supabase/vistas";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Etiqueta, Fila, Frase, Grupo, Vacio } from "@/componentes/ui/piezas";

export function Ventas() {
  const yo = useYo();
  const estado = useDatos(async () => {
    const [hoy, embudo, ritmo] = await Promise.all([
      pedir(sb().from("v_ventas_hoy").select("*").order("orden").overrideTypes<VVentasHoy[], { merge: false }>()),
      pedir(sb().from("v_embudo_ventas").select("*").overrideTypes<VEmbudoVentas[], { merge: false }>()),
      pedirUno(sb().from("v_ritmo_ventas").select("lectura").maybeSingle().overrideTypes<VRitmoVentas, { merge: false }>()),
    ]);
    const mios = hoy.filter((x) => !x.persona_id || x.persona_id === yo.persona_id);
    const otros = yo.es_direccion ? hoy.filter((x) => x.persona_id && x.persona_id !== yo.persona_id) : [];
    const nombres = new Map(otros.length
      ? (await pedir(sb().from("persona").select("id,nombre").in("id", [...new Set(otros.map((x) => x.persona_id as string))]))).map((p) => [p.id, p.nombre])
      : []);
    return { mios, otros, embudo, ritmo, nombres };
  }, [yo.persona_id]);

  const destino = (x: VVentasHoy) => x.que === "reporte_cita" && x.cita_id ? R.reporte(x.cita_id) : x.oportunidad_id ? R.oportunidad(x.oportunidad_id) : R.contacto(x.lead_id || "");
  const fila = (x: VVentasHoy, quien?: string) => (
    <Fila key={`${x.que}-${x.lead_id}-${x.oportunidad_id}-${x.cita_id}`} href={destino(x)}>
      <b>{x.nombre}{!x.persona_id ? <Etiqueta tono="a">Sin dueño</Etiqueta> : null}</b>
      <span>{quien ? `${quien} · ` : ""}{x.urgente ? <em>{x.lectura}</em> : x.lectura}</span>
    </Fila>
  );

  return (
    <Carga estado={estado}>
      {({ mios, otros, embudo, ritmo, nombres }) => {
        const etapas = (l: string) => ABIERTAS.map((e) => embudo.find((x) => x.linea === l && x.etapa === e)).filter((x): x is VEmbudoVentas => !!x);
        const bloques = ["diseno", "obra", "peritaje"].map((l) => ({ l, es: etapas(l) })).filter((b) => b.es.length);
        return (
          <Pantalla titulo="Ventas" sobre={fecha(hoyIso())} pie={R.ventas} mas={{ ruta: R.contactoNuevo, nombre: "Nuevo contacto" }}>
            {ritmo?.lectura ? <Frase>{ritmo.lectura}</Frase> : null}
            <Grupo tono={mios.some((x) => x.urgente) ? "c" : ""}>Para hoy</Grupo>
            {mios.length ? mios.map((x) => fila(x)) : <Vacio>Nada para hoy. Lo que toque mañana aparece aquí.</Vacio>}
            {otros.length ? (
              <>
                <Grupo>Lo del resto del equipo</Grupo>
                {otros.map((x) => fila(x, nombres.get(x.persona_id as string)))}
              </>
            ) : null}
            <Grupo style={{ marginTop: 34 }}>El embudo</Grupo>
            {bloques.length ? bloques.map(({ l, es }) => (
              <Fragment key={l}>
                <Grupo>{LINEA[l]}</Grupo>
                {es.map((x) => (
                  <Fila key={x.etapa} href={R.embudo(l, x.etapa)}>
                    <b>{ETAPA[x.etapa]}<Etiqueta tono="n">{x.oportunidades}</Etiqueta></b>
                    <span>
                      {Number(x.valor) ? pesos(x.valor) : "Sin valor todavía"}
                      {x.atrasadas ? <> · <em>{uno(x.atrasadas, "una atrasada", "atrasadas")}</em></> : null}
                      {x.dias_promedio != null ? ` · llevan ${x.dias_promedio === 1 ? "un día" : x.dias_promedio + " días"} en promedio` : ""}
                    </span>
                  </Fila>
                ))}
              </Fragment>
            )) : <Vacio>Todavía no hay oportunidades abiertas.</Vacio>}
            {yo.es_direccion ? <Link className="btn claro" href={R.tarifas}>Tarifas de diseño</Link> : null}
          </Pantalla>
        );
      }}
    </Carga>
  );
}
