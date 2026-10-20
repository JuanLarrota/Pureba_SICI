"use client";
// Un botón que hace algo en la base. Mientras trabaja queda deshabilitado; si
// la base dice que no, el aviso aparece arriba y la pantalla se vuelve a leer.
import { useState, type ButtonHTMLAttributes, type ReactNode } from "react";
import { useSesion } from "@/lib/sesion";
import { mal } from "@/lib/pedir";

interface Props extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, "onClick" | "type"> {
  accion: () => unknown | Promise<unknown>;
  children: ReactNode;
}

export function Boton({ accion, children, className = "btn", disabled, ...rest }: Props) {
  const { avisar, recargar } = useSesion();
  const [ocupado, setOcupado] = useState(false);
  return (
    <button type="button" className={className} disabled={disabled || ocupado} {...rest}
      onClick={async () => {
        setOcupado(true);
        try { await accion(); }
        catch (e) { avisar(mal(e)); recargar(); }
        finally { setOcupado(false); }
      }}>
      {children}
    </button>
  );
}
