"use client";
// Un campo de contraseña con el botón para verla mientras se escribe.
import { useState } from "react";

export function CampoClave({ id, nombre, etiqueta, auto }: { id: string; nombre: string; etiqueta: string; auto: "new-password" | "current-password" }) {
  const [ver, setVer] = useState(false);
  return (
    <>
      <label htmlFor={id}>{etiqueta}</label>
      <div className="clave">
        <input id={id} name={nombre} type={ver ? "text" : "password"} autoComplete={auto} minLength={6} required autoCapitalize="off" spellCheck={false} />
        <button type="button" className="ver-clave" aria-pressed={ver} aria-label={ver ? "Ocultar la contraseña" : "Mostrar la contraseña"}
          onClick={() => { setVer(!ver); document.getElementById(id)?.focus(); }}>
          {ver ? "Ocultar" : "Ver"}
        </button>
      </div>
    </>
  );
}
