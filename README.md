# forger-multicharacter

A cinematic multicharacter selector for **Qbox / QBCore** with a custom NUI (no
external UI libraries), a spawn picker, per-player character limits, starter
items, and a scene builder.

Author: **Velocity Custom**

---

## Features

- **Cinematic showcase** — live 3D preview ped, scenic backdrops, emotes, camera
  filters, and a settings panel (theme, weather, time of day, audio).
- **Spawn picker** after a character is chosen: "Last Location" or any configured
  spawn point, with the scene still live behind it.
- **No streamed assets.** Every animation the showcase and partner system use
  ships with the base game. There is no `stream/` folder to keep in sync and
  nothing extra for players to download on join.
- **Starter items** for brand new characters, with ID card support.
- **Character limits** with per-player overrides from four sources (default, ace,
  identifier, Discord role).
- **Partner system** — two players on the character screen can pair up and appear
  together doing synced emotes. Pairings persist and show even when the partner is
  offline.
- **Scene Maker** (`/scene`) — pose your character, frame a shot, set the time and
  weather, and save it as that character's personal backdrop. Co-op sessions let
  several players build one scene together.
- Two menu layouts: **Cinematic** and **Classic**, switchable in settings.
- Guaranteed correct freemode ped on spawn, so nobody gets stuck on a story ped.
- Keyboard-driven: `Enter` play, `E` emote, `J` location, `Z` zoom, `B` bars,
  `H` hide UI, `P` partner, arrows to browse.

No SQL migration is required for characters — the standard QB/Qbox `players` table
is used, and the optional backstory lives inside the existing `charinfo` JSON. The
partner and scene tables are created automatically.

---

## Install

1. Drop the folder in your resources and `ensure forger-multicharacter`.
2. **Disable your existing multicharacter** (`qbx_multicharacter`,
   `qb-multicharacter`, etc.) and any spawn selector you don't want this resource
   handing off to.
3. On Qbox, make sure the qb-core bridge is on:

   ```cfg
   setr qbx:enablebridge true
   ```

4. Point `Config.Appearance` at your clothing resource's storage.
5. Check `Config.StarterItems.items` against your own items list.

Requires `oxmysql`. Nothing else is mandatory.

---

## Character limits

`Config.Slots.default` is what everyone gets. Overrides raise it, and
`Config.Slots.absoluteMax` is a hard ceiling nothing can exceed.

```lua
Config.Overrides = {
    identifiers  = { ['license:0a1b...'] = 5 },
    aces         = { ['forger.slots.vip'] = 4 },
    discordRoles = { ['1234567890123456789'] = 6 },
}
```

`Config.Slots.resolution` decides how multiple matches combine — `'highest'` takes
the biggest that applies, `'sum'` adds them. Either way the result is clamped to
`absoluteMax`.

Grant an ace override with:

```cfg
add_ace group.vip forger.slots.vip allow
```

### Discord role setup

```cfg
set forger_discord_token "YOUR_BOT_TOKEN"
```

Set `Config.Discord.enabled = true` and fill in `guildId`. The bot must be in your
guild with the **Server Members Intent** enabled. Role lookups are cached for
`cacheSeconds` to stay inside Discord's rate limits.

---

## Starter items

Given once, to brand new characters only, immediately after the core confirms the
character was created.

```lua
Config.StarterItems = {
    enabled = true,
    items = {
        { item = 'phone',          amount = 1 },
        { item = 'id_card',        amount = 1 },
        { item = 'driver_license', amount = 1 },
        { item = 'water_bottle',   amount = 2 },
        { item = 'sandwich',       amount = 2 },
        { item = 'lockpick',       amount = 1, metadata = { quality = 100 } },
    },
    giveIdCards = true,
}
```

Each entry takes `item`, `amount`, and optionally `metadata` and `slot`.

**Inventory detection is automatic**, in this order: `ox_inventory`,
`qb-inventory`, then the core's own `AddItem`. There is nothing to configure.

**ID cards are special-cased.** `id_card` and `driver_license` are handed to
`um-idcard`, `bl_idcard` or `qbx_idcard` if one of them is running, so the licence
is built the way that resource expects. With none installed, the character's name,
date of birth, gender and nationality are written into the item metadata directly
so the card isn't blank. Set `giveIdCards = false` if your ID resource issues
licences on its own and you want this resource to stay out of it.

