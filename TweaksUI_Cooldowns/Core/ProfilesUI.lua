-- ============================================================================
-- TweaksUI: Cooldowns - Profiles UI
-- Profile management panels: profiles list, export, import
-- ============================================================================

local ADDON_NAME, TUICD = ...

TUICD.ProfilesUI = {}
local ProfilesUI = TUICD.ProfilesUI

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local PANEL_WIDTH = 450
local PANEL_HEIGHT = 620
local BUTTON_HEIGHT = 26
local LIST_ROW_HEIGHT = 28
local PADDING = 15

-- Colors
local COLORS = {
    gold = { 1, 0.82, 0 },
    green = { 0.3, 0.8, 0.3 },
    red = { 0.8, 0.3, 0.3 },
    orange = { 0.9, 0.7, 0.2 },
    blue = { 0.3, 0.6, 0.9 },
    white = { 1, 1, 1 },
    gray = { 0.6, 0.6, 0.6 },
    dimGray = { 0.4, 0.4, 0.4 },
}

local darkBackdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
}

-- ============================================================================
-- LOCAL STATE
-- ============================================================================

local profilesPanel = nil
local exportPanel = nil
local importPanel = nil

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function CreateSeparator(parent, yOffset)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", PADDING, yOffset)
    sep:SetPoint("TOPRIGHT", -PADDING, yOffset)
    sep:SetHeight(1)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    return sep
end

local function CreateSectionHeader(parent, text, yOffset)
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", PADDING, yOffset)
    header:SetText(text)
    header:SetTextColor(unpack(COLORS.gold))
    return header
end

local function CreateButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 100, height or BUTTON_HEIGHT)
    btn:SetText(text)
    return btn
end

