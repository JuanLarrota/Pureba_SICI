"use client";
// El flujo de cada tipo de proyecto: lo que pide cada fase, cuánto puede durar,
// quién responde, su lista de chequeo y sus tareas típicas. Dirección lo edita
// aquí; los datos sueltos (plazo, quién responde) se guardan sin repintar.
import { useState } from "react";
import { sb } from "@/lib/supabase/cliente";
import { bien, decir, pedir } from "@/lib/pedir";
import { useSesion, useYo } from "@/lib/sesion";
import { PUNTO, RESPONDE } from "@/lib/dominio/catalogos";
import { ESFUERZO, esfuerzo, lista, nFase, titulo, uno } from "@/lib/dominio/texto";
import { Boton } from "@/componentes/formularios/Boton";
import { Formulario, Opciones } from "@/componentes/formularios/Formulario";
import type { ListaCierre, PlantillaFaseMando, PlantillaMando } from "./tipos";

interface Props {
  pl: PlantillaMando;
  listaDe: (plantilla: string, fase: string) => ListaCierre | undefined;
  abierta: boolean;
  alCambiar: (flujoId: string) => void;   // qué flujo debe quedar abierto tras repintar
}

/** Guardar un dato del flujo sin repintar la pantalla: el comité sigue donde iba. */
function useGuardaFlujo(faseId: string) {
  const [marca, setMarca] = useState<{ texto: string; mal: boolean } | null>(null);
  const guardar = async (cambio: { dias_habiles_plazo?: number | null; responsable_papel?: "dirige" | "revisa" | "produce" }) => {
    try {
      const r = await pedir(sb().from("plantilla_fase").update(cambio).eq("id", faseId).select("id"));
      if (!r.length) throw new Error("Solo dirección cambia el flujo.");
      setMarca({ texto: "Guardado", mal: false });
    } catch (e) {
      const d = decir(e);
      setMarca({ texto: d.includes("plazo_sano") ? "Entre 1 y 400 días" : d, mal: true });
    }
  };
  const Marca = () => <i className={marca?.mal ? "m-ok mal" : "m-ok"} aria-live="polite">{marca?.texto || ""}</i>;
  return { guardar, Marca };
}