Item names that don't exist in your items list are skipped and listed in a single
console warning, so a typo costs you that one item rather than the whole batch.

To react to it yourself:

```lua
AddEventHandler('forger:server:starterItemsGiven', function(src, count)
    -- count = how many entries were successfully given
end)
```

---

## The login handoff (the one thing to verify)

Reading and deleting characters is plain oxmysql and works everywhere. The
**login / create handoff** is the only framework-specific piece, in
`bridge/framework.lua`:

- **Qbox** — `exports.qbx_core:Login(src, citizenid)` to load, and
  `exports.qbx_core:Login(src, nil, newData)` to create. Existing characters log in
  through the **qb-core bridge** rather than the native export, because the bridge
  fires `QBCore:Client:OnPlayerLoaded`, which is what illenium-appearance listens
  for to auto-load the saved skin.
- **QBCore** — `QBCore.Player.Login(src, citizenid[, newData])`.

Set `Config.Framework` to `'qbx'` or `'qb'` to skip auto-detection.

### Spawn confirmation

Calling the core's `Login` only tells **the core** it has a character. Almost
everything else on a QB/Qbox server — HUD, phone, garages, jobs, dispatch,
inventory UIs — waits for the *spawn confirmation* events instead. If those never
fire, the character loads fine but the rest of the server behaves as though the
player never joined.

They are fired from the client the moment the ped exists, is dressed, and is
standing at its coords:

| Event | Direction | Purpose |
| --- | --- | --- |
| `QBCore:Server:OnPlayerLoaded` | client → server | the confirmation both cores and most third-party resources hook |
| `QBCore:Client:OnPlayerLoaded` | client | what nearly every QB/Qbox client script waits on to initialise |
| `qb-houses:server:SetInsideMeta` | client → server | clears "inside a property" metadata |
| `qb-apartments:server:SetInsideMeta` | client → server | same, for apartments |
| `forger:server:playerSpawned` | client → server | this resource's own hook |

All of them are configurable in `Config.PostLogin` — rename them, add your own to
`extraLoadedEvents`, or turn the block off with `notifyLoaded = false`. The housing
events are harmless no-ops if you don't run those resources.

Two supporting pieces:

**The server waits for the core before releasing the client.** `FW.Login` returning
`true` only means the call was accepted; the core still has async work to do (money,
job, metadata, inventory). `server/main.lua` blocks on `FW.WaitForLoaded(src)` until
the core announces the load — tracked under both `QBCore:Server:PlayerLoaded` and
`qbx_core:server:playerLoaded` — before telling the client to spawn. On timeout
(`Config.PostLogin.loadTimeoutMs`, default 10s) it warns and continues rather than
failing, and a fallback treats a real player object carrying a citizenid as loaded
in case your setup renames the event.

**`forger:server:playerSpawned` finishes up.** It refreshes chat commands (qb-core
registers them per-character, so without this players have no commands until they
reconnect), resets the routing bucket to 0 if anything moved them — the Scene Maker
co-op sessions do — and then fires:

```lua
AddEventHandler('forger:server:playerLoaded', function(src, citizenid)
    -- your own post-spawn logic
end)
```

### Weather handback

The selector force-holds its own weather and clock every frame so a server sync
can't revert them. On spawn that hold is released (`ClearOverrideWeather`,
`ClearWeatherTypePersist`, `NetworkClearClockTimeOverride`) and
`Config.PostLogin.weatherSyncEvent` fires — `qb-weathersync:client:EnableSync` by
default. Without this the override survives into the world and the player is stuck
in permanent selector weather. Set `restoreWeatherSync = false` if your weather
resource handles this itself.

---

## Locations

`Config.Locations` holds the backdrops cycled with `J`. Every entry needs a `label`
and a `ped` vec4; everything else is optional.

| `mode` | What it does |
| --- | --- |
| `1` (default) | Over-the-shoulder portrait. |
| `2` | Prop scenario — needs `scenario` naming a `Config.PropScenarios` entry. |
| `3` | Locked-off camera — needs `camCoords`, optionally `fov`, `focusOffset`, `blurOptions`. |

