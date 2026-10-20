"use client";
// La ficha: fases con su avance, fecha y responsable, equipo con sus papeles,
// documentos y Drive. Las tareas están en las otras vistas.
import Link from "next/link";
import { sb } from "@/lib/supabase/cliente";
import { bien, mal, pedir } from "@/lib/pedir";
import { useSesion } from "@/lib/sesion";
import { R } from "@/lib/rutas";
import { ROL } from "@/lib/dominio/catalogos";
import { fecha } from "@/lib/dominio/fechas";
import { titulo, uno } from "@/lib/dominio/texto";
import { Boton } from "@/componentes/formularios/Boton";
import { Formulario, Opciones } from "@/componentes/formularios/Formulario";
import { Avatar, BarraAvance, Etiqueta, Fila, Grupo, Vacio } from "@/componentes/ui/piezas";
import { Drive } from "@/componentes/Drive";
import { CasillasPapel, nombrarPapeles, papelesDe } from "./papeles";
import type { MiembroP, VistaProps } from "./tipos";

interface Props extends VistaProps {
  equipo: MiembroP[];
  personas: { id: string; nombre: string }[];
  responden: [string, string][];   // el equipo que trabaja y dirección
}

export function Ficha({ id, p, fases, av, yo, dirijo, equipo, personas, responden }: Props) {
  const { avisar, recargar, ir } = useSesion();
  const siguiente = fases.find((f) => f.estado !== "cerrada");
  const fuera = personas.filter((x) => !equipo.some((e) => e.id === x.id));
  // Cada persona una vez, con todos sus papeles.
  const porPersona = [...equipo.reduce((m, e) => { (m.get(e.id) || m.set(e.id, { ...e, papeles: [] as string[] }).get(e.id)!).papeles.push(e.papel); return m; }, new Map<string, MiembroP & { papeles: string[] }>()).values()];

  // Guardar un dato de la fase; si la base no deja, lo dice.
  const guardaFase = async (fid: string, cambio: { fecha_compromiso?: string | null; responsable_id?: string | null }, dicho: string) => {
    try {
      const r = await pedir(sb().from("proyecto_fase").update(cambio).eq("id", fid).select("id"));
      avisar(r.length ? bien(dicho) : mal("La fecha y el responsable de una fase los cambia dirección."));
    } catch (e) { avisar(mal(e)); }
    recargar();
  };
  const abrirFase = async (fid: string) => {
    await pedir(sb().from("proyecto_fase").update({ estado: "en_curso" as const }).eq("id", fid));
    // Si la fase tiene tareas típicas, lo siguiente es repartirlas.
    const tipicas = await sb().rpc("tareas_tipicas", { p_fase: fid });
    if (tipicas.data?.length) ir(R.tipicas(fid), bien("Fase abierta. Estas son sus tareas típicas: escoja a quién se le entrega cada una."));
    else { avisar(bien("Fase abierta.")); recargar(); }
  };

  return (
    <>
      {p.tipo === "obra" && yo.obras ? <Link className="btn" href={R.obra(id)}>Ver la obra: gastos, flujo y documentos</Link> : null}
      {fases.length ? (
        <>
          <Grupo>Fases</Grupo>
          {fases.map((f) => {
            const a = av.get(f.id);
            return (
              <Fila key={f.id}>
                <b>
                  {titulo(f.fase.replace(/_/g, " "))}
                  <Etiqueta tono={f.estado === "cerrada" ? "o" : f.estado === "pendiente" ? "n" : "a"}>{f.estado === "cerrada" ? "Cerrada" : f.estado === "pendiente" ? "Por abrir" : "En curso"}</Etiqueta>
                </b>
                <span>
                  {Number(f.horas_cotizadas) ? `${Number(f.horas_cotizadas)} horas cotizadas` : "Sin horas cotizadas"}
                  {f.entrega_cliente ? ` · ${f.entrega_cliente}` : ""}
                  {a?.tareas ? ` · ${a.terminadas} de ${uno(a.tareas, "una tarea terminada", "tareas terminadas")}` : ""}
                  {!yo.es_direccion && f.fecha_compromiso ? ` · para el ${fecha(f.fecha_compromiso)}` : ""}
                  {!yo.es_direccion && f.responsable_id ? ` · responde ${equipo.find((e) => e.id === f.responsable_id)?.nombre || "dirección"}` : ""}
                </span>
                {a?.tareas ? <BarraAvance pct={(a.terminadas / a.tareas) * 100} /> : null}
                {a?.trabajo_terminado ? <span style={{ color: "var(--ok)" }}>Terminó todas sus tareas: está lista para el cierre.</span> : null}
                {dirijo && f.estado === "en_curso" ? <Link className="g-dar" href={R.tipicas(f.id)}>Repartir sus tareas típicas</Link> : null}
                {yo.registra.includes(id) && (f.estado === "en_curso" || f.estado === "en_revision") ? (
                  <Link className="g-dar" href={R.cierre(f.id)} style={{ display: "block" }}>{yo.es_direccion ? "Lista de chequeo y cierre" : "Lista de chequeo de la fase"}</Link>
                ) : null}
                {yo.es_direccion && f.estado !== "cerrada" ? (
                  <div className="dos">
                    <div>
                      <label htmlFor={`ff${f.id}`} style={{ marginTop: 10 }}>Se entrega el</label>
                      <input id={`ff${f.id}`} type="date" key={`f${f.fecha_compromiso ?? ""}`} defaultValue={f.fecha_compromiso || ""} onChange={(e) => guardaFase(f.id, { fecha_compromiso: e.target.value || null }, "Fecha de la fase guardada.")} />
                    </div>
                    <div>
                      <label htmlFor={`fr${f.id}`} style={{ marginTop: 10 }}>Responde</label>
                      <select id={`fr${f.id}`} key={`r${f.responsable_id ?? ""}`} defaultValue={f.responsable_id || ""} onChange={(e) => guardaFase(f.id, { responsable_id: e.target.value || null }, "Responsable de la fase guardado.")}>
                        <Opciones de={responden} vacia="Sin definir" />
                      </select>
                    </div>
                  </div>
                ) : null}
              </Fila>
            );
          })}
          {dirijo && yo.es_direccion && siguiente?.estado === "pendiente" ? (
            <Boton className="btn claro" accion={() => abrirFase(siguiente.id)}>Abrir {siguiente.fase.replace(/_/g, " ")}</Boton>
          ) : null}
        </>
      ) : null}

      <Grupo>Equipo</Grupo>
      {porPersona.length ? porPersona.map((e) => (
        <Fila key={e.id} style={{ display: "flex", gap: 12, alignItems: "center" }}>
          <Avatar nombre={e.nombre} otro={e.id !== yo.persona_id} />
          <div><b>{e.nombre}</b><span>{nombrarPapeles(e.papeles)} · {ROL[e.rol] || e.rol}</span></div>
        </Fila>
      )) : <Vacio corto>Todavía no tiene equipo: sin papel, nadie lo ve ni recibe tareas.</Vacio>}
      {yo.es_direccion && fuera.length ? (
        <Formulario onEnviar={async (f) => {
          const papeles = papelesDe(f, "n");
          if (!papeles.length) throw new Error("Marque al menos un papel.");
          await pedir(sb().from("acceso_proyecto").insert(papeles.map((papel) => ({ persona_id: f.persona, proyecto_id: id, papel: papel as "produce" }))));
          avisar(bien("Agregado al equipo.")); recargar();
        }}>
          <div className="dos">
            <div>
              <label htmlFor="ep">Persona</label>
              <select id="ep" name="persona"><Opciones de={fuera.map((x) => [x.id, x.nombre])} /></select>
            </div>
            <div>
              <label>Papeles</label>
              <CasillasPapel id="n" nombre="la persona" extra={[["observa", "Observa"]]} />
            </div>
          </div>
          <button className="btn claro">Agregar al equipo</button>
        </Formulario>
      ) : null}

      <Grupo>Documentos</Grupo>
      <div id="drive">{p.carpeta_drive ? <Drive url={p.carpeta_drive} /> : <Vacio corto>Este proyecto todavía no tiene su carpeta de Drive.</Vacio>}</div>
      {yo.es_direccion ? (
        <Formulario onEnviar={async (f) => {
          await pedir(sb().from("proyecto").update({ carpeta_drive: f.carpeta.trim() || null }).eq("id", id));
          avisar(bien("Carpeta guardada.")); recargar();
        }}>
          <label htmlFor="cd">Enlace de la carpeta de Drive</label>
          <input id="cd" name="carpeta" type="url" inputMode="url" placeholder="https://drive.google.com/drive/folders/…" defaultValue={p.carpeta_drive || ""} />
          <button className="btn claro">Guardar la carpeta</button>
        </Formulario>
      ) : null}
    </>
  );
}
