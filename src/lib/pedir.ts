// Lo que dice la base, sin el código del control. Lo que no es una frase, traducido.

export function decir(e: unknown): string {
  const m = String((e as { message?: string })?.message || e || "");
  if (/row-level security|permission denied/i.test(m)) return "No tiene permiso para hacer esto.";
  if (/Invalid login credentials/i.test(m)) return "El correo o la contraseña no coinciden.";
  if (/Email not confirmed/i.test(m)) return "Falta confirmar el correo: abra el mensaje que le llegó y toque el enlace.";
  if (/User already registered/i.test(m)) return "Ese correo ya tiene acceso. Entre con su contraseña o pida un enlace.";
  if (/rate limit|security purposes/i.test(m)) return "Se pidieron demasiados correos seguidos. Espere unos minutos e intente de nuevo.";
  if (/Password should be/i.test(m)) return "La contraseña debe tener al menos 6 caracteres.";
  if (/should be different from the old/i.test(m)) return "La contraseña nueva debe ser distinta de la anterior.";
  if (/Auth session missing|expired|invalid.*(token|link)/i.test(m)) return "El enlace ya no sirve. Pida otro con «Olvidé mi contraseña».";
  if (/duplicate key.*codigo/i.test(m)) return "Ya existe un proyecto con ese código.";
  if (/duplicate key.*correo/i.test(m)) return "Ya hay una persona con ese correo.";
  if (/duplicate key/i.test(m)) return "Eso ya estaba registrado.";
  if (/Failed to fetch|NetworkError/i.test(m)) return "No hay conexión. Revise la señal e intente de nuevo.";
  return m.replace(/^[A-Z]\d+\s·\s/, "");
}

type Respuesta = { data: unknown; error: unknown };
type Datos<R extends Respuesta> = Extract<R, { error: null }>["data"];

/** La respuesta de Supabase: datos o error. Si hay error, se lanza tal cual lo dijo la base.
 *  Para una lista o una función, los datos nunca vienen vacíos cuando no hay error. */
export async function pedir<R extends Respuesta>(consulta: PromiseLike<R>): Promise<NonNullable<Datos<R>>> {
  const { data, error } = await consulta;
  if (error) throw error;
  return data as NonNullable<Datos<R>>;
}

/** Como pedir(), para una sola fila que puede no existir (maybeSingle). */
export async function pedirUno<R extends Respuesta>(consulta: PromiseLike<R>): Promise<Datos<R>> {
  const { data, error } = await consulta;
  if (error) throw error;
  return data as Datos<R>;
}

export type Aviso = { tipo: "bien" | "error"; texto: string };
export const bien = (texto: string): Aviso => ({ tipo: "bien", texto });
export const mal = (e: unknown): Aviso => ({ tipo: "error", texto: decir(e) });
