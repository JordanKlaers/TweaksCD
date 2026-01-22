-- ============================================================================
-- TweaksUI: Cooldowns - CMT Migration
-- Migrates settings from Cooldown Manager Tweaks (CMT) to TweaksUI: Cooldowns
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.Migration = {}
local Migration = TUICD.Migration

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local MIGRATION_VERSION = 2  -- v2: Added position migration, fixed enabled check, added more setting mappings

-- Tracker key mapping (CMT key -> TUI:CD key)
local TRACKER_MAPPING = {
    essential = "essential",
    utility = "utility",
    buffs = "buffs",
    items = "customTrackers",  -- CMT's items tracker maps to custom trackers
}

-- Check if aspect ratio is custom pixel format
local function IsCustomAspectRatio(aspectRatio)
    if not aspectRatio then return false end
    return aspectRatio:match("^%d+x%d+$") ~= nil
end

-- Setting mapping: CMT setting name -> TUI:CD setting name (or function to transform)
local SETTING_MAPPING = {
    -- Layout settings
    columns = "columns",
    maxColumns = "columns",  -- CMT might use maxColumns
    alignment = "alignment",
    hSpacing = "spacingH",
    vSpacing = "spacingV",
    horizontalSpacing = "spacingH",  -- Alternate name
    verticalSpacing = "spacingV",    -- Alternate name
    reverseOrder = "reverseOrder",
    
    -- Row pattern needs conversion from array to string
    rowPattern = function(value)
        if type(value) == "table" then
            return "customLayout", table.concat(value, ",")
        end
        return "customLayout", ""
    end,
    
    -- Layout direction needs conversion
    layoutDirection = function(value)
        if value == "ROWS" then
            return "growDirection", "RIGHT"
        else
            return "growDirection", "DOWN"
        end
    end,
    growDirection = function(value)
        -- Normalize CMT grow direction to TUI:CD format
        if value == "LEFT" or value == "RIGHT" or value == "UP" or value == "DOWN" then
            return "growDirection", value
        end
        return "growDirection", "RIGHT"
    end,
    
    -- Icon settings
    iconSize = "iconSize",
    size = "iconSize",  -- Alternate name
    iconOpacity = "iconOpacity",
    opacity = "iconOpacity",  -- Alternate name
    borderAlpha = "borderAlpha",
    
    -- Zoom: CMT uses 1.0-3.0 (1=no zoom, 3=max zoom)
    -- TUI:CD uses 0-0.5 (0=no inset, higher=more zoom)
    zoom = function(value)
        if type(value) ~= "number" then return "zoom", 0.08 end
        local tuiZoom = (value - 1) * 0.25
        tuiZoom = math.max(0, math.min(0.5, tuiZoom))
        return "zoom", tuiZoom
    end,
    
    -- Aspect ratio
    aspectRatio = function(value, settings)
        if value == "custom" or (settings.customAspectW and settings.customAspectH) then
            return nil, nil
        end
        return "aspectRatio", value
    end,
    customAspectW = function(value, settings)
        if settings.aspectRatio == "custom" or IsCustomAspectRatio(settings.aspectRatio) then
            return "iconWidth", value
        end
        return nil, nil
    end,
    customAspectH = function(value, settings)
        if settings.aspectRatio == "custom" or IsCustomAspectRatio(settings.aspectRatio) then
            return "iconHeight", value
        end
        return nil, nil
    end,
    
    -- Text scaling
    cooldownTextScale = "cooldownTextScale",
    countTextScale = "countTextScale",
    
    -- Buff-specific (persistent display)
    persistentDisplay = nil,  -- TUI:CD doesn't have this toggle
    greyscaleInactive = "greyscaleInactive",
    inactiveAlpha = "inactiveAlpha",
    
    -- Visibility settings
    visibilityEnabled = "visibilityEnabled",
    visibilityCombat = function(value)
        return "showInCombat", value
    end,
    visibilityMouseover = nil,  -- TUI:CD uses fade system instead
    visibilityTarget = function(value)
        return "showHasTarget", value
    end,
    visibilityGroup = function(value)
        return "showInParty", value
    end,
    visibilityInstance = function(value)
        return "showInInstance", value
    end,
    visibilityInstanceTypes = nil,
    visibilityFadeAlpha = function(value)
        if type(value) ~= "number" then return "fadeAlpha", 0.3 end
        return "fadeAlpha", value / 100
    end,
    
    -- Settings we skip (no TUI:CD equivalent)
    compactMode = nil,
    compactOffset = nil,
    borderScale = nil,
    barIconSide = nil,
    barSpacing = nil,
    barIconGap = nil,
    visibilityOverrideEMT = nil,
    masqueDisabled = nil,
    masqueSavedAspect = nil,
    masqueSavedZoom = nil,
    masqueSavedBorderAlpha = nil,
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

local function MigrationPrint(msg)
    print(TUICD.CHAT_PREFIX .. "|cff00ccff[Migration]|r " .. msg)
end

-- ============================================================================
-- SETTING CONVERSION
-- ============================================================================

local function ConvertTrackerSettings(cmtSettings)
    if not cmtSettings then return {} end
    
    local tuiSettings = {
        enabled = true,  -- Enable migrated trackers
    }
    
    for cmtKey, cmtValue in pairs(cmtSettings) do
        if cmtKey ~= "iconOverrides" then
            local mapping = SETTING_MAPPING[cmtKey]
            
            if mapping == nil then
                -- Skip this setting
            elseif type(mapping) == "string" then
                tuiSettings[mapping] = cmtValue
            elseif type(mapping) == "function" then
                local tuiKey, tuiValue = mapping(cmtValue, cmtSettings)
                if tuiKey then
                    tuiSettings[tuiKey] = tuiValue
                end
            end
        end
    end
    
    -- Handle visibilityGroup -> both showInParty and showInRaid
    if cmtSettings.visibilityGroup ~= nil then
        tuiSettings.showInParty = cmtSettings.visibilityGroup
        tuiSettings.showInRaid = cmtSettings.visibilityGroup
    end
    
    return tuiSettings
end

-- ============================================================================
-- CUSTOM ENTRIES MIGRATION
-- ============================================================================

local function MigrateCustomEntries()
    if not CMT_CharDB then return 0 end
    
    -- CMT stores in customEntriesBySpec[specID] or customItemsBySpec[specID]
    local cmtEntries = CMT_CharDB.customEntriesBySpec or CMT_CharDB.customItemsBySpec
    if not cmtEntries then return 0 end
    
    local entriesMigrated = 0
    
    for specID, entries in pairs(cmtEntries) do
        if type(entries) == "table" and #entries > 0 then
            local existingEntries = TUICD.Database:GetCustomEntries(specID)
            
            if #existingEntries == 0 then
                TUICD.Database:SetCustomEntries(specID, TUICD.DeepCopy(entries))
                entriesMigrated = entriesMigrated + #entries
            end
        end
    end
    
    return entriesMigrated
end

-- ============================================================================
-- MAIN MIGRATION LOGIC
-- ============================================================================

function Migration:IsCMTDataAvailable()
    return _G.CMT_DB ~= nil
end

function Migration:HasMigrated()
    return TUICD.Database:HasMigratedFromCMT()
end

function Migration:DoMigration()
    if not self:IsCMTDataAvailable() then
        return false, "CMT data not found"
    end
    
    local trackersMigrated = 0
    local entriesMigrated = 0
    
    -- Get current CMT profile
    local currentProfile = "Default"
    if CMT_CharDB and CMT_CharDB.currentProfile then
        currentProfile = CMT_CharDB.currentProfile
    end
    
    -- Get CMT profile settings
    local cmtProfile = CMT_DB.profiles and CMT_DB.profiles[currentProfile]
    if not cmtProfile then
        cmtProfile = CMT_DB.profiles and CMT_DB.profiles["Default"]
    end
    
    if cmtProfile then
        -- Migrate each tracker
        for cmtKey, tuiKey in pairs(TRACKER_MAPPING) do
            if cmtProfile[cmtKey] then
                local convertedSettings = ConvertTrackerSettings(cmtProfile[cmtKey])
                
                -- Apply migrated settings (HasMigrated check at the top prevents re-running)
                TUICD.Database:SetTrackerSettings(tuiKey, convertedSettings)
                trackersMigrated = trackersMigrated + 1
                MigrationPrint("Migrated " .. tuiKey .. " tracker settings")
            end
        end
    end
    
    -- Migrate container positions from CMT_DB (top level)
    -- CMT stores positions like: CMT_DB.essentialTrackerPosition, CMT_DB.itemsTrackerPosition, etc.
    if CMT_DB then
        local positionKeys = {
            essential = "essentialTrackerPosition",
            utility = "utilityTrackerPosition", 
            buffs = "buffsTrackerPosition",
            customTrackers = "itemsTrackerPosition",  -- CMT's items -> TUI:CD customTrackers
        }
        
        for tuiKey, cmtPosKey in pairs(positionKeys) do
            local pos = CMT_DB[cmtPosKey]
            if pos then
                local point = pos.point or "CENTER"
                local x = pos.x or 0
                local y = pos.y or 0
                TUICD.Database:SetContainerPosition(tuiKey, point, x, y)
                MigrationPrint("Migrated " .. tuiKey .. " position from " .. cmtPosKey)
            end
        end
    end
    
    -- Migrate custom entries
    entriesMigrated = MigrateCustomEntries()
    if entriesMigrated > 0 then
        MigrationPrint("Migrated " .. entriesMigrated .. " custom tracker entries")
    end
    
    -- Mark migration complete
    TUICD.Database:SetCMTMigrated(MIGRATION_VERSION)
    
    return true, trackersMigrated, entriesMigrated
end

-- ============================================================================
-- WELCOME DIALOG
-- ============================================================================

local DISCORD_LINK = "https://discord.gg/Zzs3KhMM5b"

local function ShowWelcomeDialog(migrated)
    -- Create custom frame for copy support
    if _G["TUICD_WelcomeFrame"] then
        _G["TUICD_WelcomeFrame"]:Show()
        return
    end
    
    local frame = CreateFrame("Frame", "TUICD_WelcomeFrame", UIParent, "BackdropTemplate")
    frame:SetSize(420, 300)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("|cff00ccffTweaksUI: Cooldowns|r")
    
    -- Welcome text
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOP", title, "BOTTOM", 0, -15)
    text:SetWidth(380)
    text:SetJustifyH("CENTER")
    text:SetText("Welcome! Enhance your cooldown trackers with custom layouts, visibility controls, and more.\n\n" ..
                 "Type |cffffffff/tuicd|r to open settings.\n" ..
                 "Right-click the minimap button to unlock frames.\n\n" ..
                 "|cff888888Formerly known as Cooldown Manager Tweaks (CMT)|r")
    
    -- Discord section
    local discordLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    discordLabel:SetPoint("TOP", text, "BOTTOM", 0, -20)
    discordLabel:SetText("|cff7289DAJoin our Discord:|r")
    
    -- Copyable editbox for Discord link
    local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    editBox:SetSize(300, 20)
    editBox:SetPoint("TOP", discordLabel, "BOTTOM", 0, -5)
    editBox:SetAutoFocus(false)
    editBox:SetText(DISCORD_LINK)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    editBox:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
    
    -- Hint
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOP", editBox, "BOTTOM", 0, -3)
    hint:SetText("|cff888888Click to select, Ctrl+C to copy|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetSize(100, 24)
    closeBtn:SetPoint("BOTTOM", 0, 20)
    closeBtn:SetText("Got it!")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- X button
    local xBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    xBtn:SetPoint("TOPRIGHT", -5, -5)
    
    frame:Show()
end

-- Public function to show welcome/about
function Migration:ShowWelcome()
    ShowWelcomeDialog(false)
end

-- ============================================================================
-- CMT MIGRATION COMPLETE DIALOG
-- ============================================================================

function Migration:ShowMigrationCompleteDialog()
    -- Create custom frame for migration complete
    if _G["TUICD_MigrationCompleteFrame"] then
        _G["TUICD_MigrationCompleteFrame"]:Show()
        return
    end
    
    local frame = CreateFrame("Frame", "TUICD_MigrationCompleteFrame", UIParent, "BackdropTemplate")
    frame:SetSize(500, 340)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("|cff00ccffTweaksUI: Cooldowns|r - |cff00ff00Migration Complete|r")
    
    -- Status icon (checkmark)
    local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    statusText:SetPoint("TOP", title, "BOTTOM", 0, -10)
    statusText:SetText("|cff00ff00✓|r")
    
    -- Main text
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOP", statusText, "BOTTOM", 0, -5)
    text:SetWidth(460)
    text:SetJustifyH("CENTER")
    text:SetText("Your settings from |cffffcc00Cooldown Manager Tweaks|r have been\n" ..
                 "successfully imported into |cff00ccffTweaksUI: Cooldowns|r!\n\n" ..
                 "|cffffffffWhat was migrated:|r\n" ..
                 "• Tracker layouts (size, spacing, alignment)\n" ..
                 "• Visibility settings (combat, target, group)\n" ..
                 "• Custom tracker entries\n" ..
                 "• Frame positions\n\n" ..
                 "|cffff8800CMT is still active.|r To complete the switch:\n" ..
                 "1. Click the button below to disable CMT\n" ..
                 "2. Your UI will reload\n" ..
                 "3. TweaksUI: Cooldowns will take over with your migrated settings")
    
    -- Disable & Reload button (primary action)
    local disableBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    disableBtn:SetSize(220, 30)
    disableBtn:SetPoint("BOTTOM", 0, 55)
    disableBtn:SetText("|cff00ff00Disable CMT & Reload|r")
    disableBtn:SetScript("OnClick", function()
        C_AddOns.DisableAddOn("CooldownManagerTweaks")
        ReloadUI()
    end)
    
    -- Make the button stand out
    disableBtn:SetNormalFontObject("GameFontNormalLarge")
    
    -- Later button
    local laterBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    laterBtn:SetSize(100, 24)
    laterBtn:SetPoint("BOTTOM", 0, 20)
    laterBtn:SetText("Later")
    laterBtn:SetScript("OnClick", function() 
        frame:Hide() 
        TUICD:Print("You can type |cffffffff/tuicd|r at any time to switch from CMT.")
    end)
    
    -- X button
    local xBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    xBtn:SetPoint("TOPRIGHT", -5, -5)
    
    -- Help text at bottom
    local helpText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    helpText:SetPoint("BOTTOM", laterBtn, "TOP", 0, 30)
    helpText:SetText("|cff888888CMT will continue working until you reload.|r")
    
    frame:Show()
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- ============================================================================
-- INITIALIZATION (Called by Main.lua after Database is ready)
-- ============================================================================

function Migration:RunStartupMigration()
    -- Check if this is first load (show welcome) - only if NOT in CMT coexistence mode
    if not TUICD.CMT_COEXISTENCE_MODE then
        local isFirstLoad = not TUICD.Database:GetGlobal("welcomeShown")
        
        if isFirstLoad then
            C_Timer.After(2, function()
                ShowWelcomeDialog(false)
            end)
            TUICD.Database:SetGlobal("welcomeShown", true)
        end
    end
    -- Note: CMT migration is handled by Main.lua when in coexistence mode
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

SLASH_TUICDMIGRATE1 = "/tuicdmigrate"
SlashCmdList["TUICDMIGRATE"] = function(msg)
    -- Make sure database is initialized
    if not TUICD.Database or not TUICD.Database:IsInitialized() then
        MigrationPrint("Please wait for addon to fully load before using migration commands.")
        return
    end
    
    msg = (msg or ""):lower():trim()
    
    if msg == "status" then
        MigrationPrint("CMT Shim Loaded: " .. tostring(CMT_MIGRATION_STUB_LOADED == true))
        MigrationPrint("CMT_DB exists: " .. tostring(CMT_DB ~= nil))
        MigrationPrint("CMT_CharDB exists: " .. tostring(CMT_CharDB ~= nil))
        MigrationPrint("CMT Data Available: " .. tostring(Migration:IsCMTDataAvailable()))
        MigrationPrint("Already Migrated: " .. tostring(Migration:HasMigrated()))
        MigrationPrint("Migration Version: " .. tostring(TUICD.Database:GetCMTMigrationVersion()))
        if CMT_DB and CMT_DB.profiles then
            local profiles = {}
            for name in pairs(CMT_DB.profiles) do
                table.insert(profiles, name)
            end
            MigrationPrint("CMT Profiles: " .. table.concat(profiles, ", "))
        end
        if CMT_CharDB then
            MigrationPrint("CMT Current Profile: " .. (CMT_CharDB.currentProfile or "Default"))
        end
        
    elseif msg == "force" then
        TUICD.Database:ClearCMTMigration()
        
        if Migration:IsCMTDataAvailable() then
            local success, trackers, entries = Migration:DoMigration()
            if success then
                MigrationPrint("Forced migration complete! Reload UI to see changes.")
            else
                MigrationPrint("Migration failed: " .. tostring(trackers))
            end
        else
            MigrationPrint("No CMT data found to migrate.")
        end
        
    elseif msg == "reset" then
        TUICD.Database:ClearCMTMigration()
        MigrationPrint("Migration flag cleared.")
        
    elseif msg == "dump" then
        -- Debug: dump CMT data structure
        MigrationPrint("Dumping CMT data structure...")
        if CMT_DB then
            print("CMT_DB exists")
            if CMT_DB.profiles then
                print("  profiles:")
                for profileName, profile in pairs(CMT_DB.profiles) do
                    print("    " .. profileName .. ":")
                    for trackerKey, trackerSettings in pairs(profile) do
                        if type(trackerSettings) == "table" then
                            local keys = {}
                            for k in pairs(trackerSettings) do
                                table.insert(keys, k)
                            end
                            print("      " .. trackerKey .. ": " .. table.concat(keys, ", "))
                        end
                    end
                end
            end
        else
            print("CMT_DB is nil")
        end
        if CMT_CharDB then
            print("CMT_CharDB exists")
            for k, v in pairs(CMT_CharDB) do
                if type(v) == "table" then
                    print("  " .. k .. ": (table)")
                else
                    print("  " .. k .. ": " .. tostring(v))
                end
            end
        else
            print("CMT_CharDB is nil")
        end
        
    else
        MigrationPrint("Migration Commands:")
        print("  /tuicdmigrate status - Show migration status")
        print("  /tuicdmigrate force  - Force re-migration (requires /reload)")
        print("  /tuicdmigrate reset  - Clear migration flag")
        print("  /tuicdmigrate dump   - Dump CMT data structure for debugging")
    end
end
