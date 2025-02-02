--- === cp.ui.axutils ===
---
--- Utility functions to support `hs.axuielement`.

local require = require

local log           = require "hs.logger".new "axutils"

local canvas        = require "hs.canvas"
local eventtap      = require "hs.eventtap"
local fnutils       = require "hs.fnutils"
local geometry      = require "hs.geometry"

local is            = require "cp.is"
local prop          = require "cp.prop"
local tools         = require "cp.tools"

local sort          = table.sort

local axutils = {}

--- cp.ui.axutils.valueOf(element, name[, default]) -> anything
--- Function
--- Returns the named `AX` attribute value, or the `default` if it is empty.
---
--- Parameters:
--- * element - the `axuielement` to retrieve the attribute value for.
--- * attribute - The attribute name (e.g. "AXValue")
--- * default - (optional) if provided, this will be returned if the attribute is `nil`.
---
--- Returns:
--- * The attribute value, or the `default` if none is found.
function axutils.valueOf(element, attribute, default)
    if axutils.isValid(element) then
        return element:attributeValue(attribute) or default
    end
end

--- cp.ui.axutils.childrenInLine(element) -> table | nil
--- Function
--- Gets a table of children that are all in the same family and line as the
--- supplied element.
---
--- Parameters:
---  * element     - The base element.
---
--- Returns:
---  * The table of `axuielement` objects, otherwise `nil`.
function axutils.childrenInLine(element)
    local elements = element and element:attributeValue("AXParent")
    local children = elements and elements:attributeValue("AXChildren")
    local baseFrame = element and element:attributeValue("AXFrame")
    local result = {}
    if children and baseFrame then
        baseFrame = geometry.new(baseFrame)
        for _, child in pairs(children) do
             local childFrame = child:attributeValue("AXFrame")
             if baseFrame:intersect(childFrame).h > 0 then
                table.insert(result, child)
             end
        end
        return result
    end
end

--- cp.ui.axutils.childrenInNextLine(element) -> table | nil
--- Function
--- Gets a table of children that are in the next line in relation to the supplied
--- element. Scrollbars will be ignored.
---
--- Parameters:
---  * element - The base element.
---
--- Returns:
---  * The table of `axuielement` objects, otherwise `nil`.
function axutils.childrenInNextLine(element)
    local parent = element and element:attributeValue("AXParent")
    local childrenInLine = element and axutils.childrenInLine(element)
    local highestIndex = 0
    if childrenInLine then
        for _, child in pairs(childrenInLine) do
            if child:attributeValue("AXRole") ~= "AXScrollBar" then
                local childIndex = axutils.childIndex(child)
                if childIndex and childIndex > highestIndex then
                    highestIndex = childIndex
                end
            end
        end
    end
    if element and parent and highestIndex ~= 0 and parent:attributeValue("AXChildren")[highestIndex + 1] then
        return axutils.childrenInLine(parent:attributeValue("AXChildren")[highestIndex + 1])
    end
end

--- cp.ui.axutils.childrenInColumn(element, role, startIndex) -> table | nil
--- Function
--- Finds the children for an element, then checks to see if they match the supplied
--- role. It then compares the vertical position data of all matching children
--- and returns a table with only the elements that line up to the element defined
--- by the startIndex.
---
--- Parameters:
---  * element     - The element to retrieve the children from.
---  * role        - The required role as a string.
---  * startIndex  - A number which defines the index of the first element to use.
---
--- Returns:
---  * The table of `axuielement` objects, otherwise `nil`.
function axutils.childrenInColumn(element, role, startIndex, childIndex)
    local children = axutils.childrenWith(element, "AXRole", role)
    if children and #children >= 2 then
        local baseElement = children[startIndex]
        if baseElement then
            local frame = baseElement:attributeValue("AXFrame")
            if frame then
                local result = {}
                for i=startIndex, #children do
                    local child = children[i]
                    local f = child and child:attributeValue("AXFrame")
                    if child and f.x >= frame.x and f.x <= frame.x + frame.w then
                        table.insert(result, child)
                    end
                end
                if next(result) ~= nil then
                    if childIndex then
                        if result[childIndex] then
                            return result[childIndex]
                        end
                    else
                        return result
                    end
                end
            end
        end
    end
