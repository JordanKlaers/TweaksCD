-- ============================================================================
-- TUICD Cooldowns Module - MINIMAL VERSION
-- Settings management and UI panels ONLY for Buffs and Custom Trackers
-- No icon creation, layout, or cooldown tracking
-- ============================================================================

local ADDON_NAME, TUICD = ...

-- Ensure module IDs exist
if not TUICD.MODULE_IDS then return end
if not TUICD.MODULE_IDS.COOLDOWNS then
    TUICD.MODULE_IDS.COOLDOWNS = "cooldowns"
    TUICD.MODULE_NAMES[TUICD.MODULE_IDS.COOLDOWNS] = "Cooldown Trackers"
    table.insert(TUICD.MODULE_LOAD_ORDER, 1, TUICD.MODULE_IDS.COOLDOWNS)
end

-- Create the module
local Cooldowns = TUICD.ModuleManager:NewModule(TUICD.MODULE_IDS.COOLDOWNS)

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local ANCHOR_OPTIONS = {
    { label = "Center", value = "CENTER" },
    { label = "Top Left", value = "TOPLEFT" },
    { label = "Top", value = "TOP" },
    { label = "Top Right", value = "TOPRIGHT" },
    { label = "Left", value = "LEFT" },
    { label = "Right", value = "RIGHT" },
    { label = "Bottom Left", value = "BOTTOMLEFT" },
    { label = "Bottom", value = "BOTTOM" },
    { label = "Bottom Right", value = "BOTTOMRIGHT" },
}

-- Trackable equipment slots for custom tracker
local TRACKABLE_EQUIPMENT_SLOTS = {
    [13] = "Trinket 1",
    [14] = "Trinket 2",
    [10] = "Hands",
    [6] = "Waist",
    [15] = "Back",
    [16] = "Main Hand",
    [17] = "Off Hand",
}

-- Shared tracker defaults (used by buffs and custom trackers)
local TRACKER_DEFAULTS = {
    enabled = true,
    iconSize = 36,
    iconWidth = nil,
    iconHeight = nil,
    aspectRatio = "1:1",
    columns = 8,
    rows = 0,
    spacingH = 2,
    spacingV = 2,
    growDirection = "RIGHT",
    growSecondary = "DOWN",
    alignment = "LEFT",
    reverseOrder = false,
    customLayout = "",
    zoom = 0.08,
    borderAlpha = 1.0,
    iconOpacity = 1.0,
    iconOpacityCombat = 1.0,
    iconEdgeStyle = "sharp",
    useMasque = false,
    showTooltip = true,
    cooldownTextScale = 1.0,
    cooldownTextOffsetX = 0,
    cooldownTextOffsetY = 0,
    cooldownTextColorR = 1.0,
    cooldownTextColorG = 0.82,
    cooldownTextColorB = 0.0,
    cooldownTextFont = "Default",
    countTextScale = 1.0,
    countTextOffsetX = 0,
    countTextOffsetY = 0,
    countTextColorR = 1.0,
    countTextColorG = 1.0,
    countTextColorB = 1.0,
    countTextFont = "Default",
    hideSweep = false,
    showCountdownText = true,
    visibilityEnabled = false,
    showInCombat = true,
    showOutOfCombat = true,
    showSolo = true,
    showInParty = true,
    showInRaid = true,
    showInInstance = true,
    showInArena = true,
    showInBattleground = true,
    showHasTarget = true,
    showNoTarget = true,
    showMounted = true,
    showNotMounted = true,
    clickthrough = false,
    greyscaleInactive = true,
    inactiveAlpha = 0.5,
}

-- Default settings
local DEFAULTS = {
    global = {
        debugMode = false,
    },
    buffs = DeepCopy(TRACKER_DEFAULTS),
    customTrackers = DeepCopy(TRACKER_DEFAULTS),
}

-- Buff-specific defaults
DEFAULTS.buffs.columns = 8
DEFAULTS.buffs.rows = 0

-- Custom tracker specific defaults
DEFAULTS.customTrackers.enabled = false
DEFAULTS.customTrackers.columns = 4
DEFAULTS.customTrackers.rows = 0
DEFAULTS.customTrackers.point = "CENTER"
DEFAULTS.customTrackers.x = 0
DEFAULTS.customTrackers.y = -200

-- ============================================================================
-- LOCAL VARIABLES
-- ============================================================================

local settings = nil
local cooldownHub = nil
local settingsPanels = {}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[k] = DeepCopy(v)
        end
    else
        copy = orig
    end
    return copy
