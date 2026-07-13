# forger-multicharacter

A cinematic multicharacter selector for **QBCore**, **Qbox** and **ESX Legacy**.
It replaces your framework's built-in character screen with a live 3D character
showcase (scenic backdrops, idle poses, camera zoom, weather/time, colour-grade
filters, optional background music), a post-pick **spawn selector**, per-player
**character-limit** overrides, and a pluggable **clothing/appearance** layer that
shows each character's real saved outfit on the preview ped.

- **Frameworks:** Qbox (`qbx_core`), QBCore (`qb-core`), ESX Legacy (`es_extended`)
- **Database:** `oxmysql`
- **No SQL migration** on QB/Qbox (uses the standard `players` table). ESX uses
  the standard `users` table.

---

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Install](#install)
- [Framework setup (QBCore / Qbox / ESX)](#framework-setup)
- [Clothing / appearance](#clothing--appearance)
- [Character limits & overrides](#character-limits--overrides)
- [Discord role slots](#discord-role-slots)
- [Spawn selector](#spawn-selector)
- [Scenes, poses & camera](#scenes-poses--camera)
- [Camera filters](#camera-filters)
- [Weather, time & zoom](#weather-time--zoom)
- [Background music](#background-music)
- [Persisted preferences](#persisted-preferences)
- [Logout / switch character](#logout--switch-character)
- [Deleting owned data](#deleting-owned-data)
- [Project structure](#project-structure)
- [Events & exports](#events--exports)
- [Troubleshooting](#troubleshooting)

---

## Features

- **Cinematic character showcase** — a live 3D preview ped on scenic backdrops,
  gender-specific idle poses, camera zoom presets, and a full settings panel
  (theme, weather, time of day, camera filters, audio).
- **Two menu layouts** — **Cinematic** (info + action cluster) and **Classic**
  (vertical menu), switchable in settings.
- **Spawn selector** shown after a character is chosen: pick "Last Location" or a
  configured spawn point before dropping into the world, with the cinematic scene
  live behind the picker.
- **Guaranteed-correct freemode ped on spawn** — the player is forced onto
  `mp_m_freemode_01` / `mp_f_freemode_01` by gender *before* the clothing resource
  runs, so you never get stuck on a story ped (Michael, etc.) when a saved look
  doesn't set its own model.
- **Create / delete / play** flow, fully server-authoritative with ownership
  checks on every action.
- **Per-player character limits** with overrides that stack from four sources
  (identifier, ace, Discord role, config default).
- **Pluggable clothing layer** — shows each character's saved outfit on the
  preview ped. Works with illenium-appearance, fivem-appearance, ESX
  skinchanger/esx_skin, qb-clothing, or nothing at all.
- **Keyboard driven** — `Enter` play, `E` pose, `J` location, `Z` zoom, `B`
  cinematic bars, `H` hide UI, arrows to browse.

---

## Requirements

- `oxmysql`
- One supported framework: `qbx_core`, `qb-core`, **or** `es_extended`
- (ESX only) `es_extended` must have `Config.Multichar = true`

---

## Install

1. Drop `forger-multicharacter` into your `resources` folder.
2. Ensure it **after** `oxmysql` and your framework core:
   ```cfg
   ensure oxmysql
   ensure qbx_core        # or qb-core, or es_extended
   ensure forger-multicharacter
   ```
3. Disable your framework's built-in character selector so the two don't fight
   (see [Framework setup](#framework-setup)).
4. Restart the server.

By default `Config.AutoOpen = true` opens the selector the first time a client's
session starts. To drive it from your own connect flow instead, set it to `false`
and trigger the client event `forger:client:open` when ready.

---

## Framework setup

`Config.Framework` is `'auto'` by default and detects, in order: `qbx_core`,
`qb-core`, `es_extended`. Force it (`'qbx'`, `'qb'`, `'esx'`) if detection is ever
wrong. Only the **login / create handoff** is framework-specific; it lives in
`bridge/framework.lua`, which normalizes everything else so `server/main.lua`
never branches on the framework.

### Qbox (`qbx_core`)

- Disable Qbox's own character selection so it doesn't open its screen too.
- Recommended: enable the qb-core bridge so the QB player-loaded event fires
  (some clothing resources listen for it):
  ```cfg
  setr qbx:enablebridge true
  ```
- Characters live in the standard `players` table (`Config.DB`).

### QBCore (`qb-core`)

- Stop `qb-multicharacter` (don't `ensure` it).
- Characters live in the standard `players` table (`Config.DB`).

### ESX Legacy (`es_extended`)

- Set **`Config.Multichar = true`** in `es_extended` — this resource reuses ESX's
  own character-load flow (`esx:onPlayerJoined`), which only accepts a character
  identifier when Multichar mode is enabled.
- Don't `ensure` `esx_multicharacter` (this resource replaces it). You may keep
  `esx_identity` / `esx_skin` if your clothing flow uses them.
- Characters live in the standard `users` table (`Config.ESX`), keyed by the
  `char<slot>:<license>` identifier scheme ESX multichar uses.
- ESX enforces its own slot ceiling (`Config.ESX.maxSlots`, mirror your
  `esx_multicharacter` `Config.Slots`); this resource clamps to it.

> **New ESX characters:** creation hands off to ESX's own create flow with the
> identity payload (firstname/lastname/dob/sex). If you use `esx_identity` /
> `esx_skin`, ESX opens the creator itself on player load — leave
> `Config.Appearance.apply.newCharacterEvent = nil` in that case.

---

## Clothing / appearance

The preview ped looks sharp with a clean default freemode ped out of the box. To
show each character's **saved** outfit, point `Config.Appearance` at your clothing
resource. The config has two independent halves:

- **`read`** — how the *server* reads a saved look out of the database (so the
  preview can show it).
- **`apply`** — how the *client* puts that look onto the preview ped and onto the
  real player on spawn.

Everything clothing-specific is isolated in `bridge/appearance.lua` (the
`Appearance.*` API), so adding a new resource is a config change, not a code hunt.

### Apply methods

| `apply.method` | For | Preview ped | Real player |
|---|---|---|---|
| `export` | illenium-appearance, fivem-appearance | exact (export takes a ped) | exact (model + clothing) |
| `skinchanger` | ESX classic (esx_skin/skinchanger) | native best-effort from the component map | `skinchanger:loadSkin` |
| `event` | qb-clothing | default ped | fires the outfit-load event |
| `none` | let your framework dress the player | default ped | default ped |

### Presets

Copy the block that matches your setup over `Config.Appearance` (full list is in
`config.lua`):

- **illenium-appearance (QB / Qbox)** — `read` from the `playerskins` table by
  `citizenid`; `apply` via `setPedAppearance` / `setPlayerAppearance`.
- **illenium-appearance (ESX)** — same exports, but `read.source = 'inline'`
  (the look is on `users.skin`).
- **fivem-appearance** — same export methods; `read` from `playerskins` (QB) or
  inline `users.skin` (ESX).
- **esx_skin + skinchanger (ESX classic)** — `read.source = 'inline'` (`users.skin`
  component map); `apply.method = 'skinchanger'`.
- **qb-clothing** — `read.source = 'none'` (it loads the player's outfit itself);
  `apply.method = 'event'` with `playerEvent = 'qb-clothing:client:loadPlayerClothing'`.
- **none** — `read.source = 'none'`, `apply.method = 'none'`. Preview is a clean
  freemode ped and your framework dresses the real player on spawn.

If your clothing resource dresses the player automatically on the framework's
player-loaded event, set `Config.PostLogin.clothingLoadsItself = true` so this
resource doesn't apply a second time and fight it.

---

## Character limits & overrides

Everything lives in `config.lua` under `Config.Slots` and `Config.Overrides`.

```lua
Config.Slots = {
    default = 2,            -- base slots for everyone
    absoluteMax = 8,        -- hard ceiling no override can pass
    resolution = 'highest', -- 'highest' (take best override) or 'sum'
}
```

Grant extra slots per player through any of these — the resolver takes the best
match (or sums them, if `resolution = 'sum'`), then clamps to `absoluteMax`. On
ESX the result is additionally clamped to `Config.ESX.maxSlots`.

**By identifier** (license, discord, steam, fivem, etc.):
```lua
Config.Overrides.identifiers = {
    ['license:0a1b2c3d...']         = 5,
    ['discord:123456789012345678']  = 6,
}
```

**By ace permission** (easiest if you already run permissions):
```lua
Config.Overrides.aces = {
    ['forger.slots.vip'] = 4,
    ['group.admin']      = 8,
}
-- server.cfg:  add_ace group.vip forger.slots.vip allow
```

**By Discord role** (requires the Discord section below):
```lua
Config.Overrides.discordRoles = {
    ['1234567890123456789'] = 5, -- VIP role id
    ['9876543210987654321'] = 7, -- VIP+ role id
}
```

---

## Discord role slots

1. Create a Discord bot, invite it to your guild, and enable the **Server
   Members Intent** in the bot's settings.
2. Put the token in `server.cfg` (never in the Lua file):
   ```cfg
   set forger_discord_token "YOUR_BOT_TOKEN"
   ```
3. In `config.lua`:
   ```lua
   Config.Discord.enabled = true
   Config.Discord.guildId = 'YOUR_GUILD_ID'
   ```

Roles are cached per player for `Config.Discord.cacheSeconds` to stay well under
Discord's rate limits.

---

## Spawn selector

After a character is picked, `Config.Spawn` shows a spawn picker over the same
live cinematic backdrop. Players choose **Last Location** (only offered when the
character has a saved position) or any configured spawn point. Set
`Config.Spawn.enabled = false` to skip it and drop straight to the last saved
position; `Config.Spawn.showForNewCharacters = false` skips it for brand-new
characters. `Config.PostLogin.defaultSpawn` is the fallback / new-character spawn.

---

## Scenes, poses & camera

`Config.Locations` holds the backdrops cycled with `J` (ped spot + optional
per-location `cam`). `Config.Poses` holds the gender-specific idle animations
cycled with `E`. Both are plain lists you can extend.

- The camera is computed in front of the ped so the full body is always framed,
  and the ped is ground-snapped at spawn so it never floats.
- **Motion** (`Config.Camera.motion`, or a per-location `cam.motion`): `static`,
  `sway` (gentle arc), `orbit` (slow full orbit), `push` (slow dolly).
- Per-location override example:
  ```lua
  Config.Locations = {
      { label = 'Cassidy Falls', ped = vec4(-1642.44, 4497.86, 12.05, 55.0),
        cam = { motion = 'orbit', distance = 3.4, fov = 46.0 } },
  }
  ```

### Poses (gender-specific)

`Config.Poses` is split into `male` and `female` lists, cycled with `E`. Index 1
is a dance; the rest are the bundled pose packs streamed from `stream/`:

- male peds use the Male Pose Pack (`posepack1@diday` … `posepack6@diday`)
- female peds use the QueenSisters ladies pack

The `.ycd` files are streamed automatically. `Config.RandomPoseOnLoad` picks a
random pose per character; `Config.PoseBlendIn` controls how softly a pose eases
in; `Config.EmoteLoop` makes poses replay with a short pause instead of a seamless
loop.

---

## Camera filters

Filters are applied **game-side** so they actually change the render (CSS
`backdrop-filter` doesn't reliably touch the game in FiveM's browser). Chosen in
**Settings → Camera Filter**:

- **Portrait** — real depth-of-field blur on the scripted camera (character sharp,
  background blurred, like phone portrait mode).
- **HD Crisp**, **Noir**, **Golden** — custom **timecycle** colour grades from the
  bundled `timecycle_mods.xml` (`forger_hd`, `forger_noir`, `forger_golden`), plus
  a matching NUI tint/vignette as a cue.

Retune grades in `timecycle_mods.xml`, map names in `Config.Filters`, and edit the
`.filter-layer.f-*` rules in `web/css/style.css` for the on-screen tint. The
manifest ships `data_file 'TIMECYCLEMOD_FILE' 'timecycle_mods.xml'` — keep that
line if you rename things.

---

## Weather, time & zoom

- **Weather / time** are chosen in **Settings** and *held* while the screen is
  open (time re-applied every frame, weather every couple of seconds) so a server
  clock/weather-sync resource can't revert the selection mid-preview. If your sync
  is extremely aggressive, pause it during character select.
- **Zoom** — three presets (**Close**, **Medium**, **Far**) at the top of the
  screen, or press `Z` to cycle. Defined in `Config.Camera.zoom`;
  `Config.Camera.defaultZoom` sets the start level. The choice is saved per player.

---

## Background music

**Settings → Audio → Background Music**: paste a YouTube link and press play. It
auto-starts when the player opens the character screen (if enabled and a link is
saved), loops, and follows the Music Volume slider. It uses the YouTube IFrame
API, so the client needs internet access. (If a browser blocks first autoplay,
pressing play once starts it.)

---

## Persisted preferences

Theme, camera filter, weather, time of day, menu style, the display/audio
toggles, the volumes, the zoom level and the music link are all saved per player
with `SetResourceKvp` and restored automatically the next time they load in.

---

## Logout / switch character

`Config.Logout` adds a `/logout` command that logs the player out of their current
character (the framework saves position + data first) and re-opens the selector so
they can switch. Optional ace restriction (`Config.Logout.restricted` + `ace`) and
a per-player cooldown.

---

## Deleting owned data

`server/main.lua` deletes the character's main row (via the framework bridge) and
attempts a few common owned-data tables (`player_vehicles`, `player_houses`,
`playerskins`, and ESX `owned_vehicles` / `user_licenses`) wrapped so a missing
table never errors. Add any per-character tables your server uses to that
`cleanup` list. The key column is the character id — `citizenid` on QB/Qbox, the
`identifier` on ESX.

---

## Project structure

```
forger-multicharacter/
├── fxmanifest.lua
├── config.lua               all tunables (framework, DB, slots, appearance, scenes…)
├── bridge/
│   ├── framework.lua        SERVER: QB/Qbox/ESX adapter (list/create/delete/login) → FW.*
│   └── appearance.lua       CLIENT: clothing apply layer (export/skinchanger/event) → Appearance.*
├── client/
│   └── main.lua             selector, preview scene, camera, poses, spawn handoff, NUI bridge
├── server/
│   ├── main.lua             list/select/create/delete handlers + /logout (framework-agnostic)
│   ├── slots.lua            per-player slot resolution (overrides + Discord)
│   └── discord.lua          cached Discord role lookups
├── locales/
│   └── en.lua
├── web/                     NUI (character screen + spawn selector)
│   ├── index.html
│   ├── css/  (style.css, spawn.css)
│   ├── js/   (app.js, spawn.js)
│   ├── fonts/  img/
├── stream/                  bundled idle-pose .ycd packs
└── timecycle_mods.xml       custom colour-grade modifiers for the filters
```

The two files in `bridge/` are the only place that knows about frameworks and
clothing resources. Everything else talks through their normalized APIs (`FW.*`
on the server, `Appearance.*` on the client).

---

## Events & exports

Client:
- `forger:client:open` — open the selector (use with `Config.AutoOpen = false`).

Server (fired by this resource, for your own hooks):
- `forger:server:characterSelected(src)` — a character was selected/created.
- `forger:server:characterDeleted(src, id)` — a character was deleted.

---

## Troubleshooting

**"0 characters" / no characters show up.** Check `Config.Framework` resolved to
the right value (the console prints it on start), and that your DB config matches:
`Config.DB` (QB/Qbox `players`) or `Config.ESX` (`users`). On ESX confirm the
`users.identifier` uses the `char<slot>:<license>` scheme and that your
`Config.ESX.prefix` matches `esx_multicharacter`'s `Config.Prefix`.

**Player spawns as the wrong ped (Michael, etc.).** Leave
`Config.PostLogin.forceFreemodeModel = true` so a clean freemode base is set
before clothing loads. If your clothing resource dresses the player itself on
load, also set `Config.PostLogin.clothingLoadsItself = true`.

**Preview ped has no clothing.** Set `Config.Appearance` to the preset matching
your clothing resource. For export-based resources (illenium/fivem-appearance) the
preview is exact; for `skinchanger` it's a native best-effort; for `event`
(qb-clothing) the preview stays a default ped by design.

**ESX characters won't load.** Ensure `Config.Multichar = true` in `es_extended`
and that `esx_multicharacter` is **not** running alongside this resource.

**Loading screen never goes away (Qbox/QB "Downloading ... Server" hangs).** The
connection loading screen is normally dismissed by the framework's multichar step,
which this resource replaces — so it can hang. This resource already calls
`ShutdownLoadingScreen()` / `ShutdownLoadingScreenNui()` when the selector opens to
handle it. If your loading screen still sticks (custom loadscreen resource), also
set `setr loadscreen:externalShutdown false` in `server.cfg`.

**Repeated sky pans / fades on join.** Another spawn/char resource is respawning
the player. This resource disables the default spawn manager's auto-spawn; make
sure your old multichar/spawn flow is disabled as described in
[Framework setup](#framework-setup).

**Weather/time keeps changing during select.** A weather-sync resource is
overriding it; pause that resource during character selection.
