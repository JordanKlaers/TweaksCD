local ADDON_NAME, TUICD = ...

TUICD.NewDocks = TUICD.NewDocks or {}
local NewDocks = TUICD.NewDocks


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

local function AddNewDockConfig(data)
    return {
        name = data.name,
        desaturated = false,
        dockPosition = {
            anchorPoint = "center",
            relativeToFrame = UIParent,
            relativeAnchorPoint = "center",
            x = 0,
            y = 0
        },
        enabled = true,
        opacity = 1,
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
        showProcGlow = true,  -- Show spell activation glow
        overwriteKeys = {
            iconDisplayState = true,
            desaturated = true,
            opacity = true,
            cooldownText = true,
            countText = true,
            showProcGlow = true
        },
        boundFrames = {
            --[[
                [uniqueID] = {
                    anchorPoint = "CENTER",
                    relativeToFrame = <dock frame>,
                    relativeAnchorPoint = "CENTER",
                    x = 0,
                    y = 0
                }
            ]]
        }
    }
end
function NewDocks:GetDataBase_V2()
	local classSpecialization = TUICD.Cooldowns.GetCurrentSpecID()
    if not TweaksUI_Cooldowns_CharDB.classSpecializations then TweaksUI_Cooldowns_CharDB.classSpecializations = {} end
    TweaksUI_Cooldowns_CharDB.classSpecializations[classSpecialization] = TweaksUI_Cooldowns_CharDB.classSpecializations[classSpecialization] or {
        [classSpecialization] = {
            trackers = {},
            buffs = {},
			docks = {}
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

function NewDocks:AddNewDockInstance()
    local db = NewDocks:GetDataBase_V2()
	local newDockName = "dock " .. #db.docks
    db.docks[newDockName] = AddNewDockConfig({name = newDockName})
    return db.docks[newDockName]
end

-- Ensure a specific dock exists, creating it if needed
function NewDocks:EnsureDockExists(dockName)
    local db = NewDocks:GetDataBase_V2()
    if not db.docks[dockName] then
        db.docks[dockName] = AddNewDockConfig({name = dockName})
    end
    return db.docks[dockName]
end
function NewDocks:GetAllDockInstances()
    local db = NewDocks:GetDataBase_V2()
    return db.docks
end

function NewDocks:GetDockIntance(name)
    local db = NewDocks:GetDataBase_V2()
    return db.docks[name]
end

function NewDocks:DeleteDockInstance(name)
    local db = NewDocks:GetDataBase_V2()
    if db.docks[name] then
		--TODO: remove the icons and stuff like that
    end
end

function NewDocks:SetDockInstanceConfigValue(name, path, value)
    local db = NewDocks:GetDataBase_V2()
    accessNestedValue(db.docks[name], path, value, "set")
end

function NewDocks:GetDockInstanceConfigValue(name, path)
    local db = NewDocks:GetDataBase_V2()
    return accessNestedValue(db.docks[name], path, nil, "get")
end

-- Get formatted options for dropdown menus (icon assignment UI)
function NewDocks:GetDockDropdownOptions()
    local options = {
        { label = "None", value = false }
    }
    
    local db = NewDocks:GetDataBase_V2()
    if db and db.docks then
        for dockName, dockConfig in pairs(db.docks) do
            local displayName = (dockConfig.name and dockConfig.name ~= "") and dockConfig.name or dockName
            table.insert(options, {
                label = displayName,
                value = dockName
            })
        end
    end
    
    return options
end

-- ============================================================================
-- DOCK FRAME CREATION
-- ============================================================================

-- Storage for created dock frames
local dockFrames = {}  -- [dockName] = frame
local dockLayoutWrappers = {}  -- [dockName] = wrapper

local function CreateDockFrame(dockName)
    local frameName = "TweaksUI_Dock_" .. dockName:gsub(" ", "_")
    
    -- Return existing frame if already created
    if dockFrames[dockName] then
        return dockFrames[dockName]
    end
    
    if _G[frameName] then
        dockFrames[dockName] = _G[frameName]
        return _G[frameName]
    end
    
    -- Get dock config
    local dockConfig = NewDocks:GetDockIntance(dockName)
    if not dockConfig then
        return nil
    end
    
    local dock = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
    dock:SetSize(100, 50)
    dock:SetFrameStrata("LOW")
    dock:SetFrameLevel(20)
    dock:SetClampedToScreen(true)
    dock:SetMovable(true)
    dock:EnableMouse(false)
    
    dock:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    dock:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    dock:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    dock.label = dock:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dock.label:SetPoint("TOP", dock, "BOTTOM", 0, -2)
    dock.label:SetText(dockConfig.name or dockName)
    dock.label:SetTextColor(0.6, 0.6, 0.6, 0.8)
    dock.label:Hide()
    
    dock.dockName = dockName
    
    -- Position dock
    local pos = dockConfig.dockPosition or {}
    local anchorPoint = pos.anchorPoint or "CENTER"
    local relativePoint = pos.relativeAnchorPoint or "CENTER"
    local x = pos.x or 0
    local y = pos.y or 0
    
    dock:ClearAllPoints()
    dock:SetPoint(anchorPoint, UIParent, relativePoint, x, y)
    
    dock:Show()
    
    dockFrames[dockName] = dock
    
    return dock
end

-- ============================================================================
-- BOUND FRAMES MANAGEMENT
-- ============================================================================

-- Add or update a bound frame position in a dock
function NewDocks:AddBoundFrame(dockName, uniqueID, positionData)
    local db = NewDocks:GetDataBase_V2()
    local dock = db.docks[dockName]
    
    if not dock then
        return false
    end
    
    -- Ensure boundFrames exists
    if not dock.boundFrames then
        dock.boundFrames = {}
    end
    
    -- Set default position if not provided
    -- Note: relativeToFrame is intentionally nil here and should be resolved at runtime
    -- using NewDocks:GetOrCreateDockFrame(dockName)
    local position = positionData or {
        anchorPoint = "CENTER",
        relativeToFrame = dockFrames[dockName],  -- Resolved at runtime via GetOrCreateDockFrame
        relativeAnchorPoint = "CENTER",
        x = 0,
        y = 0
    }
    
    dock.boundFrames[uniqueID] = position
    return true
end

-- Remove a bound frame from a dock
function NewDocks:RemoveBoundFrame(dockName, uniqueID)
    local db = NewDocks:GetDataBase_V2()
    local dock = db.docks[dockName]
    
    if not dock or not dock.boundFrames then
        return false
    end
    
    dock.boundFrames[uniqueID] = nil
    return true
end

-- Calculate icon position relative to dock frame (maintains visual position)
-- Call this when first assigning an icon to a dock
function NewDocks:CalculateIconPositionRelativeToDock(uniqueID, dockName)
    local dockFrame = self:GetOrCreateDockFrame(dockName)
    if not dockFrame then return nil end
    
    -- Get icon frame from CooldownHighlights or BuffHighlights
    local iconFrame = nil
    if TUICD.CooldownHighlights and TUICD.CooldownHighlights.GetIconFrame then
        iconFrame = TUICD.CooldownHighlights:GetIconFrame(uniqueID)
    end
    if not iconFrame and _G["TUICD_Highlight_" .. uniqueID] then
        iconFrame = _G["TUICD_Highlight_" .. uniqueID]
    end
    if not iconFrame and _G["TUICD_Buff_" .. uniqueID] then
        iconFrame = _G["TUICD_Buff_" .. uniqueID]
    end
    
    if not iconFrame then return nil end
    
    -- Get current icon position relative to UIParent
    local iconPoint, iconRelTo, iconRelPoint, iconX, iconY = iconFrame:GetPoint(1)
    if not iconPoint then return nil end
    
    -- Get dock position relative to UIParent
    local dockPoint, dockRelTo, dockRelPoint, dockX, dockY = dockFrame:GetPoint(1)
    if not dockPoint then return nil end
    
    -- Calculate icon position relative to dock to maintain visual position
    -- new_x = icon_x - dock_x
    -- new_y = icon_y - dock_y
    local relativeX = (iconX or 0) - (dockX or 0)
    local relativeY = (iconY or 0) - (dockY or 0)
    
    return {
        anchorPoint = "CENTER",  -- Use CENTER for simplicity
        relativeToFrame = nil,  -- Will be resolved at runtime
        relativeAnchorPoint = "CENTER",
        x = relativeX,
        y = relativeY
    }
end

-- Apply saved position to an icon frame from dock's boundFrames
function NewDocks:ApplyBoundFramePosition(uniqueID, dockName)
    local db = NewDocks:GetDataBase_V2()
    local dock = db.docks[dockName]
    
    if not dock or not dock.boundFrames or not dock.boundFrames[uniqueID] then
        return false
    end
    
    local dockFrame = self:GetOrCreateDockFrame(dockName)
    if not dockFrame then return false end
    
    -- Get icon frame
    local iconFrame = nil
    if TUICD.CooldownHighlights and TUICD.CooldownHighlights.GetIconFrame then
        iconFrame = TUICD.CooldownHighlights:GetIconFrame(uniqueID)
    end
    if not iconFrame and _G["TUICD_Highlight_" .. uniqueID] then
        iconFrame = _G["TUICD_Highlight_" .. uniqueID]
    end
    if not iconFrame and _G["TUICD_Buff_" .. uniqueID] then
        iconFrame = _G["TUICD_Buff_" .. uniqueID]
    end
    
    if not iconFrame then return false end
    
    local position = dock.boundFrames[uniqueID]
    
    -- Apply position relative to dock
    iconFrame:ClearAllPoints()
    iconFrame:SetPoint(
        position.anchorPoint or "CENTER",
        dockFrame,
        position.relativeAnchorPoint or "CENTER",
        position.x or 0,
        position.y or 0
    )
    
    return true
end

-- Update positions of all bound icons in a dock
-- Call this when the dock is moved
function NewDocks:UpdateAllBoundIconPositions(dockName)
    local db = NewDocks:GetDataBase_V2()
    local dock = db.docks[dockName]
    
    if not dock or not dock.boundFrames then
        return
    end
    
    -- Apply saved positions to all bound icons
    for uniqueID, positionData in pairs(dock.boundFrames) do
        self:ApplyBoundFramePosition(uniqueID, dockName)
    end
end
-- ============================================================================
-- LAYOUT MODE INTEGRATION
-- Creates TUIFrame-compatible wrappers for docks so they appear in Layout Mode
-- ============================================================================

local function CreateDockLayoutWrapper(dockName)
    local dock = dockFrames[dockName]
    if not dock then return nil end
    
    local dockConfig = NewDocks:GetDockIntance(dockName)
    if not dockConfig then return nil end
    
    local wrapperId = "Dock_" .. dockName:gsub(" ", "_")
    
    -- Already has a wrapper
    if dockLayoutWrappers[dockName] then
        return dockLayoutWrappers[dockName]
    end
    
    -- Create TUIFrame-compatible wrapper object
    local wrapper = {
        id = wrapperId,
        frame = dock,
        name = dockConfig.name or dockName,
        category = "Cooldowns",
        
        -- Default position
        defaultPosition = {
            point = "CENTER",
            x = 0,
            y = 0,
        },
        
        -- Position management
        SetPosition = function(self, point, relFrame, relPoint, x, y)
            if InCombatLockdown() then return end
            
            relFrame = relFrame or UIParent
            relPoint = relPoint or point or "CENTER"
            point = point or "CENTER"
            x = x or 0
            y = y or 0
            
            dock:ClearAllPoints()
            dock:SetPoint(point, relFrame, relPoint, x, y)
            
            -- Save to dock config
            NewDocks:SetDockInstanceConfigValue(dockName, "dockPosition.anchorPoint", point)
            NewDocks:SetDockInstanceConfigValue(dockName, "dockPosition.relativeAnchorPoint", relPoint)
            NewDocks:SetDockInstanceConfigValue(dockName, "dockPosition.x", x)
            NewDocks:SetDockInstanceConfigValue(dockName, "dockPosition.y", y)
            
            -- Update all bound icon positions to move with the dock
            NewDocks:UpdateAllBoundIconPositions(dockName)
        end,
        
        GetSaveData = function(self)
            local point, relTo, relPoint, x, y = dock:GetPoint(1)
            
            if point then
                return {
                    point = point,
                    relPoint = relPoint or "CENTER",
                    x = x or 0,
                    y = y or 0,
                }
            end
            
            return {
                point = "CENTER",
                relPoint = "CENTER",
                x = 0,
                y = 0,
            }
        end,
        
        LoadSaveData = function(self, data)
            if not data then return end
            if InCombatLockdown() then return end
            
            local point = data.point or "CENTER"
            local relPoint = data.relPoint or "CENTER"
            local x = data.x or 0
            local y = data.y or 0
            
            dock:ClearAllPoints()
            dock:SetPoint(point, UIParent, relPoint, x, y)
            
            -- Save to dock config
            NewDocks:SetDockInstanceConfigValue(dockName, "dockPosition.anchorPoint", point)
            NewDocks:SetDockInstanceConfigValue(dockName, "dockPosition.relativeAnchorPoint", relPoint)
            NewDocks:SetDockInstanceConfigValue(dockName, "dockPosition.x", x)
            NewDocks:SetDockInstanceConfigValue(dockName, "dockPosition.y", y)
        end,
        
        -- Size management
        GetSize = function(self)
            return dock:GetSize()
        end,
        
        GetWidth = function(self)
            return dock:GetWidth()
        end,
        
        GetHeight = function(self)
            return dock:GetHeight()
        end,
        
        -- Scale
        GetScale = function(self)
            return dock:GetScale() or 1
        end,
        
        SetScale = function(self, scale)
            dock:SetScale(scale)
        end,
        
        -- Visibility
        Show = function(self)
            dock:Show()
        end,
        
        Hide = function(self)
            dock:Hide()
        end,
        
        IsShown = function(self)
            return dock:IsShown()
        end,
        
        -- FlyPaper snap detection
        GetSnapTarget = function(self, tolerance)
            local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)
            if not FlyPaper or not FlyPaper.Stick then return nil end
            
            local point, relFrame, relPoint, x, y = FlyPaper.Stick(
                dock,
                "TUICD",
                tolerance
            )
            if point and relFrame then
                return relFrame, point, relPoint, x, y
            end
            return nil
        end,
    }
    
    dock.tuiFrame = wrapper
    dockLayoutWrappers[dockName] = wrapper
    
    -- Register with FlyPaper for snap highlighting
    local FlyPaper = LibStub and LibStub("LibFlyPaper-2.0", true)
    if FlyPaper and FlyPaper.AddFrame then
        FlyPaper.AddFrame("TUICD", wrapperId, dock)
    end
    
    return wrapper
end

function NewDocks:RegisterDockWithLayout(dockName)
    local Layout = TUICD.Layout
    if not Layout or not Layout.RegisterElement then
        return false
    end
    
    -- Ensure dock frame exists
    local dock = dockFrames[dockName]
    if not dock then
        dock = CreateDockFrame(dockName)
    end
    
    if not dock then
        return false
    end
    
    -- Create wrapper
    local wrapper = dockLayoutWrappers[dockName]
    if not wrapper then
        wrapper = CreateDockLayoutWrapper(dockName)
    end
    
    if not wrapper then
        return false
    end
    
    local wrapperId = "Dock_" .. dockName:gsub(" ", "_")
    local dockConfig = NewDocks:GetDockIntance(dockName)
    
    -- Register with Layout
    Layout:RegisterElement(wrapperId, {
        name = dockConfig and dockConfig.name or dockName,
        category = Layout.CATEGORIES and Layout.CATEGORIES.COOLDOWNS or "Cooldowns",
        tuiFrame = wrapper,
        defaultPosition = wrapper.defaultPosition,
    })
    
    return true
end

function NewDocks:UnregisterDockFromLayout(dockName)
    local Layout = TUICD.Layout
    if not Layout or not Layout.UnregisterElement then return end
    
    local wrapperId = "Dock_" .. dockName:gsub(" ", "_")
    Layout:UnregisterElement(wrapperId)
    
    dockLayoutWrappers[dockName] = nil
end

-- Register all docks with Layout Mode
function NewDocks:RegisterAllDocksWithLayout()
    local db = NewDocks:GetDataBase_V2()
    if not db or not db.docks then return end
    
    for dockName, _ in pairs(db.docks) do
        self:RegisterDockWithLayout(dockName)
    end
end

-- Create or get a dock frame
function NewDocks:GetOrCreateDockFrame(dockName)
    if dockFrames[dockName] then
        return dockFrames[dockName]
    end
    return CreateDockFrame(dockName)
end

-- ============================================================================
-- EVENT HANDLER
-- ============================================================================





local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        NewDocks:RegisterAllDocksWithLayout()
    end
end)
