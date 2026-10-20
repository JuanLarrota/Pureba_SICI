// Las reglas que la pantalla calcula sola: fechas hábiles, plazos y frases.
import { describe, expect, it } from "vitest";
import { dia0, lunesDe, fecha, corta, enCuanto } from "@/lib/dominio/fechas";
import { habiles } from "@/lib/dominio/plazo";
import { enDias, esfuerzo, lista, uno, pesos, plata, iniciales, nFase, whatsapp } from "@/lib/dominio/texto";
import { plazo, tramo, libres, leeCarga, tramoLibre, estadoFase, avanceTotal } from "@/lib/dominio/plazo";
import { clave, R } from "@/lib/rutas";
import { decir } from "@/lib/pedir";

describe("fechas", () => {
  it("cuenta días hábiles después de a y hasta b", () => {
    const lunes = dia0("2026-10-19");
    expect(habiles(lunes, lunes + 4)).toBe(4);        // martes a viernes
    expect(habiles(lunes, lunes + 7)).toBe(5);        // hasta el lunes siguiente, sin el fin de semana
    expect(habiles(lunes + 7, lunes)).toBe(-5);
  });
  it("encuentra el lunes de una semana", () => {
    expect(lunesDe("2026-10-22")).toBe("2026-10-19");
    expect(lunesDe("2026-10-19")).toBe("2026-10-19");
    expect(lunesDe("2026-10-25")).toBe("2026-10-19");
  });
  it("escribe la fecha en español", () => {
    expect(fecha("2026-10-19")).toBe("19 de octubre");
    expect(fecha(null)).toBe("sin fecha");
    expect(corta("2026-03-05")).toBe("5 mar");
  });
  it("dice en cuánto es una fecha", () => {
    const hoy = new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 10);
    expect(enCuanto(hoy)).toBe("hoy");
  });
});

describe("texto", () => {
  it("escribe el trabajo en días", () => {
    expect(enDias(0.5)).toBe("medio día");
    expect(enDias(1)).toBe("un día");
    expect(enDias(2.5)).toBe("2,5 días");
    expect(esfuerzo(5)).toBe("una semana");
    expect(esfuerzo(7)).toBe("7 días de trabajo");
  });
  it("junta nombres y cuenta", () => {
    expect(lista(["Ana"])).toBe("Ana");
    expect(lista(["Ana", "Luis"])).toBe("Ana y Luis");
    expect(lista(["Ana", "Luis", "Teo"])).toBe("Ana, Luis y Teo");
    expect(uno(1, "una tarea", "tareas")).toBe("una tarea");
    expect(uno(3, "una tarea", "tareas")).toBe("3 tareas");
  });
  it("escribe y lee pesos", () => {
    expect(pesos(1250000)).toBe("$1.250.000");
    expect(pesos(-500)).toBe("−$500");
    expect(pesos(null)).toBe("sin valor");
    expect(plata("1.250.000")).toBe(1250000);
  });
  it("iniciales, fases y WhatsApp", () => {
    expect(iniciales("Luisa Fernanda Ríos")).toBe("LF");
    expect(nFase("proyecto_final")).toBe("Proyecto Final");
    expect(whatsapp("3001112233")).toBe("https://wa.me/573001112233");
    expect(whatsapp("")).toBe("");
  });
});

