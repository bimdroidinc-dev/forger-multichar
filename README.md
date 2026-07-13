# forger-multicharacter

A crisp, cinematic multicharacter selector for **Qbox / QBCore** with a custom
NUI (no external UI libraries), per-player character limits, and slot overrides
by Discord role, identifier, or ace permission.

Author: **Velocity Custom**

---

## Features

- **Spawn selector** shown after a character is chosen: pick "Last Location" or
  any configured spawn point (`Config.Spawn`) before dropping into the world.
  The cinematic scene stays live behind the picker. Set `Config.Spawn.enabled =
  false` to skip it and go straight to the last saved position.
- Guaranteed correct freemode ped on spawn (`Config.PostLogin.forceFreemodeModel`
  = `true`). The player is forced onto `mp_m_freemode_01` / `mp_f_freemode_01`
  by gender *before* the appearance resource runs, so you never get stuck on a
  story ped (Michael, etc.) when a saved skin doesn't set its own model.
- Cinematic character showcase with a live 3D preview ped, scenic backdrops,
  poses, and a full settings panel (theme, weather, time of day, audio).
- Two menu layouts: **Cinematic** (info + action cluster) and **Classic**
  (vertical menu), switchable in settings.
- Create / delete / play flow, all server-authoritative with ownership checks.
- **Character limits** with per-player overrides that stack from four sources.
- Custom NUI, keyboard-driven (`Enter` play, `E` pose, `J` location, `B` bars,
  `H` hide UI, arrows to browse), fully themed and accessible.

No SQL migration is required. Characters use the standard QB/Qbox `players`
table. The optional backstory is stored inside the existing `charinfo` JSON.

---

## Install

1. Drop `forger-multicharacter` into your `resources` folder.
2. Ensure it **after** `oxmysql` and your framework core:
   ```cfg
   ensure oxmysql
   ensure qbx_core        # or qb-core
   ensure forger-multicharacter
   ```
3. Disable your framework's built-in character selector so the two don't fight:
   - **Qbox:** in `qbx_core` set the multichar/spawn selection to off (see your
     `qbx_core` config; the option that opens its own character screen).
   - **qb-core:** stop `qb-multicharacter` (`ensure` it off).
4. Restart the server.

By default `Config.AutoOpen = true` opens the selector the first time a client's
session starts. If you prefer to drive it from your own connect flow, set it to
`false` and trigger the client event `forger:client:open` when ready.

---

## Character limits

Everything lives in `config.lua` under `Config.Slots` and `Config.Overrides`.

```lua
Config.Slots = {
    default = 2,          -- base slots for everyone
    absoluteMax = 8,      -- hard ceiling no override can pass
    resolution = 'highest', -- 'highest' (take best override) or 'sum'
}
```

Grant extra slots to individual players through any of these — the resolver
takes the best match (or sums them, if `resolution = 'sum'`), then clamps to
`absoluteMax`:

