-- ============================================================================
-- TUICD CooldownHighlights.lua
-- Creates positionable highlight clones for cooldown trackers
-- Supports: Essential Cooldowns, Utility Cooldowns, Custom Trackers
-- Active = ability ready (off cooldown), Inactive = on cooldown
-- ============================================================================

local addonName, TUICD = ...
TUICD.CooldownHighlights = TUICD.CooldownHighlights or {}
local CooldownHighlights = TUICD.CooldownHighlights

local RadialSwipe = TUICD.RadialSwipe or {}


-- ============================================================================
-- CONSTANTS
-- ============================================================================

local DEFAULT_SIZE = 48

-- Tracker definitions
local TRACKER_TYPES = {
    essential = {
        key = "essential",
        viewerName = "EssentialCooldownViewer",
        displayName = "Essential Cooldowns",
        framePrefix = "TweaksUI_EssentialHighlight_",
        dbKey = "essentialHighlights",
    },
    utility = {
        key = "utility",
        viewerName = "UtilityCooldownViewer",
        displayName = "Utility Cooldowns",
        framePrefix = "TweaksUI_UtilityHighlight_",
        dbKey = "utilityHighlights",
    },
    custom = {
        key = "custom",
        viewerName = "TweaksUI_CustomTrackerFrame",
        displayName = "Custom Trackers",
        framePrefix = "TweaksUI_CustomHighlight_",
        dbKey = "customHighlights",
    },
}

-- ============================================================================
-- STATE (per tracker type)
-- ============================================================================

local highlightFrames = {
    essential = {},
    utility = {},
    custom = {},
}

-- ============================================================================
-- SPELL ID CACHE (populated outside combat, used during combat)
-- This is critical for Midnight compatibility - we can't read spellIDs from
-- Blizzard's CDM icons during combat due to secret values
-- ============================================================================

local spellIDCache = {
    essential = {},  -- [slotIndex] = spellID
    utility = {},
    custom = {},
}

-- Track when cache was last updated
local cacheLastUpdated = {
    essential = 0,
    utility = 0,
    custom = 0,
}

local layoutWrappers = {
    essential = {},
    utility = {},
    custom = {},
}

local isInitialized = {}

-- Throttle state for UpdateAllHighlights
local throttleState = {
    lastUpdate = {},      -- [trackerKey] = timestamp
    pendingUpdate = {},   -- [trackerKey] = true/false
    throttleDelay = 0.1,  -- 100ms throttle (10 Hz max update rate)
}
-- ============================================================================
-- DATABASE
-- ============================================================================

local function GetDB(trackerKey)
    if not TweaksUI_Cooldowns_CharDB then TweaksUI_Cooldowns_CharDB = {} end
    
    local trackerType = TRACKER_TYPES[trackerKey]
    if not trackerType then return nil end
    
    local dbKey = trackerType.dbKey
    if not TweaksUI_Cooldowns_CharDB[dbKey] then
        TweaksUI_Cooldowns_CharDB[dbKey] = {
            hideTracker = false,
            enabled = {},
            positions = {},
            active = {
                size = {},
                opacity = {},
                saturation = {},
                aspectRatio = {},
                customAspectW = {},
                customAspectH = {},
                show = {},
            },
            inactive = {
                size = {},
                opacity = {},
                saturation = {},
                aspectRatio = {},
                customAspectW = {},
                customAspectH = {},
                show = {},
            },
        }
    end
    
    local db = TweaksUI_Cooldowns_CharDB[dbKey]
    -- Ensure all fields exist
    if not db.enabled then db.enabled = {} end
    if not db.positions then db.positions = {} end
    
    -- Ensure state tables exist and are actually tables (not booleans from old versions)
    if type(db.active) ~= "table" then
        db.active = {}
    end
    if type(db.inactive) ~= "table" then
        db.inactive = {}
    end
    
    for _, state in ipairs({"active", "inactive"}) do
        -- Double-check state is a table before accessing nested properties
        if type(db[state]) ~= "table" then
            db[state] = {}
        end
        
        if not db[state].size then db[state].size = {} end
        if not db[state].opacity then db[state].opacity = {} end
        if not db[state].saturation then db[state].saturation = {} end
        if not db[state].aspectRatio then db[state].aspectRatio = {} end
        if not db[state].customAspectW then db[state].customAspectW = {} end
        if not db[state].customAspectH then db[state].customAspectH = {} end
        if not db[state].show then db[state].show = {} end
    end
    
    -- Custom label fields (state-independent)
    if not db.labelEnabled then db.labelEnabled = {} end
    if not db.labelText then db.labelText = {} end
    if not db.labelFontSize then db.labelFontSize = {} end
    if not db.labelColor then db.labelColor = {} end
    if not db.labelOffsetX then db.labelOffsetX = {} end
    if not db.labelOffsetY then db.labelOffsetY = {} end
    
    -- Text scale fields (state-independent)
    if not db.cooldownTextScale then db.cooldownTextScale = {} end
    if not db.cooldownTextColor then db.cooldownTextColor = {} end
    if not db.cooldownTextOffsetX then db.cooldownTextOffsetX = {} end
    if not db.cooldownTextOffsetY then db.cooldownTextOffsetY = {} end
    if not db.cooldownTextAnchor then db.cooldownTextAnchor = {} end
    if not db.countTextScale then db.countTextScale = {} end
    if not db.countTextColor then db.countTextColor = {} end
    if not db.countTextOffsetX then db.countTextOffsetX = {} end
    if not db.countTextOffsetY then db.countTextOffsetY = {} end
    if not db.countTextAnchor then db.countTextAnchor = {} end
    if not db.labelAnchor then db.labelAnchor = {} end
    
    -- Per-icon sweep and countdown text settings (overrides tracker-level when set)
    if not db.hideSweep then db.hideSweep = {} end
    if not db.showCountdownText then db.showCountdownText = {} end
    
    -- Hidden icons (state-independent) - hides icon from tracker completely
    if not db.hidden then db.hidden = {} end
    
    -- Dock assignment (state-independent) - which dock (1-4) icon is assigned to
    if not db.dockAssignment then db.dockAssignment = {} end
    
    -- Radial swipe settings (state-independent)
    if not db.radialSwipe then db.radialSwipe = {} end
    if not db.radialSwipe.displayState then db.radialSwipe.displayState = {} end
    if not db.radialSwipe.texturePath then db.radialSwipe.texturePath = {} end
    if not db.radialSwipe.color then db.radialSwipe.color = {} end
    if not db.radialSwipe.scale then db.radialSwipe.scale = {} end
    if not db.radialSwipe.offsetX then db.radialSwipe.offsetX = {} end
    if not db.radialSwipe.offsetY then db.radialSwipe.offsetY = {} end
    if not db.radialSwipe.rotation then db.radialSwipe.rotation = {} end
    
    -- Custom icon texture overrides (spell ID-based, persists across reordering)
    if not db.customIconTexture then db.customIconTexture = {} end  -- [spellID] = texturePath
    if not db.customIconColor then db.customIconColor = {} end  -- [spellID] = {r, g, b}
    
    return db
end





-- ============================================================================
-- ICON COLLECTION
-- ============================================================================

local function IsIcon(frame)
    if not frame then return false end
    if frame.Cooldown or frame.cooldown then return true end
    if frame.Icon or frame.icon then return true end
    return false
end

local function GetViewer(trackerKey)
    local trackerType = TRACKER_TYPES[trackerKey]
    if not trackerType then return nil end
    return _G[trackerType.viewerName]
end

