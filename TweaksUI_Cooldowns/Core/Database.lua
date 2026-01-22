-- ============================================================================
-- TweaksUI: Cooldowns - Database
-- Character-specific settings storage
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.Database = {}
local DB = TUICD.Database

-- ============================================================================
-- DEFAULT SETTINGS
-- ============================================================================

-- Shared tracker defaults (used by all trackers)
local TRACKER_DEFAULTS = {
    enabled = true,  -- Default to disabled for new installs
    -- Icon size
    iconSize = 36,              -- Base size (used with aspect ratio)
    iconWidth = nil,            -- Custom width (nil = use iconSize + aspect)
    iconHeight = nil,           -- Custom height (nil = use iconSize + aspect)
    aspectRatio = "1:1",        -- Preset or "custom"
    -- Layout
    columns = 8,
    rows = 0,                   -- 0 = unlimited
    customLayout = "",          -- Custom pattern like "4,4,2" (empty = use columns)
    spacingH = 2,               -- Horizontal spacing between icons
    spacingV = 2,               -- Vertical spacing between rows
    growDirection = "RIGHT",    -- PRIMARY: LEFT, RIGHT, UP, or DOWN
    growSecondary = "DOWN",     -- SECONDARY: LEFT, RIGHT, UP, or DOWN
    alignment = "LEFT",         -- LEFT, CENTER, or RIGHT
    reverseOrder = false,
    -- Custom grid
    useCustomGrid = false,      -- Use custom grid layout
    customGridMode = "rowfirst",-- "rowfirst" or "colfirst"
    customGridAlign = "topleft",-- Alignment within grid
    -- Appearance
    zoom = 0.08,                -- Texture inset (0 = full, higher = more zoom)
    borderAlpha = 1.0,
    iconOpacity = 1.0,
    iconOpacityCombat = nil,    -- Opacity override for combat (nil = use iconOpacity)
    inactiveAlpha = 0.5,        -- Alpha for inactive/on-cooldown icons
    greyscaleInactive = false,  -- Desaturate inactive icons
    useMasque = false,          -- Use Masque skinning (requires Masque addon)
    showSweep = true,           -- Show cooldown sweep/spiral animation
    showCountdownText = true,   -- Show countdown numbers on cooldown
    -- Interaction
    clickthrough = false,       -- Make icons click-through
    showTooltip = true,         -- Show tooltips on mouseover
    -- Cooldown Text
    cooldownTextScale = 1.0,    -- Scale of countdown numbers
    cooldownTextFont = "Default",
    cooldownTextOffsetX = 0,
    cooldownTextOffsetY = 0,
    cooldownTextColorR = 1,
    cooldownTextColorG = 1,
    cooldownTextColorB = 1,
    -- Count/Charge Text
    countTextScale = 1.0,       -- Scale of stack counts
    countTextFont = "Default",
    countTextOffsetX = 0,
    countTextOffsetY = 0,
    countTextColorR = 1,
    countTextColorG = 1,
    countTextColorB = 1,
    -- Visibility
    visibilityEnabled = false,  -- Master toggle for visibility conditions
    showInCombat = true,
    showOutOfCombat = true,
    showSolo = true,
    showInParty = true,
    showInRaid = true,
    showInInstance = true,
    showInArena = true,
    showInBattleground = true,
    showHasTarget = true,       -- Has a target selected
    showNoTarget = true,        -- No target selected
    fadeAlpha = 0.3,            -- Alpha when visibility conditions not met
    -- Persistent icon order (saved by texture fileID)
    savedIconOrder = {},        -- Array of texture fileIDs in desired order
}

