// Una persona puede tener más de un papel en el mismo proyecto (produce y también revisa).
import { PAPELES } from "@/lib/dominio/catalogos";
import { lista } from "@/lib/dominio/texto";
import type { Datos } from "@/componentes/formularios/Formulario";

/** Las casillas de los papeles de una persona: `papel:<id>:<papel>`. */
export function CasillasPapel({ id, nombre, extra = [] }: { id: string; nombre: string; extra?: [string, string][] }) {
  return (
    <span className="papeles" role="group" aria-label={`Papeles de ${nombre}`}>
      {[...PAPELES, ...extra].map(([v, n]) => <label key={v}><input type="checkbox" name={`papel:${id}:${v}`} value="1" />{n}</label>)}
    </span>
  );
}

/** Los papeles marcados para una persona en lo que llegó del formulario. */
export const papelesDe = (f: Datos, id: string) => [...PAPELES.map(([v]) => v), "observa"].filter((v) => f[`papel:${id}:${v}`]);

/** «Dirige y produce», para leerlo de un vistazo. */
export const nombrarPapeles = (l: string[]) => {
  const n: Record<string, string> = { dirige: "dirige", produce: "produce", revisa: "revisa", observa: "observa" };
  const t = lista(l.map((x) => n[x] || x));
  return t.charAt(0).toUpperCase() + t.slice(1);
};
