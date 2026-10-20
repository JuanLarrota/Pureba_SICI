"use client";
// La carpeta de Drive de un proyecto u obra, leída con la cuenta de Google de
// cada quien. Sin el ID de cliente de Google, solo el botón para abrirla.
import { useState } from "react";
import { GOOGLE_CLIENT_ID } from "@/lib/config";
import { conectarDrive, driveVivo, ES_CARPETA, idCarpeta, listarCarpeta, type ArchivoDrive } from "@/lib/drive";
import { useDatos } from "@/lib/useDatos";
import { decir } from "@/lib/pedir";
import { fecha } from "@/lib/dominio/fechas";
import { Boton } from "@/componentes/formularios/Boton";
import { Fila, Vacio } from "@/componentes/ui/piezas";

export function Drive({ url }: { url: string }) {
  const [conectado, setConectado] = useState(driveVivo());
  const [carpeta, setCarpeta] = useState<{ id: string; nombre: string } | null>(null);
  const abrir = <a className="btn claro" href={url} target="_blank" rel="noopener">Abrir la carpeta en Drive</a>;
  if (!GOOGLE_CLIENT_ID) return <>{abrir}<p className="nota">Para ver los archivos aquí mismo falta un paso de configuración con Google. Mientras tanto, el botón abre la carpeta.</p></>;
  if (!conectado) return <><Boton accion={async () => { await conectarDrive(); setConectado(true); }}>Ver los archivos con mi cuenta de Google</Boton>{abrir}</>;
  const id = carpeta?.id || idCarpeta(url);
  if (!id) return <>{abrir}<p className="error">Ese enlace no es de una carpeta de Drive.</p></>;
  return <Listado id={id} nombre={carpeta?.nombre} abrir={abrir} entrar={setCarpeta} volver={carpeta ? () => setCarpeta(null) : undefined} desconectar={() => setConectado(false)} />;
}

function Listado({ id, nombre, abrir, entrar, volver, desconectar }: { id: string; nombre?: string; abrir: React.ReactNode; entrar: (c: { id: string; nombre: string }) => void; volver?: () => void; desconectar: () => void }) {
  const estado = useDatos<ArchivoDrive[]>(() => listarCarpeta(id).catch((e: Error) => { if (e.message === "401") { desconectar(); return []; } throw e; }), [id]);
  if (estado.cargando) return <Vacio corto>Leyendo la carpeta…</Vacio>;
  if (estado.datos === undefined) return <><p className="error">{decir(estado.error)}</p>{abrir}</>;
  return (
    <>
      {volver ? <><button type="button" className="enlace" onClick={volver}>‹ Volver a la carpeta del proyecto</button><p style={{ margin: 0, fontFamily: "var(--ui)", fontWeight: 500 }}>{nombre}</p></> : null}
      {estado.datos.map((a) => a.mimeType === ES_CARPETA
        ? <Fila key={a.id} onClick={() => entrar({ id: a.id, nombre: a.name })}><b>{a.name} ›</b><span>Carpeta</span></Fila>
        : <Fila key={a.id} href={a.webViewLink} externo><b>{a.name}</b><span>Cambió el {fecha(a.modifiedTime)}</span></Fila>)}
      {estado.datos.length ? null : <Vacio corto>La carpeta está vacía.</Vacio>}
      {abrir}
    </>
  );
}
