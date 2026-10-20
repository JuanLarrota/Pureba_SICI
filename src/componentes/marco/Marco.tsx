"use client";
// Decide qué se ve según la sesión: entrar, «falta su ficha», o la aplicación.
import { useEffect, type ReactNode } from "react";
import { useSesion } from "@/lib/sesion";
import { Entrar } from "@/pantallas/sesion/Entrar";
import { SinFicha } from "@/pantallas/sesion/SinFicha";
import { NuevaClave } from "@/pantallas/sesion/NuevaClave";

export function Marco({ children }: { children: ReactNode }) {
  const { listo, usuario, yo, recuperando } = useSesion();
  useEffect(() => {
    if ("serviceWorker" in navigator && location.protocol === "https:") navigator.serviceWorker.register("/sw.js").catch(() => {});
  }, []);
  if (!listo) return <p className="espera">Abriendo…</p>;
  if (!usuario) return <Entrar />;
  if (recuperando) return <NuevaClave recuperando />;
  if (!yo) return <SinFicha />;
  return <>{children}</>;
}