end

--- cp.ui.axutils.childInColumn(element, role, startIndex, childIndex) -> table | nil
--- Function
--- Finds the children for an element, then checks to see if they match the supplied
--- role. It then compares the vertical position data of all matching children
--- and returns an element defined by the `childIndex`, which lines up vertially
--- with the element defined by the `startIndex`.
---
--- Parameters:
---  * element     - The element to retrieve the children from.
---  * role        - The required role as a string.
---  * startIndex  - A number which defines the index of the first element to use.
---  * childIndex  - A number which defines the index of the element to return.
---
--- Returns:
---  * The `axuielement` if it matches, otherwise `nil`.
function axutils.childInColumn(element, role, startIndex, childIndex)
    return axutils.childrenInColumn(element, role, startIndex, childIndex)
end

--- cp.ui.axutils.children(element[, compareFn]) -> table
--- Function
--- Finds the children for the element. If it is an `hs.axuielement`, it will
--- attempt to get the `AXChildren` attribute. If it is a table with a `children` function,
--- that will get called. If no children exist, an empty table will be returned.
---
--- Parameters:
---  * element      - The element to retrieve the children of.
---  * compareFn    - Optional function to use to sort the order of the returned children.
---
--- Returns:
---  * a table of children
function axutils.children(element, compareFn)
    local children = element

    if element and is.callable(element.children) then
        --------------------------------------------------------------------------------
        -- There is a `children` function, priorise that.
        --------------------------------------------------------------------------------
        children = element:children()
    elseif element and element.attributeValue then
        --------------------------------------------------------------------------------
        -- It's an AXUIElement:
        --------------------------------------------------------------------------------
        children = element:attributeValue("AXChildren") or element
    end

    if type(children) == "table" then
        if type(compareFn) == "function" then
            sort(children, compareFn)
        end
        return children
    end
    return {}
end

--- cp.ui.axutils.childrenBelow(element, topElement) -> table of axuielement or nil
--- Function
--- Finds the list of `axuielement` children from the `element` which are below the specified `topElement`.
--- If the `element` is `nil`, `nil` is returned. If the `topElement` is `nil` all children are returned.
---
--- Parameters:
--- * element - The `axuielement` to find the children of.
--- * topElement - The `axuielement` that the other children must be below.
---
--- Returns:
--- * The table of `axuielements` that are below, or `nil` if the element is not available.
function axutils.childrenBelow(element, topElement)
    return element and axutils.childrenMatching(element, axutils.match.isBelow(topElement))
end

--- cp.ui.axutils.childrenAbove(element, bottomElement) -> table of axuielement or nil
--- Function
--- Finds the list of `axuielement` children from the `element` which are above the specified `bottomElement`.
--- If the `element` is `nil`, `nil` is returned. If the `topElement` is `nil` all children are returned.
---
--- Parameters:
--- * element - The `axuielement` to find the children of.
--- * topElement - The `axuielement` that the other children must be above.
---
--- Returns:
--- * The table of `axuielements` that are above, or `nil` if the element is not available.
function axutils.childrenAbove(element, bottomElement)
    return element and axutils.childrenMatching(element, axutils.match.isAbove(bottomElement))
end

--- cp.ui.axutils.hasAttributeValue(element, name, value) -> boolean
--- Function
--- Checks to see if an element has a specific value.
---
--- Parameters:
---  * element  - the `axuielement`
---  * name     - the name of the attribute
---  * value    - the value of the attribute
---
--- Returns:
---  * `true` if the `element` has the supplied attribute value, otherwise `false`.
function axutils.hasAttributeValue(element, name, value)
    return element and element:attributeValue(name) == value
