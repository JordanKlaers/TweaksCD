-- ============================================================================
-- TweaksUI: Cooldowns - Profiles
-- Profile save/load/switch/dirty tracking system
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.Profiles = {}
local Profiles = TUICD.Profiles

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local PROFILE_VERSION = "1.0.0"

-- ============================================================================
-- INTERNAL STATE
-- ============================================================================

local profileLoadedHash = nil
local lastLoadedProfile = nil
local isDirty = false

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Deep copy a table
local function DeepCopy(orig)
    if type(orig) ~= "table" then
        return orig
    end
    local copy = {}
    for k, v in pairs(orig) do
        copy[DeepCopy(k)] = DeepCopy(v)
    end
    return copy
end

-- Simple hash function for dirty detection
local function SerializeForHash(tbl, depth)
    depth = depth or 0
    if depth > 50 then return "MAX_DEPTH" end
    
    if type(tbl) ~= "table" then
        return tostring(tbl)
    end
    
    -- Sort keys for consistent hashing
    local keys = {}
    for k in pairs(tbl) do
        table.insert(keys, k)
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    
    local parts = {}
    for _, k in ipairs(keys) do
        local v = tbl[k]
        table.insert(parts, tostring(k) .. "=" .. SerializeForHash(v, depth + 1))
    end
    
    return "{" .. table.concat(parts, ",") .. "}"
end

local function HashSettings(settings)
    local str = SerializeForHash(settings)
    local hash = 0
    for i = 1, #str do
        hash = (hash * 31 + string.byte(str, i)) % 2147483647
    end
    return tostring(hash)
end

-- ============================================================================
-- DATABASE HELPERS
-- ============================================================================

-- Ensure profile storage exists in account-wide DB
local function EnsureProfileStorage()
    if not TweaksUI_Cooldowns_DB then
        TweaksUI_Cooldowns_DB = {}
    end
    if not TweaksUI_Cooldowns_DB.profiles then
        TweaksUI_Cooldowns_DB.profiles = {}
    end
end

-- Ensure character profile tracking exists
local function EnsureCharProfileInfo()
    if not TweaksUI_Cooldowns_CharDB then
        TweaksUI_Cooldowns_CharDB = {}
    end
    if not TweaksUI_Cooldowns_CharDB.profileInfo then
        TweaksUI_Cooldowns_CharDB.profileInfo = {}
    end
    if not TweaksUI_Cooldowns_CharDB.specProfiles then
        TweaksUI_Cooldowns_CharDB.specProfiles = {
            enabled = false,
        }
    end
end

-- ============================================================================
-- CURRENT SETTINGS GATHERING
-- ============================================================================

-- Get all current tracker settings as a profile-ready table
function Profiles:GetCurrentSettings()
    EnsureCharProfileInfo()
    
    local charDb = TweaksUI_Cooldowns_CharDB
    
    return {
        -- All tracker settings
        trackers = DeepCopy(charDb.trackers or {}),
        -- Custom entries per spec
        customEntries = DeepCopy(charDb.customEntries or {}),
        -- Container positions
        containerPositions = DeepCopy(charDb.containerPositions or {}),
        -- Highlight settings
        buffHighlights = DeepCopy(charDb.buffHighlights or {}),
        essentialHighlights = DeepCopy(charDb.essentialHighlights or {}),
        utilityHighlights = DeepCopy(charDb.utilityHighlights or {}),
        customHighlights = DeepCopy(charDb.customHighlights or {}),
        -- Dynamic Docks settings
        docks = DeepCopy(charDb.docks or {}),
    }
end

