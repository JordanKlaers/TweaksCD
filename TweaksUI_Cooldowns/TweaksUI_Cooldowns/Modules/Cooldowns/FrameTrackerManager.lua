-- ============================================================================
-- TUICD FrameTrackerManager.lua
-- Creates positionable highlight clones for tracker buffs
-- Detects active/inactive state via auraInstanceID (no secret value math)
-- ============================================================================

local addonName, TUICD = ...
TUICD.FrameTrackerManager = TUICD.FrameTrackerManager or {}
local FrameTrackerManager = TUICD.FrameTrackerManager

local RadialSwipe = TUICD.RadialSwipe or {}
local FRAME_PREFIX = "TweaksUI_CustomFrameTracker_"




-- ============================================================================
--[[
    Documentation:
        Setup:
            
        Tracking and responding to spell casts and cooldowns:
            > TRACKING
            Cooldown information is copied from the bilzzard frames by hooking into the methods that have the cooldown data. This is copied into the custom frames. "SetCooldownFromDurationObject" and "SetCooldown" are the two methods hooked into.
            "isCooldownDataApplied" - This flag is added on the custom frame that indicates if the cooldown data has been added to the frame. 
                - When the flag is false, new cooldown data can be set on the frame
                - Cooldown data is ONLY added to the frame when the flag is false. This ensures that its not overwritten - such as cooldown data from the GCD.
                - The flag is set "false" if
                    the event "SPELL_UPDATE_COOLDOWN" detects GCD (This means its not a real cooldown, so new cooldown can be applied)
                    OR in the "OnCooldownDone" callback which happens only after a valid cooldown has completed
            "isActualCooldown" - This flag indicates an actual cooldown is occuring currently.
                - Only when both, isOnGCD == false (meaning the spell has been put on a real cooldown) AND isCooldownDataApplied == true will the flag be set to true (A real cooldown event)
                - GCD can only be tracked in the callback for "SPELL_UPDATE_COOLDOWN"
                - The flag is only set to false in the "OnCooldownDone" callback which happens only after a valid cooldown has completed (This is the same spot as the "isCooldownDataApplied" flag)
            > RESPONDING
            "UpdateFrame_ApplyAllVisabilityConditions" is called when both flags are true
                - "isActualCooldown" indicates the state of the spell 

]]
-- ============================================================================



-- ============================================================================
-- STATE
-- ============================================================================
local cooldownManagerFrames = {
    buffs = {},
    essential = {},
    utility = {}
}

-- updateFrame is defined in the UPDATE SYSTEM section
local isInitialized = false

-- Event frame for UNIT_AURA and PLAYER_ENTERING_WORLD
local eventFrame = CreateFrame("Frame")

-- ============================================================================
-- DATABASE
-- ============================================================================
local TUICD_frames = {
    buffs = {},
    essential = {},
    utility = {}
}

