-- CropRotationPlanUI.lua
-- Small immediate-mode toolkit for the Plans, Field groups and plan editor pages.
--
-- Those pages are drawn by the frame itself (CropRotationPlanFrame:draw) with the same engine
-- calls the on-screen plan uses (drawFilledRect, renderText, Overlay), and clicks are matched
-- against the boxes registered while drawing (CropRotationPlanFrame:mouseEvent). Sizes are given
-- in GUI pixels of the 1920x1080 reference layout and scaled like the rest of the menu.
-- Colours follow the mockups, which follow the base game menu.

CropRotationPlanUI = {}
local UI = CropRotationPlanUI

UI.C = {
    panel = { 0.17, 0.17, 0.17, 1 },        -- #2c2c2c
    panelDark = { 0.11, 0.11, 0.11, 1 },    -- #1c1c1c
    row = { 0.106, 0.106, 0.106, 1 },       -- #1b1b1b
    card = { 0.12, 0.12, 0.12, 1 },         -- #1f1f1f
    side = { 0.165, 0.165, 0.165, 1 },      -- #2a2a2a
    line = { 0.23, 0.23, 0.23, 1 },         -- #3a3a3a
    lineLight = { 0.29, 0.29, 0.29, 1 },    -- #4a4a4a
    green = { 0.65, 0.80, 0.11, 1 },        -- #a6cc1c
    greenLight = { 0.77, 0.90, 0.29, 1 },   -- #c4e64a
    greenDark = { 0.14, 0.19, 0.05, 1 },    -- #24300c
    greenSel = { 0.18, 0.23, 0.08, 1 },     -- #2f3a14
    greenRing = { 0.35, 0.42, 0.16, 1 },    -- #5a6a2a
    text = { 0.95, 0.95, 0.95, 1 },         -- #f2f2f2
    muted = { 0.78, 0.78, 0.78, 1 },        -- #c8c8c8
    faint = { 0.63, 0.63, 0.63, 1 },        -- #a0a0a0
    dark = { 0.08, 0.08, 0.08, 1 },         -- #141414
    warnBg = { 0.29, 0.16, 0.08, 1 },       -- #4a2a14
    warnFg = { 1.0, 0.70, 0.48, 1 },        -- #ffb27a
    noteBg = { 0.23, 0.17, 0.10, 1 },       -- #3a2c1a
    noteFg = { 1.0, 0.77, 0.54, 1 },        -- #ffc48a
    danger = { 0.54, 0.29, 0.20, 1 },       -- #8a4a32
    dangerFg = { 1.0, 0.69, 0.56, 1 },      -- #ffb08f
    chip = { 0.23, 0.23, 0.23, 1 },         -- #3a3a3a
    hover = { 1, 1, 1, 0.08 },
    white = { 1, 1, 1, 1 },
    footer = { 0.043, 0.043, 0.043, 1 },    -- #0b0b0b
}

---------------------------------------------------------------------------
-- Units
---------------------------------------------------------------------------

function UI.px(n)
    return n * (g_pixelSizeScaledX or (1 / 1920))
end

function UI.py(n)
    return n * (g_pixelSizeScaledY or (1 / 1080))
end

---------------------------------------------------------------------------
-- Frame state: clickable boxes and tooltip of this draw
---------------------------------------------------------------------------

function UI.begin(state)
    state.hits = {}
    state.tooltip = nil
end

function UI.isInside(state, x, y, w, h)
    local mx, my = state.mouseX, state.mouseY
    return mx ~= nil and mx >= x and mx <= x + w and my >= y and my <= y + h
end

-- Registers a clickable box. The last registered box on top wins.
-- id names the box (used by tests/smoke_test.py to click it).
function UI.hit(state, x, y, w, h, onClick, tooltip, id)
    if onClick ~= nil then
        table.insert(state.hits, { x = x, y = y, w = w, h = h, onClick = onClick, id = id })
    end
    if tooltip ~= nil and UI.isInside(state, x, y, w, h) then
        state.tooltip = tooltip
    end
end

-- Runs the click of the box under the mouse; true if one was hit
function UI.click(state, mx, my)
    if state.hits == nil then
        return false
    end
    for i = #state.hits, 1, -1 do
        local h = state.hits[i]
        if mx >= h.x and mx <= h.x + h.w and my >= h.y and my <= h.y + h.h then
            h.onClick()
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

function UI.rect(x, y, w, h, c)
    if w > 0 and h > 0 then
        drawFilledRect(x, y, w, h, c[1], c[2], c[3], c[4] or 1)
    end
end

function UI.border(x, y, w, h, c, thick)
    local tx = UI.px(thick or 2)
    local ty = UI.py(thick or 2)
    UI.rect(x, y, w, ty, c)
    UI.rect(x, y + h - ty, w, ty, c)
    UI.rect(x, y, tx, h, c)
    UI.rect(x + w - tx, y, tx, h, c)
end

