"use client";
// Un formulario que guarda en la base. Lo que la persona escribió llega como
// un objeto de textos; si la base dice que no, el error se muestra arriba del
// formulario y los botones vuelven a activarse.
import { useRef, useState, type FormHTMLAttributes, type ReactNode } from "react";
import { decir } from "@/lib/pedir";

export type Datos = Record<string, string>;

interface Props extends Omit<FormHTMLAttributes<HTMLFormElement>, "onSubmit"> {
  onEnviar: (datos: Datos, boton: HTMLButtonElement | null, form: HTMLFormElement) => unknown | Promise<unknown>;
  children: ReactNode;
}

/** Lo escrito en el formulario, como textos. */
export const leer = (form: HTMLFormElement): Datos => {
  const d: Datos = {};
  for (const [k, v] of new FormData(form)) d[k] = typeof v === "string" ? v : "";
  return d;
};

export function Formulario({ onEnviar, children, ...rest }: Props) {
  const ref = useRef<HTMLFormElement>(null);
  const [error, setError] = useState<string | null>(null);
  return (
    <form ref={ref} {...rest}
      onSubmit={async (e) => {
        e.preventDefault();
        const form = e.currentTarget, boton = (e.nativeEvent as SubmitEvent).submitter as HTMLButtonElement | null;
        const botones = [...form.querySelectorAll("button")];
        botones.forEach((b) => (b.disabled = true));
        setError(null);
        try { await onEnviar(leer(form), boton, form); }
        catch (err) {
          botones.forEach((b) => (b.disabled = false));
          setError(decir(err));
          form.scrollIntoView({ block: "start", behavior: "smooth" });
          return;
        }
        // Si el formulario sigue en pantalla, vuelve a servir.
        botones.forEach((b) => (b.disabled = false));
      }}>
      {error ? <div className="error" role="alert">{error}</div> : null}
      {children}
    </form>
  );
}

/** Las opciones de un <select> a partir de un diccionario código → palabra. */
export function Opciones({ de, vacia }: { de: Record<string, string> | [string, string][]; vacia?: string }) {
  const pares = Array.isArray(de) ? de : Object.entries(de);
  return (
    <>
      {vacia !== undefined ? <option value="">{vacia}</option> : null}
      {pares.map(([k, v]) => <option key={k} value={k}>{v}</option>)}
    </>
  );
}
