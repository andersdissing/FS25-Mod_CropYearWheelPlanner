-- CropRotationPlanPages.lua
-- The Plans, plan editor and Field groups pages of the menu tab (mockups 2, 3 and 4).
-- Drawn with CropRotationPlanUI inside the sub-page container's area; `state` is the frame's
-- page state (mouse position, clickable boxes, selection, editor working copy).
--
-- The pages never change the data themselves: every edit is a request to the server
-- (CropRotationPlanSync.request), which applies it, saves it and sends it to all players.
-- In single player and on the host that happens at once. The plan editor works on a copy
-- that is only sent when the player presses Save plan.

CropRotationPlanPages = {}
local P = CropRotationPlanPages
local UI = CropRotationPlanUI
local C = UI.C
local px, py = UI.px, UI.py
local LG = CropRotationPlanLogic

local function t(key)
    return g_i18n:getText(key)
end

local function tf(key, ...)
    return string.format(g_i18n:getText(key), ...)
end

local function monthName(m)
    return t("crp_month_" .. tostring(m))
end

-- "Jun year 1"
local function monthYear(tAbs, years)
    return tf("crp_monthYear", monthName(LG.monthOf(tAbs)), LG.yearOf(tAbs, years))
end

local function durationText(d)
    if d < 12 then
        return tf("crp_durMonths", d)
    elseif d == 12 then
        return t("crp_durYear")
    end
    return tf("crp_durYears", d / 12)
end

local function monthsList(months)
    local parts = {}
    for _, m in ipairs(months) do
        table.insert(parts, monthName(m))
    end
    return table.concat(parts, "/")
end

-- Plans and field groups of the local player's farm
local function data()
    return CropRotationPlan:getFarm()
end

local OP = CropRotationPlanSync.OP

local function request(op)
    if CropRotationPlan:canEdit() then
        CropRotationPlanSync.request(op)
    end
end

-- Read-only state for this draw: no edit rights means edit buttons are disabled.
-- Returns true when the page is read-only (and draws a notice in the top right corner).
local function updateReadOnly(state, area)
    state.readOnly = not CropRotationPlan:canEdit()
    state.readOnlyText = t("crp_status_managerOnly")
    if state.readOnly then
        state.editor = nil
        state.addTo = nil
        UI.text(area.x + area.w, area.y + area.h - py(14), py(13), t("crp_status_managerOnly"), C.warnFg, "right", true)
    end
    return state.readOnly
end

-- Sends a changed copy of a stored plan
local function requestPlanChange(plan, change)
    local copy = CropRotationPlanData.copyPlan(plan)
    change(copy)
    request({ type = OP.PUT_PLAN, plan = copy })
end

local function requestGroupChange(group, planId, planYear)
    request({ type = OP.PUT_GROUP, group = { id = group.id, planId = planId, planYear = planYear, fields = {} } })
end

local function cropLabel(crop)
    if crop.ley then
        return string.format(t("crp_leyCrop"), crop.title)
    end
    return crop.title
end

local function seedLabel(seed, crop)
    if crop.ley then
        return tf("crp_leyBar", crop.title, seed.cut or LG.DEFAULT_CUT)
    end
    return crop.title
end

