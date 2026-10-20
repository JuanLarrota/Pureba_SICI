"use client";
// Cerrar una fase. La lista de chequeo se llena aquí, punto por punto. Algunos
// puntos se marcan y otros piden un dato. Lo que falta para cerrar lo cuenta la
// base; el botón de cerrar solo lo ve dirección, y si algo falta la base lo dice.
import { useState } from "react";
import { sb } from "@/lib/supabase/cliente";
import { bien, decir, pedir, pedirUno } from "@/lib/pedir";
import { useSesion, useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import { fecha, hoyIso } from "@/lib/dominio/fechas";
import { lista, nFase } from "@/lib/dominio/texto";
import type { Falta } from "@/lib/supabase/vistas";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Boton } from "@/componentes/formularios/Boton";
import { Formulario } from "@/componentes/formularios/Formulario";
import { Etiqueta, Fila, Grupo, Nota, Vacio } from "@/componentes/ui/piezas";

const QUE: Record<string, string> = { chequeo: "Lista de chequeo", cliente: "Aprobación del cliente", dedicacion: "Dedicación del equipo", tareas: "Tareas" };
const BLOQUEA: Record<string, string> = { chequeo: "falta completar la lista de chequeo", cliente: "falta la aprobación del cliente", dedicacion: "falta poner al día la dedicación" };

interface Item { id: string; orden: number; texto: string; tipo: string; opciones: string[] | null; obligatorio: boolean; activo: boolean | null; requiere_evidencia: boolean | null }
interface Respuesta { item_id: string; cumple: boolean; valor: string | null }
interface Fase { id: string; fase: string; estado: string; proyecto_id: string; exige_aprobacion_cliente: boolean; aprobada_cliente_en: string | null; aprobada_cliente_texto: string | null; entrega_cliente: string | null; proyecto: { nombre: string } | null }

export function Cierre({ faseId }: { faseId: string }) {
  const yo = useYo();
  const { ir, avisar, recargar } = useSesion();
  const estado = useDatos(async () => {
    const f = (await pedirUno(sb().from("proyecto_fase").select("id,fase,estado,proyecto_id,exige_aprobacion_cliente,aprobada_cliente_en,aprobada_cliente_texto,entrega_cliente,proyecto(nombre)").eq("id", faseId).maybeSingle())) as unknown as Fase | null;
    if (!f) return null;
    const hoja = yo.registra.includes(f.proyecto_id) && f.estado !== "pendiente" ? await pedir(sb().rpc("abrir_chequeo", { p_fase: faseId })) : null;
    const [falta, puntos, respuestas] = await Promise.all([
      pedir(sb().rpc("falta_para_cerrar", { p_fase: faseId }).overrideTypes<Falta[], { merge: false }>()),
      hoja ? pedirUno(sb().from("chequeo").select("lista_id,lista:lista_chequeo(lista_chequeo_item(id,orden,texto,tipo,opciones,obligatorio,activo,requiere_evidencia))").eq("id", hoja).maybeSingle()) : null,
      hoja ? pedir(sb().from("chequeo_respuesta").select("item_id,cumple,valor").eq("chequeo_id", hoja)) : [],
    ]);
    const lista = (puntos as unknown as { lista: { lista_chequeo_item: Item[] } | null } | null)?.lista;
    const items = (lista?.lista_chequeo_item || []).filter((i) => i.activo !== false).sort((a, b) => a.orden - b.orden);
    return { f, hoja, falta, items, respuestas: respuestas as Respuesta[] };
  }, [faseId, yo.persona_id]);

  return (
    <Carga estado={estado} atras={R.proyectos}>
      {(d) => {
        if (!d) return <Pantalla titulo="Cierre de fase" atras={R.proyectos}><Vacio>Esa fase no existe o no es de sus proyectos.</Vacio></Pantalla>;
        return <Hoja key={faseId} {...d} yoId={yo.persona_id} esDireccion={yo.es_direccion} ir={ir} avisar={avisar} recargar={recargar} />;
      }}
    </Carga>
  );
}

