-- ============================================================================
-- TUICD Cooldowns Module
-- Hooks Blizzard's Cooldown Manager viewers and applies custom layouts
-- ============================================================================

local ADDON_NAME, TUICD = ...
TUICD.Cooldowns = TUICD.Cooldowns or {}
local Cooldowns = TUICD.Cooldowns
-- Ensure module IDs exist
if not TUICD.MODULE_IDS then return end
if not TUICD.MODULE_IDS.COOLDOWNS then
    TUICD.MODULE_IDS.COOLDOWNS = "cooldowns"
    TUICD.MODULE_NAMES[TUICD.MODULE_IDS.COOLDOWNS] = "Cooldown Trackers"
    table.insert(TUICD.MODULE_LOAD_ORDER, 1, TUICD.MODULE_IDS.COOLDOWNS)
end

-- Create the module
local Cooldowns = TUICD.ModuleManager:NewModule(TUICD.MODULE_IDS.COOLDOWNS)
local HUB_WIDTH = 220
local HUB_HEIGHT = 480
local PANEL_WIDTH = 500
local PANEL_HEIGHT = 600
local BUTTON_HEIGHT = 28
local BUTTON_SPACING = 6

-- Dark backdrop
local darkBackdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
}

-- Equipment slots that can have on-use abilities
local TRACKABLE_EQUIPMENT_SLOTS = {
    [1] = "Head",
    [2] = "Neck",
    [3] = "Shoulder",
    [5] = "Chest",
    [6] = "Waist",
    [7] = "Legs",
    [8] = "Feet",
    [9] = "Wrist",
    [10] = "Hands",
    [11] = "Ring 1",
    [12] = "Ring 2",
    [13] = "Trinket 1",
    [14] = "Trinket 2",
    [15] = "Back",
    [16] = "Main Hand",
    [17] = "Off Hand",
}

-- ============================================================================
-- LOCAL VARIABLES
-- ============================================================================

local cooldownHub = nil
local settingsPanels = {}
local customTrackerIcons = {}       -- [entryKey] = iconFrame (entryKey = "spell_123" or "item_456")

-- Event system for tracker list updates
local trackerListUpdateCallbacks = {}  -- Callbacks to fire when tracker list changes

local function FireTrackerListUpdate()
    for _, callback in ipairs(trackerListUpdateCallbacks) do
        pcall(callback)
    end
end

local function RegisterTrackerListUpdateCallback(callback)
    table.insert(trackerListUpdateCallbacks, callback)
end

-- Export for external use
Cooldowns.FireTrackerListUpdate = FireTrackerListUpdate

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

function Cooldowns.SetConsistentScrollingBehavior(scrollFrame)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        
        -- Scroll 10% of visible height per tick
        local scrollAmount = self:GetHeight() * 0.05
        
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - (delta * scrollAmount))))
    end)
end

-- Get current spec ID
function Cooldowns.GetCurrentSpecID()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    local specID = GetSpecializationInfo(specIndex)
    return specID
end

-- Add a custom entry (spell, item, or equipped slot)
local function AddCustomEntry(entryType, idOrName)
    local trackedData = {
        apiIdentifier = "",
        trackingType = "",
        name = "",
        iconTexturePath = ""
    }
    
    if entryType == "spell" then
        local spellInfo = C_Spell.GetSpellInfo(tonumber(idOrName) or idOrName)
        if spellInfo then
            trackedData.apiIdentifier = spellInfo.spellID
            trackedData.trackingType = entryType
            trackedData.name = spellInfo.name
            trackedData.iconTexturePath = spellInfo.iconID
        else
            return false, "Spell ID not found: " .. tonumber(idOrName) or idOrName
        end
    elseif entryType == "item" then
        -- Normalize any input (ID or name) to itemID
        local itemID = C_Item.GetItemIDForItemInfo(tonumber(idOrName) or idOrName)
        if itemID then
            local itemName, _, _, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemID)
            trackedData.apiIdentifier = itemID
            trackedData.trackingType = entryType
            trackedData.name = itemName or "Loading..."
            trackedData.iconTexturePath = itemTexture
            if not itemName then
                --C_Item.RequestLoadItemDataByID(itemID) -- TODO: Responsd to this event: "ITEM_DATA_LOAD_RESULT" to.. add the item?
            end
        else
            return false, "Item not found: " .. idOrName
        end
        
    elseif entryType == "equipped" then
        -- For equipped slots, idOrName should be the slot ID
        local slotID = tonumber(idOrName)
        if not slotID then
            return false, "Invalid slot ID"
        end
        if not TRACKABLE_EQUIPMENT_SLOTS[slotID] then
            return false, "Invalid equipment slot: " .. slotID
        end
        local itemID = GetInventoryItemID("player", slotID)
        local _, _, _, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemID)
        trackedData.apiIdentifier = slotID -- This needs to remain as the equipped slot number to allow for dynamically changing items
        trackedData.trackingType = entryType
        trackedData.name = TRACKABLE_EQUIPMENT_SLOTS[slotID]
        trackedData.iconTexturePath = itemTexture
        
    else
        return false, "Invalid entry type: " .. tostring(entryType)
    end
    
    -- Check for duplicates
    if (TUICD.CooldownHighlights:IsAlreadyTracked(trackedData)) then
        return false
    end

    -- Add entry with enabled flag
    TUICD.CooldownHighlights:AddTrackedValue(trackedData)
    
    -- Notify UI to update if settings panel has been opened (callbacks are registered)
    -- If settings haven't been opened yet, this will be nil and we can skip the update
    -- (the list will render correctly when first opened anyway)
    if Cooldowns and Cooldowns.FireTrackerListUpdate then
        Cooldowns.FireTrackerListUpdate()
    end
    
    return true
end


--[[============================================================================
-- Two helper methods for pre populating suggested items to add to the tracker
-- ============================================================================]]

-- Check if an item has an on-use ability
local function HasOnUseAbility(itemID)
    if not itemID then return false end
    local spellName, spellID = GetItemSpell(itemID)
    return spellName ~= nil, spellID, spellName
end

-- Scan equipped items for on-use abilities
local function ScanEquippedOnUseItems()
    local trackableItems = {}
    
    for slotID, slotName in pairs(TRACKABLE_EQUIPMENT_SLOTS) do
        local itemID = GetInventoryItemID("player", slotID)
        if itemID then
            local hasOnUse, spellID, spellName = HasOnUseAbility(itemID)
            if hasOnUse then
                local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemID)
                trackableItems[slotID] = {
                    apiIdentifier = slotID,
                    trackingType = "equipped",
                    name = itemName,
                    iconTexturePath = itemTexture
                }
            end
        end
    end
    
    return trackableItems
end

-- ============================================================================
-- EXPORTS FOR SPELLBOOKHELPER
-- ============================================================================
Cooldowns.AddCustomEntry = AddCustomEntry
Cooldowns.customTrackerIcons = customTrackerIcons

-- Export to TUICD namespace so SpellbookHelper can find it
TUICD.Cooldowns = Cooldowns

