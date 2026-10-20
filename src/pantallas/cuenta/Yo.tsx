"use client";
// Mi cuenta: quién soy, las fichas del equipo (dirección), mi impacto, cómo
// tener la aplicación en el teléfono, la contraseña y salir.
import Link from "next/link";
import { sb } from "@/lib/supabase/cliente";
import { useSesion, useYo } from "@/lib/sesion";
import { R } from "@/lib/rutas";
import { ROL } from "@/lib/dominio/catalogos";
import { Pantalla } from "@/componentes/marco/Pantalla";
import { Boton } from "@/componentes/formularios/Boton";
import { Grupo, Logo } from "@/componentes/ui/piezas";

export function Yo() {
  const yo = useYo();
  const { usuario } = useSesion();
  return (
    <Pantalla titulo={yo.nombre} sobre={ROL[yo.rol] || yo.rol} atras={R.dia}>
      <p style={{ color: "var(--tinta-3)" }}>{usuario?.email}</p>
      <Logo style={{ marginTop: 28 }} />
      {yo.es_direccion ? <Link className="btn" href={R.personas} style={{ marginTop: 28 }}>Personas del equipo: fichas y accesos</Link> : null}
      {yo.asigna || yo.dirige.length ? <Link className="btn claro" href={R.impacto()} style={{ marginTop: yo.es_direccion ? 14 : 28 }}>Mi impacto</Link> : null}
      <Grupo>En el teléfono</Grupo>
      <p>Para tenerla como una aplicación: en iPhone, botón de compartir y «Agregar a inicio»; en Android, menú del navegador e «Instalar aplicación».</p>
      <Link className="btn claro" href={R.clave} style={{ marginTop: 22 }}>Cambiar mi contraseña</Link>
      <Boton className="btn peligro" accion={() => sb().auth.signOut()}>Salir</Boton>
    </Pantalla>
  );
}
