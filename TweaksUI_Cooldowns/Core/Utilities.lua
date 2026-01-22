-- ============================================================================
-- TweaksUI: Cooldowns - Utilities
-- Shared utility functions
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.Utilities = {}
local Utils = TUICD.Utilities

-- ============================================================================
-- ICON SIZE CALCULATIONS
-- ============================================================================

-- Parse aspect ratio string to get multipliers
function Utils:ParseAspectRatio(aspectStr)
    if not aspectStr or aspectStr == "1:1" then
        return 1, 1
    end
    
    local w, h = aspectStr:match("(%d+):(%d+)")
    if w and h then
        return tonumber(w), tonumber(h)
    end
    
    return 1, 1
end

-- Calculate icon dimensions from base size and aspect ratio
function Utils:CalculateIconDimensions(settings)
    local baseSize = settings.iconSize or 36
    
    -- Check for explicit width/height first
    if settings.iconWidth and settings.iconHeight then
        return settings.iconWidth, settings.iconHeight
    end
    
    -- Use aspect ratio
    local aspectRatio = settings.aspectRatio or "1:1"
    local aspectW, aspectH = self:ParseAspectRatio(aspectRatio)
    
    -- Base size is the larger dimension
    local maxAspect = math.max(aspectW, aspectH)
    local width = baseSize * (aspectW / maxAspect)
    local height = baseSize * (aspectH / maxAspect)
    
    return math.floor(width + 0.5), math.floor(height + 0.5)
end

-- ============================================================================
-- LAYOUT CALCULATIONS
-- ============================================================================

-- Parse custom layout string "4,4,2" into array {4, 4, 2}
function Utils:ParseCustomLayout(layoutStr)
    if not layoutStr or layoutStr == "" then
        return nil
    end
    
    local pattern = {}
    for num in layoutStr:gmatch("%d+") do
        table.insert(pattern, tonumber(num))
    end
    
    return #pattern > 0 and pattern or nil
end

