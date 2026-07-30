Config = {}

-- Framework -------------------------------------------------------------------

Config.Framework = 'auto' -- 'auto' | 'qbx' | 'qb'
Config.AutoOpen = true    -- open the selector when a client's session starts

Config.Logout = {
    enabled = true,
    command = 'logout',
    restricted = false,   -- true = require the ace below
    ace = 'forger.logout',
    cooldown = 2,         -- seconds between uses, per player
}

Config.DB = {
    table = 'players',
    columnLicense = 'license',
    columnCitizenId = 'citizenid',
    columnCharInfo = 'charinfo',
    columnMoney = 'money',
    columnJob = 'job',
    columnPosition = 'position',
}

-- Character slots -------------------------------------------------------------

Config.Slots = {
    default = 2,
    absoluteMax = 8,        -- no override can exceed this
    resolution = 'highest', -- 'highest' | 'sum'
}

Config.Overrides = {
    -- any identifier the player carries: license:, license2:, discord:, steam:, fivem:
    identifiers = {
        -- ['license:0a1b2c3d4e5f6a7b8c9d0e1f'] = 5,
    },
    -- grant with: add_ace group.vip forger.slots.vip allow
    aces = {
        -- ['forger.slots.vip'] = 4,
    },
    -- requires Config.Discord.enabled
    discordRoles = {
        -- ['1234567890123456789'] = 5,
    },
}

-- server.cfg: set forger_discord_token "YOUR_BOT_TOKEN"
-- The bot must be in the guild with the Server Members Intent enabled.
Config.Discord = {
    enabled = false,
    guildId = '',
    tokenConvar = 'forger_discord_token',
    cacheSeconds = 300,
}

-- Character creation ----------------------------------------------------------

Config.Creation = {
    minNameLength = 2,
    maxNameLength = 20,
    allowNumbersInName = false,
    startingMoney = { cash = 1500, bank = 5000 },
    nationalities = {
        'United States', 'United Kingdom', 'Canada', 'Nigeria', 'Mexico',
        'Germany', 'France', 'Japan', 'Brazil', 'South Africa', 'Australia',
    },
}

Config.Deletion = { enabled = true }

-- Starter items ---------------------------------------------------------------

-- Given once, to brand new characters only, right after creation. Works with
-- ox_inventory, qb-inventory or the core's own AddItem, detected in that order.
--
--   item     the item name as it appears in your items list
--   amount   how many
--   metadata optional table merged into the item's metadata
--   slot     optional inventory slot to force
--
-- 'id_card' and 'driver_license' are special-cased: if you run an ID card
-- resource (um-idcard, bl_idcard, qbx_idcard) it builds the licence for you,
-- otherwise the character's name/DOB/gender are written into the metadata here.
Config.StarterItems = {
    enabled = true,

    items = {
        { item = 'phone',          amount = 1 },
        { item = 'id_card',        amount = 1 },
        { item = 'driver_license', amount = 1 },
        { item = 'water_bottle',   amount = 2 },
        { item = 'sandwich',       amount = 2 },
        -- { item = 'radio',       amount = 1 },
        -- { item = 'lockpick',    amount = 1, metadata = { quality = 100 } },
    },

    -- Set false if your ID card resource hands out licences on its own.
    giveIdCards = true,
}

-- Preview scene ---------------------------------------------------------------

-- Backdrops cycled with J.
--
--   mode 1  over-the-shoulder portrait (default)
--   mode 2  prop scenario - needs `scenario` naming a Config.PropScenarios entry
--   mode 3  locked-off camera - needs `camCoords`, optionally fov/focusOffset/blurOptions
--
--   emote   { scenario = ... } or { dict = ..., anim = ... } or { animName = ... }
--           omit it and a random Config.Emotes.list entry is used
--   group   a job/gang name or list of them. A character whose job or gang
--           matches sees ONLY that group's locations; everyone else sees the
--           ungrouped ones.
Config.Locations = {
    { label = 'Vespucci Beach', ped = vec4(-1211.5, -1470.6, 4.4, 300.0) },
    { label = 'Legion Square',  ped = vec4(195.1, -933.9, 30.69, 235.0) },
    { label = 'City Overlook',  ped = vec4(-1520.5, 840.5, 181.4, 120.0) },

    {
        label = 'Pier Railing',
        ped = vec4(-1850.1, -1246.0, 8.6, 315.0),
        emote = { scenario = 'WORLD_HUMAN_LEANING' },
    },
    {
        label = 'Rooftop Drink',
        ped = vec4(-980.1, 662.18, 165.66, 185.35),
        mode = 2,
        scenario = 'bar',
    },
    {
        label = 'Alley Portrait',
        ped = vec4(-2541.15, 2334.54, 33.06, 334.88),
        camCoords = vec4(-2538.56, 2337.39, 33.56, 150.19),
        mode = 3,
        fov = 22.0,
        focusOffset = vec3(0.0, 0.0, 0.55),
        blurOptions = { near = 0.5, far = 5.0 },
        emote = { scenario = 'WORLD_HUMAN_SMOKING' },
    },

    -- job / gang locked examples
    -- {
    --     label = 'Mission Row',
    --     ped = vec4(444.37, -984.33, 30.69, 71.35),
    --     group = { 'police', 'sheriff' },
    --     emote = { scenario = 'WORLD_HUMAN_COP_IDLES' },
    -- },
}

