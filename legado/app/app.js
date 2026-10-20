// SICI · aplicación del equipo. Sin compilación: se sirve tal cual.
// Lo que una persona no puede hacer lo impide la base, no esta pantalla: aquí
// solo se decide qué mostrar. Los mensajes de error que vienen de la base ya
// son frases, y se muestran como llegan.
import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/+esm";
import { SUPABASE_URL, SUPABASE_KEY, GOOGLE_CLIENT_ID } from "./config.js";

const sb = createClient(SUPABASE_URL, SUPABASE_KEY);
const app = document.getElementById("app");
let usuario = null;          // la sesión de Supabase
let yo = null;               // mi ficha y lo que puedo hacer (mi_sesion)
let aviso = null;            // un mensaje para mostrar una vez arriba de la pantalla

// ---------- utilidades ----------
const h = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];
const fecha = iso => { if (!iso) return "sin fecha"; const [a, m, d] = String(iso).slice(0, 10).split("-"); return `${+d} de ${MESES[m - 1]}`; };
const hora = iso => new Date(iso).toLocaleString("es-CO", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
const hoyIso = () => new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 10);
const titulo = s => String(s || "").toLowerCase().replace(/(^|\s)(\S)/g, (m, a, b) => a + b.toUpperCase());
const ESTADO = { asignada: "Por empezar", en_curso: "En curso", en_revision: "En revisión", con_observaciones: "Devuelta", terminada: "Terminada" };
const ROL = { socio: "Socio", director: "Dirección", arquitecto: "Arquitecto", director_proyecto: "Director de proyecto", practicante: "Practicante",
  residente: "Residente", mercadeo: "Mercadeo", financiero: "Financiero" };
const UNIDAD = { diseno_arquitectonico: "Diseño arquitectónico", interiorismo: "Interiorismo", consultoria: "Consultoría", obra_propia: "Obra propia",
  obra_colega: "Obra de un colega", peritaje: "Peritaje", administracion: "Administración" };
const SEMANAS = 8;   // las que muestra la carga del equipo
// Cuánto trabajo pide una tarea, en días. Lo escoge quien la asigna.
const ESFUERZO = [[0.3, "Un par de horas"], [0.5, "Medio día"], [1, "Un día"], [2, "Dos días"], [3, "Tres días"], [5, "Una semana"], [10, "Dos semanas"], [15, "Tres semanas"], [20, "Un mes"]];
const num = n => String(Math.round(n * 10) / 10).replace(".", ",");
const enDias = n => { n = Math.round(n * 10) / 10; return n === 0.5 ? "medio día" : n === 1 ? "un día" : `${num(n)} días`; };
const esfuerzo = n => n == null ? "" : (ESFUERZO.find(e => e[0] === Number(n)) || [0, enDias(Number(n)) + " de trabajo"])[1].toLowerCase();
const dia0 = iso => Date.UTC(+iso.slice(0, 4), +iso.slice(5, 7) - 1, +iso.slice(8, 10)) / 864e5;   // días desde 1970
const lunesDe = iso => { const n = dia0(iso); return new Date((n - (new Date(n * 864e5).getUTCDay() + 6) % 7) * 864e5).toISOString().slice(0, 10); };
const corta = iso => `${+iso.slice(8, 10)} ${MESES[iso.slice(5, 7) - 1].slice(0, 3)}`;
const lista = a => a.length < 2 ? a.join("") : a.slice(0, -1).join(", ") + " y " + a[a.length - 1];
const marca = p => p === "alta" ? '<span class="marca a">Alta</span>' : p === "bloqueante" ? '<span class="marca c">Frena a otros</span>' : "";

// ---------- lo que se ve de un vistazo ----------
// Días hábiles (lunes a viernes) que quedan de mañana hasta la entrega, incluida.
const habiles = (desde, hasta) => { let n = 0; for (let d = desde + 1; d <= hasta; d++) { const s = new Date(d * 864e5).getUTCDay(); if (s && s < 6) n++; } return n; };
// Cómo va el plazo de una tarea: qué tan lleno está y de qué color. a = por vencer (dos días hábiles o menos), c = vencida.
function plazo(t) {
  const hoy = dia0(hoyIso());
  if (t.estado === "terminada") return { k: "h", pct: 100, txt: t.terminada_en ? `Entregada ${corta(String(t.terminada_en).slice(0, 10))}` : "Terminada" };
  if (!t.fecha_compromiso) return { k: "n", pct: 0, txt: "Sin fecha" };
  const fin = dia0(t.fecha_compromiso), ini = Math.min(dia0(String(t.fecha_inicio || t.creada_en || t.fecha_compromiso).slice(0, 10)), fin);
  const pct = Math.max(0, Math.min(100, (hoy - ini + 1) / (fin - ini + 1) * 100));
  if (t.estado === "en_revision") return { k: "r", pct, txt: "Pidió revisión" };
  if (hoy > fin) { const n = habiles(fin, hoy); return { k: "c", pct: 100, txt: n ? `Vencida ${n} d` : "Vencida" }; }
  if (hoy === fin) return { k: "a", pct: 100, txt: "Vence hoy" };
  const n = habiles(hoy, fin);
  return { k: n <= 2 ? "a" : "", pct, txt: n === 1 ? "Falta 1 d" : `Faltan ${n} d` };
}
const barraPlazo = t => { const p = plazo(t);
  return `<span class="pz ${p.k}" aria-label="${h(p.txt)}"><i><b style="width:${p.pct.toFixed(0)}%"></b></i><small>${h(p.txt)}</small></span>`; };
// La semana de una persona: un tramo por día hábil, lleno con lo que ya tiene encima.
function barraCapacidad(c, extra = 0) {
  if (!c) return "";
  const hab = Number(c.dias_habiles), oc = Number(c.dias_ocupados) + extra, l = hab - oc;
  if (!hab) return '<span class="cap n"><small>Sin días hábiles</small></span>';
  const k = l < -0.05 ? "c" : l < 0.5 ? "a" : "", tramos = Math.max(1, Math.round(hab));
  const s = Array.from({ length: tramos }, (_, i) => `<s><b style="width:${(Math.max(0, Math.min(1, oc - i)) * 100).toFixed(0)}%"></b></s>`).join("");
  const txt = l < -0.05 ? `${num(-l)} d de más` : l < 0.5 ? "Semana llena" : `${num(l)} d libre${l > 1 ? "s" : ""}`;
  return `<span class="cap ${k}" style="--d:${tramos}" aria-label="${h(txt)}, de ${num(hab)} días hábiles"><i>${s}</i><small>${txt}</small></span>`;
}
const iniciales = n => String(n || "?").split(/\s+/).map(x => x[0]).slice(0, 2).join("").toUpperCase();
const avatar = (n, otro) => `<span class="av${otro ? " otro" : ""}" title="${h(n)}" aria-hidden="true">${h(iniciales(n))}</span>`;
const chipEstado = e => `<span class="ch ${e}">${h(ESTADO[e] || e)}</span>`;
// Las fases de un proyecto en una tira: cerrada llena, en curso con su avance, vencida en tierra, por abrir solo el borde.
function tiraFases(fases, av, enlace) {
  const hoy = hoyIso();
  return `<div class="tf" role="list" aria-label="Fases del proyecto">${fases.map(f => {
    const a = av?.get(f.id), pct = a?.tareas ? a.terminadas / a.tareas * 100 : 0, abierta = f.estado === "en_curso" || f.estado === "en_revision";
    const tarde = abierta && f.fecha_compromiso && f.fecha_compromiso < hoy, k = f.estado === "cerrada" ? "cerrada" : tarde ? "tarde" : abierta ? "curso" : "";
    const dice = `${nFase(f.fase)}: ${f.estado === "cerrada" ? "cerrada" : tarde ? "vencida" : abierta ? `en curso, ${pct.toFixed(0)} %` : "por abrir"}`;
    const tag = enlace ? "a" : "span";
    return `<${tag} role="listitem" class="${k}" ${enlace ? `href="${enlace}"` : ""} aria-label="${h(dice)}" title="${h(dice)}"><i>${abierta ? `<b style="width:${pct.toFixed(0)}%"></b>` : ""}</i><small><span>${h(nFase(f.fase))}</span>${abierta ? `<em>${pct.toFixed(0)} %</em>` : f.estado === "cerrada" ? "<em>100 %</em>" : ""}</small></${tag}>`;
  }).join("")}</div>`;
}
const barraAvance = pct => `<span class="av-g"><i><b style="width:${pct.toFixed(0)}%"></b></i><strong>${pct.toFixed(0)} %</strong></span>`;
// En qué tramo de tiempo cae una tarea abierta, como las listas de Trello.
function tramo(t) {
  if (t.estado === "en_revision") return "revision";
  if (!t.fecha_compromiso) return "sin";
  const hoy = hoyIso(), dom = new Date((dia0(lunesDe(hoy)) + 6) * 864e5).toISOString().slice(0, 10);
  return t.fecha_compromiso < hoy ? "vencidas" : t.fecha_compromiso === hoy ? "hoy" : t.fecha_compromiso <= dom ? "semana" : "despues";
}
const TRAMO = [["vencidas", "Vencidas", "c"], ["hoy", "Para hoy", "a"], ["semana", "Esta semana", ""], ["despues", "Más adelante", ""], ["sin", "Sin fecha", ""], ["revision", "Esperando revisión", ""]];

