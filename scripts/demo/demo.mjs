// Abre la aplicación en modo demo: un Supabase de mentira con los datos de
// public/demo/datos.json (se arman con scripts/demo/armar.py --web).
// No guarda nada. Sirve para recorrer las pantallas sin sesión.
//
//   npm run demo            → http://localhost:3100  (otro puerto: PUERTO=3177 npm run demo)
//   npm run demo -- Mariana → entra como Mariana (hay que haber armado los datos para esa persona)
import { spawn } from "node:child_process";
import { createRequire } from "node:module";

const persona = process.argv[2] || "Luisa";
const puerto = process.env.PUERTO || "3100";
const env = { ...process.env, NEXT_PUBLIC_MODO: "demo", NEXT_PUBLIC_DEMO_PERSONA: persona };
// Se llama al binario de Next con el mismo Node, para que funcione igual en Windows y en Mac.
const next = createRequire(import.meta.url).resolve("next/dist/bin/next");
const hijo = spawn(process.execPath, [next, "dev", "-p", puerto], { stdio: "inherit", env });
hijo.on("exit", (c) => process.exit(c ?? 0));
