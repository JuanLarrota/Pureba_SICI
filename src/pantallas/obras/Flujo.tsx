"use client";
// Lo que sale y lo que entra, mes a mes, y lo que viene por pagar.
import { sb } from "@/lib/supabase/cliente";
import { bien, pedir } from "@/lib/pedir";
import { useSesion, useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import { dia0, fecha, hoyIso, isoDe, mesLargo } from "@/lib/dominio/fechas";
import { pesos, plata, uno } from "@/lib/dominio/texto";
import type { VObraFlujoMes, VObraPorPagar } from "@/lib/supabase/vistas";
import { Formulario } from "@/componentes/formularios/Formulario";
import { Fila, Frase, Grupo, Vacio } from "@/componentes/ui/piezas";
import { CargaSeccion, type PropsSeccion } from "./Obra";

type PorPagar = Pick<VObraPorPagar, "tercero" | "concepto" | "por_pagar" | "fecha_prevista" | "aprobacion">;

export function Flujo({ o }: PropsSeccion) {
  const yo = useYo();
  const { ir } = useSesion();
  const estado = useDatos(async () => {
    const [meses, porPagar] = await Promise.all([
      pedir(sb().from("v_obra_flujo_mes").select("*").eq("proyecto_id", o.id).order("mes").overrideTypes<VObraFlujoMes[], { merge: false }>()),
      pedir(sb().from("v_obra_por_pagar").select("tercero,concepto,por_pagar,fecha_prevista,aprobacion").eq("proyecto_id", o.id).order("fecha_prevista").overrideTypes<PorPagar[], { merge: false }>()),
    ]);
    return { meses, porPagar };
  }, [o.id]);

  return (
    <CargaSeccion estado={estado}>
      {({ meses, porPagar }) => {
        let acum = 0;
        const filas = meses.map((m) => ({ ...m, caja: (acum += Number(m.cobrado) - Number(m.pagado)) })).reverse().slice(0, 12);
        const tres = meses.slice(-3), salio = tres.reduce((s, m) => s + Number(m.pagado), 0), entro = tres.reduce((s, m) => s + Number(m.cobrado), 0);
        const hoy = hoyIso(), en28 = isoDe(dia0(hoy) + 28);
        const vencido = porPagar.filter((p) => p.fecha_prevista < hoy), pronto = porPagar.filter((p) => p.fecha_prevista >= hoy && p.fecha_prevista <= en28), despues = porPagar.filter((p) => p.fecha_prevista > en28);
        const total = (a: PorPagar[]) => pesos(a.reduce((s, p) => s + Number(p.por_pagar), 0));
        const lista = (a: PorPagar[]) => a.map((p, i) => (
          <Fila key={i}><b>{p.tercero || "Sin tercero"} · {pesos(p.por_pagar)}</b><span>{p.concepto} · {fecha(p.fecha_prevista)}{p.aprobacion === "pendiente" ? " · espera aprobación" : ""}</span></Fila>
        ));
        return (
          <>
            {meses.length ? <Frase>En los últimos {uno(tres.length, "mes", "meses")} salieron {pesos(salio)}{yo.ve_dinero ? ` y entraron ${pesos(entro)}` : ""}.</Frase> : <Vacio>Todavía no hay pagos ni cobros en esta obra.</Vacio>}
            {porPagar.length ? (
              <>
                <Grupo>Lo que viene por pagar</Grupo>
                {vencido.length ? <><Grupo tono="c">Ya debía estar pagado · {total(vencido)}</Grupo>{lista(vencido)}</> : null}
                {pronto.length ? <><Grupo tono="a">Próximas cuatro semanas · {total(pronto)}</Grupo>{lista(pronto)}</> : null}
                {despues.length ? <><Grupo>Después · {total(despues)}</Grupo>{lista(despues)}</> : null}
              </>
            ) : null}
            {filas.length ? (
              <>
                <Grupo>Mes a mes</Grupo>
                {filas.map((m) => (
                  <Fila key={m.mes}>
                    <b>{mesLargo(m.mes)}</b>
                    <span>Salieron {pesos(m.pagado)} en {uno(Number(m.pagos), "un pago", "pagos")}{yo.ve_dinero ? ` · entraron ${pesos(m.cobrado)}` : ""}</span>
                    {yo.ve_dinero ? <span>{m.caja < 0 ? <em>Caja acumulada: {pesos(m.caja)}</em> : `Caja acumulada: ${pesos(m.caja)}`}</span> : null}
                  </Fila>
                ))}
              </>
            ) : null}
            {yo.ve_dinero ? (
              <details>
                <summary className="btn claro">Registrar un cobro recibido</summary>
                <Formulario onEnviar={async (f) => {
                  if (!plata(f.valor)) throw new Error("Escriba el valor del cobro.");
                  await pedir(sb().from("ingreso").insert({ proyecto_id: o.id, valor: plata(f.valor), linea: "obra_civil" as const, concepto: f.concepto.trim(),
                    fecha: f.fecha || hoyIso(), es_anticipo: f.anticipo === "si", registrado_por: yo.persona_id }));
                  ir(R.obra(o.id, "flujo"), bien("Cobro registrado."));
                }}>
                  <label htmlFor="cv">Valor</label>
                  <input id="cv" name="valor" inputMode="numeric" autoComplete="off" required placeholder="0" />
                  <label htmlFor="cq">Concepto</label>
                  <input id="cq" name="concepto" required autoComplete="off" placeholder="Anticipo, acta 3…" />
                  <label htmlFor="cd">Fecha</label>
                  <input id="cd" name="fecha" type="date" defaultValue={hoy} max={hoy} />
                  <label htmlFor="ca">Es anticipo</label>
                  <select id="ca" name="anticipo" defaultValue="no"><option value="no">No</option><option value="si">Sí</option></select>
                  <button className="btn">Guardar el cobro</button>
                </Formulario>
              </details>
            ) : null}
          </>
        );
      }}
    </CargaSeccion>
  );
}
