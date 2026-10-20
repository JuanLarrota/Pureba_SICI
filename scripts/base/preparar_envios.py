# -*- coding: utf-8 -*-
"""Prepara las migraciones para aplicarlas a Supabase por el conector, sin contraseña.

Parte cada archivo en trozos que terminan en una sentencia completa y envuelve
cada uno en un bloque que calcula su md5 dentro de la base: si el texto llegó
alterado, la base lo rechaza y no ejecuta nada.

    python scripts/base/preparar_envios.py <carpeta_de_salida> [tamaño_en_bytes]

Así se aplicaron las 11 migraciones el 5 de octubre de 2026."""
import hashlib, json, re, sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]          # la raíz del repositorio
SALIDA = Path(sys.argv[1]) if __name__ == "__main__" else None
OBJETIVO = int(sys.argv[2]) if __name__ == "__main__" and len(sys.argv) > 2 else 15000
DOLAR = re.compile(r"\$[A-Za-z_]*\$")

def sentencias(t):
    """Devuelve las posiciones donde termina cada sentencia de nivel superior."""
    cortes, i, n = [], 0, len(t)
    while i < n:
        c = t[i]
        if t.startswith("--", i):
            j = t.find("\n", i); i = n if j < 0 else j + 1
        elif t.startswith("/*", i):
            j = t.find("*/", i); i = n if j < 0 else j + 2
        elif c == "'":
            i += 1
            while i < n:
                if t[i] == "'":
                    if i + 1 < n and t[i+1] == "'": i += 2; continue
                    i += 1; break
                i += 1
        elif c == "$":
            m = DOLAR.match(t, i)
            if m:
                j = t.find(m.group(0), m.end())
                assert j >= 0, "bloque $ sin cerrar en %d" % i
                i = j + len(m.group(0))
            else: i += 1
        elif c == ";":
            cortes.append(i + 1); i += 1
        else: i += 1
    return cortes

def sin_comentarios_sueltos(trozo):
    """Quita las líneas de comentario de nivel superior. Lo que va dentro de
    $...$ (cuerpos de función) y de las cadenas no se toca."""
    fuera, i, n, protegido = [], 0, len(trozo), []
    # marca los rangos protegidos: cadenas y bloques $
    while i < n:
        c = trozo[i]
        if trozo.startswith("--", i):
            j = trozo.find("\n", i); i = n if j < 0 else j + 1
        elif trozo.startswith("/*", i):
            j = trozo.find("*/", i); i = n if j < 0 else j + 2
        elif c == "'":
            a = i; i += 1
            while i < n:
                if trozo[i] == "'":
                    if i + 1 < n and trozo[i+1] == "'": i += 2; continue
                    i += 1; break
                i += 1
            protegido.append((a, i))
        elif c == "$":
            m = DOLAR.match(trozo, i)
            if m:
                j = trozo.find(m.group(0), m.end()); a = i
                i = j + len(m.group(0)); protegido.append((a, i))
            else: i += 1
        else: i += 1
    def dentro(p):
        return any(a <= p < b for a, b in protegido)
    pos, lineas = 0, []
    for ln in trozo.split("\n"):
        if ln.lstrip().startswith("--") and not dentro(pos + (len(ln) - len(ln.lstrip()))):
            pos += len(ln) + 1; continue
        lineas.append(ln); pos += len(ln) + 1
    limpio = "\n".join(lineas)
    # colapsa líneas en blanco repetidas, solo fuera de zonas protegidas
    if not protegido or True:
        limpio = re.sub(r"\n{3,}", "\n\n", limpio) if "$" not in limpio and "'" not in limpio else limpio
    return limpio.strip("\n") + "\n"

def envolver(contenido):
    assert "$sici_trozo$" not in contenido and "$sici_envoltura$" not in contenido
    h = hashlib.md5(contenido.encode("utf-8")).hexdigest()
    return ("do $sici_envoltura$\n"
            "declare t text := $sici_trozo$" + contenido + "$sici_trozo$;\n"
            "begin\n"
            "  if md5(t) <> '" + h + "' then\n"
            "    raise exception 'SICI: el texto llegó alterado (md5 %)', md5(t);\n"
            "  end if;\n"
            "  execute t;\n"
            "end $sici_envoltura$;\n"), h

def main():
  manifiesto = []
  for f in sorted((RAIZ / "supabase/migrations").glob("*.sql")):
      t = f.read_text(encoding="utf-8")
      cortes = sentencias(t)
      partes, ini, ultimo = [], 0, 0
      for c in cortes:
          if c - ini >= OBJETIVO:
              partes.append(t[ini:c]); ini = c
      if t[ini:].strip(): partes.append(t[ini:])
      assert "".join(partes) == t, f.name
      version, nombre = f.stem.split("_", 1)
      for k, p in enumerate(partes, 1):
          limpio = sin_comentarios_sueltos(p)
          env, h = envolver(limpio)
          destino = SALIDA / ("%s_%s_%02d.sql" % (version[-4:], nombre, k))
          destino.write_text(env, encoding="utf-8")
          manifiesto.append(dict(archivo=destino.name, migracion=f.name, version=version, nombre=nombre,
                                 parte=k, de=len(partes), md5=h, original=len(p), envio=len(env)))
  (SALIDA / "manifiesto.json").write_text(json.dumps(manifiesto, indent=1, ensure_ascii=False), encoding="utf-8")
  print("%d envíos · original %d bytes · a enviar %d bytes · mayor %d" % (
      len(manifiesto), sum(m["original"] for m in manifiesto), sum(m["envio"] for m in manifiesto),
      max(m["envio"] for m in manifiesto)))
  for m in manifiesto:
      print("  %-34s %6d → %6d" % (m["archivo"], m["original"], m["envio"]))


if __name__ == "__main__":
    main()
