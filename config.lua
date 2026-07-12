Config = {}

-- ---------------------------------------------------------------------------
-- Framework
-- ---------------------------------------------------------------------------
-- 'auto' detects, in order: qbx_core, qb-core, es_extended. Force one if
-- detection is ever wrong on your server.
--   'qbx' - Qbox         (qbx_core)
--   'qb'  - QBCore       (qb-core)
--   'esx' - ESX Legacy   (es_extended, with Config.Multichar = true)
Config.Framework = 'auto' -- 'auto' | 'qbx' | 'qb' | 'esx'

-- Open the selector automatically the first time a client's session starts.
-- If your core (qbx_core / qb-multicharacter) already opens its own selector,
-- disable that one and either keep this true, or set this false and trigger
-- 'forger:client:open' from your connect flow.
Config.AutoOpen = true

-- /logout command: logs the player out of their current character (the framework
-- saves their position + data) and re-opens this character selector, so they can
-- switch characters. This mirrors qbx_core's built-in logout, which is what
-- mil-multichar hooks into.
Config.Logout = {
    enabled = true,
    command = 'logout',       -- chat command name (players type /logout)

    -- Permission. Leave restricted = false so any player can switch characters
    -- (the normal expectation). Set restricted = true to lock it behind an ace,
    -- then grant it with, e.g.:  add_ace group.admin forger.logout allow
    restricted = false,
    ace = 'forger.logout',

    -- Optional cooldown (seconds) between uses per player, to stop spam.
    cooldown = 2,
}

-- Name of the players table and its columns (QB / Qbox default schema). Only
-- used when Config.Framework resolves to 'qb' or 'qbx'.
Config.DB = {
    table = 'players',
    columnLicense = 'license',
    columnCitizenId = 'citizenid',
    columnCharInfo = 'charinfo',
    columnMoney = 'money',
    columnJob = 'job',
    columnPosition = 'position',
    columnLastUpdated = 'last_updated',
}

-- ESX (es_extended) schema. Only used when Config.Framework resolves to 'esx'.
-- ESX stores characters in the `users` table with flat columns and an
-- identifier of the form `char<slot>:<license>` (esx_multicharacter). This
-- resource reuses ESX's own load flow (esx:onPlayerJoined), so you MUST have
-- `Config.Multichar = true` set in es_extended for ESX character loading.
Config.ESX = {
    table = 'users',
    columnIdentifier = 'identifier',   -- 'char1:license:xxxx'
    columnFirstname = 'firstname',
    columnLastname = 'lastname',
    columnDob = 'dateofbirth',
    columnSex = 'sex',                 -- 'm' / 'f' (or 0 / 1 on some forks)
    columnAccounts = 'accounts',       -- JSON: { money = .., bank = .., black_money = .. }
    columnJob = 'job',                 -- job name
    columnJobGrade = 'job_grade',
    columnPosition = 'position',       -- JSON coords
    columnSkin = 'skin',               -- JSON appearance / skinchanger map
    columnMetadata = 'metadata',       -- JSON (playtime etc. if present)
    prefix = 'char',                   -- esx_multicharacter Config.Prefix
    maxSlots = 4,                      -- esx_multicharacter Config.Slots (ceiling ESX enforces)
    startingAccounts = { money = 0, bank = 5000 }, -- new-character accounts (ESX)
}

-- ---------------------------------------------------------------------------
-- Character slots
-- ---------------------------------------------------------------------------
Config.Slots = {
    -- Every player gets this many slots unless an override grants more.
    default = 2,

    -- No override can ever push a player above this hard ceiling.
    absoluteMax = 8,

    -- When resolving overrides we take the HIGHEST value that applies, then
    -- clamp it to absoluteMax. So a player who matches both a VIP license and a
    -- VIP+ Discord role receives the larger of the two.
    resolution = 'highest', -- 'highest' | 'sum'
}

-- ---------------------------------------------------------------------------
-- Per-player overrides
-- ---------------------------------------------------------------------------
Config.Overrides = {
    -- By full identifier. Any identifier the player carries can be used here:
    -- 'license:xxxxxxxx', 'license2:xxxx', 'discord:123', 'steam:110000...',
    -- 'fivem:1234567', etc. The key must match the identifier exactly.
    identifiers = {
        -- ['license:0a1b2c3d4e5f6a7b8c9d0e1f'] = 5,
        -- ['discord:123456789012345678']       = 6,
    },

    -- By ace permission. Grant with:  add_ace group.vip forger.slots.vip allow
    -- Easiest option if you already run an admin/permissions setup.
    aces = {
        -- ['forger.slots.vip']  = 4,
        -- ['forger.slots.vip2'] = 6,
        -- ['group.admin']       = Config.Slots.absoluteMax,
    },

    -- By Discord role id (requires Config.Discord.enabled = true and a bot in
    -- your guild). Role id -> slot count.
    discordRoles = {
        -- ['1234567890123456789'] = 5, -- VIP
        -- ['9876543210987654321'] = 7, -- VIP+
    },
}

