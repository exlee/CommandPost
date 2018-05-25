--- === cp.apple.finalcutpro.plugins ===
---
--- Scans an entire system for Final Cut Pro Effects, Generators, Titles & Transitions.
---
--- Usage:
--- ```
---     require("cp.apple.finalcutpro"):plugins():scan()
--- ```

--------------------------------------------------------------------------------
--
-- EXTENSIONS:
--
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Logger:
--------------------------------------------------------------------------------
local log                       = require("hs.logger").new("scan")

--------------------------------------------------------------------------------
-- Hammerspoon Extensions:
--------------------------------------------------------------------------------
-- local inspect                   = require("hs.inspect")
local fnutils                   = require("hs.fnutils")
local fs                        = require("hs.fs")
local json                      = require("hs.json")

--------------------------------------------------------------------------------
-- CommandPost Extensions:
--------------------------------------------------------------------------------
local archiver                  = require("cp.plist.archiver")
local config                    = require("cp.config")
local localeID                  = require("cp.i18n.localeID")
local localized                 = require("cp.localized")
local plist                     = require("cp.plist")
local strings                   = require("cp.strings")
local text                      = require("cp.web.text")
local tools                     = require("cp.tools")
local watcher                   = require("cp.watcher")

local fcpApp                    = require("cp.apple.finalcutpro.app")
local id                        = require("cp.apple.finalcutpro.ids") "LogicPlugins"

--------------------------------------------------------------------------------
-- 3rd Party Extensions:
--------------------------------------------------------------------------------
local v                         = require("semver")

--------------------------------------------------------------------------------
--
-- CONSTANTS:
--
--------------------------------------------------------------------------------

-- THEME_PATTERN -> string
-- Constant
-- Theme Pattern
local THEME_PATTERN = ".*<theme>(.+)</theme>.*"

-- FLAGS_PATTERN -> string
-- Constant
-- Flags Pattern
local FLAGS_PATTERN = ".*<flags>(.+)</flags>.*"

-- OBSOLETE_FLAG -> number
-- Constant
-- Obsolete Flag
local OBSOLETE_FLAG = 2

--------------------------------------------------------------------------------
--
-- THE MODULE:
--
--------------------------------------------------------------------------------
local mod                       = {}

mod.mt                          = {}
mod.mt.__index                  = mod.mt

-- set this to `true` via _fcp:plugins():outputReport(true) to enable reporting
mod.outputReport = config.prop("fcpPluginsOutputReport", true)

local function report(message, ...)
    if mod.outputReport() then
        log.df(message, ...)
    end
end

--- cp.apple.finalcutpro.plugins.types
--- Constant
--- Table of the different audio/video/transition/generator types.
mod.types = {
    videoEffect = "videoEffect",
    audioEffect = "audioEffect",
    title       = "title",
    generator   = "generator",
    transition  = "transition",
}

--- cp.apple.finalcutpro.plugins.coreAudioPreferences
--- Constant
--- Core Audio Preferences File Path
mod.coreAudioPreferences = "/System/Library/Components/CoreAudio.component/Contents/Info.plist"

--- cp.apple.finalcutpro.plugins.audioUnitsCache
--- Constant
--- Path to the Audio Units Cache
mod.audioUnitsCache      = "~/Library/Preferences/com.apple.audio.InfoHelper.plist"

--- cp.apple.finalcutpro.plugins.appBuiltinPlugins
--- Constant
--- Table of built-in plugins
mod.appBuiltinPlugins = {
    --------------------------------------------------------------------------------
    -- Built-in Effects:
    --------------------------------------------------------------------------------
    [mod.types.videoEffect] = {
        ["FFEffectCategoryColor"]   = { "FFCorrectorEffectName" },
        ["FFMaskEffect"]            = { "FFSplineMaskEffect", "FFShapeMaskEffect" },
        ["Stylize"]                 = { "DropShadow::Filter Name" },
        ["FFEffectCategoryKeying"]  = { "Keyer::Filter Name", "LumaKeyer::Filter Name" }
    },

    --------------------------------------------------------------------------------
    -- Built-in Transitions:
    --------------------------------------------------------------------------------
    [mod.types.transition] = {
        ["Transitions::Dissolves"] = { "CrossDissolve::Filter Name", "DipToColorDissolve::Transition Name", "FFTransition_OpticalFlow" },
        ["Movements"] = { "SpinSlide::Transition Name", "Swap::Transition Name", "RippleTransition::Transition Name", "Mosaic::Transition Name", "PageCurl::Transition Name", "PuzzleSlide::Transition Name", "Slide::Transition Name" },
        ["Objects"] = { "Cube::Transition Name", "StarIris::Transition Name", "Doorway::Transition Name" },
        ["Wipes"] = { "BandWipe::Transition Name", "CenterWipe::Transition Name", "CheckerWipe::Transition Name", "ChevronWipe::Transition Name", "OvalIris::Transition Name", "ClockWipe::Transition Name", "GradientImageWipe::Transition Name", "Inset Wipe::Transition Name", "X-Wipe::Transition Name", "EdgeWipe::Transition Name" },
        ["Blurs"] = { "CrossZoom::Transition Name", "CrossBlur::Transition Name" },
    },
}

--- cp.apple.finalcutpro.plugins.appEdelEffects
--- Constant
--- Table of Built-in Soundtrack Pro EDEL Effects.
mod.appEdelEffects = {
    ["Distortion"] = {
        "Bitcrusher",
        "Clip Distortion",
        "Distortion",
        "Distortion II",
        "Overdrive",
        "Phase Distortion",
        "Ringshifter",
    },
    ["Echo"] = {
        "Delay Designer",
        "Modulation Delay",
        "Stereo Delay",
        "Tape Delay",
    },
    ["EQ"] = {
        "AutoFilter",
        "Channel EQ", -- This isn't actually listed as a Logic plugin in FCPX, but it is.
        "Fat EQ",
        "Linear Phase EQ",
    },
    ["Levels"] = {
        "Adaptive Limiter",
        "Compressor",
        "Enveloper",
        "Expander",
        "Gain",
        "Limiter",
        "Multichannel Gain",
        "Multipressor",
        "Noise Gate",
        "Spectral Gate",
        "Surround Compressor",
    },
    ["Modulation"] = {
        "Chorus",
        "Ensemble",
        "Flanger",
        "Phaser",
        "Scanner Vibrato",
        "Tremolo"
    },
    ["Spaces"] = {
        "PlatinumVerb",
        "Space Designer",
    },
    ["Specialized"] = {
        "Correlation Meter",
        "Denoiser",
        "Direction Mixer",
        "Exciter",
        "MultiMeter",
        "Stereo Spread",
        "SubBass",
        "Test Oscillator",
    },
    ["Voice"] = {
        "DeEsser",
        "Pitch Correction",
        id "PitchShifter",
        "Vocal Transformer",
    },
}

--- cp.apple.finalcutpro.plugins.types
--- Constant
--- Table of the different Motion Template Extensions
mod.motionTemplates = {
    ["Effects"] = {
        type = mod.types.videoEffect,
        extension = "moef",
    },
    ["Transitions"] = {
        type = mod.types.transition,
        extension = "motr",
    },
    ["Generators"] = {
        type = mod.types.generator,
        extension = "motn",
    },
    ["Titles"] = {
        type = mod.types.title,
        extension = "moti",
    }
}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS:
--------------------------------------------------------------------------------
local contains                  = fnutils.contains
local copy                      = fnutils.copy
local getLocalizedName          = localized.getLocalizedName
local insert, remove            = table.insert, table.remove
local unescapeXML               = text.unescapeXML