end

local function dprint(...)
    if not settings then
        local dbSettings = TUICD.Database and TUICD.Database:GetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS)
        if dbSettings and dbSettings.global and dbSettings.global.debugMode then
            print("|cff00ff00[TUICD CD]|r", ...)
        end
        return
    end
    if settings.global and settings.global.debugMode then
        print("|cff00ff00[TUICD CD]|r", ...)
    end
end

local function GetSetting(trackerKey, settingName)
    if not settings then
        Cooldowns:GetSettings()
    end
    if not settings or not settings[trackerKey] then return nil end
    return settings[trackerKey][settingName]
end

local function SetSetting(trackerKey, settingName, value)
    if not settings then
        Cooldowns:GetSettings()
    end
    if not settings then return end
    settings[trackerKey] = settings[trackerKey] or {}
    settings[trackerKey][settingName] = value
    
    if TUICD and TUICD.Database and TUICD.Database.SetModuleSettings then
        TUICD.Database:SetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS, settings)
    end
end

-- ============================================================================
-- SETTINGS MANAGEMENT
-- ============================================================================

function Cooldowns:GetSettings()
    if not settings then
        settings = DeepCopy(DEFAULTS)
        
        if TUICD and TUICD.Database then
            local dbSettings = TUICD.Database:GetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS)
            if dbSettings then
                for k, v in pairs(dbSettings) do
                    if type(v) == "table" and type(settings[k]) == "table" then
                        for sk, sv in pairs(v) do
                            settings[k][sk] = sv
                        end
                    else
                        settings[k] = v
                    end
                end
            end
        end
    end
    return settings
end

function Cooldowns:GetDefaults()
    return DeepCopy(DEFAULTS)
end

function Cooldowns:RefreshFromDatabase()
    settings = nil
    self:GetSettings()
end

function Cooldowns:SaveSettings()
    if settings then
        TUICD.Database:SetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS, settings)
    end
end

-- ============================================================================
-- CUSTOM TRACKER DATA MANAGEMENT
-- ============================================================================

local function InitializeCustomTrackerData()
    if not TweaksUI_Cooldowns_CharDB then
        TweaksUI_Cooldowns_CharDB = {}
    end
    
    TweaksUI_Cooldowns_CharDB.cooldowns = TweaksUI_Cooldowns_CharDB.cooldowns or {}
    TweaksUI_Cooldowns_CharDB.cooldowns.customEntries = TweaksUI_Cooldowns_CharDB.cooldowns.customEntries or {}
    TweaksUI_Cooldowns_CharDB.cooldowns.trackerCache = TweaksUI_Cooldowns_CharDB.cooldowns.trackerCache or {}
end

local function GetCurrentSpecID()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    local specID = GetSpecializationInfo(specIndex)
    return specID
end

local function GetCurrentSpecEntries()
    InitializeCustomTrackerData()
    
    local specID = GetCurrentSpecID()
    if not specID then return {} end
    
    TweaksUI_Cooldowns_CharDB.cooldowns.customEntries[specID] = TweaksUI_Cooldowns_CharDB.cooldowns.customEntries[specID] or {}
    return TweaksUI_Cooldowns_CharDB.cooldowns.customEntries[specID]
end

local function EntryExists(entryType, entryID)
    local entries = GetCurrentSpecEntries()
    for _, entry in ipairs(entries) do
        if entry.type == entryType and entry.id == entryID then
            return true
        end
    end
    return false
end