interface HojaProps { f: Fase; hoja: string | null; falta: Falta[]; items: Item[]; respuestas: Respuesta[]; yoId: string; esDireccion: boolean;
  ir: (r: string, a?: ReturnType<typeof bien>) => void; avisar: (a: ReturnType<typeof bien>) => void; recargar: () => void }

function Hoja({ f, hoja, falta: falta0, items, respuestas: respuestas0, yoId, esDireccion, ir, avisar, recargar }: HojaProps) {
  const [falta, setFalta] = useState(falta0);
  const [R0, setR0] = useState(() => new Map(respuestas0.map((r) => [r.item_id, r])));
  const abierta = f.estado !== "cerrada";
  const bloquea = falta.filter((x) => x.bloquea && !x.listo), abiertas = falta.find((x) => x.que === "tareas" && !x.listo);

  // Guarda un punto y vuelve a contar lo que falta, sin repintar toda la pantalla.
  const guardaPunto = async (itemId: string, cumple: boolean, valor: string | null): Promise<string | null> => {
    await pedir(sb().from("chequeo_respuesta").upsert({ chequeo_id: hoja!, item_id: itemId, cumple, valor, verificado_por: yoId }, { onConflict: "chequeo_id,item_id" }));
    setR0((m) => new Map(m).set(itemId, { item_id: itemId, cumple, valor }));
    setFalta(await pedir(sb().rpc("falta_para_cerrar", { p_fase: f.id }).overrideTypes<Falta[], { merge: false }>()));
    return null;
  };

  return (
    <Pantalla titulo={`${abierta ? "Cerrar" : "Cierre de"} ${nFase(f.fase).toLowerCase()}`} sobre={f.proyecto?.nombre} atras={R.proyecto(f.proyecto_id)}>
      {f.estado === "pendiente" ? <Nota>Esta fase todavía no se ha abierto.</Nota> : null}
      <div id="falta">
        <Grupo>Lo que hace falta</Grupo>
        {falta.map((x) => (
          <Fila key={x.que}>
            <b>{QUE[x.que] || x.que}<Etiqueta tono={x.listo ? "o" : x.bloquea ? "c" : "a"}>{x.listo ? "Listo" : x.bloquea ? "Falta" : "Aviso"}</Etiqueta></b>
            <span>{x.detalle}</span>
          </Fila>
        ))}
      </div>
      {items.length ? (
        <>
          <Grupo>Lista de chequeo</Grupo>
          {items.map((i) => <Punto key={i.id} i={i} r={R0.get(i.id)} abierta={abierta} guardar={guardaPunto} />)}
        </>
      ) : null}
      {f.exige_aprobacion_cliente && abierta ? (
        <>
          <Grupo>Aprobación del cliente</Grupo>
          {esDireccion ? (
            <Formulario onEnviar={async (fd) => {
              const r = await pedir(sb().from("proyecto_fase").update({ aprobada_cliente_en: fd.fecha, aprobada_cliente_texto: fd.texto.trim() }).eq("id", f.id).select("id"));
              if (!r.length) throw new Error("La aprobación del cliente la registra dirección.");
              avisar(bien("Aprobación del cliente guardada.")); recargar();
            }}>
              <label htmlFor="ac">Fecha en que aprobó</label>
              <input id="ac" name="fecha" type="date" max={hoyIso()} defaultValue={f.aprobada_cliente_en || ""} required />
              <label htmlFor="at">Quién aprobó y por qué medio</label>
              <input id="at" name="texto" defaultValue={f.aprobada_cliente_texto || ""} required minLength={6} placeholder="Nombre, y si fue por correo, WhatsApp o en reunión" autoComplete="off" />
              <button className="btn claro">Guardar la aprobación</button>
            </Formulario>
          ) : <p>{f.aprobada_cliente_en ? `Aprobó el ${fecha(f.aprobada_cliente_en)}: ${f.aprobada_cliente_texto}.` : "La registra dirección cuando el cliente aprueba."}</p>}
        </>
      ) : null}
      <div id="cerrar">
        {/* El botón va al final: primero se llena, después se cierra. */}
        {f.estado === "cerrada" ? <p className="bien">Esta fase ya está cerrada.</p> : f.estado === "pendiente" ? null : esDireccion ? (
          <>
            <Grupo>Cerrar la fase</Grupo>
            {bloquea.length ? <Nota>Todavía no: {lista(bloquea.map((x) => BLOQUEA[x.que]))}.</Nota> : abiertas ? <Nota>{abiertas.detalle}: si cierra la fase, siguen abiertas.</Nota> : null}
            <Boton disabled={bloquea.length > 0} accion={async () => {
              const r = await pedir(sb().from("proyecto_fase").update({ estado: "cerrada" as const }).eq("id", f.id).select("id"));
              if (!r.length) throw new Error("La fase la cierra dirección.");
              ir(R.proyecto(f.proyecto_id), bien("Fase cerrada. Quedó registrado quién la cerró y cuándo."));
            }}>Cerrar {nFase(f.fase).toLowerCase()}</Boton>
          </>
        ) : <Nota>La fase la cierra dirección. Usted puede dejar completa la lista de chequeo.</Nota>}
      </div>
    </Pantalla>
  );
}

