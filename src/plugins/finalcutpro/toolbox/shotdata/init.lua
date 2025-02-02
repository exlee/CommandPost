--- === plugins.finalcutpro.toolbox.shotdata ===
---
--- Shot Data Toolbox Panel.

local require                   = require

local log                       = require "hs.logger".new "shotdata"

local hs                        = _G.hs

local dialog                    = require "hs.dialog"
local eventtap                  = require "hs.eventtap"
local fnutils                   = require "hs.fnutils"
local image                     = require "hs.image"
local inspect                   = require "hs.inspect"
local menubar                   = require "hs.menubar"
local mouse                     = require "hs.mouse"
local task                      = require "hs.task"
local timer                     = require "hs.timer"

local config                    = require "cp.config"
local fcp                       = require "cp.apple.finalcutpro"
local fcpxml                    = require "cp.apple.fcpxml"
local i18n                      = require "cp.i18n"
local json                      = require "cp.json"
local tools                     = require "cp.tools"

local xml                       = require "hs._asm.xml"

local chooseFileOrFolder        = dialog.chooseFileOrFolder
local copy                      = fnutils.copy
local doAfter                   = timer.doAfter
local doesDirectoryExist        = tools.doesDirectoryExist
local doesFileExist             = tools.doesFileExist
local ensureDirectoryExists     = tools.ensureDirectoryExists
local execute                   = hs.execute
local getFileExtensionFromPath  = tools.getFileExtensionFromPath
local getFilenameFromPath       = tools.getFilenameFromPath
local imageFromPath             = image.imageFromPath
local removeFilenameFromPath    = tools.removeFilenameFromPath
local replace                   = tools.replace
local spairs                    = tools.spairs
local split                     = tools.split
local tableContains             = tools.tableContains
local tableCount                = tools.tableCount
local trim                      = tools.trim
local webviewAlert              = dialog.webviewAlert
local writeToFile               = tools.writeToFile

local mod = {}

-- SHOT_DATA_MANUAL_URL -> string
-- Constant
-- URL to the Shot Data Manual
local SHOT_DATA_USER_GUIDE_URL = "https://help.commandpost.io/toolbox/shot_data"

-- NOTION_TEMPLATE_URL -> string
-- Constant
-- URL to the Notion Template
local NOTION_TEMPLATE_URL = "https://soothsayer.notion.site/1e6a317008e546159ca7015011cdb173?v=a1b16c2a1fa447138268a8f1fe515bd7"

-- NOTION_TOKEN_HELP_URL -> string
-- Constant
-- URL to Token Help
local NOTION_TOKEN_HELP_URL = "https://vzhd1701.notion.site/Find-Your-Notion-Token-5f57951434c1414d84ac72f88226eede"

-- NOTION_DATABASE_VIEW_HELP_URL -> string
-- Constant
-- URL to Database View Help
local NOTION_DATABASE_VIEW_HELP_URL = "https://github.com/vzhd1701/csv2notion/raw/master/examples/db_link.png"

-- TEMPLATE_NUMBER_OF_NODES -> number
-- Constant
-- The minimum number of nodes a Shot Data template will have.
-- This is used to detect if a title is actually a Shot Data template.
local TEMPLATE_NUMBER_OF_NODES = 128

-- DEFAULT_SCENE_PREFIX -> string
-- Constant
-- The default Scene Prefix value.
local DEFAULT_SCENE_PREFIX = "INT"

-- DEFAULT_SCENE_TIME -> string
-- Constant
-- The default Scene Time value.
local DEFAULT_SCENE_TIME = "Dawn"

-- DEFAULT_SHOT_SIZE_AND_TYPE -> string
-- Constant
-- The default Shot Size & Type value.
local DEFAULT_SHOT_SIZE_AND_TYPE = "WS"

-- DEFAULT_CAMERA_ANGLE -> string
-- Constant
-- The default camera angle value.
local DEFAULT_CAMERA_ANGLE = "Eye Line"

-- DEFAULT_FLAG -> string
-- Constant
-- The default flag value.
local DEFAULT_FLAG = "false"

-- TEMPLATE_ORDER -> table
-- Constant
-- A table containing the order of the headings when exporting to a CSV.
local TEMPLATE_ORDER = {
    [1]     = "Shot ID",
    [2]     = "Shot Number",
    [3]     = "Scene Location",
    [4]     = "Shot Duration",
    [5]     = "Scene Number",
    [6]     = "Scene Prefix",
    [7]     = "Scene Time",
    [8]     = "Scene Time Range",
    [9]     = "Scene Set",
    [10]    = "Script Page No.",
    [11]    = "Scene Characters",
    [12]    = "Scene Cast",
    [13]    = "Scene Description",
    [14]    = "Shot Size & Type",
    [15]    = "Camera Movement",
    [16]    = "Camera Angle",
    [17]    = "Equipment",
    [18]    = "Lens",
    [19]    = "Lighting Notes",
    [20]    = "VFX",
    [21]    = "VFX Description",
    [22]    = "SFX",
    [23]    = "SFX Description",
    [24]    = "Music Track",
    [25]    = "Production Design",
    [26]    = "Props",
    [27]    = "Props Notes",
    [28]    = "Wardrobe ID",
    [29]    = "Wardrobe Notes",
    [30]    = "Hair",
    [31]    = "Make Up",
    [32]    = "Flag",
    [33]    = "User Notes 1",
    [34]    = "User Notes 2",
    [35]    = "Start Date",
    [36]    = "End Date",
    [37]    = "Days",
    [38]    = "Image Filename"
}

