--- === plugins.finalcutpro.menu.helpandsupport.finalcutpro ===
---
--- The Help & Support > CommandPost menu section.

--------------------------------------------------------------------------------
--
-- CONSTANTS:
--
--------------------------------------------------------------------------------

-- PRIORITY -> number
-- Constant
-- The menubar position priority.
local PRIORITY = 20

--------------------------------------------------------------------------------
--
-- THE PLUGIN:
--
--------------------------------------------------------------------------------
local plugin = {
    id              = "finalcutpro.menu.helpandsupport.finalcutpro",
    group           = "finalcutpro",
    dependencies    = {
        ["core.menu.helpandsupport"] = "helpandsupport"
    }
}

--------------------------------------------------------------------------------
-- INITIALISE PLUGIN:
--------------------------------------------------------------------------------
function plugin.init(dependencies)
    return dependencies.helpandsupport:addMenu(PRIORITY, function() return i18n("finalCutPro") end)
end

return plugin
