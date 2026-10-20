"use client";
// Una tarea: qué es, quién la tiene, cómo va, y lo que la persona puede hacer
// con ella (empezar, entregar o pedir revisión, aprobar o devolver, cambiarla).
// Sin el dato de revisión (tareas de antes), pasa por revisión y la revisa quien
// tenga ese papel en el proyecto.
import { useState } from "react";
import { sb } from "@/lib/supabase/cliente";
import { bien, pedir, pedirUno } from "@/lib/pedir";
import { useSesion, useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { asignables } from "@/lib/consultas";
import { R } from "@/lib/rutas";
import { ESTADO, PRIORIDAD } from "@/lib/dominio/catalogos";
import { fecha, hora } from "@/lib/dominio/fechas";
import { enDias, ESFUERZO, esfuerzo } from "@/lib/dominio/texto";
import type { VTareaContexto } from "@/lib/supabase/vistas";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Boton } from "@/componentes/formularios/Boton";
import { Formulario, Opciones } from "@/componentes/formularios/Formulario";
import { Grupo, Marca, Vacio } from "@/componentes/ui/piezas";
import { conRevision, SelectRevision } from "./revision";

interface Nombre { nombre: string }

export function Tarea({ id }: { id: string }) {
  const yo = useYo();
  const { ir, avisar, recargar } = useSesion();
  const estado = useDatos(async () => {
    const [t, ctx, rastro, revs] = await Promise.all([
      pedirUno(sb().from("tarea_diseno").select("id,titulo,descripcion,estado,prioridad,fecha_inicio,fecha_compromiso,dias_estimados,proyecto_id,asignada_a,asignada_por,bloqueada_por,requiere_revision,revisor_id,proyecto(nombre),tiene:persona!tarea_diseno_asignada_a_fkey(nombre),asigno:persona!tarea_diseno_asignada_por_fkey(nombre),revisa:persona!tarea_diseno_revisor_id_fkey(nombre)").eq("id", id).maybeSingle()),
      pedirUno(sb().from("v_tarea_contexto").select("para_que").eq("tarea_id", id).maybeSingle().overrideTypes<Pick<VTareaContexto, "para_que">, { merge: false }>()),
      pedir(sb().from("tarea_evento").select("tipo,de,a,ocurrio_en,persona(nombre)").eq("tarea_id", id).order("ocurrio_en")),
      pedir(sb().from("revision_diseno").select("resultado,observaciones,revisada_en,persona(nombre)").eq("tarea_id", id).order("revisada_en", { ascending: false })),
    ]);
    if (!t) return null;
    const dirijo = yo.dirige.includes(t.proyecto_id), laAsigne = t.asignada_por === yo.persona_id;
    const edita = (dirijo || laAsigne) && t.estado !== "terminada", reasigna = edita && (dirijo || yo.asigna);
    const gente = reasigna ? [...(await asignables(t.proyecto_id))].sort((a, b) => a[1].localeCompare(b[1])) : [];
    return { t, ctx, rastro, revs, dirijo, laAsigne, edita, reasigna, gente };
  }, [id, yo.persona_id]);

  const cambiarEstado = async (a: string) => {
    await pedir(sb().from("tarea_diseno").update({ estado: a as "en_curso" }).eq("id", id));
    avisar(bien(a === "en_revision" ? "Revisión pedida. Quedó la hora de la entrega." : a === "terminada" ? "Entregada y cerrada." : "Listo."));
    recargar();
  };

  return (
    <Carga estado={estado} atras={R.dia}>
      {(d) => {
        if (!d) return <Pantalla titulo="Tarea" atras={R.dia}><Vacio>Esa tarea no existe o no es de sus proyectos.</Vacio></Pantalla>;
        const { t, ctx, rastro, revs, edita, reasigna, gente } = d;
        const mia = t.asignada_a === yo.persona_id;
        const sinRevision = t.requiere_revision === false, entrega = sinRevision ? "terminada" : "en_revision";
        const reviso = !mia && !sinRevision && (t.revisor_id ? t.revisor_id === yo.persona_id : yo.revisa.includes(t.proyecto_id));
        const devuelta = revs.find((r) => r.resultado === "con_observaciones");
        const est = t.dias_estimados == null ? null : Number(t.dias_estimados);
        const proyecto = t.proyecto as unknown as Nombre | null, tiene = t.tiene as unknown as Nombre | null, asigno = t.asigno as unknown as Nombre | null, revisa = t.revisa as unknown as Nombre | null;
        return (
          <Pantalla titulo={t.titulo} sobre={proyecto?.nombre} atras={R.dia}>
            <p style={{ color: "var(--tinta-3)" }}>
              {ESTADO[t.estado]} · se entrega el {fecha(t.fecha_compromiso)}{est ? ` · pide ${esfuerzo(est)}` : ""}<Marca prioridad={t.prioridad} />
            </p>
            {t.estado === "con_observaciones" && devuelta ? (
              <div className="error"><strong>{(devuelta.persona as unknown as Nombre | null)?.nombre || "Quien revisó"} la devolvió:</strong> {devuelta.observaciones}</div>
            ) : null}
            {ctx?.para_que ? <><Grupo>Para qué sirve</Grupo><p>{ctx.para_que}</p></> : null}
            {t.descripcion ? <><Grupo>Detalle</Grupo><p>{t.descripcion}</p></> : null}
            <Grupo>Quién</Grupo>
            <p>La tiene {tiene?.nombre}. La asignó {asigno?.nombre}. {sinRevision ? "No requiere revisión: se cierra al entregarla." : revisa?.nombre ? `La revisa ${revisa.nombre}.` : "La revisa quien tenga ese papel en el proyecto."}</p>

            {mia && t.estado === "asignada" ? (
              <div className="par">
                <Boton className="btn claro" accion={() => cambiarEstado("en_curso")}>Empezar</Boton>
                <Boton accion={() => cambiarEstado(entrega)}>{sinRevision ? "Entregar y cerrar" : "Pedir revisión"}</Boton>
              </div>
            ) : mia && (t.estado === "en_curso" || t.estado === "con_observaciones") ? (
              <Boton accion={() => cambiarEstado(entrega)}>{sinRevision ? "Entregar y cerrar" : t.estado === "en_curso" ? "Pedir revisión" : "Volver a pedir revisión"}</Boton>
            ) : mia && t.estado === "en_revision" ? (
              <>
                <p className="nota">Ya está en manos de {revisa?.nombre || "quien revisa"}.</p>
                <Boton className="btn claro" accion={() => cambiarEstado("en_curso")}>Retirar la entrega</Boton>
              </>
            ) : null}

            {reviso && t.estado === "en_revision" ? (
              <Formulario onEnviar={async (f, boton) => {
                const r = boton?.value || "aprobada";
                if (r === "con_observaciones" && !f.obs.trim()) throw new Error("Para devolver hay que escribir qué falta.");
                await pedir(sb().from("revision_diseno").insert({ tarea_id: t.id, revisor_id: yo.persona_id, resultado: r as "aprobada", observaciones: f.obs.trim() || null }));
                ir(R.revisar, bien(r === "aprobada" ? "Aprobada: la tarea quedó terminada." : "Devuelta con su observación."));
              }}>
                <label htmlFor="obs">Observación (obligatoria para devolver)</label>
                <textarea id="obs" name="obs" />
                <div className="par">
                  <button className="btn" name="r" value="aprobada">Aprobar</button>
                  <button className="btn claro" name="r" value="con_observaciones">Devolver</button>
                </div>
              </Formulario>
            ) : null}

            {edita ? (
              <CambiarTarea t={{ id: t.id, asignada_a: t.asignada_a, estado: t.estado, fecha_inicio: t.fecha_inicio, fecha_compromiso: t.fecha_compromiso, prioridad: t.prioridad, requiere_revision: t.requiere_revision, revisor_id: t.revisor_id }}
                est={est} reasigna={reasigna} gente={gente} alGuardar={() => { avisar(bien("Cambio guardado. Quedó en el rastro.")); recargar(); }} />
            ) : null}

            <Grupo>Rastro</Grupo>
            <ul className="rastro">
              {rastro.map((r, i) => (
                <li key={i}>
                  <strong>{(r.persona as unknown as Nombre | null)?.nombre || "El sistema"}</strong> · {
                    r.tipo === "creada" ? "la asignó" : r.tipo === "estado" ? `${ESTADO[r.de || ""] || r.de} → ${ESTADO[r.a || ""] || r.a}` : r.tipo === "fecha" ? `movió la fecha del ${fecha(r.de)} al ${fecha(r.a)}`
                      : r.tipo === "prioridad" ? "cambió la prioridad" : "la reasignó"} · {hora(r.ocurrio_en)}
                </li>
              ))}
            </ul>
          </Pantalla>
        );
      }}
    </Carga>
  );
}

