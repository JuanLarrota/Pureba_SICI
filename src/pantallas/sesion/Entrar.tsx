"use client";
// Entrar con correo y contraseña, crear el acceso la primera vez, recuperar la
// contraseña o pedir un enlace al correo. Las cuentas las crea cada quien:
// dirección solo pone la ficha.
import { useState } from "react";
import { sb } from "@/lib/supabase/cliente";
import { bien, mal, pedir } from "@/lib/pedir";
import { useSesion } from "@/lib/sesion";
import { Formulario } from "@/componentes/formularios/Formulario";
import { Logo } from "@/componentes/ui/piezas";
import { CampoClave } from "./CampoClave";

export function Entrar() {
  const { aviso, avisar } = useSesion();
  const [modo, setModo] = useState<"entrar" | "crear">("entrar");
  const primera = modo === "crear";
  const origen = () => location.origin + "/";
  const correoEscrito = () => (document.getElementById("correo") as HTMLInputElement | null)?.value.trim() || "";
  return (
    <main>
      {aviso ? <div className={aviso.tipo} role="status">{aviso.texto}</div> : null}
      <div className="entrada">
        <Logo />
        <div className="sub">SICI · CONTROL INTERNO</div>
        <h1>{primera ? "Crear mi acceso" : "Entrar"}</h1>
        <p style={{ color: "var(--tinta-3)" }}>
          {primera ? "Use el mismo correo con el que dirección lo agregó al equipo. Le llegará un mensaje para confirmarlo." : "Con el correo que dirección registró para usted."}
        </p>
        <Formulario key={modo} onEnviar={async (f) => {
          if (primera) {
            const d = await pedir(sb().auth.signUp({ email: f.correo.trim(), password: f.clave, options: { emailRedirectTo: origen() } }));
            if (!d.session) { avisar(bien("Listo. Abra el correo que le acabamos de enviar y toque el enlace para confirmar.")); setModo("entrar"); }
          } else {
            await pedir(sb().auth.signInWithPassword({ email: f.correo.trim(), password: f.clave }));
          }
        }}>
          <label htmlFor="correo">Correo</label>
          <input id="correo" name="correo" type="email" autoComplete="email" inputMode="email" required />
          <CampoClave id="clave" nombre="clave" etiqueta="Contraseña" auto={primera ? "new-password" : "current-password"} />
          <button className="btn">{primera ? "Crear mi acceso" : "Entrar"}</button>
        </Formulario>
        <button type="button" className="enlace" onClick={() => { avisar(null); setModo(primera ? "entrar" : "crear"); }}>
          {primera ? "Ya tengo acceso" : "Es mi primera vez"}
        </button>
        <br />
        {primera ? null : (
          <>
            <button type="button" className="enlace" onClick={async () => {
              const correo = correoEscrito();
              if (!correo) return avisar(mal("Escriba primero su correo y luego toque «Olvidé mi contraseña»."));
              try {
                await pedir(sb().auth.resetPasswordForEmail(correo, { redirectTo: origen() }));
                avisar(bien("Si ese correo está registrado, le llegó un enlace para poner una contraseña nueva. Ábralo en este mismo teléfono."));
              } catch (e) { avisar(mal(e)); }
            }}>
              Olvidé mi contraseña
            </button>
            <br />
            <button type="button" className="enlace" onClick={async () => {
              const correo = correoEscrito();
              if (!correo) return avisar(mal("Escriba primero su correo."));
              try {
                await pedir(sb().auth.signInWithOtp({ email: correo, options: { shouldCreateUser: false, emailRedirectTo: origen() } }));
                avisar(bien("Le enviamos un enlace. Ábralo en este mismo teléfono."));
              } catch (e) { avisar(mal(e)); }
            }}>
              Entrar con un enlace que me llegue al correo
            </button>
          </>
        )}
      </div>
    </main>
  );
}
