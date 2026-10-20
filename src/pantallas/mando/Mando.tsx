"use client";
// Centro de mando: lo que se proyecta en el comité de arquitectura y diseño:
// el proceso entero, y por cada persona su función, lo que debe entregar, para
// cuándo y su impacto. No calcula nada propio: junta lo que ya dicen la base y
// las otras pantallas.
import Link from "next/link";
import { useState, useSyncExternalStore } from "react";
import { sb } from "@/lib/supabase/cliente";
import { pedir } from "@/lib/pedir";
import { useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import { SEMANAS } from "@/lib/config";
import { ORDEN_PLANTILLAS } from "@/lib/dominio/catalogos";
import { corta, dia0, enCuanto, fecha, hoyIso, isoDe } from "@/lib/dominio/fechas";
import { lista, nFase, uno } from "@/lib/dominio/texto";
import { avanceTotal, cargaPorPersona, libres, type Carga as CargaSemana } from "@/lib/dominio/plazo";
import type { VColaRevision, VFaseAvance } from "@/lib/supabase/vistas";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Frase, Grupo, Nota, TiraFases } from "@/componentes/ui/piezas";
import { FichaPersona } from "./FichaPersona";
import { FichaProyecto } from "./FichaProyecto";
import { Flujo } from "./Flujo";
import type { AccesoMando, Contexto, FaseMando, Gente, ListaCierre, PersonaMando, PlantillaMando, ProyectoMando, TareaMando } from "./tipos";

const ETAPAS: [string, string][] = [["asignada", "Por empezar"], ["en_curso", "En curso"], ["en_revision", "En revisión"], ["con_observaciones", "Devueltas"], ["terminada", "Terminadas en 14 días"]];

/** Si la pantalla es ancha (se proyecta), las etapas arrancan abiertas. */
const medio = () => window.matchMedia("(min-width:900px)");
const useAncho = () => useSyncExternalStore(
  (cb) => { const m = medio(); m.addEventListener("change", cb); return () => m.removeEventListener("change", cb); },
  () => medio().matches,
  () => false,
);

/** «Desplegar todo» / «Recoger todo» de un bloque: al cambiar, el bloque se vuelve a montar con todo abierto o cerrado. */
function useDesplegar() {
  const [estado, setEstado] = useState({ abierto: false, n: 0 });
  const boton = (hay: boolean) => hay ? (
    <button type="button" className="enlace" onClick={() => setEstado((e) => ({ abierto: !e.abierto, n: e.n + 1 }))}>{estado.abierto ? "Recoger todo" : "Desplegar todo"}</button>
  ) : null;
  return { ...estado, boton };
}