-- ---------------------------------------------------------------------------
-- Discord role lookups
-- ---------------------------------------------------------------------------
-- The bot token is read from a server convar so it never lives in this file.
-- In server.cfg:  set forger_discord_token "YOUR_BOT_TOKEN"
-- The bot must be in the guild with the "Server Members Intent" enabled.
Config.Discord = {
    enabled = false,
    guildId = '',           -- your Discord server id
    tokenConvar = 'forger_discord_token',
    cacheSeconds = 300,     -- cache a player's roles this long to avoid rate limits
}

-- ---------------------------------------------------------------------------
-- Character creation
-- ---------------------------------------------------------------------------
Config.Creation = {
    minNameLength = 2,
    maxNameLength = 20,
    -- Nationalities offered in the create form dropdown.
    nationalities = {
        'United States', 'United Kingdom', 'Canada', 'Nigeria', 'Mexico',
        'Germany', 'France', 'Japan', 'Brazil', 'South Africa', 'Australia',
    },
    -- Starting cash/bank for a brand new character.
    startingMoney = { cash = 1500, bank = 5000 },
    -- Regex-ish character whitelist for names (applied server side too).
    allowNumbersInName = false,
}

Config.Deletion = {
    enabled = true,
    requireConfirm = true,
}

-- ---------------------------------------------------------------------------
-- Preview scene(s)
-- ---------------------------------------------------------------------------
-- Each location is a backdrop the player can cycle with the "Change Location"
-- key (J). ped = where the character preview stands, cam = the camera.
-- Only the ped spot + heading is needed now. The camera is computed in front
-- of the ped so it always frames the full body, regardless of location.
Config.Locations = {
    { label = 'Vespucci Beach', ped = vec4(-1211.5, -1470.6, 4.4, 300.0) },
    { label = 'Legion Square',  ped = vec4(195.1, -933.9, 30.69, 235.0) },
    { label = 'City Overlook',  ped = vec4(-1520.5, 840.5, 181.4, 120.0) },
}

-- Camera framing for the preview. Built from the ped's real position + facing,
-- so it's always in front of the character and never cut off.
--
-- `motion` makes the camera move on its own:
--   'static' - locked in place
--   'sway'   - gentle arc left/right in front of the ped (default, cinematic)
--   'orbit'  - slow continuous orbit all the way around
--   'push'   - slow dolly in and out
-- Any location in Config.Locations may override these with its own `cam = {}`.
Config.Camera = {
    motion = 'static',   -- default: no movement. Per-location `cam.motion` can override.

    -- Zoom presets cycled in the menu (Z). 1 = close (default), 2 = medium,
    -- 3 = far (full head-to-toe). Each sets how far the camera stands and where
    -- it aims; tune freely.
    defaultZoom = 1,
    zoom = {
        { label = 'Close',  distance = 3.1, height = 0.48, pointAt = 0.5,  fov = 44.0 },
        { label = 'Medium', distance = 4.3, height = 0.72, pointAt = 0.78, fov = 46.0 },
        { label = 'Far',    distance = 5.8, height = 0.86, pointAt = 0.88, fov = 50.0 },
    },

    swayArc = 14.0,    -- degrees to each side for 'sway'
    swaySpeed = 0.05,  -- cycles per second for 'sway' (slow)
    orbitSpeed = 3.0,  -- degrees per second for 'orbit' (slow)
    pushAmount = 0.5,  -- metres in/out for 'push'
    pushSpeed = 0.06,  -- cycles per second for 'push' (slow)
}