-- TEMPLATE -> table
-- Constant
-- A table that contains all the fields of the Shot Data Motion Template.
local TEMPLATE = {
    [1]     = { label = "Shot Data",            ignore = true  },
    [2]     = { label = "Shot Number",          ignore = false },
    [3]     = { label = "Shot Number",          ignore = true  },
    [4]     = { label = "Scene Location",       ignore = false },
    [5]     = { label = "Scene Location",       ignore = true  },
    [6]     = { label = "Shot Duration",        ignore = false },
    [7]     = { label = "Shot Duration",        ignore = true  },
    [8]     = { label = "Script Data",          ignore = true  },
    [9]     = { label = "Scene Number",         ignore = false },
    [10]    = { label = "Scene Number",         ignore = true },
    [11]    = { label = "INT",                  ignore = true },
    [12]    = { label = "EXT",                  ignore = true },
    [13]    = { label = "I/E",                  ignore = true },
    [14]    = { label = "Scene Prefix",         ignore = true },
    [15]    = { label = "Dawn",                 ignore = true },
    [16]    = { label = "Dawn (Twilight)",      ignore = true },
    [17]    = { label = "Sunrise",              ignore = true },
    [18]    = { label = "Morning",              ignore = true },
    [19]    = { label = "Daytime",              ignore = true },
    [20]    = { label = "Evening",              ignore = true },
    [21]    = { label = "Sunset",               ignore = true },
    [22]    = { label = "Sunset",               ignore = true },
    [23]    = { label = "Dusk (Twilight)",      ignore = true },
    [24]    = { label = "Dusk",                 ignore = true },
    [25]    = { label = "Night",                ignore = true },
    [26]    = { label = "Scene Time",           ignore = true },
    [27]    = { label = "Scene Time Range",     ignore = false },
    [28]    = { label = "Scene Time Range",     ignore = true },
    [29]    = { label = "Scene Set",            ignore = false },
    [30]    = { label = "Scene Set",            ignore = true },
    [31]    = { label = "Script Page No.",      ignore = false },
    [32]    = { label = "Script Page No.",      ignore = true },
    [33]    = { label = "Scene Characters",     ignore = false },
    [34]    = { label = "Scene Characters",     ignore = true },
    [35]    = { label = "Scene Cast",           ignore = false },
    [36]    = { label = "Scene Cast",           ignore = true },
    [37]    = { label = "Scene Description",    ignore = false },
    [38]    = { label = "Scene Description",    ignore = true },
    [39]    = { label = "CAMERA & LENS DATA",   ignore = true },
    [40]    = { label = "WS",                   ignore = true },
    [41]    = { label = "MWS",                  ignore = true },
    [42]    = { label = "EWS",                  ignore = true },
    [43]    = { label = "Master",               ignore = true },
    [44]    = { label = "FS",                   ignore = true },
    [45]    = { label = "MFS",                  ignore = true },
    [46]    = { label = "Cowboy Shot",          ignore = true },
    [47]    = { label = "Medium",               ignore = true },
    [48]    = { label = "CU",                   ignore = true },
    [49]    = { label = "Choker",               ignore = true },
    [50]    = { label = "MCU",                  ignore = true },
    [51]    = { label = "ECU",                  ignore = true },
    [52]    = { label = "Cutaway",              ignore = true },
    [53]    = { label = "Cut-In",               ignore = true },
    [54]    = { label = "Zoom-In",              ignore = true },
    [55]    = { label = "Pan",                  ignore = true },
    [56]    = { label = "Two Shot",             ignore = true },
    [57]    = { label = "OTS",                  ignore = true },
    [58]    = { label = "POV",                  ignore = true },
    [59]    = { label = "Montage",              ignore = true },
    [60]    = { label = "CGI",                  ignore = true },
    [61]    = { label = "Weather Shot",         ignore = true },
    [62]    = { label = "Arial Shot",           ignore = true },
    [63]    = { label = "Shot Size & Type",     ignore = true },
    [64]    = { label = "Camera Movement",      ignore = false },
    [65]    = { label = "Camera Movement",      ignore = true },
    [66]    = { label = "Eye Level",            ignore = true },
    [67]    = { label = "High Angle",           ignore = true },
    [68]    = { label = "Low Angle",            ignore = true },
    [69]    = { label = "Shoulder Level",       ignore = true },
    [70]    = { label = "Hip Level",            ignore = true },
    [71]    = { label = "Knee Level",           ignore = true },
    [72]    = { label = "Ground Level",         ignore = true },
    [73]    = { label = "Dutch Angle/Tilt",     ignore = true },
    [74]    = { label = "POV",                  ignore = true },
    [75]    = { label = "Camera Angle",         ignore = true },
    [76]    = { label = "Equipment",            ignore = false },
    [77]    = { label = "Equipment",            ignore = true },
    [78]    = { label = "Lens",                 ignore = false },
    [79]    = { label = "Lens",                 ignore = true },
    [80]    = { label = "Lighting Notes",       ignore = false },
    [81]    = { label = "Lighting Notes",       ignore = true },
    [82]    = { label = "VFX DATA",             ignore = true },
    [83]    = { label = "No",                   ignore = true },
    [84]    = { label = "Yes",                  ignore = true },
    [85]    = { label = "VFX",                  ignore = true },
    [86]    = { label = "VFX Description",      ignore = false },
    [87]    = { label = "VFX Description",      ignore = true },
    [88]    = { label = "SOUND & MUSIC DATA",   ignore = true },
    [89]    = { label = "No",                   ignore = true },
    [90]    = { label = "Yes",                  ignore = true },
    [91]    = { label = "SFX",                  ignore = true },
    [92]    = { label = "SFX Description",      ignore = false },
    [93]    = { label = "SFX Description",      ignore = true },
    [94]    = { label = "Music Track",          ignore = false },
    [95]    = { label = "Music Track",          ignore = true },
    [96]    = { label = "ART DEPARTMENT DATA",  ignore = true },
    [97]    = { label = "Production Design",    ignore = false },
    [98]    = { label = "Production Design",    ignore = true },
    [99]    = { label = "Props",                ignore = false },
    [100]   = { label = "Props ID",             ignore = true },
    [101]   = { label = "Props Notes",          ignore = false },
    [102]   = { label = "Props Notes",          ignore = true },
    [103]   = { label = "Wardrobe ID",          ignore = true },
    [104]   = { label = "Wardrobe ID",          ignore = false },
    [105]   = { label = "Wardrobe Notes",       ignore = false },
    [106]   = { label = "Wardrobe Notes",       ignore = true },
    [107]   = { label = "HAIR & MAKE UP DATA",  ignore = true },
    [108]   = { label = "Hair",                 ignore = false },
    [109]   = { label = "Hair",                 ignore = true },
    [110]   = { label = "Make Up",              ignore = false },
    [111]   = { label = "Make Up",              ignore = true },
    [112]   = { label = "USER DATA",            ignore = true },
    [113]   = { label = "No",                   ignore = true },
    [114]   = { label = "Yes",                  ignore = true },
    [115]   = { label = "Flag",                 ignore = true },
    [116]   = { label = "User Notes 1",         ignore = false },
    [117]   = { label = "Notes 1",              ignore = true },
    [118]   = { label = "User Notes 2",         ignore = false },
    [119]   = { label = "Notes 2",              ignore = true },
    [120]   = { label = "SCHEDULE DATA",        ignore = true },
    [121]   = { label = "Start Date",           ignore = false },
    [122]   = { label = "Start Date",           ignore = true },
    [123]   = { label = "End Date",             ignore = false },
    [124]   = { label = "End Date",             ignore = true },
    [125]   = { label = "Days",                 ignore = false },
    [126]   = { label = "Days",                 ignore = true },
}

-- cachedStatusMessage -> string
-- Variable
-- A cached status message.
local cachedStatusMessage = ""

--- plugins.finalcutpro.toolbox.shotdata.settings <cp.prop: table>
--- Field
--- Snippets
mod.settings = json.prop(config.userConfigRootPath, "Shot Data", "Settings.cpShotData", {})

-- data -> table
-- Variable
-- A table containing all the current data being processed.
local data = {}

-- originalFilename -> string
-- Variable
-- Original filename of the FCPXML.
local originalFilename = ""

-- resourceCache -> table
-- Variable
-- A cache of all the resource paths.
local resourceCache = {}