local function AddCustomEntry(entryType, idOrName)
    InitializeCustomTrackerData()
    
    local specID = GetCurrentSpecID()
    if not specID then
        return false, "Could not determine current spec"
    end
    
    TweaksUI_Cooldowns_CharDB.cooldowns.customEntries[specID] = TweaksUI_Cooldowns_CharDB.cooldowns.customEntries[specID] or {}
    local entries = TweaksUI_Cooldowns_CharDB.cooldowns.customEntries[specID]
    
    local entryID
    local entryName, entryTexture
    
    if entryType == "spell" then
        if type(idOrName) == "number" then
            entryID = idOrName
        else
            local spellID = select(7, C_Spell.GetSpellInfo(idOrName))
            if not spellID then
                return false, "Unknown spell: " .. tostring(idOrName)
            end
            entryID = spellID
        end
        
        local spellInfo = C_Spell.GetSpellInfo(entryID)
        if spellInfo then
            entryName = spellInfo.name
            entryTexture = C_Spell.GetSpellTexture(entryID)
        end
        
    elseif entryType == "item" then
        if type(idOrName) == "number" then
            entryID = idOrName
        else
            entryID = C_Item.GetItemInfoInstant(idOrName)
            if not entryID then
                return false, "Unknown item: " .. tostring(idOrName)
            end
        end
        
        entryName = C_Item.GetItemNameByID(entryID)
        entryTexture = C_Item.GetItemIconByID(entryID)
        
    elseif entryType == "equipped" then
        entryID = tonumber(idOrName)
        if not entryID or not TRACKABLE_EQUIPMENT_SLOTS[entryID] then
            return false, "Invalid equipment slot: " .. tostring(idOrName)
        end
        entryName = TRACKABLE_EQUIPMENT_SLOTS[entryID]
        
    else
        return false, "Invalid entry type: " .. tostring(entryType)
    end
    
    if EntryExists(entryType, entryID) then
        return false, "Already tracking this " .. entryType
    end
    
    table.insert(entries, {
        type = entryType,
        id = entryID,
        enabled = true,
    })
    
    if not GetSetting("customTrackers", "enabled") then
        SetSetting("customTrackers", "enabled", true)
        dprint("Auto-enabled custom tracker for first entry")
    end
    
    dprint(string.format("Added custom entry: %s %d (%s)", entryType, entryID, entryName or "unknown"))
    return true, "Added: " .. (entryName or entryType .. " " .. entryID)
end

local function RemoveCustomEntry(index)
    local entries = GetCurrentSpecEntries()
    if index < 1 or index > #entries then return false end
    
    local removed = table.remove(entries, index)
    if removed then
        dprint(string.format("Removed custom entry: %s %d", removed.type, removed.id))
        return true
    end
    return false
end

local function SetCustomEntryEnabled(index, enabled)
    local entries = GetCurrentSpecEntries()
    if index < 1 or index > #entries then return false end
    
    entries[index].enabled = enabled
    return true
end

local function MoveCustomEntry(fromIndex, toIndex)
    local entries = GetCurrentSpecEntries()
    if fromIndex < 1 or fromIndex > #entries then return false end
    if toIndex < 1 or toIndex > #entries then return false end
    if fromIndex == toIndex then return false end
    
    local entry = table.remove(entries, fromIndex)
    table.insert(entries, toIndex, entry)
    
    dprint(string.format("Moved entry from %d to %d", fromIndex, toIndex))
    return true
end

local function HasOnUseAbility(itemID)
    if not itemID then return false end
    local spellName, spellID = GetItemSpell(itemID)
    return spellName ~= nil, spellID, spellName
end

local function ScanEquippedOnUseItems()
    local items = {}
    
    for slotID, slotName in pairs(TRACKABLE_EQUIPMENT_SLOTS) do
        local itemID = GetInventoryItemID("player", slotID)
        if itemID then
            local hasOnUse, spellID, spellName = HasOnUseAbility(itemID)
            if hasOnUse then
                local itemName = C_Item.GetItemNameByID(itemID)
                local itemTexture = C_Item.GetItemIconByID(itemID)
                table.insert(items, {
                    slotID = slotID,
                    slotName = slotName,
                    itemID = itemID,
                    itemName = itemName or "Unknown",
                    itemTexture = itemTexture,
                    spellID = spellID,
                    spellName = spellName,
                })
            end
        end
    end
    
    return items
end

-- ============================================================================
-- EXPORTS FOR UI MODULES
-- ============================================================================

Cooldowns.GetCurrentSpecEntries = GetCurrentSpecEntries
Cooldowns.AddCustomEntry = AddCustomEntry
Cooldowns.RemoveCustomEntry = RemoveCustomEntry
Cooldowns.SetCustomEntryEnabled = SetCustomEntryEnabled
Cooldowns.MoveCustomEntry = MoveCustomEntry
Cooldowns.ScanEquippedOnUseItems = ScanEquippedOnUseItems

TUICD.Cooldowns = Cooldowns

-- ============================================================================
-- UI CONSTANTS AND HELPERS
-- ============================================================================

local HUB_WIDTH = 220
local HUB_HEIGHT = 400
local BUTTON_HEIGHT = 28
local BUTTON_SPACING = 4
local PANEL_WIDTH = 450
local PANEL_HEIGHT = 600

local darkBackdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
}

local currentOpenPanel = nil

local function GetTrackerInfo(trackerKey)
    if trackerKey == "buffs" then
        return { name = "BuffIconCooldownViewer", displayName = "Buff Tracker", key = "buffs" }
    elseif trackerKey == "customTrackers" then
        return { name = "TweaksUI_CustomTrackerFrame", displayName = "Custom Trackers", key = "customTrackers" }
    end
    return nil
