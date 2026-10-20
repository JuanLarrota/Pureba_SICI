// El único cliente de Supabase de la aplicación. Lo que una persona no puede
// hacer lo impide la base, no esta pantalla: aquí solo se decide qué mostrar.
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { ES_DEMO, SUPABASE_KEY, SUPABASE_URL } from "@/lib/config";
import { clienteSimulado } from "./simulado";
import type { Database } from "./tipos";

export type Cliente = SupabaseClient<Database>;

let instancia: Cliente | null = null;
export function sb(): Cliente {
  if (!instancia) instancia = ES_DEMO ? clienteSimulado() : createClient<Database>(SUPABASE_URL, SUPABASE_KEY);
  return instancia;
}