local function accessNestedValue(tbl, path, value, action)
    local keys = {}
    for key in string.gmatch(path, "[^.]+") do
        table.insert(keys, key)
    end
    local current = tbl
    for i = 1, #keys - 1 do        
        if current[keys[i]] == nil then
            current[keys[i]] = {}
        end
        current = current[keys[i]]
    end
    
    -- Handle the final key with resolution
    local finalKey = keys[#keys]
    if (action == 'set') then
        current[finalKey] = value
    elseif (action == 'get') then
        return current[finalKey]
    end
end

local function AddNewTrackerValueConfig(data)
    return {
        trackerType = data.trackerType, -- essential, utility, buffs
        name = data.name,
        iconDisplayState = "active", -- "always", "inactive", "active", "never"
        iconTexturePath = "",
        defaultIconTexturePath = data.iconTexturePath,
        iconColor = {
            r = 1,
            g = 1,
            b = 1,
            a = 1,
        },
        desaturated = false,
        position = {
            anchorPoint = "center",
            relativeToFrame = nil,
            relativeAnchorPoint = "center",
            x = 0,
            y = 0
        },
        enabled = true,
        size = 48,
        opacity = 1,
        customLabel = {
            display = false,
            text = "",
            size = 10,
            x = 0,
            y = 0,
            color = {
                r = 1,
                g = 1,
                b = 1,
                a = 1,
            }
        },
        cooldownText = {
            display = true,
            size = 14,
            color = {
                r = 1,
                g = 1,
                b = 1,
                a = 1,
            },
            x = 0,
            y = 0,
            hideDefaultSweep = false
        },
        countText = {
            display = true,
            size = 12,
            color = {
                r = 1,
                g = 1,
                b = 1,
                a = 1,
            },
            x = 0,
            y = 0,
        },
        radialSwipe = {
            displayState = "never",  -- "always", "active", "inactive", "never"
            iconTexturePath = "",
            color = {
                r = 1,
                g = 1,
                b = 1,
                a = 1,
            },
            scale = 1,
            x = 0,
            y = 0,
            rotation = 0
        },
        showProcGlow = true,  -- Show spell activation glow
        dock = {
            assignedDock = false,  -- dock name or false
            layoutMode = "uncontrolled",  -- "controlled" or "uncontrolled"
            frame = nil  -- reference to dock frame (set when assigned)
        }
    }
end
function FrameTrackerManager:GetDataBase_V2(classSpecialization)
    local classSpecialization = TUICD.Cooldowns.GetCurrentSpecID()
    if not TweaksUI_Cooldowns_CharDB.classSpecializations then 
        TweaksUI_Cooldowns_CharDB.classSpecializations = {} 
    end
    
    -- Initialize spec table if it doesn't exist
    if not TweaksUI_Cooldowns_CharDB.classSpecializations[classSpecialization] then
        TweaksUI_Cooldowns_CharDB.classSpecializations[classSpecialization] = {}
    end
    
    local specDB = TweaksUI_Cooldowns_CharDB.classSpecializations[classSpecialization]
    
    -- Initialize tracker type tables
    specDB.buffs = specDB.buffs or {}
    specDB.essential = specDB.essential or {}
    specDB.utility = specDB.utility or {}
    specDB.docks = specDB.docks or {}
    
    return specDB
    --[[
    ============================================================================
        classSpecializations = {
            [specID] = {
                buffs = {},
                essential = {},
                utility = {},
                docks = {}
            }
        }
    --]]
end

function FrameTrackerManager:AddTrackerValue(trackerValueConstructorData)
    local db = FrameTrackerManager:GetDataBase_V2()
    local trackerType = trackerValueConstructorData.trackerType or "buffs"
    db[trackerType][trackerValueConstructorData.uniqueID] = AddNewTrackerValueConfig(trackerValueConstructorData)
    return db[trackerType][trackerValueConstructorData.uniqueID]
end
function FrameTrackerManager:GetAllTrackerValues(trackerType)
    local db = FrameTrackerManager:GetDataBase_V2()
    return db[trackerType]
end

function FrameTrackerManager:GetSpecificTrackerValue(uniqueID, trackerType)
    local db = FrameTrackerManager:GetDataBase_V2()
    local iconConfig = db[trackerType][uniqueID] or {}
    return iconConfig
    --[[
    if not iconConfig then return nil end
    
    -- Check if icon is assigned to a dock
    local dock = iconConfig.dock or {}
    if not dock.assignedDock or dock.assignedDock == false then
        return iconConfig
    end
    
    -- Get dock config
    local dockConfig = db.docks[dock.assignedDock]
    if not dockConfig then
        return iconConfig
    end
    
    -- For uncontrolled mode, return merged config
    -- (In the future, controlled mode will override more settings)
    if dock.layoutMode == "uncontrolled" then
        -- Create a shallow copy of icon config
        local merged = {}
        for k, v in pairs(iconConfig) do
            merged[k] = v
        end
        
        -- Deep copy function for nested tables
        local function deepCopy(tbl)
            if type(tbl) ~= "table" then return tbl end
            local copy = {}
            for k, v in pairs(tbl) do
                copy[k] = (type(v) == "table") and deepCopy(v) or v
            end
            return copy
        end
        
        -- Dynamically override settings based on dock's overwriteKeys
        if dockConfig.overwriteKeys then
            for overwriteKey, overwriteBool in pairs(dockConfig.overwriteKeys) do
                if overwriteBool and dockConfig[overwriteKey] ~= nil then
                    -- Deep copy if it's a table, otherwise just assign
                    if type(dockConfig[overwriteKey]) == "table" then
                        merged[overwriteKey] = deepCopy(dockConfig[overwriteKey])
                    else
                        merged[overwriteKey] = dockConfig[overwriteKey]
                    end
                end
            end
        end
        
        return merged
    end
    
    return iconConfig
    ]]
end

function FrameTrackerManager:CheckIsAlreadyTracker(uniqueID, trackerType)
    local db = FrameTrackerManager:GetDataBase_V2()
    return db[trackerType][uniqueID] and true or false
end

function FrameTrackerManager:RemoveTrackerValue(uniqueID, trackerType)
    local db = FrameTrackerManager:GetDataBase_V2()
    if FrameTrackerManager:CheckIsAlreadyTracker(uniqueID, trackerType) then
        -- Unregister from layout system
        FrameTrackerManager:UnregisterFromLayout(uniqueID)
        
        -- Clean up the frame
        local frame = TUICD_frames[trackerType][uniqueID]
        if frame then
            frame:Hide()
            frame:ClearAllPoints()
            TUICD_frames[trackerType][uniqueID] = nil
        end
        
        -- Remove from database
        db[trackerType][uniqueID] = nil
    end
end

function FrameTrackerManager:SetTrackerValueConfigProperty(uniqueID, trackerType, path, value)
    local db = FrameTrackerManager:GetDataBase_V2()
    accessNestedValue(db[trackerType][uniqueID], path, value, "set")
    local trackerValue = db[trackerType][uniqueID]
    if trackerValue and TUICD_frames[trackerType][uniqueID] then
        FrameTrackerManager:UpdateFrame_ConfigurationChanges(uniqueID, trackerType)
        if trackerType == "buffs" then
            FrameTrackerManager:UpdateFrame_AuraEvent(uniqueID)
        else
            FrameTrackerManager:UpdateFrame_CooldownEvent(uniqueID, trackerType)
        end
    end
end

function FrameTrackerManager:GetTrackerValueConfigProperty(uniqueID, trackerType, path)
    local db = FrameTrackerManager:GetDataBase_V2()
    return accessNestedValue(db[trackerType][uniqueID], path, nil, "get")
end

function FrameTrackerManager:getTrackerValuesListForSettings(trackerType)
    local listTrackerValues = {}
    for key, value in ipairs({ "buffs", "essential", "utility" }) do
        local trackerValues = FrameTrackerManager:GetAllTrackerValues(value)
        -- Loop through the buffs values
        for uniqueID, trackerValue in pairs(trackerValues) do
            -- Only add frames that are currently tracked by the cooldown manager
            if cooldownManagerFrames[value][uniqueID] then
                table.insert(listTrackerValues, {
                    uniqueID = uniqueID,
                    trackerType = trackerValue.trackerType,
                    name = trackerValue.name,
                    defaultIconTexturePath = trackerValue.defaultIconTexturePath
                })
            end
        end
    end
    return listTrackerValues
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
        isMounted = TUICD.UnitAPI:IsMountedOrTravelForm(),
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
-- BUFF SLOT ACCESS
-- ============================================================================

-- Get the buffs viewer frame
function FrameTrackerManager:GetCooldownManagerViewer(trackerType)
    local viewers = {
        buffs = _G["BuffIconCooldownViewer"],
        essential = _G["EssentialCooldownViewer"],
        utility = _G["UtilityCooldownViewer"]
    }
    return viewers[trackerType]
end

local function ScanAndSaveCurrentCooldownManagerFrames(trackerType)
    local viewer = FrameTrackerManager:GetCooldownManagerViewer(trackerType)
    if not viewer then return {} end

    local numChildren = 0
    pcall(function() numChildren = viewer:GetNumChildren() or 0 end)
    local indexUponCollection = 1
    for i = 1, numChildren do
        local child = select(i, viewer:GetChildren())
        if child then
            -- Buffs are grabbed by finding frames that have a spellID, texture, icon frame and cooldown frame.
            local spellID = nil
            local texture = nil
            local icon = child.Icon or child.icon
            local cooldown = child.Cooldown or child.cooldown
            local spellData = {}
            
            -- Try to extract spellID
            local success = pcall(function()
                if child.GetSpellID then
                    spellID = child:GetBaseSpellID()
                elseif child.spellID then
                    spellID = child.spellID or child.spellId or child.SpellID or child.SpellId
                end
                if spellID then
                    spellData = C_Spell.GetSpellInfo(spellID)
                end
                if icon then
                    texture = (icon.GetTexture and icon:GetTexture()) or icon.texture or spellData.iconID
                end
                child.tuicd_spellID = spellID
                child.tuicd_name = spellData.name
                child.tuicd_texture = texture
                child.tuicd_indexUponCollection = indexUponCollection
                -- Should be the cooldown that holds the cached info used within the hooks but keeping on the frame as well ^
                cooldown.tuicd_spellID = spellID
                cooldown.tuicd_name = spellData.name
                cooldown.tuicd_texture = texture
                cooldown.tuicd_indexUponCollection = indexUponCollection
            end)
            --save buffs to state based on the information collected
            if spellID and texture and icon and cooldown then
                -- Store the source frame reference
                cooldownManagerFrames[trackerType][spellID] = child
                
                -- Add to database if not already tracker
                if not FrameTrackerManager:CheckIsAlreadyTracker(spellID, trackerType) then
                    FrameTrackerManager:AddTrackerValue({
                        uniqueID = spellID,
                        iconTexturePath = texture,
                        name = spellData.name,
                        trackerType = trackerType
                    })
                end
            end
        end
    end
    
    -- After scanning, create frames for any trackers in database that were scanned but don't have frames yet
    local trackerConfigs = FrameTrackerManager:GetAllTrackerValues(trackerType)
    if trackerConfigs then
        for spellID, trackerConfig in pairs(trackerConfigs) do
            -- Only create frame if this tracker was found during scan AND doesn't already have a frame
            if cooldownManagerFrames[trackerType][spellID] and not TUICD_frames[trackerType][spellID] then
                FrameTrackerManager:CreateTrackerFrame(spellID, trackerConfig, trackerType)
            end
        end
    end
    FrameTrackerManager:RegisterAllWithLayout()
end

-- ============================================================================
-- HIGHLIGHT FRAME CREATION (Clone-based - we create our own frame and copy data)
-- ============================================================================

function FrameTrackerManager:CreateTrackerFrame(uniqueID, trackerConfig, trackerType)
    if TUICD_frames[trackerType][uniqueID] then
        return TUICD_frames[trackerType][uniqueID]
    end
    local frameName = FRAME_PREFIX .. uniqueID
    
    local frame = CreateFrame("Button", frameName, UIParent, "BackdropTemplate")
    frame:SetSize(trackerConfig.size, trackerConfig.size)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(100)
    
    -- CRITICAL: Make frame movable for Layout mode
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)  -- Don't eat mouse clicks - Layout overlay handles that
    
    -- Background (hide if Masque is enabled)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(0, 0, 0, 0)
    
    -- Icon texture
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.Icon = frame.icon  -- Masque expects .Icon

    frame.icon:SetPoint("TOPLEFT", 0, 0)
    frame.icon:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.icon:SetTexCoord(0, 1, 0, 1)  -- Crop off edges for cleaner look
    frame.icon:SetTexture(trackerConfig.defaultIconTexturePath)    
    -- Cooldown spiral
    frame.cooldown = CreateFrame("Cooldown", frameName .. "_Cooldown", frame, "CooldownFrameTemplate")
    frame.Cooldown = frame.cooldown  -- Masque expects .Cooldown
    frame.cooldown:SetAllPoints(frame.icon)
    frame.cooldown:SetFrameLevel(frame:GetFrameLevel() + 2)  -- Above icon texture
    frame.cooldown:SetDrawEdge(true)
    frame.cooldown:SetDrawBling(false)
    frame.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    
    -- Apply sweep and countdown text settings (per-icon overrides tracker-level)
    local hideSweep = trackerConfig.cooldownText.hideDefaultSweep
    local showCountdownText = trackerConfig.cooldownText.display

    
    frame.cooldown:SetDrawSwipe(hideSweep)
    frame.cooldown:SetHideCountdownNumbers(not showCountdownText)
    
    -- Store settings on cooldown for hooks to use
    frame.cooldown._TUI_hideSweep = hideSweep
    frame.cooldown._TUI_showCountdownText = showCountdownText
    frame.cooldown:SetScript("OnCooldownDone", function(self)
        local spellInfo = C_Spell.GetSpellInfo(frame.uniqueID)
        frame.isCooldownDataApplied = false
        frame.isActualCooldown = false
    end)
    
    -- Create StatusBar for tracker cooldown progress (secret-value compatible)
    -- This uses the new Midnight API that accepts DurationObjects with secrets
    frame.statusBar = CreateFrame("StatusBar", frameName .. "_StatusBar", frame)
    frame.statusBar:SetPoint("LEFT", frame, "RIGHT", 0, 0)  -- Inside frame, 2px from bottom
    frame.statusBar:SetSize(trackerConfig.size * 4, trackerConfig.size)  -- 85% of icon width, 4px tall
    frame.statusBar:SetMinMaxValues(0, 1)
    frame.statusBar:SetValue(1)
    frame.statusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    frame.statusBar:GetStatusBarTexture():SetHorizTile(false)
    frame.statusBar:SetStatusBarColor(0.2, 0.8, 1, 0.9)
    frame.statusBar:SetFrameLevel(frame:GetFrameLevel() + 3)  -- Above cooldown
    
    -- Create background for status bar
    frame.statusBar.bg = frame.statusBar:CreateTexture(nil, "BACKGROUND")
    frame.statusBar.bg:SetAllPoints(frame.statusBar)
    frame.statusBar.bg:SetColorTexture(0, 0, 0, 0)
    
    -- Create border for better visibility
    frame.statusBar.border = CreateFrame("Frame", nil, frame.statusBar, "BackdropTemplate")
    frame.statusBar.border:SetAllPoints()
    frame.statusBar.border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame.statusBar.border:SetBackdropBorderColor(0, 0, 0, 0)
    
    frame.statusBar:Hide()  -- Hidden by default, shown when cooldown is active
    

    -- Stack count text (bottom right, larger font)
    frame.count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    frame.Count = frame.count  -- Masque expects .Count
    frame.count:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.count:SetJustifyH("RIGHT")
    frame.count:SetDrawLayer("OVERLAY", 7)
    -- frame.count:SetText("87")
    
    -- Proc glow overlay (using Blizzard's built-in glow style)
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
    
    -- Custom label (for accessibility / identification)
    frame.customLabel = frame:CreateFontString(nil, "OVERLAY")
    frame.customLabel:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    frame.customLabel:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.customLabel:SetTextColor(1, 1, 1, 1)
    frame.customLabel:SetShadowOffset(1, -1)
    frame.customLabel:SetShadowColor(0, 0, 0, 1)
    frame.customLabel:SetDrawLayer("OVERLAY", 7)
    frame.customLabel:Hide()
    
    -- Apply saved position or default
    local pos = trackerConfig.position
    if pos and pos.anchorPoint and pos.x and pos.y then
        frame:ClearAllPoints()
        frame:SetPoint(
            pos.anchorPoint, 
            UIParent,  -- Always use UIParent for simplicity
            pos.relativeAnchorPoint or pos.anchorPoint, 
            pos.x or 0, 
            pos.y or 0
        )
    else
        -- Default position - center with offset based on slot
        frame:SetPoint("CENTER", UIParent, "CENTER", -200, -100)
    end
    
    -- Initialize cooldown state flags
    frame.isCooldownDataApplied = false
    frame.isOnGCD = true
    frame.isBuffActive = false
    
    frame.uniqueID = uniqueID
    -- Initially hidden
    frame:Show()
    
    TUICD_frames[trackerType][uniqueID] = frame
    
    -- Note: Layout registration happens in RegisterWithLayout(), called from EnableHighlight()
    return frame
end

function FrameTrackerManager:UpdateFrame_ApplyAllVisabilityConditions(uniqueID, trackerType)
    local trackerConfig = FrameTrackerManager:GetSpecificTrackerValue(uniqueID, trackerType)
    local sourceFrame = cooldownManagerFrames[trackerType][uniqueID]
    local frame = TUICD_frames[trackerType][uniqueID]
    
    if not frame or not trackerConfig then return end
    local spellInfo = C_Spell.GetSpellInfo(uniqueID)
    -- Determine current state (buff active or spell available)
    local buffPresentOrSpellAvailable = (
        (trackerType == 'buffs' and frame.isBuffActive)
        or (trackerType == 'essential' and not frame.isActualCooldown)
        or (trackerType == 'utility' and not frame.isActualCooldown)
    )
    
    -- Track if any element will be shown
    local anyElementVisible = false
    
    -- =========================================================================
    -- ICON VISIBILITY
    -- =========================================================================
    local showIcon = (
        trackerConfig.iconDisplayState == "always"
        or (trackerConfig.iconDisplayState == "active" and buffPresentOrSpellAvailable)
        or (trackerConfig.iconDisplayState == "inactive" and not buffPresentOrSpellAvailable)
    )
    
    if showIcon then
        frame.icon:Show()
        anyElementVisible = true
        
        -- Apply desaturation for inactive state
        if not buffPresentOrSpellAvailable then
            frame.icon:SetDesaturated(trackerConfig.desaturated or false)
        else
            frame.icon:SetDesaturated(false)
        end
    else
        frame.icon:Hide()
    end
    
    -- =========================================================================
    -- COOLDOWN SWIPE/SPIRAL & EDGE
    -- =========================================================================
    local showSwipe = (frame.isActualCooldown or frame.isBuffActive) and not trackerConfig.cooldownText.hideDefaultSweep
    
    pcall(function()
        frame.cooldown:SetDrawSwipe(showSwipe)
        frame.cooldown:SetDrawEdge(showSwipe)
    end)

    -- =========================================================================
    -- COOLDOWN TEXT (Countdown Numbers)
    -- =========================================================================
    local showCooldownText = (frame.isActualCooldown or frame.isBuffActive) and trackerConfig.cooldownText.display
    local success, error = pcall(function()
        frame.cooldown:SetHideCountdownNumbers(not showCooldownText)
    end)
    
    -- =========================================================================
    -- STATUS BAR (Cooldown Progress Bar)
    -- =========================================================================
    if frame.statusBar then
        -- Show/hide status bar based on cooldown state and GCD
        -- Only show for real cooldowns, not GCD
        if frame.isActualCooldown or frame.isBuffActive then
            frame.statusBar:Show()
            anyElementVisible = true
        else
            frame.statusBar:Hide()
        end
    end
    
    -- =========================================================================
    -- CUSTOM LABEL
    -- =========================================================================
    if frame.customLabel and trackerConfig.customLabel then
        if trackerConfig.customLabel.display and trackerConfig.customLabel.text and trackerConfig.customLabel.text ~= "" then
            frame.customLabel:Show()
            anyElementVisible = true
        else
            frame.customLabel:Hide()
        end
    end
    
    -- =========================================================================
    -- PROC GLOW (Spell Activation Overlay)
    -- =========================================================================
    if frame.glowFrame then
        pcall(function()
            if frame.glowFrame:IsShown() then
                anyElementVisible = true
            end
        end)
    end
    
    -- =========================================================================
    -- MASTER FRAME VISIBILITY
    -- Hide the entire frame if nothing is visible
    -- =========================================================================
    if anyElementVisible or buffPresentOrSpellAvailable then
        frame:Show()
    else
        frame:Hide()
    end
end

function FrameTrackerManager:UpdateFrame_ConfigurationChanges(uniqueID, trackerType)
    local trackerConfig = FrameTrackerManager:GetSpecificTrackerValue(uniqueID, trackerType)
    local sourceFrame = cooldownManagerFrames[trackerType][uniqueID]
    local frame = TUICD_frames[trackerType][uniqueID]
    
    -- Update icon texture
    frame.icon:SetTexture(trackerConfig.defaultIconTexturePath) -- trackerConfig.iconTexturePath or
    
    -- Update icon color
    local color = trackerConfig.iconColor or {}
    frame.icon:SetVertexColor(
        color.r or 1,
        color.g or 1,
        color.b or 1,
        color.a or 1
    )
    
    -- Update size
    frame:SetSize(trackerConfig.size, trackerConfig.size)
    
    -- Update opacity
    frame:SetAlpha(trackerConfig.opacity or 1)
        
    -- Attempt to get the cooldown text frame if possible, to update its styles
    local cdText = frame.cooldown.Text or frame.cooldown.text
    if not cdText then
        -- Search regions for FontString
        for i = 1, frame.cooldown:GetNumRegions() do
            local region = select(i, frame.cooldown:GetRegions())
            if region and region:GetObjectType() == "FontString" then
                cdText = region
                break
            end
        end
    end
        
    if cdText and trackerConfig.cooldownText then
        pcall(function()
            -- Apply font size
            local fontPath, _, fontFlags = cdText:GetFont()
            if fontPath and trackerConfig.cooldownText.size then
                cdText:SetFont(fontPath, trackerConfig.cooldownText.size, fontFlags or "OUTLINE")
            end
            
            -- Apply color
            if trackerConfig.cooldownText.color then
                cdText:SetTextColor(
                    trackerConfig.cooldownText.color.r or 1,
                    trackerConfig.cooldownText.color.g or 1,
                    trackerConfig.cooldownText.color.b or 1,
                    trackerConfig.cooldownText.color.a or 1
                )
            end
            
            -- Apply offset
            cdText:ClearAllPoints()
            cdText:SetPoint("CENTER", frame.cooldown, "CENTER", 
                trackerConfig.cooldownText.x or 0, 
                trackerConfig.cooldownText.y or 0)
        end)
    end

    
    -- Update count/stack text
    if frame.count and trackerConfig.countText then
        pcall(function()
            -- Apply font size
            local fontPath, _, fontFlags = frame.count:GetFont()
            if fontPath and trackerConfig.countText.size then
                frame.count:SetFont(fontPath, trackerConfig.countText.size, fontFlags or "OUTLINE")
            end

            -- Clear text if display is disabled (will be populated by UpdateFrame_AuraEvent)
            if not trackerConfig.countText.display then
                frame.count:SetText("")
            end
            
            
            -- Apply color
            if trackerConfig.countText.color then
                frame.count:SetTextColor(
                    trackerConfig.countText.color.r or 1,
                    trackerConfig.countText.color.g or 1,
                    trackerConfig.countText.color.b or 1,
                    trackerConfig.countText.color.a or 1
                )
            end
            
            -- Apply offset
            frame.count:ClearAllPoints()
            frame.count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 
                (trackerConfig.countText.x or 0) - 2, 
                (trackerConfig.countText.y or 0) + 2)
        end)
    end
    
    -- Update custom label
    if frame.customLabel and trackerConfig.customLabel then
        pcall(function()
            -- Set visibility and text
            if trackerConfig.customLabel.display and trackerConfig.customLabel.text and trackerConfig.customLabel.text ~= "" then
                frame.customLabel:SetText(trackerConfig.customLabel.text)
                frame.customLabel:Show()
            else
                frame.customLabel:Hide()
            end
            
            -- Apply font size
            if trackerConfig.customLabel.size then
                frame.customLabel:SetFont("Fonts\\FRIZQT__.TTF", trackerConfig.customLabel.size, "OUTLINE")
            end
            
            -- Apply color
            if trackerConfig.customLabel.color then
                frame.customLabel:SetTextColor(
                    trackerConfig.customLabel.color.r or 1,
                    trackerConfig.customLabel.color.g or 1,
                    trackerConfig.customLabel.color.b or 1,
                    trackerConfig.customLabel.color.a or 1
                )
            end
            
            -- Apply offset
            frame.customLabel:ClearAllPoints()
            frame.customLabel:SetPoint("CENTER", frame, "CENTER", 
                trackerConfig.customLabel.x or 0, 
                trackerConfig.customLabel.y or 0)
        end)
    end
    
    -- Update position
    local pos = trackerConfig.position
    frame:ClearAllPoints()
    frame:SetPoint(
        pos.anchorPoint, 
        UIParent,
        pos.relativeAnchorPoint or pos.anchorPoint, 
        pos.x or 0, 
        pos.y or 0
    )
