// Un Supabase de mentira para recorrer las pantallas sin sesión real: responde
// con datos fijos (public/demo/datos.json) y anota lo que la aplicación intenta
// escribir. No valida reglas: eso lo prueba pruebas/probar_contra_postgres.py
// contra la base de verdad.
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "./tipos";

type Fila = Record<string, unknown>;
type Datos = Record<string, unknown>;

let datos: Promise<Datos> | null = null;
const cargar = () => (datos ??= fetch("/demo/datos.json").then((r) => r.json() as Promise<Datos>));

export const registro: unknown[] = [];

function consulta(tabla: string) {
  const q = { tabla, filtros: {} as Fila, sin: {} as Fila, en: null as [string, unknown[]] | null, fuera: null as [string, string[]] | null,
    op: "select", cuerpo: null as unknown, uno: false, tope: 0, devuelve: false };
  const api: Record<string, unknown> = {
    select() { if (q.op !== "select") q.devuelve = true; return api; },
    neq(k: string, v: unknown) { q.sin[k] = v; return api; },
    in(k: string, vs: unknown[]) { q.en = [k, vs]; return api; },
    order() { return api; }, or() { return api; }, gte() { return api; }, lte() { return api; },
    eq(k: string, v: unknown) { q.filtros[k] = v; return api; },
    is(k: string, v: unknown) { q.filtros[k] = v; return api; },
    maybeSingle() { q.uno = true; return api; },
    single() { q.uno = true; return api; },
    limit(n: number) { q.tope = n; return api; },
    not(k: string, op: string, v: unknown) { if (op === "in") q.fuera = [k, String(v).replace(/[()]/g, "").split(",")]; return api; },
    insert(c: unknown) { q.op = "insert"; q.cuerpo = c; return api; },
    upsert(c: unknown) { q.op = "upsert"; q.cuerpo = c; return api; },
    update(c: unknown) { q.op = "update"; q.cuerpo = c; return api; },
    overrideTypes() { return api; }, returns() { return api; },
    then(ok: (r: unknown) => unknown, no?: (e: unknown) => unknown) {
      return cargar().then((F) => {
        if (q.op !== "select") {
          registro.push(q);
          // Los cambios a una fila conocida se aplican en memoria, para que la pantalla los muestre hasta recargar.
          if (q.op === "update" && q.filtros.id !== undefined) for (const x of (F[tabla] as Fila[] | undefined) || []) if (x.id === q.filtros.id) Object.assign(x, q.cuerpo as Fila);
          return { data: q.devuelve ? [{ id: (q.filtros.id as string) ?? "nuevo" }] : null, error: null };
        }
        let d = F[tabla] as Fila[] | undefined;
        if (d === undefined) return { data: null, error: { message: "la prueba no tiene datos para " + tabla } };
        for (const [k, v] of Object.entries(q.filtros)) d = d.filter((x) => !(k in x) || x[k] === v);
        for (const [k, v] of Object.entries(q.sin)) d = d.filter((x) => !(k in x) || x[k] !== v);
        if (q.en) { const [k, vs] = q.en; d = d.filter((x) => !(k in x) || vs.includes(x[k])); }
        if (q.fuera) { const [k, vs] = q.fuera; d = d.filter((x) => !(k in x) || !vs.includes(String(x[k]))); }
        if (q.tope) d = d.slice(0, q.tope);
        return { data: q.uno ? d[0] ?? null : d, error: null };
      }).then(ok, no);
    },
  };
  return api;
}

export function clienteSimulado(): SupabaseClient<Database> {
  const cliente = {
    from: consulta,
    rpc(nombre: string, args?: Record<string, unknown>) {
      registro.push({ rpc: nombre, args });
      // Como el real: se le pueden encadenar overrideTypes(), select(), etc. antes del await.
      const api: Record<string, unknown> = {
        overrideTypes() { return api; }, returns() { return api; }, select() { return api; }, single() { return api; }, maybeSingle() { return api; },
        then(ok: (r: unknown) => unknown, no?: (e: unknown) => unknown) {
          return cargar().then((F) => {
            const d = F[`rpc:${nombre}:${args?.p_persona}`] ?? F["rpc:" + nombre];
            return d === undefined ? { data: null, error: { message: "la prueba no tiene " + nombre } } : { data: d, error: null };
          }).then(ok, no);
        },
        catch(no: (e: unknown) => unknown) { return (api.then as (ok: (r: unknown) => unknown) => Promise<unknown>)((r) => r).catch(no); },
      };
      return api;
    },
    auth: {
      onAuthStateChange(cb: (evento: string, sesion: unknown) => void) {
        setTimeout(() => cb("INITIAL_SESSION", { user: { id: "u1", email: "demo@ejemplo.local" } }), 0);
        return { data: { subscription: { unsubscribe() {} } } };
      },
      signOut: async () => ({ error: null }),
      signInWithPassword: async () => ({ data: {}, error: null }),
      signUp: async () => ({ data: { session: null }, error: null }),
      signInWithOtp: async () => ({ data: {}, error: null }),
      resetPasswordForEmail: async () => ({ data: {}, error: null }),
      updateUser: async () => ({ data: { user: {} }, error: null }),
    },
  };
  return cliente as unknown as SupabaseClient<Database>;
}
