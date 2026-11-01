-- CropYearWheelPlannerCrops.lua
-- The crops that can be planned, read from the game (map + DLC + mod crops actually loaded).
--
-- Reads the same data as the game's own crop calendar (InGameMenuCalendarFrame):
-- g_fruitTypeManager:getFruitTypes() filtered to shownOnMap, and for every period
-- getIsPlantableInPeriod / getIsHarvestableInPeriod with missionInfo.growthMode.
-- getIsPlantableInPeriod indexes growthDataSeasonal without a nil check, so it is only called
-- for fruit types that have seasonal growth data (no protected calls: the ModHub TestRunner forbids them).
--
-- Growth time = months from the first month of the sowing window to the first harvest month
-- after it (wheat: Sep -> Jul = 10). Outside seasonal growth every period answers "yes", so the
-- built-in calendar below (FS25 crop calendar, farmingsimulator.wiki.gg) is used instead.
--
-- A crop: { name, title, sow = { months 1..12 }, grow, ley, block, color, iconFilename }

CropYearWheelPlannerCrops = {}

CropYearWheelPlannerCrops.GROWTH_MODE_SEASONAL = 1
CropYearWheelPlannerCrops.GRASS = "GRASS"

-- Not part of a rotation: l10n key of the reason
CropYearWheelPlannerCrops.BLOCKED = {
    POPLAR = "cywp_block_tree",
    GRAPE = "cywp_block_tree",
    OLIVE = "cywp_block_tree",
    SUGARCANE = "cywp_block_regrows",
    MEADOW = "cywp_block_meadow",
    -- Rice needs a paddy field; how the game marks one is still open (GitHub issue #1)
    RICE = "cywp_block_paddy",
    RICELONGGRAIN = "cywp_block_paddy",
}

-- Fallback calendar: sow months and months from sowing to harvest
CropYearWheelPlannerCrops.CALENDAR = {
    BARLEY = { sow = { 9, 10 }, grow = 9 },
    WHEAT = { sow = { 9, 10 }, grow = 10 },
    OAT = { sow = { 3, 4 }, grow = 4 },
    SORGHUM = { sow = { 4, 5 }, grow = 4 },
    MAIZE = { sow = { 4, 5 }, grow = 4 },
    CANOLA = { sow = { 8, 9 }, grow = 11 },
    SUNFLOWER = { sow = { 3, 4 }, grow = 7 },
    SOYBEAN = { sow = { 4, 5 }, grow = 6 },
    PEA = { sow = { 3, 4 }, grow = 4 },
    GREENBEAN = { sow = { 4, 5, 6 }, grow = 4 },
    POTATO = { sow = { 3, 4 }, grow = 5 },
    SUGARBEET = { sow = { 3, 4 }, grow = 7 },
    REDBEET = { sow = { 4, 5, 6 }, grow = 4 },
    ONION = { sow = { 3, 4 }, grow = 5 },
    CARROT = { sow = { 4, 5, 6, 7 }, grow = 4 },
    PARSNIP = { sow = { 4, 5, 6 }, grow = 4 },
    COTTON = { sow = { 2, 3 }, grow = 8 },
    RICE = { sow = { 4, 5 }, grow = 4 },
    RICELONGGRAIN = { sow = { 4 }, grow = 5 },
    GRASS = { sow = { 3, 4, 5, 6, 7, 8, 9, 10, 11 }, grow = 3 },
}

-- Bar colours (mockup palette); other crops get one from FALLBACK_COLORS
CropYearWheelPlannerCrops.COLORS = {
    BARLEY = { 0.79, 0.64, 0.29 },
    WHEAT = { 0.89, 0.77, 0.42 },
    OAT = { 0.85, 0.81, 0.63 },
    SORGHUM = { 0.71, 0.35, 0.23 },
    MAIZE = { 0.95, 0.76, 0.19 },
    CANOLA = { 0.93, 0.85, 0.23 },
    SUNFLOWER = { 0.94, 0.66, 0.12 },
    SOYBEAN = { 0.66, 0.72, 0.35 },
    PEA = { 0.53, 0.72, 0.31 },
    GREENBEAN = { 0.37, 0.62, 0.24 },
    POTATO = { 0.78, 0.60, 0.42 },
    SUGARBEET = { 0.91, 0.85, 0.75 },
    REDBEET = { 0.72, 0.25, 0.42 },
    ONION = { 0.88, 0.70, 0.48 },
    CARROT = { 0.90, 0.51, 0.18 },
    PARSNIP = { 0.94, 0.89, 0.72 },
    COTTON = { 0.91, 0.91, 0.91 },
    RICE = { 0.75, 0.82, 0.54 },
    RICELONGGRAIN = { 0.84, 0.88, 0.63 },
    SPINACH = { 0.31, 0.56, 0.23 },
    OILSEEDRADISH = { 0.61, 0.44, 0.69 },
    GRASS = { 0.35, 0.63, 0.29 },
}
CropYearWheelPlannerCrops.FALLBACK_COLORS = {
    { 0.55, 0.75, 0.85 }, { 0.85, 0.60, 0.75 }, { 0.70, 0.70, 0.45 }, { 0.50, 0.80, 0.65 },
    { 0.80, 0.55, 0.45 }, { 0.65, 0.60, 0.85 },
}

CropYearWheelPlannerCrops.list = {}   -- sorted by title
CropYearWheelPlannerCrops.byName = {}
-- Goes up every time the crops are read again; caches of derived data compare it
CropYearWheelPlannerCrops.version = 0

local function readPeriods(fruitDesc, predicate, growthMode)
    local periods = {}
    if predicate == nil or fruitDesc.growthDataSeasonal == nil then
        return periods
    end
    for period = 1, 12 do
        if predicate(fruitDesc, growthMode, period) then
            periods[period] = true
        end
    end
    return periods
end

local function count(set)
    local n = 0
    for _ in pairs(set) do
        n = n + 1
    end
    return n
end

-- Growth time from the start of the sowing window to the first harvest period after it
local function growthFromPeriods(plantable, harvestable)
    local start = nil
    for p = 1, 12 do
        local prev = ((p - 2) % 12) + 1
        if plantable[p] and not plantable[prev] then
            start = p
            break
        end
    end
    if start == nil then
        start = 1
    end
    for d = 1, 12 do
        if harvestable[((start - 1 + d) % 12) + 1] then
            return d
        end
    end
    return nil
end

local function growthMode()
    local info = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    if info ~= nil and type(info.growthMode) == "number" then
        return info.growthMode
    end
    return CropYearWheelPlannerCrops.GROWTH_MODE_SEASONAL
end

-- Builds one crop from a fruit type, or nil if it should not be listed at all
local function buildCrop(fruitDesc, mode, colorIndex)
    local name = fruitDesc.name
    if type(name) ~= "string" then
        return nil
    end

    local title = name
    local iconFilename = nil
    local fillType = nil
    if fruitDesc.index ~= nil and g_fruitTypeManager.getFillTypeByFruitTypeIndex ~= nil then
        fillType = g_fruitTypeManager:getFillTypeByFruitTypeIndex(fruitDesc.index)
    end
    if type(fillType) == "table" then
        if type(fillType.title) == "string" and fillType.title ~= "" then
            title = fillType.title
        end
        if type(fillType.hudOverlayFilename) == "string" and fillType.hudOverlayFilename ~= "" then
            iconFilename = fillType.hudOverlayFilename
        end
    end

    local crop = {
        name = name,
        title = title,
        sow = {},
        grow = 0,
        ley = (name == CropYearWheelPlannerCrops.GRASS),
        block = CropYearWheelPlannerCrops.BLOCKED[name],
        color = CropYearWheelPlannerCrops.COLORS[name] or CropYearWheelPlannerCrops.FALLBACK_COLORS[(colorIndex % #CropYearWheelPlannerCrops.FALLBACK_COLORS) + 1],
        iconFilename = iconFilename,
    }

    local isCatchCrop = fruitDesc.getIsCatchCrop ~= nil and fruitDesc:getIsCatchCrop()
    if crop.block == nil and isCatchCrop == true then
        crop.block = "cywp_block_catchCrop"
    end

    local plantable, harvestable = {}, {}
    if mode == CropYearWheelPlannerCrops.GROWTH_MODE_SEASONAL then
        plantable = readPeriods(fruitDesc, fruitDesc.getIsPlantableInPeriod, mode)
        harvestable = readPeriods(fruitDesc, fruitDesc.getIsHarvestableInPeriod, mode)
    end

    local calendar = CropYearWheelPlannerCrops.CALENDAR[name]
    if count(plantable) > 0 and count(harvestable) > 0 and count(plantable) < 12 then
        for p = 1, 12 do
            if plantable[p] then
                table.insert(crop.sow, CropYearWheelPlannerLogic.periodToMonth(p))
            end
        end
        table.sort(crop.sow)
        crop.grow = growthFromPeriods(plantable, harvestable) or 0
        if not crop.ley and crop.block == nil and count(harvestable) >= 11 then
            crop.block = "cywp_block_allYear"
        end
    elseif calendar ~= nil then
        crop.sow = calendar.sow
        crop.grow = calendar.grow
    elseif crop.block == nil then
        crop.block = "cywp_block_unknown"
    end

    if crop.ley then
        -- Grass: the player picks how long the ley stays; 3 months is the shortest
        crop.grow = CropYearWheelPlannerLogic.LEY_DURATIONS[1]
    end
    if crop.block == nil and (crop.grow == nil or crop.grow <= 0 or #crop.sow == 0) then
        crop.block = "cywp_block_unknown"
    end
    return crop
end

-- Reads the crops from the game. Call after the map is loaded.
function CropYearWheelPlannerCrops.load()
    local list, byName = {}, {}
    local fruitTypes = nil
    if g_fruitTypeManager ~= nil and g_fruitTypeManager.getFruitTypes ~= nil then
        fruitTypes = g_fruitTypeManager:getFruitTypes()
    end
    if type(fruitTypes) == "table" then
        local mode = growthMode()
        local colorIndex = 0
        for _, fruitDesc in pairs(fruitTypes) do
            if type(fruitDesc) == "table" and fruitDesc.shownOnMap then
                local crop = buildCrop(fruitDesc, mode, colorIndex)
                if crop ~= nil and byName[crop.name] == nil then
                    colorIndex = colorIndex + 1
                    table.insert(list, crop)
                    byName[crop.name] = crop
                end
            end
        end
    end
    table.sort(list, function(a, b)
        return a.title < b.title
    end)
    CropYearWheelPlannerCrops.list = list
    CropYearWheelPlannerCrops.byName = byName
    CropYearWheelPlannerCrops.version = CropYearWheelPlannerCrops.version + 1
    CropYearWheelPlannerCrops.editorLists = {}
    Logging.info("[CropYearWheelPlanner] %d crops read from the game", #list)
end

-- Crop by fruit type name. Crops in a plan that this map does not have get a grey stand-in,
-- so the plan still shows (and keeps its growth time from the calendar when known).
function CropYearWheelPlannerCrops.get(name)
    local crop = CropYearWheelPlannerCrops.byName[name]
    if crop ~= nil then
        return crop
    end
    local calendar = CropYearWheelPlannerCrops.CALENDAR[name] or { sow = {}, grow = 1 }
    crop = {
        name = name,
        title = name,
        sow = calendar.sow,
        grow = calendar.grow,
        ley = (name == CropYearWheelPlannerCrops.GRASS),
        block = "cywp_block_notOnMap",
        color = { 0.5, 0.5, 0.5 },
    }
    CropYearWheelPlannerCrops.byName[name] = crop
    return crop
end

-- Lookup table name -> crop for CropYearWheelPlannerLogic, including stand-ins for every crop in the plans
function CropYearWheelPlannerCrops.getLookup(plans)
    for _, plan in ipairs(plans or {}) do
        for _, seed in ipairs(plan.seeds) do
            CropYearWheelPlannerCrops.get(seed.crop)
        end
    end
    return CropYearWheelPlannerCrops.byName
end

-- Crops for the plan editor: grass is blocked when "Grass in rotation" is off.
-- Built once per setting (and again after the crops are read again).
CropYearWheelPlannerCrops.editorLists = {}

function CropYearWheelPlannerCrops.getEditorList(grassAllowed)
    local key = grassAllowed and "grass" or "noGrass"
    local cached = CropYearWheelPlannerCrops.editorLists[key]
    if cached ~= nil and (CropYearWheelPlanner == nil or CropYearWheelPlanner.cacheEnabled ~= false) then
        return cached
    end
    local out = {}
    for _, crop in ipairs(CropYearWheelPlannerCrops.list) do
        if crop.ley and not grassAllowed and crop.block == nil then
            local copy = {}
            for k, v in pairs(crop) do
                copy[k] = v
            end
            copy.block = "cywp_block_grassOff"
            table.insert(out, copy)
        else
            table.insert(out, crop)
        end
    end
    CropYearWheelPlannerCrops.editorLists[key] = out
    return out
end

function CropYearWheelPlannerCrops.getTitle(name)
    return CropYearWheelPlannerCrops.get(name).title
end
