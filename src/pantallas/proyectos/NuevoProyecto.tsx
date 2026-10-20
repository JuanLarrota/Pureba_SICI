"use client";
// Crear un proyecto desde su plantilla: nombre, código, tipo, unidad, horas
// cotizadas por fase y los papeles de cada persona del equipo (puede tener varios).
import { useState } from "react";
import { sb } from "@/lib/supabase/cliente";
import { bien, pedir } from "@/lib/pedir";
import { useSesion, useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import { ORDEN_PLANTILLAS, UNIDAD } from "@/lib/dominio/catalogos";
import { titulo } from "@/lib/dominio/texto";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Formulario, Opciones } from "@/componentes/formularios/Formulario";
import { Grupo, Nota } from "@/componentes/ui/piezas";
import { CasillasPapel } from "./papeles";

interface FasePlantilla { fase: string; orden: number; opcional: boolean }
interface Plantilla { id: string; nombre: string; tipo: string; descripcion: string | null; plantilla_fase: FasePlantilla[] }

export function NuevoProyecto({ tipo }: { tipo: string | null }) {
  const yo = useYo();
  const estado = useDatos(async () => {
    const [plantillas, personas] = await Promise.all([
      pedir(sb().from("plantilla_proyecto").select("id,nombre,tipo,descripcion,plantilla_fase(fase,orden,opcional)").eq("activa", true)),
      pedir(sb().from("persona").select("id,nombre,rol").eq("es_interno", true).eq("activo", true).order("nombre")),
    ]);
    const ordenadas = (plantillas as unknown as Plantilla[]).slice().sort((a, b) => ORDEN_PLANTILLAS.indexOf(a.nombre) - ORDEN_PLANTILLAS.indexOf(b.nombre));
    return { plantillas: ordenadas, personas };
  }, [yo.persona_id]);
  return (
    <Carga estado={estado} atras={R.proyectos}>
      {({ plantillas, personas }) => <FormularioProyecto plantillas={plantillas} personas={personas} tipo={tipo} />}
    </Carga>
  );
}

function FormularioProyecto({ plantillas, personas, tipo }: { plantillas: Plantilla[]; personas: { id: string; nombre: string; rol: string }[]; tipo: string | null }) {
  const { ir, recargarSesion } = useSesion();
  const deObra = tipo === "obra" ? plantillas.find((x) => x.tipo === "obra") ?? null : null;
  const [plantillaId, setPlantillaId] = useState(deObra?.id ?? plantillas[0]?.id ?? "");
  const pl = plantillas.find((x) => x.id === plantillaId);
  const fases = [...(pl?.plantilla_fase ?? [])].sort((a, b) => a.orden - b.orden);
  return (
    <Pantalla titulo={deObra ? "Abrir una obra" : "Crear proyecto nuevo"} atras={deObra ? R.obras : R.proyectos}>
      <Formulario onEnviar={async (f) => {
        const horas: Record<string, number> = {}, omitir: string[] = [], equipo: { persona_id: string; papel: string }[] = [];
        for (const [k, v] of Object.entries(f)) {
          if (k.startsWith("aplica:") && v === "no") omitir.push(k.slice(7));
          if (k.startsWith("papel:") && v) { const [, persona_id, papel] = k.split(":"); equipo.push({ persona_id, papel }); }
        }
        for (const [k, v] of Object.entries(f)) if (k.startsWith("horas:") && v && !omitir.includes(k.slice(6))) horas[k.slice(6)] = Number(v);
        const id = (await pedir(sb().rpc("abrir_proyecto", { p_codigo: f.codigo.trim().toUpperCase(), p_nombre: f.nombre.trim(), p_plantilla: f.plantilla, p_unidad: f.unidad as "diseno_arquitectonico",
          p_horas: horas, p_equipo: equipo, p_omitir: omitir as "insight"[] }))) as unknown as string;
        if (f.carpeta.trim()) await pedir(sb().from("proyecto").update({ carpeta_drive: f.carpeta.trim() }).eq("id", id));
        await recargarSesion();   // la ficha de quien abre cambia: ahora dirige o registra en este proyecto
        if (plantillas.find((x) => x.id === f.plantilla)?.tipo === "obra") return ir(R.obra(id), bien("Obra abierta. Escriba el valor del contrato, el residente y las fechas."));
        ir(R.proyecto(id), bien("Proyecto abierto con sus fases y su equipo."));
      }}>
        <label htmlFor="np">Nombre</label>
        <input id="np" name="nombre" required autoComplete="off" />
        <label htmlFor="co">Código corto</label>
        <input id="co" name="codigo" required autoComplete="off" placeholder="CASA GO" style={{ textTransform: "uppercase" }} />
        <label htmlFor="pl">Tipo de proyecto</label>
        <select id="pl" name="plantilla" value={plantillaId} onChange={(e) => setPlantillaId(e.target.value)}>
          <Opciones de={plantillas.map((x) => [x.id, x.nombre])} />
        </select>
        <label htmlFor="un">Unidad de negocio</label>
        <select id="un" name="unidad" defaultValue={deObra ? "obra_propia" : Object.keys(UNIDAD)[0]}><Opciones de={UNIDAD} /></select>
        {/* Al cambiar de plantilla los campos de horas vuelven a empezar. */}
        <div id="fases" key={plantillaId}>
          {fases.length ? (
            <>
              <Grupo>Horas cotizadas por fase</Grupo>
              {fases.map((f) => (
                <div key={f.fase} className="linea">
                  <b>{titulo(f.fase.replace(/_/g, " "))}</b>
                  {f.opcional ? <select name={`aplica:${f.fase}`} aria-label="¿Aplica?" defaultValue="si"><option value="si">Aplica</option><option value="no">No aplica</option></select> : null}
                  <input type="number" name={`horas:${f.fase}`} min={0} step={1} inputMode="numeric" placeholder="0" aria-label={`Horas de ${f.fase}`} />
                </div>
              ))}
            </>
          ) : <Nota>Este tipo de proyecto no tiene fases.</Nota>}
        </div>
        <Grupo>Equipo</Grupo>
        <Nota style={{ marginTop: 0 }}>Marque uno o varios papeles por persona. Sin ninguno, no participa.</Nota>
        {personas.map((x) => (
          <div key={x.id} className="linea">
            <b>{x.nombre}</b>
            <CasillasPapel id={x.id} nombre={x.nombre} />
          </div>
        ))}
        <label htmlFor="ca">Carpeta de Drive (opcional)</label>
        <input id="ca" name="carpeta" type="url" inputMode="url" placeholder="https://drive.google.com/drive/folders/…" />
        <button className="btn">Crear el proyecto</button>
      </Formulario>
    </Pantalla>
  );
}
