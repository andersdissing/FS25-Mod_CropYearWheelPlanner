-- CropYearWheelPlannerLogic.lua
-- Pure functions: no game API calls, so the logic can be tested outside the game (tests/test_logic.py).
--
-- Time in a plan is counted in absolute months: t = 0 is January of plan year 1,
-- t = 12 is January of plan year 2, and so on. A plan with L years has L * 12 months and
-- wraps around: after the last month of year L comes January of year 1 again.
--
-- A plan:  { id, name, years, seeds = { { crop, t, dur, cut } } }
--   crop  fruit type name (e.g. "WHEAT")
--   t     sow month (0 .. years * 12 - 1)
--   dur   only grass (ley): months the ley stays; other crops use the crop's growth time
--   cut   only grass: cut every 2 ("ready to harvest") or 3 ("fully grown") growing months
--
-- A crop (from CropYearWheelPlannerCrops): { name, sow = { months 1..12 }, grow, ley, block }
--   grow   months from sowing to harvest
--   ley    true for grass: the player chooses how long it stays
--   block  l10n key of the reason it cannot be used in a rotation, or nil
--
-- The rules follow the plan editor mockup (docs: Editor_Crop.dc.html):
--   * a seed occupies its sow month up to and including its harvest month;
--   * the next crop may be sown in the harvest month of the one before;
--   * a gap is the time between a harvest and the next sowing, shown when at least
--     one month in between is free.

CropYearWheelPlannerLogic = {}

CropYearWheelPlannerLogic.MAX_YEARS = 8
CropYearWheelPlannerLogic.LEY_DURATIONS = { 3, 6, 12, 24, 36 }
CropYearWheelPlannerLogic.CUT_INTERVALS = { 2, 3 }
CropYearWheelPlannerLogic.DEFAULT_CUT = 2
-- Grass grows from March to October; no growth November to February
CropYearWheelPlannerLogic.FIRST_GROWING_MONTH = 3
CropYearWheelPlannerLogic.LAST_GROWING_MONTH = 10

local L = CropYearWheelPlannerLogic

---------------------------------------------------------------------------
-- Months and periods
---------------------------------------------------------------------------

-- Game period 1 = March ... period 10 = December, 11 = January, 12 = February.
function L.periodToMonth(period)
    return ((period + 1) % 12) + 1
end

function L.monthToPeriod(month)
    return ((month - 3) % 12) + 1
end

-- Month 1..12 of an absolute month
function L.monthOf(t)
    return (t % 12) + 1
end

-- Plan year 1..years of an absolute month (wraps)
function L.yearOf(t, years)
    return math.floor((t % (years * 12)) / 12) + 1
end

-- The game year (environment.currentYear) runs March to February. Plans run January to
-- December, so January and February belong to the next calendar year.
function L.calendarYear(gameYear, period)
    if period >= 11 then
        return gameYear + 1
    end
    return gameYear
end

local function contains(list, value)
    for _, v in ipairs(list) do
        if v == value then
            return true
        end
    end
    return false
end
L.contains = contains

---------------------------------------------------------------------------
-- Seeds and gaps
---------------------------------------------------------------------------

-- Length in months from sowing to harvest (or last cut for a ley)
function L.seedLength(seed, crop)
    if seed.dur ~= nil then
        return seed.dur
    end
    if crop ~= nil and crop.grow ~= nil and crop.grow > 0 then
        return crop.grow
    end
    return 1
end

-- Seeds sorted by sow month, each { i = index in plan.seeds, crop, t, e = harvest month, dur, cut }
function L.getSeeds(plan, crops)
    local list = {}
    for i, seed in ipairs(plan.seeds) do
        table.insert(list, {
            i = i,
            crop = seed.crop,
            t = seed.t,
            e = seed.t + L.seedLength(seed, crops[seed.crop]),
            dur = seed.dur,
            cut = seed.cut,
        })
    end
    table.sort(list, function(a, b)
        if a.t == b.t then
            return a.i < b.i
        end
        return a.t < b.t
    end)
    return list
