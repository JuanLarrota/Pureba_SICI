"use client";
// Registrar el día: dos toques por día, en qué estuvo la mañana y en qué la
// tarde. Nada de horas ni de frases. Lo que pasó hace más de una semana lo
// corrige dirección.
import { sb } from "@/lib/supabase/cliente";
import { bien, pedir } from "@/lib/pedir";
import { useSesion, useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import { dia0, diaSemana, fecha, hoyIso, isoDe } from "@/lib/dominio/fechas";
import { nFase, titulo } from "@/lib/dominio/texto";
import type { VDedicacionPendiente } from "@/lib/supabase/vistas";
import type { Database } from "@/lib/supabase/tipos";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Formulario } from "@/componentes/formularios/Formulario";
import { Grupo, Nota } from "@/componentes/ui/piezas";

interface Hecho { fecha: string; bloque: string; tipo: string; proyecto_id: string | null; fase_id: string | null }
interface FaseAbierta { id: string; fase: string; estado: string; proyecto_id: string; proyecto: { nombre: string } | null }

export function Registro() {
  const yo = useYo();
  const { ir } = useSesion();
  const estado = useDatos(async () => {
    const hoy = hoyIso(), desde = isoDe(dia0(hoy) - 14);
    const [pendientes, hechos, fases] = await Promise.all([
      pedir(sb().from("v_dedicacion_pendiente").select("fecha").eq("persona_id", yo.persona_id).order("fecha", { ascending: false }).overrideTypes<Pick<VDedicacionPendiente, "fecha">[], { merge: false }>()),
      pedir(sb().from("dedicacion").select("fecha,bloque,tipo,proyecto_id,fase_id").eq("persona_id", yo.persona_id).gte("fecha", desde)),
      pedir(sb().from("proyecto_fase").select("id,fase,estado,proyecto_id,proyecto(nombre)").in("estado", ["en_curso", "en_revision"])),
    ]);
    const abiertas = (fases as unknown as FaseAbierta[]).filter((f) => yo.registra.includes(f.proyecto_id)).sort((a, b) => (a.proyecto?.nombre || "").localeCompare(b.proyecto?.nombre || ""));
    return { hoy, pendientes, hechos: hechos as Hecho[], abiertas };
  }, [yo.persona_id]);

  return (
    <Carga estado={estado}>
      {({ hoy, pendientes, hechos, abiertas }) => {
        const valor = (d?: Hecho) => (!d ? "" : d.tipo === "proyecto" ? `f:${d.fase_id}:${d.proyecto_id}` : d.tipo);
        const dias = [hoy, ...pendientes.map((x) => x.fecha).filter((x) => x !== hoy)];
        const editable = (d: string) => yo.es_direccion || dia0(hoy) - dia0(d) <= 7;
        const Selector = ({ dia, bloque }: { dia: string; bloque: "manana" | "tarde" }) => {
          const d = hechos.find((x) => x.fecha === dia && x.bloque === bloque), v = valor(d);
          return (
            <select name={`${dia}|${bloque}`} aria-label={`${bloque === "manana" ? "Mañana" : "Tarde"} del ${fecha(dia)}`} defaultValue={v}
              onChange={bloque === "manana" ? (e) => {
                // Si fue todo el día en lo mismo, la tarde se llena sola.
                const t = e.target.closest(".dos")?.querySelector<HTMLSelectElement>('select[name$="|tarde"]');
                if (t && !t.value) t.value = e.target.value;
              } : undefined}>
              <option value="">Sin registrar</option>
              {abiertas.map((f) => <option key={f.id} value={`f:${f.id}:${f.proyecto_id}`}>{f.proyecto?.nombre} · {nFase(f.fase).toLowerCase()}</option>)}
              {d?.tipo === "proyecto" && !abiertas.some((f) => f.id === d.fase_id) ? <option value={v}>Una fase que ya cerró</option> : null}
              <option value="estructura">Trabajo interno de ESA</option>
              <option value="ausencia">No trabajé</option>
            </select>
          );
        };
        return (
          <Pantalla titulo="Registrar mi día" atras={R.dia}>
            <Formulario onEnviar={async (f) => {
              const filas = Object.entries(f).filter(([, v]) => v).map(([k, v]) => {
                const [dia, bloque] = k.split("|"), [, fase, proyecto] = v.startsWith("f:") ? v.split(":") : [];
                return { persona_id: yo.persona_id, fecha: dia, bloque: bloque as "manana" | "tarde", tipo: fase ? "proyecto" : v, proyecto_id: proyecto || null, fase_id: fase || null };
              });
              if (!filas.length) throw new Error("Escoja al menos en qué estuvo una mañana o una tarde.");
              // Las horas de cada bloque las pone la base al guardar.
              await pedir(sb().from("dedicacion").upsert(filas as unknown as Database["public"]["Tables"]["dedicacion"]["Insert"][], { onConflict: "persona_id,fecha,bloque" }));
              const n = new Set(filas.map((x) => x.fecha)).size;
              ir(R.dia, bien(`Quedó registrado${n > 1 ? `: ${n} días` : ""}.`));
            }}>
              {dias.map((d) => (
                <div key={d}>
                  <Grupo tono={d !== hoy ? "c" : ""}>{d === hoy ? "Hoy" : titulo(diaSemana(d))}, {fecha(d)}</Grupo>
                  {editable(d) ? (
                    <div className="dos">
                      <div><label>Mañana</label><Selector dia={d} bloque="manana" /></div>
                      <div><label>Tarde</label><Selector dia={d} bloque="tarde" /></div>
                    </div>
                  ) : <Nota>Pasó más de una semana: este día lo corrige dirección.</Nota>}
                </div>
              ))}
              <button className="btn">Guardar</button>
            </Formulario>
            <Nota>Si estuvo todo el día en lo mismo, escoja la mañana: la tarde se llena sola. {abiertas.length ? "" : "Todavía no hay fases abiertas en sus proyectos: puede registrar trabajo interno."}</Nota>
          </Pantalla>
        );
      }}
    </Carga>
  );
}