-- string:split(delimiter) -> table
-- Function
-- Splits a string into a table, separated by a separator pattern.
--
-- Parameters:
--  * delimiter - Separator pattern
--
-- Returns:
--  * table
function string:split(delimiter) -- luacheck: ignore
   local list = {}
   local pos = 1
   if string.find("", delimiter, 1) then -- this would result in endless loops
      error("delimiter matches empty string: %s", delimiter)
   end
   while true do
      local first, last = self:find(delimiter, pos)
      if first then -- found?
         insert(list, self:sub(pos, first-1))
         pos = last+1
      else
         insert(list, self:sub(pos))
         break
      end
   end
   return list
end

-- endsWith(str, ending) -> boolean
-- Function
-- Checks to see if `str` has the same ending as `ending`.
--
-- Parameters:
--  * str       - String to analysis
--  * ending    - End of string to compare against
--
-- Returns:
--  * table
local function endsWith(str, ending)
    local len = #ending
    return str:len() >= len and str:sub(len * -1) == ending
end

--- cp.apple.finalcutpro.plugins:scanSystemAudioUnits(locale) -> none
--- Function
--- Scans for Validated Audio Units, and saves the results to a cache for faster subsequent startup times.
---
--- Parameters:
---  * locale   - the locale to scan in.
---
--- Returns:
---  * None
function mod.mt:scanSystemAudioUnits(locale)
    locale = localeID(locale)
    --------------------------------------------------------------------------------
    -- Restore from cache:
    --------------------------------------------------------------------------------
    local cache = {}
    local cacheFile = mod.audioUnitsCache

    local currentModification = fs.attributes(cacheFile) and fs.attributes(cacheFile).modification
    local lastModification = config.get("audioUnitsCacheModification", nil)
    local audioUnitsCache = config.get("audioUnitsCache", nil)

    if currentModification and lastModification and audioUnitsCache and currentModification == lastModification then
        report("  * Using Audio Units Cache (" .. tostring(#audioUnitsCache) .. " items)")
        for _, data in pairs(audioUnitsCache) do
            local coreAudioPlistPath = data.coreAudioPlistPath or nil
            local audioEffect = data.audioEffect or nil
            local category = data.category or nil
            local plugin = data.plugin or nil
            local loc = data.locale or nil
            self:registerPlugin(coreAudioPlistPath, audioEffect, category, "OS X", plugin, loc)
        end
        return
    end

    --------------------------------------------------------------------------------
    -- Get the full list of Audio Unit Plugins via `auval`:
    --------------------------------------------------------------------------------
    local output, status = hs.execute("auval -s aufx")
    local audioEffect = mod.types.audioEffect

    if status and output then

        local coreAudioPlistPath = mod.coreAudioPreferences
        local coreAudioPlistData = plist.fileToTable(coreAudioPlistPath)

        local lines = tools.lines(output)
        for _, line in pairs(lines) do
            local fullName = string.match(line, "^%w%w%w%w%s%w%w%w%w%s%w%w%w%w%s+%-%s+(.*)$")
            if fullName then
                local category, plugin = string.match(fullName, "^(.-):%s*(.*)$")
                --------------------------------------------------------------------------------
                -- CoreAudio Audio Units:
                --------------------------------------------------------------------------------
                if coreAudioPlistData and category == "Apple" then
                    --------------------------------------------------------------------------------
                    -- Look up the alternate name:
                    --------------------------------------------------------------------------------
                    for _, component in pairs(coreAudioPlistData["AudioComponents"]) do
                        if component.name == fullName then
                            category = "Specialized"
                            local tags = component.tags
                            if tags then
                                if contains(tags, "Pitch") then category = "Voice"
                                elseif contains(tags, "Delay") then category = "Echo"
                                elseif contains(tags, "Reverb") then category = "Spaces"
                                elseif contains(tags, "Equalizer") then category = "EQ"
                                elseif contains(tags, "Dynamics Processor") then category = "Levels"
                                elseif contains(tags, "Distortion") then category = "Distortion" end
                            end
                        end
                    end
                end

                --------------------------------------------------------------------------------
                -- Cache Plugin:
                --------------------------------------------------------------------------------
                table.insert(cache, {
                    coreAudioPlistPath = coreAudioPlistPath,
                    audioEffect = audioEffect,
                    category = category,
                    plugin = plugin,
                    locale = locale.code,
                })

                self:registerPlugin(coreAudioPlistPath, audioEffect, category, "OS X", plugin, locale)
            end
        end

        --------------------------------------------------------------------------------
        -- Save Cache:
        --------------------------------------------------------------------------------
        if currentModification and #cache ~= 0 then
            config.set("audioUnitsCacheModification", currentModification)
            config.set("audioUnitsCache", cache)
            report("  * Saved " .. #cache .. " Audio Units to Cache.")
        else
            log.ef("  * Failed to cache Audio Units.")
        end
    else
        log.ef("  * Failed to scan for Audio Units.")
    end

end

--- cp.apple.finalcutpro.plugins:scanUserEffectsPresets(locale) -> none
--- Function
--- Scans Final Cut Pro Effects Presets
---
--- Parameters:
---  * `locale`    - The locale to scan for.
---
--- Returns:
---  * None
function mod.mt:scanUserEffectsPresets(locale)
    locale = localeID(locale)

    --------------------------------------------------------------------------------
    -- User Presets Path:
    --------------------------------------------------------------------------------
    local path = fs.pathToAbsolute("~/Library/Application Support/ProApps/Effects Presets")

    --------------------------------------------------------------------------------
    -- Restore from cache:
    --------------------------------------------------------------------------------
    local cache = {}

    local currentSize = fs.attributes(path) and fs.attributes(path).size
    local lastSize = config.get("userEffectsPresetsCacheModification", nil)
    local userEffectsPresetsCache = config.get("userEffectsPresetsCache", nil)

    if currentSize and lastSize and userEffectsPresetsCache and currentSize == lastSize then
        report("  * Using User Effects Presets Cache (" .. tostring(#userEffectsPresetsCache) .. " items).")
        for _, data in pairs(userEffectsPresetsCache) do
            local effectPath = data.effectPath or nil
            local effectType = data.effectType or nil
            local category = data.category or nil
            local plugin = data.plugin or nil
            local lan = data.locale or nil
            self:registerPlugin(effectPath, effectType, category, "Final Cut", plugin, lan)
        end
        return
    end

    local videoEffect, audioEffect = mod.types.videoEffect, mod.types.audioEffect
    if tools.doesDirectoryExist(path) then
        for file in fs.dir(path) do
            local plugin = string.match(file, "(.+)%.effectsPreset")
            if plugin then
                local effectPath = path .. "/" .. file
                local preset = archiver.unarchiveFile(effectPath)
                if preset then
                    local category = preset.category
                    local effectType = preset.effectType or preset.presetEffectType
                    if category then
                        local type = effectType == "effect.audio.effect" and audioEffect or videoEffect
                        self:registerPlugin(effectPath, type, category, "Final Cut", plugin, locale)

                        --------------------------------------------------------------------------------
                        -- Cache Plugin:
                        --------------------------------------------------------------------------------
                        table.insert(cache, {
                            effectPath = effectPath,
                            effectType = type,
                            category = category,
                            plugin = plugin,
                            locale = locale.code,
                        })

                    end
                end
            end
        end

        --------------------------------------------------------------------------------
        -- Save Cache:
        --------------------------------------------------------------------------------
        if currentSize and #cache ~= 0 then
            config.set("userEffectsPresetsCacheModification", currentSize)
            config.set("userEffectsPresetsCache", cache)
            report("  * Saved " .. #cache .. " User Effects Presets to Cache.")
        else
            log.ef("  * Failed to cache User Effects Presets.")
        end

    end
end

-- getMotionTheme(filename) -> string | nil
-- Function
-- Process a plugin so that it's added to the current scan
--
-- Parameters:
--  * filename - Filename of the plugin
--
-- Returns:
--  * The theme name, or `nil` if not found.
--
-- Notes:
--  * getMotionTheme("~/Movies/Motion Templates.localized/Effects.localized/3065D03D-92D7-4FD9-B472-E524B87B5012.localized/DAEB0CAD-E702-4BF9-94B5-AE89D7F8FB00.localized/DAEB0CAD-E702-4BF9-94B5-AE89D7F8FB00.moef")
local function getMotionTheme(filename)
    filename = filename and fs.pathToAbsolute(filename)
    if filename then
        local inTemplate = false
        local theme = nil
        local flags = nil

        --------------------------------------------------------------------------------
        -- Reads through the motion file, looking for the template/theme elements:
        --------------------------------------------------------------------------------
        local file = io.open(filename,"r")
        while theme == nil or flags == nil do
            local line = file:read("*l")
            if line == nil then break end
            if not inTemplate then
                inTemplate = endsWith(line, "<template>")
            end
            if inTemplate then
                theme = theme or line:match(THEME_PATTERN)
                flags = line:match(FLAGS_PATTERN) or flags
                if endsWith(line, "</template>") then
                    break
                end
            end
        end
        file:close()

        --------------------------------------------------------------------------------
        -- Unescape the theme text:
        --------------------------------------------------------------------------------
        theme = theme and unescapeXML(theme) or nil

        --------------------------------------------------------------------------------
        -- Convert flags to a number for checking:
        --------------------------------------------------------------------------------
        flags = flags and tonumber(flags) or 0
        local isObsolete = (flags & OBSOLETE_FLAG) == OBSOLETE_FLAG
        return theme, isObsolete
    end
    return nil
end
mod._getMotionTheme = getMotionTheme

-- getPluginName(path, pluginExt) -> boolean
-- Function
-- Checks if the specified path is a plugin directory, and returns the plugin name.
--
-- Parameters:
--  * `path`        - The path to the directory to check
--  * `pluginExt`   - The plugin extensions to check for.
--
-- Returns:
--  * The plugin name.
--  * The plugin theme.
--  * `true` if the plugin is obsolete
local function getPluginName(path, pluginExt, locale)
    if path and tools.doesDirectoryExist(path) then
        locale = localeID(locale)
        local localName, realName = getLocalizedName(path, locale)
        if realName then
            local targetExt = "."..pluginExt
            for file in fs.dir(path) do
                if endsWith(file, targetExt) then
                    local name = file:sub(1, (targetExt:len()+1)*-1)
                    local pluginPath = path .. "/" .. name .. targetExt
                    if name == realName then
                        name = localName
                    end
                    return name, getMotionTheme(pluginPath)
                end
            end
        end
    end
    return nil, nil, nil
end
mod._getPluginName = getPluginName

--- cp.apple.finalcutpro.plugins:scanPluginsDirectory(locale, path, filter) -> boolean
--- Method
--- Scans a root plugins directory. Plugins directories have a standard structure which comes in two flavours:
---
---   1. <type>/<plugin name>/<plugin name>.<ext>
---   2. <type>/<group>/<plugin name>/<plugin name>.<ext>
---   3. <type>/<group>/<theme>/<plugin name>/<plugin name>.<ext>
---
--- This is somewhat complicated by 'localization', wherein each of the folder levels may have a `.localized` extension. If this is the case, it will contain a subfolder called `.localized`, which in turn contains files which describe the local name for the folder in any number of locales.
---
--- This function will drill down through the contents of the specified `path`, assuming the above structure, and then register any contained plugins in the `locale` provided. Other locales are ignored, other than some use of English when checking for specific effect types (Effect, Generator, etc.).
---
--- Parameters:
---  * `locale`   - The locale code to scan for (e.g. "en" or "fr").
---  * `path`       - The path of the root plugin directory to scan.
---  * `checkFn`    - A function which will receive the path being scanned and return `true` if it should be scanned.
---
--- Returns:
---  * `true` if the plugin directory was successfully scanned.
function mod.mt:scanPluginsDirectory(locale, path, checkFn)
    locale = localeID(locale)
    --------------------------------------------------------------------------------
    -- Check that the directoryPath actually exists:
    --------------------------------------------------------------------------------
    path = fs.pathToAbsolute(path)
    if not path then
        log.wf("The provided path does not exist: '%s'", path)
        return false
    end

    --------------------------------------------------------------------------------
    -- Check that the directoryPath is actually a directory:
    --------------------------------------------------------------------------------
    local attrs = fs.attributes(path)
    if not attrs or attrs.mode ~= "directory" then
        log.ef("The provided path is not a directory: '%s'", path)
        return false
    end

    local failure = false

    --------------------------------------------------------------------------------
    -- Loop through the files in the directory:
    --------------------------------------------------------------------------------
    for file in fs.dir(path) do
        if file:sub(1,1) ~= "." then
            local typePath = path .. "/" .. file
            local typeNameEN = getLocalizedName(typePath, "en")
            local mt = mod.motionTemplates[typeNameEN]
            if mt then
                local plugin = {
                    type = mt.type,
                    extension = mt.extension,
                    check = checkFn or function() return true end,
                }
                failure = failure or not self:scanPluginTypeDirectory(locale, typePath, plugin)
            end
        end
    end

    return not failure
end

-- cp.apple.finalcutpro.plugins:handlePluginDirectory(locale, path, plugin) -> boolean
-- Method
-- Handles a Plugin Directory.
--
-- Parameters:
--  * `locale`    - The locale to scan with.
--  * `path`        - The path to the plugin type directory.
--  * `plugin`      - A table containing the plugin details collected so far.
--
-- Returns:
--  * `true` if it's a legit plugin directory, even if we didn't register it, otherwise `false` if it's not a plugin directory.
function mod.mt:handlePluginDirectory(locale, path, plugin)
    local pluginName, themeName, obsolete = getPluginName(path, plugin.extension, locale)
    if pluginName then
        plugin.name = pluginName
        plugin.themeLocal = plugin.themeLocal or themeName
        --------------------------------------------------------------------------------
        -- Only register it if not obsolete and if the check function
        -- passes (if present):
        --------------------------------------------------------------------------------
        if not obsolete and plugin:check() then
            self:registerPlugin(
                path,
                plugin.type,
                plugin.categoryLocal,
                plugin.themeLocal,
                plugin.name,
                locale
            )
        end
        --------------------------------------------------------------------------------
        -- Return true if it's a legit plugin directory, even if we didn't register it.
        --------------------------------------------------------------------------------
        return true
    end
    --------------------------------------------------------------------------------
    -- Return false if it's not a plugin directory.
    --------------------------------------------------------------------------------
    return false
end

-- cp.apple.finalcutpro.plugins:scanPluginTypeDirectory(locale, path, plugin) -> boolean
-- Method
-- Scans a folder as a plugin type folder, such as 'Effects', 'Transitions', etc. The contents will be folders that are 'groups' of plugins, containing related plugins.
--
-- Parameters:
--  * `locale`    - The locale to scan with.
--  * `path`        - The path to the plugin type directory.
--  * `plugin`      - A table containing the plugin details collected so far.
--
-- Returns:
--  * `true` if the folder was scanned successfully.
function mod.mt:scanPluginTypeDirectory(locale, path, plugin)
    locale = localeID(locale)
    local failure = false

    for file in fs.dir(path) do
        if file:sub(1,1) ~= "." then
            local p = copy(plugin)
            local childPath = path .. "/" .. file
            local attrs = fs.attributes(childPath)
            if attrs and attrs.mode == "directory" then
                if not self:handlePluginDirectory(locale, childPath, p) then
                    p.categoryLocal, p.categoryReal = getLocalizedName(childPath, locale)
                    failure = failure or not self:scanPluginCategoryDirectory(locale, childPath, p)
                end
            end
        end
    end

    return not failure
end

--- cp.apple.finalcutpro.plugins:scanPluginCategoryDirectory(locale, path, plugin) -> boolean
--- Method
--- Scans a folder as a plugin category folder. The contents will be folders that are either theme folders or actual plugins.
---
--- Parameters:
---  * `locale`        - The locale to scan with.
---  * `path`            - The path to the plugin type directory
---  * `plugin`      - A table containing the plugin details collected so far.
---
--- Returns:
---  * `true` if the folder was scanned successfully.
function mod.mt:scanPluginCategoryDirectory(locale, path, plugin)
    locale = localeID(locale)
    local failure = false

    for file in fs.dir(path) do
        if file:sub(1,1) ~= "." then
            local p = copy(plugin)
            local childPath = path .. "/" .. file
            local attrs = fs.attributes(childPath)
            if attrs and attrs.mode == "directory" then
                if not self:handlePluginDirectory(locale, childPath, p) then
                    p.themeLocal, p.themeReal = getLocalizedName(childPath, locale)
                    failure = failure or not self:scanPluginThemeDirectory(locale, childPath, p)
                end
            end
        end
    end

    return not failure
end

--- cp.apple.finalcutpro.plugins:scanPluginThemeDirectory(locale, path, plugin) -> boolean
--- Method
--- Scans a folder as a plugin theme folder. The contents will be plugin folders.
---
--- Parameters:
---  * `locale`        - The locale to scan with.
---  * `path`            - The path to the plugin type directory
---  * `plugin`          - A table containing the plugin details collected so far.
---
--- Returns:
---  * `true` if the folder was scanned successfully.
function mod.mt:scanPluginThemeDirectory(locale, path, plugin)
    locale = localeID(locale)
    for file in fs.dir(path) do
        if file:sub(1,1) ~= "." then
            local p = copy(plugin)
            local pluginPath = path .. "/" .. file
            if fs.attributes(pluginPath).mode == "directory" then
                self:handlePluginDirectory(locale, pluginPath, p)
            end
        end
    end
    return true
end

--- cp.apple.finalcutpro.plugins:registerPlugin(path, type, categoryName, themeName, pluginName, locale) -> plugin
--- Method
--- Registers a plugin with the specified details.
---
--- Parameters:
---  * `path`           - The path to the plugin directory.
---  * `type`           - The type of plugin
---  * `categoryName`   - The category name, in the specified locale.
---  * `themeName`      - The theme name, in the specified locale. May be `nil` if not in a theme.
---  * `pluginName`     - The plugin name, in the specified locale.
---  * `locale`         - The `cp.i18n.localeID` or string code for same (e.g. "en", "fr", "de")
---
--- Returns:
---  * The plugin object.
function mod.mt:registerPlugin(path, type, categoryName, themeName, pluginName, locale)

    -- TODO: Chris added `fcpApp:currentLocale()` because for some reason `locale` was coming in as `nil`?
    locale = localeID(locale) or fcpApp:currentLocale()

    local plugins = self._plugins
    if not plugins then
        plugins = {}
        self._plugins = plugins
    end

    local lang = plugins[locale.code]
    if not lang then
        lang = {}
        plugins[locale.code] = lang
    end

    local types = lang[type]
    if not types then
        types = {}
        lang[type] = types
    end

    local plugin = {
        path = path,
        type = type,
        category = categoryName,
        theme = themeName,
        name = pluginName,
        locale = locale.code,
    }
    insert(types, plugin)
    --------------------------------------------------------------------------------
    -- Caching:
    --------------------------------------------------------------------------------
    if mod._motionTemplatesToCache then
        insert(mod._motionTemplatesToCache, plugin)
    end
    return plugin
end

--- cp.apple.finalcutpro.plugins:reset() -> none
--- Method
--- Resets all the cached plugins.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function mod.mt:reset()
    self._plugins = {}
end

--- cp.apple.finalcutpro.plugins:effectBundleStrings() -> table
--- Method
--- Returns all the Effect Bundle Strings.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The effect bundle strings in a table.
function mod.mt:effectBundleStrings()
    local source = self._effectBundleStrings
    if not source then
        local context = {
            appPath = fcpApp:path(),
            locale = fcpApp:currentLocale().aliases,
        }
        source = strings.new():context(context):fromPlist("${appPath}/Contents/Frameworks/Flexo.framework/Resources/${locale}.lproj/FFEffectBundleLocalizable.strings")
        self._effectBundleStrings = source
    end
    return source
end

--- cp.apple.finalcutpro.plugins:translateEffectBundle(input, locale) -> none
--- Method
--- Translates an Effect Bundle Item.
---
--- Parameters:
---  * input - The original name
---  * locale - The locale code you want to attempt to translate to
---
--- Returns:
---  * The translated value for `input` in the specified locale, if present.
function mod.mt:translateEffectBundle(input, locale)
    locale = localeID(locale)
    local context = { locale = locale.aliases }
    return self:effectBundleStrings():find(input, context) or input
end

--- cp.apple.finalcutpro.plugins:scanAppAudioEffectBundles() -> none
--- Method
--- Scans the Audio Effect Bundles directories.
---
--- Parameters:
---  * directoryPath - Directory to scan
---
--- Returns:
---  * None
function mod.mt:scanAppAudioEffectBundles(locale)
    locale = localeID(locale)
    local audioEffect = mod.types.audioEffect
    local path = fcpApp:path() .. "/Contents/Frameworks/Flexo.framework/Resources/Effect Bundles"
    if tools.doesDirectoryExist(path) then
        for file in fs.dir(path) do
            --------------------------------------------------------------------------------
            -- Example: Alien.Voice.audio.effectBundle
            --------------------------------------------------------------------------------
            local name, category, type = string.match(file, "^([^%.]+)%.([^%.]+)%.([^%.]+)%.effectBundle$")
            if name and type == "audio" then
                local plugin = self:translateEffectBundle(name, locale)
                self:registerPlugin(path .. "/" .. file, audioEffect, category, "Final Cut", plugin, locale)
            end
        end
    end
end

--- cp.apple.finalcutpro.plugins:scanAppMotionTemplates(locale) -> none
--- Method
--- Scans for app-provided Final Cut Pro Plugins.
---
--- Parameters:
---  * `locale`    - The locale to scan for.
---
--- Returns:
---  * None
function mod.mt:scanAppMotionTemplates(locale)
    locale = localeID(locale)
    local fcpPath = fcpApp:path()
    self:scanPluginsDirectory(locale, fcpPath .. "/Contents/PlugIns/MediaProviders/MotionEffect.fxp/Contents/Resources/PETemplates.localized")
    self:scanPluginsDirectory(
        locale,
        fcpPath .. "/Contents/PlugIns/MediaProviders/MotionEffect.fxp/Contents/Resources/Templates.localized",
        --------------------------------------------------------------------------------
        -- We filter out the 'Simple' category here, since it contains
        -- unlisted iMovie titles.
        --------------------------------------------------------------------------------
        function(plugin) return plugin.categoryReal ~= "Simple" end
    )
end

--- cp.apple.finalcutpro.plugins:scanUserMotionTemplates(locale) -> none
--- Method
--- Scans for user-provided Final Cut Pro Plugins.
---
--- Parameters:
---  * `locale`    - The locale to scan for.
---
--- Returns:
---  * None
function mod.mt:scanUserMotionTemplates(locale)
    locale = localeID(locale)
    --------------------------------------------------------------------------------
    -- User Motion Templates Path:
    --------------------------------------------------------------------------------
    local path = "~/Movies/Motion Templates.localized"
    local pathToAbsolute = fs.pathToAbsolute(path)

    --------------------------------------------------------------------------------
    -- Restore from cache:
    --------------------------------------------------------------------------------
    local currentSize = fs.attributes(pathToAbsolute) and fs.attributes(pathToAbsolute).size
    local lastSize = config.get("userMotionTemplatesCacheSize", nil)
    local userMotionTemplatesCache = config.get("userMotionTemplatesCache", nil)
    if currentSize and lastSize and currentSize == lastSize then
        if userMotionTemplatesCache and userMotionTemplatesCache[locale.code] and #userMotionTemplatesCache[locale.code] > 0 then
            --------------------------------------------------------------------------------
            -- Restore from cache:
            --------------------------------------------------------------------------------
            report("  * Loading User Motion Templates from Cache (%s items)", #userMotionTemplatesCache[locale.code])
            for _, data in pairs(userMotionTemplatesCache[locale.code]) do
                self:registerPlugin(data.path, data.type, data.category, data.theme, data.name, data.locale)
            end
            return
        else
            report("  * Could not find User Motion Template Cache for locale: %s", locale.code)
        end
    end

    --------------------------------------------------------------------------------
    -- Scan for User Motion Templates:
    --------------------------------------------------------------------------------
    mod._motionTemplatesToCache = nil
    mod._motionTemplatesToCache = {}
    local result = self:scanPluginsDirectory(locale, path)
    if result and currentSize then
        --------------------------------------------------------------------------------
        -- Save to cache:
        --------------------------------------------------------------------------------
        config.set("userMotionTemplatesCache", {
            [locale.code] = mod._motionTemplatesToCache,
        })
        config.set("userMotionTemplatesCacheSize", currentSize)

        report("  * Saving User Motion Tempaltes to Cache (%s items)", #mod._motionTemplatesToCache)

        mod._motionTemplatesToCache = nil
    end
    return result
end

--- cp.apple.finalcutpro.plugins:scanSystemMotionTemplates(locale) -> none
--- Method
--- Scans for system-provided Final Cut Pro Plugins.
---
--- Parameters:
---  * `locale`    - The locale to scan for.
---
--- Returns:
---  * None
function mod.mt:scanSystemMotionTemplates(locale)
    locale = localeID(locale)

    --------------------------------------------------------------------------------
    -- User Motion Templates Path:
    --------------------------------------------------------------------------------
    local path = "/Library/Application Support/Final Cut Pro/Templates.localized"
    local pathToAbsolute = fs.pathToAbsolute(path)
    if not pathToAbsolute then
        report("Folder does not exist: %s", path)
        return nil
    end

    --------------------------------------------------------------------------------
    -- Restore from cache:
    --------------------------------------------------------------------------------
    local currentSize = fs.attributes(pathToAbsolute) and fs.attributes(pathToAbsolute).size
    local lastSize = config.get("systemMotionTemplatesCacheSize", nil)
    local systemMotionTemplatesCache = config.get("systemMotionTemplatesCache", nil)

    if currentSize and lastSize and currentSize == lastSize then
        if systemMotionTemplatesCache and systemMotionTemplatesCache[locale.code] and #systemMotionTemplatesCache[locale.code] > 0 then
            --------------------------------------------------------------------------------
            -- Restore from cache:
            --------------------------------------------------------------------------------
            report("  * Loading System Motion Templates from Cache (%s items)", #systemMotionTemplatesCache[locale.code])

            --log.df("mod._motionTemplatesToCache: %s", hs.inspect(config.get("systemMotionTemplatesCache")))


            for _, data in pairs(systemMotionTemplatesCache[locale.code]) do
                self:registerPlugin(data.path, data.type, data.category, data.theme, data.name, data.locale)
            end

            return
        else
            report("  * Could not find System Motion Template Cache for locale: %s", locale.code)
        end
    end

    --------------------------------------------------------------------------------
    -- Scan for User Motion Templates:
    --------------------------------------------------------------------------------
    mod._motionTemplatesToCache = nil
    mod._motionTemplatesToCache = {}
    local result = self:scanPluginsDirectory(locale, path)
    if result and currentSize then
        --------------------------------------------------------------------------------
        -- Save to cache:
        --------------------------------------------------------------------------------
        config.set("systemMotionTemplatesCache", {
            [locale.code] = mod._motionTemplatesToCache,
        })
        config.set("systemMotionTemplatesCacheSize", currentSize)

        report("  * Saving System Motion Templates to Cache (%s items)", #mod._motionTemplatesToCache)

        mod._motionTemplatesToCache = nil
    end
    return result

end

--- cp.apple.finalcutpro.plugins:scanAppEdelEffects() -> none
--- Method
--- Scans for Soundtrack Pro EDEL Effects.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function mod.mt:scanAppEdelEffects(locale)
    locale = localeID(locale)
    local audioEffect = mod.types.audioEffect
    for category, plugins in pairs(mod.appEdelEffects) do
        for _, plugin in ipairs(plugins) do
            self:registerPlugin(nil, audioEffect, category, "Logic", plugin, locale)
        end
    end

    --------------------------------------------------------------------------------
    -- TODO: I haven't worked out a way to programatically work out the category
    -- yet, so aborted this method:
    --------------------------------------------------------------------------------
    --[[
    local path = fcpApp():path() .. "/Contents/Frameworks/Flexo.framework/PlugIns/Audio/EDEL.bundle/Contents/Resources/Plug-In Settings"
    if tools.doesDirectoryExist(path) then
        for file in fs.dir(path) do
            local filePath = fs.pathToAbsolute(path .. "/" .. file)
            attrs = fs.attributes(filePath)
            if attrs.mode == "directory" then

                local category = "All"
                local plugin = file

                for _, currentlocale in pairs(mod.supportedlocales) do

                    if not mod._plugins[currentLocale.code]["AudioEffects"] then
                        mod._plugins[currentLocale.code]["AudioEffects"] = {}
                    end

                    if not mod._plugins[currentLocale.code]["AudioEffects"][category] then
                        mod._plugins[currentLocale.code]["AudioEffects"][category] = {}
                    end

                    local pluginID = #mod._plugins[currentLocale.code]["AudioEffects"][category] + 1
                    mod._plugins[currentLocale.code]["AudioEffects"][category][pluginID] = plugin

                end
            end
        end
    end
    --]]

end

--- cp.apple.finalcutpro.plugins:effectStrings() -> table
--- Method
--- Returns a table of Effects Strings.
---
--- Parameters:
---  * None
---
--- Returns:
---  * A table of effect strings.
function mod.mt:effectStrings()
    local source = self._effectStrings
    if not source then
        source = strings.new():context({
            appPath = fcpApp:path(),
            locale = fcpApp:currentLocale().aliases,
        })
        source:fromPlist("${appPath}/Contents/PlugIns/InternalFiltersXPC.pluginkit/Contents/PlugIns/Filters.bundle/Contents/Resources/${locale}.lproj/Localizable.strings")
        source:fromPlist("${appPath}/Contents/Frameworks/Flexo.framework/Versions/A/Resources/${locale}.lproj/FFLocalizable.strings")
        self._effectStrings = source
    end
    return source
end

-- translateInternalEffect(input, locale) -> none
-- Function
-- Translates an Effect Bundle Item
--
-- Parameters:
--  * input - The original name
--  * locale - The `localeID` code you want to attempt to translate to
--
-- Returns:
--  * Result as string
--
-- Notes:
--  * require("cp.plist").fileToTable("/Applications/Final Cut Pro.app/Contents/PlugIns/InternalFiltersXPC.pluginkit/Contents/PlugIns/Filters.bundle/Contents/Resources/English.lproj/Localizable.strings")
--  * translateInternalEffect("Draw Mask", "en")
function mod.mt:translateInternalEffect(input, locale)
    locale = localeID(locale)
    local context = {
        locale = locale.aliases
    }
    return self:effectStrings():find(input, context) or input
end

-- compareOldMethodToNewMethodResults() -> none
-- Function
-- Compares the new Scan Results to the original scan results stored in settings.
--
-- Parameters:
--  * None
--
-- Returns:
--  * None
function mod.mt:compareOldMethodToNewMethodResults(locale)
    locale = localeID(locale)

    --------------------------------------------------------------------------------
    -- Debug Message:
    --------------------------------------------------------------------------------
    report("-----------------------------------------------------------")
    report(" COMPARING RESULTS TO THE RESULTS STORED IN YOUR SETTINGS:")
    report("-----------------------------------------------------------\n")

    --------------------------------------------------------------------------------
    -- Plugin Types:
    --------------------------------------------------------------------------------
    local pluginTypes = {
        ["AudioEffects"] = mod.types.audioEffect,
        ["VideoEffects"] = mod.types.videoEffect,
        ["Transitions"] = mod.types.transition,
        ["Generators"] = mod.types.generator,
        ["Titles"] = mod.types.title,
    }

    --------------------------------------------------------------------------------
    -- Begin Scan:
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    -- Debug Message:
    --------------------------------------------------------------------------------
    report("---------------------------------------------------------")
    report(" CHECKING LOCALE: %s", locale.code)
    report("---------------------------------------------------------")

    for oldType,newType in pairs(pluginTypes) do
        --------------------------------------------------------------------------------
        -- Get settings from GUI Scripting Results:
        --------------------------------------------------------------------------------
        local oldPlugins = config.get(locale.code .. ".all" .. oldType)

        if oldPlugins then

            --------------------------------------------------------------------------------
            -- Debug Message:
            --------------------------------------------------------------------------------
            report(" - Checking Plugin Type: %s", oldType)

            local newPlugins = self._plugins[locale.code][newType]
            local newPluginNames = {}
            if newPlugins then
                for _,plugin in ipairs(newPlugins) do
                    local name = plugin.name
                    local plugins = newPluginNames[name]
                    if not plugins then
                        plugins = {
                            matched = {},
                            unmatched = {},
                            partials = {},
                        }
                        newPluginNames[name] = plugins
                    end
                    insert(plugins.unmatched, plugin)
                end
            end

            --------------------------------------------------------------------------------
            -- Compare Results:
            --------------------------------------------------------------------------------
            local errorCount = 0
            for _, oldFullName in pairs(oldPlugins) do
                local oldTheme, oldName = string.match(oldFullName, "^(.-) %- (.+)$")
                oldName = oldName or oldFullName
                newPlugins = newPluginNames[oldFullName] or newPluginNames[oldName]
                if not newPlugins then
                    report("  - ERROR: Missing %s: %s", oldType, oldFullName)
                    errorCount = errorCount + 1
                else
                    local unmatched = newPlugins.unmatched
                    local found = false
                    for i,plugin in ipairs(unmatched) do
                        -- report("  - INFO:  Checking plugin: %s (%s)", plugin.name, plugin.theme)
                        if plugin.theme == oldTheme then
                            -- report("  - INFO:  Exact match for plugin: %s (%s)", oldName, oldTheme)
                            insert(newPlugins.matched, plugin)
                            remove(unmatched, i)
                            found = true
                            break
                        end
                    end
                    if not found then
                        -- report("  - INFO:  Partial for '%s' plugin.", oldFullName)
                        insert(newPlugins.partials, oldFullName)
                    end
                end
            end

            for _, plugins in pairs(newPluginNames) do
                if #plugins.partials ~= #plugins.unmatched then
                    for _,oldFullName in ipairs(plugins.partials) do
                        report("  - ERROR: Old %s plugin unmatched: %s", newType, oldFullName)
                        errorCount = errorCount + 1
                    end

                    for _,plugin in ipairs(plugins.unmatched) do
                        local newFullName = plugin.name
                        if plugin.theme then
                            newFullName = plugin.theme .." - "..newFullName
                        end
                        report("  - ERROR: New %s plugin unmatched: %s\n\t\t%s", newType, newFullName, plugin.path)
                        errorCount = errorCount + 1
                    end
                end
            end

            --------------------------------------------------------------------------------
            -- If all results matched:
            --------------------------------------------------------------------------------
            if errorCount == 0 then
                report("  - SUCCESS: %s all matched!\n", oldType)
            else
                report("")
            end
        else
            report(" - SKIPPING: Could not find settings for: %s (%s)", oldType, locale.code)
        end
    end
end

--- cp.apple.finalcutpro.plugins:app() -> plugins
--- Method
--- Returns the `cp.apple.finalcutpro` object.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The `cp.apple.finalcutpro` object.
function mod.mt:app()
    return self._app
end

--- cp.apple.finalcutpro.plugins:init() -> plugins
--- Method
--- Initialises the module.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The plugins object.
function mod.mt:init()

    --------------------------------------------------------------------------------
    -- Define Soundtrack Pro EDEL Effects Paths:
    --------------------------------------------------------------------------------
    self.appEdelEffectPaths = {
        fcpApp:path() .. "/Contents/Frameworks/Flexo.framework/PlugIns/Audio/EDEL.bundle/Contents/Resources/Plug-In Settings"
    }

    --------------------------------------------------------------------------------
    -- Add Final Cut Pro 10.4 Specific Effects:
    --------------------------------------------------------------------------------
    local version = fcpApp:version()
    if version and version >= v("10.4") then
        mod.appBuiltinPlugins[mod.types.videoEffect]["FFEffectCategoryColor"] = { "FFCorrectorColorBoard", "PAEColorCurvesEffectDisplayName", "PAECorrectorEffectDisplayName", "PAELUTEffectDisplayName", "HDRTools::Filter Name", "PAEHSCurvesEffectDisplayName" }
    end

    return self
end

--- cp.apple.finalcutpro.plugins:ofType(type[, locale]) -> table
--- Method
--- Finds the plugins of the specified type (`types.videoEffect`, etc.) and if provided, locale.
---
--- Parameters:
---  * `type`        - The plugin type. See `types` for the complete list.
---  * `locale`    - The locale code to search for (e.g. "en"). Defaults to the current FCPX langauge.
---
--- Returns:
---  * A table of the available plugins of the specified type.
function mod.mt:ofType(type, locale)
    locale = localeID(locale)
    local plugins = self._plugins
    local bestLocale = fcpApp:bestSupportedLocale(locale) or fcpApp:currentLocale()
    if not bestLocale then
        log.wf("Unsupported locale was requested: %s", locale.code)
        return nil
    end

    if not plugins or not plugins[bestLocale.code] then
        plugins = self:scan(bestLocale)
    else
        plugins = plugins[bestLocale.code]
    end
    return plugins and plugins[type]
end

--- cp.apple.finalcutpro.plugins:videoEffects([locale]) -> table
--- Method
--- Finds the 'video effect' plugins.
---
--- Parameters:
---  * `locale`    - The locale code to search for (e.g. "en"). Defaults to the current FCPX langauge.
---
--- Returns:
---  * A table of the available plugins.
function mod.mt:videoEffects(locale)
    locale = localeID(locale)
    return self:ofType(mod.types.videoEffect, locale)
end

--- cp.apple.finalcutpro.plugins:audioEffects([locale]) -> table
--- Method
--- Finds the 'audio effect' plugins.
---
--- Parameters:
---  * `locale`    - The locale code to search for (e.g. "en"). Defaults to the current FCPX langauge.
---
--- Returns:
---  * A table of the available plugins.
function mod.mt:audioEffects(locale)
    locale = localeID(locale)
    return self:ofType(mod.types.audioEffect, locale)
end

--- cp.apple.finalcutpro.plugins:titles([locale]) -> table
--- Method
--- Finds the 'title' plugins.
---
--- Parameters:
---  * `locale`    - The locale code to search for (e.g. "en"). Defaults to the current FCPX langauge.
---
--- Returns:
---  * A table of the available plugins.
function mod.mt:titles(locale)
    locale = localeID(locale)
    return self:ofType(mod.types.title, locale)
end

--- cp.apple.finalcutpro.plugins:transitions([locale]) -> table
--- Method
--- Finds the 'transitions' plugins.
---
--- Parameters:
--- * `locale`    - The locale code to search for (e.g. "en"). Defaults to the current FCPX langauge.
---
--- Returns:
--- * A table of the available plugins.
function mod.mt:transitions(locale)
    locale = localeID(locale)
    return self:ofType(mod.types.transition, locale)
end

--- cp.apple.finalcutpro.plugins:generators([locale]) -> table
--- Method
--- Finds the 'generator' plugins.
---
--- Parameters:
---  * `locale`    - The locale code to search for (e.g. "en"). Defaults to the current FCPX langauge.
---
--- Returns:
---  * A table of the available plugins.
function mod.mt:generators(locale)
    locale = localeID(locale)
    return self:ofType(mod.types.generator, locale)
end

--- cp.apple.finalcutpro.plugins:scanAppBuiltInPlugins([locale]) -> None
--- Method
--- Scan Built In Plugins.
---
--- Parameters:
---  * `locale`    - The `cp.i18n.localeID` code to search for. Defaults to the current FCPX langauge.
---
--- Returns:
---  * None
function mod.mt:scanAppBuiltInPlugins(locale)
    locale = localeID(locale)
    --------------------------------------------------------------------------------
    -- Add Supported locales, Plugin Types & Built-in Effects to Results Table:
    --------------------------------------------------------------------------------
    for pluginType,categories in pairs(mod.appBuiltinPlugins) do
        for category,plugins in pairs(categories) do
            category = self:translateInternalEffect(category, locale)
            for _,plugin in pairs(plugins) do
                self:registerPlugin(nil, pluginType, category, nil, self:translateInternalEffect(plugin, locale), locale)
            end
        end
    end
end

-- cp.apple.finalcutpro.plugins:_loadPluginVersionCache(rootPath, version, locale, searchHistory) -> boolean
-- Method
-- Tries to load the cached plugin list from the specified root path. It will search previous version history if enabled and available.
--
-- Parameters:
--  * `rootPath`         - The path the version folders are stored under.
--  * `version`          - The FCPX version number.
--  * `locale`         - The locale to load.
--  * `searchHistory`    - If `true`, previous versions of this minor version will be searched.
--
-- Notes:
--  * When `searchHistory` is `true`, it will only search to the `0` patch level. E.g. `10.3.2` will stop searching at `10.3.0`.
function mod.mt:_loadPluginVersionCache(rootPath, version, locale, searchHistory)
    locale = localeID(locale)
    version = type(version) == "string" and v(version) or version
    local filePath = fs.pathToAbsolute(string.format("%s/%s/plugins.%s.json", rootPath, version, locale.code))
    if filePath then
        local file = io.open(filePath, "r")
        if file then
            local content = file:read("*all")
            file:close()
            local result = json.decode(content)
            self._plugins[locale.code] = result
            return result ~= nil
        end
    elseif searchHistory and version.patch > 0 then
        return self:_loadPluginVersionCache(rootPath, v(version.major, version.minor, version.patch-1), locale, searchHistory)
    end
    return false
end

local USER_PLUGIN_CACHE = "~/Library/Caches/org.latenitefilms.CommandPost/FinalCutPro"
local CP_PLUGIN_CACHE   = config.scriptPath .. "/cp/apple/finalcutpro/plugins/cache"

--- cp.apple.finalcutpro.plugins.clearCaches() -> boolean
--- Function
--- Clears any local caches created for tracking the plugins.
---
--- Parameters:
---  * None
---
--- Returns:
---  * `true` if the caches have been cleared successfully.
---
--- Notes:
---  * Does not uninstall any of the actual plugins.
function mod.mt.clearCaches()
    local cachePath = fs.pathToAbsolute(USER_PLUGIN_CACHE)
    if cachePath then
        local ok, err = tools.rmdir(cachePath, true)
        if not ok then
            log.ef("Unable to remove user plugin cache: %s", err)
            return false
        end
    end
    config.set("audioUnitsCacheModification", nil)
    config.set("audioUnitsCache", nil)
    config.set("userEffectsPresetsCacheModification", nil)
    config.set("userEffectsPresetsCache", nil)
    config.set("userMotionTemplatesCache", nil)
    config.set("userMotionTemplatesCacheSize", nil)
    config.set("systemMotionTemplatesCache", nil)
    config.set("systemMotionTemplatesCacheSize", nil)
    return true
end

-- cp.apple.finalcutpro.plugins:_loadAppPluginCache(locale) -> boolean
-- Method
-- Attempts to load the app-bundled plugin list from the cache.
--
-- Parameters:
--  * `locale` - The localeID to load for.
--
-- Returns:
--  * `true` if the cache was loaded successfully.
function mod.mt:_loadAppPluginCache(locale)
    locale = localeID(locale)
    local fcpVersion = fcpApp:versionString()
    if not fcpVersion then
        return false
    end

    return self:_loadPluginVersionCache(USER_PLUGIN_CACHE, fcpVersion, locale, false)
        or self:_loadPluginVersionCache(CP_PLUGIN_CACHE, fcpVersion, locale, true)
end

-- ensureDirectoryExists(rootPath, ...) -> string | nil
-- Function
-- Ensures all steps on a provided path exist. If not, attempts to create them.
-- If it fails, `nil` is returned.
--
-- Parameters:
--  * `rootPath` - The root path (should already exist).
--  * `...`      - The list of path steps to create
--
-- Returns:
--  * The full path, if it exists, or `nil` if unable to create the directory for some reason.
local function ensureDirectoryExists(rootPath, ...)
    local fullPath = rootPath
    for _,path in ipairs(table.pack(...)) do
        fullPath = fullPath .. "/" .. path
        if not fs.pathToAbsolute(fullPath) then
            local success, err = fs.mkdir(fullPath)
            if not success then
                log.ef("Problem ensuring that '%s' exists: %s", fullPath, err)
                return nil
            end
        end
    end
    return fs.pathToAbsolute(fullPath)
end

-- cp.apple.finalcutpro.plugins:_saveAppPluginCache(locale) -> boolean
-- Method
-- Saves the current plugin cache as the 'app-bundled' cache.
--
-- Note: This should only be called before any system or user level plugins are loaded!
--
-- Parameters:
--  * `locale`     The locale
--
-- Returns:
--  * `true` if the cache was saved successfully.
function mod.mt:_saveAppPluginCache(locale)
    locale = localeID(locale)
    report("  * Saving App Plugin Cache.")
    local fcpVersion = fcpApp:version()
    if not fcpVersion then
        log.ef("Failed to detect Final Cut Pro version: %s", fcpVersion)
        return false
    end
    local version = tostring(fcpVersion)
    if not version then
        log.ef("Failed to translate Final Cut Pro version: %s", version)
        return false
    end
    local path = ensureDirectoryExists("~/Library/Caches", "org.latenitefilms.CommandPost", "FinalCutPro", version)
    if not path then
        return false
    end
    local cachePath = path .. "/plugins."..locale.code..".json"
    local plugins = self._plugins[locale.code]
    if plugins then
        local file = io.open(cachePath, "w")
        if file then
            file:write(json.encode(plugins))
            file:close()
            return true
        end
    else
        --------------------------------------------------------------------------------
        -- Remove it:
        --------------------------------------------------------------------------------
        os.remove(cachePath)
    end
    return false
end

-- cp.apple.finalcutpro.plugins:scanAppPlugins(locale) -> none
-- Method
-- Scans App Plugins for a specific locale.
--
-- Parameters:
--  * locale - The locale you want to scan for.
--
-- Returns:
--  * None
function mod.mt:scanAppPlugins(locale)
    locale = localeID(locale)
    --------------------------------------------------------------------------------
    -- First, try loading from the cache:
    --------------------------------------------------------------------------------
    local cacheStartTime = os.clock()
    if not self:_loadAppPluginCache(locale) then

        --------------------------------------------------------------------------------
        -- Scan Built-in Plugins:
        --------------------------------------------------------------------------------
        local startTime = os.clock()
        self:scanAppBuiltInPlugins(locale)
        local finishTime = os.clock()
        report("  * scanAppBuiltInPlugins(%s): %s", locale.code, finishTime-startTime)

        --------------------------------------------------------------------------------
        -- Scan Soundtrack Pro EDEL Effects:
        --------------------------------------------------------------------------------
        startTime = os.clock()
        self:scanAppEdelEffects(locale)
        finishTime = os.clock()
        report("  * scanAppEdelEffects(%s): %s", locale.code, finishTime-startTime)

        --------------------------------------------------------------------------------
        -- Scan Audio Effect Bundles:
        --------------------------------------------------------------------------------
        startTime = os.clock()
        self:scanAppAudioEffectBundles(locale)
        finishTime = os.clock()
        report("  * scanAppAudioEffectBundles(%s): %s", locale.code, finishTime-startTime)

        --------------------------------------------------------------------------------
        -- Scan App Motion Templates:
        --------------------------------------------------------------------------------
        startTime = os.clock()
        self:scanAppMotionTemplates(locale)
        finishTime = os.clock()
        report("   * scanAppMotionTemplates(%s): %s", locale.code, finishTime-startTime)

        self:_saveAppPluginCache(locale)
    else
        local cacheFinishTime = os.clock()
        report("  * Loaded App Plugins from Cache: %s", cacheFinishTime-cacheStartTime)
    end

end

-- cp.apple.finalcutpro.plugins:scanSystemPlugins(locale) -> none
-- Method
-- Scans System Plugins for a specific locale.
--
-- Parameters:
--  * locale - The locale code you want to scan for.
--
-- Returns:
--  * None
function mod.mt:scanSystemPlugins(locale)
    locale = localeID(locale)
    --------------------------------------------------------------------------------
    -- Scan System-level Motion Templates:
    --------------------------------------------------------------------------------
    local startTime = os.clock()
    self:scanSystemMotionTemplates(locale)
    local finishTime = os.clock()
    report("  * scanSystemMotionTemplates(%s): %s", locale, finishTime-startTime)

    --------------------------------------------------------------------------------
    -- Scan System Audio Units:
    --------------------------------------------------------------------------------
    startTime = os.clock()
    self:scanSystemAudioUnits(locale)
    finishTime = os.clock()
    report("  * scanSystemAudioUnits(%s): %s", locale, finishTime-startTime)

end

-- cp.apple.finalcutpro.plugins:scanUserPlugins(locale) -> none
-- Method
-- Scans User Plugins for a specific locale.
--
-- Parameters:
--  * locale - The locale code you want to scan for.
--
-- Returns:
--  * None
function mod.mt:scanUserPlugins(locale)
    locale = localeID(locale)
    --------------------------------------------------------------------------------
    -- Scan User Effect Presets:
    --------------------------------------------------------------------------------
    local startTime = os.clock()
    self:scanUserEffectsPresets(locale)
    local finishTime = os.clock()
    report("  * scanUserEffectsPresets(%s): %s", locale, finishTime-startTime)

    --------------------------------------------------------------------------------
    -- Scan User Motion Templates:
    --------------------------------------------------------------------------------
    startTime = os.clock()
    self:scanUserMotionTemplates(locale)
    finishTime = os.clock()
    report("  * scanUserMotionTemplates(%s): %s", locale, finishTime-startTime)

end

--- cp.apple.finalcutpro.plugins:scan() -> none
--- Function
--- Scans Final Cut Pro for Effects, Transitions, Generators & Titles
---
--- Parameters:
---  * fcp - the `cp.apple.finalcutpro` instance
---
--- Returns:
---  * None
function mod.mt:scan(locale)

    locale = localeID(locale) or fcpApp:currentLocale()

    --------------------------------------------------------------------------------
    -- Reset Results Table:
    --------------------------------------------------------------------------------
    self:reset()

    --------------------------------------------------------------------------------
    -- Debug Messaging:
    --------------------------------------------------------------------------------
    report("---------------------------------------------------------")
    report("FINAL CUT PRO PLUGIN SCANNER:")
    report("---------------------------------------------------------")

    --------------------------------------------------------------------------------
    -- Scan app-bundled plugins:
    --------------------------------------------------------------------------------
    report("* Scanning app-bundled plugins:")
    local startTime = os.clock()
    self:scanAppPlugins(locale)
    local finishTime = os.clock()
    report("    * scanAppPlugins(%s) took: %s", locale.code, finishTime-startTime)

    --------------------------------------------------------------------------------
    -- Scan system-installed plugins:
    --------------------------------------------------------------------------------
    report(" ")
    report("* Scanning system-installed plugins:")
    startTime = os.clock()
    self:scanSystemPlugins(locale)
    finishTime = os.clock()
    report("    * scanSystemPlugins(%s) took: %s", locale, finishTime-startTime)

    --------------------------------------------------------------------------------
    -- Scan user-installed plugins:
    --------------------------------------------------------------------------------
    report(" ")
    report("* Scanning user-installed plugins:")
    startTime = os.clock()
    self:scanUserPlugins(locale)
    finishTime = os.clock()
    report("    * scanUserPlugins(%s) took: %s", locale, finishTime-startTime)

    --------------------------------------------------------------------------------
    -- Debug Messaging:
    --------------------------------------------------------------------------------
    report("---------------------------------------------------------")

    return self._plugins[locale]

end

--- cp.apple.finalcutpro.plugins:scanAll() -> nil
--- Method
--- Scans all supported locales, loading them into memory.
---
--- Parameters:
---  * None
---
--- Returns:
---  * Nothing
function mod.mt:scanAll()
    for _,locale in ipairs(fcpApp:supportedLocales()) do
        self:scan(locale)
    end
end

--- cp.apple.finalcutpro.plugins:watch(events) -> watcher
--- Method
--- Adds a watcher for the provided events table.
---
--- Parameters:
---  * events - A table of events to watch.
---
--- Returns:
---  * The watcher object
---
--- Notes:
---  * The events can be:
---  ** videoEffects
---  ** audioEffects
---  ** transitions
---  ** titles
---  ** generators
function mod.mt:watch(events)
    return self._watcher:watch(events)
end

--- cp.apple.finalcutpro.plugins:unwatch(id) -> watcher
--- Method
--- Unwatches a watcher with a specific ID.
---
--- Parameters:
---  * id - The ID of the watcher to stop watching.
---
--- Returns:
---  * The watcher object.
function mod.mt:unwatch(a)
    return self._watcher:unwatch(a)
end

--- cp.apple.finalcutpro.plugins.new(fcp) -> plugins object
--- Function
--- Creates a new Plugins Object.
---
--- Parameters:
---  * fcp - The `cp.apple.finalcutpro` object
---
--- Returns:
---  * The plugins object
function mod.new(fcp)
    local o = {
        _app = fcp,
        _plugins = {},
        _watcher = watcher.new("videoEffects", "audioEffects", "transitions", "titles", "generators"),
    }
    return setmetatable(o, mod.mt):init()
end

--------------------------------------------------------------------------------
-- Ensures the cache is cleared if the config is reset:
--------------------------------------------------------------------------------
config.watch({
    reset = mod.mt.clearCaches,
})

return mod