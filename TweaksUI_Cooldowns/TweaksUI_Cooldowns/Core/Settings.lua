-- ============================================================================
-- TweaksUI: Cooldowns - Settings
-- Main settings hub UI - simplified for cooldowns-only addon
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.Settings = {}
local Settings = TUICD.Settings

-- ============================================================
-- CONSTANTS
-- ============================================================
local HUB_WIDTH = 200
local HUB_HEIGHT = 320
local BUTTON_WIDTH = 170
local BUTTON_HEIGHT = 28
local BUTTON_SPACING = 6
local SECTION_SPACING = 16

local PANEL_WIDTH = 420
local PANEL_HEIGHT = 600

-- ============================================================
-- DARK BACKDROP TEMPLATE
-- ============================================================
local darkBackdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
}

-- Panel references
local hubPanel = nil
local allPanels = {}
local moduleSettingsPanels = {}

-- Static popup for reload prompt
StaticPopupDialogs["TUICD_RELOAD_PROMPT"] = {
    text = "Settings changed. Reload UI to apply?",
    button1 = "Reload Now",
    button2 = "Later",
    OnAccept = function()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ============================================================
-- HELPER: Create a dockable panel
-- ============================================================
local function CreateDockedPanel(name, width, height, headerText)
    local p = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    p:SetSize(width, height)
    p:SetBackdrop(darkBackdrop)
    p:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    p:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    p:SetFrameStrata("HIGH")
    p:Hide()
    
    local header = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOP", 0, -12)
    header:SetText(headerText)
    header:SetTextColor(1, 0.82, 0)  -- Gold color
    p.header = header
    
    local closeBtn = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() p:Hide() end)
    
    table.insert(allPanels, p)
    return p
end

-- ============================================================
-- HELPER: Position panel next to hub
-- ============================================================
local function PositionPanelNextToHub(targetPanel)
    if not hubPanel then return end
    targetPanel:ClearAllPoints()
    targetPanel:SetPoint("TOPLEFT", hubPanel, "TOPRIGHT", 0, 0)
end

-- ============================================================
-- HELPER: Hide all docked panels
-- ============================================================
local function HideAllPanels()
    for _, p in ipairs(allPanels) do
        p:Hide()
    end
end

-- ============================================================
-- HELPER: Open a panel (hide others, dock to hub)
-- ============================================================
local function OpenPanel(targetPanel)
    HideAllPanels()
    PositionPanelNextToHub(targetPanel)
    targetPanel:Show()
end

