--- === cp.fn.ax ===
---
--- A collection of useful functions for working with AX.
---
--- You may also find functions in [cp.fn](cp.fn.md) and [cp.fn.table](cp.fn.table.md) useful.

local require               = require

-- local log                   = require "hs.logger" .new "fnax"

local fn                    = require "cp.fn"
local is                    = require "cp.is"
local prop                  = require "cp.prop"

local isCallable            = is.callable
local isUserdata            = is.userdata
local isTable               = is.table
local isTruthy              = is.truthy
local constant              = fn.constant
local chain, pipe           = fn.chain, fn.pipe
local default               = fn.value.default
local get, ifilter, map     = fn.table.get, fn.table.ifilter, fn.table.map

local pack, unpack, sort    = table.pack, table.unpack, table.sort

local mod = {}

--- cp.fn.ax.isUIElement(value) -> boolean
--- Function
--- Checks to see if the `value` is an `axuielement`
---
--- Parameters:
--- * value - The value to check
---
--- Returns:
--- * `true` if the value is an `axuielement`
local function isUIElement(value)
    return isUserdata(value) and isCallable(value.attributeValue)
end

--- fn.ax.uielement(uivalue) -> axuielement | nil
--- Function
--- Returns the axuielement for the given `uivalue`.
---
--- Parameters:
---  * uivalue - The value to get the `axuielement` from.
---
--- Returns:
---  * The `axuielement` for the given `value` or `nil`.
---
--- Notes:
---   * If the `value` is an `axuielement`, it is returned.
---   * If the `value` is a table with a callable `UI` field, the `UI` field is called and the result is returned.
---   * If the `value` is callable, it is called and the result is returned.
---   * Otherwise, `nil` is returned.
local function uielement(uivalue)
    -- first, check if it's an element with a UI field
    if isTable(uivalue) and isCallable(uivalue.UI) then
        uivalue = uivalue:UI()
    end
    -- then, check if it's a callable
    if isCallable(uivalue) then
        uivalue = uivalue()
    end
    -- finally, check if it's an axuielement
    return isUIElement(uivalue) and uivalue or nil
end

--- fn.ax.uielementList(value) -> table of axuielement | nil
--- Function
--- Returns the `axuielement` list for the given `value`, if available.
---
--- Parameters:
---  * value - The value to get the `axuielement` list from.
---
--- Returns:
---  * The `axuielement` list for the given `value` or `nil`.
---
--- Notes:
---   * If the `value` is a `table` with a `UI` field, the `UI` field is called and the result is returned if it is a list.
---   * If the `value` is callable (i.e. a `function`), it is called and the result is returned if it is a list.
---   * If the `value` is a `table`, it is returned.
---   * Otherwise, `nil` is returned.
local function uielementList(value)
    -- first, check if it's an element with a UI field
    if isTable(value) and isCallable(value.UI) then
        value = value:UI()
    end
    -- then, check if it's a callable
    if isCallable(value) then
        value = value()
    end
    -- finally, check if it's a list
    if isTable(value) then
        return value
    end
    return nil
end

mod.isUIElement = isUIElement
mod.uielement = uielement
mod.uielementList = uielementList

--- cp.fn.ax.children(value) -> table | nil
--- Function
--- Returns the children of the given `value`.
---
--- Parameters:
---  * value - The value to get the children from.
---
--- Returns:
---  * The children of the given `value` or `nil`.
---
--- Notes:
---   * If it is a `table` with a `AXChildren` field, the `AXChildren` field is returned.
---   * If it is a `table` with a `UI` field, the `UI` field is called and the result is returned.
---   * If it is a `table` with a `children` function, it is called and the result is returned.
---   * If it is a `table` with a `children` field, the `children` field is returned.
---   * Otherwise, if it's any `table`, that table is returned.
mod.children = fn.any(
    -- if it is a uielement that has `AXChildren` then use that
    chain // uielement >> get "AXChildren",
    -- if it's a resolvable uielementList, then use that
    uielementList,
    -- if it has a `children` method then call that
    fn.table.call "children",
    -- if it has a `children` field that is a table then return that
    chain // get "children" >> fn.value.filter(is.table)
)

