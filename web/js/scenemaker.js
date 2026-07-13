/* ==========================================================================
   forger-multicharacter :: scene maker UI (own build)
   Listens: sceneOpen / sceneClose / scenePanel
   Posts:   sceneStance, sceneCam, sceneWeather, sceneTime, sceneMove,
            sceneSave, sceneClear, sceneClose
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
        }).catch(function () {});
    }
    function $(id) { return document.getElementById(id); }
    function el(tag, cls) { var e = document.createElement(tag); if (cls) e.className = cls; return e; }

    var root = $('scene-maker');
    var panel = $('smPanel');
    var stances = [];
    var cam = null;
    var curStance = null;
    var curWeather = null;
    var curCat = null;

    // ---- stance picker (category tabs + grid) -----------------------------
    function categories() {
        var seen = {}, out = [];
        stances.forEach(function (s) { if (!seen[s.category]) { seen[s.category] = 1; out.push(s.category); } });
        return out;
    }
    function renderCats() {
        var wrap = $('smCats'); wrap.innerHTML = '';
        categories().forEach(function (cat) {
            var b = el('button', 'sm__cat' + (cat === curCat ? ' is-active' : ''));
            b.textContent = cat;
            b.addEventListener('click', function () { curCat = cat; renderCats(); renderStances(); });
            wrap.appendChild(b);
        });
    }
    function renderStances() {
        var wrap = $('smStances'); wrap.innerHTML = '';
        stances.filter(function (s) { return s.category === curCat; }).forEach(function (s) {
            var b = el('button', 'sm__chip' + (s.id === curStance ? ' is-active' : ''));
            b.textContent = s.name;
            b.addEventListener('click', function () {
                curStance = s.id; renderStances();
                post('sceneStance', { id: s.id });
            });
            wrap.appendChild(b);
        });
    }

    // ---- custom slider (fill + knob always aligned; pointer-drag) ---------
    function makeSlider(def, value, onInput) {
        var row = el('div', 'sm__slider');
        var head = el('div', 'sm__slider-head');
        var name = el('span'); name.textContent = def.label;
        var val = el('span');
        head.appendChild(name); head.appendChild(val);

        var track = el('div', 'sm__track');
        var fill = el('div', 'sm__fill');
        var knob = el('div', 'sm__knob');
        track.appendChild(fill); track.appendChild(knob);
        row.appendChild(head); row.appendChild(track);

        var cur = value;
        function pct(v) { return (v - def.min) / (def.max - def.min) * 100; }
        function label(v) {
            var r = Math.round(v / def.step) * def.step;
            return (def.dec ? r.toFixed(def.dec) : Math.round(r)) + (def.unit || '');
        }
        function paint() {
            var p = Math.max(0, Math.min(100, pct(cur)));
            fill.style.width = p + '%';
            knob.style.left = p + '%';
            val.textContent = label(cur);
        }
        function fromX(clientX) {
            var r = track.getBoundingClientRect();
            var p = Math.max(0, Math.min(1, (clientX - r.left) / r.width));
            var v = def.min + p * (def.max - def.min);
            v = Math.round(v / def.step) * def.step;
            var changed = v !== cur;
            cur = v; paint();
            if (changed) onInput(cur);
        }
        var dragging = false;
        track.addEventListener('pointerdown', function (e) {
            dragging = true;
            try { track.setPointerCapture(e.pointerId); } catch (_) {}
            fromX(e.clientX); e.preventDefault();
        });
        track.addEventListener('pointermove', function (e) { if (dragging) fromX(e.clientX); });
        function end(e) { dragging = false; try { track.releasePointerCapture(e.pointerId); } catch (_) {} }
        track.addEventListener('pointerup', end);
        track.addEventListener('pointercancel', end);

        paint();
        return { row: row, set: function (v) { cur = v; paint(); } };
    }

    // ---- camera sliders ---------------------------------------------------
    var CAM_DEFS = [
        { key: 'angle', label: 'Orbit', min: 0, max: 360, step: 1, unit: '\u00B0', dec: 0 },
        { key: 'distance', label: 'Distance', min: 1.5, max: 9, step: 0.1, unit: 'm', dec: 1 },
        { key: 'height', label: 'Height', min: -0.5, max: 2.5, step: 0.05, unit: 'm', dec: 2 },
        { key: 'fov', label: 'Zoom', min: 25, max: 65, step: 1, unit: '', dec: 0 },
        { key: 'speed', label: 'Auto-spin', min: 0, max: 25, step: 1, unit: '\u00B0/s', dec: 0 }
    ];
    function renderCam() {
        var wrap = $('smCam'); wrap.innerHTML = '';
        CAM_DEFS.forEach(function (def) {
            var v = (cam && cam[def.key] != null) ? cam[def.key] : def.min;
            v = Math.max(def.min, Math.min(def.max, v));
            var s = makeSlider(def, v, function (nv) {
                if (cam) cam[def.key] = nv;
                var payload = {}; payload[def.key] = nv;
                post('sceneCam', payload);
            });
            wrap.appendChild(s.row);
        });
    }

    // ---- time -------------------------------------------------------------
    function pad(n) { return (n < 10 ? '0' : '') + n; }
    function setupTime(hour, minute) {
        var range = $('smTime');
        var mins = (hour * 60 + minute);
        range.value = mins;
        $('smTimeVal').textContent = pad(hour) + ':' + pad(minute);
        range.oninput = function () {
            var total = parseInt(range.value, 10);
            var h = Math.floor(total / 60), m = total % 60;
            $('smTimeVal').textContent = pad(h) + ':' + pad(m);
            post('sceneTime', { hour: h, minute: m });
        };
    }

    // ---- weather ----------------------------------------------------------
    var weatherList = [];
    function renderWeathers(list) {
        weatherList = list || weatherList;
        var wrap = $('smWeathers'); wrap.innerHTML = '';
        weatherList.forEach(function (w) {
            var b = el('button', 'sm__weather' + (w === curWeather ? ' is-active' : ''));
            b.textContent = w.toLowerCase().replace('_', ' ');
            b.addEventListener('click', function () {
                curWeather = w; renderWeathers(weatherList);
                post('sceneWeather', { weather: w });
            });
            wrap.appendChild(b);
        });
    }

    // ---- vehicles ---------------------------------------------------------
    var garage = [];
    var placedPlates = {};
    function renderGarage() {
        var wrap = $('smVehList'); wrap.innerHTML = '';
        if (!garage.length) {
            wrap.innerHTML = '<div class="sm__vehempty">No vehicles found in your garage.</div>';
            return;
        }
        garage.forEach(function (v) {
            var placed = !!placedPlates[v.plate];
            var b = el('button', 'sm__veh' + (placed ? ' is-placed' : ''));
            var name = el('span'); name.textContent = (v.model || 'vehicle').toUpperCase();
            var plate = el('span', 'sm__veh-plate'); plate.textContent = v.plate || '—';
            b.appendChild(name); b.appendChild(plate);
            if (!placed) {
                b.addEventListener('click', function () {
                    post('scenePlaceVehicle', { model: v.model, plate: v.plate });
                });
            }
            wrap.appendChild(b);
        });
    }
    function setVehCount(n, plates) {
        $('smVehCount').textContent = n || 0;
        if (Array.isArray(plates)) {
            placedPlates = {};
            plates.forEach(function (p) { placedPlates[p] = true; });
            renderGarage();
        }
    }

    // ---- open / close -----------------------------------------------------
    function applyRole(role, coop) {
        var invitee = role === 'invitee';
        // organizer-only controls
        Array.prototype.forEach.call(document.querySelectorAll('#smPanel .sm__org'), function (elm) {
            elm.style.display = invitee ? 'none' : '';
        });
        $('smCoop').style.display = coop ? '' : 'none';
        $('smInvNote').style.display = invitee ? '' : 'none';
        $('smHint').textContent = invitee
            ? 'Pick your stance and place your vehicles'
            : (coop ? 'Invite players, build the scene, then Save' : 'Pose your character, frame the shot, then Save');
        var title = $('smPanel').querySelector('.sm__title');
        if (title) title.textContent = invitee ? 'JOIN SCENE' : 'BUILD BACKDROP';
    }

    function renderRoster(roster) {
        var wrap = $('smRoster'); wrap.innerHTML = '';
        (roster || []).forEach(function (m) {
            var row = el('div', 'sm__member');
            var nm = el('span'); nm.textContent = m.name || 'Player';
            var tag = el('span', 'sm__member-tag');
            tag.textContent = m.organizer ? 'HOST' : 'GUEST';
            if (m.organizer) tag.classList.add('is-host');
            row.appendChild(nm); row.appendChild(tag);
            wrap.appendChild(row);
        });
        $('smMemberCount').textContent = (roster || []).length || 1;
    }

    function open(d) {
        d = d || {};
        stances = Array.isArray(d.stances) ? d.stances : [];
        cam = d.cam || {};
        curStance = (stances[0] && stances[0].id) || null;
        curCat = (stances[0] && stances[0].category) || null;
        curWeather = d.weather || null;
        garage = [];
        placedPlates = {};
        $('smVehCount').textContent = '0';
        $('smVehList').innerHTML = '<div class="sm__vehempty">Load your garage to place a vehicle.</div>';

        applyRole(d.role || 'organizer', !!d.coop);
        renderRoster([]);
        renderCats();
        renderStances();
        renderCam();
        setupTime(d.hour || 12, d.minute || 0);
        renderWeathers(Array.isArray(d.weathers) ? d.weathers : []);

        root.classList.remove('is-hidden');
        panel.classList.remove('is-hidden');
        requestAnimationFrame(function () { root.classList.add('is-open'); });
    }
    function close() {
        hideOverlays();
        root.classList.remove('is-open');
        setTimeout(function () {
            if (!root.classList.contains('is-open')) root.classList.add('is-hidden');
        }, 280);
    }

    // ---- overlays: instructions / invite prompt / player picker -----------
    var instruct = $('sm-instruct'), prompt = $('sm-prompt'), picker = $('sm-picker');
    var INSTRUCT = {
        vehicle: '<span><b class="smi__k">Arrows</b>move</span><span class="smi__sep">|</span>'
               + '<span><b class="smi__k">Q/E</b>rotate</span><span class="smi__sep">|</span>'
               + '<span><b class="smi__k">Shift</b>faster</span><span class="smi__sep">|</span>'
               + '<span><b class="smi__k">Enter</b>place</span><span class="smi__sep">|</span>'
               + '<span><b class="smi__k smi__k--no">Bksp</b>cancel</span>',
        move: '<span><b class="smi__k">Walk</b>to position</span><span class="smi__sep">|</span>'
            + '<span><b class="smi__k">E</b>set</span><span class="smi__sep">|</span>'
            + '<span><b class="smi__k smi__k--no">Bksp</b>cancel</span>'
    };
    function showInstruct(show, mode) {
        if (show) { instruct.innerHTML = INSTRUCT[mode] || ''; instruct.classList.remove('is-hidden'); }
        else instruct.classList.add('is-hidden');
    }
    function showPrompt(show, name) {
        if (show) { $('smpTitle').textContent = (name || 'A player') + ' invited you to build a scene'; prompt.classList.remove('is-hidden'); }
        else prompt.classList.add('is-hidden');
    }
    var pickerSel = {};
    function showPicker(players) {
        pickerSel = {};
        var list = $('smkList'); list.innerHTML = '';
        if (!players || !players.length) {
            list.innerHTML = '<div class="smk__empty">No players nearby. Stand closer and try again.</div>';
        } else {
            players.forEach(function (p) {
                var row = el('div', 'smk__row');
                var nm = el('span'); nm.textContent = p.name + '  (#' + p.id + ')';
                var ck = el('div', 'smk__check');
                row.appendChild(nm); row.appendChild(ck);
                row.addEventListener('click', function () {
                    if (pickerSel[p.id]) { delete pickerSel[p.id]; row.classList.remove('is-sel'); ck.textContent = ''; }
                    else { pickerSel[p.id] = true; row.classList.add('is-sel'); ck.textContent = '\u2713'; }
                });
                list.appendChild(row);
            });
        }
        picker.classList.remove('is-hidden');
    }
    $('smkCancel').addEventListener('click', function () { picker.classList.add('is-hidden'); });
    $('smkSend').addEventListener('click', function () {
        var ids = Object.keys(pickerSel).map(function (k) { return parseInt(k, 10); });
        picker.classList.add('is-hidden');
        if (ids.length) post('sceneInviteSend', { ids: ids });
    });
    function hideOverlays() {
        showInstruct(false); showPrompt(false); picker.classList.add('is-hidden');
    }

    // ---- buttons ----------------------------------------------------------
    $('smMove').addEventListener('click', function () { post('sceneMove', {}); });
    $('smSave').addEventListener('click', function () { post('sceneSave', {}); });
    $('smClear').addEventListener('click', function () { post('sceneClear', {}); });
    $('smClose').addEventListener('click', function () { post('sceneClose', {}); });
    $('smGarage').addEventListener('click', function () { post('sceneGarage', {}); });
    $('smVehClear').addEventListener('click', function () { post('sceneRemoveVehicles', {}); });
    $('smInvite').addEventListener('click', function () { post('sceneInvite', {}); });

    window.addEventListener('message', function (ev) {
        var d = ev.data || {};
        if (d.action === 'sceneOpen') open(d.data);
        else if (d.action === 'sceneClose') close();
        else if (d.action === 'scenePanel') {
            if (d.show) panel.classList.remove('is-hidden');
            else panel.classList.add('is-hidden');
        }
        else if (d.action === 'sceneGarage') { garage = Array.isArray(d.list) ? d.list : []; renderGarage(); }
        else if (d.action === 'sceneVehicles') { setVehCount(d.count, d.plates); }
        else if (d.action === 'sceneRoster') { renderRoster(d.roster); }
        else if (d.action === 'sceneInstruct') { showInstruct(d.show, d.mode); }
        else if (d.action === 'sceneInvitePrompt') { showPrompt(d.show, d.name); }
        else if (d.action === 'sceneInvitePicker') { showPicker(d.players); }
        else if (d.action === 'sceneConfigSync') {
            if (typeof d.hour === 'number') setupTime(d.hour, d.minute || 0);
            if (d.weather) { curWeather = d.weather; renderWeathers(weatherList); }
        }
    });
})();
