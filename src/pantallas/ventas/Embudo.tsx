"use client";
// Las oportunidades de una etapa del embudo, en una línea de negocio.
import { sb } from "@/lib/supabase/cliente";
import { pedir } from "@/lib/pedir";
import { useDatos } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import { ETAPA, LINEA, lineaDe } from "@/lib/dominio/catalogos";
import { fecha, hoyIso } from "@/lib/dominio/fechas";
import { pesos } from "@/lib/dominio/texto";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Fila, Vacio } from "@/componentes/ui/piezas";

export function Embudo({ linea, etapa }: { linea: string; etapa: string }) {
  const estado = useDatos(async () => {
    const ops = await pedir(sb().from("oportunidad").select("id,nombre,unidad,etapa,valor_estimado,siguiente_paso,siguiente_paso_en")
      .eq("etapa", etapa as "cita_viabilidad").order("siguiente_paso_en"));
    return ops.filter((o) => lineaDe(o.unidad) === linea);
  }, [linea, etapa]);
  const hoy = hoyIso();
  return (
    <Carga estado={estado} atras={R.ventas}>
      {(ops) => (
        <Pantalla titulo={ETAPA[etapa] || etapa} sobre={LINEA[linea]} atras={R.ventas} pie={R.ventas}>
          {ops.length ? ops.map((o) => {
            const tarde = !!o.siguiente_paso_en && o.siguiente_paso_en < hoy;
            const paso = `${o.siguiente_paso} · ${fecha(o.siguiente_paso_en)}`;
            return (
              <Fila key={o.id} href={R.oportunidad(o.id)}>
                <b>{o.nombre}</b>
                <span>{pesos(o.valor_estimado)} · {tarde ? <em>{paso}</em> : paso}</span>
              </Fila>
            );
          }) : <Vacio>Ninguna en esta etapa.</Vacio>}
        </Pantalla>
      )}
    </Carga>
  );
}
