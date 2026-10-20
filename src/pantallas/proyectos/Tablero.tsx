"use client";
// Tablero: una columna por estado; en el celular se desliza de lado, una a la
// vez. Las tarjetas se arrastran entre columnas con las mismas reglas de los
// botones de la tarea (destinos). Con el ratón el arrastre arranca al mover;
// con el dedo, al dejarlo quieto un momento sobre la tarjeta, para no pelear
// con el desplazamiento del tablero.
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { sb } from "@/lib/supabase/cliente";
import { bien, mal, pedir } from "@/lib/pedir";
import { useSesion } from "@/lib/sesion";
import { R } from "@/lib/rutas";
import { COLUMNAS } from "@/lib/dominio/catalogos";
import { corta } from "@/lib/dominio/fechas";
import { nFase } from "@/lib/dominio/texto";
import { plazo } from "@/lib/dominio/plazo";
import { Avatar, BarraPlazo, Marca } from "@/componentes/ui/piezas";
import { destinos } from "./destinos";
import { nombreFaseDe, quienDe, type TareaP, type VistaProps } from "./tipos";

interface Arrastre {
  card: HTMLElement; x: number; y: number; activo: boolean; id: number; toque: boolean;
  espera?: ReturnType<typeof setTimeout>; dx?: number; dy?: number; fantasma?: HTMLElement; sobre?: HTMLElement | null;
}
// Dónde se estaba mirando antes de recargar, para volver ahí.
let restaurar: { proyecto: string; y: number; x: number } | null = null;

