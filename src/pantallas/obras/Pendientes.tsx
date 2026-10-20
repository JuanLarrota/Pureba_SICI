"use client";
// Remates, trámites y compras: quien lo hace no es quien lo verifica.
import { sb } from "@/lib/supabase/cliente";
import { bien, mal, pedir } from "@/lib/pedir";
import { useSesion, useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { asignables, nombresDe } from "@/lib/consultas";
import { R } from "@/lib/rutas";
import { ESTADO_PEND, PRIORIDAD, TIPO_PEND } from "@/lib/dominio/catalogos";
import { fecha, hoyIso } from "@/lib/dominio/fechas";
import { Boton } from "@/componentes/formularios/Boton";
import { Formulario, Opciones } from "@/componentes/formularios/Formulario";
import { Fila, Grupo, Marca, Vacio } from "@/componentes/ui/piezas";
import { CargaSeccion, type PropsSeccion } from "./Obra";

const PESO: Record<string, number> = { bloqueante: 0, alta: 1, normal: 2 };

export function Pendientes({ o, registra }: PropsSeccion) {
  const yo = useYo();
  const { ir, avisar, recargar } = useSesion();
  const estado = useDatos(async () => {
    const [abiertos, cerrados, equipo] = await Promise.all([
      pedir(sb().from("pendiente_obra").select("id,titulo,tipo,prioridad,ubicacion,estado,fecha_compromiso,responsable_id,ejecutor_id,creado_por").eq("proyecto_id", o.id).not("estado", "in", "(cerrado,descartado)").order("fecha_compromiso", { nullsFirst: false })),
      pedir(sb().from("pendiente_obra").select("id,titulo,verificado_en,verificado_por").eq("proyecto_id", o.id).eq("estado", "cerrado").order("verificado_en", { ascending: false }).limit(5)),
      registra ? asignables(o.id) : new Map<string, string>(),
    ]);
    const quien = await nombresDe([...abiertos.flatMap((p) => [p.responsable_id, p.ejecutor_id]), ...cerrados.map((p) => p.verificado_por)]);
    abiertos.sort((a, b) => PESO[a.prioridad] - PESO[b.prioridad]);
    return { abiertos, cerrados, gente: [...equipo].sort((a, b) => a[1].localeCompare(b[1])), quien };
  }, [o.id, registra]);

  const cambiaPendiente = async (id: string, cambio: { estado?: "por_verificar" | "descartado"; verificado_por?: string; descartado_porque?: string }, dicho: string) => {
    const r = await pedir(sb().from("pendiente_obra").update(cambio).eq("id", id).select("id"));
    avisar(r.length ? bien(dicho) : mal("Ese pendiente lo mueve quien responde por él, quien lo hace o dirección."));
    recargar();
  };

  return (
    <CargaSeccion estado={estado}>
      {({ abiertos, cerrados, gente, quien }) => {
        const hoy = hoyIso();
        return (
          <>
            {registra ? (
              <details open={!abiertos.length}>
                <summary className="btn">Nuevo pendiente</summary>
                <Formulario onEnviar={async (f) => {
                  await pedir(sb().from("pendiente_obra").insert({ proyecto_id: o.id, titulo: f.titulo.trim(), tipo: f.tipo as "ejecucion", prioridad: f.prioridad as "normal",
                    ubicacion: f.ubicacion.trim() || null, responsable_id: f.responsable, ejecutor_id: f.ejecutor || null, fecha_compromiso: f.fecha || null, creado_por: yo.persona_id }));
                  ir(R.obra(o.id, "pendientes"), bien("Pendiente creado."));
                }}>
                  <label htmlFor="pt">Qué hay que hacer</label>
                  <input id="pt" name="titulo" required minLength={4} autoComplete="off" placeholder="Instalar el lavamanos del baño social" />
                  <div className="dos">
                    <div><label htmlFor="py">Tipo</label><select id="py" name="tipo" defaultValue="ejecucion"><Opciones de={TIPO_PEND} /></select></div>
                    <div><label htmlFor="pp">Prioridad</label><select id="pp" name="prioridad" defaultValue="normal"><Opciones de={PRIORIDAD} /></select></div>
                  </div>
                  <label htmlFor="pu">Dónde</label>
                  <input id="pu" name="ubicacion" autoComplete="off" placeholder="Cocina, baño social, fachada…" />
                  <label htmlFor="pr">Responde</label>
                  <select id="pr" name="responsable" required defaultValue={yo.persona_id}><Opciones de={gente} /></select>
                  <label htmlFor="pe">Lo hace (si es otra persona)</label>
                  <select id="pe" name="ejecutor" defaultValue=""><Opciones de={gente} vacia="La misma persona" /></select>
                  <label htmlFor="pf">Para cuándo</label>
                  <input id="pf" name="fecha" type="date" min={hoy} />
                  <button className="btn">Crear el pendiente</button>
                </Formulario>
              </details>
            ) : null}
            <Grupo>Abiertos</Grupo>
            {abiertos.map((p) => {
              const hizo = p.ejecutor_id || p.responsable_id, mio = [p.responsable_id, p.ejecutor_id, p.creado_por].includes(yo.persona_id);
              return (
                <Fila key={p.id}>
                  <b>{p.titulo}<Marca prioridad={p.prioridad} /></b>
                  <span>{TIPO_PEND[p.tipo]}{p.ubicacion ? " · " + p.ubicacion : ""} · responde {quien.get(p.responsable_id || "") || "alguien"}{p.ejecutor_id ? " · lo hace " + (quien.get(p.ejecutor_id) || "alguien") : ""}</span>
                  <span>{ESTADO_PEND[p.estado]}{p.fecha_compromiso ? <> · {p.fecha_compromiso < hoy ? <em>era para el {fecha(p.fecha_compromiso)}</em> : "para el " + fecha(p.fecha_compromiso)}</> : null}</span>
                  {p.estado === "por_verificar"
                    ? (hizo !== yo.persona_id && registra
                      ? <Boton className="btn claro" accion={() => cambiaPendiente(p.id, { verificado_por: yo.persona_id }, "Verificado y cerrado.")}>Verifiqué que quedó hecho</Boton>
                      : <span>Lo verifica alguien distinto de quien lo hizo.</span>)
                    : mio || yo.es_direccion ? <Boton className="btn claro" accion={() => cambiaPendiente(p.id, { estado: "por_verificar" }, "Marcado como hecho. Falta que otra persona lo verifique.")}>Ya quedó hecho</Boton> : null}
                  {yo.es_direccion || p.responsable_id === yo.persona_id ? (
                    <details>
                      <summary className="enlace">Descartarlo</summary>
                      <Formulario onEnviar={(f) => cambiaPendiente(p.id, { estado: "descartado", descartado_porque: f.razon.trim() }, "Pendiente descartado.")}>
                        <label htmlFor={`dr${p.id}`}>Por qué ya no se hace</label>
                        <input id={`dr${p.id}`} name="razon" required autoComplete="off" />
                        <button className="btn peligro">Descartar</button>
                      </Formulario>
                    </details>
                  ) : null}
                </Fila>
              );
            })}
            {abiertos.length ? null : <Vacio corto>Ningún pendiente abierto.</Vacio>}
            {cerrados.length ? (
              <>
                <Grupo>Cerrados hace poco</Grupo>
                {cerrados.map((p) => <Fila key={p.id}><b>{p.titulo}</b><span>Lo verificó {quien.get(p.verificado_por || "") || "alguien"} el {fecha(p.verificado_en)}</span></Fila>)}
              </>
            ) : null}
          </>
        );
      }}
    </CargaSeccion>
  );
}
