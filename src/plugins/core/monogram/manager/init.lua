--- === plugins.core.monogram.manager ===
---
--- Monogram Manager Plugin.

local require                   = require

local log                       = require "hs.logger".new "monogram"

local application               = require "hs.application"
local inspect                   = require "hs.inspect"
local socket                    = require "hs.socket"
local task                      = require "hs.task"
local udp                       = require "hs.socket.udp"

local config                    = require "cp.config"
local json                      = require "cp.json"
local tools                     = require "cp.tools"

local doesDirectoryExist        = tools.doesDirectoryExist
local execute                   = _G.hs.execute
local infoForBundleID           = application.infoForBundleID
local launchOrFocusByBundleID   = application.launchOrFocusByBundleID
local playErrorSound            = tools.playErrorSound

local mod = {}

-- UDP_PORT -> number
-- Constant
-- The port to setup the UDP server on.
local UDP_PORT = 51234

-- MONOGRAM_CREATOR_BUNDLE_ID -> string
-- Constant
-- The Monogram Creator Bundle ID.
local MONOGRAM_CREATOR_BUNDLE_ID = "com.monogramcc.Monogram-Creator"

-- MONOGRAM_CREATOR_DOWNLOAD_URL -> string
-- Constant
-- The Monogram Creator Download URL.
local MONOGRAM_CREATOR_DOWNLOAD_URL = "https://monogramcc.com/download/beta/"

-- MONOGRAM_CREATOR_INTEGRATIONS_PATH -> string
-- Constant
-- The Monogram Creators Integration Path.
local MONOGRAM_CREATOR_INTEGRATIONS_PATH = os.getenv("HOME") .. "/Library/Application Support/Monogram/Service/integrations"

--- plugins.core.monogram.manager.NUMBER_OF_FAVOURITES -> number
--- Constant
--- Number of favourites
mod.NUMBER_OF_FAVOURITES = 20

--- plugins.core.monogram.manager.favourites <cp.prop: table>
--- Variable
--- A `cp.prop` that that contains all the Monogram Favourites.
mod.favourites = json.prop(os.getenv("HOME") .. "/Library/Application Support/CommandPost/", "Monogram", "Favourites.cpMonogram", {})

--- plugins.core.monogram.manager.lastPort -> number
--- Variable
--- The port that Monogram Creator used to connect to CommandPost.
mod.lastPort = 59178

-- getMonogramCreatorBundleID() -> string
-- Function
-- Returns the Monogram Creator Bundle ID. It first tries to find a running version
-- of Monogram Creator, and if none is running then checks for installations of the
-- Internal release, then Alpha, then Beta, then public release.
--
-- Parameters:
--  * None
--
-- Returns:
--  * The bundle ID as a string, or `nil` if Monogram Creator is not installed.
local function getMonogramCreatorBundleID()
    if application.get(MONOGRAM_CREATOR_BUNDLE_ID .. "-Internal") then
        return MONOGRAM_CREATOR_BUNDLE_ID .. "-Internal"
    elseif application.get(MONOGRAM_CREATOR_BUNDLE_ID .. "-Alpha") then
        return MONOGRAM_CREATOR_BUNDLE_ID .. "-Alpha"
    elseif application.get(MONOGRAM_CREATOR_BUNDLE_ID .. "-Beta") then
        return MONOGRAM_CREATOR_BUNDLE_ID .. "-Beta"
    elseif application.get(MONOGRAM_CREATOR_BUNDLE_ID) then
        return MONOGRAM_CREATOR_BUNDLE_ID
    elseif infoForBundleID(MONOGRAM_CREATOR_BUNDLE_ID .. "-Internal") then
        return MONOGRAM_CREATOR_BUNDLE_ID .. "-Internal"
    elseif infoForBundleID(MONOGRAM_CREATOR_BUNDLE_ID .. "-Alpha") then
        return MONOGRAM_CREATOR_BUNDLE_ID .. "-Alpha"
    elseif infoForBundleID(MONOGRAM_CREATOR_BUNDLE_ID .. "-Beta") then
        return MONOGRAM_CREATOR_BUNDLE_ID .. "-Beta"
    elseif infoForBundleID(MONOGRAM_CREATOR_BUNDLE_ID) then
        return MONOGRAM_CREATOR_BUNDLE_ID
    end