Config.RandomLocationOnLoad = true -- start on a random location instead of the first

-- One synchronised scene drives the ped AND its props, which is what keeps a
-- bottle or glass glued to the hand. Prop models are hashes because these are the
-- exact props the drink_3 clip was authored against.
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

-- Scenes used INSTEAD of Config.Locations when the viewed character has a partner.
--   cam.view   'back' (camera behind the couple) or 'front'
--   cam.motion 'static' | 'sway' | 'pan' | 'orbit' | 'push'
--   type       'walk' makes the couple stroll from `from` to `to` and loop
Config.CoupleLocations = {
    {
        label = 'Overlook',
        ped = vec4(920.1934, -10.6644, 111.2755, 138.2280),
        cam = { view = 'back', motion = 'pan', panArc = 16.0, panSpeed = 0.018 },
    },
    {
        label = 'Beach',
        ped = vec4(-1494.8589, -1305.7769, 4.2923, 110.3542),
        cam = { view = 'front', motion = 'static' },
    },
    {
        label = 'Stroll',
        type = 'walk',
        from = vec4(916.9807, 23.6701, 113.5521, 326.2358),
        to   = vec4(947.3136, 71.4556, 113.5484, 143.9492),
        walkSpeed = 1.0,
        cam = { view = 'front', motion = 'static' },
    },
}

-- Camera ----------------------------------------------------------------------

-- Two framing systems. SOLO shots use `offset` / `focus` / `soloFov`: the camera
-- sits at a fixed offset in the PED'S OWN space, so the portrait reads the same
-- at every location. PAIR and saved Scene Maker shots use the polar
-- `distance` / `height` / `pointAt` / `fov` values, because they frame two or
-- more subjects.
Config.Camera = {
    motion = 'static',  -- 'static' | 'sway' | 'orbit' | 'pan' | 'push'
    posture = 'side',   -- 'side' = ped keeps its heading, 'front' = ped turns to camera
    defaultZoom = 1,

    -- offset/focus: x = side, y = forward, z = up. Cycled with Z.
    zoom = {
        { label = 'Close',
          offset = vec3(-1.2, 1.3, 0.55), focus = vec3(0.28, 0.0, 0.58), soloFov = 12.0,
          distance = 3.1, height = 0.48, pointAt = 0.5,  fov = 44.0 },
        { label = 'Medium',
          offset = vec3(-1.5, 1.5, 0.60), focus = vec3(0.30, 0.0, 0.60), soloFov = 16.0,
          distance = 4.3, height = 0.72, pointAt = 0.78, fov = 46.0 },
        { label = 'Far',
          offset = vec3(-2.0, 2.2, 0.72), focus = vec3(0.30, 0.0, 0.66), soloFov = 22.0,
          distance = 5.8, height = 0.86, pointAt = 0.88, fov = 50.0 },
    },

    -- applied on top of the solo offsets while a mode 2 scenario is on screen
    scenarioOffsetAdd = vec3(-0.3, 0.6, 0.15),
    scenarioFovAdd = 6.0,

    swayArc = 14.0,
    swaySpeed = 0.05,
    orbitSpeed = 3.0,
    pushAmount = 0.5,
    pushSpeed = 0.06,

    -- added to the selected zoom preset while a partner is in shot
    pairMotion = 'static',
    pairDistanceAdd = 1.3,
    pairHeightAdd = 0.2,
    pairPointAtAdd = 0.18,
    pairFovAdd = 5.0,
    pairSwayArc = 8.0,

    -- shallow depth of field on the character shot; a mode 3 location's
    -- blurOptions overrides near/far
    dof = {
        enabled = true,
        near = 0.5,
        far = 2.0,
        pairFar = 3.0,
        strength = 1.0,
        maxNearInFocus = 1.5,
        focusBias = 2.0,
    },

    -- slow push-in on the first open only; switches and location changes are instant
    intro = {
        enabled = true,
        duration = 5000,
        jitter = 0.3,
        fovOffset = 3.0,
    },
}

