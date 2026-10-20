// Un Supabase de mentira para probar las pantallas sin sesión real: responde
// con datos fijos y anota lo que la aplicación intenta escribir. No valida
// reglas: eso lo prueba probar_contra_postgres.py contra la base de verdad.
const F = await (await fetch("_datos.json")).json();
const registro = (window.__registro = []);
function consulta(tabla) {
  const q = { tabla, filtros: {}, sin: {}, op: "select", cuerpo: null, uno: false };
  const api = {
    select() { if (q.op !== "select") q.devuelve = true; return api; }, neq(k, v) { q.sin[k] = v; return api; }, in(k, vs) { q.en = [k, vs]; return api; }, order() { return api; }, or() { return api; }, gte() { return api; },
    eq(k, v) { q.filtros[k] = v; return api; }, maybeSingle() { q.uno = true; return api; },
    is(k, v) { q.filtros[k] = v; return api; }, limit(n) { q.tope = n; return api; },
    not(k, op, v) { if (op === "in") q.fuera = [k, String(v).replace(/[()]/g, "").split(",")]; return api; },
    insert(c) { q.op = "insert"; q.cuerpo = c; return api; }, upsert(c) { q.op = "upsert"; q.cuerpo = c; return api; }, update(c) { q.op = "update"; q.cuerpo = c; return api; },
    then(ok, no) {
      let r;
      if (q.op !== "select") { registro.push(q);
        // Los cambios a una fila conocida se aplican en memoria, para que la pantalla los muestre hasta recargar.
        if (q.op === "update" && q.filtros.id !== undefined) for (const x of F[tabla] || []) if (x.id === q.filtros.id) Object.assign(x, q.cuerpo); r = { data: q.devuelve ? [{ id: q.filtros.id ?? "nuevo" }] : null, error: null }; }
      else {
        let d = F[tabla];
        if (d === undefined) r = { data: null, error: { message: "la prueba no tiene datos para " + tabla } };
        else { // filtra solo por las columnas que la fila de prueba sí trae
          for (const [k, v] of Object.entries(q.filtros)) d = d.filter(x => !(k in x) || x[k] === v);
          for (const [k, v] of Object.entries(q.sin)) d = d.filter(x => !(k in x) || x[k] !== v);
          if (q.en) d = d.filter(x => !(q.en[0] in x) || q.en[1].includes(x[q.en[0]]));
          if (q.fuera) d = d.filter(x => !(q.fuera[0] in x) || !q.fuera[1].includes(x[q.fuera[0]]));
          if (q.tope) d = d.slice(0, q.tope);
          r = { data: q.uno ? (d[0] ?? null) : d, error: null }; }
      }
      return Promise.resolve(r).then(ok, no);
    },
  };
  return api;
}
export function createClient() {
  return {
    from: consulta,
    rpc(nombre, args) { registro.push({ rpc: nombre, args }); const d = F[`rpc:${nombre}:${args?.p_persona}`] ?? F["rpc:" + nombre];
      return Promise.resolve(d === undefined ? { data: null, error: { message: "la prueba no tiene " + nombre } } : { data: d, error: null }); },
    auth: {
      onAuthStateChange(cb) { setTimeout(() => cb("INITIAL_SESSION", { user: { id: "u1", email: "luisa@ejemplo.local" } }), 0); return { data: { subscription: { unsubscribe() {} } } }; },
      signOut: async () => ({ error: null }), signInWithPassword: async () => ({ data: {}, error: null }),
      signUp: async () => ({ data: { session: null }, error: null }), signInWithOtp: async () => ({ data: {}, error: null }),
      resetPasswordForEmail: async () => ({ data: {}, error: null }), updateUser: async () => ({ data: { user: {} }, error: null }),
    },
  };
}
