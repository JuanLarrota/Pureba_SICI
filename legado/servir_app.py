# -*- coding: utf-8 -*-
"""Sirve la aplicación en este computador, en http://localhost:3000.

Es el mismo puerto que Supabase usa por defecto para devolver a la persona
después de confirmar su correo, así que el registro funciona sin configurar
nada más. Para el equipo, la aplicación va publicada en un sitio con https.

    python3 legado/servir_app.py
"""
import functools, http.server, os
from pathlib import Path

APP = str(Path(__file__).resolve().parent / "app")
os.chdir(APP)

class Sin_cache(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):                      # cada ajuste se ve al recargar
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
    def log_message(self, *a): pass

http.server.ThreadingHTTPServer(("127.0.0.1", 3000), functools.partial(Sin_cache, directory=APP)).serve_forever()