describe("plazo", () => {
  const hoy = "2026-10-19";   // lunes
  it("una tarea vencida va en tierra y cuenta los días hábiles de atraso", () => {
    const p = plazo({ fecha_inicio: "2026-10-12", fecha_compromiso: "2026-10-16", estado: "en_curso" }, hoy);
    expect(p.k).toBe("c");
    expect(p.txt).toBe("Vencida 1 d");
    expect(p.pct).toBe(100);
  });
  it("una tarea que vence en dos días hábiles o menos va en ocre", () => {
    expect(plazo({ fecha_inicio: "2026-10-19", fecha_compromiso: "2026-10-21", estado: "asignada" }, hoy).k).toBe("a");
    expect(plazo({ fecha_inicio: "2026-10-19", fecha_compromiso: "2026-10-19", estado: "asignada" }, hoy).txt).toBe("Vence hoy");
    expect(plazo({ fecha_inicio: "2026-10-19", fecha_compromiso: "2026-10-20", estado: "asignada" }, hoy).txt).toBe("Falta 1 d");
  });
  it("una tarea a tiempo, en revisión, terminada o sin fecha", () => {
    expect(plazo({ fecha_inicio: "2026-10-19", fecha_compromiso: "2026-10-30", estado: "en_curso" }, hoy)).toMatchObject({ k: "", txt: "Faltan 9 d" });
    expect(plazo({ fecha_inicio: "2026-10-12", fecha_compromiso: "2026-10-16", estado: "en_revision" }, hoy)).toMatchObject({ k: "r", txt: "Pidió revisión" });
    expect(plazo({ fecha_compromiso: "2026-10-16", estado: "terminada", terminada_en: "2026-10-15T20:00:00Z" }, hoy)).toMatchObject({ k: "h", txt: "Entregada 15 oct" });
    expect(plazo({ fecha_compromiso: null }, hoy)).toMatchObject({ k: "n", txt: "Sin fecha" });
  });
  it("reparte las tareas por tramos, como las listas de Trello", () => {
    expect(tramo({ fecha_compromiso: "2026-10-16", estado: "asignada" }, hoy)).toBe("vencidas");
    expect(tramo({ fecha_compromiso: "2026-10-19", estado: "asignada" }, hoy)).toBe("hoy");
    expect(tramo({ fecha_compromiso: "2026-10-25", estado: "asignada" }, hoy)).toBe("semana");
    expect(tramo({ fecha_compromiso: "2026-10-26", estado: "asignada" }, hoy)).toBe("despues");
    expect(tramo({ fecha_compromiso: null, estado: "asignada" }, hoy)).toBe("sin");
    expect(tramo({ fecha_compromiso: "2026-10-16", estado: "en_revision" }, hoy)).toBe("revision");
  });
  it("la capacidad se lee en frases", () => {
    expect(libres({ dias_habiles: 5, dias_ocupados: 3 })).toBe(2);
    expect(leeCarga({ dias_habiles: 5, dias_ocupados: 6 })).toEqual({ texto: "Tiene un día más de lo que cabe", pasada: true });
    expect(leeCarga({ dias_habiles: 5, dias_ocupados: 4.8 }).texto).toBe("Semana llena");
    expect(leeCarga({ dias_habiles: 0, dias_ocupados: 0 }).texto).toBe("Sin días hábiles en la semana");
  });
  it("lo libre en un tramo suma las semanas que toca, a prorrata de sus días", () => {
    const sem = [{ persona_id: "p", nombre: "P", semana: "2026-10-19", dias_habiles: 5, dias_ocupados: 2, tareas: 1, sin_estimar: 0, vencidas: 0 },
                 { persona_id: "p", nombre: "P", semana: "2026-10-26", dias_habiles: 5, dias_ocupados: 0, tareas: 0, sin_estimar: 0, vencidas: 0 }];
    const t = tramoLibre(sem, "2026-10-19", "2026-10-23");   // toda la primera semana
    expect(t).toMatchObject({ dias_habiles: 5, dias_ocupados: 2, libre: 3, fuera: false });
    expect(tramoLibre(sem, "2026-10-22", "2026-10-27").dias_habiles).toBeCloseTo(4);   // jueves y viernes + lunes y martes
    expect(tramoLibre(sem, "2026-11-20", "2026-11-25").fuera).toBe(true);
  });
  it("una fase se lee por su estado y su avance", () => {
    const av = new Map([["b", { fase_id: "b", tareas: 4, terminadas: 2 }]]);
    expect(estadoFase({ id: "a", estado: "cerrada", fase: "insight" }, av, hoy)).toMatchObject({ k: "cerrada", pct: 0 });
    expect(estadoFase({ id: "b", estado: "en_curso", fase: "anteproyecto", fecha_compromiso: "2026-10-30" }, av, hoy)).toMatchObject({ k: "curso", pct: 50 });
    expect(estadoFase({ id: "b", estado: "en_curso", fase: "anteproyecto", fecha_compromiso: "2026-10-10" }, av, hoy)).toMatchObject({ k: "tarde", dice: "vencida" });
    expect(avanceTotal([{ tareas: 4, terminadas: 2 }, { tareas: 2, terminadas: 1 }])).toEqual({ tot: 6, hechas: 3, pct: 50 });
  });
});

describe("rutas y errores", () => {
  it("escribe la misma ruta siempre igual", () => {
    expect(clave("/tarea/?id=t1")).toBe("/tarea?id=t1");
    expect(clave("/")).toBe("/");
    expect(clave(R.proyecto("p1", "lista"))).toBe("/proyecto?id=p1&vista=lista");
  });
  it("traduce lo que la base dice", () => {
    expect(decir({ message: "new row violates row-level security policy" })).toBe("No tiene permiso para hacer esto.");
    expect(decir({ message: "D9 · La tarea vencida avisa" })).toBe("La tarea vencida avisa");
    expect(decir(new Error("Failed to fetch"))).toBe("No hay conexión. Revise la señal e intente de nuevo.");
  });
});