-- Apply settings from a profile table to current character
function Profiles:ApplySettings(profileData)
    print("|cff00ff00[TUI:CD DEBUG]|r ApplySettings called")
    
    if not profileData then 
        print("|cff00ff00[TUI:CD DEBUG]|r No profileData!")
        return false, "No profile data" 
    end
    
    print("|cff00ff00[TUI:CD DEBUG]|r profileData has trackers: " .. tostring(profileData.trackers ~= nil))
    
    EnsureCharProfileInfo()
    
    local charDb = TweaksUI_Cooldowns_CharDB
    print("|cff00ff00[TUI:CD DEBUG]|r charDb exists: " .. tostring(charDb ~= nil))
    
    -- Apply tracker settings
    if profileData.trackers then
        print("|cff00ff00[TUI:CD DEBUG]|r Copying trackers...")
        charDb.trackers = DeepCopy(profileData.trackers)
        print("|cff00ff00[TUI:CD DEBUG]|r Trackers copied. charDb.trackers exists: " .. tostring(charDb.trackers ~= nil))
    end
    
    -- Apply custom entries
    if profileData.customEntries then
        charDb.customEntries = DeepCopy(profileData.customEntries)
    end
    
    -- Apply container positions
    if profileData.containerPositions then
        charDb.containerPositions = DeepCopy(profileData.containerPositions)
    end
    
    -- Apply highlight settings
    if profileData.buffHighlights then
        charDb.buffHighlights = DeepCopy(profileData.buffHighlights)
    end
    if profileData.essentialHighlights then
        charDb.essentialHighlights = DeepCopy(profileData.essentialHighlights)
    end
    if profileData.utilityHighlights then
        charDb.utilityHighlights = DeepCopy(profileData.utilityHighlights)
    end
    if profileData.customHighlights then
        charDb.customHighlights = DeepCopy(profileData.customHighlights)
    end
    
    -- Apply Dynamic Docks settings
    if profileData.docks then
        charDb.docks = DeepCopy(profileData.docks)
    end
    
    print("|cff00ff00[TUI:CD DEBUG]|r All settings applied to charDb")
    
    -- Fire settings changed event
    if TUICD.Events then
        TUICD.Events:Fire(TUICD.EVENTS.TRACKER_SETTINGS_CHANGED, nil, nil, nil)
    end
    
    -- Refresh Docks if available
    if TUICD.Docks and TUICD.Docks.RefreshAllDocks then
        TUICD.Docks:RefreshAllDocks()
    end
    
    print("|cff00ff00[TUI:CD DEBUG]|r ApplySettings completed successfully")
    return true
end

-- ============================================================================
-- PROFILE OPERATIONS
-- ============================================================================

-- Save current settings as a named profile
function Profiles:SaveProfile(name)
    if not name or name == "" then
        return false, "Profile name is required"
    end
    
    EnsureProfileStorage()
    
    local currentSettings = self:GetCurrentSettings()
    
    TweaksUI_Cooldowns_DB.profiles[name] = {
        version = PROFILE_VERSION,
        created = TweaksUI_Cooldowns_DB.profiles[name] and TweaksUI_Cooldowns_DB.profiles[name].created or time(),
        modified = time(),
        trackers = currentSettings.trackers,
        customEntries = currentSettings.customEntries,
        containerPositions = currentSettings.containerPositions,
        buffHighlights = currentSettings.buffHighlights,
        essentialHighlights = currentSettings.essentialHighlights,
        utilityHighlights = currentSettings.utilityHighlights,
        customHighlights = currentSettings.customHighlights,
        docks = currentSettings.docks,
    }
    
    -- Update tracking
    self:SetLoadedProfile(name, currentSettings)
    
    TUICD:Print("Profile saved: |cff00ff00" .. name .. "|r")
    return true
end

-- Load a named profile
function Profiles:LoadProfile(name, skipWarning)
    EnsureProfileStorage()
    
    print("|cff00ff00[TUI:CD DEBUG]|r LoadProfile called: name='" .. tostring(name) .. "', skipWarning=" .. tostring(skipWarning))
    
    local profile = TweaksUI_Cooldowns_DB.profiles[name]
    if not profile then
        print("|cff00ff00[TUI:CD DEBUG]|r Profile NOT FOUND in DB!")
        -- List available profiles
        print("|cff00ff00[TUI:CD DEBUG]|r Available profiles:")
        for pname, _ in pairs(TweaksUI_Cooldowns_DB.profiles or {}) do
            print("|cff00ff00[TUI:CD DEBUG]|r   - '" .. tostring(pname) .. "'")
        end
        return false, "Profile not found: " .. name
    end
    
    print("|cff00ff00[TUI:CD DEBUG]|r Profile found, applying settings...")
    
    -- Check for unsaved changes
    if not skipWarning and self:IsDirty() then
        print("|cff00ff00[TUI:CD DEBUG]|r Dirty check triggered, returning warning")
        return false, "DIRTY_WARNING", lastLoadedProfile
    end
    
    -- Apply the profile
    local success, err = self:ApplySettings(profile)
    if not success then
        print("|cff00ff00[TUI:CD DEBUG]|r ApplySettings FAILED: " .. tostring(err))
        return false, err
    end
    
    print("|cff00ff00[TUI:CD DEBUG]|r ApplySettings succeeded")
    
    -- Ensure all new default settings exist (for profiles saved on older versions)
    if TUICD.Database and TUICD.Database.EnsureDefaults then
        TUICD.Database:EnsureDefaults()
    end
    
    -- Update tracking
    self:SetLoadedProfile(name, self:GetCurrentSettings())
    
    print("|cff00ff00[TUI:CD DEBUG]|r SetLoadedProfile called, lastLoadedProfile now: " .. tostring(lastLoadedProfile))
    
    TUICD:Print("Profile loaded: |cff00ff00" .. name .. "|r")
    
    return true, "NEEDS_RELOAD"