-- Calculate grid positions for icons
function Utils:CalculateGridPositions(count, settings)
    local positions = {}
    
    local columns = settings.columns or 8
    local customLayout = self:ParseCustomLayout(settings.customLayout)
    local growDirection = settings.growDirection or "RIGHT"
    local growSecondary = settings.growSecondary or "DOWN"
    local alignment = settings.alignment or "LEFT"
    local spacingH = settings.spacingH or 2
    local spacingV = settings.spacingV or 2
    local iconWidth, iconHeight = self:CalculateIconDimensions(settings)
    
    -- Determine horizontal/vertical primary
    local horizontalPrimary = (growDirection == "LEFT" or growDirection == "RIGHT")
    
    -- Calculate positions
    local currentRow = 0
    local currentCol = 0
    local rowLimit = customLayout and customLayout[1] or columns
    local rowIndex = 1
    
    for i = 1, count do
        -- Calculate x/y based on grow direction
        local x, y
        
        if horizontalPrimary then
            x = currentCol * (iconWidth + spacingH)
            y = currentRow * (iconHeight + spacingV)
            
            if growDirection == "LEFT" then x = -x end
            if growSecondary == "UP" then y = -y else y = -y end
        else
            x = currentRow * (iconWidth + spacingH)
            y = currentCol * (iconHeight + spacingV)
            
            if growSecondary == "LEFT" then x = -x end
            if growDirection == "UP" then y = -y else y = -y end
        end
        
        positions[i] = { x = x, y = y }
        
        -- Advance position
        currentCol = currentCol + 1
        if currentCol >= rowLimit then
            currentCol = 0
            currentRow = currentRow + 1
            rowIndex = rowIndex + 1
            rowLimit = customLayout and (customLayout[rowIndex] or customLayout[#customLayout]) or columns
        end
    end
    
    -- Apply alignment offset if needed
    if alignment ~= "LEFT" and horizontalPrimary then
        -- Group by row and apply alignment
        local rows = {}
        local maxRowWidth = 0
        
        -- Group positions by row
        local rowNum = 0
        local colNum = 0
        local rowItems = {}
        rowLimit = customLayout and customLayout[1] or columns
        rowIndex = 1
        
        for i = 1, count do
            table.insert(rowItems, positions[i])
            colNum = colNum + 1
            
            if colNum >= rowLimit or i == count then
                local rowWidth = colNum * (iconWidth + spacingH) - spacingH
                maxRowWidth = math.max(maxRowWidth, rowWidth)
                
                rows[rowNum] = {
                    items = rowItems,
                    width = rowWidth,
                }
                
                rowItems = {}
                colNum = 0
                rowNum = rowNum + 1
                rowIndex = rowIndex + 1
                rowLimit = customLayout and (customLayout[rowIndex] or customLayout[#customLayout]) or columns
            end
        end
        
        -- Apply offsets based on alignment
        local posIndex = 1
        for r = 0, rowNum - 1 do
            local row = rows[r]
            if row then
                local offset = 0
                if alignment == "CENTER" then
                    offset = (maxRowWidth - row.width) / 2
                elseif alignment == "RIGHT" then
                    offset = maxRowWidth - row.width
                end
                
                for _, pos in ipairs(row.items) do
                    if growDirection == "LEFT" then
                        positions[posIndex].x = positions[posIndex].x - offset
                    else
                        positions[posIndex].x = positions[posIndex].x + offset
                    end
                    posIndex = posIndex + 1
                end
            end
        end
    end
    
    return positions
end

-- ============================================================================
-- VISIBILITY CHECKS
-- ============================================================================

function Utils:ShouldShowTracker(settings)
    if not settings.visibilityEnabled then
        return true  -- No visibility restrictions
    end
    
    local shouldShow = false
    
    -- Combat check
    local inCombat = InCombatLockdown()
    if inCombat and settings.showInCombat then
        shouldShow = true
    elseif not inCombat and settings.showOutOfCombat then
        shouldShow = true
    end
    
    if not shouldShow then
        return false, settings.fadeAlpha or 0.3
    end
    
    -- Group check
    local inRaid = IsInRaid()
    local inParty = IsInGroup() and not inRaid
    local solo = not IsInGroup()
    
    if solo and not settings.showSolo then
        return false, settings.fadeAlpha or 0.3
    end
    if inParty and not settings.showInParty then
        return false, settings.fadeAlpha or 0.3
    end
    if inRaid and not settings.showInRaid then
        return false, settings.fadeAlpha or 0.3
    end
    
    -- Target check
    local hasTarget = UnitExists("target")
    if hasTarget and not settings.showHasTarget then
        return false, settings.fadeAlpha or 0.3
    end
    if not hasTarget and not settings.showNoTarget then
        return false, settings.fadeAlpha or 0.3
    end
    
    -- Instance check
    local _, instanceType = IsInInstance()
    if instanceType == "arena" and not settings.showInArena then
        return false, settings.fadeAlpha or 0.3
    end
    if instanceType == "pvp" and not settings.showInBattleground then
        return false, settings.fadeAlpha or 0.3
    end
    if (instanceType == "party" or instanceType == "raid") and not settings.showInInstance then
        return false, settings.fadeAlpha or 0.3
    end
    
    return true, 1.0
end

-- ============================================================================
-- SPELL/ITEM HELPERS
-- ============================================================================

-- Get spell info safely (Midnight API)
function Utils:GetSpellInfo(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then
            return info.name, nil, info.iconID, nil, nil, nil, spellID
        end
    end
    return nil
end

-- Get spell texture safely (Midnight API)
function Utils:GetSpellTexture(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    return nil
end

-- Get spell cooldown safely (Midnight API with Duration Object support)
function Utils:GetSpellCooldown(spellID)
    if TUICD.HAS_SPELL_COOLDOWN_DURATION then
        -- Midnight API
        local cooldownInfo = C_Spell.GetSpellCooldown(spellID)
        if cooldownInfo then
            local duration
            if cooldownInfo.duration then
                -- Duration might be a Duration Object
                if type(cooldownInfo.duration) == "table" and cooldownInfo.duration.GetValue then
                    duration = cooldownInfo.duration:GetValue()
                else
                    duration = cooldownInfo.duration
                end
            else
                duration = 0
            end
            return cooldownInfo.startTime or 0, duration, cooldownInfo.isEnabled and 1 or 0
        end
    end
    return 0, 0, 0
end

-- Get item cooldown safely (Midnight API)
function Utils:GetItemCooldown(itemID)
    if C_Container and C_Container.GetItemCooldown then
        local startTime, duration, enable = C_Container.GetItemCooldown(itemID)
        return startTime or 0, duration or 0, enable or 0
    end
    return 0, 0, 0
end

-- ============================================================================
-- TABLE UTILITIES
-- ============================================================================

-- Check if table contains value
function Utils:TableContains(tbl, value)
    if not tbl then return false end
    for _, v in pairs(tbl) do
        if v == value then return true end
    end
    return false
end

-- Get table length (works for non-sequential tables too)
function Utils:TableCount(tbl)
    if not tbl then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Shallow copy
function Utils:ShallowCopy(tbl)
    if type(tbl) ~= "table" then return tbl end
    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = v
    end
    return copy
end

-- ============================================================================
-- UI HELPERS
-- ============================================================================

-- Create a slider with an editable input box
function Utils:CreateSliderWithInput(parent, options)
    local label = options.label or "Slider"
    local min = options.min or 0
    local max = options.max or 100
    local step = options.step or 1
    local value = options.value or min
    local isFloat = options.isFloat or false
    local decimals = options.decimals or 0
    local width = options.width or 140
    local labelWidth = options.labelWidth or 130
    local valueWidth = options.valueWidth or 45
    local onValueChanged = options.onValueChanged
    
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(labelWidth + width + valueWidth + 20, 26)
    
    -- Label
    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labelText:SetPoint("LEFT", 0, 0)
    labelText:SetWidth(labelWidth)
    labelText:SetJustifyH("LEFT")
    labelText:SetText(label)
    labelText:SetTextColor(0.8, 0.8, 0.8)
    
    -- Slider
    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("LEFT", labelText, "RIGHT", 10, 0)
    slider:SetWidth(width)
    slider:SetHeight(17)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(value)
    
    -- Hide default text
    slider.Low:SetText("")
    slider.High:SetText("")
    slider.Text:SetText("")
    
    -- Value edit box
    local editBox = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    editBox:SetPoint("LEFT", slider, "RIGHT", 10, 0)
    editBox:SetSize(valueWidth, 20)
    editBox:SetAutoFocus(false)
    editBox:SetJustifyH("CENTER")
    
    local function FormatValue(val)
        if isFloat then
            return string.format("%." .. decimals .. "f", val)
        else
            return string.format("%d", val)
        end
    end
    
    editBox:SetText(FormatValue(value))
    
    -- Slider changed
    slider:SetScript("OnValueChanged", function(self, val)
        editBox:SetText(FormatValue(val))
        if onValueChanged then
            onValueChanged(val)
        end
    end)
    
    -- Edit box changed
    editBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            val = math.max(min, math.min(max, val))
            slider:SetValue(val)
        end
        self:ClearFocus()
    end)
    
    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(FormatValue(slider:GetValue()))
        self:ClearFocus()
    end)
    
    container.slider = slider
    container.editBox = editBox
    container.label = labelText
    
    return container
end

-- ============================================================================
-- SERIALIZATION
-- ============================================================================

-- Serialize a table to a string (for export)
function Utils:TableToString(tbl)
    if type(tbl) ~= "table" then
        return nil
    end
    
    local function serialize(val, depth)
        depth = depth or 0
        if depth > 50 then return "nil" end
        
        local t = type(val)
        if t == "nil" then
            return "nil"
        elseif t == "boolean" then
            return val and "true" or "false"
        elseif t == "number" then
            return tostring(val)
        elseif t == "string" then
            return string.format("%q", val)
        elseif t == "table" then
            local parts = {}
            
            -- Handle array part
            local arrayPart = {}
            local maxIndex = 0
            for i, v in ipairs(val) do
                arrayPart[i] = serialize(v, depth + 1)
                maxIndex = i
            end
            
            -- Handle hash part
            for k, v in pairs(val) do
                if type(k) ~= "number" or k > maxIndex or k < 1 or math.floor(k) ~= k then
                    local keyStr
                    if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                        keyStr = k
                    else
                        keyStr = "[" .. serialize(k, depth + 1) .. "]"
                    end
                    table.insert(parts, keyStr .. "=" .. serialize(v, depth + 1))
                end
            end
            
            -- Combine array and hash parts
            local arrayStr = table.concat(arrayPart, ",")
            local hashStr = table.concat(parts, ",")
            
            if arrayStr ~= "" and hashStr ~= "" then
                return "{" .. arrayStr .. "," .. hashStr .. "}"
            elseif arrayStr ~= "" then
                return "{" .. arrayStr .. "}"
            else
                return "{" .. hashStr .. "}"
            end
        else
            return "nil"  -- Unsupported type
        end
    end
    
    return serialize(tbl)
end

-- Deserialize a string back to a table (for import)
function Utils:StringToTable(str)
    if type(str) ~= "string" then
        return nil
    end
    
    -- Safely load the string as a Lua chunk
    local func, err = loadstring("return " .. str)
    if not func then
        return nil, err
    end
    
    -- Execute in a sandboxed environment
    local env = {}
    setfenv(func, env)
    
    local success, result = pcall(func)
    if not success then
        return nil, result
    end
    
    return result
end
