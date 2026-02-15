-- ============================================================================
-- TUICD BuffHighlights.lua
-- Creates positionable highlight clones for tracked buffs
-- Detects active/inactive state via auraInstanceID (no secret value math)
-- ============================================================================

local addonName, TUICD = ...
TUICD.BuffHighlights = TUICD.BuffHighlights or {}
local BuffHighlights = TUICD.BuffHighlights

local RadialSwipe = TUICD.RadialSwipe or {}
local FRAME_PREFIX = "TweaksUI_BuffHighlight_"

-- ============================================================================
-- STATE
-- ============================================================================
local cooldownManagerBuffFrames = {}
-- updateFrame is defined in the UPDATE SYSTEM section
local isInitialized = false

-- Event frame for UNIT_AURA and PLAYER_ENTERING_WORLD
local eventFrame = CreateFrame("Frame")

-- ============================================================================
-- DATABASE
-- ============================================================================
local TUICD_buffFrames = {}

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

local function AddNewBuffValue(data)
    return {
        apiIdentifier = data.apiIdentifier, -- this might be the spell ID or the item ID ect. (This value might likely be identical to the "uniqueID" key, but this exists incase there is ever a reason they might need to be different)
        trackingType = "buff", --spell / item / (maybe) buff
        name = data.name,
        iconDisplayState = "active", -- "always", "inactive", "active", "never"
        iconTexturePath = "",
        defaultIconTexturePath = data.iconTexturePath,
        indexUponCollection = data.indexUponCollection,
        iconColor = nil,
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
function BuffHighlights:GetDataBase_V2(classSpecialization)
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
                buffs = {}
            }
        }
    --]]
end

function BuffHighlights:AddBuffValue(trackedValue)
    local db = BuffHighlights:GetDataBase_V2()
    db.buffs[trackedValue.apiIdentifier] = AddNewBuffValue(trackedValue)
    return db.buffs[trackedValue.apiIdentifier]
end
function BuffHighlights:GetBuffValues()
    local db = BuffHighlights:GetDataBase_V2()
    return db.buffs
end

function BuffHighlights:GetBuffValue(uniqueID)
    local db = BuffHighlights:GetDataBase_V2()
    local iconConfig = db.buffs[uniqueID]
    
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
end

function BuffHighlights:IsAlreadyTrackedBuff(buffValue)
    if not buffValue or not buffValue.apiIdentifier then
        return false
    end
    local db = BuffHighlights:GetDataBase_V2()
    return db.buffs[buffValue.apiIdentifier] and true or false
end

function BuffHighlights:RemoveBuffValue(buffValue)
    local db = BuffHighlights:GetDataBase_V2()
    if BuffHighlights:IsAlreadyTrackedBuff(buffValue) then
        local uniqueID = buffValue.apiIdentifier
        
        -- Unregister from layout system
        BuffHighlights:UnregisterFromLayout(uniqueID)
        
        -- Clean up the frame
        local frame = TUICD_buffFrames[uniqueID]
        if frame then
            frame:Hide()
            frame:ClearAllPoints()
            TUICD_buffFrames[uniqueID] = nil
        end
        
        -- Remove from database
        db.buffs[uniqueID] = nil
    end
end

function BuffHighlights:SetBuffConfigValue(uniqueID, path, value)
    local db = BuffHighlights:GetDataBase_V2()
    accessNestedValue(db.buffs[uniqueID], path, value, "set")
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
    
    local buffValue = db.buffs[uniqueID]
    if buffValue and TUICD_buffFrames[uniqueID] then
        BuffHighlights:UpdateBuffConfigurations(uniqueID)
        BuffHighlights:UpdateBuffForAURAEvent(uniqueID)
        --BuffHighlights:UpdateFrameConfigurationChanges(uniqueID, buffValue)
    end
end

function BuffHighlights:GetBuffConfigValue(uniqueID, path)
    --todo:  fix all the state update things to use this instead of the old one, and then connect to the updatefromonconfigchanges or w/e
    local db = BuffHighlights:GetDataBase_V2()
    return accessNestedValue(db.buffs[uniqueID], path, nil, "get")
end

