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
-- Database things
-- ============================================================================

local trackerFrames = {}

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

local function AddNewTrackedValue(data)
    return {
        apiIdentifier = data.apiIdentifier, -- this might be the spell ID or the item ID ect. (This value might likely be identical to the "uniqueID" key, but this exists incase there is ever a reason they might need to be different)
        trackingType = data.trackingType, --spell / item / (maybe) buff
        name = data.name,
        iconDisplayState = "always", -- "always", "cooldown", "available", "never"
        iconTexturePath = "",
        defaultIconTexturePath = data.iconTexturePath,
        iconColor = nil,
        desaturated = false,
        parentFrame = UIParent,
        position = {
            anchorPoint = "CENTER",
            relativeToFrame = nil,
            relativeAnchorPoint = "CENTER",
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
            size = 1,
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
            displayState = "never",  -- "always", "cooldown", "available", "never"
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
        dock = {
            assignedDock = false,  -- dock name or false
            layoutMode = "uncontrolled",  -- "controlled" or "uncontrolled"
            frame = nil  -- reference to dock frame (set when assigned)
        }
    }
end
function CooldownHighlights:GetDataBase_V2()
    local classSpecialization = TUICD.Cooldowns.GetCurrentSpecID()
    if not TweaksUI_Cooldowns_CharDB.classSpecializations then TweaksUI_Cooldowns_CharDB.classSpecializations = {} end
    TweaksUI_Cooldowns_CharDB.classSpecializations[classSpecialization] = TweaksUI_Cooldowns_CharDB.classSpecializations[classSpecialization] or {
        [classSpecialization] = {
            trackers = {},
            buffs = {}
        }
    }
    TweaksUI_Cooldowns_CharDB.classSpecializations[classSpecialization].trackers = TweaksUI_Cooldowns_CharDB.classSpecializations[classSpecialization].trackers or {}
	TweaksUI_Cooldowns_CharDB.classSpecializations[classSpecialization].buffs = TweaksUI_Cooldowns_CharDB.classSpecializations[classSpecialization].buffs or {}
	TweaksUI_Cooldowns_CharDB.classSpecializations[classSpecialization].docks = TweaksUI_Cooldowns_CharDB.classSpecializations[classSpecialization].docks or {}
    return TweaksUI_Cooldowns_CharDB.classSpecializations[classSpecialization]
    --[[
    ============================================================================
        classSpecializations = {
            123 = {
                trackers = {},
                buffs = {},
                docks = {}
            }
        }
    --]]
end

function CooldownHighlights:AddTrackedValue(trackedValue)
    local db = CooldownHighlights:GetDataBase_V2()
    db.trackers[trackedValue.apiIdentifier] = AddNewTrackedValue(trackedValue)
end
function CooldownHighlights:GetTrackedValues()
    local db = CooldownHighlights:GetDataBase_V2()
    return db.trackers
end

function CooldownHighlights:GetTrackedValue(uniqueID)
    local db = CooldownHighlights:GetDataBase_V2()
    local iconConfig = db.trackers[uniqueID]
    
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
end

function CooldownHighlights:IsAlreadyTracked(trackedValue)
    if not trackedValue or not trackedValue.apiIdentifier then
        return false
    end
    local db = CooldownHighlights:GetDataBase_V2()
    return db.trackers[trackedValue.apiIdentifier] and true or false
end

function CooldownHighlights:RemoveTrackedValue(trackedValue)
    local db = CooldownHighlights:GetDataBase_V2()
    if CooldownHighlights:IsAlreadyTracked(trackedValue) then
        local uniqueID = trackedValue.apiIdentifier
        
        -- Unregister from layout system
        CooldownHighlights:UnregisterFromLayout(uniqueID)
        
        -- Clean up the frame
        local frame = trackerFrames[uniqueID]
        if frame then
            frame:Hide()
            frame:ClearAllPoints()
            trackerFrames[uniqueID] = nil
        end
        
        -- Remove from database
        db.trackers[uniqueID] = nil
    end
end

function CooldownHighlights:SetTrackerConfigValue(uniqueID, path, value)
    local db = CooldownHighlights:GetDataBase_V2()
    accessNestedValue(db.trackers[uniqueID], path, value, "set")
    -- TODO: notify docks
    -- if slotIndex and string.find(payload.statePath, "dockAssignment") then
    --     if TUICD.Docks then
    --         local dockIndex = payload.value
    --         if dockIndex and dockIndex >= 1 and dockIndex <= 4 then
    --             TUICD.Docks:AssignIcon(dockIndex, trackerKey, slotIndex)
    --         else
    --             -- Unassign from all docks
    --             for i = 1, 4 do
    --                 TUICD.Docks:UnassignIcon(i, trackerKey, slotIndex)
    --             end
    --         end
    --     end
        
    --     -- Refresh layout mode overlay (show/hide based on dock status)
    --     if TUICD.LayoutMode and TUICD.LayoutMode.RefreshPerIconOverlay then
    --         TUICD.LayoutMode:RefreshPerIconOverlay(trackerKey, slotIndex)
    --     end
    -- end
    
    local trackedValue = db.trackers[uniqueID]
    if trackedValue and trackerFrames[uniqueID] then
        CooldownHighlights:UpdateFrameConfigurationChanges(uniqueID, trackedValue)
    end
end

function CooldownHighlights:GetTrackerConfigValue(uniqueID, path, value)
    --todo:  fix all the state update things to use this instead of the old one, and then connect to the updatefromonconfigchanges or w/e
    local db = CooldownHighlights:GetDataBase_V2()
    return accessNestedValue(db.trackers[uniqueID], path, nil, "get")
end

-- Get the icon frame for a tracked value
function CooldownHighlights:GetIconFrame(uniqueID)
    return trackerFrames[uniqueID]
end

function CooldownHighlights:getTrackedValuesListForSettings()
    local trackedValues = CooldownHighlights:GetTrackedValues()
    local listTrackedValues = {}
     -- Loop through the tracked values
    for uniqueID, trackedData in pairs(trackedValues) do
        -- Process each tracked value
        table.insert(listTrackedValues, {
            uniqueID = uniqueID,
            trackingType = trackedData.trackingType,
            apiIdentifier = trackedData.apiIdentifier,
            name = trackedData.name,
            defaultIconTexturePath = trackedData.defaultIconTexturePath
        })
    end
    
    return listTrackedValues
end

function CooldownHighlights:ApplyPreexistingSpellConfig(targetID, config)
    local db = CooldownHighlights:GetDataBase_V2()
    db.trackers[targetID].iconDisplayState = config.iconDisplayState
    db.trackers[targetID].iconTexturePath = config.textTurePath
    db.trackers[targetID].iconColor = config.iconColor
    db.trackers[targetID].desaturated = config.desaturated
    db.trackers[targetID].enabled = config.enabled
    db.trackers[targetID].size = config.size
    db.trackers[targetID].opacity = config.opacity
    db.trackers[targetID].customLabel = config.customLabel
    db.trackers[targetID].cooldownText = config.cooldownText
    db.trackers[targetID].countText = config.countText
    db.trackers[targetID].radialSwipe = config.radialSwipe
    CooldownHighlights:UpdateFrameConfigurationChanges(targetID, db.trackers[targetID])
end

-- ============================================================================
-- STATE (per tracker type)
-- ============================================================================

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


-- Cooldowns longer than 3000ms (3 sec) are "real" cooldowns, not GCD (~1500ms)
local GCD_THRESHOLD = 3000

-- ============================================================================
-- HIGHLIGHT FRAME CREATION
-- ============================================================================

local function CreateHighlightFrame(uniqueID, trackedValue)
    if trackerFrames[uniqueID] then
        return trackerFrames[uniqueID]
    end
    
    local frameName = "TUICD_Highlight_" .. uniqueID
    local frame = CreateFrame("Button", frameName, trackedValue.parentFrame, "BackdropTemplate")
    frame:SetSize(trackedValue.size, trackedValue.size)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(100)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(false)
    
    -- Background
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
    frame.Icon = frame.icon
    frame.icon:SetPoint("TOPLEFT", 0, 0)
    frame.icon:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.icon:SetTexCoord(0, 1, 0, 1)
    
    -- Set icon texture
    if trackedValue.iconTexturePath and trackedValue.iconTexturePath ~= "" then
        frame.icon:SetTexture(trackedValue.iconTexturePath)
    elseif trackedValue.defaultIconTexturePath then
        frame.icon:SetTexture(trackedValue.defaultIconTexturePath)
    else
        frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    -- Apply icon color if set
    if trackedValue.iconColor then
        frame.icon:SetVertexColor(
            trackedValue.iconColor.r or 1,
            trackedValue.iconColor.g or 1,
            trackedValue.iconColor.b or 1,
            trackedValue.iconColor.a or 1
        )
    end
    
    -- Create radial swipe for cooldown animation
    RadialSwipe:InitializeRadialSwipe(frame, trackedValue.size)
    -- Apply radial swipe texture if set
    if trackedValue.radialSwipe.iconTexturePath and trackedValue.radialSwipe.iconTexturePath ~= "" then
        frame.radialSwipe:SetTexture(trackedValue.radialSwipe.iconTexturePath)
    end
    
    -- Apply radial swipe color
    if frame.radialSwipe.SetColor then
        frame.radialSwipe:SetColor(
            trackedValue.radialSwipe.color.r or 1,
            trackedValue.radialSwipe.color.g or 1,
            trackedValue.radialSwipe.color.b or 1,
            trackedValue.radialSwipe.color.a or 1
        )
    end
    
    -- Apply radial swipe scale
    if frame.radialSwipe.SetSize and trackedValue.radialSwipe.scale then
        local swipeSize = trackedValue.size * trackedValue.radialSwipe.scale
        frame.radialSwipe:SetSize(swipeSize, swipeSize)
    end
    
    -- Apply radial swipe position offset
    if frame.radialSwipe.SetOffset then
        frame.radialSwipe:SetOffset(trackedValue.radialSwipe.x or 0, trackedValue.radialSwipe.y or 0)
    end
    
    -- Apply radial swipe rotation
    if frame.radialSwipe.SetRotation then
        frame.radialSwipe:SetRotation(trackedValue.radialSwipe.rotation or 0)
    end

    -- Cooldown spiral (uses CooldownFrameTemplate which includes countdown text)
    frame.cooldown = CreateFrame("Cooldown", frameName .. "_Cooldown", frame, "CooldownFrameTemplate")
    frame.Cooldown = frame.cooldown
    frame.cooldown:SetAllPoints(frame.icon)
    frame.cooldown:SetDrawEdge(true)
    frame.cooldown:SetDrawBling(false)
    frame.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    
    -- Store unique identifier
    frame.cooldown._TUI_uniqueID = uniqueID
    frame.cooldown:SetScript("OnCooldownDone", function(self)
        frame.isOnCooldown = false
        CooldownHighlights:UpdateHighlightFrame(self._TUI_uniqueID)
    end)
    
    -- Apply cooldown sweep visibility
    local hideSweep = trackedValue.cooldownText.hideDefaultSweep or false
    frame.cooldown:SetDrawSwipe(not hideSweep)
    frame.cooldown:SetDrawEdge(not hideSweep)
    frame.cooldown:SetHideCountdownNumbers(not (trackedValue.cooldownText.display or false))
    if not frame.cooldownData then
        pcall(function()
            frame.cooldownData = C_Spell.GetSpellCooldownDuration(uniqueID)
        end)
    end
    -- Store settings on cooldown for hooks to use
    frame.cooldown._TUI_hideSweep = hideSweep
    frame.cooldown._TUI_showCountdownText = trackedValue.cooldownText.display or false
    frame.cooldown._TUI_uniqueID = uniqueID
    frame.cooldown.hideCountdownText = not (trackedValue.cooldownText.display or false)
    
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
    
    -- Charge/stack count text (bottom right corner)
    frame.count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    frame.Count = frame.count
    frame.count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.count:SetJustifyH("RIGHT")
    frame.count:SetDrawLayer("OVERLAY", 7)
    
    -- Border texture (for potential Masque support later)
    frame.Border = frame:CreateTexture(nil, "OVERLAY")
    frame.Border:SetAllPoints(frame)
    frame.Border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.Border:SetBlendMode("ADD")
    frame.Border:SetAlpha(0)
    
    -- Proc glow overlay
    frame.glowFrame = CreateFrame("Frame", frameName .. "_Glow", frame)
    frame.glowFrame:SetAllPoints()
    frame.glowFrame:SetFrameLevel(frame:GetFrameLevel() + 5)
    frame.glowFrame:Hide()
    
    -- Create the glow texture
    frame.glowTexture = frame.glowFrame:CreateTexture(nil, "OVERLAY")
    frame.glowTexture:SetPoint("TOPLEFT", -8, 8)
    frame.glowTexture:SetPoint("BOTTOMRIGHT", 8, -8)
    frame.glowTexture:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.glowTexture:SetBlendMode("ADD")
    frame.glowTexture:SetVertexColor(1, 1, 0.6, 0.8)
    
    -- Animated glow ants
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
    
    -- Custom accessibility label
    frame.customLabel = frame:CreateFontString(nil, "OVERLAY")
    frame.customLabel:SetFont("Fonts\\FRIZQT__.TTF", trackedValue.customLabel.size or 10, "OUTLINE")
    frame.customLabel:SetPoint("CENTER", frame, "CENTER", trackedValue.customLabel.x or 0, trackedValue.customLabel.y or 0)
    frame.customLabel:SetTextColor(
        trackedValue.customLabel.color.r or 1,
        trackedValue.customLabel.color.g or 1,
        trackedValue.customLabel.color.b or 1,
        trackedValue.customLabel.color.a or 1
    )
    frame.customLabel:SetShadowOffset(1, -1)
    frame.customLabel:SetShadowColor(0, 0, 0, 1)
    frame.customLabel:SetDrawLayer("OVERLAY", 7)
    
    -- Show custom label if text is set
    if trackedValue.customLabel.display and trackedValue.customLabel.text and trackedValue.customLabel.text ~= "" then
        frame.customLabel:SetText(trackedValue.customLabel.text)
        frame.customLabel:Show()
    else
        frame.customLabel:Hide()
    end
    
    -- Store references
    frame.uniqueID = uniqueID
    frame.trackedValue = trackedValue
    
    -- Set initial position from saved data
    local pos = trackedValue.position
    if pos and pos.x and pos.y then
        frame:ClearAllPoints()
        frame:SetPoint(pos.anchorPoint or "CENTER", trackedValue.parentFrame, pos.relativeAnchorPoint or pos.anchorPoint or "CENTER", pos.x, pos.y)
    else
        -- Default position
        frame:SetPoint("CENTER", trackedValue.parentFrame, "CENTER", 0, 0)
    end
    
    -- Set opacity
    frame:SetAlpha(trackedValue.opacity or 1)
    
    -- Show or hide based on enabled flag and viewState
    if trackedValue.enabled then
        frame:Show()
    else
        frame:Hide()
    end
    
    -- Store in cache
    trackerFrames[uniqueID] = frame
    
    -- Register with layout system
    CooldownHighlights:RegisterWithLayout(uniqueID, trackedValue)
    
    -- Initialize visibility and cooldown state
    CooldownHighlights:UpdateHighlightFrame(uniqueID, trackedValue)
    
    return frame
end


local function CalculateFrameCooldown(uniqueID, trackedValue)
    local frame = trackerFrames[uniqueID]
    if not frame then return end
    local trackType = trackedValue.trackingType


    
    -- =========================================================================
    -- COOLDOWN AND CHARGE UPDATES: Use cached spellID for API calls
    -- The spellID cache is populated outside combat, so we can safely use
    -- C_Spell APIs during combat without reading from the (secret) source icon
    -- =========================================================================
    local sourceCooldown = frame.Cooldown or frame.cooldown
    -- For spells: Use C_Spell API (charges first, then regular cooldown)
    -- Pass directly to SetCooldownFromDurationObject - NO conditionals on Duration objects
    if trackedValue.apiIdentifier and trackType == "spell" then
        local success = false
        -- Try charges cooldown first (for spells with charges like Fire Blast, Roll)
        local charges = C_Spell.GetSpellCharges(trackedValue.apiIdentifier) or {}
        if charges.maxCharges and charges.maxCharges > 1 then
            local chargeText = charges.currentCharges > 0 and charges.currentCharges or ""
            frame.hasCharges = true
            frame.currentCharges = charges.currentCharges
            frame.count:SetText(chargeText)
            if trackedValue.countText.display then
                frame.count:Show()
            else
                frame.count:Hide()
            end
        else
            frame.hasCharges = false
            frame.currentCharges = nil
            frame.count:SetText("")
            frame.count:Hide()
        end
        if C_Spell.GetSpellChargeDuration and frame.cooldown.SetCooldownFromDurationObject then
            success = pcall(function()
                frame.cooldown:SetCooldownFromDurationObject(C_Spell.GetSpellChargeDuration(trackedValue.apiIdentifier), true)
            end)
            -- if success then DevTool:AddData('properly setting cooldown') end
        -- Fallback to regular cooldown duration
        end
        if not success and C_Spell.GetSpellCooldownDuration and frame.cooldown.SetCooldownFromDurationObject then
            pcall(function()
                frame.cooldown:SetCooldownFromDurationObject(C_Spell.GetSpellCooldownDuration(trackedValue.apiIdentifier), true)
            end)
            -- if success then DevTool:AddData('properly setting cooldown') end
        end
    -- For non-spells (items/equipment): Pass through from source cooldown frame
    elseif sourceCooldown and sourceCooldown.GetCooldownDuration and frame.cooldown.SetCooldownFromDurationObject then
        pcall(function()
            frame.cooldown:SetCooldownFromDurationObject(sourceCooldown:GetCooldownDuration(), true)
        end)
        -- if success then DevTool:AddData('properly setting cooldown') end
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
    
    -- Additional check for charge-based spells: if charges < max, treat as recharging (on cooldown)
    -- This catches the case where you have 1+ charges available but not all charges
    if frame.hasCharges and frame.currentCharges then
        local charges = C_Spell.GetSpellCharges(trackedValue.apiIdentifier)
        if charges and charges.maxCharges and charges.currentCharges < charges.maxCharges then
            thisIconOnCooldown = true
        end
    end

    return thisIconOnCooldown
end


function CooldownHighlights:ApplyVisibilityConditions(uniqueID, trackedValue, frame, isOnCooldown)
    if not frame then return end
    
    -- Override cooldown state for charge-based spells: if we have charges available, treat as "available"
    local effectivelyOnCooldown = isOnCooldown
    if frame.hasCharges and frame.currentCharges and frame.currentCharges > 0 then
        effectivelyOnCooldown = false
    end
    
    local displayState = trackedValue.iconDisplayState
    local shouldDisplayFrame = displayState == "always"
        or (displayState == "cooldown" and effectivelyOnCooldown)
        or (displayState == "available" and not effectivelyOnCooldown)
    frame.shouldDisplayFrame = shouldDisplayFrame
    -- Update cooldown sweep visibility
    local hideSweep = trackedValue.cooldownText.hideDefaultSweep or false

    -- Update cooldown text visibility
    local showCountdownText = trackedValue.cooldownText.display or false
    if isOnCooldown then
        frame.cooldown:SetDrawSwipe(not hideSweep)
        frame.cooldown:SetDrawEdge(not hideSweep)
        frame.cooldown.hideCountdownText = not showCountdownText
        frame.cooldown:SetHideCountdownNumbers(not showCountdownText)
    else
        -- Not on cooldown, hide countdown text
        frame.cooldown.hideCountdownText = true
        frame.cooldown:SetHideCountdownNumbers(true)
    end

    -- Update radial swipe visibility regardless of icon display state
    local showRadialSwipe = CooldownHighlights:UpdateRadialSwipeVisbility(uniqueID, trackedValue, frame, isOnCooldown)
    
    if shouldDisplayFrame then
        local shouldDesaturate = trackedValue.desaturated and effectivelyOnCooldown
        local opacity = trackedValue.opacity
        frame:Show()
        frame:SetAlpha(opacity)
        frame.icon:SetDesaturated(shouldDesaturate)
        frame.icon:Show()
    else
        -- Icon should be hidden - only show frame if radial swipe should be visible
        if showRadialSwipe then
            -- Hide icon and backdrop but keep frame visible for radial swipe
            frame.icon:Hide()
            frame:Show()
        else
            -- Hide entire frame
            frame:Hide()
        end
    end
    -- Notify dock if this icon is docked
    -- local dockAssignment = CooldownHighlights:GetState(trackerKey, "dockAssignment." .. slotIndex)
    -- if dockAssignment and TUICD.Docks then
    --     TUICD.Docks:NotifyIconUpdate(trackerKey, slotIndex)
    -- end
end

function CooldownHighlights:UpdateHighlightFrame(uniqueID, trackedValue)
    local frame = trackerFrames[uniqueID]
    if not frame or not trackedValue then return end
    
    -- Calculate current cooldown state
    local isOnCooldown = CalculateFrameCooldown(uniqueID, trackedValue)
    -- Initialize state tracking on first run
    if not frame._TUI_currentCooldownState then
        frame._TUI_currentCooldownState = nil  -- nil means unknown/first run
    end
    if not frame._TUI_lastChargeCount then
        frame._TUI_lastChargeCount = nil
    end
    
    -- Check if state changed (transition detected)
    local stateChanged = (frame._TUI_currentCooldownState ~= isOnCooldown)
    
    -- Check if charge count changed (for spells with charges)
    local chargeCountChanged = false
    if frame.hasCharges and frame.currentCharges then
        chargeCountChanged = (frame._TUI_lastChargeCount ~= frame.currentCharges)
        frame._TUI_lastChargeCount = frame.currentCharges
    end
    
    -- Always update visibility conditions (handles configuration changes)
    CooldownHighlights:ApplyVisibilityConditions(uniqueID, trackedValue, frame, isOnCooldown)

    -- Early return if no state change AND no charge count change (skip animation logic)
    -- For charge-based spells, we need to update even when cooldown state hasn't changed
    -- because charge count itself is changing (e.g., 1/3 → 0/3 or 0/3 → 1/3)
    if not stateChanged and not chargeCountChanged and frame._TUI_currentCooldownState ~= nil then
        return  -- No transition, skip radial swipe animation updates
    end
    -- Update state tracking
    frame._TUI_currentCooldownState = isOnCooldown
    frame.isOnCooldown = isOnCooldown
    -- Start radial swipe animation when transitioning to cooldown OR when charge count changes while on cooldown
    if (stateChanged or chargeCountChanged) and isOnCooldown then
        frame.cooldown._TUI_cooldownComplete = false
        local radialDisplayState = (trackedValue.radialSwipe.displayState or "never")
        -- Only start the animation if it should show when the cooldown is triggered. This help performance by not animating hidden frames.
        if radialDisplayState == "always" or radialDisplayState == "cooldown" then
            if not frame.cooldownData then
                pcall(function()
                    frame.cooldownData = C_Spell.GetSpellCooldownDuration(uniqueID)
                end)
            end
            RadialSwipe:OnUpdate(frame, 'isStart')
        end
        -- Apply cooldown text settings if they've changed since last cooldown
        if frame._TUI_cooldownSettingsDirty and frame._TUI_cooldownTextSettings then
            pcall(function()
                local cdText = frame.cooldown.Text or frame.cooldown.text
                if not cdText then
                    for i = 1, frame.cooldown:GetNumRegions() do
                        local region = select(i, frame.cooldown:GetRegions())
                        if region and region:GetObjectType() == "FontString" then
                            cdText = region
                            break
                        end
                    end
                end
                
                if cdText and trackedValue.cooldownText.display then
                    if cdText.GetFont then
                        local fontPath, _, fontFlags = cdText:GetFont()
                        if fontPath then
                            cdText:SetFont(fontPath, trackedValue.cooldownText.size or 14, fontFlags or "OUTLINE")
                        end
                    end
                    if cdText.SetTextColor then
                        cdText:SetTextColor(
                            trackedValue.cooldownText.color.r or 1,
                            trackedValue.cooldownText.color.g or 1,
                            trackedValue.cooldownText.color.b or 1,
                            trackedValue.cooldownText.color.a or 1
                        )
                    end
                    if cdText.ClearAllPoints then
                        cdText:ClearAllPoints()
                        cdText:SetPoint("CENTER", frame.cooldown, "CENTER", 
                            trackedValue.cooldownText.x or 0, 
                            trackedValue.cooldownText.y or 0)
                    end
                end
            end)
            -- Clear dirty flag after applying
            frame._TUI_cooldownSettingsDirty = false
        end
    end
end

function CooldownHighlights:UpdateAllHighlights()
    local trackedValues = CooldownHighlights:GetTrackedValues()
    if not trackedValues then return end
    
    local inCombat = InCombatLockdown()
    
    -- Iterate through all tracked values by uniqueID
    for uniqueID, trackedValue in pairs(trackedValues) do
        -- Only process enabled entries
        if trackedValue.enabled then
            -- Only create frames outside of combat to avoid taint
            if not trackerFrames[uniqueID] then
                if not inCombat then
                    pcall(CreateHighlightFrame, uniqueID, trackedValue)
                end
            end
            
            -- Only update if frame exists
            if trackerFrames[uniqueID] then
                pcall(CooldownHighlights.UpdateHighlightFrame, CooldownHighlights, uniqueID, trackedValue)
            end
        end
    end
end

-- Throttled version of UpdateAllHighlights - limits update frequency globally
function CooldownHighlights:UpdateAllHighlightsThrottled()
    local throttleKey = "global"  -- Use single throttle key for all updates
    local now = GetTime()
    local lastUpdate = throttleState.lastUpdate[throttleKey] or 0
    local timeSinceLastUpdate = now - lastUpdate
    
    -- If enough time has passed, update immediately
    if timeSinceLastUpdate >= throttleState.throttleDelay then
        throttleState.lastUpdate[throttleKey] = now
        throttleState.pendingUpdate[throttleKey] = false
        CooldownHighlights:UpdateAllHighlights()
    else
        -- Too soon - schedule a delayed update if not already pending
        if not throttleState.pendingUpdate[throttleKey] then
            throttleState.pendingUpdate[throttleKey] = true
            local remainingDelay = throttleState.throttleDelay - timeSinceLastUpdate
            C_Timer.After(remainingDelay, function()
                if throttleState.pendingUpdate[throttleKey] then
                    throttleState.lastUpdate[throttleKey] = GetTime()
                    throttleState.pendingUpdate[throttleKey] = false
                    CooldownHighlights:UpdateAllHighlights()
                end
            end)
        end
    end
end


-- ============================================================================
-- LAYOUT INTEGRATION
-- ============================================================================

local layoutWrappers = {}  -- Cache layout wrappers by uniqueID

local function CreateLayoutWrapper(uniqueID, trackedValue)
    local frame = trackerFrames[uniqueID]
    if not frame or not trackedValue then return nil end
    
    local wrapperId = "TUICD_Tracker_" .. uniqueID
    local displayName = trackedValue.name or tostring(uniqueID)
    
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
            -- Skip if docked - dock manages positioning
            local currentConfig = CooldownHighlights:GetTrackerConfigValue(uniqueID, "dock.assignedDock")
            if currentConfig and currentConfig ~= false then
                return
            end
            
            frame:ClearAllPoints()
            frame:SetPoint(point, trackedValue.parentFrame, relPoint, x, y)
            
            -- Update position in database
            CooldownHighlights:SetTrackerConfigValue(uniqueID, "position", {
                anchorPoint = point,
                relativeToFrame = trackedValue.parentFrame,
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
            -- Skip if docked - dock manages positioning
            local currentConfig = CooldownHighlights:GetTrackerConfigValue(uniqueID, "dock.assignedDock")
            if currentConfig and currentConfig ~= false then
                return
            end
            
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

function CooldownHighlights:RegisterWithLayout(uniqueID, trackedValue)
    local frame = trackerFrames[uniqueID]
    if not frame or not trackedValue then return end
    
    local wrapperId = "TUICD_Tracker_" .. uniqueID
    
    -- Return existing wrapper if already registered
    if layoutWrappers[uniqueID] then
        return layoutWrappers[uniqueID]
    end
    
    local wrapper = CreateLayoutWrapper(uniqueID, trackedValue)
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

function CooldownHighlights:UnregisterFromLayout(uniqueID)
    local wrapperId = "TUICD_Tracker_" .. uniqueID
    
    local Layout = TUICD.Layout
    if Layout and Layout.UnregisterElement then
        Layout:UnregisterElement(wrapperId)
    end
    
    layoutWrappers[uniqueID] = nil
end

-- ============================================================================
-- TRACKER HIDE ENFORCEMENT
-- ============================================================================

local hideEnforcementHooks = {}

function CooldownHighlights:StartHideEnforcement(trackerKey)
    if hideEnforcementHooks[trackerKey] then return end
    
    local viewer = GetViewer(trackerKey)
    if not viewer then return end
    
    -- Hook Show() to prevent external code from showing the viewer
    local originalShow = viewer.Show
    viewer.Show = function(self)
        if shouldEverythingBeHidden(trackerKey) or CooldownHighlights:GetState(trackerKey, "hideTracker") then
            -- Silently ignore Show() calls when hideTracker is enabled
            return
        end
        originalShow(self)
    end
    
    -- Hook SetAlpha() to prevent external code from changing alpha
    local originalSetAlpha = viewer.SetAlpha
    viewer.SetAlpha = function(self, alpha)
        if shouldEverythingBeHidden(trackerKey) or CooldownHighlights:GetState(trackerKey, "hideTracker") then
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


function CooldownHighlights:StopHideEnforcement(trackerKey)
    if not hideEnforcementHooks[trackerKey] then return end
    
    local viewer = GetViewer(trackerKey)
    if viewer then
        -- Restore original methods
        viewer.Show = hideEnforcementHooks[trackerKey].originalShow
        viewer.SetAlpha = hideEnforcementHooks[trackerKey].originalSetAlpha
    end
    
    hideEnforcementHooks[trackerKey] = nil
end

function CooldownHighlights:UpdateRadialSwipeVisbility(uniqueID, trackedValue, frame, isOnCooldown)
    -- Update radial swipe visibility based on display state setting
    local showRadialSwipe = false
    if frame and frame.radialSwipe then
        local radialDisplayState = trackedValue.radialSwipe.displayState
        
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

-- Apply configuration changes to a highlight frame (size, color, texture, etc.)
-- This is called when user changes settings in the UI
-- For runtime cooldown/visibility updates, use UpdateHighlightFrame instead
function CooldownHighlights:UpdateFrameConfigurationChanges(uniqueID, trackedValue)
    local frame = trackerFrames[uniqueID]
    if not frame or not trackedValue then return end
    local isOnCooldown = CalculateFrameCooldown(uniqueID, trackedValue)
    --===========================
    -- Apply frame size
    --===========================
    frame:SetSize(trackedValue.size, trackedValue.size)
    
    --===========================
    -- Apply RadialSwipe settings
    --===========================
    if frame.radialSwipe then
        frame.radialDisplayState = trackedValue.radialSwipe.displayState
        -- Apply texture
        if frame.radialSwipe.SetTexture then
            if trackedValue.radialSwipe.iconTexturePath and trackedValue.radialSwipe.iconTexturePath ~= "" then
                frame.radialSwipe:SetTexture(trackedValue.radialSwipe.iconTexturePath)
            else
                frame.radialSwipe:SetTexture("Interface\\AddOns\\TweaksUI_Cooldowns\\Media\\Textures\\square_outline.tga")
            end
        end
        
        -- Apply size
        if frame.radialSwipe.SetSize then
            local swipeSize = trackedValue.size * (trackedValue.radialSwipe.scale or 1)
            frame.radialSwipe:SetSize(swipeSize, swipeSize)
        end
        
        -- Apply color
        if frame.radialSwipe.SetColor then
            frame.radialSwipe:SetColor(
                trackedValue.radialSwipe.color.r or 1,
                trackedValue.radialSwipe.color.g or 1,
                trackedValue.radialSwipe.color.b or 1,
                trackedValue.radialSwipe.color.a or 1
            )
        end
        
        -- Apply position offset
        if frame.radialSwipe.SetOffset then
            frame.radialSwipe:SetOffset(
                trackedValue.radialSwipe.x or 0,
                trackedValue.radialSwipe.y or 0
            )
        end
        
        -- Apply rotation
        if frame.radialSwipe.SetRotation then
            frame.radialSwipe:SetRotation(trackedValue.radialSwipe.rotation or 0)
        end
    end

    CooldownHighlights:UpdateRadialSwipeVisbility(uniqueID, trackedValue, frame, isOnCooldown)

    --===========================
    -- Apply Icon texture and color
    --===========================
    if trackedValue.iconTexturePath and trackedValue.iconTexturePath ~= "" then
        frame.icon:SetTexture(trackedValue.iconTexturePath)
    elseif trackedValue.defaultIconTexturePath then
        frame.icon:SetTexture(trackedValue.defaultIconTexturePath)
    else
        frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    
    -- Apply icon color
    if trackedValue.iconColor then
        frame.icon:SetVertexColor(
            trackedValue.iconColor.r or 1,
            trackedValue.iconColor.g or 1,
            trackedValue.iconColor.b or 1,
            trackedValue.iconColor.a or 1
        )
    else
        frame.icon:SetVertexColor(1, 1, 1, 1)
    end
    
    --===========================
    -- Apply opacity
    --===========================
    frame:SetAlpha(trackedValue.opacity or 1)


    --===========================
    -- Apply cooldown text settings
    --===========================
    frame._TUI_cooldownTextSettings = {
        size = trackedValue.cooldownText.size,
        color = trackedValue.cooldownText.color,
        offsetX = trackedValue.cooldownText.x,
        offsetY = trackedValue.cooldownText.y,
    }
    frame._TUI_cooldownSettingsDirty = true
    
    --===========================
    -- Apply custom label settings
    --===========================
    if frame.customLabel then
        if trackedValue.customLabel.display and trackedValue.customLabel.text and trackedValue.customLabel.text ~= "" then
            frame.customLabel:SetFont("Fonts\\FRIZQT__.TTF", trackedValue.customLabel.size or 10, "OUTLINE")
            frame.customLabel:SetText(trackedValue.customLabel.text)
            frame.customLabel:SetTextColor(
                trackedValue.customLabel.color.r or 1,
                trackedValue.customLabel.color.g or 1,
                trackedValue.customLabel.color.b or 1,
                trackedValue.customLabel.color.a or 1
            )
            frame.customLabel:ClearAllPoints()
            frame.customLabel:SetPoint("CENTER", frame, "CENTER", 
                trackedValue.customLabel.x or 0, 
                trackedValue.customLabel.y or 0)
            frame.customLabel:Show()
        else
            frame.customLabel:Hide()
        end
    end
    
    --===========================
    -- Apply Charges settings
    --===========================
    if frame.count then
        local countText = trackedValue.countText or {}
        
        -- Display setting
        if countText.display == false then
            frame.count:Hide()
        else
            frame.count:Show()
        end
        
        -- Size setting
        local fontSize = countText.size or 14
        local fontPath, _, fontFlags = frame.count:GetFont()
        if fontPath then
            frame.count:SetFont(fontPath, fontSize, fontFlags)
        end
        
        -- Color setting
        if countText.color then
            frame.count:SetTextColor(
                countText.color.r or 1,
                countText.color.g or 1,
                countText.color.b or 1,
                countText.color.a or 1
            )
        else
            frame.count:SetTextColor(1, 1, 1, 1)
        end
        
        -- Offset settings
        frame.count:ClearAllPoints()
        local offsetX = countText.x or 0
        local offsetY = countText.y or 0
        frame.count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", offsetX, offsetY)
    end
    --===========================
    -- Apply position (only if not docked)
    --===========================
    local dockInfo = trackedValue.dock or {}
    if not dockInfo.assignedDock or dockInfo.assignedDock == false then
        -- Only apply position when not docked
        if trackedValue.position then
            frame:ClearAllPoints()
            frame:SetPoint(
                trackedValue.position.anchorPoint or "CENTER",
                UIParent,
                trackedValue.position.relativeAnchorPoint or trackedValue.position.anchorPoint or "CENTER",
                trackedValue.position.x or 0,
                trackedValue.position.y or 0
            )
        end
    end
    -- If docked, the dock system manages positioning
    
    -- Trigger a runtime update to apply current cooldown/visibility state
    CooldownHighlights:UpdateHighlightFrame(uniqueID, trackedValue)
end



-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function CooldownHighlights:Initialize()
    -- Get current spec ID
    local currentSpec = TUICD.Cooldowns and TUICD.Cooldowns.GetCurrentSpecID and TUICD.Cooldowns.GetCurrentSpecID()
    if not currentSpec then return end
    
    -- Check if already initialized for this spec
    if isInitialized[currentSpec] then return end
    isInitialized[currentSpec] = true
    
    -- Get tracked values for this spec
    local trackedValues = CooldownHighlights:GetTrackedValues()
    if not trackedValues then return end
    
    -- Only create frames outside combat to avoid taint
    if not InCombatLockdown() then
        -- Create frames for all enabled entries
        for uniqueID, trackedValue in pairs(trackedValues) do
            if trackedValue.enabled then
                pcall(CreateHighlightFrame, uniqueID, trackedValue)
            end
        end
    end
    
    -- TODO: Restore dock assignments after frames exist
    -- Use longer delay and iterate over dock assignments directly
    -- local function RestoreDockAssignments()
    --     if not TUICD.Docks then return end
    --     
    --     for uniqueID, trackedValue in pairs(trackedValues) do
    --         if trackedValue.dockAssignment and trackerFrames[uniqueID] then
    --             TUICD.Docks:AssignIcon(trackedValue.dockAssignment, uniqueID)
    --         end
    --     end
    -- end
    -- 
    -- -- Try restoration at multiple times to handle varying load orders
    -- C_Timer.After(1, RestoreDockAssignments)
    -- C_Timer.After(3, RestoreDockAssignments)
    
    -- Register layout callbacks
    local Layout = TUICD.Layout
    if Layout then
        Layout:RegisterCallback("OnLayoutModeEnter", function()
            -- TODO: Register frames with layout system
            CooldownHighlights:UpdateAllHighlights()
        end)
        
        Layout:RegisterCallback("OnLayoutModeExit", function()
            CooldownHighlights:UpdateAllHighlights()
        end)
    end
end

function CooldownHighlights:InitializeAll()
    -- Just call Initialize - it now handles the current spec
    self:Initialize()
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
    if event == "SPELL_UPDATE_COOLDOWN" 
        or event == "SPELL_UPDATE_CHARGES"
        or event == "ACTIONBAR_UPDATE_COOLDOWN" then
        -- Runtime updates - use UpdateHighlightFrame via UpdateAllHighlights
        CooldownHighlights:UpdateAllHighlightsThrottled()
    end
    if event == "UNIT_AURA" then
        local unit = ...
        if (unit == "player") then
            CooldownHighlights:UpdateAllHighlightsThrottled()
        end
    end
end)
