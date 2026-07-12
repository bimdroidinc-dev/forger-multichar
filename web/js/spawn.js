/* ==========================================================================
   forger-multicharacter :: spawn selector (decoupled NUI screen)

   Listens only for its own NUI messages so it never collides with app.js:
     { action: 'spawnOpen',  data: { spawns, brand, title, subtitle } }
     { action: 'spawnClose' }
   Sends back:
     POST https://<resource>/spawnSelect  { id: '<tileId>' }
   ========================================================================== */
(function () {
    'use strict';

    var RES = (typeof GetParentResourceName === 'function')
        ? GetParentResourceName() : 'forger-multicharacter';

    function post(cb, body) {
        return fetch('https://' + RES + '/' + cb, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body || {})
        }).catch(function () { /* NUI offline (browser preview) - ignore */ });
    }

    function $(id) { return document.getElementById(id); }

    // ---- inline icon set (lucide-style) -----------------------------------
    function svg(inner) {
        return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
            'stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
            inner + '</svg>';
    }
    var ICONS = {
        'map-pin': svg('<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/><circle cx="12" cy="10" r="3"/>'),
        building: svg('<rect x="4" y="2" width="16" height="20" rx="2"/><path d="M9 22v-4h6v4"/><path d="M8 6h.01M16 6h.01M8 10h.01M16 10h.01M8 14h.01M16 14h.01"/>'),
        plane: svg('<path d="M17.8 19.2 16 11l3.5-3.5C21 6 21.5 4 21 3c-1-.5-3 0-4.5 1.5L13 8 4.8 6.2c-.5-.1-.9.1-1.1.5l-.3.5c-.2.5-.1 1 .3 1.3L9 12l-2 3H4l-1 1 3 2 2 3 1-1v-3l3-2 3.5 5.3c.3.4.8.5 1.3.3l.5-.2c.4-.3.6-.7.5-1.2Z"/>'),
        mountain: svg('<path d="m8 3 4 8 5-5 5 15H2L8 3z"/>'),
        trees: svg('<path d="M10 10v.2A3 3 0 0 1 8.9 16H5a3 3 0 0 1-1-5.8V10a3 3 0 0 1 6 0Z"/><path d="M7 16v6M13 19v3M12 19h8.3a1 1 0 0 0 .7-1.7L18 14h.3a1 1 0 0 0 .7-1.7L16 9h.2a1 1 0 0 0 .8-1.7L13 3l-1.4 1.5"/>'),
        waves: svg('<path d="M2 6c.6.5 1.2 1 2.5 1C7 7 7 5 9.5 5c2.6 0 2.4 2 5 2 2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1"/><path d="M2 12c.6.5 1.2 1 2.5 1 2.5 0 2.5-2 5-2 2.6 0 2.4 2 5 2 2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1"/><path d="M2 18c.6.5 1.2 1 2.5 1 2.5 0 2.5-2 5-2 2.6 0 2.4 2 5 2 2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1"/>'),
        home: svg('<path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><path d="M9 22V12h6v10"/>'),
        briefcase: svg('<rect x="2" y="7" width="20" height="14" rx="2"/><path d="M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"/>'),
        star: svg('<path d="m12 2 3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14l-5-4.87 6.91-1.01L12 2z"/>'),
        history: svg('<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/><path d="M12 7v5l4 2"/>')
    };
    function icon(name) { return ICONS[name] || ICONS['map-pin']; }
    var CHECK = svg('<path d="M20 6 9 17l-5-5"/>');

    // ---- state ------------------------------------------------------------
    var root = $('spawn');
    var grid = $('spawnGrid');
    var confirmBtn = $('spawnConfirm');
    var selectedId = null;

    function open(data) {
        data = data || {};
        var spawns = Array.isArray(data.spawns) ? data.spawns : [];

        // header text
        if (data.brand && data.brand.name) $('spawnEyebrow').textContent = data.brand.name;
        if (data.title) $('spawnTitle').textContent = data.title;
        if (data.subtitle) $('spawnSubtitle').textContent = data.subtitle;

        // build tiles
        grid.innerHTML = '';
        selectedId = null;
        confirmBtn.disabled = true;

        spawns.forEach(function (sp, i) {
            var tile = document.createElement('button');
            tile.type = 'button';
            tile.className = 'spawn-tile';
            tile.setAttribute('role', 'option');
            tile.setAttribute('data-id', sp.id);
            tile.style.animationDelay = (i * 45) + 'ms';

            var flag = sp.last ? '<span class="spawn-tile__flag">LAST</span>' : '';
            tile.innerHTML =
                '<span class="spawn-tile__check">' + CHECK + '</span>' + flag +
                '<span class="spawn-tile__icon">' + icon(sp.icon) + '</span>' +
                '<span class="spawn-tile__label"></span>' +
                '<span class="spawn-tile__desc"></span>';
            // textContent (not innerHTML) so labels can never inject markup
            tile.querySelector('.spawn-tile__label').textContent = sp.label || sp.id || '';
            tile.querySelector('.spawn-tile__desc').textContent = sp.desc || '';

            tile.addEventListener('click', function () { select(sp.id, tile); });
            tile.addEventListener('dblclick', function () { select(sp.id, tile); confirm(); });
            grid.appendChild(tile);
        });

        root.classList.remove('is-hidden');
        root.setAttribute('aria-hidden', 'false');
        // next frame so the transition plays
        requestAnimationFrame(function () { root.classList.add('is-open'); });
    }

    function close() {
        root.classList.remove('is-open');
        root.setAttribute('aria-hidden', 'true');
        // hide after the fade so it doesn't eat clicks
        setTimeout(function () {
            if (!root.classList.contains('is-open')) root.classList.add('is-hidden');
        }, 280);
    }

    function select(id, tile) {
        selectedId = id;
        var tiles = grid.querySelectorAll('.spawn-tile');
        for (var i = 0; i < tiles.length; i++) tiles[i].classList.remove('is-selected');
        if (tile) tile.classList.add('is-selected');
        confirmBtn.disabled = false;
        // move the live backdrop to this spawn point
        post('spawnPreview', { id: id });
    }

    function confirm() {
        if (!selectedId) return;
        confirmBtn.disabled = true;
        post('spawnSelect', { id: selectedId });
        // the client fades out and tears the scene down; hide the UI now
        close();
    }

    confirmBtn.addEventListener('click', confirm);

    // Back: return to the character selector (client restores that scene).
    function goBack() {
        post('spawnBack', {});
        close();
    }
    var backBtn = $('spawnBack');
    if (backBtn) backBtn.addEventListener('click', goBack);

    // Enter confirms the current selection; Escape goes back to characters.
    document.addEventListener('keydown', function (e) {
        if (root.classList.contains('is-hidden')) return;
        if (e.key === 'Enter' && selectedId) { e.preventDefault(); confirm(); }
        else if (e.key === 'Escape') { e.preventDefault(); goBack(); }
    });

    var blackout = document.getElementById('blackout');
    function setBlackout(on) { if (blackout) blackout.classList.toggle('off', !on); }
    // failsafe: never leave the world permanently covered if no reveal arrives
    setTimeout(function () { setBlackout(false); }, 30000);

    window.addEventListener('message', function (ev) {
        var d = ev.data || {};
        if (d.action === 'spawnOpen') open(d.data);
        else if (d.action === 'spawnClose') close();
        else if (d.action === 'blackoutOn') setBlackout(true);
        else if (d.action === 'blackoutOff') setBlackout(false);
    });
})();
