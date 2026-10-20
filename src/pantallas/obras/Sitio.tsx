"use client";
// La bitácora del día: quiénes estaban, en qué frente, qué avanzó, qué pasó.
import { sb } from "@/lib/supabase/cliente";
import { bien, pedir } from "@/lib/pedir";
import { useSesion, useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { nombresDe } from "@/lib/consultas";
import { R } from "@/lib/rutas";
import { CLIMA } from "@/lib/dominio/catalogos";
import { corta, diaSemana, fecha, hoyIso } from "@/lib/dominio/fechas";
import { lista, titulo, uno } from "@/lib/dominio/texto";
import type { VBitacoraFaltante } from "@/lib/supabase/vistas";
import { Formulario } from "@/componentes/formularios/Formulario";
import { Fila, Grupo, Vacio } from "@/componentes/ui/piezas";
import { CargaSeccion, type PropsSeccion } from "./Obra";

export function Sitio({ o, registra }: PropsSeccion) {
  const yo = useYo();
  const { ir } = useSesion();
  const estado = useDatos(async () => {
    const [dias, faltan] = await Promise.all([
      pedir(sb().from("bitacora").select("id,fecha,personal_sitio,frente_trabajo,avance,novedad,clima,registrado_por").eq("proyecto_id", o.id).order("fecha", { ascending: false }).limit(10)),
      pedir(sb().from("v_bitacora_faltante").select("fecha").eq("proyecto_id", o.id).order("fecha", { ascending: false }).overrideTypes<Pick<VBitacoraFaltante, "fecha">[], { merge: false }>()),
    ]);
    const quien = await nombresDe(dias.map((d) => d.registrado_por));
    return { dias, faltan, quien };
  }, [o.id]);

  return (
    <CargaSeccion estado={estado}>
      {({ dias, faltan, quien }) => {
        const hoy = hoyIso(), deHoy = dias.find((d) => d.fecha === hoy);
        return (
          <>
            {faltan.length ? (
              <div className={faltan.length >= 3 ? "error" : "nota"} role="status">
                {faltan.length === 1 ? "Falta la bitácora del " + fecha(faltan[0].fecha) : `Faltan ${faltan.length} días de bitácora en el último mes: ${lista(faltan.slice(0, 6).map((f) => corta(f.fecha)))}${faltan.length > 6 ? "…" : ""}`}.
              </div>
            ) : null}
            {registra ? (
              <details open={!deHoy}>
                <summary className={`btn${deHoy ? " claro" : ""}`}>{deHoy ? "Registrar otro día" : "Bitácora de hoy"}</summary>
                <Formulario onEnviar={async (f) => {
                  const { error } = await sb().from("bitacora").insert({ proyecto_id: o.id, fecha: f.fecha, personal_sitio: f.personal === "" ? null : Number(f.personal),
                    frente_trabajo: f.frente.trim() || null, avance: f.avance.trim() || null, novedad: f.novedad.trim() || null, clima: f.clima || null, registrado_por: yo.persona_id });
                  if (error) throw /duplicate key/i.test(error.message) ? new Error(`Ya hay bitácora del ${fecha(f.fecha)} en esta obra.`) : error;
                  ir(R.obra(o.id, "sitio"), bien("Bitácora guardada."));
                }}>
                  <label htmlFor="bd">Día</label>
                  <input id="bd" name="fecha" type="date" defaultValue={deHoy ? (faltan[0]?.fecha || "") : hoy} max={hoy} required />
                  <div className="dos">
                    <div><label htmlFor="bp">Personas en obra</label><input id="bp" name="personal" type="number" min={0} inputMode="numeric" placeholder="0" /></div>
                    <div><label htmlFor="bc">Clima</label><select id="bc" name="clima" defaultValue=""><option value="">Sin anotar</option>{CLIMA.map((c) => <option key={c}>{c}</option>)}</select></div>
                  </div>
                  <label htmlFor="bf">Frente de trabajo</label>
                  <input id="bf" name="frente" autoComplete="off" placeholder="Mampostería segundo piso" />
                  <label htmlFor="ba">Qué avanzó</label>
                  <textarea id="ba" name="avance" />
                  <label htmlFor="bn">Novedades (si hubo)</label>
                  <textarea id="bn" name="novedad" placeholder="Llegó tarde el material, visita del cliente…" />
                  <button className="btn">Guardar la bitácora</button>
                </Formulario>
              </details>
            ) : null}
            <Grupo>Últimos días</Grupo>
            {dias.map((d) => (
              <Fila key={d.id}>
                <b>{titulo(diaSemana(d.fecha))} {fecha(d.fecha)}{d.personal_sitio != null ? ` · ${uno(d.personal_sitio, "una persona", "personas")}` : ""}</b>
                <span>{[d.frente_trabajo, d.clima].filter(Boolean).join(" · ")}</span>
                {d.avance ? <span>{d.avance}</span> : null}
                {d.novedad ? <span><em>{d.novedad}</em></span> : null}
                <span>La escribió {quien.get(d.registrado_por || "") || "alguien"}</span>
              </Fila>
            ))}
            {dias.length ? null : <Vacio corto>Todavía no hay bitácora en esta obra.</Vacio>}
          </>
        );
      }}
    </CargaSeccion>
  );
}