// Lo que dice la base, sin el código del control. Lo que no es una frase, traducido.
function decir(e) {
  const m = String(e?.message || e || "");
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
async function pedir(consulta) { const { data, error } = await consulta; if (error) throw error; return data; }

// ---------- marco ----------
function cabecera(t, { sobre = "", atras = "" } = {}) {
  const ini = yo ? yo.nombre.split(/\s+/).map(x => x[0]).slice(0, 2).join("").toUpperCase() : "";
  return `<header class="cab">${atras ? `<button class="atras" data-ir="${atras}" aria-label="Volver">‹</button>` : ""}
    <div style="flex:1;min-width:0">${sobre ? `<small>${h(sobre)}</small>` : ""}<h1>${h(t)}</h1></div>
    ${yo && !atras ? `<button class="yo" data-ir="#/yo" aria-label="Mi cuenta">${h(ini)}</button>` : ""}</header>`;
}
function pie(actual, porRevisar = 0) {
  const manda = yo.asigna || yo.dirige.length;
  // Seis como máximo, para que quepan en un teléfono: con Obras, quien tiene Mando ve allí la carga del equipo.
  const it = [["#/", "Mi día"], ...(yo.vende ? [["#/ventas", "Ventas"]] : []), ...(yo.revisa.length ? [["#/revisar", "Revisar"]] : []), ["#/proyectos", "Proyectos"],
    ...(yo.obras ? [["#/obras", "Obras"]] : []), ...(yo.obras && manda ? [] : [["#/equipo", "Equipo"]]),
    manda ? ["#/mando", "Mando"] : ["#/impacto", "Impacto"]];   // quien dirige ve el impacto de todos en el centro de mando
  return `<nav class="pie" aria-label="Secciones"><div>${it.map(([r, n]) =>
    `<a href="${r}" ${r === actual ? 'aria-current="page"' : ""}>${n}${r === "#/revisar" && porRevisar ? `<i>${porRevisar}</i>` : ""}</a>`).join("")}</div></nav>`;
}
function pinta(html) {
  const a = aviso; aviso = null;
  app.innerHTML = html.replace("<main>", `<main>${a ? `<div class="${a.tipo}" role="status">${h(a.texto)}</div>` : ""}`);
  window.scrollTo(0, 0);
}
function ir(ruta, mensaje) { if (mensaje) aviso = mensaje; if (location.hash === ruta) navegar(); else location.hash = ruta; }
const bien = texto => ({ tipo: "bien", texto });
const mal = e => ({ tipo: "error", texto: decir(e) });

// ---------- entrar ----------
// Un campo de contraseña con el botón para verla mientras se escribe.
const campoClave = (id, nombre, etiqueta, auto) => `<label for="${id}">${etiqueta}</label><div class="clave">
  <input id="${id}" name="${nombre}" type="password" autocomplete="${auto}" minlength="6" required autocapitalize="off" spellcheck="false">
  <button type="button" class="ver-clave" data-accion="verClave" data-para="${id}" aria-pressed="false" aria-label="Mostrar la contraseña">Ver</button></div>`;
let recuperando = false;   // llegó desde el correo para cambiar la contraseña
function vistaEntrar(modo = "entrar") {
  const primera = modo === "crear";
  pinta(`<main><div class="entrada">
    <picture class="logo"><source srcset="logo-blanco.png" media="(prefers-color-scheme: dark)"><img src="logo.png" width="1000" height="431" alt="ESA Arquitectura"></picture><div class="sub">SICI · CONTROL INTERNO</div>
    <h1>${primera ? "Crear mi acceso" : "Entrar"}</h1>
    <p style="color:var(--tinta-3)">${primera ? "Use el mismo correo con el que dirección lo agregó al equipo. Le llegará un mensaje para confirmarlo." : "Con el correo que dirección registró para usted."}</p>
    <form data-form="${primera ? "crear" : "entrar"}">
      <label for="correo">Correo</label><input id="correo" name="correo" type="email" autocomplete="email" inputmode="email" required>
      ${campoClave("clave", "clave", "Contraseña", primera ? "new-password" : "current-password")}
      <button class="btn">${primera ? "Crear mi acceso" : "Entrar"}</button>
    </form>
    <button class="enlace" data-accion="${primera ? "modoEntrar" : "modoCrear"}">${primera ? "Ya tengo acceso" : "Es mi primera vez"}</button><br>
    ${primera ? "" : '<button class="enlace" data-accion="recuperar">Olvidé mi contraseña</button><br><button class="enlace" data-accion="enlace">Entrar con un enlace que me llegue al correo</button>'}
  </div></main>`);
}
// Contraseña nueva: llega desde el correo de recuperación o desde Mi cuenta.
function vistaNuevaClave() {
  pinta(`${recuperando ? "" : cabecera("Cambiar mi contraseña", { atras: "#/yo" })}<main><div class="${recuperando ? "entrada" : ""}">
    ${recuperando ? '<picture class="logo"><source srcset="logo-blanco.png" media="(prefers-color-scheme: dark)"><img src="logo.png" width="1000" height="431" alt="ESA Arquitectura"></picture><div class="sub">SICI · CONTROL INTERNO</div><h1>Nueva contraseña</h1>' : ""}
    <p style="color:var(--tinta-3)">Escriba la contraseña nueva dos veces. Debe tener al menos 6 caracteres.</p>
    <form data-form="nuevaClave">
      ${campoClave("clave1", "clave1", "Contraseña nueva", "new-password")}
      ${campoClave("clave2", "clave2", "Repítala", "new-password")}
      <button class="btn">Guardar la contraseña</button>
    </form></div></main>`);
}
const formularios = {
  async nuevaClave(f) {
    if (f.clave1 !== f.clave2) throw new Error("Las dos contraseñas no son iguales. Escríbalas de nuevo.");
    await pedir(sb.auth.updateUser({ password: f.clave1 }));
    recuperando = false;
    if (location.hash.includes("type=recovery") || location.hash.includes("access_token")) history.replaceState(null, "", location.pathname);
    ir("#/", bien("Contraseña cambiada."));
  },
  async entrar(f) { await pedir(sb.auth.signInWithPassword({ email: f.correo.trim(), password: f.clave })); },
  async crear(f) {
    const d = await pedir(sb.auth.signUp({ email: f.correo.trim(), password: f.clave, options: { emailRedirectTo: location.origin + location.pathname } }));
    if (!d.session) { aviso = bien("Listo. Abra el correo que le acabamos de enviar y toque el enlace para confirmar."); vistaEntrar(); }
  },
};
const acciones = {
  verClave(el) {
    const campo = document.getElementById(el.dataset.para), ver = campo.type === "password";
    campo.type = ver ? "text" : "password";
    el.textContent = ver ? "Ocultar" : "Ver";
    el.setAttribute("aria-pressed", ver ? "true" : "false");
    el.setAttribute("aria-label", ver ? "Ocultar la contraseña" : "Mostrar la contraseña");
    campo.focus();
  },
  async recuperar() {
    const correo = document.getElementById("correo").value.trim();
    if (!correo) { aviso = mal("Escriba primero su correo y luego toque «Olvidé mi contraseña»."); return vistaEntrar(); }
    await pedir(sb.auth.resetPasswordForEmail(correo, { redirectTo: location.origin + location.pathname }));
    aviso = bien("Si ese correo está registrado, le llegó un enlace para poner una contraseña nueva. Ábralo en este mismo teléfono.");
    vistaEntrar();
  },
  modoCrear: () => vistaEntrar("crear"),
  modoEntrar: () => vistaEntrar(),
  async enlace() {
    const correo = document.getElementById("correo").value.trim();
    if (!correo) { aviso = mal("Escriba primero su correo."); return vistaEntrar(); }
    await pedir(sb.auth.signInWithOtp({ email: correo, options: { shouldCreateUser: false, emailRedirectTo: location.origin + location.pathname } }));
    aviso = bien("Le enviamos un enlace. Ábralo en este mismo teléfono."); vistaEntrar();
  },
  async salir() { await sb.auth.signOut(); },
};

// ---------- mi día ----------
async function vistaDia() {
  const [dia, cola, listas, sinRegistrar, ventas, carga] = await Promise.all([
    pedir(sb.from("v_mi_dia").select("*").order("orden").order("fecha_compromiso", { nullsFirst: false })),
    yo.revisa.length ? pedir(sb.from("v_cola_revision").select("tarea_id")) : [],
    yo.dirige.length ? pedir(sb.from("v_fase_avance").select("fase_id,proyecto_id,fase").eq("trabajo_terminado", true)) : [],
    pedir(sb.from("v_dedicacion_pendiente").select("fecha").eq("persona_id", yo.persona_id)),
    yo.vende ? pedir(sb.from("v_ventas_hoy").select("persona_id,urgente")) : [],
    sb.rpc("carga_semanal", { p_semanas: 1 }).then(r => r.data || []),
  ]);
  // Para dibujar el plazo hace falta el día en que empezó cada tarea de diseño.
  const ids = dia.filter(t => t.origen === "diseno").map(t => t.id);
  const inicio = new Map(ids.length ? (await pedir(sb.from("tarea_diseno").select("id,fecha_inicio,creada_en").in("id", ids))).map(x => [x.id, x]) : []);
  // Quien vende ve aquí cuánto le toca hoy del embudo; el detalle está en Ventas.
  const deVentas = ventas.filter(x => !x.persona_id || x.persona_id === yo.persona_id);
  const venta = yo.vende ? `<a class="fila" href="#/ventas"><b>Ventas para hoy</b><span>${deVentas.length ? `${deVentas.some(x => x.urgente) ? "<em>" : ""}${uno(deVentas.length, "Una cosa", "cosas")} del embudo${deVentas.some(x => x.urgente) ? "</em>" : ""}` : "Nada del embudo para hoy"}</span></a>` : "";
  // El tiempo se registra escogiendo, dos veces al día. Sin eso una fase no cierra.
  const tiempo = `<a class="fila" href="#/registro"><b>Registrar mi día</b><span>${sinRegistrar.length ? `<em>Le ${sinRegistrar.length === 1 ? "falta un día" : `faltan ${sinRegistrar.length} días`} por registrar</em>` : "En qué trabajó hoy, mañana y tarde"}</span></a>`;
  // Fases que ya terminaron su trabajo en los proyectos que dirijo: falta decidir el cierre.
  const mias = listas.filter(a => yo.dirige.includes(a.proyecto_id));
  const nombres = mias.length ? new Map((await pedir(sb.from("proyecto").select("id,nombre").in("id", mias.map(a => a.proyecto_id)))).map(x => [x.id, x.nombre])) : new Map();
  const decidir = mias.length ? `<div class="grupo">Para decidir</div>` + mias.map(a => `<a class="fila" href="#/cierre/${a.fase_id}"><b>${h(nFase(a.fase))} de ${h(nombres.get(a.proyecto_id) || "un proyecto")}</b>
    <span>Terminó todas sus tareas: está lista para el cierre.</span></a>`).join("") : "";
  // Las tareas por tramo de tiempo, como las listas de Trello. La base ya las trae en su orden de importancia.
  const por = new Map(TRAMO.map(([k]) => [k, []]));
  for (const t of dia) por.get(tramo(t)).push(t);
  const lista = TRAMO.filter(([k]) => por.get(k).length).map(([k, nombre, c]) => `<div class="grupo ${c}">${nombre} · ${por.get(k).length}</div>` + por.get(k).map(t => {
    const espera = /^La espera /.test(t.lectura || "") ? `<span class="espera-tag">${h(t.lectura.split(" · ")[0])}</span>` : "";
    const cuerpo = `<b>${h(t.titulo)}${marca(t.prioridad)}${espera}</b><span>${h(titulo(t.proyecto))}${t.origen === "diseno" ? "" : " · pendiente de obra"}</span>${barraPlazo({ ...t, ...inicio.get(t.id) })}`;
    return t.origen === "diseno" ? `<a class="fila" href="#/tarea/${t.id}">${cuerpo}</a>` : `<a class="fila" href="#/obra/${t.proyecto_id}/pendientes">${cuerpo}</a>`;
  }).join("")).join("");
  // Mi semana: cuánto tengo encima y cuántas cosas vencen.
  const mia = carga.find(c => c.persona_id === yo.persona_id && c.semana <= hoyIso());
  const n = k => por.get(k).length;
  const semana = dia.length || mia ? `<section class="semana" aria-label="Mi semana"><div class="grupo" style="margin-top:0">Mi semana</div>${barraCapacidad(mia)}
    <div class="cuenta"><div class="${n("vencidas") ? "c" : ""}"><b>${n("vencidas")}</b><small>Vencidas</small></div><div class="${n("hoy") ? "a" : ""}"><b>${n("hoy")}</b><small>Para hoy</small></div><div><b>${n("semana")}</b><small>Esta semana</small></div></div></section>` : "";
  pinta(cabecera("Mi día", { sobre: fecha(hoyIso()) }) + `<main>${semana}${tiempo}${venta}${decidir}${lista || (decidir ? "" : '<p class="vacio">Nada pendiente. Cuando le asignen algo, aparece aquí.</p>')}</main>
    <button class="mas" data-ir="#/nueva" aria-label="Nueva tarea">+</button>` + pie("#/", cola.length));
}

// ---------- una tarea ----------
async function vistaTarea(id) {
  const [t, ctx, rastro, revs] = await Promise.all([
    pedir(sb.from("tarea_diseno").select("id,titulo,descripcion,estado,prioridad,fecha_inicio,fecha_compromiso,dias_estimados,proyecto_id,asignada_a,asignada_por,bloqueada_por,requiere_revision,revisor_id," +
      "proyecto(nombre),tiene:persona!tarea_diseno_asignada_a_fkey(nombre),asigno:persona!tarea_diseno_asignada_por_fkey(nombre),revisa:persona!tarea_diseno_revisor_id_fkey(nombre)").eq("id", id).maybeSingle()),
    pedir(sb.from("v_tarea_contexto").select("para_que").eq("tarea_id", id).maybeSingle()),
    pedir(sb.from("tarea_evento").select("tipo,de,a,ocurrio_en,persona(nombre)").eq("tarea_id", id).order("ocurrio_en")),
    pedir(sb.from("revision_diseno").select("resultado,observaciones,revisada_en,persona(nombre)").eq("tarea_id", id).order("revisada_en", { ascending: false })),
  ]);
  if (!t) return pinta(cabecera("Tarea", { atras: "#/" }) + '<main><p class="vacio">Esa tarea no existe o no es de sus proyectos.</p></main>');
  const mia = t.asignada_a === yo.persona_id, dirijo = yo.dirige.includes(t.proyecto_id), laAsigne = t.asignada_por === yo.persona_id;
  // Sin el dato (tareas de antes), pasa por revisión y la revisa quien tenga ese papel en el proyecto.
  const sinRevision = t.requiere_revision === false, entrega = sinRevision ? "terminada" : "en_revision";
  const reviso = !mia && !sinRevision && (t.revisor_id ? t.revisor_id === yo.persona_id : yo.revisa.includes(t.proyecto_id));
  const devuelta = revs.find(r => r.resultado === "con_observaciones");
  let botones = "";
  if (mia && t.estado === "asignada") botones = `<div class="par"><button class="btn claro" data-accion="estado" data-id="${t.id}" data-a="en_curso">Empezar</button><button class="btn" data-accion="estado" data-id="${t.id}" data-a="${entrega}">${sinRevision ? "Entregar y cerrar" : "Pedir revisión"}</button></div>`;
  else if (mia && (t.estado === "en_curso" || t.estado === "con_observaciones")) botones = `<button class="btn" data-accion="estado" data-id="${t.id}" data-a="${entrega}">${sinRevision ? "Entregar y cerrar" : t.estado === "en_curso" ? "Pedir revisión" : "Volver a pedir revisión"}</button>`;
  else if (mia && t.estado === "en_revision") botones = `<p class="nota">Ya está en manos de ${t.revisa?.nombre ? h(t.revisa.nombre) : "quien revisa"}.</p><button class="btn claro" data-accion="estado" data-id="${t.id}" data-a="en_curso">Retirar la entrega</button>`;
  if (reviso && t.estado === "en_revision") botones += `<form data-form="revisar" data-id="${t.id}">
      <label for="obs">Observación (obligatoria para devolver)</label><textarea id="obs" name="obs"></textarea>
      <div class="par"><button class="btn" name="r" value="aprobada">Aprobar</button><button class="btn claro" name="r" value="con_observaciones">Devolver</button></div></form>`;
  const edita = (dirijo || laAsigne) && t.estado !== "terminada", reasigna = edita && (dirijo || yo.asigna);
  const gente = reasigna ? [...await asignables(t.proyecto_id)].sort((a, b) => a[1].localeCompare(b[1])) : [];
  const est = t.dias_estimados == null ? null : Number(t.dias_estimados);
  pinta(cabecera(t.titulo, { sobre: t.proyecto.nombre, atras: "#/" }) + `<main>
    <p style="color:var(--tinta-3)">${h(ESTADO[t.estado])} · se entrega el ${h(fecha(t.fecha_compromiso))}${est ? " · pide " + h(esfuerzo(est)) : ""}${marca(t.prioridad)}</p>
    ${t.estado === "con_observaciones" && devuelta ? `<div class="error"><strong>${h(devuelta.persona?.nombre || "Quien revisó")} la devolvió:</strong> ${h(devuelta.observaciones)}</div>` : ""}
    ${ctx?.para_que ? `<div class="grupo">Para qué sirve</div><p>${h(ctx.para_que)}</p>` : ""}
    ${t.descripcion ? `<div class="grupo">Detalle</div><p>${h(t.descripcion)}</p>` : ""}
    <div class="grupo">Quién</div><p>La tiene ${h(t.tiene?.nombre)}. La asignó ${h(t.asigno?.nombre)}. ${sinRevision ? "No requiere revisión: se cierra al entregarla." : t.revisa?.nombre ? `La revisa ${h(t.revisa.nombre)}.` : "La revisa quien tenga ese papel en el proyecto."}</p>
    ${botones}
    ${edita ? `<div class="grupo">Cambiar la tarea</div><form data-form="editar" data-id="${t.id}" data-tiene="${t.asignada_a}">
      ${reasigna ? `<label for="q">Responsable</label><select id="q" name="quien">${gente.map(([id, n]) => `<option value="${id}" ${id === t.asignada_a ? "selected" : ""}>${h(n)}</option>`).join("")}</select>` : ""}
      ${reasigna && t.estado !== "en_revision" ? (reparto = { revisores: gente }, selectRevision("e", !sinRevision, t.revisor_id || "")) : ""}
      <div class="dos">
        <div><label for="i">Empieza</label><input id="i" name="inicio" type="date" value="${h(t.fecha_inicio || "")}"></div>
        <div><label for="f">Entrega</label><input id="f" name="fecha" type="date" value="${h(t.fecha_compromiso || "")}" required></div>
        <div><label for="e">Trabajo que pide</label><select id="e" name="dias"><option value="">Sin estimar</option>${(est && !ESFUERZO.some(x => x[0] === est) ? [[est, enDias(est)], ...ESFUERZO] : ESFUERZO).map(([v, n]) => `<option value="${v}" ${v === est ? "selected" : ""}>${h(n)}</option>`).join("")}</select></div>
        <div><label for="p">Prioridad</label><select id="p" name="prioridad">${[["normal", "Normal"], ["alta", "Alta"], ["bloqueante", "Frena a otros"]].map(([v, n]) => `<option value="${v}" ${v === t.prioridad ? "selected" : ""}>${n}</option>`).join("")}</select></div>
      </div><button class="btn claro">Guardar el cambio</button></form>` : ""}
    <div class="grupo">Rastro</div><ul class="rastro">${rastro.map(r => `<li><strong>${h(r.persona?.nombre || "El sistema")}</strong> · ${
      r.tipo === "creada" ? "la asignó" : r.tipo === "estado" ? h(`${ESTADO[r.de] || r.de} → ${ESTADO[r.a] || r.a}`) : r.tipo === "fecha" ? `movió la fecha del ${h(fecha(r.de))} al ${h(fecha(r.a))}` :
      r.tipo === "prioridad" ? "cambió la prioridad" : "la reasignó"} · ${h(hora(r.ocurrio_en))}</li>`).join("")}</ul>
  </main>`);
}
acciones.estado = async el => {
  await pedir(sb.from("tarea_diseno").update({ estado: el.dataset.a }).eq("id", el.dataset.id));
  aviso = bien(el.dataset.a === "en_revision" ? "Revisión pedida. Quedó la hora de la entrega." : el.dataset.a === "terminada" ? "Entregada y cerrada." : "Listo."); navegar();
};
formularios.revisar = async (f, form, boton) => {
  const r = boton?.value || "aprobada";
  if (r === "con_observaciones" && !f.obs.trim()) throw new Error("Para devolver hay que escribir qué falta.");
  await pedir(sb.from("revision_diseno").insert({ tarea_id: form.dataset.id, revisor_id: yo.persona_id, resultado: r, observaciones: f.obs.trim() || null }));
  ir("#/revisar", bien(r === "aprobada" ? "Aprobada: la tarea quedó terminada." : "Devuelta con su observación."));
};
formularios.editar = async (f, form) => {
  if (f.inicio && f.inicio > f.fecha) throw new Error("La tarea no puede empezar después de su entrega.");
  await pedir(sb.from("tarea_diseno").update({ fecha_inicio: f.inicio || null, fecha_compromiso: f.fecha, prioridad: f.prioridad,
    dias_estimados: f.dias ? Number(f.dias) : null, ...(f.quien ? { asignada_a: f.quien } : {}),
    ...("rr:e" in f ? conRevision(f, "e", f.quien || form.dataset.tiene) : {}) }).eq("id", form.dataset.id));
  aviso = bien("Cambio guardado. Quedó en el rastro."); navegar();
};

// ---------- repartir tareas ----------
// Quien dirige arma una o varias tareas y se las entrega a su responsable. Al
// escoger a la persona ve cuánto le queda libre la semana de la entrega.
let reparto = null;   // lo que necesita el formulario abierto
async function asignables(pid) {
  const [equipo, direccion] = await Promise.all([
    pedir(sb.from("acceso_proyecto").select("papel,persona(id,nombre)").eq("proyecto_id", pid).neq("papel", "observa")),
    pedir(sb.from("persona").select("id,nombre").in("rol", ["socio", "director"]).eq("activo", true).eq("es_interno", true)),
  ]);
  return new Map([...equipo.map(e => [e.persona.id, e.persona.nombre]), ...direccion.map(p => [p.id, p.nombre])]);
}
const cargaPorPersona = filas => { const m = new Map(); for (const c of filas) (m.get(c.persona_id) || m.set(c.persona_id, []).get(c.persona_id)).push(c); return m; };
const libres = c => Number(c.dias_habiles) - Number(c.dias_ocupados);
// Una persona puede tener más de un papel en el mismo proyecto (produce y también revisa).
const PAPELES = [["produce", "Produce"], ["revisa", "Revisa"], ["dirige", "Dirige"]];
const casillasPapel = (id, nombre, extra = []) => `<span class="papeles" role="group" aria-label="Papeles de ${h(nombre)}">${[...PAPELES, ...extra].map(([v, n]) =>
  `<label><input type="checkbox" name="papel:${id}:${v}" value="1">${n}</label>`).join("")}</span>`;
const papelesDe = (f, id) => [...PAPELES, ["observa"]].map(([v]) => v).filter(v => f[`papel:${id}:${v}`]);
const nombrarPapeles = l => { const n = { dirige: "dirige", produce: "produce", revisa: "revisa", observa: "observa" }, t = lista(l.map(x => n[x] || x)); return t.charAt(0).toUpperCase() + t.slice(1); };
async function vistaNueva(proyectoId, personaId) {
  const proyectos = (await pedir(sb.from("proyecto").select("id,nombre").eq("estado", "activo").order("nombre"))).filter(p => yo.registra.includes(p.id));
  if (!proyectos.length) return pinta(cabecera("Nueva tarea", { atras: "#/" }) + '<main><p class="vacio">Todavía no hace parte del equipo de ningún proyecto. Dirección lo agrega desde la ficha del proyecto.</p></main>');
  const pid = proyectos.some(p => p.id === proyectoId) ? proyectoId : proyectos[0].id;
  const [gente, abiertas, fases, carga] = await Promise.all([
    asignables(pid),
    pedir(sb.from("tarea_diseno").select("id,titulo").eq("proyecto_id", pid).neq("estado", "terminada").order("titulo")),
    pedir(sb.from("proyecto_fase").select("id,fase,estado").eq("proyecto_id", pid).order("orden")),
    pedir(sb.rpc("carga_semanal", { p_semanas: SEMANAS })),
  ]);
  const puedeAsignar = yo.asigna || yo.dirige.includes(pid), porPersona = cargaPorPersona(carga);
  const espacio = id => porPersona.has(id) ? libres(porPersona.get(id)[0]) : null;
  // Primero quien más espacio tiene esta semana.
  const opciones = puedeAsignar ? [...gente].sort((a, b) => (espacio(b[0]) ?? -99) - (espacio(a[0]) ?? -99) || a[1].localeCompare(b[1])) : [[yo.persona_id, yo.nombre]];
  const enCurso = fases.find(x => x.estado === "en_curso");
  reparto = { n: 0, opciones, abiertas, porPersona, espacio, persona: opciones.some(o => o[0] === personaId) ? personaId : null,
    revisores: [...gente].sort((a, b) => a[1].localeCompare(b[1])) };
  pinta(cabecera(puedeAsignar ? "Repartir tareas" : "Nueva tarea", { atras: puedeAsignar ? "#/equipo" : "#/" }) + `<main><form data-form="tarea">
    <label for="pr">Proyecto</label><select id="pr" name="proyecto" data-cambia="proyectoTarea">${proyectos.map(p => `<option value="${p.id}" ${p.id === pid ? "selected" : ""}>${h(p.nombre)}</option>`).join("")}</select>
    ${fases.length ? `<label for="fa">Fase</label><select id="fa" name="fase"><option value="">Sin fase</option>${fases.map(x => `<option value="${x.id}" ${x.id === enCurso?.id ? "selected" : ""}>${h(titulo(x.fase.replace(/_/g, " ")))}</option>`).join("")}</select>` : ""}
    ${puedeAsignar ? "" : '<p class="nota">Puede crearse tareas propias. Entregarle una tarea a otra persona es de quien dirige el proyecto.</p>'}
    <div id="tareas">${bloqueTarea()}</div>
    ${puedeAsignar ? '<button type="button" class="btn claro" data-accion="otraTarea">Agregar otra tarea</button>' : ""}
    <button class="btn" id="entregar">${puedeAsignar ? "Entregar la tarea" : "Crear la tarea"}</button></form></main>`);
  reparto.puedeAsignar = puedeAsignar;
  acciones.pista(document.querySelector("fieldset.tarea select"));
}
function bloqueTarea() {
  const r = reparto, i = r.n++;
  // Primero el cuándo y el cuánto; con eso se ve quién tiene espacio en ese tramo.
  return `<fieldset class="tarea" data-i="${i}"><legend>Tarea</legend>
    <label for="ti${i}">Qué hay que entregar</label><input id="ti${i}" name="ti:${i}" required minlength="4" autocomplete="off">
    <div class="dos"><div><label for="in${i}">Empieza</label><input id="in${i}" name="in:${i}" type="date" value="${hoyIso()}" required data-cambia="pista"></div>
      <div><label for="fe${i}">Entrega</label><input id="fe${i}" name="fe:${i}" type="date" min="${hoyIso()}" required data-cambia="pista"></div>
      <div><label for="es${i}">Trabajo que pide</label><select id="es${i}" name="es:${i}" required data-cambia="pista"><option value="">Escoja</option>${ESFUERZO.map(([v, n]) => `<option value="${v}">${n}</option>`).join("")}</select></div>
      <div><label for="pi${i}">Prioridad</label><select id="pi${i}" name="pi:${i}"><option value="normal">Normal</option><option value="alta">Alta</option><option value="bloqueante">Frena a otros</option></select></div></div>
    ${selectResponsable(i)}
    ${selectRevision(i)}
    ${r.abiertas.length ? `<label for="de${i}">Depende de (opcional)</label><select id="de${i}" name="de:${i}"><option value="">De ninguna</option>${r.abiertas.map(a => `<option value="${a.id}">${h(a.titulo)}</option>`).join("")}</select>` : ""}
    <p class="pista" id="pista${i}" aria-live="polite"></p>
    ${i ? '<button type="button" class="enlace" data-accion="quitarTarea">Quitar esta tarea</button>' : ""}</fieldset>`;
}
const cuantas = () => { const n = document.querySelectorAll("fieldset.tarea").length, b = document.getElementById("entregar"); if (b && reparto.puedeAsignar) b.textContent = n > 1 ? `Entregar las ${n} tareas` : "Entregar la tarea"; };
acciones.proyectoTarea = el => ir(`#/nueva/${el.value}`);
acciones.otraTarea = () => { document.getElementById("tareas").insertAdjacentHTML("beforeend", bloqueTarea()); cuantas();
  const f = document.querySelector("fieldset.tarea:last-child"); acciones.pista(f.querySelector("select")); f.querySelector("input").focus(); };
acciones.quitarTarea = el => { el.closest("fieldset").remove(); cuantas(); };
// Lo que le queda libre a una persona entre el inicio y la entrega: suma las
// semanas que toca el tramo y, de una semana tomada a medias, la parte que cae
// dentro (por días de lunes a viernes).
function tramoLibre(sem, ini, fin) {
  const a = dia0(ini), b = dia0(fin); let hab = 0, oc = 0, visto = -Infinity;
  for (const s of sem || []) {
    const l = dia0(s.semana), d0 = Math.max(a, l), d1 = Math.min(b, l + 4); visto = Math.max(visto, l + 6);
    if (d1 < d0) continue;
    const fr = (d1 - d0 + 1) / 5; hab += Number(s.dias_habiles) * fr; oc += Number(s.dias_ocupados) * fr;
  }
  return { dias_habiles: hab, dias_ocupados: oc, libre: hab - oc, fuera: b > visto };
}
const datosTarea = f => { const i = f.dataset.i, v = n => f.querySelector(`[name="${n}:${i}"]`)?.value || "";
  return { i, ini: v("in"), fin: v("fe"), pide: Number(v("es")) || 0, quien: v("qu") }; };
const selectResponsable = i => `<label for="qu${i}">Responsable, con sus días libres en ese tramo</label>
    <select id="qu${i}" name="qu:${i}" required data-cambia="pista" disabled><option value="">Primero las fechas y el trabajo que pide</option></select>`;
// Si la entrega pasa por revisión y a quién se le delega. Sin revisión, la
// tarea se cierra cuando su responsable la entrega.
const selectRevision = (i, req = true, quien = "") => `<div class="dos"><div><label for="rr${i}">Requiere revisión</label>
      <select id="rr${i}" name="rr:${i}" data-cambia="revision"><option value="si" ${req ? "selected" : ""}>Sí</option><option value="no" ${req ? "" : "selected"}>No, se cierra al entregarla</option></select></div>
    <div><label for="rv${i}">Revisa</label><select id="rv${i}" name="rv:${i}" required ${req ? "" : "disabled"}><option value="">${req ? "Escoja" : "Nadie"}</option>${
      (reparto?.revisores || []).map(([id, n]) => `<option value="${id}" ${id === quien ? "selected" : ""}>${h(n)}</option>`).join("")}</select></div></div>`;
acciones.revision = el => { const rv = el.form.querySelector(`[name="rv:${el.name.slice(3)}"]`), no = el.value === "no";
  rv.disabled = no; rv.options[0].textContent = no ? "Nadie" : "Escoja"; if (no) rv.value = ""; };
const conRevision = (f, i, quien) => { const req = f["rr:" + i] !== "no", rv = req ? f["rv:" + i] || null : null;
  if (req && !rv) throw new Error("Falta escoger quién revisa.");
  if (rv && rv === quien) throw new Error("Quien revisa no puede ser la misma persona que entrega la tarea.");
  return { requiere_revision: req, revisor_id: rv }; };
// Rehace la lista de responsables con lo que cada uno tiene libre en ese tramo.
function responsables(f) {
  const d = datosTarea(f), sel = f.querySelector(`[name="qu:${d.i}"]`);
  if (!d.ini || !d.fin || !d.pide || d.ini > d.fin) { sel.disabled = true;
    sel.innerHTML = `<option value="">${d.ini && d.fin && d.ini > d.fin ? "La entrega va antes del inicio" : "Primero las fechas y el trabajo que pide"}</option>`; return; }
  const antes = sel.dataset.quien || reparto.persona || (reparto.opciones.length === 1 ? reparto.opciones[0][0] : "");
  const filas = reparto.opciones.map(([id, n]) => [id, n, reparto.porPersona.has(id) ? tramoLibre(reparto.porPersona.get(id), d.ini, d.fin) : null])
    .sort((a, b) => (b[2]?.libre ?? -99) - (a[2]?.libre ?? -99) || a[1].localeCompare(b[1]));
  const lee = t => !t ? "" : t.dias_habiles < 0.05 ? " · sin días hábiles en el tramo" : t.libre < -0.05 ? ` · ya pasada por ${enDias(-t.libre)}`
    : t.libre + 0.05 < d.pide ? ` · ${t.libre < 0.05 ? "sin días libres" : enDias(t.libre) + " libre" + (t.libre > 1 ? "s" : "")}, no le alcanza` : ` · ${enDias(t.libre)} libre${t.libre > 1 ? "s" : ""}`;
  sel.disabled = false;
  sel.innerHTML = (reparto.opciones.length > 1 ? '<option value="">Escoja</option>' : "") + filas.map(([id, n, t]) => `<option value="${id}" ${id === antes ? "selected" : ""}>${h(n + lee(t))}</option>`).join("");
}
acciones.pista = el => {
  const f = el.closest("fieldset"), caja = document.getElementById("pista" + f.dataset.i);
  if (el.name?.startsWith("qu:")) el.dataset.quien = el.value; else responsables(f);
  const d = datosTarea(f), sem = reparto.porPersona.get(d.quien), nombre = (reparto.opciones.find(o => o[0] === d.quien) || [])[1] || "";
  if (!d.quien || !sem || !d.ini || !d.fin || !d.pide || d.ini > d.fin) { caja.textContent = ""; return; }
  const t = tramoLibre(sem, d.ini, d.fin), queda = t.libre - d.pide, cuando = d.ini === d.fin ? `el ${fecha(d.ini)}` : `entre el ${fecha(d.ini)} y el ${fecha(d.fin)}`;
  const libreTxt = t.libre < 0.05 ? "el tramo lleno" : `${enDias(t.libre)} libre${t.libre > 1 ? "s" : ""}`;
  caja.innerHTML = barraCapacidad(t, d.pide) + (t.dias_habiles < 0.05 ? `${h(nombre)} no tiene días hábiles ${cuando}.`
    : queda < -0.05 ? `<em>${h(nombre)} tiene ${libreTxt} ${cuando} y la tarea pide ${enDias(d.pide)}: queda pasada por ${enDias(-queda)}.</em>`
    : `${h(nombre)} tiene ${libreTxt} ${cuando}, de ${enDias(t.dias_habiles)} hábiles. ${queda < 0.05 ? "Con esta tarea queda llena." : `Con esta tarea le queda${queda > 1 ? "n" : ""} ${enDias(queda)}.`}`)
    + (t.fuera ? " La entrega cae más allá de las semanas que se alcanzan a ver: el cálculo llega hasta donde hay datos." : "");
};
formularios.tarea = async f => {
  const filas = Object.keys(f).filter(k => k.startsWith("ti:")).map(k => k.slice(3)).map(i => ({ proyecto_id: f.proyecto, fase_id: f.fase || null,
    titulo: f["ti:" + i].trim(), asignada_a: f["qu:" + i], asignada_por: yo.persona_id, fecha_inicio: f["in:" + i], fecha_compromiso: f["fe:" + i],
    dias_estimados: Number(f["es:" + i]), prioridad: f["pi:" + i], bloqueada_por: f["de:" + i] || null, ...conRevision(f, i, f["qu:" + i]) }));
  const torcida = filas.find(x => x.fecha_inicio > x.fecha_compromiso);
  if (torcida) throw new Error(`«${torcida.titulo}» no puede empezar después de su entrega.`);
  await pedir(sb.from("tarea_diseno").insert(filas));
  const quienes = [...new Set(filas.map(x => (reparto.opciones.find(o => o[0] === x.asignada_a) || [])[1]).filter(Boolean))];
  const propia = filas.every(x => x.asignada_a === yo.persona_id);
  ir(reparto.puedeAsignar && !propia ? "#/equipo" : "#/", bien(propia ? (filas.length > 1 ? "Tareas creadas." : "Tarea creada.")
    : `${filas.length > 1 ? filas.length + " tareas entregadas" : "Tarea entregada"} a ${lista(quienes)}: ya ${filas.length > 1 ? "están" : "está"} en su día.`));
};

// ---------- las tareas típicas de una fase ----------
// Al abrir una fase, la base propone lo que siempre se hace en ella, con su
// propósito, su fecha y el trabajo que suele pedir. Quien dirige solo escoge a
// quién se le entrega cada una.
const espaciosDe = {};   // fase → los espacios del proyecto que se escribieron
async function vistaTipicas(faseId) {
  const f = await pedir(sb.from("proyecto_fase").select("id,fase,estado,proyecto_id,proyecto(nombre)").eq("id", faseId).maybeSingle());
  if (!f) return pinta(cabecera("Tareas de la fase", { atras: "#/proyectos" }) + '<main><p class="vacio">Esa fase no existe o no es de sus proyectos.</p></main>');
  const atras = `#/proyecto/${f.proyecto_id}`, espacios = (espaciosDe[faseId] || "").split(",").map(x => x.trim()).filter(Boolean);
  const [prop, gente, carga, ya] = await Promise.all([
    pedir(sb.rpc("tareas_tipicas", { p_fase: faseId, p_espacios: espacios })),
    asignables(f.proyecto_id),
    pedir(sb.rpc("carga_semanal", { p_semanas: SEMANAS })),
    pedir(sb.from("tarea_diseno").select("plantilla_tarea_id,espacio").eq("fase_id", faseId)),
  ]);
  const cab = cabecera(`Tareas de ${nFase(f.fase).toLowerCase()}`, { sobre: f.proyecto?.nombre, atras });
  if (!prop.length) return pinta(cab + `<main><p class="vacio">Esta fase todavía no tiene tareas típicas. Dirección las define una vez en el centro de mando, en el flujo de este tipo de proyecto.</p>
    <a class="btn claro" href="#/nueva/${f.proyecto_id}">Repartir tareas a mano</a></main>`);
  const repartida = x => ya.some(y => y.plantilla_tarea_id === x.plantilla_tarea_id && (y.espacio || null) === (x.espacio || null));
  const nuevas = prop.filter(x => !repartida(x)), porEspacio = prop.some(x => x.por_espacio);
  const porPersona = cargaPorPersona(carga), espacio = id => porPersona.has(id) ? libres(porPersona.get(id)[0]) : null;
  const opciones = [...gente].sort((a, b) => (espacio(b[0]) ?? -99) - (espacio(a[0]) ?? -99) || a[1].localeCompare(b[1]));
  reparto = { n: 0, opciones, abiertas: [], porPersona, espacio, persona: null, puedeAsignar: true, revisores: [...gente].sort((a, b) => a[1].localeCompare(b[1])) };
  pinta(cab + `<main>
    ${porEspacio ? `<form data-form="espacios" data-fase="${faseId}"><label for="esp">Espacios del proyecto, separados por coma</label>
      <input id="esp" name="espacios" value="${h(espaciosDe[faseId] || "")}" placeholder="Cocina, Baño principal, Sala" autocomplete="off">
      <button class="btn claro">${espacios.length ? "Volver a proponer con estos espacios" : "Proponer una tarea por cada espacio"}</button></form>` : ""}
    ${prop.length > nuevas.length ? `<p class="nota">${prop.length - nuevas.length === 1 ? "Una de las tareas típicas ya está repartida" : `${prop.length - nuevas.length} de las tareas típicas ya están repartidas`}: no se vuelve${prop.length - nuevas.length === 1 ? "" : "n"} a proponer.</p>` : ""}
    ${nuevas.length ? `<form data-form="tipicas" data-fase="${faseId}" data-proyecto="${f.proyecto_id}"><div id="tareas">${nuevas.map(x => { const i = reparto.n++, est = x.dias_estimados == null ? null : Number(x.dias_estimados);
      return `<fieldset class="tarea" data-i="${i}"><legend>${h(x.titulo)}</legend>
        <p style="margin:14px 0 0;color:var(--tinta-3);font-size:.9rem">${h(x.proposito)}</p>
        <input type="hidden" name="pt:${i}" value="${h(x.plantilla_tarea_id)}"><input type="hidden" name="ep:${i}" value="${h(x.espacio || "")}">
        <div class="dos"><div><label for="in${i}">Empieza</label><input id="in${i}" name="in:${i}" type="date" value="${hoyIso()}" required data-cambia="pista"></div>
          <div><label for="fe${i}">Entrega</label><input id="fe${i}" name="fe:${i}" type="date" min="${hoyIso()}" value="${h(x.fecha_sugerida || "")}" required data-cambia="pista"></div></div>
        <label for="es${i}">Trabajo que pide</label><select id="es${i}" name="es:${i}" required data-cambia="pista"><option value="">Escoja</option>${(est && !ESFUERZO.some(e => e[0] === est) ? [[est, enDias(est)], ...ESFUERZO] : ESFUERZO).map(([v, n]) => `<option value="${v}" ${v === est ? "selected" : ""}>${h(n)}</option>`).join("")}</select>
        ${selectResponsable(i)}
        ${selectRevision(i)}
        <p class="pista" id="pista${i}" aria-live="polite"></p>
        ${nuevas.length > 1 ? '<button type="button" class="enlace" data-accion="quitarTarea">No entregar esta ahora</button>' : ""}</fieldset>`; }).join("")}</div>
      <button class="btn" id="entregar">${nuevas.length > 1 ? `Entregar las ${nuevas.length} tareas` : "Entregar la tarea"}</button></form>`
      : '<p class="vacio">Todas las tareas típicas de esta fase ya están repartidas.</p>'}
    <a class="btn claro" href="${atras}">${nuevas.length ? "Ahora no" : "Volver al proyecto"}</a></main>`);
  document.querySelectorAll("fieldset.tarea").forEach(x => acciones.pista(x.querySelector("select")));
}
formularios.espacios = async (f, form) => { espaciosDe[form.dataset.fase] = f.espacios; navegar(); };
formularios.tipicas = async (f, form) => {
  const filas = Object.keys(f).filter(k => k.startsWith("pt:")).map(k => k.slice(3)).map(i => ({ plantilla_tarea_id: f["pt:" + i], espacio: f["ep:" + i] || null,
    asignada_a: f["qu:" + i], fecha_inicio: f["in:" + i], fecha_compromiso: f["fe:" + i], dias_estimados: Number(f["es:" + i]), ...conRevision(f, i, f["qu:" + i]) }));
  if (!filas.length) throw new Error("No quedó ninguna tarea para entregar.");
  if (filas.some(x => x.fecha_inicio > x.fecha_compromiso)) throw new Error("Hay una tarea que empieza después de su entrega.");
  const n = await pedir(sb.rpc("crear_tareas", { p_fase: form.dataset.fase, p_tareas: filas }));
  const quienes = [...new Set(filas.map(x => (reparto.opciones.find(o => o[0] === x.asignada_a) || [])[1]).filter(Boolean))];
  ir(`#/proyecto/${form.dataset.proyecto}`, bien(`${n === 1 ? "Tarea entregada" : n + " tareas entregadas"} a ${lista(quienes)}: ya ${n === 1 ? "está" : "están"} en su día.`));
};

// ---------- registrar el día ----------
// Dos toques por día: en qué estuvo la mañana y en qué la tarde. Nada de horas
// ni de frases. Lo que pasó hace más de una semana lo corrige dirección.
const SEMANA = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"];
async function vistaRegistro() {
  const hoy = hoyIso(), desde = new Date((dia0(hoy) - 14) * 864e5).toISOString().slice(0, 10);
  const [pendientes, hechos, fases] = await Promise.all([
    pedir(sb.from("v_dedicacion_pendiente").select("fecha").eq("persona_id", yo.persona_id).order("fecha", { ascending: false })),
    pedir(sb.from("dedicacion").select("fecha,bloque,tipo,proyecto_id,fase_id").eq("persona_id", yo.persona_id).gte("fecha", desde)),
    pedir(sb.from("proyecto_fase").select("id,fase,estado,proyecto_id,proyecto(nombre)").in("estado", ["en_curso", "en_revision"])),
  ]);
  const abiertas = fases.filter(f => yo.registra.includes(f.proyecto_id)).sort((a, b) => (a.proyecto?.nombre || "").localeCompare(b.proyecto?.nombre || ""));
  const valor = d => !d ? "" : d.tipo === "proyecto" ? `f:${d.fase_id}:${d.proyecto_id}` : d.tipo;
  const selector = (dia, bloque) => { const d = hechos.find(x => x.fecha === dia && x.bloque === bloque), v = valor(d);
    return `<select name="${dia}|${bloque}" aria-label="${bloque === "manana" ? "Mañana" : "Tarde"} del ${h(fecha(dia))}" ${bloque === "manana" ? 'data-cambia="copiaTarde"' : ""}><option value="">Sin registrar</option>
      ${abiertas.map(f => `<option value="f:${f.id}:${f.proyecto_id}" ${v === `f:${f.id}:${f.proyecto_id}` ? "selected" : ""}>${h(f.proyecto?.nombre)} · ${h(nFase(f.fase).toLowerCase())}</option>`).join("")}
      ${d?.tipo === "proyecto" && !abiertas.some(f => f.id === d.fase_id) ? `<option value="${v}" selected>Una fase que ya cerró</option>` : ""}
      <option value="estructura" ${v === "estructura" ? "selected" : ""}>Trabajo interno de ESA</option><option value="ausencia" ${v === "ausencia" ? "selected" : ""}>No trabajé</option></select>`; };
  const dias = [hoy, ...pendientes.map(x => x.fecha).filter(x => x !== hoy)];
  const editable = d => yo.es_direccion || dia0(hoy) - dia0(d) <= 7;
  pinta(cabecera("Registrar mi día", { atras: "#/" }) + `<main><form data-form="registro">
    ${dias.map(d => `<div class="grupo ${d !== hoy ? "c" : ""}">${d === hoy ? "Hoy" : titulo(SEMANA[new Date(dia0(d) * 864e5).getUTCDay()])}, ${h(fecha(d))}</div>
      ${editable(d) ? `<div class="dos"><div><label>Mañana</label>${selector(d, "manana")}</div><div><label>Tarde</label>${selector(d, "tarde")}</div></div>`
        : '<p class="nota">Pasó más de una semana: este día lo corrige dirección.</p>'}`).join("")}
    <button class="btn">Guardar</button></form>
    <p class="nota">Si estuvo todo el día en lo mismo, escoja la mañana: la tarde se llena sola. ${abiertas.length ? "" : "Todavía no hay fases abiertas en sus proyectos: puede registrar trabajo interno."}</p></main>`);
}
acciones.copiaTarde = el => { const t = el.closest(".dos").querySelector('select[name$="|tarde"]'); if (t && !t.value) t.value = el.value; };
formularios.registro = async f => {
  const filas = Object.entries(f).filter(([, v]) => v).map(([k, v]) => { const [dia, bloque] = k.split("|"), [, fase, proyecto] = v.startsWith("f:") ? v.split(":") : [];
    return { persona_id: yo.persona_id, fecha: dia, bloque, tipo: fase ? "proyecto" : v, proyecto_id: proyecto || null, fase_id: fase || null }; });
  if (!filas.length) throw new Error("Escoja al menos en qué estuvo una mañana o una tarde.");
  await pedir(sb.from("dedicacion").upsert(filas, { onConflict: "persona_id,fecha,bloque" }));
  ir("#/", bien(`Quedó registrado${new Set(filas.map(x => x.fecha)).size > 1 ? `: ${new Set(filas.map(x => x.fecha)).size} días` : ""}.`));
};

// ---------- cerrar una fase ----------
// La lista de chequeo se llena aquí, punto por punto. Algunos puntos se marcan
// y otros piden un dato. Lo que falta para cerrar lo cuenta la base; el botón
// de cerrar solo lo ve dirección, y si algo falta la base lo dice.
const PUNTO = { casilla: "Se marca", opcion: "Se escoge una opción", numero: "Un número", fecha: "Una fecha", enlace: "Un enlace" };
let cierre = null;   // la hoja abierta: { fase, chequeo }
const pintaFalta = falta => `<div class="grupo">Lo que hace falta</div>${falta.map(x => `<div class="fila"><b>${h({ chequeo: "Lista de chequeo", cliente: "Aprobación del cliente", dedicacion: "Dedicación del equipo", tareas: "Tareas" }[x.que] || x.que)}
    <span class="marca ${x.listo ? "o" : x.bloquea ? "c" : "a"}">${x.listo ? "Listo" : x.bloquea ? "Falta" : "Aviso"}</span></b><span>${h(x.detalle)}</span></div>`).join("")}`;
// El botón va al final: primero se llena, después se cierra.
const pintaCerrar = (falta, f) => { const bloquea = falta.filter(x => x.bloquea && !x.listo), abiertas = falta.find(x => x.que === "tareas" && !x.listo);
  return f.estado === "cerrada" ? '<p class="bien">Esta fase ya está cerrada.</p>' : f.estado === "pendiente" ? "" : yo.es_direccion
    ? `<div class="grupo">Cerrar la fase</div>${bloquea.length ? `<p class="nota">Todavía no: ${h(lista(bloquea.map(x => ({ chequeo: "falta completar la lista de chequeo", cliente: "falta la aprobación del cliente", dedicacion: "falta poner al día la dedicación" }[x.que]))))}.</p>`
        : abiertas ? `<p class="nota">${h(abiertas.detalle)}: si cierra la fase, siguen abiertas.</p>` : ""}
       <button class="btn" data-accion="cerrarFase" data-id="${f.id}" data-proyecto="${f.proyecto_id}" ${bloquea.length ? "disabled" : ""}>Cerrar ${h(nFase(f.fase).toLowerCase())}</button>`
    : '<p class="nota">La fase la cierra dirección. Usted puede dejar completa la lista de chequeo.</p>'; };
async function vistaCierre(faseId) {
  const f = await pedir(sb.from("proyecto_fase").select("id,fase,estado,proyecto_id,exige_aprobacion_cliente,aprobada_cliente_en,aprobada_cliente_texto,entrega_cliente,proyecto(nombre)").eq("id", faseId).maybeSingle());
  if (!f) return pinta(cabecera("Cierre de fase", { atras: "#/proyectos" }) + '<main><p class="vacio">Esa fase no existe o no es de sus proyectos.</p></main>');
  const hoja = yo.registra.includes(f.proyecto_id) && f.estado !== "pendiente" ? await pedir(sb.rpc("abrir_chequeo", { p_fase: faseId })) : null;
  const [falta, puntos, respuestas] = await Promise.all([
    pedir(sb.rpc("falta_para_cerrar", { p_fase: faseId })),
    hoja ? pedir(sb.from("chequeo").select("lista_id,lista:lista_chequeo(lista_chequeo_item(id,orden,texto,tipo,opciones,obligatorio,activo,requiere_evidencia))").eq("id", hoja).maybeSingle()) : null,
    hoja ? pedir(sb.from("chequeo_respuesta").select("item_id,cumple,valor").eq("chequeo_id", hoja)) : [],
  ]);
  cierre = { fase: f, chequeo: hoja };
  const items = (puntos?.lista?.lista_chequeo_item || []).filter(i => i.activo !== false).sort((a, b) => a.orden - b.orden), R = new Map(respuestas.map(r => [r.item_id, r]));
  const abierta = f.estado !== "cerrada";
  const campo = i => { const r = R.get(i.id), v = r?.cumple ? r.valor ?? "" : "", comun = `data-cambia="dato" data-item="${i.id}" ${abierta ? "" : "disabled"} aria-label="${h(i.texto)}"`;
    return i.requiere_evidencia ? '<p class="nota" style="margin:8px 0 0">Este punto pide una foto o un archivo, y eso todavía no se adjunta desde aquí.</p>'
      : i.tipo === "opcion" ? `<select ${comun}><option value="">Escoja</option>${(i.opciones || []).map(o => `<option ${o === v ? "selected" : ""}>${h(o)}</option>`).join("")}</select>`
      : i.tipo === "numero" ? `<input ${comun} inputmode="decimal" value="${h(v)}" placeholder="Un número">`
      : i.tipo === "fecha" ? `<input ${comun} type="date" value="${h(v)}">`
      : i.tipo === "enlace" ? `<input ${comun} type="url" inputmode="url" value="${h(v)}" placeholder="https://…">`
      : `<button type="button" class="btn ${r?.cumple ? "" : "claro"} casilla" data-accion="marcar" data-item="${i.id}" aria-pressed="${!!r?.cumple}" ${abierta ? "" : "disabled"}>${r?.cumple ? "Cumplido" : "Marcar como cumplido"}</button>`; };
  pinta(cabecera(`${abierta ? "Cerrar" : "Cierre de"} ${nFase(f.fase).toLowerCase()}`, { sobre: f.proyecto?.nombre, atras: `#/proyecto/${f.proyecto_id}` }) + `<main>
    ${f.estado === "pendiente" ? '<p class="nota">Esta fase todavía no se ha abierto.</p>' : ""}
    <div id="falta">${pintaFalta(falta)}</div>
    ${items.length ? `<div class="grupo">Lista de chequeo</div>${items.map(i => `<div class="fila punto" id="punto-${i.id}"><b>${h(i.texto)}${i.obligatorio ? "" : '<span class="marca n">Opcional</span>'}</b>
        ${campo(i)}<span class="m-ok" aria-live="polite"></span></div>`).join("")}` : ""}
    ${f.exige_aprobacion_cliente && abierta ? `<div class="grupo">Aprobación del cliente</div>${yo.es_direccion ? `<form data-form="aprobacion" data-id="${f.id}">
        <label for="ac">Fecha en que aprobó</label><input id="ac" name="fecha" type="date" max="${hoyIso()}" value="${h(f.aprobada_cliente_en || "")}" required>
        <label for="at">Quién aprobó y por qué medio</label><input id="at" name="texto" value="${h(f.aprobada_cliente_texto || "")}" required minlength="6" placeholder="Nombre, y si fue por correo, WhatsApp o en reunión" autocomplete="off">
        <button class="btn claro">Guardar la aprobación</button></form>`
      : `<p>${f.aprobada_cliente_en ? `Aprobó el ${h(fecha(f.aprobada_cliente_en))}: ${h(f.aprobada_cliente_texto)}.` : "La registra dirección cuando el cliente aprueba."}</p>`}` : ""}
    <div id="cerrar">${pintaCerrar(falta, f)}</div>
  </main>`);
}
async function guardaPunto(el, cumple, valor) {
  const marca = el.closest(".punto").querySelector(".m-ok");
  try {
    await pedir(sb.from("chequeo_respuesta").upsert({ chequeo_id: cierre.chequeo, item_id: el.dataset.item, cumple, valor, verificado_por: yo.persona_id }, { onConflict: "chequeo_id,item_id" }));
    marca.className = "m-ok"; marca.textContent = cumple ? "Guardado" : "Quedó pendiente";
    const falta = await pedir(sb.rpc("falta_para_cerrar", { p_fase: cierre.fase.id }));
    document.getElementById("falta").innerHTML = pintaFalta(falta); document.getElementById("cerrar").innerHTML = pintaCerrar(falta, cierre.fase);
    return true;
  } catch (e) { marca.className = "m-ok mal"; marca.textContent = decir(e); return false; }
}
acciones.dato = el => guardaPunto(el, el.value.trim() !== "", el.value.trim() || null);
acciones.marcar = async el => { const ahora = el.getAttribute("aria-pressed") !== "true";
  if (await guardaPunto(el, ahora, null)) { el.setAttribute("aria-pressed", ahora); el.classList.toggle("claro", !ahora); el.textContent = ahora ? "Cumplido" : "Marcar como cumplido"; } };
formularios.aprobacion = async (f, form) => {
  const r = await pedir(sb.from("proyecto_fase").update({ aprobada_cliente_en: f.fecha, aprobada_cliente_texto: f.texto.trim() }).eq("id", form.dataset.id).select("id"));
  if (!r.length) throw new Error("La aprobación del cliente la registra dirección.");
  aviso = bien("Aprobación del cliente guardada."); navegar();
};
acciones.cerrarFase = async el => {
  const r = await pedir(sb.from("proyecto_fase").update({ estado: "cerrada" }).eq("id", el.dataset.id).select("id"));
  if (!r.length) throw new Error("La fase la cierra dirección.");
  ir(`#/proyecto/${el.dataset.proyecto}`, bien("Fase cerrada. Quedó registrado quién la cerró y cuándo."));
};

// ---------- ventas ----------
// El embudo se trabaja en frases y escogiendo. Las reglas las pone la base:
// sin siguiente paso no hay oportunidad abierta (V1), sin reunión de
// presentación no sale una cotización (V2) y sin el reporte de la cita no se
// cotiza (V3). Esta pantalla solo muestra lo que toca hoy y deja hacerlo.
const ETAPA = { cita_viabilidad: "Cita de viabilidad", presupuesto_detallado: "Cotización en preparación", cotizacion_enviada: "Cotización presentada",
  negociacion: "Contrato y anticipo", ganada: "Ganada", perdida: "Perdida" };
const ABIERTAS = ["cita_viabilidad", "presupuesto_detallado", "cotizacion_enviada", "negociacion"];
const LINEA = { diseno: "Diseño e interiorismo", obra: "Obra", peritaje: "Peritajes" };
const lineaDe = u => ["obra_propia", "obra_colega"].includes(u) ? "obra" : u === "peritaje" ? "peritaje" : "diseno";
const CANAL = { google_ads: "Google Ads", meta_ads: "Meta (Instagram y Facebook)", instagram_organico: "Instagram, sin pauta", referido: "Lo refirió alguien",
  cliente_recurrente: "Ya era cliente", web_organico: "La página web", asistente_ia: "Le preguntó a una IA", whatsapp_directo: "Escribió directo al WhatsApp",
  youtube: "YouTube", linkedin: "LinkedIn", otro: "Otro" };
// Cómo dice el cliente que nos encontró, para leerlo en una frase.
const ENCONTRO = { google_ads: "en Google", meta_ads: "en Instagram o Facebook", instagram_organico: "en Instagram", referido: "por una recomendación",
  cliente_recurrente: "porque ya era cliente", web_organico: "en la página web", asistente_ia: "preguntándole a una IA", whatsapp_directo: "por WhatsApp",
  youtube: "en YouTube", linkedin: "en LinkedIn", otro: "por otro medio" };
const MOTIVO = { precio: "El precio", tiempo: "El tiempo", competencia: "Se fue con otro", desaparecio: "Dejó de responder", sin_capacidad_pago: "No tiene cómo pagarlo",
  no_calificado: "No era para nosotros", aplazado: "Lo aplazó", otro: "Otro motivo" };
const RECURSO = { inmediato: "Ya lo tiene", "0_3_meses": "En menos de tres meses", "3_12_meses": "Entre tres meses y un año", mas_12_meses: "En más de un año", no_sabe: "No sabe todavía" };
const PROPOSITO = { vivienda: "Para vivir", inversion: "Para invertir o arrendar", mixto: "Las dos cosas", comercial: "Un negocio" };
const LOTE = { si: "Sí", en_proceso: "Lo está comprando", no: "No" };
const TIPO_CITA = { viabilidad: "Cita de viabilidad", presentacion: "Presentación de la cotización", seguimiento: "Reunión" };
const ESTADO_CITA = { agendada: "Agendada", realizada: "Hecha", no_show: "No llegó", reprogramada: "Movida", cancelada: "Cancelada" };
const ESTADO_COT = { borrador: "Borrador", emitida: "Enviada", aceptada: "Aceptada", rechazada: "Rechazada", vencida: "Vencida", reemplazada: "Reemplazada" };
const frase = s => s ? s[0].toUpperCase() + s.slice(1) : s;
const pesos = n => n == null ? "sin valor" : (Number(n) < 0 ? "−$" : "$") + Math.abs(Math.round(Number(n))).toLocaleString("es-CO");
const opciones = (o, sel = "", vacia = "") => (vacia ? `<option value="">${h(vacia)}</option>` : "") + Object.entries(o).map(([k, v]) => `<option value="${k}" ${k === sel ? "selected" : ""}>${h(v)}</option>`).join("");
const momento = iso => `${fecha(iso)}, ${new Date(iso).toLocaleTimeString("es-CO", { hour: "numeric", minute: "2-digit" })}`;
const ahoraLocal = () => new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16);
const whatsapp = t => { const d = String(t || "").replace(/\D/g, ""); return d ? `https://wa.me/${d.length === 10 ? "57" + d : d}` : ""; };
async function gente() { return pedir(sb.from("persona").select("id,nombre").eq("es_interno", true).eq("activo", true).order("nombre")); }

