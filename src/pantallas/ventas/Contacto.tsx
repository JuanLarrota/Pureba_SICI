"use client";
// Un contacto: los intentos, y la cita cuando la acepta.
import { useEffect } from "react";
import { sb } from "@/lib/supabase/cliente";
import { bien, pedir, pedirUno } from "@/lib/pedir";
import { useSesion, useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { gente } from "@/lib/consultas";
import { R } from "@/lib/rutas";
import { CANAL, ESTADO_LEAD, UNIDAD } from "@/lib/dominio/catalogos";
import { ahoraLocal, momento } from "@/lib/dominio/fechas";
import { whatsapp } from "@/lib/dominio/texto";
import type { Json } from "@/lib/supabase/tipos";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Boton } from "@/componentes/formularios/Boton";
import { Formulario, Opciones } from "@/componentes/formularios/Formulario";
import { Fila, Grupo, Nota, Vacio } from "@/componentes/ui/piezas";

export function Contacto({ id }: { id: string }) {
  const yo = useYo();
  const { ir, avisar, recargar } = useSesion();
  const estado = useDatos(async () => {
    const [l, intentos, equipo] = await Promise.all([
      pedirUno(sb().from("lead").select("id,nombre,telefono,correo,ciudad,canal,como_nos_encontro,mensaje_inicial,estado,creado_en,primer_contacto_en,motivo_descarte").eq("id", id).maybeSingle()),
      pedir(sb().from("contacto_lead").select("fecha,medio,direccion,respondio,nota").eq("lead_id", id).order("fecha")),
      gente(),
    ]);
    if (!l) return null;
    const [op] = await pedir(sb().from("oportunidad").select("id").eq("lead_id", id));
    return { l, intentos, equipo, redirigir: op?.id ?? null };
  }, [id]);

  return (
    <Carga estado={estado} atras={R.ventas}>
      {(d) => {
        if (!d) return <Pantalla titulo="Contacto" atras={R.ventas}><Vacio>Ese contacto no existe o no lo puede ver.</Vacio></Pantalla>;
        if (d.redirigir) return <Redirigir a={R.oportunidad(d.redirigir)} />;
        const { l, intentos, equipo } = d;
        const vivo = !["descartado", "convertido"].includes(l.estado);
        return (
          <Pantalla titulo={l.nombre || l.telefono || "Contacto"} sobre={ESTADO_LEAD[l.estado] || l.estado} atras={R.ventas} pie={R.ventas}>
            <Fila>
              <b>
                {l.telefono ? <a href={`tel:${l.telefono}`}>{l.telefono}</a> : "Sin teléfono"}
                {l.telefono ? <> · <a href={whatsapp(l.telefono)} target="_blank" rel="noopener">WhatsApp</a></> : null}
              </b>
              <span>{l.correo ? `${l.correo} · ` : ""}{l.ciudad ? `${l.ciudad} · ` : ""}llegó por {CANAL[l.canal] || l.canal} el {momento(l.creado_en)}</span>
              {l.mensaje_inicial ? <span>«{l.mensaje_inicial}»</span> : null}
            </Fila>
            {l.estado === "nutricion" ? <Nota>Está en nutrición: tres intentos sin respuesta. Si vuelve a escribir, sale solo.</Nota> : null}
            {l.estado === "descartado" ? <Nota>Descartado: {l.motivo_descarte}.</Nota> : null}
            <Grupo>Intentos</Grupo>
            {intentos.length ? intentos.map((i, k) => (
              <Fila key={k}>
                <span>{momento(i.fecha)} · {i.direccion === "entrante" ? "escribió él" : i.respondio ? "respondió" : "no respondió"} · {i.medio}{i.nota ? ` · ${i.nota}` : ""}</span>
              </Fila>
            )) : <Vacio corto>Ninguno todavía.</Vacio>}
            {vivo ? (
              <>
                <div className="par">
                  {([["false", "No respondió"], ["true", "Respondió"]] as [string, string][]).map(([r, n]) => (
                    <Boton key={r} className="btn claro" accion={async () => {
                      await pedir(sb().from("contacto_lead").insert({ lead_id: l.id, medio: "whatsapp", direccion: "saliente", respondio: r === "true", registrado_por: yo.persona_id }).select("id"));
                      avisar(bien(r === "true" ? "Quedó que respondió." : "Intento registrado. Al tercero sin respuesta pasa a nutrición.")); recargar();
                    }}>{n}</Boton>
                  ))}
                </div>
                <Grupo>Agendar la cita de viabilidad</Grupo>
                <Formulario onEnviar={async (f) => {
                  const r = (await pedir(sb().rpc("agendar_cita_de_lead", { p_lead: l.id, p_datos: f as unknown as Json }))) as unknown as { oportunidad_id: string };
                  ir(R.oportunidad(r.oportunidad_id), bien("Cita agendada. Ya es una oportunidad, con su siguiente paso."));
                }}>
                  <label htmlFor="lc">Cuándo</label>
                  <input id="lc" name="cita" type="datetime-local" min={ahoraLocal()} required />
                  <label htmlFor="lu">Qué busca</label>
                  <select id="lu" name="unidad" defaultValue="diseno_arquitectonico"><Opciones de={UNIDAD} /></select>
                  <label htmlFor="lp">Nombre del proyecto</label>
                  <input id="lp" name="proyecto" placeholder="Casa en Cerritos" autoComplete="off" />
                  <label htmlFor="lr">Quién hace la cita</label>
                  <select id="lr" name="responsable_id" defaultValue={yo.persona_id}><Opciones de={equipo.map((p) => [p.id, p.nombre])} /></select>
                  <button className="btn">Agendar la cita</button>
                </Formulario>
                <details>
                  <summary className="enlace">Descartarlo</summary>
                  <Formulario onEnviar={async (f) => {
                    await pedir(sb().from("lead").update({ estado: "descartado", motivo_descarte: f.motivo.trim() }).eq("id", l.id).select("id"));
                    ir(R.ventas, bien("Descartado, con su motivo."));
                  }}>
                    <label htmlFor="ld">Por qué</label>
                    <input id="ld" name="motivo" required minLength={4} placeholder="Es proveedor, busca empleo, no tiene proyecto…" autoComplete="off" />
                    <button className="btn peligro">Descartar</button>
                  </Formulario>
                </details>
              </>
            ) : null}
          </Pantalla>
        );
      }}
    </Carga>
  );
}

/** El contacto ya es una oportunidad: se abre esa. */
function Redirigir({ a }: { a: string }) {
  const { ir } = useSesion();
  useEffect(() => { ir(a); }, [a, ir]);
  return <p className="espera">Abriendo…</p>;
}
