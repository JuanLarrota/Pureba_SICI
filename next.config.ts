import type { NextConfig } from "next";

// La aplicación es puramente de navegador: toda regla vive en la base (RLS,
// disparadores, funciones). Por eso se exporta como sitio estático y se sirve
// desde Cloudflare Pages o cualquier host de archivos, sin servidor de Node.
const nextConfig: NextConfig = {
  output: "export",
  trailingSlash: true,          // /tarea/ → tarea/index.html: funciona en cualquier host estático
  images: { unoptimized: true },
  reactStrictMode: true,
};

export default nextConfig;