-- Idle poses cycled with the "Change Pose" key (E).
-- Idle animations cycled with E, split by gender. Index 1 is the default and
-- is a dance. The rest are the streamed pose packs (male pack for male peds,
-- QueenSisters ladies pack for female peds).
Config.Poses = {
    male = {
        { dict = 'anim@amb@nightclub@dancers@crowddance_facedj@hi_intensity', anim = 'hi_dance_crowd_13_v2_male^1' }, -- dance
        { dict = 'anim@amb@nightclub@mini@dance@dance_solo@male@var_a@', anim = 'high_center' },   -- dance
        { dict = 'anim@amb@nightclub@mini@dance@dance_solo@male@var_b@', anim = 'high_center' },   -- dance
        { dict = 'posepack1@diday', anim = 'posepack1_clip' },
        { dict = 'posepack2@diday', anim = 'posepack2_clip' },
        { dict = 'posepack3@diday', anim = 'posepack3_clip' },
        { dict = 'posepack4@diday', anim = 'posepack4_clip' },
        { dict = 'posepack5@diday', anim = 'posepack5_clip' },
        { dict = 'posepack6@diday', anim = 'posepack6_clip' },
    },
    female = {
        { dict = 'anim@amb@nightclub@dancers@crowddance_facedj@hi_intensity', anim = 'hi_dance_crowd_13_v2_male^1' }, -- dance
        { dict = 'anim@amb@nightclub@mini@dance@dance_solo@female@var_a@', anim = 'high_center' }, -- dance
        { dict = 'anim@amb@nightclub@mini@dance@dance_solo@female@var_b@', anim = 'high_center' }, -- dance
        { dict = 'cigarettestate@queensisters', anim = 'cigarette_clip' },
        { dict = 'littelqueen@queensisters', anim = 'littelqueen_clip' },
        { dict = 'littelqueen3@queensisters', anim = 'littelqueen3_clip' },
        { dict = 'littlequeen2queensisters', anim = 'littlequeen2_clip' },
        { dict = 'lovethislife@queensisters', anim = 'lovethislife_clip' },
    },
}

-- Show a random pose each time a character is displayed on load / when browsing
-- to a different character, instead of always starting on the first one. Changing
-- location or coming back from the spawn selector keeps the current pose.
Config.RandomPoseOnLoad = true

-- How fast a single idle pose (cycled with E) eases in, so the ped visibly
-- moves into the pose instead of snapping to it.
--   1.5 = soft lead-in (default)   8.0 = instant snap
Config.PoseBlendIn = 1.5

-- Loop idle poses with a pause between cycles instead of a continuous seamless
-- loop. The emote plays through, holds briefly, then replays.
Config.EmoteLoop = {
    spaced = true,
    gapSeconds = 1.4,     -- pause between the end of one cycle and the next
    minCycleMs = 2200,    -- minimum time per cycle (for very short/held clips)
}

-- ---------------------------------------------------------------------------
-- Appearance / clothing
-- ---------------------------------------------------------------------------
-- Loading a saved character's clothing/face is clothing-resource specific.
-- This section has two independent halves:
--   read  = how the SERVER reads a character's saved look out of the database
--            (so the selection preview shows their real clothing).
--   apply = how the CLIENT puts that look onto a ped (the preview ped) and onto
--            the real player on spawn.
--
-- Pick the preset that matches your clothing resource, or hand-tune the fields.
-- Ready-made presets are listed at the bottom of this block - copy one over the
-- values below. If you run 'none', the preview shows a clean freemode ped and
-- your framework/clothing resource dresses the real player on spawn as usual.
Config.Appearance = {
    resource = 'illenium-appearance', -- name of your clothing resource (for exports)

    -- Fallback freemode models when no saved look exists / can't be read.
    fallbackMale = 'mp_m_freemode_01',
    fallbackFemale = 'mp_f_freemode_01',

    -- READ: where the saved appearance lives.
    read = {
        -- 'table'  = a dedicated skins table keyed by the character id
        --            (illenium-appearance `playerskins`, fivem-appearance, etc.)
        -- 'inline' = a column on the character row itself
        --            (ESX `users.skin`, old qb-clothing `players.skin`)
        -- 'none'   = don't read; preview is always a default freemode ped
        source = 'table',
        table = 'playerskins',      -- (source='table') skins table name
        idColumn = 'citizenid',     -- (source='table') key column in that table
        column = 'skin',            -- JSON column holding the saved look
        activeColumn = 'active',    -- (source='table') only the row with active=1; false to ignore
    },

    -- APPLY: how the client dresses a ped / the player.
    apply = {
        -- 'export'     = call an export that accepts a ped (illenium-appearance,
        --                fivem-appearance). Previews the exact look on the ped.
        -- 'skinchanger'= ESX classic (esx_skin + skinchanger). Component-map data
        --                is applied to the preview ped natively (best effort) and
        --                to the player via skinchanger events.
        -- 'event'      = fire a player-only event to (re)load the player's outfit
        --                (qb-clothing). The preview shows a default ped.
        -- 'none'       = never apply; preview + player use default peds and your
        --                framework handles dressing on spawn.
        method = 'export',

        -- (method='export') exports[resource][pedExport](ped, data)
        pedExport = 'setPedAppearance',
        -- (method='export') exports[resource][playerExport](data) - also sets model
        playerExport = 'setPlayerAppearance',

        -- (method='event') event fired client-side to load the player's saved
        -- outfit after spawn (no ped preview).
        playerEvent = 'qb-clothing:client:loadPlayerClothing',

        -- Optional: event fired for a BRAND-NEW character so the clothing resource
        -- opens its creator (so the character gets a saved look). Leave nil if your
        -- framework/clothing resource opens the creator itself (ESX does this via
        -- esx_identity/esx_skin). Illenium (QB): 'illenium-appearance:client:createFirstCharacter'.
        newCharacterEvent = 'illenium-appearance:client:createFirstCharacter',
    },
}

