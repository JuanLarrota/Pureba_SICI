"use client";
// Registrar un gasto, aprobar lo que pasa del umbral, pagar lo facturado.
import { sb } from "@/lib/supabase/cliente";
import { bien, mal, pedir, pedirUno } from "@/lib/pedir";
import { useSesion, useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { nombresDe } from "@/lib/consultas";
import { R } from "@/lib/rutas";
import { ESTADO_DINERO, MEDIO } from "@/lib/dominio/catalogos";
import { fecha, hoyIso } from "@/lib/dominio/fechas";
import { pesos, plata, titulo } from "@/lib/dominio/texto";
import type { Json } from "@/lib/supabase/tipos";
import type { VMovimientoVigente, VObraPorPagar } from "@/lib/supabase/vistas";
import { Boton } from "@/componentes/formularios/Boton";
import { Formulario, Opciones } from "@/componentes/formularios/Formulario";
import { Etiqueta, Fila, Grupo, Nota, Vacio } from "@/componentes/ui/piezas";
import { CargaSeccion, type PropsSeccion } from "./Obra";

const QUE_PASO = { causacion: "Llegó la factura y falta pagarla", pago: "Ya se pagó", compromiso: "Quedó comprometido (orden o cotización aceptada)" };
type PorAprobar = Pick<VMovimientoVigente, "id" | "fecha" | "valor" | "tercero_id" | "tercero_nombre" | "concepto" | "numero_factura" | "registrado_por">;
type Ultimo = Pick<VMovimientoVigente, "id" | "fecha" | "estado" | "naturaleza" | "valor" | "tercero_id" | "tercero_nombre" | "concepto" | "numero_factura" | "aprobacion">;

export function Gastos({ o, registra }: PropsSeccion) {
  const yo = useYo();
  const { ir, avisar, recargar } = useSesion();
  const estado = useDatos(async () => {
    const [porAprobar, porPagar, ultimos, cats, par] = await Promise.all([
      pedir(sb().from("v_movimiento_vigente").select("id,fecha,valor,tercero_id,tercero_nombre,concepto,numero_factura,registrado_por").eq("proyecto_id", o.id).eq("aprobacion", "pendiente").order("fecha").overrideTypes<PorAprobar[], { merge: false }>()),
      pedir(sb().from("v_obra_por_pagar").select("*").eq("proyecto_id", o.id).order("fecha_prevista").overrideTypes<VObraPorPagar[], { merge: false }>()),
      pedir(sb().from("v_movimiento_vigente").select("id,fecha,estado,naturaleza,valor,tercero_id,tercero_nombre,concepto,numero_factura,aprobacion").eq("proyecto_id", o.id).order("fecha", { ascending: false }).order("registrado_en", { ascending: false }).limit(25).overrideTypes<Ultimo[], { merge: false }>()),
      registra ? pedir(sb().from("categoria_costo").select("id,nombre,tipo_gasto").eq("activo", true).order("orden").order("nombre")) : [],
      registra ? pedirUno(sb().from("parametro").select("umbral_aprobacion").maybeSingle()) : null,
    ]);
    const quien = await nombresDe([...porAprobar.flatMap((m) => [m.tercero_id, m.registrado_por]), ...ultimos.map((m) => m.tercero_id)]);
    return { porAprobar, porPagar, ultimos, cats, par, quien };
  }, [o.id, registra]);

  const decidirGasto = async (id: string, decision: "aprobado" | "rechazado") => {
    if (decision === "rechazado" && !window.confirm("¿Rechazar este gasto? La decisión queda registrada y no se cambia.")) return;
    const r = await pedir(sb().from("movimiento").update(decision === "aprobado" ? { aprobacion: decision, aprobado_por: yo.persona_id, aprobado_en: new Date().toISOString() } : { aprobacion: decision })
      .eq("id", id).select("id"));
    avisar(r.length ? bien(decision === "aprobado" ? "Gasto aprobado: ya se puede pagar." : "Gasto rechazado.") : mal("Solo dirección decide sobre un gasto."));
    recargar();
  };

  return (
    <CargaSeccion estado={estado}>
      {({ porAprobar, porPagar, ultimos, cats, par, quien }) => {
        const tercero = (m: { tercero_nombre: string | null; tercero_id: string | null }) => m.tercero_nombre || quien.get(m.tercero_id || "") || "Sin tercero";
        const hoy = hoyIso(), deObra = cats.filter((c) => c.tipo_gasto === "COSTOS OPERATIVOS"), otras = cats.filter((c) => c.tipo_gasto !== "COSTOS OPERATIVOS");
        return (
          <>
            {registra ? (
              <details open={!ultimos.length}>
                <summary className="btn">Registrar un gasto</summary>
                <Formulario onEnviar={async (f) => {
                  const gid = await pedir(sb().rpc("registrar_gasto", { p_datos: { proyecto_id: o.id, categoria_id: f.categoria, estado: f.estado, valor: plata(f.valor),
                    tercero: f.tercero, concepto: f.concepto, numero_factura: f.factura, medio: f.medio, fecha: f.fecha, fecha_prevista_pago: f.prevista } as unknown as Json }));
                  const [m] = await pedir(sb().from("movimiento").select("aprobacion").eq("id", gid as unknown as string));
                  ir(R.obra(o.id, "gastos"), bien(m?.aprobacion === "pendiente" ? "Gasto guardado. Como llega al umbral, espera la aprobación de dirección antes de pagarse." : "Gasto guardado."));
                }}>
                  <label htmlFor="ge">Qué pasó</label>
                  <select id="ge" name="estado" defaultValue="causacion"><Opciones de={QUE_PASO} /></select>
                  <label htmlFor="gc">Categoría</label>
                  <select id="gc" name="categoria" required defaultValue="">
                    {cats.length ? null : <option value="">Falta cargar las categorías</option>}
                    {deObra.length ? <optgroup label="De la obra">{deObra.map((c) => <option key={c.id} value={c.id}>{titulo(c.nombre)}</option>)}</optgroup> : null}
                    {otras.length ? <optgroup label="Otras">{otras.map((c) => <option key={c.id} value={c.id}>{titulo(c.nombre)}</option>)}</optgroup> : null}
                  </select>
                  <label htmlFor="gv">Valor</label>
                  <input id="gv" name="valor" inputMode="numeric" autoComplete="off" required placeholder="0" />
                  <label htmlFor="gt">A quién se le paga</label>
                  <input id="gt" name="tercero" required autoComplete="off" placeholder="Proveedor o contratista" />
                  <label htmlFor="gq">Qué se compró o qué trabajo fue</label>
                  <input id="gq" name="concepto" required autoComplete="off" />
                  <label htmlFor="gf">Número de la factura (si la hay)</label>
                  <input id="gf" name="factura" autoComplete="off" />
                  <label htmlFor="gm">Con qué se pagó</label>
                  <select id="gm" name="medio" defaultValue="no_aplica"><option value="no_aplica">Todavía no se ha pagado</option><Opciones de={MEDIO} /></select>
                  <div className="dos">
                    <div><label htmlFor="gd">Fecha</label><input id="gd" name="fecha" type="date" defaultValue={hoy} max={hoy} /></div>
                    <div><label htmlFor="gp">Se paga el</label><input id="gp" name="prevista" type="date" /></div>
                  </div>
                  {par ? <Nota>Si el valor llega a {pesos(par.umbral_aprobacion)} o más, el gasto queda esperando la aprobación de dirección antes de pagarse.</Nota> : null}
                  <button className="btn">Guardar el gasto</button>
                </Formulario>
              </details>
            ) : null}

            {porAprobar.length ? (
              <>
                <Grupo tono="c">Esperan aprobación</Grupo>
                {porAprobar.map((m) => (
                  <Fila key={m.id}>
                    <b>{tercero(m)} · {pesos(m.valor)}</b>
                    <span>{m.concepto}{m.numero_factura ? " · factura " + m.numero_factura : ""} · lo registró {quien.get(m.registrado_por || "") || "alguien"} el {fecha(m.fecha)}</span>
                    {yo.es_direccion ? (
                      <div className="par">
                        <Boton accion={() => decidirGasto(m.id, "aprobado")}>Aprobar</Boton>
                        <Boton className="btn peligro" accion={() => decidirGasto(m.id, "rechazado")}>Rechazar</Boton>
                      </div>
                    ) : <span>Espera a dirección.</span>}
                  </Fila>
                ))}
              </>
            ) : null}

            <Grupo>Por pagar</Grupo>
            {porPagar.map((p) => (
              <Fila key={p.raiz_id}>
                <b>{p.tercero || "Sin tercero"} · {pesos(p.por_pagar)}</b>
                <span>{p.concepto}{p.numero_factura ? " · factura " + p.numero_factura : p.facturado ? "" : " · sin factura todavía"} · {p.fecha_prevista < hoy ? <em>se debía pagar el {fecha(p.fecha_prevista)}</em> : "se paga el " + fecha(p.fecha_prevista)}{p.aprobacion === "pendiente" ? " · espera aprobación" : ""}</span>
                {registra && p.aprobacion !== "pendiente" ? (
                  <details>
                    <summary className="enlace">Registrar el pago</summary>
                    <Formulario onEnviar={async (f) => {
                      await pedir(sb().from("movimiento").insert({ proyecto_id: o.id, centro_costo_id: f.cc, estado: "pago" as const, origen_id: f.raiz, valor: Number(f.valor),
                        tercero_nombre: f.tercero, concepto: f.concepto, medio: f.medio as "banco", fecha: f.fecha || hoyIso(), registrado_por: yo.persona_id }));
                      ir(R.obra(o.id, "gastos"), bien("Pago registrado."));
                    }}>
                      <input type="hidden" name="raiz" value={p.raiz_id} /><input type="hidden" name="cc" value={p.centro_costo_id} /><input type="hidden" name="valor" value={String(p.por_pagar)} />
                      <input type="hidden" name="tercero" value={p.tercero || "Sin tercero"} /><input type="hidden" name="concepto" value={p.concepto} />
                      <div className="dos">
                        <div><label htmlFor={`pm${p.raiz_id}`}>Con qué</label><select id={`pm${p.raiz_id}`} name="medio" defaultValue="banco"><Opciones de={MEDIO} /></select></div>
                        <div><label htmlFor={`pd${p.raiz_id}`}>El día</label><input id={`pd${p.raiz_id}`} name="fecha" type="date" defaultValue={hoy} max={hoy} /></div>
                      </div>
                      <button className="btn claro">Pagado: {pesos(p.por_pagar)}</button>
                    </Formulario>
                  </details>
                ) : null}
              </Fila>
            ))}
            {porPagar.length ? null : <Vacio corto>Nada por pagar.</Vacio>}

            <Grupo>Últimos movimientos</Grupo>
            {ultimos.map((m) => (
              <Fila key={m.id}>
                <b>{tercero(m)} · {m.naturaleza === "devolucion" ? "−" : ""}{pesos(m.valor)}</b>
                <span>{m.concepto} · {m.naturaleza === "devolucion" ? "Devolución" : ESTADO_DINERO[m.estado]}{m.numero_factura ? " · factura " + m.numero_factura : ""} · {fecha(m.fecha)}{m.aprobacion === "pendiente" ? <Etiqueta tono="a">Por aprobar</Etiqueta> : m.aprobacion === "aprobado" ? <Etiqueta tono="o">Aprobado</Etiqueta> : null}</span>
              </Fila>
            ))}
            {ultimos.length ? null : <Vacio corto>Todavía no hay gastos registrados.</Vacio>}
          </>
        );
      }}
    </CargaSeccion>
  );
}
