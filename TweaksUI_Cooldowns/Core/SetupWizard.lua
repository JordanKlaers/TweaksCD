-- ============================================================================
-- TweaksUI: Cooldowns - Setup Wizard
-- First-time setup experience to guide users through required WoW settings
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.SetupWizard = {}
local SetupWizard = TUICD.SetupWizard

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local PANEL_WIDTH = 500
local PANEL_HEIGHT = 620
local BUTTON_HEIGHT = 32

-- ============================================================================
-- SETUP STATE
-- ============================================================================

local setupFrame = nil
local setupComplete = false

-- Check if setup has been completed
function SetupWizard:IsSetupComplete()
    if TweaksUI_Cooldowns_DB and TweaksUI_Cooldowns_DB.setupComplete then
        return true
    end
    return false
end

-- Mark setup as complete
function SetupWizard:MarkSetupComplete()
    if not TweaksUI_Cooldowns_DB then
        TweaksUI_Cooldowns_DB = {}
    end
    TweaksUI_Cooldowns_DB.setupComplete = true
    setupComplete = true
end

-- Reset setup (for testing or if user wants to see wizard again)
function SetupWizard:ResetSetup()
    if TweaksUI_Cooldowns_DB then
        TweaksUI_Cooldowns_DB.setupComplete = false
    end
    setupComplete = false
end

-- ============================================================================
-- SETUP WIZARD UI
-- ============================================================================

