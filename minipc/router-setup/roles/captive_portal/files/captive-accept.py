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

REDIRECT         = 'http://biblioteca.tel/'  # Destino post-autenticación (resuelve via Bind9)
# HTTP (no HTTPS) intencional: biblioteca.tel sirve cert auto-firmado que dispara
# warning en el browser. Como es tráfico VLAN30 interno (no atraviesa internet),
# HTTP es seguro y evita el "Tu conexión no es privada" post-auth.

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
NFT_SET_NAME     = 'captive_allowed_mac'
VLAN30_IFACE     = 'enp171s0.30'
IPv4_RE          = re.compile(r'^\d{1,3}(\.\d{1,3}){3}$')
MAC_RE           = re.compile(r'lladdr\s+([0-9a-f]{2}(?::[0-9a-f]{2}){5})', re.IGNORECASE)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)


def lookup_mac_for_ip(client_ip):
    """Obtiene la MAC del cliente desde la tabla ARP del kernel.

    La entrada ARP existe con certeza al momento de procesar /accept: el kernel
    ya resolvió la MAC del cliente cuando recibió el SYN de la conexión TCP.
    """
    try:
        result = subprocess.run(
            ['ip', 'neigh', 'show', client_ip, 'dev', VLAN30_IFACE],
            check=True, capture_output=True, text=True, timeout=2
        )
        m = MAC_RE.search(result.stdout)
        if m:
            return m.group(1).lower()
        logging.warning('ARP lookup para %s: sin lladdr en: %r', client_ip, result.stdout)
        return None
    except subprocess.CalledProcessError as e:
        logging.warning('ip neigh falló para %s: %s', client_ip, e.stderr.strip())
        return None
    except subprocess.TimeoutExpired:
        logging.warning('ip neigh timeout para %s', client_ip)
        return None


class AcceptHandler(http.server.BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        logging.info('%s - %s', self.address_string(), fmt % args)

    def do_GET(self):
        # nginx pasa la IP real del cliente via X-Real-IP
        client_ip = self.headers.get('X-Real-IP', self.client_address[0])

        if IPv4_RE.match(client_ip):
            mac = lookup_mac_for_ip(client_ip)
            if mac:
                try:
                    subprocess.run(
                        [
                            'nft', 'add', 'element',
                            NFT_TABLE_FAMILY, NFT_TABLE_NAME, NFT_SET_NAME,
                            '{ ' + mac + ' }',
                        ],
                        check=True, capture_output=True
                    )
                    logging.info('Authorized: IP=%s MAC=%s', client_ip, mac)
                except subprocess.CalledProcessError as e:
                    logging.warning('nft error para %s (%s): %s', client_ip, mac, e.stderr.decode())
            else:
                logging.warning('No se pudo resolver MAC para %s — acceso no concedido', client_ip)

        # NO hacemos `conntrack -D` aquí. Hacerlo MID-respuesta mata el reverse-NAT
        # de los paquetes en vuelo: la respuesta sale con src=192.168.30.1:80 en
        # lugar de la IP/puerto que el browser pidió → el TCP del cliente la descarta
        # → el meta-refresh nunca se procesa → el usuario debe clickear "Aceptar"
        # de nuevo (el famoso bug del doble-click).
        #
        # Es seguro NO flushear porque nginx envía `Connection: close` (keepalive_timeout 0):
        # el browser cierra el TCP al recibir la respuesta. El meta-refresh abre TCP nuevo
        # → nftables lo evalúa fresh → mark=0x1 ya está → sin DNAT → llega directo a la RPi.

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