-- resourceCache -> table
-- Variable
-- A table of all the files to copy.
local filesToCopy = {}

-- desktopPath -> string
-- Constant
-- Path to the users desktop
local desktopPath = os.getenv("HOME") .. "/Desktop/"

--- plugins.finalcutpro.toolbox.shotdata.lastOpenPath <cp.prop: string>
--- Field
--- Last open path
mod.lastOpenPath = config.prop("toolbox.shotdata.lastOpenPath", desktopPath)

--- plugins.finalcutpro.toolbox.shotdata.lastUploadPath <cp.prop: string>
--- Field
--- Last upload path
mod.lastUploadPath = config.prop("toolbox.shotdata.lastUploadPath", desktopPath)

--- plugins.finalcutpro.toolbox.shotdata.destinationPath <cp.prop: string>
--- Field
--- Last save path
mod.destinationPath = config.prop("toolbox.shotdata.destinationPath", desktopPath)

--- plugins.finalcutpro.toolbox.shotdata.automaticallyUploadCSV <cp.prop: boolean>
--- Field
--- Automatically Upload CSV?
mod.automaticallyUploadCSV = config.prop("toolbox.shotdata.automaticallyUploadCSV", true)

--- plugins.finalcutpro.toolbox.shotdata.mergeData <cp.prop: boolean>
--- Field
--- Merge data?
mod.mergeData = config.prop("toolbox.shotdata.mergeData", true)

--- plugins.finalcutpro.toolbox.shotdata.token <cp.prop: string>
--- Field
--- Notion Token.
mod.token = config.prop("toolbox.shotdata.token", "")

--- plugins.finalcutpro.toolbox.shotdata.databaseURL <cp.prop: string>
--- Field
--- Notion Database URL.
mod.databaseURL = config.prop("toolbox.shotdata.databaseURL", "")

--- plugins.finalcutpro.toolbox.shotdata.defaultEmoji <cp.prop: string>
--- Field
--- Default Emoji
mod.defaultEmoji = config.prop("toolbox.shotdata.defaultEmoji", "🎬")

--- plugins.finalcutpro.toolbox.shotdata.defaultEmoji <cp.prop: table>
--- Field
--- Ignore Columns
mod.ignoreColumns = config.prop("toolbox.shotdata.ignoreColumns", {})

-- renderPanel(context) -> none
-- Function
-- Generates the Preference Panel HTML Content.
--
-- Parameters:
--  * context - Table of data that you want to share with the renderer
--
-- Returns:
--  * HTML content as string
local function renderPanel(context)
    if not mod._renderPanel then
        local err
        mod._renderPanel, err = mod._env:compileTemplate("html/panel.html")
        if err then
            error(err)
        end
    end
    return mod._renderPanel(context)
end

-- generateContent() -> string
-- Function
-- Generates the Preference Panel HTML Content.
--
-- Parameters:
--  * None
--
-- Returns:
--  * HTML content as string
local function generateContent()
    local context = {
        i18n = i18n,
    }
    return renderPanel(context)
end

-- installMotionTemplate() -> none
-- Function
-- Install Motion Template.
--
-- Parameters:
--  * None
--
-- Returns:
--  * None
local function installMotionTemplate()
    webviewAlert(mod._manager.getWebview(), function(result)
        if result == i18n("ok") then
            local moviesPath = os.getenv("HOME") .. "/Movies"
            if not ensureDirectoryExists(moviesPath, "Motion Templates.localized", "Titles.localized", "CommandPost") then
                webviewAlert(mod._manager.getWebview(), function() end, i18n("shotDataFailedToInstallTemplate"), i18n("shotDataFailedToInstallTemplateDescription"), i18n("ok"), nil, "warning")
                return
            end
            local runString = [[cp -R "]] .. config.basePath .. "/plugins/finalcutpro/toolbox/shotdata/motiontemplate/Shot Data" .. [[" "]] .. os.getenv("HOME") .. "/Movies/Motion Templates.localized/Titles.localized/CommandPost" .. [["]]
            local output, status = execute(runString)
            if output and status then
                webviewAlert(mod._manager.getWebview(), function() end, i18n("shotDataInstalledSuccessfully"), i18n("shotDataInstalledSuccessfullyDescription"), i18n("ok"), nil, "informational")
            else
                webviewAlert(mod._manager.getWebview(), function() end, i18n("shotDataFailedToInstallTemplate"), i18n("shotDataFailedToInstallTemplateDescription"), i18n("ok"), nil, "warning")
            end
        end
    end, i18n("shotDataInstallMotionTemplate"), i18n("shotDataInstallMotionTemplateDescription"), i18n("ok"), i18n("cancel"), "informational")
end

-- secondsToClock(seconds) -> string
-- Function
-- Converts seconds to a string in the hh:mm:ss format.
--
-- Parameters:
--  * seconds - The number of seconds to convert.
--
-- Returns:
--  * A string
local function secondsToClock(seconds)
    seconds = tonumber(seconds) or 0
    local hours = string.format("%02.f", math.floor(seconds/3600));
    local mins = string.format("%02.f", math.floor(seconds/60 - (hours*60)));
    local secs = string.format("%02.f", math.floor(seconds - hours*3600 - mins *60));
    return hours..":"..mins..":"..secs
end