-- Emotes ----------------------------------------------------------------------

-- Cycled with E, and used as the random pick for any location without its own
-- emote. Everything here ships with the base game: this resource has no stream/.
--
-- Emote menus animate the LOCAL PLAYER ped only and this resource previews on a
-- separate ped, so an { animName = 'x' } emote is looked up in `aliases` first.
-- An unresolved name falls back to a random `list` entry and logs a warning once.
-- Prefer `scenario` or `dict`+`anim`, which work on any ped.
Config.Emotes = {
    resource = 'auto', -- 'auto' | 'rpemotes-reborn' | 'rpemotes' | 'scully_emotemenu' | 'native'
    randomOnLoad = true,

    list = {
        { scenario = 'WORLD_HUMAN_SMOKING' },
        { scenario = 'WORLD_HUMAN_STAND_MOBILE' },
        { scenario = 'WORLD_HUMAN_LEANING' },
        { scenario = 'WORLD_HUMAN_AA_COFFEE' },
        { scenario = 'WORLD_HUMAN_GUARD_STAND' },
        { scenario = 'WORLD_HUMAN_STAND_IMPATIENT' },
        { scenario = 'WORLD_HUMAN_MUSCLE_FLEX' },
        { scenario = 'WORLD_HUMAN_TOURIST_MAP' },
        { dict = 'anim@amb@nightclub@mini@dance@dance_solo@male@var_a@', anim = 'high_center' },
        { dict = 'anim@amb@nightclub@mini@dance@dance_solo@female@var_a@', anim = 'high_center' },
        { dict = 'anim@heists@humane_labs@finale@keycards', anim = 'ped_a_enter_loop', flag = 1 },
        { dict = 'rcmnigel1bnmt_1b', anim = 'hola_amigo', flag = 1 },
    },

    aliases = {
        texting = { dict = 'cellphone@', anim = 'cellphone_text_read_base', flag = 49 },
        smoke   = { scenario = 'WORLD_HUMAN_SMOKING' },
        lean    = { scenario = 'WORLD_HUMAN_LEANING' },
        coffee  = { scenario = 'WORLD_HUMAN_AA_COFFEE' },
        idle3   = { scenario = 'WORLD_HUMAN_STAND_IMPATIENT' },
    },
}

Config.EmoteBlendIn = 1.5 -- 1.5 = soft lead-in, 8.0 = instant snap

-- Only applies to dict+anim emotes; scenarios are a continuous hold.
Config.EmoteLoop = {
    spaced = true,
    gapSeconds = 1.4,
    minCycleMs = 2200,
}

-- Scene placement -------------------------------------------------------------

Config.Scene = {
    collisionTimeoutMs = 5000,
    placeTolerance = 1.0, -- re-assert coords until the ped is this close
    placeTimeoutMs = 3000,

    -- true  = raycast down and stand the ped on the surface found (safest)
    -- false = trust the Z in Config.Locations exactly
    groundSnap = true,
}

-- Appearance ------------------------------------------------------------------

Config.Appearance = {
    resource = 'illenium-appearance', -- 'illenium-appearance' | 'qbx_clothing' | 'fivem-appearance' | 'none'
    fallbackMale = 'mp_m_freemode_01',
    fallbackFemale = 'mp_f_freemode_01',

    -- where the saved look lives. illenium (QB) uses playerskins.skin keyed by
    -- citizenid with active = 1; older qb-clothing used players.skin.
    skinTable = 'playerskins',
    skinIdColumn = 'citizenid',
    skinColumn = 'skin',
    skinActiveColumn = 'active',

    -- 'setPedAppearance' applies components/props/face/hair/tattoos without
    -- touching the model; 'setPlayerAppearance' would also re-set the model.
    applyExport = 'setPedAppearance',
}

-- UI --------------------------------------------------------------------------

Config.Brand = {
    name = 'FORGER',
    tag = 'MULTICHARACTER',
    logo = 'img/logo.svg',
}

