"use client";
// Cómo va la plata, en qué se fue y lo que hay que mover.
import { sb } from "@/lib/supabase/cliente";
import { bien, pedir } from "@/lib/pedir";
import { useSesion, useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import { fecha } from "@/lib/dominio/fechas";
import { pesos, plata, titulo, uno } from "@/lib/dominio/texto";
import type { VBalanceCentroCosto } from "@/lib/supabase/vistas";
import { Formulario, Opciones } from "@/componentes/formularios/Formulario";
import { Cifra, Fila, Frase, Grupo, Vacio } from "@/componentes/ui/piezas";
import { CargaSeccion, type PropsSeccion } from "./Obra";

const ESTADO_OBRA = { activo: "En curso", pausado: "En pausa", terminado: "Terminada" };

export function Resumen({ o }: PropsSeccion) {
  const yo = useYo();
  const { ir } = useSesion();
  const estado = useDatos(async () => {
    const [cats, gente] = await Promise.all([
      pedir(sb().from("v_balance_centro_costo").select("categoria,presupuesto,proyectado,por_pagar,excluir_de_rentabilidad").eq("proyecto_id", o.id)
        .overrideTypes<Pick<VBalanceCentroCosto, "categoria" | "presupuesto" | "proyectado" | "por_pagar" | "excluir_de_rentabilidad">[], { merge: false }>()),
      yo.es_direccion ? pedir(sb().from("persona").select("id,nombre").eq("es_interno", true).eq("activo", true).order("nombre")) : [],
    ]);
    return { cats, gente };
  }, [o.id, yo.es_direccion]);

  return (
    <CargaSeccion estado={estado}>
      {({ cats, gente }) => {
        const usadas = cats.filter((c) => !c.excluir_de_rentabilidad && (Number(c.proyectado) || Number(c.presupuesto))).sort((a, b) => Number(b.proyectado) - Number(a.proyectado));
        const caja = Number(o.cobrado) - Number(o.pagado);
        const mover: [string | null, string, string, boolean][] = [];
        if (o.gastos_por_aprobar) mover.push([R.obra(o.id, "gastos"), uno(o.gastos_por_aprobar, "Un gasto espera aprobación", "gastos esperan aprobación"), `${pesos(o.valor_por_aprobar)} en total`, true]);
        if (o.pendientes_abiertos) mover.push([R.obra(o.id, "pendientes"), uno(o.pendientes_abiertos, "Un pendiente abierto", "pendientes abiertos"),
          o.pendientes_vencidos ? (o.pendientes_vencidos === 1 ? "Uno ya pasó su fecha" : `${o.pendientes_vencidos} ya pasaron su fecha`) : "Ninguno ha pasado su fecha", o.pendientes_vencidos > 0]);
        if (o.estado === "activo" && o.dias_sin_bitacora) mover.push([R.obra(o.id, "sitio"), `${uno(o.dias_sin_bitacora, "Un día", "días")} de obra sin bitácora`, "En el último mes, de lunes a sábado", o.dias_sin_bitacora >= 3]);
        if (o.adicionales_pendientes) mover.push([null, uno(o.adicionales_pendientes, "Un adicional espera al cliente", "adicionales esperan al cliente"), "El cliente los aprueba desde su portal", false]);
        return (
          <>
            <Frase>{o.lectura}</Frase>
            {o.alerta ? <div className="error" role="status">{o.alerta}</div> : null}
            <Grupo>La plata</Grupo>
            <div className="cifras">
              <Cifra t="Contrato" v={o.valor_contrato ? pesos(o.valor_contrato) : "Sin escribir"} />
              <Cifra t="Gastado" v={pesos(o.costo_proyectado)} sub={o.pct_contrato != null ? `${o.pct_contrato} % del contrato` : ""} />
              <Cifra t="Pagado" v={pesos(o.pagado)} />
              <Cifra t="Por pagar" v={pesos(o.por_pagar)} />
              {yo.ve_dinero ? (
                <>
                  <Cifra t="Cobrado al cliente" v={pesos(o.cobrado)} />
                  <Cifra t="Caja de la obra" v={pesos(caja)} sub={caja < 0 ? "Se ha pagado más de lo cobrado" : "Lo cobrado menos lo pagado"} mal={caja < 0} />
                </>
              ) : null}
            </div>
            <Grupo>Lo que hay que mover</Grupo>
            {mover.map(([r, t, s, mal], i) => (
              <Fila key={i} href={r ?? undefined}>
                <b>{t}</b><span>{mal ? <em>{s}</em> : s}</span>
              </Fila>
            ))}
            {mover.length ? null : <Vacio corto>Nada pendiente.</Vacio>}
            {usadas.length ? (
              <>
                <Grupo>En qué se ha ido</Grupo>
                {usadas.map((c) => (
                  <Fila key={c.categoria}>
                    <b>{titulo(c.categoria)}</b>
                    <span>{pesos(c.proyectado)}{Number(c.presupuesto) ? <> de {pesos(c.presupuesto)} presupuestados{Number(c.proyectado) > Number(c.presupuesto) ? <> · <em>se pasó</em></> : null}</> : null}{Number(c.por_pagar) ? ` · debe ${pesos(c.por_pagar)}` : ""}</span>
                  </Fila>
                ))}
              </>
            ) : null}
            <Grupo>Datos de la obra</Grupo>
            {yo.es_direccion ? (
              <Formulario onEnviar={async (f) => {
                await pedir(sb().from("proyecto").update({ valor_contrato: plata(f.contrato) || null, residente_id: f.residente || null,
                  fecha_inicio: f.inicio || null, fecha_fin_prevista: f.fin || null, estado: f.estado as "activo" }).eq("id", o.id));
                // El residente queda en el equipo de la obra para poder registrar en ella.
                if (f.residente) {
                  const ya = await pedir(sb().from("acceso_proyecto").select("persona_id").eq("proyecto_id", o.id).eq("persona_id", f.residente));
                  if (!ya.length) await pedir(sb().from("acceso_proyecto").insert({ persona_id: f.residente, proyecto_id: o.id, papel: "produce" as const, nivel: "registro" as const }));
                }
                ir(R.obra(o.id), bien("Datos de la obra guardados."));
              }}>
                <label htmlFor="vc">Valor del contrato</label>
                <input id="vc" name="contrato" inputMode="numeric" autoComplete="off" defaultValue={o.valor_contrato ? Number(o.valor_contrato).toLocaleString("es-CO") : ""} placeholder="0" />
                <label htmlFor="re">Residente</label>
                <select id="re" name="residente" defaultValue={o.residente_id || ""}><Opciones de={gente.map((x) => [x.id, x.nombre])} vacia="Sin residente" /></select>
                <div className="dos">
                  <div><label htmlFor="fi">Empezó el</label><input id="fi" name="inicio" type="date" defaultValue={o.fecha_inicio || ""} /></div>
                  <div><label htmlFor="ff">Se entrega el</label><input id="ff" name="fin" type="date" defaultValue={o.fecha_fin_prevista || ""} /></div>
                </div>
                <label htmlFor="es">Estado</label>
                <select id="es" name="estado" defaultValue={o.estado}><Opciones de={ESTADO_OBRA} /></select>
                <button className="btn claro">Guardar los datos</button>
              </Formulario>
            ) : (
              <Fila>
                <b>{o.residente ? o.residente : "Sin residente"}</b>
                <span>Residente{o.fecha_inicio ? " · empezó el " + fecha(o.fecha_inicio) : ""}{o.fecha_fin_prevista ? " · se entrega el " + fecha(o.fecha_fin_prevista) : ""}</span>
              </Fila>
            )}
          </>
        );
      }}
    </CargaSeccion>
  );
}
