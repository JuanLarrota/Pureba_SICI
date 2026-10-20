# La demostración publicada

Es https://claude.ai/artifact/9b3QGprwnwjbxWxamhhFAF: la aplicación real con un
Supabase simulado y tres personas para escoger (Luisa, Mariana, Allison).

`sici.html` es la página. Se publica con estos archivos al lado, que no pueden
empezar por «_»:
- `app.js` y `estilos.css`, copiados de `app/`;
- `config.js`, vacío;
- `supabase_falso.js`, que lee `datos_<persona>.json` según el botón escogido;
- `datos_luisa.json`, `datos_mariana.json` y `datos_allison.json`;
- los logos y el ícono.

Para armar los datos de cada persona:
```bash
python3 pruebas/app_simulada/armar.py vista.json Luisa
python3 pruebas/app_simulada/demo_proyectos.py app/_datos.json Luisa
cp app/_datos.json <carpeta>/datos_luisa.json   # y lo mismo con Mariana y Allison
```

Felipe comenta sobre la página y los cambios se hacen ahí mismo. **Después,
copia `app.js` y `estilos.css` del artefacto a `app/`**: así lo hecho en la
demostración llega a la aplicación real. Revisa también si algún cambio pide
columnas que la base no tiene.
