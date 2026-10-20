"use client";
// El reporte después de la cita: se escoge, no se escribe.
import { useState } from "react";
import { sb } from "@/lib/supabase/cliente";
import { bien, pedir, pedirUno } from "@/lib/pedir";
import { useSesion } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import { LOTE, MOTIVO, PROPOSITO, RECURSO, TIPO_CITA } from "@/lib/dominio/catalogos";
import { ahoraLocal, hoyIso } from "@/lib/dominio/fechas";
import { num, pesos } from "@/lib/dominio/texto";
import type { Json } from "@/lib/supabase/tipos";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Formulario, Opciones } from "@/componentes/formularios/Formulario";
import { Grupo, Vacio } from "@/componentes/ui/piezas";

interface OportunidadDeCita { nombre: string; unidad: string | null; valor_estimado: number | null; area_m2: number | null }

export function Reporte({ citaId }: { citaId: string }) {
  const { ir } = useSesion();
  const estado = useDatos(async () =>
    pedirUno(sb().from("cita").select("id,tipo,estado,programada_para,modalidad,oportunidad_id,oportunidad(nombre,unidad,valor_estimado,area_m2)").eq("id", citaId).maybeSingle()),
  [citaId]);
  return (
    <Carga estado={estado} atras={R.ventas}>
      {(c) => {
        if (!c) return <Pantalla titulo="Reporte de la cita" atras={R.ventas}><Vacio>Esa cita no existe o no la puede ver.</Vacio></Pantalla>;
        const op = c.oportunidad as unknown as OportunidadDeCita | null, atras = R.oportunidad(c.oportunidad_id);
        if (!["agendada", "reprogramada"].includes(c.estado)) {
          return <Pantalla titulo="Reporte de la cita" sobre={op?.nombre} atras={atras}><p className="bien">Esta cita ya tiene su reporte.</p></Pantalla>;
        }
        return <FormularioReporte cita={{ id: c.id, tipo: c.tipo, oportunidad_id: c.oportunidad_id }} op={op} atras={atras} ir={ir} />;
      }}
    </Carga>
  );
}

const SiNo = ({ id, tercera }: { id: string; tercera?: string }) => (
  <select id={id} name={id} defaultValue="">
    <option value="">Escoja</option>
    <option value="true">Sí</option>
    <option value="false">No</option>
    {tercera ? <option value="">{tercera}</option> : null}
  </select>
);