-- ============================================================================
-- SHARED UI HELPER: Render Tracked Values List
-- ============================================================================
-- Used by both Entries tab and Individual Icons tab to render the same list
function Cooldowns.RenderTrackedValuesList(container, options)
    -- Clear ALL children of the container (not just tracked rows)
    -- This ensures old frames don't stick around
    local children = {container:GetChildren()}
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end
    
    -- Use local array for building rows (not exposed externally)
    local rows = {}
    
    -- Get tracked values from database
    local listTrackedValues = options.listTrackedValues
    if not listTrackedValues or #listTrackedValues == 0 then
        local noItems = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noItems:SetPoint("CENTER")
        noItems:SetText(options.emptyText or "No entries tracked")
        noItems:SetTextColor(0.5, 0.5, 0.5)
        rows[1] = noItems
        if options.scrollChild then
            options.scrollChild:SetHeight(90)
        end
        if options.onEmpty then
            options.onEmpty()
        end
        return
    end
    
    local rowY = -3
    local rowHeight = options.rowHeight or 21
    
    for slotIndex = 1, #listTrackedValues do
        local entry = listTrackedValues[slotIndex]
        if entry then
            -- Use data from database: trackingType, apiIdentifier, name, iconTexturePath
            local displayName = entry.name or "Unknown"
            local displayTexture = entry.defaultIconTexturePath

            -- Check if entry is enabled
            local isEnabled = entry.enabled ~= false  -- Default to true if not set
            
            -- Check if equipped slot has on-use ability
            local hasOnUse = true
            local isEmptySlot = false
            if entry.trackingType == "equipped" then
                local itemID = GetInventoryItemID("player", entry.apiIdentifier)
                if itemID then
                    hasOnUse = HasOnUseAbility(itemID)
                else
                    isEmptySlot = true
                end
            end
            
            
            local willDisplay = hasOnUse and not isEmptySlot
            
            local row = CreateFrame("Button", nil, container)
            row:SetPoint("TOPLEFT", 3, rowY)
            row:SetPoint("TOPRIGHT", -3, rowY)
            row:SetHeight(rowHeight - 2)
            
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.bg:SetColorTexture(0.2, 0.2, 0.2, 0.3)
            
            local slotLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            slotLabel:SetPoint("LEFT", 4, 0)
            slotLabel:SetText("#" .. slotIndex)
            slotLabel:SetTextColor(0.8, 0.8, 0.8)
            
            local iconPreview = row:CreateTexture(nil, "ARTWORK")
            iconPreview:SetPoint("LEFT", 22, 0)
            iconPreview:SetSize(18, 18)
            iconPreview:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if displayTexture then
                pcall(function() iconPreview:SetTexture(displayTexture) end)
            end
            if not willDisplay then
                iconPreview:SetDesaturated(true)
                iconPreview:SetAlpha(0.5)
            end
            
            -- Type indicator
            local typeChar
            if entry.trackingType == "spell" then
                typeChar = "|cff71d5ffS|r"  -- Blue for spell
            elseif entry.trackingType == "item" or entry.trackingType == "equipped" then
                typeChar = "|cffa335eeI|r"  -- Purple for item
            else
                typeChar = "|cff00ff00E|r"  -- Green for equipped
            end
            
            -- Build label with status indicators
            local labelText = displayName or "Loading..."
            if not isEnabled then
                labelText = "|cff666666[" .. typeChar .. "] " .. labelText .. "|r"
            elseif isEmptySlot then
                labelText = "|cff666666[" .. typeChar .. "] " .. labelText .. " |cffff6600(empty)|r|r"
            elseif not hasOnUse then
                labelText = "|cff666666[" .. typeChar .. "] " .. labelText .. "|r"
            else
                labelText = "[" .. typeChar .. "] " .. labelText
            end
            
            local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nameLabel:SetPoint("LEFT", 45, 0)
            nameLabel:SetPoint("RIGHT", -80, 0)
            nameLabel:SetJustifyH("LEFT")
            nameLabel:SetText(labelText)
            nameLabel:SetWordWrap(false)
            
            -- Show remove button (X) or enabled indicator based on options
            if options.removeEnabled then
                local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                removeBtn:SetPoint("RIGHT", -4, 0)
                removeBtn:SetSize(20, 18)
                removeBtn:SetText("X")
                removeBtn:SetScript("OnClick", function(self, button)
                    self:GetParent():SetScript("OnClick", nil)  -- Disable row click
                    -- Remove the entry
                    if entry then
                        TUICD.CooldownHighlights:RemoveTrackedValue(entry)
                        if TUICD.Cooldowns and TUICD.Cooldowns.FireTrackerListUpdate then
                            TUICD.Cooldowns.FireTrackerListUpdate()
                        end
                    end
                end)
                removeBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine("Remove Entry", 1, 1, 1)
                    GameTooltip:Show()
                end)
                removeBtn:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            else
                local enabledIndicator = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                enabledIndicator:SetPoint("RIGHT", -4, 0)
                enabledIndicator:SetText(isEnabled and "|cff00ff00On|r" or "|cff666666Off|r")
            end
            
            row.slotIndex = slotIndex
            row.entry = entry
            
            -- Click handler
            row:SetScript("OnClick", function(self)
                if options.onRowClick then
                    options.onRowClick(self, slotIndex, rows)
                end
            end)
            
            row:SetScript("OnEnter", function(self)
                if options.selectedSlot ~= slotIndex then
                    self.bg:SetColorTexture(0.25, 0.25, 0.3, 0.5)
                end
                -- Show tooltip with entry details
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(displayName, 1, 1, 1)
                GameTooltip:AddLine("Type: " .. (entry.trackingType or "Unknown"), 0.7, 0.7, 0.7)
                GameTooltip:AddLine("ID: " .. tostring(entry.apiIdentifier or "?"), 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            
            row:SetScript("OnLeave", function(self)
                if options.selectedSlot ~= slotIndex then
                    self.bg:SetColorTexture(0.2, 0.2, 0.2, 0.3)
                end
                GameTooltip:Hide()
            end)
            
            rows[#rows + 1] = row
            rowY = rowY - rowHeight
        end
    end
    
    -- Update scroll child height based on content
    local totalHeight = math.max(90, #rows * rowHeight + 6)
    if options.scrollChild then
        options.scrollChild:SetHeight(totalHeight)
    end
    
    -- Auto-select first slot if nothing selected
    if options.autoSelectFirst and not options.selectedSlot and #rows > 0 and rows[1].slotIndex then
        rows[1]:Click()
    end
end

-- ============================================================================
-- VISIBILITY SYSTEM
-- ============================================================================
-- Handles show/hide based on combat, group, instance conditions
-- Also handles show/hide based on visibility conditions

-- Visibility condition defaults

-- Get current player state for visibility checks
local function GetPlayerState()
    local state = {
        inCombat = InCombatLockdown() or UnitAffectingCombat("player"),
        inGroup = IsInGroup(),
        inRaid = IsInRaid(),
        inInstance = false,
        inArena = false,
        inBattleground = false,
        isSolo = not IsInGroup(),
        hasTarget = UnitExists("target"),
        isMounted = TUICD.UnitAPI and TUICD.UnitAPI:IsMountedOrTravelForm() or IsMounted(),
    }
    
    -- Check instance type
    local _, instanceType = IsInInstance()
    if instanceType == "party" or instanceType == "raid" then
        state.inInstance = true
    elseif instanceType == "arena" then
        state.inArena = true
    elseif instanceType == "pvp" then
        state.inBattleground = true
    end
    
    return state
end

-- ============================================================================
-- SETTINGS HUB
-- ============================================================================

function Cooldowns:CreateHub(parent)
    if cooldownHub then return cooldownHub end
    
    local hub = CreateFrame("Frame", "TweaksUI_Cooldowns_Hub", parent or UIParent, "BackdropTemplate")
    hub:SetSize(HUB_WIDTH, HUB_HEIGHT + 50)  -- Increased height for preset dropdown
    hub:SetBackdrop(darkBackdrop)
    hub:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    hub:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    hub:SetFrameStrata("DIALOG")
    hub:Hide()
    
    -- Title
    local title = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Cooldown Trackers")
    title:SetTextColor(1, 0.82, 0)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, hub, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        hub:Hide()
        self:HideAllPanels()
    end)
    
    -- Close all panels when hub is hidden
    hub:SetScript("OnHide", function()
        self:HideAllPanels()
    end)
    
    local yOffset = -38
    
    -- Add Preset Dropdown at the top
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
    
    -- Section label
    local sectionLabel = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sectionLabel:SetPoint("TOP", 0, yOffset)
    sectionLabel:SetText("|cff888888Blizzard Trackers|r")
    yOffset = yOffset - 16
    
    -- Buff Tracker button
    local buffBtn = CreateFrame("Button", nil, hub, "UIPanelButtonTemplate")
    buffBtn:SetSize(HUB_WIDTH - 30, BUTTON_HEIGHT)
    buffBtn:SetPoint("TOP", 0, yOffset)
    buffBtn:SetText("Buff Tracker")
    buffBtn:SetScript("OnClick", function()
        self:TogglePanel("buffs")
    end)
    yOffset = yOffset - BUTTON_HEIGHT - BUTTON_SPACING
    
    yOffset = yOffset - 6
    
    -- Custom Trackers section label
    local customLabel = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    customLabel:SetPoint("TOP", 0, yOffset)
    customLabel:SetText("|cff888888Custom Trackers|r")
    yOffset = yOffset - 16
    
    -- Custom Trackers button
    -- local customBtn = CreateFrame("Button", nil, hub, "UIPanelButtonTemplate")
    -- customBtn:SetSize(HUB_WIDTH - 30, BUTTON_HEIGHT)
    -- customBtn:SetPoint("TOP", 0, yOffset)
    -- customBtn:SetText("Custom Trackers")
    -- customBtn:SetScript("OnClick", function()
    --     self:TogglePanel("customTrackers")
    -- end)
    -- yOffset = yOffset - BUTTON_HEIGHT - BUTTON_SPACING
    
    yOffset = yOffset - 6
    
    -- Dynamic Docks section label
    local docksLabel = hub:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    docksLabel:SetPoint("TOP", 0, yOffset)
    docksLabel:SetText("|cff888888Dynamic Docks|r")
    yOffset = yOffset - 16
    
    -- Dynamic Docks button
    local docksBtn = CreateFrame("Button", nil, hub, "UIPanelButtonTemplate")
    docksBtn:SetSize(HUB_WIDTH - 30, BUTTON_HEIGHT)
    docksBtn:SetPoint("TOP", 0, yOffset)
    docksBtn:SetText("Dock Settings")
    docksBtn:SetScript("OnClick", function()
        self:ToggleDocksPanel()
    end)
    docksBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Dynamic Docks", 1, 1, 1)
        GameTooltip:AddLine("Group icons from any tracker into custom containers", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    docksBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    yOffset = yOffset - BUTTON_HEIGHT - BUTTON_SPACING
    
    -- Register with GlobalScale for settings scaling
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

-- Toggle the cooldowns settings panel (called from main Settings hub)
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
    self:HideDocksPanel()
    if cooldownHub then cooldownHub:Hide() end
end

-- Hide just the tracker settings panels (not hub or docks)
function Cooldowns:HideTrackerPanels()
    for _, panel in pairs(settingsPanels) do
        if panel then panel:Hide() end
    end
end

function Cooldowns:TogglePanel(trackerKey)
    -- Hide other panels
    for key, panel in pairs(settingsPanels) do
        if panel and key ~= trackerKey then
            panel:Hide()
        end
    end
    -- Also hide Docks panel when opening tracker settings
    self:HideDocksPanel()
    
    if settingsPanels[trackerKey] then
        if settingsPanels[trackerKey]:IsShown() then
            settingsPanels[trackerKey]:Hide()
        else
            settingsPanels[trackerKey]:Show()
        end
    else
        -- Create the appropriate panel
        if trackerKey == "customTrackers" then
            --self:CreateCustomTrackersPanel()
        else
            self:CreateTrackerPanel(trackerKey)
        end
        if settingsPanels[trackerKey] then
            settingsPanels[trackerKey]:Show()
        end
    end
end
-- ============================================================================
-- TRACKER SETTINGS PANEL
-- ============================================================================


function Cooldowns:CreateTrackerPanel(trackerKey)
    local panel = CreateFrame("Frame", "TweaksUI_Cooldowns_" .. trackerKey .. "_Panel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetPoint("TOPLEFT", cooldownHub, "TOPRIGHT", 0, 0)
    panel:SetBackdrop(darkBackdrop)
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetFrameStrata("DIALOG")
    
    settingsPanels[trackerKey] = panel
    
    -- Register with GlobalScale for settings scaling
    if TUICD.GlobalScale then
        TUICD.GlobalScale:RegisterSettingsPanel(panel, 1.0)
    end
    
    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Buff Tracker")
    title:SetTextColor(1, 0.82, 0)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        panel:Hide()
    end)
    
    -- Content frame (no tabs needed - only one view)
    local content = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    content:SetPoint("TOPLEFT", 10, -45)
    content:SetPoint("BOTTOMRIGHT", -28, 10)
    Cooldowns.SetConsistentScrollingBehavior(content)
    
    local scrollChild = CreateFrame("Frame", nil, content)
    scrollChild:SetSize(PANEL_WIDTH - 50, 800)
    content:SetScrollChild(scrollChild)

    
    -- Helper function to determine tracker type for a given uniqueID
    local function getTrackerTypeForID(uniqueID)
        for _, trackerType in ipairs({"buffs", "essential", "utility"}) do
            if TUICD.FrameTrackerManager:CheckIsAlreadyTracker(uniqueID, trackerType) then
                return trackerType
            end
        end
        return "buffs" -- fallback default
    end
    
    -- Build content directly (no tabs needed)
    local config = {
        type = "buffs",
        sharedState = {},  -- Shared state for controls to communicate
        listTrackedValues = function() return TUICD.FrameTrackerManager:getTrackerValuesListForSettings("buffs") end,
        getCurrentEntryConfig = function(uniqueID) 
            local trackerType = getTrackerTypeForID(uniqueID)
            return TUICD.FrameTrackerManager:GetSpecificTrackerValue(uniqueID, trackerType) 
        end,
        setValue = function(uniqueID, path, value) 
            local trackerType = getTrackerTypeForID(uniqueID)
            TUICD.FrameTrackerManager:SetTrackerValueConfigProperty(uniqueID, trackerType, path, value) 
        end,
        getValue = function(uniqueID, path) 
            local trackerType = getTrackerTypeForID(uniqueID)
            return TUICD.FrameTrackerManager:GetTrackerValueConfigProperty(uniqueID, trackerType, path) 
        end
    }
    config.configInputs = Cooldowns:GetIconConfigInputs(config)
    Cooldowns:BuildPerIconTab(scrollChild, config)
    
    panel:Show()
end

-- =====================================================================
-- INPUT FACTORY METHODS
-- =====================================================================

-- Creates: Label + Text Input (EditBox)
-- Returns: label frame (for anchoring next control)
local function CreateTextInput(parent, config, anchor)
    config = config or {}
    
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetText(config.label)
    label:SetTextColor(0.8, 0.8, 0.8)
    label:SetPoint(config.anchorPoint or "TOPLEFT", anchor, config.relativePoint or "BOTTOMLEFT", config.offsetX or 0, config.offsetY or -15)
    
    local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    input:SetPoint("LEFT", label, "RIGHT", 10, 0)
    input:SetSize(config.width or 50, 18)
    input:SetAutoFocus(false)
    input:SetMaxLetters(config.maxLetters or 1000)
    
    -- Don't use SetNumeric - it blocks decimal points
    -- We'll validate manually in the OnEnterPressed/OnEditFocusLost handlers
    input:SetText(tostring(config:getValue()))
    
    config.min = config.min or 0
    config.max = config.max or 5000
    input:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local value = config.numeric and tonumber(self:GetText()) or self:GetText()
        if config.numeric then
            -- Validate and clamp numeric input
            if not value then
                value = config.min or 0
            end
            value = math.max(config.min, math.min(config.max, value))
            self:SetText(tostring(value))
        end
        config:setValue(value)
    end)
    input:SetScript("OnEditFocusLost", function(self)
        local value = config.numeric and tonumber(self:GetText()) or self:GetText()
        if config.numeric then
            -- Validate and clamp numeric input (respects config.clamp for backward compatibility)
            if not value then
                value = config.min or 0
            end
            value = math.max(config.min, math.min(config.max, value))
            self:SetText(tostring(value))
        end
        config:setValue(value)
    end)
    
    return label, input
end

-- Returns: label frame (for anchoring next control)
local function CreateDropdown(parent, config, anchor)
    config = config or {}
    
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetText(config.label)
    label:SetTextColor(0.8, 0.8, 0.8)
    
    label:SetPoint(config.anchorPoint or "TOPLEFT", anchor, config.relativePoint or "BOTTOMLEFT", config.offsetX or 0, config.offsetY or -15)
    
    local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", label, "RIGHT", -10, 0)
    UIDropDownMenu_SetWidth(dropdown, config.width or 140)
    
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        for _, opt in ipairs(config.options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.value = opt.value
            info.func = function()
                config:setValue(opt.value)
                UIDropDownMenu_SetText(dropdown, opt.label)
            end
            info.checked = (config:getValue() == opt.value)
            UIDropDownMenu_AddButton(info, level)
        end
    end)
        
    -- Set initial text from current value
    local currentValue = config:getValue()
    for _, opt in ipairs(config.options) do
        if opt.value == currentValue then
            UIDropDownMenu_SetText(dropdown, opt.label)
            break
        end
    end
    
    return label, dropdown
end

local function CreateColorPicker(parent, config, anchor)
    config = config or {}

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetText(config.label)
    label:SetTextColor(0.8, 0.8, 0.8)
    label:SetPoint(config.anchorPoint or "TOPLEFT", anchor, config.relativePoint or "BOTTOMLEFT", config.offsetX or 0, config.offsetY or -10)
    
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetPoint("LEFT", label, "RIGHT", 10, 0)
    btn:SetSize(24, 16)
    btn:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1})
    local color = config:getValue()
    btn:SetBackdropColor(color.r, color.g, color.b, color.a or 1)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    btn:SetScript("OnClick", function()
        local currentColor = config:getValue()
        local r, g, b, a = currentColor.r or 1, currentColor.g or 1, currentColor.b or 1, currentColor.a or 1
        
        local info = {
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                local na = ColorPickerFrame:GetColorAlpha() or 1
                btn:SetBackdropColor(nr, ng, nb, na)
                config:setValue({r = nr, g = ng, b = nb, a = na})
            end,
            opacityFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                local na = ColorPickerFrame:GetColorAlpha() or 1
                btn:SetBackdropColor(nr, ng, nb, na)
                config:setValue({r = nr, g = ng, b = nb, a = na})
            end or nil,
            cancelFunc = function(prev)
                btn:SetBackdropColor(prev.r, prev.g, prev.b, prev.a or 1)
                config:setValue({r = prev.r, g = prev.g, b = prev.b, a = prev.a or 1})
            end,
            opacity = a,
            r = r,
            g = g,
            b = b,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)
    
    return label, btn
end

local function CreateCheckbox(parent, config, anchor)
    config = config or {}
    
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetSize(24, 24)
    checkbox:SetPoint(config.anchorPoint or "TOPLEFT", anchor, config.relativePoint or "BOTTOMLEFT", config.offsetX or 0, config.offsetY or -5)
    
    checkbox:SetChecked(config:getValue())
    -- checkbox:Hide()
    
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
    label:SetText(config.label)
    label:SetTextColor(0.8, 0.8, 0.8)
    -- label:Hide()
    
    if config.setValue then
        checkbox:SetScript("OnClick", function(self)
            config:setValue(self:GetChecked())
        end)
    end
    
    return checkbox, label
end

-- Creates: Label + Position Shift Buttons (4 arrow buttons)
-- Returns: label frame (for anchoring next control)
local function CreatePositionButtons(parent, config, anchor)
    -- config: { onUp, onDown, onLeft, onRight, anchorTo, anchorPoint, relativePoint, offsetX, offsetY, hidden }
    config = config or {}
    
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetText(config.label)
    label:SetTextColor(0.8, 0.8, 0.8)
    
    
    label:SetPoint(config.anchorPoint or "TOPLEFT", anchor, config.relativePoint or "BOTTOMLEFT", config.offsetX or 0, config.offsetY or -25)
    
    local leftBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    leftBtn:SetPoint("LEFT", label, "RIGHT", 4, 0)
    leftBtn:SetSize(60, 20)
    leftBtn:SetText("left")
    leftBtn:SetScript("OnClick", function () config:setValue("x", -1) end)

    local upBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    upBtn:SetPoint("BOTTOM", leftBtn, "TOP", 30, 4)
    upBtn:SetSize(60, 20)
    upBtn:SetText("up")
    upBtn:SetScript("OnClick", function () config:setValue("y", 1) end)
    
    
    local downBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    downBtn:SetPoint("TOP", leftBtn, "BOTTOM", 30, -4)
    downBtn:SetSize(60, 20)
    downBtn:SetText("down")
    downBtn:SetScript("OnClick", function () config:setValue("y", -1) end)
    
    local rightBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    rightBtn:SetPoint("LEFT", leftBtn, "RIGHT", 4, 0)
    rightBtn:SetSize(60, 20)
    rightBtn:SetText("right")
    rightBtn:SetScript("OnClick", function () config:setValue("x", 1) end)
    
    return label, upBtn, downBtn, leftBtn, rightBtn
end

local function CreateButton(parent, config, anchor)
    config = config or {}
    
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetText(config.label or "")
    label:SetTextColor(0.8, 0.8, 0.8)
    label:SetPoint(config.anchorPoint or "TOPLEFT", anchor, config.relativePoint or "BOTTOMLEFT", config.offsetX or 0, config.offsetY or -25)
    
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetPoint("LEFT", label, "RIGHT", 4, 0)
    btn:SetSize(config.width or 100, config.height or 24)
    btn:SetText(config.buttonText or "Button")
    
    if config.onClick then
        btn:SetScript("OnClick", function()
            config:onClick()
        end)
    end
    
    return label, btn
end

local function CreateLabel(parent, config, anchor)
    config = config or {}
    
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetText(config.label or "")
    label:SetTextColor(0.8, 0.8, 0.8)
    label:SetPoint(config.anchorPoint or "TOPLEFT", anchor, config.relativePoint or "BOTTOMLEFT", config.offsetX or 0, config.offsetY or -10)
    
    local valueLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valueLabel:SetPoint("LEFT", label, "RIGHT", 4, 0)
    valueLabel:SetTextColor(1, 1, 0.5)
    
    if config.getValue then
        valueLabel:SetText(config:getValue() or "")
    end
    
    -- Store reference for potential updates
    label.valueLabel = valueLabel
    
    return label, valueLabel
end

--[[ =====================================================================
    CONFIG INPUT DEFINITIONS

    This is used by both buffs, custom icons, and docks
-- =====================================================================]]

function Cooldowns:GetIconConfigInputs(config)
    local RADIAL_DISPLAY_OPTIONS = {}
    if config.type == 'buffs' then
        RADIAL_DISPLAY_OPTIONS = {
            { label = "Show Always", value = "always" },
            { label = "Show when active", value = "active" },
            { label = "Show when inactive", value = "inactive" },
            { label = "Show Never", value = "never" },
        }
    elseif config.type == 'customIcons' then
        RADIAL_DISPLAY_OPTIONS = {
            { label = "Show Always", value = "always" },
            { label = "Show Only on Cooldown", value = "cooldown" },
            { label = "Show Only when Available", value = "available" },
            { label = "Show Never", value = "never" },
        }
    end
    
    return {
        -- Icon settings
        {
            type = "header",
            text = "|cffffcc00Icon Settings|r",
            state = 'expanded',
            sectionContent = { -- Icon Display State
                {
                    type = "dropdown",
                    label = "Icon Display State:",
                    options = RADIAL_DISPLAY_OPTIONS,
                    getValue = function(self) return config.getValue(self.uniqueID, "iconDisplayState") or "always" end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "iconDisplayState", value) end,
                },
                -- Texture Path
                {
                    type = "textinput",
                    label = "Custom Texture Path:",
                    width = 250,
                    getValue = function(self) return config.getValue(self.uniqueID, "iconTexturePath") or "" end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "iconTexturePath", value) end,
                },
                -- Icon Color
                {
                    type = "colorpicker",
                    label = "Icon Color:",
                    getValue = function(self) return config.getValue(self.uniqueID, "iconColor") or {r=1, g=1, b=1, a=1} end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "iconColor", value) end,
                },
                -- Position Buttons
                {
                    type = "positionbuttons",
                    label = "Shift Position:",
                    getValue = function(self) 
                        local x = config.getValue(self.uniqueID, "position.x") or 0
                        local y = config.getValue(self.uniqueID, "position.y") or 0
                        return x, y
                    end,
                    setValue = function(self, axis, value)
                        local oldValueX, oldValueY = self:getValue()
                        local newValue = 0
                        if axis == 'y' then newValue = oldValueY + value end
                        if axis == 'x' then newValue = oldValueX + value end
                        
                        config.setValue(self.uniqueID, "position." .. axis, newValue)
                    end,
                },
                -- Size
                {
                    type = "textinput",
                    label = "Size:",
                    numeric = true,
                    getValue = function(self) return config.getValue(self.uniqueID, "size") or 48 end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "size", value) end,
                },
                -- Opacity
                {
                    type = "textinput",
                    label = "Opacity:",
                    numeric = true,
                    max = 1,
                    min = 0,
                    getValue = function(self) return config.getValue(self.uniqueID, "opacity") or 1.0 end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "opacity", value) end,
                },
                -- Desaturate
                {
                    type = "checkbox",
                    label = "Desaturate when on cooldown",
                    getValue = function(self) return config.getValue(self.uniqueID, "desaturated") or false end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "desaturated", value) end,
                },
                -- Hide Default Swipe
                {
                    type = "checkbox",
                    label = "Hide default swipe animation",
                    getValue = function(self) return config.getValue(self.uniqueID, "cooldownText.hideDefaultSweep") == true end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "cooldownText.hideDefaultSweep", value) end,
                }
            }
        },
        
        -- Section Header: Radial Swipe
        {
            type = "header",
            text = "|cff00ccffRadial Swipe|r",
            state = 'collapsed',
            section = {
                -- Radial Display State
                {
                    type = "dropdown",
                    label = "Display State:",
                    options = RADIAL_DISPLAY_OPTIONS,
                    getValue = function(self) return config.getValue(self.uniqueID, "radialSwipe.displayState") or "always" end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "radialSwipe.displayState", value) end,
                },
                -- Radial Texture
                {
                    type = "textinput",
                    label = "Custom Texture Path:",
                    width = 250,
                    getValue = function(self) return config.getValue(self.uniqueID, "radialSwipe.iconTexturePath") or "" end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "radialSwipe.iconTexturePath", value) end,
                },
                -- Radial Color
                {
                    type = "colorpicker",
                    label = "Color:",
                    getValue = function(self) return config.getValue(self.uniqueID, "radialSwipe.color") or {r=1, g=1, b=1, a=1} end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "radialSwipe.color", value) end,
                },
                -- Radial Scale
                {
                    type = "textinput",
                    label = "Scale:",
                    getValue = function(self) return config.getValue(self.uniqueID, "radialSwipe.scale") or 1.0 end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "radialSwipe.scale", value) end,
                },
                -- Radial Position Buttons
                {
                    type = "positionbuttons",
                    label = "Shift Position:",
                    getValue = function(self) 
                        local x = config.getValue(self.uniqueID, "radialSwipe.x") or 0
                        local y = config.getValue(self.uniqueID, "radialSwipe.y") or 0
                        return x, y
                    end,
                    setValue = function(self, axis, value)
                        local oldValueX, oldValueY = self:getValue()
                        local newValue = 0
                        if axis == 'y' then newValue = oldValueY + value end
                        if axis == 'x' then newValue = oldValueX + value end
                        
                        config.setValue(self.uniqueID, "radialSwipe." .. axis, newValue)
                    end,
                },
                -- Radial Rotation
                {
                    type = "textinput",
                    label = "Rotate Texture (degrees):",
                    numeric = true,
                    offsetY = -40,
                    getValue = function(self) return config.getValue(self.uniqueID, "radialSwipe.rotation") or 0 end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "radialSwipe.rotation", value) end,
                },
            }
        },
        
        -- Section Header: Dock Assignment
        {
            type = "header",
            text = "Dock Assignment",
            state = 'collapsed',
            section = {
                -- Dock Assignment Dropdown
                {
                    type = "dropdown",
                    label = "Assign to Dock:",
                    options = function(self)
                        -- Get dock options from NewDocks module
                        if TUICD.NewDocks and TUICD.NewDocks.GetDockDropdownOptions then
                            return TUICD.NewDocks:GetDockDropdownOptions()
                        end
                        return {{ label = "None", value = false }}
                    end,
                    getValue = function(self) 
                        return config.getValue(self.uniqueID, "dock.assignedDock") or false
                    end,
                    setValue = function(self, value)
                        config.setValue(self.uniqueID, "dock.assignedDock", value)
                    end,
                },
                -- Layout Mode (for future use)
                {
                    type = "dropdown",
                    label = "Layout Mode:",
                    options = {
                        { label = "Uncontrolled (Group Only)", value = "uncontrolled" },
                        { label = "Controlled (Dock Manages)", value = "controlled", disabled = true }
                    },
                    getValue = function(self)
                        local dockInfo = config.getValue(self.uniqueID, "dock")
                        if dockInfo and dockInfo.layoutMode then
                            return dockInfo.layoutMode
                        end
                        return "uncontrolled"
                    end,
                    setValue = function(self, value)
                        config.setValue(self.uniqueID, "dock.layoutMode", value)
                    end,
                },
            }
        },
        
        -- Section Header: Cooldown Text
        {
            type = "header",
            text = "Cooldown Text",
            state = 'collapsed',
            section = {
                -- Cooldown Text Display
                {
                    type = "checkbox",
                    label = "Display Cooldown Text",
                    getValue = function(self) return config.getValue(self.uniqueID, "cooldownText.display") or false end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "cooldownText.display", value) end,
                },
                -- Cooldown Text Size
                {
                    type = "textinput",
                    label = "Size:",
                    numeric = true,
                    getValue = function(self) return config.getValue(self.uniqueID, "cooldownText.size") or 14 end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "cooldownText.size", value) end,
                },
                -- Cooldown Text Color
                {
                    type = "colorpicker",
                    label = "Color:",
                    getValue = function(self) return config.getValue(self.uniqueID, "cooldownText.color") or {r=1, g=1, b=1, a=1} end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "cooldownText.color", value) end,
                },
                -- Cooldown Text Offset X
                {
                    type = "textinput",
                    label = "Offset X:",
                    numeric = true,
                    getValue = function(self) return config.getValue(self.uniqueID, "cooldownText.x") or 0 end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "cooldownText.x", value) end,
                },
                -- Cooldown Text Offset Y
                {
                    type = "textinput",
                    label = "Offset Y:",
                    numeric = true,
                    getValue = function(self) return config.getValue(self.uniqueID, "cooldownText.y") or 0 end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "cooldownText.y", value) end,
                },
            }
        },
        
        -- Section Header: Count Text
        {
            type = "header",
            text = "Count/Charge Text",
            state = 'collapsed',
            section = {
                -- Count Text Display
                {
                    type = "checkbox",
                    label = "Display Charge/Count Text",
                    getValue = function(self) return config.getValue(self.uniqueID, "countText.display") or false end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "countText.display", value) end,
                },
                -- Count Text Size
                {
                    type = "textinput",
                    label = "Size:",
                    numeric = true,
                    getValue = function(self) return config.getValue(self.uniqueID, "countText.size") or 14 end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "countText.size", value) end,
                },
                -- Count Text Color
                {
                    type = "colorpicker",
                    label = "Color:",
                    getValue = function(self) return config.getValue(self.uniqueID, "countText.color") or {r=1, g=1, b=1, a=1} end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "countText.color", value) end,
                },
                -- Count Text Offset X
                {
                    type = "textinput",
                    label = "Offset X:",
                    numeric = true,
                    getValue = function(self) return config.getValue(self.uniqueID, "countText.x") or 0 end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "countText.x", value) end,
                },
                -- Count Text Offset Y
                {
                    type = "textinput",
                    label = "Offset Y:",
                    numeric = true,
                    getValue = function(self) return config.getValue(self.uniqueID, "countText.y") or 0 end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "countText.y", value) end,
                },
        -- Section Header: Custom Label
            }
        },
        
        {
            type = "header",
            text = "Custom Label (Accessibility)",
            state = 'collapsed',
            section = {
                -- Label Enable
                {
                    type = "checkbox",
                    label = "Show Custom Label",
                    getValue = function(self) return config.getValue(self.uniqueID, "customLabel.display") or false end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "customLabel.display", value) end,
                },
                -- Label Text
                {
                    type = "textinput",
                    label = "Text:",
                    getValue = function(self) return config.getValue(self.uniqueID, "customLabel.text") or "" end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "customLabel.text", value) end,
                },
                -- Label Size
                {
                    type = "textinput",
                    label = "Font Size:",
                    numeric = true,
                    getValue = function(self) return config.getValue(self.uniqueID, "customLabel.size") or 14 end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "customLabel.size", value) end,
                },
                -- Label Color
                {
                    type = "colorpicker",
                    label = "Color:",
                    getValue = function(self) return config.getValue(self.uniqueID, "customLabel.color") or {r=1, g=1, b=1, a=1} end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "customLabel.color", value) end,
                },
                -- Label Offset X
                {
                    type = "textinput",
                    label = "Offset X:",
                    numeric = true,
                    getValue = function(self) return config.getValue(self.uniqueID, "customLabel.x") or 0 end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "customLabel.x", value) end,
                },
                -- Label Offset Y
                {
                    type = "textinput",
                    label = "Offset Y:",
                    numeric = true,
                    getValue = function(self) return config.getValue(self.uniqueID, "customLabel.y") or 0 end,
                    setValue = function(self, value) config.setValue(self.uniqueID, "customLabel.y", value) end,
                },
            }
        },
        
        -- Copy Settings Section
        --[[
            PATTERN FOR INTERDEPENDENT CONTROLS:
            This section demonstrates how to create controls that update in response to each other.
            
            Key concepts:
            1. Store shared data in config.sharedState (accessible to all controls)
            2. When a control changes a shared value, it triggers RenderControlsForSelection(self.uniqueID)
            3. Re-rendering destroys and recreates all controls, so all getValue() calls execute fresh
            4. This automatically refreshes any controls that depend on shared state
            
            To add new interdependent controls:
            - Store the value in config.sharedState in your setValue function
            - Call RenderControlsForSelection(self.uniqueID) after updating shared state
            - Other controls can read from config.sharedState in their getValue functions
            - No need to manually store widget references or call update methods
            
            Example:
                setValue = function(self, value)
                    config.sharedState.myValue = value
                    RenderControlsForSelection(self.uniqueID)  -- Triggers refresh
                end,
                
                getValue = function(self)
                    return config.sharedState.myValue or "default"
                end,
        ]]
        {
            type = "header",
            text = "Copy Settings to Another Icon",
            state = "collapsed",
            section = {
                {
                    type = "dropdown",
                    label = "Target Icon:",
                    sharedState = "copySettings_target",  -- Shared state key for this section
                    getOptions = function(self)
                        local options = {}
                        
                        local trackedValues = config.listTrackedValues()
                        for _, entry in ipairs(trackedValues) do
                            -- Don't include the current icon in the list
                            if entry.uniqueID ~= self.uniqueID then
                                table.insert(options, {
                                    value = entry.uniqueID,
                                    label = entry.name or tostring(entry.uniqueID)
                                })
                            end
                        end
                        return options
                    end,
                    getValue = function(self)
                        return nil  -- Always start fresh
                    end,
                    setValue = function(self, value)
                        -- Store in shared state accessible to other controls
                        if not config.sharedState then
                            config.sharedState = {}
                        end
                        config.sharedState.copySettings_target = value
                        
                        -- Trigger re-render to update all dependent controls
                        -- This refreshes the label and any other controls that read from shared state
                        if self.uniqueID and config.RenderControlsForSelection then
                            config.RenderControlsForSelection(self.uniqueID)
                        end
                    end,
                },
                {
                    type = "label",
                    label = "Selected:",
                    sharedState = "copySettings_target",
                    getValue = function(self)
                        -- Read from shared state
                        if config.sharedState and config.sharedState.copySettings_target then
                            local selectedTarget = config.sharedState.copySettings_target
                            local trackedValues = config.listTrackedValues()
                            for _, entry in ipairs(trackedValues) do
                                if entry.uniqueID == selectedTarget then
                                    return entry.name or tostring(selectedTarget)
                                end
                            end
                            return tostring(selectedTarget)
                        end
                        return "None"
                    end,
                },
                {
                    type = "button",
                    label = "",
                    buttonText = "Copy Settings",
                    width = 120,
                    sharedState = "copySettings_target",
                    onClick = function(self)
                        -- Get the target from shared state
                        local targetID = config.sharedState and config.sharedState.copySettings_target
                        
                        if not targetID then
                            TUICD:Print("|cffff0000Error:|r Please select a target icon")
                            return
                        end
                        
                        -- Get the source config (current icon)
                        -- local sourceConfig = TUICD.CooldownHighlights:GetTrackedValue(self.uniqueID)
                        -- if not sourceConfig then
                        --     TUICD:Print("|cffff0000Error:|r Could not get source config")
                        --     return
                        -- end
                        
                        -- -- Apply config to target
                        -- TUICD.CooldownHighlights:ApplyPreexistingSpellConfig(targetID, sourceConfig)
                        
                        -- -- Show success message
                        -- local targetName = "Unknown"
                        -- local trackedValues = config.listTrackedValues()
                        -- for _, entry in ipairs(trackedValues) do
                        --     if entry.uniqueID == targetID then
                        --         targetName = entry.name or tostring(targetID)
                        --         break
                        --     end
                        -- end
                        -- TUICD:Print("|cff00ff00Settings copied to:|r " .. targetName)
                        
                        -- -- Clear the selection after copying
                        -- if config.sharedState then
                        --     config.sharedState.copySettings_target = nil
                        -- end
                    end,
                },
            }
        },
        
    }
