"use client";
// Lo que una pantalla le pide a la base al abrirse. Se vuelve a pedir cuando
// cambia alguna dependencia o cuando alguien llama a recargar().
import { useEffect, useState } from "react";
import { useSesion } from "./sesion";

export type Estado<T> = { cargando: true; datos?: undefined; error?: undefined } | { cargando: false; datos: T; error?: undefined } | { cargando: false; datos?: undefined; error: unknown };

export function useDatos<T>(cargar: () => Promise<T>, deps: unknown[]): Estado<T> {
  const { version } = useSesion();
  const clave = JSON.stringify([...deps, version]);
  const [res, setRes] = useState<{ clave: string; estado: Estado<T> } | null>(null);
  useEffect(() => {
    let vivo = true;
    cargar()
      .then((d) => vivo && setRes({ clave, estado: { cargando: false, datos: d } }))
      .catch((e: unknown) => vivo && setRes({ clave, estado: { cargando: false, error: e } }));
    return () => { vivo = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [clave]);
  // Mientras la respuesta sea de otra consulta, la pantalla está cargando.
  return res && res.clave === clave ? res.estado : { cargando: true };
}