-- Presets (copy the matching block over Config.Appearance above):
--
-- illenium-appearance (QB / Qbox):
--   resource='illenium-appearance',
--   read  = { source='table', table='playerskins', idColumn='citizenid', column='skin', activeColumn='active' }
--   apply = { method='export', pedExport='setPedAppearance', playerExport='setPlayerAppearance' }
--
-- illenium-appearance (ESX):  (skin stored inline on users.skin)
--   resource='illenium-appearance',
--   read  = { source='inline', column='skin' }
--   apply = { method='export', pedExport='setPedAppearance', playerExport='setPlayerAppearance' }
--
-- fivem-appearance (QB or ESX):
--   resource='fivem-appearance',
--   read  = { source='table', table='playerskins', idColumn='citizenid', column='skin', activeColumn='active' }  -- QB
--   -- or read = { source='inline', column='skin' }  -- ESX
--   apply = { method='export', pedExport='setPedAppearance', playerExport='setPlayerAppearance' }
--
-- esx_skin + skinchanger (ESX classic):
--   resource='skinchanger',
--   read  = { source='inline', column='skin' }
--   apply = { method='skinchanger' }
--
-- qb-clothing (QBCore classic):
--   resource='qb-clothing',
--   read  = { source='none' }         -- qb-clothing loads on player load itself
--   apply = { method='event', playerEvent='qb-clothing:client:loadPlayerClothing' }
--
-- none (let your framework dress the player; preview is a default ped):
--   read = { source='none' }, apply = { method='none' }

-- ---------------------------------------------------------------------------
-- Default UI settings (a player can change these; they are stored client side
-- via NUI messages only, nothing is written to disk here).
-- ---------------------------------------------------------------------------
Config.DefaultSettings = {
    theme = 'dark',        -- 'dark' | 'light' | 'auto'
    weather = 'SNOW',      -- one of the weather keys in Config.WeatherOptions
    hour = 20,
    minute = 0,
    menuStyle = 'cinematic', -- 'cinematic' | 'classic'
    cinematicBars = false,
    fpsMode = false,
    keybindHints = true,
    soundEffects = true,
    soundVolume = 50,
    backgroundMusic = true,
    musicVolume = 30,
}

-- Weather buttons shown in settings (key = GTA weather type, icon = lucide id).
Config.WeatherOptions = {
    { key = 'EXTRASUNNY', icon = 'sun',        label = 'Clear' },
    { key = 'CLEAR',      icon = 'sun-dim',    label = 'Sunny' },
    { key = 'CLOUDS',     icon = 'cloud',      label = 'Cloudy' },
    { key = 'OVERCAST',   icon = 'cloudy',     label = 'Overcast' },
    { key = 'SMOG',       icon = 'cloud-fog',  label = 'Smog' },
    { key = 'RAIN',       icon = 'cloud-rain', label = 'Rain' },
    { key = 'THUNDER',    icon = 'cloud-lightning', label = 'Thunder' },
    { key = 'FOGGY',      icon = 'cloud-fog',  label = 'Fog' },
    { key = 'SNOW',       icon = 'snowflake',  label = 'Snow' },
    { key = 'BLIZZARD',   icon = 'wind',       label = 'Blizzard' },
    { key = 'XMAS',       icon = 'thermometer', label = 'Frost' },
}