function UI.dashed(x, y, w, h, c)
    local dashX, gapX = UI.px(8), UI.px(6)
    local dashY, gapY = UI.py(8), UI.py(6)
    local tx, ty = UI.px(2), UI.py(2)
    local p = 0
    while p < w do
        local len = math.min(dashX, w - p)
        UI.rect(x + p, y, len, ty, c)
        UI.rect(x + p, y + h - ty, len, ty, c)
        p = p + dashX + gapX
    end
    p = 0
    while p < h do
        local len = math.min(dashY, h - p)
        UI.rect(x, y + p, tx, len, c)
        UI.rect(x + w - tx, y + p, tx, len, c)
        p = p + dashY + gapY
    end
end

-- Shortens text to fit maxWidth
function UI.fit(text, size, maxWidth, bold)
    setTextBold(bold == true)
    -- 2px tolerance: a box made exactly as wide as its text must not shorten it (game screenshot 2026-10-30)
    if getTextWidth(size, text) <= maxWidth + UI.px(2) then
        setTextBold(false)
        return text
    end
    -- Remove whole UTF-8 characters (æ, ø, å are two bytes), never half of one
    local function dropLastChar(s)
        local i = string.len(s)
        while i > 1 do
            local b = string.byte(s, i)
            if b < 128 or b >= 192 then
                break
            end
            i = i - 1
        end
        return string.sub(s, 1, i - 1)
    end
    local s = text
    while string.len(s) > 1 and getTextWidth(size, s .. "..") > maxWidth do
        s = dropLastChar(s)
    end
    setTextBold(false)
    return s .. ".."
end

-- align: "left" (default), "center", "right"; x is the left edge, centre or right edge
function UI.text(x, y, size, text, c, align, bold)
    c = c or UI.C.text
    setTextColor(c[1], c[2], c[3], c[4] or 1)
    setTextBold(bold == true)
    if align == "center" then
        setTextAlignment(RenderText.ALIGN_CENTER)
    elseif align == "right" then
        setTextAlignment(RenderText.ALIGN_RIGHT)
    else
        setTextAlignment(RenderText.ALIGN_LEFT)
    end
    renderText(x, y, size, text)
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
end

-- Text vertically centred in a box of height h at y
function UI.textIn(x, y, h, size, text, c, align, bold)
    UI.text(x, y + (h - size) * 0.5 + size * 0.15, size, text, c, align, bold)
end

-- Wraps text into lines that fit maxWidth
function UI.wrap(text, size, maxWidth)
    local lines = {}
    local line = ""
    for word in string.gmatch(text, "%S+") do
        local candidate = line == "" and word or (line .. " " .. word)
        if getTextWidth(size, candidate) > maxWidth and line ~= "" then
            table.insert(lines, line)
            line = word
        else
            line = candidate
        end
    end
    if line ~= "" then
        table.insert(lines, line)
    end
    return lines
end

-- Draws wrapped text from the top (topY = top edge); returns the y below the last line
function UI.paragraph(x, topY, maxWidth, size, text, c)
    local lineH = size * 1.45
    local y = topY
    for _, line in ipairs(UI.wrap(text, size, maxWidth)) do
        y = y - lineH
        UI.text(x, y + size * 0.3, size, line, c)
    end
    return y
end

-- Button: opts = { bg, fg, ring, dashed, size, bold, align, disabled, onClick, tooltip, selected, id, edit }
-- Without edit rights (state.readOnly):
--   edit = true    the button only changes the plans: it is not drawn at all
--   edit = "show"  the button also shows plan content (plan name, crop card, field number):
--                  it is drawn as usual but cannot be clicked
function UI.button(state, x, y, w, h, label, opts)
    opts = opts or {}
    if opts.edit and state.readOnly then
        if opts.edit ~= "show" then
            return false
        end
        opts.onClick = nil
        opts.tooltip = nil
    end
    local bg = opts.bg
    if opts.selected and opts.selectedBg ~= nil then
        bg = opts.selectedBg
    end
    if bg ~= nil then
        UI.rect(x, y, w, h, bg)
    end
    if opts.dashed then
        UI.dashed(x, y, w, h, opts.ring or UI.C.lineLight)
    elseif opts.ring ~= nil then
        UI.border(x, y, w, h, opts.ring)
    end
    local hovered = not opts.disabled and opts.onClick ~= nil and UI.isInside(state, x, y, w, h)
    if hovered then
        UI.rect(x, y, w, h, UI.C.hover)
    end
    if label ~= nil and label ~= "" then
        local size = opts.size or UI.py(14)
        local fg = opts.fg or UI.C.text
        if opts.disabled then
            fg = { fg[1], fg[2], fg[3], 0.35 }
        end
        local pad = UI.px(10)
        local text = UI.fit(label, size, w - 2 * pad, opts.bold)
        if opts.align == "left" then
            UI.textIn(x + pad, y, h, size, text, fg, "left", opts.bold)
        else
            UI.textIn(x + w * 0.5, y, h, size, text, fg, "center", opts.bold)
        end
    end
    if not opts.disabled then
        UI.hit(state, x, y, w, h, opts.onClick, opts.tooltip, opts.id or label)
    elseif opts.tooltip ~= nil then
        UI.hit(state, x, y, w, h, nil, opts.tooltip)
    end
    return hovered
