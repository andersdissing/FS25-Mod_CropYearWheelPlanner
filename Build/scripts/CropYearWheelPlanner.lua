-- CropYearWheelPlanner.lua
-- FS25 mod: crop rotation plans built in the game, shown on screen.
--
-- Per farm, kept by the server and stored in <savegame>/cropYearWheelPlanner.xml (CropYearWheelPlannerData):
--   plans        name, years in cycle, seeds (crop + sow month)
--   field groups fields, plan, "plan year now"
--   grass in rotation
-- Per player, stored on the player's PC (modSettings): display full / minimized / hidden, position.
-- A new savegame starts empty; plans and field groups are made in the menu (Esc) > Crop Year Wheel Planner.
-- Multiplayer: edits go through the server (CropYearWheelPlannerSync).
--
-- Alt+R (rebindable in Settings > Controls) switches between full and minimized.
-- Minimized is a single icon: yellow = tasks now (with count), green = tasks next month, grey = nothing.

local modDirectory = g_currentModDirectory

source(modDirectory .. "scripts/CropYearWheelPlannerLogic.lua")
source(modDirectory .. "scripts/CropYearWheelPlannerCrops.lua")
source(modDirectory .. "scripts/CropYearWheelPlannerData.lua")
source(modDirectory .. "scripts/CropYearWheelPlannerSync.lua")
source(modDirectory .. "scripts/CropYearWheelPlannerUI.lua")
source(modDirectory .. "scripts/CropYearWheelPlannerPages.lua")
source(modDirectory .. "scripts/CropYearWheelPlannerFrame.lua")

CropYearWheelPlanner = {}
CropYearWheelPlanner.modDirectory = modDirectory

CropYearWheelPlanner.DISPLAY_FULL = "full"
CropYearWheelPlanner.DISPLAY_MINIMIZED = "minimized"
CropYearWheelPlanner.DISPLAY_HIDDEN = "hidden"
-- Order used by the settings option (state 1..3)
CropYearWheelPlanner.DISPLAY_MODES = CropYearWheelPlannerData.DISPLAY_MODES

-- Where on screen the plan is drawn (state 1..2 in the settings option)
CropYearWheelPlanner.POSITIONS = CropYearWheelPlannerData.POSITIONS
CropYearWheelPlanner.ANCHORS = {
    top = { x = 0.20, topY = 0.99 },   -- top of the screen, between the help list and the right-hand HUD
    left = { x = 0.012, topY = 0.67 }, -- left side above the minimap
}

CropYearWheelPlanner.data = CropYearWheelPlannerData.new()
CropYearWheelPlanner.settings = CropYearWheelPlannerData.newLocalSettings()