function BuffHighlights:getTrackedValuesListForSettings()
    local buffValues = BuffHighlights:GetBuffValues()
    local listTrackedValues = {}
    
    -- Loop through the buff values
    for uniqueID, buffData in pairs(buffValues) do

        -- Only add buffs that are currently tracked by the cooldown manager.
        if (cooldownManagerBuffFrames[uniqueID]) then
            table.insert(listTrackedValues, {
                uniqueID = uniqueID,
                trackingType = buffData.trackingType,
                apiIdentifier = buffData.apiIdentifier,
                name = buffData.name,
                defaultIconTexturePath = buffData.defaultIconTexturePath
            })
        end
    end
    return listTrackedValues
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

-- Get the buff viewer frame
local function GetBuffViewer()
    return _G["BuffIconCooldownViewer"]
end

local function ScanAndSaveCurrentBuffs()
    local viewer = GetBuffViewer()
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
                cooldownManagerBuffFrames[spellID] = child
                
                -- Add to database if not already tracked
                if not BuffHighlights:IsAlreadyTrackedBuff({ apiIdentifier = spellID }) then
                    BuffHighlights:AddBuffValue({
                        apiIdentifier = spellID,
                        iconTexturePath = texture,
                        name = spellData.name,
                        indexUponCollection = indexUponCollection
                    })
                end
            end
        end
    end
    
    -- After scanning, create frames for any buffs in database that were scanned but don't have frames yet
    local buffConfigs = BuffHighlights:GetBuffValues()
    for spellID, buffConfig in pairs(buffConfigs) do
        -- Only create frame if this buff was found during scan AND doesn't already have a frame
        if cooldownManagerBuffFrames[spellID] and not TUICD_buffFrames[spellID] then
            BuffHighlights:CreateHighlightFrame(spellID, buffConfig)
        end
    end
    BuffHighlights:RegisterAllWithLayout()
end

-- ============================================================================
-- HIGHLIGHT FRAME CREATION (Clone-based - we create our own frame and copy data)
-- ============================================================================