-- processTitles(nodes) -> none
-- Function
-- Process Titles.
--
-- Parameters:
--  * nodes - A table of XML nodes.
--
-- Returns:
--  * None
local function processTitles(nodes)
    if nodes then
        for _, node in pairs(nodes) do
            local nodeName = node:name()
            if nodeName == "spine" or nodeName == "gap" or nodeName == "asset-clip" or nodeName == "video" then
                --------------------------------------------------------------------------------
                -- Secondary Storyline:
                --------------------------------------------------------------------------------
                processTitles(node:children())
            elseif nodeName == "title" then
                --------------------------------------------------------------------------------
                -- Title:
                --------------------------------------------------------------------------------
                local results = {}

                local scenePrefixValue          = DEFAULT_SCENE_PREFIX
                local sceneTimeValue            = DEFAULT_SCENE_TIME
                local shotSizeAndTypeValue      = DEFAULT_SHOT_SIZE_AND_TYPE
                local cameraAngleValue          = DEFAULT_CAMERA_ANGLE

                local flagValue                 = DEFAULT_FLAG
                local vfxFlagValue              = DEFAULT_FLAG
                local sfxFlagValue              = DEFAULT_FLAG

                local titleDuration             = nil

                local photoPath                 = nil

                --------------------------------------------------------------------------------
                -- Get title duration:
                --------------------------------------------------------------------------------
                for _, v in pairs(node:rawAttributes()) do
                    if v:name() == "duration" then
                        titleDuration = v:stringValue()
                        break
                    end
                end

                --------------------------------------------------------------------------------
                -- Format Title Duration:
                --------------------------------------------------------------------------------
                if titleDuration then
                    titleDuration = titleDuration:gsub("s", "")
                    if titleDuration:find("/") then
                        local elements = split(titleDuration, "/")
                        titleDuration = tostring(tonumber(elements[1]) / tonumber(elements[2]))
                    end
                    titleDuration = secondsToClock(titleDuration)
                end

                --------------------------------------------------------------------------------
                -- Process Nodes:
                --------------------------------------------------------------------------------
                local nodeChildren = node:children()
                if nodeChildren and #nodeChildren >= TEMPLATE_NUMBER_OF_NODES then
                    local textCount = 1
                    for _, nodeChild in pairs(nodeChildren) do
                        if nodeChild:name() == "text" then
                            --------------------------------------------------------------------------------
                            -- Text Node:
                            --------------------------------------------------------------------------------
                            if TEMPLATE[textCount].ignore == false then
                                local textStyles = nodeChild:children()
                                local textStyle = textStyles and textStyles[1]
                                if textStyle and textStyle:name() == "text-style" then
                                    local value = textStyle:stringValue()
                                    local label = TEMPLATE[textCount].label
                                    results[label] = value
                                end
                            end
                            textCount = textCount + 1
                        elseif nodeChild:name() == "param" then
                            --------------------------------------------------------------------------------
                            -- Parameter Node:
                            --------------------------------------------------------------------------------
                            local rawAttributes = nodeChild:rawAttributes()
                            local name, value
                            for _, v in pairs(rawAttributes) do
                                if v:name() == "name" then
                                    name = v:stringValue()
                                elseif v:name() == "value" then
                                    value = v:stringValue()
                                end
                            end
                            if name == "Scene Prefix" then
                                scenePrefixValue = value:match("%((.*)%)")
                            elseif name == "Scene Time" then
                                sceneTimeValue = value:match("%((.*)%)")
                            elseif name == "Shot Size & Type" then
                                shotSizeAndTypeValue = value:match("%((.*)%)")
                            elseif name == "Camera Angle" then
                                cameraAngleValue = value:match("%((.*)%)")
                            elseif name == "Flag" then
                                if value == "1" then
                                    flagValue = "true"
                                end
                            elseif name == "VFX" then
                                if value == "1" then
                                    vfxFlagValue = "true"
                                end
                            elseif name == "SFX" then
                                if value == "1" then
                                    sfxFlagValue = "true"
                                end
                            end
                        elseif nodeChild:name() == "video" then
                            --------------------------------------------------------------------------------
                            -- Connected Video:
                            --------------------------------------------------------------------------------
                            local rawAttributes = nodeChild:rawAttributes()
                            local ref
                            for _, v in pairs(rawAttributes) do
                                if v:name() == "ref" then
                                    ref = v:stringValue()
                                end
                            end
                            if ref and resourceCache[ref] then
                                photoPath = resourceCache[ref]
                            end
                        end
                    end

                    --------------------------------------------------------------------------------
                    -- Add Parameter values to results table:
                    --------------------------------------------------------------------------------
                    results["Scene Prefix"] = scenePrefixValue
                    results["Scene Time"] = sceneTimeValue
                    results["Shot Size & Type"] = shotSizeAndTypeValue
                    results["Camera Angle"] = cameraAngleValue
                    results["Flag"] = flagValue
                    results["VFX"] = vfxFlagValue
                    results["SFX"] = sfxFlagValue


                    --------------------------------------------------------------------------------
                    -- If the Shot Duration field is empty, populate it with the Title Duration:
                    --------------------------------------------------------------------------------
                    if titleDuration and not results["Shot Duration"] then
                        results["Shot Duration"] = titleDuration
                    end

                    --------------------------------------------------------------------------------
                    -- Generate a unique Shot ID:
                    --------------------------------------------------------------------------------
                    local shotID = results["Scene Number"] .. "-" .. results["Shot Number"]
                    results["Shot ID"] = shotID

                    --------------------------------------------------------------------------------
                    -- If there's an image "attached" to the title, include it in filesToCopy:
                    --------------------------------------------------------------------------------
                    if photoPath then
                        filesToCopy[shotID] = photoPath
                        results["Image Filename"] = shotID .. ".png"
                    end

                    --------------------------------------------------------------------------------
                    -- Add results to data table:
                    --------------------------------------------------------------------------------
                    table.insert(data, copy(results))
                end
            end
        end

    end
end

-- uploadToNotion(csvPath) -> none
-- Function
-- Uploads a CSV files to Notion.
--
-- Parameters:
--  * csvPath - A string containing the path to the CSV file.
--
-- Returns:
--  * None
local function uploadToNotion(csvPath)

    local injectScript = mod._manager.injectScript

    injectScript([[
        setStatus('green', `]] .. i18n("preparingToUploadCSVDataToNotion") .. [[...`);
    ]])

    --log.df("lets process: %s", csvPath)

    local token                 = mod.token()
    local databaseURL           = mod.databaseURL()
    local mergeData             = mod.mergeData()
    local ignoreColumns         = mod.ignoreColumns()
    local defaultEmoji          = mod.defaultEmoji()

    --------------------------------------------------------------------------------
    -- Make sure there's a valid token!
    --------------------------------------------------------------------------------
    if not token or trim(token) == "" then
        injectScript("setStatus('red', '" .. string.upper(i18n("failed")) .. ": " .. i18n("aValidTokenIsRequired") .. "');")
        return
    end

    --log.df("mergeData: %s", mergeData)
    --log.df("databaseURL: %s", databaseURL)
    --log.df("defaultEmoji: %s", defaultEmoji)
    --log.df("token: %s", token)

    --------------------------------------------------------------------------------
    -- Define path to csv2notion:
    --------------------------------------------------------------------------------
    local binPath = config.basePath .. "/plugins/finalcutpro/toolbox/shotdata/csv2notion/csv2notion"

    --------------------------------------------------------------------------------
    -- Setup Arguments for csv2notion:
    --------------------------------------------------------------------------------
    local arguments = {
        "--token",
        token,
    }

    if databaseURL and databaseURL ~= "" then
        table.insert(arguments, "--url")
        table.insert(arguments, databaseURL)
    end

    table.insert(arguments, "--mandatory-column")
    table.insert(arguments, "Shot ID")

    table.insert(arguments, "--image-column")
    table.insert(arguments, "Image Filename")

    table.insert(arguments, "--image-column-keep")

    table.insert(arguments, "--image-caption-column")
    table.insert(arguments, "Scene Description")

    if mergeData then
        table.insert(arguments, "--merge")
        for _, id in pairs(TEMPLATE_ORDER) do
            if not tableContains(ignoreColumns, id) then
                --------------------------------------------------------------------------------
                -- Don't ignore this column:
                --------------------------------------------------------------------------------
                table.insert(arguments, "--merge-only-column")
                table.insert(arguments, id)
            end
        end
    end

    if defaultEmoji and defaultEmoji ~= "" then
        table.insert(arguments, "--default-icon")
        table.insert(arguments, defaultEmoji)
    end

    table.insert(arguments, "--verbose")

    table.insert(arguments, csvPath)

    --------------------------------------------------------------------------------
    -- Trigger new hs.task that calls csv2notion:
    --------------------------------------------------------------------------------
    mod.notionTask = task.new(binPath, function() -- (exitCode, stdOut, stdErr)
        --------------------------------------------------------------------------------
        -- Callback Function:
        --------------------------------------------------------------------------------
        --[[
        log.df("Shot Data Completion Callback:")
        log.df(" - exitCode: %s", exitCode)
        log.df(" - stdOut: %s", stdOut)
        log.df(" - stdErr: %s", stdErr)
        --]]
    end, function(_, _, stdErr) -- (obj, stdOut, stdErr)
        --------------------------------------------------------------------------------
        -- Stream Callback Function:
        --------------------------------------------------------------------------------
        --log.df("Stream Callback Function")
        --log.df("obj: %s", obj)
        --log.df("stdOut: %s", stdOut)
        if stdErr and stdErr ~= "" then

            --------------------------------------------------------------------------------
            -- Remove Line Breaks:
            --------------------------------------------------------------------------------
            local status = stdErr:gsub("[\r\n%z]", "")

            --------------------------------------------------------------------------------
            -- Trim any white space:
            --------------------------------------------------------------------------------
            status = trim(status)

            --------------------------------------------------------------------------------
            -- Remove type prefix:
            --------------------------------------------------------------------------------
            local statusColour = "green"
            if status:sub(1, 11) == "INFO: Done!" then
                status = i18n("successfullyUploadedToNotion") .. "!"
            elseif status:sub(1, 6) == "INFO: " then
                status = status:sub(7) .. "..."
            elseif status:sub(1, 10) == "CRITICAL: " then
                status = status:sub(11)
                statusColour = "red"
            elseif status:sub(1, 9) == "WARNING: " then
                status = status:sub(10)
                statusColour = "orange"
            elseif status:sub(2, 2) == "%" or status:sub(3, 3) == "%" or status:sub(4, 4) == "%" then
                --------------------------------------------------------------------------------
                -- Example:
                --
                -- 0%|          | 0/19 [00:00<?, ?it/s]
                --------------------------------------------------------------------------------
                status = i18n("uploading") .. "... " .. status
            end

            --------------------------------------------------------------------------------
            -- Update the User Interface:
            --------------------------------------------------------------------------------
            if status:len() < 160 then
                injectScript("setStatus(`" .. statusColour .. "`, `" .. status .. "`);")
            else
                injectScript("setStatus(`red`, `" .. string.upper(i18n("error")) .. ": " .. i18n("checkTheDebugConsoleForTheFullErrorMessage") .. "...`);")
            end

            --------------------------------------------------------------------------------
            -- Write to Debug Console:
            --------------------------------------------------------------------------------
            log.df("Shot Data Upload Status: %s", status)
        end

        return true
    end, arguments):start()