-- Deep copy utility
local function DeepCopy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for k, v in pairs(orig) do
            copy[DeepCopy(k)] = DeepCopy(v)
        end
        setmetatable(copy, DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- Copy defaults for each tracker
local function CreateTrackerDefaults()
    return DeepCopy(TRACKER_DEFAULTS)
end

-- Account-wide defaults (minimal)
local DATABASE_DEFAULTS = {
    global = {
        version = TUICD.VERSION,
        lastSeenVersion = nil,  -- Track last version user has seen patch notes for
        debugMode = false,
        showMinimapButton = true,
        masqueEnabled = true,
    },
}

-- Character-specific defaults
local CHAR_DATABASE_DEFAULTS = {
    -- Tracker settings
    trackers = {
        essential = CreateTrackerDefaults(),
        utility = CreateTrackerDefaults(),
        buffs = CreateTrackerDefaults(),
        customTrackers = CreateTrackerDefaults(),
    },
    
    -- Custom tracker entries (per-spec)
    customEntries = {},  -- [specID] = { {type="spell", id=123}, ... }
    
    -- Position data
    containerPositions = {},  -- [trackerKey] = {point, x, y}
    
    -- Highlight settings (for alerts system)
    buffHighlights = {},
    essentialHighlights = {},
    utilityHighlights = {},
    customHighlights = {},
    
    -- Migration flags
    cmtMigrationVersion = nil,
    cmtMigrationDate = nil,
}

-- Add buff-specific defaults
CHAR_DATABASE_DEFAULTS.trackers.buffs.greyscaleInactive = true
CHAR_DATABASE_DEFAULTS.trackers.buffs.inactiveAlpha = 0.5

-- Custom tracker defaults
CHAR_DATABASE_DEFAULTS.trackers.customTrackers.enabled = true
CHAR_DATABASE_DEFAULTS.trackers.customTrackers.columns = 4
CHAR_DATABASE_DEFAULTS.trackers.customTrackers.point = "CENTER"
CHAR_DATABASE_DEFAULTS.trackers.customTrackers.x = 0
CHAR_DATABASE_DEFAULTS.trackers.customTrackers.y = -200

-- ============================================================================
-- MERGE HELPERS
-- ============================================================================

-- Merge defaults into existing table (only adds missing keys)
local function MergeDefaults(existing, defaults)
    if type(existing) ~= "table" or type(defaults) ~= "table" then
        return existing or defaults
    end
    
    for key, defaultValue in pairs(defaults) do
        if existing[key] == nil then
            if type(defaultValue) == "table" then
                existing[key] = DeepCopy(defaultValue)
            else
                existing[key] = defaultValue
            end
        elseif type(defaultValue) == "table" and type(existing[key]) == "table" then
            MergeDefaults(existing[key], defaultValue)
        end
    end
    
    return existing
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function DB:Initialize()
    -- Create or get account-wide saved variables
    if not TweaksUI_Cooldowns_DB then
        TweaksUI_Cooldowns_DB = DeepCopy(DATABASE_DEFAULTS)
    end
    self.db = TweaksUI_Cooldowns_DB
    
    -- Create or get per-character saved variables
    if not TweaksUI_Cooldowns_CharDB then
        TweaksUI_Cooldowns_CharDB = DeepCopy(CHAR_DATABASE_DEFAULTS)
    end
    self.charDb = TweaksUI_Cooldowns_CharDB
    
    -- Ensure all default keys exist
    self:EnsureDefaults()
    
    TUICD:PrintDebug("Database initialized")
end

function DB:EnsureDefaults()
    -- Ensure global section exists
    MergeDefaults(self.db, DATABASE_DEFAULTS)
    
    -- Ensure character database has all required fields
    MergeDefaults(self.charDb, CHAR_DATABASE_DEFAULTS)
    
    -- Ensure each tracker has all settings
    for trackerKey, defaults in pairs(CHAR_DATABASE_DEFAULTS.trackers) do
        if not self.charDb.trackers[trackerKey] then
            self.charDb.trackers[trackerKey] = DeepCopy(defaults)
        else
            MergeDefaults(self.charDb.trackers[trackerKey], defaults)
        end
    end
end

-- ============================================================================
-- TRACKER SETTINGS
-- ============================================================================

function DB:GetTrackerSettings(trackerKey)
    if not self.charDb.trackers[trackerKey] then
        self.charDb.trackers[trackerKey] = CreateTrackerDefaults()
    end
    return self.charDb.trackers[trackerKey]
end

function DB:GetTrackerSetting(trackerKey, key)
    local settings = self:GetTrackerSettings(trackerKey)
    return settings[key]
end

function DB:SetTrackerSetting(trackerKey, key, value)
    local settings = self:GetTrackerSettings(trackerKey)
    settings[key] = value
    TUICD.Events:Fire(TUICD.EVENTS.TRACKER_SETTINGS_CHANGED, trackerKey, key, value)
end

function DB:SetTrackerSettings(trackerKey, settingsTable)
    if not settingsTable then return end
    self.charDb.trackers[trackerKey] = settingsTable
    TUICD.Events:Fire(TUICD.EVENTS.TRACKER_SETTINGS_CHANGED, trackerKey, nil, nil)
end

-- ============================================================================
-- GLOBAL SETTINGS
-- ============================================================================

function DB:GetGlobal(key)
    if not self.db then return nil end
    if not self.db.global then return nil end
    return self.db.global[key]
end

function DB:SetGlobal(key, value)
    if not self.db then return end
    if not self.db.global then
        self.db.global = {}
    end
    self.db.global[key] = value
end

-- ============================================================================
-- CUSTOM ENTRIES
-- ============================================================================

function DB:GetCustomEntries(specID)
    if not self.charDb.customEntries then
        self.charDb.customEntries = {}
    end
    if not self.charDb.customEntries[specID] then
        self.charDb.customEntries[specID] = {}
    end
    return self.charDb.customEntries[specID]
end

function DB:SetCustomEntries(specID, entries)
    if not self.charDb.customEntries then
        self.charDb.customEntries = {}
    end
    self.charDb.customEntries[specID] = entries
    TUICD.Events:Fire(TUICD.EVENTS.CUSTOM_ENTRIES_CHANGED, specID)
end

function DB:AddCustomEntry(specID, entryType, entryID)
    local entries = self:GetCustomEntries(specID)
    table.insert(entries, { type = entryType, id = entryID })
    TUICD.Events:Fire(TUICD.EVENTS.CUSTOM_ENTRIES_CHANGED, specID)
end

function DB:RemoveCustomEntry(specID, index)
    local entries = self:GetCustomEntries(specID)
    if entries[index] then
        table.remove(entries, index)
        TUICD.Events:Fire(TUICD.EVENTS.CUSTOM_ENTRIES_CHANGED, specID)
    end
end

-- ============================================================================
-- CONTAINER POSITIONS
-- ============================================================================

function DB:GetContainerPosition(trackerKey)
    if not self.charDb.containerPositions then
        self.charDb.containerPositions = {}
    end
    return self.charDb.containerPositions[trackerKey]
end

function DB:SetContainerPosition(trackerKey, point, x, y)
    if not self.charDb.containerPositions then
        self.charDb.containerPositions = {}
    end
    self.charDb.containerPositions[trackerKey] = {
        point = point,
        x = x,
        y = y,
    }
end

function DB:ClearContainerPositions()
    if self.charDb then
        self.charDb.containerPositions = {}
    end
end

-- ============================================================================
-- HIGHLIGHT SETTINGS
-- ============================================================================

function DB:GetHighlightSettings(highlightKey)
    if not self.charDb[highlightKey] then
        self.charDb[highlightKey] = {}
    end
    return self.charDb[highlightKey]
end

function DB:SetHighlightSettings(highlightKey, settings)
    self.charDb[highlightKey] = settings
end

-- ============================================================================
-- MIGRATION FLAGS
-- ============================================================================

function DB:HasMigratedFromCMT()
    if not self.charDb then return false end
    return self.charDb.cmtMigrationVersion ~= nil
end

function DB:GetCMTMigrationVersion()
    if not self.charDb then return 0 end
    return self.charDb.cmtMigrationVersion or 0
end

function DB:SetCMTMigrated(version)
    if not self.charDb then return end
    self.charDb.cmtMigrationVersion = version
    self.charDb.cmtMigrationDate = date("%Y-%m-%d %H:%M:%S")
end

function DB:ClearCMTMigration()
    if not self.charDb then return end
    self.charDb.cmtMigrationVersion = nil
    self.charDb.cmtMigrationDate = nil
end

-- ============================================================================
-- INITIALIZATION CHECK
-- ============================================================================

function DB:IsInitialized()
    return self.db ~= nil and self.charDb ~= nil
end

-- ============================================================================
-- CHARACTER KEY
-- ============================================================================

function DB:GetCharacterKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    return name .. "-" .. realm
end

-- ============================================================================
-- DEEP COPY UTILITY (exposed for external use)
-- ============================================================================

TUICD.DeepCopy = DeepCopy