end

--- plugins.core.monogram.manager.performAction -> table
--- Variable
--- A table of actions that are triggered by the callback function.
mod.performAction = {}

--- plugins.core.monogram.manager.plugins -> table
--- Variable
--- A table of Monogram plugins to install.
mod.plugins = {}

--- plugins.core.monogram.manager.registerPlugin(name, path) -> none
--- Function
--- Registers a new Monogram plugin.
---
--- Parameters:
---  * name - The name of the plugin.
---  * path - The path to the folder containing the plugin.
---
--- Returns:
---  * None
function mod.registerPlugin(name, path)
    mod.plugins[name] = path
end

--- plugins.core.monogram.manager.registerAction(name, fn) -> none
--- Function
--- Registers a new Monogram Action.
---
--- Parameters:
---  * name - The name of the plugin.
---  * fn - The function to trigger.
---
--- Returns:
---  * None
function mod.registerAction(name, fn)
    mod.performAction[name] = fn
end

-- callbackFn(data) -> none
-- Function
-- The callback function triggered by the UDP socket.
--
-- Parameters:
--  * data - The data read from the socket as a string
--
-- Returns:
--  * None
local function callbackFn(data, sockAddress)
    if data then
        local decodedData = json.decode(data)
        local action = mod.performAction[decodedData.input]
        if action then
            action(decodedData)
        else
            log.ef("Unknown Monogram Message:\n%s\n%s", decodedData and inspect(decodedData))
        end

        --------------------------------------------------------------------------------
        -- Get the Monogram port so we can send messages back:
        --------------------------------------------------------------------------------
        local address = socket.parseAddress(sockAddress)
        mod.lastPort = address.port
    end
end

--- plugins.core.monogram.manager.launchCreatorBundle() -> none
--- Function
--- Launch the Monogram Creator.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function mod.launchCreatorBundle()
    local bundleID = getMonogramCreatorBundleID()
    if bundleID then
        launchOrFocusByBundleID(bundleID)
    end
end

--- plugins.core.monogram.manager.launchCreatorBundle() -> none
--- Function
--- Launch the Monogram Creator.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function mod.openDownloadMonogramCreatorURL()
    execute("open " .. MONOGRAM_CREATOR_DOWNLOAD_URL)
end

-- setupPlugin() -> none
-- Function
-- Copies Monogram Plugins from CommandPost application bundle to
-- the Application Support folder, then adds the paths to Monogram
-- Creator's preferences file.
--
-- Parameters:
--  * None
--
-- Returns:
--  * None
local function setupPlugins()
    for pluginName, sourcePath in pairs(mod.plugins) do
        local destination = MONOGRAM_CREATOR_INTEGRATIONS_PATH .."/" .. pluginName .. ".palette/signature.txt"
        local source = sourcePath .. pluginName .. ".palette/signature.txt"
        task.new("/usr/bin/diff", function(exitCode, _, _)
            if exitCode ~= 0 then
                log.df("Updating Monogram Creator Intergration: %s", pluginName)
                task.new("/bin/cp", function(copyExitCode, stdOut, stdErr)
                    if copyExitCode ~= 0 then
                        log.ef("Failed to update Monogram Integration: %s", pluginName)
                        log.df(" - exitCode: '%s', %s", exitCode, type(exitCode))
                        log.df(" - stdOut: '%s', %s", stdOut, type(stdOut))
                        log.df(" - stdErr: '%s', %s", stdErr, type(stdErr))
                    end
                end, {"-R", sourcePath .. pluginName .. ".palette/", MONOGRAM_CREATOR_INTEGRATIONS_PATH .. "/" .. pluginName .. ".palette/"}):start()
            end
        end, {source, destination}):start()
    end
end

