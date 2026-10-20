// Google Drive: cada quien entra con su propia cuenta de Google y ve solo lo que Drive le deja ver.
import { GOOGLE_CLIENT_ID } from "@/lib/config";

interface Token { token: string; hasta: number }
declare global {
  interface Window { google?: { accounts?: { oauth2?: { initTokenClient(c: unknown): { requestAccessToken(): void } } } } }
}

let drive: Token | null = null;
try { if (typeof sessionStorage !== "undefined") drive = JSON.parse(sessionStorage.getItem("sici.drive") || "null"); } catch { /* sin memoria de sesión */ }

export const driveVivo = () => !!drive && drive.hasta > Date.now();
export const olvidarDrive = () => { drive = null; };

export function conectarDrive(): Promise<void> {
  return new Promise((ok, no) => {
    if (!window.google?.accounts?.oauth2) return no(new Error("Google todavía no cargó. Intente de nuevo en unos segundos."));
    window.google.accounts.oauth2.initTokenClient({
      client_id: GOOGLE_CLIENT_ID, scope: "https://www.googleapis.com/auth/drive.metadata.readonly",
      callback: (r: { error?: string; access_token: string; expires_in: number }) => {
        if (r.error) return no(new Error("Google no dio permiso para ver la carpeta."));
        drive = { token: r.access_token, hasta: Date.now() + (r.expires_in - 60) * 1000 };
        try { sessionStorage.setItem("sici.drive", JSON.stringify(drive)); } catch { /* igual sirve en esta pantalla */ }
        ok();
      },
    }).requestAccessToken();
  });
}

export const idCarpeta = (url: string) => (String(url).match(/folders\/([\w-]+)/) || String(url).match(/[?&]id=([\w-]+)/) || [])[1];

export interface ArchivoDrive { id: string; name: string; mimeType: string; modifiedTime: string; webViewLink: string }
export const ES_CARPETA = "application/vnd.google-apps.folder";

/** Los archivos de una carpeta. Lanza «401» si el permiso venció. */
export async function listarCarpeta(id: string): Promise<ArchivoDrive[]> {
  if (!drive) throw new Error("401");
  const q = new URLSearchParams({ q: `'${id}' in parents and trashed = false`, fields: "files(id,name,mimeType,modifiedTime,webViewLink)", orderBy: "folder,name",
    pageSize: "200", supportsAllDrives: "true", includeItemsFromAllDrives: "true" });
  const r = await fetch("https://www.googleapis.com/drive/v3/files?" + q, { headers: { Authorization: "Bearer " + drive.token } });
  if (r.status === 401) { drive = null; throw new Error("401"); }
  if (!r.ok) throw new Error(r.status === 404 || r.status === 403 ? "Su cuenta de Google no tiene acceso a esta carpeta. Pida que se la compartan." : "Drive no respondió.");
  const { files } = (await r.json()) as { files: ArchivoDrive[] };
  return files;
}