async function vistaVentas() {
  const [hoy, embudo, ritmo] = await Promise.all([
    pedir(sb.from("v_ventas_hoy").select("*").order("orden")),
    pedir(sb.from("v_embudo_ventas").select("*")),
    pedir(sb.from("v_ritmo_ventas").select("lectura").maybeSingle()),
  ]);
  const mios = hoy.filter(x => !x.persona_id || x.persona_id === yo.persona_id);
  const otros = yo.es_direccion ? hoy.filter(x => x.persona_id && x.persona_id !== yo.persona_id) : [];
  const nombres = otros.length ? new Map((await pedir(sb.from("persona").select("id,nombre").in("id", [...new Set(otros.map(x => x.persona_id))]))).map(p => [p.id, p.nombre])) : new Map();
  const destino = x => x.que === "reporte_cita" ? `#/reporte/${x.cita_id}` : x.oportunidad_id ? `#/oportunidad/${x.oportunidad_id}` : `#/contacto/${x.lead_id}`;
  const fila = (x, quien) => `<a class="fila" href="${destino(x)}"><b>${h(x.nombre)}${!x.persona_id ? '<span class="marca a">Sin dueño</span>' : ""}</b>
    <span>${quien ? h(quien) + " · " : ""}${x.urgente ? "<em>" : ""}${h(x.lectura)}${x.urgente ? "</em>" : ""}</span></a>`;
  const etapas = l => ABIERTAS.map(e => embudo.find(x => x.linea === l && x.etapa === e)).filter(Boolean);
  const bloque = l => { const es = etapas(l); if (!es.length) return "";
    return `<div class="grupo">${h(LINEA[l])}</div>${es.map(x => `<a class="fila" href="#/embudo/${l}/${x.etapa}"><b>${h(ETAPA[x.etapa])}<span class="marca n">${x.oportunidades}</span></b>
      <span>${Number(x.valor) ? pesos(x.valor) : "Sin valor todavía"}${x.atrasadas ? ` · <em>${uno(x.atrasadas, "una atrasada", "atrasadas")}</em>` : ""}${x.dias_promedio != null ? ` · llevan ${x.dias_promedio === 1 ? "un día" : x.dias_promedio + " días"} en promedio` : ""}</span></a>`).join("")}`; };
  pinta(cabecera("Ventas", { sobre: fecha(hoyIso()) }) + `<main>
    ${ritmo?.lectura ? `<p class="frase">${h(ritmo.lectura)}</p>` : ""}
    <div class="grupo ${mios.some(x => x.urgente) ? "c" : ""}">Para hoy</div>
    ${mios.map(x => fila(x)).join("") || '<p class="vacio">Nada para hoy. Lo que toque mañana aparece aquí.</p>'}
    ${otros.length ? `<div class="grupo">Lo del resto del equipo</div>${otros.map(x => fila(x, nombres.get(x.persona_id))).join("")}` : ""}
    <div class="grupo" style="margin-top:34px">El embudo</div>
    ${["diseno", "obra", "peritaje"].map(bloque).join("") || '<p class="vacio">Todavía no hay oportunidades abiertas.</p>'}
    ${yo.es_direccion ? '<a class="btn claro" href="#/tarifas">Tarifas de diseño</a>' : ""}
  </main><button class="mas" data-ir="#/contacto-nuevo" aria-label="Nuevo contacto">+</button>` + pie("#/ventas"));
}

async function vistaEmbudo(linea, etapa) {
  const ops = (await pedir(sb.from("oportunidad").select("id,nombre,unidad,etapa,valor_estimado,siguiente_paso,siguiente_paso_en").eq("etapa", etapa).order("siguiente_paso_en")))
    .filter(o => lineaDe(o.unidad) === linea);
  pinta(cabecera(ETAPA[etapa] || etapa, { sobre: LINEA[linea], atras: "#/ventas" }) + `<main>${ops.map(o => `<a class="fila" href="#/oportunidad/${o.id}"><b>${h(o.nombre)}</b>
      <span>${pesos(o.valor_estimado)} · ${o.siguiente_paso_en < hoyIso() ? "<em>" : ""}${h(o.siguiente_paso)} · ${h(fecha(o.siguiente_paso_en))}${o.siguiente_paso_en < hoyIso() ? "</em>" : ""}</span></a>`).join("")
    || '<p class="vacio">Ninguna en esta etapa.</p>'}</main>` + pie("#/ventas"));
}

async function vistaOportunidad(id) {
  const o = await pedir(sb.from("oportunidad").select("id,nombre,etapa,unidad,canal,valor_estimado,area_m2,ciudad,siguiente_paso,siguiente_paso_en,siguiente_paso_por,responsable_id,lead_id,origen_oportunidad_id,motivo_perdida,detalle_perdida").eq("id", id).maybeSingle());
  if (!o) return pinta(cabecera("Oportunidad", { atras: "#/ventas" }) + '<main><p class="vacio">Esa oportunidad no existe o no la puede ver.</p></main>');
  const [citas, cots, ficha, lead, equipo] = await Promise.all([
    pedir(sb.from("cita").select("id,tipo,estado,programada_para,transcripcion_url").eq("oportunidad_id", id).order("programada_para")),
    pedir(sb.from("cotizacion").select("id,numero,valor,estado,emitida_en,vence_en").eq("oportunidad_id", id).order("creada_en")),
    pedir(sb.from("calificacion").select("decisor_presente,tiene_lote,recurso_disponible,proposito,primera_cotizacion,area_inicial_m2").eq("oportunidad_id", id).maybeSingle()),
    o.lead_id ? pedir(sb.from("lead").select("nombre,telefono,correo,canal,como_nos_encontro,mensaje_inicial").eq("id", o.lead_id).maybeSingle()) : null,
    gente(),
  ]);
  const abierta = ABIERTAS.includes(o.etapa), quien = new Map(equipo.map(p => [p.id, p.nombre]));
  const presentacion = citas.some(c => c.tipo === "presentacion" && ["agendada", "realizada"].includes(c.estado));
  const pendiente = c => ["agendada", "reprogramada"].includes(c.estado) && new Date(c.programada_para) < new Date(Date.now() + 864e5);
  pinta(cabecera(o.nombre, { sobre: `${ETAPA[o.etapa]} · ${LINEA[lineaDe(o.unidad)]}`, atras: "#/ventas" }) + `<main>
    ${lead ? `<div class="fila"><b>${h(lead.nombre || "Sin nombre")}</b><span>${lead.telefono ? `<a href="tel:${h(lead.telefono)}">${h(lead.telefono)}</a> · <a href="${whatsapp(lead.telefono)}" target="_blank" rel="noopener">WhatsApp</a> · ` : ""}${lead.correo ? h(lead.correo) + " · " : ""}Llegó por ${h(CANAL[lead.canal] || lead.canal)}${lead.como_nos_encontro && lead.como_nos_encontro !== lead.canal ? `; dice que nos encontró ${h(ENCONTRO[lead.como_nos_encontro] || "")}` : ""}</span>
      ${lead.mensaje_inicial ? `<span>«${h(lead.mensaje_inicial)}»</span>` : ""}</div>` : `<p class="nota">${o.origen_oportunidad_id ? `Nació del diseño que ESA ganó: <a href="#/oportunidad/${o.origen_oportunidad_id}">ver esa venta</a>.` : `Llegó por ${h(CANAL[o.canal] || o.canal)}.`}</p>`}
    <div class="fila"><b>${pesos(o.valor_estimado)}</b><span>${o.area_m2 ? `${num(o.area_m2)} m² · ` : ""}${o.ciudad ? h(o.ciudad) + " · " : ""}responde ${h(quien.get(o.responsable_id) || "sin responsable")}</span></div>

    ${abierta ? `<div class="grupo ${o.siguiente_paso_en < hoyIso() ? "c" : ""}">Siguiente paso</div>
    <form data-form="paso" data-id="${o.id}">
      <label for="sp">Qué sigue</label><input id="sp" name="paso" value="${h(o.siguiente_paso)}" required minlength="4" autocomplete="off">
      <div class="dos"><div><label for="spe">Cuándo</label><input id="spe" name="en" type="date" min="${hoyIso()}" value="${h(o.siguiente_paso_en)}" required></div>
      <div><label for="spq">Quién</label><select id="spq" name="por">${equipo.map(p => `<option value="${p.id}" ${p.id === o.siguiente_paso_por ? "selected" : ""}>${h(p.nombre)}</option>`).join("")}</select></div></div>
      <button class="btn claro">Guardar el siguiente paso</button></form>` : o.etapa === "perdida"
      ? `<p class="nota">Se perdió: ${h((MOTIVO[o.motivo_perdida] || "").toLowerCase())}${o.detalle_perdida ? `. ${h(o.detalle_perdida)}` : ""}.</p>` : '<p class="bien">Venta ganada.</p>'}

    <div class="grupo">Reuniones</div>
    ${citas.map(c => `<${pendiente(c) ? `a href="#/reporte/${c.id}"` : "div"} class="fila"><b>${h(TIPO_CITA[c.tipo])}<span class="marca ${c.estado === "realizada" ? "o" : c.estado === "no_show" ? "c" : "n"}">${h(ESTADO_CITA[c.estado])}</span></b>
      <span>${h(momento(c.programada_para))}${pendiente(c) ? " · <em>Hacer el reporte</em>" : ""}${c.transcripcion_url ? ` · <a href="${h(c.transcripcion_url)}" target="_blank" rel="noopener">transcripción</a>` : ""}</span></${pendiente(c) ? "a" : "div"}>`).join("") || '<p class="vacio" style="padding:14px 0">Ninguna todavía.</p>'}
    ${abierta ? `<details><summary class="enlace">Agendar una reunión</summary><form data-form="cita" data-id="${o.id}">
      <label for="ct">Qué reunión</label><select id="ct" name="tipo">${opciones(TIPO_CITA, presentacion || o.etapa === "cita_viabilidad" ? "seguimiento" : "presentacion")}</select>
      <label for="cc">Cuándo</label><input id="cc" name="cuando" type="datetime-local" min="${ahoraLocal()}" required>
      <label for="cm">Cómo</label><select id="cm" name="modalidad"><option value="videollamada">Videollamada</option><option value="presencial">En persona</option><option value="llamada">Llamada</option></select>
      <button class="btn claro">Agendar</button></form></details>` : ""}

    ${ficha ? `<div class="grupo">Lo que dejó la cita</div><div class="fila"><span>${h(frase(lista([
      ficha.decisor_presente == null ? "" : ficha.decisor_presente ? "estaba quien decide" : "no estaba quien decide",
      { si: "tiene lote", en_proceso: "está comprando el lote", no: "no tiene lote" }[ficha.tiene_lote] || "",
      { inmediato: "ya tiene el recurso", "0_3_meses": "tiene el recurso en menos de tres meses", "3_12_meses": "tiene el recurso en tres meses a un año",
        mas_12_meses: "tiene el recurso en más de un año", no_sabe: "no sabe cuándo tendrá el recurso" }[ficha.recurso_disponible] || "",
      { vivienda: "es para vivir", inversion: "es para invertir o arrendar", mixto: "es para vivir e invertir", comercial: "es para un negocio" }[ficha.proposito] || "",
      ficha.primera_cotizacion == null ? "" : ficha.primera_cotizacion ? "somos la primera cotización que pide" : "ya tiene otras cotizaciones"].filter(Boolean))))}.</span></div>` : ""}

    <div class="grupo">Cotizaciones</div>
    ${cots.map(z => `<div class="fila"><b>${h(z.numero)} · ${pesos(z.valor)}<span class="marca ${z.estado === "aceptada" ? "o" : z.estado === "vencida" || z.estado === "rechazada" ? "c" : "n"}">${h(ESTADO_COT[z.estado])}</span></b>
      <span>${z.emitida_en ? `Enviada el ${h(fecha(z.emitida_en))}${z.vence_en ? `, vence el ${h(fecha(z.vence_en))}` : ""}` : "Sin enviar"}</span>
      ${z.estado === "emitida" && abierta ? `<div class="par"><button class="btn claro" data-accion="cotizacion" data-id="${z.id}" data-estado="aceptada">La aceptó</button><button class="btn claro" data-accion="cotizacion" data-id="${z.id}" data-estado="rechazada">La rechazó</button></div>` : ""}</div>`).join("") || '<p class="vacio" style="padding:14px 0">Ninguna todavía.</p>'}
    ${abierta ? `<details><summary class="enlace">Enviar una cotización</summary>${presentacion ? "" : '<p class="nota">Primero se agenda la reunión de presentación: es donde se vende. Sin ella la base no deja enviarla.</p>'}
      <form data-form="cotizacion" data-id="${o.id}">
      <div class="dos"><div><label for="zn">Número</label><input id="zn" name="numero" required placeholder="45_26" autocomplete="off"></div>
      <div><label for="zt">De qué</label><select id="zt" name="tipo"><option value="diseno">Diseño</option><option value="obra">Obra</option><option value="consultoria">Consultoría</option><option value="peritaje">Peritaje</option></select></div></div>
      <div class="dos"><div><label for="zv">Valor sin IVA</label><input id="zv" name="valor" inputmode="numeric" required value="${o.valor_estimado ? Math.round(o.valor_estimado) : ""}"></div>
      <div><label for="zc">Lo que nos cuesta</label><input id="zc" name="costo" inputmode="numeric" placeholder="Para diseño y consultoría"></div></div>
      <button class="btn">Enviar cotización</button></form></details>` : ""}

    ${abierta ? `<div class="grupo">Desenlace</div>
      <button class="btn" data-accion="ganada" data-id="${o.id}">Ganada: firmó y pagó el anticipo</button>
      <details><summary class="enlace">Se perdió</summary><form data-form="perdida" data-id="${o.id}">
        <label for="pm">Por qué</label><select id="pm" name="motivo" required>${opciones(MOTIVO, "", "Escoja")}</select>
        <label for="pd">Lo que dijo, si quiere dejarlo</label><input id="pd" name="detalle" autocomplete="off">
        <button class="btn peligro">Marcarla como perdida</button></form></details>` : ""}
  </main>` + pie("#/ventas"));
}
formularios.paso = async (f, form) => {
  const r = await pedir(sb.from("oportunidad").update({ siguiente_paso: f.paso.trim(), siguiente_paso_en: f.en, siguiente_paso_por: f.por }).eq("id", form.dataset.id).select("id"));
  if (!r.length) throw new Error("No puede cambiar esta oportunidad.");
  aviso = bien("Siguiente paso guardado."); navegar();
};
formularios.cita = async (f, form) => {
  await pedir(sb.from("cita").insert({ oportunidad_id: form.dataset.id, tipo: f.tipo, modalidad: f.modalidad, programada_para: new Date(f.cuando).toISOString() }).select("id"));
  aviso = bien(`${TIPO_CITA[f.tipo]} agendada para el ${momento(new Date(f.cuando).toISOString())}.`); navegar();
};
formularios.cotizacion = async (f, form) => {
  const valor = Number(String(f.valor).replace(/\D/g, "")), costo = f.costo ? Number(String(f.costo).replace(/\D/g, "")) : null;
  await pedir(sb.from("cotizacion").insert({ oportunidad_id: form.dataset.id, numero: f.numero.trim(), tipo: f.tipo, valor, costo_estimado: costo, estado: "emitida" }).select("id"));
  aviso = bien("Cotización enviada. La oportunidad quedó en «cotización presentada»."); navegar();
};
acciones.cotizacion = async el => {
  await pedir(sb.from("cotizacion").update({ estado: el.dataset.estado, respondida_en: hoyIso() }).eq("id", el.dataset.id).select("id"));
  aviso = bien(el.dataset.estado === "aceptada" ? "Aceptada: la oportunidad pasó a contrato y anticipo." : "Quedó registrado que la rechazó."); navegar();
};
acciones.ganada = async el => {
  const r = await pedir(sb.from("oportunidad").update({ etapa: "ganada" }).eq("id", el.dataset.id).select("id"));
  if (!r.length) throw new Error("No puede cambiar esta oportunidad.");
  ir(`#/oportunidad/${el.dataset.id}`, bien("Venta ganada. Si era un diseño, ya nació la oportunidad de obra a nombre de quien responde por las obras."));
};
formularios.perdida = async (f, form) => {
  const r = await pedir(sb.from("oportunidad").update({ etapa: "perdida", motivo_perdida: f.motivo, detalle_perdida: f.detalle.trim() || null }).eq("id", form.dataset.id).select("id"));
  if (!r.length) throw new Error("No puede cambiar esta oportunidad.");
  aviso = bien("Quedó como perdida, con su motivo."); navegar();
};

