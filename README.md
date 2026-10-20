# SICI · Sistema Integrado de Control Interno

ESA Arquitectura S.A.S. · Pereira, Colombia.

Un solo sistema que une mercadeo, ventas, diseño por fases, presupuesto, obra y
finanzas, amarrado a **proyecto** y **centro de costo**, para ver la
rentabilidad real de cada proyecto y quién hizo qué.

> El estado al día, las reglas de trabajo y lo que sigue están en [`CLAUDE.md`](CLAUDE.md)
> y en [`docs/contexto/`](docs/contexto/LEAME.md). Léelos antes de tocar nada.

## Qué hay aquí

```
├── src/              la aplicación del equipo: Next.js 16 + TypeScript, exportada estática   → docs/aplicacion.md
├── public/           iconos, logo, manifest de la PWA
├── e2e/              recorridos de Playwright: cada pantalla abre en modo demo
├── supabase/
│   ├── migrations/   la base: tipos, tablas, reglas, vistas que escriben frases (25 migraciones)
│   ├── semilla/      datos iniciales (los reales no viajan a GitHub)
│   └── pruebas/      551 pruebas contra un Postgres real + 170 errores sembrados   → docs/base-de-datos.md
├── scripts/
│   ├── etl/          lee los Excel reales y escribe las semillas
│   ├── base/         tipos para la aplicación, envíos y cargas a producción por el conector
│   ├── demo/         los datos de ejemplo y el arranque en modo demo
│   └── prototipo/    el prototipo HTML anterior al MVP (referencia)
├── docs/             contexto del negocio, marca, guías técnicas
└── legado/           la aplicación anterior (PWA sin compilación), congelada
```

## Puesta en marcha

**La aplicación** (Node 24, solo para desarrollar):

```bash
npm install
npm run dev          # http://localhost:3000 contra el Supabase de producción
npm run demo         # http://localhost:3100 con datos de ejemplo, sin sesión
npm run verificar    # tipos + estilo + pruebas + exportación + recorridos
```

**La base** (Python 3.11; no hace falta Node ni Docker):

```bash
python -m venv .venv
.venv/Scripts/pip install -r scripts/base/requirements.txt        # Mac: .venv/bin/pip
.venv/Scripts/python supabase/pruebas/probar_contra_postgres.py    # Mac: .venv/bin/python
.venv/Scripts/python scripts/base/generar_tipos.py                 # tras cada migración
```

## Reglas que no se negocian

Datos reales nunca van a GitHub. Commit y push solo cuando Felipe lo pida. La
llave `service_role` jamás va al navegador. Nada se borra en la base: se anula o
se retira, con rastro. El detalle, en `CLAUDE.md` §2.