end

--- cp.ui.axutils.withAttributeValue(element, name, value) -> hs.axuielement | nil
--- Function
--- Checks if the element has an attribute value with the specified `name` and `value`.
--- If so, the element is returned, otherwise `nil`.
---
--- Parameters:
---  * element       - The element to check
---  * name          - The name of the attribute to check
---  * value         - The value of the attribute
---
--- Returns:
---  * The `axuielement` if it matches, otherwise `nil`.
function axutils.withAttributeValue(element, name, value)
    return axutils.hasAttributeValue(element, name, value) and element or nil
end

--- cp.ui.axutils.withRole(element, role) -> hs.axuielement | nil
--- Function
--- Checks if the element has an "AXRole" attribute with the specified `role`.
--- If so, the element is returned, otherwise `nil`.
---
--- Parameters:
---  * element       - The element to check
---  * role          - The required role
---
--- Returns:
---  * The `axuielement` if it matches, otherwise `nil`.
function axutils.withRole(element, role)
    return axutils.withAttributeValue(element, "AXRole", role)
end

--- cp.ui.axutils.withValue(element, value) -> hs.axuielement | nil
--- Function
--- Checks if the element has an "AXValue" attribute with the specified `value`.
--- If so, the element is returned, otherwise `nil`.
---
--- Parameters:
---  * element       - The element to check
---  * value         - The required value
---
--- Returns:
---  * The `axuielement` if it matches, otherwise `nil`.
function axutils.withValue(element, value)
    return axutils.withAttributeValue(element, "AXValue", value)
end

--- cp.ui.axutils.withTitle(element, title) -> hs.axuielement | nil
--- Function
--- Checks if the element has an "AXTitle" attribute with the specified `title`.
--- If so, the element is returned, otherwise `nil`.
---
--- Parameters:
---  * element       - The element to check
---  * title         - The required title
---
--- Returns:
---  * The `axuielement` if it matches, otherwise `nil`.
function axutils.withTitle(element, title)
    return axutils.withAttributeValue(element, "AXTitle", title)
end

--- cp.ui.axutils.childWith(element, name, value) -> axuielement
--- Function
--- This searches for the first child of the specified element which has an attribute with the matching name and value.
---
--- Parameters:
---  * element  - the axuielement
---  * name     - the name of the attribute
---  * value    - the value of the attribute
---
--- Returns:
---  * The first matching child, or nil if none was found
function axutils.childWith(element, name, value)
    return axutils.childMatching(element, function(child) return axutils.hasAttributeValue(child, name, value) end)
end

--- cp.ui.axutils.childWithID(element, value) -> axuielement
--- Function
--- This searches for the first child of the specified element which has `AXIdentifier` with the specified value.
---
--- Parameters:
---  * element  - the axuielement
---  * value    - the value
---
--- Returns:
---  * The first matching child, or `nil` if none was found
function axutils.childWithID(element, value)
    return axutils.childWith(element, "AXIdentifier", value)
end

--- cp.ui.axutils.childWithRole(element, value) -> axuielement
--- Function
--- This searches for the first child of the specified element which has `AXRole` with the specified value.
---
--- Parameters:
---  * element  - the axuielement
---  * value    - the value
---
--- Returns:
---  * The first matching child, or `nil` if none was found
function axutils.childWithRole(element, value)
    return axutils.childWith(element, "AXRole", value)
end

--- cp.ui.axutils.childWithTitle(element, value) -> axuielement
--- Function
--- This searches for the first child of the specified element which has `AXTitle` with the specified value.
---
--- Parameters:
---  * element	- the axuielement
---  * value	- the value
---
--- Returns:
---  * The first matching child, or `nil` if none was found
function axutils.childWithTitle(element, value)
    return axutils.childWith(element, "AXTitle", value)
end

