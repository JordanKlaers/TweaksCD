-- ============================================================================
-- TweaksUI: Cooldowns - Constants
-- ============================================================================

local ADDON_NAME, TUICD = ...

-- Make addon table global
_G.TUICD = TUICD

-- Version info
TUICD.VERSION = "2.0.0"
TUICD.ADDON_NAME = "TweaksUI: Cooldowns"
TUICD.ADDON_SHORT = "TUI:CD"

-- Chat prefix
TUICD.CHAT_PREFIX = "|cff00ccff[TUI:CD]|r "

-- Colors
TUICD.COLORS = {
    BRAND = "00ccff",
    SUCCESS = "00ff00",
    WARNING = "ffcc00",
    ERROR = "ff3333",
    MUTED = "888888",
}

-- Blizzard Cooldown Viewer definitions
TUICD.TRACKERS = {
    { 
        name = "EssentialCooldownViewer", 
        displayName = "Essential Cooldowns", 
        key = "essential",
        isBarType = false 
    },
    { 
        name = "UtilityCooldownViewer", 
        displayName = "Utility Cooldowns", 
        key = "utility",
        isBarType = false 
    },
    { 
        name = "BuffIconCooldownViewer", 
        displayName = "Buff Tracker", 
        key = "buffs",
        isBarType = false 
    },
}

-- Equipment slots that can have on-use abilities
TUICD.TRACKABLE_EQUIPMENT_SLOTS = {
    [1] = "Head",
    [2] = "Neck",
    [3] = "Shoulder",
    [5] = "Chest",
    [6] = "Waist",
    [7] = "Legs",
    [8] = "Feet",
    [9] = "Wrist",
    [10] = "Hands",
    [11] = "Ring 1",
    [12] = "Ring 2",
    [13] = "Trinket 1",
    [14] = "Trinket 2",
    [15] = "Back",
    [16] = "Main Hand",
    [17] = "Off Hand",
}

-- Aspect ratio presets
TUICD.ASPECT_PRESETS = {
    { label = "1:1 (Square)", value = "1:1" },
    { label = "4:3", value = "4:3" },
    { label = "3:4", value = "3:4" },
    { label = "16:9 (Wide)", value = "16:9" },
    { label = "9:16 (Tall)", value = "9:16" },
    { label = "2:1", value = "2:1" },
    { label = "1:2", value = "1:2" },
    { label = "Custom", value = "custom" },
}

-- UI Constants
TUICD.UI = {
    HUB_WIDTH = 220,
    HUB_HEIGHT = 485,
    PANEL_WIDTH = 420,
    PANEL_HEIGHT = 600,
    BUTTON_HEIGHT = 28,
    BUTTON_SPACING = 6,
}

-- Dock Constants
TUICD.DOCKS = {
    NUM_DOCKS = 4,
    DEFAULT_SPACING = 4,
    DEFAULT_ICON_SIZE = 36,
    
    -- Orientation
    ORIENTATION = {
        HORIZONTAL = "horizontal",
        VERTICAL = "vertical",
    },
    
    -- Justification (alignment within dock)
    JUSTIFY = {
        -- Horizontal orientations
        LEFT = "left",
        CENTER = "center", 
        RIGHT = "right",
        -- Vertical orientations
        TOP = "top",
        MIDDLE = "middle",
        BOTTOM = "bottom",
    },
}

-- Dark backdrop template
TUICD.BACKDROP_DARK = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
}

-- Midnight API Detection (v2.0+ is Midnight-only)
-- These are kept for backwards compatibility - actual detection is in Core/API/API.lua
-- After API.lua loads, these will be true (Midnight guarantees these APIs exist)
TUICD.HAS_SPELL_COOLDOWN_DURATION = true  -- C_Spell.GetSpellCooldownDuration
TUICD.HAS_SPELL_CHARGES_DURATION = true   -- C_Spell.GetSpellChargesCooldownDuration