Config.DefaultSettings = {
    theme = 'dark',          -- 'dark' | 'light' | 'auto'
    weather = 'SNOW',
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

Config.WeatherOptions = {
    { key = 'EXTRASUNNY', icon = 'sun',              label = 'Clear' },
    { key = 'CLEAR',      icon = 'sun-dim',          label = 'Sunny' },
    { key = 'CLOUDS',     icon = 'cloud',            label = 'Cloudy' },
    { key = 'OVERCAST',   icon = 'cloudy',           label = 'Overcast' },
    { key = 'SMOG',       icon = 'cloud-fog',        label = 'Smog' },
    { key = 'RAIN',       icon = 'cloud-rain',       label = 'Rain' },
    { key = 'THUNDER',    icon = 'cloud-lightning',  label = 'Thunder' },
    { key = 'FOGGY',      icon = 'cloud-fog',        label = 'Fog' },
    { key = 'SNOW',       icon = 'snowflake',        label = 'Snow' },
    { key = 'BLIZZARD',   icon = 'wind',             label = 'Blizzard' },
    { key = 'XMAS',       icon = 'thermometer',      label = 'Frost' },
}

-- dof = real depth-of-field blur; timecycle = a custom modifier from
-- timecycle_mods.xml (not a stock GTA one)
Config.Filters = {
    hd       = { timecycle = 'forger_hd',     strength = 1.0 },
    portrait = { dof = true },
    noir     = { timecycle = 'forger_noir',   strength = 1.0 },
    golden   = { timecycle = 'forger_golden', strength = 1.0 },
}

-- Partner system --------------------------------------------------------------

Config.Partner = {
    enabled = true,
    searchMinChars = 1,
    requestTimeout = 120, -- seconds an invite stays in the Incoming tab
    sceneZOffset = 0.98,  -- global lift for the paired-scene origin
    emoteBlendIn = 1.5,

    -- All dictionaries below ship with the base game. Three entry forms:
    --   { dict, m, f }         the viewed ped takes its own gender's clip,
    --                          the partner takes the other
    --   { dict, left, right }  left = viewed ped, right = partner
    --   { a = {dict, clip}, b = {dict, clip} }  inviter plays a, target plays b
    --
    -- Per-emote fixes: zOffset (added to sceneZOffset), headingOffset (degrees),
    -- upperBody, walk, sideOffset. Clips authored at ground level need
    -- zOffset = -0.98; the side-on ones also need headingOffset = 90.0.
    emotes = {
        couple = {
            { label = 'Quiet Moment', dict = 'timetable@trevor@ig_1',
              m = 'ig_1_thedontknowwhy_trevor',         f = 'ig_1_thedontknowwhy_patricia' },
            { label = 'Talking',      dict = 'timetable@trevor@ig_1',
              m = 'ig_1_therearejustsomemoments_trevor', f = 'ig_1_therearejustsomemoments_patricia' },
            { label = 'Looking Out',  dict = 'timetable@trevor@ig_1',
              m = 'ig_1_thedesertissobeautiful_trevor',  f = 'ig_1_thedesertissobeautiful_patricia' },
            { label = 'Hug',
              a = { dict = 'mp_ped_interaction', clip = 'kisses_guy' },
              b = { dict = 'mp_ped_interaction', clip = 'kisses_girl' },
              zOffset = 0.0 },
            { label = 'Walk Together', upperBody = true, walk = true, sideOffset = 0.5,
              a = { dict = 'amb@world_human_hang_out_street@male_c@base', clip = 'base' },
              b = { dict = 'amb@world_human_hang_out_street@male_c@base', clip = 'base' } },
        },
        friend = {
            { label = 'Sarcastic',  dict = 'anim@mp_player_intcelebrationpaired@f_f_sarcastic',
              left = 'sarcastic_left', right = 'sarcastic_right',
              zOffset = -0.98, headingOffset = 90.0 },
            { label = 'Fist Bump',  dict = 'anim@mp_player_intcelebrationpaired@f_f_fist_bump',
              left = 'fist_bump_left', right = 'fist_bump_right',
              zOffset = -0.98, headingOffset = 90.0 },
            { label = 'Handshake',  dict = 'anim@mp_player_intcelebrationpaired@m_m_manly_handshake',
              left = 'manly_handshake_left', right = 'manly_handshake_right',
              zOffset = -0.98, headingOffset = 90.0 },
            { label = 'Bro Hug',    dict = 'anim@mp_player_intcelebrationpaired@m_m_bro_hug',
              left = 'bro_hug_left', right = 'bro_hug_right',
              zOffset = -0.98, headingOffset = 90.0 },
            { label = 'Friend Hug', dict = 'anim@mp_player_intcelebrationpaired@f_m_bro_hug',
              left = 'bro_hug_left', right = 'bro_hug_right',
              zOffset = -0.98, headingOffset = 90.0 },
        },
    },
}

-- Post-login spawn ------------------------------------------------------------

Config.PostLogin = {
    teleportToLast = true,
    defaultSpawn = vec4(-1035.7, -2731.6, 12.8, 240.0),

    -- force the correct freemode ped by gender before the appearance resource
    -- runs, so a saved skin that sets no model can't leave the player on a story ped
    forceFreemodeModel = true,

    setModel = false,
    applyAppearance = true,

    -- true if your clothing resource loads the saved skin itself on
    -- QBCore:Client:OnPlayerLoaded (illenium does)
    clothingLoadsItself = true,
    loadClothingEvent = 'illenium-appearance:client:reloadSkin',
    -- NEW characters: opens the creator so the character gets a saved look at all
    newCharacterEvent = 'illenium-appearance:client:createFirstCharacter',

    -- Login only tells the CORE a character is loaded. Everything else - HUD,
    -- phone, garages, jobs, dispatch, inventory - waits for these spawn
    -- confirmation events, so without them the server acts as if nobody joined.
    notifyLoaded = true,
    serverLoadedEvent = 'QBCore:Server:OnPlayerLoaded',
    clientLoadedEvent = 'QBCore:Client:OnPlayerLoaded',
    extraLoadedEvents = {
        { name = 'qb-houses:server:SetInsideMeta',     server = true, args = { 0, false } },
        { name = 'qb-apartments:server:SetInsideMeta', server = true, args = { 0, 0, false } },
    },

    -- release the selector's forced weather/clock, or the override survives into
    -- the world for that player
    restoreWeatherSync = true,
    weatherSyncEvent = 'qb-weathersync:client:EnableSync',

    resetRoutingBucket = true,
    loadTimeoutMs = 10000, -- how long the server waits for the core's PlayerLoaded
}

-- Spawn selector --------------------------------------------------------------

Config.Spawn = {
    enabled = true,
    showForNewCharacters = true,

    allowLastLocation = true,
    lastLocationLabel = 'Last Location',
    lastLocationDesc  = 'Return to where you logged off',

    title = 'CHOOSE SPAWN',
    subtitle = 'Where do you want to start?',

    -- icon ids come from the set in web/js/spawn.js: map-pin, building, plane,
    -- mountain, trees, waves, home, briefcase, star, history
    locations = {
        { id = 'legion',   label = 'Legion Square',  desc = 'Downtown Los Santos',  icon = 'building', coords = vec4(195.1, -933.9, 30.69, 235.0) },
        { id = 'lsia',     label = 'LS Airport',     desc = 'Los Santos Intl',      icon = 'plane',    coords = vec4(-1035.7, -2731.6, 12.8, 240.0) },
        { id = 'vespucci', label = 'Vespucci Beach', desc = 'Sun, sand and pier',   icon = 'waves',    coords = vec4(-1211.5, -1470.6, 4.4, 300.0) },
        { id = 'sandy',    label = 'Sandy Shores',   desc = 'Blaine County desert', icon = 'mountain', coords = vec4(1853.0, 3689.0, 34.2, 210.0) },
        { id = 'paleto',   label = 'Paleto Bay',     desc = 'The far north',        icon = 'trees',    coords = vec4(-108.0, 6467.0, 31.6, 135.0) },
    },

    default = vec4(-1035.7, -2731.6, 12.8, 240.0),
}

-- Scene Maker -----------------------------------------------------------------

-- /scene lets a player pose their character, frame a shot and set the time and
-- weather, then save it as that character's personal backdrop in the selector.
Config.SceneMaker = {
    enabled = true,
    command = 'scene',
    restricted = false,
    ace = 'forger.scene',

    -- orbit rig: angle = azimuth around the ped, height = metres above the feet
    camera = {
        defaults = { angle = 200.0, height = 0.55, distance = 3.4, fov = 45.0, speed = 0.0 },
        limits   = { height = { -0.5, 2.5 }, distance = { 1.5, 9.0 }, fov = { 25.0, 65.0 } },
    },

    weathers = {
        'CLEAR', 'EXTRASUNNY', 'CLOUDS', 'OVERCAST', 'NEUTRAL',
        'RAIN', 'THUNDER', 'CLEARING', 'FOGGY', 'SMOG', 'XMAS', 'SNOW', 'BLIZZARD',
    },

    -- either a `scenario`, or a `dict` + `anim` (+ optional `flag`)
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
}

-- Co-op scene building: invite nearby players into an isolated session. The
-- organizer controls time, weather and camera and saves the scene.
Config.SceneMaker.coop = {
    enabled = true,
    maxInvitees = 4,
    inviteRadius = 14.0,  -- metres
    inviteTimeout = 30,   -- seconds
    bucketBase = 720000,  -- routing-bucket range for isolated sessions
}