end

-- Delete a profile
function Profiles:DeleteProfile(name)
    EnsureProfileStorage()
    
    if not TweaksUI_Cooldowns_DB.profiles[name] then
        return false, "Profile not found"
    end
    
    -- Don't allow deleting the currently loaded profile
    if name == lastLoadedProfile then
        return false, "Cannot delete the currently loaded profile"
    end
    
    TweaksUI_Cooldowns_DB.profiles[name] = nil
    TUICD:Print("Profile deleted: |cffff8800" .. name .. "|r")
    return true
end

-- Duplicate a profile
function Profiles:DuplicateProfile(sourceName, newName)
    EnsureProfileStorage()
    
    if TweaksUI_Cooldowns_DB.profiles[newName] then
        return false, "A profile with that name already exists"
    end
    
    local source = TweaksUI_Cooldowns_DB.profiles[sourceName]
    if not source then
        return false, "Source profile not found"
    end
    
    TweaksUI_Cooldowns_DB.profiles[newName] = {
        version = PROFILE_VERSION,
        created = time(),
        modified = time(),
        trackers = DeepCopy(source.trackers or {}),
        customEntries = DeepCopy(source.customEntries or {}),
        containerPositions = DeepCopy(source.containerPositions or {}),
        buffHighlights = DeepCopy(source.buffHighlights or {}),
        essentialHighlights = DeepCopy(source.essentialHighlights or {}),
        utilityHighlights = DeepCopy(source.utilityHighlights or {}),
        customHighlights = DeepCopy(source.customHighlights or {}),
    }
    
    TUICD:Print("Profile duplicated: |cff00ff00" .. newName .. "|r")
    return true
end

-- Rename a profile
function Profiles:RenameProfile(oldName, newName)
    EnsureProfileStorage()
    
    if not TweaksUI_Cooldowns_DB.profiles[oldName] then
        return false, "Profile not found"
    end
    
    if TweaksUI_Cooldowns_DB.profiles[newName] then
        return false, "A profile with that name already exists"
    end
    
    if oldName == newName then
        return true  -- Nothing to do
    end
    
    -- Copy and delete
    TweaksUI_Cooldowns_DB.profiles[newName] = TweaksUI_Cooldowns_DB.profiles[oldName]
    TweaksUI_Cooldowns_DB.profiles[newName].modified = time()
    TweaksUI_Cooldowns_DB.profiles[oldName] = nil
    
    -- Update tracking if this was the loaded profile
    if lastLoadedProfile == oldName then
        lastLoadedProfile = newName
        EnsureCharProfileInfo()
        TweaksUI_Cooldowns_CharDB.profileInfo.basedOn = newName
    end
    
    TUICD:Print("Profile renamed: |cff00ff00" .. newName .. "|r")
    return true
end

-- Get list of all profiles
function Profiles:GetProfileList()
    EnsureProfileStorage()
    
    local list = {}
    
    for name, data in pairs(TweaksUI_Cooldowns_DB.profiles) do
        table.insert(list, {
            name = name,
            created = data.created,
            modified = data.modified,
            version = data.version,
        })
    end
    
    -- Sort alphabetically
    table.sort(list, function(a, b)
        return a.name < b.name
    end)
    
    return list
end

