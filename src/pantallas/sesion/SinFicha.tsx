"use client";
// Entró bien, pero su correo todavía no está en el equipo.
import { sb } from "@/lib/supabase/cliente";
import { useSesion } from "@/lib/sesion";
import { Boton } from "@/componentes/formularios/Boton";
import { Logo } from "@/componentes/ui/piezas";

export function SinFicha() {
  const { usuario, aviso, recargarSesion } = useSesion();
  return (
    <main>
      {aviso ? <div className={aviso.tipo} role="status">{aviso.texto}</div> : null}
      <div className="entrada">
        <Logo />
        <div className="sub">SICI · CONTROL INTERNO</div>
        <h1>Falta su ficha</h1>
        <p>Entró bien, pero el correo <strong>{usuario?.email}</strong> todavía no está en el equipo. Pídale a dirección que lo agregue con ese mismo correo y vuelva a abrir la aplicación.</p>
        <Boton className="btn claro" accion={recargarSesion}>Ya me agregaron</Boton>
        <Boton className="btn peligro" accion={() => sb().auth.signOut()}>Salir</Boton>
      </div>
    </main>
  );
}