--- cp.ui.axutils.childWithDescription(element, value) -> axuielement
--- Function
--- This searches for the first child of the specified element which has `AXDescription` with the specified value.
---
--- Parameters:
---  * element  - the axuielement
---  * value    - the value
---
--- Returns:
---  * The first matching child, or `nil` if none was found
function axutils.childWithDescription(element, value)
    return axutils.childWith(element, "AXDescription", value)
end

--- cp.ui.axutils.childMatching(element, matcherFn[, index]) -> axuielement
--- Function
--- This searches for the first child of the specified element for which the provided function returns `true`.
--- The function will receive one parameter - the current child.
---
--- Parameters:
---  * element      - the axuielement
---  * matcherFn    - the function which checks if the child matches the requirements.
---  * index        - the number of matching child to return. Defaults to `1`.
---
--- Returns:
---  * The first matching child, or nil if none was found
function axutils.childMatching(element, matcherFn, index)
    assert(type(matcherFn) == "function", "The matcherFn must be a function.")
    index = index or 1
    if element then
        local children = axutils.children(element)
        if children and #children > 0 then
            local count = 0
            for _,child in ipairs(children) do
                if matcherFn(child) then
                    count = count + 1
                    if count == index then
                        return child
                    end
                end
            end
        end
    end
    return nil
end

--- cp.ui.axutils.childAtIndex(element, index, compareFn[, matcherFn]) -> axuielement
--- Function
--- Searches for the child element which is at number `index` when sorted using the `compareFn`.
---
--- Parameters:
---  * element      - the axuielement or array of axuielements
---  * index        - the index number of the child to find.
---  * compareFn    - a function to compare the elements.
---  * matcherFn    - an optional function which is passed each child and returns `true` if the child should be processed.
---
--- Returns:
---  * The child, or `nil` if the index is larger than the number of children.
function axutils.childAtIndex(element, index, compareFn, matcherFn)
    if element and index > 0 then
        local children = axutils.children(element)
        if children then
            if matcherFn then
                children = axutils.childrenMatching(children, matcherFn)
            end
            if #children >= index then
                sort(children, compareFn)
                return children[index]
            end
        end
    end
    return nil
end

--- === cp.ui.axutils.compare ===
---
--- Contains functions for comparing `axuielement`s.

axutils.compare = {}

--- cp.ui.axutils.compare.leftToRight(a, b) -> boolean
--- Function
--- Returns `true` if element `a` is left of element `b`. May be used with `table.sort`.
---
--- Parameters:
---  * a - The first element
---  * b - The second element
---
--- Returns:
---  * `true` if `a` is left of `b`.
function axutils.compare.leftToRight(a, b)
    local aFrame = a and a:attributeValue("AXFrame")
    local bFrame = b and b:attributeValue("AXFrame")
    return (type(aFrame) == "table" and type(bFrame) == "table" and aFrame.x < bFrame.x) or false
end

--- cp.ui.axutils.compare.rightToLeft(a, b) -> boolean
--- Function
--- Returns `true` if element `a` is right of element `b`. May be used with `table.sort`.
---
--- Parameters:
---  * a - The first element
---  * b - The second element
---
--- Returns:
---  * `true` if `a` is right of `b`.
function axutils.compare.rightToLeft(a, b)
    local aFrame = a and a:attributeValue("AXFrame")
    local bFrame = b and b:attributeValue("AXFrame")
    return (type(aFrame) == "table" and type(bFrame) == "table" and aFrame.x + aFrame.w > bFrame.x + bFrame.w) or false
end

--- cp.ui.axutils.compare.topToBottom(a, b) -> boolean
--- Function
--- Returns `true` if element `a` is above element `b`. May be used with `table.sort`.
---
--- Parameters:
---  * a - The first element
---  * b - The second element
---
--- Returns:
---  * `true` if `a` is above `b`.
function axutils.compare.topToBottom(a, b)
    local aFrame = a and a:attributeValue("AXFrame")
    local bFrame = b and b:attributeValue("AXFrame")
    return (type(aFrame) == "table" and type(bFrame) == "table" and aFrame.y < bFrame.y) or false