-- Check if a profile exists
function Profiles:ProfileExists(name)
    EnsureProfileStorage()
    return TweaksUI_Cooldowns_DB.profiles[name] ~= nil
end

-- ============================================================================
-- DIRTY STATE TRACKING
-- ============================================================================

-- Set the currently loaded profile (called after save/load)
function Profiles:SetLoadedProfile(name, settingsSnapshot)
    lastLoadedProfile = name
    profileLoadedHash = HashSettings(settingsSnapshot or self:GetCurrentSettings())
    isDirty = false
    
    TUICD:PrintDebug("SetLoadedProfile: " .. tostring(name) .. ", hash=" .. tostring(profileLoadedHash))
    
    EnsureCharProfileInfo()
    TweaksUI_Cooldowns_CharDB.profileInfo.basedOn = name
    TweaksUI_Cooldowns_CharDB.profileInfo.loadedAt = time()
    TweaksUI_Cooldowns_CharDB.profileInfo.loadedHash = profileLoadedHash
end

-- Mark settings as potentially dirty (call when any setting changes)
function Profiles:MarkDirty()
    if not profileLoadedHash then
        -- No profile loaded yet, nothing to compare against
        return
    end
    
    local currentHash = HashSettings(self:GetCurrentSettings())
    isDirty = (currentHash ~= profileLoadedHash)
end

-- Mark as clean (after saving)
function Profiles:MarkClean()
    profileLoadedHash = HashSettings(self:GetCurrentSettings())
    isDirty = false
    
    EnsureCharProfileInfo()
    TweaksUI_Cooldowns_CharDB.profileInfo.loadedHash = profileLoadedHash
end

-- Check if there are unsaved changes
function Profiles:IsDirty()
    -- If no profile was ever loaded, not dirty
    if not profileLoadedHash then
        TUICD:PrintDebug("IsDirty: No profileLoadedHash, returning false")
        return false
    end
    
    -- Recalculate current hash
    local currentSettings = self:GetCurrentSettings()
    local currentHash = HashSettings(currentSettings)
    isDirty = (currentHash ~= profileLoadedHash)
    
    if TUICD.debugMode then
        TUICD:PrintDebug("IsDirty check:")
        TUICD:PrintDebug("  Loaded hash: " .. tostring(profileLoadedHash))
        TUICD:PrintDebug("  Current hash: " .. tostring(currentHash))
        TUICD:PrintDebug("  Is dirty: " .. tostring(isDirty))
    end
    
    return isDirty
end

-- Clear dirty state (reset hash to current state)
function Profiles:ClearDirty()
    profileLoadedHash = HashSettings(self:GetCurrentSettings())
    isDirty = false
    TUICD:PrintDebug("ClearDirty: new hash=" .. tostring(profileLoadedHash))
end

-- Get dirty state info
function Profiles:GetDirtyState()
    return {
        isDirty = self:IsDirty(),
        basedOn = lastLoadedProfile,
    }
end

-- Get the currently loaded profile name
function Profiles:GetLoadedProfileName()
    return lastLoadedProfile
end

-- ============================================================================
-- SPEC AUTO-SWITCH
-- ============================================================================

-- Get spec profile mapping for current character
function Profiles:GetSpecProfile(specIndex)
    EnsureCharProfileInfo()
    return TweaksUI_Cooldowns_CharDB.specProfiles[specIndex]
end

-- Set spec profile mapping
function Profiles:SetSpecProfile(specIndex, profileName)
    EnsureCharProfileInfo()
    TweaksUI_Cooldowns_CharDB.specProfiles[specIndex] = profileName
end

-- Check if spec auto-switch is enabled
function Profiles:IsSpecAutoSwitchEnabled()
    EnsureCharProfileInfo()
    return TweaksUI_Cooldowns_CharDB.specProfiles.enabled == true
end

-- Set spec auto-switch enabled
function Profiles:SetSpecAutoSwitchEnabled(enabled)
    EnsureCharProfileInfo()
    TweaksUI_Cooldowns_CharDB.specProfiles.enabled = enabled
end

