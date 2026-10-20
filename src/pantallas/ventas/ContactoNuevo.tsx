"use client";
// Un contacto nuevo: por dónde llegó, qué escribió y, si ya aceptó la cita, cuándo.
import { sb } from "@/lib/supabase/cliente";
import { bien, pedir } from "@/lib/pedir";
import { useSesion, useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { gente } from "@/lib/consultas";
import { R } from "@/lib/rutas";
import { CANAL, UNIDAD } from "@/lib/dominio/catalogos";
import { ahoraLocal } from "@/lib/dominio/fechas";
import type { Json } from "@/lib/supabase/tipos";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Formulario, Opciones } from "@/componentes/formularios/Formulario";
import { Grupo } from "@/componentes/ui/piezas";

export function ContactoNuevo() {
  const yo = useYo();
  const { ir } = useSesion();
  const estado = useDatos(() => gente(), []);
  return (
    <Carga estado={estado} atras={R.ventas}>
      {(equipo) => (
        <Pantalla titulo="Nuevo contacto" atras={R.ventas}>
          <Formulario onEnviar={async (f) => {
            const r = (await pedir(sb().rpc("nuevo_contacto", { p_datos: f as unknown as Json }))) as unknown as { oportunidad_id?: string | null };
            ir(r.oportunidad_id ? R.oportunidad(r.oportunidad_id) : R.ventas, bien(r.oportunidad_id ? "Contacto guardado y cita agendada." : "Contacto guardado. Queda en «Para hoy» hasta el primer contacto."));
          }}>
            <label htmlFor="nn">Nombre</label>
            <input id="nn" name="nombre" autoComplete="off" />
            <div className="dos">
              <div><label htmlFor="nt">Teléfono</label><input id="nt" name="telefono" type="tel" inputMode="tel" autoComplete="off" /></div>
              <div><label htmlFor="nc">Ciudad</label><input id="nc" name="ciudad" autoComplete="off" /></div>
            </div>
            <label htmlFor="ne">Correo</label>
            <input id="ne" name="correo" type="email" inputMode="email" autoComplete="off" />
            <label htmlFor="nk">Por dónde llegó</label>
            <select id="nk" name="canal" required defaultValue=""><Opciones de={CANAL} vacia="Escoja" /></select>
            <label htmlFor="nf">Cómo dice que nos encontró</label>
            <select id="nf" name="como_nos_encontro" defaultValue=""><Opciones de={CANAL} vacia="No lo dijo" /></select>
            <label htmlFor="nm">Lo que escribió</label>
            <textarea id="nm" name="mensaje" />
            <Grupo>Si ya aceptó la cita</Grupo>
            <label htmlFor="nci">Cuándo</label>
            <input id="nci" name="cita" type="datetime-local" min={ahoraLocal()} />
            <div className="dos">
              <div><label htmlFor="nu">Qué busca</label><select id="nu" name="unidad" defaultValue="diseno_arquitectonico"><Opciones de={UNIDAD} /></select></div>
              <div><label htmlFor="nr">Quién hace la cita</label><select id="nr" name="responsable_id" defaultValue={yo.persona_id}><Opciones de={equipo.map((p) => [p.id, p.nombre])} /></select></div>
            </div>
            <button className="btn">Guardar el contacto</button>
          </Formulario>
        </Pantalla>
      )}
    </Carga>
  );
}
