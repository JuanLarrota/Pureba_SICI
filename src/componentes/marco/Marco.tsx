"use client";
// Decide qué se ve según la sesión: entrar, «falta su ficha», o la aplicación.
import { useEffect, type ReactNode } from "react";
import { useSesion } from "@/lib/sesion";
import { Entrar } from "@/pantallas/sesion/Entrar";
import { SinFicha } from "@/pantallas/sesion/SinFicha";
import { NuevaClave } from "@/pantallas/sesion/NuevaClave";

export function Marco({ children }: { children: ReactNode }) {
  const { listo, usuario, yo, recuperando, vistaActiva, verComo } = useSesion();
  useEffect(() => {
    if ("serviceWorker" in navigator && location.protocol === "https:") navigator.serviceWorker.register("/sw.js").catch(() => {});
  }, []);
  if (!listo) return <p className="espera">Abriendo…</p>;
  if (!usuario) return <Entrar />;
  if (recuperando) return <NuevaClave recuperando />;
  if (!yo) return <SinFicha />;
  return (
    <>
      {vistaActiva ? (
        <div role="status" style={{ position: "sticky", top: 0, zIndex: 50, display: "flex", gap: 12, alignItems: "center", justifyContent: "space-between",
          padding: "10px 16px", background: "var(--negro, #000)", color: "var(--blanco, #fff)", fontSize: 14 }}>
          <span>Viendo como: <strong>{yo.nombre}</strong></span>
          <button type="button" onClick={() => verComo(null)} style={{ background: "none", border: "1px solid currentColor", color: "inherit", padding: "4px 12px", borderRadius: 999, font: "inherit" }}>Volver a mi vista</button>
        </div>
      ) : null}
      {children}
    </>
  );
}