-- Handle spec change event
function Profiles:OnSpecChanged()
    print("|cff00ff00[TUI:CD DEBUG]|r OnSpecChanged called")
    
    local enabled = self:IsSpecAutoSwitchEnabled()
    print("|cff00ff00[TUI:CD DEBUG]|r Auto-switch enabled: " .. tostring(enabled))
    
    if not enabled then
        return
    end
    
    local specIndex = GetSpecialization()
    print("|cff00ff00[TUI:CD DEBUG]|r Current spec index: " .. tostring(specIndex))
    
    if not specIndex then 
        print("|cff00ff00[TUI:CD DEBUG]|r No spec index, aborting")
        return 
    end
    
    local profileName = self:GetSpecProfile(specIndex)
    print("|cff00ff00[TUI:CD DEBUG]|r Profile for spec " .. specIndex .. ": " .. tostring(profileName))
    
    if not profileName then 
        print("|cff00ff00[TUI:CD DEBUG]|r No profile assigned, aborting")
        return 
    end
    
    print("|cff00ff00[TUI:CD DEBUG]|r lastLoadedProfile: " .. tostring(lastLoadedProfile))
    
    -- Check if we're already on this profile
    if profileName == lastLoadedProfile then
        print("|cff00ff00[TUI:CD DEBUG]|r Already on this profile, skipping")
        return
    end
    
    print("|cff00ff00[TUI:CD DEBUG]|r Will switch from '" .. tostring(lastLoadedProfile) .. "' to '" .. profileName .. "'")
    
    -- For spec auto-switch, just switch without asking about dirty state
    local success, result = self:LoadProfile(profileName, true)
    print("|cff00ff00[TUI:CD DEBUG]|r LoadProfile returned: success=" .. tostring(success) .. ", result=" .. tostring(result))
    
    if success then
        TUICD:Print("Auto-switched to profile: |cff00ff00" .. profileName .. "|r (spec change)")
        self:ShowReloadDialog(profileName)
    else
        TUICD:PrintError("Failed to switch profile: " .. tostring(result))
    end
end

