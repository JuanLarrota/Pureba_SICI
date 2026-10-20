"use client";
// La sesión de la persona: su cuenta de Supabase y su ficha (mi_sesion), el
// aviso que se muestra una vez al cambiar de pantalla y la navegación.
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { sb } from "@/lib/supabase/cliente";
import { mal, pedir, type Aviso } from "@/lib/pedir";
import { clave } from "@/lib/rutas";

/** Mi ficha y lo que puedo hacer, tal como lo devuelve la función mi_sesion de la base. */
export interface Yo {
  persona_id: string;
  nombre: string;
  rol: string;
  es_direccion: boolean;
  es_socio?: boolean;
  asigna: boolean;
  dirige: string[];
  revisa: string[];
  registra: string[];
  vende: boolean;
  obras: boolean;
  ve_dinero: boolean;
  ve_reservado?: boolean;
}

interface Sesion {
  usuario: User | null;
  yo: Yo | null;
  listo: boolean;          // ya se supo si hay sesión
  recuperando: boolean;    // llegó desde el correo para cambiar la contraseña
  terminarRecuperacion: () => void;
  actual: string;          // la pantalla abierta, como clave de ruta
  aviso: Aviso | null;
  version: number;         // cambia cuando hay que volver a leer la pantalla
  avisar: (a: Aviso | null) => void;
  ir: (ruta: string, aviso?: Aviso) => void;
  recargar: () => void;
  recargarSesion: () => Promise<void>;
}

const Contexto = createContext<Sesion | null>(null);
const CUALQUIERA = "*";

export function SesionProvider({ children }: { children: ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const search = useSearchParams();
  const actual = clave(pathname + (search.toString() ? `?${search}` : ""));
  const [usuario, setUsuario] = useState<User | null>(null);
  const [yo, setYo] = useState<Yo | null>(null);
  const [listo, setListo] = useState(false);
  const [recuperando, setRecuperando] = useState(false);
  const [version, setVersion] = useState(0);
  // El aviso sabe para qué pantalla es. Se ve ahí y desaparece al pasar a otra pantalla.
  const [avisoEstado, setAvisoEstado] = useState<{ aviso: Aviso; para: string } | null>(null);

  const cargarYo = useCallback(async (u: User | null) => {
    if (!u) { setYo(null); return; }
    try {
      setYo((await pedir(sb().rpc("mi_sesion"))) as unknown as Yo);
      setAvisoEstado((a) => (a?.para === CUALQUIERA ? null : a));
    } catch (e) { setYo(null); setAvisoEstado({ aviso: mal(e), para: CUALQUIERA }); }
  }, []);

  // Al cambiar de pantalla, el aviso que no es para la nueva se va. Se hace un
  // instante después para no cambiar estado dentro del propio efecto.
  useEffect(() => {
    const t = setTimeout(() => setAvisoEstado((a) => (a && a.para !== actual && a.para !== CUALQUIERA ? null : a)), 0);
    return () => clearTimeout(t);
  }, [actual]);

  useEffect(() => {
    let anterior: string | undefined;
    const { data } = sb().auth.onAuthStateChange((evento, sesion) => {
      const u = sesion?.user ?? null;
      if (evento === "PASSWORD_RECOVERY") { setRecuperando(true); anterior = u?.id; setUsuario(u); cargarYo(u).then(() => setListo(true)); return; }
      if (evento === "INITIAL_SESSION" || u?.id !== anterior) {
        anterior = u?.id;
        setUsuario(u);
        cargarYo(u).then(() => setListo(true));
      }
    });
    return () => data.subscription.unsubscribe();
  }, [cargarYo]);

  const avisar = useCallback((a: Aviso | null) => setAvisoEstado(a ? { aviso: a, para: actual } : null), [actual]);
  const recargar = useCallback(() => setVersion((v) => v + 1), []);
  const terminarRecuperacion = useCallback(() => setRecuperando(false), []);
  const ir = useCallback((ruta: string, aviso?: Aviso) => {
    const destino = clave(ruta);
    if (aviso) setAvisoEstado({ aviso, para: destino });
    if (destino === actual) setVersion((v) => v + 1);
    else router.push(ruta);
  }, [router, actual]);
  const recargarSesion = useCallback(() => cargarYo(usuario), [cargarYo, usuario]);

  const aviso = avisoEstado && (avisoEstado.para === actual || avisoEstado.para === CUALQUIERA) ? avisoEstado.aviso : null;
  const valor = useMemo<Sesion>(() => ({ usuario, yo, listo, recuperando, terminarRecuperacion, actual, aviso, version, avisar, ir, recargar, recargarSesion }),
    [usuario, yo, listo, recuperando, terminarRecuperacion, actual, aviso, version, avisar, ir, recargar, recargarSesion]);
  return <Contexto.Provider value={valor}>{children}</Contexto.Provider>;
}

export function useSesion(): Sesion {
  const s = useContext(Contexto);
  if (!s) throw new Error("useSesion solo funciona dentro de SesionProvider");
  return s;
}

/** La ficha de quien entró. Solo se usa en pantallas que ya saben que hay ficha. */
export function useYo(): Yo {
  const { yo } = useSesion();
  if (!yo) throw new Error("No hay ficha en sesión");
  return yo;
}