-- Layout (normalized screen coordinates, origin bottom-left)
CropYearWheelPlanner.UI = {
    x = 0.012,
    topY = 0.67,
    textSize = 0.0135,
    titleSize = 0.0155,
    lineGap = 0.0045,
    padding = 0.006,
    colGap = 0.012,
    indent = 0.010,
    groupGap = 0.005,
    bgColor = { 0, 0, 0, 0.62 },
    colorText = { 1, 1, 1, 1 },
    colorMuted = { 0.72, 0.72, 0.72, 1 },
    colorNow = { 0.98, 0.80, 0.25, 1 },
    colorTitle = { 0.55, 0.85, 0.45, 1 },
    colorWarn = { 1, 0.45, 0.35, 1 },
    -- Minimized: one icon. Yellow = tasks now, green = tasks next month, grey = nothing to do
    iconHeight = 0.042,
    iconPadding = 0.004,
    iconBadgeSize = 0.0145,
    iconColorNow = { 0.98, 0.80, 0.25, 1 },
    iconColorSoon = { 0.55, 0.85, 0.45, 1 },
    iconColorIdle = { 0.6, 0.6, 0.6, 0.45 },
    iconBgAlphaIdle = 0.25,
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function t(key)
    return g_i18n:getText(key)
end

local function monthName(month)
    return t("cywp_month_" .. tostring(month))
end
CropYearWheelPlanner.monthName = monthName

function CropYearWheelPlanner.taskText(task)
    return string.format("%s %s", t("cywp_action_" .. task.action), CropYearWheelPlannerCrops.getTitle(task.crop))
end

function CropYearWheelPlanner:getEnvironment()
    if g_currentMission == nil then
        return nil
    end
    return g_currentMission.environment
end

function CropYearWheelPlanner:getCurrentYear()
    local env = self:getEnvironment()
    if env == nil or env.currentYear == nil then
        return 1
    end
    return env.currentYear
end

function CropYearWheelPlanner:getCurrentPeriod()
    local env = self:getEnvironment()
    if env == nil or env.currentPeriod == nil then
        return 1
    end
    return env.currentPeriod
end

function CropYearWheelPlanner:getCurrentMonth()
    return CropYearWheelPlannerLogic.periodToMonth(self:getCurrentPeriod())
end

-- Calendar year (January to December) that plan years are counted in
function CropYearWheelPlanner:getCalendarYear()
    return CropYearWheelPlannerLogic.calendarYear(self:getCurrentYear(), self:getCurrentPeriod())
end

-- Farm of the local player (1 in single player; 0 = spectator)
function CropYearWheelPlanner:getFarmId()
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        local farmId = g_currentMission:getFarmId()
        if farmId ~= nil then
            return farmId
        end
    end
    return 1
end

-- User id of the local player (multiplayer)
function CropYearWheelPlanner:getUserId()
    if g_currentMission ~= nil then
        return g_currentMission.playerUserId
    end
    return nil
end

function CropYearWheelPlanner:isMultiplayer()
    return CropYearWheelPlannerSync.isMultiplayer()
end

-- May the local player edit the farm's plans / change who can edit?
function CropYearWheelPlanner:canEdit()
    return CropYearWheelPlannerSync.canEdit(self:getFarmId(), self:getUserId())
end

function CropYearWheelPlanner:canChangePermission()
    return CropYearWheelPlannerSync.canChangePermission(self:getFarmId(), self:getUserId())
end

function CropYearWheelPlanner:getEveryoneCanEdit()
    return self:getFarm().editPermission == CropYearWheelPlannerData.EDIT_EVERYONE
end

function CropYearWheelPlanner:setEveryoneCanEdit(everyone)
    CropYearWheelPlannerSync.request({ type = CropYearWheelPlannerSync.OP.SET_PERMISSION, value = everyone })
end

function CropYearWheelPlanner:isSpectator()
    local spectator = (FarmManager ~= nil and FarmManager.SPECTATOR_FARM_ID) or 0
    return self:getFarmId() == spectator
end

-- Plans, field groups and grass setting of the local player's farm
function CropYearWheelPlanner:getFarm()
    return CropYearWheelPlannerData.getFarm(self.data, self:getFarmId(), true)
end

function CropYearWheelPlanner:getCrops()
    return CropYearWheelPlannerCrops.getLookup(self:getFarm().plans)
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local function indexOf(list, value)
    for i, v in ipairs(list) do
        if v == value then
            return i
        end
    end
    return 1
end

function CropYearWheelPlanner:getDisplayModeIndex()
    return indexOf(CropYearWheelPlanner.DISPLAY_MODES, self.settings.displayMode)
end

function CropYearWheelPlanner:getPositionIndex()
    return indexOf(CropYearWheelPlanner.POSITIONS, self.settings.position)
end

-- Display and position are the player's own: saved on this PC, not sent to anyone
function CropYearWheelPlanner:setDisplayMode(mode)
    self.settings.displayMode = mode
    CropYearWheelPlannerData.saveLocal(self.settings)
end

function CropYearWheelPlanner:setPosition(position)
    if CropYearWheelPlanner.ANCHORS[position] ~= nil then
        self.settings.position = position
        CropYearWheelPlannerData.saveLocal(self.settings)
    end
end

function CropYearWheelPlanner:getGrassInRotation()
    return self:getFarm().grassInRotation
end

function CropYearWheelPlanner:setGrassInRotation(allowed)
    CropYearWheelPlannerSync.request({ type = CropYearWheelPlannerSync.OP.SET_GRASS, value = allowed })
end

-- Only the server writes the savegame file
function CropYearWheelPlanner:save()
    if g_server ~= nil then
        CropYearWheelPlannerData.save(self.data)
    end
end

---------------------------------------------------------------------------
-- Mod event listener
---------------------------------------------------------------------------

function CropYearWheelPlanner:loadMap(filename)
    local settings, existed = CropYearWheelPlannerData.loadLocal()
    self.settings = settings
    if g_server ~= nil then
        local data, oldDisplay = CropYearWheelPlannerData.load()
        self.data = data
        if not existed and oldDisplay ~= nil then
            -- v2.0 kept display and position in the savegame
            CropYearWheelPlannerData.applyOldDisplay(self.settings, oldDisplay)
            CropYearWheelPlannerData.saveLocal(self.settings)
        end
    end
    -- A client keeps self.data: it is filled by the server's CropYearWheelPlannerStateEvent
    CropYearWheelPlannerCrops.load()
    -- A dedicated server has no screen: no on-screen plan and no menu tab there
    if g_dedicatedServer == nil then
        self.iconOverlay = Overlay.new(modDirectory .. "icon_minimized.dds", 0, 0, 0, 0)
        CropYearWheelPlannerFrame.install(modDirectory)
    end
    addConsoleCommand("cywpLoadExample", "Crop Year Wheel Planner: replace plans and field groups with the Riverbend Springs example", "consoleLoadExample", self)
    addConsoleCommand("cywpReloadCrops", "Crop Year Wheel Planner: read the crops from the game again", "consoleReloadCrops", self)
end

function CropYearWheelPlanner:deleteMap()
    removeConsoleCommand("cywpLoadExample")
    removeConsoleCommand("cywpReloadCrops")
    CropYearWheelPlannerFrame.uninstall()
    CropYearWheelPlannerUI.deleteIcons()
    if self.iconOverlay ~= nil then
        self.iconOverlay:delete()
        self.iconOverlay = nil
    end
end

function CropYearWheelPlanner:consoleLoadExample()
    if g_server == nil then
        return "Crop Year Wheel Planner: cywpLoadExample only works on the server"
    end
    local farm = self:getFarm()
    CropYearWheelPlannerData.loadExample(farm, self:getCalendarYear())
    self:save()
    CropYearWheelPlannerSync.broadcastFarm(self:getFarmId())
    return string.format("Crop Year Wheel Planner: example loaded for farm %d (%d plans, %d field groups)", self:getFarmId(), #farm.plans, #farm.groups)
end

function CropYearWheelPlanner:consoleReloadCrops()
    CropYearWheelPlannerCrops.load()
    local lines = {}
    for _, crop in ipairs(CropYearWheelPlannerCrops.list) do
        local months = {}
        for _, m in ipairs(crop.sow) do
            table.insert(months, tostring(m))
        end
        table.insert(lines, string.format("%s (%s): sow %s, grow %d%s", crop.title, crop.name, table.concat(months, ","), crop.grow or 0, crop.block and (", " .. crop.block) or ""))
    end
    print(table.concat(lines, "\n"))
    return string.format("Crop Year Wheel Planner: %d crops", #CropYearWheelPlannerCrops.list)
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------

function CropYearWheelPlanner.registerActionEvents()
    local inputAction = InputAction.CYWP_TOGGLE_SIZE
    if inputAction == nil then
        return
    end
    local _, eventId = g_inputBinding:registerActionEvent(inputAction, CropYearWheelPlanner, CropYearWheelPlanner.onToggleSize, false, true, false, true)
    if eventId ~= nil then
        g_inputBinding:setActionEventText(eventId, t("input_CYWP_TOGGLE_SIZE"))
        g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_LOW)
    end
end

-- Full -> minimized -> full. From hidden the key brings it back as minimized.
function CropYearWheelPlanner:onToggleSize()
    if self.settings.displayMode == CropYearWheelPlanner.DISPLAY_FULL then
        self:setDisplayMode(CropYearWheelPlanner.DISPLAY_MINIMIZED)
    elseif self.settings.displayMode == CropYearWheelPlanner.DISPLAY_MINIMIZED then
        self:setDisplayMode(CropYearWheelPlanner.DISPLAY_FULL)
    else
        self:setDisplayMode(CropYearWheelPlanner.DISPLAY_MINIMIZED)
    end
end

PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
    PlayerInputComponent.registerGlobalPlayerActionEvents,
    function(...)
        CropYearWheelPlanner.registerActionEvents()
    end
)

-- Write the file with the savegame (also the first save of a new career, which creates the folder)
if FSBaseMission ~= nil and FSBaseMission.saveSavegame ~= nil then
    FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, function(...)
        CropYearWheelPlanner:save()
    end)
