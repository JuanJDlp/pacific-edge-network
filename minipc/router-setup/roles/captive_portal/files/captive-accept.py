#!/usr/bin/env python3
"""
Captive portal accept handler — Pacific Edge Network
Recibe /accept de nginx, autoriza la IP del cliente en nft, redirige al portal.
"""
import http.server
import socketserver
import subprocess
import logging
import sys
import re

REDIRECT         = 'http://biblioteca.local'   # Destino post-autenticación (resuelve via Bind9)

# HTML de éxito: <TITLE>Success</TITLE> hace que macOS/iOS CNA cierre el popup
# al detectar que la autenticación fue exitosa. El meta-refresh y JS redirigen
# al usuario al portal de la biblioteca.
SUCCESS_HTML = (
    '<HTML><HEAD>'
    '<TITLE>Success</TITLE>'
    '<meta http-equiv="refresh" content="0;url=' + REDIRECT + '">'
    '<script>window.location.replace("' + REDIRECT + '");</script>'
    '</HEAD><BODY>Success'
    '<p>Acceso autorizado. <a href="' + REDIRECT + '">Ir a la biblioteca &rarr;</a></p>'
    '</BODY></HTML>'
).encode('utf-8')
PORT             = 2051
NFT_TABLE_FAMILY = 'inet'
NFT_TABLE_NAME   = 'filter'
NFT_SET_NAME     = 'captive_allowed'
IPv4_RE          = re.compile(r'^\d{1,3}(\.\d{1,3}){3}$')

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)


class AcceptHandler(http.server.BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        logging.info('%s - %s', self.address_string(), fmt % args)

    def do_GET(self):
        # nginx pasa la IP real del cliente via X-Real-IP
        client_ip = self.headers.get('X-Real-IP', self.client_address[0])

        if IPv4_RE.match(client_ip):
            try:
                subprocess.run(
                    [
                        'nft', 'add', 'element',
                        NFT_TABLE_FAMILY, NFT_TABLE_NAME, NFT_SET_NAME,
                        '{ ' + client_ip + ' }',
                    ],
                    check=True, capture_output=True
                )
                logging.info('Authorized: %s', client_ip)
            except subprocess.CalledProcessError as e:
                logging.warning('nft error for %s: %s', client_ip, e.stderr.decode())

        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(SUCCESS_HTML)))
        self.end_headers()
        self.wfile.write(SUCCESS_HTML)


class ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


if __name__ == '__main__':
    server = ThreadingHTTPServer(('127.0.0.1', PORT), AcceptHandler)
    logging.info('Accept handler listening on 127.0.0.1:%d', PORT)
    server.serve_forever()