Other per-location fields:

- `emote` — `{ scenario = ... }`, `{ dict = ..., anim = ... }` or `{ animName = ... }`.
  Omit it and a random `Config.Emotes.list` entry is used.
- `group` — a job or gang name, or a list of them. A character whose job or gang
  matches sees **only** that group's locations; everyone else sees the ungrouped
  ones. Job and gang names come from the players table automatically.
- `cam` — low-level overrides (`view`, `motion`, `panArc`, …).

`Config.RandomLocationOnLoad` starts the selector on a random location instead of
always the first. Cycling with `J` still walks the list in order from there.

### Prop scenarios (mode 2)

One synchronised scene drives the ped **and** its props, which is what keeps a
bottle or glass glued to the hand rather than floating beside it.

```lua
Config.PropScenarios = {
    bar = {
        dict = 'safe@trevor@ig_5',
        anim = 'drink_3',
        zOffset = 0.0,
        rotZ = 20.67,
        props = {
            { model = 1360987401,  anim = 'drink_3_beer' },
            { model = -1296774200, anim = 'drink_3_cam' },
        },
    },
}
```

`model` accepts a name or a hash. Hashes are used above because those are the exact
props the `drink_3` clip was authored against.

### Placing the ped

Collision is requested and **waited for** before the ped is placed, then the
position is re-asserted until the ped is within `Config.Scene.placeTolerance` of the
target. Placing a ped before the area has streamed is what leaves it floating or
buried to the chest.

`Config.Scene.groundSnap` controls how the Z is resolved:

- `true` (default) — raycast down and stand the ped on whatever surface is found.
  Correct even if a location's Z is approximate, and it handles pier decks and roads
  properly instead of snapping to the terrain underneath.
- `false` — trust the Z in `Config.Locations` exactly. Use this if you captured the
  coords while standing at the spot.

---

## Emotes

`Config.Emotes.list` is the rotation, cycled with `E` and used as the random pick
for any location that doesn't name its own emote. Each entry is one of:

```lua
{ scenario = 'WORLD_HUMAN_SMOKING' }         -- works on any ped
{ dict = '...', anim = '...', flag = 49 }     -- works on any ped
{ animName = 'texting' }                      -- an emote-menu name
```

**On `animName`:** emote menus (`rpemotes-reborn`, `rpemotes`, `scully_emotemenu`)
expose an export that animates the **local player ped only**. This resource
previews on a separate ped, so a partner, a saved scene and the spawn backdrop can
all coexist. An `animName` emote is therefore looked up in `Config.Emotes.aliases`
first:

```lua
aliases = {
    texting = { dict = 'cellphone@', anim = 'cellphone_text_read_base', flag = 49 },
    smoke   = { scenario = 'WORLD_HUMAN_SMOKING' },
}
```

A name that isn't there can't play on the preview ped, so a random `list` entry is
used instead and the console prints a one-off warning naming it. Prefer `scenario`
or `dict`+`anim` for locations.

`Config.EmoteLoop` applies to dict+anim emotes only — they play through, pause, then
replay. Scenarios are a continuous hold and are simply kept alive if something
clears them.

---

## Camera

Two framing systems live side by side in `Config.Camera.zoom`, cycled with `Z`:

```lua
{ label = 'Close',
  -- SOLO shots: the camera sits at a fixed offset in the ped's OWN space and aims
  -- at a second offset, so the portrait reads the same at every location no matter
  -- which way the ped faces. x = side, y = forward, z = up.
  offset = vec3(-1.2, 1.3, 0.55),
  focus  = vec3(0.28, 0.0, 0.58),
  soloFov = 12.0,

  -- PAIR and saved Scene Maker shots keep the polar values, because those shots
  -- have to fit two or more subjects.
  distance = 3.1, height = 0.48, pointAt = 0.5, fov = 44.0 },
```

`Config.Camera.posture = 'front'` turns the ped to face the camera instead of
keeping its location heading.