local function CreateSetupPanel()
    if setupFrame then return setupFrame end
    
    -- Main frame
    setupFrame = CreateFrame("Frame", "TUICD_SetupWizard", UIParent, "BackdropTemplate")
    setupFrame:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    setupFrame:SetPoint("CENTER", 0, 50)
    setupFrame:SetFrameStrata("DIALOG")
    setupFrame:SetFrameLevel(100)
    setupFrame:SetMovable(true)
    setupFrame:EnableMouse(true)
    setupFrame:RegisterForDrag("LeftButton")
    setupFrame:SetScript("OnDragStart", setupFrame.StartMoving)
    setupFrame:SetScript("OnDragStop", setupFrame.StopMovingOrSizing)
    setupFrame:SetClampedToScreen(true)
    
    -- Backdrop
    setupFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    setupFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.98)
    
    -- Title
    local title = setupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -20)
    title:SetText("|cff00ccffTweaksUI: Cooldowns|r")
    
    local subtitle = setupFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -5)
    subtitle:SetText("|cffffd100First-Time Setup|r")
    
    -- Welcome text
    local welcomeText = setupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    welcomeText:SetPoint("TOP", subtitle, "BOTTOM", 0, -20)
    welcomeText:SetWidth(PANEL_WIDTH - 50)
    welcomeText:SetJustifyH("CENTER")
    welcomeText:SetText("Welcome! Before TweaksUI: Cooldowns can work properly,\nyou need to configure a few WoW settings.")
    
    -- Instructions container
    local instructionsFrame = CreateFrame("Frame", nil, setupFrame, "BackdropTemplate")
    instructionsFrame:SetPoint("TOP", welcomeText, "BOTTOM", 0, -15)
    instructionsFrame:SetSize(PANEL_WIDTH - 40, 360)
    instructionsFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    instructionsFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    instructionsFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    local yOffset = -15
    
    -- Step 1: Enable Cooldown Manager
    local step1Title = instructionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    step1Title:SetPoint("TOPLEFT", 15, yOffset)
    step1Title:SetText("|cffffd100Step 1:|r Enable Cooldown Manager")
    
    local step1Text = instructionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    step1Text:SetPoint("TOPLEFT", step1Title, "BOTTOMLEFT", 10, -5)
    step1Text:SetWidth(PANEL_WIDTH - 80)
    step1Text:SetJustifyH("LEFT")
    step1Text:SetText("|cffffffffPress |cffffd100ESC|r > |cffffffffGame Menu|r > |cffffffffOptions|r > |cffffffffGameplay|r\nScroll down and |cff00ff00enable|r \"|cffffd100Cooldown Manager|r\"")
    
    yOffset = yOffset - 75
    
    -- Step 2: Edit Mode Settings
    local step2Title = instructionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    step2Title:SetPoint("TOPLEFT", 15, yOffset)
    step2Title:SetText("|cffffd100Step 2:|r Configure Edit Mode")
    
    local step2Text = instructionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    step2Text:SetPoint("TOPLEFT", step2Title, "BOTTOMLEFT", 10, -5)
    step2Text:SetWidth(PANEL_WIDTH - 80)
    step2Text:SetJustifyH("LEFT")
    step2Text:SetText("|cffffffffPress |cffffd100ESC|r > |cffffffffEdit Mode|r (or type |cffffd100/em|r)\n\nFor |cff00ccffEssential Cooldowns|r, |cff00ccffUtility Cooldowns|r, AND |cff00ccffBuff Tracker|r:\n  - Click each tracker to select it\n  - Set |cffffd100Scale|r to |cff00ff00100%|r\n  - Set |cffffd100Visibility|r to |cff00ff00Always Shown|r")
    
    yOffset = yOffset - 115
    
    -- Step 3: Buff Tracker Special
    local step3Title = instructionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    step3Title:SetPoint("TOPLEFT", 15, yOffset)
    step3Title:SetText("|cffffd100Step 3:|r Buff Tracker Setting")
    
    local step3Text = instructionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    step3Text:SetPoint("TOPLEFT", step3Title, "BOTTOMLEFT", 10, -5)
    step3Text:SetWidth(PANEL_WIDTH - 80)
    step3Text:SetJustifyH("LEFT")
    step3Text:SetText("|cffffffffWhile still in Edit Mode with the Buff Tracker selected:\n  - |cffff4444UNCHECK|r \"|cffffd100Hide When Inactive|r\"\n\nThis allows TweaksUI to show inactive buff slots.")
    
    yOffset = yOffset - 85
    
    -- Note
    local noteText = instructionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteText:SetPoint("TOPLEFT", 15, yOffset)
    noteText:SetWidth(PANEL_WIDTH - 80)
    noteText:SetJustifyH("LEFT")
    noteText:SetTextColor(0.6, 0.6, 0.6)
    noteText:SetText("|cff888888Tip: Type |cffffd100/cdm|r to open Blizzard's Cooldown Manager settings\nto configure which spells appear in each tracker.|r")
    
    -- Buttons
    local buttonContainer = CreateFrame("Frame", nil, setupFrame)
    buttonContainer:SetPoint("BOTTOM", 0, 25)
    buttonContainer:SetSize(PANEL_WIDTH - 40, 80)
    
    -- "I've Done This - Reload UI" button
    local reloadButton = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    reloadButton:SetSize(250, BUTTON_HEIGHT)
    reloadButton:SetPoint("TOP", 0, 0)
    reloadButton:SetText("I've Done This - Reload UI")
    reloadButton:SetScript("OnClick", function()
        SetupWizard:MarkSetupComplete()
        ReloadUI()
    end)
    
    -- Make reload button stand out
    reloadButton:SetNormalFontObject("GameFontNormalLarge")
    
    -- "Skip for Now" button
    local skipButton = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    skipButton:SetSize(120, 24)
    skipButton:SetPoint("TOP", reloadButton, "BOTTOM", 0, -8)
    skipButton:SetText("Skip for Now")
    skipButton:GetFontString():SetTextColor(0.7, 0.7, 0.7)
    skipButton:SetScript("OnClick", function()
        setupFrame:Hide()
        -- Continue loading without marking complete
        if TUICD.ContinueLoading then
            TUICD.ContinueLoading()
        end
    end)
    
    -- "Don't Show Again" checkbox
    local dontShowCheck = CreateFrame("CheckButton", nil, buttonContainer, "UICheckButtonTemplate")
    dontShowCheck:SetSize(24, 24)
    dontShowCheck:SetPoint("TOPLEFT", skipButton, "BOTTOMLEFT", -24, -5)
    dontShowCheck.text = dontShowCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dontShowCheck.text:SetPoint("LEFT", dontShowCheck, "RIGHT", 2, 0)
    dontShowCheck.text:SetText("|cff888888Don't show this again|r")
    dontShowCheck:SetScript("OnClick", function(self)
        if self:GetChecked() then
            SetupWizard:MarkSetupComplete()
        else
            SetupWizard:ResetSetup()
        end
    end)
    
    -- Close button (X)
    local closeButton = CreateFrame("Button", nil, setupFrame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function()
        setupFrame:Hide()
        if TUICD.ContinueLoading then
            TUICD.ContinueLoading()
        end
    end)
    
    return setupFrame
end

-- Show the setup wizard
function SetupWizard:Show()
    local frame = CreateSetupPanel()
    frame:Show()
end

-- Hide the setup wizard
function SetupWizard:Hide()
    if setupFrame then
        setupFrame:Hide()
    end
end

-- Check if wizard should be shown and handle accordingly
-- Returns true if wizard was shown (loading should be deferred)
-- Returns false if setup is complete (continue loading normally)
function SetupWizard:CheckAndShow()
    if self:IsSetupComplete() then
        return false
    end
    
    self:Show()
    return true
end

-- ============================================================================
-- SLASH COMMAND FOR TESTING
-- ============================================================================

SLASH_TUICDSETUP1 = "/tuicdsetup"
SlashCmdList["TUICDSETUP"] = function(msg)
    if msg == "reset" then
        SetupWizard:ResetSetup()
        print("|cff00ccff[TUI:CD]|r Setup wizard reset. Type /rl to see it again.")
    elseif msg == "show" then
        SetupWizard:Show()
    else
        print("|cff00ccff[TUI:CD]|r Setup wizard commands:")
        print("  /tuicdsetup show - Show the setup wizard")
        print("  /tuicdsetup reset - Reset setup (show wizard on next load)")
    end
end

return SetupWizard