export function Mando() {
  const yo = useYo();
  const [flujoAbierto, setFlujoAbierto] = useState<string | null>(null);   // el flujo que se estaba editando vuelve a quedar abierto
  const ancho = useAncho();
  const personas = useDesplegar(), proyectosD = useDesplegar(), flujos = useDesplegar();
  const estado = useDatos(async () => {
    const hoy = hoyIso(), desde = isoDe(dia0(hoy) - 14);
    const [carga, tareas, personas, accesos, proyectos, fases, cola, plantillas, avance, listasCierre] = await Promise.all([
      pedir(sb().rpc("carga_semanal", { p_semanas: SEMANAS }).overrideTypes<CargaSemana[], { merge: false }>()),
      pedir(sb().from("tarea_diseno").select("id,titulo,estado,prioridad,fecha_inicio,fecha_compromiso,dias_estimados,terminada_en,creada_en,asignada_a,proyecto_id,proyecto(nombre),fase:proyecto_fase(fase)")
        .or(`estado.neq.terminada,terminada_en.gte.${desde}`).order("fecha_compromiso", { nullsFirst: false }).overrideTypes<TareaMando[], { merge: false }>()),
      pedir(sb().from("persona").select("id,nombre,rol,profesion(nombre)").eq("es_interno", true).eq("activo", true).order("nombre").overrideTypes<PersonaMando[], { merge: false }>()),
      pedir(sb().from("acceso_proyecto").select("persona_id,proyecto_id,papel").overrideTypes<AccesoMando[], { merge: false }>()),
      pedir(sb().from("proyecto").select("id,codigo,nombre,unidad,tipo,fase").eq("estado", "activo").order("nombre").overrideTypes<ProyectoMando[], { merge: false }>()),
      pedir(sb().from("proyecto_fase").select("id,proyecto_id,fase,orden,estado,fecha_compromiso,entrega_cliente,responsable_id,dias_habiles_plazo").order("orden").overrideTypes<FaseMando[], { merge: false }>()),
      pedir(sb().from("v_cola_revision").select("*").order("revision_pedida_en").overrideTypes<VColaRevision[], { merge: false }>()),
      pedir(sb().from("plantilla_proyecto").select("id,nombre,tipo,descripcion,plantilla_fase(id,fase,orden,opcional,entrega_cliente,exige_chequeo,exige_aprobacion_cliente,exige_dedicacion,dias_habiles_plazo,responsable_papel,plantilla_tarea(id,titulo,orden,activa,por_espacio,dias_plazo,dias_estimados))")
        .eq("activa", true).overrideTypes<PlantillaMando[], { merge: false }>()),
      pedir(sb().from("v_fase_avance").select("fase_id,proyecto_id,fase,tareas,terminadas,trabajo_terminado").overrideTypes<VFaseAvance[], { merge: false }>()),
      pedir(sb().from("lista_chequeo").select("id,plantilla_id,fase,version,lista_chequeo_item(id,orden,texto,tipo,opciones,obligatorio,activo)").eq("ambito", "fase_diseno").eq("activa", true)
        .order("version", { ascending: false }).overrideTypes<ListaCierre[], { merge: false }>()),
    ]);
    return { hoy, carga, tareas, personas, accesos, proyectos, fases, cola, plantillas, avance, listasCierre };
  }, []);

  return (
    <Carga estado={estado}>
      {({ hoy, carga, tareas, personas: fichas, accesos, proyectos, fases, cola, plantillas, avance, listasCierre }) => {
        const av = new Map(avance.map((a) => [a.fase_id, a]));
        // La lista de cierre de una fase: la de su tipo de proyecto y, si no tiene, la general de esa fase.
        const listaDe = (plantilla: string, fase: string) => listasCierre.find((l) => l.plantilla_id === plantilla && l.fase === fase) || listasCierre.find((l) => !l.plantilla_id && l.fase === fase);
        const P = new Map(fichas.map((p) => [p.id, p])), nom = (id: string | null | undefined) => (P.get(id || "")?.nombre || "").split(" ")[0] || "Alguien", pr = new Map(proyectos.map((p) => [p.id, p]));
        const abiertas = tareas.filter((t) => t.estado !== "terminada"), vence = (t: TareaMando) => !!t.fecha_compromiso && t.fecha_compromiso < hoy && t.estado !== "en_revision";
        const vencidas = abiertas.filter(vence), tarde = cola.filter((c) => c.fuera_de_plazo), porPersona = cargaPorPersona(carga);
        const gente: Gente[] = [...porPersona].map(([id, sem]) => ({ id, sem, nombre: sem[0].nombre, ficha: P.get(id), suyas: abiertas.filter((t) => t.asignada_a === id) }))
          .sort((a, b) => b.suyas.filter(vence).length - a.suyas.filter(vence).length || a.nombre.localeCompare(b.nombre));
        const pasadas = gente.filter((p) => libres(p.sem[0]) < -0.05);
        const ctx: Contexto = { hoy, nom, vence };

        // La frase del comité: primero lo que pesa.
        const partes: string[] = [];
        if (vencidas.length) partes.push(`${uno(vencidas.length, "Hay una tarea vencida", "tareas vencidas")}, de ${lista([...new Set(vencidas.map((t) => nom(t.asignada_a)))])}.`.replace(/^(\d)/, "Hay $1"));
        const fasesTarde = fases.filter((f) => f.estado !== "cerrada" && f.estado !== "pendiente" && f.fecha_compromiso && f.fecha_compromiso < hoy && pr.has(f.proyecto_id));
        if (fasesTarde.length) partes.push(fasesTarde.length === 1 ? `${nFase(fasesTarde[0].fase)} de ${pr.get(fasesTarde[0].proyecto_id)!.nombre} debía entregarse el ${fecha(fasesTarde[0].fecha_compromiso)}.`
          : `${fasesTarde.length} fases ya pasaron su fecha de entrega: ${lista(fasesTarde.map((f) => `${nFase(f.fase).toLowerCase()} de ${pr.get(f.proyecto_id)!.nombre}`))}.`);
        if (cola.length) partes.push(`${cola.length === 1 ? "Una tarea espera revisión" : `Esperan revisión ${cola.length} tareas`}${tarde.length ? (tarde.length === cola.length ? (cola.length === 1 ? " y ya pasó el plazo" : ", todas fuera de plazo") : `, ${tarde.length === 1 ? "una" : tarde.length} fuera de plazo`) : ""}.`);
        if (pasadas.length) partes.push(`${lista(pasadas.map((p) => p.nombre.split(" ")[0]))} ${pasadas.length > 1 ? "tienen" : "tiene"} más trabajo del que cabe esta semana.`);
        const listas = avance.filter((a) => a.trabajo_terminado && pr.has(a.proyecto_id));
        if (listas.length) partes.push(`${lista(listas.map((a) => `${nFase(a.fase)} de ${pr.get(a.proyecto_id)!.nombre}`))} ${listas.length > 1 ? "terminaron todas sus tareas: están listas" : "terminó todas sus tareas: está lista"} para el cierre.`);
        const frase = !abiertas.length && !partes.length ? "Todavía no hay tareas abiertas. Cuando se repartan, el comité las ve aquí." : partes.length ? partes.join(" ") : "Todo va al día: ninguna tarea ni fase vencida, nada espera revisión y nadie está pasado de carga.";

        // El proceso entero, por etapa.
        const tarjeta = (t: TareaMando) => (
          <Link key={t.id} className="m-t" href={R.tarea(t.id)}>
            <b>{t.titulo}</b>
            <span>{nom(t.asignada_a)} · {t.estado === "terminada" ? `terminó el ${corta((t.terminada_en || "").slice(0, 10))}`
              : vence(t) ? <em>vencida {enCuanto(t.fecha_compromiso!)}</em> : t.fecha_compromiso ? corta(t.fecha_compromiso) : <em>sin fecha</em>}</span>
          </Link>
        );
        const etapas = ETAPAS.map(([e, n]) => {
          const l = tareas.filter((t) => t.estado === e).sort((a, b) => (e === "terminada" ? (b.terminada_en || "").localeCompare(a.terminada_en || "") : 0));
          return (
            <details key={e} className="m-e" open={ancho}>
              <summary><b>{l.length}</b><span>{n}</span></summary>
              {l.length ? l.slice(0, 12).map(tarjeta) : <p className="m-nada">Ninguna.</p>}
              {l.length > 12 ? <p className="m-nada">Y {l.length - 12} más.</p> : null}
            </details>
          );
        });

        // La matriz de control (la del Excel de Luisa): el avance va en la barra y las vencidas se nombran, de la más atrasada a la menos.
        const deDiseno = proyectos.filter((p) => p.tipo !== "obra");
        const matriz = deDiseno.map((p) => {
          const fs = fases.filter((f) => f.proyecto_id === p.id), { tot, pct } = avanceTotal(avance.filter((a) => a.proyecto_id === p.id)), pc = Math.round(pct);
          const ven = abiertas.filter((t) => t.proyecto_id === p.id && vence(t)).map((t) => ({ t, d: dia0(hoy) - dia0(t.fecha_compromiso!) })).sort((a, b) => b.d - a.d);
          return (
            <Link key={p.id} href={R.proyecto(p.id)}>
              <span className="mx-cab"><b>{p.nombre}</b>{ven.length ? <span className="marca c">{uno(ven.length, "una vencida", "vencidas")}</span> : null}</span>
              {tot ? (
                <span className={`mx-av${pc >= 100 ? " ok" : ""}`} role="img" aria-label={`Avance total: ${pc} %`}><i><b style={{ width: `${pc}%` }} /></i><strong>{pc} %</strong></span>
              ) : <span className="m-nada">Sin tareas</span>}
              {ven.length ? (
                <ul className="mx-ven">
                  {ven.slice(0, 3).map(({ t, d }) => <li key={t.id}><span>{t.titulo}</span><small>{nom(t.asignada_a).split(" ")[0]} · {d === 1 ? "1 día" : `${d} días`}</small></li>)}
                  {ven.length > 3 ? <li className="mas">y {ven.length - 3} más</li> : null}
                </ul>
              ) : null}
              {fs.length ? <TiraFases fases={fs} av={av} hoy={hoy} /> : <span className="m-nada">Sin fases</span>}
            </Link>
          );
        });

        const ordenadas = [...plantillas].sort((a, b) => ORDEN_PLANTILLAS.indexOf(a.nombre) - ORDEN_PLANTILLAS.indexOf(b.nombre)).filter((pl) => pl.tipo !== "obra");

        return (
          <Pantalla titulo="Centro de mando" sobre={`Arquitectura y diseño · ${fecha(hoy)}`} pie={R.mando} porRevisar={cola.length} ancho claseMain="mando">
            <Frase style={{ marginTop: 18 }}>{frase}</Frase>
            <Grupo>El proceso</Grupo>
            <div className="m-etapas">{etapas}</div>

            <div className="m-cab">
              <Grupo>Cada persona</Grupo>
              <span>
                {yo.es_direccion ? <Link className="enlace" href={R.personas} style={{ marginRight: 16 }}>Agregar o ver fichas</Link> : null}
                {personas.boton(gente.length > 0)}
              </span>
            </div>
            <div id="personas" key={`personas-${personas.n}`}>
              {gente.length ? gente.map((p) => <FichaPersona key={p.id} p={p} accesos={accesos} pr={pr} ctx={ctx} abierta={personas.abierto} />)
                : <p className="m-nada">Todavía no hay equipo que mostrar.</p>}
            </div>

            <div className="m-cab"><Grupo>Fases por proyecto</Grupo></div>
            <div className="mx">{matriz.length ? matriz : <p className="m-nada">Todavía no hay proyectos de arquitectura y diseño abiertos.</p>}</div>

            <div className="m-cab"><Grupo>Cada proyecto</Grupo>{proyectosD.boton(deDiseno.length > 0)}</div>
            <div id="proyectos" key={`proyectos-${proyectosD.n}`}>
              {deDiseno.length ? deDiseno.map((p) => <FichaProyecto key={p.id} p={p} fases={fases} abiertas={abiertas} accesos={accesos} P={P} av={av} ctx={ctx} abierta={proyectosD.abierto} />)
                : <p className="m-nada">Todavía no hay proyectos de arquitectura y diseño abiertos.</p>}
            </div>

            <div className="m-cab"><Grupo>El flujo de cada tipo de proyecto</Grupo>{flujos.boton(ordenadas.length > 0)}</div>
            <div id="flujos" key={`flujos-${flujos.n}`}>
              {ordenadas.length ? ordenadas.map((pl) => <Flujo key={pl.id} pl={pl} listaDe={listaDe} abierta={flujos.abierto || flujoAbierto === pl.id} alCambiar={setFlujoAbierto} />)
                : <p className="m-nada">Todavía no hay plantillas de proyecto.</p>}
            </div>

            <Nota>Las tareas se reparten en Equipo y el impacto sale solo de lo entregado y lo revisado. El tiempo máximo de cada fase y quién responde por ella se definen una vez, en el flujo: al abrir la fase en un proyecto, el sistema le pone su fecha de entrega y su responsable. Cambiar el flujo no mueve los proyectos que ya están andando.</Nota>
          </Pantalla>
        );
      }}
    </Carga>
  );
}