/** Un punto de la lista: se marca o pide un dato, y dice si quedó guardado. */
function Punto({ i, r, abierta, guardar }: { i: Item; r?: Respuesta; abierta: boolean; guardar: (itemId: string, cumple: boolean, valor: string | null) => Promise<string | null> }) {
  const [marca, setMarca] = useState<{ texto: string; mal: boolean } | null>(null);
  const v = r?.cumple ? r.valor ?? "" : "";
  const intenta = async (cumple: boolean, valor: string | null) => {
    try { await guardar(i.id, cumple, valor); setMarca({ texto: cumple ? "Guardado" : "Quedó pendiente", mal: false }); return true; }
    catch (e) { setMarca({ texto: decir(e), mal: true }); return false; }
  };
  const dato = (e: { target: { value: string } }) => { const t = e.target.value.trim(); intenta(t !== "", t || null); };
  const comun = { disabled: !abierta, "aria-label": i.texto };
  const campo = i.requiere_evidencia ? <Nota style={{ margin: "8px 0 0" }}>Este punto pide una foto o un archivo, y eso todavía no se adjunta desde aquí.</Nota>
    : i.tipo === "opcion" ? <select {...comun} defaultValue={v} onChange={dato}><option value="">Escoja</option>{(i.opciones || []).map((o) => <option key={o}>{o}</option>)}</select>
    : i.tipo === "numero" ? <input {...comun} inputMode="decimal" defaultValue={v} placeholder="Un número" onChange={dato} />
    : i.tipo === "fecha" ? <input {...comun} type="date" defaultValue={v} onChange={dato} />
    : i.tipo === "enlace" ? <input {...comun} type="url" inputMode="url" defaultValue={v} placeholder="https://…" onChange={dato} />
    : <button type="button" className={`btn ${r?.cumple ? "" : "claro"} casilla`} aria-pressed={!!r?.cumple} disabled={!abierta}
        onClick={() => intenta(!r?.cumple, null)}>{r?.cumple ? "Cumplido" : "Marcar como cumplido"}</button>;
  return (
    <div className="fila punto" id={`punto-${i.id}`}>
      <b>{i.texto}{i.obligatorio ? null : <Etiqueta tono="n">Opcional</Etiqueta>}</b>
      {campo}
      <span className={`m-ok${marca?.mal ? " mal" : ""}`} aria-live="polite">{marca?.texto || ""}</span>
    </div>
  );
}