// El reporte después de la cita: se escoge, no se escribe.
async function vistaReporte(citaId) {
  const c = await pedir(sb.from("cita").select("id,tipo,estado,programada_para,modalidad,oportunidad_id,oportunidad(nombre,unidad,valor_estimado,area_m2)").eq("id", citaId).maybeSingle());
  if (!c) return pinta(cabecera("Reporte de la cita", { atras: "#/ventas" }) + '<main><p class="vacio">Esa cita no existe o no la puede ver.</p></main>');
  const atras = `#/oportunidad/${c.oportunidad_id}`;
  if (!["agendada", "reprogramada"].includes(c.estado)) return pinta(cabecera("Reporte de la cita", { sobre: c.oportunidad?.nombre, atras }) + '<main><p class="bien">Esta cita ya tiene su reporte.</p></main>');
  const primera = c.tipo === "viabilidad", sn = (n, t) => `<select id="${n}" name="${n}"><option value="">Escoja</option><option value="true">Sí</option><option value="false">No</option>${t ? `<option value="">${t}</option>` : ""}</select>`;
  pinta(cabecera("Después de la cita", { sobre: `${c.oportunidad?.nombre} · ${TIPO_CITA[c.tipo]}`, atras }) + `<main><form data-form="reporte" data-id="${c.id}" data-oportunidad="${c.oportunidad_id}">
    <label for="llego">¿Llegó?</label><select id="llego" name="llego" data-cambia="reportePinta"><option value="true">Sí, fue la reunión</option><option value="false">No llegó</option></select>
    <div data-si="llego">
      <label for="grabacion">¿Autorizó grabarla?</label>${sn("grabacion")}
      <label for="transcripcion">Enlace de la transcripción, si hay</label><input id="transcripcion" name="transcripcion" type="url" inputmode="url" placeholder="https://docs.google.com/…" autocomplete="off">
      ${primera ? `<div class="grupo">Lo que dejó la cita</div>
      <label for="decisor_presente">¿Estaba quien decide?</label>${sn("decisor_presente")}
      <label for="tiene_lote">¿Tiene lote?</label><select id="tiene_lote" name="tiene_lote">${opciones(LOTE, "", "Escoja")}</select>
      <label for="recurso_disponible">¿Cuándo tiene el recurso?</label><select id="recurso_disponible" name="recurso_disponible">${opciones(RECURSO, "", "Escoja")}</select>
      <label for="proposito">¿Para qué es?</label><select id="proposito" name="proposito">${opciones(PROPOSITO, "", "Escoja")}</select>
      <label for="primera_cotizacion">¿Somos la primera cotización que pide?</label>${sn("primera_cotizacion", "No lo dijo")}
      <div class="dos"><div><label for="area">Área aproximada, m²</label><input id="area" name="area" inputmode="decimal" data-cambia="sugerir" value="${c.oportunidad?.area_m2 ?? ""}"></div>
      <div><label for="valor">Valor estimado</label><input id="valor" name="valor" inputmode="numeric" value="${c.oportunidad?.valor_estimado ? Math.round(c.oportunidad.valor_estimado) : ""}" placeholder="Lo sugiere la tarifa"></div></div>
      <p class="pista" id="sugerido"></p>` : ""}
      <div class="grupo">Cómo sigue</div>
      <label for="sigue">Escoja</label><select id="sigue" name="sigue" required data-cambia="reportePinta">
        ${primera ? '<option value="cotizar">Le presentamos la cotización</option>' : '<option value="contrato">Acepta: firma y paga el anticipo</option>'}
        <option value="otra_cita">Otra reunión</option><option value="pensarlo">Lo va a pensar</option><option value="no_sigue">No sigue</option></select>
      <div data-si="cuando"><label for="cuando">${primera ? "Cuándo se le presenta la cotización" : "Cuándo es la reunión"}</label><input id="cuando" name="cuando" type="datetime-local" min="${ahoraLocal()}"></div>
      <div data-si="seguimiento" hidden><label for="seguimiento">Cuándo se le vuelve a llamar</label><input id="seguimiento" name="seguimiento" type="date" min="${hoyIso()}"></div>
      <div data-si="motivo" hidden><label for="motivo">Por qué no sigue</label><select id="motivo" name="motivo">${opciones(MOTIVO, "", "Escoja")}</select>
        <label for="detalle">Lo que dijo, si quiere dejarlo</label><input id="detalle" name="detalle" autocomplete="off"></div>
    </div>
    <button class="btn">Guardar el reporte</button></form></main>`);
  acciones.reportePinta();
}
acciones.reportePinta = () => {
  const f = document.querySelector('[data-form="reporte"]'); if (!f) return;
  const llego = f.llego.value === "true", s = f.sigue.value;
  f.querySelector('[data-si="llego"]').hidden = !llego;
  f.querySelector('[data-si="cuando"]').hidden = !["cotizar", "otra_cita"].includes(s);
  f.querySelector('[data-si="cuando"] label').textContent = s === "cotizar" ? "Cuándo se le presenta la cotización" : "Cuándo es la reunión";
  f.querySelector('[data-si="seguimiento"]').hidden = s !== "pensarlo";
  f.querySelector('[data-si="motivo"]').hidden = s !== "no_sigue";
};
acciones.sugerir = async el => {
  const area = Number(String(el.value).replace(",", ".")), p = document.getElementById("sugerido"), unidad = "diseno_arquitectonico";
  if (!area) { p.textContent = ""; return; }
  try { const v = await pedir(sb.rpc("valor_sugerido", { p_unidad: unidad, p_area: area }));
    p.textContent = v ? `Según las tarifas, para ${num(area)} m² son ${pesos(v)}. Si deja el valor vacío, se usa ese.` : "No hay tarifa escrita para esa área: escriba el valor."; }
  catch { p.textContent = ""; }
};
formularios.reporte = async (f, form) => {
  const b = v => v === "true" ? true : v === "false" ? false : null, numero = v => v ? Number(String(v).replace(/[^\d,.]/g, "").replace(",", ".")) : null;
  const datos = { llego: f.llego === "true", grabacion: b(f.grabacion), transcripcion: f.transcripcion || null, sigue: f.sigue, cuando: f.cuando || null,
    seguimiento: f.seguimiento || null, motivo: f.motivo || null, detalle: f.detalle || null };
  if ("decisor_presente" in f) Object.assign(datos, { decisor_presente: b(f.decisor_presente), tiene_lote: f.tiene_lote || null, recurso_disponible: f.recurso_disponible || null,
    proposito: f.proposito || null, primera_cotizacion: b(f.primera_cotizacion), area: numero(f.area), valor: f.valor ? Number(String(f.valor).replace(/\D/g, "")) : null });
  await pedir(sb.rpc("reporte_de_cita", { p_cita: form.dataset.id, p_datos: datos }));
  ir(`#/oportunidad/${form.dataset.oportunidad}`, bien(!datos.llego ? "Quedó que no llegó. El siguiente paso es reagendarla."
    : { cotizar: "Reporte guardado y presentación agendada. Ya puede preparar la cotización.", otra_cita: "Reporte guardado y reunión agendada.",
        pensarlo: "Reporte guardado. Le toca la llamada el día que escogió.", contrato: "Reporte guardado: pasa a contrato y anticipo.", no_sigue: "Reporte guardado: quedó como perdida, con su motivo." }[datos.sigue]));
};

// Un contacto: los intentos, y la cita cuando la acepta.
async function vistaContacto(id) {
  const [l, intentos, equipo] = await Promise.all([
    pedir(sb.from("lead").select("id,nombre,telefono,correo,ciudad,canal,como_nos_encontro,mensaje_inicial,estado,creado_en,primer_contacto_en,motivo_descarte").eq("id", id).maybeSingle()),
    pedir(sb.from("contacto_lead").select("fecha,medio,direccion,respondio,nota").eq("lead_id", id).order("fecha")),
    gente(),
  ]);
  if (!l) return pinta(cabecera("Contacto", { atras: "#/ventas" }) + '<main><p class="vacio">Ese contacto no existe o no lo puede ver.</p></main>');
  const [op] = await pedir(sb.from("oportunidad").select("id").eq("lead_id", id));
  if (op) return ir(`#/oportunidad/${op.id}`);
  const vivo = !["descartado", "convertido"].includes(l.estado);
  pinta(cabecera(l.nombre || l.telefono || "Contacto", { sobre: { nuevo: "Sin primer contacto", contactado: "Contactado", calificado: "Calificado", nutricion: "En nutrición", descartado: "Descartado" }[l.estado] || l.estado, atras: "#/ventas" }) + `<main>
    <div class="fila"><b>${l.telefono ? `<a href="tel:${h(l.telefono)}">${h(l.telefono)}</a>` : "Sin teléfono"}${l.telefono ? ` · <a href="${whatsapp(l.telefono)}" target="_blank" rel="noopener">WhatsApp</a>` : ""}</b>
      <span>${l.correo ? h(l.correo) + " · " : ""}${l.ciudad ? h(l.ciudad) + " · " : ""}llegó por ${h(CANAL[l.canal] || l.canal)} el ${h(momento(l.creado_en))}</span>${l.mensaje_inicial ? `<span>«${h(l.mensaje_inicial)}»</span>` : ""}</div>
    ${l.estado === "nutricion" ? '<p class="nota">Está en nutrición: tres intentos sin respuesta. Si vuelve a escribir, sale solo.</p>' : ""}
    ${l.estado === "descartado" ? `<p class="nota">Descartado: ${h(l.motivo_descarte)}.</p>` : ""}
    <div class="grupo">Intentos</div>
    ${intentos.map(i => `<div class="fila"><span>${h(momento(i.fecha))} · ${i.direccion === "entrante" ? "escribió él" : i.respondio ? "respondió" : "no respondió"} · ${h(i.medio)}${i.nota ? " · " + h(i.nota) : ""}</span></div>`).join("") || '<p class="vacio" style="padding:14px 0">Ninguno todavía.</p>'}
    ${vivo ? `<div class="par"><button class="btn claro" data-accion="intento" data-id="${l.id}" data-respondio="false">No respondió</button><button class="btn claro" data-accion="intento" data-id="${l.id}" data-respondio="true">Respondió</button></div>
    <div class="grupo">Agendar la cita de viabilidad</div>
    <form data-form="citaLead" data-id="${l.id}">
      <label for="lc">Cuándo</label><input id="lc" name="cita" type="datetime-local" min="${ahoraLocal()}" required>
      <label for="lu">Qué busca</label><select id="lu" name="unidad">${opciones(UNIDAD, "diseno_arquitectonico")}</select>
      <label for="lp">Nombre del proyecto</label><input id="lp" name="proyecto" placeholder="Casa en Cerritos" autocomplete="off">
      <label for="lr">Quién hace la cita</label><select id="lr" name="responsable_id">${equipo.map(p => `<option value="${p.id}" ${p.id === yo.persona_id ? "selected" : ""}>${h(p.nombre)}</option>`).join("")}</select>
      <button class="btn">Agendar la cita</button></form>
    <details><summary class="enlace">Descartarlo</summary><form data-form="descartar" data-id="${l.id}">
      <label for="ld">Por qué</label><input id="ld" name="motivo" required minlength="4" placeholder="Es proveedor, busca empleo, no tiene proyecto…" autocomplete="off">
      <button class="btn peligro">Descartar</button></form></details>` : ""}
  </main>` + pie("#/ventas"));
}
acciones.intento = async el => {
  await pedir(sb.from("contacto_lead").insert({ lead_id: el.dataset.id, medio: "whatsapp", direccion: "saliente", respondio: el.dataset.respondio === "true", registrado_por: yo.persona_id }).select("id"));
  aviso = bien(el.dataset.respondio === "true" ? "Quedó que respondió." : "Intento registrado. Al tercero sin respuesta pasa a nutrición."); navegar();
};
formularios.citaLead = async (f, form) => {
  const r = await pedir(sb.rpc("agendar_cita_de_lead", { p_lead: form.dataset.id, p_datos: f }));
  ir(`#/oportunidad/${r.oportunidad_id}`, bien("Cita agendada. Ya es una oportunidad, con su siguiente paso."));
};
formularios.descartar = async (f, form) => {
  await pedir(sb.from("lead").update({ estado: "descartado", motivo_descarte: f.motivo.trim() }).eq("id", form.dataset.id).select("id"));
  ir("#/ventas", bien("Descartado, con su motivo."));
};

async function vistaContactoNuevo() {
  const equipo = await gente();
  pinta(cabecera("Nuevo contacto", { atras: "#/ventas" }) + `<main><form data-form="contacto">
    <label for="nn">Nombre</label><input id="nn" name="nombre" autocomplete="off">
    <div class="dos"><div><label for="nt">Teléfono</label><input id="nt" name="telefono" type="tel" inputmode="tel" autocomplete="off"></div>
    <div><label for="nc">Ciudad</label><input id="nc" name="ciudad" autocomplete="off"></div></div>
    <label for="ne">Correo</label><input id="ne" name="correo" type="email" inputmode="email" autocomplete="off">
    <label for="nk">Por dónde llegó</label><select id="nk" name="canal" required>${opciones(CANAL, "", "Escoja")}</select>
    <label for="nf">Cómo dice que nos encontró</label><select id="nf" name="como_nos_encontro">${opciones(CANAL, "", "No lo dijo")}</select>
    <label for="nm">Lo que escribió</label><textarea id="nm" name="mensaje"></textarea>
    <div class="grupo">Si ya aceptó la cita</div>
    <label for="nci">Cuándo</label><input id="nci" name="cita" type="datetime-local" min="${ahoraLocal()}">
    <div class="dos"><div><label for="nu">Qué busca</label><select id="nu" name="unidad">${opciones(UNIDAD, "diseno_arquitectonico")}</select></div>
    <div><label for="nr">Quién hace la cita</label><select id="nr" name="responsable_id">${equipo.map(p => `<option value="${p.id}" ${p.id === yo.persona_id ? "selected" : ""}>${h(p.nombre)}</option>`).join("")}</select></div></div>
    <button class="btn">Guardar el contacto</button></form></main>`);
}
formularios.contacto = async f => {
  const r = await pedir(sb.rpc("nuevo_contacto", { p_datos: f }));
  ir(r.oportunidad_id ? `#/oportunidad/${r.oportunidad_id}` : "#/ventas", bien(r.oportunidad_id ? "Contacto guardado y cita agendada." : "Contacto guardado. Queda en «Para hoy» hasta el primer contacto."));
};

async function vistaTarifas() {
  const ts = await pedir(sb.from("tarifa_diseno").select("id,unidad,area_desde,area_hasta,valor,alcance,activa").eq("activa", true).order("unidad").order("area_desde"));
  pinta(cabecera("Tarifas de diseño", { atras: "#/ventas" }) + `<main>
    <p class="nota">El reporte de la cita sugiere el valor con estas tarifas cuando se escribe el área. Las escribe dirección.</p>
    ${ts.map(t => `<div class="fila"><b>${h(UNIDAD[t.unidad])} · de ${num(t.area_desde)} a ${num(t.area_hasta)} m²</b><span>${pesos(t.valor)}${t.alcance ? " · " + h(t.alcance) : ""}</span>
      <button class="enlace" data-accion="quitarTarifa" data-id="${t.id}">Quitarla</button></div>`).join("") || '<p class="vacio">Todavía no hay tarifas.</p>'}
    <div class="grupo">Agregar una</div><form data-form="tarifa">
      <label for="tu">Para qué</label><select id="tu" name="unidad">${opciones({ diseno_arquitectonico: UNIDAD.diseno_arquitectonico, interiorismo: UNIDAD.interiorismo })}</select>
      <div class="dos"><div><label for="td">Desde, m²</label><input id="td" name="desde" inputmode="decimal" required></div><div><label for="th">Hasta, m²</label><input id="th" name="hasta" inputmode="decimal" required></div></div>
      <label for="tv">Valor sin IVA</label><input id="tv" name="valor" inputmode="numeric" required>
      <label for="ta">Qué incluye</label><input id="ta" name="alcance" placeholder="Arquitectónico y complementarios" autocomplete="off">
      <button class="btn">Agregar la tarifa</button></form></main>` + pie("#/ventas"));
}
formularios.tarifa = async f => {
  const n = v => Number(String(v).replace(",", "."));
  await pedir(sb.from("tarifa_diseno").insert({ unidad: f.unidad, area_desde: n(f.desde), area_hasta: n(f.hasta), valor: Number(String(f.valor).replace(/\D/g, "")), alcance: f.alcance.trim() || null, creada_por: yo.persona_id }).select("id"));
  aviso = bien("Tarifa agregada."); navegar();
};
acciones.quitarTarifa = async el => {
  await pedir(sb.from("tarifa_diseno").update({ activa: false }).eq("id", el.dataset.id).select("id"));
  aviso = bien("Tarifa quitada."); navegar();
};

// ---------- mover tareas en el tablero ----------
// Arrastrar una tarjeta a otra columna es lo mismo que oprimir el botón en la
// tarea, con las mismas reglas: quien la tiene la empieza o la entrega; quien la
// revisa la aprueba o la devuelve (para devolver hay que escribir qué falta).
function destinos(t, pid) {
  const mia = t.asignada_a === yo.persona_id, sinRevision = t.requiere_revision === false, entrega = sinRevision ? "terminada" : "en_revision";
  const reviso = !mia && !sinRevision && (t.revisor_id ? t.revisor_id === yo.persona_id : yo.revisa.includes(pid));
  // Dirección mueve todas las tareas (Felipe, 19-10-2026). Lo único que no salta es la
  // revisión que se fijó al crear la tarea: a «Terminadas» llega sola si no requiere
  // revisión; si la requiere, la aprueba quien la revisa (si es quien dirige, al soltarla aquí).
  if (yo.es_direccion || (pid && yo.dirige.includes(pid))) {
    if (t.estado === "terminada" && !yo.es_direccion) return [];   // reabrir una terminada es de dirección
    const a = ["asignada", "en_curso"];
    if (!sinRevision) a.push("en_revision");
    if (sinRevision || (reviso && t.estado === "en_revision")) a.push("terminada");
    if (reviso && t.estado === "en_revision") a.push("con_observaciones");
    return a.filter(e => e !== t.estado);
  }
  if (mia) return { asignada: ["en_curso", entrega], en_curso: ["asignada", entrega], con_observaciones: [entrega], en_revision: ["en_curso"] }[t.estado] || [];
  if (reviso && t.estado === "en_revision") return ["terminada", "con_observaciones"];
  return [];
}
async function moverTarea(card, a) {
  const de = card.closest(".kb-c"), para = document.querySelector(`.kb-c[data-estado="${a}"]`), desde = de.dataset.estado;
  if (desde === "en_revision" && a === "con_observaciones") return ir(`#/tarea/${card.dataset.id}`, { tipo: "bien", texto: "Para devolverla, escriba abajo qué falta y oprima Devolver." });
  // Se mueve y se pinta de una vez; si la base no lo acepta, el tablero vuelve a como estaba.
  const nada = para.querySelector(".kb-nada"); if (nada) nada.remove();
  const ref = [...para.querySelectorAll(".kb-t")][0]; para.insertBefore(card, ref || null);
  card.className = card.className.replace(/\be-\S+/, "e-" + a);
  for (const c of [de, para]) c.querySelector("header b").textContent = c.querySelectorAll(".kb-t").length;
  if (!de.querySelector(".kb-t")) de.insertAdjacentHTML("beforeend", '<p class="kb-nada">Ninguna.</p>');
  try {
    if (desde === "en_revision" && a === "terminada" && card.dataset.puede.includes("con_observaciones"))
      await pedir(sb.from("revision_diseno").insert({ tarea_id: card.dataset.id, revisor_id: yo.persona_id, resultado: "aprobada", observaciones: null }));
    else await pedir(sb.from("tarea_diseno").update({ estado: a }).eq("id", card.dataset.id));
    // Se vuelve a pintar para que los conteos de arriba cuadren, sin perder dónde se estaba mirando.
    const y = window.scrollY, x = document.querySelector(".kb")?.scrollLeft || 0;
    aviso = bien(`«${card.querySelector("b").firstChild.textContent.trim()}» pasó a ${COLUMNAS.find(c => c[0] === a)[1]}.`);
    await navegar(); window.scrollTo(0, y); const kb = document.querySelector(".kb"); if (kb) kb.scrollLeft = x;
  } catch (e) { aviso = mal(e); navegar(); }
}
// El arrastre: con el ratón arranca al mover; con el dedo, al dejarlo quieto un
// momento sobre la tarjeta, para no pelear con el desplazamiento del tablero.
let arrastre = null;
document.addEventListener("pointerdown", e => {
  const card = e.target.closest(".kb-t[data-puede]");
  if (!card || e.button > 0 || !card.dataset.puede) return;
  arrastre = { card, x: e.clientX, y: e.clientY, activo: false, id: e.pointerId, toque: e.pointerType !== "mouse" };
  if (arrastre.toque) arrastre.espera = setTimeout(() => arrastre && empezarArrastre(e.clientX, e.clientY), 320);
});
function empezarArrastre(x, y) {
  const a = arrastre, r = a.card.getBoundingClientRect(); a.activo = true; a.dx = x - r.left; a.dy = y - r.top;
  a.fantasma = a.card.cloneNode(true); a.fantasma.classList.add("kb-fantasma"); a.fantasma.style.width = r.width + "px";
  document.body.appendChild(a.fantasma); a.card.classList.add("kb-origen");
  const puede = a.card.dataset.puede.split(" ");
  document.querySelectorAll(".kb-c").forEach(c => c.classList.add(puede.includes(c.dataset.estado) ? "kb-puede" : c.contains(a.card) ? "kb-sale" : "kb-no"));
  moverFantasma(x, y); navigator.vibrate?.(15);
}
function moverFantasma(x, y) {
  const a = arrastre; a.fantasma.style.transform = `translate(${x - a.dx}px,${y - a.dy}px) rotate(1.5deg)`;
  a.fantasma.hidden = true; const col = document.elementFromPoint(x, y)?.closest(".kb-c.kb-puede"); a.fantasma.hidden = false;
  document.querySelectorAll(".kb-c.kb-sobre").forEach(c => c !== col && c.classList.remove("kb-sobre")); col?.classList.add("kb-sobre"); a.sobre = col;
  const kb = document.querySelector(".kb"), b = kb?.getBoundingClientRect();   // cerca del borde, el tablero se corre solo
  if (b && x > b.right - 40) kb.scrollLeft += 14; else if (b && x < b.left + 40) kb.scrollLeft -= 14;
}
document.addEventListener("pointermove", e => {
  const a = arrastre; if (!a || e.pointerId !== a.id) return;
  if (!a.activo) { if (Math.hypot(e.clientX - a.x, e.clientY - a.y) < 8) return; if (a.toque) { clearTimeout(a.espera); arrastre = null; return; } empezarArrastre(e.clientX, e.clientY); }
  moverFantasma(e.clientX, e.clientY);
});
document.addEventListener("dragstart", e => { if (e.target.closest?.(".kb-t[data-puede]")) e.preventDefault(); });
document.addEventListener("touchmove", e => { if (arrastre?.activo) e.preventDefault(); }, { passive: false });
function soltar(e, cancelar) {
  const a = arrastre; if (!a || (e && e.pointerId !== a.id)) return; arrastre = null; clearTimeout(a.espera);
  if (!a.activo) return;
  a.fantasma.remove(); a.card.classList.remove("kb-origen");
  document.querySelectorAll(".kb-c").forEach(c => c.classList.remove("kb-puede", "kb-sale", "kb-no", "kb-sobre"));
  a.card.addEventListener("click", ev => ev.preventDefault(), { once: true, capture: true });   // que soltar no abra la tarea
  if (!cancelar && a.sobre) moverTarea(a.card, a.sobre.dataset.estado);
}
document.addEventListener("pointerup", e => soltar(e));
document.addEventListener("pointercancel", e => soltar(e, true));
document.addEventListener("keydown", e => { if (e.key === "Escape" && arrastre?.activo) soltar(null, true); });
document.addEventListener("contextmenu", e => { if (arrastre?.toque) e.preventDefault(); });

// ---------- revisar ----------
async function vistaRevisar() {
  const cola = (await pedir(sb.from("v_cola_revision").select("*").order("revision_pedida_en"))).filter(c => !c.revisor_id || c.revisor_id === yo.persona_id);
  pinta(cabecera("Revisar") + `<main>${cola.map(c => `<a class="fila" href="#/tarea/${c.tarea_id}"><b>${h(c.titulo)}${marca(c.prioridad)}</b>
      <span>${h(titulo(c.proyecto))} · ${c.fuera_de_plazo ? "<em>" : ""}${h(c.lectura)}${c.fuera_de_plazo ? "</em>" : ""}</span></a>`).join("") ||
    '<p class="vacio">Nada espera revisión.</p>'}</main>` + pie("#/revisar", cola.length));
}

