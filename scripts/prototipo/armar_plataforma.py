# -*- coding: utf-8 -*-
"""Mete en el prototipo de la plataforma los módulos que se arman con datos.

Toma documentos/sici-plataforma.html y reemplaza:
  · «01 Obra» por el tablero de todas las obras y la ficha de cada una
    (modulo_obra_plataforma.txt + los datos de exportar_obras.py);
  · «Diseño» por «Arquitectura y diseño»
    (modulo_diseno_plataforma.txt + los datos de exportar_vista_previa.py).
Y redibuja el menú en cascada (navegacion_plataforma.txt): cada módulo despliega
sus espacios, y «Registro en sitio» queda dentro de Obra.
Se puede correr las veces que haga falta.

    .venv/bin/python scripts/base/exportar_vista_previa.py diseno.json
    .venv/bin/python scripts/prototipo/exportar_obras.py obras.json
    python3 scripts/prototipo/armar_plataforma.py diseno.json obras.json

El resultado lleva datos reales de la empresa: vive en documentos/, fuera del
repositorio.
"""
import json, re, shutil, sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
PLATAFORMA = RAIZ.parent / "documentos" / "sici-plataforma.html"
RESPALDO = RAIZ.parent / "documentos" / "anterior" / "sici-plataforma-2026-08-29.html"

t = PLATAFORMA.read_text(encoding="utf-8")
if not RESPALDO.exists():
    RESPALDO.parent.mkdir(exist_ok=True)
    shutil.copy2(PLATAFORMA, RESPALDO)
original = RESPALDO.read_text(encoding="utf-8")

# El detalle de Nirvana (variación, capítulos, adicionales) se conserva tal como estaba.
a = original.index('    <div class="hero bad">\n      <div class="hero-k lbl">Costo final proyectado</div>')
b = original.index('    <div class="foot lbl">Fuente · BALANCE')
NIRVANA = original[a:b].rstrip("\n")


def modulo(t, clave, plantilla, datos, desde, hasta, extra=None):
    partes = re.split(r"^===(CSS|HTML|JS)===\n", (RAIZ / "scripts/prototipo" / plantilla).read_text(encoding="utf-8"), flags=re.M)
    mod = dict(zip(partes[1::2], partes[2::2]))
    html = mod["HTML"]
    for k, v in (extra or {}).items():
        html = html.replace(k, v)
    js = mod["JS"].replace("/*DATOS*/", json.dumps(datos, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/"))
    a, b = t.index(desde), t.index(hasta)
    t = t[:a] + desde + "\n" + html + t[b:]
    t = re.sub(r"/\* %s-CSS \*/.*?/\* /%s-CSS \*/\n" % (clave, clave), "", t, flags=re.S)
    i = t.index("</style>")
    t = t[:i] + "/* %s-CSS */\n" % clave + mod["CSS"] + "/* /%s-CSS */\n" % clave + t[i:]
    t = re.sub(r'<script id="%s-js">.*?</script>\n' % clave.lower(), "", t, flags=re.S)
    return t.rstrip("\n") + '\n<script id="%s-js">\n' % clave.lower() + js + "</script>\n"


diseno = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
t = modulo(t, "DZ", "modulo_diseno_plataforma.txt", diseno,
           "  <!-- ============ DISEÑO ============ -->", "  <!-- ============ VENTAS ============ -->")
if len(sys.argv) > 2:
    obras = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
    t = modulo(t, "OB", "modulo_obra_plataforma.txt", obras,
               "  <!-- ============ OBRA ============ -->", "  <!-- ============ CAPTURA ============ -->",
               {"<!--NIRVANA-->": NIRVANA})

# La navegación en cascada: el menú se dibuja desde una sola lista de módulos y espacios
partes = re.split(r"^===(CSS|JS)===\n", (RAIZ / "scripts/prototipo/navegacion_plataforma.txt").read_text(encoding="utf-8"), flags=re.M)
nav = dict(zip(partes[1::2], partes[2::2]))
pendientes = sum(1 for c in diseno["cola"] if c["fuera_de_plazo"]) + sum(1 for c in diseno["carga"] if c["vencidas"] > 0)
t = re.sub(r'<div class="navlist"[^>]*>.*?</div>\n</nav>', '<div class="navlist" id="navlist"></div>\n</nav>', t, flags=re.S)
t = re.sub(r"/\* NAV-CSS \*/.*?/\* /NAV-CSS \*/\n", "", t, flags=re.S)
i = t.index("</style>")
t = t[:i] + "/* NAV-CSS */\n" + nav["CSS"] + "/* /NAV-CSS */\n" + t[i:]
guion = '<script id="nav-js">\n' + nav["JS"].replace("/*PEND_DISENO*/", str(pendientes)) + "</script>\n"
t, n = re.subn(r'<script id="nav-js">.*?</script>\n', lambda m: guion, t, flags=re.S)
if not n:   # la primera vez: sale el guion original, que traía los títulos de cada módulo
    t, n = re.subn(r"<script>\s*\(function\(\)\{\s*var titulos=.*?</script>\n", lambda m: guion, t, flags=re.S)
assert n == 1, "no encontré el guion de navegación"
# El guion de navegación va de último: llama a los módulos, que ya deben existir.
t = t.replace(guion, "").rstrip("\n") + "\n" + guion

# El logo de la marca, tal cual: solo se le da el ancho (ver marca/LEAME.md).
import base64
logo = base64.b64encode((RAIZ / "public/logo.png").read_bytes()).decode()
marca = ('<div class="brand">\n    <img class="brand-logo" width="1000" height="431" alt="ESA Arquitectura" src="data:image/png;base64,' + logo + '">\n'
         '    <div class="brand-sys">SICI · CONTROL INTERNO</div>\n  </div>')
t, n = re.subn(r'<div class="brand">.*?<div class="brand-sys">[^<]*</div>\s*</div>', lambda m: marca, t, flags=re.S)
assert n == 1, "no encontré la marca del menú"
t = re.sub(r"/\* LOGO-CSS \*/.*?/\* /LOGO-CSS \*/\n", "", t, flags=re.S)
i = t.index("</style>")
t = t[:i] + """/* LOGO-CSS */
.brand-logo{display:block;width:128px;height:auto;}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]) .brand-logo{filter:invert(1);}}
:root[data-theme="dark"] .brand-logo{filter:invert(1);}
@media (max-width:860px){.brand-logo{width:96px;}}
/* /LOGO-CSS */
""" + t[i:]

PLATAFORMA.write_text(t, encoding="utf-8")
print("escrito", PLATAFORMA, len(t), "bytes")
