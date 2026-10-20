// Recorre cada pantalla en modo demo (entrando como Luisa, que dirige todo):
// abre, espera a que la base de mentira responda, exige que no haya errores de
// JavaScript ni el aviso «No se pudo abrir», y guarda una captura para mirar.
import { test, expect, type Page } from "@playwright/test";

// Los identificadores son los de scripts/demo (datos_ejemplo.py + armar.py --web + demo_proyectos.py).
const PANTALLAS: [string, string, RegExp][] = [
  ["mi-dia", "/", /Mi día/],
  ["tarea", "/tarea/?id=t05", /Diseño del walking closet/],
  ["nueva", "/nueva/?proyecto=pr1", /Repartir tareas/],
  ["revisar", "/revisar/", /Revisar/],
  ["proyectos", "/proyectos/", /Proyectos/],
  ["proyecto-tablero", "/proyecto/?id=pr1", /Las Margaritas/],
  ["proyecto-lista", "/proyecto/?id=pr1&vista=lista", /Las Margaritas/],
  ["proyecto-cronograma", "/proyecto/?id=pr1&vista=cronograma", /Las Margaritas/],
  ["proyecto-ficha", "/proyecto/?id=pr1&vista=ficha", /Las Margaritas/],
  ["nuevo-proyecto", "/nuevo-proyecto/", /Crear proyecto nuevo/],
  ["tipicas", "/tipicas/?fase=f_pr1_anteproyecto", /Tareas de anteproyecto/],
  ["cierre", "/cierre/?fase=f_pr1_anteproyecto", /anteproyecto/i],
  ["clave", "/clave/", /Cambiar mi contraseña/],
  ["registro", "/registro/", /Registrar mi día/],
  ["equipo", "/equipo/", /Equipo|Mi carga/],
  ["personas", "/personas/", /Personas/],
  ["mando", "/mando/", /Centro de mando/],
  ["impacto", "/impacto/", /Impacto/],
  ["ventas", "/ventas/", /Ventas/],
  ["embudo", "/embudo/?linea=diseno&etapa=presupuesto_detallado", /Cotización en preparación/],
  ["oportunidad", "/oportunidad/?id=o1", /Casa en Cerritos/],
  ["reporte", "/reporte/?cita=c3", /Después de la cita/],
  ["contacto", "/contacto/?id=l7", /Mónica Herrera/],
  ["contacto-nuevo", "/contacto-nuevo/", /Nuevo contacto/],
  ["tarifas", "/tarifas/", /Tarifas de diseño/],
  ["obras", "/obras/", /Obras/],
  ["obra-resumen", "/obra/?id=ob1", /Casa en La Florida/],
  ["obra-gastos", "/obra/?id=ob1&seccion=gastos", /Casa en La Florida/],
  ["obra-flujo", "/obra/?id=ob1&seccion=flujo", /Casa en La Florida/],
  ["obra-documentos", "/obra/?id=ob1&seccion=documentos", /Casa en La Florida/],
  ["obra-pendientes", "/obra/?id=ob1&seccion=pendientes", /Casa en La Florida/],
  ["obra-sitio", "/obra/?id=ob1&seccion=sitio", /Casa en La Florida/],
  ["yo", "/yo/", /Luisa/],
];

async function abrir(page: Page, ruta: string) {
  const errores: string[] = [];
  page.on("pageerror", (e) => errores.push(e.message));
  page.on("console", (m) => { if (m.type() === "error") errores.push(m.text()); });
  await page.goto(ruta);
  await expect(page.locator("header.cab h1")).toBeVisible({ timeout: 30_000 });
  await expect(page.locator("header.cab h1")).not.toHaveText("No se pudo abrir");
  return errores;
}

for (const [nombre, ruta, titulo] of PANTALLAS) {
  test(`abre ${nombre}`, async ({ page }) => {
    const errores = await abrir(page, ruta);
    await expect(page.locator("body")).toContainText(titulo);
    await page.screenshot({ path: `e2e/capturas/${nombre}.png`, fullPage: true });
    expect(errores.filter((e) => !/favicon|Download the React DevTools/i.test(e)), "errores en consola").toEqual([]);
  });
}

test("el pie lleva a las secciones y Mi día tiene sus grupos", async ({ page }) => {
  await abrir(page, "/");
  await expect(page.locator("nav.pie a")).toHaveCount(6);
  await expect(page.locator(".grupo", { hasText: "Mi semana" })).toBeVisible();
  await page.locator("nav.pie a", { hasText: "Proyectos" }).click();
  await expect(page.locator("header.cab h1")).toHaveText("Proyectos");
  await expect(page.locator("a.pr")).toHaveCount(5);   // los cinco proyectos de la hoja de Luisa en la demo
});

test("entregar una tarea recorre el formulario y vuelve con el aviso", async ({ page }) => {
  await abrir(page, "/nueva/?proyecto=pr1");
  await page.fill("#ti0", "Probar el recorrido");
  // Primero las fechas y el trabajo; con eso se habilita el responsable, ordenado por lo libre en ese tramo.
  await page.fill("#fe0", "2026-12-18");
  await page.selectOption("#es0", "1");
  await expect(page.locator("#qu0")).toBeEnabled();
  await page.locator("#qu0 option").nth(1).waitFor({ state: "attached" });
  const responsable = await page.locator("#qu0 option").nth(1).getAttribute("value");
  await page.selectOption("#qu0", responsable!);
  // Requiere revisión: la revisa alguien distinto de quien la entrega.
  const revisores = await page.locator("#rv0 option").evaluateAll((os) => os.map((o) => (o as HTMLOptionElement).value).filter(Boolean));
  await page.selectOption("#rv0", revisores.find((v) => v !== responsable)!);
  await page.locator("p.pista").first().waitFor();
  await page.click("#entregar");
  await expect(page.locator("header.cab h1")).toHaveText(/Equipo|Mi carga/);
  await expect(page.locator(".bien")).toContainText(/entregada|creada/i);
});