end

-- "<  value  >" stepper. onPrev / onNext nil = that arrow is disabled.
-- opts.edit and no edit rights: only the value is shown, without arrows.
function UI.stepper(state, x, y, w, h, value, onPrev, onNext, opts)
    opts = opts or {}
    local arrows = not (opts.edit and state.readOnly)
    UI.rect(x, y, w, h, UI.C.panelDark)
    UI.border(x, y, w, h, arrows and (opts.ring or UI.C.lineLight) or UI.C.line)
    local aw = UI.px(36)
    local id = opts.id or "stepper"
    if arrows then
        UI.button(state, x, y, aw, h, "<", { fg = UI.C.green, bold = true, disabled = onPrev == nil, onClick = onPrev, size = UI.py(16), id = id .. ":prev" })
        UI.button(state, x + w - aw, y, aw, h, ">", { fg = UI.C.green, bold = true, disabled = onNext == nil, onClick = onNext, size = UI.py(16), id = id .. ":next" })
    end
    local size = opts.size or UI.py(14)
    UI.textIn(x + w * 0.5, y, h, size, UI.fit(value, size, w - 2 * aw, true), UI.C.text, "center", true)
end

-- Small upper-case label above a control
function UI.label(x, y, text)
    UI.text(x, y, UI.py(12), string.upper(text), UI.C.muted, "left", true)
end

-- Pill with a status text; ok = green, otherwise orange
function UI.pill(rightX, y, h, text, ok)
    local size = UI.py(13)
    setTextBold(true)
    local w = getTextWidth(size, text) + UI.px(28)
    setTextBold(false)
    UI.rect(rightX - w, y, w, h, ok and UI.C.greenDark or UI.C.warnBg)
    UI.textIn(rightX - w * 0.5, y, h, size, text, ok and UI.C.green or UI.C.warnFg, "center", true)
end

---------------------------------------------------------------------------
-- Crop icons: the game's own fill type icon on a square in the crop's colour
---------------------------------------------------------------------------

UI.icons = {}

local function getIconOverlay(crop)
    if crop.iconFilename == nil then
        return nil
    end
    local overlay = UI.icons[crop.iconFilename]
    if overlay == nil then
        local ok, result = pcall(Overlay.new, crop.iconFilename, 0, 0, 0, 0)
        if not ok or result == nil then
            UI.icons[crop.iconFilename] = false
            return nil
        end
        overlay = result
        UI.icons[crop.iconFilename] = overlay
    end
    if overlay == false then
        return nil
    end
    return overlay
end

-- Square of size s (height in screen units; width corrected for the screen aspect)
function UI.cropSquare(crop, x, y, s, alpha)
    alpha = alpha or 1
    local w = s * (UI.px(1) / UI.py(1))
    local c = crop.color or { 0.5, 0.5, 0.5 }
    UI.rect(x, y, w, s, { c[1], c[2], c[3], alpha })
    local overlay = getIconOverlay(crop)
    if overlay ~= nil then
        local inset = s * 0.12
        overlay:setPosition(x + inset * (w / s), y + inset)
        overlay:setDimension(w - 2 * inset * (w / s), s - 2 * inset)
        overlay:setColor(0.08, 0.08, 0.08, alpha)
        overlay:render()
    end
    return w
end

function UI.deleteIcons()
    for _, overlay in pairs(UI.icons) do
        if overlay then
            overlay:delete()
        end
    end
    UI.icons = {}
end

---------------------------------------------------------------------------
-- Tooltip, drawn last
---------------------------------------------------------------------------

function UI.drawTooltip(state)
    if state.tooltip == nil or state.mouseX == nil then
        return
    end
    local size = UI.py(13)
    local lines = UI.wrap(state.tooltip, size, UI.px(360))
    local w = 0
    for _, line in ipairs(lines) do
        w = math.max(w, getTextWidth(size, line))
    end
    local pad = UI.px(10)
    local lineH = size * 1.4
    local h = #lines * lineH + UI.py(12)
    local x = state.mouseX + UI.px(16)
    local y = state.mouseY - h - UI.py(8)
    if x + w + 2 * pad > 1 then
        x = 1 - w - 2 * pad
    end
    if y < 0 then
        y = state.mouseY + UI.py(20)
    end
    UI.rect(x, y, w + 2 * pad, h, { 0.05, 0.05, 0.05, 0.95 })
    UI.border(x, y, w + 2 * pad, h, UI.C.lineLight, 1)
    local ty = y + h - UI.py(6)
    for _, line in ipairs(lines) do
        ty = ty - lineH
        UI.text(x + pad, ty + size * 0.3, size, line, UI.C.text)
    end
end

-- Reset render state for the rest of the GUI
function UI.finish()
    setTextColor(1, 1, 1, 1)
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
end