-- removePlugins() -> none
-- Function
-- Deletes Monogram Plugins.
--
-- Parameters:
--  * None
--
-- Returns:
--  * None
local function removePlugins()
    for pluginName, _ in pairs(mod.plugins) do
        local path = MONOGRAM_CREATOR_INTEGRATIONS_PATH .."/" .. pluginName .. ".palette/"
        if doesDirectoryExist(path) then
            task.new("/bin/rm", function(exitCode, stdOut, stdErr)
                if exitCode ~= 0 then
                    log.ef("Failed to delete Monogram Integration: %s", pluginName)
                    log.df(" - exitCode: '%s', %s", exitCode, type(exitCode))
                    log.df(" - stdOut: '%s', %s", stdOut, type(stdOut))
                    log.df(" - stdErr: '%s', %s", stdErr, type(stdErr))
                end
            end, {"-rf", path}):start()
        end
    end
end

--- plugins.core.monogram.manager.enabled <cp.prop: boolean>
--- Field
--- Enable or disable Monogram Support.
mod.enabled = config.prop("monogram.enabled", false):watch(function(enabled)
    if enabled then
        mod.server = udp.server(UDP_PORT):receive(callbackFn)
    else
        if mod.server then
            mod.server:close()
            mod.server = nil
        end
    end
end)

--- plugins.core.monogram.manager.automaticProfileSwitching <cp.prop: boolean>
--- Field
--- Enable or disable Automatic Profile Switching
mod.automaticProfileSwitching = config.prop("monogram.automaticProfileSwitching", false)

--- plugins.core.monogram.manager.setEnabled(enabled) -> none
--- Function
--- Enables or disables Monogram Support.
---
--- Parameters:
---  * enabled - A boolean
---
--- Returns:
---  * `true` if Monogram support is enabled, otherwise `false`
function mod.setEnabled(enabled)
    if enabled then
        setupPlugins()
        mod.enabled(true)
    else
        removePlugins()
        mod.enabled(false)
    end
    return mod.enabled()
end

--- plugins.core.monogram.manager.changeContext(context) -> none
--- Function
--- Switches the Monogram Profile.
---
--- Parameters:
---  * context - The name of the context you want to switch to.
---
--- Returns:
---  * None
function mod.changeContext(context)
    if mod.enabled() then
        local m = {
            ["command"] = {
                ["commandString"] = "changeContext",
                ["context"] = context,
            }
        }
        local message = json.encode(m)
        mod.server:send(message, "127.0.0.1", mod.lastPort)
    end
end

--- plugins.core.monogram.manager.sign() -> none
--- Function
--- Signs all the Monogram Integrations.
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function mod.sign()
    local basePath = config.basePath
    local appPath = basePath .. "/../../monogramsign"
    local secretPath = basePath .. "/../../command_post.key"
    for pluginName, sourcePath in pairs(mod.plugins) do
        local pluginPath = sourcePath .. pluginName .. ".palette"
        local cmd = appPath .. [[ "]] .. pluginPath .. [[" -k "]] .. secretPath .. [["]]
        local _, status = execute(cmd)
        if not status then
            log.ef("Failed to sign: %s", pluginName)
        else
            log.df("Successfully signed: %s", pluginName)
        end
    end
    setupPlugins()
end

local plugin = {
    id          = "core.monogram.manager",
    group       = "core",
    required    = true,
    dependencies    = {
        ["core.action.manager"] = "actionManager",
    }
}

function plugin.init(deps)
    --------------------------------------------------------------------------------
    -- Register favourites:
    --------------------------------------------------------------------------------
    for i=1, mod.NUMBER_OF_FAVOURITES do
        mod.registerAction("CommandPost Favourites.Favourite " .. string.format("%02d", i), function()
            local faves = mod.favourites()
            local fave = faves[tostring(i)]
            if fave then
                local handler = deps.actionManager.getHandler(fave.handlerID)
                if handler then
                    if not handler:execute(fave.action) then
                        log.ef("Unable to execute Monogram Favourite #%s: %s", i, fave and inspect(fave))
                    end
                else
                    log.ef("Unable to find handler to execute Monogram Favourite #%s: %s", i, fave and inspect(fave))
                end
            else
                log.ef("No action is assigned to the favourite in the Monogram Control Surfaces Panel in CommandPost.")
                playErrorSound()
            end
        end)
    end

    return mod
end

function plugin.postInit()
    mod.enabled:update()
    if mod.enabled() then
        setupPlugins()
    end
end

return plugin