local function CreateCheckbox(parent, text, initialValue, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.text:SetText(text)
    cb:SetChecked(initialValue)
    if onChange then
        cb:SetScript("OnClick", function(self)
            onChange(self:GetChecked())
        end)
    end
    return cb
end

-- ============================================================================
-- STATIC POPUPS
-- ============================================================================

StaticPopupDialogs["TUICD_SAVE_PROFILE"] = {
    text = "Enter a name for this profile:",
    button1 = "Save",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 50,
    OnAccept = function(self)
        local text = self.EditBox:GetText()
        if text and text ~= "" then
            local success, err = TUICD.Profiles:SaveProfile(text)
            if success then
                ProfilesUI:RefreshProfilesList()
            else
                TUICD:PrintError(err or "Failed to save profile")
            end
        end
    end,
    OnShow = function(self)
        self.EditBox:SetText(UnitName("player") .. " - ")
        self.EditBox:HighlightText()
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local text = self:GetText()
        if text and text ~= "" then
            local success, err = TUICD.Profiles:SaveProfile(text)
            if success then
                ProfilesUI:RefreshProfilesList()
            else
                TUICD:PrintError(err or "Failed to save profile")
            end
        end
        parent:Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["TUICD_DELETE_PROFILE"] = {
    text = "Delete profile \"%s\"?\n\nThis cannot be undone.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        local success, err = TUICD.Profiles:DeleteProfile(data)
        if success then
            ProfilesUI:RefreshProfilesList()
        else
            TUICD:PrintError(err or "Failed to delete profile")
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["TUICD_DUPLICATE_PROFILE"] = {
    text = "Enter name for the copy:",
    button1 = "Duplicate",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 50,
    OnAccept = function(self, data)
        local text = self.EditBox:GetText()
        if text and text ~= "" then
            local success, err = TUICD.Profiles:DuplicateProfile(data, text)
            if success then
                ProfilesUI:RefreshProfilesList()
            else
                TUICD:PrintError(err or "Failed to duplicate profile")
            end
        end
    end,
    OnShow = function(self, data)
        self.EditBox:SetText(data .. " (Copy)")
        self.EditBox:HighlightText()
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local text = self:GetText()
        if text and text ~= "" then
            local success, err = TUICD.Profiles:DuplicateProfile(parent.data, text)
            if success then
                ProfilesUI:RefreshProfilesList()
            else
                TUICD:PrintError(err or "Failed to duplicate profile")
            end
        end
        parent:Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["TUICD_LOAD_PROFILE_DIRTY"] = {
    text = "You have unsaved changes.\n\nWhat would you like to do?",
    button1 = "Save & Load",
    button2 = "Discard & Load",
    button3 = "Cancel",
    OnAccept = function(self, data)
        -- Save current to existing profile, then load
        local currentProfile = TUICD.Profiles:GetLoadedProfileName()
        if currentProfile then
            TUICD.Profiles:SaveProfile(currentProfile)
        end
        local success, result = TUICD.Profiles:LoadProfile(data.profileName, true)
        if success then
            ProfilesUI:RefreshProfilesList()
            if result == "NEEDS_RELOAD" then
                StaticPopup_Show("TUICD_RELOAD_AFTER_PROFILE")
            end
        end
    end,
    OnCancel = function(self, data)
        -- Discard and load
        local success, result = TUICD.Profiles:LoadProfile(data.profileName, true)
        if success then
            ProfilesUI:RefreshProfilesList()
            if result == "NEEDS_RELOAD" then
                StaticPopup_Show("TUICD_RELOAD_AFTER_PROFILE")
            end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["TUICD_RELOAD_AFTER_PROFILE"] = {
    text = "Profile loaded. Reload UI to apply changes?\n\n|cff888888Some settings require a reload to take effect.|r",
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

StaticPopupDialogs["TUICD_IMPORT_SUCCESS"] = {
    text = "Profile \"%s\" imported successfully!\n\nWould you like to load it now?",
    button1 = "Load Now",
    button2 = "Later",
    OnAccept = function(self, data)
        local success, result = TUICD.Profiles:LoadProfile(data, true)
        if success then
            ProfilesUI:RefreshProfilesList()
            if result == "NEEDS_RELOAD" then
                StaticPopup_Show("TUICD_RELOAD_AFTER_PROFILE")
            end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ============================================================================
-- PROFILES PANEL
-- ============================================================================

local function CreateProfileRow(parent, profileData, yOffset, isLoaded)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", 0, yOffset)
    row:SetPoint("TOPRIGHT", 0, yOffset)
    row:SetHeight(LIST_ROW_HEIGHT)
    
    -- Background
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if isLoaded then
        bg:SetColorTexture(0.2, 0.4, 0.2, 0.3)
    else
        bg:SetColorTexture(0.15, 0.15, 0.15, 0.3)
    end
    
    -- Loaded indicator
    if isLoaded then
        local indicator = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        indicator:SetPoint("LEFT", 5, 0)
        indicator:SetText(">")
        indicator:SetTextColor(unpack(COLORS.gold))
    end
    
    -- Profile name
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", isLoaded and 22 or 8, 0)
    nameText:SetText(profileData.name)
    nameText:SetTextColor(unpack(COLORS.white))
    
    -- Buttons on right
    local btnWidth = 50
    local btnSpacing = 4
    
    -- Delete button
    local deleteBtn = CreateButton(row, "Del", btnWidth, 22)
    deleteBtn:SetPoint("RIGHT", -5, 0)
    deleteBtn:SetScript("OnClick", function()
        local dialog = StaticPopup_Show("TUICD_DELETE_PROFILE", profileData.name)
        if dialog then
            dialog.data = profileData.name
        end
    end)
    -- Can't delete loaded profile
    if isLoaded then
        deleteBtn:Disable()
        deleteBtn:SetAlpha(0.5)
    end
    
    -- Duplicate button
    local dupeBtn = CreateButton(row, "Copy", btnWidth, 22)
    dupeBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -btnSpacing, 0)
    dupeBtn:SetScript("OnClick", function()
        local dialog = StaticPopup_Show("TUICD_DUPLICATE_PROFILE", profileData.name)
        if dialog then
            dialog.data = profileData.name
        end
    end)
    
    -- Update button (only for loaded profile)
    if isLoaded then
        local updateBtn = CreateButton(row, "Update", btnWidth + 10, 22)
        updateBtn:SetPoint("RIGHT", dupeBtn, "LEFT", -btnSpacing, 0)
        updateBtn:SetScript("OnClick", function()
            TUICD.Profiles:SaveProfile(profileData.name)
            ProfilesUI:RefreshProfilesList()
        end)
    else
        -- Load button
        local loadBtn = CreateButton(row, "Load", btnWidth, 22)
        loadBtn:SetPoint("RIGHT", dupeBtn, "LEFT", -btnSpacing, 0)
        loadBtn:SetScript("OnClick", function()
            -- Check dirty state
            if TUICD.Profiles:IsDirty() then
                local dialog = StaticPopup_Show("TUICD_LOAD_PROFILE_DIRTY")
                if dialog then
                    dialog.data = { profileName = profileData.name }
                end
            else
                local success, result = TUICD.Profiles:LoadProfile(profileData.name, true)
                if success then
                    ProfilesUI:RefreshProfilesList()
                    if result == "NEEDS_RELOAD" then
                        StaticPopup_Show("TUICD_RELOAD_AFTER_PROFILE")
                    end
                else
                    TUICD:PrintError(result or "Failed to load profile")
                end
            end
        end)
    end
    
    return row
end

function ProfilesUI:CreateProfilesPanel()
    if profilesPanel then return profilesPanel end
    
    local panel = CreateFrame("Frame", "TUICD_ProfilesPanel", UIParent, "BackdropTemplate")
    panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    panel:SetBackdrop(darkBackdrop)
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(100)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetClampedToScreen(true)
    panel:Hide()
    
    -- Register ESC to close
    tinsert(UISpecialFrames, "TUICD_ProfilesPanel")
    
    -- Header
    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOP", 0, -12)
    header:SetText("Profiles")
    header:SetTextColor(unpack(COLORS.gold))
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() panel:Hide() end)
    
    local yOffset = -40
    
    -- Current Settings Section
    local currentHeader = CreateSectionHeader(panel, "Current Settings", yOffset)
    yOffset = yOffset - 22
    
    -- Dirty indicator
    panel.dirtyIndicator = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.dirtyIndicator:SetPoint("TOPLEFT", PADDING, yOffset)
    panel.dirtyIndicator:SetText("")
    yOffset = yOffset - 18
    
    -- Based on text
    panel.basedOnText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.basedOnText:SetPoint("TOPLEFT", PADDING, yOffset)
    panel.basedOnText:SetTextColor(unpack(COLORS.gray))
    yOffset = yOffset - 25
    
    CreateSeparator(panel, yOffset)
    yOffset = yOffset - 15
    
    -- Saved Profiles Section
    CreateSectionHeader(panel, "Saved Profiles", yOffset)
    yOffset = yOffset - 25
    
    -- Scroll frame for profile list
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", PADDING, yOffset)
    scrollFrame:SetPoint("TOPRIGHT", -PADDING - 25, yOffset)
    scrollFrame:SetHeight(150)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(PANEL_WIDTH - 60, 400)
    scrollFrame:SetScrollChild(scrollChild)
    panel.profileListContent = scrollChild
    
    yOffset = yOffset - 160
    
    -- Save New Profile button
    local saveNewBtn = CreateButton(panel, "Save Current as New Profile...", 200, BUTTON_HEIGHT)
    saveNewBtn:SetPoint("TOPLEFT", PADDING, yOffset)
    saveNewBtn:SetScript("OnClick", function()
        StaticPopup_Show("TUICD_SAVE_PROFILE")
    end)
    
    yOffset = yOffset - 40
    CreateSeparator(panel, yOffset)
    yOffset = yOffset - 15
    
    -- Spec Auto-Switch Section
    CreateSectionHeader(panel, "Spec Auto-Switch", yOffset)
    yOffset = yOffset - 25
    
    -- Enable checkbox
    panel.specAutoSwitchCB = CreateCheckbox(panel, "Enable automatic profile switching on spec change", 
        TUICD.Profiles:IsSpecAutoSwitchEnabled(),
        function(checked)
            TUICD.Profiles:SetSpecAutoSwitchEnabled(checked)
            ProfilesUI:UpdateSpecDropdowns()
        end)
    panel.specAutoSwitchCB:SetPoint("TOPLEFT", PADDING, yOffset)
    yOffset = yOffset - 30
    
    -- Spec dropdowns container
    panel.specDropdownContainer = CreateFrame("Frame", nil, panel)
    panel.specDropdownContainer:SetPoint("TOPLEFT", PADDING, yOffset)
    panel.specDropdownContainer:SetSize(PANEL_WIDTH - PADDING * 2, 100)
    panel.specDropdowns = {}
    
    yOffset = yOffset - 110
    CreateSeparator(panel, yOffset)
    yOffset = yOffset - 15
    
    -- Import/Export Section
    CreateSectionHeader(panel, "Import / Export", yOffset)
    yOffset = yOffset - 30
    
    -- Export button
    local exportBtn = CreateButton(panel, "Export Current Settings", 160, BUTTON_HEIGHT)
    exportBtn:SetPoint("TOPLEFT", PADDING, yOffset)
    exportBtn:SetScript("OnClick", function()
        ProfilesUI:ShowExportPanel()
    end)
    
    -- Import button
    local importBtn = CreateButton(panel, "Import Profile", 120, BUTTON_HEIGHT)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 10, 0)
    importBtn:SetScript("OnClick", function()
        ProfilesUI:ShowImportPanel()
    end)
    
    profilesPanel = panel
    
    -- Register with GlobalScale for settings scaling
    if TUICD.GlobalScale then
        TUICD.GlobalScale:RegisterSettingsPanel(panel, 1.0)
    end
    
    return panel
end

function ProfilesUI:RefreshProfilesList()
    if not profilesPanel then return end
    
    local content = profilesPanel.profileListContent
    
    -- Clear existing rows
    for _, child in pairs({content:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    -- Update dirty state
    local dirtyState = TUICD.Profiles:GetDirtyState()
    if dirtyState.isDirty then
        profilesPanel.dirtyIndicator:SetText("|cffffcc00Unsaved changes|r")
    else
        profilesPanel.dirtyIndicator:SetText("|cff00ff00Settings saved|r")
    end
    
    -- Update based on text
    local loadedName = TUICD.Profiles:GetLoadedProfileName()
    if loadedName then
        profilesPanel.basedOnText:SetText("Based on: |cffffffff" .. loadedName .. "|r")
    else
        profilesPanel.basedOnText:SetText("|cff888888No profile loaded|r")
    end
    
    -- Get profiles and create rows
    local profiles = TUICD.Profiles:GetProfileList()
    local yOffset = 0
    
    if #profiles == 0 then
        local noProfiles = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noProfiles:SetPoint("TOP", 0, -10)
        noProfiles:SetText("|cff888888No saved profiles yet|r")
    else
        for _, profileData in ipairs(profiles) do
            local isLoaded = (profileData.name == loadedName)
            local row = CreateProfileRow(content, profileData, yOffset, isLoaded)
            yOffset = yOffset - LIST_ROW_HEIGHT - 2
        end
    end
    
    content:SetHeight(math.max(math.abs(yOffset) + 20, 100))
end

function ProfilesUI:UpdateSpecDropdowns()
    if not profilesPanel then return end
    
    local container = profilesPanel.specDropdownContainer
    local enabled = TUICD.Profiles:IsSpecAutoSwitchEnabled()
    
    -- Clear existing dropdowns
    for _, dropdown in pairs(profilesPanel.specDropdowns) do
        dropdown:Hide()
        dropdown:SetParent(nil)
    end
    profilesPanel.specDropdowns = {}
    
    -- Don't show dropdowns if disabled
    if not enabled then
        container:SetAlpha(0.5)
        return
    end
    
    container:SetAlpha(1.0)
    
    -- Get number of specs
    local numSpecs = GetNumSpecializations()
    if not numSpecs or numSpecs == 0 then return end
    
    local profiles = TUICD.Profiles:GetProfileList()
    local yOffset = 0
    
    for i = 1, numSpecs do
        local _, specName = GetSpecializationInfo(i)
        if specName then
            -- Create label
            local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOPLEFT", 0, yOffset)
            label:SetText(specName .. ":")
            
            -- Create dropdown
            local dropdown = CreateFrame("Frame", "TUICD_SpecDropdown" .. i, container, "UIDropDownMenuTemplate")
            dropdown:SetPoint("TOPLEFT", 80, yOffset + 5)
            UIDropDownMenu_SetWidth(dropdown, 180)
            
            local currentProfile = TUICD.Profiles:GetSpecProfile(i)
            UIDropDownMenu_SetText(dropdown, currentProfile or "None")
            
            UIDropDownMenu_Initialize(dropdown, function(self, level)
                local info = UIDropDownMenu_CreateInfo()
                
                -- "None" option
                info.text = "None"
                info.value = nil
                info.checked = (currentProfile == nil)
                info.func = function()
                    TUICD.Profiles:SetSpecProfile(i, nil)
                    UIDropDownMenu_SetText(dropdown, "None")
                end
                UIDropDownMenu_AddButton(info, level)
                
                -- Profile options
                for _, profileData in ipairs(profiles) do
                    info.text = profileData.name
                    info.value = profileData.name
                    info.checked = (currentProfile == profileData.name)
                    info.func = function()
                        TUICD.Profiles:SetSpecProfile(i, profileData.name)
                        UIDropDownMenu_SetText(dropdown, profileData.name)
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end)
            
            profilesPanel.specDropdowns[i] = dropdown
            yOffset = yOffset - 25
        end
    end
end

-- ============================================================================
-- EXPORT PANEL
-- ============================================================================

function ProfilesUI:CreateExportPanel()
    if exportPanel then return exportPanel end
    
    local panel = CreateFrame("Frame", "TUICD_ExportPanel", UIParent, "BackdropTemplate")
    panel:SetSize(450, 350)
    panel:SetBackdrop(darkBackdrop)
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetPoint("CENTER")
    panel:Hide()
    
    tinsert(UISpecialFrames, "TUICD_ExportPanel")
    
    -- Header
    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOP", 0, -12)
    header:SetText("Export Profile")
    header:SetTextColor(unpack(COLORS.gold))
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    
    -- Instructions
    local instructions = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions:SetPoint("TOP", 0, -40)
    instructions:SetWidth(400)
    instructions:SetText("Copy this string to share your current tracker settings:")
    
    -- Edit box container with background
    local editBg = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    editBg:SetPoint("TOPLEFT", PADDING, -70)
    editBg:SetPoint("BOTTOMRIGHT", -PADDING, 60)
    editBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    editBg:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    editBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    -- Scroll frame for export string
    local scrollFrame = CreateFrame("ScrollFrame", nil, editBg, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)
    
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(scrollFrame:GetWidth() - 10)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scrollFrame:SetScrollChild(editBox)
    
    -- Make the background clickable to focus the edit box
    editBg:EnableMouse(true)
    editBg:SetScript("OnMouseDown", function()
        editBox:SetFocus()
    end)
    
    panel.outputEditBox = editBox
    
    -- Generate button
    local generateBtn = CreateButton(panel, "Generate Export String", 160, BUTTON_HEIGHT)
    generateBtn:SetPoint("BOTTOMLEFT", PADDING, 15)
    generateBtn:SetScript("OnClick", function()
        local exportString, err = TUICD.Profiles:ExportProfile()
        if exportString then
            editBox:SetText(exportString)
            editBox:HighlightText()
            editBox:SetFocus()
        else
            TUICD:PrintError(err or "Failed to export profile")
        end
    end)
    
    -- Back button
    local backBtn = CreateButton(panel, "Back", 80, BUTTON_HEIGHT)
    backBtn:SetPoint("BOTTOMRIGHT", -PADDING, 15)
    backBtn:SetScript("OnClick", function()
        panel:Hide()
        ProfilesUI:ShowProfilesPanel()
    end)
    
    exportPanel = panel
    
    -- Register with GlobalScale for settings scaling
    if TUICD.GlobalScale then
        TUICD.GlobalScale:RegisterSettingsPanel(panel, 1.0)
    end
    
    return panel
end

-- ============================================================================
-- IMPORT PANEL
-- ============================================================================

function ProfilesUI:CreateImportPanel()
    if importPanel then return importPanel end
    
    local panel = CreateFrame("Frame", "TUICD_ImportPanel", UIParent, "BackdropTemplate")
    panel:SetSize(450, 400)
    panel:SetBackdrop(darkBackdrop)
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetPoint("CENTER")
    panel:Hide()
    
    tinsert(UISpecialFrames, "TUICD_ImportPanel")
    
    -- Header
    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOP", 0, -12)
    header:SetText("Import Profile")
    header:SetTextColor(unpack(COLORS.gold))
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    
    -- Instructions
    local instructions = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions:SetPoint("TOP", 0, -40)
    instructions:SetWidth(400)
    instructions:SetText("Paste an export string below:")
    
    -- Edit box container with background
    local editBg = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    editBg:SetPoint("TOPLEFT", PADDING, -65)
    editBg:SetPoint("TOPRIGHT", -PADDING, -65)
    editBg:SetHeight(150)
    editBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    editBg:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    editBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    -- Scroll frame for import string
    local scrollFrame = CreateFrame("ScrollFrame", nil, editBg, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -25, 5)
    
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(scrollFrame:GetWidth() - 10)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scrollFrame:SetScrollChild(editBox)
    
    -- Make the background clickable to focus the edit box
    editBg:EnableMouse(true)
    editBg:SetScript("OnMouseDown", function()
        editBox:SetFocus()
    end)
    
    panel.inputEditBox = editBox
    
    -- Validation results
    panel.validationResults = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.validationResults:SetPoint("TOPLEFT", PADDING, -225)
    panel.validationResults:SetWidth(400)
    panel.validationResults:SetJustifyH("LEFT")
    panel.validationResults:SetText("|cff888888Paste a string and click Validate|r")
    
    -- Profile name
    local nameLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", PADDING, -260)
    nameLabel:SetText("Profile Name:")
    
    local nameEditBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    nameEditBox:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0)
    nameEditBox:SetSize(200, 22)
    nameEditBox:SetAutoFocus(false)
    nameEditBox:SetText("Imported Profile")
    panel.profileNameEditBox = nameEditBox
    
    -- Validate button
    local validateBtn = CreateButton(panel, "Validate", 100, BUTTON_HEIGHT)
    validateBtn:SetPoint("BOTTOMLEFT", PADDING, 15)
    validateBtn:SetScript("OnClick", function()
        local importString = editBox:GetText()
        local profileData, err = TUICD.Profiles:ImportProfile(importString)
        
        if profileData then
            panel._validatedData = profileData
            panel.validationResults:SetText("|cff00ff00Valid profile!|r\nClick Import to save it.")
            panel.importBtn:Enable()
        else
            panel._validatedData = nil
            panel.validationResults:SetText("|cffff4444Error:|r " .. (err or "Unknown error"))
            panel.importBtn:Disable()
        end
    end)
    
    -- Import button
    local importBtn = CreateButton(panel, "Import", 100, BUTTON_HEIGHT)
    importBtn:SetPoint("LEFT", validateBtn, "RIGHT", 10, 0)
    importBtn:Disable()
    importBtn:SetScript("OnClick", function()
        if not panel._validatedData then
            TUICD:PrintError("Please validate the import string first")
            return
        end
        
        local profileName = nameEditBox:GetText()
        if not profileName or profileName == "" then
            TUICD:PrintError("Please enter a profile name")
            return
        end
        
        local success, err = TUICD.Profiles:SaveImportedProfile(panel._validatedData, profileName)
        if success then
            panel:Hide()
            ProfilesUI:RefreshProfilesList()
            local dialog = StaticPopup_Show("TUICD_IMPORT_SUCCESS", profileName)
            if dialog then
                dialog.data = profileName
            end
        else
            TUICD:PrintError(err or "Failed to import profile")
        end
    end)
    panel.importBtn = importBtn
    
    -- Back button
    local backBtn = CreateButton(panel, "Back", 80, BUTTON_HEIGHT)
    backBtn:SetPoint("BOTTOMRIGHT", -PADDING, 15)
    backBtn:SetScript("OnClick", function()
        panel:Hide()
        ProfilesUI:ShowProfilesPanel()
    end)
    
    importPanel = panel
    
    -- Register with GlobalScale for settings scaling
    if TUICD.GlobalScale then
        TUICD.GlobalScale:RegisterSettingsPanel(panel, 1.0)
    end
    
    return panel
end

-- ============================================================================
-- SHOW FUNCTIONS
-- ============================================================================

function ProfilesUI:ShowProfilesPanel()
    if not profilesPanel then
        self:CreateProfilesPanel()
    end
    
    -- Close other panels first (tracker panels, docks panel)
    for _, trackerKey in ipairs({"essential", "utility", "buffs", "customTrackers"}) do
        local trackerPanel = _G["TweaksUI_Cooldowns_" .. trackerKey .. "_Panel"]
        if trackerPanel and trackerPanel:IsShown() then
            trackerPanel:Hide()
        end
    end
    
    local docksPanel = _G["TUICD_DocksPanel"]
    if docksPanel and docksPanel:IsShown() then
        docksPanel:Hide()
    end
    
    -- Position to the right of the settings hub if it exists
    local hub = _G["TUICD_SettingsHub"]
    if hub and hub:IsShown() then
        profilesPanel:ClearAllPoints()
        profilesPanel:SetPoint("TOPLEFT", hub, "TOPRIGHT", 5, 0)
    else
        profilesPanel:ClearAllPoints()
        profilesPanel:SetPoint("CENTER")
    end
    
    -- Ensure it's on top
    profilesPanel:SetFrameStrata("DIALOG")
    profilesPanel:Raise()
    
    self:RefreshProfilesList()
    self:UpdateSpecDropdowns()
    profilesPanel:Show()
end

function ProfilesUI:ShowExportPanel()
    -- Close the profiles panel first
    if profilesPanel then
        profilesPanel:Hide()
    end
    
    if not exportPanel then
        self:CreateExportPanel()
    end
    exportPanel.outputEditBox:SetText("")
    exportPanel:Show()
end

function ProfilesUI:ShowImportPanel()
    -- Close the profiles panel first
    if profilesPanel then
        profilesPanel:Hide()
    end
    
    if not importPanel then
        self:CreateImportPanel()
    end
    importPanel.inputEditBox:SetText("")
    importPanel.validationResults:SetText("|cff888888Paste a string and click Validate|r")
    importPanel.profileNameEditBox:SetText("Imported Profile")
    importPanel.importBtn:Disable()
    importPanel._validatedData = nil
    importPanel:Show()
end

function ProfilesUI:HideAll()
    if profilesPanel then profilesPanel:Hide() end
    if exportPanel then exportPanel:Hide() end
    if importPanel then importPanel:Hide() end
end

function ProfilesUI:Toggle()
    if profilesPanel and profilesPanel:IsShown() then
        self:HideAll()
    else
        self:ShowProfilesPanel()
    end
end
