"use client";
// Las tarifas de diseño por área: con ellas el reporte de la cita sugiere el valor.
import { sb } from "@/lib/supabase/cliente";
import { bien, pedir } from "@/lib/pedir";
import { useSesion, useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import { UNIDAD } from "@/lib/dominio/catalogos";
import { num, pesos } from "@/lib/dominio/texto";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Boton } from "@/componentes/formularios/Boton";
import { Formulario, Opciones } from "@/componentes/formularios/Formulario";
import { Fila, Grupo, Nota, Vacio } from "@/componentes/ui/piezas";

export function Tarifas() {
  const yo = useYo();
  const { avisar, recargar } = useSesion();
  const estado = useDatos(() => pedir(sb().from("tarifa_diseno").select("id,unidad,area_desde,area_hasta,valor,alcance,activa").eq("activa", true).order("unidad").order("area_desde")), []);
  return (
    <Carga estado={estado} atras={R.ventas}>
      {(ts) => (
        <Pantalla titulo="Tarifas de diseño" atras={R.ventas} pie={R.ventas}>
          <Nota>El reporte de la cita sugiere el valor con estas tarifas cuando se escribe el área. Las escribe dirección.</Nota>
          {ts.length ? ts.map((t) => (
            <Fila key={t.id}>
              <b>{UNIDAD[t.unidad]} · de {num(t.area_desde)} a {num(t.area_hasta)} m²</b>
              <span>{pesos(t.valor)}{t.alcance ? ` · ${t.alcance}` : ""}</span>
              <Boton className="enlace" accion={async () => {
                await pedir(sb().from("tarifa_diseno").update({ activa: false }).eq("id", t.id).select("id"));
                avisar(bien("Tarifa quitada.")); recargar();
              }}>Quitarla</Boton>
            </Fila>
          )) : <Vacio>Todavía no hay tarifas.</Vacio>}
          <Grupo>Agregar una</Grupo>
          <Formulario onEnviar={async (f) => {
            const n = (v: string) => Number(String(v).replace(",", "."));
            await pedir(sb().from("tarifa_diseno").insert({ unidad: f.unidad as "diseno_arquitectonico", area_desde: n(f.desde), area_hasta: n(f.hasta), valor: Number(String(f.valor).replace(/\D/g, "")), alcance: f.alcance.trim() || null, creada_por: yo.persona_id }).select("id"));
            avisar(bien("Tarifa agregada.")); recargar();
          }}>
            <label htmlFor="tu">Para qué</label>
            <select id="tu" name="unidad" defaultValue="diseno_arquitectonico"><Opciones de={{ diseno_arquitectonico: UNIDAD.diseno_arquitectonico, interiorismo: UNIDAD.interiorismo }} /></select>
            <div className="dos">
              <div><label htmlFor="td">Desde, m²</label><input id="td" name="desde" inputMode="decimal" required /></div>
              <div><label htmlFor="th">Hasta, m²</label><input id="th" name="hasta" inputMode="decimal" required /></div>
            </div>
            <label htmlFor="tv">Valor sin IVA</label>
            <input id="tv" name="valor" inputMode="numeric" required />
            <label htmlFor="ta">Qué incluye</label>
            <input id="ta" name="alcance" placeholder="Arquitectónico y complementarios" autoComplete="off" />
            <button className="btn">Agregar la tarifa</button>
          </Formulario>
        </Pantalla>
      )}
    </Carga>
  );
}
