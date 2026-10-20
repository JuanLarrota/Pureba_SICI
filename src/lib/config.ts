// Lo único que cambia entre instalaciones. Ninguno de estos valores es secreto:
// la llave publicable solo deja hacer lo que las reglas de la base permiten a
// cada usuario con sesión, y sin sesión no deja leer nada.
// Se pueden sobreescribir con variables NEXT_PUBLIC_* en .env.local.
export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "https://khbmraaiprcjocmprzkb.supabase.co";
export const SUPABASE_KEY = process.env.NEXT_PUBLIC_SUPABASE_KEY ?? "sb_publishable_lB_wlCMZcxjmvt-_ONpyrg_ML3wdOs8";

// Para listar los archivos de la carpeta de Drive de cada proyecto dentro de la
// aplicación. Es el «ID de cliente» de Google Cloud (tipo «Aplicación web»).
// Vacío: la aplicación solo muestra el botón para abrir la carpeta en Drive.
export const GOOGLE_CLIENT_ID = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID ?? "";

// «demo»: la aplicación corre con un Supabase de mentira y datos de ejemplo
// (public/demo/datos.json). Sirve para recorrer las pantallas sin sesión; no guarda nada.
export const MODO = process.env.NEXT_PUBLIC_MODO ?? "real";
export const ES_DEMO = MODO === "demo";
// En la demo se puede escoger con quién se entra (Luisa, Mariana, Carlos, Teo, Allison).
export const DEMO_PERSONA = process.env.NEXT_PUBLIC_DEMO_PERSONA ?? "Luisa";

export const SEMANAS = 8;   // las que muestra la carga del equipo
