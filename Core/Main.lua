-- ============================================================================
-- TweaksUI: Cooldowns - Main
-- Core addon initialization and slash commands
-- Version 3.0.2 - Unified Architecture
-- ============================================================================

local ADDON_NAME, TUICD = ...

-- Make TUICD accessible globally
_G.TUICD = TUICD


-- Central helper to toggle the main settings hub
function TUICD:ToggleSettings()
    if self.Settings and self.Settings.Toggle then
        self.Settings:Toggle()
    else
        self:PrintError("Settings UI not ready yet. Try again in a moment.")
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")

local addonLoaded = false
local playerLoggedIn = false

local function Initialize()
    if not addonLoaded or not playerLoggedIn then
        return
    end
    
    -- Initialize database
    TUICD.Database:Initialize()
    
    -- Initialize GlobalScale
    if TUICD.GlobalScale then
        TUICD.GlobalScale:Initialize()
    end
    
    -- Initialize Profiles system
    if TUICD.Profiles then
        TUICD.Profiles:Initialize()
    end
    
    -- Initialize ProfileImportExport
    if TUICD.ProfileImportExport then
        TUICD.ProfileImportExport:Initialize()
    end
    
    -- Initialize media
    TUICD.Media:Initialize()
    
    -- Initialize SnapLocking (standalone utility, not a module)
    if TUICD.SnapLocking and TUICD.SnapLocking.Initialize then
        TUICD.SnapLocking:Initialize()
    end
    
    -- Initialize all registered modules (including Layout and Cooldowns)
    if TUICD.ModuleManager then
        TUICD.ModuleManager:InitializeAll()
        TUICD.ModuleManager:EnableAll()
    end
    
    -- Initialize minimap button
    if TUICD.MinimapButton then
        TUICD.MinimapButton:Initialize()
    end
    
    -- Apply snap attachments after frames are created
    if TUICD.SnapLocking then
        C_Timer.After(2, function()
            TUICD.SnapLocking:ApplyAllAttachments()
        end)
    end
    
    -- Load forceAllVisible state
    TUICD:LoadForceAllVisibleState()
    
    TUICD:Print("Loaded - Type |cffFFFFFF/tuicd|r to open settings")
end

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        addonLoaded = true
        Initialize()
    elseif event == "PLAYER_LOGIN" then
        playerLoggedIn = true
        Initialize()
    end
end)

-- ============================================================================
-- PLAYER_LOGOUT CLEANUP
-- ============================================================================

local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", function()
    TUICD:PrintDebug("PLAYER_LOGOUT: Restoring Blizzard frames...")
    
    -- Restore all docked icons
    if TUICD.Docks and TUICD.Docks.RestoreAllDockedIcons then
        pcall(function()
            TUICD.Docks:RestoreAllDockedIcons()
        end)
    end
    
    TUICD:PrintDebug("PLAYER_LOGOUT: Cleanup complete")
end)

-- ============================================================================
-- SLASH COMMAND HANDLER
-- ============================================================================