**By identifier** (license, discord, steam, fivem, etc.):
```lua
Config.Overrides.identifiers = {
    ['license:0a1b2c3d...'] = 5,
    ['discord:123456789012345678'] = 6,
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

### Discord role setup

1. Create a Discord bot, invite it to your guild, and enable the
   **Server Members Intent** in the bot's settings.
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

## The one integration point to verify

Reading and deleting characters is plain oxmysql and works everywhere. The
**login / create handoff** is the only framework-specific piece, in
`bridge/framework.lua`:

- **Qbox** uses `exports.qbx_core:Login(src, citizenid)` to load an existing
  character and `exports.qbx_core:Login(src, nil, newData)` to create one.
- **QBCore** uses `QBCore.Player.Login(src, citizenid[, newData])`.

If your core version expects a different creation payload, adjust
`FW.CreateAndLogin` — it is small and clearly commented. Set
`Config.Framework` to `'qbx'` or `'qb'` to skip auto-detection.

---

## Deleting owned data

`server/main.lua` deletes the `players` row and attempts a few common
owned-data tables (`player_vehicles`, `player_houses`, `playerskins`) wrapped so
a missing table never errors. Add any per-character tables your server uses to
that `cleanup` list.

---

## Preview clothing (optional)

The preview ped uses a clean default freemode look out of the box. To show each
character's **saved** clothing, wire your appearance resource:

- Set `Config.Appearance.resource` (`illenium-appearance`, `fivem-appearance`,
  or `qbx_clothing`).
- Have the server include each character's saved appearance JSON in the payload
  (read it from your skins table in `fetchCharacters`), and the client will
  apply it via `applyAppearance` in `client/main.lua`.

This is left as a hook because skin storage differs per server; the selector
looks sharp without it.

---

## Scenes & poses

`Config.Locations` holds the backdrops cycled with `J` (ped spot + camera).
`Config.Poses` holds the idle animations cycled with `E`. Both are plain lists
you can extend.

The camera is computed in front of the ped so the full body is always framed.
Tune it in `Config.Camera`:

```lua
Config.Camera = {
    distance = 2.75,  -- metres in front (bigger = further / more zoomed out)
    height = 0.55,    -- metres up (bigger = looks down more)
    pointAt = 0.45,   -- height on the body the camera aims at
    fov = 38.0,       -- lower = tighter zoom
    -- widened automatically while paired:
    pairDistance = 3.7, pairHeight = 0.6, pairPointAt = 0.5, pairFov = 42.0,
}
```

The ped is ground-snapped at spawn so it never floats, even if a location's z
is slightly off.

### Moving (dynamic) camera

`Config.Camera.motion` animates the shot:

- `static` – locked in place
- `sway` – gentle arc left/right in front of the ped (default)
- `orbit` – slow continuous orbit all the way around
- `push` – slow dolly in and out

Speeds/ranges are `swayArc`, `swaySpeed`, `orbitSpeed`, `pushAmount`, `pushSpeed`.
Any location can override the camera for that scene by adding a `cam` table:

```lua
Config.Locations = {
    { label = 'Cassidy Falls', ped = vec4(-1642.44, 4497.86, 12.05, 55.0),
      cam = { motion = 'orbit', distance = 3.4, fov = 46.0 } },
}
```

Grounding note: the character is spawned and then placed with `SetEntityCoords`
(the offset variant, so the feet sit on the surface) at a z found by a downward
ray, which correctly hits pier decks, roads and terrain. Keep location spots
outdoors. Camera motion defaults to `static`; give a location a `cam` table to
move the camera only in the scenes that want it, and the camera is created
already framed on the character so it never eases/drops in.

### Poses (gender-specific, dancing by default)

`Config.Poses` is split into `male` and `female` lists, cycled with `E`. Index 1
is the default and is a dance. The rest are the bundled pose packs:

- male peds use the Male Pose Pack (`posepack1@diday` ... `posepack6@diday`)
- female peds use the QueenSisters Premium Ladies Pack

All pose `.ycd` files are streamed from `stream/` automatically. The ladies pack
files are renamed to match their in-game dictionary names (with the `@`) so
`RequestAnimDict` resolves them. These single-ped poses are separate from the
couple/friend **partner** emotes.

---

## Partner system (couple & friend)

Two players who **both have the character screen open** can pair up and perform
synced paired emotes.

1. Open the character screen. Presence is tracked automatically and the panel
   shows your **server ID**.
2. Open **Partner** (users icon in cinematic, "Partner" in the classic menu, or
   press `P`).
3. **Search** by in-game name or server ID. Only players who also have the
   screen open appear.
4. Send a request with the **heart** (couple) or **users** (friend) button. The
   target gets a top-left notification and an **Incoming** badge.
5. The target **accepts** → a MATCH! popup shows and each player now sees their
   partner's character beside them doing the paired emote.
6. Either partner can **cycle emotes** with the on-screen bar (or left/right
   arrows while paired) and **Leave** with the bar button or `X`.

Pairing tears down automatically when either player picks a character, closes
the screen, or disconnects.

### Emotes

Couple emotes come from the two animation packs bundled in `stream/` — they load
automatically, no separate resource. Friend emotes use built-in GTA paired
animations (no files). Edit `Config.Partner.emotes.couple` / `.friend` to add,
remove, or relabel; each entry is a paired clip where the inviter plays `a` and
the target plays `b`. Disable the whole feature with `Config.Partner.enabled = false`.

---

## Troubleshooting: "no characters show up"

The players table stores either `license:...` or `license2:...` depending on
setup. This resource matches against **all** of a player's license identifiers.
When zero characters are found, the server console prints exactly what it matched
and the table/column used:

```
[forger-multicharacter] 0 characters for Name. Matched against {license:abc, license2:def} in `players.license`.
```

Compare that to the `license` column of the player's row. If it holds a
different value, point `Config.DB.columnLicense` at the column your framework
actually uses.

---

## Camera filters

Filters are applied **game-side** so they actually change the scene (CSS
`backdrop-filter` doesn't reliably touch the game on FiveM's browser). Chosen in
**Settings > Camera Filter**:

- **Portrait** - a real depth-of-field blur on the scripted camera: the
  character stays sharp and the background blurs, like phone portrait mode.
- **HD Crisp**, **Noir**, **Golden** - custom **timecycle** colour grades from
  the bundled `timecycle_mods.xml` (`forger_hd`, `forger_noir`, `forger_golden`
  - your own modifiers, not stock GTA ones), plus a matching NUI tint/vignette
  as a visible cue.

Edit `timecycle_mods.xml` to retune the grades, `Config.Filters` to map filter
names to a timecycle modifier / DOF, and the `.filter-layer.f-*` rules in
`web/css/style.css` for the on-screen tint. Because they're timecycle-based, the
resource ships `data_file 'TIMECYCLEMOD_FILE' 'timecycle_mods.xml'` in the
manifest - keep that line if you rename things.

## Background music (YouTube)

**Settings > Audio > Background Music**: paste a YouTube link and press play.
The track auto-starts whenever the player opens the character screen (if
Background Music is enabled and a link is saved), loops, and follows the Music
Volume slider. It uses the YouTube IFrame API, so the player's client needs
internet access. (If a browser blocks first autoplay, pressing play once starts
it.)

## Persisted preferences

Theme, camera filter, weather, time of day, menu style, the display/audio
toggles, the volumes and the music link are all saved per-player with
`SetResourceKvp` and restored automatically the next time they load in.

## Weather / time hold

While the character screen is open the chosen time is re-applied **every frame**
and the weather every couple of seconds, so a server clock or weather-sync
resource can't revert the player's selection mid-preview. (If your sync resource
is extremely aggressive, pause it during character select via whatever
export/event it provides.)

The scene also forces a streaming focus + load-scene pass at the location so the
backdrop renders in full detail instead of low-LOD popping.

## Camera zoom

Three zoom presets sit at the top of the character screen (or press `Z` to
cycle): **Close** (the original tight shot), **Medium** (a step back), and
**Far** (full head-to-toe). They're defined in `Config.Camera.zoom` - each entry
sets the camera distance, height, aim and FOV, so you can retune any of them.
`Config.Camera.defaultZoom` picks the starting level, and the player's choice is
saved with the rest of their preferences.

## No spawn pan / repeated fades

On join the resource disables the default spawn manager's auto-spawn
(`setAutoSpawn(false)`) and keeps the screen black + the player hidden until the
selector's camera is ready. Without this the game keeps respawning the player
(each respawn plays GTA's top-down establishing pan and a fade), which looks
like the camera panning from the sky and the screen going dark on a loop. If you
still see repeated fades, another resource (usually an un-disabled core
multichar or a spawn script) is respawning the player - disable its spawn/char
flow as described in the install section.

## Partner emotes: grounding & location changes

- The paired-emote clips in the couple packs are authored with the origin at the
  ped's root, so the synchronized-scene origin is raised by
  `Config.Partner.sceneZOffset` (default 0.98) so the couple stand on the ground
  instead of sinking to the waist. If a future pack sits slightly high/low, tune
  that one value.
- Changing location (`J`) while paired now re-creates the paired scene at the new
  spot so your partner comes with you.

The couple/friend emotes are exactly the ones bundled in `Config.Partner.emotes`
(all cycled with the on-screen emote bar). A "hold hands and walk together" style
emote needs a *walking* paired animation, which isn't in the uploaded packs - drop
a walking paired `.ycd` in `stream/` and add it to `Config.Partner.emotes.couple`
and it'll appear in the cycle.

## Persistent partners & appearance cloning

Pairings are stored in the `forger_partners` table (auto-created) keyed by
character **citizenid**, so they survive restarts. Whenever a player views a
paired character on the selection screen, their partner's real character is
cloned into the scene doing the couple/friend emote - **even if the partner is
offline**. Browsing to a different character shows that character's partner (or
none).

To clone the partner's actual **appearance** (clothes/face), the server reads
their saved look from your clothing resource via `Config.Appearance` -
`skinTable` / `skinIdColumn` / `skinColumn` and applies it with
`exports[resource][applyExport](ped, skin)`. Point those at your appearance
resource's storage. If `skinTable = false` (or the format doesn't match), the
partner still appears as a correct-gender ped, just in default clothing.

Invites now pop a **direct confirmation box** (Accept / Decline) with a 10-second
countdown. If it times out, the request stays in the **Incoming** tab (up to
`Config.Partner.requestTimeout`) so it can be accepted/declined from the Partner
menu. "Leave" on the emote bar permanently unpairs (removes the DB record).

## Spawn / appearance (illenium-appearance)

This resource replaces your multichar, so it also runs the login->spawn handoff.
Configured for illenium in `Config.PostLogin`:

- **Existing character** -> fires `illenium-appearance:client:reloadSkin`, which
  loads the character's saved model + clothing, then teleports to the last saved
  position.
- **New character** -> fires `illenium-appearance:client:createFirstCharacter`,
  opening illenium's creator so the character actually gets a saved look. Without
  this, characters made in the selector have NO appearance and spawn as a default
  ped every time - which is the usual cause of "spawning as another ped".

Both event names are in `Config.PostLogin` (`loadClothingEvent` /
`newCharacterEvent`) - if your illenium fork uses different names, change them
there. `Config.PostLogin.setModel/applyAppearance` stay off for illenium.

Offline partners: pairings live in `forger_partners` by citizenid, so you see
your partner (cloned from their saved character) whenever you view the paired
character even if they're offline, and they see you the same way.