end

-- processFCPXML(path) -> none
-- Function
-- Process a FCPXML file.
--
-- Parameters:
--  * path - A string containing the path to the FCPXML file.
--
-- Returns:
--  * None
local function processFCPXML(path)
    local fcpxmlPath = path and fcpxml.valid(path)
    if fcpxmlPath then
        --------------------------------------------------------------------------------
        -- Open the FCPXML:
        --------------------------------------------------------------------------------
        local document = xml.open(fcpxmlPath)

        --------------------------------------------------------------------------------
        -- Process Resources:
        --------------------------------------------------------------------------------
        filesToCopy = {}
        resourceCache = {}
        local resources = document:XPathQuery("/fcpxml[1]/resources[1]")
        local resourcesChildren = resources and resources[1] and resources[1]:children()
        if resourcesChildren then
            for _, element in pairs(resourcesChildren) do
                if element:name() == "asset" then
                    local rawAttributes = element:rawAttributes()
                    local id, src
                    for _, v in pairs(rawAttributes) do
                        if v:name() == "id" then
                            id = v:stringValue()
                        end
                    end
                    local elementChildren = element:children()
                    for _, v in pairs(elementChildren) do
                        if v:name() == "media-rep" then
                            for _, attribute in pairs(v:rawAttributes()) do
                                if attribute:name() == "src" then
                                    src = attribute:stringValue()
                                    --------------------------------------------------------------------------------
                                    -- Remove the file://
                                    --------------------------------------------------------------------------------
                                    src = replace(src, "file://", "")

                                    --------------------------------------------------------------------------------
                                    -- Remove any URL encoding:
                                    --------------------------------------------------------------------------------
                                    src = src:gsub('%%(%x%x)', function(h) return string.char(tonumber(h, 16)) end)
                                end
                            end
                        end
                    end
                    if id and src then
                        resourceCache[id] = src
                    end
                end
            end
        end

        --------------------------------------------------------------------------------
        -- Process Sequence Spine:
        --------------------------------------------------------------------------------
        local spine = document:XPathQuery("/fcpxml[1]/library[1]/event[1]/project[1]/sequence[1]/spine[1]")
        local spineChildren = spine and spine[1] and spine[1]:children()

        --------------------------------------------------------------------------------
        -- If there's no spineChildren, then try another path (for drag & drop):
        --------------------------------------------------------------------------------
        if not spineChildren then
            spine = document:XPathQuery("/fcpxml[1]/project[1]/sequence[1]/spine[1]")
            spineChildren = spine and spine[1] and spine[1]:children()
        end

        --------------------------------------------------------------------------------
        -- If drag and drop FCPXML, then use the project name for the filename:
        --------------------------------------------------------------------------------
        if spineChildren and not originalFilename then
            local projectName = spine and spine[1] and spine[1]:parent():parent():rawAttributes()[1]:stringValue()
            originalFilename = projectName
        end

        --------------------------------------------------------------------------------
        -- Reset our data table:
        --------------------------------------------------------------------------------
        data = {}

        --------------------------------------------------------------------------------
        -- Process the titles:
        --------------------------------------------------------------------------------
        processTitles(spineChildren)

        --------------------------------------------------------------------------------
        -- Abort if we didn't get any results:
        --------------------------------------------------------------------------------
        if not next(data) then
            webviewAlert(mod._manager.getWebview(), function() end, i18n("failedToProcessFCPXML"), i18n("shotDataFCPXMLFailedDescription"), i18n("ok"), nil, "warning")
            return
        end

        --------------------------------------------------------------------------------
        -- Convert the titles data to CSV data:
        --------------------------------------------------------------------------------
        local output = ""

        local numberOfHeadings = tableCount(TEMPLATE_ORDER)

        for i=1, numberOfHeadings do
            output = output .. TEMPLATE_ORDER[i]
            if i ~= numberOfHeadings then
                output = output .. ","
            end
        end

        output = output .. "\n"

        for _, row in pairs(data) do
            for i=1, numberOfHeadings do
                local currentHeading = TEMPLATE_ORDER[i]
                local value = row[currentHeading]
                if value then
                    if value:match(",") or value:match([["]]) then
                        output = output .. [["]] .. value:gsub([["]], [[""]]) .. [["]]
                    else
                        output = output .. value
                    end
                    if i ~= numberOfHeadings then
                        output = output .. ","
                    end
                else
                    --------------------------------------------------------------------------------
                    -- It's a blank/empty field:
                    --------------------------------------------------------------------------------
                    if i ~= numberOfHeadings then
                        output = output .. ","
                    end
                end
            end
            output = output .. "\n"
        end

        --------------------------------------------------------------------------------
        -- Make sure the destination path still exists, otherwise use Desktop:
        --------------------------------------------------------------------------------
        if not doesDirectoryExist(mod.destinationPath()) then
            mod.destinationPath(desktopPath)
        end

        local destinationPath = mod.destinationPath()

        if destinationPath then
            --------------------------------------------------------------------------------
            -- Make a sub-folder for the year/month/day/time:
            --------------------------------------------------------------------------------
            local dateFolderName = originalFilename .. " - " .. os.date("%Y%m%d %H%M")
            local exportPath = destinationPath .. "/" .. dateFolderName

            if doesDirectoryExist(exportPath) then
                --------------------------------------------------------------------------------
                -- If the folder already exists, add the seconds as well:
                --------------------------------------------------------------------------------
                dateFolderName = originalFilename .. " - " .. os.date("%Y%m%d %H%M %S")
                exportPath = destinationPath .. "/" .. dateFolderName
            end

            if not ensureDirectoryExists(destinationPath, dateFolderName) then
                --------------------------------------------------------------------------------
                -- Failed to create the necessary sub-folder:
                --------------------------------------------------------------------------------
                webviewAlert(mod._manager.getWebview(), function() end, i18n("failedToCreateExportDestination"), i18n("failedToCreateExportDestinationDescription"), i18n("ok"))
                return
            end

            --------------------------------------------------------------------------------
            -- Consolidate images:
            --------------------------------------------------------------------------------
            local consolidateSuccessful = true
            if tableCount(filesToCopy) >= 1 then
                for destinationFilename, sourcePath in pairs(filesToCopy) do
                    local status = false
                    if doesFileExist(sourcePath) then
                        --------------------------------------------------------------------------------
                        -- Save the image as PNG:
                        --------------------------------------------------------------------------------
                        local originalImage = imageFromPath(sourcePath)
                        if originalImage then
                            local pngPath = exportPath .. "/" .. destinationFilename .. ".png"
                            status = originalImage:saveToFile(pngPath)
                        end
                    end
                    if not status then
                        consolidateSuccessful = false
                        log.ef("Failed to copy source file: %s", sourcePath)
                    end
                end
            end

            local exportedFilePath = exportPath .. "/" .. originalFilename .. ".csv"
            writeToFile(exportedFilePath, output)

            if consolidateSuccessful then
                --------------------------------------------------------------------------------
                -- Upload to Notion:
                --------------------------------------------------------------------------------
                if mod.automaticallyUploadCSV() then
                    uploadToNotion(exportedFilePath)
                else
                    if tableCount(filesToCopy) >= 1 then
                        webviewAlert(mod._manager.getWebview(), function() end, i18n("success") .. "!", i18n("theCSVAndConsolidatedImagesHasBeenExportedSuccessfully"), i18n("ok"))
                    else
                        webviewAlert(mod._manager.getWebview(), function() end, i18n("success") .. "!", i18n("theCSVHasBeenExportedSuccessfully"), i18n("ok"))
                    end
                end
            else
                webviewAlert(mod._manager.getWebview(), function() end, i18n("someErrorsHaveOccurred"), i18n("csvExportedSuccessfullyImagesCouldNotBeConsolidated"), i18n("ok"))
            end
        end
    else
        webviewAlert(mod._manager.getWebview(), function() end, i18n("invalidFCPXMLFile"), i18n("theSuppliedFCPXMLDidNotPassDtdValidationPleaseCheckThatTheFCPXMLSuppliedIsValidAndTryAgain"), i18n("ok"), nil, "warning")
    end
end

-- convertFCPXMLtoCSV() -> none
-- Function
-- Converts a FCPXML to a CSV.
--
-- Parameters:
--  * None
--
-- Returns:
--  * None
local function convertFCPXMLtoCSV()
    if not doesDirectoryExist(mod.lastOpenPath()) then
        mod.lastOpenPath(desktopPath)
    end
    local result = chooseFileOrFolder(i18n("pleaseSelectAFCPXMLFileToConvert") .. ":", mod.lastOpenPath(), true, false, false, {"fcpxml", "fcpxmld"}, true)
    local path = result and result["1"]
    if path then
        originalFilename = getFilenameFromPath(path, true)
        mod.lastOpenPath(removeFilenameFromPath(path))
        processFCPXML(path)
    end
end

-- selectAndUploadCSV() -> none
-- Function
-- Converts a FCPXML to a CSV.
--
-- Parameters:
--  * None
--
-- Returns:
--  * None
local function selectAndUploadCSV()
    if not doesDirectoryExist(mod.lastUploadPath()) then
        mod.lastUploadPath(desktopPath)
    end
    local result = chooseFileOrFolder(i18n("pleaseSelectACSVFile") .. ":", mod.lastUploadPath(), true, false, false, {"csv"}, true)
    local path = result and result["1"]
    if path then
        mod.lastUploadPath(removeFilenameFromPath(path))
        uploadToNotion(path)
    end
end

-- updateUI() -> none
-- Function
-- Update the user interface.
--
-- Parameters:
--  * None
--
-- Returns:
--  * None
local function updateUI()
    --------------------------------------------------------------------------------
    -- Make sure the destination path still exists, otherwise use Desktop:
    --------------------------------------------------------------------------------
    if not doesDirectoryExist(mod.destinationPath()) then
        mod.destinationPath(desktopPath)
    end

    local injectScript = mod._manager.injectScript
    local script = ""

    --------------------------------------------------------------------------------
    -- Update the status message:
    --------------------------------------------------------------------------------
    local statusMessage = i18n("readyForANewCSVFile")
    if cachedStatusMessage ~= "" then
        statusMessage = cachedStatusMessage
        cachedStatusMessage = ""
    end
    script = script .. [[
        setStatus("green", `]] .. statusMessage .. [[...`);
    ]]

    --------------------------------------------------------------------------------
    -- Update the user interface elements:
    --------------------------------------------------------------------------------
    local enableDroppingFinalCutProProjectToDockIcon = tostring(mod._preferences.dragAndDropTextAction() == "shotdata")
    script = script .. [[
        changeCheckedByID("enableDroppingFinalCutProProjectToDockIcon", ]] .. enableDroppingFinalCutProProjectToDockIcon .. [[);
        changeCheckedByID("automaticallyUploadCSV", ]] .. tostring(mod.automaticallyUploadCSV()) .. [[);
        changeCheckedByID("mergeData", ]] .. tostring(mod.mergeData()) .. [[);

        changeValueByID("token", "]] .. mod.token() .. [[");
        changeValueByID("databaseURL", "]] .. mod.databaseURL() .. [[");
        changeValueByID("defaultEmoji", "]] .. mod.defaultEmoji() .. [[");

        changeInnerHTMLByID("destinationPath", `]] .. mod.destinationPath() .. [[`);
    ]]

    --------------------------------------------------------------------------------
    -- Update the Ignore Columns List:
    --------------------------------------------------------------------------------
    local ignoreColumns = mod.ignoreColumns()
    for _, id in pairs(TEMPLATE_ORDER) do
        script = script .. [[
            changeIgnoreColumnsOptionSelected("]] .. id .. [[", ]] .. tostring(tableContains(ignoreColumns, id)) .. [[)
        ]]
    end

    injectScript(script)
end

-- callback() -> none
-- Function
-- JavaScript Callback for the Panel
--
-- Parameters:
--  * id - ID as string
--  * params - Table of paramaters
--
-- Returns:
--  * None
local function callback(id, params)
    local callbackType = params and params["type"]
    if not callbackType then
        log.ef("Invalid callback type in Shot Data Toolbox Panel.")
        return
    end
    if callbackType == "installMotionTemplate" then
        --------------------------------------------------------------------------------
        -- Install Motion Template:
        --------------------------------------------------------------------------------
        installMotionTemplate()
    elseif callbackType == "convertFCPXMLtoCSV" then
        --------------------------------------------------------------------------------
        -- Convert a FCPXML to CSV:
        --------------------------------------------------------------------------------
        convertFCPXMLtoCSV()
    elseif callbackType == "dropbox" then
        --------------------------------------------------------------------------------
        -- Convert a FCPXML to CSV via Drop Zone:
        --------------------------------------------------------------------------------

        ---------------------------------------------------
        -- Make CommandPost active:
        ---------------------------------------------------
        hs.focus()

        ---------------------------------------------------
        -- Try again after a second incase FCPX has stolen
        -- back focus:
        ---------------------------------------------------
        doAfter(2, function()
            hs.focus()
        end)

        ---------------------------------------------------
        -- Get value from UI:
        ---------------------------------------------------
        local value = params["value"] or ""
        local path = os.tmpname() .. ".fcpxml"

        ---------------------------------------------------
        -- Reset the original filename (as we'll use
        -- the project name instead):
        ---------------------------------------------------
        originalFilename = nil

        ---------------------------------------------------
        -- Write the FCPXML data to a temporary file:
        ---------------------------------------------------
        writeToFile(path, value)

        ---------------------------------------------------
        -- Process the FCPXML:
        ---------------------------------------------------
        processFCPXML(path)
    elseif callbackType == "uploadCSV" then
        --------------------------------------------------------------------------------
        -- The Upload CSV Button has been pressed:
        --------------------------------------------------------------------------------
        selectAndUploadCSV()
    elseif callbackType == "findToken" then
        --------------------------------------------------------------------------------
        -- Find Token Help Button:
        --------------------------------------------------------------------------------
        execute("open " .. NOTION_TOKEN_HELP_URL)
    elseif callbackType == "findDatabaseURL" then
        --------------------------------------------------------------------------------
        -- Find Database Help Button:
        --------------------------------------------------------------------------------
        execute("open " .. NOTION_DATABASE_VIEW_HELP_URL)
    elseif callbackType == "openNotionTemplate" then
        --------------------------------------------------------------------------------
        -- Open Notion Template URL:
        --------------------------------------------------------------------------------
        execute("open " .. NOTION_TEMPLATE_URL)
    elseif callbackType == "updateUI" then
        --------------------------------------------------------------------------------
        -- Update the User Interface:
        --------------------------------------------------------------------------------
        updateUI()
    elseif callbackType == "updateText" then
        --------------------------------------------------------------------------------
        -- Updated Text Values from the User Interface:
        --------------------------------------------------------------------------------
        local tid = params and params["id"]
        local value = params and params["value"]
        if tid then
            if tid == "token" then
                mod.token(value)
            elseif tid == "databaseURL" then
                mod.databaseURL(value)
            elseif tid == "defaultEmoji" then
                mod.defaultEmoji(value)
            end
        end
    elseif callbackType == "updateChecked" then
        --------------------------------------------------------------------------------
        -- Updated Checked Values from the User Interface:
        --------------------------------------------------------------------------------
        local tid = params and params["id"]
        local value = params and params["value"]

        if tid then
            if tid == "automaticallyUploadCSV" then
                mod.automaticallyUploadCSV(value)
            elseif tid == "mergeData" then
                mod.mergeData(value)
            elseif tid == "enableDroppingFinalCutProProjectToDockIcon" then

                if value then
                    mod._preferences.dragAndDropTextAction("shotdata")
                else
                    if mod._preferences.dragAndDropTextAction() == "shotdata" then
                        mod._preferences.dragAndDropTextAction("")
                    end
                end
            end
        end
    elseif callbackType == "updateOptions" then
        --------------------------------------------------------------------------------
        -- Updated Select Values from the User Interface:
        --------------------------------------------------------------------------------
        local tid = params and params["id"]
        local value = params and params["value"]
        if tid then
            if tid == "ignoreColumns" then
                mod.ignoreColumns(value)
            end
        end
    elseif callbackType == "loadSettings" then
        --------------------------------------------------------------------------------
        -- Load Settings:
        --------------------------------------------------------------------------------
        local menu = {}

        local settings = mod.settings()

        local numberOfSettings = tableCount(settings)

        local function updateSettings(setting)
            mod.token(setting["token"])
            mod.databaseURL(setting["databaseURL"])
            mod.defaultEmoji(setting["defaultEmoji"])
            mod.automaticallyUploadCSV(setting["automaticallyUploadCSV"])
            mod.mergeData(setting["mergeData"])
            mod.ignoreColumns(setting["ignoreColumns"])

            --------------------------------------------------------------------------------
            -- Change Export Destination:
            --------------------------------------------------------------------------------
            local destinationPath = setting["destinationPath"]
            if doesDirectoryExist(destinationPath) then
                mod.destinationPath(destinationPath)
            end

            updateUI()
        end

        if numberOfSettings == 0 then
            table.insert(menu, {
                title = i18n("none"),
                disabled = true,
            })
        else
            for tid, setting in pairs(settings) do
                table.insert(menu, {
                    title = tid,
                    fn = function() updateSettings(setting) end
                })
            end
            table.insert(menu, {
                title = "-",
                disabled = true,
            })
            table.insert(menu, {
                title = i18n("deleteAllSettings"),
                fn = function()
                    mod.settings({})
                    updateUI()
                end,
            })

        end

        local popup = menubar.new()
        popup:setMenu(menu):removeFromMenuBar()
        popup:popupMenu(mouse.absolutePosition(), true)
    elseif callbackType == "saveSettings" then
        --------------------------------------------------------------------------------
        -- Save Settings:
        --------------------------------------------------------------------------------
        local label = params and params["label"]
        if label and label ~= "" then
            local settings = mod.settings()

            settings[label] = {
                ["token"]                           = mod.token(),
                ["databaseURL"]                     = mod.databaseURL(),
                ["defaultEmoji"]                    = mod.defaultEmoji(),
                ["automaticallyUploadCSV"]          = mod.automaticallyUploadCSV(),
                ["mergeData"]                       = mod.mergeData(),
                ["ignoreColumns"]                   = mod.ignoreColumns(),
                ["destinationPath"]                 = mod.destinationPath()
            }

            mod.settings(settings)
        end
    elseif callbackType == "changeExportDestination" then
        --------------------------------------------------------------------------------
        -- Change Export Destination:
        --------------------------------------------------------------------------------
        if not doesDirectoryExist(mod.destinationPath()) then
            --------------------------------------------------------------------------------
            -- Make sure the destination path still exists, otherwise use Desktop:
            --------------------------------------------------------------------------------
            mod.destinationPath(desktopPath)
        end

        local destinationPathResult = chooseFileOrFolder(i18n("pleaseSelectAFolderToSaveTheCSVTo") .. ":", mod.destinationPath(), false, true, false)
        local destinationPath = destinationPathResult and destinationPathResult["1"]

        if destinationPath then
           mod.destinationPath(destinationPath)
        end

        --------------------------------------------------------------------------------
        -- Update the user interface:
        --------------------------------------------------------------------------------
        updateUI()
    elseif callbackType == "emojiPicker" then
        --------------------------------------------------------------------------------
        -- Emoji Picker Button Pressed:
        --------------------------------------------------------------------------------
        mod.defaultEmoji("")

        local injectScript = mod._manager.injectScript
        local script = [[
            changeValueByID("defaultEmoji", "]] .. mod.defaultEmoji() .. [[");
            document.getElementById("defaultEmoji").focus();
            pressButton("openEmojiPicker");
        ]]
        injectScript(script)
    elseif callbackType == "openEmojiPicker" then
        --------------------------------------------------------------------------------
        -- Open Emoji Picker (triggered by above JavaScript):
        --------------------------------------------------------------------------------
        eventtap.keyStroke({"control", "command"}, "space")
    elseif callbackType == "clearSelection" then
        --------------------------------------------------------------------------------
        -- Clear Selection:
        --------------------------------------------------------------------------------
        mod.ignoreColumns({})

        --------------------------------------------------------------------------------
        -- Update the user interface:
        --------------------------------------------------------------------------------
        updateUI()
    elseif callbackType == "revealExportDestination" then
        --------------------------------------------------------------------------------
        -- Open the Export Destination Folder:
        --------------------------------------------------------------------------------
        if not doesDirectoryExist(mod.destinationPath()) then
            mod.destinationPath(desktopPath)
            updateUI()
        end

        execute([[open "]] .. mod.destinationPath() .. [["]])
    elseif callbackType == "openUserGuide" then
        --------------------------------------------------------------------------------
        -- Read Manual Button:
        --------------------------------------------------------------------------------
        execute("open " .. SHOT_DATA_USER_GUIDE_URL)
    else
        --------------------------------------------------------------------------------
        -- Unknown Callback:
        --------------------------------------------------------------------------------
        log.df("Unknown Callback in Shot Data Toolbox Panel:")
        log.df("id: %s", inspect(id))
        log.df("params: %s", inspect(params))
    end
end

local plugin = {
    id              = "finalcutpro.toolbox.shotdata",
    group           = "finalcutpro",
    dependencies    = {
        ["core.toolbox.manager"]        = "manager",
        ["core.preferences.general"]    = "preferences",
    }
}

function plugin.init(deps, env)
    --------------------------------------------------------------------------------
    -- Only load plugin if Final Cut Pro is supported:
    --------------------------------------------------------------------------------
    if not fcp:isSupported() then return end

    --------------------------------------------------------------------------------
    -- Inter-plugin Connectivity:
    --------------------------------------------------------------------------------
    mod._manager                = deps.manager
    mod._preferences            = deps.preferences
    mod._env                    = env

    --------------------------------------------------------------------------------
    -- Setup Utilities Panel:
    --------------------------------------------------------------------------------
    mod._panel = deps.manager.addPanel({
        priority        = 3,
        id              = "shotdata",
        label           = i18n("shotData"),
        image           = imageFromPath(env:pathToAbsolute("/images/shotdata.png")),
        tooltip         = i18n("shotData"),
        height          = 1100,
    })
    :addContent(1, generateContent, false)

    --------------------------------------------------------------------------------
    -- Setup Callback Manager:
    --------------------------------------------------------------------------------
    mod._panel:addHandler("onchange", "shotDataPanelCallback", callback)

    --------------------------------------------------------------------------------
    -- Drag & Drop Text to the Dock Icon:
    --------------------------------------------------------------------------------
    mod._preferences.registerDragAndDropTextAction("shotdata", i18n("sendFCPXMLToShotData"), function(value)
        ---------------------------------------------------
        -- Show the Panel:
        ---------------------------------------------------
        mod._manager.show("shotdata")

        ---------------------------------------------------
        -- Give it a second to load the user interface:
        ---------------------------------------------------
        doAfter(1, function()
            ---------------------------------------------------
            -- Update the status:
            ---------------------------------------------------
            if mod.automaticallyUploadCSV() then
                cachedStatusMessage = i18n("waitingForFCPXMLToBeProcessed")
            end

            ---------------------------------------------------
            -- Setup a temporary file path:
            ---------------------------------------------------
            local path = os.tmpname() .. ".fcpxml"

            ---------------------------------------------------
            -- Reset the original filename (as we'll use
            -- the project name instead):
            ---------------------------------------------------
            originalFilename = nil

            ---------------------------------------------------
            -- Write the FCPXML data to a temporary file:
            ---------------------------------------------------
            writeToFile(path, value)

            ---------------------------------------------------
            -- Process the FCPXML:
            ---------------------------------------------------
            processFCPXML(path)
        end)
    end)

    --------------------------------------------------------------------------------
    -- Drag & Drop File to the Dock Icon:
    --------------------------------------------------------------------------------
    mod._preferences.registerDragAndDropFileAction("shotdata", i18n("sendFCPXMLToShotData"), function(path)
        ---------------------------------------------------
        -- Show the Panel:
        ---------------------------------------------------
        mod._manager.show("shotdata")

        ---------------------------------------------------
        -- Give it a second to load the user interface:
        ---------------------------------------------------
        doAfter(1, function()
            ---------------------------------------------------
            -- Update the status:
            ---------------------------------------------------
            if mod.automaticallyUploadCSV() then
                cachedStatusMessage = i18n("waitingForFCPXMLToBeProcessed")
            end

            ---------------------------------------------------
            -- Set the Original Filename for later:
            ---------------------------------------------------
            originalFilename = getFilenameFromPath(path, true)

            ---------------------------------------------------
            -- Process the FCPXML:
            ---------------------------------------------------
            processFCPXML(path)
        end)
    end)

    return mod
end

return plugin