interface TareaEditable {
  id: string; asignada_a: string; estado: string; fecha_inicio: string | null; fecha_compromiso: string | null; prioridad: string;
  requiere_revision: boolean; revisor_id: string | null;
}

/** Cambiar la tarea: responsable, revisión, fechas, trabajo que pide y prioridad. Queda en el rastro. */
function CambiarTarea({ t, est, reasigna, gente, alGuardar }: { t: TareaEditable; est: number | null; reasigna: boolean; gente: [string, string][]; alGuardar: () => void }) {
  const conRevisionAqui = reasigna && t.estado !== "en_revision";
  const [req, setReq] = useState(t.requiere_revision !== false);
  const [revisor, setRevisor] = useState(t.revisor_id || "");
  const opcionesEsfuerzo: [string, string][] = (est && !ESFUERZO.some((x) => x[0] === est) ? [[est, enDias(est)] as [number, string], ...ESFUERZO] : ESFUERZO).map(([v, n]) => [String(v), n]);
  return (
    <>
      <Grupo>Cambiar la tarea</Grupo>
      <Formulario onEnviar={async (f) => {
        if (f.inicio && f.inicio > f.fecha) throw new Error("La tarea no puede empezar después de su entrega.");
        await pedir(sb().from("tarea_diseno").update({ fecha_inicio: f.inicio || null, fecha_compromiso: f.fecha, prioridad: f.prioridad as "normal",
          dias_estimados: f.dias ? Number(f.dias) : null, ...(f.quien ? { asignada_a: f.quien } : {}),
          ...("rr:e" in f ? conRevision(f, "e", f.quien || t.asignada_a) : {}) }).eq("id", t.id));
        alGuardar();
      }}>
        {reasigna ? (
          <>
            <label htmlFor="q">Responsable</label>
            <select id="q" name="quien" defaultValue={t.asignada_a}><Opciones de={gente} /></select>
          </>
        ) : null}
        {conRevisionAqui ? <SelectRevision i="e" revisores={gente} req={req} setReq={setReq} revisor={revisor} setRevisor={setRevisor} /> : null}
        <div className="dos">
          <div><label htmlFor="i">Empieza</label><input id="i" name="inicio" type="date" defaultValue={t.fecha_inicio || ""} /></div>
          <div><label htmlFor="f">Entrega</label><input id="f" name="fecha" type="date" defaultValue={t.fecha_compromiso || ""} required /></div>
          <div><label htmlFor="e">Trabajo que pide</label><select id="e" name="dias" defaultValue={est == null ? "" : String(est)}><Opciones de={opcionesEsfuerzo} vacia="Sin estimar" /></select></div>
          <div><label htmlFor="p">Prioridad</label><select id="p" name="prioridad" defaultValue={t.prioridad}><Opciones de={PRIORIDAD} /></select></div>
        </div>
        <button className="btn claro">Guardar el cambio</button>
      </Formulario>
    </>
  );
}