-- Show reload dialog after profile switch
function Profiles:ShowReloadDialog(profileName)
    StaticPopupDialogs["TUICD_PROFILE_RELOAD"] = {
        text = "Profile '" .. profileName .. "' has been loaded.\n\nA UI reload is required to fully apply the new settings.",
        button1 = "Reload Now",
        button2 = "Later",
        OnAccept = function()
            ReloadUI()
        end,
        OnCancel = function()
            TUICD:Print("|cffffcc00Reminder:|r Type |cff00ff00/rl|r to reload when ready.")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("TUICD_PROFILE_RELOAD")
end

-- Show dialog when spec switch is blocked due to dirty profile
function Profiles:ShowSpecSwitchBlockedDialog(specIndex, targetProfile)
    -- Store the current profile name for saving
    local currentProfileName = lastLoadedProfile
    
    StaticPopupDialogs["TUICD_SPEC_SWITCH_DIRTY"] = {
        text = "You have unsaved changes to your current profile.\n\nSwitch to '" .. targetProfile .. "'?",
        button1 = "Save & Switch",
        button2 = "Discard & Switch", 
        button3 = "Cancel",
        OnAccept = function()
            -- Save current settings to the current profile, then switch
            if currentProfileName then
                Profiles:SaveProfile(currentProfileName)
                TUICD:Print("Saved changes to: |cff00ff00" .. currentProfileName .. "|r")
            end
            local success = Profiles:LoadProfile(targetProfile, true)
            if success then
                TUICD:Print("Switched to profile: |cff00ff00" .. targetProfile .. "|r")
                Profiles:ShowReloadDialog(targetProfile)
            end
        end,
        OnCancel = function()
            -- "Discard & Switch" - clear dirty state and switch
            Profiles:ClearDirty()
            local success = Profiles:LoadProfile(targetProfile, true)
            if success then
                TUICD:Print("Switched to profile: |cff00ff00" .. targetProfile .. "|r (changes discarded)")
                Profiles:ShowReloadDialog(targetProfile)
            end
        end,
        OnAlt = function()
            -- "Cancel" - do nothing
            TUICD:Print("Profile switch cancelled.")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("TUICD_SPEC_SWITCH_DIRTY")
end

-- ============================================================================
-- IMPORT/EXPORT
-- ============================================================================

-- Export current settings as a string
function Profiles:ExportProfile(profileName)
    EnsureProfileStorage()
    
    local profile
    if profileName then
        profile = TweaksUI_Cooldowns_DB.profiles[profileName]
        if not profile then
            return nil, "Profile not found"
        end
    else
        -- Export current settings
        profile = self:GetCurrentSettings()
        profile.version = PROFILE_VERSION
        profile.exportedAt = time()
    end
    
    -- Add metadata
    local exportData = {
        addon = "TweaksUI_Cooldowns",
        version = PROFILE_VERSION,
        exportedAt = time(),
        profile = profile,
    }
    
    -- Serialize
    local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
    if not LibDeflate then
        return nil, "LibDeflate not available"
    end
    
    -- Convert to string
    local serialized = TUICD.Utilities:TableToString(exportData)
    if not serialized then
        return nil, "Failed to serialize profile"
    end
    
    -- Compress
    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then
        return nil, "Failed to compress profile"
    end
    
    -- Encode for sharing
    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return nil, "Failed to encode profile"
    end
    
    return "!TUICD1!" .. encoded, nil
end

-- Import settings from a string
function Profiles:ImportProfile(importString, profileName)
    if not importString or importString == "" then
        return nil, "Import string is empty"
    end
    
    -- Check header
    if not importString:match("^!TUICD1!") then
        return nil, "Invalid import string format"
    end
    
    local encoded = importString:gsub("^!TUICD1!", "")
    
    local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
    if not LibDeflate then
        return nil, "LibDeflate not available"
    end
    
    -- Decode
    local compressed = LibDeflate:DecodeForPrint(encoded)
    if not compressed then
        return nil, "Failed to decode import string"
    end
    
    -- Decompress
    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return nil, "Failed to decompress import string"
    end
    
    -- Deserialize
    local importData = TUICD.Utilities:StringToTable(serialized)
    if not importData then
        return nil, "Failed to deserialize import data"
    end
    
    -- Validate
    if importData.addon ~= "TweaksUI_Cooldowns" then
        return nil, "This is not a TweaksUI: Cooldowns profile"
    end
    
    if not importData.profile then
        return nil, "Import data missing profile"
    end
    
    -- Return validated profile data for the UI to save
    return importData.profile, nil
end

-- Save an imported profile
function Profiles:SaveImportedProfile(profileData, profileName)
    if not profileName or profileName == "" then
        return false, "Profile name is required"
    end
    
    EnsureProfileStorage()
    
    if TweaksUI_Cooldowns_DB.profiles[profileName] then
        return false, "A profile with that name already exists"
    end
    
    TweaksUI_Cooldowns_DB.profiles[profileName] = {
        version = PROFILE_VERSION,
        created = time(),
        modified = time(),
        imported = true,
        trackers = DeepCopy(profileData.trackers or {}),
        customEntries = DeepCopy(profileData.customEntries or {}),
        containerPositions = DeepCopy(profileData.containerPositions or {}),
        buffHighlights = DeepCopy(profileData.buffHighlights or {}),
        essentialHighlights = DeepCopy(profileData.essentialHighlights or {}),
        utilityHighlights = DeepCopy(profileData.utilityHighlights or {}),
        customHighlights = DeepCopy(profileData.customHighlights or {}),
    }
    
    TUICD:Print("Profile imported: |cff00ff00" .. profileName .. "|r")
    return true
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function Profiles:Initialize()
    EnsureProfileStorage()
    EnsureCharProfileInfo()
    
    -- Restore tracking state from character DB
    if TweaksUI_Cooldowns_CharDB.profileInfo.basedOn then
        lastLoadedProfile = TweaksUI_Cooldowns_CharDB.profileInfo.basedOn
        profileLoadedHash = TweaksUI_Cooldowns_CharDB.profileInfo.loadedHash
    end
    
    -- Register for spec change events
    -- Both events are needed for reliable detection across all scenarios
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    frame:SetScript("OnEvent", function(self, event, unit)
        -- PLAYER_SPECIALIZATION_CHANGED passes a unit argument
        if event == "PLAYER_SPECIALIZATION_CHANGED" and unit ~= "player" then
            return
        end
        
        -- Delay slightly to let game settle
        C_Timer.After(0.5, function()
            Profiles:OnSpecChanged()
        end)
    end)
    
    TUICD:PrintDebug("Profiles system initialized")
end