-- ---------------------------------------------------------------------------
-- Camera filters
-- ---------------------------------------------------------------------------
-- These are applied game-side so they actually affect the scene:
--   dof       = real depth-of-field background blur on the scripted camera
--   timecycle = a CUSTOM timecycle modifier (shipped in timecycle_mods.xml,
--               NOT a stock GTA one) for colour grading
--   strength  = 0..1 timecycle strength
-- The NUI also shows a matching subtle vignette/tint as a cue.
Config.Filters = {
    hd       = { timecycle = 'forger_hd',     strength = 1.0 },
    portrait = { dof = true },
    noir     = { timecycle = 'forger_noir',   strength = 1.0 },
    golden   = { timecycle = 'forger_golden', strength = 1.0 },
}

-- ---------------------------------------------------------------------------
-- Post-login spawn
-- ---------------------------------------------------------------------------
-- Because this resource replaces your framework's multichar, it also hands the
-- player off to spawn after they pick a character. Without this you'd be left
-- standing at the character-select spot.
Config.PostLogin = {
    teleportToLast = true,  -- move the player to their character's last saved position
    defaultSpawn = vec4(-1035.7, -2731.6, 12.8, 240.0), -- fallback / new-character spawn (LSIA)

    -- Guarantee the player lands on the correct freemode ped by gender
    -- (mp_m_freemode_01 / mp_f_freemode_01) BEFORE the clothing resource runs.
    -- Without this you keep whatever ped the game spawned you as (a story ped
    -- like Michael) whenever the saved look does not set a model itself, which
    -- is the "I don't spawn as my freemode ped" bug. The clothing resource then
    -- just layers the saved clothing/face on top of this clean base.
    forceFreemodeModel = true,

    -- Apply the character's saved look to the real player ped on spawn, using
    -- Config.Appearance.apply. Turn this OFF only if your framework/clothing
    -- resource already dresses the player automatically on load (e.g. some
    -- illenium/qb-clothing setups load the skin on the framework's player-loaded
    -- event, in which case a second apply here is redundant).
    applyAppearance = true,

    -- Some clothing resources dress the player themselves on the framework's
    -- player-loaded event, so this resource doesn't need to. Set to false to let
    -- this resource apply the look on spawn (via Config.Appearance.apply).
    -- Leave true if your clothing resource loads the skin on player-load itself
    -- (default illenium-appearance / qb-clothing behaviour).
    clothingLoadsItself = false,
}

-- ---------------------------------------------------------------------------
-- Spawn selector
-- ---------------------------------------------------------------------------
-- After a character is chosen, show a spawn-point picker before dropping the
-- player into the world. Set enabled = false to skip it and go straight to the
-- last saved position (original behaviour).
Config.Spawn = {
    enabled = true,

    -- Also show the picker for brand-new characters. New characters have no
    -- "last location", so only the fixed points below are offered. Turn this off
    -- if you want new characters to always drop at Config.PostLogin.defaultSpawn
    -- (e.g. an apartment / spawn handled by another resource).
    showForNewCharacters = true,

    -- Offer a "Last Location" tile when the character has a saved position.
    allowLastLocation = true,
    lastLocationLabel = 'Last Location',
    lastLocationDesc  = 'Return to where you logged off',

    -- Heading text on the picker.
    title = 'CHOOSE SPAWN',
    subtitle = 'Where do you want to start?',

    -- Fixed spawn points. `icon` is any id from the built-in icon set in
    -- web/js/spawn.js (map-pin, building, plane, mountain, trees, waves, home,
    -- briefcase, star, history). Unknown ids fall back to a pin.
    locations = {
        { id = 'legion',  label = 'Legion Square',  desc = 'Downtown Los Santos',   icon = 'building', coords = vec4(195.1, -933.9, 30.69, 235.0) },
        { id = 'lsia',    label = 'LS Airport',     desc = 'Los Santos Intl',       icon = 'plane',    coords = vec4(-1035.7, -2731.6, 12.8, 240.0) },
        { id = 'vespucci',label = 'Vespucci Beach', desc = 'Sun, sand and pier',    icon = 'waves',    coords = vec4(-1211.5, -1470.6, 4.4, 300.0) },
        { id = 'sandy',   label = 'Sandy Shores',   desc = 'Blaine County desert',  icon = 'mountain', coords = vec4(1853.0, 3689.0, 34.2, 210.0) },
        { id = 'paleto',  label = 'Paleto Bay',     desc = 'The far north',         icon = 'trees',    coords = vec4(-108.0, 6467.0, 31.6, 135.0) },
    },

    -- Ultimate fallback if a chosen point somehow has no coords.
    default = vec4(-1035.7, -2731.6, 12.8, 240.0),
}

-- Branding shown top-left. Replace img with your own logo in web/img/.
Config.Brand = {
    name = 'FORGER',
    tag = 'MULTICHARACTER',
    logo = 'img/logo.svg',
}


