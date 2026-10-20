"use client";
// La carpeta de Drive y el índice de lo importante: contrato, planos, pólizas.
import { sb } from "@/lib/supabase/cliente";
import { bien, mal, pedir } from "@/lib/pedir";
import { useSesion, useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { nombresDe } from "@/lib/consultas";
import { R } from "@/lib/rutas";
import { TIPO_DOC } from "@/lib/dominio/catalogos";
import { fecha } from "@/lib/dominio/fechas";
import { Drive } from "@/componentes/Drive";
import { Boton } from "@/componentes/formularios/Boton";
import { Formulario, Opciones } from "@/componentes/formularios/Formulario";
import { Fila, Grupo, Vacio } from "@/componentes/ui/piezas";
import { CargaSeccion, type PropsSeccion } from "./Obra";

export function Documentos({ o, registra }: PropsSeccion) {
  const yo = useYo();
  const { ir, avisar, recargar } = useSesion();
  const estado = useDatos(async () => {
    const docs = await pedir(sb().from("documento_obra").select("id,tipo,titulo,enlace,fecha,registrado_por,registrado_en").eq("proyecto_id", o.id).is("retirado_en", null).order("registrado_en", { ascending: false }));
    const quien = await nombresDe(docs.map((d) => d.registrado_por));
    return { docs, quien };
  }, [o.id]);

  return (
    <CargaSeccion estado={estado}>
      {({ docs, quien }) => {
        const porTipo = Object.keys(TIPO_DOC).map((t) => [t, docs.filter((d) => d.tipo === t)] as const).filter(([, a]) => a.length);
        return (
          <>
            <Grupo>Lo importante</Grupo>
            {porTipo.flatMap(([t, a]) => a.map((d) => (
              <Fila key={d.id}>
                <a href={d.enlace} target="_blank" rel="noopener" className="doc"><b>{d.titulo} ›</b></a>
                <span>{TIPO_DOC[t]}{d.fecha ? " · del " + fecha(d.fecha) : ""} · lo puso {quien.get(d.registrado_por || "") || "alguien"}</span>
                {yo.es_direccion || d.registrado_por === yo.persona_id ? (
                  <Boton className="enlace" accion={async () => {
                    if (!window.confirm("¿Retirar este documento del índice? El archivo sigue en Drive.")) return;
                    const r = await pedir(sb().from("documento_obra").update({ retirado_en: new Date().toISOString() }).eq("id", d.id).select("id"));
                    avisar(r.length ? bien("Documento retirado del índice.") : mal("Lo retira dirección o quien lo puso.")); recargar();
                  }}>Retirar</Boton>
                ) : null}
              </Fila>
            )))}
            {docs.length ? null : <Vacio corto>Todavía no hay documentos en el índice. Ponga aquí el contrato, el presupuesto, los planos, la licencia y las pólizas.</Vacio>}
            {registra ? (
              <details>
                <summary className="btn claro">Agregar un documento</summary>
                <Formulario onEnviar={async (f) => {
                  if (!/^https:\/\//.test(f.enlace.trim())) throw new Error("El enlace debe empezar por https://, como los de Drive.");
                  await pedir(sb().from("documento_obra").insert({ proyecto_id: o.id, tipo: f.tipo as "contrato", titulo: f.titulo.trim(), enlace: f.enlace.trim(), fecha: f.fecha || null, registrado_por: yo.persona_id }));
                  ir(R.obra(o.id, "documentos"), bien("Documento agregado al índice."));
                }}>
                  <label htmlFor="dt">Qué es</label>
                  <select id="dt" name="tipo" defaultValue="contrato"><Opciones de={TIPO_DOC} /></select>
                  <label htmlFor="dn">Nombre</label>
                  <input id="dn" name="titulo" required minLength={3} autoComplete="off" placeholder="Contrato de obra firmado" />
                  <label htmlFor="de">Enlace de Drive</label>
                  <input id="de" name="enlace" type="url" inputMode="url" required placeholder="https://drive.google.com/…" />
                  <label htmlFor="df">Fecha del documento</label>
                  <input id="df" name="fecha" type="date" />
                  <button className="btn">Agregar al índice</button>
                </Formulario>
              </details>
            ) : null}
            <Grupo>Carpeta de Drive</Grupo>
            <div id="drive">{o.carpeta_drive ? <Drive url={o.carpeta_drive} /> : <Vacio corto>Esta obra todavía no tiene su carpeta de Drive.</Vacio>}</div>
            {yo.es_direccion ? (
              <Formulario onEnviar={async (f) => {
                await pedir(sb().from("proyecto").update({ carpeta_drive: f.carpeta.trim() || null }).eq("id", o.id));
                avisar(bien("Carpeta guardada.")); recargar();
              }}>
                <label htmlFor="cdr">Enlace de la carpeta de Drive</label>
                <input id="cdr" name="carpeta" type="url" inputMode="url" placeholder="https://drive.google.com/drive/folders/…" defaultValue={o.carpeta_drive || ""} />
                <button className="btn claro">Guardar la carpeta</button>
              </Formulario>
            ) : null}
          </>
        );
      }}
    </CargaSeccion>
  );
}
