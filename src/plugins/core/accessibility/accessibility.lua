--- === plugins.core.accessibility ===
---
--- Accessibility Plugin.

local require           = require
local hs                = _G.hs

local application       = require "hs.application"

local config            = require "cp.config"
local i18n              = require "cp.i18n"
local prop              = require "cp.prop"
local tools             = require "cp.tools"

local mod = {}

--- plugins.core.accessibility.shouldWeTryCloseSystemPreferences -> boolean
--- Variable
--- Should we try and close system preferences?
mod.shouldWeTryCloseSystemPreferences = false

--- plugins.core.accessibility.systemPreferencesAlreadyOpen -> boolean
--- Variable
--- Was System Preferences already open?
mod.systemPreferencesAlreadyOpen = false

--- plugins.core.accessibility.enabled <cp.prop: boolean; read-only>
--- Constant
--- Is `true` if Accessibility permissions have been enabled for CommandPost.
--- Plugins interested in being notfied about accessibility status should
--- `watch` this property.
mod.enabled = prop.new(hs.accessibilityState):watch(function(enabled)
    if enabled then
        --------------------------------------------------------------------------------
        -- Close System Preferences, unless it was already open:
        --------------------------------------------------------------------------------
        if mod.shouldWeTryCloseSystemPreferences and not mod.systemPreferencesAlreadyOpen then
            local systemPrefs = application.applicationsForBundleID("com.apple.systempreferences")
            if systemPrefs and next(systemPrefs) ~= nil then
                systemPrefs[1]:kill()
                --------------------------------------------------------------------------------
                -- Give focus back to CommandPost:
                --------------------------------------------------------------------------------
                mod.setup:focus()
            end
            mod.shouldWeTryCloseSystemPreferences = false
        end
        mod.completeSetupPanel()
    else
        mod.showSetupPanel()
    end
end)

--- plugins.core.accessibility.completeSetupPanel() -> none
--- Function
--- Called when the setup panel for accessibility was shown and is ready to complete.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function mod.completeSetupPanel()
    if mod.showing then
        mod.showing = false
        mod.setup.nextPanel()
    end
end

--- plugins.core.accessibility.showSetupPanel() -> none
--- Function
--- Called when the Setup Panel should be shown to prompt the user about enabling Accessbility.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function mod.showSetupPanel()
    mod.showing = true
    mod.setup.addPanel(mod.panel)
    mod.setup.show()
end

--- plugins.core.accessibility.init(setup) -> table
--- Function
--- Initialises the module.
---
--- Parameters:
---  * setup - Dependancies setup
---
--- Returns:
---  * The module as a table
function mod.init(setup)
    mod.setup = setup
    mod.panel = setup.panel.new("accessibility", 10)
        :addIcon(config.basePath .. "/plugins/core/accessibility/images/UniversalAccessPref.icns")
        :addParagraph(i18n("accessibilityNote"), false)
        :addButton({
            label       = i18n("allowAccessibility"),
            onclick     = function()
                mod.shouldWeTryCloseSystemPreferences = true
                local systemPrefs = application.applicationsForBundleID("com.apple.systempreferences")
                if systemPrefs and next(systemPrefs) ~= nil then
                    mod.systemPreferencesAlreadyOpen = true
                end
                hs:accessibilityState(true)
            end,
        })
        :addButton({
            label       = i18n("quit"),
            onclick     = function() config.application():kill() end,
        })

    --------------------------------------------------------------------------------
    -- Get updated when the accessibility state changes:
    --------------------------------------------------------------------------------
    hs.accessibilityStateCallback = function()
        if not hs.accessibilityState() then
            mod.shouldWeTryCloseSystemPreferences = true
            local systemPrefs = application.applicationsForBundleID("com.apple.systempreferences")
            if systemPrefs and next(systemPrefs) ~= nil then
                mod.systemPreferencesAlreadyOpen = true
            end
        end
        mod.enabled:update()
    end

    --------------------------------------------------------------------------------
    -- Update to the current state:
    --------------------------------------------------------------------------------
    mod.enabled:update()

    return mod
end

local plugin = {
    id              = "core.accessibility",
    group           = "core",
    required        = true,
    dependencies    = {
        ["core.setup"]  = "setup",
    }
}

function plugin.init(deps)
    return mod.init(deps.setup)
end

return plugin