end

-- Free gaps between consecutive seeds (cyclic). a = harvest month of the seed before,
-- b = sow month of the seed after (b > a, may go past the end of the plan).
function L.getGaps(plan, crops)
    local Lm = plan.years * 12
    local seeds = L.getSeeds(plan, crops)
    local gaps = {}
    if #seeds == 0 then
        table.insert(gaps, { a = 0, b = Lm })
        return gaps
    end
    for k, s in ipairs(seeds) do
        local nextSeed = seeds[(k % #seeds) + 1]
        local b = nextSeed.t
        if k == #seeds then
            b = nextSeed.t + Lm
        end
        if b - s.e >= 2 then
            table.insert(gaps, { a = s.e, b = b })
        end
    end
    return gaps
end

-- The gap that starts at month a (compared modulo the plan length), or nil
function L.findGap(plan, crops, a)
    local Lm = plan.years * 12
    for _, gap in ipairs(L.getGaps(plan, crops)) do
        if (a - gap.a) % Lm == 0 then
            return gap
        end
    end
    return nil
end

-- Sow months (absolute) where the crop can be sown in the gap and is harvested before
-- the next crop is sown. Empty when the crop is blocked.
function L.getSowChoices(crop, a, b)
    local out = {}
    if crop == nil or crop.block ~= nil then
        return out
    end
    local grow = crop.grow or 0
    if crop.ley then
        grow = L.LEY_DURATIONS[1]
    end
    if grow <= 0 then
        return out
    end
    for s = a, b do
        if contains(crop.sow, L.monthOf(s)) and s + grow <= b then
            table.insert(out, s)
        end
    end
    return out
end

function L.cropFits(crop, a, b)
    return #L.getSowChoices(crop, a, b) > 0
end

-- Ley durations (months) that fit between sowing and the next crop's sowing
function L.getLeyChoices(sow, b)
    local out = {}
    for _, d in ipairs(L.LEY_DURATIONS) do
        if sow + d <= b then
            table.insert(out, d)
        end
    end
    return out
end

-- Number of growing months (March to October) after sowing, up to and including month `to`
local function isGrowingMonth(t)
    local m = L.monthOf(t)
    return m >= L.FIRST_GROWING_MONTH and m <= L.LAST_GROWING_MONTH
end

function L.getGrowingMonths(from, to)
    local n = 0
    for t = from + 1, to do
        if isGrowingMonth(t) then
            n = n + 1
        end
    end
    return n
end

-- About how many cuts a ley gives: one every `interval` growing months
function L.getCutCount(sow, dur, interval)
    return math.floor(L.getGrowingMonths(sow, sow + dur) / interval)
end

-- Absolute months of the cuts of a ley
function L.getCutMonths(sow, dur, interval)
    local out = {}
    local growing = 0
    for t = sow + 1, sow + dur do
        if isGrowingMonth(t) then
            growing = growing + 1
            if growing % interval == 0 then
                table.insert(out, t)
            end
        end
    end
    return out
end

-- Crops (names) that can be sown in the month after a harvest at absolute month h
function L.getFollowUps(cropList, h, exceptName)
    local out = {}
    local m = L.monthOf(h)
    for _, crop in ipairs(cropList) do
        if crop.name ~= exceptName and crop.block == nil and contains(crop.sow, m) then
            table.insert(out, crop.name)
        end
    end
    return out
end

-- New seed for the plan; t is stored inside 0 .. years*12 - 1
function L.makeSeed(plan, crop, sow, dur, cut)
    local Lm = plan.years * 12
    local seed = { crop = crop.name, t = sow % Lm }
    if crop.ley then
        seed.dur = dur or L.LEY_DURATIONS[1]
        seed.cut = cut or L.DEFAULT_CUT
    end
    return seed
end

---------------------------------------------------------------------------
-- Plan checks
---------------------------------------------------------------------------

-- Overlapping seeds: list of { a = seed, b = next seed } that share a growing month.
-- Harvest and next sowing in the same month is allowed.
function L.getOverlaps(plan, crops)
    local Lm = plan.years * 12
    local seeds = L.getSeeds(plan, crops)
    local out = {}
    if #seeds == 1 then
        if seeds[1].e - seeds[1].t > Lm then
            table.insert(out, { a = seeds[1], b = seeds[1] })
        end
        return out
    end
    for k, s in ipairs(seeds) do
        local nextSeed = seeds[(k % #seeds) + 1]
        local b = nextSeed.t
        if k == #seeds then
            b = nextSeed.t + Lm
        end
        if s.e > b then
            table.insert(out, { a = s, b = nextSeed })
        end
    end
    return out
end

-- Plan years (1..years) where no crop grows at all
function L.getEmptyYears(plan, crops)
    local Lm = plan.years * 12
    local used = {}
    for _, s in ipairs(L.getSeeds(plan, crops)) do
        for t = s.t, s.e do
            used[math.floor((t % Lm) / 12) + 1] = true
        end
    end
    local out = {}
    for y = 1, plan.years do
        if not used[y] then
            table.insert(out, y)
        end
    end
    return out
end

-- Free months in the whole cycle
function L.getFreeMonths(plan, crops)
    local n = 0
    for _, gap in ipairs(L.getGaps(plan, crops)) do
        n = n + math.max(0, gap.b - gap.a - 1)
    end
    return n
end

-- The last year can be removed if nothing is sown in it and the plan still has no overlaps
function L.canRemoveYear(plan, crops)
    if plan.years <= 1 then
        return false
    end
    local lastYearStart = (plan.years - 1) * 12
    for _, seed in ipairs(plan.seeds) do
        if seed.t >= lastYearStart then
            return false
        end
    end
    local shorter = { years = plan.years - 1, seeds = plan.seeds }
    return #L.getOverlaps(shorter, crops) == 0
end

function L.canAddYear(plan)
    return plan.years < L.MAX_YEARS
end

---------------------------------------------------------------------------
-- Year rows (plan editor and plan list)
---------------------------------------------------------------------------

-- Splits months from..to (absolute, inclusive) into pieces per year row:
-- { row = 1..years, from = 0..11, to = 0..11 }
function L.getPieces(from, to, years)
    local Lm = years * 12
    local out = {}
    for t = from, to do
        local k = t % Lm
        local row = math.floor(k / 12) + 1
        local col = k % 12
        local last = out[#out]
        if last ~= nil and last.row == row and last.to == col - 1 then
            last.to = col
        else
            table.insert(out, { row = row, from = col, to = col })
        end
    end
    return out
end

-- Bars per year row: rows[y] = { { seed, from, to, lane } }. Bars that share a month
-- (harvest, then sowing in the same month) get different lanes (1 or 2).
function L.getRows(plan, crops)
    local rows = {}
    for y = 1, plan.years do
        rows[y] = {}
    end
    for _, s in ipairs(L.getSeeds(plan, crops)) do
        for _, p in ipairs(L.getPieces(s.t, s.e, plan.years)) do
            table.insert(rows[p.row], { seed = s, from = p.from, to = p.to, lane = 1 })
        end
    end
    for y = 1, plan.years do
        table.sort(rows[y], function(a, b)
            return a.from < b.from
        end)
        local laneEnd = {}
        for _, bar in ipairs(rows[y]) do
            local lane = nil
            for l, e in ipairs(laneEnd) do
                if e < bar.from then
                    lane = l
                    break
                end
            end
            if lane == nil then
                table.insert(laneEnd, bar.to)
                lane = #laneEnd
            else
                laneEnd[lane] = bar.to
            end
            bar.lane = math.min(lane, 2)
        end
    end
    return rows
end

-- Gap pieces per year row: rows[y] = { { gap, from, to } } (free months only)
function L.getGapRows(plan, crops)
    local rows = {}
    for y = 1, plan.years do
        rows[y] = {}
    end
    for _, gap in ipairs(L.getGaps(plan, crops)) do
        if gap.b - gap.a >= 2 then
            for _, p in ipairs(L.getPieces(gap.a + 1, gap.b - 1, plan.years)) do
                table.insert(rows[p.row], { gap = gap, from = p.from, to = p.to })
            end
        end
    end
    return rows
end

-- Crop names that grow in plan year y, in the order they appear in that year
function L.getCropsInYear(plan, crops, y)
    local list = {}
    for _, bar in ipairs(L.getRows(plan, crops)[y] or {}) do
        table.insert(list, bar)
    end
    table.sort(list, function(a, b)
        return a.from < b.from
    end)
    local names = {}
    for _, bar in ipairs(list) do
        table.insert(names, bar.seed.crop)
    end
    return names
end

---------------------------------------------------------------------------
-- Field groups
---------------------------------------------------------------------------

-- A field group: { fields = { ids }, planId, planYear, anchorYear }
-- planYear is the plan year in calendar year anchorYear; it moves on by itself every year.
function L.getPlanYear(group, calendarYear, years)
    local planYear = group.planYear or 1
    local anchor = group.anchorYear or calendarYear
    return ((planYear - 1 + (calendarYear - anchor)) % years) + 1
end

-- Task list of a plan: { { action = "sow" | "harvest" | "cut", crop, t } }, t absolute
function L.getTasks(plan, crops)
    local tasks = {}
    for _, s in ipairs(L.getSeeds(plan, crops)) do
        table.insert(tasks, { action = "sow", crop = s.crop, t = s.t })
        local crop = crops[s.crop]
        if (crop ~= nil and crop.ley) or s.dur ~= nil then
            local cuts = L.getCutMonths(s.t, s.e - s.t, s.cut or L.DEFAULT_CUT)
            if #cuts == 0 or cuts[#cuts] ~= s.e then
                table.insert(cuts, s.e)
            end
            for _, c in ipairs(cuts) do
                table.insert(tasks, { action = "cut", crop = s.crop, t = c })
            end
        else
            table.insert(tasks, { action = "harvest", crop = s.crop, t = s.e })
        end
    end
    return tasks
end

-- Status of a field group in calendar year Y, month m (1..12):
--   planYear   1..years
--   nowTasks   tasks this month
--   nextTask   next task after this month (nil if the plan has no tasks)
--   nextIn     months until nextTask
--   nextMonth  month 1..12 of nextTask
--   nextIsNextYear  true if nextTask is in the next calendar year
--   cropsThisYear   crop names in this plan year
function L.getGroupStatus(plan, crops, group, calendarYear, month)
    local Lm = plan.years * 12
    local planYear = L.getPlanYear(group, calendarYear, plan.years)
    local now = (planYear - 1) * 12 + (month - 1)
    local status = {
        planYear = planYear,
        nowTasks = {},
        cropsThisYear = L.getCropsInYear(plan, crops, planYear),
    }
    local best = nil
    for _, task in ipairs(L.getTasks(plan, crops)) do
        local d = (task.t - now) % Lm
        if d == 0 then
            table.insert(status.nowTasks, task)
        elseif best == nil or d < best then
            best = d
            status.nextTask = task
        end
    end
    if status.nextTask ~= nil then
        status.nextIn = best
        status.nextMonth = ((month - 1 + best) % 12) + 1
        status.nextIsNextYear = (month - 1 + best) >= 12
    elseif #status.nowTasks > 0 then
        -- Only one task in the whole plan: it comes back after a full cycle
        status.nextTask = status.nowTasks[1]
        status.nextIn = Lm
        status.nextMonth = month
        status.nextIsNextYear = true
    end
    return status
end