end

---------------------------------------------------------------------------
-- Content
---------------------------------------------------------------------------

local function fieldsText(fields)
    local parts = {}
    for _, id in ipairs(fields) do
        table.insert(parts, tostring(id))
    end
    return string.format("%s %s", t(#fields == 1 and "cywp_field" or "cywp_fields"), table.concat(parts, ", "))
end

-- "Wheat -> Canola", grass as "Grass (ley)"
function CropYearWheelPlanner.cropsText(names)
    local parts = {}
    for _, name in ipairs(names) do
        local crop = CropYearWheelPlannerCrops.get(name)
        if crop.ley then
            table.insert(parts, string.format(t("cywp_leyCrop"), crop.title))
        else
            table.insert(parts, crop.title)
        end
    end
    if #parts == 0 then
        return "-"
    end
    return table.concat(parts, " > ")
end

-- Returns a list of plans that have field groups:
--   { title, groups = { { name, yearText, crops, status, isNow, nextIn, fieldCount } } }
function CropYearWheelPlanner:buildGroups()
    local crops = self:getCrops()
    local calendarYear = self:getCalendarYear()
    local month = self:getCurrentMonth()
    local farm = self:getFarm()
    local out = {}

    for _, plan in ipairs(farm.plans) do
        local entry = { title = plan.name, groups = {} }
        for _, group in ipairs(farm.groups) do
            if group.planId == plan.id and #group.fields > 0 then
                local s = CropYearWheelPlannerLogic.getGroupStatus(plan, crops, group, calendarYear, month)
                local row = {
                    name = fieldsText(group.fields),
                    yearText = string.format(t("cywp_cycleYear"), s.planYear, plan.years),
                    crops = CropYearWheelPlanner.cropsText(s.cropsThisYear),
                    status = "",
                    isNow = false,
                    fieldCount = #group.fields,
                }
                if #s.nowTasks > 0 then
                    local parts = {}
                    for _, task in ipairs(s.nowTasks) do
                        table.insert(parts, CropYearWheelPlanner.taskText(task))
                    end
                    row.status = t("cywp_now") .. ": " .. table.concat(parts, ", ")
                    row.isNow = true
                elseif s.nextTask ~= nil then
                    local when = monthName(s.nextMonth)
                    if s.nextIsNextYear then
                        when = string.format(t("cywp_whenNextYear"), when)
                    end
                    row.status = string.format("%s: %s (%s)", t("cywp_next"), CropYearWheelPlanner.taskText(s.nextTask), when)
                    row.nextIn = s.nextIn
                end
                table.insert(entry.groups, row)
            end
        end
        if #entry.groups > 0 then
            table.insert(out, entry)
        end
    end
    return out
end

-- Attention state for the minimized icon.
--   "now"  : at least one field group has a task this month (count = number of fields)
--   "soon" : nothing now, but a task next month
--   "idle" : nothing this month or next
function CropYearWheelPlanner:getAttention(plans)
    local nowCount = 0
    local soon = false
    for _, plan in ipairs(plans) do
        for _, row in ipairs(plan.groups) do
            if row.isNow then
                nowCount = nowCount + row.fieldCount
            elseif row.nextIn == 1 then
                soon = true
            end
        end
    end
    if nowCount > 0 then
        return "now", nowCount
    elseif soon then
        return "soon", 0
    end
    return "idle", 0
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function setColor(c)
    setTextColor(c[1], c[2], c[3], c[4])
end

function CropYearWheelPlanner:getTitle()
    return string.format(t("cywp_title"), self:getCurrentYear(), monthName(self:getCurrentMonth()))
end

function CropYearWheelPlanner:drawFull(plans)
    local U = CropYearWheelPlanner.UI
    local size = U.textSize
    local title = self:getTitle()
    local footer = nil
    if #plans == 0 then
        footer = t("cywp_hudEmpty")
    end

    -- Column widths
    local wPlan, wName, wYear, wCrops, wStatus = 0, 0, 0, 0, 0
    local rowCount = 0
    for _, p in ipairs(plans) do
        setTextBold(true)
        wPlan = math.max(wPlan, getTextWidth(size, p.title))
        setTextBold(false)
        for _, r in ipairs(p.groups) do
            wName = math.max(wName, getTextWidth(size, r.name))
            wYear = math.max(wYear, getTextWidth(size, r.yearText))
            wCrops = math.max(wCrops, getTextWidth(size, r.crops))
            wStatus = math.max(wStatus, getTextWidth(size, r.status))
            rowCount = rowCount + 1
        end
    end
    local rowWidth = U.indent + wName + wYear + wCrops + wStatus + 3 * U.colGap
    local width = math.max(rowWidth, wPlan, getTextWidth(U.titleSize, title)) + 2 * U.padding
    if footer ~= nil then
        width = math.max(width, getTextWidth(size, footer) + 2 * U.padding)
    end

    local lineH = size + U.lineGap
    local height = U.padding * 2 + (U.titleSize + U.lineGap)
        + #plans * (lineH + U.groupGap) + rowCount * lineH
    if footer ~= nil then
        height = height + lineH + U.groupGap
    end
    local bottomY = U.topY - height

    drawFilledRect(U.x, bottomY, width, height, U.bgColor[1], U.bgColor[2], U.bgColor[3], U.bgColor[4])

    setTextAlignment(RenderText.ALIGN_LEFT)
    local x = U.x + U.padding
    local y = U.topY - U.padding - U.titleSize

    setTextBold(true)
    setColor(U.colorTitle)
    renderText(x, y, U.titleSize, title)
    setTextBold(false)

    local xName = x + U.indent
    local xYear = xName + wName + U.colGap
    local xCrops = xYear + wYear + U.colGap
    local xStatus = xCrops + wCrops + U.colGap

    for _, p in ipairs(plans) do
        y = y - lineH - U.groupGap
        setTextBold(true)
        setColor(U.colorText)
        renderText(x, y, size, p.title)
        setTextBold(false)

        for _, r in ipairs(p.groups) do
            y = y - lineH
            setColor(U.colorText)
            renderText(xName, y, size, r.name)
            setColor(U.colorTitle)
            renderText(xYear, y, size, r.yearText)
            setColor(U.colorText)
            renderText(xCrops, y, size, r.crops)
            if r.isNow then
                setTextBold(true)
                setColor(U.colorNow)
            else
                setColor(U.colorMuted)
            end
            renderText(xStatus, y, size, r.status)
            setTextBold(false)
        end
    end

    if footer ~= nil then
        y = y - lineH - U.groupGap
        setColor(U.colorMuted)
        renderText(x, y, size, footer)
    end
end

function CropYearWheelPlanner:drawMinimized(plans)
    local U = CropYearWheelPlanner.UI
    if self.iconOverlay == nil then
        return
    end

    local state, count = self:getAttention(plans)
    local color = U.iconColorIdle
    local bgAlpha = U.bgColor[4]
    if state == "now" then
        color = U.iconColorNow
    elseif state == "soon" then
        color = U.iconColorSoon
    else
        bgAlpha = U.iconBgAlphaIdle
    end

    -- Square icon: convert height to screen-width units
    local aspect = 1
    if g_screenWidth ~= nil and g_screenHeight ~= nil and g_screenWidth > 0 then
        aspect = g_screenHeight / g_screenWidth
    end
    local h = U.iconHeight
    local w = h * aspect
    local padY = U.iconPadding
    local padX = U.iconPadding * aspect
    local boxW = w + 2 * padX
    local boxH = h + 2 * padY
    local boxY = U.topY - boxH

    drawFilledRect(U.x, boxY, boxW, boxH, U.bgColor[1], U.bgColor[2], U.bgColor[3], bgAlpha)

    self.iconOverlay:setPosition(U.x + padX, boxY + padY)
    self.iconOverlay:setDimension(w, h)
    self.iconOverlay:setColor(color[1], color[2], color[3], color[4])
    self.iconOverlay:render()

    -- Number of fields with work this month, bottom right of the box
    if count > 0 then
        setTextAlignment(RenderText.ALIGN_RIGHT)
        setTextBold(true)
        setTextColor(1, 1, 1, 1)
        renderText(U.x + boxW - padX * 0.5, boxY + padY * 0.5, U.iconBadgeSize, tostring(count))
        setTextBold(false)
        setTextAlignment(RenderText.ALIGN_LEFT)
    end
end

function CropYearWheelPlanner:draw()
    if self.settings.displayMode == CropYearWheelPlanner.DISPLAY_HIDDEN then
        return
    end
    if g_gui ~= nil and g_gui:getIsGuiVisible() then
        return
    end
    if g_currentMission == nil or g_currentMission.hud == nil then
        return
    end
    if g_currentMission.hud.getIsVisible ~= nil and not g_currentMission.hud:getIsVisible() then
        return
    end

    local anchor = CropYearWheelPlanner.ANCHORS[self.settings.position] or CropYearWheelPlanner.ANCHORS.top
    CropYearWheelPlanner.UI.x = anchor.x
    CropYearWheelPlanner.UI.topY = anchor.topY

    local plans = self:buildGroups()
    if self.settings.displayMode == CropYearWheelPlanner.DISPLAY_MINIMIZED then
        self:drawMinimized(plans)
    else
        self:drawFull(plans)
    end

    -- Reset render state for other mods
    setTextColor(1, 1, 1, 1)
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
end

addModEventListener(CropYearWheelPlanner)
