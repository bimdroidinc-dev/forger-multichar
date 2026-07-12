/* forger-multicharacter NUI */
(function () {
    'use strict';

    // ---- lucide-style icon set --------------------------------------------
    const ICONS = {
        users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
        play: '<polygon points="6 3 20 12 6 21 6 3"/>',
        'chevron-left': '<path d="m15 18-6-6 6-6"/>',
        'chevron-right': '<path d="m9 18 6-6-6-6"/>',
        heart: '<path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.29 1.5 4.04 3 5.5l7 7Z"/>',
        star: '<polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>',
        settings: '<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/>',
        'log-out': '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" x2="9" y1="12" y2="12"/>',
        'user-plus': '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><line x1="19" x2="19" y1="8" y2="14"/><line x1="22" x2="16" y1="11" y2="11"/>',
        trash: '<path d="M3 6h18"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><line x1="10" x2="10" y1="11" y2="17"/><line x1="14" x2="14" y1="11" y2="17"/>',
        x: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
        reset: '<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/>',
        moon: '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>',
        sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/>',
        'sun-dim': '<circle cx="12" cy="12" r="4"/><path d="M12 4h.01"/><path d="M20 12h.01"/><path d="M12 20h.01"/><path d="M4 12h.01"/><path d="M17.66 6.34h.01"/><path d="M17.66 17.66h.01"/><path d="M6.34 17.66h.01"/><path d="M6.34 6.34h.01"/>',
        contrast: '<circle cx="12" cy="12" r="10"/><path d="M12 18a6 6 0 0 0 0-12v12z"/>',
        cloud: '<path d="M17.5 19H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z"/>',
        cloudy: '<path d="M17.5 21H9a7 7 0 1 1 6.71-9h1.79a4.5 4.5 0 1 1 0 9Z"/>',
        'cloud-rain': '<path d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242"/><path d="M16 14v6"/><path d="M8 14v6"/><path d="M12 16v6"/>',
        'cloud-lightning': '<path d="M6 16.326A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 .5 8.973"/><path d="m13 12-3 5h4l-3 5"/>',
        'cloud-fog': '<path d="M4 14.899A7 7 0 1 1 15.71 8h1.79a4.5 4.5 0 0 1 2.5 8.242"/><path d="M16 17H7"/><path d="M17 21H9"/>',
        snowflake: '<line x1="2" x2="22" y1="12" y2="12"/><line x1="12" x2="12" y1="2" y2="22"/><path d="m20 16-4-4 4-4"/><path d="m4 8 4 4-4 4"/><path d="m16 4-4 4-4-4"/><path d="m8 20 4-4 4 4"/>',
        wind: '<path d="M17.7 7.7a2.5 2.5 0 1 1 1.8 4.3H2"/><path d="M9.6 4.6A2 2 0 1 1 11 8H2"/><path d="M12.6 19.4A2 2 0 1 0 14 16H2"/>',
        thermometer: '<path d="M14 4v10.54a4 4 0 1 1-4 0V4a2 2 0 0 1 4 0Z"/>',
        clock: '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>',
        monitor: '<rect width="20" height="14" x="2" y="3" rx="2"/><line x1="8" x2="16" y1="21" y2="21"/><line x1="12" x2="12" y1="17" y2="21"/>',
        volume: '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>',
        palette: '<circle cx="13.5" cy="6.5" r=".5" fill="currentColor"/><circle cx="17.5" cy="10.5" r=".5" fill="currentColor"/><circle cx="8.5" cy="7.5" r=".5" fill="currentColor"/><circle cx="6.5" cy="12.5" r=".5" fill="currentColor"/><path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.926 0 1.648-.746 1.648-1.688 0-.437-.18-.835-.437-1.125-.29-.289-.438-.652-.438-1.125a1.64 1.64 0 0 1 1.668-1.668h1.996c3.051 0 5.555-2.503 5.555-5.555C21.965 6.012 17.461 2 12 2z"/>',
        layout: '<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M3 9h18"/><path d="M9 21V9"/>',
        film: '<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M7 3v18"/><path d="M3 7.5h4"/><path d="M3 12h18"/><path d="M3 16.5h4"/><path d="M17 3v18"/><path d="M17 7.5h4"/><path d="M17 16.5h4"/>',
        keyboard: '<rect width="20" height="16" x="2" y="4" rx="2"/><path d="M6 8h.01"/><path d="M10 8h.01"/><path d="M14 8h.01"/><path d="M18 8h.01"/><path d="M8 12h.01"/><path d="M12 12h.01"/><path d="M16 12h.01"/><path d="M7 16h10"/>',
        wallet: '<path d="M19 7V4a1 1 0 0 0-1-1H5a2 2 0 0 0 0 4h15a1 1 0 0 1 1 1v4h-3a2 2 0 0 0 0 4h3a1 1 0 0 0 1-1v-2a1 1 0 0 0-1-1"/><path d="M3 5v14a2 2 0 0 0 2 2h15a1 1 0 0 0 1-1v-4"/>',
        bank: '<line x1="3" x2="21" y1="22" y2="22"/><line x1="6" x2="6" y1="18" y2="11"/><line x1="10" x2="10" y1="18" y2="11"/><line x1="14" x2="14" y1="18" y2="11"/><line x1="18" x2="18" y1="18" y2="11"/><polygon points="12 2 20 7 4 7"/>',
        volume2: '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>',
        alert: '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
        check: '<path d="M20 6 9 17l-5-5"/>',
        search: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
        inbox: '<polyline points="22 12 16 12 14 15 10 15 8 12 2 12"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
        send: '<path d="M14.536 21.686a.5.5 0 0 0 .937-.024l6.5-19a.496.496 0 0 0-.635-.635l-19 6.5a.5.5 0 0 0-.024.937l7.93 3.18a2 2 0 0 1 1.112 1.11z"/><path d="m21.854 2.147-10.94 10.939"/>',
        user: '<circle cx="12" cy="7" r="4"/><path d="M6 21v-2a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v2"/>',
        'heart-off': '<path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2a5.5 5.5 0 0 0-1.32.16"/><path d="m2 2 20 20"/><path d="M5 8.5c-.32 2 .88 3.5 2 4.5l5 5 3-3"/>',
        aperture: '<circle cx="12" cy="12" r="10"/><path d="m14.31 8 5.74 9.94"/><path d="M9.69 8h11.48"/><path d="m7.38 12 5.74-9.94"/><path d="M9.69 16 3.95 6.06"/><path d="M14.31 16H2.83"/><path d="m16.62 12-5.74 9.94"/>',
        pause: '<rect x="6" y="4" width="4" height="16" rx="1"/><rect x="14" y="4" width="4" height="16" rx="1"/>',
        music: '<path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>',
        'zoom-in': '<circle cx="11" cy="11" r="8"/><line x1="21" x2="16.65" y1="21" y2="16.65"/><line x1="11" x2="11" y1="8" y2="14"/><line x1="8" x2="14" y1="11" y2="11"/>',
        scan: '<path d="M3 7V5a2 2 0 0 1 2-2h2"/><path d="M17 3h2a2 2 0 0 1 2 2v2"/><path d="M21 17v2a2 2 0 0 1-2 2h-2"/><path d="M7 21H5a2 2 0 0 1-2-2v-2"/>',
        maximize: '<path d="M8 3H5a2 2 0 0 0-2 2v3"/><path d="M21 8V5a2 2 0 0 0-2-2h-3"/><path d="M3 16v3a2 2 0 0 0 2 2h3"/><path d="M16 21h3a2 2 0 0 0 2-2v-3"/>',
    };

    function svg(name, cls) {
        const inner = ICONS[name] || '';
        return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"' + (cls ? ' class="' + cls + '"' : '') + '>' + inner + '</svg>';
    }

    // ---- NUI plumbing ------------------------------------------------------
    const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'forger-multicharacter';
    function post(cb, data) {
        return fetch('https://' + RES + '/' + cb, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        }).catch(function () {});
    }

    // ---- state -------------------------------------------------------------
    const state = {
        characters: [],
        maxSlots: 2,
        index: 0,
        settings: {},
        defaults: {},
        weatherOptions: [],
        nationalities: [],
        busy: false,
        favorites: {},
        filter: 'none',
        musicUrl: '',
        musicPlaying: false,
        zoom: 1,
    };

    const $ = function (id) { return document.getElementById(id); };
    const app = $('app');

    function totalSlots() {
        const withEmpty = state.characters.length < state.maxSlots ? 1 : 0;
        return state.characters.length + withEmpty;
    }
    function currentSlot() {
        if (state.index < state.characters.length) {
            return { type: 'char', data: state.characters[state.index] };
        }
        return { type: 'empty' };
    }

    function money(n) { return (Number(n) || 0).toLocaleString('en-US') + '$'; }
    function ageOf(birthdate) {
        if (!birthdate) return null;
        const y = parseInt(String(birthdate).slice(0, 4), 10);
        if (!y || y < 1900) return null;
        const age = new Date().getFullYear() - y;
        return (age > 0 && age < 120) ? age : null;
    }

    // ---- lightweight sfx ---------------------------------------------------
    let actx = null;
    function blip(freq) {
        if (!state.settings.soundEffects) return;
        try {
            actx = actx || new (window.AudioContext || window.webkitAudioContext)();
            const o = actx.createOscillator(), g = actx.createGain();
            o.type = 'sine'; o.frequency.value = freq || 520;
            g.gain.value = (state.settings.soundVolume || 50) / 100 * 0.06;
            o.connect(g); g.connect(actx.destination);
            o.start(); g.gain.exponentialRampToValueAtTime(0.0001, actx.currentTime + 0.12);
            o.stop(actx.currentTime + 0.13);
        } catch (e) {}
    }

    // ---- rendering ---------------------------------------------------------
    function renderBrand() {
        $('brandMark').innerHTML = svg('users');
        if (state.brand) {
            $('brandName').textContent = state.brand.name || 'FORGER';
            $('brandTag').textContent = state.brand.tag || 'MULTICHARACTER';
        }
    }

    function renderHints() {
        const hints = [
            { k: 'Enter', t: 'Play' },
            { k: 'E', t: 'Change Pose' },
            { k: 'J', t: 'Change Location' },
            { k: 'Z', t: 'Zoom' },
            { k: 'B', t: 'Cinematic Bars' },
            { k: 'H', t: 'Hide UI' },
        ];
        $('hints').innerHTML = hints.map(function (h) {
            return '<span class="hint"><kbd>' + h.k + '</kbd>' + h.t + '</span>';
        }).join('');
        $('hints').style.display = state.settings.keybindHints ? 'flex' : 'none';
    }

    function metaLine(c) {
        const bits = [];
        bits.push(c.job && c.job.label ? c.job.label : 'Unemployed');
        const a = ageOf(c.birthdate);
        if (a) bits.push(a + ' yo');
        if (c.nationality && c.nationality !== 'Unknown') bits.push(c.nationality);
        if (c.playtime && c.playtime !== '0m') bits.push(c.playtime);
        return bits.map(function (b, i) {
            return (i ? '<span class="sep"></span>' : '') + '<span>' + escapeHtml(b) + '</span>';
        }).join('');
    }

    function escapeHtml(s) {
        return String(s).replace(/[&<>"]/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
        });
    }

    function renderInfo() {
        const slot = currentSlot();
        const info = $('info');
        if (slot.type === 'empty') {
            info.className = 'info is-empty';
            info.innerHTML =
                '<h1 class="info__name">Empty Slot</h1>' +
                '<div class="info__desc">This slot is open. Create a new character to bring them to life.</div>';
            return;
        }
        const c = slot.data;
        info.className = 'info';
        info.innerHTML =
            '<h1 class="info__name">' + escapeHtml(c.firstname + ' ' + c.lastname) + '</h1>' +
            '<div class="info__meta">' + metaLine(c) + '</div>' +
            '<p class="info__desc">' + escapeHtml(c.backstory || (c.firstname + ' has no story on record yet.')) + '</p>' +
            '<div class="info__money">' +
                '<span class="amt cash">' + svg('wallet') + money(c.cash) + '</span>' +
                '<span class="amt bank">' + svg('bank') + money(c.bank) + '</span>' +
            '</div>' +
            '<button class="info__delete" data-act="delete">' + svg('trash') + 'Delete character</button>';
    }

    function renderClassicHead() {
        const slot = currentSlot();
        const head = $('classicHead');
        if (slot.type === 'empty') {
            head.innerHTML = '<div class="n">Empty Slot</div>';
            return;
        }
        const c = slot.data;
        head.innerHTML =
            '<div class="n">' + escapeHtml(c.firstname + ' ' + c.lastname) + '</div>' +
            '<div class="m">' + metaLine(c) + '</div>';
    }

    function renderActions() {
        const slot = currentSlot();
        const el = $('actions');
        let html = '';
        if (slot.type === 'char') {
            const favOn = state.favorites[slot.data.citizenid] ? ' is-on' : '';
            html += '<button class="btn btn--play" data-act="play">' + svg('play') + 'Play</button>';
            html += '<button class="btn btn--icon' + favOn + '" data-act="fav" title="Favorite">' + svg('heart') + '</button>';
            html += '<button class="btn btn--icon" data-act="star" title="Star">' + svg('star') + '</button>';
        } else {
            html += '<button class="btn btn--play" data-act="create">' + svg('user-plus') + 'Create</button>';
        }
        html += '<button class="btn btn--icon" data-act="settings" title="Settings">' + svg('settings') + '</button>';
        html += '<button class="btn btn--icon" data-act="exit" title="Exit">' + svg('log-out') + '</button>';
        el.innerHTML = html;
    }

    function renderMenu() {
        const slot = currentSlot();
        const items = [];
        if (slot.type === 'char') {
            items.push({ label: 'Play', act: 'play' });
            items.push({ label: 'Delete', act: 'delete', danger: true });
        } else {
            items.push({ label: 'Create', act: 'create' });
        }
        items.push({ label: 'Settings', act: 'settings' });
        items.push({ label: 'Exit', act: 'exit' });
        $('menu').innerHTML = items.map(function (it, i) {
            return '<button class="menu__item' + (i === 0 ? ' is-active' : '') + (it.danger ? ' is-danger' : '') +
                '" data-act="' + it.act + '">' + it.label + '</button>';
        }).join('');
    }

    function renderDots() {
        const total = totalSlots();
        let html = '';
        for (let i = 0; i < total; i++) {
            const empty = i >= state.characters.length ? ' is-empty' : '';
            html += '<span class="dot' + (i === state.index ? ' is-active' : '') + empty + '"></span>';
        }
        $('dots').innerHTML = html;
    }

    function renderZoom() {
        const items = [
            { i: 1, label: 'Close', icon: 'zoom-in' },
            { i: 2, label: 'Medium', icon: 'scan' },
            { i: 3, label: 'Far', icon: 'maximize' },
        ];
        const bar = $('zoombar');
        bar.innerHTML = items.map(function (z) {
            return '<button data-zoom="' + z.i + '" class="' + (state.zoom === z.i ? 'is-on' : '') + '">' + svg(z.icon) + z.label + '</button>';
        }).join('');
        bar.querySelectorAll('[data-zoom]').forEach(function (b) {
            b.addEventListener('click', function () { setZoom(parseInt(b.getAttribute('data-zoom'), 10)); });
        });
    }

    function setZoom(i) {
        i = Math.max(1, Math.min(3, i));
        state.zoom = i;
        post('setZoom', { index: i });
        renderZoom(); blip(); persist();
    }

    function renderAll() {
        renderInfo();
        renderClassicHead();
        renderActions();
        renderMenu();
        renderDots();
        renderZoom();
    }

    // ---- navigation --------------------------------------------------------
    function setIndex(i) {
        const total = totalSlots();
        state.index = (i + total) % total;
        renderAll();
        blip(440);
        const slot = currentSlot();
        post('preview', slot.type === 'char'
            ? { gender: slot.data.gender, appearance: slot.data.appearance || null }
            : { gender: 0, __empty: true });
    }
    function next() { setIndex(state.index + 1); }
    function prev() { setIndex(state.index - 1); }

    // ---- settings sheet ----------------------------------------------------
    function buildSettings() {
        const s = state.settings;
        const themeSeg = [
            { v: 'dark', label: 'Dark', icon: 'moon' },
            { v: 'light', label: 'Light', icon: 'sun' },
            { v: 'auto', label: 'Auto', icon: 'contrast' },
        ].map(function (t) {
            return '<button data-theme-opt="' + t.v + '" class="' + (s.theme === t.v ? 'is-on' : '') + '">' + svg(t.icon) + t.label + '</button>';
        }).join('');

        const weatherGrid = state.weatherOptions.map(function (w) {
            return '<button data-weather="' + w.key + '" title="' + w.label + '" class="' + (s.weather === w.key ? 'is-on' : '') + '">' + svg(w.icon) + '</button>';
        }).join('');

        const menuSeg = [
            { v: 'classic', label: 'Classic', icon: 'layout' },
            { v: 'cinematic', label: 'Cinematic', icon: 'film' },
        ].map(function (m) {
            return '<button data-menu-opt="' + m.v + '" class="' + (s.menuStyle === m.v ? 'is-on' : '') + '">' + svg(m.icon) + m.label + '</button>';
        }).join('');

        const filterGrid = [
            { v: 'none', label: 'None' },
            { v: 'hd', label: 'HD Crisp' },
            { v: 'portrait', label: 'Portrait' },
            { v: 'noir', label: 'Noir' },
            { v: 'golden', label: 'Golden' },
        ].map(function (f) {
            return '<button class="filter-opt' + (state.filter === f.v ? ' is-on' : '') + '" data-filter="' + f.v + '">' +
                '<span class="sw ' + f.v + '"></span>' + f.label + '</button>';
        }).join('');

        function toggleRow(key, title, desc, keyHint) {
            return '<div class="row"><div class="row__text"><div class="t">' + title + '</div><div class="d">' + desc + '</div></div>' +
                (keyHint ? '<div class="row__key"><kbd>' + keyHint + '</kbd></div>' : '') +
                '<label class="switch"><input type="checkbox" data-toggle="' + key + '" ' + (s[key] ? 'checked' : '') + '/><span class="track"></span></label></div>';
        }

        $('settingsSheet').innerHTML =
            '<div class="sheet__head"><div><div class="sheet__title">Settings</div><div class="sheet__sub">Customize your experience</div></div>' +
            '<div class="sheet__tools"><button class="icobtn" data-act="reset" title="Reset">' + svg('reset') + '</button>' +
            '<button class="icobtn" data-act="closeSettings" title="Close">' + svg('x') + '</button></div></div>' +

            '<div class="group"><div class="group__label">' + svg('palette') + 'Theme</div><div class="seg">' + themeSeg + '</div></div>' +

            '<div class="group"><div class="group__label">' + svg('cloudy') + 'Weather</div><div class="weather">' + weatherGrid + '</div></div>' +

            '<div class="group"><div class="group__label">' + svg('clock') + 'Time of Day <span style="margin-left:auto" class="time-big"><b id="timeLabel"></b></span></div>' +
            '<div class="slider-row"><div class="slider-head"><span>Hour</span><b id="hourVal">' + s.hour + '</b></div><input type="range" id="hour" min="0" max="23" value="' + s.hour + '"/></div>' +
            '<div class="slider-row"><div class="slider-head"><span>Minute</span><b id="minVal">' + pad(s.minute) + '</b></div><input type="range" id="minute" min="0" max="59" value="' + s.minute + '"/></div></div>' +

            '<div class="group"><div class="group__label">' + svg('monitor') + 'Display</div>' +
            '<div style="font-size:12px;color:var(--muted);margin-bottom:8px">Menu Style</div><div class="seg">' + menuSeg + '</div>' +
            '<div style="height:12px"></div>' +
            toggleRow('cinematicBars', 'Cinematic Bars', 'Adds black bars top and bottom.', 'B') +
            toggleRow('fpsMode', 'FPS Mode', 'Reduces visual effects to improve performance.') +
            toggleRow('keybindHints', 'Keybind Hints', 'Show keyboard shortcuts on screen.') + '</div>' +

            '<div class="group"><div class="group__label">' + svg('aperture') + 'Camera Filter</div><div class="filter-grid">' + filterGrid + '</div></div>' +

            '<div class="group"><div class="group__label">' + svg('volume') + 'Audio</div>' +
            toggleRow('soundEffects', 'Sound Effects', 'Interface clicks and blips.') +
            '<div class="slider-row"><div class="slider-head"><span>Sound Volume</span><b id="sfxVal">' + s.soundVolume + '%</b></div><input type="range" id="sfxVol" min="0" max="100" value="' + s.soundVolume + '"/></div>' +
            toggleRow('backgroundMusic', 'Background Music', 'Plays a YouTube track on the character screen.') +
            '<div class="music-row"><input id="musicUrl" placeholder="Paste a YouTube link..." autocomplete="off" spellcheck="false" value="' + escapeHtml(state.musicUrl || '') + '"/>' +
            '<button class="music-btn' + (state.musicPlaying ? ' is-playing' : '') + '" id="musicToggle" title="Play / Stop">' + svg(state.musicPlaying ? 'pause' : 'play') + '</button></div>' +
            '<div class="music-now" id="musicNow"></div>' +
            '<div class="slider-row"><div class="slider-head"><span>Music Volume</span><b id="musVal">' + s.musicVolume + '%</b></div><input type="range" id="musVol" min="0" max="100" value="' + s.musicVolume + '"/></div></div>';

        wireSettings();
        updateTimeLabel();
        paintSliders();
    }

    function pad(n) { return String(n).padStart(2, '0'); }
    function updateTimeLabel() {
        const el = $('timeLabel');
        if (el) el.textContent = pad(state.settings.hour) + ':' + pad(state.settings.minute);
    }
    function paintSliders() {
        [['hour', 23], ['minute', 59], ['sfxVol', 100], ['musVol', 100]].forEach(function (p) {
            const el = $(p[0]); if (el) el.style.setProperty('--fill', (el.value / p[1] * 100) + '%');
        });
    }

    function wireSettings() {
        const sheet = $('settingsSheet');
        sheet.querySelectorAll('[data-theme-opt]').forEach(function (b) {
            b.addEventListener('click', function () {
                state.settings.theme = b.getAttribute('data-theme-opt');
                applyTheme(); markOn(sheet, '[data-theme-opt]', b); blip(); persist();
            });
        });
        sheet.querySelectorAll('[data-menu-opt]').forEach(function (b) {
            b.addEventListener('click', function () {
                state.settings.menuStyle = b.getAttribute('data-menu-opt');
                app.setAttribute('data-menu', state.settings.menuStyle);
                markOn(sheet, '[data-menu-opt]', b); renderAll(); blip(); persist();
            });
        });
        sheet.querySelectorAll('[data-weather]').forEach(function (b) {
            b.addEventListener('click', function () {
                const w = b.getAttribute('data-weather');
                state.settings.weather = w;
                markOn(sheet, '[data-weather]', b);
                post('applySetting', { key: 'weather', value: w }); blip(); persist();
            });
        });
        sheet.querySelectorAll('[data-toggle]').forEach(function (inp) {
            inp.addEventListener('change', function () {
                const key = inp.getAttribute('data-toggle');
                state.settings[key] = inp.checked;
                if (key === 'cinematicBars') app.classList.toggle('bars-on', inp.checked);
                if (key === 'keybindHints') $('hints').style.display = inp.checked ? 'flex' : 'none';
                if (key === 'backgroundMusic') {
                    if (inp.checked && state.musicUrl) playMusic(state.musicUrl);
                    else stopMusic();
                }
                blip(); persist();
            });
        });
        const hour = $('hour'), minute = $('minute');
        function timeChange() {
            state.settings.hour = parseInt(hour.value, 10);
            state.settings.minute = parseInt(minute.value, 10);
            $('hourVal').textContent = state.settings.hour;
            $('minVal').textContent = pad(state.settings.minute);
            updateTimeLabel(); paintSliders();
            post('applySetting', { key: 'time', hour: state.settings.hour, minute: state.settings.minute });
            persist();
        }
        hour.addEventListener('input', timeChange);
        minute.addEventListener('input', timeChange);

        const sfx = $('sfxVol'), mus = $('musVol');
        sfx.addEventListener('input', function () { state.settings.soundVolume = parseInt(sfx.value, 10); $('sfxVal').textContent = sfx.value + '%'; paintSliders(); persist(); });
        mus.addEventListener('input', function () {
            state.settings.musicVolume = parseInt(mus.value, 10);
            $('musVal').textContent = mus.value + '%'; paintSliders();
            setMusicVolume(state.settings.musicVolume); persist();
        });

        // camera filters
        sheet.querySelectorAll('[data-filter]').forEach(function (b) {
            b.addEventListener('click', function () {
                applyFilter(b.getAttribute('data-filter'));
                markOn(sheet, '[data-filter]', b); blip(); persist();
            });
        });

        // background music (YouTube)
        const urlInput = $('musicUrl'), toggle = $('musicToggle');
        if (urlInput) {
            urlInput.addEventListener('change', function () {
                state.musicUrl = urlInput.value.trim();
                persist();
                if (state.musicUrl && state.settings.backgroundMusic) playMusic(state.musicUrl);
            });
        }
        if (toggle) {
            toggle.addEventListener('click', function () {
                if (state.musicPlaying) { stopMusic(); }
                else if (state.musicUrl) { playMusic(state.musicUrl); }
                else { toast('Paste a YouTube link first.', 'err'); }
                blip();
            });
        }
        updateMusicUI();
    }

    // persist the full setup (theme/filter/music/volumes/etc.) to the client (KVP)
    function persist() {
        post('savePrefs', {
            theme: state.settings.theme,
            menuStyle: state.settings.menuStyle,
            cinematicBars: state.settings.cinematicBars,
            fpsMode: state.settings.fpsMode,
            keybindHints: state.settings.keybindHints,
            soundEffects: state.settings.soundEffects,
            soundVolume: state.settings.soundVolume,
            backgroundMusic: state.settings.backgroundMusic,
            musicVolume: state.settings.musicVolume,
            weather: state.settings.weather,
            hour: state.settings.hour,
            minute: state.settings.minute,
            filter: state.filter,
            musicUrl: state.musicUrl,
            zoom: state.zoom,
        });
    }

    function markOn(scope, sel, active) {
        scope.querySelectorAll(sel).forEach(function (n) { n.classList.remove('is-on'); });
        active.classList.add('is-on');
    }

    function applyTheme() {
        const t = state.settings.theme;
        if (t === 'auto') {
            const h = state.settings.hour;
            app.setAttribute('data-theme', (h >= 7 && h < 19) ? 'light' : 'dark');
        } else {
            app.setAttribute('data-theme', t);
        }
    }

    function openSettings() { buildSettings(); $('settingsSheet').classList.add('is-open'); }
    function closeSettings() { $('settingsSheet').classList.remove('is-open'); }

    // ---- create sheet ------------------------------------------------------
    function buildCreate() {
        const nats = state.nationalities.map(function (n) { return '<option value="' + escapeHtml(n) + '">' + escapeHtml(n) + '</option>'; }).join('');
        $('createSheet').innerHTML =
            '<div class="sheet__head"><div><div class="sheet__title">New Character</div><div class="sheet__sub">' +
            (state.characters.length) + ' of ' + state.maxSlots + ' slots used</div></div>' +
            '<div class="sheet__tools"><button class="icobtn" data-act="closeCreate">' + svg('x') + '</button></div></div>' +

            '<div class="grid-2">' +
            '<div class="field"><label>First name</label><input id="fFirst" maxlength="20" placeholder="John" autocomplete="off"/></div>' +
            '<div class="field"><label>Last name</label><input id="fLast" maxlength="20" placeholder="Doe" autocomplete="off"/></div></div>' +

            '<div class="field"><label>Date of birth</label><input id="fDob" type="date" value="2000-01-01"/></div>' +

            '<div class="field"><label>Gender</label><div class="gender-pick">' +
            '<button data-gender="0" class="is-on">Male</button><button data-gender="1">Female</button></div></div>' +

            '<div class="field"><label>Nationality</label><select id="fNat">' + nats + '</select></div>' +

            '<div class="field"><label>Backstory <span style="color:var(--muted-2)">(optional)</span></label>' +
            '<textarea id="fStory" maxlength="300" placeholder="A ghost in the system, no past, no trace..."></textarea></div>' +

            '<div class="sheet__cta"><button class="cta" data-act="closeCreate">Cancel</button>' +
            '<button class="cta cta--primary" data-act="submitCreate">' + svg('user-plus') + 'Create character</button></div>';

        let gender = 0;
        const sheet = $('createSheet');
        sheet.querySelectorAll('[data-gender]').forEach(function (b) {
            b.addEventListener('click', function () {
                gender = parseInt(b.getAttribute('data-gender'), 10);
                markOn(sheet, '[data-gender]', b); blip();
            });
        });
        sheet._getGender = function () { return gender; };
    }

    function openCreate() { buildCreate(); $('createSheet').classList.add('is-open'); }
    function closeCreate() { $('createSheet').classList.remove('is-open'); }

    function submitCreate() {
        if (state.busy) return;
        const first = $('fFirst').value.trim();
        const last = $('fLast').value.trim();
        if (first.length < 2 || last.length < 2) { toast('Names must be at least 2 characters.', 'err'); return; }
        state.busy = true;
        const btn = $('createSheet').querySelector('[data-act="submitCreate"]');
        if (btn) btn.setAttribute('disabled', 'true');
        post('create', {
            firstname: first,
            lastname: last,
            birthdate: $('fDob').value || '2000-01-01',
            gender: $('createSheet')._getGender(),
            nationality: $('fNat').value,
            backstory: $('fStory').value.trim(),
        });
    }

    // ---- delete ------------------------------------------------------------
    function askDelete() {
        const slot = currentSlot();
        if (slot.type !== 'char') return;
        const c = slot.data;
        const modal = $('modal');
        modal.innerHTML =
            '<div class="modal__box"><div class="modal__icon">' + svg('alert') + '</div>' +
            '<div class="modal__title">Delete ' + escapeHtml(c.firstname + ' ' + c.lastname) + '?</div>' +
            '<div class="modal__text">This permanently removes the character and everything they own. This cannot be undone.</div>' +
            '<div class="modal__cta"><button class="cta" data-act="closeModal">Cancel</button>' +
            '<button class="cta cta--danger" data-act="confirmDelete">' + svg('trash') + 'Delete</button></div></div>';
        modal.classList.add('is-open');
    }
    function closeModal() { $('modal').classList.remove('is-open'); }
    function confirmDelete() {
        if (state.busy) return;
        const slot = currentSlot();
        if (slot.type !== 'char') return;
        state.busy = true;
        post('delete', { citizenid: slot.data.citizenid });
    }

    // ---- action dispatch ---------------------------------------------------
    function doAction(act) {
        switch (act) {
            case 'play': {
                const slot = currentSlot();
                if (slot.type === 'char' && !state.busy) {
                    state.busy = true; blip(660);
                    post('play', { citizenid: slot.data.citizenid });
                }
                break;
            }
            case 'create': openCreate(); break;
            case 'delete': askDelete(); break;
            case 'settings': openSettings(); break;
            case 'closeSettings': closeSettings(); break;
            case 'submitCreate': submitCreate(); break;
            case 'closeCreate': closeCreate(); break;
            case 'closeModal': closeModal(); break;
            case 'confirmDelete': confirmDelete(); break;
            case 'reset': resetSettings(); break;
            case 'fav': {
                const slot = currentSlot();
                if (slot.type === 'char') { state.favorites[slot.data.citizenid] = !state.favorites[slot.data.citizenid]; renderActions(); blip(); }
                break;
            }
            case 'star': blip(); break;
            case 'exit': post('close', {}); closeSettings(); closeCreate(); closeModal(); break;
        }
    }

    function resetSettings() {
        state.settings = Object.assign({}, state.defaults);
        state.filter = 'none';
        applyFilter('none');
        stopMusic();
        applyTheme();
        app.setAttribute('data-menu', state.settings.menuStyle);
        app.classList.toggle('bars-on', !!state.settings.cinematicBars);
        buildSettings();
        renderHints();
        renderAll();
        post('applySetting', { key: 'weather', value: state.settings.weather });
        post('applySetting', { key: 'time', hour: state.settings.hour, minute: state.settings.minute });
        persist();
    }

    // global click delegation for [data-act]
    document.addEventListener('click', function (e) {
        const t = e.target.closest('[data-act]');
        if (t) doAction(t.getAttribute('data-act'));
    });
    $('prev').innerHTML = svg('chevron-left');
    $('next').innerHTML = svg('chevron-right');
    $('prev').addEventListener('click', prev);
    $('next').addEventListener('click', next);

    // ---- keyboard ----------------------------------------------------------
    function anySheetOpen() {
        return $('settingsSheet').classList.contains('is-open') ||
            $('createSheet').classList.contains('is-open') ||
            $('modal').classList.contains('is-open');
    }
    document.addEventListener('keydown', function (e) {
        if (app.classList.contains('is-hidden')) return;
        const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName);
        const key = e.key.toLowerCase();

        if (key === 'escape') {
            e.preventDefault();
            if ($('modal').classList.contains('is-open')) return closeModal();
            if ($('createSheet').classList.contains('is-open')) return closeCreate();
            if ($('settingsSheet').classList.contains('is-open')) return closeSettings();
            return;
        }
        if (typing) return;
        if (anySheetOpen()) return;

        if (key === 'arrowleft') { e.preventDefault(); prev(); }
        else if (key === 'arrowright') { e.preventDefault(); next(); }
        else if (key === 'enter') { e.preventDefault(); doAction('play'); }
        else if (key === 'e') { e.preventDefault(); post('changePose', {}); blip(); }
        else if (key === 'j') { e.preventDefault(); post('changeLocation', {}); blip(); }
        else if (key === 'z') { e.preventDefault(); setZoom(state.zoom >= 3 ? 1 : state.zoom + 1); }
        else if (key === 'b') {
            e.preventDefault();
            state.settings.cinematicBars = !state.settings.cinematicBars;
            app.classList.toggle('bars-on', state.settings.cinematicBars); blip();
        }
        else if (key === 'h') { e.preventDefault(); app.classList.toggle('ui-hidden'); }
    });

    // ---- toast -------------------------------------------------------------
    let toastT = null;
    function toast(msg, kind) {
        const el = $('toast');
        el.className = 'toast ' + (kind || '');
        el.innerHTML = svg(kind === 'ok' ? 'check' : 'alert') + '<span>' + escapeHtml(msg) + '</span>';
        el.classList.add('show');
        clearTimeout(toastT);
        toastT = setTimeout(function () { el.classList.remove('show'); }, 3200);
    }

    // ---- camera filter ----------------------------------------------------
    function applyFilter(name) {
        state.filter = (name && name !== 'none') ? name : 'none';
        const el = $('filterLayer');
        if (el) el.className = 'filter-layer' + (state.filter !== 'none' ? ' f-' + state.filter : '');
        post('setFilter', { name: state.filter });
    }

    // ---- background music (YouTube) ---------------------------------------
    let ytPlayer = null, ytReady = false, ytPending = null;

    function loadYT() {
        if (window.YT && window.YT.Player) { onYTReady(); return; }
        if (document.getElementById('yt-api')) return;
        const tag = document.createElement('script');
        tag.id = 'yt-api';
        tag.src = 'https://www.youtube.com/iframe_api';
        document.head.appendChild(tag);
        window.onYouTubeIframeAPIReady = onYTReady;
    }
    function onYTReady() {
        if (ytPlayer) return;
        ytPlayer = new YT.Player('ytPlayer', {
            height: '1', width: '1',
            playerVars: { autoplay: 1, controls: 0, disablekb: 1, playsinline: 1, fs: 0 },
            events: {
                onReady: function () {
                    ytReady = true;
                    setMusicVolume(state.settings.musicVolume || 30);
                    if (ytPending) { playMusic(ytPending); ytPending = null; }
                },
                onStateChange: function (e) {
                    if (e.data === YT.PlayerState.ENDED && state.musicPlaying && ytPlayer) {
                        ytPlayer.playVideo(); // loop
                    }
                    if (e.data === YT.PlayerState.PLAYING) state.musicPlaying = true;
                    updateMusicUI();
                },
            },
        });
    }
    function ytId(url) {
        if (!url) return null;
        const m = String(url).match(/(?:youtu\.be\/|[?&]v=|\/embed\/|\/live\/|\/shorts\/)([A-Za-z0-9_-]{11})/);
        if (m) return m[1];
        return /^[A-Za-z0-9_-]{11}$/.test(String(url)) ? url : null;
    }
    function playMusic(url) {
        const id = ytId(url);
        if (!id) { toast('That YouTube link looks invalid.', 'err'); return; }
        if (!ytReady) { ytPending = url; loadYT(); state.musicPlaying = true; updateMusicUI(); return; }
        try { ytPlayer.loadVideoById(id); setMusicVolume(state.settings.musicVolume || 30); ytPlayer.playVideo(); } catch (e) {}
        state.musicPlaying = true; updateMusicUI();
    }
    function stopMusic() {
        state.musicPlaying = false;
        if (ytReady && ytPlayer) { try { ytPlayer.stopVideo(); } catch (e) {} }
        updateMusicUI();
    }
    function setMusicVolume(v) {
        if (ytReady && ytPlayer) { try { ytPlayer.setVolume(Math.max(0, Math.min(100, v || 0))); } catch (e) {} }
    }
    function updateMusicUI() {
        const t = $('musicToggle');
        if (t) { t.innerHTML = svg(state.musicPlaying ? 'pause' : 'play'); t.classList.toggle('is-playing', state.musicPlaying); }
        const now = $('musicNow');
        if (now) now.textContent = state.musicPlaying ? 'Now playing' : (state.musicUrl ? 'Paused' : '');
    }

    // ---- restore saved preferences ----------------------------------------
    function applyPrefs(p) {
        if (!p || typeof p !== 'object' || !Object.keys(p).length) return;
        ['theme', 'menuStyle', 'cinematicBars', 'fpsMode', 'keybindHints', 'soundEffects',
         'soundVolume', 'backgroundMusic', 'musicVolume', 'weather', 'hour', 'minute'
        ].forEach(function (k) { if (p[k] !== undefined && p[k] !== null) state.settings[k] = p[k]; });
        if (p.filter !== undefined) state.filter = p.filter || 'none';
        if (p.musicUrl !== undefined) state.musicUrl = p.musicUrl || '';
        if (p.zoom !== undefined) state.zoom = Math.max(1, Math.min(3, parseInt(p.zoom, 10) || 1));

        applyTheme();
        app.setAttribute('data-menu', state.settings.menuStyle || 'cinematic');
        app.classList.toggle('bars-on', !!state.settings.cinematicBars);
        renderHints();
        renderAll();
        applyFilter(state.filter);

        if (state.settings.backgroundMusic && state.musicUrl) playMusic(state.musicUrl);
        if ($('settingsSheet').classList.contains('is-open')) buildSettings();
    }

    // ---- messages from client ---------------------------------------------
    window.addEventListener('message', function (ev) {
        const d = ev.data || {};
        if (d.action === 'open') {
            app.classList.remove('is-hidden');
            loadYT();
            applyFilter(state.filter);
        } else if (d.action === 'close') {
            app.classList.add('is-hidden');
            state.busy = false;
            stopMusic();
        } else if (d.action === 'spawnHide') {
            // handing off to the spawn selector: hide the character UI but keep
            // the music playing (the YT player lives outside #app now).
            app.classList.add('is-hidden');
            state.busy = false;
        } else if (d.action === 'spawnShow') {
            // returning from the spawn selector via Back: reveal the character UI
            // again and re-preview the currently highlighted slot so the scene
            // rebuilds. Music was never stopped.
            app.classList.remove('is-hidden');
            applyFilter(state.filter);
            var backSlot = currentSlot();
            post('preview', backSlot.type === 'char'
                ? { gender: backSlot.data.gender, appearance: backSlot.data.appearance || null }
                : { gender: 0, __empty: true });
        } else if (d.action === 'setData') {
            applyData(d.data);
        } else if (d.action === 'prefs') {
            applyPrefs(d.data);
        } else if (d.action === 'actionResult') {
            handleResult(d.data);
        } else if (d.action === 'locationChanged') {
            toast(d.label, 'ok');
        }
    });

    function applyData(data) {
        state.characters = data.characters || [];
        state.maxSlots = data.maxSlots || 2;
        state.brand = data.brand || state.brand;
        state.weatherOptions = data.weatherOptions || state.weatherOptions;
        state.nationalities = data.nationalities || state.nationalities;
        if (data.settings) {
            state.defaults = Object.assign({}, data.settings);
            if (!state.settings || !Object.keys(state.settings).length) {
                state.settings = Object.assign({}, data.settings);
            }
        }
        // clamp index
        const total = totalSlots();
        if (state.index >= total) state.index = Math.max(0, total - 1);

        applyTheme();
        app.setAttribute('data-menu', state.settings.menuStyle || 'cinematic');
        app.classList.toggle('bars-on', !!state.settings.cinematicBars);
        renderBrand();
        renderHints();
        renderAll();

        // preview current
        const slot = currentSlot();
        post('preview', slot.type === 'char'
            ? { gender: slot.data.gender, appearance: slot.data.appearance || null }
            : { gender: 0, __empty: true });
    }

    function handleResult(res) {
        state.busy = false;
        if (!res) return;
        if (res.action === 'create') {
            const btn = $('createSheet').querySelector('[data-act="submitCreate"]');
            if (btn) btn.removeAttribute('disabled');
            if (res.ok) { closeCreate(); }
            else { toast(res.err || 'Could not create character.', 'err'); }
        } else if (res.action === 'delete') {
            if (res.ok) { closeModal(); toast('Character deleted.', 'ok'); state.index = 0; }
            else { toast(res.err || 'Could not delete character.', 'err'); }
        } else if (res.action === 'select') {
            if (!res.ok) toast(res.err || 'Could not load character.', 'err');
        }
    }
})();