local function CollectIcons(trackerKey)
    local icons = {}
    local viewer = GetViewer(trackerKey)
    
    if not viewer or not viewer.GetChildren then return icons end
    
    local numChildren = viewer:GetNumChildren() or 0
    
    for i = 1, numChildren do
        local child = select(i, viewer:GetChildren())
        -- Don't check IsShown - icons might briefly hide during GCD/updates
        if child and IsIcon(child) then
            icons[#icons + 1] = child
        elseif child and child.GetNumChildren then
            local numNested = child:GetNumChildren() or 0
            for j = 1, numNested do
                local nested = select(j, child:GetChildren())
                if nested and IsIcon(nested) then
                    icons[#icons + 1] = nested
                end
            end
        end
    end
    
    -- Sort by visual position (top-to-bottom, left-to-right)
    table.sort(icons, function(a, b)
        local at, bt = a:GetTop() or 0, b:GetTop() or 0
        local al, bl = a:GetLeft() or 0, b:GetLeft() or 0
        if math.abs(at - bt) > 5 then return at > bt end
        return al < bl
    end)
    
    return icons
end

-- ============================================================================
-- SPELL ID CACHE SYSTEM
-- Cache spellIDs outside of combat so we can use them during combat
-- Critical for Midnight compatibility - CDM icons have secret spellIDs in combat
-- ============================================================================

-- Extract spellID from an icon (only works reliably outside combat)
local function ExtractSpellID(icon)
    if not icon then return nil end
    
    -- Direct property access
    local spellID = icon.spellID or icon.SpellID or icon.spellId
    
    -- Try GetSpellID method
    if not spellID and icon.GetSpellID then
        pcall(function() spellID = icon:GetSpellID() end)
    end
    
    -- Custom tracker stores as trackID
    if not spellID and icon.trackType == "spell" and icon.trackID then
        spellID = icon.trackID
    end
    
    -- Check if the value is a secret (can't be used in comparisons)
    if spellID and issecretvalue and issecretvalue(spellID) then
        return nil  -- Return nil for secret values - can't cache them
    end
    
    return spellID
end

-- Cache spellIDs for a tracker (ONLY call outside combat)
local function CacheSpellIDs(trackerKey)
    if InCombatLockdown() then
        return
    end
    
    -- Use the ordered icons from Cooldowns module if available
    local icons
    local Cooldowns = TUICD.Cooldowns
    if Cooldowns and Cooldowns.GetOrderedIcons then
        local viewer = GetViewer(trackerKey)
        if viewer then
            icons = Cooldowns.GetOrderedIcons(viewer, trackerKey)
        else
            icons = {}
        end
    else
        icons = CollectIcons(trackerKey)
    end
    
    local cacheUpdated = false
    for slotIndex, icon in ipairs(icons) do
        local spellID = ExtractSpellID(icon)
        if spellID then
            -- Only update if changed (or new)
            if spellIDCache[trackerKey][slotIndex] ~= spellID then
                spellIDCache[trackerKey][slotIndex] = spellID
                cacheUpdated = true
            end
        end
    end
    
    if cacheUpdated then
        cacheLastUpdated[trackerKey] = GetTime()
    end
end

-- Get cached spellID for a slot (safe to call during combat)
local function GetCachedSpellID(trackerKey, slotIndex)
    return spellIDCache[trackerKey] and spellIDCache[trackerKey][slotIndex]
end

-- Refresh cache for all trackers (call on PLAYER_REGEN_ENABLED)
local function RefreshAllSpellIDCaches()
    if InCombatLockdown() then return end
    
    for trackerKey in pairs(TRACKER_TYPES) do
        CacheSpellIDs(trackerKey)
    end
end

-- ============================================================================
-- VISIBILITY CONDITION CHECKING
-- Per-icon highlights should respect the tracker's visibility conditions
-- ============================================================================

-- Get current player state for visibility checks (mirrors Cooldowns.lua logic)
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
        isMounted = IsMounted(),
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

-- Check if highlight should be visible based on tracker's visibility conditions
-- trackerKey: "essential", "utility", or "custom"
local function ShouldHighlightBeVisible(trackerKey)
    -- Always show in Layout Mode for positioning
    local layoutContainer = _G["TweaksUI_LayoutContainer"]
    if layoutContainer and layoutContainer:IsShown() then
        return true
    end
    
    -- Always show in Edit Mode
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        return true
    end
    
    -- Get tracker settings via Database
    if not TUICD.Database then return true end
    
    -- Map "custom" to "customTrackers" for database access
    local dbTrackerKey = (trackerKey == "custom") and "customTrackers" or trackerKey
    
    local visibilityEnabled = TUICD.Database:GetTrackerSetting(dbTrackerKey, "visibilityEnabled")
    if not visibilityEnabled then
        return true  -- Visibility system disabled = always show
    end
    
    local state = GetPlayerState()
    
    -- OR logic: if ANY checked condition is true, show the highlight
    if state.inCombat and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showInCombat") then return true end
    if not state.inCombat and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showOutOfCombat") then return true end
    if state.isSolo and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showSolo") then return true end
    if state.inGroup and not state.inRaid and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showInParty") then return true end
    if state.inRaid and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showInRaid") then return true end
    if state.inInstance and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showInInstance") then return true end
    if state.inArena and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showInArena") then return true end
    if state.inBattleground and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showInBattleground") then return true end
    if state.hasTarget and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showHasTarget") then return true end
    if not state.hasTarget and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showNoTarget") then return true end
    if state.isMounted and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showMounted") then return true end
    if not state.isMounted and TUICD.Database:GetTrackerSetting(dbTrackerKey, "showNotMounted") then return true end
    
    -- No conditions matched
    return false
end

-- ============================================================================
-- VISUAL STATE DETECTION
-- ============================================================================

-- Cooldowns longer than 3000ms (3 sec) are "real" cooldowns, not GCD (~1500ms)
local GCD_THRESHOLD = 3000

-- Detect visual state by checking if source icon has a REAL cooldown (not GCD)
-- We check actual cooldown duration to avoid GCD false positives
-- NOTE: GetCooldownTimes returns MILLISECONDS
local function GetIconVisualState(icon)
    if not icon then return true end  -- Default to "ready" if no icon
    
    local isReady = true
    
    -- Check cooldown frame times - only count as "on cooldown" if duration > GCD threshold
    -- NOTE: GetCooldownTimes returns MILLISECONDS
    pcall(function()
        local cooldown = icon.Cooldown or icon.cooldown
        if cooldown and cooldown.GetCooldownTimes then
            local start, duration = cooldown:GetCooldownTimes()
            if start and duration and type(start) == "number" and type(duration) == "number" and duration > 0 then
                -- Only count as "on cooldown" if duration > 3000ms (3 sec)
                if duration > GCD_THRESHOLD then
                    -- Convert to seconds for remaining time check
                    local startSec = start / 1000
                    local durationSec = duration / 1000
                    local remaining = (startSec + durationSec) - GetTime()
                    if remaining > 0.1 then
                        isReady = false
                    end
                end
            end
        end
    end)
    
    return isReady
end

local function GetSlotInfo(trackerKey, slotIndex)
    -- Use TUICD.Cooldowns.GetOrderedIcons if available (same order as layout/list)
    local icons
    local Cooldowns = TUICD.Cooldowns
    if Cooldowns and Cooldowns.GetOrderedIcons then
        local viewer = GetViewer(trackerKey)
        if viewer then
            icons = Cooldowns.GetOrderedIcons(viewer, trackerKey)
        else
            icons = {}
        end
    else
        -- Fallback to local CollectIcons
        icons = CollectIcons(trackerKey)
    end
    
    local icon = icons[slotIndex]
    
    if not icon then return nil end
    
    local info = {
        icon = icon,
        isActive = true,  -- Will be set by visual state check
        texture = nil,
        name = "Slot " .. slotIndex,
    }
    
    -- Get visual state (ready vs on cooldown) without doing cooldown math
    info.isActive = GetIconVisualState(icon)
    
    -- Get texture safely
    local textureObj = icon.Icon or icon.icon
    if textureObj then
        pcall(function()
            info.texture = textureObj:GetTexture()
        end)
    end
    
    return info
end

local function GetSlotCount(trackerKey)
    -- Use TUICD.Cooldowns.GetOrderedIcons if available (same order as layout/list)
    local Cooldowns = TUICD.Cooldowns
    if Cooldowns and Cooldowns.GetOrderedIcons then
        local viewer = GetViewer(trackerKey)
        if viewer then
            return #Cooldowns.GetOrderedIcons(viewer, trackerKey)
        end
    end
    -- Fallback
    return #CollectIcons(trackerKey)
end

local function GetShouldShowCountdownText(trackerKey, slotIndex)
    local showCountdownText = CooldownHighlights:GetState(trackerKey, "showCountdownText." .. slotIndex)  -- Per-icon setting
    if showCountdownText == nil and TUICD.Database then
        local countdownSetting = TUICD.Database:GetTrackerSetting(trackerKey, "showCountdownText")
        showCountdownText = (countdownSetting ~= nil) and countdownSetting or true
    end
    if showCountdownText == nil then showCountdownText = true end
    return showCountdownText
end

-- ============================================================================
-- HIGHLIGHT FRAME CREATION
-- ============================================================================

local function CreateHighlightFrame(trackerKey, slotIndex)
    if highlightFrames[trackerKey][slotIndex] then
        return highlightFrames[trackerKey][slotIndex]
    end
    
    local trackerType = TRACKER_TYPES[trackerKey]
    local frameName = trackerType.framePrefix .. slotIndex
    local size = CooldownHighlights:GetState(trackerKey, "active.size." .. slotIndex) or DEFAULT_SIZE
    
    -- Check if Masque is enabled for this tracker
    -- For custom highlights, use customTrackers setting
    local masqueTrackerKey = (trackerKey == "custom") and "customTrackers" or trackerKey
    local useMasque = TUICD.Cooldowns and TUICD.Cooldowns.IsMasqueAvailable and TUICD.Cooldowns:IsMasqueAvailable()
    local masqueEnabled = useMasque and TUICD.Database and TUICD.Database:GetTrackerSetting(masqueTrackerKey, "useMasque")
    
    local frame = CreateFrame("Button", frameName, UIParent, "BackdropTemplate")
    frame:SetSize(size, size)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(100)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    
    -- Background (hide if Masque is enabled)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    
    if masqueEnabled then
        frame:SetBackdropColor(0, 0, 0, 0)
        frame:SetBackdropBorderColor(0, 0, 0, 0)
    else
        frame:SetBackdropColor(0, 0, 0, 0.6)
        frame:SetBackdropBorderColor(0, 0, 0, 1)
    end
    
    -- Icon texture
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.Icon = frame.icon  -- Masque expects .Icon
    if masqueEnabled then
        frame.icon:SetAllPoints(frame)
        frame.icon:SetTexCoord(0, 1, 0, 1)
    else
        frame.icon:SetPoint("TOPLEFT", 2, -2)
        frame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    

    -- Create radial swipe for cooldown animation (matches DebugTest configuration)
    RadialSwipe:InitializeRadialSwipe(frame, size)
    
    -- Apply custom texture from DB if set, otherwise use default
    local radialTexture = CooldownHighlights:GetState(trackerKey, "radialSwipe.texturePath." .. slotIndex)
    if radialTexture and radialTexture ~= "" then
        frame.radialSwipe:SetTexture(radialTexture)
    end
    
    
    -- TODO: implement the cooldown swipe considering performance - frame:SetScript("OnUpdate", function(self) RadialSwipe:OnUpdate(self) end)

    -- Cooldown spiral (uses CooldownFrameTemplate which includes countdown text)
    frame.cooldown = CreateFrame("Cooldown", frameName .. "_Cooldown", frame, "CooldownFrameTemplate")
    frame.Cooldown = frame.cooldown  -- Masque expects .Cooldown
    frame.cooldown:SetAllPoints(frame.icon)
    frame.cooldown:SetDrawEdge(not masqueEnabled)  -- Masque handles edge
    frame.cooldown:SetDrawBling(false)
    frame.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    
    frame.cooldown._TUI_trackerKey = trackerKey
    frame.cooldown._TUI_slotIndex = slotIndex
    frame.cooldown:SetScript("OnCooldownDone", function(self)
        CooldownHighlights:UpdateHighlightFrame(self._TUI_trackerKey, self._TUI_slotIndex)
    end)
    
    -- Apply sweep and countdown text settings (per-icon overrides tracker-level)
    local hideSweep = CooldownHighlights:GetState(trackerKey, "hideSweep." .. slotIndex)  -- Per-icon setting (true=hide, false=show, nil=use tracker default)
    
    
    -- Handle sweep visibility with proper hierarchy
    if hideSweep == nil then
        -- Per-icon not set, check tracker-level hideSweep setting
        if TUICD.Database then
            local trackerHideSweep = TUICD.Database:GetTrackerSetting(trackerKey, "hideSweep")
            hideSweep = (trackerHideSweep == true)  -- Use tracker setting
        else
            hideSweep = false  -- Default to showing sweep
        end
    end
    
    local showCountdownText = GetShouldShowCountdownText(trackerKey, slotIndex)
    
    frame.cooldown:SetDrawSwipe(not hideSweep)  -- Invert: hideSweep=true means don't draw
    frame.cooldown:SetDrawEdge(not hideSweep)
    -- upon creation, the frame hides the cooldown text untill it can be determined it should be shown.
    frame.cooldown:SetHideCountdownNumbers(true)
    
    -- Store settings on cooldown for hooks to use
    frame.cooldown._TUI_hideSweep = hideSweep
    frame.cooldown._TUI_showCountdownText = showCountdownText
    frame.cooldown._TUI_trackerKey = trackerKey
    frame.cooldown._TUI_slotIndex = slotIndex
    frame.cooldown.hideCountdownText = true  -- Start with countdown text hidden
    
    -- Hook SetCooldown to reapply settings after Blizzard updates
    hooksecurefunc(frame.cooldown, "SetCooldown", function(self)
        pcall(function()
            self:SetDrawSwipe(not self._TUI_hideSweep)
            self:SetDrawEdge(not self._TUI_hideSweep)
            self:SetHideCountdownNumbers(self.hideCountdownText)
        end)
    end)
    -- Also hook SetCooldownFromDurationObject for Midnight API
    if frame.cooldown.SetCooldownFromDurationObject then
        hooksecurefunc(frame.cooldown, "SetCooldownFromDurationObject", function(self)
            pcall(function()
                self:SetDrawSwipe(not self._TUI_hideSweep)
                self:SetDrawEdge(not self._TUI_hideSweep)
                self:SetHideCountdownNumbers(self.hideCountdownText)
            end)
        end)
    end
    
    -- Charge/stack count text (bottom right corner, explicitly above cooldown)
    frame.count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    frame.Count = frame.count  -- Masque expects .Count
    frame.count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.count:SetJustifyH("RIGHT")
    frame.count:SetDrawLayer("OVERLAY", 7)  -- High sublayer to ensure above cooldown text
    
    -- Border texture for Masque
    frame.Border = frame:CreateTexture(nil, "OVERLAY")
    frame.Border:SetAllPoints(frame)
    frame.Border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.Border:SetBlendMode("ADD")
    frame.Border:SetAlpha(0)  -- Hidden, Masque controls this
    
    -- Proc glow overlay (using Blizzard's built-in glow)
    -- We'll use ActionButton overlay glow system if available
    frame.glowFrame = CreateFrame("Frame", frameName .. "_Glow", frame)
    frame.glowFrame:SetAllPoints()
    frame.glowFrame:SetFrameLevel(frame:GetFrameLevel() + 5)
    frame.glowFrame:Hide()
    
    -- Create the glow texture (yellow spell activation border)
    frame.glowTexture = frame.glowFrame:CreateTexture(nil, "OVERLAY")
    frame.glowTexture:SetPoint("TOPLEFT", -8, 8)
    frame.glowTexture:SetPoint("BOTTOMRIGHT", 8, -8)
    frame.glowTexture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.glowTexture:SetBlendMode("ADD")
    frame.glowTexture:SetVertexColor(1, 1, 0.6, 0.8)
    
    -- Animated glow ants (the spinning border effect)
    frame.glowAnts = frame.glowFrame:CreateTexture(nil, "OVERLAY")
    frame.glowAnts:SetPoint("TOPLEFT", -4, 4)
    frame.glowAnts:SetPoint("BOTTOMRIGHT", 4, -4)
    frame.glowAnts:SetTexture("Interface\\Cooldown\\star4")
    frame.glowAnts:SetBlendMode("ADD")
    frame.glowAnts:SetVertexColor(1, 1, 0.5, 0.6)
    
    -- Animation group for the glow
    frame.glowAnim = frame.glowAnts:CreateAnimationGroup()
    frame.glowAnim:SetLooping("REPEAT")
    local rotation = frame.glowAnim:CreateAnimation("Rotation")
    rotation:SetDegrees(-360)
    rotation:SetDuration(4)
    
    -- Custom accessibility label (user-defined text overlay)
    frame.customLabel = frame:CreateFontString(nil, "OVERLAY")
    frame.customLabel:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    frame.customLabel:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.customLabel:SetTextColor(1, 1, 1, 1)
    frame.customLabel:SetShadowOffset(1, -1)
    frame.customLabel:SetShadowColor(0, 0, 0, 1)
    frame.customLabel:SetDrawLayer("OVERLAY", 7)
    frame.customLabel:Hide()
    
    -- Store references
    frame.trackerKey = trackerKey
    frame.slotIndex = slotIndex
    frame._TUI_useMasque = masqueEnabled
    
    -- Set initial position
    local pos = CooldownHighlights:GetState(trackerKey, "position." .. slotIndex)
    if pos then
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", -200 + (slotIndex * 60), -150)
    end
    
    frame:Show()
    highlightFrames[trackerKey][slotIndex] = frame
    
    -- Register with LayoutMode for drag support
    if TUICD.LayoutMode and TUICD.LayoutMode.RegisterPerIconFrame then
        local trackerType = TRACKER_TYPES[trackerKey]
        local displayName = (trackerType and trackerType.displayName or trackerKey) .. " Icon " .. slotIndex
        TUICD.LayoutMode:RegisterPerIconFrame(frame, trackerKey, slotIndex, displayName)
    end
    
    -- Add to Masque group if enabled
    if masqueEnabled then
        local masqueGroup = TUICD.Cooldowns:GetMasqueGroup(masqueTrackerKey)
        if masqueGroup then
            masqueGroup:AddButton(frame, {
                Icon = frame.icon,
                Cooldown = frame.cooldown,
                Count = frame.count,
                Border = frame.Border,
            })
            frame._TUI_MasqueGroup = masqueTrackerKey
        end
    end
    CooldownHighlights:UpdateFrameConfigurationChanges(trackerKey, slotIndex, GetDB(trackerKey) or {})

    return frame
end

-- ============================================================================
-- ASPECT RATIO
-- ============================================================================

local function ParseAspectRatio(aspectStr, trackerKey, slotIndex, state)
    if aspectStr == "custom" then
        local db = GetDB(trackerKey)
        local w = db and db[state].customAspectW[slotIndex] or 1
        local h = db and db[state].customAspectH[slotIndex] or 1
        return w, h
    end
    
    local w, h = aspectStr:match("(%d+):(%d+)")
    if w and h then
        return tonumber(w), tonumber(h)
    end
    return 1, 1
end

-- ============================================================================
-- UPDATE LOGIC
-- ============================================================================
local function CalculateFrameCooldown(trackerKey, slotIndex)
    local frame = highlightFrames[trackerKey][slotIndex]
    if not frame then return end
    local slotInfo = GetSlotInfo(trackerKey, slotIndex)
    local sourceIcon = slotInfo and slotInfo.icon or {}
    local spellID = sourceIcon.spellID or sourceIcon.SpellID or sourceIcon.spellId
    if not spellID and sourceIcon.GetSpellID then
        pcall(function() spellID = sourceIcon:GetSpellID() end)
    end
    -- Fallback for custom tracker icons: they store spellID as trackID when trackType == "spell"
    if not spellID and sourceIcon.trackType == "spell" and sourceIcon.trackID then
        spellID = sourceIcon.trackID
    end
    -- =========================================================================
    -- COOLDOWN AND CHARGE UPDATES: Use cached spellID for API calls
    -- The spellID cache is populated outside combat, so we can safely use
    -- C_Spell APIs during combat without reading from the (secret) source icon
    -- =========================================================================
    -- sourceIcon and spellID already obtained above for custom texture check
    local sourceCooldown = sourceIcon.Cooldown or sourceIcon.cooldown
    
    -- Get spellID from cache first (populated outside combat)
    -- This is critical for Midnight compatibility
    local spellID = GetCachedSpellID(trackerKey, slotIndex)
    
    -- If cache miss (shouldn't happen normally), try direct read (only works outside combat)
    if not spellID and not InCombatLockdown() then
        spellID = ExtractSpellID(sourceIcon)
        -- Update cache while we're at it
        if spellID then
            spellIDCache[trackerKey][slotIndex] = spellID
        end
    end
    
    -- For spells: Use C_Spell API (charges first, then regular cooldown)
    -- Pass directly to SetCooldownFromDurationObject - NO conditionals on Duration objects
    if spellID and C_Spell then
        -- Try charges cooldown first (for spells with charges like Fire Blast, Roll)
        if C_Spell.GetSpellChargesCooldownDuration and frame.cooldown.SetCooldownFromDurationObject then
            pcall(function()
                frame.cooldown:SetCooldownFromDurationObject(C_Spell.GetSpellChargesCooldownDuration(spellID), true)
            end)
        -- Fallback to regular cooldown duration
        elseif C_Spell.GetSpellCooldownDuration and frame.cooldown.SetCooldownFromDurationObject then
            pcall(function()
                frame.cooldown:SetCooldownFromDurationObject(C_Spell.GetSpellCooldownDuration(spellID), true)
            end)
        end
    -- For non-spells (items/equipment): Pass through from source cooldown frame
    elseif sourceCooldown and sourceCooldown.GetCooldownDuration and frame.cooldown.SetCooldownFromDurationObject then
        pcall(function()
            frame.cooldown:SetCooldownFromDurationObject(sourceCooldown:GetCooldownDuration(), true)
        end)
    end



    -- Default to "ready" (not on cooldown) - only set to true if we CONFIRM a real cooldown
    local thisIconOnCooldown = false
    
    -- Check actual cooldown duration from source cooldown
    -- NOTE: GetCooldownTimes returns MILLISECONDS
    pcall(function()
        if sourceCooldown and sourceCooldown.GetCooldownTimes then
            local start, duration = sourceCooldown:GetCooldownTimes()
            
            if start and duration and type(start) == "number" and type(duration) == "number" and duration > 0 then
                -- Only count as "on cooldown" if duration > 3000ms (3 sec) - ignore GCD (~1500ms)
                if duration > GCD_THRESHOLD then
                    -- Convert ms to seconds for comparison with GetTime()
                    local startSec = start / 1000
                    local durationSec = duration / 1000
                    local remaining = (startSec + durationSec) - GetTime()
                    if remaining > 0.1 then
                        thisIconOnCooldown = true
                    end
                end
            end
        end
    end)
    
    -- Fallback: Try frame's own cooldown
    if not thisIconOnCooldown then
        pcall(function()
            if frame.cooldown and frame.cooldown.GetCooldownTimes then
                local start, duration = frame.cooldown:GetCooldownTimes()
                
                if start and duration and type(start) == "number" and type(duration) == "number" and duration > 0 then
                    if duration > GCD_THRESHOLD then
                        local startSec = start / 1000
                        local durationSec = duration / 1000
                        local remaining = (startSec + durationSec) - GetTime()
                        if remaining > 0.1 then
                            thisIconOnCooldown = true
                        end
                    end
                end
            end
        end)
    end

    return thisIconOnCooldown
end

local function ApplyVisibilityConditions(trackerKey, slotIndex, isOnCooldown)
    local frame = highlightFrames[trackerKey][slotIndex]
    if not frame then return end
    local showInactive = CooldownHighlights:GetState(trackerKey, "inactive.show." .. slotIndex)
    local showActive = CooldownHighlights:GetState(trackerKey, "active.show." .. slotIndex)
    -- Notify dock if this icon is docked
    local dockAssignment = CooldownHighlights:GetState(trackerKey, "dockAssignment." .. slotIndex)
    if dockAssignment and TUICD.Docks then
        TUICD.Docks:NotifyIconUpdate(trackerKey, slotIndex)
    end
    
    -- Determine visibility based on confirmed cooldown state AND tracker visibility
    local trackerVisible = ShouldHighlightBeVisible(trackerKey)
    local shouldShow = trackerVisible
    if shouldShow then
        if isOnCooldown then
            -- CONFIRMED on a real cooldown (> GCD) - check if user wants inactive state shown
            if not showInactive then
                shouldShow = false
            end
        else
            -- Either ready OR couldn't confirm cooldown - treat as ready
            -- Check if user wants active state shown
            if not showActive then
                shouldShow = false
            end
        end
    end
    if isOnCooldown then
        local showCountdownText = GetShouldShowCountdownText(trackerKey, slotIndex)
        
        -- Check if this is a GCD cooldown using GetCooldownTimes (returns milliseconds)
        local isGCD = false
        if frame.cooldown and frame.cooldown.GetCooldownTimes then
            pcall(function()
                local start, duration = frame.cooldown:GetCooldownTimes()
                if start and duration and duration > 0 and duration <= GCD_THRESHOLD then
                    isGCD = true
                end
            end)
        end
        
        if isGCD then
            -- This is a GCD, hide the countdown text
            frame.cooldown.hideCountdownText = true
            frame.cooldown:SetHideCountdownNumbers(true)
        else
            -- Real cooldown, use the showCountdownText setting
            frame.cooldown.hideCountdownText = not showCountdownText
            frame.cooldown:SetHideCountdownNumbers(not showCountdownText)
        end
    else
        -- Not on cooldown, hide countdown text
        frame.cooldown.hideCountdownText = true
        frame.cooldown:SetHideCountdownNumbers(true)
    end

    if shouldShow then
        --Apply correct state's visual settings
        local actualState = isOnCooldown and "inactive" or "active"
        local actualOpacity = CooldownHighlights:GetState(trackerKey, actualState .. ".opacity." .. slotIndex) or 1.0
        local actualSaturated = CooldownHighlights:GetState(trackerKey, actualState .. ".saturated." .. slotIndex)
        if actualSaturated == nil then actualSaturated = (actualState == "active") end
        frame:Show()
        frame:SetAlpha(actualOpacity)
        frame.icon:SetDesaturated(not actualSaturated)
        frame.icon:Show()
    else
        local showRadialSwipe = CooldownHighlights:UpdateRadialSwipeVisbility(trackerKey, slotIndex, isOnCooldown, frame)        
        -- The conditions above have already determined if the radial should be visible or not        
        if showRadialSwipe then
            -- Hide icon and backdrop but keep frame visible for radial swipe
            frame.icon:Hide()
            -- Hide backdrop by making it fully transparent
            if not frame._TUI_useMasque then
                frame:SetBackdropColor(0, 0, 0, 0)
                frame:SetBackdropBorderColor(0, 0, 0, 0)
            end
            frame:Show()
        else
            -- Hide entire frame
            frame:Hide()
        end
    end
end

function CooldownHighlights:UpdateHighlightFrame(trackerKey, slotIndex)
    local frame = highlightFrames[trackerKey][slotIndex]
    if not frame then return end
    
    -- Calculate current cooldown state
    local isOnCooldown = CalculateFrameCooldown(trackerKey, slotIndex)
    
    -- Initialize state tracking on first run
    if not frame._TUI_lastCooldownState then
        frame._TUI_lastCooldownState = nil  -- nil means unknown/first run
    end
    
    -- Check if state changed (transition detected)
    local stateChanged = (frame._TUI_lastCooldownState ~= isOnCooldown)
    
    -- Early return if no state change (performance optimization)
    if not stateChanged and frame._TUI_lastCooldownState ~= nil then
        return  -- No transition, skip update
    end
    
    -- State changed or first run - update frame
    frame._TUI_lastCooldownState = isOnCooldown
    
    -- Always update visibility conditions on state change
    ApplyVisibilityConditions(trackerKey, slotIndex, isOnCooldown)
    --==========================================
    -- TODO: charge/count cooldown text, layout mode settings, proc glow, glow frame, 
    --==========================================
    
    local slotInfo = GetSlotInfo(trackerKey, slotIndex) or {}
    local sourceIcon = slotInfo.icon
    local sourceCooldown = sourceIcon.Cooldown or sourceIcon.cooldown
    local spellID = GetCachedSpellID(trackerKey, slotIndex)
    -- If cache miss (shouldn't happen normally), try direct read (only works outside combat)
    if not spellID and not InCombatLockdown() then
        spellID = ExtractSpellID(sourceIcon)
        -- Update cache while we're at it
        if spellID then
            spellIDCache[trackerKey][slotIndex] = spellID
        end
    end
    if not spellID then
        spellID = sourceIcon.spellID or sourceIcon.SpellID or sourceIcon.spellId
    end
    if not spellID and sourceIcon.GetSpellID then
        pcall(function() spellID = sourceIcon:GetSpellID() end)
    end
    -- Fallback for custom tracker icons: they store spellID as trackID when trackType == "spell"
    if not spellID and sourceIcon.trackType == "spell" and sourceIcon.trackID then
        spellID = sourceIcon.trackID
    end
    frame.secretSpellId = spellID
    -- =========================================================================
    -- CHARGE/COUNT DISPLAY: Copy count/charge text
    -- CRITICAL: No conditionals on returned values - they may be secret
    -- Just pass directly to SetText and let Blizzard handle it
    -- =========================================================================
    
    -- Method 1: Use C_Spell.GetSpellDisplayCount API for spells
    -- Pass directly to SetText - NO conditionals on the result
    if spellID and C_Spell and C_Spell.GetSpellDisplayCount then
        pcall(function()
            frame.count:SetText(C_Spell.GetSpellDisplayCount(spellID))
            frame.count:Show()
        end)
    else
        -- Method 2: Source icon's Count FontString pass-through (for items/equipment)
        local sourceCountFS = sourceIcon.Count or sourceIcon.count or sourceIcon.CountText or sourceIcon.countText
        
        -- Try cooldown frame's count if not found on icon
        if not sourceCountFS and sourceCooldown then
            sourceCountFS = sourceCooldown.Count or sourceCooldown.count or sourceCooldown.Charges or sourceCooldown.charges
        end
        
        -- Try icon's children if still not found
        if not sourceCountFS and sourceIcon.GetChildren then
            pcall(function()
                for i = 1, sourceIcon:GetNumChildren() do
                    local child = select(i, sourceIcon:GetChildren())
                    if child then
                        local childCount = child.Count or child.count
                        if childCount then
                            sourceCountFS = childCount
                            break
                        end
                    end
                end
            end)
        end
        
        -- Pass through from source FontString - NO conditionals on GetText result
        if sourceCountFS and sourceCountFS.GetText then
            pcall(function()
                frame.count:SetText(sourceCountFS:GetText())
            end)
            -- Use SetAlphaFromBoolean for visibility (handles secret booleans)
            if sourceCountFS.IsShown then
                pcall(function()
                    frame.count:SetAlphaFromBoolean(sourceCountFS:IsShown(), 1, 0)
                end)
            end
            frame.count:Show()
        else
            frame.count:SetText("")
            frame.count:Hide()
        end
    end
    
    -- =========================================================================
    -- Copy glow state from source icon (proc/spell activation glow)
    -- =========================================================================
    local showGlow = false
    
    -- First, check if per-icon proc glow is enabled (default true)
    local procGlowEnabled = CooldownHighlights:GetState(trackerKey, "showProcGlow." .. slotIndex)
    if procGlowEnabled == nil then procGlowEnabled = true end
    
    if procGlowEnabled then
        -- Method 1: Direct API check using IsSpellOverlayed (most reliable)
        if spellID and IsSpellOverlayed then
            pcall(function()
                if IsSpellOverlayed(spellID) then
                    showGlow = true
                end
            end)
        end
        
        -- Method 2: Check source icon's overlay frames (fallback)
        if not showGlow then
            pcall(function()
                -- Check for overlay glow frame (standard Blizzard glow)
                if sourceIcon.overlay and sourceIcon.overlay:IsShown() then
                    showGlow = true
                elseif sourceIcon.SpellActivationAlert and sourceIcon.SpellActivationAlert:IsShown() then
                    showGlow = true
                elseif sourceIcon.OverlayGlow and sourceIcon.OverlayGlow:IsShown() then
                    showGlow = true
                -- Check for children that might be glow frames
                elseif sourceIcon.GetChildren then
                    for i = 1, sourceIcon:GetNumChildren() do
                        local child = select(i, sourceIcon:GetChildren())
                        if child and child:IsShown() then
                            local name = child:GetName() or ""
                            if name:find("Glow") or name:find("Overlay") or name:find("Activation") then
                                showGlow = true
                                break
                            end
                        end
                    end
                end
            end)
        end
    end
    -- Apply glow state to our frame
    if frame.glowFrame then
        if showGlow then
            frame.glowFrame:Show()
            if frame.glowAnim and not frame.glowAnim:IsPlaying() then
                frame.glowAnim:Play()
            end
        else
            frame.glowFrame:Hide()
            if frame.glowAnim and frame.glowAnim:IsPlaying() then
                frame.glowAnim:Stop()
            end
        end
    end

   
    if frame.cooldown then
        local hideSweep = CooldownHighlights:GetState(trackerKey, "hideSweep." .. slotIndex)  -- Per-icon setting (true=hide, false=show, nil=use tracker default)

        -- Handle sweep visibility with proper hierarchy
        if hideSweep == nil then
            -- Per-icon not set, check tracker-level hideSweep setting
            if TUICD.Database then
                local trackerHideSweep = TUICD.Database:GetTrackerSetting(trackerKey, "hideSweep")
                hideSweep = (trackerHideSweep == true)  -- Use tracker setting
            else
                hideSweep = false  -- Default to showing sweep
            end
        end
        
        -- Apply immediately
        pcall(function()
            frame.cooldown:SetDrawSwipe(not hideSweep)  -- Invert: hideSweep=true means don't draw
            --frame.cooldown:SetHideCountdownNumbers(true) -- Cooldown text is hidden untill it can be determined if it should show
            frame.cooldown:SetHideCountdownNumbers(false)
        end)
    end
    
   
    
    -- Check if Layout mode is active
    local isLayoutMode = false
    local layoutContainer = _G["TweaksUI_LayoutContainer"]
    if layoutContainer and layoutContainer:IsShown() then
        isLayoutMode = true
    end
    
    if not slotInfo then
        if isLayoutMode then
            frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            frame.icon:SetDesaturated(true)
            frame.cooldown:Clear()
            if frame.count then frame.count:Hide() end
            if frame.glowFrame then frame.glowFrame:Hide() end
            frame:SetAlpha(0.5)
            frame:Show()
        else
            frame:Hide()
        end
        return
    end
    
    -- Determine current state based on cooldown
    local currentState = slotInfo.isActive and "active" or "inactive"
    local showThisState = CooldownHighlights:GetState(trackerKey, currentState .. ".show." .. slotIndex)
    
    -- During layout mode, always show
    if isLayoutMode then
        if not showThisState then
            frame.icon:SetDesaturated(true)
            frame:SetAlpha(0.4)
        else
            local saturated = CooldownHighlights:GetState(trackerKey, currentState .. ".saturated." .. slotIndex)
            if saturated == nil then saturated = (currentState == "active") end
            local opacity = CooldownHighlights:GetState(trackerKey, currentState .. ".opacity." .. slotIndex) or 1.0
            frame.icon:SetDesaturated(not saturated)
            frame:SetAlpha(opacity)
        end
        
        frame.cooldown:Clear()
        if frame.count then frame.count:Hide() end
        if frame.glowFrame then frame.glowFrame:Hide() end
        frame:Show()
        return
    end
end

function CooldownHighlights:UpdateAllHighlights(trackerKey)
    local db = GetDB(trackerKey)
    
    local inCombat = InCombatLockdown()
    if not db then return end
    
    for slotIndex, enabled in pairs(db.enabled) do
        if enabled then
            -- Only create frames outside of combat to avoid taint
            if not highlightFrames[trackerKey][slotIndex] then
                if not inCombat then
                    pcall(CreateHighlightFrame, trackerKey, slotIndex)
                end
            end
            -- Only update if frame exists
            if highlightFrames[trackerKey][slotIndex] then
                local success, err = pcall(CooldownHighlights.UpdateHighlightFrame, CooldownHighlights, trackerKey, slotIndex)
            end
        end
    end
end

-- Throttled version of UpdateAllHighlights - limits update frequency per tracker
function CooldownHighlights:UpdateAllHighlightsThrottled(trackerKey)
    local now = GetTime()
    local lastUpdate = throttleState.lastUpdate[trackerKey] or 0
    local timeSinceLastUpdate = now - lastUpdate
    
    -- If enough time has passed, update immediately
    if timeSinceLastUpdate >= throttleState.throttleDelay then
        throttleState.lastUpdate[trackerKey] = now
        throttleState.pendingUpdate[trackerKey] = false
        CooldownHighlights:UpdateAllHighlights(trackerKey)
    else
        -- Too soon - schedule a delayed update if not already pending
        if not throttleState.pendingUpdate[trackerKey] then
            throttleState.pendingUpdate[trackerKey] = true
            local remainingDelay = throttleState.throttleDelay - timeSinceLastUpdate
            C_Timer.After(remainingDelay, function()
                if throttleState.pendingUpdate[trackerKey] then
                    throttleState.lastUpdate[trackerKey] = GetTime()
                    throttleState.pendingUpdate[trackerKey] = false
                    CooldownHighlights:UpdateAllHighlights(trackerKey)
                end
            end)
        end
    end
end

-- ============================================================================
-- LAYOUT INTEGRATION
-- ============================================================================

local function CreateLayoutWrapper(trackerKey, slotIndex)
    local frame = highlightFrames[trackerKey][slotIndex]
    if not frame then return nil end
    
    local trackerType = TRACKER_TYPES[trackerKey]
    local wrapperId = trackerType.framePrefix .. slotIndex
    
    local wrapper = {
        id = wrapperId,
        name = trackerType.displayName .. " #" .. slotIndex,
        category = "Cooldowns",
        frame = frame,
        hideSizeMatching = true,
        defaultPosition = {
            point = "CENTER",
            x = -200 + (slotIndex * 60),
            y = -150,
        },
        contentFrames = {},
        
        onPositionChanged = function(self, point, relFrame, relPoint, x, y)
            -- Skip if docked - dock controls position
            if CooldownHighlights:GetState(trackerKey, "dockAssignment." .. slotIndex) then return end
            frame:ClearAllPoints()
            frame:SetPoint(point, UIParent, point, x, y)
            CooldownHighlights:UpdateState(trackerKey, { slotIndex = slotIndex }, {
                statePath = "positions." .. slotIndex,
                value = { point = point, relPoint = relPoint, x = x, y = y }
            })
        end,
        
        GetPosition = function(self)
            local point, relTo, relPoint, x, y = frame:GetPoint(1)
            return { point = point, relFrame = relTo, relPoint = relPoint, x = x, y = y }
        end,
        
        SetPosition = function(self, point, relFrame, relPoint, x, y)
            -- Skip if docked - dock controls position
            if CooldownHighlights:GetState(trackerKey, "dockAssignment." .. slotIndex) then return end
            frame:ClearAllPoints()
            frame:SetPoint(point, relFrame or UIParent, relPoint or point, x or 0, y or 0)
            if self.onPositionChanged then
                self:onPositionChanged(point, relFrame, relPoint, x, y)
            end
        end,
        
        LoadSaveData = function(self, data)
            if not data then return end
            local point = data.point or "CENTER"
            self:SetPosition(point, UIParent, point, data.x, data.y)
            if data.scale then
                self:SetScale(data.scale)
            end
        end,
        
        SetScale = function(self, scale)
            if frame and scale then
                frame:SetScale(scale)
            end
        end,
        
        GetScale = function(self)
            return frame:GetScale() or 1
        end,
        
        GetSize = function(self)
            return frame:GetSize()
        end,
        
        SetSize = function(self, width, height)
            if frame and width and height then
                frame:SetSize(width, height)
            end
        end,
        
        IsShown = function(self)
            local layoutContainer = _G["TweaksUI_LayoutContainer"]
            if layoutContainer and layoutContainer:IsShown() then
                return true
            end
            return frame and frame:IsShown()
        end,
        
        GetSaveData = function(self)
            local left = frame:GetLeft()
            local bottom = frame:GetBottom()
            if not left or not bottom then
                local point, _, _, x, y = frame:GetPoint(1)
                return {
                    point = point or "CENTER",
                    x = x or 0,
                    y = y or 0,
                    scale = self:GetScale(),
                }
            end
            return {
                point = "BOTTOMLEFT",
                x = left,
                y = bottom,
                scale = self:GetScale(),
            }
        end,
        
        GetSnapTarget = function(self, tolerance)
            local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)
            if not FlyPaper then return nil end
            tolerance = tolerance or 15
            local point, relFrame, relPoint, x, y = FlyPaper.GetBestAnchorForGroup(
                frame,
                "TUICD",
                tolerance
            )
            if point and relFrame then
                return relFrame, point, relPoint, x, y
            end
            return nil
        end,
        
        sizeLocked = false,
        SetSizeLocked = function(self, locked)
            self.sizeLocked = locked
        end,
        IsSizeLocked = function(self)
            return self.sizeLocked
        end,
        
        ForceSetSize = function(self, width, height)
            if frame and width and height then
                frame:SetSize(width, height)
            end
        end,
        
        GetWidth = function(self)
            return frame:GetWidth()
        end,
        GetHeight = function(self)
            return frame:GetHeight()
        end,
        SetWidth = function(self, width)
            if frame and width then
                frame:SetWidth(width)
            end
        end,
        SetHeight = function(self, height)
            if frame and height then
                frame:SetHeight(height)
            end
        end,
    }
    
    return wrapper
end

local function RegisterWithLayout(trackerKey, slotIndex)
    local frame = highlightFrames[trackerKey][slotIndex]
    if not frame then return end
    
    local trackerType = TRACKER_TYPES[trackerKey]
    local wrapperId = trackerType.framePrefix .. slotIndex
    
    if layoutWrappers[trackerKey][slotIndex] then
        return layoutWrappers[trackerKey][slotIndex]
    end
    
    local wrapper = CreateLayoutWrapper(trackerKey, slotIndex)
    if not wrapper then return nil end
    
    layoutWrappers[trackerKey][slotIndex] = wrapper
    
    local Layout = TUICD.Layout
    if Layout and Layout.RegisterElement then
        Layout:RegisterElement(wrapperId, {
            name = wrapper.name,
            category = "Cooldowns",
            tuiFrame = wrapper,
            defaultPosition = wrapper.defaultPosition,
            onPositionChanged = function(id, pos)
                if wrapper.onPositionChanged then
                    wrapper:onPositionChanged(pos.point, pos.relFrame, pos.relPoint, pos.x, pos.y)
                end
            end,
        })
    end
    
    return wrapper
end

local function UnregisterFromLayout(trackerKey, slotIndex)
    local trackerType = TRACKER_TYPES[trackerKey]
    local wrapperId = trackerType.framePrefix .. slotIndex
    
    local Layout = TUICD.Layout
    if Layout and Layout.UnregisterElement then
        Layout:UnregisterElement(wrapperId)
    end
    
    layoutWrappers[trackerKey][slotIndex] = nil
end

local function RegisterAllWithLayout(trackerKey)
    local db = GetDB(trackerKey)
    if not db then return end
    
    for slotIndex, enabled in pairs(db.enabled) do
        if enabled then
            if highlightFrames[trackerKey][slotIndex] then
                RegisterWithLayout(trackerKey, slotIndex)
            end
        end
    end
end

-- ============================================================================
-- TRACKER HIDE ENFORCEMENT
-- ============================================================================

local hideEnforcementHooks = {}

local function StartHideEnforcement(trackerKey)
    if hideEnforcementHooks[trackerKey] then return end
    
    local viewer = GetViewer(trackerKey)
    if not viewer then return end
    
    -- Hook Show() to prevent external code from showing the viewer
    local originalShow = viewer.Show
    viewer.Show = function(self)
        if CooldownHighlights:GetState(trackerKey, "hideTracker") then
            -- Silently ignore Show() calls when hideTracker is enabled
            return
        end
        originalShow(self)
    end
    
    -- Hook SetAlpha() to prevent external code from changing alpha
    local originalSetAlpha = viewer.SetAlpha
    viewer.SetAlpha = function(self, alpha)
        if CooldownHighlights:GetState(trackerKey, "hideTracker") then
            -- Force alpha to 0 when hideTracker is enabled
            originalSetAlpha(self, 0)
            return
        end
        originalSetAlpha(self, alpha)
    end
    
    hideEnforcementHooks[trackerKey] = {
        originalShow = originalShow,
        originalSetAlpha = originalSetAlpha
    }
end

local function StopHideEnforcement(trackerKey)
    if not hideEnforcementHooks[trackerKey] then return end
    
    local viewer = GetViewer(trackerKey)
    if viewer then
        -- Restore original methods
        viewer.Show = hideEnforcementHooks[trackerKey].originalShow
        viewer.SetAlpha = hideEnforcementHooks[trackerKey].originalSetAlpha
    end
    
    hideEnforcementHooks[trackerKey] = nil
end

function CooldownHighlights:UpdateRadialSwipeVisbility(trackerKey, slotIndex, isOnCooldown, frame)
    -- Update radial swipe visibility based on display state setting
    local showRadialSwipe = false
    if frame.radialSwipe then
        local radialDisplayState = CooldownHighlights:GetState(trackerKey, "radialSwipe.displayState." .. slotIndex) or "always"
        
        if radialDisplayState == "always" then
            -- Always show (full texture when ready, animated swipe when on cooldown)
            showRadialSwipe = true
        elseif radialDisplayState == "cooldown" then
            -- Only show during cooldown (animated swipe)
            showRadialSwipe = isOnCooldown
        elseif radialDisplayState == "available" then
            -- Only show when ready/available (full texture)
            showRadialSwipe = not isOnCooldown
        elseif radialDisplayState == "never" then
            -- Never show
            showRadialSwipe = false
        end
        
        
        if showRadialSwipe then
            frame.radialSwipe:Show()
        else
            frame.radialSwipe:Hide()
        end
    end
    return showRadialSwipe
end

function CooldownHighlights:UpdateFrameConfigurationChanges(trackerKey, slotIndex, db)
    local isOnCooldown = CalculateFrameCooldown(trackerKey, slotIndex)
    local enabled = CooldownHighlights:GetState(trackerKey, "enabled." .. slotIndex)
    CooldownHighlights:EnableHighlight(trackerKey, slotIndex, enabled)

    --===========================
    -- Apply RadialSwipe settings
    --===========================
    --apply modified texture
    local frame = highlightFrames[trackerKey] and highlightFrames[trackerKey][slotIndex]
    if (not frame) then
        return
    end
    if frame and frame.radialSwipe and frame.radialSwipe.SetTexture then
        local path = db and db.radialSwipe.texturePath[slotIndex] or ""
        if path and path ~= "" then
            frame.radialSwipe:SetTexture(path)
        else
            -- Reset to default when cleared
            frame.radialSwipe:SetTexture("Interface\\AddOns\\TweaksUI_Cooldowns\\Media\\Textures\\square_outline.tga")
        end
    end
    --Apply Size
    local radialScale = CooldownHighlights:GetState(trackerKey, "radialSwipe.scale." .. slotIndex) or 1.0
    local width, height = frame:GetSize()
    local swipeSize = math.max(width, height)  -- Use the larger dimension as base
    if frame.radialSwipe.SetSize then
        frame.radialSwipe:SetSize(swipeSize * radialScale, swipeSize * radialScale)
    end
    -- Apply color
    local color = CooldownHighlights:GetState(trackerKey, "radialSwipe.color." .. slotIndex) or {1, 1, 1, 1}
    if color and frame.radialSwipe.SetColor then
        frame.radialSwipe:SetColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end
    -- Apply position offset
    local offsetX = CooldownHighlights:GetState(trackerKey, "radialSwipe.offsetX." .. slotIndex) or 0
    local offsetY = CooldownHighlights:GetState(trackerKey, "radialSwipe.offsetY." .. slotIndex) or 0
    if frame.radialSwipe.SetOffset then
        frame.radialSwipe:SetOffset(offsetX, offsetY)
    end
    -- Apply rotation
    local rotation = CooldownHighlights:GetState(trackerKey, "radialSwipe.rotation." .. slotIndex) or 0
    if frame.radialSwipe.SetRotation then
        frame.radialSwipe:SetRotation(rotation)
    end


    CooldownHighlights:UpdateRadialSwipeVisbility(trackerKey, slotIndex, isOnCooldown, frame)

    --===========================
    -- Apply Spell Icon settings
    --===========================
    local slotInfo = GetSlotInfo(trackerKey, slotIndex) or {}
    local sourceIcon = slotInfo.icon or {}
    local spellID = sourceIcon and (sourceIcon.spellID or sourceIcon.SpellID or sourceIcon.spellId)
    if not spellID and sourceIcon and sourceIcon.GetSpellID then
        pcall(function() spellID = sourceIcon:GetSpellID() end)
    end
    -- Fallback for custom tracker icons: they store spellID as trackID when trackType == "spell"
    if not spellID and sourceIcon.trackType == "spell" and sourceIcon.trackID then
        spellID = sourceIcon.trackID
    end
    -- Check for custom icon texture override (spell ID-based)
    local customTexture = spellID and CooldownHighlights:GetState(trackerKey, "customIconTexture." .. tostring(spellID))
    if customTexture and customTexture ~= "" then
        frame.icon:SetTexture(customTexture)
        frame.icon:SetPoint("TOPLEFT", 0, 0)
        frame.icon:SetPoint("BOTTOMRIGHT", 0, 0)
        frame.icon:SetTexCoord(0, 1, 0, 1)
        frame:SetBackdropColor(0, 0, 0, 0)
        frame:SetBackdropBorderColor(0, 0, 0, 0)
    elseif slotInfo.texture then
        frame.icon:SetTexture(slotInfo.texture)
    else
        frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    -- Apply custom icon color (spell ID-based)
    local customColor = spellID and CooldownHighlights:GetState(trackerKey, "customIconColor." .. tostring(spellID))
    if customColor then
        frame.icon:SetVertexColor(customColor[1] or 1, customColor[2] or 1, customColor[3] or 1)
    else
        frame.icon:SetVertexColor(1, 1, 1)
    end

    local size = CooldownHighlights:GetState(trackerKey, "active.size." .. slotIndex) or DEFAULT_SIZE
    frame:SetSize(size, size)
    
    -- Determine actual state and visibility
    local actualState = isOnCooldown and "inactive" or "active"
    local showInactive = CooldownHighlights:GetState(trackerKey, "inactive.show." .. slotIndex)
    local showActive = CooldownHighlights:GetState(trackerKey, "active.show." .. slotIndex)
    local shouldShowIcon = (isOnCooldown and showInactive) or (not isOnCooldown and showActive)
    if shouldShowIcon then
        -- Apply state-specific visual settings and show
        local actualOpacity = CooldownHighlights:GetState(trackerKey, actualState .. ".opacity." .. slotIndex) or 1.0
        local actualSaturated = CooldownHighlights:GetState(trackerKey, actualState .. ".saturated." .. slotIndex)
        if actualSaturated == nil then actualSaturated = (actualState == "active") end

        frame:SetAlpha(actualOpacity)
        frame.icon:SetDesaturated(not actualSaturated)
        frame.icon:Show()
    else
        -- Hide icon when show setting is disabled for this state
        frame.icon:Hide()
    end








    --TODO: Implement the settings that only display when a spell is on cooldown (cooldown size ect.)
    
    -- Apply text scale, color, and offset settings
    -- local cooldownTextScale = CooldownHighlights:GetState(trackerKey, "cooldownTextScale." .. slotIndex) or 1.0
    -- local cooldownTextColor = CooldownHighlights:GetState(trackerKey, "cooldownTextColor." .. slotIndex) or {1, 1, 1, 1}
    -- local cooldownTextOffsetX = CooldownHighlights:GetState(trackerKey, "cooldownTextOffsetX." .. slotIndex) or 0
    -- local cooldownTextOffsetY = CooldownHighlights:GetState(trackerKey, "cooldownTextOffsetY." .. slotIndex) or 0
    -- local cooldownTextAnchor = CooldownHighlights:GetState(trackerKey, "cooldownTextAnchor." .. slotIndex) or "CENTER"
    -- local countTextScale = CooldownHighlights:GetState(trackerKey, "countTextScale." .. slotIndex) or 1.0
    -- local countTextColor = CooldownHighlights:GetState(trackerKey, "countTextColor." .. slotIndex) or {1, 1, 1, 1}
    -- local countTextOffsetX = CooldownHighlights:GetState(trackerKey, "countTextOffsetX." .. slotIndex) or 0
    -- local countTextOffsetY = CooldownHighlights:GetState(trackerKey, "countTextOffsetY." .. slotIndex) or 0
    -- local countTextAnchor = CooldownHighlights:GetState(trackerKey, "countTextAnchor." .. slotIndex) or "BOTTOMRIGHT"
    
    -- -- Scale, color, and offset cooldown text (countdown numbers on the cooldown spiral)
    -- if frame.cooldown then
    --     pcall(function()
    --         -- Try to find the countdown text in the cooldown frame
    --         local cdText = frame.cooldown.Text or frame.cooldown.text
    --         if not cdText then
    --             -- Search regions for FontString
    --             for i = 1, frame.cooldown:GetNumRegions() do
    --                 local region = select(i, frame.cooldown:GetRegions())
    --                 if region and region:GetObjectType() == "FontString" then
    --                     cdText = region
    --                     break
    --                 end
    --             end
    --         end
            
    --         if cdText then
    --             if cdText.GetFont then
    --                 local fontPath, _, fontFlags = cdText:GetFont()
    --                 if fontPath then
    --                     local baseSize = 14  -- Base font size for cooldown text
    --                     cdText:SetFont(fontPath, baseSize * cooldownTextScale, fontFlags or "OUTLINE")
    --                 end
    --             end
    --             if cdText.SetTextColor then
    --                 cdText:SetTextColor(cooldownTextColor[1] or 1, cooldownTextColor[2] or 1, cooldownTextColor[3] or 1, cooldownTextColor[4] or 1)
    --             end
    --             -- Apply anchor and offset
    --             if cdText.ClearAllPoints then
    --                 cdText:ClearAllPoints()
    --                 cdText:SetPoint(cooldownTextAnchor, frame.cooldown, cooldownTextAnchor, cooldownTextOffsetX, cooldownTextOffsetY)
    --             end
    --         end
    --     end)
    -- end
    
    -- -- Scale, color, and offset count text (stack/charge numbers)
    -- if frame.count then
    --     pcall(function()
    --         local fontPath, _, fontFlags = frame.count:GetFont()
    --         if fontPath then
    --             local baseSize = 12  -- Base font size for count text
    --             frame.count:SetFont(fontPath, baseSize * countTextScale, fontFlags or "OUTLINE")
    --         end
    --         frame.count:SetTextColor(countTextColor[1] or 1, countTextColor[2] or 1, countTextColor[3] or 1, countTextColor[4] or 1)
    --         -- Apply anchor and offset
    --         frame.count:ClearAllPoints()
    --         frame.count:SetPoint(countTextAnchor, frame, countTextAnchor, countTextOffsetX, countTextOffsetY)
    --     end)
    -- end
    
    -- -- Custom accessibility label
    -- if frame.customLabel then
    --     if CooldownHighlights:GetState(trackerKey, "labelEnabled." .. slotIndex) then
    --         local labelText = CooldownHighlights:GetState(trackerKey, "labelText." .. slotIndex) or ""
    --         local fontSize = CooldownHighlights:GetState(trackerKey, "labelFontSize." .. slotIndex) or 14
    --         local labelColor = CooldownHighlights:GetState(trackerKey, "labelColor." .. slotIndex) or {1, 1, 1, 1}
    --         local offsetX = CooldownHighlights:GetState(trackerKey, "labelOffsetX." .. slotIndex) or 0
    --         local offsetY = CooldownHighlights:GetState(trackerKey, "labelOffsetY." .. slotIndex) or 0
    --         local labelAnchor = CooldownHighlights:GetState(trackerKey, "labelAnchor." .. slotIndex) or "CENTER"
            
    --         frame.customLabel:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
    --         frame.customLabel:SetText(labelText)
    --         frame.customLabel:SetTextColor(labelColor[1] or 1, labelColor[2] or 1, labelColor[3] or 1, labelColor[4] or 1)
    --         frame.customLabel:ClearAllPoints()
    --         frame.customLabel:SetPoint(labelAnchor, frame, labelAnchor, offsetX, offsetY)
    --         frame.customLabel:Show()
    --     else
    --         frame.customLabel:Hide()
    --     end
    -- end

end

--==================================================
-- State Management
--==================================================

-- Helper to resolve ambiguous key (string vs number)
-- Checks if numeric or string version exists, or decides which to use for new keys
-- If both exist (duplicate), consolidates to NUMERIC key and removes string key
local function resolveKey(tbl, keyStr)
    local numKey = tonumber(keyStr)
    local hasNumKey = numKey ~= nil and tbl[numKey] ~= nil
    local hasStrKey = tbl[keyStr] ~= nil
    
    -- If BOTH keys exist (duplicate from old data), consolidate to numeric key
    if hasNumKey and hasStrKey then
        -- Remove the string key, keep numeric key
        tbl[keyStr] = nil
        return numKey
    end
    
    -- Try numeric key first if it's a valid number and exists
    if hasNumKey then
        return numKey
    end
    
    -- Try string key - if exists, migrate to numeric if possible
    if hasStrKey then
        if numKey ~= nil then
            -- Migrate to numeric key for consistency
            tbl[numKey] = tbl[keyStr]
            tbl[keyStr] = nil
            return numKey
        end
        return keyStr  -- Can't convert to number, keep as string
    end
    
    -- Neither exists - use numeric key for new entries if possible
    if numKey ~= nil then
        return numKey
    end
    return keyStr  -- Not a number, use string
end


-- Set nested value using table of keys
local function accessNestedValue(tbl, path, value, action)
    local keys = {}
    for key in string.gmatch(path, "[^.]+") do
        table.insert(keys, key)
    end
    local current = tbl
    for i = 1, #keys - 1 do
        local keyStr = keys[i]
        local key = resolveKey(current, keyStr)
        
        if current[key] == nil then
            current[key] = {}
        end
        current = current[key]
    end
    
    -- Handle the final key with resolution
    local finalKey = resolveKey(current, keys[#keys])
    if (action == 'set') then
        current[finalKey] = value
    elseif (action == 'get') then
        return current[finalKey]
    end
end

function CooldownHighlights:GetSlotIndexFromSpellID(trackerKey, spellID)
    local db = GetDB(trackerKey) or {}
    for slotIndex, enabled in pairs(db.enabled) do
        if enabled and highlightFrames[trackerKey][slotIndex] then
            -- Check if this slot's spellID matches
            local cachedSpellID = GetCachedSpellID(trackerKey, slotIndex)
            if cachedSpellID == spellID then
                return slotIndex
            end
        end
    end
    return -1
end

function CooldownHighlights:UpdateState(trackerKey, identifier, payload)
    local db = GetDB(trackerKey)
    if not db then return end
    
    local slotIndex = (
            identifier.spellId
            and CooldownHighlights:GetSlotIndexFromSpellID(trackerKey, identifier.spellId)
        )
        or identifier.slotIndex
    accessNestedValue(db, payload.statePath, payload.value, "set")

    
    -- Check if this is a hideTracker setting change (tracker-level, not per-slot)
    if string.find(payload.statePath, "hideTracker") then
        self:ApplyTrackerVisibility(trackerKey)
    end

    if (string.find(payload.statePath, "hidden")) then
        -- Save database to ensure changes persist
        if TUICD.Database and TUICD.Database.SetModuleSettings then
            TUICD.Database:SetModuleSettings(TUICD.MODULE_IDS.COOLDOWNS, TUICD.Cooldowns:GetSettings())
        end
        
        -- Refresh the tracker layout to apply alpha=0 on hidden icons
        if TUICD.Cooldowns and TUICD.Cooldowns.RefreshTrackerLayout then
            TUICD.Cooldowns.RefreshTrackerLayout(trackerKey)
        end
    end
    
    -- Check if this is a dock assignment change (per-icon)
    if slotIndex and string.find(payload.statePath, "dockAssignment") then
        if TUICD.Docks then
            local dockIndex = payload.value
            if dockIndex and dockIndex >= 1 and dockIndex <= 4 then
                TUICD.Docks:AssignIcon(dockIndex, trackerKey, slotIndex)
            else
                -- Unassign from all docks
                for i = 1, 4 do
                    TUICD.Docks:UnassignIcon(i, trackerKey, slotIndex)
                end
            end
        end
        
        -- Refresh layout mode overlay (show/hide based on dock status)
        if TUICD.LayoutMode and TUICD.LayoutMode.RefreshPerIconOverlay then
            TUICD.LayoutMode:RefreshPerIconOverlay(trackerKey, slotIndex)
        end
    end
    
    if (slotIndex) then
        CooldownHighlights:UpdateFrameConfigurationChanges(trackerKey, slotIndex, db)
    end
end


function CooldownHighlights:GetState(trackerKey, path, log)
    local db = GetDB(trackerKey)
    if not db then return end
    local value = accessNestedValue(db, path, nil, "get")
    return value
end




function CooldownHighlights:EnableHighlight(trackerKey, slotIndex, enabled)
    if enabled then
        -- Only create frames outside combat to avoid taint
        if not highlightFrames[trackerKey][slotIndex] and not InCombatLockdown() then
            CreateHighlightFrame(trackerKey, slotIndex)
            
        end
        if highlightFrames[trackerKey][slotIndex] then
            RegisterWithLayout(trackerKey, slotIndex)
            
            -- If this icon has a dock assignment, reparent to dock
            local dockAssignment = CooldownHighlights:GetState(trackerKey, "dockAssignment." .. slotIndex)
            if dockAssignment and TUICD.Docks then
                TUICD.Docks:AssignIcon(dockAssignment, trackerKey, slotIndex)
            end
            
            -- Show the frame when re-enabling
            highlightFrames[trackerKey][slotIndex]:Show()
        end
    else
        if highlightFrames[trackerKey][slotIndex] then
            highlightFrames[trackerKey][slotIndex]:Hide()
        end
        UnregisterFromLayout(trackerKey, slotIndex)
    end
end


function CooldownHighlights:IsIconHidden(trackerKey, slotIndex)
    local db = GetDB(trackerKey)
    return db and db.hidden[slotIndex] == true
end

-- Helper to check for CDM viewer layout issues (duplicate icons, stale state)
local function HasViewerLayoutIssue(viewer)
    local hasIssue = false
    local iconCount = 0
    
    pcall(function()
        local seenIndices = {}
        local children = {viewer:GetChildren()}
        
        for _, child in ipairs(children) do
            -- Check if this looks like a CDM icon (has layoutIndex and cooldownID)
            if child.layoutIndex then
                -- Check for duplicate layoutIndex (Blizzard bug with stale icons between characters)
                if seenIndices[child.layoutIndex] then
                    hasIssue = true
                    return  -- Exit early, no need to check more
                end
                seenIndices[child.layoutIndex] = true
                
                -- Count valid icons
                if child.cooldownID then
                    iconCount = iconCount + 1
                end
            end
        end
    end)
    
    return hasIssue, iconCount
end

function CooldownHighlights:ApplyTrackerVisibility(trackerKey)
    local viewer = GetViewer(trackerKey)
    if not viewer then return end
    
    if CooldownHighlights:GetState(trackerKey, "hideTracker") then
        -- Use alpha + mouse disable instead of Hide() to avoid OnShow issues when unhiding
        viewer:SetAlpha(0)
        viewer:EnableMouse(false)
        StartHideEnforcement(trackerKey)
    else
        StopHideEnforcement(trackerKey)
        viewer:SetAlpha(1)
        viewer:EnableMouse(true)
        
        -- Only call Show() if viewer is actually hidden, and protect against secret value errors
        if not viewer:IsShown() then
            -- Check for layout issues before showing (Blizzard CDM bug with stale icons)
            local hasLayoutIssue, iconCount = HasViewerLayoutIssue(viewer)
            
            if hasLayoutIssue then
                -- Don't try to Show() - it will trigger RefreshLayout which errors on duplicates
                -- Alpha is already 1, so the viewer content is visible anyway
                return
            end
            
            -- Fix Midnight Beta secret value issue before showing
            pcall(function()
                for _, child in ipairs({viewer:GetChildren()}) do
                    -- Clear secret values by setting to false using rawset
                    rawset(child, "allowAvailableAlert", false)
                    rawset(child, "allowOnCooldownAlert", false)
                end
            end)
            
            -- Wrap Show() in pcall - if it fails, the viewer is at least visible via alpha
            pcall(viewer.Show, viewer)
        end
    end
end

function CooldownHighlights:GetSlotCount(trackerKey)
    return GetSlotCount(trackerKey)
end

function CooldownHighlights:GetSlotInfo(trackerKey, slotIndex)
    return GetSlotInfo(trackerKey, slotIndex)
end

function CooldownHighlights:GetFrame(trackerKey, slotIndex)
    if highlightFrames[trackerKey] then
        return highlightFrames[trackerKey][slotIndex]
    end
    return nil
end

function CooldownHighlights:IsEnabled(trackerKey, slotIndex)
    return CooldownHighlights:GetState(trackerKey, "enabled." .. slotIndex)
end

function CooldownHighlights:GetTrackerTypes()
    return TRACKER_TYPES
end

-- Public API to refresh spellID cache (call when outside combat)
function CooldownHighlights:RefreshSpellIDCache(trackerKey)
    if InCombatLockdown() then
        print("|cff00ff00TweaksUI:|r Cannot refresh spellID cache during combat")
        return false
    end
    
    if trackerKey then
        CacheSpellIDs(trackerKey)
        print("|cff00ff00TweaksUI:|r Refreshed spellID cache for", trackerKey)
    else
        RefreshAllSpellIDCaches()
        print("|cff00ff00TweaksUI:|r Refreshed all spellID caches")
    end
    return true
end

-- Public API to get cached spellID (for debugging)
function CooldownHighlights:GetCachedSpellID(trackerKey, slotIndex)
    return GetCachedSpellID(trackerKey, slotIndex)
end

-- Public API to dump cache state (for debugging)
function CooldownHighlights:DumpSpellIDCache(trackerKey)
    print("|cff00ff00TweaksUI SpellID Cache:|r")
    if trackerKey then
        print("  Tracker:", trackerKey)
        local cache = spellIDCache[trackerKey]
        if cache then
            local count = 0
            for slotIndex, spellID in pairs(cache) do
                local spellName = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                spellName = spellName and spellName.name or "Unknown"
                print(string.format("    Slot %d: %d (%s)", slotIndex, spellID, spellName))
                count = count + 1
            end
            print("  Total:", count, "cached spellIDs")
        else
            print("  (no cache)")
        end
    else
        for key, cache in pairs(spellIDCache) do
            local count = 0
            for _ in pairs(cache) do count = count + 1 end
            print(string.format("  %s: %d cached spellIDs (last updated: %.1f sec ago)", 
                key, count, GetTime() - (cacheLastUpdated[key] or 0)))
        end
    end
end

function CooldownHighlights:ToggleDebug()
    debugMode = not debugMode
    print("|cff00ff00TweaksUI CooldownHighlights:|r Debug mode", debugMode and "ENABLED" or "DISABLED")
end

function CooldownHighlights:SetPosition(trackerKey, slotIndex, point, relPoint, x, y)
    SetHighlightPosition(trackerKey, slotIndex, point, relPoint, x, y)
end

function CooldownHighlights:DumpCooldownInfo(trackerKey, slotIndex)
    -- Use TUICD.Cooldowns.GetOrderedIcons if available (same order as layout/list)
    local icons
    local Cooldowns = TUICD.Cooldowns
    if Cooldowns and Cooldowns.GetOrderedIcons then
        local viewer = GetViewer(trackerKey)
        if viewer then
            icons = Cooldowns.GetOrderedIcons(viewer, trackerKey)
        else
            icons = {}
        end
    else
        icons = CollectIcons(trackerKey)
    end
    local icon = icons[slotIndex or 1]
    
    if not icon then
        print("|cffff0000[CooldownHighlights]|r No icon found at slot", slotIndex or 1)
        return
    end
    
    print("|cff00ff00[CooldownHighlights]|r Dumping info for", trackerKey, "slot", slotIndex or 1)
    print("  Icon:", icon:GetName() or "unnamed")
    
    -- Check spellID
    local spellID = icon.spellID or icon.SpellID or icon.spellId
    if not spellID and icon.GetSpellID then
        pcall(function() spellID = icon:GetSpellID() end)
    end
    print("  SpellID:", spellID or "(not found)")
    
    -- Try C_Spell.GetSpellDisplayCount if we have spellID
    if spellID and C_Spell and C_Spell.GetSpellDisplayCount then
        local success, result = pcall(function()
            return C_Spell.GetSpellDisplayCount(spellID)
        end)
        print("  C_Spell.GetSpellDisplayCount:", success and (result or "(nil)") or ("ERROR: " .. tostring(result)))
    end
    
    -- Check C_Spell cooldown APIs
    print("  C_Spell cooldown APIs:")
    print("    C_Spell.GetSpellCooldown:", (C_Spell and C_Spell.GetSpellCooldown) and "YES" or "no")
    print("    C_Spell.GetSpellCooldownDuration:", (C_Spell and C_Spell.GetSpellCooldownDuration) and "YES" or "no")
    
    -- Try C_Spell.GetSpellCooldown if we have spellID
    if spellID and C_Spell and C_Spell.GetSpellCooldown then
        local success, result = pcall(function()
            return C_Spell.GetSpellCooldown(spellID)
        end)
        if success and result then
            print("    GetSpellCooldown result:")
            print("      startTime:", result.startTime)
            print("      duration:", result.duration)
            print("      isEnabled:", result.isEnabled)
            print("      modRate:", result.modRate)
        else
            print("    GetSpellCooldown:", success and "(nil)" or ("ERROR: " .. tostring(result)))
        end
    end
    
    -- Try C_Spell.GetSpellCooldownDuration if it exists
    if spellID and C_Spell and C_Spell.GetSpellCooldownDuration then
        local success, result = pcall(function()
            return C_Spell.GetSpellCooldownDuration(spellID)
        end)
        print("    GetSpellCooldownDuration:", success and (result and "Duration Object" or "(nil)") or ("ERROR: " .. tostring(result)))
    end
    
    -- Try C_Spell.GetSpellCharges if we have spellID
    if spellID and C_Spell and C_Spell.GetSpellCharges then
        local success, result = pcall(function()
            return C_Spell.GetSpellCharges(spellID)
        end)
        if success and result then
            print("  C_Spell.GetSpellCharges: currentCharges=", result.currentCharges, "maxCharges=", result.maxCharges)
        else
            print("  C_Spell.GetSpellCharges:", success and "(nil)" or ("ERROR: " .. tostring(result)))
        end
    end
    
    -- Try GetSpellCharges global function
    if spellID and GetSpellCharges then
        local success, current, max = pcall(function()
            return GetSpellCharges(spellID)
        end)
        if success then
            print("  GetSpellCharges:", current or "(nil)", "/", max or "(nil)")
        end
    end
    
    -- Check direct fields
    local fields = {}
    if icon.Count then table.insert(fields, "Count") end
    if icon.count then table.insert(fields, "count") end
    if icon.Icon then table.insert(fields, "Icon") end
    if icon.icon then table.insert(fields, "icon") end
    if icon.Cooldown then table.insert(fields, "Cooldown") end
    if icon.cooldown then table.insert(fields, "cooldown") end
    if icon.spellID then table.insert(fields, "spellID") end
    if icon.SpellID then table.insert(fields, "SpellID") end
    if icon.charges then table.insert(fields, "charges") end
    if icon.Charges then table.insert(fields, "Charges") end
    print("  Direct fields:", #fields > 0 and table.concat(fields, ", ") or "(none)")
    
    -- Check for numeric charges value
    if type(icon.charges) == "number" then
        print("  icon.charges (number):", icon.charges)
    end
    if type(icon.Charges) == "number" then
        print("  icon.Charges (number):", icon.Charges)
    end
    if type(icon.currentCharges) == "number" then
        print("  icon.currentCharges:", icon.currentCharges)
    end
    if type(icon.maxCharges) == "number" then
        print("  icon.maxCharges:", icon.maxCharges)
    end
    
    -- Check direct Count field
    local directCount = icon.Count or icon.count
    if directCount then
        print("  icon.Count text:", directCount:GetText() or "(nil)", "visible:", directCount:IsShown())
    end
    
    -- Check cooldown frame
    local cooldown = icon.Cooldown or icon.cooldown
    if cooldown then
        print("  Cooldown frame:", cooldown:GetName() or "unnamed")
        
        -- Check for Midnight Duration Object API
        print("  Cooldown APIs available:")
        print("    GetCooldownDuration:", cooldown.GetCooldownDuration and "YES" or "no")
        print("    GetCooldownTimes:", cooldown.GetCooldownTimes and "YES" or "no")
        print("    SetCooldownFromDurationObject:", cooldown.SetCooldownFromDurationObject and "YES" or "no")
        
        -- Try GetCooldownDuration if available
        if cooldown.GetCooldownDuration then
            local success, result = pcall(function()
                return cooldown:GetCooldownDuration()
            end)
            print("    GetCooldownDuration result:", success and (result and "Duration Object" or "(nil)") or ("ERROR: " .. tostring(result)))
        end
        
        -- Try GetCooldownTimes if available
        if cooldown.GetCooldownTimes then
            local success, start, duration = pcall(function()
                return cooldown:GetCooldownTimes()
            end)
            if success then
                print("    GetCooldownTimes: start=", start, "duration=", duration)
            else
                print("    GetCooldownTimes: ERROR:", start)
            end
        end
        
        -- Check cooldown's count fields
        local cdCount = cooldown.Count or cooldown.count or cooldown.Charges or cooldown.charges
        if cdCount then
            print("  cooldown.Count text:", cdCount:GetText() or "(nil)", "visible:", cdCount:IsShown())
        end
        
        -- Check cooldown children
        if cooldown.GetChildren then
            print("  Cooldown children:", cooldown:GetNumChildren())
            for i = 1, cooldown:GetNumChildren() do
                local child = select(i, cooldown:GetChildren())
                local childName = child:GetName() or child:GetObjectType()
                print("    Child:", childName)
                if child.GetRegions then
                    for j = 1, child:GetNumRegions() do
                        local region = select(j, child:GetRegions())
                        if region:GetObjectType() == "FontString" then
                            print("      FontString:", region:GetName() or "unnamed", "text:", region:GetText() or "(nil)")
                        end
                    end
                end
            end
        end
    end
    
    -- Check icon's regions
    print("  Icon regions:")
    if icon.GetRegions then
        for i = 1, icon:GetNumRegions() do
            local region = select(i, icon:GetRegions())
            if region:GetObjectType() == "FontString" then
                print("    FontString:", region:GetName() or "unnamed", "text:", region:GetText() or "(nil)", "visible:", region:IsShown())
            end
        end
    end
    
    -- Check icon's children
    print("  Icon children:", icon:GetNumChildren())
    if icon.GetChildren then
        for i = 1, icon:GetNumChildren() do
            local child = select(i, icon:GetChildren())
            local childName = child:GetName() or child:GetObjectType()
            print("    Child:", childName)
            
            -- Check child's count field
            local childCount = child.Count or child.count
            if childCount then
                print("      Count field:", childCount:GetText() or "(nil)")
            end
            
            -- Check child's regions
            if child.GetRegions then
                for j = 1, child:GetNumRegions() do
                    local region = select(j, child:GetRegions())
                    if region:GetObjectType() == "FontString" then
                        print("      FontString:", region:GetName() or "unnamed", "text:", region:GetText() or "(nil)")
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function CooldownHighlights:Initialize(trackerKey)
    -- If no trackerKey provided, initialize for all trackers
    if not trackerKey then
        for _, key in ipairs({"essential", "utility", "buffs", "customTrackers"}) do
            self:Initialize(key)
        end
        return
    end
    
    if isInitialized[trackerKey] then return end
    isInitialized[trackerKey] = true

    
    -- Create frames for any enabled highlights (only outside combat)
    local db = GetDB(trackerKey)
    if not db then return end
    
    if not InCombatLockdown() then
        for slotIndex, enabled in pairs(db.enabled) do
            if enabled then
                CreateHighlightFrame(trackerKey, slotIndex)
            end
        end
        
        -- Cache spellIDs for this tracker (only outside combat)
        CacheSpellIDs(trackerKey)
    end
    
    -- Restore dock assignments after frames exist
    -- Use longer delay and iterate over dock assignments directly
    local function RestoreDockAssignments()
        if not TUICD.Docks or not db or not db.dockAssignment then return end
        
        for slotIndex, dockIndex in pairs(db.dockAssignment) do
            if dockIndex and highlightFrames[trackerKey] and highlightFrames[trackerKey][slotIndex] then
                TUICD.Docks:AssignIcon(dockIndex, trackerKey, slotIndex)
            end
        end
    end
    
    -- Try restoration at multiple times to handle varying load orders
    C_Timer.After(1, RestoreDockAssignments)
    C_Timer.After(3, RestoreDockAssignments)
    
    -- Apply tracker visibility
    self:ApplyTrackerVisibility(trackerKey)
    
    -- Register callbacks
    local Layout = TUICD.Layout
    if Layout then
        Layout:RegisterCallback("OnLayoutModeEnter", function()
            RegisterAllWithLayout(trackerKey)
            CooldownHighlights:UpdateAllHighlights(trackerKey)
        end)
        
        Layout:RegisterCallback("OnLayoutModeExit", function()
            CooldownHighlights:UpdateAllHighlights(trackerKey)
        end)
    end
end

function CooldownHighlights:InitializeAll()
    for trackerKey, _ in pairs(TRACKER_TYPES) do
        self:Initialize(trackerKey)
    end
end

-- ============================================================================
-- EVENT HANDLING: Refresh spellID cache after combat ends
-- ============================================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
eventFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("UNIT_AURA")  -- For buff tracker



eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended - refresh all spellID caches
        -- Small delay to let CDM icons settle
        C_Timer.After(0.5, function()
            -- Double-check we're still out of combat (could have re-engaged)
            if not InCombatLockdown() then
                RefreshAllSpellIDCaches()
            end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Zone change or login - refresh caches after things settle
        C_Timer.After(2, function()
            if not InCombatLockdown() then
                RefreshAllSpellIDCaches()
            end
        end)
    elseif event == "SPELL_DATA_LOAD_RESULT" then
        -- Spell data loaded - might have new spellIDs available
        if not InCombatLockdown() then
            C_Timer.After(0.5, function()
                if not InCombatLockdown() then
                    RefreshAllSpellIDCaches()
                end
            end)
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" 
        or event == "SPELL_UPDATE_CHARGES"
        or event == "ACTIONBAR_UPDATE_COOLDOWN"
        or event == "UNIT_AURA" then
        -- UpdateHighlightFrame()
        
        if event == "UNIT_AURA" then
            local target = ...
            if target and string.lower(target) == "player" then
                --DevTool:AddData({ event = event, target = target }, "UNIT_AURA (player)")
                CooldownHighlights:UpdateAllHighlightsThrottled("buffs")
            end
        else
            for _, key in ipairs({"essential", "utility", "custom"}) do
                CooldownHighlights:UpdateAllHighlightsThrottled(key)
            end
        end
    end
end)

-- Auto-initialize after a delay
C_Timer.After(2, function()
    CooldownHighlights:InitializeAll()
    -- Also cache spellIDs after initialization
    if not InCombatLockdown() then
        C_Timer.After(1, RefreshAllSpellIDCaches)
    end
end)