end

--- cp.ui.axutils.compare.bottomToTop(a, b) -> boolean
--- Function
--- Returns `true` if element `a` is below element `b`. May be used with `table.sort`.
---
--- Parameters:
---  * a - The first element
---  * b - The second element
---
--- Returns:
---  * `true` if `a` is below `b`.
function axutils.compare.bottomToTop(a, b)
    local aFrame = a and a:attributeValue("AXFrame")
    local bFrame = b and b:attributeValue("AXFrame")
    return (type(aFrame) == "table" and type(bFrame) == "table" and aFrame.y + aFrame.h > bFrame.y + bFrame.h) or false
end

--- cp.ui.axutils.childFromLeft(element, index[, matcherFn]) -> axuielement
--- Function
--- Searches for the child element which is at number `index` when sorted left-to-right.
---
--- Parameters:
---  * element      - the axuielement or array of axuielements
---  * index        - the index number of the child to find.
---  * matcherFn    - an optional function which is passed each child and returns `true` if the child should be processed.
---
--- Returns:
---  * The child, or `nil` if the index is larger than the number of children.
function axutils.childFromLeft(element, index, matcherFn)
    return axutils.childAtIndex(element, index, axutils.compare.leftToRight, matcherFn)
end

--- cp.ui.axutils.childFromRight(element, index[, matcherFn]) -> axuielement
--- Function
--- Searches for the child element which is at number `index` when sorted right-to-left.
---
--- Parameters:
---  * element      - the axuielement or array of axuielements
---  * index        - the index number of the child to find.
---  * matcherFn    - an optional function which is passed each child and returns `true` if the child should be processed.
---
--- Returns:
---  * The child, or `nil` if the index is larger than the number of children.
function axutils.childFromRight(element, index, matcherFn)
    return axutils.childAtIndex(element, index, axutils.compare.rightToLeft, matcherFn)
end

--- cp.ui.axutils.childFromTop(element, index[, matcherFn]) -> axuielement
--- Function
--- Searches for the child element which is at number `index` when sorted top-to-bottom.
---
--- Parameters:
---  * element      - the axuielement or array of axuielements
---  * index        - the index number of the child to find.
---  * matcherFn    - an optional function which is passed each child and returns `true` if the child should be processed.
---
--- Returns:
---  * The child, or `nil` if the index is larger than the number of children.
function axutils.childFromTop(element, index, matcherFn)
    return axutils.childAtIndex(element, index, axutils.compare.topToBottom, matcherFn)
end

--- cp.ui.axutils.childFromBottom(element, index) -> axuielement
--- Function
--- Searches for the child element which is at number `index` when sorted bottom-to-top.
---
--- Parameters:
---  * element      - the axuielement or array of axuielements
---  * index        - the index number of the child to find.
---  * matcherFn    - an optional function which is passed each child and returns `true` if the child should be processed.
---
--- Returns:
---  * The child, or `nil` if the index is larger than the number of children.
function axutils.childFromBottom(element, index, matcherFn)
    return axutils.childAtIndex(element, index, axutils.compare.bottomToTop, matcherFn)
end

--- cp.ui.axutils.childrenWith(element, name, value) -> axuielement
--- Function
--- This searches for all children of the specified element which has an attribute with the matching name and value.
---
--- Parameters:
---  * element  - the axuielement
---  * name     - the name of the attribute
---  * value    - the value of the attribute
---
--- Returns:
---  * All matching children, or `nil` if none was found
function axutils.childrenWith(element, name, value)
    return axutils.childrenMatching(element, function(child) return axutils.hasAttributeValue(child, name, value) end)
end