export function Tablero({ id, fases, tareas, hoy, yo, repartir }: VistaProps) {
  const { ir, avisar, recargar } = useSesion();
  const kb = useRef<HTMLDivElement>(null);
  const arrastre = useRef<Arrastre | null>(null);
  const ignorarClick = useRef(false);
  // Lo movido se pinta de una vez; si la base no lo acepta, la recarga lo devuelve a su sitio.
  const [movidas, setMovidas] = useState<Record<string, string>>({});
  const fase = new Map(fases.map((f) => [f.id, f]));
  const visibles = tareas.map((t) => (movidas[t.id] ? { ...t, estado: movidas[t.id] } : t));

  // Al volver a montarse tras recargar, vuelve a donde se estaba mirando.
  useEffect(() => {
    if (restaurar?.proyecto !== id) return;
    const { y, x } = restaurar; restaurar = null;
    const t = setTimeout(() => { window.scrollTo(0, y); if (kb.current) kb.current.scrollLeft = x; }, 0);
    return () => clearTimeout(t);
  }, [id]);

  async function moverTarea(card: HTMLElement, a: string) {
    const tid = card.dataset.id!, desde = card.closest<HTMLElement>(".kb-c")?.dataset.estado;
    const t = tareas.find((x) => x.id === tid); if (!t) return;
    if (desde === "en_revision" && a === "con_observaciones") return ir(R.tarea(tid), { tipo: "bien", texto: "Para devolverla, escriba abajo qué falta y oprima Devolver." });
    setMovidas((m) => ({ ...m, [tid]: a }));
    try {
      if (desde === "en_revision" && a === "terminada" && (card.dataset.puede || "").includes("con_observaciones"))
        await pedir(sb().from("revision_diseno").insert({ tarea_id: tid, revisor_id: yo.persona_id, resultado: "aprobada" as const, observaciones: null }));
      else await pedir(sb().from("tarea_diseno").update({ estado: a as "en_curso" }).eq("id", tid));
      // Se vuelve a pintar para que los conteos de arriba cuadren, sin perder dónde se estaba mirando.
      restaurar = { proyecto: id, y: window.scrollY, x: kb.current?.scrollLeft || 0 };
      avisar(bien(`«${t.titulo}» pasó a ${COLUMNAS.find((c) => c[0] === a)?.[1]}.`));
      recargar();
    } catch (e) { avisar(mal(e)); recargar(); }
  }

  useEffect(() => {
    const raiz = kb.current; if (!raiz) return;
    const columnas = () => [...raiz.querySelectorAll<HTMLElement>(".kb-c")];
    function empezar(x: number, y: number) {
      const a = arrastre.current; if (!a) return;
      const r = a.card.getBoundingClientRect(); a.activo = true; a.dx = x - r.left; a.dy = y - r.top;
      a.fantasma = a.card.cloneNode(true) as HTMLElement; a.fantasma.classList.add("kb-fantasma"); a.fantasma.style.width = r.width + "px";
      document.body.appendChild(a.fantasma); a.card.classList.add("kb-origen");
      const puede = (a.card.dataset.puede || "").split(" ");
      columnas().forEach((c) => c.classList.add(puede.includes(c.dataset.estado || "") ? "kb-puede" : c.contains(a.card) ? "kb-sale" : "kb-no"));
      moverFantasma(x, y); navigator.vibrate?.(15);
    }
    function moverFantasma(x: number, y: number) {
      const a = arrastre.current; if (!a?.fantasma) return;
      a.fantasma.style.transform = `translate(${x - (a.dx || 0)}px,${y - (a.dy || 0)}px) rotate(1.5deg)`;
      a.fantasma.hidden = true; const col = document.elementFromPoint(x, y)?.closest<HTMLElement>(".kb-c.kb-puede") ?? null; a.fantasma.hidden = false;
      const tablero = kb.current; if (!tablero) return;
      tablero.querySelectorAll(".kb-c.kb-sobre").forEach((c) => c !== col && c.classList.remove("kb-sobre")); col?.classList.add("kb-sobre"); a.sobre = col;
      const b = tablero.getBoundingClientRect();   // cerca del borde, el tablero se corre solo
      if (x > b.right - 40) tablero.scrollLeft += 14; else if (x < b.left + 40) tablero.scrollLeft -= 14;
    }
    function soltar(e: PointerEvent | null, cancelar = false) {
      const a = arrastre.current; if (!a || (e && e.pointerId !== a.id)) return;
      arrastre.current = null; clearTimeout(a.espera);
      if (!a.activo) return;
      a.fantasma?.remove(); a.card.classList.remove("kb-origen");
      columnas().forEach((c) => c.classList.remove("kb-puede", "kb-sale", "kb-no", "kb-sobre"));
      ignorarClick.current = true;   // que soltar no abra la tarea
      setTimeout(() => { ignorarClick.current = false; }, 300);
      if (!cancelar && a.sobre?.dataset.estado) moverTarea(a.card, a.sobre.dataset.estado);
    }
    const alBajar = (e: PointerEvent) => {
      const card = (e.target as HTMLElement).closest<HTMLElement>(".kb-t[data-puede]");
      if (!card || e.button > 0 || !card.dataset.puede) return;
      const a: Arrastre = { card, x: e.clientX, y: e.clientY, activo: false, id: e.pointerId, toque: e.pointerType !== "mouse" };
      arrastre.current = a;
      if (a.toque) a.espera = setTimeout(() => arrastre.current === a && empezar(e.clientX, e.clientY), 320);
    };
    const alMover = (e: PointerEvent) => {
      const a = arrastre.current; if (!a || e.pointerId !== a.id) return;
      if (!a.activo) {
        if (Math.hypot(e.clientX - a.x, e.clientY - a.y) < 8) return;
        if (a.toque) { clearTimeout(a.espera); arrastre.current = null; return; }
        empezar(e.clientX, e.clientY);
      }
      moverFantasma(e.clientX, e.clientY);
    };
    const alSoltar = (e: PointerEvent) => soltar(e);
    const alCancelar = (e: PointerEvent) => soltar(e, true);
    const alTeclear = (e: KeyboardEvent) => { if (e.key === "Escape" && arrastre.current?.activo) soltar(null, true); };
    const alArrastrarNativo = (e: DragEvent) => { if ((e.target as HTMLElement).closest?.(".kb-t[data-puede]")) e.preventDefault(); };
    const alTocar = (e: TouchEvent) => { if (arrastre.current?.activo) e.preventDefault(); };
    const alMenu = (e: Event) => { if (arrastre.current?.toque) e.preventDefault(); };
    raiz.addEventListener("pointerdown", alBajar);
    document.addEventListener("pointermove", alMover);
    document.addEventListener("pointerup", alSoltar);
    document.addEventListener("pointercancel", alCancelar);
    document.addEventListener("keydown", alTeclear);
    document.addEventListener("dragstart", alArrastrarNativo);
    document.addEventListener("touchmove", alTocar, { passive: false });
    document.addEventListener("contextmenu", alMenu);
    return () => {
      raiz.removeEventListener("pointerdown", alBajar);
      document.removeEventListener("pointermove", alMover);
      document.removeEventListener("pointerup", alSoltar);
      document.removeEventListener("pointercancel", alCancelar);
      document.removeEventListener("keydown", alTeclear);
      document.removeEventListener("dragstart", alArrastrarNativo);
      document.removeEventListener("touchmove", alTocar);
      document.removeEventListener("contextmenu", alMenu);
      arrastre.current?.fantasma?.remove(); arrastre.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, tareas]);

  const tarjeta = (t: TareaP) => {
    const k = plazo(t, hoy).k, puede = destinos(t, id, yo), quien = quienDe(t);
    return (
      <Link key={t.id} className={`kb-t e-${t.estado} ${k === "c" || k === "a" ? k : ""}`} href={R.tarea(t.id)} data-id={t.id}
        {...(puede.length ? { "data-puede": puede.join(" "), title: "Arrástrela para cambiarla de columna" } : {})} draggable={false}
        onClick={(e) => { if (ignorarClick.current) { e.preventDefault(); ignorarClick.current = false; } }}>
        <span className="f">{nombreFaseDe(t, fase, nFase)}</span>
        <b>{t.titulo}<Marca prioridad={t.prioridad} /></b>
        <span className="q"><Avatar nombre={quien} otro={t.asignada_a !== yo.persona_id} />{quien.split(" ")[0]} · {t.fecha_compromiso ? corta(t.fecha_compromiso) : "sin fecha"}</span>
        <BarraPlazo t={t} hoy={hoy} />
      </Link>
    );
  };

  return (
    <>
      <div className="kb" ref={kb} tabIndex={0} aria-label="Tareas por estado" data-proyecto={id}>
        {COLUMNAS.map(([e, n]) => {
          const l = visibles.filter((t) => t.estado === e)
            .sort((a, b) => e === "terminada" ? String(b.terminada_en || "").localeCompare(String(a.terminada_en || "")) : String(a.fecha_compromiso || "9").localeCompare(String(b.fecha_compromiso || "9")));
          const tope = e === "terminada" ? 8 : 40;
          return (
            <section key={e} className={`kb-c c-${e}`} data-estado={e}>
              <header><span>{n}</span><b>{l.length}</b></header>
              {l.length ? l.slice(0, tope).map(tarjeta) : <p className="kb-nada">Ninguna.</p>}
              {e === "terminada" && l.length > 8 ? <p className="kb-nada">Y {l.length - 8} más.</p> : null}
            </section>
          );
        })}
      </div>
      {repartir}
    </>
  );
}