**Motion.** `Config.Camera.motion` is `static` by default. `sway`, `pan`, `orbit`
and `push` animate the shot, and any location can override it with its own
`cam.motion`. On solo shots the motion nudges the camera's side offset rather than
orbiting the ped, so the subject stays framed instead of swinging in and out.

**Depth of field.** `Config.Camera.dof` puts shallow depth of field on the character
shot — the blur that drops the background away. A mode 3 location's `blurOptions`
overrides `near`/`far`. The `portrait` camera filter replaces it with a tighter
distance-tracked blur.

**Intro.** `Config.Camera.intro` runs a slow push-in the first time the screen
opens. Character switches and location changes are always instant.

---

## Partner system

Two players who **both have the character screen open** can pair up.

1. Open the character screen. Presence is tracked automatically and the panel shows
   your **server ID**.
2. Open **Partner** (users icon in cinematic, "Partner" in classic, or press `P`).
3. **Search** by in-game name or server ID. Only players who also have the screen
   open appear.
4. Send a request with the **heart** (couple) or **users** (friend) button.
5. The target gets a confirmation box with a 10-second countdown. If it times out
   the request stays in the **Incoming** tab for `Config.Partner.requestTimeout`.
6. On accept, each player sees their partner's character beside them doing the
   paired emote. Cycle emotes with the on-screen bar or the arrow keys; leave with
   the bar button or `X`.

Pairings are stored in the `forger_partners` table (created automatically) keyed by
**citizenid**, so they survive restarts and show up **even when the partner is
offline**. Browsing to a different character shows that character's partner, or
none. "Leave" permanently unpairs.

The partner's real appearance is cloned from your clothing resource's storage via
`Config.Appearance`. If that doesn't match, the partner still appears as a
correct-gender ped in default clothing.

### Paired emotes

All dictionaries ship with the base game. Three entry forms:

```lua
-- gender paired: the viewed ped takes its own gender's clip, the partner the other
{ label = 'Talking', dict = 'timetable@trevor@ig_1',
  m = 'ig_1_therearejustsomemoments_trevor', f = 'ig_1_therearejustsomemoments_patricia' }

-- left / right paired
{ label = 'Fist Bump', dict = 'anim@mp_player_intcelebrationpaired@f_f_fist_bump',
  left = 'fist_bump_left', right = 'fist_bump_right' }

-- role paired: the inviter plays 'a', the target plays 'b'
{ label = 'Hug', a = { dict = '...', clip = '...' }, b = { dict = '...', clip = '...' } }
```

Both peds are local to each client, so each client only has to be self-consistent.

**If a clip sinks the peds or faces them the wrong way**, fix it per emote rather
than retuning everything:

- `Config.Partner.sceneZOffset` (default `0.98`) is the global lift, because most
  paired clips are authored with the origin at the ped's root and would otherwise
  sink the couple to the waist.
- `zOffset` on an emote is **added** to that. Clips authored at ground level — the
  paired celebration dicts — need `zOffset = -0.98`.
- `headingOffset` rotates the scene origin in degrees. The side-on celebration clips
  need `90.0`.

Both peds are **unfrozen** for the synchronised scene. A frozen ped can't be driven
by one — it just plays the animation where it was pinned — which is worth knowing if
you add your own paired emotes.

`upperBody = true` plays the emote on the upper body only, leaving the legs free;
add `walk = true` and the legs run a walk cycle. The shipped `Walk Together` entry
uses this. Changing location while paired re-creates the scene at the new spot so
your partner comes with you.

Disable the whole feature with `Config.Partner.enabled = false`.

---

## Scene Maker

`/scene` opens an in-game builder: pose your character, frame the camera, set the
time and weather, place vehicles, and save it as that character's personal backdrop
in the selector. Saved per character in `forger_scenes`.

Players opt into seeing saved scenes with the **custom scene** toggle in settings. A
partner always wins — while paired, the couple scene shows instead.

- `Config.SceneMaker.stances` — the poses the ped can hold. Either a `scenario` or a
  `dict` + `anim` (+ optional `flag`).
- `Config.SceneMaker.camera` — the orbit rig's defaults and limits.
- `Config.SceneMaker.restricted` + `ace` — lock the command behind a permission.

### Co-op scenes

