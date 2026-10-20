// Las piezas gráficas: lo que se lee de un vistazo. Siguen a legado/app/app.js y
// a las clases de globals.css (la versión que Felipe revisó el 19-10): barra de
// plazo (.pz), capacidad de la semana (.cap), avatar (.av), estado (.ch), tira de
// fases (.tf) y avance (.av-g). Salvia a tiempo, ocre por vencer, tierra vencido.
import Link from "next/link";
import type { CSSProperties, ReactNode } from "react";
import { ESTADO } from "@/lib/dominio/catalogos";
import { hoyIso } from "@/lib/dominio/fechas";
import { iniciales, nFase, num } from "@/lib/dominio/texto";
import { estadoFase, libres, plazo, type AvanceFase, type Capacidad, type ConPlazo, type FaseResumen } from "@/lib/dominio/plazo";

/** Quién: las iniciales en un cuadro negro; «otro» en hueso, para distinguir lo ajeno de lo mío. */
export const Avatar = ({ nombre, otro = false }: { nombre?: string | null; otro?: boolean }) => (
  <span className={`av${otro ? " otro" : ""}`} title={nombre || "?"} aria-hidden="true">{iniciales(nombre || "?")}</span>
);

/** Estado de una tarea. */
export const ChipEstado = ({ estado }: { estado: string }) => <span className={`ch ${estado}`}>{ESTADO[estado] || estado}</span>;

/** La marca de prioridad al lado del título. */
export const Marca = ({ prioridad }: { prioridad?: string | null }) =>
  prioridad === "alta" ? <span className="marca a">Alta</span> : prioridad === "bloqueante" ? <span className="marca c">Frena a otros</span> : null;

export const Etiqueta = ({ tono = "n", children }: { tono?: string; children: ReactNode }) => <span className={`marca ${tono}`}>{children}</span>;

/** Barra de plazo de una tarea: del día en que empieza al día en que se entrega, llena con lo que ya pasó. */
export function BarraPlazo({ t, hoy }: { t: ConPlazo; hoy?: string }) {
  const p = plazo(t, hoy);
  return <span className={`pz ${p.k}`} aria-label={p.txt}><i><b style={{ width: `${p.pct.toFixed(0)}%` }} /></i><small>{p.txt}</small></span>;
}

/** La semana de una persona: un tramo por día hábil, lleno con lo que ya tiene encima. «extra» suma lo que se le va a dar. */
export function BarraCapacidad({ c, extra = 0 }: { c?: Capacidad | null; extra?: number }) {
  if (!c) return null;
  const hab = Number(c.dias_habiles), oc = Number(c.dias_ocupados) + extra, l = hab - oc;
  if (!hab) return <span className="cap n"><small>Sin días hábiles</small></span>;
  const k = l < -0.05 ? "c" : l < 0.5 ? "a" : "", tramos = Math.max(1, Math.round(hab));
  const txt = l < -0.05 ? `${num(-l)} d de más` : l < 0.5 ? "Semana llena" : `${num(l)} d libre${l > 1 ? "s" : ""}`;
  return (
    <span className={`cap ${k}`} style={{ "--d": tramos } as CSSProperties} aria-label={`${txt}, de ${num(hab)} días hábiles`}>
      <i>{Array.from({ length: tramos }, (_, i) => <s key={i}><b style={{ width: `${(Math.max(0, Math.min(1, oc - i)) * 100).toFixed(0)}%` }} /></s>)}</i>
      <small>{txt}</small>
    </span>
  );
}

/** Las fases de un proyecto en una tira: cerrada llena, en curso con su avance, vencida en tierra, por abrir solo el borde. */
export function TiraFases({ fases, av, enlace, hoy = hoyIso() }: { fases: FaseResumen[]; av?: Map<string, AvanceFase>; enlace?: string; hoy?: string }) {
  return (
    <div className="tf" role="list" aria-label="Fases del proyecto">
      {fases.map((f) => {
        const e = estadoFase(f, av, hoy), dice = `${nFase(f.fase)}: ${e.dice}`;
        const dentro = (
          <>
            <i>{e.abierta ? <b style={{ width: `${e.pct.toFixed(0)}%` }} /> : null}</i>
            <small><span>{nFase(f.fase)}</span>{e.abierta ? <em>{e.pct.toFixed(0)} %</em> : f.estado === "cerrada" ? <em>100 %</em> : null}</small>
          </>
        );
        return enlace
          ? <Link key={f.id} role="listitem" className={e.k} href={enlace} aria-label={dice} title={dice}>{dentro}</Link>
          : <span key={f.id} role="listitem" className={e.k} aria-label={dice} title={dice}>{dentro}</span>;
      })}
    </div>
  );
}

/** Avance general: una barra y su número. */
export const BarraAvance = ({ pct }: { pct: number }) => (
  <span className="av-g"><i><b style={{ width: `${pct.toFixed(0)}%` }} /></i><strong>{pct.toFixed(0)} %</strong></span>
);

export const Cifra = ({ t, v, sub = "", mal = false }: { t: string; v: string; sub?: string; mal?: boolean }) => (
  <div className="cifra"><small>{t}</small><b className={mal ? "c" : undefined}>{v}</b>{sub ? <span>{sub}</span> : null}</div>
);

export const Grupo = ({ tono = "", children, style }: { tono?: string; children: ReactNode; style?: CSSProperties }) => <div className={`grupo ${tono}`} style={style}>{children}</div>;
export const Vacio = ({ children, corto = false }: { children: ReactNode; corto?: boolean }) => <p className="vacio" style={corto ? { padding: "14px 0" } : undefined}>{children}</p>;
export const Nota = ({ children, style }: { children: ReactNode; style?: CSSProperties }) => <p className="nota" style={style}>{children}</p>;
export const Frase = ({ children, style }: { children: ReactNode; style?: CSSProperties }) => <p className="frase" style={style}>{children}</p>;
/** Lo que la pantalla dice en rojo tierra dentro de una frase. */
export const Em = ({ children }: { children: ReactNode }) => <em>{children}</em>;

/** Una fila de lista: título en negrilla y líneas debajo. Es enlace, botón o solo texto. */
export function Fila({ href, externo, onClick, children, className = "", style, ariaExpanded }: { href?: string; externo?: boolean; onClick?: () => void; children: ReactNode; className?: string; style?: CSSProperties; ariaExpanded?: boolean }) {
  const cls = `fila ${className}`.trim();
  if (href && externo) return <a className={cls} href={href} target="_blank" rel="noopener" style={style}>{children}</a>;
  if (href) return <Link className={cls} href={href} style={style} aria-expanded={ariaExpanded}>{children}</Link>;
  if (onClick) return <button type="button" className={cls} onClick={onClick} style={style}>{children}</button>;
  return <div className={cls} style={style}>{children}</div>;
}

/** El logo oficial: solo cambia de tamaño, nunca de proporción (docs/marca/LEAME.md). */
export const Logo = ({ style }: { style?: CSSProperties }) => (
  <picture className="logo" style={style}>
    <source srcSet="/logo-blanco.png" media="(prefers-color-scheme: dark)" />
    <img src="/logo.png" width={1000} height={431} alt="ESA Arquitectura" />
  </picture>
);

export { libres };