end

function Cooldowns:BuildPerIconTab(parent, config)
    local y = -10
    local selectedSlot = nil

    -- Track expanded/collapsed state for each section
    -- This persists across rerenders so sections stay open/closed
    local sectionStates = {}  -- [sectionIndex] = "expanded" or "collapsed"
    
    -- Header
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 5, y)
    header:SetText("Individual Icons")
    header:SetTextColor(1, 0.82, 0)
    
    -- Description
    local description = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    description:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
    description:SetJustifyH("LEFT")
    description:SetText("|cff888888Create individual icons for your abilities that can be configured and moved outside of the main trackers.|r")
    y = y - 18
    
    -- Slot list container
    local listContainer = CreateFrame("Frame", "TweaksCD_perIcon_ListContainer", parent, "BackdropTemplate")
    listContainer:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -10)
    listContainer:SetSize(PANEL_WIDTH - 60, 90)
    listContainer:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    listContainer:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    listContainer:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    -- Create scroll frame inside list container
    local scrollFrame = CreateFrame("ScrollFrame", "TweaksCD_perIcon_ScrollFrame", listContainer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -22, 2)
    Cooldowns.SetConsistentScrollingBehavior(scrollFrame)
    
    local scrollChild = CreateFrame("Frame", "TweaksCD_perIcon_ScrollChild", scrollFrame)
    scrollChild:SetWidth(PANEL_WIDTH - 84)
    scrollChild:SetHeight(1)  -- Will be updated dynamically
    scrollFrame:SetScrollChild(scrollChild)
    
    y = y - 100
    
    -- Controls panel (no container, no scrolling - dynamically sized)
    local controlsPanel = CreateFrame("Frame", "TweaksCD_perIcon_ControlsPanel", parent, "BackdropTemplate")
    controlsPanel:SetPoint("TOPLEFT", scrollFrame, "BOTTOMLEFT", 0, -20)
    controlsPanel:SetSize(PANEL_WIDTH - 60, 100)  -- Width matches listContainer, height will be updated dynamically
    controlsPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    controlsPanel:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
    controlsPanel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    -- Height will be set dynamically based on content
    
    -- "No Selection" label (on panel, centered)
    local noSelectionLabel = controlsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    noSelectionLabel:SetPoint("CENTER", controlsPanel, "TOP", 0, -200)
    noSelectionLabel:SetText("Select an icon above to configure")
    noSelectionLabel:SetTextColor(0.5, 0.5, 0.5)
    
    -- =====================================================================
    -- RENDER CONTROLS FOR SELECTION (Destroy & Recreate Pattern)
    -- =====================================================================
    local function RenderControlsForSelection(uniqueID)
        Cooldowns:RenderConfigControls({
            parent = controlsPanel,
            config = config,
            sectionStates = sectionStates,
            getContextData = function()
                if not uniqueID then return nil end
                local trackedValue = config.getCurrentEntryConfig(uniqueID)
                if not trackedValue then return nil end
                return {
                    uniqueID = uniqueID,
                    trackedValue = trackedValue
                }
            end,
            showNoSelection = function()
                noSelectionLabel:Show()
                controlsPanel:SetHeight(400)
            end,
            hideNoSelection = function()
                noSelectionLabel:Hide()
            end,
            getHeaderText = function(data)
                return data.trackedValue.name or data.uniqueID
            end,
            renderCustomHeader = function(container, lastControl, data)
                -- Icon Preview
                local iconPreview = container:CreateTexture(nil, "ARTWORK")
                iconPreview:SetPoint("LEFT", lastControl, "RIGHT", 10, 0)
                iconPreview:SetSize(20, 20)
                iconPreview:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                
                local previewTexture = data.trackedValue.iconTexturePath
                if not previewTexture or previewTexture == "" then
                    previewTexture = data.trackedValue.defaultIconTexturePath
                end
                if previewTexture and previewTexture ~= "" then
                    pcall(function() iconPreview:SetTexture(previewTexture) end)
                end
                
                return lastControl  -- Keep header as last control for anchoring
            end,
            setContextOnControl = function(controlDef, data)
                controlDef.uniqueID = data.uniqueID
            end,
            onRerender = function()
                RenderControlsForSelection(uniqueID)
            end,
        })
    end
    
    -- Make RenderControlsForSelection accessible to controls via config
    config.RenderControlsForSelection = RenderControlsForSelection
    
    -- Initial render (no selection)
    RenderControlsForSelection(nil)

    local function RenderTrackedList()
        Cooldowns.RenderTrackedValuesList(scrollChild, {
            listTrackedValues = config.listTrackedValues(),        
            scrollChild = scrollChild,
            selectedSlot = selectedSlot,
            rowHeight = 21,
            autoSelectFirst = true,
            emptyText = "No entries tracked",
            onEmpty = function()
                RenderControlsForSelection(nil)
            end,
            onRowClick = function(row, slotIndex, rows)
                selectedSlot = slotIndex
                for _, r in ipairs(rows) do
                    if r.bg then r.bg:SetColorTexture(0.2, 0.2, 0.2, 0.3) end
                end
                row.bg:SetColorTexture(0.3, 0.5, 0.3, 0.6)
                -- Get uniqueID from entry
                local entry = row.entry
                if entry and entry.uniqueID then
                    RenderControlsForSelection(entry.uniqueID)
                end
            end
        })
    end
    
    -- Register callback for tracker list updates
    RegisterTrackerListUpdateCallback(RenderTrackedList)
    
    -- Initial population
    C_Timer.After(0.1, RenderTrackedList)
    
    parent:SetHeight(math.abs(y) + 370)