-- Status of a plan: text and whether it is OK
local function planStatus(plan, crops, withCounts)
    local overlaps = LG.getOverlaps(plan, crops)
    if #overlaps > 0 then
        return t("crp_statusOverlap"), false
    end
    local empty = LG.getEmptyYears(plan, crops)
    if #empty > 0 then
        local parts = {}
        for _, y in ipairs(empty) do
            table.insert(parts, tostring(y))
        end
        return tf("crp_statusEmptyYears", table.concat(parts, ", ")), false
    end
    if withCounts then
        return tf("crp_statusCounts", #plan.seeds, LG.getFreeMonths(plan, crops)), true
    end
    return t("crp_statusOk"), true
end

local function showTextInput(title, default, onText)
    if TextInputDialog == nil or TextInputDialog.show == nil then
        Logging.warning("[CropRotationPlan] TextInputDialog not available")
        return
    end
    TextInputDialog.show(function(_, text, clickOk)
        if clickOk and text ~= nil then
            text = string.gsub(text, "^%s+", "")
            text = string.gsub(text, "%s+$", "")
            if text ~= "" then
                onText(text)
            end
        end
    end, P, default or "", title, title, 40, t("button_ok"))
end

---------------------------------------------------------------------------
-- Owned fields (farmland ownership)
---------------------------------------------------------------------------

function P.refreshOwnedFields(state)
    local owned = {}
    local ok, err = pcall(function()
        local farmId = g_currentMission:getFarmId()
        local fields = g_fieldManager.fields
        if fields == nil and g_fieldManager.getFields ~= nil then
            fields = g_fieldManager:getFields()
        end
        for _, field in pairs(fields or {}) do
            local id = field.getId ~= nil and field:getId() or nil
            local farmland = field.farmland
            if id ~= nil and farmland ~= nil and g_farmlandManager:getFarmlandOwner(farmland.id) == farmId then
                table.insert(owned, id)
            end
        end
    end)
    if not ok then
        Logging.warning("[CropRotationPlan] Could not read owned fields: %s", tostring(err))
    end
    table.sort(owned)
    state.ownedFields = owned
end

---------------------------------------------------------------------------
-- Year wheel: one row per plan year, months Jan to Dec, bars from sowing to harvest
---------------------------------------------------------------------------

-- opts: { editor = state.editor or nil, onBar = function(seed) }
local function drawWheel(state, plan, crops, x, y, w, h, opts)
    local labelW = px(86)
    local gx = x + labelW
    local gw = w - labelW
    local headH = py(22)
    local rowGap = py(8)
    local rowH = math.min(py(62), (h - headH - rowGap * plan.years) / plan.years)
    local colW = gw / 12

    for m = 1, 12 do
        UI.text(gx + (m - 0.5) * colW, y + h - py(16), py(12), string.upper(monthName(m)), C.muted, "center", true)
    end

    local rows = LG.getRows(plan, crops)
    local gapRows = opts.editor ~= nil and LG.getGapRows(plan, crops) or nil
    local Lm = plan.years * 12
    local laneH = (rowH - py(14)) / 2

    for yr = 1, plan.years do
        local ry = y + h - headH - yr * (rowH + rowGap) + rowGap
        UI.textIn(x, ry, rowH, py(14), string.upper(tf("crp_yearN", yr)), C.green, "left", true)
        UI.rect(gx, ry, gw, rowH, C.row)

        if gapRows ~= nil then
            for _, piece in ipairs(gapRows[yr]) do
                local gap = piece.gap
                local sel = opts.editor.sel
                local on = sel.type == "gap" and (sel.a - gap.a) % Lm == 0
                local bx = gx + piece.from * colW + px(2)
                local bw = (piece.to - piece.from + 1) * colW - px(4)
                if on then
                    UI.rect(bx, ry + py(4), bw, rowH - py(8), C.greenDark)
                end
                UI.button(state, bx, ry + py(4), bw, rowH - py(8), "+", {
                    id = "gap:" .. tostring(gap.a % Lm), dashed = true, ring = on and C.green or C.lineLight, fg = C.green, bold = true,
                    tooltip = tf("crp_gapTip", monthYear(gap.a + 1, plan.years), monthYear(gap.b - 1, plan.years)),
                    onClick = function()
                        opts.editor.sel = { type = "gap", a = gap.a }
                        opts.editor.crop = nil
                        opts.editor.sow = nil
                        opts.editor.panelScroll = 0
                    end,
                })
            end
        end

        for _, bar in ipairs(rows[yr]) do
            local seed = bar.seed
            local crop = crops[seed.crop] or CropRotationPlanCrops.get(seed.crop)
            local bx = gx + bar.from * colW + px(1)
            local bw = (bar.to - bar.from + 1) * colW - px(3)
            local by = ry + rowH - py(6) - bar.lane * laneH
            if opts.editor == nil then
                by = ry + rowH - py(5) - bar.lane * laneH
            end
            local c = crop.color or { 0.5, 0.5, 0.5 }
            UI.rect(bx, by, bw, laneH - py(2), { c[1], c[2], c[3], 1 })
            local selected = opts.editor ~= nil and opts.editor.sel.type == "seed" and opts.editor.sel.i == seed.i
            if selected then
                UI.border(bx, by, bw, laneH - py(2), C.white)
            end
            local iconS = laneH - py(8)
            local tx = bx + px(6)
            if bw > px(40) then
                tx = tx + UI.cropSquare(crop, bx + px(4), by + py(3), iconS) + px(4)
            end
            local label = UI.fit(seedLabel(seed, crop), py(12), bx + bw - tx - px(4), true)
            if bw > px(30) then
                UI.textIn(tx, by, laneH - py(2), py(12), label, C.dark, "left", true)
            end
            local onBar = nil
            if not state.readOnly then
                onBar = function()
                    opts.onBar(seed)
                end
            end
            UI.hit(state, bx, by, bw, laneH - py(2), onBar, tf("crp_barTip", crop.title, monthYear(seed.t, plan.years), monthYear(seed.e, plan.years)), "bar:" .. seed.crop .. ":" .. tostring(seed.t))
        end

        if #rows[yr] == 0 and opts.editor == nil then
            UI.textIn(gx + px(12), ry, rowH, py(13), t("crp_noCropsYet"), C.muted)
        end
    end
end

---------------------------------------------------------------------------
-- Plans page (mockup 2)
---------------------------------------------------------------------------

local function getSelectedPlan(state)
    local d = data()
    local plan = CropRotationPlanData.getPlan(d, state.selectedPlanId)
    if plan == nil and #d.plans > 0 then
        plan = d.plans[1]
        state.selectedPlanId = plan.id
    end
    return plan
end

function P.openEditor(state, plan, sel)
    local copy = CropRotationPlanData.copyPlan(plan)
    local crops = CropRotationPlanCrops.getLookup({ copy })
    if sel == nil then
        local gaps = LG.getGaps(copy, crops)
        if #gaps > 0 then
            sel = { type = "gap", a = gaps[1].a }
        else
            sel = { type = "none" }
        end
    end
    state.editor = { plan = copy, sel = sel, panelScroll = 0 }
end

-- Asks for a name, then asks the server for the plan. The new plan is selected when it
-- arrives (see drawPlans).
local function newPlan(state)
    local d = data()
    showTextInput(t("crp_planName"), tf("crp_newPlanName", #d.plans + 1), function(text)
        state.waitForPlan = d.nextPlanId
        request({ type = OP.NEW_PLAN, name = text })
    end)
end

local function cardLines(seed, crop, yr, years)
    local sowRow = LG.yearOf(seed.t, years)
    local harvestRow = LG.yearOf(seed.e, years)
    local line1, line2
    if sowRow == yr then
        line1 = tf("crp_sowIn", monthName(LG.monthOf(seed.t)))
    else
        line1 = tf("crp_sownInYear", sowRow)
    end
    if harvestRow == yr then
        line2 = tf(crop.ley and "crp_lastCutIn" or "crp_harvestIn", monthName(LG.monthOf(seed.e)))
    else
        line2 = tf(crop.ley and "crp_lastCutInYear" or "crp_harvestedInYear", harvestRow)
    end
    return line1, line2
end

local function drawColumns(state, plan, crops, x, y, w, h)
    local n = plan.years
    local gap = px(12)
    local cw = (w - gap * (n - 1)) / n
    local rows = LG.getRows(plan, crops)
    local gapRows = LG.getGapRows(plan, crops)
    for yr = 1, n do
        local cx = x + (yr - 1) * (cw + gap)
        UI.rect(cx, y, cw, h, C.panel)
        UI.text(cx + px(12), y + h - py(28), py(14), string.upper(tf("crp_yearN", yr)), C.green, "left", true)
        local cy = y + h - py(40)
        local cardH = py(66)
        for _, bar in ipairs(rows[yr]) do
            if cy - cardH < y + py(58) then
                break
            end
            cy = cy - cardH
            local seed = bar.seed
            local crop = crops[seed.crop] or CropRotationPlanCrops.get(seed.crop)
            local line1, line2 = cardLines(seed, crop, yr, n)
            UI.button(state, cx + px(10), cy, cw - px(20), cardH, nil, {
                id = "card:" .. seed.crop .. ":" .. tostring(yr), edit = "show", bg = C.card,
                onClick = function()
                    P.openEditor(state, plan, { type = "seed", i = seed.i })
                end,
            })
            local c = crop.color or { 0.5, 0.5, 0.5 }
            UI.rect(cx + px(20), cy + cardH - py(24), px(12), py(12), { c[1], c[2], c[3], 1 })
            local textW = cw - px(60)
            UI.text(cx + px(40), cy + cardH - py(26), py(15), UI.fit(cropLabel(crop), py(15), textW, true), C.text, "left", true)
            UI.text(cx + px(40), cy + py(24), py(12), UI.fit(line1, py(12), textW), C.muted)
            UI.text(cx + px(40), cy + py(8), py(12), UI.fit(line2, py(12), textW), C.muted)
            cy = cy - py(8)
        end
        UI.button(state, cx + px(10), y + py(10), cw - px(20), py(38), t("crp_addCrop"), {
            id = "addCrop:" .. tostring(yr), edit = true, dashed = true, ring = C.lineLight, fg = C.green, bold = true, size = py(13),
            onClick = function()
                local first = gapRows[yr][1]
                if first ~= nil then
                    P.openEditor(state, plan, { type = "gap", a = first.gap.a })
                else
                    P.openEditor(state, plan, nil)
                end
            end,
        })
    end
end

function P.drawPlans(state, area)
    if state.editor ~= nil then
        P.drawEditor(state, area)
        return
    end
    local d = data()
    local crops = CropRotationPlan:getCrops()
    local top = area.y + area.h
    local left = area.x
    if CropRotationPlan:isSpectator() then
        UI.paragraph(left, top - py(10), area.w * 0.6, py(16), t("crp_spectator"), C.muted)
        return
    end
    updateReadOnly(state, area)
    -- Select a plan this player just made, once the server has sent it
    if state.waitForPlan ~= nil then
        local made = nil
        for _, p in ipairs(d.plans) do
            if p.id >= state.waitForPlan then
                made = p
            end
        end
        if made ~= nil then
            state.selectedPlanId = made.id
            state.waitForPlan = nil
        end
    end
    local plan = getSelectedPlan(state)

    -- Left: list of plans
    local colW = px(270)
    local y = top - py(30)
    UI.text(left, y, py(16), string.upper(t("crp_plans")), C.text, "left", true)
    y = y - py(14)
    local reserved = py(44) * 3 + py(40)
    for _, p in ipairs(d.plans) do
        local bh = py(62)
        if y - bh < area.y + reserved then
            break
        end
        y = y - bh
        local sel = plan ~= nil and p.id == plan.id
        UI.button(state, left, y, colW, bh, nil, {
            id = "plan:" .. p.name, bg = sel and C.greenSel or C.panel, ring = sel and C.green or C.line,
            onClick = function()
                state.selectedPlanId = p.id
                state.confirmDelete = nil
            end,
        })
        UI.text(left + px(16), y + bh - py(28), py(16), UI.fit(p.name, py(16), colW - px(32), true), C.text, "left", true)
        UI.text(left + px(16), y + py(12), py(13), tf("crp_planMeta", p.years, CropRotationPlanData.countGroupsForPlan(d, p.id)), C.muted)
        y = y - py(8)
    end
    y = y - py(44)
    UI.button(state, left, y, colW, py(44), string.upper(t("crp_newPlan")), {
        edit = true, dashed = true, ring = C.lineLight, fg = C.green, bold = true,
        onClick = function()
            newPlan(state)
        end,
    })

    local rx = left + colW + px(28)
    local rw = area.x + area.w - rx
    if plan == nil then
        UI.paragraph(rx, top - py(10), rw * 0.6, py(16), t("crp_noPlans"), C.muted)
        return
    end

    y = y - py(54)
    UI.button(state, left, y, colW, py(44), string.upper(t("crp_editPlan")), {
        edit = true, bg = C.green, fg = C.dark, bold = true,
        onClick = function()
            P.openEditor(state, plan, nil)
        end,
    })
    y = y - py(54)
    local confirming = state.confirmDelete == plan.id
    UI.button(state, left, y, colW, py(44), string.upper(t(confirming and "crp_deleteConfirm" or "crp_deletePlan")), {
        edit = true, ring = C.danger, fg = C.dangerFg, bold = true, bg = confirming and C.warnBg or nil,
        tooltip = t("crp_deletePlanTip"),
        onClick = function()
            if confirming then
                request({ type = OP.DELETE_PLAN, id = plan.id })
                state.confirmDelete = nil
                state.selectedPlanId = nil
            else
                state.confirmDelete = plan.id
            end
        end,
    })

    -- Right: header controls
    local hy = top - py(62)
    UI.label(rx, top - py(14), t("crp_planName"))
    UI.button(state, rx, hy, px(320), py(40), plan.name, {
        edit = "show", bg = C.panelDark, ring = C.lineLight, align = "left", size = py(16), tooltip = t("crp_renameTip"),
        onClick = function()
            showTextInput(t("crp_planName"), plan.name, function(text)
                requestPlanChange(plan, function(copy)
                    copy.name = text
                end)
            end)
        end,
    })
    local sx = rx + px(340)
    UI.label(sx, top - py(14), t("crp_yearsInCycle"))
    UI.stepper(state, sx, hy, px(170), py(40), tostring(plan.years),
        LG.canRemoveYear(plan, crops) and function()
            requestPlanChange(plan, function(copy)
                copy.years = copy.years - 1
            end)
        end or nil,
        LG.canAddYear(plan) and function()
            requestPlanChange(plan, function(copy)
                copy.years = copy.years + 1
            end)
        end or nil,
        { ring = C.green, id = "years", edit = true })
    local vx = sx + px(190)
    UI.label(vx, top - py(14), t("crp_view"))
    local columns = state.plansView ~= "rows"
    UI.rect(vx, hy, px(250), py(40), C.panelDark)
    UI.button(state, vx, hy, px(120), py(40), string.upper(t("crp_viewColumns")), {
        bg = columns and C.green or nil, fg = columns and C.dark or C.text, bold = true, size = py(13),
        onClick = function()
            state.plansView = "columns"
        end,
    })
    UI.button(state, vx + px(120), hy, px(130), py(40), string.upper(t("crp_viewRows")), {
        bg = (not columns) and C.green or nil, fg = (not columns) and C.dark or C.text, bold = true, size = py(13),
        onClick = function()
            state.plansView = "rows"
        end,
    })
    UI.border(vx, hy, px(250), py(40), C.lineLight)
    local statusText, ok = planStatus(plan, crops, false)
    UI.pill(area.x + area.w, hy + py(4), py(32), statusText, ok)

    -- Body
    local by = area.y + py(30)
    local bodyTop = hy - py(18)
    if columns then
        drawColumns(state, plan, crops, rx, by, rw, bodyTop - by)
    else
        UI.rect(rx, by, rw, bodyTop - by, C.panel)
        drawWheel(state, plan, crops, rx + px(16), by + py(10), rw - px(32), bodyTop - by - py(20), {
            onBar = function(seed)
                P.openEditor(state, plan, { type = "seed", i = seed.i })
            end,
        })
    end
    UI.text(rx, area.y + py(8), py(13), t(columns and "crp_columnsHint" or "crp_rowsHint"), C.muted)
end

---------------------------------------------------------------------------
-- Plan editor (mockup 4)
---------------------------------------------------------------------------

local function drawSidePanel(state, ed, crops, cropList, x, y, w, h)
    local plan = ed.plan
    local pad = px(24)
    local cx = x + pad
    local cw = w - 2 * pad
    local panelTop = y + h
    local cursor = panelTop - py(20) + (ed.panelScroll or 0)

    -- "Add seed to plan" stays at the bottom of the panel; the content above it scrolls
    -- with the mouse wheel, and only what is fully inside that area is drawn.
    local buttonH = py(44)
    local contentBottom = y + buttonH + py(28)
    local function visible(by, bh)
        return by >= contentBottom and by + bh <= panelTop
    end

    local sel = ed.sel
    if sel.type == "gap" then
        local gap = LG.findGap(plan, crops, sel.a)
        if gap == nil then
            ed.sel = { type = "none" }
            return
        end

        cursor = cursor - py(20)
        if visible(cursor, py(20)) then
            UI.text(cx, cursor, py(18), string.upper(t("crp_addSeed")), C.text, "left", true)
        end
        local lines = UI.wrap(tf("crp_gapText", monthYear(gap.a + 1, plan.years), monthYear(gap.b - 1, plan.years)), py(13), cw)
        for _, line in ipairs(lines) do
            cursor = cursor - py(19)
            if visible(cursor, py(16)) then
                UI.text(cx, cursor, py(13), line, C.muted)
            end
        end
        cursor = cursor - py(14)

        local fit, noFit = {}, {}
        for _, crop in ipairs(cropList) do
            if LG.cropFits(crop, gap.a, gap.b) then
                table.insert(fit, crop)
            else
                table.insert(noFit, crop)
            end
        end

        local crop = nil
        if ed.crop ~= nil then
            for _, c in ipairs(fit) do
                if c.name == ed.crop then
                    crop = c
                end
            end
        end

        -- Crops that fit: two columns of buttons. Once a crop is picked only that one is shown
        -- (with "Change crop"), so the sow months and grass options fit in the panel.
        local bw = (cw - px(6)) / 2
        local bh = py(46)
        local shown = fit
        if crop ~= nil then
            shown = { crop }
        end
        for i, crop in ipairs(shown) do
            local col = (i - 1) % 2
            if col == 0 then
                cursor = cursor - bh - py(6)
            end
            local bx = cx + col * (bw + px(6))
            if visible(cursor, bh) then
                local picked = ed.crop == crop.name
                UI.button(state, bx, cursor, bw, bh, nil, {
                    id = "crop:" .. crop.name, bg = picked and C.greenSel or C.card, ring = picked and C.green or C.line,
                    onClick = function()
                        ed.crop = crop.name
                        ed.sow = nil
                        ed.dur = nil
                    end,
                })
                local sq = UI.cropSquare(crop, bx + px(8), cursor + (bh - py(26)) * 0.5, py(26))
                local tx = bx + px(14) + sq
                local tw = bx + bw - tx - px(6)
                UI.text(tx, cursor + bh - py(21), py(14), UI.fit(crop.title, py(14), tw, true), C.text, "left", true)
                local choices = LG.getSowChoices(crop, gap.a, gap.b)
                local sowText
                if #choices > 4 then
                    sowText = monthName(LG.monthOf(choices[1])) .. "-" .. monthName(LG.monthOf(choices[#choices]))
                else
                    local parts = {}
                    for _, s in ipairs(choices) do
                        table.insert(parts, monthName(LG.monthOf(s)))
                    end
                    sowText = table.concat(parts, "/")
                end
                local sub = (crop.ley and t("crp_leySub") or tf("crp_monthsSub", crop.grow)) .. " - " .. tf("crp_sowSub", sowText)
                UI.text(tx, cursor + py(8), py(11), UI.fit(sub, py(11), tw), C.muted)
            end
        end

        if crop ~= nil then
            if visible(cursor, bh) then
                UI.button(state, cx + bw + px(6), cursor, bw, bh, t("crp_changeCrop"), {
                    id = "changeCrop", dashed = true, ring = C.lineLight, fg = C.green, bold = true, size = py(13),
                    onClick = function()
                        ed.crop = nil
                        ed.sow = nil
                        ed.dur = nil
                        ed.panelScroll = 0
                    end,
                })
            end
        else
            -- Crops that do not fit: greyed icons with the reason on hover
            cursor = cursor - py(28)
            if visible(cursor, py(14)) then
                UI.text(cx, cursor, py(12), string.upper(tf("crp_noFit", #noFit)), C.faint, "left", true)
            end
            local iconS = py(26)
            local iconW = iconS * (px(1) / py(1))
            local perRow = math.max(1, math.floor((cw + px(5)) / (iconW + px(5))))
            for i, other in ipairs(noFit) do
                local col = (i - 1) % perRow
                if col == 0 then
                    cursor = cursor - iconS - py(5)
                end
                local ix = cx + col * (iconW + px(5))
                if visible(cursor, iconS) then
                    UI.cropSquare(other, ix, cursor, iconS, 0.35)
                    local reason
                    if other.block ~= nil then
                        reason = t(other.block)
                    else
                        reason = tf("crp_needs", other.grow, monthsList(other.sow))
                    end
                    UI.hit(state, ix, cursor, iconW, iconS, nil, other.title .. ": " .. reason)
                end
            end
        end

        if #fit == 0 then
            cursor = cursor - py(56)
            if visible(cursor, py(48)) then
                UI.rect(cx, cursor, cw, py(48), C.noteBg)
                UI.textIn(cx + px(12), cursor, py(48), py(13), t("crp_nothingFits"), C.noteFg)
            end
        elseif crop == nil then
            cursor = cursor - py(36)
            if visible(cursor, py(16)) then
                UI.text(cx, cursor, py(13), t("crp_pickCrop"), C.muted)
            end
        else
            local choices = LG.getSowChoices(crop, gap.a, gap.b)
            local sow = choices[1]
            for _, s in ipairs(choices) do
                if s == ed.sow then
                    sow = s
                end
            end

            -- Choice buttons that wrap into rows
            local function choiceRow(items, labelOf, isOn, onPick)
                local bx = cx
                local rowH = py(36)
                cursor = cursor - rowH - py(6)
                for _, item in ipairs(items) do
                    local label = labelOf(item)
                    setTextBold(true)
                    local wBtn = getTextWidth(py(13), label) + px(24)
                    setTextBold(false)
                    if bx + wBtn > cx + cw and bx > cx then
                        bx = cx
                        cursor = cursor - rowH - py(6)
                    end
                    if visible(cursor, rowH) then
                        local on = isOn(item)
                        UI.button(state, bx, cursor, wBtn, rowH, label, {
                            bg = on and C.green or C.greenDark, ring = on and C.green or C.greenRing,
                            fg = on and C.dark or C.greenLight, bold = true, size = py(13),
                            onClick = function()
                                onPick(item)
                            end,
                        })
                    end
                    bx = bx + wBtn + px(6)
                end
            end

            cursor = cursor - py(30)
            if visible(cursor, py(14)) then
                UI.text(cx, cursor, py(13), string.upper(t("crp_sowInLabel")), C.muted, "left", true)
            end
            choiceRow(choices, function(s)
                return monthYear(s, plan.years)
            end, function(s)
                return s == sow
            end, function(s)
                ed.sow = s
            end)

            local dur = crop.grow
            local cut = LG.DEFAULT_CUT
            if crop.ley then
                local durations = LG.getLeyChoices(sow, gap.b)
                dur = durations[#durations]
                for _, d in ipairs(durations) do
                    if d == ed.dur then
                        dur = d
                    end
                end
                if ed.cut == 3 then
                    cut = 3
                end
                cursor = cursor - py(26)
                if visible(cursor, py(14)) then
                    UI.text(cx, cursor, py(13), string.upper(t("crp_keepAsLey")), C.muted, "left", true)
                end
                choiceRow(durations, durationText, function(d)
                    return d == dur
                end, function(d)
                    ed.dur = d
                end)

                cursor = cursor - py(26)
                if visible(cursor, py(14)) then
                    UI.text(cx, cursor, py(13), string.upper(t("crp_cutWhen")), C.muted, "left", true)
                end
                local kw = (cw - px(6)) / 2
                local kh = py(52)
                cursor = cursor - kh - py(6)
                for i, k in ipairs(LG.CUT_INTERVALS) do
                    local kx = cx + (i - 1) * (kw + px(6))
                    if visible(cursor, kh) then
                        local on = k == cut
                        UI.button(state, kx, cursor, kw, kh, nil, {
                            id = "cut:" .. tostring(k), bg = on and C.greenSel or C.card, ring = on and C.green or C.line,
                            onClick = function()
                                ed.cut = k
                            end,
                        })
                        UI.text(kx + px(10), cursor + kh - py(22), py(13), UI.fit(t(k == 2 and "crp_cutReady" or "crp_cutFull"), py(13), kw - px(20), true), C.text, "left", true)
                        UI.text(kx + px(10), cursor + py(10), py(11), UI.fit(tf("crp_cutSub", k, LG.getCutCount(sow, dur, k)), py(11), kw - px(20)), C.muted)
                    end
                end
            end

            -- Result
            local h = sow + dur
            local result
            if crop.ley then
                result = tf("crp_resultLey", crop.title, monthYear(sow, plan.years), dur, cut, LG.getCutCount(sow, dur, cut), monthYear(h, plan.years))
            else
                result = tf("crp_resultCrop", crop.title, monthYear(sow, plan.years), crop.grow, monthYear(h, plan.years))
            end
            local resultLines = UI.wrap(result, py(13), cw - px(24))
            local rh = #resultLines * py(19) + py(18)
            cursor = cursor - rh - py(12)
            if visible(cursor, rh) then
                UI.rect(cx, cursor, cw, rh, C.greenDark)
                local ly = cursor + rh - py(9)
                for _, line in ipairs(resultLines) do
                    ly = ly - py(19)
                    UI.text(cx + px(12), ly + py(4), py(13), line, C.greenLight)
                end
            end

            -- Follow-up crops
            local follow = LG.getFollowUps(cropList, h, crop.name)
            if #follow > 0 then
                cursor = cursor - py(30)
                if visible(cursor, py(24)) then
                    local label = t("crp_followUps")
                    UI.text(cx, cursor + py(7), py(12), label, C.muted)
                    local fx = cx + getTextWidth(py(12), label) + px(8)
                    for _, name in ipairs(follow) do
                        local fc = CropRotationPlanCrops.get(name)
                        local fw = py(24) * (px(1) / py(1))
                        if fx + fw > cx + cw then
                            break
                        end
                        UI.cropSquare(fc, fx, cursor, py(24))
                        UI.hit(state, fx, cursor, fw, py(24), nil, tf("crp_followTip", fc.title, monthName(LG.monthOf(h))))
                        fx = fx + fw + px(5)
                    end
                end
            end

            if cursor < contentBottom then
                UI.text(cx + cw, contentBottom - py(16), py(11), t("crp_scrollMore"), C.faint, "right")
            end
            do
                UI.button(state, cx, y + py(16), cw, buttonH, string.upper(t("crp_addSeedButton")), {
                    bg = C.green, fg = C.dark, bold = true,
                    onClick = function()
                        local seed = LG.makeSeed(plan, crop, sow, dur, cut)
                        table.insert(plan.seeds, seed)
                        ed.sel = { type = "seed", i = #plan.seeds }
                        ed.crop = nil
                        ed.sow = nil
                        ed.dur = nil
                        ed.cut = nil
                        ed.panelScroll = 0
                    end,
                })
            end
        end

    elseif sel.type == "seed" then
        local seed = nil
        for _, s in ipairs(LG.getSeeds(plan, crops)) do
            if s.i == sel.i then
                seed = s
            end
        end
        if seed == nil then
            ed.sel = { type = "none" }
            return
        end
        local crop = crops[seed.crop] or CropRotationPlanCrops.get(seed.crop)
        cursor = cursor - py(26)
        local sq = UI.cropSquare(crop, cx, cursor - py(2), py(24))
        UI.text(cx + sq + px(10), cursor + py(2), py(18), string.upper(crop.title), C.text, "left", true)
        local text
        if crop.ley then
            text = tf("crp_seedLeyText", monthYear(seed.t, plan.years), seed.e - seed.t, seed.cut or LG.DEFAULT_CUT, monthYear(seed.e, plan.years))
        else
            text = tf("crp_seedText", monthYear(seed.t, plan.years), monthYear(seed.e, plan.years), seed.e - seed.t)
        end
        cursor = UI.paragraph(cx, cursor - py(14), cw, py(14), text, C.text)
        if crop.block == "crp_block_notOnMap" then
            cursor = UI.paragraph(cx, cursor - py(6), cw, py(13), t("crp_block_notOnMap"), C.warnFg)
        end
        cursor = cursor - py(20) - py(44)
        UI.button(state, cx, cursor, cw, py(44), string.upper(t("crp_removeSeed")), {
            ring = C.danger, fg = C.dangerFg, bold = true,
            onClick = function()
                table.remove(plan.seeds, seed.i)
                -- Select the gap the removed seed leaves behind
                ed.sel = { type = "none" }
                local Lm = plan.years * 12
                for _, g in ipairs(LG.getGaps(plan, crops)) do
                    if (seed.t - g.a) % Lm <= g.b - g.a then
                        ed.sel = { type = "gap", a = g.a }
                    end
                end
            end,
        })
    else
        UI.paragraph(cx, cursor, cw, py(14), t("crp_editorHint"), C.muted)
    end
end

function P.drawEditor(state, area)
    local ed = state.editor
    local plan = ed.plan
    local crops = CropRotationPlanCrops.getLookup({ plan })
    local cropList = CropRotationPlanCrops.getEditorList(CropRotationPlan:getGrassInRotation())
    local top = area.y + area.h
    local x = area.x

    -- Header
    UI.text(x, top - py(18), py(13), string.upper(t("crp_tab_title") .. " > " .. t("crp_subtab_plans")), C.green, "left", true)
    UI.text(x, top - py(50), py(26), string.upper(t("crp_editPlan")), C.text, "left", true)
    local hx = x + px(300)
    local hy = top - py(58)
    UI.label(hx, top - py(14), t("crp_planName"))
    UI.button(state, hx, hy, px(300), py(40), plan.name, {
        bg = C.panelDark, ring = C.lineLight, align = "left", size = py(16), tooltip = t("crp_renameTip"),
        onClick = function()
            showTextInput(t("crp_planName"), plan.name, function(text)
                plan.name = text
            end)
        end,
    })
    local sx = hx + px(324)
    UI.label(sx, top - py(14), t("crp_yearsInCycle"))
    UI.stepper(state, sx, hy, px(170), py(40), tostring(plan.years),
        LG.canRemoveYear(plan, crops) and function()
            plan.years = plan.years - 1
            ed.sel = { type = "none" }
        end or nil,
        LG.canAddYear(plan) and function()
            plan.years = plan.years + 1
            ed.sel = { type = "none" }
        end or nil,
        { ring = C.green, id = "years" })
    local statusText, ok = planStatus(plan, crops, true)
    UI.pill(area.x + area.w, hy + py(4), py(32), statusText, ok)

    -- Footer: Cancel and Save plan
    local fh = py(60)
    UI.rect(area.x, area.y, area.w, fh, C.footer)
    UI.textIn(area.x + px(20), area.y, fh, py(13), t("crp_editorFooter"), C.muted)
    local bw = px(170)
    UI.button(state, area.x + area.w - px(20) - bw, area.y + py(8), bw, py(44), string.upper(t("crp_savePlan")), {
        bg = C.green, fg = C.dark, bold = true,
        onClick = function()
            -- The edit right is checked here, in request() and again by the server
            if CropRotationPlan:canEdit() then
                request({ type = OP.PUT_PLAN, plan = CropRotationPlanData.copyPlan(plan) })
            end
            state.selectedPlanId = plan.id
            state.editor = nil
        end,
    })
    UI.button(state, area.x + area.w - px(32) - 2 * bw, area.y + py(8), bw, py(44), string.upper(t("crp_cancel")), {
        bg = C.chip, fg = C.text, bold = true,
        onClick = function()
            state.editor = nil
        end,
    })

    -- Body: year wheel and side panel
    local bodyY = area.y + fh + py(12)
    local bodyTop = hy - py(16)
    local sideW = px(420)
    local sideX = area.x + area.w - sideW
    UI.rect(sideX, bodyY, sideW, bodyTop - bodyY, C.side)
    UI.rect(sideX, bodyY, px(1), bodyTop - bodyY, C.line)
    state.panelRegion = { x = sideX, y = bodyY, w = sideW, h = bodyTop - bodyY }

    local wheelW = sideX - x - px(28)
    drawWheel(state, plan, crops, x, bodyY + py(40), wheelW, bodyTop - bodyY - py(40), {
        editor = ed,
        onBar = function(seed)
            ed.sel = { type = "seed", i = seed.i }
            ed.panelScroll = 0
        end,
    })
    local hint = UI.wrap(t("crp_wheelHint"), py(13), wheelW - px(86))
    local ly = bodyY + py(24)
    for i, line in ipairs(hint) do
        if i <= 2 then
            UI.text(x + px(86), ly - (i - 1) * py(18), py(13), line, C.muted)
        end
    end

    drawSidePanel(state, ed, crops, cropList, sideX, bodyY, sideW, bodyTop - bodyY)
end

---------------------------------------------------------------------------
-- Field groups page (mockup 3)
---------------------------------------------------------------------------

local function fieldsTextOf(group)
    local parts = {}
    for _, id in ipairs(group.fields) do
        table.insert(parts, tostring(id))
    end
    return table.concat(parts, ", ")
end

function P.drawGroups(state, area)
    local d = data()
    local crops = CropRotationPlan:getCrops()
    local calendarYear = CropRotationPlan:getCalendarYear()
    local top = area.y + area.h
    local panelW = px(300)
    local listW = area.w - panelW - px(28)
    local x = area.x
    if CropRotationPlan:isSpectator() then
        UI.paragraph(x, top - py(10), area.w * 0.6, py(16), t("crp_spectator"), C.muted)
        return
    end
    updateReadOnly(state, area)
    -- Put a field group this player just made into "add fields" mode, once the server has sent it
    if state.waitForGroup ~= nil then
        for _, g in ipairs(d.groups) do
            if g.id >= state.waitForGroup then
                state.addTo = g.id
                state.waitForGroup = nil
            end
        end
    end

    -- Columns
    local colGap = px(14)
    local fieldsW, planW, yearW, delW = px(250), px(230), px(190), px(44)
    local cropsW = listW - px(32) - fieldsW - planW - yearW - delW - 4 * colGap
    local xFields = x + px(16)
    local xPlan = xFields + fieldsW + colGap
    local xYear = xPlan + planW + colGap
    local xCrops = xYear + yearW + colGap
    local xDel = xCrops + cropsW + colGap

    local hy = top - py(24)
    UI.text(xFields, hy, py(13), string.upper(t("crp_colFields")), C.muted, "left", true)
    UI.text(xPlan, hy, py(13), string.upper(t("crp_colPlan")), C.muted, "left", true)
    UI.text(xYear, hy, py(13), string.upper(t("crp_colPlanYear")), C.muted, "left", true)
    UI.text(xCrops, hy, py(13), UI.fit(string.upper(tf("crp_colCrops", calendarYear)), py(13), cropsW + delW, true), C.muted, "left", true)

    local rowH = py(58)
    local rowGap = py(6)
    local listTop = hy - py(12)
    local listBottom = area.y + py(64)
    local maxRows = math.max(1, math.floor((listTop - listBottom) / (rowH + rowGap)))
    local scroll = math.max(0, math.min(state.groupScroll or 0, #d.groups - maxRows))
    state.groupScroll = scroll
    state.scrollRegion = { x = x, y = listBottom, w = listW, h = listTop - listBottom, max = math.max(0, #d.groups - maxRows) }

    local ry = listTop
    for i = scroll + 1, math.min(#d.groups, scroll + maxRows) do
        local group = d.groups[i]
        ry = ry - rowH
        UI.rect(x, ry, listW, rowH, C.panel)
        local plan = CropRotationPlanData.getPlan(d, group.planId)

        -- Field chips (click to remove) and +
        local chipH = py(30)
        local chipY = ry + (rowH - chipH) * 0.5
        local cx = xFields
        local shown = 0
        for _, id in ipairs(group.fields) do
            local label = tostring(id)
            setTextBold(true)
            -- 28px: 2 x 10px button padding plus room, so "23" is never shortened to "2.."
            local cw = getTextWidth(py(14), label) + px(28)
            setTextBold(false)
            if cx + cw > xFields + fieldsW - px(80) then
                break
            end
            UI.button(state, cx, chipY, cw, chipH, label, {
                id = "chip:" .. label, edit = "show", bg = C.chip, bold = true, tooltip = tf("crp_removeFieldTip", id),
                onClick = function()
                    request({ type = OP.ASSIGN_FIELD, groupId = 0, fieldId = id })
                end,
            })
            cx = cx + cw + px(6)
            shown = shown + 1
        end
        if shown < #group.fields then
            UI.textIn(cx, chipY, chipH, py(13), "+" .. tostring(#group.fields - shown), C.muted, "left", true)
            UI.hit(state, cx, chipY, px(30), chipH, nil, fieldsTextOf(group))
            cx = cx + px(34)
        end
        local adding = state.addTo == group.id
        UI.button(state, cx, chipY, px(34), chipH, "+", {
            id = "addField:" .. tostring(i), edit = true, dashed = not adding, ring = C.lineLight, bg = adding and C.green or nil,
            fg = adding and C.dark or C.green, bold = true, tooltip = t("crp_addFieldTip"),
            onClick = function()
                if state.addTo == group.id then
                    state.addTo = nil
                else
                    state.addTo = group.id
                end
            end,
        })

        -- Plan
        local planIds = { false }
        for _, p in ipairs(d.plans) do
            table.insert(planIds, p.id)
        end
        local current = 1
        for k, id in ipairs(planIds) do
            if id == group.planId then
                current = k
            end
        end
        local function setPlan(k)
            requestGroupChange(group, planIds[k] or nil, 1)
        end
        local stepH = py(38)
        local stepY = ry + (rowH - stepH) * 0.5
        UI.stepper(state, xPlan, stepY, planW, stepH, plan ~= nil and plan.name or t("crp_noPlan"),
            #planIds > 1 and function()
                setPlan(((current - 2) % #planIds) + 1)
            end or nil,
            #planIds > 1 and function()
                setPlan((current % #planIds) + 1)
            end or nil, { id = "groupPlan:" .. tostring(i), edit = true })

        -- Plan year now
        if plan ~= nil then
            local planYear = LG.getPlanYear(group, calendarYear, plan.years)
            local function setYear(y)
                requestGroupChange(group, group.planId, y)
            end
            UI.stepper(state, xYear, stepY, yearW, stepH, tf("crp_yearN", planYear),
                plan.years > 1 and function()
                    setYear(((planYear - 2) % plan.years) + 1)
                end or nil,
                plan.years > 1 and function()
                    setYear((planYear % plan.years) + 1)
                end or nil, { id = "groupYear:" .. tostring(i), edit = true })
            local cropsText = CropRotationPlan.cropsText(LG.getCropsInYear(plan, crops, planYear))
            UI.textIn(xCrops, ry, rowH, py(14), UI.fit(cropsText, py(14), cropsW), C.text)
        else
            UI.stepper(state, xYear, stepY, yearW, stepH, "-", nil, nil)
            UI.textIn(xCrops, ry, rowH, py(14), t("crp_pickPlan"), C.muted)
        end

        -- Remove group (click twice)
        local confirming = state.confirmGroup == group.id
        UI.button(state, xDel, stepY, delW, stepH, confirming and "?" or "X", {
            id = "delGroup:" .. tostring(i), edit = true, ring = C.danger, fg = C.dangerFg, bold = true, bg = confirming and C.warnBg or nil,
            tooltip = t(confirming and "crp_removeGroupConfirm" or "crp_removeGroupTip"),
            onClick = function()
                if confirming then
                    request({ type = OP.DELETE_GROUP, id = group.id })
                    state.confirmGroup = nil
                    state.addTo = nil
                else
                    state.confirmGroup = group.id
                end
            end,
        })
        ry = ry - rowGap
    end

    if #d.groups == 0 then
        UI.paragraph(x, listTop, listW * 0.8, py(15), t("crp_noGroups"), C.muted)
    elseif #d.groups > maxRows then
        UI.text(x + listW, listBottom - py(18), py(12), tf("crp_scrollHint", scroll + 1, math.min(#d.groups, scroll + maxRows), #d.groups), C.muted, "right")
    end

    UI.button(state, x, area.y + py(10), px(260), py(44), string.upper(t("crp_newGroup")), {
        edit = true, dashed = true, ring = C.lineLight, fg = C.green, bold = true,
        onClick = function()
            state.waitForGroup = d.nextGroupId
            state.groupScroll = math.max(0, #d.groups + 1 - maxRows)
            request({ type = OP.NEW_GROUP })
        end,
    })

    -- Right panel: the farm's own fields
    local px0 = area.x + area.w - panelW
    UI.rect(px0, area.y, px(1), area.h, C.line)
    local cx = px0 + px(26)
    local cw = panelW - px(26)
    local y = top - py(20)
    UI.text(cx, y, py(16), string.upper(t("crp_yourFields")), C.text, "left", true)
    local addGroup = state.addTo ~= nil and CropRotationPlanData.getGroup(d, state.addTo) or nil
    if addGroup ~= nil then
        y = UI.paragraph(cx, y - py(6), cw, py(13), t("crp_addFieldHint"), C.green)
    else
        y = UI.paragraph(cx, y - py(6), cw, py(13), t("crp_yourFieldsText"), C.muted)
    end
    y = y - py(8)

    local owned = state.ownedFields or {}
    local cols = 5
    local gap = px(8)
    local cellW = (cw - gap * (cols - 1)) / cols
    local cellH = py(34)
    local helpLines = UI.wrap(t("crp_planYearHelp"), py(13), cw)
    local helpH = #helpLines * py(13) * 1.45 + py(10)
    local gridBottom = area.y + helpH + py(10)
    local shownFields = 0
    for k, id in ipairs(owned) do
        local col = (k - 1) % cols
        if col == 0 then
            y = y - cellH - gap
        end
        if y < gridBottom then
            break
        end
        local inGroup = CropRotationPlanData.getGroupOfField(d, id)
        local isInAddGroup = inGroup ~= nil and inGroup == addGroup
        local bg = inGroup ~= nil and C.greenSel or C.chip
        local fg = inGroup ~= nil and C.greenLight or C.muted
        UI.button(state, cx + col * (cellW + gap), y, cellW, cellH, tostring(id), {
            id = "field:" .. tostring(id), bg = bg, fg = fg, bold = true, ring = isInAddGroup and C.green or nil,
            tooltip = t(inGroup ~= nil and "crp_fieldInGroup" or "crp_fieldFree"),
            onClick = addGroup ~= nil and function()
                request({ type = OP.ASSIGN_FIELD, groupId = isInAddGroup and 0 or addGroup.id, fieldId = id })
            end or nil,
        })
        shownFields = shownFields + 1
    end
    if #owned == 0 then
        y = UI.paragraph(cx, y, cw, py(13), t("crp_noOwnedFields"), C.warnFg)
    elseif shownFields < #owned then
        UI.text(cx, gridBottom - py(4), py(12), tf("crp_moreFields", #owned - shownFields), C.muted)
    end
    UI.paragraph(cx, area.y + helpH, cw, py(13), t("crp_planYearHelp"), C.muted)
end
