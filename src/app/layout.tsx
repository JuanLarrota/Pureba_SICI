import type { Metadata, Viewport } from "next";
import { Jost, Work_Sans } from "next/font/google";
import Script from "next/script";
import { Suspense } from "react";
import { SesionProvider } from "@/lib/sesion";
import { Marco } from "@/componentes/marco/Marco";
import "./globals.css";

// Jost para la interfaz, Work Sans para el texto: las dos únicas tipografías del sistema visual.
const jost = Jost({ subsets: ["latin"], weight: ["300", "400", "500", "600"], variable: "--font-jost", display: "swap" });
const workSans = Work_Sans({ subsets: ["latin"], weight: ["400", "500"], variable: "--font-work-sans", display: "swap" });

export const metadata: Metadata = {
  title: "SICI · ESA Arquitectura",
  description: "Tareas, proyectos y equipo de ESA Arquitectura",
  manifest: "/manifest.webmanifest",
  appleWebApp: { capable: true, title: "SICI", statusBarStyle: "default" },
  icons: { icon: "/icono-192.png", apple: "/icono-180.png" },
};
export const viewport: Viewport = { themeColor: "#000000", width: "device-width", initialScale: 1, viewportFit: "cover" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="es" className={`${jost.variable} ${workSans.variable}`}>
      <body>
        <div id="app" className="app">
          <Suspense fallback={<p className="espera">Abriendo…</p>}>
            <SesionProvider>
              <Marco>{children}</Marco>
            </SesionProvider>
          </Suspense>
        </div>
        <noscript>Esta aplicación necesita JavaScript.</noscript>
        <Script src="https://accounts.google.com/gsi/client" strategy="lazyOnload" />
      </body>
    </html>
  );
}