--- cp.ui.axutils.childrenWithRole(element, value) -> axuielement
--- Function
--- This searches for all children of the specified element which has an `AXRole` attribute with the matching value.
---
--- Parameters:
---  * element  - the axuielement
---  * value    - the value of the attribute
---
--- Returns:
---  * All matching children, or `nil` if none was found
function axutils.childrenWithRole(element, value)
    return axutils.childrenWith(element, "AXRole", value)
end

--- cp.ui.axutils.childrenMatching(element, matcherFn) -> { axuielement }
--- Function
--- This searches for all children of the specified element for which the provided
--- function returns `true`. The function will receive one parameter - the current child.
---
--- Parameters:
---  * element  - the axuielement
---  * matcherFn    - the function which checks if the child matches the requirements.
---
--- Returns:
---  * All matching children, or `nil` if none was found
function axutils.childrenMatching(element, matcherFn)
    if element then
        return fnutils.ifilter(axutils.children(element), matcherFn)
    end
    return nil
end

--- cp.ui.axutils.hasChild(element, matcherFn) -> boolean
--- Function
--- Checks if the axuielement has a child that passes the `matcherFn`.
---
--- Parameters:
--- * element - the `axuielement` to check.
--- * matcherFn - the `function` that accepts an `axuielement` and returns a `boolean`
---
--- Returns:
--- * `true` if any child matches, otherwise `false`.
function axutils.hasChild(element, matcherFn)
    return axutils.childMatching(element, matcherFn) ~= nil
end

--- cp.ui.axutils.childIndex(element) -> number or nil
--- Function
--- Finds the index of the specified child element, if it is present. If not, `nil` is returned.
---
--- Parameters:
--- * element - The `axuielement` to find the index of.
---
--- Returns:
--- * The index (`1` or higher) of the `element`, or `nil` if it was not found.
function axutils.childIndex(element)
    local parent = element:attributeValue("AXParent")
    local children = parent and axutils.children(parent)
    if children and #children > 0 then
        for i,child in ipairs(children) do
            if child == element then
                return i
            end
        end
    end
end

--- cp.ui.axutils.isValid(element) -> boolean
--- Function
--- Checks if the axuilelement is still valid - that is, still active in the UI.
---
--- Parameters:
---  * element  - the axuielement
---
--- Returns:
---  * `true` if the element is valid.
function axutils.isValid(element)
    if element ~= nil and type(element) ~= "userdata" then
        error(string.format("The element must be \"userdata\" but was %q.", type(element)))
    end
    return element ~= nil and element:isValid()
end

-- isInvalid(value[, verifyFn]) -> boolean
-- Function
-- Checks to see if an `axuielement` is invalid.
--
-- Parameters:
--  * value     - an `axuielement` object.
--  * verifyFn  - an optional function which will check the cached element to verify it is still valid.
--
-- Returns:
--  * `true` if the `value` is invalid or not verified, otherwise `false`.
local function isInvalid(value, verifyFn)
    return value == nil or not axutils.isValid(value) or verifyFn and not verifyFn(value)
end

--- cp.ui.axutils.cache(source, key, finderFn[, verifyFn]) -> axuielement
--- Function
--- Checks if the cached value at the `source[key]` is a valid axuielement. If not
--- it will call the provided `finderFn()` function (with no arguments), cache the result and return it.
---
--- If the optional `verifyFn` is provided, it will be called to check that the cached
--- value is still valid. It is passed a single parameter (the axuielement) and is expected
--- to return `true` or `false`.
---
--- Parameters:
---  * source       - the table containing the cache
---  * key          - the key the value is cached under
---  * finderFn     - the function which will return the element if not found.
---  * [verifyFn]   - an optional function which will check the cached element to verify it is still valid.
---
--- Returns:
---  * The valid cached value.
function axutils.cache(source, key, finderFn, verifyFn)
    local value
    if source then
        value = source[key]
    end

    if value == nil or isInvalid(value, verifyFn) then
        value = finderFn()
        if isInvalid(value, verifyFn) then
            value = nil
        end
    end

    if source then
        source[key] = value
    end

    return value