end

local function CountTableEntries(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- ============================================================================
-- EXPORT / IMPORT
-- ============================================================================

local function SerializeCooldownSettings()
    local serialized = "TweaksUI_Cooldowns:"
    
    local function serializeTable(tbl, prefix)
        local result = ""
        for k, v in pairs(tbl) do
            local key = prefix and (prefix .. "." .. k) or k
            if type(v) == "table" then
                result = result .. serializeTable(v, key)
            elseif type(v) == "boolean" then
                result = result .. key .. "=" .. (v and "true" or "false") .. ";"
            elseif type(v) == "number" then
                result = result .. key .. "=" .. tostring(v) .. ";"
            elseif type(v) == "string" then
                result = result .. key .. "=" .. v .. ";"
            end
        end
        return result
    end
    
    serialized = serialized .. serializeTable(settings, nil)
    return serialized
end

local function DeserializeCooldownSettings(str)
    if not str or not str:find("^TweaksUI_Cooldowns:") then
        return nil, "Invalid import string"
    end
    
    str = str:gsub("^TweaksUI_Cooldowns:", "")
    
    local newSettings = DeepCopy(DEFAULTS)
    
    for pair in str:gmatch("([^;]+)") do
        local key, value = pair:match("(.+)=(.+)")
        if key and value then
            local parts = {}
            for part in key:gmatch("[^%.]+") do
                table.insert(parts, part)
            end
            
            local current = newSettings
            for i = 1, #parts - 1 do
                if current[parts[i]] then
                    current = current[parts[i]]
                end
            end
            
            local finalKey = parts[#parts]
            if value == "true" then
                current[finalKey] = true
            elseif value == "false" then
                current[finalKey] = false
            elseif tonumber(value) then
                current[finalKey] = tonumber(value)
            else
                current[finalKey] = value
            end
        end
    end
    
    return newSettings
end

function Cooldowns:ShowExportDialog()
    local dialog = CreateFrame("Frame", "TweaksUI_Cooldowns_ExportDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(450, 350)
    dialog:SetPoint("CENTER")
    dialog:SetBackdrop(darkBackdrop)
    dialog:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    dialog:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    dialog:SetFrameStrata("DIALOG")
    dialog:EnableMouse(true)
    
    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Export Cooldown Tracker Settings")
    title:SetTextColor(1, 0.82, 0)
    
    local closeBtn = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -3, -3)
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 50)
    
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(390)
    editBox:SetAutoFocus(false)
    editBox:SetText(SerializeCooldownSettings())
    editBox:HighlightText()
    scrollFrame:SetScrollChild(editBox)
    
    local copyLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    copyLabel:SetPoint("BOTTOM", 0, 30)
    copyLabel:SetText("Press Ctrl+C to copy")
    copyLabel:SetTextColor(0.8, 0.8, 0.8)
    
    local closeButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    closeButton:SetPoint("BOTTOM", 0, 10)
    closeButton:SetSize(100, 24)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function() dialog:Hide() end)
end

function Cooldowns:ShowImportDialog()
    local dialog = CreateFrame("Frame", "TweaksUI_Cooldowns_ImportDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(450, 350)
    dialog:SetPoint("CENTER")
    dialog:SetBackdrop(darkBackdrop)
    dialog:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    dialog:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    dialog:SetFrameStrata("DIALOG")
    dialog:EnableMouse(true)
    
    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Import Cooldown Tracker Settings")
    title:SetTextColor(1, 0.82, 0)
    
    local closeBtn = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -3, -3)
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 80)
    
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(390)
    editBox:SetAutoFocus(true)
    editBox:SetText("")
    scrollFrame:SetScrollChild(editBox)
    
    local pasteLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pasteLabel:SetPoint("BOTTOM", 0, 58)
    pasteLabel:SetText("Paste import string above (Ctrl+V)")
    pasteLabel:SetTextColor(0.8, 0.8, 0.8)
    
    local module = self
    
    local importButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    importButton:SetPoint("BOTTOMLEFT", 50, 20)
    importButton:SetSize(100, 24)
    importButton:SetText("Import")
    importButton:SetScript("OnClick", function()
        local str = editBox:GetText()
        local newSettings, err = DeserializeCooldownSettings(str)
        if newSettings then
            for k, v in pairs(newSettings) do
                settings[k] = v
            end
            if TUICD and TUICD.Print then
                TUICD:Print("Cooldown Tracker settings imported successfully!")
            end
            dialog:Hide()
        else
            if TUICD and TUICD.Print then
                TUICD:Print("|cffff0000Import failed:|r " .. (err or "Unknown error"))
            end
        end
    end)
    
    local cancelButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancelButton:SetPoint("BOTTOMRIGHT", -50, 20)
    cancelButton:SetSize(100, 24)
    cancelButton:SetText("Cancel")
    cancelButton:SetScript("OnClick", function() dialog:Hide() end)