--- cp.fn.ax.childrenMatching(predicate[, comparator]) -> table of axuielement | nil
--- Function
--- Returns the children of the given `uivalue` that match the given `predicate`.
---
--- Parameters:
---  * predicate - The predicate to match.
---  * comparator - An optional comparator to use. Defaults to [topDown](#topDown).
---
--- Returns:
---  * A table of `axuielement`s that match the given `predicate`.
function mod.childrenMatching(predicate, comparator)
    comparator = comparator or mod.topDown
    return chain // mod.children >> ifilter(predicate) >> sort(comparator)
end

--- cp.fn.ax.childMatching(predicate[, index][, comparator]) -> function(uivalue) -> axuielement | nil
--- Function
--- Returns a function that will return the first child of the given `uivalue` that matches the given `predicate`.
---
--- Parameters:
---  * predicate - A function that will be called with the child `axuielement` and should return `true` if the child matches.
---  * index - An optional number that will be used to determine the child to return. Defaults to `1`.
---  * comparator - An optional function that will be called with the child `axuielement` and should return `true` if the child matches. Defaults to [`cp.fn.ax.topDown`](cp.fn.ax.md#topDown).
---
--- Returns:
---  * A function that will return the first child of the given `uivalue` that matches the given `predicate`.
function mod.childMatching(predicate, index, comparator)
    if is.callable(index) then
        comparator, index = index, nil
    end
    index = index or 1
    comparator = comparator or mod.topDown

    return function(uivalue)
        local children = mod.children(uivalue)
        if children then
            if comparator then
                table.sort(children, comparator)
            end
            local found = 0
            for _, child in ipairs(children) do
                if predicate(child) then
                    found = found + 1
                end
                if found >= index then
                    return child
                end
            end
        end
    end
end

--- cp.fn.ax.childWith(attribute, value) -> function(uivalue) -> axuielement | nil
--- Function
--- Returns a function that will return the first child of the given `uivalue` that has the given `attribute` set to `value`.
---
--- Parameters:
---  * attribute - The attribute to check.
---  * value - The value to check.
---
--- Returns:
---  * A function that will return the first child of the given `uivalue` that has the given `attribute` set to `value`.
mod.childWith = pipe(mod.hasAttributeValue, mod.childMatching)

--- cp.fn.ax.performAction(action) -> function(uivalue) -> axuielement | false | nil, errString
--- Function
--- Performs the given `action` on the given `uivalue`.
---
--- Parameters:
---  * action - The action to perform (e.g. "AXPress")
---
--- Returns:
---  * A function that accepts an `axuielement` [uivalue](#uielement) which in turn returns the result of performing the action.
function mod.performAction(action)
    return function(uivalue)
        local element = uielement(uivalue)
        if element then
            return element:performAction(action)
        end
        return nil, "No axuielement to perform action on"
    end
end

--- cp.fn.ax.hasAttributeValue(attribute, value) -> function(uivalue) -> boolean
--- Function
--- Returns a function that returns `true` if the given `uivalue` has the given `attribute` set to the `value`.
---
--- Parameters:
---  * attribute - The attribute to check for.
---  * value - The value to check for.
---
--- Returns:
---  * A function that accepts an `axuielement` [uivalue](#uielement) which in turn returns `true` if the `uivalue` has the given `attribute` set to the `value`.
function mod.hasAttributeValue(attribute, value)
    return function(uivalue)
        local element = uielement(uivalue)
        if element then
            return element:attributeValue(attribute) == value
        end
        return false
    end
end

--- cp.fn.ax.hasRole(role) -> function(uivalue) -> boolean
--- Function
--- Returns a function that returns `true` if the given `uivalue` has the given `AXRole`.
---
--- Parameters:
---  * role - The role to check for.
---
--- Returns:
---  * A function that accepts an `axuielement` [uivalue](#uielement) which in turn returns `true` if the `uivalue` has the given `AXRole`.
mod.hasRole = fn.with("AXRole", mod.hasAttributeValue)

-- ========================================================
-- Comparators
-- ========================================================

--- cp.fn.ax.leftToRight(a, b) -> boolean
--- Function
--- Returns `true` if element `a` is left of element `b`. May be used with `table.sort`.
---
--- Parameters:
---  * a - The first element
---  * b - The second element
---
--- Returns:
---  * `true` if `a` is left of `b`.
function mod.leftToRight(a, b)
    local aFrame, bFrame = a:attributeValue("AXFrame"), b:attributeValue("AXFrame")
    return (aFrame ~= nil and bFrame ~= nil and aFrame.x < bFrame.x) or false
end

--- cp.fn.ax.rightToLeft(a, b) -> boolean
--- Function
--- Returns `true` if element `a` is right of element `b`. May be used with `table.sort`.
---
--- Parameters:
---  * a - The first element
---  * b - The second element
---
--- Returns:
---  * `true` if `a` is right of `b`.
function mod.rightToLeft(a, b)
    local aFrame, bFrame = a:attributeValue("AXFrame"), b:attributeValue("AXFrame")
    return (aFrame ~= nil and bFrame ~= nil and aFrame.x + aFrame.w > bFrame.x + bFrame.w) or false
end

--- cp.fn.ax.topToBottom(a, b) -> boolean
--- Function
--- Returns `true` if element `a` is above element `b`. May be used with `table.sort`.
---
--- Parameters:
---  * a - The first element
---  * b - The second element
---
--- Returns:
---  * `true` if `a` is above `b`.
function mod.topToBottom(a, b)
    local aFrame, bFrame = a:attributeValue("AXFrame"), b:attributeValue("AXFrame")
    return (aFrame ~= nil and bFrame ~= nil and aFrame.y < bFrame.y) or false
end

--- cp.fn.ax.bottomToTop(a, b) -> boolean
--- Function
--- Returns `true` if element `a` is below element `b`. May be used with `table.sort`.
---
--- Parameters:
---  * a - The first element
---  * b - The second element
---
--- Returns:
---  * `true` if `a` is below `b`.
function mod.bottomToTop(a, b)
    local aFrame, bFrame = a:attributeValue("AXFrame"), b:attributeValue("AXFrame")
    return (aFrame ~= nil and bFrame ~= nil and aFrame.y + aFrame.h > bFrame.y + bFrame.h) or false
end

--- cp.fn.ax.topDown(a, b) -> boolean
--- Function
--- Compares two `axuielement`s based on their top-to-bottom, left-to-right position.
---
--- Parameters:
---  * a - The first `axuielement` to compare.
---  * b - The second `axuielement` to compare.
---
--- Returns:
---  * `true` if `a` is above or to the left of `b` in the UI, `false` otherwise.
mod.topDown = fn.compare(mod.topToBottom, mod.leftToRight)

--- cp.fn.ax.bottomUp(a, b) -> boolean
--- Function
--- Compares two `axuielement`s based on their bottom-to-top, right-to-left position.
---
--- Parameters:
---  * a - The first `axuielement` to compare.
---  * b - The second `axuielement` to compare.
---
--- Returns:
---  * `true` if `a` is below or to the right of `b` in the UI, `false` otherwise.
mod.bottomUp = fn.compare(mod.bottomToTop, mod.rightToLeft)

--- cp.fn.ax.init(elementType, ...) -> function(parent, uiFinder) -> cp.ui.Element
--- Function
--- Creates a function that will create a new `cp.ui.Element` of the given `elementType` with the given `parent` and `uiFinder`.
--- Any additional arguments will be passed to the `elementType` constructor after the `parent` and `uiFinder`.
--- If any of the additional arguments are a `function`, they will be called with the `parent` and `uiFinder` as the first two arguments
--- when being passed into the constructor.
---
--- Parameters:
---  * elementType - The type of `cp.ui.Element` to create.
---  * ... - Any additional arguments to pass to the `elementType` constructor.
---
--- Returns:
---  * A function that will create a new `cp.ui.Element` of the given `elementType` with the given `parent` and `uiFinder`.
function mod.init(elementType, ...)
    -- map the arguments and convert any which are not functions to constant functions
    local args = map(pack(...), function(arg)
        if isCallable(arg) then
            return arg
        else
            return constant(arg)
        end
    end)

    -- return the function that will create the element
    return function(parent, uiFinder)
        -- map calls for the argument functions, passing in the parent and uiFinder
        local mappedArgs = map(args, function(arg)
            return arg(parent, uiFinder)
        end)
        -- construct the Element
        return elementType(parent, uiFinder, unpack(mappedArgs))
    end
end

--- cp.fn.ax.prop(uiFinder, attributeName[, settable]) -> cp.prop
--- Function
--- Creates a new `cp.prop` which will find the `hs.axuielement` via the `uiFinder` and
--- get/set the value (if settable is `true`).
---
--- Parameters:
---  * uiFinder      - the `cp.prop` or `function` which will retrieve the current `hs.axuielement`.
---  * attributeName - the `AX` atrribute name the property links to.
---  * settable      - Defaults to `false`. If `true`, the property will also be settable.
---
--- Returns:
---  * The `cp.prop` for the attribute.
---
--- Notes:
---  * If the `uiFinder` is a `cp.prop`, it will be monitored for changes, making the resulting `prop` "live".
function mod.prop(uiFinder, attributeName, settable)
    if prop.is(uiFinder) then
        return uiFinder:mutate(
            chain // uielement >> get(attributeName),
            settable and function(newValue, original)
                local ui = original()
                return ui and ui:setAttributeValue(attributeName, newValue)
            end
        )
    end
end

--- cp.fn.ax.matchesIf(...) -> function(value) -> boolean
--- Function
--- Creates a `function` which will return `true` if the `value` is either an `axuielement`,
--- an [Element](cp.ui.Element.md), or a `callable` (function) that returns an `axuielement` that matches the predicate.
---
--- Parameters:
---  * ... - Any number of predicates, all of which must return a `truthy` value for the `value` to match.
---
--- Returns:
---  * A `function` which will return `true` if the `value` is a match.
function mod.matchesIf(...)
    return pipe(
        chain // uielement >> fn.all(...),
        isTruthy
    )
end

return mod