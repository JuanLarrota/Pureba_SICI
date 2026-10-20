# Marca · ESA Arquitectura

El logo es uno solo y es este. Lo entregó Felipe el 13 de octubre de 2026.

| Archivo | Para qué |
|---|---|
| `esa-arquitectura-original.webp` | El archivo tal como llegó. No se toca. |
| `esa-arquitectura.png` | Negro sobre transparente, 2000 × 862. Para fondos claros. |
| `esa-arquitectura-blanco.png` | El mismo dibujo en blanco. Para fondos oscuros. |

Si existe el archivo vectorial (SVG, AI o PDF), debe ir aquí y reemplazar a los
PNG como fuente: estos salen de una imagen de 2000 puntos de ancho.

## La regla

**El tamaño cambia; la proporción, nunca.** La proporción es 2000 a 862.

- En pantalla se le da **solo el ancho**; el alto lo calcula el navegador
  (`height: auto`). Nunca se escriben ancho y alto a la vez.
- No se estira, no se recorta, no se inclina, no se le cambia el color por otro
  que no sea negro o blanco, y no se redibuja con una tipografía parecida.
- La única reducción exacta en puntos enteros es 1000 × 431. Cualquier otro
  tamaño se obtiene escalando en pantalla, no guardando otro archivo.
- En un ícono cuadrado el logo va completo y centrado sobre blanco, con aire
  alrededor. No se recorta a las letras.

## Dónde está puesto

- La aplicación: `app/logo.png`, `app/logo-blanco.png` y los íconos
  `app/icono-*.png`. Se regeneran desde esta carpeta.
- El prototipo de la plataforma: `scripts/prototipo/armar_plataforma.py` lo incrusta
  en el menú desde `app/logo.png`.
