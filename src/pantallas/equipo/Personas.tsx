"use client";
// Las personas del equipo: quién ya entró, su rol y su profesión. Dirección
// agrega a alguien con su correo; después esa persona crea su propio acceso.
import { sb } from "@/lib/supabase/cliente";
import { bien, mal, pedir } from "@/lib/pedir";
import { useSesion, useYo } from "@/lib/sesion";
import { useDatos } from "@/lib/useDatos";
import { R } from "@/lib/rutas";
import { ROL } from "@/lib/dominio/catalogos";
import { Carga } from "@/componentes/marco/Carga";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Boton } from "@/componentes/formularios/Boton";
import { Formulario, Opciones } from "@/componentes/formularios/Formulario";
import { Etiqueta, Fila, Grupo, Nota } from "@/componentes/ui/piezas";

const ROLES = ["practicante", "arquitecto", "director_proyecto", "residente", "director", "mercadeo", "financiero", "socio"];

export function Personas() {
  const yo = useYo();
  const { avisar, recargar } = useSesion();
  // Quien tiene Mando y Obras no ve Equipo en el pie: llega desde Mi cuenta.
  const atras = yo.obras && (yo.asigna || yo.dirige.length) ? R.yo : R.equipo;
  const estado = useDatos(async () => {
    const [personas, profesiones] = await Promise.all([
      pedir(sb().from("persona").select("id,nombre,rol,correo,auth_user_id,ve_reservado,profesion(nombre)").eq("es_interno", true).eq("activo", true).order("nombre")),
      yo.es_direccion ? pedir(sb().from("profesion").select("id,nombre").eq("activa", true).order("nombre")) : [],
    ]);
    return { personas, profesiones };
  }, [yo.persona_id]);

  return (
    <Carga estado={estado} atras={atras}>
      {({ personas, profesiones }) => (
        <Pantalla titulo="Personas" atras={atras}>
          {personas.map((p) => {
            const profesion = p.profesion as unknown as { nombre: string } | null;
            return (
              <Fila key={p.id}>
                <b>{p.nombre}<Etiqueta tono={p.auth_user_id ? "o" : "n"}>{p.auth_user_id ? "Ya entró" : "No ha entrado"}</Etiqueta></b>
                <span>{ROL[p.rol] || p.rol}{profesion ? ` · ${profesion.nombre}` : ""}{yo.es_direccion && p.correo ? ` · ${p.correo}` : ""}</span>
                {yo.es_socio && p.rol !== "socio" ? (
                  // F7 · Préstamos y la cuenta de los socios: los ve un socio y a quien él le dé el permiso.
                  <Boton className="enlace" accion={async () => {
                    const si = !p.ve_reservado;
                    if (si && !window.confirm("Va a ver los préstamos, los créditos y la cuenta de los socios. ¿Le da el permiso?")) return;
                    const r = await pedir(sb().from("persona").update({ ve_reservado: si }).eq("id", p.id).select("id"));
                    avisar(r.length ? bien(si ? "Permiso dado: ya ve préstamos y socios." : "Permiso quitado.") : mal("Este permiso lo da un socio.")); recargar();
                  }}>{p.ve_reservado ? "Ve préstamos y socios · quitarle el permiso" : "Darle permiso de ver préstamos y socios"}</Boton>
                ) : yo.ve_reservado && (p.rol === "socio" || p.ve_reservado) ? <span>Ve préstamos y socios</span> : null}
              </Fila>
            );
          })}
          {yo.es_direccion ? (
            <>
              <Grupo>Agregar a alguien</Grupo>
              <Formulario onEnviar={async (f) => {
                await pedir(sb().from("persona").insert({ nombre: f.nombre.trim(), correo: f.correo.trim().toLowerCase(), rol: f.rol as "practicante", es_interno: true, horas_semana: 40, profesion_id: f.profesion || null }));
                avisar(bien(`${f.nombre.trim()} ya tiene ficha. Falta que cree su acceso con ese correo.`)); recargar();
              }}>
                <label htmlFor="pn">Nombre completo</label>
                <input id="pn" name="nombre" required autoComplete="off" />
                <label htmlFor="pc">Correo con el que va a entrar</label>
                <input id="pc" name="correo" type="email" required autoComplete="off" inputMode="email" />
                <div className="dos">
                  <div><label htmlFor="prl">Rol</label><select id="prl" name="rol" defaultValue="practicante"><Opciones de={ROLES.map((r) => [r, ROL[r]])} /></select></div>
                  <div><label htmlFor="pf">Profesión</label><select id="pf" name="profesion" defaultValue=""><Opciones de={profesiones.map((x) => [x.id, x.nombre])} vacia="Sin definir" /></select></div>
                </div>
                <button className="btn">Agregar al equipo de ESA</button>
                <Nota>Después, esa persona abre la aplicación, toca «Es mi primera vez» y crea su acceso con ese mismo correo.</Nota>
              </Formulario>
            </>
          ) : null}
        </Pantalla>
      )}
    </Carga>
  );
}
