# Dónde están los datos reales

Todo vive en Google Drive, sincronizado en la Mac de Felipe bajo
`~/Library/CloudStorage/`. Una sesión en la nube **no tiene estas carpetas**:
para cargar datos nuevos hace falta la Mac de Felipe o que él suba el archivo.

| Qué | Dónde | Lo usa |
|---|---|---|
| Libro mayor 2024–2026 | `GoogleDrive-esa.documentos@gmail.com/Mi unidad/03 Contabilidad/01 FINANANZAS/` (hoja `RELACION PAGOS ESA`, encabezado en la fila 11; de 2026 se toma el corte `CONSOLIDADO*` más reciente) | `scripts/etl/cargar_historico.py` |
| Balances de Nirvana | `GoogleDrive-estudio.esa.arquitectura@gmail.com/Mi unidad/04_2026/04_26 Obra Nirvana/03_Presupuesto/balances/` | `scripts/etl/cargar_balance_obra.py` |
| Cotizaciones | `GoogleDrive-esa.documentos@gmail.com/Mi unidad/04 Cotizaciones/<año>/NN_AA Nombre` (una carpeta «Contrato» indica que se ganó) | reconstrucción del embudo |
| Transcripciones de citas | `GoogleDrive-<cuenta personal de Felipe>/Mi unidad/Google Meet` | análisis de ventas |
| Hoja de tareas del equipo | Google Sheets `1ARIj8XqRZAhR1yFF1nWzzNz1oNpKEOQVzvYt8q7OgTU` («Seguimiento tareas ESA 2026») | importación pendiente |
| Mercadeo y ventas 2026 | Drive `1qdMDLQM3-dBUA0TMAWq8AdmGENmy4cAP` | contexto de Allison |

**Cómo está armado el libro mayor:**
- La columna `CENTROS DE COSTOS` **es el proyecto**.
- El centro de costo real es el cruce de proyecto × `CATEGORIA PAGOS`.
- `CATEGORIA INGRESOS` son líneas de servicio, no canales.
- El libro no trae el canal de adquisición: la atribución está en
  `03 Contabilidad/ANALISIS VENTAS.xlsx`.

**Cómo está armado el balance de obra:**
- Desde el 02-10-2026 los adicionales vienen como «MOD-» dentro de cada capítulo.
- La observación del ítem reemplazado dice qué MOD lo sustituye.
- El bloque de la derecha (columnas Q–U) suma el VALOR FINAL.
- La columna O es el porcentaje de avance.

**Carpeta hermana `../documentos/`** (fuera del repositorio, nunca a GitHub):
- la negociación de adicionales de Nirvana;
- la reconstrucción de cotizaciones 2026;
- los tratos cerrados de Pipedrive;
- la lista de reactivación de clientes;
- las transcripciones de citas;
- el prototipo y el documento de arquitectura en HTML.