// ---------- proyectos ----------
async function vistaProyectos() {
  const ps = await pedir(sb.from("proyecto").select("id,codigo,nombre,tipo,unidad,fase,estado").eq("estado", "activo").order("nombre"));
  const ids = ps.map(p => p.id);
  const [fases, avance, abiertas] = ids.length ? await Promise.all([
    pedir(sb.from("proyecto_fase").select("id,proyecto_id,fase,orden,estado,fecha_compromiso").in("proyecto_id", ids).order("orden")),
    pedir(sb.from("v_fase_avance").select("fase_id,proyecto_id,tareas,terminadas")),
    pedir(sb.from("tarea_diseno").select("id,proyecto_id,estado,fecha_compromiso").in("proyecto_id", ids).neq("estado", "terminada")),
  ]) : [[], [], []];
  const av = new Map(avance.map(a => [a.fase_id, a]));
  const ficha = p => {
    const fs = fases.filter(f => f.proyecto_id === p.id), aa = avance.filter(a => a.proyecto_id === p.id), tot = aa.reduce((n, a) => n + a.tareas, 0), hechas = aa.reduce((n, a) => n + a.terminadas, 0);
    const ts = abiertas.filter(t => t.proyecto_id === p.id), v = ts.filter(t => t.fecha_compromiso && t.fecha_compromiso < hoyIso() && t.estado !== "en_revision").length;
    const act = fs.find(f => f.estado === "en_curso" || f.estado === "en_revision");
    return `<a class="pr" href="#/proyecto/${p.id}"><b>${h(p.nombre)}</b><span>${h(UNIDAD[p.unidad] || p.unidad)}${act ? " · en " + h(nFase(act.fase).toLowerCase()) : ""} · ${ts.length ? uno(ts.length, "una tarea abierta", "tareas abiertas") : "sin tareas abiertas"}${v ? ` · <em>${uno(v, "una vencida", "vencidas")}</em>` : ""}</span>
      ${fs.length ? tiraFases(fs, av) : ""}${tot ? barraAvance(hechas / tot * 100) : ""}</a>`;
  };
  pinta(cabecera("Proyectos") + `<main>${ps.map(ficha).join("") ||
    `<p class="vacio">${yo.es_direccion ? "Todavía no hay proyectos. Abra el primero con el botón de abajo." : "Todavía no hace parte de ningún proyecto."}</p>`}
    ${yo.es_direccion ? '<a class="btn" href="#/nuevo-proyecto">Crear proyecto nuevo</a>' : ""}</main>` + pie("#/proyectos"));
}
// Cada proyecto es un tablero: arriba cómo va (fases y cifras) y cuatro maneras
// de verlo. Tablero por estado, lista por fase, cronograma por semanas y la ficha.
const VISTAS = [["tablero", "Tablero"], ["lista", "Lista"], ["cronograma", "Cronograma"], ["ficha", "Ficha"]];
const COLUMNAS = [["asignada", "Por empezar"], ["en_curso", "En curso"], ["en_revision", "En revisión"], ["con_observaciones", "Devueltas"], ["terminada", "Terminadas"]];
async function vistaProyecto(id, vista = "tablero") {
  if (!VISTAS.some(v => v[0] === vista)) vista = "tablero";
  const [p, fases, equipo, tareas, personas, avance] = await Promise.all([
    pedir(sb.from("proyecto").select("id,codigo,nombre,tipo,unidad,carpeta_drive").eq("id", id).maybeSingle()),
    pedir(sb.from("proyecto_fase").select("id,fase,orden,estado,horas_cotizadas,entrega_cliente,fecha_compromiso,responsable_id").eq("proyecto_id", id).order("orden")),
    pedir(sb.from("acceso_proyecto").select("papel,persona(id,nombre,rol)").eq("proyecto_id", id)),
    pedir(sb.from("tarea_diseno").select("id,titulo,estado,prioridad,fecha_inicio,fecha_compromiso,creada_en,terminada_en,dias_estimados,fase_id,asignada_a,requiere_revision,revisor_id,tiene:persona!tarea_diseno_asignada_a_fkey(nombre)").eq("proyecto_id", id).order("fecha_compromiso", { nullsFirst: false })),
    yo.es_direccion && vista === "ficha" ? pedir(sb.from("persona").select("id,nombre").eq("es_interno", true).eq("activo", true).order("nombre")) : [],
    pedir(sb.from("v_fase_avance").select("fase_id,tareas,terminadas,trabajo_terminado").eq("proyecto_id", id)),
  ]);
  if (!p) return pinta(cabecera("Proyecto", { atras: "#/proyectos" }) + '<main><p class="vacio">Ese proyecto no existe o usted no hace parte de su equipo.</p></main>');
  const av = new Map(avance.map(a => [a.fase_id, a])), fase = new Map(fases.map(f => [f.id, f]));
  const abiertas = tareas.filter(t => t.estado !== "terminada"), vencidas = abiertas.filter(t => plazo(t).k === "c");
  const hechas = tareas.length - abiertas.length, pct = tareas.length ? hechas / tareas.length * 100 : 0;
  const cuenta = e => tareas.filter(t => t.estado === e).length;
  const nombreFase = t => fase.get(t.fase_id) ? nFase(fase.get(t.fase_id).fase) : "Sin fase";
  const quien = t => t.tiene?.nombre || "Sin responsable";
  const dirijo = yo.dirige.includes(id);

  const cab = `<section class="p-cab">${fases.length ? tiraFases(fases, av, `#/proyecto/${id}/lista`) : ""}
    <div class="p-avance ${vencidas.length ? "c" : ""}">${vencidas.length ? `<b>${vencidas.length}</b><span>${vencidas.length === 1 ? "tarea vencida" : "tareas vencidas"} · avance ${pct.toFixed(0)} %</span>`
      : `<b>${pct.toFixed(0)}<small style="font-size:.4em"> %</small></b><span>de avance · ${uno(hechas, "una tarea terminada", "terminadas")} de ${tareas.length}</span>`}</div>
    <div class="kp"><div><b>${cuenta("asignada")}</b><small>Por empezar</small></div><div><b>${cuenta("en_curso") + cuenta("con_observaciones")}</b><small>En curso</small></div>
      <div><b>${cuenta("en_revision")}</b><small>En revisión</small></div><div class="${vencidas.length ? "c" : ""}"><b>${vencidas.length}</b><small>Vencidas</small></div></div></section>
    <nav class="pestanas p-tabs" aria-label="Vistas del proyecto"><div>${VISTAS.map(([v, n]) => `<a href="#/proyecto/${id}/${v}" ${v === vista ? 'aria-current="page"' : ""}>${n}</a>`).join("")}</div></nav>`;
  const repartir = yo.registra.includes(id) ? `<a class="btn claro" href="#/nueva/${id}">${dirijo || yo.asigna ? "Repartir tareas de este proyecto" : "Nueva tarea en este proyecto"}</a>` : "";

  let cuerpo = "";
  if (vista === "tablero") {
    const tarjeta = t => { const k = plazo(t).k, puede = destinos(t, id);
      return `<a class="kb-t e-${t.estado} ${k === "c" || k === "a" ? k : ""}" href="#/tarea/${t.id}" data-id="${t.id}"${puede.length ? ` data-puede="${puede.join(" ")}" title="Arrástrela para cambiarla de columna" draggable="false"` : ""}><span class="f">${h(nombreFase(t))}</span><b>${h(t.titulo)}${marca(t.prioridad)}</b>
        <span class="q">${avatar(quien(t), t.asignada_a !== yo.persona_id)}${h(quien(t).split(" ")[0])} · ${t.fecha_compromiso ? h(corta(t.fecha_compromiso)) : "sin fecha"}</span>${barraPlazo(t)}</a>`; };
    cuerpo = `<div class="kb" tabindex="0" aria-label="Tareas por estado" data-proyecto="${id}">${COLUMNAS.map(([e, n]) => { const l = tareas.filter(t => t.estado === e)
        .sort((a, b) => e === "terminada" ? String(b.terminada_en || "").localeCompare(String(a.terminada_en || "")) : String(a.fecha_compromiso || "9").localeCompare(String(b.fecha_compromiso || "9")));
      return `<section class="kb-c c-${e}" data-estado="${e}"><header><span>${n}</span><b>${l.length}</b></header>${l.slice(0, e === "terminada" ? 8 : 40).map(tarjeta).join("") || '<p class="kb-nada">Ninguna.</p>'}${e === "terminada" && l.length > 8 ? `<p class="kb-nada">Y ${l.length - 8} más.</p>` : ""}</section>`; }).join("")}</div>${repartir}`;
  } else if (vista === "lista") {
    const grupos = [...fases.map(f => [f, tareas.filter(t => t.fase_id === f.id)]), [null, tareas.filter(t => !fase.has(t.fase_id))]].filter(([f, l]) => l.length || (f && (f.estado === "en_curso" || f.estado === "en_revision")));
    const hoy = hoyIso();
    cuerpo = grupos.map(([f, l]) => { const abierta = f && (f.estado === "en_curso" || f.estado === "en_revision"), tarde = abierta && f.fecha_compromiso && f.fecha_compromiso < hoy;
      const a = f && av.get(f.id);
      return `<section class="ls-g ${f?.estado === "cerrada" ? "cerrada" : tarde ? "tarde" : abierta ? "curso" : ""}"><header><b>${h(f ? nFase(f.fase) : "Sin fase")}</b>${f ? `<span class="marca ${FASE[f.estado][1]}">${FASE[f.estado][0]}</span>` : ""}
          <span>${a?.tareas ? `${a.terminadas} de ${a.tareas} terminadas` : uno(l.length, "una tarea", "tareas")}${f?.fecha_compromiso ? ` · ${tarde ? "<em style='font-style:normal;color:var(--critico)'>" : ""}se entrega el ${h(fecha(f.fecha_compromiso))}${tarde ? "</em>" : ""}` : ""}</span></header>
        ${l.map(t => `<a class="ls-t" href="#/tarea/${t.id}"><b>${h(t.titulo)}${marca(t.prioridad)}</b><span class="q">${avatar(quien(t), t.asignada_a !== yo.persona_id)}${chipEstado(t.estado)}</span>${barraPlazo(t)}</a>`).join("") || '<p class="kb-nada">Sin tareas todavía.</p>'}</section>`; }).join("") + repartir;
  } else if (vista === "cronograma") {
    const hoy = dia0(hoyIso()), conFecha = tareas.filter(t => t.fecha_compromiso);
    if (!conFecha.length) cuerpo = '<p class="vacio">Todavía no hay tareas con fecha para dibujar.</p>' + repartir;
    else {
      const ini = t => Math.min(dia0(String(t.fecha_inicio || t.creada_en || t.fecha_compromiso).slice(0, 10)), dia0(t.fecha_compromiso));
      let l0 = dia0(lunesDe(new Date(Math.min(hoy - 14, ...conFecha.map(ini)) * 864e5).toISOString().slice(0, 10)));
      let fin = Math.max(hoy + 27, ...conFecha.map(t => dia0(t.fecha_compromiso)));
      const n = Math.min(Math.ceil((fin - l0 + 1) / 7), 16); fin = l0 + n * 7 - 1;
      const total = n * 7, x = d => ((Math.max(l0, Math.min(d, fin + 1)) - l0) / total * 100);
      const fila = t => { const p = plazo(t), a = ini(t), b = Math.max(dia0(t.fecha_compromiso), p.k === "c" ? hoy : 0), izq = x(a), der = 100 - x(b + 1);
        if (b < l0 || a > fin) return "";
        const hecho = t.estado === "terminada" ? 100 : Math.max(0, Math.min(100, (hoy - a + 1) / (b - a + 1) * 100));
        return `<a class="cr-t ${p.k}" href="#/tarea/${t.id}" aria-label="${h(t.titulo)}: ${h(p.txt)}"><i style="left:${izq.toFixed(2)}%;right:${der.toFixed(2)}%"><b style="width:${hecho.toFixed(0)}%"></b></i>
          <span style="${izq > 55 ? `right:${der.toFixed(2)}%` : `left:${izq.toFixed(2)}%`}">${h(t.titulo)} · ${h(iniciales(quien(t)))} · ${h(p.k === "h" ? "terminada" : p.txt.toLowerCase())}</span></a>`; };
      const grupos = [...fases.map(f => [nFase(f.fase), conFecha.filter(t => t.fase_id === f.id)]), ["Sin fase", conFecha.filter(t => !fase.has(t.fase_id))]].filter(([, l]) => l.length);
      cuerpo = `<div class="cr" style="--n:${n}" tabindex="0" role="group" aria-label="Cronograma del proyecto"><div class="cr-in">
          <div class="cr-sems">${Array.from({ length: n }, (_, i) => { const s = new Date((l0 + i * 7) * 864e5).toISOString().slice(0, 10); return `<span>${s === lunesDe(hoyIso()) ? "Esta" : corta(s)}</span>`; }).join("")}</div>
          <div class="cr-fondo">${"<span></span>".repeat(n)}</div>${hoy >= l0 && hoy <= fin ? `<div class="cr-hoy" style="left:${x(hoy + 0.5).toFixed(2)}%"></div>` : ""}
          ${grupos.map(([g, l]) => `<div class="cr-g"><span>${h(g)}</span></div>${l.map(fila).join("")}`).join("")}</div></div>
        <div class="cr-ley"><span><i style="background:var(--tinta)"></i>Lo que ya pasó</span><span><i style="background:var(--alerta)"></i>Por vencer</span><span><i style="background:var(--critico)"></i>Vencida, hasta hoy</span><span><i style="background:var(--ok)"></i>Terminada</span></div>${repartir}`;
    }
  } else {
    const siguiente = fases.find(f => f.estado !== "cerrada");
    const responden = yo.es_direccion ? [...await asignables(id)].sort((a, b) => a[1].localeCompare(b[1])) : [];   // el equipo que trabaja y dirección
    const fuera = personas.filter(x => !equipo.some(e => e.persona.id === x.id));
    cuerpo = `${p.tipo === "obra" && yo.obras ? `<a class="btn" href="#/obra/${id}">Ver la obra: gastos, flujo y documentos</a>` : ""}
    ${fases.length ? `<div class="grupo">Fases</div>${fases.map(f => `<div class="fila"><b>${h(titulo(f.fase.replace(/_/g, " ")))}<span class="marca ${f.estado === "cerrada" ? "o" : f.estado === "pendiente" ? "n" : "a"}">${f.estado === "cerrada" ? "Cerrada" : f.estado === "pendiente" ? "Por abrir" : "En curso"}</span></b>
        <span>${Number(f.horas_cotizadas) ? Number(f.horas_cotizadas) + " horas cotizadas" : "Sin horas cotizadas"}${f.entrega_cliente ? " · " + h(f.entrega_cliente) : ""}${av.get(f.id)?.tareas ? ` · ${av.get(f.id).terminadas} de ${uno(av.get(f.id).tareas, "una tarea terminada", "tareas terminadas")}` : ""}${!yo.es_direccion && f.fecha_compromiso ? " · para el " + h(fecha(f.fecha_compromiso)) : ""}${!yo.es_direccion && f.responsable_id ? " · responde " + h(equipo.find(e => e.persona.id === f.responsable_id)?.persona.nombre || "dirección") : ""}</span>
        ${av.get(f.id)?.tareas ? barraAvance(av.get(f.id).terminadas / av.get(f.id).tareas * 100) : ""}
        ${av.get(f.id)?.trabajo_terminado ? '<span style="color:var(--ok)">Terminó todas sus tareas: está lista para el cierre.</span>' : ""}
        ${dirijo && f.estado === "en_curso" ? `<a class="g-dar" href="#/tipicas/${f.id}">Repartir sus tareas típicas</a>` : ""}
        ${yo.registra.includes(id) && (f.estado === "en_curso" || f.estado === "en_revision") ? `<a class="g-dar" href="#/cierre/${f.id}" style="display:block">${yo.es_direccion ? "Lista de chequeo y cierre" : "Lista de chequeo de la fase"}</a>` : ""}
        ${yo.es_direccion && f.estado !== "cerrada" ? `<div class="dos"><div><label for="ff${f.id}" style="margin-top:10px">Se entrega el</label><input id="ff${f.id}" type="date" value="${h(f.fecha_compromiso || "")}" data-cambia="fechaFase" data-id="${f.id}"></div>
          <div><label for="fr${f.id}" style="margin-top:10px">Responde</label><select id="fr${f.id}" data-cambia="responsableFase" data-id="${f.id}"><option value="">Sin definir</option>${responden.map(([pid, n]) => `<option value="${pid}" ${pid === f.responsable_id ? "selected" : ""}>${h(n)}</option>`).join("")}</select></div></div>` : ""}</div>`).join("")}
      ${dirijo && yo.es_direccion && siguiente?.estado === "pendiente" ? `<button class="btn claro" data-accion="abrirFase" data-id="${siguiente.id}">Abrir ${h(siguiente.fase.replace(/_/g, " "))}</button>` : ""}` : ""}

    <div class="grupo">Equipo</div>
    ${[...equipo.reduce((m, e) => (m.get(e.persona.id) || m.set(e.persona.id, { persona: e.persona, papeles: [] }).get(e.persona.id)).papeles.push(e.papel) && m, new Map()).values()]
      .map(e => `<div class="fila" style="display:flex;gap:12px;align-items:center">${avatar(e.persona.nombre, e.persona.id !== yo.persona_id)}<div><b>${h(e.persona.nombre)}</b><span>${h(nombrarPapeles(e.papeles))} · ${h(ROL[e.persona.rol] || e.persona.rol)}</span></div></div>`).join("") || '<p class="vacio" style="padding:14px 0">Todavía no tiene equipo: sin papel, nadie lo ve ni recibe tareas.</p>'}
    ${yo.es_direccion && fuera.length ? `<form data-form="equipo" data-id="${id}"><div class="dos">
        <div><label for="ep">Persona</label><select id="ep" name="persona">${fuera.map(x => `<option value="${x.id}">${h(x.nombre)}</option>`).join("")}</select></div>
        <div><label>Papeles</label>${casillasPapel("n", "la persona", [["observa", "Observa"]])}</div>
      </div><button class="btn claro">Agregar al equipo</button></form>` : ""}

    <div class="grupo">Documentos</div><div id="drive">${p.carpeta_drive ? "" : '<p class="vacio" style="padding:14px 0">Este proyecto todavía no tiene su carpeta de Drive.</p>'}</div>
    ${yo.es_direccion ? `<form data-form="carpeta" data-id="${id}"><label for="cd">Enlace de la carpeta de Drive</label>
      <input id="cd" name="carpeta" type="url" inputmode="url" placeholder="https://drive.google.com/drive/folders/…" value="${h(p.carpeta_drive || "")}">
      <button class="btn claro">Guardar la carpeta</button></form>` : ""}`;
  }
  app.classList.toggle("ancho", vista !== "ficha");
  pinta(cabecera(p.nombre, { sobre: `${UNIDAD[p.unidad] || p.unidad} · ${p.codigo}`, atras: "#/proyectos" }) + `<main>${cab}${cuerpo}</main>` + pie("#/proyectos"));
  if (vista === "ficha" && p.carpeta_drive) pintaDrive(p.carpeta_drive);
}
acciones.abrirFase = async el => {
  await pedir(sb.from("proyecto_fase").update({ estado: "en_curso" }).eq("id", el.dataset.id));
  // Si la fase tiene tareas típicas, lo siguiente es repartirlas.
  const tipicas = await sb.rpc("tareas_tipicas", { p_fase: el.dataset.id });
  if (tipicas.data?.length) ir(`#/tipicas/${el.dataset.id}`, bien("Fase abierta. Estas son sus tareas típicas: escoja a quién se le entrega cada una."));
  else { aviso = bien("Fase abierta."); navegar(); }
};
async function guardaFase(el, cambio, dicho) {
  try { const r = await pedir(sb.from("proyecto_fase").update(cambio).eq("id", el.dataset.id).select("id"));
    aviso = r.length ? bien(dicho) : mal("La fecha y el responsable de una fase los cambia dirección."); }
  catch (e) { aviso = mal(e); }
  navegar();
}
acciones.fechaFase = el => guardaFase(el, { fecha_compromiso: el.value || null }, "Fecha de la fase guardada.");
acciones.responsableFase = el => guardaFase(el, { responsable_id: el.value || null }, "Responsable de la fase guardado.");
formularios.equipo = async (f, form) => { const papeles = papelesDe(f, "n");
  if (!papeles.length) throw new Error("Marque al menos un papel.");
  await pedir(sb.from("acceso_proyecto").insert(papeles.map(papel => ({ persona_id: f.persona, proyecto_id: form.dataset.id, papel })))); aviso = bien("Agregado al equipo."); navegar(); };
formularios.carpeta = async (f, form) => { await pedir(sb.from("proyecto").update({ carpeta_drive: f.carpeta.trim() || null }).eq("id", form.dataset.id)); aviso = bien("Carpeta guardada."); navegar(); };

async function vistaNuevoProyecto(tipo) {
  const [plantillas, personas] = await Promise.all([
    pedir(sb.from("plantilla_proyecto").select("id,nombre,tipo,descripcion,plantilla_fase(fase,orden,opcional)").eq("activa", true)),
    pedir(sb.from("persona").select("id,nombre,rol").eq("es_interno", true).eq("activo", true).order("nombre")),
  ]);
  const orden = ["Diseño", "Peritaje", "Consultoría", "Obra", "Montaje de interiores", "Interno"];
  plantillas.sort((a, b) => orden.indexOf(a.nombre) - orden.indexOf(b.nombre));
  window.__plantillas = plantillas;
  const deObra = tipo === "obra" ? plantillas.find(x => x.tipo === "obra") : null;
  pinta(cabecera(deObra ? "Abrir una obra" : "Crear proyecto nuevo", { atras: deObra ? "#/obras" : "#/proyectos" }) + `<main><form data-form="proyecto">
    <label for="np">Nombre</label><input id="np" name="nombre" required autocomplete="off">
    <label for="co">Código corto</label><input id="co" name="codigo" required autocomplete="off" placeholder="CASA GO" style="text-transform:uppercase">
    <label for="pl">Tipo de proyecto</label><select id="pl" name="plantilla" data-cambia="fasesPlantilla">${plantillas.map(x => `<option value="${x.id}" ${x === deObra ? "selected" : ""}>${h(x.nombre)}</option>`).join("")}</select>
    <label for="un">Unidad de negocio</label><select id="un" name="unidad">${Object.entries(UNIDAD).map(([v, n]) => `<option value="${v}" ${deObra && v === "obra_propia" ? "selected" : ""}>${n}</option>`).join("")}</select>
    <div id="fases"></div>
    <div class="grupo">Equipo</div><p class="nota" style="margin-top:0">Marque uno o varios papeles por persona. Sin ninguno, no participa.</p>${personas.map(x => `<div class="linea"><b>${h(x.nombre)}</b>${casillasPapel(x.id, x.nombre)}</div>`).join("")}
    <label for="ca">Carpeta de Drive (opcional)</label><input id="ca" name="carpeta" type="url" inputmode="url" placeholder="https://drive.google.com/drive/folders/…">
    <button class="btn">Crear el proyecto</button></form></main>`);
  acciones.fasesPlantilla(document.getElementById("pl"));
}
acciones.fasesPlantilla = el => {
  const pl = window.__plantillas.find(x => x.id === el.value), fases = [...pl.plantilla_fase].sort((a, b) => a.orden - b.orden);
  document.getElementById("fases").innerHTML = fases.length ? `<div class="grupo">Horas cotizadas por fase</div>` + fases.map(f =>
    `<div class="linea"><b>${h(titulo(f.fase.replace(/_/g, " ")))}</b>${f.opcional ? `<select name="aplica:${f.fase}" aria-label="¿Aplica?"><option value="si">Aplica</option><option value="no">No aplica</option></select>` : ""}
      <input type="number" name="horas:${f.fase}" min="0" step="1" inputmode="numeric" placeholder="0" aria-label="Horas de ${h(f.fase)}"></div>`).join("")
    : '<p class="nota">Este tipo de proyecto no tiene fases.</p>';
};
formularios.proyecto = async f => {
  const horas = {}, omitir = [], equipo = [];
  for (const [k, v] of Object.entries(f)) {
    if (k.startsWith("aplica:") && v === "no") omitir.push(k.slice(7));
    if (k.startsWith("papel:") && v) { const [, persona_id, papel] = k.split(":"); equipo.push({ persona_id, papel }); }
  }
  for (const [k, v] of Object.entries(f)) if (k.startsWith("horas:") && v && !omitir.includes(k.slice(6))) horas[k.slice(6)] = Number(v);
  const id = await pedir(sb.rpc("abrir_proyecto", { p_codigo: f.codigo.trim().toUpperCase(), p_nombre: f.nombre.trim(), p_plantilla: f.plantilla, p_unidad: f.unidad,
    p_horas: horas, p_equipo: equipo, p_omitir: omitir }));
  if (f.carpeta.trim()) await pedir(sb.from("proyecto").update({ carpeta_drive: f.carpeta.trim() }).eq("id", id));
  yo = await pedir(sb.rpc("mi_sesion"));
  if (window.__plantillas.find(x => x.id === f.plantilla)?.tipo === "obra") return ir(`#/obra/${id}`, bien("Obra abierta. Escriba el valor del contrato, el residente y las fechas."));
  ir(`#/proyecto/${id}`, bien("Proyecto abierto con sus fases y su equipo."));
};

// ---------- obra ----------
// El tablero de todas las obras y la ficha de cada una, con sus espacios en
// pestañas. La plata, las alertas y las frases las calcula la base
// (v_obra_tablero); aquí se pintan. Quién registra y quién aprueba también lo
// decide la base: el residente registra en su obra, dirección aprueba.
const SECCION_OBRA = [["resumen", "Resumen"], ["gastos", "Gastos y facturas"], ["flujo", "Flujo de caja"], ["documentos", "Documentos"], ["pendientes", "Pendientes"], ["sitio", "Registro en sitio"]];
const ESTADO_DINERO = { compromiso: "Comprometido", causacion: "Facturado, por pagar", pago: "Pagado" };
const MEDIO = { banco: "Transferencia o consignación", efectivo: "Efectivo", tarjeta: "Tarjeta", credito: "Crédito" };
const TIPO_DOC = { contrato: "Contrato", presupuesto: "Presupuesto", planos: "Planos", licencia: "Licencia", poliza: "Póliza", acta: "Acta", factura: "Factura", informe: "Informe", otro: "Otro" };
const TIPO_PEND = { ejecucion: "Ejecución", tramite: "Trámite", revision: "Revisión", compra: "Compra" };
const ESTADO_PEND = { abierto: "Abierto", en_ejecucion: "En ejecución", por_verificar: "Hecho, falta verificar", cerrado: "Cerrado", descartado: "Descartado" };
const CLIMA = ["Soleado", "Nublado", "Lluvia en la mañana", "Lluvia en la tarde", "Lluvia todo el día"];
const plata = v => Math.round(Number(String(v ?? "").replace(/[^\d]/g, "")) || 0);   // «1.250.000» → 1250000
const mesLargo = iso => `${titulo(MESES[+iso.slice(5, 7) - 1])} de ${iso.slice(0, 4)}`;
const cifra = (t, v, sub = "", mal = false) => `<div class="cifra"><small>${h(t)}</small><b${mal ? ' class="c"' : ""}>${h(v)}</b>${sub ? `<span>${h(sub)}</span>` : ""}</div>`;
const nombresDe = async ids => { ids = [...new Set(ids.filter(Boolean))];
  return new Map(ids.length ? (await pedir(sb.from("persona").select("id,nombre").in("id", ids))).map(p => [p.id, p.nombre]) : []); };
let trasPintar = null;   // lo que una sección hace cuando ya está en pantalla (leer Drive)

async function vistaObras() {
  const obras = await pedir(sb.from("v_obra_tablero").select("*").order("estado").order("nombre"));
  const conAlerta = obras.filter(o => o.alerta), activas = obras.filter(o => o.estado === "activo").length;
  const suma = k => obras.reduce((s, o) => s + Number(o[k] || 0), 0);
  const frase = !obras.length ? "" : conAlerta.length ? `${conAlerta.length === 1 ? "Una obra tiene" : conAlerta.length + " obras tienen"} algo que mover hoy.` : "Todas las obras están al día.";
  pinta(cabecera("Obras", { sobre: obras.length ? uno(activas, "Una obra en curso", "obras en curso") : "" }) + `<main>
    ${frase ? `<p class="frase">${h(frase)}</p>` : ""}
    ${yo.ve_dinero && obras.length > 1 ? `<p style="color:var(--tinta-3)">Entre todas llevan ${pesos(suma("costo_proyectado"))} en gastos y deben ${pesos(suma("por_pagar"))}.</p>` : ""}
    ${obras.map(o => `<a class="fila" href="#/obra/${o.id}"><b>${h(o.nombre)}${o.estado === "pausado" ? '<span class="marca n">En pausa</span>' : ""}</b>
      ${o.alerta ? `<span><em>${h(o.alerta)}</em></span>` : ""}<span>${h(o.lectura)}</span>
      <span>${o.residente ? "Residente: " + h(o.residente) : "Sin residente"} · ${o.ultima_bitacora ? "última bitácora el " + h(fecha(o.ultima_bitacora)) : "sin bitácora"}</span></a>`).join("")
      || `<p class="vacio">${yo.es_direccion ? "Todavía no hay obras. Abra la primera con el botón de abajo." : "Todavía no hace parte de ninguna obra."}</p>`}
    ${yo.es_direccion ? '<a class="btn" href="#/nuevo-proyecto/obra">Abrir una obra</a>' : ""}</main>` + pie("#/obras"));
}

async function vistaObra(id, sec = "resumen") {
  const o = await pedir(sb.from("v_obra_tablero").select("*").eq("id", id).maybeSingle());
  if (!o) return pinta(cabecera("Obra", { atras: "#/obras" }) + '<main><p class="vacio">Esa obra no existe, ya terminó o usted no hace parte de ella.</p></main>' + pie("#/obras"));
  if (!OBRA[sec]) sec = "resumen";
  trasPintar = null;
  const cuerpo = await OBRA[sec](o, yo.registra.includes(id));
  pinta(cabecera(o.nombre, { sobre: `Obra · ${o.codigo}`, atras: "#/obras" }) +
    `<nav class="pestanas" aria-label="Espacios de la obra"><div>${SECCION_OBRA.map(([k, n]) => `<a href="#/obra/${id}/${k}" ${k === sec ? 'aria-current="page"' : ""}>${n}</a>`).join("")}</div></nav>
    <main>${cuerpo}</main>` + pie("#/obras"));
  document.querySelector('.pestanas [aria-current="page"]')?.scrollIntoView({ inline: "center", block: "nearest" });
  trasPintar?.();
}