local function HandleSlashCommand(msg)
    local cmd, args = msg:match("^(%S*)%s*(.*)$")
    cmd = cmd:lower()
    
    if cmd == "" or cmd == "settings" or cmd == "options" then
        TUICD:ToggleSettings()
        
    elseif cmd == "help" then
        TUICD:Print("|cff00ccff=== TUI: Cooldowns Commands ===|r")
        TUICD:Print("|cffffff00/tuicd|r - Open settings hub")
        TUICD:Print("|cffffff00/tuicd layout|r - Toggle Layout Mode")
        TUICD:Print("|cffffff00/tuicd cdm|r - Open Blizzard Cooldown Manager")
        TUICD:Print("|cffffff00/tuicd showall|r - Toggle visibility bypass")
        TUICD:Print("|cffffff00/tuicd status|r - Show debug status info")
        TUICD:Print("|cffffff00/tuicd debug|r - Toggle debug mode")
        TUICD:Print("|cffffff00/tuicd dock|r - Dock management commands")
        TUICD:Print("|cffffff00/tuicd remigrate|r - Re-import positions from TweaksUI")
        TUICD:Print("|cffffff00/tuicd migrateprofiles|r - Convert old profiles to 3.0 format")
        TUICD:Print("|cffffff00/tuicd version|r - Show version info")
        TUICD:Print("|cffffff00/cdm|r - Toggle Blizzard Cooldown Settings")
        TUICD:Print("|cffffff00/rl|r - Reload UI")
        
    elseif cmd == "layout" then
        if TUICD.Layout then
            TUICD.Layout:Toggle()
        else
            TUICD:PrintError("Layout module not available")
        end
        
    elseif cmd == "cdm" or cmd == "cooldownmanager" then
        -- Open Blizzard's Cooldown Settings frame
        local cooldownFrame = CooldownViewerSettings or _G["CooldownViewerSettings"]
        if cooldownFrame then
            if cooldownFrame:IsShown() then
                cooldownFrame:Hide()
            else
                cooldownFrame:Show()
            end
        else
            TUICD:PrintError("Cooldown Settings not available")
        end
        
    elseif cmd == "dock" then
        -- Dock management commands
        local subcmd, subargs = args:match("^(%S*)%s*(.*)$")
        subcmd = (subcmd or ""):lower()
        
        if subcmd == "" or subcmd == "help" then
            TUICD:Print("|cff00ccff=== Dock Commands ===|r")
            TUICD:Print("|cffffff00/tuicd dock cleanup|r - Remove orphaned assignments (? icons)")
            TUICD:Print("|cffffff00/tuicd dock cleanup <1-4>|r - Cleanup specific dock only")
            TUICD:Print("|cffffff00/tuicd dock clear <1-4>|r - Clear all assignments from a dock")
            TUICD:Print("|cffffff00/tuicd dock list|r - List all dock assignments")
            
        elseif subcmd == "cleanup" then
            if not TUICD.Modules or not TUICD.Modules.Docks then
                TUICD:PrintError("Docks module not available")
                return
            end
            local dockNum = tonumber(subargs)
            TUICD.Modules.Docks:CleanupOrphans(dockNum)
            
        elseif subcmd == "clear" then
            if not TUICD.Modules or not TUICD.Modules.Docks then
                TUICD:PrintError("Docks module not available")
                return
            end
            local dockNum = tonumber(subargs)
            if not dockNum then
                TUICD:PrintError("Usage: /tuicd dock clear <1-4>")
                return
            end
            TUICD.Modules.Docks:ClearDock(dockNum)
            
        elseif subcmd == "list" then
            TUICD:Print("|cff00ccff=== Dock Assignments ===|r")
            local totalCount = 0
            
            -- List BuffHighlights dock assignments
            local buffDB = TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB.buffHighlights
            if buffDB and buffDB.dockAssignment then
                for slotIndex, dockIndex in pairs(buffDB.dockAssignment) do
                    if dockIndex then
                        TUICD:Print(string.format("  Dock %d: |cffffff00buffs|r slot %d", dockIndex, slotIndex))
                        totalCount = totalCount + 1
                    end
                end
            end
            
            -- List CooldownHighlights dock assignments
            for _, trackerKey in ipairs({"essential", "utility", "customTrackers"}) do
                local db = TweaksUI_Cooldowns_CharDB and TweaksUI_Cooldowns_CharDB[trackerKey .. "Highlights"]
                if db and db.dockAssignment then
                    for slotIndex, dockIndex in pairs(db.dockAssignment) do
                        if dockIndex then
                            TUICD:Print(string.format("  Dock %d: |cffffff00%s|r slot %d", dockIndex, trackerKey, slotIndex))
                            totalCount = totalCount + 1
                        end
                    end
                end
            end
            
            if totalCount == 0 then
                TUICD:Print("  (no dock assignments)")
            else
                TUICD:Print(string.format("Total: %d assignment(s)", totalCount))
            end
        else
            TUICD:Print("Unknown dock command: " .. subcmd)
            TUICD:Print("Type /tuicd dock help for commands")
        end
        
    else
        TUICD:Print("Unknown command: " .. cmd)
        TUICD:Print("Type /tuicd help for commands")
    end
end

-- Register slash commands
for _, cmd in ipairs(TUICD.SLASH_COMMANDS) do
    local cmdName = cmd:upper():gsub("/", "")
    _G["SLASH_" .. cmdName .. "1"] = cmd
    SlashCmdList[cmdName] = HandleSlashCommand
end

-- Additional standalone commands
SLASH_TUICDLAYOUT1 = "/tuicdlayout"
SlashCmdList["TUICDLAYOUT"] = function(msg)
    local subcmd = msg:lower():match("^(%S*)") or ""
    
    if subcmd == "grid" then
        if TUICD.Layout then
            TUICD.Layout:ToggleGrid()
        end
    else
        if TUICD.Layout then
            TUICD.Layout:Toggle()
        end
    end
end

-- Quick reload command
SLASH_RL1 = "/rl"
SlashCmdList["RL"] = function()
    ReloadUI()
end

-- Edit Mode shortcut
SLASH_EM1 = "/em"
SlashCmdList["EM"] = function()
    if EditModeManagerFrame then
        if EditModeManagerFrame:IsShown() then
            HideUIPanel(EditModeManagerFrame)
        else
            ShowUIPanel(EditModeManagerFrame)
        end
    end
end

-- Blizzard Cooldown Manager shortcut
SLASH_CDM1 = "/cdm"
SlashCmdList["CDM"] = function()
    -- CooldownViewerSettings is Blizzard's Cooldown Settings frame
    local cooldownFrame = CooldownViewerSettings or _G["CooldownViewerSettings"]
    
    if cooldownFrame then
        if cooldownFrame:IsShown() then
            cooldownFrame:Hide()
        else
            cooldownFrame:Show()
        end
    else
        TUICD:PrintError("Cooldown Settings not available.")
    end
end
