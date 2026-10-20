"use client";
// Una oportunidad: quién es, qué sigue, sus reuniones, lo que dejó la cita,
// sus cotizaciones y el desenlace. La base impide lo que no corresponde.
import Link from "next/link";
import { sb } from "@/lib/supabase/cliente";
import { bien, pedir, pedirUno } from "@/lib/pedir";
import { useSesion } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { gente } from "@/lib/consultas";
import { R } from "@/lib/rutas";
import { ABIERTAS, CANAL, ENCONTRO, ESTADO_CITA, ESTADO_COT, ETAPA, LINEA, lineaDe, MOTIVO, TIPO_CITA } from "@/lib/dominio/catalogos";
import { ahoraLocal, fecha, hoyIso, momento } from "@/lib/dominio/fechas";
import { frase, lista, num, pesos, whatsapp } from "@/lib/dominio/texto";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Boton } from "@/componentes/formularios/Boton";
import { Formulario, Opciones } from "@/componentes/formularios/Formulario";
import { Etiqueta, Fila, Grupo, Nota, Vacio } from "@/componentes/ui/piezas";

export function Oportunidad({ id }: { id: string }) {
  const { ir, avisar, recargar } = useSesion();
  const estado = useDatos(async () => {
    const o = await pedirUno(sb().from("oportunidad").select("id,nombre,etapa,unidad,canal,valor_estimado,area_m2,ciudad,siguiente_paso,siguiente_paso_en,siguiente_paso_por,responsable_id,lead_id,origen_oportunidad_id,motivo_perdida,detalle_perdida").eq("id", id).maybeSingle());
    if (!o) return null;
    const [citas, cots, ficha, lead, equipo] = await Promise.all([
      pedir(sb().from("cita").select("id,tipo,estado,programada_para,transcripcion_url").eq("oportunidad_id", id).order("programada_para")),
      pedir(sb().from("cotizacion").select("id,numero,valor,estado,emitida_en,vence_en").eq("oportunidad_id", id).order("creada_en")),
      pedirUno(sb().from("calificacion").select("decisor_presente,tiene_lote,recurso_disponible,proposito,primera_cotizacion,area_inicial_m2").eq("oportunidad_id", id).maybeSingle()),
      o.lead_id ? pedirUno(sb().from("lead").select("nombre,telefono,correo,canal,como_nos_encontro,mensaje_inicial").eq("id", o.lead_id).maybeSingle()) : null,
      gente(),
    ]);
    return { o, citas, cots, ficha, lead, equipo };
  }, [id]);

  const guardaYRecarga = (dicho: string) => { avisar(bien(dicho)); recargar(); };

  return (
    <Carga estado={estado} atras={R.ventas}>
      {(d) => {
        if (!d) return <Pantalla titulo="Oportunidad" atras={R.ventas}><Vacio>Esa oportunidad no existe o no la puede ver.</Vacio></Pantalla>;
        const { o, citas, cots, ficha, lead, equipo } = d;
        const hoy = hoyIso();
        const abierta = ABIERTAS.includes(o.etapa), quien = new Map(equipo.map((p) => [p.id, p.nombre]));
        const presentacion = citas.some((c) => c.tipo === "presentacion" && ["agendada", "realizada"].includes(c.estado));
        const pendiente = (c: { estado: string; programada_para: string }) => ["agendada", "reprogramada"].includes(c.estado) && new Date(c.programada_para) < new Date(Date.now() + 864e5);
        const opcionesEquipo: [string, string][] = equipo.map((p) => [p.id, p.nombre]);
        return (
          <Pantalla titulo={o.nombre} sobre={`${ETAPA[o.etapa]} · ${LINEA[lineaDe(o.unidad)]}`} atras={R.ventas} pie={R.ventas}>
            {lead ? (
              <Fila>
                <b>{lead.nombre || "Sin nombre"}</b>
                <span>
                  {lead.telefono ? <><a href={`tel:${lead.telefono}`}>{lead.telefono}</a> · <a href={whatsapp(lead.telefono)} target="_blank" rel="noopener">WhatsApp</a> · </> : null}
                  {lead.correo ? `${lead.correo} · ` : ""}
                  Llegó por {CANAL[lead.canal] || lead.canal}
                  {lead.como_nos_encontro && lead.como_nos_encontro !== lead.canal ? `; dice que nos encontró ${ENCONTRO[lead.como_nos_encontro] || ""}` : ""}
                </span>
                {lead.mensaje_inicial ? <span>«{lead.mensaje_inicial}»</span> : null}
              </Fila>
            ) : (
              <Nota>{o.origen_oportunidad_id ? <>Nació del diseño que ESA ganó: <Link href={R.oportunidad(o.origen_oportunidad_id)}>ver esa venta</Link>.</> : `Llegó por ${CANAL[o.canal] || o.canal}.`}</Nota>
            )}
            <Fila>
              <b>{pesos(o.valor_estimado)}</b>
              <span>{o.area_m2 ? `${num(o.area_m2)} m² · ` : ""}{o.ciudad ? `${o.ciudad} · ` : ""}responde {quien.get(o.responsable_id || "") || "sin responsable"}</span>
            </Fila>

            {abierta ? (
              <>
                <Grupo tono={o.siguiente_paso_en && o.siguiente_paso_en < hoy ? "c" : ""}>Siguiente paso</Grupo>
                <Formulario onEnviar={async (f) => {
                  const r = await pedir(sb().from("oportunidad").update({ siguiente_paso: f.paso.trim(), siguiente_paso_en: f.en, siguiente_paso_por: f.por }).eq("id", o.id).select("id"));
                  if (!r.length) throw new Error("No puede cambiar esta oportunidad.");
                  guardaYRecarga("Siguiente paso guardado.");
                }}>
                  <label htmlFor="sp">Qué sigue</label>
                  <input id="sp" name="paso" defaultValue={o.siguiente_paso || ""} required minLength={4} autoComplete="off" />
                  <div className="dos">
                    <div><label htmlFor="spe">Cuándo</label><input id="spe" name="en" type="date" min={hoy} defaultValue={o.siguiente_paso_en || ""} required /></div>
                    <div><label htmlFor="spq">Quién</label><select id="spq" name="por" defaultValue={o.siguiente_paso_por || ""}><Opciones de={opcionesEquipo} /></select></div>
                  </div>
                  <button className="btn claro">Guardar el siguiente paso</button>
                </Formulario>
              </>
            ) : o.etapa === "perdida" ? (
              <Nota>Se perdió: {(MOTIVO[o.motivo_perdida || ""] || "").toLowerCase()}{o.detalle_perdida ? `. ${o.detalle_perdida}` : ""}.</Nota>
            ) : <p className="bien">Venta ganada.</p>}

            <Grupo>Reuniones</Grupo>
            {citas.length ? citas.map((c) => {
              const cuerpo = (
                <>
                  <b>{TIPO_CITA[c.tipo]}<Etiqueta tono={c.estado === "realizada" ? "o" : c.estado === "no_show" ? "c" : "n"}>{ESTADO_CITA[c.estado]}</Etiqueta></b>
                  <span>
                    {momento(c.programada_para)}
                    {pendiente(c) ? <> · <em>Hacer el reporte</em></> : null}
                    {c.transcripcion_url ? <> · <a href={c.transcripcion_url} target="_blank" rel="noopener">transcripción</a></> : null}
                  </span>
                </>
              );
              return pendiente(c) ? <Fila key={c.id} href={R.reporte(c.id)}>{cuerpo}</Fila> : <Fila key={c.id}>{cuerpo}</Fila>;
            }) : <Vacio corto>Ninguna todavía.</Vacio>}
            {abierta ? (
              <details>
                <summary className="enlace">Agendar una reunión</summary>
                <Formulario onEnviar={async (f) => {
                  await pedir(sb().from("cita").insert({ oportunidad_id: o.id, tipo: f.tipo, modalidad: f.modalidad, programada_para: new Date(f.cuando).toISOString() }).select("id"));
                  guardaYRecarga(`${TIPO_CITA[f.tipo]} agendada para el ${momento(new Date(f.cuando).toISOString())}.`);
                }}>
                  <label htmlFor="ct">Qué reunión</label>
                  <select id="ct" name="tipo" defaultValue={presentacion || o.etapa === "cita_viabilidad" ? "seguimiento" : "presentacion"}><Opciones de={TIPO_CITA} /></select>
                  <label htmlFor="cc">Cuándo</label>
                  <input id="cc" name="cuando" type="datetime-local" min={ahoraLocal()} required />
                  <label htmlFor="cm">Cómo</label>
                  <select id="cm" name="modalidad" defaultValue="videollamada"><Opciones de={{ videollamada: "Videollamada", presencial: "En persona", llamada: "Llamada" }} /></select>
                  <button className="btn claro">Agendar</button>
                </Formulario>
              </details>
            ) : null}

            {ficha ? (
              <>
                <Grupo>Lo que dejó la cita</Grupo>
                <Fila>
                  <span>{frase(lista([
                    ficha.decisor_presente == null ? "" : ficha.decisor_presente ? "estaba quien decide" : "no estaba quien decide",
                    ({ si: "tiene lote", en_proceso: "está comprando el lote", no: "no tiene lote" } as Record<string, string>)[ficha.tiene_lote || ""] || "",
                    ({ inmediato: "ya tiene el recurso", "0_3_meses": "tiene el recurso en menos de tres meses", "3_12_meses": "tiene el recurso en tres meses a un año",
                      mas_12_meses: "tiene el recurso en más de un año", no_sabe: "no sabe cuándo tendrá el recurso" } as Record<string, string>)[ficha.recurso_disponible || ""] || "",
                    ({ vivienda: "es para vivir", inversion: "es para invertir o arrendar", mixto: "es para vivir e invertir", comercial: "es para un negocio" } as Record<string, string>)[ficha.proposito || ""] || "",
                    ficha.primera_cotizacion == null ? "" : ficha.primera_cotizacion ? "somos la primera cotización que pide" : "ya tiene otras cotizaciones",
                  ].filter(Boolean)))}.</span>
                </Fila>
              </>
            ) : null}

            <Grupo>Cotizaciones</Grupo>
            {cots.length ? cots.map((z) => (
              <Fila key={z.id}>
                <b>{z.numero} · {pesos(z.valor)}<Etiqueta tono={z.estado === "aceptada" ? "o" : z.estado === "vencida" || z.estado === "rechazada" ? "c" : "n"}>{ESTADO_COT[z.estado]}</Etiqueta></b>
                <span>{z.emitida_en ? `Enviada el ${fecha(z.emitida_en)}${z.vence_en ? `, vence el ${fecha(z.vence_en)}` : ""}` : "Sin enviar"}</span>
                {z.estado === "emitida" && abierta ? (
                  <div className="par">
                    <Boton className="btn claro" accion={async () => {
                      await pedir(sb().from("cotizacion").update({ estado: "aceptada", respondida_en: hoyIso() }).eq("id", z.id).select("id"));
                      guardaYRecarga("Aceptada: la oportunidad pasó a contrato y anticipo.");
                    }}>La aceptó</Boton>
                    <Boton className="btn claro" accion={async () => {
                      await pedir(sb().from("cotizacion").update({ estado: "rechazada", respondida_en: hoyIso() }).eq("id", z.id).select("id"));
                      guardaYRecarga("Quedó registrado que la rechazó.");
                    }}>La rechazó</Boton>
                  </div>
                ) : null}
              </Fila>
            )) : <Vacio corto>Ninguna todavía.</Vacio>}
            {abierta ? (
              <details>
                <summary className="enlace">Enviar una cotización</summary>
                {presentacion ? null : <Nota>Primero se agenda la reunión de presentación: es donde se vende. Sin ella la base no deja enviarla.</Nota>}
                <Formulario onEnviar={async (f) => {
                  const valor = Number(String(f.valor).replace(/\D/g, "")), costo = f.costo ? Number(String(f.costo).replace(/\D/g, "")) : null;
                  await pedir(sb().from("cotizacion").insert({ oportunidad_id: o.id, numero: f.numero.trim(), tipo: f.tipo as "diseno", valor, costo_estimado: costo, estado: "emitida" }).select("id"));
                  guardaYRecarga("Cotización enviada. La oportunidad quedó en «cotización presentada».");
                }}>
                  <div className="dos">
                    <div><label htmlFor="zn">Número</label><input id="zn" name="numero" required placeholder="45_26" autoComplete="off" /></div>
                    <div><label htmlFor="zt">De qué</label><select id="zt" name="tipo" defaultValue="diseno"><Opciones de={{ diseno: "Diseño", obra: "Obra", consultoria: "Consultoría", peritaje: "Peritaje" }} /></select></div>
                  </div>
                  <div className="dos">
                    <div><label htmlFor="zv">Valor sin IVA</label><input id="zv" name="valor" inputMode="numeric" required defaultValue={o.valor_estimado ? Math.round(o.valor_estimado) : ""} /></div>
                    <div><label htmlFor="zc">Lo que nos cuesta</label><input id="zc" name="costo" inputMode="numeric" placeholder="Para diseño y consultoría" /></div>
                  </div>
                  <button className="btn">Enviar cotización</button>
                </Formulario>
              </details>
            ) : null}

            {abierta ? (
              <>
                <Grupo>Desenlace</Grupo>
                <Boton accion={async () => {
                  const r = await pedir(sb().from("oportunidad").update({ etapa: "ganada" }).eq("id", o.id).select("id"));
                  if (!r.length) throw new Error("No puede cambiar esta oportunidad.");
                  ir(R.oportunidad(o.id), bien("Venta ganada. Si era un diseño, ya nació la oportunidad de obra a nombre de quien responde por las obras."));
                }}>Ganada: firmó y pagó el anticipo</Boton>
                <details>
                  <summary className="enlace">Se perdió</summary>
                  <Formulario onEnviar={async (f) => {
                    const r = await pedir(sb().from("oportunidad").update({ etapa: "perdida", motivo_perdida: f.motivo as "precio", detalle_perdida: f.detalle.trim() || null }).eq("id", o.id).select("id"));
                    if (!r.length) throw new Error("No puede cambiar esta oportunidad.");
                    guardaYRecarga("Quedó como perdida, con su motivo.");
                  }}>
                    <label htmlFor="pm">Por qué</label>
                    <select id="pm" name="motivo" required defaultValue=""><Opciones de={MOTIVO} vacia="Escoja" /></select>
                    <label htmlFor="pd">Lo que dijo, si quiere dejarlo</label>
                    <input id="pd" name="detalle" autoComplete="off" />
                    <button className="btn peligro">Marcarla como perdida</button>
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
