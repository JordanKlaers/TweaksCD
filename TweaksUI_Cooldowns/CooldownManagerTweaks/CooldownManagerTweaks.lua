-- ============================================================================
-- Cooldown Manager Tweaks - Migration Helper
-- This stub exists solely to load CMT's SavedVariables so TweaksUI: Cooldowns
-- can migrate settings from the old CMT addon.
-- ============================================================================

-- These globals will be populated by WoW from the SavedVariables files
-- if the user previously had CMT installed
CMT_DB = CMT_DB or nil
CMT_CharDB = CMT_CharDB or nil

-- Flag that this stub loaded (not the real CMT)
CMT_MIGRATION_STUB_LOADED = true