end

-- ============================================================================
-- MAIN HUB
-- ============================================================================

function Cooldowns:CreateHub(parent)
    if cooldownHub then return cooldownHub end
    
    local hub = CreateFrame("Frame", "TweaksUI_Cooldowns_Hub", parent or UIParent, "BackdropTemplate")
    hub:SetSize(HUB_WIDTH, HUB_HEIGHT + 50)
    hub:SetBackdrop(darkBackdrop)
    hub:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    hub:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    hub:SetFrameStrata("DIALOG")
    hub:Hide()
    
    local title = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Cooldown Trackers")
    title:SetTextColor(1, 0.82, 0)
    
    local closeBtn = CreateFrame("Button", nil, hub, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        hub:Hide()
        self:HideAllPanels()
    end)
    
    hub:SetScript("OnHide", function()
        self:HideAllPanels()
    end)
    
    local yOffset = -38
    
    if TUICD.PresetDropdown then
        local presetContainer, nextY = TUICD.PresetDropdown:Create(
            hub,
            "cooldowns",
            "Cooldowns",
            yOffset,
            {
                width = 140,
                showSaveButton = true,
                showDeleteButton = true,
            }
        )
        yOffset = nextY - 8
    end
    
    local sectionLabel = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sectionLabel:SetPoint("TOP", 0, yOffset)
    sectionLabel:SetText("|cff888888Blizzard Trackers|r")
    yOffset = yOffset - 16
    
    -- Buffs tracker button
    local buffsBtn = CreateFrame("Button", nil, hub, "UIPanelButtonTemplate")
    buffsBtn:SetSize(HUB_WIDTH - 30, BUTTON_HEIGHT)
    buffsBtn:SetPoint("TOP", 0, yOffset)
    buffsBtn:SetText("Buff Tracker")
    buffsBtn:SetScript("OnClick", function()
        self:TogglePanel("buffs")
    end)
    yOffset = yOffset - BUTTON_HEIGHT - BUTTON_SPACING
    
    yOffset = yOffset - 6
    
    local customLabel = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    customLabel:SetPoint("TOP", 0, yOffset)
    customLabel:SetText("|cff888888Custom Trackers|r")
    yOffset = yOffset - 16
    
    local customBtn = CreateFrame("Button", nil, hub, "UIPanelButtonTemplate")
    customBtn:SetSize(HUB_WIDTH - 30, BUTTON_HEIGHT)
    customBtn:SetPoint("TOP", 0, yOffset)
    customBtn:SetText("Custom Trackers")
    customBtn:SetScript("OnClick", function()
        self:TogglePanel("customTrackers")
    end)
    yOffset = yOffset - BUTTON_HEIGHT - BUTTON_SPACING
    
    yOffset = yOffset - 4
    
    local sep = hub:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOP", 0, yOffset)
    sep:SetSize(HUB_WIDTH - 20, 1)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    yOffset = yOffset - 12
    
    local ieLabel = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ieLabel:SetPoint("TOP", 0, yOffset)
    ieLabel:SetText("|cff888888Import / Export|r")
    yOffset = yOffset - 20
    
    local exportBtn = CreateFrame("Button", nil, hub, "UIPanelButtonTemplate")
    exportBtn:SetSize(HUB_WIDTH - 30, BUTTON_HEIGHT)
    exportBtn:SetPoint("TOP", 0, yOffset)
    exportBtn:SetText("Export All")
    exportBtn:SetScript("OnClick", function()
        self:ShowExportDialog()
    end)
    yOffset = yOffset - BUTTON_HEIGHT - BUTTON_SPACING
    
    local importBtn = CreateFrame("Button", nil, hub, "UIPanelButtonTemplate")
    importBtn:SetSize(HUB_WIDTH - 30, BUTTON_HEIGHT)
    importBtn:SetPoint("TOP", 0, yOffset)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        self:ShowImportDialog()
    end)
    
    if TUICD.GlobalScale then
        TUICD.GlobalScale:RegisterSettingsPanel(hub, 1.0)
    end
    
    cooldownHub = hub
    return hub