end

--- cp.ui.axutils.snapshot(element[, filename]) -> hs.image
--- Function
--- Takes a snapshot of the specified `axuielement` and returns it.
--- If the `filename` is provided it also saves the file to the specified location.
---
--- Parameters:
---  * element      - The `axuielement` to snap.
---  * filename     - (optional) The path to save the image as a PNG file.
---  * elementFrame - (optional) The hs.geometry frame of what you want to capture
---
--- Returns:
---  * An `hs.image` file, or `nil` if the element could not be snapped.
function axutils.snapshot(element, filename, elementFrame)
    if axutils.isValid(element) then
        local window = element:attributeValue("AXWindow")
        if window then
            local hsWindow = window:asHSWindow()

            local isSecureInputEnabled = eventtap.isSecureInputEnabled()
            local windowSnap = hsWindow and hsWindow:snapshot()
            if not windowSnap then
                if isSecureInputEnabled then
                    local secureInputApplicationTitle = tools.secureInputApplicationTitle()
                    if secureInputApplicationTitle then
                        log.ef("[cp.ui.axutils.snapshot] Snapshot could not be captured because '%s' has enabled 'Secure Input'. Please try closing any password prompts or permission dialog boxes it has open.", secureInputApplicationTitle)
                    else
                        log.ef("[cp.ui.axutils.snapshot] Snapshot could not be captured because another application has enabled 'Secure Input'. Please try closing any open password prompts or permission dialog boxes.")
                    end
                else
                    log.ef("[cp.ui.axutils.snapshot] Snapshot could not be captured, so aborting. 'Secure Input' was not enabled.")
                end
                return
            end

            local windowFrame = window and window:attributeValue("AXFrame")
            if not windowFrame then
                log.ef("[cp.ui.axutils.snapshot] Failed to get the window frame, so aborting.")
                return
            end

            local shotSize = windowSnap and windowSnap:size()

            local ratio = shotSize and windowFrame and shotSize.h / windowFrame.h
            elementFrame = elementFrame or (element and element:attributeValue("AXFrame"))

            local imageFrame = {
                x = (windowFrame.x-elementFrame.x)*ratio,
                y = (windowFrame.y-elementFrame.y)*ratio,
                w = shotSize.w,
                h = shotSize.h,
            }

            local c = canvas.new({w=elementFrame.w*ratio, h=elementFrame.h*ratio})
            c[1] = {
                type = "image",
                image = windowSnap,
                imageScaling = "none",
                imageAlignment = "topLeft",
                frame = imageFrame,
            }

            local elementSnap = c:imageFromCanvas()

            if filename then
                elementSnap:saveToFile(filename)
            end

            return elementSnap
        end
    end
    return nil
end

--- cp.ui.axutils.prop(uiFinder, attributeName[, settable]) -> cp.prop
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
function axutils.prop(uiFinder, attributeName, settable)
    if prop.is(uiFinder) then
        return uiFinder:mutate(function(original)
            local ui = original()
            return ui and ui:attributeValue(attributeName)
        end,
        settable and function(newValue, original)
            local ui = original()
            return ui and ui:setAttributeValue(attributeName, newValue)
        end
    )
    end
end

--- === cp.ui.axutils.match ===
---
--- Contains common `hs.axuielement` matching functions.

axutils.match = {}

--- cp.ui.axutils.match.role(roleName) -> function
--- Function
--- Returns a `match` function that will return true if the `axuielement` has the specified `AXRole`.
---
--- Parameters:
---  * roleName  - The role to check for.
---
--- Returns:
---  * `function(element) -> boolean` that checks the `AXRole` is `roleName`
function axutils.match.role(roleName)
    return function(element)
        return axutils.hasAttributeValue(element, "AXRole", roleName)
    end
end