function FormularioReporte({ cita, op, atras, ir }: { cita: { id: string; tipo: string; oportunidad_id: string }; op: OportunidadDeCita | null; atras: string; ir: (r: string, a?: ReturnType<typeof bien>) => void }) {
  const primera = cita.tipo === "viabilidad";
  const [llego, setLlego] = useState("true");
  const [sigue, setSigue] = useState(primera ? "cotizar" : "contrato");
  const [sugerido, setSugerido] = useState("");
  const si = llego === "true";

  const sugerir = async (texto: string) => {
    const area = Number(String(texto).replace(",", "."));
    if (!area) { setSugerido(""); return; }
    try {
      const v = await pedir(sb().rpc("valor_sugerido", { p_unidad: "diseno_arquitectonico", p_area: area }));
      setSugerido(v ? `Según las tarifas, para ${num(area)} m² son ${pesos(v)}. Si deja el valor vacío, se usa ese.` : "No hay tarifa escrita para esa área: escriba el valor.");
    } catch { setSugerido(""); }
  };

  return (
    <Pantalla titulo="Después de la cita" sobre={`${op?.nombre} · ${TIPO_CITA[cita.tipo]}`} atras={atras}>
      <Formulario onEnviar={async (f) => {
        const b = (v: string | undefined) => v === "true" ? true : v === "false" ? false : null;
        const numero = (v: string | undefined) => v ? Number(String(v).replace(/[^\d,.]/g, "").replace(",", ".")) : null;
        const datos: Record<string, unknown> = { llego: f.llego === "true", grabacion: b(f.grabacion), transcripcion: f.transcripcion || null, sigue: f.sigue, cuando: f.cuando || null,
          seguimiento: f.seguimiento || null, motivo: f.motivo || null, detalle: f.detalle || null };
        if ("decisor_presente" in f) Object.assign(datos, { decisor_presente: b(f.decisor_presente), tiene_lote: f.tiene_lote || null, recurso_disponible: f.recurso_disponible || null,
          proposito: f.proposito || null, primera_cotizacion: b(f.primera_cotizacion), area: numero(f.area), valor: f.valor ? Number(String(f.valor).replace(/\D/g, "")) : null });
        await pedir(sb().rpc("reporte_de_cita", { p_cita: cita.id, p_datos: datos as unknown as Json }));
        ir(R.oportunidad(cita.oportunidad_id), bien(!datos.llego ? "Quedó que no llegó. El siguiente paso es reagendarla."
          : ({ cotizar: "Reporte guardado y presentación agendada. Ya puede preparar la cotización.", otra_cita: "Reporte guardado y reunión agendada.",
            pensarlo: "Reporte guardado. Le toca la llamada el día que escogió.", contrato: "Reporte guardado: pasa a contrato y anticipo.", no_sigue: "Reporte guardado: quedó como perdida, con su motivo." } as Record<string, string>)[String(datos.sigue)]));
      }}>
        <label htmlFor="llego">¿Llegó?</label>
        <select id="llego" name="llego" value={llego} onChange={(e) => setLlego(e.target.value)}>
          <option value="true">Sí, fue la reunión</option>
          <option value="false">No llegó</option>
        </select>
        <div hidden={!si}>
          <label htmlFor="grabacion">¿Autorizó grabarla?</label><SiNo id="grabacion" />
          <label htmlFor="transcripcion">Enlace de la transcripción, si hay</label>
          <input id="transcripcion" name="transcripcion" type="url" inputMode="url" placeholder="https://docs.google.com/…" autoComplete="off" />
          {primera ? (
            <>
              <Grupo>Lo que dejó la cita</Grupo>
              <label htmlFor="decisor_presente">¿Estaba quien decide?</label><SiNo id="decisor_presente" />
              <label htmlFor="tiene_lote">¿Tiene lote?</label>
              <select id="tiene_lote" name="tiene_lote" defaultValue=""><Opciones de={LOTE} vacia="Escoja" /></select>
              <label htmlFor="recurso_disponible">¿Cuándo tiene el recurso?</label>
              <select id="recurso_disponible" name="recurso_disponible" defaultValue=""><Opciones de={RECURSO} vacia="Escoja" /></select>
              <label htmlFor="proposito">¿Para qué es?</label>
              <select id="proposito" name="proposito" defaultValue=""><Opciones de={PROPOSITO} vacia="Escoja" /></select>
              <label htmlFor="primera_cotizacion">¿Somos la primera cotización que pide?</label><SiNo id="primera_cotizacion" tercera="No lo dijo" />
              <div className="dos">
                <div><label htmlFor="area">Área aproximada, m²</label><input id="area" name="area" inputMode="decimal" defaultValue={op?.area_m2 ?? ""} onChange={(e) => sugerir(e.target.value)} /></div>
                <div><label htmlFor="valor">Valor estimado</label><input id="valor" name="valor" inputMode="numeric" defaultValue={op?.valor_estimado ? Math.round(op.valor_estimado) : ""} placeholder="Lo sugiere la tarifa" /></div>
              </div>
              <p className="pista" id="sugerido">{sugerido}</p>
            </>
          ) : null}
          <Grupo>Cómo sigue</Grupo>
          <label htmlFor="sigue">Escoja</label>
          <select id="sigue" name="sigue" required value={sigue} onChange={(e) => setSigue(e.target.value)}>
            {primera ? <option value="cotizar">Le presentamos la cotización</option> : <option value="contrato">Acepta: firma y paga el anticipo</option>}
            <option value="otra_cita">Otra reunión</option>
            <option value="pensarlo">Lo va a pensar</option>
            <option value="no_sigue">No sigue</option>
          </select>
          <div hidden={!["cotizar", "otra_cita"].includes(sigue)}>
            <label htmlFor="cuando">{sigue === "cotizar" ? "Cuándo se le presenta la cotización" : "Cuándo es la reunión"}</label>
            <input id="cuando" name="cuando" type="datetime-local" min={ahoraLocal()} />
          </div>
          <div hidden={sigue !== "pensarlo"}>
            <label htmlFor="seguimiento">Cuándo se le vuelve a llamar</label>
            <input id="seguimiento" name="seguimiento" type="date" min={hoyIso()} />
          </div>
          <div hidden={sigue !== "no_sigue"}>
            <label htmlFor="motivo">Por qué no sigue</label>
            <select id="motivo" name="motivo" defaultValue=""><Opciones de={MOTIVO} vacia="Escoja" /></select>
            <label htmlFor="detalle">Lo que dijo, si quiere dejarlo</label>
            <input id="detalle" name="detalle" autoComplete="off" />
          </div>
        </div>
        <button className="btn">Guardar el reporte</button>
      </Formulario>
    </Pantalla>
  );
}
