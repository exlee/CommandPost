--- === plugins.finalcutpro.timeline.playhead ===
---
--- Manages features relating to the Timeline Playhead.

local require = require

local eventtap                  = require("hs.eventtap")

local config                    = require("cp.config")
local dialog                    = require("cp.dialog")
local fcp                       = require("cp.apple.finalcutpro")
local i18n                      = require("cp.i18n")

local mod = {}

local viewer = fcp.viewer
local contents = fcp.timeline.contents
local playhead = fcp.timeline.playhead

mod._offset = nil

--------------------------------------------------------------------------------
-- This will reposition the content view to lock on the playhead.
--------------------------------------------------------------------------------
local positionPlayhead = function()
    --------------------------------------------------------------------------------
    -- Timeline isn't visible:
    --------------------------------------------------------------------------------
    local contentFrame = contents:viewFrame()
    local playheadPosition = playhead:position()
    if contentFrame == nil or playheadPosition == nil then
        return
    end

    --------------------------------------------------------------------------------
    -- Reset the stored offset if the viewFrame gets too narrow:
    --------------------------------------------------------------------------------
    if mod._offset >= contentFrame.w then mod._offset = math.floor(contentFrame.w/2) end

    --------------------------------------------------------------------------------
    -- Track the timeline:
    --------------------------------------------------------------------------------
    local timelineFrame = contents:timelineFrame()
    local scrollWidth = timelineFrame.w - contentFrame.w
    local scrollPoint = timelineFrame.x*-1 + playheadPosition - mod._offset
    local scrollTarget = scrollPoint/scrollWidth

    -----------------------------------------------------------------------
    -- Don't change timeline position if SHIFT key is pressed:
    -----------------------------------------------------------------------
    local modifiers = eventtap.checkKeyboardModifiers()
    if modifiers and not modifiers["shift"] then
        contents:shiftHorizontalTo(scrollTarget)
    end
end

--- plugins.finalcutpro.timeline.playhead.scrollingTimeline <cp.prop: boolean>
--- Variable
--- Enables or disables the scrolling timeline.
mod.scrollingTimeline = config.prop("scrollingTimelineActive", false):watch(function(active)
    if active then
        --------------------------------------------------------------------------------
        -- Display Notification:
        --------------------------------------------------------------------------------
        dialog.displayNotification(i18n("scrollingTimelineActivated"))
    else
        dialog.displayNotification(i18n("scrollingTimelineDeactivated"))
    end
end)

--- plugins.finalcutpro.timeline.playhead.alwaysCentered <cp.prop: boolean>
--- Variable
--- If `true`, the playhead will be centered in the view while scrolling.
mod.alwaysCentered = config.prop("scrollingTimelineCentered", false)

--- plugins.finalcutpro.timeline.playhead.tracking <cp.prop: boolean; read-only; live>
--- Variable
--- If `true`, we are tracking the playhead position.
mod.tracking = mod.scrollingTimeline:AND(viewer.isPlaying):AND(contents.isShowing):watch(function(tracking)
    if tracking then
        -- calculate the intial playhead offset
        local viewFrame = contents:viewFrame()
        mod._offset = playhead:position() - viewFrame.x
        if mod.alwaysCentered() or mod._offset <= 0 or mod._offset >= viewFrame.w then
            --------------------------------------------------------------------------------
            -- Align the playhead to the centre of the timeline view:
            --------------------------------------------------------------------------------
            mod._offset = math.floor(viewFrame.w/2)
        end

        playhead.timecode:watch(positionPlayhead, true)
    else
        playhead.timecode:unwatch(positionPlayhead)
    end
end, true)


local plugin = {
    id = "finalcutpro.timeline.playhead",
    group = "finalcutpro",
    dependencies = {
        ["finalcutpro.menu.manager"]                = "menuManager",
        ["finalcutpro.commands"]                    = "fcpxCmds",
        ["finalcutpro.preferences.manager"]         = "prefs",
    }
}

function plugin.init(deps)
    --------------------------------------------------------------------------------
    -- Only load plugin if Final Cut Pro is supported:
    --------------------------------------------------------------------------------
    if not fcp:isSupported() then return end

    local menu, cmds = deps.menuManager.timeline, deps.fcpxCmds

    --------------------------------------------------------------------------------
    -- Setup Menu:
    --------------------------------------------------------------------------------
    local section = menu:addSection(1000)
    section
        :addItems(1000, function()
            return {
                { title = i18n("enableScrollingTimeline"),      fn = function() mod.scrollingTimeline:toggle() end,     checked = mod.scrollingTimeline() },
            }
        end)

    --------------------------------------------------------------------------------
    -- Setup Commands:
    --------------------------------------------------------------------------------
    cmds
        :add("cpScrollingTimeline")
        :groupedBy("timeline")
        :activatedBy():ctrl():option():cmd("w")
        :whenActivated(function() mod.scrollingTimeline:toggle() end)

    return mod
end

return plugin
