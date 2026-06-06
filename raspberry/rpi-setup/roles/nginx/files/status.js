/* ============================================================================
   status.js - Polls /status (written by health-check.sh) and updates the
   live indicator. No frameworks.
   ============================================================================ */
(function () {
    'use strict';

    var REFRESH_MS = 30000;
    var TEMP_WARN  = 70;
    var TEMP_FAIL  = 75;
    var DISK_WARN  = 80;
    var DISK_FAIL  = 85;

    function el(sel) { return document.querySelector(sel); }

    function setStatus(level, text) {
        var dot = el('.status-dot');
        var lbl = el('.status-text');
        if (!dot || !lbl) return;
        dot.className = 'status-dot status-dot--' + level;
        lbl.textContent = text;
    }

    function summarise(data) {
        var s = data.services || {};
        var sys = data.system || {};
        var c = data.content || {};

        // Treat "N/A" (Jellyfin not installed) as not-a-failure.
        var down = Object.keys(s).filter(function (k) {
            return s[k] !== 'OK' && s[k] !== 'N/A';
        });

        if (down.length) {
            return { level: 'fail',
                     text:  'Servicios con problema: ' + down.join(', ') };
        }
        if (c.zim_count === 0) {
            return { level: 'warn',
                     text:  'Sin contenido cargado · ejecutar download-zims.sh' };
        }
        if (sys.cpu_temp_c >= TEMP_FAIL || sys.disk_used_pct >= DISK_FAIL) {
            return { level: 'fail',
                     text:  'Sistema sobrecargado · avisar al encargado' };
        }
        if (sys.cpu_temp_c >= TEMP_WARN || sys.disk_used_pct >= DISK_WARN) {
            return { level: 'warn',
                     text:  'Sistema funcionando · revisar pronto' };
        }
        return { level: 'ok',
                 text:  'Funcionando · ' + (c.zim_count || 0) + ' fuentes cargadas' };
    }

    function tick() {
        fetch('/status', { cache: 'no-store' })
            .then(function (r) {
                if (!r.ok) throw new Error('HTTP ' + r.status);
                return r.json();
            })
            .then(function (data) {
                var s = summarise(data);
                setStatus(s.level, s.text);
            })
            .catch(function () {
                setStatus('warn', 'Estado del sistema no disponible');
            });
    }

    tick();
    setInterval(tick, REFRESH_MS);
})();