end

function Cooldowns:ShowHub(parent)
    if not cooldownHub then
        cooldownHub = self:CreateHub(parent)
    end
    
    if parent then
        cooldownHub:ClearAllPoints()
        cooldownHub:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, 0)
    end
    
    cooldownHub:Show()
end

function Cooldowns:ToggleSettingsPanel(parent)
    if not cooldownHub then
        cooldownHub = self:CreateHub(parent)
    end
    
    if cooldownHub:IsShown() then
        self:HideAllPanels()
    else
        if parent then
            cooldownHub:ClearAllPoints()
            cooldownHub:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, 0)
        end
        cooldownHub:Show()
    end
end

function Cooldowns:HideAllPanels()
    for _, panel in pairs(settingsPanels) do
        if panel then panel:Hide() end
    end
    if cooldownHub then cooldownHub:Hide() end
    currentOpenPanel = nil
end

function Cooldowns:HideTrackerPanels()
    for _, panel in pairs(settingsPanels) do
        if panel then panel:Hide() end
    end
    currentOpenPanel = nil
end

function Cooldowns:TogglePanel(trackerKey)
    for key, panel in pairs(settingsPanels) do
        if panel and key ~= trackerKey then
            panel:Hide()
        end
    end
    
    if settingsPanels[trackerKey] then
        if settingsPanels[trackerKey]:IsShown() then
            settingsPanels[trackerKey]:Hide()
            currentOpenPanel = nil
        else
            settingsPanels[trackerKey]:Show()
            currentOpenPanel = trackerKey
        end
    else
        if trackerKey == "customTrackers" then
            self:CreateCustomTrackersPanel()
        else
            self:CreateTrackerPanel(trackerKey)
        end
        if settingsPanels[trackerKey] then
            settingsPanels[trackerKey]:Show()
            currentOpenPanel = trackerKey
        end
    end
end

-- ============================================================================
-- TRACKER PANEL (For Buffs)
-- ============================================================================

function Cooldowns:CreateTrackerPanel(trackerKey)
    local trackerInfo = GetTrackerInfo(trackerKey)
    if not trackerInfo then return end
    
    local panel = CreateFrame("Frame", "TweaksUI_Cooldowns_" .. trackerKey .. "_Panel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetPoint("TOPLEFT", cooldownHub, "TOPRIGHT", 0, 0)
    panel:SetBackdrop(darkBackdrop)
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetFrameStrata("DIALOG")
    
    settingsPanels[trackerKey] = panel
    
    if TUICD.GlobalScale then
        TUICD.GlobalScale:RegisterSettingsPanel(panel, 1.0)
    end
    
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText(trackerInfo.displayName)
    title:SetTextColor(1, 0.82, 0)
    
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        panel:Hide()
    end)
    
    panel:SetScript("OnHide", function()
        currentOpenPanel = nil
    end)
    
    -- Simplified panel with just "Individual Icons" tab
    local content = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    content:SetPoint("TOPLEFT", 10, -40)
    content:SetPoint("BOTTOMRIGHT", -28, 10)
    
    local scrollChild = CreateFrame("Frame", nil, content)
    scrollChild:SetSize(PANEL_WIDTH - 50, 800)
    content:SetScrollChild(scrollChild)
    
    -- Build per-icon settings
    self:BuildPerIconTab(scrollChild, trackerKey)
    
    panel:Show()
end

-- ============================================================================
-- PER-ICON SETTINGS TAB
-- ============================================================================

function Cooldowns:BuildPerIconTab(parent, trackerType)
    local y = -10
    local CooldownHighlights = TUICD.CooldownHighlights
    
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 5, y)
    header:SetText("Individual Icons")
    header:SetTextColor(1, 0.82, 0)
    y = y - 26
    
    local description = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    description:SetPoint("TOPLEFT", 5, y)
    description:SetPoint("TOPRIGHT", -10, y)
    description:SetJustifyH("LEFT")
    description:SetText("|cff888888Individual icon settings managed through CooldownHighlights module.|r")
    y = y - 40
    
    if not CooldownHighlights then
        local errorText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        errorText:SetPoint("TOPLEFT", 5, y)
        errorText:SetText("|cffff0000CooldownHighlights module not available|r")
        return
    end
    
    local infoText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOPLEFT", 5, y)
    infoText:SetPoint("TOPRIGHT", -10, y)
    infoText:SetJustifyH("LEFT")
    infoText:SetText("Per-icon settings like hide, size, position are handled by the CooldownHighlights module.\n\nSettings are saved per character/spec.")
    infoText:SetTextColor(0.7, 0.7, 0.7)