end

-- ============================================================================
-- GENERIC CONFIG CONTROL RENDERER
-- Shared rendering logic for all config panels (icons, buffs, docks)
-- ============================================================================

function Cooldowns:RenderConfigControls(options)
    --[[
        options = {
            parent = frame,                    -- Parent frame to render into
            config = config,                   -- Config object with configInputs
            sectionStates = {},                -- Table to persist expand/collapse state
            getContextData = function() end,   -- Optional: Returns context data or nil to not render
            showNoSelection = function() end,  -- Optional: Called when getContextData returns nil
            hideNoSelection = function() end,  -- Optional: Called before rendering
            getHeaderText = function(data) end, -- Returns header text string
            renderCustomHeader = function(container, lastControl, data) end, -- Optional: render custom elements, returns last control
            setContextOnControl = function(controlDef, data) end, -- Sets context fields on each control
            onRerender = function() end,       -- Called when section is toggled
        }
    ]]
    
    local parent = options.parent
    local config = options.config
    local sectionStates = options.sectionStates or {}
    
    -- Destroy old controls container
    if parent.currentControlsContainer then
        parent.currentControlsContainer:Hide()
        parent.currentControlsContainer:SetParent(nil)
        parent.currentControlsContainer = nil
    end
    
    -- Get context data (e.g., selected icon's uniqueID and tracked value)
    local contextData = nil
    if options.getContextData then
        contextData = options.getContextData()
        if not contextData then
            -- No valid context - show "no selection" state
            if options.showNoSelection then
                options.showNoSelection()
            end
            return
        end
    end
    
    -- Hide "no selection" label if it exists
    if options.hideNoSelection then
        options.hideNoSelection()
    end
    
    -- Create fresh controls container
    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()
    parent.currentControlsContainer = container
    
    -- Build controls
    local lastControl = nil
    
    -- Render main header
    if options.getHeaderText then
        local header = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", 10, -10)
        header:SetText(options.getHeaderText(contextData))
        header:SetTextColor(1, 0.82, 0)
        lastControl = header
    end
    
    -- Render custom header elements (e.g., icon preview)
    if options.renderCustomHeader then
        lastControl = options.renderCustomHeader(container, lastControl, contextData)
    end
    
    -- Validate config inputs
    if not config.configInputs then
        print("ERROR: config.configInputs is nil")
        return
    end
    
    -- Loop through config inputs and render sections
    local sectionIndex = 0
    for i, inputDef in ipairs(config.configInputs) do
        if inputDef.type == "header" then
            sectionIndex = sectionIndex + 1
            
            -- Initialize section state from definition if not already set
            if sectionStates[sectionIndex] == nil then
                sectionStates[sectionIndex] = inputDef.state or "expanded"
            end
            
            local isExpanded = (sectionStates[sectionIndex] == "expanded")
            local sectionContent = inputDef.section or inputDef.sectionContent or {}
            
            -- Create clickable header button
            local headerBtn = CreateFrame("Button", nil, container)
            if lastControl then
                headerBtn:SetPoint("TOPLEFT", lastControl, "BOTTOMLEFT", 0, inputDef.anchorOffsetY or -20)
            else
                headerBtn:SetPoint("TOPLEFT", 10, -10)
            end
            headerBtn:SetSize(PANEL_WIDTH - 80, 20)
            
            -- Expand/collapse icon
            local icon = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            icon:SetPoint("LEFT", 0, 0)
            icon:SetText(isExpanded and "[-]" or "[+]")
            icon:SetTextColor(0.7, 0.7, 0.7)
            
            -- Header text
            local headerText = headerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            headerText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
            headerText:SetText(inputDef.text or "")
            headerText:SetTextColor(1, 0.82, 0)
            
            -- Capture section index for toggle handler
            local capturedSectionIndex = sectionIndex
            
            -- Click handler to toggle section
            headerBtn:SetScript("OnClick", function()
                -- Toggle state
                sectionStates[capturedSectionIndex] = (sectionStates[capturedSectionIndex] == "expanded") and "collapsed" or "expanded"
                -- Rerender
                if options.onRerender then
                    options.onRerender()
                end
            end)
            
            -- Hover effects
            headerBtn:SetScript("OnEnter", function()
                headerText:SetTextColor(1, 1, 0.5)
                icon:SetTextColor(1, 1, 0.5)
            end)
            headerBtn:SetScript("OnLeave", function()
                headerText:SetTextColor(1, 0.82, 0)
                icon:SetTextColor(0.7, 0.7, 0.7)
            end)
            
            lastControl = headerBtn
            
            -- Render section content if expanded
            if isExpanded then
                for _, controlDef in ipairs(sectionContent) do
                    -- Set context fields on control
                    if options.setContextOnControl then
                        options.setContextOnControl(controlDef, contextData)
                    end
                    
                    -- Handle dynamic options for dropdowns
                    if controlDef.type == "dropdown" and controlDef.getOptions then
                        controlDef.options = controlDef:getOptions()
                    end
                    
                    -- Render control based on type
                    local controlFrame = nil
                    if controlDef.type == "dropdown" then
                        local label, dropdown = CreateDropdown(container, controlDef, lastControl)
                        controlFrame = label
                    elseif controlDef.type == "textinput" then
                        local label, input = CreateTextInput(container, controlDef, lastControl)
                        controlFrame = label
                    elseif controlDef.type == "colorpicker" then
                        local label, btn = CreateColorPicker(container, controlDef, lastControl)
                        controlFrame = label
                    elseif controlDef.type == "checkbox" then
                        local checkbox, label = CreateCheckbox(container, controlDef, lastControl)
                        controlFrame = checkbox
                    elseif controlDef.type == "positionbuttons" then
                        local label, upBtn, downBtn, leftBtn, rightBtn = CreatePositionButtons(container, controlDef, lastControl)
                        controlFrame = label
                    elseif controlDef.type == "button" then
                        local label, btn = CreateButton(container, controlDef, lastControl)
                        controlFrame = label
                    elseif controlDef.type == "label" then
                        local label, valueLabel = CreateLabel(container, controlDef, lastControl)
                        controlFrame = label
                    end
                    
                    if controlFrame then
                        lastControl = controlFrame
                    end
                end
            end
        end
    end
    
    -- Set panel height dynamically based on last control
    if lastControl and lastControl.GetBottom then
        local panelTop = parent:GetTop()
        local lastControlBottom = lastControl:GetBottom()
        if panelTop and lastControlBottom then
            local contentHeight = panelTop - lastControlBottom + 40
            parent:SetHeight(math.max(contentHeight, 400))
        else
            parent:SetHeight(900)
        end
    else
        parent:SetHeight(900)
    end
end

-- ============================================================================
-- BUILD DOCK CONFIG PANEL
-- Renders collapsible config sections for a dock (no icon list needed)
-- ============================================================================

function Cooldowns:BuildDockConfigPanel(parent, config)
    -- Track expanded/collapsed state for each section
    local sectionStates = {}
    
    -- Controls panel (dynamically sized based on content)
    local controlsPanel = CreateFrame("Frame", "TweaksCD_DockConfig_ControlsPanel", parent, "BackdropTemplate")
    controlsPanel:SetPoint("TOPLEFT", 10, -10)
    controlsPanel:SetPoint("TOPRIGHT", -10, -10)
    controlsPanel:SetHeight(100)  -- Will be updated dynamically
    controlsPanel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    controlsPanel:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
    controlsPanel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    -- Render function using shared logic
    local function RenderControls()
        Cooldowns:RenderConfigControls({
            parent = controlsPanel,
            config = config,
            sectionStates = sectionStates,
            getHeaderText = function()
                return "Dock Configuration: " .. (config.dockName or "Unknown")
            end,
            setContextOnControl = function(controlDef, data)
                -- Set uniqueID so GetIconConfigInputs controls work for docks
                controlDef.uniqueID = config.dockName
            end,
            onRerender = function()
                RenderControls()
            end,
        })
    end
    
    -- Make RenderControls accessible to controls via config
    config.RenderControls = RenderControls
    
    -- Initial render
    RenderControls()
    
    -- Set parent height
    if controlsPanel and controlsPanel.GetBottom then
        local panelBottom = controlsPanel:GetBottom()
        local parentTop = parent:GetTop()
        if panelBottom and parentTop then
            parent:SetHeight(math.max(parentTop - panelBottom + 20, 600))
        end
    end
end

-- ============================================================================
-- DOCKS SETTINGS PANEL
-- ============================================================================

local docksPanel = nil
local selectedDockName = nil  -- Actual dock key from database
local dockDropdown = nil

function Cooldowns:CreateDocksPanel()
    if docksPanel then return docksPanel end
    
    local panel = CreateFrame("Frame", "TweaksUI_Cooldowns_Docks_Panel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetPoint("TOPLEFT", cooldownHub, "TOPRIGHT", 0, 0)
    panel:SetBackdrop(darkBackdrop)
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    panel:Hide()
    
    settingsPanels["docks"] = panel
    
    -- Register with GlobalScale for settings scaling
    if TUICD.GlobalScale then
        TUICD.GlobalScale:RegisterSettingsPanel(panel, 1.0)
    end
    
    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Dynamic Docks")
    title:SetTextColor(1, 0.82, 0)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        panel:Hide()
    end)
    
    -- Dock selector bar
    local selectorBar = CreateFrame("Frame", nil, panel)
    selectorBar:SetPoint("TOPLEFT", 15, -40)
    selectorBar:SetPoint("TOPRIGHT", -15, -40)
    selectorBar:SetHeight(35)
    
    -- "Current Dock:" label
    local dockLabel = selectorBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dockLabel:SetPoint("LEFT", 0, 0)
    dockLabel:SetText("Current Dock:")
    
    -- Dropdown for dock selection
    local dropdown = CreateFrame("Frame", "TweaksUI_DockSelectorDropdown", selectorBar, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", dockLabel, "RIGHT", 0, -2)
    UIDropDownMenu_SetWidth(dropdown, 150)
    
    local function RefreshDockDropdown()
        UIDropDownMenu_Initialize(dropdown, function(self, level)
            if not TUICD.NewDocks then return end
            
            local db = TUICD.NewDocks:GetDataBase_V2()
            local dockList = {}
            
            -- Collect all docks from database
            for dockKey, dockData in pairs(db.docks) do
                table.insert(dockList, {
                    key = dockKey,
                    displayName = (dockData.name and dockData.name ~= "") and dockData.name or dockKey
                })
            end
            
            -- Sort by key for consistent ordering
            table.sort(dockList, function(a, b) return a.key < b.key end)
            
            -- Create dropdown items
            for _, dock in ipairs(dockList) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = dock.displayName
                info.value = dock.key
                info.func = function()
                    selectedDockName = dock.key
                    UIDropDownMenu_SetText(dropdown, dock.displayName)
                    Cooldowns:RefreshDocksPanel()
                end
                info.checked = (selectedDockName == dock.key)
                UIDropDownMenu_AddButton(info, level)
            end
            
            -- Show message if no docks
            if #dockList == 0 then
                local info = UIDropDownMenu_CreateInfo()
                info.text = "|cff888888No docks created|r"
                info.disabled = true
                UIDropDownMenu_AddButton(info, level)
            end
        end)
    end
    
    -- Initialize selectedDockName to first dock or nil
    if TUICD.NewDocks then
        local db = TUICD.NewDocks:GetDataBase_V2()
        for dockKey, _ in pairs(db.docks) do
            selectedDockName = dockKey
            break
        end
    end
    
    RefreshDockDropdown()
    if selectedDockName then
        local db = TUICD.NewDocks:GetDataBase_V2()
        local dockData = db.docks[selectedDockName]
        local displayName = (dockData and dockData.name and dockData.name ~= "") and dockData.name or selectedDockName
        UIDropDownMenu_SetText(dropdown, displayName)
    else
        UIDropDownMenu_SetText(dropdown, "No docks")
    end
    dockDropdown = dropdown
    
    -- Add/Remove dock buttons
    local addBtn = CreateFrame("Button", nil, selectorBar, "UIPanelButtonTemplate")
    addBtn:SetPoint("LEFT", dropdown, "RIGHT", 10, 2)
    addBtn:SetSize(80, 22)
    addBtn:SetText("New Dock")
    addBtn:SetScript("OnClick", function()
        if not TUICD.NewDocks then return end
        
        -- Generate unique dock name
        local db = TUICD.NewDocks:GetDataBase_V2()
        local count = 0
        for _ in pairs(db.docks) do count = count + 1 end
        local newDockKey = "Dock " .. (count + 1)
        
        -- Create new dock
        TUICD.NewDocks:EnsureDockExists(newDockKey)
        selectedDockName = newDockKey
        
        -- Refresh dropdown and panel
        RefreshDockDropdown()
        UIDropDownMenu_SetText(dropdown, newDockKey)
        Cooldowns:RefreshDocksPanel()
    end)
    
    local deleteBtn = CreateFrame("Button", nil, selectorBar, "UIPanelButtonTemplate")
    deleteBtn:SetPoint("LEFT", addBtn, "RIGHT", 4, 0)
    deleteBtn:SetSize(80, 22)
    deleteBtn:SetText("Delete Dock")
    deleteBtn:SetScript("OnClick", function()
        if not TUICD.NewDocks or not selectedDockName then return end
        
        -- Confirm deletion
        StaticPopupDialogs["TUICD_DELETE_DOCK"] = {
            text = "Delete dock '" .. selectedDockName .. "'?",
            button1 = "Delete",
            button2 = "Cancel",
            OnAccept = function()
                local db = TUICD.NewDocks:GetDataBase_V2()
                db.docks[selectedDockName] = nil
                
                -- Select first remaining dock or nil
                selectedDockName = nil
                for dockKey, _ in pairs(db.docks) do
                    selectedDockName = dockKey
                    break
                end
                
                -- Refresh
                RefreshDockDropdown()
                if selectedDockName then
                    local dockData = db.docks[selectedDockName]
                    local displayName = (dockData and dockData.name and dockData.name ~= "") and dockData.name or selectedDockName
                    UIDropDownMenu_SetText(dropdown, displayName)
                else
                    UIDropDownMenu_SetText(dropdown, "No docks")
                end
                Cooldowns:RefreshDocksPanel()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("TUICD_DELETE_DOCK")
    end)
    
    -- Content area (scroll frame)
    local contentArea = CreateFrame("Frame", nil, panel)
    contentArea:SetPoint("TOPLEFT", 15, -80)
    contentArea:SetPoint("BOTTOMRIGHT", -15, 15)
    
    -- Create scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, contentArea, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -20, 0)
    Cooldowns.SetConsistentScrollingBehavior(scrollFrame)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(scrollFrame:GetWidth() - 10, 1600)
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Build dock configuration panel
    local config = {
        type = "dock",
        dockName = selectedDockName,
        sharedState = {},
        getValue = function(dockName, path)
            if not TUICD.NewDocks then return nil end
            return TUICD.NewDocks:GetDockInstanceConfigValue(dockName, path)
        end,
        setValue = function(dockName, path, value)
            if not TUICD.NewDocks then return end
            TUICD.NewDocks:SetDockInstanceConfigValue(dockName, path, value)
            -- TODO: Apply changes to actual dock rendering if needed
        end,
    }
    
    -- Only build panel if a dock is selected
    if selectedDockName then
        -- CRITICAL: Ensure dock exists in database before rendering config
        if TUICD.NewDocks then
            local dockInstance = TUICD.NewDocks:GetDockIntance(config.dockName)
            if not dockInstance then
                -- Create dock with default config if it doesn't exist
                TUICD.NewDocks:EnsureDockExists(config.dockName)
            end
        end
        
        config.configInputs = Cooldowns:GetIconConfigInputs(config)
        Cooldowns:BuildDockConfigPanel(scrollChild, config)
    else
        -- Show "no docks" message
        local noDocksLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noDocksLabel:SetPoint("CENTER", scrollChild, "TOP", 0, -100)
        noDocksLabel:SetText("No docks created. Click 'New Dock' to create one.")
        noDocksLabel:SetTextColor(0.7, 0.7, 0.7)
    end
    
    panel.config = config
    panel.scrollChild = scrollChild
    
    docksPanel = panel
    return panel
end

function Cooldowns:RefreshDocksPanel()
    if not docksPanel or not docksPanel.scrollChild then return end
    
    -- Clear scroll child and rebuild
    local scrollChild = docksPanel.scrollChild
    
    -- Remove all children
    local children = {scrollChild:GetChildren()}
    for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
    end
    
    -- Update config
    docksPanel.config.dockName = selectedDockName
    
    -- Rebuild panel content
    if selectedDockName then
        -- Ensure dock exists
        if TUICD.NewDocks then
            local dockInstance = TUICD.NewDocks:GetDockIntance(selectedDockName)
            if not dockInstance then
                TUICD.NewDocks:EnsureDockExists(selectedDockName)
            end
        end
        
        docksPanel.config.configInputs = Cooldowns:GetIconConfigInputs(docksPanel.config)
        Cooldowns:BuildDockConfigPanel(scrollChild, docksPanel.config)
    else
        -- Show "no docks" message
        local noDocksLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noDocksLabel:SetPoint("CENTER", scrollChild, "TOP", 0, -100)
        noDocksLabel:SetText("No docks created. Click 'New Dock' to create one.")
        noDocksLabel:SetTextColor(0.7, 0.7, 0.7)
    end
end

function Cooldowns:ToggleDocksPanel()
    if not docksPanel then
        docksPanel = self:CreateDocksPanel()
    end
    
    if docksPanel:IsShown() then
        docksPanel:Hide()
    else
        -- Hide other tracker panels
        self:HideTrackerPanels()
        
        -- Position next to Cooldowns hub
        if cooldownHub and cooldownHub:IsShown() then
            docksPanel:ClearAllPoints()
            docksPanel:SetPoint("TOPLEFT", cooldownHub, "TOPRIGHT", 0, 0)
        end
        
        self:RefreshDocksPanel()
        docksPanel:Show()
    end
end

function Cooldowns:ShowDocksPanel()
    if not docksPanel then
        docksPanel = self:CreateDocksPanel()
    end
    
    -- Position next to Cooldowns hub
    if cooldownHub and cooldownHub:IsShown() then
        docksPanel:ClearAllPoints()
        docksPanel:SetPoint("TOPLEFT", cooldownHub, "TOPRIGHT", 0, 0)
    end
    
    self:RefreshDocksPanel()
    docksPanel:Show()
end

function Cooldowns:HideDocksPanel()
    if docksPanel then
        docksPanel:Hide()
    end
end



-- ============================================================================
-- CUSTOM TRACKERS SETTINGS PANEL
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
    
    -- Register with GlobalScale for settings scaling
    if TUICD.GlobalScale then
        TUICD.GlobalScale:RegisterSettingsPanel(panel, 1.0)
    end
    
    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Custom Trackers")
    title:SetTextColor(1, 0.82, 0)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    
    -- Tab system
    local tabs = {
        { name = "Entries", key = "entries" },
        { name = "Individual Icons", key = "pericon" },
    }
    
    local tabContainer = CreateFrame("Frame", nil, panel)
    tabContainer:SetPoint("TOPLEFT", 10, -40)
    tabContainer:SetPoint("TOPRIGHT", -10, -40)
    tabContainer:SetHeight(28)
    
    local contentContainer = CreateFrame("Frame", nil, panel)
    contentContainer:SetPoint("TOPLEFT", tabContainer, "BOTTOMLEFT", 0, -4)
    contentContainer:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 10)
    
    local contentFrames = {}
    local tabButtons = {}
    local currentTab = 1
    
    -- Helper to create tab content with scroll
    local function CreateTabContent()
        local content = CreateFrame("ScrollFrame", nil, contentContainer, "UIPanelScrollFrameTemplate")
        content:SetAllPoints()
        content:Hide()
        Cooldowns.SetConsistentScrollingBehavior(content)
        
        local scrollChild = CreateFrame("Frame", nil, content)
        scrollChild:SetSize(PANEL_WIDTH - 70, 800)
        content:SetScrollChild(scrollChild)
        content.scrollChild = scrollChild
        
        return content
    end

    
    -- ========================================
    -- SHARED HELPER FUNCTIONS
    -- ========================================
    
    local function CreateHeader(parent, yOffset, text)
        yOffset = yOffset - 8
        local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOPLEFT", 5, yOffset)
        header:SetText(text)
        header:SetTextColor(1, 0.82, 0)
        return yOffset - 18
    end
    
    
    -- ========================================
    -- TAB 1: ENTRIES (Add/Remove Spells/Items)
    -- ========================================
    local function BuildEntriesTab(parent)
        local y = -10
        
        -- ========================================
        -- DRAG & DROP ZONE
        -- ========================================
        y = y - 10
        y = CreateHeader(parent, y, "Add Entry")
        
        -- Create drop zone frame
        local dropZone = CreateFrame("Button", nil, parent, "BackdropTemplate")
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
        
        -- Drop zone handlers
        local function ProcessPanelDrop()
            local cursorType, id, subType, spellID = GetCursorInfo()
            
            if cursorType == "spell" then
                local actualSpellID = spellID or id
                if actualSpellID then
                    local success, msg = AddCustomEntry("spell", actualSpellID)
                    ClearCursor()
                    if success then
                        RebuildCustomTrackerIcons()
                        if panel.RefreshEntriesList then
                            panel:RefreshEntriesList()
                        end
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
                    if success then
                        RebuildCustomTrackerIcons()
                        if panel.RefreshEntriesList then
                            panel:RefreshEntriesList()
                        end
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
        
        y = y - 55
        
        -- Manual entry row
        local typeLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        typeLabel:SetPoint("TOPLEFT", 10, y)
        typeLabel:SetText("Manual:")
        typeLabel:SetTextColor(0.6, 0.6, 0.6)
        
        local typeDropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
        typeDropdown:SetPoint("LEFT", typeLabel, "RIGHT", -10, -2)
        UIDropDownMenu_SetWidth(typeDropdown, 65)
        
        local selectedType = "spell"
        UIDropDownMenu_Initialize(typeDropdown, function(self, level)
            local info = UIDropDownMenu_CreateInfo()
            info.text = "Spell"
            info.value = "spell"
            info.func = function() selectedType = "spell"; UIDropDownMenu_SetText(typeDropdown, "Spell") end
            info.checked = (selectedType == "spell")
            UIDropDownMenu_AddButton(info, level)
            
            info = UIDropDownMenu_CreateInfo()
            info.text = "Item"
            info.value = "item"
            info.func = function() selectedType = "item"; UIDropDownMenu_SetText(typeDropdown, "Item") end
            info.checked = (selectedType == "item")
            UIDropDownMenu_AddButton(info, level)
        end)
        UIDropDownMenu_SetText(typeDropdown, "Spell")
        
        local idInput = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        idInput:SetPoint("LEFT", typeDropdown, "RIGHT", 0, 2)
        idInput:SetSize(70, 20)
        idInput:SetAutoFocus(false)
        idInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        
        local addBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        addBtn:SetPoint("LEFT", idInput, "RIGHT", 3, 0)
        addBtn:SetSize(45, 20)
        addBtn:SetText("Add")
        
        addBtn:SetScript("OnClick", function()
            local input = idInput:GetText():trim()
            if input == "" then return end
            
            local success, msg = AddCustomEntry(selectedType, input)
            if success then
                idInput:SetText("")
                RebuildCustomTrackerIcons()
                if panel.RefreshEntriesList then
                    panel:RefreshEntriesList()
                end
            end
        end)
        
        idInput:SetScript("OnEnterPressed", function(self)
            addBtn:Click()
            self:ClearFocus()
        end)
        y = y - 30
        
        -- ========================================
        -- ADD EQUIPPED SLOTS
        -- ========================================
        y = y - 5
        y = CreateHeader(parent, y, "Add Equipped Slot")
        
        local equipHelp = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        equipHelp:SetPoint("TOPLEFT", 10, y)
        equipHelp:SetText("|cff888888Click + to track on-use equipment:|r")
        y = y - 14
        
        local equipContainer = CreateFrame("Frame", nil, parent)
        equipContainer:SetPoint("TOPLEFT", 10, y)
        equipContainer:SetSize(PANEL_WIDTH - 50, 80)
        panel.equipContainer = equipContainer
        
        local equipElements = {}
        
        -- Refresh available equipped items to add
        function panel:RefreshEquipmentList()
            for _, elem in ipairs(equipElements) do
                if elem.Hide then elem:Hide() end
                if elem.SetParent then elem:SetParent(nil) end
            end
            wipe(equipElements)
            
            local eqY = 0
            local currentEquipped = ScanEquippedOnUseItems()
            
            -- Get tracked values from CooldownHighlights and filter for equipped items
            local trackedValues = TUICD.CooldownHighlights:GetTrackedValues()
            
            -- Check which slots are already tracked
            -- trackedValues is keyed by apiIdentifier, which for equipped items is the slotID
            local trackedSlots = {}
            for uniqueID, trackedData in pairs(trackedValues) do
                if trackedData.trackingType == "equipped" then
                    -- apiIdentifier is the slotID for equipped items
                    trackedSlots[trackedData.apiIdentifier] = true
                end
            end
            
            local hasAny = false
            for slotID, itemInfo in pairs(currentEquipped) do
                if not trackedSlots[slotID] then
                    hasAny = true
                    local row = CreateFrame("Frame", nil, equipContainer)
                    row:SetPoint("TOPLEFT", 0, eqY)
                    row:SetSize(PANEL_WIDTH - 70, 20)
                    table.insert(equipElements, row)
                    
                    local icon = row:CreateTexture(nil, "ARTWORK")
                    icon:SetPoint("LEFT", 0, 0)
                    icon:SetSize(18, 18)
                    icon:SetTexture(itemInfo.texture)
                    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    
                    local slotName = itemInfo.slotName or TRACKABLE_EQUIPMENT_SLOTS[slotID] or "Slot " .. slotID
                    local itemName = itemInfo.itemName or "Unknown"
                    
                    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
                    label:SetPoint("RIGHT", row, "RIGHT", -40, 0)
                    label:SetJustifyH("LEFT")
                    label:SetText(string.format("|cff888888[%s]|r %s", slotName, itemName))
                    label:SetWordWrap(false)
                    
                    local addSlotBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    addSlotBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                    addSlotBtn:SetSize(30, 18)
                    addSlotBtn:SetText("+")
                    addSlotBtn:SetScript("OnClick", function()
                        AddCustomEntry("equipped", slotID)
                        RebuildCustomTrackerIcons()
                        panel:RefreshEquipmentList()
                        panel:RefreshEntriesList()
                    end)
                    
                    eqY = eqY - 22
                end
            end
            
            if not hasAny then
                local noNew = equipContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                noNew:SetPoint("TOPLEFT", 0, 0)
                if CountTableEntries(currentEquipped) == 0 then
                    noNew:SetText("|cff666666No on-use equipment currently equipped|r")
                else
                    noNew:SetText("|cff666666All on-use equipment already tracked|r")
                end
                table.insert(equipElements, noNew)
            end
        end
        
        y = y - 70
        
        -- ========================================
        -- UNIFIED ENTRIES LIST
        -- ========================================
        y = y - 10
        y = CreateHeader(parent, y, "Tracked Entries (This Spec)")
        
        local reorderHelp = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        reorderHelp:SetPoint("TOPLEFT", 10, y)
        reorderHelp:SetText("|cff888888Arrows to reorder, X to remove|r")
        y = y - 14
        
        local entriesContainer = CreateFrame("Frame", nil, parent)
        entriesContainer:SetPoint("TOPLEFT", 10, y)
        entriesContainer:SetSize(PANEL_WIDTH - 50, 250)
        panel.entriesContainer = entriesContainer
        
        -- Refresh unified entries list
        function RenderTrackedList()
            Cooldowns.RenderTrackedValuesList(entriesContainer, {
                rowHeight = 26,
                emptyText = "|cff888888No entries - drop spells/items above to add|r",
                removeEnabled = true,
                onRowClick = function(row, slotIndex, rows)
                    -- Entries tab doesn't need row selection behavior
                end
            })
        end

        RenderTrackedList()

        RegisterTrackerListUpdateCallback(RenderTrackedList)

        parent:SetHeight(math.abs(y) + 300)
    end

    
    -- ========================================
    -- TAB: Individual Icons Settings for Custom Trackers
    -- ========================================
    
    
    -- Build tab content builders
    local tabBuilders = {
        entries = BuildEntriesTab,
        pericon = function (parent) 
            local config = {
                type = "customIcons",
                sharedState = {},  -- Shared state for controls to communicate
                listTrackedValues = function() return TUICD.CooldownHighlights:getTrackedValuesListForSettings() end,
                getCurrentEntryConfig = function(uniqueID) return TUICD.CooldownHighlights:GetTrackedValue(uniqueID) end,
                getValue = function(uniqueID, path) return TUICD.CooldownHighlights:GetTrackerConfigValue(uniqueID, path) end,
                setValue = function(uniqueID, path, value) TUICD.CooldownHighlights:SetTrackerConfigValue(uniqueID, path, value) end,
            }
            --[[
                NOTE: The config object is passed by reference to both GetIconConfigInputs and BuildPerIconTab.
                Closures in GetIconConfigInputs capture this reference, so they can access RenderControlsForSelection
                even though it's added to config later by BuildPerIconTab. This enables controls to trigger rerenders.
            ]]
            config.configInputs = Cooldowns:GetIconConfigInputs(config)
            Cooldowns:BuildPerIconTab(parent, config)
        end,
    }
    
    -- Create content frames and tab buttons
    local tabWidth = (PANEL_WIDTH - 20) / #tabs
    
    for i, tab in ipairs(tabs) do
        -- Create content frame
        local content = CreateTabContent()
        contentFrames[tab.key] = content
        
        -- Build content
        if tabBuilders[tab.key] then
            tabBuilders[tab.key](content.scrollChild)
        end
        
        -- Create tab button
        local tabBtn = CreateFrame("Button", nil, tabContainer)
        tabBtn:SetSize(tabWidth - 2, 26)
        tabBtn:SetPoint("LEFT", (i - 1) * tabWidth, 0)
        
        tabBtn.bg = tabBtn:CreateTexture(nil, "BACKGROUND")
        tabBtn.bg:SetAllPoints()
        tabBtn.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
        
        tabBtn.text = tabBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tabBtn.text:SetPoint("CENTER")
        tabBtn.text:SetText(tab.name)
        
        tabBtn:SetScript("OnClick", function()
            -- Hide all content
            for _, cf in pairs(contentFrames) do
                cf:Hide()
            end
            -- Show selected
            contentFrames[tab.key]:Show()
            -- Update button visuals
            for _, btn in ipairs(tabButtons) do
                btn.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
                btn.text:SetTextColor(0.7, 0.7, 0.7)
            end
            tabBtn.bg:SetColorTexture(0.3, 0.3, 0.5, 1)
            tabBtn.text:SetTextColor(1, 1, 1)
            currentTab = i
            
            -- Refresh entries tab when shown
            if tab.key == "entries" then
                if panel.RefreshEquipmentList then panel:RefreshEquipmentList() end
                if panel.RefreshCustomEntriesList then panel:RefreshCustomEntriesList() end
            end
        end)
        
        tabBtn:SetScript("OnEnter", function(self)
            if currentTab ~= i then
                self.bg:SetColorTexture(0.25, 0.25, 0.35, 0.9)
            end
        end)
        
        tabBtn:SetScript("OnLeave", function(self)
            if currentTab ~= i then
                self.bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
            end
        end)
        
        tabButtons[i] = tabBtn
    end
    
    -- Show first tab
    if tabButtons[1] then
        tabButtons[1]:Click()
    end
    
    -- Initial refresh
    C_Timer.After(0.1, function()
        if panel.RefreshEquippedItemsList then panel:RefreshEquippedItemsList() end
        if panel.RefreshCustomEntriesList then panel:RefreshCustomEntriesList() end
    end)
    
    panel:Show()
end


    