const OBRA = {
  // Cómo va la plata, en qué se fue y lo que hay que mover.
  async resumen(o) {
    const [cats, gente] = await Promise.all([
      pedir(sb.from("v_balance_centro_costo").select("categoria,presupuesto,proyectado,por_pagar,excluir_de_rentabilidad").eq("proyecto_id", o.id)),
      yo.es_direccion ? pedir(sb.from("persona").select("id,nombre").eq("es_interno", true).eq("activo", true).order("nombre")) : [],
    ]);
    const usadas = cats.filter(c => !c.excluir_de_rentabilidad && (Number(c.proyectado) || Number(c.presupuesto))).sort((a, b) => b.proyectado - a.proyectado);
    const caja = Number(o.cobrado) - Number(o.pagado);
    const mover = [
      o.gastos_por_aprobar ? [`${o.id}/gastos`, uno(o.gastos_por_aprobar, "Un gasto espera aprobación", "gastos esperan aprobación"), `${pesos(o.valor_por_aprobar)} en total`, true] : null,
      o.pendientes_abiertos ? [`${o.id}/pendientes`, uno(o.pendientes_abiertos, "Un pendiente abierto", "pendientes abiertos"),
        o.pendientes_vencidos ? (o.pendientes_vencidos === 1 ? "Uno ya pasó su fecha" : `${o.pendientes_vencidos} ya pasaron su fecha`) : "Ninguno ha pasado su fecha", o.pendientes_vencidos > 0] : null,
      o.estado === "activo" && o.dias_sin_bitacora ? [`${o.id}/sitio`, `${uno(o.dias_sin_bitacora, "Un día", "días")} de obra sin bitácora`, "En el último mes, de lunes a sábado", o.dias_sin_bitacora >= 3] : null,
      o.adicionales_pendientes ? [null, uno(o.adicionales_pendientes, "Un adicional espera al cliente", "adicionales esperan al cliente"), "El cliente los aprueba desde su portal", false] : null,
    ].filter(Boolean);
    return `<p class="frase">${h(o.lectura)}</p>${o.alerta ? `<div class="error" role="status">${h(o.alerta)}</div>` : ""}
      <div class="grupo">La plata</div><div class="cifras">
        ${cifra("Contrato", o.valor_contrato ? pesos(o.valor_contrato) : "Sin escribir")}
        ${cifra("Gastado", pesos(o.costo_proyectado), o.pct_contrato != null ? `${o.pct_contrato} % del contrato` : "")}
        ${cifra("Pagado", pesos(o.pagado))}
        ${cifra("Por pagar", pesos(o.por_pagar))}
        ${yo.ve_dinero ? cifra("Cobrado al cliente", pesos(o.cobrado)) + cifra("Caja de la obra", pesos(caja), caja < 0 ? "Se ha pagado más de lo cobrado" : "Lo cobrado menos lo pagado", caja < 0) : ""}
      </div>
      <div class="grupo">Lo que hay que mover</div>
      ${mover.map(([r, t, s, mal]) => `${r ? `<a class="fila" href="#/obra/${r}">` : '<div class="fila">'}<b>${h(t)}</b><span>${mal ? `<em>${h(s)}</em>` : h(s)}</span>${r ? "</a>" : "</div>"}`).join("") || '<p class="vacio" style="padding:14px 0">Nada pendiente.</p>'}
      ${usadas.length ? `<div class="grupo">En qué se ha ido</div>${usadas.map(c => `<div class="fila"><b>${h(titulo(c.categoria))}</b><span>${pesos(c.proyectado)}${Number(c.presupuesto) ? ` de ${pesos(c.presupuesto)} presupuestados${Number(c.proyectado) > Number(c.presupuesto) ? " · <em>se pasó</em>" : ""}` : ""}${Number(c.por_pagar) ? ` · debe ${pesos(c.por_pagar)}` : ""}</span></div>`).join("")}` : ""}
      ${yo.es_direccion ? `<div class="grupo">Datos de la obra</div><form data-form="datosObra" data-id="${o.id}">
          <label for="vc">Valor del contrato</label><input id="vc" name="contrato" inputmode="numeric" autocomplete="off" value="${o.valor_contrato ? h(Number(o.valor_contrato).toLocaleString("es-CO")) : ""}" placeholder="0">
          <label for="re">Residente</label><select id="re" name="residente"><option value="">Sin residente</option>${gente.map(x => `<option value="${x.id}" ${x.id === o.residente_id ? "selected" : ""}>${h(x.nombre)}</option>`).join("")}</select>
          <div class="dos"><div><label for="fi">Empezó el</label><input id="fi" name="inicio" type="date" value="${h(o.fecha_inicio || "")}"></div>
            <div><label for="ff">Se entrega el</label><input id="ff" name="fin" type="date" value="${h(o.fecha_fin_prevista || "")}"></div></div>
          <label for="es">Estado</label><select id="es" name="estado">${opciones({ activo: "En curso", pausado: "En pausa", terminado: "Terminada" }, o.estado)}</select>
          <button class="btn claro">Guardar los datos</button></form>`
        : `<div class="grupo">Datos de la obra</div><div class="fila"><b>${o.residente ? h(o.residente) : "Sin residente"}</b><span>Residente${o.fecha_inicio ? " · empezó el " + h(fecha(o.fecha_inicio)) : ""}${o.fecha_fin_prevista ? " · se entrega el " + h(fecha(o.fecha_fin_prevista)) : ""}</span></div>`}`;
  },

  // Registrar un gasto, aprobar lo que pasa del umbral, pagar lo facturado.
  async gastos(o, registra) {
    const [porAprobar, porPagar, ultimos, cats, par] = await Promise.all([
      pedir(sb.from("v_movimiento_vigente").select("id,fecha,valor,tercero_id,tercero_nombre,concepto,numero_factura,registrado_por").eq("proyecto_id", o.id).eq("aprobacion", "pendiente").order("fecha")),
      pedir(sb.from("v_obra_por_pagar").select("*").eq("proyecto_id", o.id).order("fecha_prevista")),
      pedir(sb.from("v_movimiento_vigente").select("id,fecha,estado,naturaleza,valor,tercero_id,tercero_nombre,concepto,numero_factura,aprobacion").eq("proyecto_id", o.id).order("fecha", { ascending: false }).order("registrado_en", { ascending: false }).limit(25)),
      registra ? pedir(sb.from("categoria_costo").select("id,nombre,tipo_gasto").eq("activo", true).order("orden").order("nombre")) : [],
      registra ? pedir(sb.from("parametro").select("umbral_aprobacion").maybeSingle()) : null,
    ]);
    const quien = await nombresDe([...porAprobar, ...ultimos].flatMap(m => [m.tercero_id, m.registrado_por]));
    const tercero = m => m.tercero_nombre || quien.get(m.tercero_id) || "Sin tercero";
    const hoy = hoyIso(), deObra = cats.filter(c => c.tipo_gasto === "COSTOS OPERATIVOS"), otras = cats.filter(c => c.tipo_gasto !== "COSTOS OPERATIVOS");
    return `${registra ? `<details ${ultimos.length ? "" : "open"}><summary class="btn">Registrar un gasto</summary><form data-form="gasto" data-id="${o.id}">
        <label for="ge">Qué pasó</label><select id="ge" name="estado">${opciones({ causacion: "Llegó la factura y falta pagarla", pago: "Ya se pagó", compromiso: "Quedó comprometido (orden o cotización aceptada)" })}</select>
        <label for="gc">Categoría</label><select id="gc" name="categoria" required>${cats.length ? "" : '<option value="">Falta cargar las categorías</option>'}
          ${deObra.length ? `<optgroup label="De la obra">${deObra.map(c => `<option value="${c.id}">${h(titulo(c.nombre))}</option>`).join("")}</optgroup>` : ""}
          ${otras.length ? `<optgroup label="Otras">${otras.map(c => `<option value="${c.id}">${h(titulo(c.nombre))}</option>`).join("")}</optgroup>` : ""}</select>
        <label for="gv">Valor</label><input id="gv" name="valor" inputmode="numeric" autocomplete="off" required placeholder="0">
        <label for="gt">A quién se le paga</label><input id="gt" name="tercero" required autocomplete="off" placeholder="Proveedor o contratista">
        <label for="gq">Qué se compró o qué trabajo fue</label><input id="gq" name="concepto" required autocomplete="off">
        <label for="gf">Número de la factura (si la hay)</label><input id="gf" name="factura" autocomplete="off">
        <label for="gm">Con qué se pagó</label><select id="gm" name="medio"><option value="no_aplica">Todavía no se ha pagado</option>${opciones(MEDIO)}</select>
        <div class="dos"><div><label for="gd">Fecha</label><input id="gd" name="fecha" type="date" value="${hoy}" max="${hoy}"></div>
          <div><label for="gp">Se paga el</label><input id="gp" name="prevista" type="date"></div></div>
        ${par ? `<p class="nota">Si el valor llega a ${pesos(par.umbral_aprobacion)} o más, el gasto queda esperando la aprobación de dirección antes de pagarse.</p>` : ""}
        <button class="btn">Guardar el gasto</button></form></details>` : ""}

      ${porAprobar.length ? `<div class="grupo c">Esperan aprobación</div>${porAprobar.map(m => `<div class="fila"><b>${h(tercero(m))} · ${pesos(m.valor)}</b>
        <span>${h(m.concepto)}${m.numero_factura ? " · factura " + h(m.numero_factura) : ""} · lo registró ${h(quien.get(m.registrado_por) || "alguien")} el ${h(fecha(m.fecha))}</span>
        ${yo.es_direccion ? `<div class="par"><button class="btn" data-accion="aprobarGasto" data-id="${m.id}">Aprobar</button><button class="btn peligro" data-accion="rechazarGasto" data-id="${m.id}">Rechazar</button></div>` : "<span>Espera a dirección.</span>"}</div>`).join("")}` : ""}

      <div class="grupo">Por pagar</div>
      ${porPagar.map(p => `<div class="fila"><b>${h(p.tercero || "Sin tercero")} · ${pesos(p.por_pagar)}</b>
        <span>${h(p.concepto)}${p.numero_factura ? " · factura " + h(p.numero_factura) : p.facturado ? "" : " · sin factura todavía"} · ${p.fecha_prevista < hoyIso() ? `<em>se debía pagar el ${h(fecha(p.fecha_prevista))}</em>` : "se paga el " + h(fecha(p.fecha_prevista))}${p.aprobacion === "pendiente" ? " · espera aprobación" : ""}</span>
        ${registra && p.aprobacion !== "pendiente" ? `<details><summary class="enlace">Registrar el pago</summary><form data-form="pagoGasto" data-id="${o.id}">
          <input type="hidden" name="raiz" value="${p.raiz_id}"><input type="hidden" name="cc" value="${p.centro_costo_id}"><input type="hidden" name="valor" value="${p.por_pagar}">
          <input type="hidden" name="tercero" value="${h(p.tercero || "Sin tercero")}"><input type="hidden" name="concepto" value="${h(p.concepto)}">
          <div class="dos"><div><label for="pm${p.raiz_id}">Con qué</label><select id="pm${p.raiz_id}" name="medio">${opciones(MEDIO)}</select></div>
            <div><label for="pd${p.raiz_id}">El día</label><input id="pd${p.raiz_id}" name="fecha" type="date" value="${hoy}" max="${hoy}"></div></div>
          <button class="btn claro">Pagado: ${pesos(p.por_pagar)}</button></form></details>` : ""}</div>`).join("") || '<p class="vacio" style="padding:14px 0">Nada por pagar.</p>'}

      <div class="grupo">Últimos movimientos</div>
      ${ultimos.map(m => `<div class="fila"><b>${h(tercero(m))} · ${m.naturaleza === "devolucion" ? "−" : ""}${pesos(m.valor)}</b>
        <span>${h(m.concepto)} · ${h(m.naturaleza === "devolucion" ? "Devolución" : ESTADO_DINERO[m.estado])}${m.numero_factura ? " · factura " + h(m.numero_factura) : ""} · ${h(fecha(m.fecha))}${m.aprobacion === "pendiente" ? '<span class="marca a">Por aprobar</span>' : m.aprobacion === "aprobado" ? '<span class="marca o">Aprobado</span>' : ""}</span></div>`).join("") || '<p class="vacio" style="padding:14px 0">Todavía no hay gastos registrados.</p>'}`;
  },

  // Lo que sale y lo que entra, mes a mes, y lo que viene por pagar.
  async flujo(o) {
    const [meses, porPagar] = await Promise.all([
      pedir(sb.from("v_obra_flujo_mes").select("*").eq("proyecto_id", o.id).order("mes")),
      pedir(sb.from("v_obra_por_pagar").select("tercero,concepto,por_pagar,fecha_prevista,aprobacion").eq("proyecto_id", o.id).order("fecha_prevista")),
    ]);
    let acum = 0;
    const filas = meses.map(m => ({ ...m, caja: (acum += Number(m.cobrado) - Number(m.pagado)) })).reverse().slice(0, 12);
    const tres = meses.slice(-3), salio = tres.reduce((s, m) => s + Number(m.pagado), 0), entro = tres.reduce((s, m) => s + Number(m.cobrado), 0);
    const hoy = hoyIso(), en28 = new Date(Date.now() + 28 * 864e5).toISOString().slice(0, 10);
    const vencido = porPagar.filter(p => p.fecha_prevista < hoy), pronto = porPagar.filter(p => p.fecha_prevista >= hoy && p.fecha_prevista <= en28), despues = porPagar.filter(p => p.fecha_prevista > en28);
    const total = a => pesos(a.reduce((s, p) => s + Number(p.por_pagar), 0));
    const lista = a => a.map(p => `<div class="fila"><b>${h(p.tercero || "Sin tercero")} · ${pesos(p.por_pagar)}</b><span>${h(p.concepto)} · ${h(fecha(p.fecha_prevista))}${p.aprobacion === "pendiente" ? " · espera aprobación" : ""}</span></div>`).join("");
    return `${meses.length ? `<p class="frase">En los últimos ${uno(tres.length, "mes", "meses")} salieron ${pesos(salio)}${yo.ve_dinero ? ` y entraron ${pesos(entro)}` : ""}.</p>` : '<p class="vacio">Todavía no hay pagos ni cobros en esta obra.</p>'}
      ${porPagar.length ? `<div class="grupo">Lo que viene por pagar</div>
        ${vencido.length ? `<div class="grupo c">Ya debía estar pagado · ${total(vencido)}</div>${lista(vencido)}` : ""}
        ${pronto.length ? `<div class="grupo a">Próximas cuatro semanas · ${total(pronto)}</div>${lista(pronto)}` : ""}
        ${despues.length ? `<div class="grupo">Después · ${total(despues)}</div>${lista(despues)}` : ""}` : ""}
      ${filas.length ? `<div class="grupo">Mes a mes</div>${filas.map(m => `<div class="fila"><b>${h(mesLargo(m.mes))}</b>
        <span>Salieron ${pesos(m.pagado)} en ${uno(Number(m.pagos), "un pago", "pagos")}${yo.ve_dinero ? ` · entraron ${pesos(m.cobrado)}` : ""}</span>
        ${yo.ve_dinero ? `<span>${m.caja < 0 ? `<em>Caja acumulada: ${pesos(m.caja)}</em>` : `Caja acumulada: ${pesos(m.caja)}`}</span>` : ""}</div>`).join("")}` : ""}
      ${yo.ve_dinero ? `<details><summary class="btn claro">Registrar un cobro recibido</summary><form data-form="cobro" data-id="${o.id}">
          <label for="cv">Valor</label><input id="cv" name="valor" inputmode="numeric" autocomplete="off" required placeholder="0">
          <label for="cq">Concepto</label><input id="cq" name="concepto" required autocomplete="off" placeholder="Anticipo, acta 3…">
          <label for="cd">Fecha</label><input id="cd" name="fecha" type="date" value="${hoy}" max="${hoy}">
          <label for="ca">Es anticipo</label><select id="ca" name="anticipo"><option value="no">No</option><option value="si">Sí</option></select>
          <button class="btn">Guardar el cobro</button></form></details>` : ""}`;
  },

  // La carpeta de Drive y el índice de lo importante: contrato, planos, pólizas.
  async documentos(o, registra) {
    const docs = await pedir(sb.from("documento_obra").select("id,tipo,titulo,enlace,fecha,registrado_por,registrado_en").eq("proyecto_id", o.id).is("retirado_en", null).order("registrado_en", { ascending: false }));
    const quien = await nombresDe(docs.map(d => d.registrado_por));
    if (o.carpeta_drive) trasPintar = () => pintaDrive(o.carpeta_drive);
    const porTipo = Object.keys(TIPO_DOC).map(t => [t, docs.filter(d => d.tipo === t)]).filter(([, a]) => a.length);
    return `<div class="grupo">Lo importante</div>
      ${porTipo.map(([t, a]) => a.map(d => `<div class="fila"><a href="${h(d.enlace)}" target="_blank" rel="noopener" class="doc"><b>${h(d.titulo)} ›</b></a>
        <span>${h(TIPO_DOC[t])}${d.fecha ? " · del " + h(fecha(d.fecha)) : ""} · lo puso ${h(quien.get(d.registrado_por) || "alguien")}</span>
        ${yo.es_direccion || d.registrado_por === yo.persona_id ? `<button class="enlace" data-accion="retirarDocumento" data-id="${d.id}">Retirar</button>` : ""}</div>`).join("")).join("")
        || '<p class="vacio" style="padding:14px 0">Todavía no hay documentos en el índice. Ponga aquí el contrato, el presupuesto, los planos, la licencia y las pólizas.</p>'}
      ${registra ? `<details><summary class="btn claro">Agregar un documento</summary><form data-form="documento" data-id="${o.id}">
          <label for="dt">Qué es</label><select id="dt" name="tipo">${opciones(TIPO_DOC)}</select>
          <label for="dn">Nombre</label><input id="dn" name="titulo" required minlength="3" autocomplete="off" placeholder="Contrato de obra firmado">
          <label for="de">Enlace de Drive</label><input id="de" name="enlace" type="url" inputmode="url" required placeholder="https://drive.google.com/…">
          <label for="df">Fecha del documento</label><input id="df" name="fecha" type="date">
          <button class="btn">Agregar al índice</button></form></details>` : ""}
      <div class="grupo">Carpeta de Drive</div><div id="drive">${o.carpeta_drive ? "" : '<p class="vacio" style="padding:14px 0">Esta obra todavía no tiene su carpeta de Drive.</p>'}</div>
      ${yo.es_direccion ? `<form data-form="carpeta" data-id="${o.id}"><label for="cdr">Enlace de la carpeta de Drive</label>
        <input id="cdr" name="carpeta" type="url" inputmode="url" placeholder="https://drive.google.com/drive/folders/…" value="${h(o.carpeta_drive || "")}">
        <button class="btn claro">Guardar la carpeta</button></form>` : ""}`;
  },

  // Remates, trámites y compras: quien lo hace no es quien lo verifica.
  async pendientes(o, registra) {
    const [abiertos, cerrados, equipo] = await Promise.all([
      pedir(sb.from("pendiente_obra").select("id,titulo,tipo,prioridad,ubicacion,estado,fecha_compromiso,responsable_id,ejecutor_id,creado_por").eq("proyecto_id", o.id).not("estado", "in", "(cerrado,descartado)").order("fecha_compromiso", { nullsFirst: false })),
      pedir(sb.from("pendiente_obra").select("id,titulo,verificado_en,verificado_por").eq("proyecto_id", o.id).eq("estado", "cerrado").order("verificado_en", { ascending: false }).limit(5)),
      registra ? asignables(o.id) : new Map(),
    ]);
    const quien = await nombresDe([...abiertos.flatMap(p => [p.responsable_id, p.ejecutor_id]), ...cerrados.map(p => p.verificado_por)]);
    const peso = { bloqueante: 0, alta: 1, normal: 2 };
    abiertos.sort((a, b) => peso[a.prioridad] - peso[b.prioridad]);
    const hoy = hoyIso(), gente = [...equipo].sort((a, b) => a[1].localeCompare(b[1]));
    return `${registra ? `<details ${abiertos.length ? "" : "open"}><summary class="btn">Nuevo pendiente</summary><form data-form="pendiente" data-id="${o.id}">
        <label for="pt">Qué hay que hacer</label><input id="pt" name="titulo" required minlength="4" autocomplete="off" placeholder="Instalar el lavamanos del baño social">
        <div class="dos"><div><label for="py">Tipo</label><select id="py" name="tipo">${opciones(TIPO_PEND)}</select></div>
          <div><label for="pp">Prioridad</label><select id="pp" name="prioridad">${opciones({ normal: "Normal", alta: "Alta", bloqueante: "Frena a otros" })}</select></div></div>
        <label for="pu">Dónde</label><input id="pu" name="ubicacion" autocomplete="off" placeholder="Cocina, baño social, fachada…">
        <label for="pr">Responde</label><select id="pr" name="responsable" required>${gente.map(([pid, n]) => `<option value="${pid}" ${pid === yo.persona_id ? "selected" : ""}>${h(n)}</option>`).join("")}</select>
        <label for="pe">Lo hace (si es otra persona)</label><select id="pe" name="ejecutor"><option value="">La misma persona</option>${gente.map(([pid, n]) => `<option value="${pid}">${h(n)}</option>`).join("")}</select>
        <label for="pf">Para cuándo</label><input id="pf" name="fecha" type="date" min="${hoy}">
        <button class="btn">Crear el pendiente</button></form></details>` : ""}
      <div class="grupo">Abiertos</div>
      ${abiertos.map(p => { const hizo = p.ejecutor_id || p.responsable_id, mio = [p.responsable_id, p.ejecutor_id, p.creado_por].includes(yo.persona_id);
        return `<div class="fila"><b>${h(p.titulo)}${marca(p.prioridad)}</b>
          <span>${h(TIPO_PEND[p.tipo])}${p.ubicacion ? " · " + h(p.ubicacion) : ""} · responde ${h(quien.get(p.responsable_id) || "alguien")}${p.ejecutor_id ? " · lo hace " + h(quien.get(p.ejecutor_id) || "alguien") : ""}</span>
          <span>${h(ESTADO_PEND[p.estado])}${p.fecha_compromiso ? ` · ${p.fecha_compromiso < hoy ? `<em>era para el ${h(fecha(p.fecha_compromiso))}</em>` : "para el " + h(fecha(p.fecha_compromiso))}` : ""}</span>
          ${p.estado === "por_verificar" ? (hizo !== yo.persona_id && registra ? `<button class="btn claro" data-accion="verificarPendiente" data-id="${p.id}">Verifiqué que quedó hecho</button>` : "<span>Lo verifica alguien distinto de quien lo hizo.</span>")
            : mio || yo.es_direccion ? `<button class="btn claro" data-accion="pendienteHecho" data-id="${p.id}">Ya quedó hecho</button>` : ""}
          ${yo.es_direccion || p.responsable_id === yo.persona_id ? `<details><summary class="enlace">Descartarlo</summary><form data-form="descartar" data-id="${p.id}">
            <label for="dr${p.id}">Por qué ya no se hace</label><input id="dr${p.id}" name="razon" required autocomplete="off"><button class="btn peligro">Descartar</button></form></details>` : ""}</div>`; }).join("")
        || '<p class="vacio" style="padding:14px 0">Ningún pendiente abierto.</p>'}
      ${cerrados.length ? `<div class="grupo">Cerrados hace poco</div>${cerrados.map(p => `<div class="fila"><b>${h(p.titulo)}</b><span>Lo verificó ${h(quien.get(p.verificado_por) || "alguien")} el ${h(fecha(p.verificado_en))}</span></div>`).join("")}` : ""}`;
  },

  // La bitácora del día: quiénes estaban, en qué frente, qué avanzó, qué pasó.
  async sitio(o, registra) {
    const [dias, faltan] = await Promise.all([
      pedir(sb.from("bitacora").select("id,fecha,personal_sitio,frente_trabajo,avance,novedad,clima,registrado_por").eq("proyecto_id", o.id).order("fecha", { ascending: false }).limit(10)),
      pedir(sb.from("v_bitacora_faltante").select("fecha").eq("proyecto_id", o.id).order("fecha", { ascending: false })),
    ]);
    const quien = await nombresDe(dias.map(d => d.registrado_por));
    const hoy = hoyIso(), deHoy = dias.find(d => d.fecha === hoy);
    return `${faltan.length ? `<div class="${faltan.length >= 3 ? "error" : "nota"}" role="status">${faltan.length === 1 ? "Falta la bitácora del " + h(fecha(faltan[0].fecha)) : `Faltan ${faltan.length} días de bitácora en el último mes: ${h(lista(faltan.slice(0, 6).map(f => corta(f.fecha))))}${faltan.length > 6 ? "…" : ""}`}.</div>` : ""}
      ${registra ? `<details ${deHoy ? "" : "open"}><summary class="btn${deHoy ? " claro" : ""}">${deHoy ? "Registrar otro día" : "Bitácora de hoy"}</summary><form data-form="bitacora" data-id="${o.id}">
          <label for="bd">Día</label><input id="bd" name="fecha" type="date" value="${deHoy ? (faltan[0]?.fecha || "") : hoy}" max="${hoy}" required>
          <div class="dos"><div><label for="bp">Personas en obra</label><input id="bp" name="personal" type="number" min="0" inputmode="numeric" placeholder="0"></div>
            <div><label for="bc">Clima</label><select id="bc" name="clima"><option value="">Sin anotar</option>${CLIMA.map(c => `<option>${c}</option>`).join("")}</select></div></div>
          <label for="bf">Frente de trabajo</label><input id="bf" name="frente" autocomplete="off" placeholder="Mampostería segundo piso">
          <label for="ba">Qué avanzó</label><textarea id="ba" name="avance"></textarea>
          <label for="bn">Novedades (si hubo)</label><textarea id="bn" name="novedad" placeholder="Llegó tarde el material, visita del cliente…"></textarea>
          <button class="btn">Guardar la bitácora</button></form></details>` : ""}
      <div class="grupo">Últimos días</div>
      ${dias.map(d => `<div class="fila"><b>${h(titulo(SEMANA[new Date(d.fecha + "T12:00").getDay()]))} ${h(fecha(d.fecha))}${d.personal_sitio != null ? ` · ${uno(d.personal_sitio, "una persona", "personas")}` : ""}</b>
        <span>${[d.frente_trabajo, d.clima].filter(Boolean).map(h).join(" · ")}</span>${d.avance ? `<span>${h(d.avance)}</span>` : ""}${d.novedad ? `<span><em>${h(d.novedad)}</em></span>` : ""}
        <span>La escribió ${h(quien.get(d.registrado_por) || "alguien")}</span></div>`).join("") || '<p class="vacio" style="padding:14px 0">Todavía no hay bitácora en esta obra.</p>'}`;
  },
};