--- cp.ui.axutils.match.exactly(value) -> function
--- Function
--- Returns a `match` function that will return true if the `axuielement` matches the provided value exactly.
---
--- Parameters:
---  * value  - The value to check for.
---
--- Returns:
---  * `function(element) -> boolean` that checks the value matches exactly.
function axutils.match.exactly(value)
    return function(element)
        return element == value
    end
end

--- cp.ui.axutils.match.emptyList(element) -> function
--- Function
--- Returns a `match` function that will return true if `element` is an empty list, or has no children.
---
--- Parameters:
---  * element  - The `axuielement` to check.
---
--- Returns:
---  * `true` if the element is an empty list.
function axutils.match.emptyList(element)
    return element and #element == 0
end


-- cp.ui.axutils.match.containsOnly(values) -> function
-- Function
-- Returns a "match" function which will check its input value to see if it is a table which contains the same values in any order.
--
-- Parameters:
-- * values     - A [Set](cp.collect.Set.md) or `table` specifying exactly what items must be in the matching table, in any order.
--
-- Returns:
-- * A `function` that will accept a single input value, which will only return `true` the input is a `table` containing exactly the items in `values` in any order.
function axutils.match.containsOnly(values)
    return function(other)
        if other and values and #other == #values then
            for _,v in ipairs(other) do
                if not tools.tableContains(values, v) then
                    return false
                end
            end
            return true
        end
        return false
    end
end

--- cp.ui.axutils.match.isBelow(value) -> function
--- Function
--- Returns a `match` function that will return `true` if the `axuielement` is below the provided `value` `axuielement`.
---
--- Parameters:
---  * value  - The `axuielement` to check.
---
--- Returns:
---  * A function returning `true` if the element is below the provided `value`.
function axutils.match.isBelow(value)
    return function(other)
        if other == nil then
            return false
        elseif value == nil then
            return true
        else
            local aFrame = value:attributeValue("AXFrame")
            local bFrame = other:attributeValue("AXFrame")
            return aFrame.y + aFrame.h < bFrame.y
        end
    end
end

--- cp.ui.axutils.match.isAbove(value) -> function
--- Function
--- Returns a `match` function that will return `true` if the `axuielement` is above the provided `value` `axuielement`.
---
--- Parameters:
---  * value  - The `axuielement` to check.
---
--- Returns:
---  * A function returning `true` if the element is above the provided `value`.
function axutils.match.isAbove(value)
    return function(other)
        if other == nil then
            return false
        elseif value == nil then
            return true
        else
            local aFrame = value:attributeValue("AXFrame")
            local bFrame = other:attributeValue("AXFrame")
            return aFrame.y < bFrame.y + bFrame.h
        end
    end
end

--- cp.ui.axutils.match.isLeftOf(value) -> function
--- Function
--- Returns a `match` function that will return `true` if the `axuielement` is left of the provided `value` `axuielement`.
---
--- Parameters:
---  * value  - The `axuielement` to check.
---
--- Returns:
---  * A function returning `true` if the element is left of the provided `value`.
function axutils.match.isLeftOf(value)
    return function(other)
        if other == nil then
            return false
        elseif value == nil then
            return true
        else
            local aFrame = value:attributeValue("AXFrame")
            local bFrame = other:attributeValue("AXFrame")
            return aFrame.x < bFrame.x
        end
    end
end

--- cp.ui.axutils.match.isRightOf(value) -> function
--- Function
--- Returns a `match` function that will return `true` if the `axuielement` is right of the provided `value` `axuielement`.
---
--- Parameters:
---  * value  - The `axuielement` to check.
---
--- Returns:
---  * A function returning `true` if the element is right of the provided `value`.
function axutils.match.isRightOf(value)
    return function(other)
        if other == nil then
            return false
        elseif value == nil then
            return true
        else
            local aFrame = value:attributeValue("AXFrame")
            local bFrame = other:attributeValue("AXFrame")
            return aFrame.x + aFrame.w > bFrame.x + bFrame.w
        end
    end
end

return axutils
