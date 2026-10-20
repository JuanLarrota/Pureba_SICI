"use client";
// Contraseña nueva: llega desde el correo de recuperación o desde Mi cuenta.
import { sb } from "@/lib/supabase/cliente";
import { bien, pedir } from "@/lib/pedir";
import { useSesion } from "@/lib/sesion";
import { R } from "@/lib/rutas";
import { Formulario } from "@/componentes/formularios/Formulario";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Logo } from "@/componentes/ui/piezas";
import { CampoClave } from "./CampoClave";

export function NuevaClave({ recuperando = false }: { recuperando?: boolean }) {
  const { ir, aviso, terminarRecuperacion } = useSesion();
  const formulario = (
    <>
      <p style={{ color: "var(--tinta-3)" }}>Escriba la contraseña nueva dos veces. Debe tener al menos 6 caracteres.</p>
      <Formulario onEnviar={async (f) => {
        if (f.clave1 !== f.clave2) throw new Error("Las dos contraseñas no son iguales. Escríbalas de nuevo.");
        await pedir(sb().auth.updateUser({ password: f.clave1 }));
        if (location.hash.includes("type=recovery") || location.hash.includes("access_token")) history.replaceState(null, "", location.pathname);
        terminarRecuperacion();
        ir(R.dia, bien("Contraseña cambiada."));
      }}>
        <CampoClave id="clave1" nombre="clave1" etiqueta="Contraseña nueva" auto="new-password" />
        <CampoClave id="clave2" nombre="clave2" etiqueta="Repítala" auto="new-password" />
        <button className="btn">Guardar la contraseña</button>
      </Formulario>
    </>
  );
  if (recuperando) {
    return (
      <main>
        {aviso ? <div className={aviso.tipo} role="status">{aviso.texto}</div> : null}
        <div className="entrada">
          <Logo />
          <div className="sub">SICI · CONTROL INTERNO</div>
          <h1>Nueva contraseña</h1>
          {formulario}
        </div>
      </main>
    );
  }
  return <Pantalla titulo="Cambiar mi contraseña" atras={R.yo}>{formulario}</Pantalla>;
}