formularios.datosObra = async (f, form) => {
  const id = form.dataset.id;
  await pedir(sb.from("proyecto").update({ valor_contrato: plata(f.contrato) || null, residente_id: f.residente || null,
    fecha_inicio: f.inicio || null, fecha_fin_prevista: f.fin || null, estado: f.estado }).eq("id", id));
  // El residente queda en el equipo de la obra para poder registrar en ella.
  if (f.residente) {
    const ya = await pedir(sb.from("acceso_proyecto").select("persona_id").eq("proyecto_id", id).eq("persona_id", f.residente));
    if (!ya.length) await pedir(sb.from("acceso_proyecto").insert({ persona_id: f.residente, proyecto_id: id, papel: "produce", nivel: "registro" }));
  }
  ir(`#/obra/${id}`, bien("Datos de la obra guardados."));
};
formularios.gasto = async (f, form) => {
  const id = form.dataset.id;
  const gid = await pedir(sb.rpc("registrar_gasto", { p_datos: { proyecto_id: id, categoria_id: f.categoria, estado: f.estado, valor: plata(f.valor),
    tercero: f.tercero, concepto: f.concepto, numero_factura: f.factura, medio: f.medio, fecha: f.fecha, fecha_prevista_pago: f.prevista } }));
  const [m] = await pedir(sb.from("movimiento").select("aprobacion").eq("id", gid));
  ir(`#/obra/${id}/gastos`, bien(m?.aprobacion === "pendiente" ? "Gasto guardado. Como llega al umbral, espera la aprobación de dirección antes de pagarse." : "Gasto guardado."));
};
async function decidirGasto(el, decision) {
  if (decision === "rechazado" && !confirm("¿Rechazar este gasto? La decisión queda registrada y no se cambia.")) return;
  const r = await pedir(sb.from("movimiento").update(decision === "aprobado" ? { aprobacion: decision, aprobado_por: yo.persona_id, aprobado_en: new Date().toISOString() } : { aprobacion: decision })
    .eq("id", el.dataset.id).select("id"));
  aviso = r.length ? bien(decision === "aprobado" ? "Gasto aprobado: ya se puede pagar." : "Gasto rechazado.") : mal("Solo dirección decide sobre un gasto.");
  navegar();
}
acciones.aprobarGasto = el => decidirGasto(el, "aprobado");
acciones.rechazarGasto = el => decidirGasto(el, "rechazado");
formularios.pagoGasto = async (f, form) => {
  await pedir(sb.from("movimiento").insert({ proyecto_id: form.dataset.id, centro_costo_id: f.cc, estado: "pago", origen_id: f.raiz, valor: Number(f.valor),
    tercero_nombre: f.tercero, concepto: f.concepto, medio: f.medio, fecha: f.fecha || hoyIso(), registrado_por: yo.persona_id }));
  ir(`#/obra/${form.dataset.id}/gastos`, bien("Pago registrado."));
};
formularios.cobro = async (f, form) => {
  if (!plata(f.valor)) throw new Error("Escriba el valor del cobro.");
  await pedir(sb.from("ingreso").insert({ proyecto_id: form.dataset.id, valor: plata(f.valor), linea: "obra_civil", concepto: f.concepto.trim(),
    fecha: f.fecha || hoyIso(), es_anticipo: f.anticipo === "si", registrado_por: yo.persona_id }));
  ir(`#/obra/${form.dataset.id}/flujo`, bien("Cobro registrado."));
};
formularios.documento = async (f, form) => {
  if (!/^https:\/\//.test(f.enlace.trim())) throw new Error("El enlace debe empezar por https://, como los de Drive.");
  await pedir(sb.from("documento_obra").insert({ proyecto_id: form.dataset.id, tipo: f.tipo, titulo: f.titulo.trim(), enlace: f.enlace.trim(), fecha: f.fecha || null, registrado_por: yo.persona_id }));
  ir(`#/obra/${form.dataset.id}/documentos`, bien("Documento agregado al índice."));
};
acciones.retirarDocumento = async el => {
  if (!confirm("¿Retirar este documento del índice? El archivo sigue en Drive.")) return;
  const r = await pedir(sb.from("documento_obra").update({ retirado_en: new Date().toISOString() }).eq("id", el.dataset.id).select("id"));
  aviso = r.length ? bien("Documento retirado del índice.") : mal("Lo retira dirección o quien lo puso."); navegar();
};
formularios.pendiente = async (f, form) => {
  await pedir(sb.from("pendiente_obra").insert({ proyecto_id: form.dataset.id, titulo: f.titulo.trim(), tipo: f.tipo, prioridad: f.prioridad,
    ubicacion: f.ubicacion.trim() || null, responsable_id: f.responsable, ejecutor_id: f.ejecutor || null, fecha_compromiso: f.fecha || null, creado_por: yo.persona_id }));
  ir(`#/obra/${form.dataset.id}/pendientes`, bien("Pendiente creado."));
};
async function cambiaPendiente(id, cambio, dicho) {
  const r = await pedir(sb.from("pendiente_obra").update(cambio).eq("id", id).select("id"));
  aviso = r.length ? bien(dicho) : mal("Ese pendiente lo mueve quien responde por él, quien lo hace o dirección."); navegar();
}
acciones.pendienteHecho = el => cambiaPendiente(el.dataset.id, { estado: "por_verificar" }, "Marcado como hecho. Falta que otra persona lo verifique.");
acciones.verificarPendiente = el => cambiaPendiente(el.dataset.id, { verificado_por: yo.persona_id }, "Verificado y cerrado.");
formularios.descartar = (f, form) => cambiaPendiente(form.dataset.id, { estado: "descartado", descartado_porque: f.razon.trim() }, "Pendiente descartado.");
formularios.bitacora = async (f, form) => {
  const { error } = await sb.from("bitacora").insert({ proyecto_id: form.dataset.id, fecha: f.fecha, personal_sitio: f.personal === "" ? null : Number(f.personal),
    frente_trabajo: f.frente.trim() || null, avance: f.avance.trim() || null, novedad: f.novedad.trim() || null, clima: f.clima || null, registrado_por: yo.persona_id });
  if (error) throw /duplicate key/i.test(error.message) ? new Error(`Ya hay bitácora del ${fecha(f.fecha)} en esta obra.`) : error;
  ir(`#/obra/${form.dataset.id}/sitio`, bien("Bitácora guardada."));
};

// ---------- Drive ----------
// Cada quien entra con su propia cuenta de Google y ve solo lo que Drive le deja ver.
let drive = null;   // { token, hasta }
try { drive = JSON.parse(sessionStorage.getItem("sici.drive")); } catch { /* sin memoria de sesión */ }
const driveVivo = () => drive && drive.hasta > Date.now();
function conectarDrive() {
  return new Promise((ok, no) => {
    if (!window.google?.accounts?.oauth2) return no(new Error("Google todavía no cargó. Intente de nuevo en unos segundos."));
    google.accounts.oauth2.initTokenClient({ client_id: GOOGLE_CLIENT_ID, scope: "https://www.googleapis.com/auth/drive.metadata.readonly",
      callback: r => { if (r.error) return no(new Error("Google no dio permiso para ver la carpeta."));
        drive = { token: r.access_token, hasta: Date.now() + (r.expires_in - 60) * 1000 };
        try { sessionStorage.setItem("sici.drive", JSON.stringify(drive)); } catch { /* igual sirve en esta pantalla */ }
        ok(); } }).requestAccessToken();
  });
}
const idCarpeta = url => (String(url).match(/folders\/([\w-]+)/) || String(url).match(/[?&]id=([\w-]+)/) || [])[1];
async function pintaDrive(url, carpeta, nombre) {
  const caja = document.getElementById("drive"); if (!caja) return;
  const abrir = `<a class="btn claro" href="${h(url)}" target="_blank" rel="noopener">Abrir la carpeta en Drive</a>`;
  if (!GOOGLE_CLIENT_ID) { caja.innerHTML = abrir + '<p class="nota">Para ver los archivos aquí mismo falta un paso de configuración con Google. Mientras tanto, el botón abre la carpeta.</p>'; return; }
  if (!driveVivo()) { caja.innerHTML = `<button class="btn" data-accion="conectarDrive" data-url="${h(url)}">Ver los archivos con mi cuenta de Google</button>` + abrir; return; }
  const id = carpeta || idCarpeta(url);
  if (!id) { caja.innerHTML = abrir + '<p class="error">Ese enlace no es de una carpeta de Drive.</p>'; return; }
  caja.innerHTML = '<p class="vacio" style="padding:14px 0">Leyendo la carpeta…</p>';
  try {
    const q = new URLSearchParams({ q: `'${id}' in parents and trashed = false`, fields: "files(id,name,mimeType,modifiedTime,webViewLink)", orderBy: "folder,name",
      pageSize: "200", supportsAllDrives: "true", includeItemsFromAllDrives: "true" });
    const r = await fetch("https://www.googleapis.com/drive/v3/files?" + q, { headers: { Authorization: "Bearer " + drive.token } });
    if (r.status === 401) { drive = null; return pintaDrive(url); }
    if (!r.ok) throw new Error(r.status === 404 || r.status === 403 ? "Su cuenta de Google no tiene acceso a esta carpeta. Pida que se la compartan." : "Drive no respondió.");
    const { files } = await r.json();
    caja.innerHTML = (carpeta ? `<button class="enlace" data-accion="carpetaDrive" data-url="${h(url)}">‹ Volver a la carpeta del proyecto</button><p style="margin:0;font-family:var(--ui);font-weight:500">${h(nombre)}</p>` : "") +
      (files.map(a => a.mimeType === "application/vnd.google-apps.folder"
        ? `<button class="fila" data-accion="carpetaDrive" data-url="${h(url)}" data-id="${h(a.id)}" data-nombre="${h(a.name)}"><b>${h(a.name)} ›</b><span>Carpeta</span></button>`
        : `<a class="fila" href="${h(a.webViewLink)}" target="_blank" rel="noopener"><b>${h(a.name)}</b><span>Cambió el ${h(fecha(a.modifiedTime))}</span></a>`).join("") ||
        '<p class="vacio" style="padding:14px 0">La carpeta está vacía.</p>') + abrir;
  } catch (e) { caja.innerHTML = `<p class="error">${h(decir(e))}</p>` + abrir; }
}
acciones.conectarDrive = async el => { await conectarDrive(); pintaDrive(el.dataset.url); };
acciones.carpetaDrive = el => pintaDrive(el.dataset.url, el.dataset.id, el.dataset.nombre);

// ---------- equipo: la carga por semana ----------
// Una fila por persona y una columna por semana. El número es lo que le queda
// libre; las barras son sus tareas, del día en que empiezan al día en que se
// entregan. Los números los calcula la base (carga_semanal): aquí se pintan.
const leeCarga = c0 => { const l = libres(c0); return Number(c0.dias_habiles) === 0 ? "Sin días hábiles en la semana" : l < -0.05 ? `<em>Tiene ${enDias(-l)} más de lo que cabe</em>`
  : l < 0.5 ? "Semana llena" : Number(c0.dias_ocupados) === 0 ? "Libre esta semana" : `Le queda${l > 1 ? "n" : ""} ${enDias(l)} esta semana`; };
const celdasCarga = sem => sem.map(s => { const x = libres(s), hab = Number(s.dias_habiles), oc = Number(s.dias_ocupados);
  return `<span class="${hab === 0 ? "n" : x < -0.05 ? "c" : x < 0.5 ? "a" : ""}" aria-label="Semana del ${h(fecha(s.semana))}: ${hab === 0 ? "sin días hábiles" : x < -0.05 ? "pasada por " + enDias(-x) : enDias(x) + " libres de " + num(hab)}">
    <b>${hab === 0 ? "–" : x < -0.05 ? "+" + num(-x) : x < 0.5 ? "0" : num(x)}</b><small>${hab === 0 ? "" : x < -0.05 ? "de más" : x < 0.5 ? "llena" : x <= 1 ? "libre" : "libres"}</small>
    <i style="width:${hab ? Math.min(oc / hab * 100, 100).toFixed(0) : 0}%"></i></span>`; }).join("");
function fraseCarga(gente, primera) {
  const libre = gente.filter(p => libres(p.sem[0]) >= 0.5).sort((a, b) => libres(b.sem[0]) - libres(a.sem[0]));
  const pasada = gente.filter(p => libres(p.sem[0]) < -0.05);
  const cuando = primera ? "Esta semana" : "La semana que viene";
  let f = libre.length ? `${cuando} ${libre.length > 1 ? "tienen" : "tiene"} espacio ${lista(libre.map(p => `${p.nombre.split(" ")[0]} (${enDias(libres(p.sem[0]))})`))}.`
    : (() => { for (let s = 1; s < SEMANAS; s++) { const q = gente.filter(p => libres(p.sem[s]) >= 0.5); if (q.length) return `${cuando} nadie tiene espacio. ${q.length > 1 ? "Los primeros que se desocupan son" : "El primero que se desocupa es"} ${lista(q.map(p => p.nombre.split(" ")[0]))}, la semana del ${fecha(q[0].sem[s].semana)}.`; }
        return `Nadie tiene espacio en las próximas ${SEMANAS} semanas.`; })();
  if (pasada.length) f += ` ${lista(pasada.map(p => `${p.nombre.split(" ")[0]} (${enDias(-libres(p.sem[0]))})`))} ${pasada.length > 1 ? "tienen" : "tiene"} más trabajo del que cabe.`;
  return f;
}
async function vistaEquipo() {
  const [carga, tareas] = await Promise.all([
    pedir(sb.rpc("carga_semanal", { p_semanas: SEMANAS })),
    pedir(sb.from("tarea_diseno").select("id,titulo,estado,prioridad,fecha_inicio,fecha_compromiso,creada_en,asignada_a,proyecto_id,proyecto(nombre)").neq("estado", "terminada").order("fecha_compromiso", { nullsFirst: false })),
  ]);
  const gente = [...cargaPorPersona(carga)].map(([id, sem]) => ({ id, nombre: sem[0].nombre, sem }));
  const asigno = yo.asigna || yo.dirige.length > 0, todos = gente.length > 1 || asigno;
  if (!gente.length) return pinta(cabecera("Equipo") + `<main><p class="vacio">Todavía no hay a quién mostrar. ${yo.es_direccion ? "Agregue al equipo para ver su carga." : ""}</p>
    <a class="btn claro" href="#/personas">Personas del equipo</a></main>` + pie("#/equipo"));
  const semanas = gente[0].sem.map(s => s.semana), l0 = dia0(semanas[0]), total = 7 * semanas.length, hoy = dia0(hoyIso()), fin = l0 + total - 1;
  const pos = (a, b) => `left:${((a - l0) / total * 100).toFixed(2)}%;width:${((b - a + 1) / total * 100).toFixed(2)}%`;
  let sinMedir = 0;
  const filas = gente.map(p => {
    const c0 = p.sem[0], l = libres(c0), suyas = tareas.filter(t => t.asignada_a === p.id); let k = 0;
    sinMedir += p.sem.reduce((n, s) => Math.max(n, s.sin_estimar), 0);
    // Una fila por tarea: la barra va del inicio a la entrega y el nombre queda debajo, siempre legible.
    const barras = suyas.filter(t => t.fecha_compromiso).map(t => {
      const b0 = dia0(t.fecha_compromiso), vencida = b0 < hoy && t.estado !== "en_revision";
      let a = Math.min(dia0(t.fecha_inicio || t.creada_en.slice(0, 10)), b0), b = vencida ? hoy : b0;
      if (b < l0 || a > fin) return "";
      a = Math.max(a, l0); b = Math.min(b, fin);
      const izq = (a - l0) / total * 100, der = (fin - b) / total * 100;
      return `<a href="#/tarea/${t.id}" class="${vencida ? "v" : t.estado === "en_revision" ? "r" : t.estado === "con_observaciones" ? "d" : ""}" style="top:${k++ * 36}px">
        <i style="left:${izq.toFixed(2)}%;right:${der.toFixed(2)}%"></i><span style="${izq > 55 ? `right:${der.toFixed(2)}%` : `left:${izq.toFixed(2)}%`}">${h(t.titulo)} · ${
          vencida ? "vencida" : t.estado === "en_revision" ? "en revisión" : t.estado === "con_observaciones" ? "devuelta" : h(corta(t.fecha_compromiso))}</span></a>`;
    }).join("");
    const ajenas = c0.tareas - suyas.filter(t => t.estado !== "en_revision" && t.fecha_compromiso && Math.max(dia0(t.fecha_compromiso), hoy) <= l0 + 6).length;
    return `<section class="g-p"><div class="g-quien"><b>${avatar(p.nombre, p.id !== yo.persona_id)} ${h(p.nombre)}</b>${barraCapacidad(c0)}<span>${
        c0.vencidas ? `<em>${c0.vencidas === 1 ? "Una vencida" : c0.vencidas + " vencidas"}</em>` : ""}${ajenas > 0 && !suyas.length ? `${c0.vencidas ? " · " : ""}En proyectos que usted no ve` : ""}</span>
        ${asigno ? `<a class="g-dar" href="#/nueva/-/${p.id}">Entregarle una tarea</a>` : ""}</div>
      <div class="g-celdas">${celdasCarga(p.sem)}</div>
      <div class="g-barras" style="height:${k * 36}px">${barras}</div></section>`;
  }).join("");
  pinta(cabecera(todos ? "Equipo" : "Mi carga", { sobre: "Carga por semana" }) + `<main>
    <p class="frase" style="margin-top:18px">${h(todos ? fraseCarga(gente, l0 <= hoy) : (l => l < -0.05 ? `Tiene ${enDias(-l)} más de lo que cabe esta semana.` : l < 0.5 ? "Tiene la semana llena." : `Le queda${l > 1 ? "n" : ""} ${enDias(l)} esta semana.`)(libres(gente[0].sem[0])))}</p>
    ${asigno ? '<a class="btn" href="#/nueva">Repartir tareas</a>' : ""}
    <div class="gantt" style="--n:${semanas.length}" tabindex="0" role="group" aria-label="Carga del equipo por semana"><div class="g-in">
      <div class="g-sems">${semanas.map((s, i) => `<span>${i === 0 && l0 <= hoy ? "Esta" : corta(s)}</span>`).join("")}</div>${filas}</div></div>
    <p class="nota">El número es lo que le queda libre a cada persona en la semana, en días. Cada raya es una tarea, del día en que empieza al día en que se entrega; en rojo, las vencidas.${sinMedir ? ` Hay ${sinMedir === 1 ? "una tarea" : sinMedir + " tareas"} sin estimar: se ${sinMedir === 1 ? "ve" : "ven"} en el calendario pero no ${sinMedir === 1 ? "suma" : "suman"} carga.` : ""}</p>
    <a class="btn claro" href="#/personas">Personas del equipo</a></main>` + pie("#/equipo"));
}

// ---------- centro de mando ----------
// Lo que se proyecta en el comité de arquitectura y diseño: el proceso entero,
// y por cada persona su función, lo que debe entregar, para cuándo y su impacto.
// No calcula nada propio: junta lo que ya dicen la base y las otras pantallas.
const RESPONDE = { dirige: "Quien dirige el proyecto", revisa: "Quien revisa", produce: "Quien produce" };
const PAPEL = { dirige: "Dirige", produce: "Produce en", revisa: "Revisa en", observa: "Observa" };
const FASE = { pendiente: ["Por abrir", "n"], en_curso: ["En curso", "a"], en_revision: ["En revisión", "a"], cerrada: ["Cerrada", "o"] };
const nFase = f => titulo(String(f || "").replace(/_/g, " "));
const enCuanto = iso => { const d = dia0(iso) - dia0(hoyIso()); return d === 0 ? "hoy" : d === 1 ? "mañana" : d > 1 ? `en ${d} días` : d === -1 ? "desde ayer" : `hace ${-d} días`; };
const TITULO_AJENO = { espera: "Nadie esperó por su trabajo" };   // el título de la base le habla a la persona; en comité se habla de ella
const uno = (n, s, p) => n === 1 ? s : `${n} ${p}`;
async function vistaMando() {
  const hoy = hoyIso(), desde = new Date((dia0(hoy) - 14) * 864e5).toISOString().slice(0, 10);
  const [carga, tareas, personas, accesos, proyectos, fases, cola, plantillas, avance, listasCierre] = await Promise.all([
    pedir(sb.rpc("carga_semanal", { p_semanas: SEMANAS })),
    pedir(sb.from("tarea_diseno").select("id,titulo,estado,prioridad,fecha_inicio,fecha_compromiso,dias_estimados,terminada_en,creada_en,asignada_a,proyecto_id,proyecto(nombre),fase:proyecto_fase(fase)")
      .or(`estado.neq.terminada,terminada_en.gte.${desde}`).order("fecha_compromiso", { nullsFirst: false })),
    pedir(sb.from("persona").select("id,nombre,rol,profesion(nombre)").eq("es_interno", true).eq("activo", true).order("nombre")),
    pedir(sb.from("acceso_proyecto").select("persona_id,proyecto_id,papel")),
    pedir(sb.from("proyecto").select("id,codigo,nombre,unidad,tipo,fase").eq("estado", "activo").order("nombre")),
    pedir(sb.from("proyecto_fase").select("id,proyecto_id,fase,orden,estado,fecha_compromiso,entrega_cliente,responsable_id,dias_habiles_plazo").order("orden")),
    pedir(sb.from("v_cola_revision").select("*").order("revision_pedida_en")),
    pedir(sb.from("plantilla_proyecto").select("id,nombre,tipo,descripcion,plantilla_fase(id,fase,orden,opcional,entrega_cliente,exige_chequeo,exige_aprobacion_cliente,exige_dedicacion,dias_habiles_plazo,responsable_papel,plantilla_tarea(id,titulo,orden,activa,por_espacio,dias_plazo,dias_estimados))").eq("activa", true)),
    pedir(sb.from("v_fase_avance").select("fase_id,proyecto_id,fase,tareas,terminadas,trabajo_terminado")),
    pedir(sb.from("lista_chequeo").select("id,plantilla_id,fase,version,lista_chequeo_item(id,orden,texto,tipo,opciones,obligatorio,activo)").eq("ambito", "fase_diseno").eq("activa", true).order("version", { ascending: false })),
  ]);
  const av = new Map(avance.map(a => [a.fase_id, a]));
  // La lista de cierre de una fase: la de su tipo de proyecto y, si no tiene, la general de esa fase.
  const listaDe = (plantilla, fase) => listasCierre.find(l => l.plantilla_id === plantilla && l.fase === fase) || listasCierre.find(l => !l.plantilla_id && l.fase === fase);
  const P = new Map(personas.map(p => [p.id, p])), nom = id => (P.get(id)?.nombre || "").split(" ")[0] || "Alguien", pr = new Map(proyectos.map(p => [p.id, p]));
  const abiertas = tareas.filter(t => t.estado !== "terminada"), vence = t => t.fecha_compromiso && t.fecha_compromiso < hoy && t.estado !== "en_revision";
  const vencidas = abiertas.filter(vence), tarde = cola.filter(c => c.fuera_de_plazo), porPersona = cargaPorPersona(carga);
  const gente = [...porPersona].map(([id, sem]) => ({ id, sem, nombre: sem[0].nombre, ficha: P.get(id), suyas: abiertas.filter(t => t.asignada_a === id) }))
    .sort((a, b) => b.suyas.filter(vence).length - a.suyas.filter(vence).length || a.nombre.localeCompare(b.nombre));
  const pasadas = gente.filter(p => libres(p.sem[0]) < -0.05);

  // La frase del comité: primero lo que pesa.
  const partes = [];
  if (vencidas.length) partes.push(`${uno(vencidas.length, "Hay una tarea vencida", "tareas vencidas")}, de ${lista([...new Set(vencidas.map(t => nom(t.asignada_a)))])}.`.replace(/^(\d)/, "Hay $1"));
  const fasesTarde = fases.filter(f => f.estado !== "cerrada" && f.estado !== "pendiente" && f.fecha_compromiso && f.fecha_compromiso < hoy && pr.has(f.proyecto_id));
  if (fasesTarde.length) partes.push(fasesTarde.length === 1 ? `${nFase(fasesTarde[0].fase)} de ${pr.get(fasesTarde[0].proyecto_id).nombre} debía entregarse el ${fecha(fasesTarde[0].fecha_compromiso)}.`
    : `${fasesTarde.length} fases ya pasaron su fecha de entrega: ${lista(fasesTarde.map(f => `${nFase(f.fase).toLowerCase()} de ${pr.get(f.proyecto_id).nombre}`))}.`);
  if (cola.length) partes.push(`${cola.length === 1 ? "Una tarea espera revisión" : `Esperan revisión ${cola.length} tareas`}${tarde.length ? (tarde.length === cola.length ? (cola.length === 1 ? " y ya pasó el plazo" : ", todas fuera de plazo") : `, ${tarde.length === 1 ? "una" : tarde.length} fuera de plazo`) : ""}.`);
  if (pasadas.length) partes.push(`${lista(pasadas.map(p => p.nombre.split(" ")[0]))} ${pasadas.length > 1 ? "tienen" : "tiene"} más trabajo del que cabe esta semana.`);
  const listas = avance.filter(a => a.trabajo_terminado && pr.has(a.proyecto_id));
  if (listas.length) partes.push(`${lista(listas.map(a => `${nFase(a.fase)} de ${pr.get(a.proyecto_id).nombre}`))} ${listas.length > 1 ? "terminaron todas sus tareas: están listas" : "terminó todas sus tareas: está lista"} para el cierre.`);
  const frase = !abiertas.length && !partes.length ? "Todavía no hay tareas abiertas. Cuando se repartan, el comité las ve aquí." : partes.length ? partes.join(" ") : "Todo va al día: ninguna tarea ni fase vencida, nada espera revisión y nadie está pasado de carga.";

  const tarjeta = t => `<a class="m-t" href="#/tarea/${t.id}"><b>${h(t.titulo)}</b><span>${h(nom(t.asignada_a))} · ${t.estado === "terminada" ? "terminó el " + h(corta(t.terminada_en.slice(0, 10)))
    : vence(t) ? `<em>vencida ${h(enCuanto(t.fecha_compromiso))}</em>` : t.fecha_compromiso ? h(corta(t.fecha_compromiso)) : "<em>sin fecha</em>"}</span></a>`;
  const ancho = matchMedia("(min-width:900px)").matches;
  const etapas = [["asignada", "Por empezar"], ["en_curso", "En curso"], ["en_revision", "En revisión"], ["con_observaciones", "Devueltas"], ["terminada", "Terminadas en 14 días"]].map(([e, n]) => {
    const l = tareas.filter(t => t.estado === e).sort((a, b) => e === "terminada" ? b.terminada_en.localeCompare(a.terminada_en) : 0);
    return `<details class="m-e" ${ancho ? "open" : ""}><summary><b>${l.length}</b><span>${n}</span></summary>${l.slice(0, 12).map(tarjeta).join("") || '<p class="m-nada">Ninguna.</p>'}${l.length > 12 ? `<p class="m-nada">Y ${l.length - 12} más.</p>` : ""}</details>`;
  }).join("");

  const filaTarea = t => `<a class="fila" href="#/tarea/${t.id}"><b>${h(t.titulo)}${marca(t.prioridad)}</b>${barraPlazo(t)}<span>${h(t.proyecto?.nombre)}${t.fase?.fase ? " · " + h(nFase(t.fase.fase)) : ""} · ${h(ESTADO[t.estado])} · ${
    !t.fecha_compromiso ? "<em>sin fecha de entrega</em>" : vence(t) ? `<em>era para el ${h(fecha(t.fecha_compromiso))}, vencida ${h(enCuanto(t.fecha_compromiso))}</em>` : `se entrega el ${h(fecha(t.fecha_compromiso))}, ${h(enCuanto(t.fecha_compromiso))}`}${
    t.dias_estimados != null ? " · pide " + h(esfuerzo(t.dias_estimados)) : ""}</span></a>`;
  const funcion = id => { const g = {}; for (const a of accesos) if (a.persona_id === id && pr.has(a.proyecto_id)) (g[a.papel] ||= []).push(pr.get(a.proyecto_id).nombre);
    return ["dirige", "revisa", "produce", "observa"].filter(k => g[k]).map(k => `${PAPEL[k]} ${lista(g[k])}.`).join(" "); };
  const fichas = gente.map(p => { const v = p.suyas.filter(vence).length, rev = p.suyas.filter(t => t.estado === "en_revision").length;
    return `<details class="m-p"><summary><b>${h(p.nombre)}</b><span>${h(ROL[p.ficha?.rol] || "")}${p.ficha?.profesion ? " · " + h(p.ficha.profesion.nombre) : ""}</span>
      ${barraCapacidad(p.sem[0])}<span class="m-r">${p.suyas.length ? uno(p.suyas.length, "Un entregable abierto", "entregables abiertos") : "Sin entregables abiertos"}${v ? ` · <em>${uno(v, "una vencida", "vencidas")}</em>` : ""}${rev ? ` · ${rev} en revisión` : ""}</span></summary>
      <div class="m-dos"><div>
        <div class="grupo">Entregables y tiempos</div>${p.suyas.map(filaTarea).join("") || '<p class="m-nada">No tiene nada abierto.</p>'}
        ${yo.asigna || yo.dirige.length ? `<a class="g-dar" href="#/nueva/-/${p.id}">Entregarle una tarea</a>` : ""}
      </div><div>
        <div class="grupo">Función</div><p>${h(funcion(p.id)) || "Todavía no tiene papel en ningún proyecto."}</p>
        <div class="grupo">Carga de las próximas semanas</div>
        <div class="gantt m-g" style="--n:${p.sem.length}"><div class="g-in"><div class="g-sems">${p.sem.map((s, i) => `<span>${i === 0 && s.semana <= hoy ? "Esta" : corta(s.semana)}</span>`).join("")}</div><div class="g-celdas">${celdasCarga(p.sem)}</div></div></div>
        <div class="grupo">Impacto</div><div id="imp-${p.id}" class="m-imp"><p class="m-nada">${yo.es_direccion || p.id === yo.persona_id ? "Leyendo…" : "El impacto de cada persona lo ve dirección."}</p></div>
      </div></div></details>`; }).join("");

  // La matriz de control (la del Excel de Luisa): cada proyecto, su avance y el estado de cada fase.
  // La matriz de control: el avance va en la barra y las vencidas se nombran, de la más atrasada a la menos.
  const matriz = proyectos.filter(p => p.tipo !== "obra").map(p => { const fs = fases.filter(f => f.proyecto_id === p.id), aa = avance.filter(a => a.proyecto_id === p.id),
      tot = aa.reduce((n, a) => n + a.tareas, 0), hechas = aa.reduce((n, a) => n + a.terminadas, 0), pc = tot ? Math.round(hechas / tot * 100) : 0;
    const ven = abiertas.filter(t => t.proyecto_id === p.id && vence(t)).map(t => ({ t, d: dia0(hoy) - dia0(t.fecha_compromiso) })).sort((a, b) => b.d - a.d);
    return `<a href="#/proyecto/${p.id}"><span class="mx-cab"><b>${h(p.nombre)}</b>${ven.length ? `<span class="marca c">${uno(ven.length, "una vencida", "vencidas")}</span>` : ""}</span>
      ${tot ? `<span class="mx-av${pc >= 100 ? " ok" : ""}" role="img" aria-label="Avance total: ${pc} %"><i><b style="width:${pc}%"></b></i><strong>${pc} %</strong></span>` : '<span class="m-nada">Sin tareas</span>'}
      ${ven.length ? `<ul class="mx-ven">${ven.slice(0, 3).map(({ t, d }) => `<li><span>${h(t.titulo)}</span><small>${h(nom(t.asignada_a).split(" ")[0])} · ${d === 1 ? "1 día" : d + " días"}</small></li>`).join("")}${ven.length > 3 ? `<li class="mas">y ${ven.length - 3} más</li>` : ""}</ul>` : ""}
      ${fs.length ? tiraFases(fs, av) : '<span class="m-nada">Sin fases</span>'}</a>`; }).join("");
  const tablero = proyectos.filter(p => p.tipo !== "obra").map(p => { const fs = fases.filter(f => f.proyecto_id === p.id), act = fs.find(f => f.estado === "en_curso" || f.estado === "en_revision"), ts = abiertas.filter(t => t.proyecto_id === p.id), v = ts.filter(vence).length;
    const eq = accesos.filter(a => a.proyecto_id === p.id && P.has(a.persona_id) && a.papel !== "observa");
    return `<details class="m-p"><summary><b>${h(p.nombre)}</b><span>${h(UNIDAD[p.unidad] || p.unidad)}${act ? " · en " + h(nFase(act.fase).toLowerCase()) : ""}</span>
      <span class="m-r">${act?.fecha_compromiso ? (act.fecha_compromiso < hoy ? `<em>La fase era para el ${h(fecha(act.fecha_compromiso))}</em>` : `La fase se entrega el ${h(fecha(act.fecha_compromiso))}, ${h(enCuanto(act.fecha_compromiso))}`) : act ? "La fase no tiene fecha de entrega" : "Ninguna fase en curso"} · ${ts.length ? uno(ts.length, "una tarea abierta", "tareas abiertas") : "sin tareas abiertas"}${v ? ` · <em>${uno(v, "una vencida", "vencidas")}</em>` : ""}</span></summary>
      <div class="m-dos"><div>${fs.length ? tiraFases(fs, av) : ""}
        <div class="grupo">Fases y entregables al cliente</div>${fs.map(f => `<div class="fila"><b>${h(nFase(f.fase))}<span class="marca ${FASE[f.estado][1]}">${FASE[f.estado][0]}</span></b>
          <span>${f.entrega_cliente ? h(f.entrega_cliente) : "Sin entregable definido"}${f.responsable_id ? ` · responde ${h(nom(f.responsable_id))}` : f.estado !== "pendiente" && f.estado !== "cerrada" ? " · <em>sin responsable</em>" : ""}${av.get(f.id)?.tareas ? ` · ${av.get(f.id).terminadas} de ${uno(av.get(f.id).tareas, "una tarea terminada", "tareas terminadas")}` : ""}${av.get(f.id)?.trabajo_terminado ? ` · <a href="#/cierre/${f.id}" style="color:var(--ok)">lista para el cierre</a>` : ""}${f.fecha_compromiso ? ` · ${f.estado !== "cerrada" && f.fecha_compromiso < hoy ? "<em>" : ""}para el ${h(fecha(f.fecha_compromiso))}${f.estado !== "cerrada" && f.fecha_compromiso < hoy ? "</em>" : ""}` : ""}</span></div>`).join("") || '<p class="m-nada">Este proyecto no tiene fases.</p>'}
        <a class="g-dar" href="#/proyecto/${p.id}">Abrir la ficha del proyecto</a>
      </div><div>
        <div class="grupo">Equipo</div><p>${["dirige", "revisa", "produce"].map(k => { const q = eq.filter(a => a.papel === k).map(a => nom(a.persona_id)); return q.length ? `${k === "dirige" ? "Dirige" : k === "revisa" ? "Revisa" : "Produce"}${q.length > 1 ? "n" : ""} ${h(lista(q))}.` : ""; }).filter(Boolean).join(" ") || "Todavía no tiene equipo."}</p>
        <div class="grupo">Lo que sigue</div>${ts.slice(0, 6).map(filaTarea).join("") || '<p class="m-nada">Nada abierto.</p>'}${ts.length > 6 ? `<p class="m-nada">Y ${ts.length - 6} más en la ficha.</p>` : ""}
      </div></div></details>`; }).join("");

  // El flujo de cada tipo de proyecto: lo que pide cada fase, cuánto puede durar y quién responde.
  const orden = ["Diseño", "Peritaje", "Consultoría", "Obra", "Montaje de interiores", "Interno"];
  const flujos = [...plantillas].sort((a, b) => orden.indexOf(a.nombre) - orden.indexOf(b.nombre)).filter(pl => pl.tipo !== "obra").map(pl => {
    const fs = [...(pl.plantilla_fase || [])].sort((a, b) => a.orden - b.orden), total = fs.reduce((n, f) => n + (f.dias_habiles_plazo || 0), 0), sin = fs.filter(f => !f.dias_habiles_plazo).length;
    return `<details class="m-p" ${flujoAbierto === pl.id ? "open" : ""}><summary><b>${h(pl.nombre)}</b><span>${h(pl.descripcion || "")}</span>
      <span class="m-r">${!fs.length ? "Sin fases" : `${uno(fs.length, "Una fase", "fases")}${total ? ` · ${total} días hábiles${sin ? " en las que tienen plazo" : " de principio a fin"}` : ""}${sin ? ` · <em>${sin === fs.length ? "ninguna tiene plazo todavía" : uno(sin, "una sin plazo", "sin plazo")}</em>` : ""}`}</span></summary>
      <div class="m-flujo">${fs.map((f, i) => { const exige = [f.exige_chequeo && "lista de chequeo", f.exige_aprobacion_cliente && "aprobación del cliente", f.exige_dedicacion && "dedicación registrada"].filter(Boolean);
        const tt = (f.plantilla_tarea || []).filter(x => x.activa !== false).sort((a, b) => a.orden - b.orden);
        return `<div class="m-f"><small>${String(i + 1).padStart(2, "0")}${f.opcional ? " · si aplica" : ""}</small><b>${h(nFase(f.fase))}</b>
          <p><span>Entrega al cliente</span>${f.entrega_cliente ? h(f.entrega_cliente) : "Sin definir"}</p>
          <p><span>Tiempo máximo</span>${yo.es_direccion ? `<label class="m-en"><input type="number" min="1" max="400" inputmode="numeric" value="${f.dias_habiles_plazo ?? ""}" placeholder="–" data-cambia="plazoFase" data-id="${f.id}" aria-label="Días hábiles de ${h(nFase(f.fase))}"> días hábiles</label><i class="m-ok" aria-live="polite"></i>`
            : f.dias_habiles_plazo ? `${f.dias_habiles_plazo} días hábiles` : "Sin plazo"}</p>
          <p><span>Responde</span>${yo.es_direccion ? `<select data-cambia="papelFase" data-id="${f.id}" aria-label="Quién responde por ${h(nFase(f.fase))}">${Object.entries(RESPONDE).map(([v, n]) => `<option value="${v}" ${v === f.responsable_papel ? "selected" : ""}>${n}</option>`).join("")}</select><i class="m-ok" aria-live="polite"></i>`
            : RESPONDE[f.responsable_papel] || "Quien dirige"}</p>
          <p><span>Para cerrarla</span>${exige.length ? titulo(exige[0][0]) + lista(exige).slice(1) : "Nada"}</p>
          ${(() => { const l = listaDe(pl.id, f.fase), pts = (l?.lista_chequeo_item || []).filter(x => x.activo !== false).sort((a, b) => a.orden - b.orden), propia = l?.plantilla_id === pl.id;
            return `<div class="m-tt"><span>Lista de chequeo</span>${pts.map(x => `<p>${h(x.texto)}<small>${h(PUNTO[x.tipo] || x.tipo)}${x.tipo === "opcion" ? ": " + h(lista(x.opciones || [])) : ""}${x.obligatorio ? "" : " · opcional"}</small>
                ${yo.es_direccion && propia ? `<button type="button" class="enlace" data-accion="quitarPunto" data-id="${x.id}" data-flujo="${pl.id}">Quitar</button>` : ""}</p>`).join("") || `<p>${f.exige_chequeo ? "<em>Sin puntos: así la fase no se puede cerrar</em>" : "No pide lista"}</p>`}
              ${pts.length && !propia ? '<p><small>Es la lista general de esta fase. Al agregar un punto se crea una propia de este tipo de proyecto.</small></p>' : ""}
              ${yo.es_direccion ? `<details><summary>Agregar un punto</summary><form data-form="punto" data-fase="${f.id}" data-flujo="${pl.id}">
                <label>Qué se verifica<input name="texto" required minlength="4" autocomplete="off"></label>
                <label>Cómo se responde<select name="tipo">${Object.entries(PUNTO).map(([v, n]) => `<option value="${v}">${n}</option>`).join("")}</select></label>
                <label>Opciones, separadas por coma (solo si se escoge)<input name="opciones" autocomplete="off" placeholder="Sí, No aplica"></label>
                <label>Es obligatorio<select name="obligatorio"><option value="si">Sí: sin él la fase no cierra</option><option value="">No: se pregunta, pero no frena</option></select></label>
                <button class="btn claro">Guardar el punto</button></form></details>` : ""}</div>`; })()}
          <div class="m-tt"><span>Tareas típicas</span>${tt.map(x => `<p>${h(x.titulo)}<small>${[x.por_espacio && "una por espacio", x.dias_plazo != null && `se entrega en ${x.dias_plazo} días hábiles`, x.dias_estimados != null && "pide " + esfuerzo(x.dias_estimados)].filter(Boolean).join(" · ")}</small>
              ${yo.es_direccion ? `<button type="button" class="enlace" data-accion="quitarTipica" data-id="${x.id}" data-flujo="${pl.id}">Quitar</button>` : ""}</p>`).join("") || "<p>Sin definir</p>"}
            ${yo.es_direccion ? `<details><summary>Agregar una tarea típica</summary><form data-form="tipica" data-fase="${f.id}" data-flujo="${pl.id}" data-orden="${(tt.at(-1)?.orden || 0) + 10}">
              <label>Qué hay que entregar<input name="titulo" required minlength="4" autocomplete="off"></label>
              <label>Para qué sirve en el proyecto<textarea name="proposito" required minlength="12"></textarea></label>
              <label>Se repite<select name="por_espacio"><option value="">Una vez en la fase</option><option value="si">Una por cada espacio</option></select></label>
              <label>Se entrega en (días hábiles)<input name="dias_plazo" type="number" min="0" max="120" inputmode="numeric"></label>
              <label>Trabajo que pide<select name="dias" required><option value="">Escoja</option>${ESFUERZO.map(([v, n]) => `<option value="${v}">${n}</option>`).join("")}</select></label>
              <button class="btn claro">Guardar la tarea típica</button></form></details>` : ""}</div></div>`; }).join("") || '<p class="m-nada">Este tipo de proyecto no tiene fases: solo tareas.</p>'}</div></details>`; }).join("");

  pinta(cabecera("Centro de mando", { sobre: `Arquitectura y diseño · ${fecha(hoy)}` }) + `<main class="mando">
    <p class="frase" style="margin-top:18px">${h(frase)}</p>
    <div class="grupo">El proceso</div><div class="m-etapas">${etapas}</div>
    <div class="m-cab"><div class="grupo">Cada persona</div><span>${yo.es_direccion ? '<a class="enlace" href="#/personas" style="margin-right:16px">Agregar o ver fichas</a>' : ""}${gente.length ? '<button type="button" class="enlace" data-accion="desplegar" data-de="personas">Desplegar todo</button>' : ""}</span></div>
    <div id="personas">${fichas || '<p class="m-nada">Todavía no hay equipo que mostrar.</p>'}</div>
    <div class="m-cab"><div class="grupo">Fases por proyecto</div></div><div class="mx">${matriz || '<p class="m-nada">Todavía no hay proyectos de arquitectura y diseño abiertos.</p>'}</div>
    <div class="m-cab"><div class="grupo">Cada proyecto</div>${tablero ? '<button type="button" class="enlace" data-accion="desplegar" data-de="proyectos">Desplegar todo</button>' : ""}</div>
    <div id="proyectos">${tablero || '<p class="m-nada">Todavía no hay proyectos de arquitectura y diseño abiertos.</p>'}</div>
    <div class="m-cab"><div class="grupo">El flujo de cada tipo de proyecto</div>${flujos ? '<button type="button" class="enlace" data-accion="desplegar" data-de="flujos">Desplegar todo</button>' : ""}</div>
    <div id="flujos">${flujos || '<p class="m-nada">Todavía no hay plantillas de proyecto.</p>'}</div>
    <p class="nota">Las tareas se reparten en Equipo y el impacto sale solo de lo entregado y lo revisado. El tiempo máximo de cada fase y quién responde por ella se definen una vez, en el flujo: al abrir la fase en un proyecto, el sistema le pone su fecha de entrega y su responsable. Cambiar el flujo no mueve los proyectos que ya están andando.</p>
  </main>` + pie("#/mando", cola.length));

  // El impacto de cada quien llega después, para no demorar la pantalla.
  for (const p of gente) if (yo.es_direccion || p.id === yo.persona_id) sb.rpc("indicadores", { p_persona: p.id }).then(({ data, error }) => {
    const caja = document.getElementById("imp-" + p.id); if (!caja) return;
    caja.innerHTML = error ? `<p class="m-nada">${h(decir(error))}</p>` : data.map(i => `<p><small>${h(p.id === yo.persona_id ? i.titulo : TITULO_AJENO[i.indicador] || i.titulo)}</small>${h(i.frase)}</p>`).join("") || '<p class="m-nada">Todavía no hay nada que decir.</p>';
  });
}
// Las tareas típicas sí repintan: el flujo que se estaba editando vuelve a quedar abierto.
let flujoAbierto = null;
formularios.tipica = async (f, form) => {
  await pedir(sb.from("plantilla_tarea").insert({ plantilla_fase_id: form.dataset.fase, orden: Number(form.dataset.orden), titulo: f.titulo.trim(), proposito: f.proposito.trim(),
    por_espacio: !!f.por_espacio, dias_plazo: f.dias_plazo === "" ? null : Number(f.dias_plazo), dias_estimados: Number(f.dias) }));
  flujoAbierto = form.dataset.flujo; aviso = bien("Tarea típica guardada: se propondrá cada vez que se abra esta fase."); navegar();
};
formularios.punto = async (f, form) => {
  const opciones = f.opciones.split(",").map(x => x.trim()).filter(Boolean);
  if (f.tipo === "opcion" && opciones.length < 2) throw new Error("Para escoger hacen falta al menos dos opciones, separadas por coma.");
  await pedir(sb.rpc("punto_de_cierre", { p_plantilla_fase: form.dataset.fase, p_texto: f.texto.trim(), p_tipo: f.tipo, p_opciones: f.tipo === "opcion" ? opciones : null, p_obligatorio: !!f.obligatorio }));
  flujoAbierto = form.dataset.flujo; aviso = bien("Punto guardado: se pedirá para cerrar esta fase, también en los proyectos que ya la tienen abierta."); navegar();
};
acciones.quitarPunto = async el => {
  const r = await pedir(sb.from("lista_chequeo_item").update({ activo: false }).eq("id", el.dataset.id).select("id"));
  if (!r.length) throw new Error("La lista de chequeo la cambia dirección.");
  flujoAbierto = el.dataset.flujo; aviso = bien("Ese punto ya no se pide."); navegar();
};
acciones.quitarTipica = async el => {
  const r = await pedir(sb.from("plantilla_tarea").update({ activa: false }).eq("id", el.dataset.id).select("id"));
  if (!r.length) throw new Error("Las tareas típicas las cambia dirección.");
  flujoAbierto = el.dataset.flujo; aviso = bien("Ya no se propone. Las tareas que se crearon con ella siguen como estaban."); navegar();
};
// Guardar un dato del flujo sin repintar la pantalla: el comité sigue donde iba.
async function guardaFlujo(el, cambio) {
  const marca = el.closest("p").querySelector(".m-ok");
  try { const r = await pedir(sb.from("plantilla_fase").update(cambio).eq("id", el.dataset.id).select("id"));
    if (!r.length) throw new Error("Solo dirección cambia el flujo.");
    marca.className = "m-ok"; marca.textContent = "Guardado"; }
  catch (e) { marca.className = "m-ok mal"; marca.textContent = decir(e).includes("plazo_sano") ? "Entre 1 y 400 días" : decir(e); }
}
acciones.plazoFase = el => guardaFlujo(el, { dias_habiles_plazo: el.value === "" ? null : Number(el.value) });
acciones.papelFase = el => guardaFlujo(el, { responsable_papel: el.value });
acciones.desplegar = el => { const d = [...document.querySelectorAll(`#${el.dataset.de} > details`)], abrir = d.some(x => !x.open); d.forEach(x => x.open = abrir); el.textContent = abrir ? "Recoger todo" : "Desplegar todo"; };

// ---------- personas ----------
async function vistaPersonas() {
  const [personas, profesiones] = await Promise.all([
    pedir(sb.from("persona").select("id,nombre,rol,correo,auth_user_id,ve_reservado,profesion(nombre)").eq("es_interno", true).eq("activo", true).order("nombre")),
    yo.es_direccion ? pedir(sb.from("profesion").select("id,nombre").eq("activa", true).order("nombre")) : [],
  ]);
  pinta(cabecera("Personas", { atras: yo.obras && (yo.asigna || yo.dirige.length) ? "#/yo" : "#/equipo" }) + `<main>
    ${personas.map(p => `<div class="fila"><b>${h(p.nombre)}<span class="marca ${p.auth_user_id ? "o" : "n"}">${p.auth_user_id ? "Ya entró" : "No ha entrado"}</span></b>
      <span>${h(ROL[p.rol] || p.rol)}${p.profesion ? " · " + h(p.profesion.nombre) : ""}${yo.es_direccion && p.correo ? " · " + h(p.correo) : ""}</span>
      ${yo.es_socio && p.rol !== "socio" ? `<button class="enlace" data-accion="reservado" data-id="${p.id}" data-si="${p.ve_reservado ? "" : "1"}">${p.ve_reservado ? "Ve préstamos y socios · quitarle el permiso" : "Darle permiso de ver préstamos y socios"}</button>`
        : yo.ve_reservado && (p.rol === "socio" || p.ve_reservado) ? "<span>Ve préstamos y socios</span>" : ""}</div>`).join("")}
    ${yo.es_direccion ? `<div class="grupo">Agregar a alguien</div><form data-form="persona">
      <label for="pn">Nombre completo</label><input id="pn" name="nombre" required autocomplete="off">
      <label for="pc">Correo con el que va a entrar</label><input id="pc" name="correo" type="email" required autocomplete="off" inputmode="email">
      <div class="dos"><div><label for="prl">Rol</label><select id="prl" name="rol">${["practicante", "arquitecto", "director_proyecto", "residente", "director", "mercadeo", "financiero", "socio"].map(r => `<option value="${r}">${ROL[r]}</option>`).join("")}</select></div>
        <div><label for="pf">Profesión</label><select id="pf" name="profesion"><option value="">Sin definir</option>${profesiones.map(x => `<option value="${x.id}">${h(x.nombre)}</option>`).join("")}</select></div></div>
      <button class="btn">Agregar al equipo de ESA</button>
      <p class="nota">Después, esa persona abre la aplicación, toca «Es mi primera vez» y crea su acceso con ese mismo correo.</p></form>` : ""}
  </main>`);
}
// F7 · Préstamos y la cuenta de los socios: los ve un socio y a quien él le dé el permiso.
acciones.reservado = async el => {
  const si = !!el.dataset.si;
  if (si && !confirm("Va a ver los préstamos, los créditos y la cuenta de los socios. ¿Le da el permiso?")) return;
  const r = await pedir(sb.from("persona").update({ ve_reservado: si }).eq("id", el.dataset.id).select("id"));
  aviso = r.length ? bien(si ? "Permiso dado: ya ve préstamos y socios." : "Permiso quitado.") : mal("Este permiso lo da un socio."); navegar();
};
formularios.persona = async f => {
  await pedir(sb.from("persona").insert({ nombre: f.nombre.trim(), correo: f.correo.trim().toLowerCase(), rol: f.rol, es_interno: true, horas_semana: 40, profesion_id: f.profesion || null }));
  aviso = bien(`${f.nombre.trim()} ya tiene ficha. Falta que cree su acceso con ese correo.`); navegar();
};

// ---------- impacto ----------
async function vistaImpacto(abierto) {
  const ind = await pedir(sb.rpc("indicadores"));
  const detalle = abierto ? await pedir(sb.rpc("indicador_detalle", { p_indicador: abierto })) : null;
  const con = ["cumplio", "primera", "espera", "hitos", "margen", "revisiones"];
  pinta(cabecera("Impacto", { sobre: "Últimas cuatro semanas" }) + `<main>${ind.map(i => `
      <${con.includes(i.indicador) && i.suficiente ? `a href="#/impacto/${i.indicador === abierto ? "" : i.indicador}" class="fila despliega" aria-expanded="${i.indicador === abierto}"` : `div class="fila"`}><span style="margin:0 0 4px;font:600 .62rem var(--ui);letter-spacing:.2em;text-transform:uppercase;color:var(--taupe)">${h(i.titulo)}</span>
        <p class="frase">${h(i.frase)}</p></${con.includes(i.indicador) && i.suficiente ? "a" : "div"}>
      ${i.indicador === abierto && detalle ? detalle.map(d => `<div class="fila" style="padding-left:16px;border-left:1px solid var(--tinta)"><b>${h(d.titulo)}</b><span>${d.a_favor ? "" : "<em>"}${h(d.hecho)}${d.a_favor ? "" : "</em>"}${d.excluida ? " · no cuenta: lo corrigió dirección" : ""}</span></div>`).join("") : ""}`).join("") ||
    '<p class="vacio">Todavía no hay nada que decir.</p>'}
    <p class="nota">Ninguna frase cuenta tareas hechas ni horas trabajadas. Solo cuentan las tareas que le asignó otra persona.</p></main>` + pie("#/impacto"));
}

// ---------- mi cuenta ----------
function vistaYo() {
  pinta(cabecera(yo.nombre, { sobre: ROL[yo.rol] || yo.rol, atras: "#/" }) + `<main>
    <p style="color:var(--tinta-3)">${h(usuario.email)}</p>
    <picture class="logo" style="margin-top:28px"><source srcset="logo-blanco.png" media="(prefers-color-scheme: dark)"><img src="logo.png" width="1000" height="431" alt="ESA Arquitectura"></picture>
    ${yo.es_direccion ? '<a class="btn" href="#/personas" style="margin-top:28px">Personas del equipo: fichas y accesos</a>' : ""}
    ${yo.asigna || yo.dirige.length ? `<a class="btn claro" href="#/impacto" style="margin-top:${yo.es_direccion ? 14 : 28}px">Mi impacto</a>` : ""}
    <div class="grupo">En el teléfono</div><p>Para tenerla como una aplicación: en iPhone, botón de compartir y «Agregar a inicio»; en Android, menú del navegador e «Instalar aplicación».</p>
    <a class="btn claro" href="#/clave" style="margin-top:22px">Cambiar mi contraseña</a>
    <button class="btn peligro" data-accion="salir">Salir</button></main>`);
}
function vistaSinFicha() {
  pinta(`<main><div class="entrada"><picture class="logo"><source srcset="logo-blanco.png" media="(prefers-color-scheme: dark)"><img src="logo.png" width="1000" height="431" alt="ESA Arquitectura"></picture><div class="sub">SICI · CONTROL INTERNO</div>
    <h1>Falta su ficha</h1><p>Entró bien, pero el correo <strong>${h(usuario.email)}</strong> todavía no está en el equipo. Pídale a dirección que lo agregue con ese mismo correo y vuelva a abrir la aplicación.</p>
    <button class="btn claro" data-accion="reintentar">Ya me agregaron</button><button class="btn peligro" data-accion="salir">Salir</button></div></main>`);
}
acciones.reintentar = () => arrancar();

// ---------- navegación ----------
async function navegar() {
  if (!usuario) return vistaEntrar();
  if (recuperando) return vistaNuevaClave();
  if (!yo) return vistaSinFicha();
  const [, ruta = "", arg, arg2] = location.hash.split("/");
  app.classList.toggle("ancho", ruta === "mando");
  try {
    if (ruta === "tarea" && arg) await vistaTarea(arg);
    else if (ruta === "nueva") await vistaNueva(arg, arg2);
    else if (ruta === "revisar") await vistaRevisar();
    else if (ruta === "proyectos") await vistaProyectos();
    else if (ruta === "proyecto" && arg) await vistaProyecto(arg, arg2);
    else if (ruta === "nuevo-proyecto") await vistaNuevoProyecto(arg);
    else if (ruta === "obras") await vistaObras();
    else if (ruta === "obra" && arg) await vistaObra(arg, arg2);
    else if (ruta === "equipo") await vistaEquipo();
    else if (ruta === "personas") await vistaPersonas();
    else if (ruta === "mando") await vistaMando();
    else if (ruta === "tipicas" && arg) await vistaTipicas(arg);
    else if (ruta === "cierre" && arg) await vistaCierre(arg);
    else if (ruta === "registro") await vistaRegistro();
    else if (ruta === "impacto") await vistaImpacto(arg);
    else if (ruta === "ventas") await vistaVentas();
    else if (ruta === "embudo" && arg) await vistaEmbudo(arg, arg2);
    else if (ruta === "oportunidad" && arg) await vistaOportunidad(arg);
    else if (ruta === "reporte" && arg) await vistaReporte(arg);
    else if (ruta === "contacto" && arg) await vistaContacto(arg);
    else if (ruta === "contacto-nuevo") await vistaContactoNuevo();
    else if (ruta === "tarifas") await vistaTarifas();
    else if (ruta === "yo") vistaYo();
    else if (ruta === "clave") vistaNuevaClave();
    else await vistaDia();
  } catch (e) {
    pinta(cabecera("No se pudo abrir", { atras: "#/" }) + `<main><div class="error">${h(decir(e))}</div><button class="btn claro" data-accion="reintentar">Intentar de nuevo</button></main>`);
  }
}
async function arrancar() {
  try { yo = usuario ? await pedir(sb.rpc("mi_sesion")) : null; }
  catch (e) { yo = null; aviso = mal(e); }
  navegar();
}

document.addEventListener("click", async e => {
  const el = e.target.closest("[data-ir],[data-accion]");
  if (!el || el.closest("form") && el.type === "submit") return;
  e.preventDefault();
  if (el.dataset.ir) return ir(el.dataset.ir);
  el.disabled = true;
  try { await acciones[el.dataset.accion](el); }
  catch (err) { aviso = mal(err); navegar(); }
  finally { el.disabled = false; }
});
document.addEventListener("change", e => { const el = e.target.closest("[data-cambia]"); if (el) acciones[el.dataset.cambia](el); });
document.addEventListener("submit", async e => {
  const form = e.target.closest("[data-form]"); if (!form) return;
  e.preventDefault();
  const boton = e.submitter, datos = Object.fromEntries(new FormData(form));
  form.querySelectorAll("button").forEach(b => b.disabled = true);
  try { await formularios[form.dataset.form](datos, form, boton); }
  catch (err) {
    form.querySelectorAll("button").forEach(b => b.disabled = false);
    form.querySelector(".error")?.remove();
    form.insertAdjacentHTML("afterbegin", `<div class="error" role="alert">${h(decir(err))}</div>`);
    form.scrollIntoView({ block: "start", behavior: "smooth" });
  }
});
window.addEventListener("hashchange", navegar);
sb.auth.onAuthStateChange((evento, sesion) => {
  const antes = usuario?.id;
  usuario = sesion?.user || null;
  if (evento === "PASSWORD_RECOVERY") { recuperando = true; setTimeout(vistaNuevaClave, 0); return; }
  if (evento === "INITIAL_SESSION" || usuario?.id !== antes) setTimeout(arrancar, 0);
});
if ("serviceWorker" in navigator && location.protocol === "https:") navigator.serviceWorker.register("sw.js").catch(() => {});