function BuffHighlights:CreateHighlightFrame(uniqueID, buffConfig)
    if TUICD_buffFrames[uniqueID] then
        return TUICD_buffFrames[uniqueID]
    end
    local frameName = FRAME_PREFIX .. uniqueID
    local size = BuffHighlights:GetBuffConfigValue(uniqueID, "size")
    
    local frame = CreateFrame("Button", frameName, UIParent, "BackdropTemplate")
    frame:SetSize(size, size)
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
    frame.icon:SetTexture(BuffHighlights:GetBuffConfigValue(uniqueID, "defaultIconTexturePath"))    
    -- Cooldown spiral
    frame.cooldown = CreateFrame("Cooldown", frameName .. "_Cooldown", frame, "CooldownFrameTemplate")
    frame.Cooldown = frame.cooldown  -- Masque expects .Cooldown
    frame.cooldown:SetAllPoints(frame.icon)
    frame.cooldown:SetFrameLevel(frame:GetFrameLevel() + 2)  -- Above icon texture
    frame.cooldown:SetDrawEdge(true)
    frame.cooldown:SetDrawBling(false)
    frame.cooldown:SetSwipeColor(0, 0, 0, 0.8)
    
    -- Apply sweep and countdown text settings (per-icon overrides tracker-level)
    local hideSweep = BuffHighlights:GetBuffConfigValue(uniqueID, "cooldownText.hideDefaultSweep")
    local showCountdownText = BuffHighlights:GetBuffConfigValue(uniqueID, "cooldownText.display")

    
    frame.cooldown:SetDrawSwipe(hideSweep)
    frame.cooldown:SetHideCountdownNumbers(not showCountdownText)
    
    -- Store settings on cooldown for hooks to use
    frame.cooldown._TUI_hideSweep = hideSweep
    frame.cooldown._TUI_showCountdownText = showCountdownText
    
    -- Hook SetCooldown to reapply settings after Blizzard updates
    hooksecurefunc(frame.cooldown, "SetCooldown", function(self)
        pcall(function()
            self:SetDrawSwipe(self._TUI_hideSweep)
            self:SetHideCountdownNumbers(not self._TUI_showCountdownText)
        end)
    end)
    -- Also hook SetCooldownFromDurationObject for Midnight API
    if frame.cooldown.SetCooldownFromDurationObject then
        hooksecurefunc(frame.cooldown, "SetCooldownFromDurationObject", function(self)
            pcall(function()
                self:SetDrawSwipe(self._TUI_hideSweep)
                self:SetHideCountdownNumbers(not self._TUI_showCountdownText)
            end)
        end)
    end
    
    -- Create radial swipe for cooldown animation
    RadialSwipe:InitializeRadialSwipe(frame, buffConfig.size)
    -- Apply radial swipe texture if set
    if buffConfig.radialSwipe.iconTexturePath and buffConfig.radialSwipe.iconTexturePath ~= "" then
        frame.radialSwipe:SetTexture(buffConfig.radialSwipe.iconTexturePath)
    end
    
    -- Apply radial swipe color
    if frame.radialSwipe.SetColor then
        frame.radialSwipe:SetColor(
            buffConfig.radialSwipe.color.r or 1,
            buffConfig.radialSwipe.color.g or 1,
            buffConfig.radialSwipe.color.b or 1,
            buffConfig.radialSwipe.color.a or 1
        )
    end
    
    -- Apply radial swipe scale
    if frame.radialSwipe.SetSize and buffConfig.radialSwipe.scale then
        local swipeSize = buffConfig.size * buffConfig.radialSwipe.scale
        frame.radialSwipe:SetSize(swipeSize, swipeSize)
    end
    
    -- Apply radial swipe position offset
    if frame.radialSwipe.SetOffset then
        frame.radialSwipe:SetOffset(buffConfig.radialSwipe.x or 0, buffConfig.radialSwipe.y or 0)
    end
    
    -- Apply radial swipe rotation
    if frame.radialSwipe.SetRotation then
        frame.radialSwipe:SetRotation(buffConfig.radialSwipe.rotation or 0)
    end
    frame.cooldown._TUI_uniqueID = uniqueID
    frame.cooldown:SetScript("OnCooldownDone", function(self)
        frame.isOnCooldown = false
        BuffHighlights:UpdateBuffForAURAEvent(self._TUI_uniqueID)
        --TODO: maybe add UpdateCooldown event thing also?
    end)
    frame.radialDisplayState = buffConfig.radialSwipe.displayState
    
    -- Create StatusBar for tracking cooldown progress (secret-value compatible)
    -- This uses the new Midnight API that accepts DurationObjects with secrets
    frame.statusBar = CreateFrame("StatusBar", frameName .. "_StatusBar", frame)
    frame.statusBar:SetPoint("LEFT", frame, "RIGHT", 0, 0)  -- Inside frame, 2px from bottom
    frame.statusBar:SetSize(size * 4, size)  -- 85% of icon width, 4px tall
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
    frame.statusBar.border:SetBackdropBorderColor(0, 0, 0, 1)
    
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
    local pos = BuffHighlights:GetBuffConfigValue(uniqueID, "position")
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
    
    -- Initially hidden
    frame:Hide()
    
    TUICD_buffFrames[uniqueID] = frame
    
    -- Note: Layout registration happens in RegisterWithLayout(), called from EnableHighlight()
    return frame
end

function BuffHighlights:UpdateRadialSwipeVisbility(uniqueID, buffConfig, frame, isOnCooldown)
    -- Update radial swipe visibility based on display state setting
    local showRadialSwipe = false
    if frame and frame.radialSwipe then
        local radialDisplayState = buffConfig.radialSwipe.displayState
        
        if radialDisplayState == "always" then
            -- Always show (full texture when ready, animated swipe when on cooldown)
            showRadialSwipe = true
        elseif radialDisplayState == "cooldown" or radialDisplayState == "active" then
            -- Only show during cooldown (animated swipe)
            showRadialSwipe = isOnCooldown
        elseif radialDisplayState == "available" or radialDisplayState == "inactive" then
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



