"use client";
// El marco de cada pantalla: cabecera, el aviso de una vez, el contenido, el
// botón «+» y el pie con las secciones.
import Link from "next/link";
import { useEffect, type ReactNode } from "react";
import { usePathname } from "next/navigation";
import { useSesion } from "@/lib/sesion";
import { iniciales } from "@/lib/dominio/texto";
import { R } from "@/lib/rutas";

interface Props {
  titulo: string;
  sobre?: string | null;
  atras?: string;                 // ruta del botón «volver»
  pie?: string;                   // ruta de la sección activa del pie; sin pie si no viene
  porRevisar?: number;
  mas?: { ruta: string; nombre: string };   // el botón flotante
  ancho?: boolean;                // usa todo el ancho en pantalla grande (mando, tablero)
  claseMain?: string;
  pestanas?: ReactNode;           // una nav.pestanas entre la cabecera y el contenido (los espacios de una obra)
  children: ReactNode;
}

export function Pantalla({ titulo, sobre, atras, pie, porRevisar = 0, mas, ancho = false, claseMain, pestanas, children }: Props) {
  const { yo, aviso, ir } = useSesion();
  useEffect(() => {
    const app = document.getElementById("app");
    app?.classList.toggle("ancho", ancho);
    window.scrollTo(0, 0);
    return () => app?.classList.remove("ancho");
  }, [ancho]);
  return (
    <>
      <header className="cab">
        {atras ? <button className="atras" onClick={() => ir(atras)} aria-label="Volver">‹</button> : null}
        <div style={{ flex: 1, minWidth: 0 }}>
          {sobre ? <small>{sobre}</small> : null}
          <h1>{titulo}</h1>
        </div>
        {yo && !atras ? <Link className="yo" href={R.yo} aria-label="Mi cuenta">{iniciales(yo.nombre)}</Link> : null}
      </header>
      {pestanas}
      <main className={claseMain}>
        {aviso ? <div className={aviso.tipo} role="status">{aviso.texto}</div> : null}
        {children}
      </main>
      {mas ? <Link className="mas" href={mas.ruta} aria-label={mas.nombre}>+</Link> : null}
      {pie && yo ? <Pie actual={pie} porRevisar={porRevisar} /> : null}
    </>
  );
}

/** Las secciones de abajo. Seis como máximo, para que quepan en un teléfono. */
export function Pie({ actual, porRevisar = 0 }: { actual: string; porRevisar?: number }) {
  const { yo } = useSesion();
  const pathname = usePathname();
  if (!yo) return null;
  const manda = yo.asigna || yo.dirige.length > 0;
  const items: [string, string][] = [
    [R.dia, "Mi día"],
    ...(yo.vende ? [[R.ventas, "Ventas"] as [string, string]] : []),
    ...(yo.revisa.length ? [[R.revisar, "Revisar"] as [string, string]] : []),
    [R.proyectos, "Proyectos"],
    ...(yo.obras ? [[R.obras, "Obras"] as [string, string]] : []),
    ...(yo.obras && manda ? [] : [[R.equipo, "Equipo"] as [string, string]]),
    manda ? [R.mando, "Mando"] : [R.impacto(), "Impacto"],   // quien dirige ve el impacto de todos en el centro de mando
  ];
  const limpia = (r: string) => r.split("?")[0].replace(/\/+$/, "") || "/";
  const aqui = limpia(actual || pathname);
  return (
    <nav className="pie" aria-label="Secciones">
      <div>
        {items.map(([r, n]) => (
          <Link key={r} href={r} aria-current={limpia(r) === aqui ? "page" : undefined}>
            {n}{r === R.revisar && porRevisar ? <i>{porRevisar}</i> : null}
          </Link>
        ))}
      </div>
    </nav>
  );
}