-- ============================================================
-- CREATE THE HUB PANEL
-- ============================================================
function Settings:CreatePanel()
    if hubPanel then return hubPanel end
    
    -- Main hub panel
    hubPanel = CreateFrame("Frame", "TUICD_HubPanel", UIParent, "BackdropTemplate")
    hubPanel:SetSize(HUB_WIDTH, HUB_HEIGHT)
    hubPanel:SetPoint("CENTER", -200, 0)
    hubPanel:SetBackdrop(darkBackdrop)
    hubPanel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    hubPanel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    hubPanel:SetFrameStrata("HIGH")
    hubPanel:SetMovable(true)
    hubPanel:EnableMouse(true)
    hubPanel:RegisterForDrag("LeftButton")
    hubPanel:SetScript("OnDragStart", hubPanel.StartMoving)
    hubPanel:SetScript("OnDragStop", hubPanel.StopMovingOrSizing)
    hubPanel:SetClampedToScreen(true)
    hubPanel:Hide()
    
    -- Register for ESC closing
    tinsert(UISpecialFrames, "TUICD_HubPanel")
    
    -- Title (cyan for TUI:CD branding)
    local title = hubPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cff00ccffTUI: Cooldowns|r")
    
    -- Version
    local version = hubPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    version:SetPoint("TOP", title, "BOTTOM", 0, -2)
    version:SetText("|cff00ff00v" .. TUICD.VERSION .. "|r")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, hubPanel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() 
        HideAllPanels()
        hubPanel:Hide() 
    end)
    
    local yOffset = -50
    
    -- ============================================================
    -- MODULES SECTION
    -- ============================================================
    local modulesLabel = hubPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    modulesLabel:SetPoint("TOPLEFT", 15, yOffset)
    modulesLabel:SetText("|cffaaaaaa— Modules —|r")
    yOffset = yOffset - 22
    
    -- Cooldowns Button
    local cooldownsBtn = CreateFrame("Button", nil, hubPanel, "UIPanelButtonTemplate")
    cooldownsBtn:SetPoint("TOPLEFT", 15, yOffset)
    cooldownsBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    cooldownsBtn:SetText("Cooldowns")
    cooldownsBtn:SetScript("OnClick", function()
        self:OpenCooldownsPanel()
    end)
    yOffset = yOffset - BUTTON_HEIGHT - BUTTON_SPACING
    
    -- Layout Button
    local layoutBtn = CreateFrame("Button", nil, hubPanel, "UIPanelButtonTemplate")
    layoutBtn:SetPoint("TOPLEFT", 15, yOffset)
    layoutBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    layoutBtn:SetText("Layout Mode")
    layoutBtn:SetScript("OnClick", function()
        if TUICD.Layout then
            TUICD.Layout:Toggle()
        end
    end)
    yOffset = yOffset - BUTTON_HEIGHT - SECTION_SPACING
    
    -- ============================================================
    -- SETTINGS SECTION
    -- ============================================================
    local settingsLabel = hubPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    settingsLabel:SetPoint("TOPLEFT", 15, yOffset)
    settingsLabel:SetText("|cffaaaaaa— Settings —|r")
    yOffset = yOffset - 22
    
    -- Profiles Button
    local profilesBtn = CreateFrame("Button", nil, hubPanel, "UIPanelButtonTemplate")
    profilesBtn:SetPoint("TOPLEFT", 15, yOffset)
    profilesBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    profilesBtn:SetText("Profiles")
    profilesBtn:SetScript("OnClick", function()
        self:OpenProfilesPanel()
    end)
    yOffset = yOffset - BUTTON_HEIGHT - BUTTON_SPACING
    
    -- About Button
    local aboutBtn = CreateFrame("Button", nil, hubPanel, "UIPanelButtonTemplate")
    aboutBtn:SetPoint("TOPLEFT", 15, yOffset)
    aboutBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    aboutBtn:SetText("About")
    aboutBtn:SetScript("OnClick", function()
        self:OpenAboutPanel()
    end)
    yOffset = yOffset - BUTTON_HEIGHT - SECTION_SPACING
    
    -- ============================================================
    -- QUICK ACTIONS SECTION
    -- ============================================================
    local actionsLabel = hubPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    actionsLabel:SetPoint("TOPLEFT", 15, yOffset)
    actionsLabel:SetText("|cffaaaaaa— Quick Actions —|r")
    yOffset = yOffset - 22
    
    -- Open Blizzard CDM button
    local cdmBtn = CreateFrame("Button", nil, hubPanel, "UIPanelButtonTemplate")
    cdmBtn:SetPoint("TOPLEFT", 15, yOffset)
    cdmBtn:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
    cdmBtn:SetText("Blizzard CDM")
    cdmBtn:SetScript("OnClick", function()
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
    end)
    cdmBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Blizzard Cooldown Manager", 1, 0.82, 0)
        GameTooltip:AddLine("Opens Blizzard's Cooldown Settings", 1, 1, 1)
        GameTooltip:AddLine("to enable/disable trackers.", 1, 1, 1)
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("Also accessible via |cff00ff00/cdm|r", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    cdmBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Close panels when hub is hidden
    hubPanel:SetScript("OnHide", function()
        HideAllPanels()
        -- Exit layout mode if it's active
        if TUICD.Layout and TUICD.Layout:IsActive() then
            TUICD.Layout:Exit()
        end
    end)
    
    return hubPanel
end

-- ============================================================
-- OPEN COOLDOWNS PANEL
-- ============================================================
function Settings:OpenCooldownsPanel()
    -- Use the Cooldowns module's built-in settings panel
    if TUICD.Cooldowns and TUICD.Cooldowns.ToggleSettingsPanel then
        TUICD.Cooldowns:ToggleSettingsPanel(hubPanel)
    else
        TUICD:PrintError("Cooldowns module not available")
    end
end

-- ============================================================
-- OPEN PROFILES PANEL
-- ============================================================
function Settings:OpenProfilesPanel()
    if TUICD.ProfilesUI then
        TUICD.ProfilesUI:ShowProfilesPanel(hubPanel)
    else
        TUICD:PrintError("ProfilesUI not available")
    end
end

-- ============================================================
-- CREATE ABOUT PANEL
-- ============================================================
function Settings:OpenAboutPanel()
    if not moduleSettingsPanels.about then
        local panel = CreateDockedPanel("TUICD_AboutPanel", PANEL_WIDTH, 450, "About TUI: Cooldowns")
        
        -- Create scroll frame for content
        local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 15, -40)
        scrollFrame:SetPoint("BOTTOMRIGHT", -35, 15)
        
        local content = CreateFrame("Frame", nil, scrollFrame)
        content:SetSize(PANEL_WIDTH - 60, 450)
        scrollFrame:SetScrollChild(content)
        
        local yPos = 0
        
        -- Header info
        local header = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        header:SetPoint("TOPLEFT", 0, yPos)
        header:SetText("|cff00ccffTweaksUI: Cooldowns|r v" .. TUICD.VERSION)
        yPos = yPos - 25
        
        local desc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", 0, yPos)
        desc:SetWidth(PANEL_WIDTH - 60)
        desc:SetJustifyH("LEFT")
        desc:SetText("A standalone cooldown tracking addon for World of Warcraft: Midnight.")
        yPos = yPos - 25
        
        local author = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        author:SetPoint("TOPLEFT", 0, yPos)
        author:SetText("|cffffffffAuthor:|r Meltheran")
        author:SetTextColor(0.7, 0.7, 0.7)
        yPos = yPos - 20
        
        local website = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        website:SetPoint("TOPLEFT", 0, yPos)
        website:SetText("|cffffffffCurseForge:|r curseforge.com/wow/addons/tweaksui-cooldowns")
        website:SetTextColor(0.7, 0.7, 0.7)
        yPos = yPos - 35
        
        -- Part of TweaksUI Section
        local partOfTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        partOfTitle:SetPoint("TOPLEFT", 0, yPos)
        partOfTitle:SetText("|cff00ff80Part of TweaksUI|r")
        yPos = yPos - 22
        
        local partOfText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        partOfText:SetPoint("TOPLEFT", 0, yPos)
        partOfText:SetWidth(PANEL_WIDTH - 60)
        partOfText:SetJustifyH("LEFT")
        partOfText:SetSpacing(2)
        partOfText:SetText("TUI: Cooldowns is the standalone version of the Cooldowns module from the full TweaksUI suite. If you want additional features like Unit Frames, Nameplates, Cast Bars, and more, check out the full TweaksUI addon!")
        partOfText:SetTextColor(0.8, 0.8, 0.8)
        yPos = yPos - partOfText:GetStringHeight() - 20
        
        -- Discord Section
        local discordTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        discordTitle:SetPoint("TOPLEFT", 0, yPos)
        discordTitle:SetText("|cff5865F2Join the Community!|r")
        yPos = yPos - 22
        
        local discordLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        discordLabel:SetPoint("TOPLEFT", 0, yPos)
        discordLabel:SetText("|cff5865F2Discord:|r")
        
        -- Copyable Discord link EditBox
        local discordEditBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
        discordEditBox:SetPoint("TOPLEFT", 55, yPos + 3)
        discordEditBox:SetSize(220, 20)
        discordEditBox:SetAutoFocus(false)
        discordEditBox:SetText("https://discord.gg/mYuggs3zwT")
        discordEditBox:SetCursorPosition(0)
        discordEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        discordEditBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        discordEditBox:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
        discordEditBox:SetScript("OnTextChanged", function(self)
            self:SetText("https://discord.gg/mYuggs3zwT")
        end)
        yPos = yPos - 24
        
        local copyHint = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        copyHint:SetPoint("TOPLEFT", 0, yPos)
        copyHint:SetText("|cff888888(Click to select, Ctrl+C to copy)|r")
        
        moduleSettingsPanels.about = panel
    end
    
    OpenPanel(moduleSettingsPanels.about)
end

-- ============================================================
-- PUBLIC: Get Hub Panel Reference
-- ============================================================
function Settings:GetHubPanel()
    return hubPanel
end

-- ============================================================
-- TOGGLE / SHOW / HIDE
-- ============================================================
function Settings:Toggle()
    if not hubPanel then
        self:CreatePanel()
    end
    
    if hubPanel:IsShown() then
        HideAllPanels()
        hubPanel:Hide()
    else
        hubPanel:Show()
    end
end

function Settings:Show()
    if not hubPanel then
        self:CreatePanel()
    end
    hubPanel:Show()
end

function Settings:Hide()
    if hubPanel then
        HideAllPanels()
        hubPanel:Hide()
    end
end