end

--[[
    This method is used to update properties that can only be configured when the buffs is active
]]
function FrameTrackerManager:UpdateFrame_AuraEvent(uniqueID, isBuffActive)
    local frame = TUICD_frames["buffs"][uniqueID]
    if not frame then
        return
    end
    local sourceFrame = cooldownManagerFrames["buffs"][uniqueID]
    local config = FrameTrackerManager:GetSpecificTrackerValue(uniqueID, "buffs")
    local isActive = false
    local auraInstanceID = nil
    if sourceFrame then
        pcall(function()
            auraInstanceID = sourceFrame.auraInstanceID
            isActive = (auraInstanceID ~= nil)
        end)
    end
    
 
    if auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then       
        local success = pcall(function()
            -- minDisplayCount of 2 means don't show "1" (only show 2+)
            if config.countText.display then
                frame.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount("player", auraInstanceID, 1))
            else
                frame.count:SetText("")
            end
            frame.count:Show()
        end)
    elseif sourceFrame then
        local sourceCountFS = sourceFrame.Count or sourceFrame.count
        if not sourceCountFS and sourceFrame.GetChildren then
            pcall(function()
                for i = 1, sourceFrame:GetNumChildren() do
                    local child = select(i, sourceFrame:GetChildren())
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
        if sourceCountFS and sourceCountFS.GetText then
            pcall(function()
                if config.countText.display then
                    frame.count:SetText(sourceCountFS:GetText())
                else
                    frame.count:SetText("")
                end
            end)
            -- Use SetAlphaFromBoolean for visibility (handles secret booleans)
            if sourceCountFS.IsShown and frame.count.SetAlphaFromBoolean then
                pcall(function()
                    frame.count:SetAlphaFromBoolean(sourceCountFS:IsShown(), 1, 1)
                end)
            end
            frame.count:Show()
        else
            frame.count:SetText("")
            frame.count:Show()
        end
    else
        frame.count:SetText("")
        frame.count:Show()
    end

    FrameTrackerManager:UpdateFrame_ApplyAllVisabilityConditions(uniqueID, 'buffs')
end


function FrameTrackerManager:UpdateFrame_CooldownEvent(uniqueID, trackerType)
    local frame = TUICD_frames[trackerType][uniqueID]
    if not frame then
        return
    end
    local sourceFrame = cooldownManagerFrames[trackerType][uniqueID]
    local config = FrameTrackerManager:GetSpecificTrackerValue(uniqueID, trackerType)
   
    -- =========================================================================
    -- COOLDOWN - Mirror directly from source icon's Cooldown frame
    -- This is the key - Blizzard's cooldown frame is already showing correctly
    -- =========================================================================
    local sourceCooldown = sourceFrame and (sourceFrame.Cooldown or sourceFrame.cooldown)
    if sourceCooldown and frame.cooldown then
        -- Find the cooldown frame's built-in countdown text FontString
        local cdText = frame.cooldown.Text or frame.cooldown.text
        if not cdText then
            -- Search regions for FontString
            for i = 1, frame.cooldown:GetNumRegions() do
                local region = select(i, frame.cooldown:GetRegions())
                if region and region:GetObjectType() == "FontString" then
                    cdText = region
                    break
                end
            end
        end
        
        if cdText and config and config.cooldownText then
            local cdTextConfig = config.cooldownText
            pcall(function()
                -- Apply font size
                local fontPath, _, fontFlags = cdText:GetFont()
                if fontPath then
                    cdText:SetFont(fontPath, cdTextConfig.size or 14, fontFlags or "OUTLINE")
                end
                
                -- Apply color
                if cdTextConfig.color then
                    cdText:SetTextColor(
                        cdTextConfig.color.r or 1,
                        cdTextConfig.color.g or 1,
                        cdTextConfig.color.b or 1,
                        cdTextConfig.color.a or 1
                    )
                end
                
                -- Apply offset
                cdText:ClearAllPoints()
                cdText:SetPoint("CENTER", frame.cooldown, "CENTER", cdTextConfig.x or 0, cdTextConfig.y or 0)
            end)
        end
    end
    FrameTrackerManager:UpdateFrame_ApplyAllVisabilityConditions(uniqueID, trackerType)
end
-- ============================================================================
-- LAYOUT INTEGRATION
-- ============================================================================

local layoutWrappers = {}  -- Cache layout wrappers by uniqueID

local function CreateLayoutWrapper(uniqueID, trackerValue, trackerType)
    local frame = TUICD_frames[trackerType][uniqueID]
    if not frame or not trackerValue then return nil end
    
    local wrapperId = "TUICD_Tracker_" .. uniqueID
    local displayName = trackerValue.name or tostring(uniqueID)
    
    local wrapper = {
        id = wrapperId,
        name = displayName,
        category = "Cooldowns",
        frame = frame,
        hideSizeMatching = true,
        defaultPosition = {
            point = "CENTER",
            x = 0,
            y = 0,
        },
        contentFrames = {},
        
        onPositionChanged = function(self, point, relFrame, relPoint, x, y)
            -- TODO: Skip if docked when dock system is updated
            -- if trackerValue.dockAssignment then return end
            frame:ClearAllPoints()
            frame:SetPoint(point, UIParent, point, x, y)
            
            -- Update position in database
            FrameTrackerManager:SetTrackerValueConfigProperty(uniqueID, trackerType, "position", {
                anchorPoint = point,
                relativeToFrame = UIParent,
                relativeAnchorPoint = relPoint,
                x = x,
                y = y
            })
        end,
        
        GetPosition = function(self)
            local point, relTo, relPoint, x, y = frame:GetPoint(1)
            return { point = point, relFrame = relTo, relPoint = relPoint, x = x, y = y }
        end,
        
        SetPosition = function(self, point, relFrame, relPoint, x, y)
            -- TODO: Skip if docked when dock system is updated
            -- if trackerValue.dockAssignment then return end
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

function FrameTrackerManager:RegisterWithLayout(uniqueID, buffConfig, trackerType)
    local frame = TUICD_frames[trackerType][uniqueID]
    if not frame or not buffConfig then return end
    
    local wrapperId = "TUICD_Tracker_" .. uniqueID
    
    -- Return existing wrapper if already registered
    if layoutWrappers[uniqueID] then
        return layoutWrappers[uniqueID]
    end
    
    local wrapper = CreateLayoutWrapper(uniqueID, buffConfig, trackerType)
    if not wrapper then return nil end
    
    layoutWrappers[uniqueID] = wrapper
    
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

function FrameTrackerManager:RegisterAllWithLayout()
    if not TUICD.Layout then
        dprint("Layout module not available")
        return
    end
    
    for _, trackerType in ipairs({"buffs", "essential", "utility"}) do
        local trackerValuesForType = FrameTrackerManager:GetAllTrackerValues(trackerType)
        for uniqueID, trackerValue in pairs(trackerValuesForType) do
            if trackerValue.enabled and TUICD_frames[trackerType][uniqueID] then
                FrameTrackerManager:RegisterWithLayout(uniqueID, trackerValue, trackerType)
            end
        end
    end
end

function FrameTrackerManager:UnregisterFromLayout(uniqueID)
    local wrapperId = "TUICD_Tracker_" .. uniqueID
    
    local Layout = TUICD.Layout
    if Layout and Layout.UnregisterElement then
        Layout:UnregisterElement(wrapperId)
    end
    
    layoutWrappers[uniqueID] = nil
end


-- ============================================================================
-- PUBLIC API
-- ============================================================================


-- Set up hooks on BuffIconCooldownViewer to mirror cooldown updates
function FrameTrackerManager:SetupCooldownManagerHooks()
    for _, trackerType in ipairs({"buffs", "essential", "utility"}) do
        local viewer = FrameTrackerManager:GetCooldownManagerViewer(trackerType)
        if not viewer then
            C_Timer.After(1, function() self:SetupCooldownManagerHooks() end)
            return
        end
        
        hooksecurefunc(viewer, "Layout", function()
            -- After Layout, scan icons and set up cooldown hooks
            C_Timer.After(0, function()  -- Next frame, after Blizzard sets cooldowns
                self:HookAllBuffCooldownFrames(trackerType)
            end)
        end)
        -- Initial scan of existing icons
        self:HookAllBuffCooldownFrames(trackerType)
    end
end

-- Hook all buffs icon cooldowns to mirror to per-icon frames
function FrameTrackerManager:HookAllBuffCooldownFrames(trackerType)
    local viewer = FrameTrackerManager:GetCooldownManagerViewer(trackerType)
    if not viewer then return end
    ScanAndSaveCurrentCooldownManagerFrames(trackerType)
    for slotIndex, cdm_frame in pairs(cooldownManagerFrames[trackerType]) do
        -- Only hook frames that haven't been hooked yet
        if not cdm_frame._tuicd_hasHookedFrame then
            cdm_frame._tuicd_hasHookedFrame = true
        
            -- Hide the Blizzard buffs frames by keeping alpha at 0
            cdm_frame._tuicd_alphaLocked = true
            --cdm_frame:SetAlpha(0)
            
            -- Hook SetAlpha with recursion guard
            hooksecurefunc(cdm_frame, 'SetAlpha', function(self, alpha)
                if not self._tuicd_settingAlpha and alpha ~= 0 then
                    self._tuicd_settingAlpha = true
                    --self:SetAlpha(0)
                    self._tuicd_settingAlpha = false
                end
            end)
            
            local function hookCallback(self)
                local uniqueID = self.tuicd_spellID
                if uniqueID and TUICD_frames[trackerType][uniqueID] then
                    -- For buffs, track active state based on visibility
                    local isShown = false
                    pcall(function() 
                        isShown = self:IsShown()
                    end)
                    if trackerType == "buffs" then
                        TUICD_frames[trackerType][uniqueID].isBuffActive = isShown
                        local durationObj = nil
                        pcall(function()
                            durationObj = C_UnitAuras.GetAuraDuration("player", self:GetAuraSpellInstanceID())
                            if durationObj then
                                local frame = TUICD_frames[trackerType][uniqueID]
                                frame.cooldown:SetCooldownFromDurationObject(durationObj)
                                frame.statusBar:SetTimerDuration(
                                    durationObj,
                                    Enum.StatusBarInterpolation.ExponentialEaseOut,
                                    Enum.StatusBarTimerDirection.RemainingTime
                                )
                                DevTool:AddData("HAS set durationObj for the buff")
                            else
                                DevTool:AddData("no durationObj for the buff")
                            end

                        end)
                    else
                        --TUICD_frames[trackerType][uniqueID].isCooldownDataApplied = isShown
                    end
                    FrameTrackerManager:UpdateFrame_AuraEvent(uniqueID)
                end
            end

            if cdm_frame.RefreshApplications then hooksecurefunc(cdm_frame, "RefreshApplications", hookCallback) end
            if cdm_frame.RefreshActive then hooksecurefunc(cdm_frame, "RefreshActive", hookCallback) end
            if cdm_frame.UpdateShownState then hooksecurefunc(cdm_frame, "UpdateShownState", hookCallback) end

            local sourceCooldown = cdm_frame.Cooldown or cdm_frame.cooldown
            if sourceCooldown and not cdm_frame.hasHookedCooldown then
                cdm_frame.hasHookedCooldown = true
                -- Hook SetCooldownFromDurationObject (Midnight primary method)
                if sourceCooldown.SetCooldownFromDurationObject then
                    hooksecurefunc(sourceCooldown, "SetCooldownFromDurationObject", function(self, durationObj, clearIfZero)
                        local success, error = pcall(function()
                            local uniqueID = self.tuicd_spellID
                            local customFrame = TUICD_frames[trackerType][uniqueID]
                            if not customFrame then return end
                            local spellInfo = C_Spell.GetSpellInfo(uniqueID)
                            if not customFrame.isCooldownDataApplied then
                                local success, error = pcall(function()
                                    customFrame.cooldown:SetCooldownFromDurationObject(durationObj, clearIfZero)
                                    if customFrame.statusBar and customFrame.statusBar.SetTimerDuration then
                                        customFrame.statusBar:SetTimerDuration(
                                            durationObj,
                                            Enum.StatusBarInterpolation.ExponentialEaseOut,
                                            Enum.StatusBarTimerDirection.RemainingTime
                                        )
                                    end
                                end)
                                if success then
                                    customFrame.isCooldownDataApplied = true
                                else
                                    customFrame.isCooldownDataApplied = false
                                end
                            end
                        end)
                    end)
                end
                
                -- Hook SetCooldown (traditional method)
                hooksecurefunc(sourceCooldown, "SetCooldown", function(self, start, duration)
                    local success, error = pcall(function()
                        local uniqueID = self.tuicd_spellID
                        local customFrame = TUICD_frames[trackerType][uniqueID]
                        if not customFrame then return end
                        local spellInfo = C_Spell.GetSpellInfo(uniqueID)
                        if not customFrame.isCooldownDataApplied then
                            local success, error = pcall(function()
                                customFrame.cooldown:SetCooldown(start, duration)
                                if customFrame.statusBar and customFrame.statusBar.SetTimerDuration then
                                    local durationObj = nil
                                    if trackerType == "buffs" then
                                        pcall(function() durationObj = C_UnitAuras.GetAuraDuration("player", cdm_frame:GetAuraSpellInstanceID()) end)
                                    else
                                        pcall(function() durationObj = C_Spell.GetSpellCooldownDuration(uniqueID) end)
                                    end
                                    if durationObj then
                                        customFrame.statusBar:SetTimerDuration(
                                            durationObj,
                                            Enum.StatusBarInterpolation.ExponentialEaseOut,
                                            Enum.StatusBarTimerDirection.RemainingTime
                                        )
                                    end
                                end
                            end)
                            if success then
                                customFrame.isCooldownDataApplied = true
                            else
                                customFrame.isCooldownDataApplied = false
                            end
                        end
                    end)
                end)

                -- Hook Clear
                hooksecurefunc(sourceCooldown, "Clear", function(self)
                    pcall(function()
                        local uniqueID = self.tuicd_spellID
                        local customFrame = TUICD_frames[trackerType][uniqueID]
                        if not customFrame then return end
                        customFrame.cooldownData = nil
                        -- Clear cooldown data
                        customFrame.cooldown:Clear()
                        customFrame.statusBar:Hide()
                        
                        -- Update visibility
                        FrameTrackerManager:UpdateFrame_ApplyAllVisabilityConditions(uniqueID, trackerType)
                    end)
                end)
            end
        end -- End of _tuicd_hasHookedFrame check
    end
end

function FrameTrackerManager:UpdateAllHighlights()
    for _, trackerType in ipairs({"buffs", "essential", "utility"}) do
        local trackerConfigs = FrameTrackerManager:GetAllTrackerValues(trackerType)
        if trackerConfigs then
            for uniqueID, trackerConfig in pairs(trackerConfigs) do
                if trackerType == "buffs" then
                    FrameTrackerManager:UpdateFrame_AuraEvent(uniqueID)
                else
                    FrameTrackerManager:UpdateFrame_CooldownEvent(uniqueID, trackerType)
                end
            end
        end
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
local hasPlayerEnetedWorld = false
local hasDatabaseLoaded = false

function FrameTrackerManager:Initalize()
    if isInitialized or not hasDatabaseLoaded or not hasPlayerEnetedWorld then return end
    isInitialized = true

    FrameTrackerManager:SetupCooldownManagerHooks()
    FrameTrackerManager:UpdateAllHighlights()
    C_Timer.After(3, function()
        -- Re-setup hooks in case viewer was recreated
        FrameTrackerManager:SetupCooldownManagerHooks()
        FrameTrackerManager:UpdateAllHighlights()
    end)
end

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        hasPlayerEnetedWorld = true
        FrameTrackerManager:Initalize()
    end
    if event == "SPELL_UPDATE_COOLDOWN" then
        local spellID, baseSpellID, category, startRecoveryCategory = ...
        
        -- Check if we're tracking this spell in any tracker type
        for _, trackerType in ipairs({"buffs", "essential", "utility"}) do
            local customFrame = TUICD_frames[trackerType][spellID]
            if customFrame then
                local success, error = pcall(function()
                    
                    local cooldownInfo = C_Spell.GetSpellCooldown(spellID)
                    local spellInfo = C_Spell.GetSpellInfo(spellID)
                    if cooldownInfo.isOnGCD == false and customFrame.isCooldownDataApplied then
                        customFrame.isActualCooldown = true
                        FrameTrackerManager:UpdateFrame_ApplyAllVisabilityConditions(spellID, trackerType)
                    end
                    if cooldownInfo.isOnGCD then
                        customFrame.isCooldownDataApplied = false
                    end
                end)
                break
            end
        end
    end
end)

TUICD.Events:Register("DATABASE_LOADED", function()
    hasDatabaseLoaded = true
    FrameTrackerManager:Initalize()
end)
