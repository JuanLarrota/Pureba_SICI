"use client";
import { useSearchParams } from "next/navigation";

/** Un parámetro de la consulta (?id=…), o null si no viene. */
export function useParametro(nombre: string): string | null {
  const p = useSearchParams();
  return p.get(nombre);
}