function Fase({ f, i, pl, listaDe, alCambiar }: { f: PlantillaFaseMando; i: number } & Omit<Props, "abierta">) {
  const yo = useYo();
  const { avisar, recargar } = useSesion();
  const { guardar, Marca } = useGuardaFlujo(f.id);
  const [plazoGuardado, setPlazoGuardado] = useState(f.dias_habiles_plazo == null ? "" : String(f.dias_habiles_plazo));
  const exige = [f.exige_chequeo && "lista de chequeo", f.exige_aprobacion_cliente && "aprobación del cliente", f.exige_dedicacion && "dedicación registrada"].filter((x): x is string => !!x);
  const tt = (f.plantilla_tarea || []).filter((x) => x.activa !== false).sort((a, b) => a.orden - b.orden);
  const l = listaDe(pl.id, f.fase), pts = (l?.lista_chequeo_item || []).filter((x) => x.activo !== false).sort((a, b) => a.orden - b.orden), propia = l?.plantilla_id === pl.id;
  const listo = (dicho: string) => { alCambiar(pl.id); avisar(bien(dicho)); recargar(); };
  return (
    <div className="m-f">
      <small>{String(i + 1).padStart(2, "0")}{f.opcional ? " · si aplica" : ""}</small>
      <b>{nFase(f.fase)}</b>
      <p><span>Entrega al cliente</span>{f.entrega_cliente ? f.entrega_cliente : "Sin definir"}</p>
      <p>
        <span>Tiempo máximo</span>
        {yo.es_direccion ? (
          <>
            <label className="m-en">
              <input type="number" min={1} max={400} inputMode="numeric" defaultValue={f.dias_habiles_plazo ?? ""} placeholder="–" aria-label={`Días hábiles de ${nFase(f.fase)}`}
                onBlur={(e) => { if (e.target.value !== plazoGuardado) { setPlazoGuardado(e.target.value); guardar({ dias_habiles_plazo: e.target.value === "" ? null : Number(e.target.value) }); } }} />
              {" "}días hábiles
            </label>
            <Marca />
          </>
        ) : f.dias_habiles_plazo ? `${f.dias_habiles_plazo} días hábiles` : "Sin plazo"}
      </p>
      <p>
        <span>Responde</span>
        {yo.es_direccion ? (
          <>
            <select defaultValue={f.responsable_papel || "dirige"} aria-label={`Quién responde por ${nFase(f.fase)}`} onChange={(e) => guardar({ responsable_papel: e.target.value as "dirige" })}>
              <Opciones de={RESPONDE} />
            </select>
            <Marca />
          </>
        ) : RESPONDE[f.responsable_papel || ""] || "Quien dirige"}
      </p>
      <p><span>Para cerrarla</span>{exige.length ? titulo(exige[0][0]) + lista(exige).slice(1) : "Nada"}</p>
      <div className="m-tt">
        <span>Lista de chequeo</span>
        {pts.length ? pts.map((x) => (
          <p key={x.id}>
            {x.texto}
            <small>{PUNTO[x.tipo] || x.tipo}{x.tipo === "opcion" ? `: ${lista(x.opciones || [])}` : ""}{x.obligatorio ? "" : " · opcional"}</small>
            {yo.es_direccion && propia ? (
              <Boton className="enlace" accion={async () => {
                const r = await pedir(sb().from("lista_chequeo_item").update({ activo: false }).eq("id", x.id).select("id"));
                if (!r.length) throw new Error("La lista de chequeo la cambia dirección.");
                listo("Ese punto ya no se pide.");
              }}>Quitar</Boton>
            ) : null}
          </p>
        )) : <p>{f.exige_chequeo ? <em>Sin puntos: así la fase no se puede cerrar</em> : "No pide lista"}</p>}
        {pts.length && !propia ? <p><small>Es la lista general de esta fase. Al agregar un punto se crea una propia de este tipo de proyecto.</small></p> : null}
        {yo.es_direccion ? (
          <details>
            <summary>Agregar un punto</summary>
            <Formulario onEnviar={async (d) => {
              const opciones = d.opciones.split(",").map((x) => x.trim()).filter(Boolean);
              if (d.tipo === "opcion" && opciones.length < 2) throw new Error("Para escoger hacen falta al menos dos opciones, separadas por coma.");
              await pedir(sb().rpc("punto_de_cierre", { p_plantilla_fase: f.id, p_texto: d.texto.trim(), p_tipo: d.tipo, p_opciones: d.tipo === "opcion" ? opciones : undefined, p_obligatorio: !!d.obligatorio }));
              listo("Punto guardado: se pedirá para cerrar esta fase, también en los proyectos que ya la tienen abierta.");
            }}>
              <label>Qué se verifica<input name="texto" required minLength={4} autoComplete="off" /></label>
              <label>Cómo se responde<select name="tipo" defaultValue="casilla"><Opciones de={PUNTO} /></select></label>
              <label>Opciones, separadas por coma (solo si se escoge)<input name="opciones" autoComplete="off" placeholder="Sí, No aplica" /></label>
              <label>Es obligatorio<select name="obligatorio" defaultValue="si"><option value="si">Sí: sin él la fase no cierra</option><option value="">No: se pregunta, pero no frena</option></select></label>
              <button className="btn claro">Guardar el punto</button>
            </Formulario>
          </details>
        ) : null}
      </div>
      <div className="m-tt">
        <span>Tareas típicas</span>
        {tt.length ? tt.map((x) => (
          <p key={x.id}>
            {x.titulo}
            <small>{[x.por_espacio && "una por espacio", x.dias_plazo != null && `se entrega en ${x.dias_plazo} días hábiles`, x.dias_estimados != null && `pide ${esfuerzo(x.dias_estimados)}`].filter(Boolean).join(" · ")}</small>
            {yo.es_direccion ? (
              <Boton className="enlace" accion={async () => {
                const r = await pedir(sb().from("plantilla_tarea").update({ activa: false }).eq("id", x.id).select("id"));
                if (!r.length) throw new Error("Las tareas típicas las cambia dirección.");
                listo("Ya no se propone. Las tareas que se crearon con ella siguen como estaban.");
              }}>Quitar</Boton>
            ) : null}
          </p>
        )) : <p>Sin definir</p>}
        {yo.es_direccion ? (
          <details>
            <summary>Agregar una tarea típica</summary>
            <Formulario onEnviar={async (d) => {
              await pedir(sb().from("plantilla_tarea").insert({ plantilla_fase_id: f.id, orden: (tt.at(-1)?.orden || 0) + 10, titulo: d.titulo.trim(), proposito: d.proposito.trim(),
                por_espacio: !!d.por_espacio, dias_plazo: d.dias_plazo === "" ? null : Number(d.dias_plazo), dias_estimados: Number(d.dias) }));
              listo("Tarea típica guardada: se propondrá cada vez que se abra esta fase.");
            }}>
              <label>Qué hay que entregar<input name="titulo" required minLength={4} autoComplete="off" /></label>
              <label>Para qué sirve en el proyecto<textarea name="proposito" required minLength={12} /></label>
              <label>Se repite<select name="por_espacio" defaultValue=""><option value="">Una vez en la fase</option><option value="si">Una por cada espacio</option></select></label>
              <label>Se entrega en (días hábiles)<input name="dias_plazo" type="number" min={0} max={120} inputMode="numeric" /></label>
              <label>Trabajo que pide<select name="dias" required defaultValue=""><Opciones de={ESFUERZO.map(([v, n]) => [String(v), n])} vacia="Escoja" /></select></label>
              <button className="btn claro">Guardar la tarea típica</button>
            </Formulario>
          </details>
        ) : null}
      </div>
    </div>
  );
}

export function Flujo({ pl, listaDe, abierta, alCambiar }: Props) {
  const fs = [...(pl.plantilla_fase || [])].sort((a, b) => a.orden - b.orden);
  const total = fs.reduce((n, f) => n + (f.dias_habiles_plazo || 0), 0), sin = fs.filter((f) => !f.dias_habiles_plazo).length;
  return (
    <details className="m-p" open={abierta}>
      <summary>
        <b>{pl.nombre}</b>
        <span>{pl.descripcion || ""}</span>
        <span className="m-r">
          {!fs.length ? "Sin fases" : (
            <>
              {uno(fs.length, "Una fase", "fases")}
              {total ? ` · ${total} días hábiles${sin ? " en las que tienen plazo" : " de principio a fin"}` : ""}
              {sin ? <> · <em>{sin === fs.length ? "ninguna tiene plazo todavía" : uno(sin, "una sin plazo", "sin plazo")}</em></> : null}
            </>
          )}
        </span>
      </summary>
      <div className="m-flujo">
        {fs.length ? fs.map((f, i) => <Fase key={f.id} f={f} i={i} pl={pl} listaDe={listaDe} alCambiar={alCambiar} />)
          : <p className="m-nada">Este tipo de proyecto no tiene fases: solo tareas.</p>}
      </div>
    </details>
  );
}