end

-- ============================================================================
-- CUSTOM TRACKERS PANEL
-- ============================================================================

function Cooldowns:CreateCustomTrackersPanel()
    local panel = CreateFrame("Frame", "TweaksUI_Cooldowns_customTrackers_Panel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT + 50)
    panel:SetPoint("TOPLEFT", cooldownHub, "TOPRIGHT", 0, 0)
    panel:SetBackdrop(darkBackdrop)
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetFrameStrata("DIALOG")
    
    settingsPanels["customTrackers"] = panel
    local trackerKey = "customTrackers"
    
    if TUICD.GlobalScale then
        TUICD.GlobalScale:RegisterSettingsPanel(panel, 1.0)
    end
    
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Custom Trackers")
    title:SetTextColor(1, 0.82, 0)
    
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    
    -- Create scroll content
    local content = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    content:SetPoint("TOPLEFT", 10, -40)
    content:SetPoint("BOTTOMRIGHT", -28, 10)
    
    local scrollChild = CreateFrame("Frame", nil, content)
    scrollChild:SetSize(PANEL_WIDTH - 50, 1200)
    content:SetScrollChild(scrollChild)
    
    local y = -10
    
    -- Master Enable
    local enableHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    enableHeader:SetPoint("TOPLEFT", 5, y)
    enableHeader:SetText("Master Enable")
    enableHeader:SetTextColor(1, 0.82, 0)
    y = y - 20
    
    local enableCheck = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
    enableCheck:SetPoint("TOPLEFT", 10, y)
    enableCheck:SetSize(24, 24)
    enableCheck:SetChecked(GetSetting(trackerKey, "enabled") or false)
    enableCheck:SetScript("OnClick", function(self)
        SetSetting(trackerKey, "enabled", self:GetChecked())
    end)
    
    local enableLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    enableLabel:SetPoint("LEFT", enableCheck, "RIGHT", 4, 0)
    enableLabel:SetText("Enable Custom Trackers")
    enableLabel:SetTextColor(0.8, 0.8, 0.8)
    y = y - 36
    
    -- Add Entry Section
    local addHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    addHeader:SetPoint("TOPLEFT", 5, y)
    addHeader:SetText("Add Entry")
    addHeader:SetTextColor(1, 0.82, 0)
    y = y - 20
    
    -- Drop zone
    local dropZone = CreateFrame("Button", nil, scrollChild, "BackdropTemplate")
    dropZone:SetPoint("TOPLEFT", 10, y)
    dropZone:SetSize(PANEL_WIDTH - 60, 45)
    dropZone:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    dropZone:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    dropZone:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    local dropText = dropZone:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dropText:SetPoint("CENTER")
    dropText:SetText("|cff888888Drop spell or item here|r")
    
    local function ProcessPanelDrop()
        local cursorType, id, subType, spellID = GetCursorInfo()
        
        if cursorType == "spell" then
            local actualSpellID = spellID or id
            if actualSpellID then
                local success, msg = AddCustomEntry("spell", actualSpellID)
                ClearCursor()
                if success and panel.RefreshEntriesList then
                    panel:RefreshEntriesList()
                    dropText:SetText("|cff00ff00Added!|r")
                    C_Timer.After(1.5, function()
                        dropText:SetText("|cff888888Drop spell or item here|r")
                    end)
                end
                return true
            end
        elseif cursorType == "item" then
            local itemID = id
            if itemID then
                local success, msg = AddCustomEntry("item", itemID)
                ClearCursor()
                if success and panel.RefreshEntriesList then
                    panel:RefreshEntriesList()
                    dropText:SetText("|cff00ff00Added!|r")
                    C_Timer.After(1.5, function()
                        dropText:SetText("|cff888888Drop spell or item here|r")
                    end)
                end
                return true
            end
        end
        ClearCursor()
        return false
    end
    
    dropZone:SetScript("OnReceiveDrag", ProcessPanelDrop)
    dropZone:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and GetCursorInfo() then
            ProcessPanelDrop()
        end
    end)
    
    dropZone:SetScript("OnEnter", function(self)
        if GetCursorInfo() then
            self:SetBackdropBorderColor(0.2, 0.8, 0.2, 1)
            dropText:SetText("|cff00ff00Release to add!|r")
        else
            self:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        end
    end)
    
    dropZone:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        dropText:SetText("|cff888888Drop spell or item here|r")
    end)
    
    y = y - 60
    
    -- Manual entry
    local manualLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    manualLabel:SetPoint("TOPLEFT", 10, y)
    manualLabel:SetText("Manual ID/Name:")
    manualLabel:SetTextColor(0.6, 0.6, 0.6)
    
    local idInput = CreateFrame("EditBox", nil, scrollChild, "InputBoxTemplate")
    idInput:SetPoint("LEFT", manualLabel, "RIGHT", 8, 0)
    idInput:SetSize(100, 20)
    idInput:SetAutoFocus(false)
    idInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    
    local addBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    addBtn:SetPoint("LEFT", idInput, "RIGHT", 3, 0)
    addBtn:SetSize(80, 20)
    addBtn:SetText("Add Spell")
    
    addBtn:SetScript("OnClick", function()
        local input = idInput:GetText():trim()
        if input ~= "" then
            local success = AddCustomEntry("spell", input)
            if success then
                idInput:SetText("")
                if panel.RefreshEntriesList then
                    panel:RefreshEntriesList()
                end
            end
        end
    end)
    
    idInput:SetScript("OnEnterPressed", function(self)
        addBtn:Click()
        self:ClearFocus()
    end)
    
    y = y - 36
    
    -- Entries List
    local listHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listHeader:SetPoint("TOPLEFT", 5, y)
    listHeader:SetText("Tracked Entries")
    listHeader:SetTextColor(1, 0.82, 0)
    y = y - 20
    
    local entriesContainer = CreateFrame("Frame", nil, scrollChild)
    entriesContainer:SetPoint("TOPLEFT", 10, y)
    entriesContainer:SetSize(PANEL_WIDTH - 60, 400)
    panel.entriesContainer = entriesContainer
    
    local entryElements = {}
    
    function panel:RefreshEntriesList()
        for _, elem in ipairs(entryElements) do
            if elem.Hide then elem:Hide() end
            if elem.SetParent then elem:SetParent(nil) end
        end
        wipe(entryElements)
        
        local entries = GetCurrentSpecEntries()
        local eY = 0
        
        if #entries == 0 then
            local noEntries = entriesContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            noEntries:SetPoint("TOPLEFT", 0, 0)
            noEntries:SetText("|cff666666No entries for current spec|r")
            table.insert(entryElements, noEntries)
            return
        end
        
        for i, entry in ipairs(entries) do
            local row = CreateFrame("Frame", nil, entriesContainer, "BackdropTemplate")
            row:SetPoint("TOPLEFT", 0, eY)
            row:SetSize(PANEL_WIDTH - 80, 24)
            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 0,
            })
            row:SetBackdropColor(0.15, 0.15, 0.15, i % 2 == 0 and 0.5 or 0.3)
            table.insert(entryElements, row)
            
            -- Entry name
            local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            name:SetPoint("LEFT", 4, 0)
            name:SetPoint("RIGHT", -100, 0)
            name:SetJustifyH("LEFT")
            name:SetText(string.format("[%s] ID: %d", entry.type, entry.id))
            
            -- Remove button
            local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            removeBtn:SetPoint("RIGHT", -2, 0)
            removeBtn:SetSize(60, 18)
            removeBtn:SetText("Remove")
            removeBtn:SetScript("OnClick", function()
                RemoveCustomEntry(i)
                panel:RefreshEntriesList()
            end)
            
            eY = eY - 26
        end
    end
    
    panel:RefreshEntriesList()
    panel:Show()
end

-- ============================================================================
-- MODULE LIFECYCLE
-- ============================================================================

function Cooldowns:OnInitialize()
    dprint("Cooldowns module initialized (MINIMAL VERSION - settings only)")
    
    InitializeCustomTrackerData()
    self:GetSettings()
end

function Cooldowns:OnEnable()
    dprint("Cooldowns module enabled (MINIMAL VERSION - no rendering)")
    
    -- Initialize settings
    self:GetSettings()
    
    -- That's it - no icon creation, no hooks, no rendering
end

function Cooldowns:OnDisable()
    dprint("Cooldowns module disabled")
end

function Cooldowns:OnProfileChanged(profileName)
    dprint("Profile changed to:", profileName)
    
    self:GetSettings()
    InitializeCustomTrackerData()
end

-- Save settings on logout
local saveFrame = CreateFrame("Frame")
saveFrame:RegisterEvent("PLAYER_LOGOUT")
saveFrame:SetScript("OnEvent", function()
    if settings then
        TUICD.Database:SetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS, settings)
    end
end)

return Cooldowns
