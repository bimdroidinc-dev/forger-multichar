Config = {}

-- ---------------------------------------------------------------------------
-- Framework
-- ---------------------------------------------------------------------------
-- 'auto' will try to detect qbx_core, then qb-core. Force one if detection is
-- ever wrong on your server.
Config.Framework = 'auto' -- 'auto' | 'qbx' | 'qb'

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

-- Name of the players table and its columns (QB / Qbox default schema).
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

-- Scenes used INSTEAD of Config.Locations when the character being viewed has a
-- couple (a saved partner). Cycled with the same location key. Per-scene `cam`:
--   view   = 'back' (camera behind the couple) or 'front' (default, see faces)
--   motion = 'pan' for a slow cinematic pan, or 'static' / 'sway' / 'orbit'
-- A scene with type = 'walk' makes the couple stroll from `from` to `to`, then
-- loop back to the start.
Config.CoupleLocations = {
    -- 1. Overlook: back view of the couple looking out over the city, slow pan.
    {
        label = 'Overlook',
        ped = vec4(920.1934, -10.6644, 111.2755, 138.2280),
        cam = { view = 'back', motion = 'pan', panArc = 16.0, panSpeed = 0.018 },
    },
    -- 2. Beach: normal front view.
    {
        label = 'Beach',
        ped = vec4(-1494.8589, -1305.7769, 4.2923, 110.3542),
        cam = { view = 'front', motion = 'static' },
    },
    -- 3. Stroll: the couple walks from `from` to `to`, then loops to the start.
    {
        label = 'Stroll',
        type = 'walk',
        from = vec4(916.9807, 23.6701, 113.5521, 326.2358),
        to   = vec4(947.3136, 71.4556, 113.5484, 143.9492),
        walkSpeed = 1.0,          -- 1.0 = normal walk, ~2.0 = jog
        cam = { view = 'front', motion = 'static' },
    },
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

    -- Widened relative to the CURRENT zoom while paired, so Close/Medium/Far
    -- still work with a partner (added on top of the selected zoom preset).
    pairMotion = 'static',
    pairDistanceAdd = 1.3,
    pairHeightAdd = 0.2,
    pairPointAtAdd = 0.18,
    pairFovAdd = 5.0,
    pairSwayArc = 8.0,
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

-- How fast a single idle pose (cycled with E) eases in. Matches the couple
-- lead-in (Config.Partner.emoteBlendIn) so the ped visibly moves into the pose
-- instead of snapping to it.
--   1.5 = soft lead-in (default)   8.0 = instant snap
Config.PoseBlendIn = 1.5

-- Loop idle poses and couple emotes with a pause between cycles instead of a
-- continuous seamless loop. The emote plays through, holds briefly, then replays.
Config.EmoteLoop = {
    spaced = true,
    gapSeconds = 1.4,     -- pause between the end of one cycle and the next
    minCycleMs = 2200,    -- minimum time per cycle (for very short/held clips)
}

-- ---------------------------------------------------------------------------
-- Appearance
-- ---------------------------------------------------------------------------
-- Loading a saved character's clothing/face is appearance-resource specific.
-- Set the resource you use and this script will try its common export. If your
-- resource is not listed, extend Config.Appearance.apply in client/main.lua.
Config.Appearance = {
    resource = 'illenium-appearance', -- 'illenium-appearance' | 'qbx_clothing' | 'fivem-appearance' | 'none'
    -- Fallback freemode models when no saved appearance exists.
    fallbackMale = 'mp_m_freemode_01',
    fallbackFemale = 'mp_f_freemode_01',

    -- illenium-appearance (QB) stores each character's saved look in the
    -- `playerskins` table, `skin` column (JSON), keyed by `citizenid`, with an
    -- `active = 1` flag marking the current one. (Older qb-clothing setups used
    -- `players`.`skin` - switch back to that if yours does.)
    skinTable = 'playerskins',
    skinIdColumn = 'citizenid',
    skinColumn = 'skin',            -- JSON column holding the saved appearance
    skinActiveColumn = 'active',    -- only read the active skin (set false to ignore)
    -- illenium export used to apply the clothing/face after we set the model
    -- ourselves. 'setPedAppearance' applies components/props/face/hair/tattoos
    -- (no model). 'setPlayerAppearance' would also re-set the model.
    applyExport = 'setPedAppearance',
}

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
-- Partner system
-- ---------------------------------------------------------------------------
-- Two players who both have the character screen open can pair up and perform
-- synced paired emotes. "couple" uses the romantic packs you streamed;
-- "friend" uses built-in friendly paired anims (no extra files needed).
Config.Partner = {
    enabled = true,
    searchMinChars = 1,     -- min characters before a name search runs
    requestTimeout = 120,   -- seconds an invite stays in the Incoming tab (prompt shows for 10s)
    sceneZOffset = 0.98,    -- raises the paired-emote origin so peds don't sink

    -- Blend-in speed for paired emotes. This controls the lead-in you see before
    -- the couple settles into the final pose:
    --   1.5 = a soft, visible "move into the emote" transition (default)
    --   8.0 = snap straight into the pose with no lead-in
    emoteBlendIn = 1.5,

    -- Streamed anim dictionaries this resource ships (in stream/). Listed so the
    -- client can preload/verify them. Do not rename unless you rename the .ycd.
    streamedDicts = {
        'mx@couple1_a', 'mx@couple1_b', 'mx@couple2_a', 'mx@couple2_b',
        'mx@couple3_a', 'mx@couple3_b', 'mx@couplephone_m', 'mx@couplephone_f',
        'mx@piggypack_a', 'mx@piggypack_b', 'mx@pack4.1_a', 'mx@pack4.1_b',
        'mx@couple4.2_a', 'mx@couple4.2_b', 'mx@couple4.3_a', 'mx@couple4.3_b',
        'mx@couple4.4_a', 'mx@couple4.4_b', 'mx@couple4.5_a', 'mx@couple4.5_b',
    },

    -- Each emote is a paired clip: the inviter plays 'a', the target plays 'b'.
    -- Optional per-emote flags:
    --   upperBody  = play the emote on the upper body only (legs stay free)
    --   walk       = with upperBody, the legs do a walk cycle so it reads as
    --                "walking together" (the peds stand side by side)
    --   sideOffset = spacing between the two peds for the upper-body path
    emotes = {
        couple = {
            { label = 'Embrace',      a = { dict = 'mx@couple1_a', clip = 'mx@couple1_a_clip' }, b = { dict = 'mx@couple1_b', clip = 'mx@couple1_b_clip' } },
            { label = 'Hold Close',   a = { dict = 'mx@couple2_a', clip = 'mx@couple2_clip' },   b = { dict = 'mx@couple2_b', clip = 'mx@couple2b_clip' } },
            { label = 'Slow Dance',   a = { dict = 'mx@couple3_a', clip = 'mx@couple3_a_clip' }, b = { dict = 'mx@couple3_b', clip = 'mx@couple3_b_clip' } },
            { label = 'Phone Cuddle', a = { dict = 'mx@couplephone_m', clip = 'mx@couplephone_m_clip' }, b = { dict = 'mx@couplephone_f', clip = 'mx@couplephone_f_clip' } },
            { label = 'Piggyback',    a = { dict = 'mx@piggypack_a', clip = 'mxclip_a' },         b = { dict = 'mx@piggypack_b', clip = 'mxanim_b' } },
            { label = 'Pack 4.1',     a = { dict = 'mx@pack4.1_a', clip = 'mx@pack4.1_a_clip' },  b = { dict = 'mx@pack4.1_b', clip = 'mx@pack4.1_b_clip' } },
            { label = 'Pack 4.2',     a = { dict = 'mx@couple4.2_a', clip = 'mx@couple4.2_a_clip' }, b = { dict = 'mx@couple4.2_b', clip = 'mx@couple4.2_b_clip' } },
            { label = 'Pack 4.3',     a = { dict = 'mx@couple4.3_a', clip = 'mx@couple4.3_a_clip' }, b = { dict = 'mx@couple4.3_b', clip = 'mx@couple4.3_b_clip' } },
            { label = 'Pack 4.4',     a = { dict = 'mx@couple4.4_a', clip = 'mx@couple4.4_a_clip' }, b = { dict = 'mx@couple4.4_b', clip = 'mx@couple4.4_b_clip' } },
            { label = 'Pack 4.5',     a = { dict = 'mx@couple4.5_a', clip = 'mx@couple4.5_a_clip' }, b = { dict = 'mx@couple4.5_b', clip = 'mx@couple4.5_b_clip' } },
            -- Upper-body demo: legs walk in step, arms free (swap the a/b clips
            -- for a real hold-hands upper-body anim if you have one).
            { label = 'Walk Together', upperBody = true, walk = true, sideOffset = 0.5,
              a = { dict = 'amb@world_human_hang_out_street@male_c@base', clip = 'base' },
              b = { dict = 'amb@world_human_hang_out_street@male_c@base', clip = 'base' } },
        },
        friend = {
            { label = 'Bro Hug',   a = { dict = 'mp_ped_interaction', clip = 'hugs_guy_a' },      b = { dict = 'mp_ped_interaction', clip = 'hugs_guy_b' } },
            { label = 'Handshake', a = { dict = 'mp_ped_interaction', clip = 'handshake_guy_a' }, b = { dict = 'mp_ped_interaction', clip = 'handshake_guy_b' } },
        },
    },
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

    -- FIX: guarantee the player lands on the correct freemode ped by gender
    -- (mp_m_freemode_01 / mp_f_freemode_01) BEFORE the appearance resource runs.
    -- Without this you keep whatever ped the game spawned you as (a story ped
    -- like Michael) whenever the saved skin does not set a model itself, which
    -- is exactly the "I don't spawn as my freemode ped" bug. illenium then just
    -- layers the saved clothing/face on top of this clean base.
    forceFreemodeModel = true,

    setModel = false,
    -- Apply the character's saved look (model + clothing) to the player ped on
    -- spawn, using the appearance the server read from the skin table and
    -- Config.Appearance.applyExport (illenium's setPlayerAppearance). This is the
    -- reliable way to guarantee the correct ped: this resource shows the character
    -- on a SEPARATE preview ped during selection, so nothing sets the real player
    -- ped unless we do it here. Leave ON for illenium/qbx.
    applyAppearance = true,

    -- EXISTING characters: illenium loads the saved model + clothing itself on
    -- 'QBCore:Client:OnPlayerLoaded' when the player logs in, so this resource no
    -- longer triggers a reload (doing so raced illenium's cache and crashed it).
    -- Kept here only for reference / non-illenium setups.
    loadClothingEvent = 'illenium-appearance:client:reloadSkin',
    -- NEW character: open illenium's appearance creator so the character actually
    -- gets a saved look (without this, new chars spawn as a default ped forever).
    newCharacterEvent = 'illenium-appearance:client:createFirstCharacter',

    -- If you switch away from illenium and want this resource to spawn the ped
    -- itself, set setModel/applyAppearance = true, clear the two events above, and
    -- make sure Config.Appearance (skinTable/applyExport) matches your resource.
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

-- ---------------------------------------------------------------------------
-- Scene Maker
-- ---------------------------------------------------------------------------
-- An in-game tool (/scene) that lets a player pose their character, frame the
-- camera, and set the time/weather, then SAVE it as that character's personal
-- backdrop in the selector. Saved per character (forger_scenes table).
Config.SceneMaker = {
    enabled = true,
    command = 'scene',          -- /scene to open the builder (in-game)

    restricted = false,         -- true = require the ace below
    ace = 'forger.scene',

    -- Orbit camera rig for framing the shot. angle = azimuth around the ped,
    -- height = metres above feet, distance = zoom out, fov, speed = auto-orbit.
    camera = {
        defaults = { angle = 200.0, height = 0.55, distance = 3.4, fov = 45.0, speed = 0.0 },
        limits   = { height = { -0.5, 2.5 }, distance = { 1.5, 9.0 }, fov = { 25.0, 65.0 } },
        steps    = { orbit = 3.0, height = 0.08, distance = 0.25, fov = 2.0 },
    },

    -- Weathers offered in the picker.
    weathers = {
        'CLEAR', 'EXTRASUNNY', 'CLOUDS', 'OVERCAST', 'NEUTRAL',
        'RAIN', 'THUNDER', 'CLEARING', 'FOGGY', 'SMOG', 'XMAS', 'SNOW', 'BLIZZARD',
    },

    -- Stances the ped can hold. Either a `scenario` (GTA world scenario) or a
    -- `dict` + `anim` (+ optional `flag`). Grouped by `category` in the UI.
    stances = {
        { id = 'stand',     name = 'Stand',        category = 'Idle', scenario = 'WORLD_HUMAN_STAND_IMPATIENT' },
        { id = 'stand_up',  name = 'Stand tall',   category = 'Idle', scenario = 'WORLD_HUMAN_STAND_IMPATIENT_UPRIGHT' },
        { id = 'guard',     name = 'Guard',        category = 'Idle', scenario = 'WORLD_HUMAN_GUARD_STAND' },
        { id = 'lean',      name = 'Lean',         category = 'Idle', scenario = 'WORLD_HUMAN_LEANING' },
        { id = 'smoke',     name = 'Smoke',        category = 'Idle', scenario = 'WORLD_HUMAN_SMOKING' },
        { id = 'phone',     name = 'On phone',     category = 'Idle', scenario = 'WORLD_HUMAN_STAND_MOBILE' },
        { id = 'coffee',    name = 'Coffee',       category = 'Idle', scenario = 'WORLD_HUMAN_AA_COFFEE' },
        { id = 'map',       name = 'Read map',     category = 'Idle', scenario = 'WORLD_HUMAN_TOURIST_MAP' },
        { id = 'statue',    name = 'Statue',       category = 'Idle', scenario = 'WORLD_HUMAN_HUMAN_STATUE' },

        { id = 'sit_ledge', name = 'Sit on ledge', category = 'Sit',  scenario = 'WORLD_HUMAN_SEAT_LEDGE' },
        { id = 'sit_steps', name = 'Sit on steps', category = 'Sit',  scenario = 'WORLD_HUMAN_SEAT_STEPS' },
        { id = 'sit_wall',  name = 'Sit on wall',  category = 'Sit',  scenario = 'WORLD_HUMAN_SEAT_WALL' },

        { id = 'muscle',    name = 'Muscle flex',  category = 'Cool', scenario = 'WORLD_HUMAN_MUSCLE_FLEX' },
        { id = 'superhero', name = 'Superhero',    category = 'Cool', scenario = 'WORLD_HUMAN_SUPERHERO' },
        { id = 'slouch',    name = 'Slouch',       category = 'Cool', scenario = 'WORLD_HUMAN_BUM_STANDING' },

        { id = 'binoculars',name = 'Binoculars',   category = 'Fun',  scenario = 'WORLD_HUMAN_BINOCULARS' },
        { id = 'cheer',     name = 'Cheer',        category = 'Fun',  scenario = 'WORLD_HUMAN_CHEERING' },
        { id = 'yoga',      name = 'Yoga',         category = 'Fun',  scenario = 'WORLD_HUMAN_YOGA' },
        { id = 'sunbathe',  name = 'Sunbathe',     category = 'Fun',  scenario = 'WORLD_HUMAN_SUNBATHE_BACK' },
        { id = 'salute',    name = 'Salute',       category = 'Fun',  dict = 'mp_player_int_uppersalute', anim = 'mp_player_int_salute', flag = 49 },
        { id = 'wave',      name = 'Wave',         category = 'Fun',  dict = 'friends@frj@ig_1', anim = 'wave_a', flag = 49 },
        { id = 'thumbsup',  name = 'Thumbs up',    category = 'Fun',  dict = 'anim@mp_player_intcelebrationmale@thumbs_up', anim = 'thumbs_up', flag = 49 },
    },

    -- Movement speed multiplier when repositioning the ped in the builder.
    moveSpeed = 1.0,

    -- How far the SAVED scene is pulled back when viewed in the selector, relative
    -- to how it was framed in the builder. The selector adds depth-of-field that
    -- makes the subject read closer, so >1.0 gives a bit more breathing room.
    viewZoomOut = 1.25,
}

-- Co-op scene building: invite nearby players into a shared, isolated session to
-- build a scene together. Organizer controls time/weather/camera and saves;
-- invitees pick their stance and place their own vehicles.
Config.SceneMaker.coop = {
    enabled = true,
    maxInvitees = 4,        -- organizer + up to 4 others
    inviteRadius = 14.0,    -- metres: how close a player must be to be invited
    inviteTimeout = 30,     -- seconds before an invite expires
    bucketBase = 720000,    -- routing-bucket range for isolated build sessions
}