`Config.SceneMaker.coop` lets the organizer invite nearby players into an isolated
routing bucket to build one scene together. The organizer controls time, weather and
camera and saves; invitees pick their own stance and place their own vehicles.
`bucketBase` is the routing-bucket range used for those sessions.

---

## Spawn selector

After a character is chosen, `Config.Spawn` shows a picker over the live scene.
Highlighting a tile flies the camera to that spot and streams it in, so the player
sees where they'll appear.

- `allowLastLocation` adds the "Last Location" tile when the character has a saved
  position.
- `showForNewCharacters = false` sends new characters straight to
  `Config.PostLogin.defaultSpawn`.
- `enabled = false` skips the picker entirely and goes to the last saved position.
- `icon` accepts any id from the set in `web/js/spawn.js`: `map-pin`, `building`,
  `plane`, `mountain`, `trees`, `waves`, `home`, `briefcase`, `star`, `history`.

### Last-position protection

After login the player is logged in while their hidden ped is still parked at the
showcase or spawn-preview coords, so any framework save in that window would write
those coords as the character's last position. The server stashes the real last
position at select time, writes the true spawn position once the client confirms
placement, and restores the stash if the player drops before ever spawning.

---

## Appearance and spawn

Configured for illenium-appearance in `Config.PostLogin`:

- **Existing character** — illenium loads the saved model and clothing itself on
  `QBCore:Client:OnPlayerLoaded` (`clothingLoadsItself = true`), so this resource
  doesn't trigger a reload. The look is pre-applied to the hidden player ped while
  the spawn picker is open, so the final spawn has no model swap inside the black
  screen.
- **New character** — fires `newCharacterEvent` to open illenium's creator, so the
  character actually gets a saved look. Without this, characters created in the
  selector have no appearance and spawn as a default ped every time.

`forceFreemodeModel` puts the player on `mp_m_freemode_01` / `mp_f_freemode_01` by
gender **before** the appearance resource runs, so a saved skin that sets no model
can't leave them on a story ped.

For a different clothing resource, point `Config.Appearance` at its storage and
check `applyExport`. `setPedAppearance` applies components, props, face, hair and
tattoos without touching the model; `setPlayerAppearance` would also re-set it.

---

## Camera filters

`Config.Filters` are applied game-side, not as a CSS overlay:

- `dof` — real depth-of-field background blur on the scripted camera.
- `timecycle` — a **custom** modifier shipped in `timecycle_mods.xml`, not a stock
  GTA one, plus a `strength` from 0 to 1.

The NUI shows a matching subtle vignette as a cue. Add your own by defining the
modifier in `timecycle_mods.xml` and adding an entry here.

---

## Persisted preferences

Theme, filter, zoom, weather, time, music URL, volumes, menu style and the custom
scene toggle are saved client-side with `SetResourceKvp` under `forger:prefs`, so a
player's setup is restored on their next login. Nothing is written to your database.

---

## Troubleshooting

**No characters show up.** The players table stores either `license:...` or
`license2:...` depending on setup, and this resource matches against **all** of a
player's license identifiers. When zero are found, the console prints exactly what
it matched and the table and column used:

```
[forger-multicharacter] 0 characters for Name. Matched against {license:abc, license2:def} in `players.license`.
```

If the identifiers listed there don't look like what's in your table, point
`Config.DB.columnLicense` at the column that does hold them.

**Clothing doesn't update when browsing characters.** Check
`Config.Appearance.skinTable` / `skinIdColumn` / `skinColumn`, and that
`skinActiveColumn` matches how your resource flags the current skin. Set it to
`false` if yours has no active flag.

**The core never fired its PlayerLoaded event.** Printed when `FW.WaitForLoaded`
times out. The character usually still loads, but it means something is wrong or
slow in your core, or the event has been renamed. Raise
`Config.PostLogin.loadTimeoutMs` if your server is simply slow to start.

**Starter items missing.** The warning names the items that failed. Those are item
names, not labels — check them against your items list.

**An emote isn't playing.** If the console names it, it's an `animName` with no
`Config.Emotes.aliases` entry. Add one, or switch that location to a `scenario`.

---

## License

See `LICENSE`.