function BuffHighlights:UpdateBuffConfigurations(uniqueID)
    local buffConfig = BuffHighlights:GetBuffValue(uniqueID)
    local sourceIcon = cooldownManagerBuffFrames[uniqueID]
    local frame = TUICD_buffFrames[uniqueID]
    local isActive = false
    local auraInstanceID = nil
    frame.radialDisplayState = buffConfig.radialSwipe.displayState
    if sourceIcon then
        pcall(function()
            auraInstanceID = sourceIcon.auraInstanceID
            isActive = (auraInstanceID ~= nil)
        end)
    end
    local showForCurrentState = (buffConfig.iconDisplayState == "always") or (buffConfig.iconDisplayState == "active" and isActive) or (buffConfig.iconDisplayState == "inactive" and not isActive) or false
    if showForCurrentState then
        frame:Show()
    else
        frame:Hide()
        return
    end
    if not isActive and showForCurrentState then
        frame.icon:SetDesaturated(buffConfig.desaturated)
    end
    
    -- Update icon texture
    local iconTexture = buffConfig.iconTexturePath
    if not iconTexture or iconTexture == "" then
        iconTexture = buffConfig.defaultIconTexturePath
    end
    if iconTexture then
        frame.icon:SetTexture(iconTexture)
    end
    
    -- Update icon color
    if buffConfig.iconColor and buffConfig.iconColor.r then
        frame.icon:SetVertexColor(
            buffConfig.iconColor.r or 1,
            buffConfig.iconColor.g or 1,
            buffConfig.iconColor.b or 1,
            buffConfig.iconColor.a or 1
        )
    else
        -- Reset to default white if no color is set
        frame.icon:SetVertexColor(1, 1, 1, 1)
    end
    
    -- Update size
    if buffConfig.size then
        frame:SetSize(buffConfig.size, buffConfig.size)
    end
    
    -- Update opacity
    if buffConfig.opacity then
        frame:SetAlpha(buffConfig.opacity)
    end

    if frame.cooldown then
        pcall(function()
            frame.cooldown:SetDrawSwipe(not buffConfig.cooldownText.hideDefaultSweep)
            frame.cooldown:SetHideCountdownNumbers(not buffConfig.cooldownText.display)
        end)
        
        -- Update cooldown text styling (if it exists)
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
        
        if cdText and buffConfig.cooldownText then
            pcall(function()
                -- Apply font size
                local fontPath, _, fontFlags = cdText:GetFont()
                if fontPath and buffConfig.cooldownText.size then
                    cdText:SetFont(fontPath, buffConfig.cooldownText.size, fontFlags or "OUTLINE")
                end
                
                -- Apply color
                if buffConfig.cooldownText.color then
                    cdText:SetTextColor(
                        buffConfig.cooldownText.color.r or 1,
                        buffConfig.cooldownText.color.g or 1,
                        buffConfig.cooldownText.color.b or 1,
                        buffConfig.cooldownText.color.a or 1
                    )
                end
                
                -- Apply offset
                cdText:ClearAllPoints()
                cdText:SetPoint("CENTER", frame.cooldown, "CENTER", 
                    buffConfig.cooldownText.x or 0, 
                    buffConfig.cooldownText.y or 0)
            end)
        end
    end
    
    -- Update count/stack text
    if frame.count and buffConfig.countText then
        pcall(function()
            -- Apply font size
            local fontPath, _, fontFlags = frame.count:GetFont()
            if fontPath and buffConfig.countText.size then
                frame.count:SetFont(fontPath, buffConfig.countText.size, fontFlags or "OUTLINE")
            end

            -- Clear text if display is disabled (will be populated by UpdateBuffForAURAEvent)
            if not buffConfig.countText.display then
                frame.count:SetText("")
            end
            
            
            -- Apply color
            if buffConfig.countText.color then
                frame.count:SetTextColor(
                    buffConfig.countText.color.r or 1,
                    buffConfig.countText.color.g or 1,
                    buffConfig.countText.color.b or 1,
                    buffConfig.countText.color.a or 1
                )
            end
            
            -- Apply offset
            frame.count:ClearAllPoints()
            frame.count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 
                (buffConfig.countText.x or 0) - 2, 
                (buffConfig.countText.y or 0) + 2)
        end)
    end
    
    -- Update custom label
    if frame.customLabel and buffConfig.customLabel then
        pcall(function()
            -- Set visibility and text
            if buffConfig.customLabel.display and buffConfig.customLabel.text and buffConfig.customLabel.text ~= "" then
                frame.customLabel:SetText(buffConfig.customLabel.text)
                frame.customLabel:Show()
            else
                frame.customLabel:Hide()
            end
            
            -- Apply font size
            if buffConfig.customLabel.size then
                frame.customLabel:SetFont("Fonts\\FRIZQT__.TTF", buffConfig.customLabel.size, "OUTLINE")
            end
            
            -- Apply color
            if buffConfig.customLabel.color then
                frame.customLabel:SetTextColor(
                    buffConfig.customLabel.color.r or 1,
                    buffConfig.customLabel.color.g or 1,
                    buffConfig.customLabel.color.b or 1,
                    buffConfig.customLabel.color.a or 1
                )
            end
            
            -- Apply offset
            frame.customLabel:ClearAllPoints()
            frame.customLabel:SetPoint("CENTER", frame, "CENTER", 
                buffConfig.customLabel.x or 0, 
                buffConfig.customLabel.y or 0)
        end)
    end
    
    -- Update position
    local pos = buffConfig.position
    if pos and pos.anchorPoint and pos.x and pos.y then
        frame:ClearAllPoints()
        frame:SetPoint(
            pos.anchorPoint, 
            UIParent,
            pos.relativeAnchorPoint or pos.anchorPoint, 
            pos.x or 0, 
            pos.y or 0
        )
    end
    
    -- Update radial swipe configuration
    if frame.radialSwipe and buffConfig.radialSwipe then
        -- Apply texture
        if frame.radialSwipe.SetTexture then
            if buffConfig.radialSwipe.iconTexturePath and buffConfig.radialSwipe.iconTexturePath ~= "" then
                frame.radialSwipe:SetTexture(buffConfig.radialSwipe.iconTexturePath)
            else
                frame.radialSwipe:SetTexture("Interface\\AddOns\\TweaksUI_Cooldowns\\Media\\Textures\\square_outline.tga")
            end
        end
        
        -- Apply size/scale
        if frame.radialSwipe.SetSize then
            local swipeSize = buffConfig.size * (buffConfig.radialSwipe.scale or 1)
            frame.radialSwipe:SetSize(swipeSize, swipeSize)
        end
        
        -- Apply color
        if frame.radialSwipe.SetColor then
            frame.radialSwipe:SetColor(
                buffConfig.radialSwipe.color.r or 1,
                buffConfig.radialSwipe.color.g or 1,
                buffConfig.radialSwipe.color.b or 1,
                buffConfig.radialSwipe.color.a or 1
            )
        end
        
        -- Apply position offset
        if frame.radialSwipe.SetOffset then
            frame.radialSwipe:SetOffset(
                buffConfig.radialSwipe.x or 0,
                buffConfig.radialSwipe.y or 0
            )
        end
        
        -- Apply rotation
        if frame.radialSwipe.SetRotation then
            frame.radialSwipe:SetRotation(buffConfig.radialSwipe.rotation or 0)
        end
    end
    
    -- Update radial swipe visibility based on buff active state
    -- Check if buff has an active duration (not just if it's active)
    local hasActiveDuration = false
    if isActive and frame.cooldown and frame.cooldown.GetCooldownTimes then
        pcall(function()
            local start, duration = frame.cooldown:GetCooldownTimes()
            if start and duration and duration > 0 then
                local startSec = start / 1000
                local durationSec = duration / 1000
                local remaining = (startSec + durationSec) - GetTime()
                hasActiveDuration = remaining > 0
            end
        end)
    end

    pcall(function()
        frame.cooldown:SetDrawSwipe(not buffConfig.cooldownText.hideDefaultSweep)
        frame.cooldown:SetDrawEdge(not buffConfig.cooldownText.hideDefaultSweep)
        frame.cooldown:SetHideCountdownNumbers(not buffConfig.cooldownText.display)
    end)
    -- For buffs: hasActiveDuration means buff has a timer counting down ("on cooldown")
    -- Permanent buffs (no duration) should not show radial swipe cooldown
    BuffHighlights:UpdateRadialSwipeVisbility(uniqueID, buffConfig, frame, hasActiveDuration)
end

function BuffHighlights:UpdateBuffForAURAEvent(uniqueID, auraInstanceID)
    local frame = TUICD_buffFrames[uniqueID]
    if not frame then
        return
    end
    local sourceIcon = cooldownManagerBuffFrames[uniqueID]
    local config = BuffHighlights:GetBuffValue(uniqueID)

    local isActive = false
    local auraInstanceID = auraInstanceID or nil
    if sourceIcon then
        pcall(function()
            auraInstanceID = sourceIcon.auraInstanceID
            isActive = (auraInstanceID ~= nil)
        end)
    end
    
    -- Check if buff has an active duration (temporary buff) vs permanent buff
    local hasActiveDuration = false
    if isActive and frame.cooldown and frame.cooldown.GetCooldownTimes then
        pcall(function()
            local start, duration = frame.cooldown:GetCooldownTimes()
            -- GetCooldownTimes returns milliseconds
            if start and duration and duration > 0 then
                local startSec = start / 1000
                local durationSec = duration / 1000
                local remaining = (startSec + durationSec) - GetTime()
                hasActiveDuration = remaining > 0
            end
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
    elseif sourceIcon then
        local sourceCountFS = sourceIcon.Count or sourceIcon.count
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

    -- Respect iconDisplayState configuration
    local showForCurrentState = (config.iconDisplayState == "always") or 
                                 (config.iconDisplayState == "active" and isActive) or 
                                 (config.iconDisplayState == "inactive" and not isActive)
    
    if showForCurrentState then
        if not isActive then
            frame.icon:SetDesaturated(config.desaturated)
        end
        frame:Show()
    else
        frame:Hide()
    end
    
    -- Update radial swipe visibility based on buff duration state
    -- For buffs: hasActiveDuration means buff has a timer counting down ("on cooldown")
    -- Permanent buffs (no duration) should not show radial swipe cooldown
    BuffHighlights:UpdateRadialSwipeVisbility(uniqueID, config, frame, hasActiveDuration)
end


function BuffHighlights:UpdateBuffForActiveCooldown(uniqueID, buffState)
    local frame = TUICD_buffFrames[uniqueID]
    if not frame then
        return
    end
    local sourceIcon = cooldownManagerBuffFrames[uniqueID]
    local config = BuffHighlights:GetBuffValue(uniqueID)
   
    -- =========================================================================
    -- COOLDOWN - Mirror directly from source icon's Cooldown frame
    -- This is the key - Blizzard's cooldown frame is already showing correctly
    -- =========================================================================
    local sourceCooldown = sourceIcon and (sourceIcon.Cooldown or sourceIcon.cooldown)
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
        
        -- Apply sweep visibility
        if config and config.cooldownText then
            pcall(function()
                frame.cooldown:SetDrawSwipe(not config.cooldownText.hideDefaultSweep)
                frame.cooldown:SetDrawEdge(not config.cooldownText.hideDefaultSweep)
                frame.cooldown:SetHideCountdownNumbers(not config.cooldownText.display)
            end)
        end
    elseif frame.cooldown then
        frame.cooldown:Clear()
        frame.isOnCooldown = false
        -- Cooldown cleared means buff duration expired or buff became permanent
        if config and config.radialSwipe then
            BuffHighlights:UpdateRadialSwipeVisbility(uniqueID, config, frame, false)
        end
    end
end
-- ============================================================================
-- LAYOUT INTEGRATION
-- ============================================================================

local layoutWrappers = {}  -- Cache layout wrappers by uniqueID

local function CreateLayoutWrapper(uniqueID, trackedValue)
    local frame = TUICD_buffFrames[uniqueID]
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
            -- TODO: Skip if docked when dock system is updated
            -- if trackedValue.dockAssignment then return end
            frame:ClearAllPoints()
            frame:SetPoint(point, UIParent, point, x, y)
            
            -- Update position in database
            BuffHighlights:SetBuffConfigValue(uniqueID, "position", {
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
            -- if trackedValue.dockAssignment then return end
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

function BuffHighlights:RegisterWithLayout(uniqueID, buffConfig)
    local frame = TUICD_buffFrames[uniqueID]
    if not frame or not buffConfig then return end
    
    local wrapperId = "TUICD_Tracker_" .. uniqueID
    
    -- Return existing wrapper if already registered
    if layoutWrappers[uniqueID] then
        return layoutWrappers[uniqueID]
    end
    
    local wrapper = CreateLayoutWrapper(uniqueID, buffConfig)
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

function BuffHighlights:RegisterAllWithLayout()
    if not TUICD.Layout then
        dprint("Layout module not available")
        return
    end
    
    local buffConfigs = BuffHighlights:GetBuffValues()
    for uniqueID, buffConfig in pairs(buffConfigs) do
        if buffConfig.enabled and TUICD_buffFrames[uniqueID] then
            BuffHighlights:RegisterWithLayout(uniqueID, buffConfig)
        end
    end
end

function BuffHighlights:UnregisterFromLayout(uniqueID)
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
function BuffHighlights:SetupBuffManagerHooks()
    local viewer = GetBuffViewer()
    if not viewer then
        dprint("BuffIconCooldownViewer not found, will retry")
        C_Timer.After(1, function() self:SetupBuffManagerHooks() end)
        return
    end
    
    hooksecurefunc(viewer, "Layout", function()
        -- After Layout, scan icons and set up cooldown hooks
        C_Timer.After(0, function()  -- Next frame, after Blizzard sets cooldowns
            self:HookAllBuffCooldownFrames()
        end)
    end)
    -- Initial scan of existing icons
    self:HookAllBuffCooldownFrames()
end

-- Hook all buff icon cooldowns to mirror to per-icon frames
function BuffHighlights:HookAllBuffCooldownFrames()
    local viewer = GetBuffViewer()
    if not viewer then return end
    ScanAndSaveCurrentBuffs()
    for slotIndex, cdm_buffFrame in pairs(cooldownManagerBuffFrames) do
        -- Hide the Blizzard buff frames by keeping alpha at 0
        if not cdm_buffFrame._tuicd_alphaLocked then
            cdm_buffFrame._tuicd_alphaLocked = true
            cdm_buffFrame:SetAlpha(0)
            
            -- Hook SetAlpha with recursion guard
            hooksecurefunc(cdm_buffFrame, 'SetAlpha', function(self, alpha)
                if not self._tuicd_settingAlpha and alpha ~= 0 then
                    self._tuicd_settingAlpha = true
                    self:SetAlpha(0)
                    self._tuicd_settingAlpha = false
                end
            end)
        end
        
        hooksecurefunc(cdm_buffFrame, "RefreshApplications", function(self)
            local uniqueID = self.tuicd_spellID
            if uniqueID and TUICD_buffFrames[uniqueID] then
                BuffHighlights:UpdateBuffForAURAEvent(uniqueID)
            end
        end)

        -- RefreshActive is called when buff becomes active/inactive
        hooksecurefunc(cdm_buffFrame, "RefreshActive", function(self)
            local uniqueID = self.tuicd_spellID
            if uniqueID and TUICD_buffFrames[uniqueID] then
                BuffHighlights:UpdateBuffForAURAEvent(uniqueID)
            end
        end)
        hooksecurefunc(cdm_buffFrame, "UpdateShownState", function(self)
            local uniqueID = self.tuicd_spellID
            if uniqueID and TUICD_buffFrames[uniqueID] then
                BuffHighlights:UpdateBuffForAURAEvent(uniqueID)
            end
        end)

        local sourceCooldown = cdm_buffFrame.Cooldown or cdm_buffFrame.cooldown
        if sourceCooldown and not cdm_buffFrame.hasHookedCooldown then
            cdm_buffFrame.hasHookedCooldown = true
            -- Hook SetCooldownFromDurationObject (Midnight primary method)
            if sourceCooldown.SetCooldownFromDurationObject then
                hooksecurefunc(sourceCooldown, "SetCooldownFromDurationObject", function(self, durationObj, clearIfZero)
                    local uniqueID = self.tuicd_spellID
                    if uniqueID and TUICD_buffFrames[uniqueID] and TUICD_buffFrames[uniqueID].cooldown then
                        local targetCd = TUICD_buffFrames[uniqueID].cooldown
                        if targetCd.SetCooldownFromDurationObject then
                            pcall(function()
                                targetCd:SetCooldownFromDurationObject(durationObj, clearIfZero)
                                targetCd:Show()
                                TUICD_buffFrames[uniqueID].isOnCooldown = true
                                
                                -- Update StatusBar with DurationObject (secret-value compatible)
                                -- This will animate the bar automatically with interpolation
                                if TUICD_buffFrames[uniqueID].statusBar and TUICD_buffFrames[uniqueID].statusBar.SetTimerDuration then
                                    pcall(function()
                                        TUICD_buffFrames[uniqueID].statusBar:SetTimerDuration(
                                            durationObj,
                                            Enum.StatusBarInterpolation.ExponentialEaseOut,
                                            Enum.StatusBarTimerDirection.RemainingTime
                                        )
                                        TUICD_buffFrames[uniqueID].statusBar:Show()
                                    end)
                                end
                                
                                local config = BuffHighlights:GetBuffValue(uniqueID)
                                if config.radialSwipe.displayState == "always" or config.radialSwipe.displayState == "cooldown" or config.radialSwipe.displayState == "active" then
                                    TUICD_buffFrames[uniqueID].cooldown._TUI_cooldownComplete = false
                                    TUICD_buffFrames[uniqueID].isOnCooldown = true  -- Buff has active duration counting down
                                    RadialSwipe:OnUpdate(TUICD_buffFrames[uniqueID])
                                end
                                BuffHighlights:UpdateBuffForActiveCooldown(uniqueID, "active")
                            end)
                        end
                    end
                end)
            end
            
            -- Hook SetCooldown (traditional method)
            hooksecurefunc(sourceCooldown, "SetCooldown", function(self, start, duration)
                local uniqueID = self.tuicd_spellID
                if uniqueID and TUICD_buffFrames[uniqueID] and TUICD_buffFrames[uniqueID].cooldown then
                    local targetCd = TUICD_buffFrames[uniqueID].cooldown
                    pcall(function()
                        targetCd:SetCooldown(start, duration)
                        targetCd:Show()
                        TUICD_buffFrames[uniqueID].isOnCooldown = true
                        
                        -- Update StatusBar using traditional SetCooldown values
                        -- Convert start/duration to DurationObject for StatusBar
                        if TUICD_buffFrames[uniqueID].statusBar and start > 0 and duration > 0 then
                            pcall(function()
                                -- Create DurationObject from start/duration values
                                if C_DurationUtil and C_DurationUtil.CreateDuration then
                                    local durationObj = C_DurationUtil.CreateDuration()
                                    durationObj:SetTimeFromStart(start, duration)
                                    if durationObj and TUICD_buffFrames[uniqueID].statusBar.SetTimerDuration then
                                        TUICD_buffFrames[uniqueID].statusBar:SetTimerDuration(
                                            durationObj,
                                            Enum.StatusBarInterpolation.ExponentialEaseOut,
                                            Enum.StatusBarTimerDirection.RemainingTime
                                        )
                                        TUICD_buffFrames[uniqueID].statusBar:Show()
                                    end
                                end
                            end)
                        end
                        
                        local config = BuffHighlights:GetBuffValue(uniqueID)
                        if config.radialSwipe.displayState == "always" or config.radialSwipe.displayState == "cooldown" or config.radialSwipe.displayState == "active" then
                            TUICD_buffFrames[uniqueID].cooldown._TUI_cooldownComplete = false
                            TUICD_buffFrames[uniqueID].isOnCooldown = true  -- Buff has active duration counting down
                            RadialSwipe:OnUpdate(TUICD_buffFrames[uniqueID])
                        end
                        BuffHighlights:UpdateBuffForActiveCooldown(uniqueID, "active")
                    end)
                end
            end)
            
            -- Hook Clear
            hooksecurefunc(sourceCooldown, "Clear", function(self)
                local uniqueID = self.tuicd_spellID
                if uniqueID and TUICD_buffFrames[uniqueID] and TUICD_buffFrames[uniqueID].cooldown then
                    pcall(function()
                        TUICD_buffFrames[uniqueID].cooldown:Clear()
                        TUICD_buffFrames[uniqueID].isOnCooldown = false
                        
                        -- Hide StatusBar when cooldown is cleared
                        if TUICD_buffFrames[uniqueID].statusBar then
                            TUICD_buffFrames[uniqueID].statusBar:Hide()
                        end
                        
                        BuffHighlights:UpdateBuffForActiveCooldown(uniqueID, "inactive")
                    end)
                end
            end)
        end
    end
end

function BuffHighlights:UpdateAllHighlights()
    local buffConfigs = BuffHighlights:GetBuffValues()
    for uniqueID, buffConfig in pairs(buffConfigs) do
        BuffHighlights:UpdateBuffForAURAEvent(uniqueID)
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================
local hasPlayerEnetedWorld = false
local hasDatabaseLoaded = false

function BuffHighlights:Initalize()
    if isInitialized or not hasDatabaseLoaded or not hasPlayerEnetedWorld then return end
    isInitialized = true
    BuffHighlights:SetupBuffManagerHooks()
    BuffHighlights:UpdateAllHighlights()
    C_Timer.After(3, function()
        -- Re-setup hooks in case viewer was recreated
        BuffHighlights:SetupBuffManagerHooks()
        BuffHighlights:UpdateAllHighlights()
    end)
end

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_ENTERING_WORLD" then
        hasPlayerEnetedWorld = true
        BuffHighlights:Initalize()
    end
end)

TUICD.Events:Register("DATABASE_LOADED", function()
    hasDatabaseLoaded = true
    BuffHighlights:Initalize()
end)
