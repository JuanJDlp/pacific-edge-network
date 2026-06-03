// Managed by Ansible — do not edit on the RPi directly.
// Resuelve las tarjetas de Kiwix (data-zim-category) contra el catálogo OPDS de
// Kiwix-serve y rellena la sección "Descubre" con un artículo al azar por ZIM.
// Diseñado para ser tolerante a fallos: si Kiwix no responde, las tarjetas
// quedan con su href de fallback (/viewer) y "Descubre" se oculta.

(function () {
    "use strict";

    var CATALOG_URL = "/catalog/v2/entries";
    var CATALOG_SESSION_KEY = "biblioteca:catalog:v1";
    var CATALOG_TTL_MS = 5 * 60 * 1000;       // 5 min — refleja cambios tras update-kiwix-content
    var FETCH_TIMEOUT_MS = 4000;              // por request individual

    function fetchWithTimeout(url, opts) {
        var ctrl = new AbortController();
        var t = setTimeout(function () { ctrl.abort(); }, FETCH_TIMEOUT_MS);
        var merged = Object.assign({}, opts || {}, { signal: ctrl.signal });
        return fetch(url, merged).finally(function () { clearTimeout(t); });
    }

    function loadCatalogFromSession() {
        try {
            var raw = sessionStorage.getItem(CATALOG_SESSION_KEY);
            if (!raw) return null;
            var parsed = JSON.parse(raw);
            if (!parsed || (Date.now() - parsed.ts) > CATALOG_TTL_MS) return null;
            return parsed.entries;
        } catch (_) { return null; }
    }

    function saveCatalogToSession(entries) {
        try {
            sessionStorage.setItem(CATALOG_SESSION_KEY, JSON.stringify({
                ts: Date.now(),
                entries: entries
            }));
        } catch (_) { /* quota / disabled — no-op */ }
    }

    // Devuelve un array de { category, title, name, contentPath, summary }
    // donde contentPath es algo como "/content/wikipedia_es_all_mini_2026-05"
    // y name es el nombre versionado del libro (sin "/content/").
    // Importante: el feed OPDS usa xmlns="http://www.w3.org/2005/Atom".
    // Safari es estricto con namespaces — usamos getElementsByTagNameNS("*", ...)
    // para no depender del prefijo o de la default-namespace.
    function parseCatalog(xmlText) {
        var doc = new DOMParser().parseFromString(xmlText, "application/xml");
        if (doc.querySelector("parsererror")) {
            console.warn("[biblioteca] catalogo: parse XML fallo");
            return [];
        }
        var entries = Array.prototype.slice.call(getAllNS(doc, "entry"));
        var parsed = entries.map(function (entry) {
            var category = textOfNS(entry, "category");
            var title    = textOfNS(entry, "title");
            var summary  = textOfNS(entry, "summary");
            // Elegir el <link type="text/html"> — apunta a /content/<name versionado>
            var htmlLink = null;
            var links = getAllNS(entry, "link");
            for (var i = 0; i < links.length; i++) {
                if (links[i].getAttribute("type") === "text/html") {
                    htmlLink = links[i].getAttribute("href");
                    break;
                }
            }
            if (!category || !htmlLink) return null;
            var contentPath = htmlLink.replace(/\/$/, "");
            var name = contentPath.replace(/^\/content\//, "");
            return {
                category: category,
                title: title || category,
                name: name,
                contentPath: contentPath,
                summary: summary || ""
            };
        }).filter(Boolean);
        return parsed;
    }

    function getAllNS(parent, localName) {
        // getElementsByTagNameNS("*", X) = "cualquier namespace, localName=X"
        if (parent.getElementsByTagNameNS) {
            return parent.getElementsByTagNameNS("*", localName);
        }
        return parent.getElementsByTagName(localName);
    }

    function textOfNS(parent, localName) {
        var el = getAllNS(parent, localName)[0];
        return el ? (el.textContent || "").trim() : "";
    }

    function getCatalog() {
        var cached = loadCatalogFromSession();
        if (cached) return Promise.resolve(cached);
        return fetchWithTimeout(CATALOG_URL, { credentials: "same-origin" })
            .then(function (r) {
                if (!r.ok) throw new Error("catalog HTTP " + r.status);
                return r.text();
            })
            .then(function (xml) {
                var entries = parseCatalog(xml);
                if (entries.length) saveCatalogToSession(entries);
                return entries;
            });
    }

    // Reescribe los href de las .card[data-zim-category] al path versionado.
    function rewriteCards(entries) {
        var byCategory = {};
        entries.forEach(function (e) { byCategory[e.category] = e; });
        var cards = document.querySelectorAll(".card[data-zim-category]");
        Array.prototype.forEach.call(cards, function (card) {
            var cat = card.getAttribute("data-zim-category");
            var entry = byCategory[cat];
            if (entry) {
                card.setAttribute("href", entry.contentPath + "/");
            }
        });
    }

    // Extrae el título de un artículo desde el HTML devuelto por /random.
    function extractArticleTitle(html) {
        var m = html.match(/<title>([\s\S]*?)<\/title>/i);
        if (!m) return null;
        var t = m[1].replace(/\s+/g, " ").trim();
        // Kiwix añade el sufijo del ZIM al final: "Artículo - Wikipedia"
        t = t.replace(/\s*[—\-\|]\s*(Wikipedia|Wikilibro|Wikibooks|Wikinoticias|Wikinews|Wikiversidad|Wikiversity|Wikiviajes|Wikivoyage).*$/i, "");
        return t || null;
    }

    function pickRandomArticle(entry) {
        var url = "/random?content=" + encodeURIComponent(entry.name);
        return fetchWithTimeout(url, { credentials: "same-origin", redirect: "follow" })
            .then(function (r) {
                if (!r.ok) throw new Error("random HTTP " + r.status);
                return r.text().then(function (html) {
                    return {
                        articleUrl: r.url,                  // URL final tras el 302
                        title: extractArticleTitle(html)
                    };
                });
            });
    }

    function populateDescubre(entries) {
        var container = document.getElementById("descubre-cards");
        if (!container) return;
        var byCategory = {};
        entries.forEach(function (e) { byCategory[e.category] = e; });
        var cards = container.querySelectorAll(".descubre__card[data-zim-category]");
        var pending = cards.length;
        var succeeded = 0;

        if (!pending) {
            container.setAttribute("data-state", "empty");
            return;
        }

        Array.prototype.forEach.call(cards, function (card) {
            var cat = card.getAttribute("data-zim-category");
            var entry = byCategory[cat];
            if (!entry) {
                renderFallbackCard(card, cat, null);
                if (--pending === 0) finalize();
                return;
            }
            pickRandomArticle(entry)
                .then(function (result) {
                    if (result.title && result.articleUrl) {
                        renderArticleCard(card, entry, result.title, result.articleUrl);
                        succeeded++;
                    } else {
                        renderFallbackCard(card, cat, entry);
                    }
                })
                .catch(function () {
                    renderFallbackCard(card, cat, entry);
                })
                .finally(function () {
                    if (--pending === 0) finalize();
                });
        });

        function finalize() {
            container.setAttribute("data-state", succeeded > 0 ? "ready" : "error");
        }
    }

    function renderArticleCard(card, entry, title, articleUrl) {
        card.classList.remove("descubre__card--skeleton");
        card.setAttribute("data-state", "ready");
        // Convertir el <article> en un link clickeable envolviendo su contenido
        var sourceLabel = entry.title || entry.category;
        card.innerHTML =
            '<a class="descubre__link" href="' + escapeAttr(articleUrl) + '">' +
              '<span class="descubre__source">' + escapeHtml(sourceLabel) + '</span>' +
              '<span class="descubre__title">' + escapeHtml(title) + '</span>' +
              '<span class="descubre__cta">Leer →</span>' +
            '</a>';
    }

    function renderFallbackCard(card, category, entry) {
        card.classList.remove("descubre__card--skeleton");
        card.setAttribute("data-state", "fallback");
        var sourceLabel = entry ? (entry.title || category) : capitalize(category);
        var href = entry ? (entry.contentPath + "/") : "/viewer";
        card.innerHTML =
            '<a class="descubre__link" href="' + escapeAttr(href) + '">' +
              '<span class="descubre__source">' + escapeHtml(sourceLabel) + '</span>' +
              '<span class="descubre__title">Explora el contenido</span>' +
              '<span class="descubre__cta">Abrir →</span>' +
            '</a>';
    }

    // Cuando no hay catalogo (Kiwix caido / parse fallo), reemplazamos cada
    // skeleton por una tarjeta fallback que al menos lleva al book picker.
    // NUNCA ocultamos la seccion: la idea es que el usuario siempre tenga algo.
    function renderDescubreFallback() {
        var container = document.getElementById("descubre-cards");
        if (!container) return;
        var cards = container.querySelectorAll(".descubre__card[data-zim-category]");
        Array.prototype.forEach.call(cards, function (card) {
            renderFallbackCard(card, card.getAttribute("data-zim-category"), null);
        });
        container.setAttribute("data-state", "fallback");
    }

    function escapeHtml(s) {
        return String(s).replace(/[&<>"']/g, function (c) {
            return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
        });
    }
    function escapeAttr(s) { return escapeHtml(s); }
    function capitalize(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s; }

    function boot() {
        getCatalog()
            .then(function (entries) {
                if (!entries || !entries.length) {
                    console.warn("[biblioteca] catalogo vacio — Descubre en modo fallback");
                    renderDescubreFallback();
                    return;
                }
                rewriteCards(entries);
                populateDescubre(entries);
            })
            .catch(function (err) {
                // Sin catalogo (Kiwix caido, TLS rechazado, parse fallo):
                // dejar tarjetas de "Explora" con su /viewer y renderizar fallback
                // en Descubre para que la seccion no quede en blanco.
                console.warn("[biblioteca] catalogo fallo:", err);
                renderDescubreFallback();
            });
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", boot);
    } else {
        boot();
    }
})();
