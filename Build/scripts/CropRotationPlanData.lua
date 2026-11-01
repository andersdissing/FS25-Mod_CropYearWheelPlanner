-- CropRotationPlanData.lua
-- Plans and field groups per farm, stored by the server in <savegame>/cropRotationPlan.xml.
-- A new savegame starts with no plans and no field groups.
--
--   <cropRotationPlan version="3">
--     <farm id="1" grassInRotation="true" editPermission="manager" nextPlanId="2" nextGroupId="2">
--       <plans>
--         <plan id="1" name="4-year rotation" years="4">
--           <seed crop="WHEAT" t="9"/>
--           <seed crop="GRASS" t="3" dur="12" cut="2"/>
--         </plan>
--       </plans>
--       <fieldGroups>
--         <fieldGroup id="1" fields="3 4 5" plan="1" planYear="2" anchorYear="5"/>
--       </fieldGroups>
--     </farm>
--   </cropRotationPlan>
--
-- Files from v2.0 have <plans> and <fieldGroups> directly under the root: they become farm 1
-- (the single player farm). Their display settings move to the local settings file.
--
-- Display and position are per player and stored on the player's own PC:
--   <profile>/modSettings/FS25_CropRotationPlan/settings.xml

CropRotationPlanData = {}
CropRotationPlanData.FILENAME = "cropRotationPlan.xml"
CropRotationPlanData.XML_ROOT = "cropRotationPlan"
CropRotationPlanData.VERSION = 3
CropRotationPlanData.LOCAL_FOLDER = "modSettings/FS25_CropRotationPlan/"
CropRotationPlanData.LOCAL_FILENAME = "settings.xml"

CropRotationPlanData.DISPLAY_MODES = { "full", "minimized", "hidden" }
-- Who may edit a farm's plans in multiplayer: only the farm manager (default) or everyone on the farm
CropRotationPlanData.EDIT_MANAGER = "manager"
CropRotationPlanData.EDIT_EVERYONE = "everyone"
CropRotationPlanData.POSITIONS = { "top", "left" }

-- Limits checked by the server on every edit
CropRotationPlanData.MAX_NAME_LENGTH = 40
CropRotationPlanData.MAX_SEEDS = 120
CropRotationPlanData.MAX_PLANS = 50
CropRotationPlanData.MAX_GROUPS = 200

function CropRotationPlanData.new()
    return { farms = {} }
end

function CropRotationPlanData.newFarm()
    return {
        grassInRotation = true,
        editPermission = CropRotationPlanData.EDIT_MANAGER,
        plans = {},
        groups = {},
        nextPlanId = 1,
        nextGroupId = 1,
    }
end

-- Farm data; created empty when missing and `create` is true
function CropRotationPlanData.getFarm(data, farmId, create)
    local farm = data.farms[farmId]
    if farm == nil and create then
        farm = CropRotationPlanData.newFarm()
        data.farms[farmId] = farm
    end
    return farm
end

local function isOneOf(value, list)
    for _, v in ipairs(list) do
        if v == value then
            return true
        end
    end
    return false
end

local function parseIds(text)
    local ids = {}
    for part in string.gmatch(text or "", "%S+") do
        local id = tonumber(part)
        if id ~= nil then
            table.insert(ids, math.floor(id))
        end
    end
    return ids
end

local function joinIds(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        table.insert(parts, tostring(id))
    end
    return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Savegame file (server)
---------------------------------------------------------------------------

local function getPath()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then
        return nil
    end
    local dir = g_currentMission.missionInfo.savegameDirectory
    if dir == nil then
        return nil
    end
    return dir .. "/" .. CropRotationPlanData.FILENAME
end
CropRotationPlanData.getPath = getPath

local function loadFarm(xmlFile, key, farm)
    local i = 0
    while true do
        local planKey = string.format("%s.plans.plan(%d)", key, i)
        if not xmlFile:hasProperty(planKey) then
            break
        end
        local plan = {
            id = xmlFile:getInt(planKey .. "#id", farm.nextPlanId),
            name = xmlFile:getString(planKey .. "#name", ""),
            years = math.max(1, math.min(CropRotationPlanLogic.MAX_YEARS, xmlFile:getInt(planKey .. "#years", 1))),
            seeds = {},
        }
        local Lm = plan.years * 12
        local j = 0
        while true do
            local seedKey = string.format("%s.seed(%d)", planKey, j)
            if not xmlFile:hasProperty(seedKey) then
                break
            end
            local crop = xmlFile:getString(seedKey .. "#crop")
            local t = xmlFile:getInt(seedKey .. "#t")
            if crop ~= nil and t ~= nil then
                table.insert(plan.seeds, {
                    crop = crop,
                    t = t % Lm,
                    dur = xmlFile:getInt(seedKey .. "#dur"),
                    cut = xmlFile:getInt(seedKey .. "#cut"),
                })
            end
            j = j + 1
        end
        table.insert(farm.plans, plan)
        farm.nextPlanId = math.max(farm.nextPlanId, plan.id + 1)
        i = i + 1
    end

    i = 0
    while true do
        local groupKey = string.format("%s.fieldGroups.fieldGroup(%d)", key, i)
        if not xmlFile:hasProperty(groupKey) then
            break
        end
        local group = {
            id = xmlFile:getInt(groupKey .. "#id", farm.nextGroupId),
            fields = parseIds(xmlFile:getString(groupKey .. "#fields", "")),
            planId = xmlFile:getInt(groupKey .. "#plan"),
            planYear = xmlFile:getInt(groupKey .. "#planYear", 1),
            anchorYear = xmlFile:getInt(groupKey .. "#anchorYear"),
        }
        table.insert(farm.groups, group)
        farm.nextGroupId = math.max(farm.nextGroupId, group.id + 1)
        i = i + 1
    end
end

-- Returns the data and, for files from v2.0, their display settings (to move to the local file)
function CropRotationPlanData.load()
    local data = CropRotationPlanData.new()
    local path = getPath()
    if path == nil or not fileExists(path) then
        return data, nil
    end
    local xmlFile = XMLFile.load("cropRotationPlanXML", path)
    if xmlFile == nil then
        return data, nil
    end
    local root = CropRotationPlanData.XML_ROOT
    local oldDisplay = nil

    local i = 0
    while true do
        local key = string.format("%s.farm(%d)", root, i)
        if not xmlFile:hasProperty(key) then
            break
        end
        local farmId = xmlFile:getInt(key .. "#id")
        if farmId ~= nil then
            local farm = CropRotationPlanData.getFarm(data, farmId, true)
            farm.grassInRotation = xmlFile:getBool(key .. "#grassInRotation", true)
            if xmlFile:getString(key .. "#editPermission") == CropRotationPlanData.EDIT_EVERYONE then
                farm.editPermission = CropRotationPlanData.EDIT_EVERYONE
            end
            farm.nextPlanId = xmlFile:getInt(key .. "#nextPlanId", 1)
            farm.nextGroupId = xmlFile:getInt(key .. "#nextGroupId", 1)
            loadFarm(xmlFile, key, farm)
        end
        i = i + 1
    end

    -- v2.0 file: everything at the root, one farm
    if xmlFile:hasProperty(root .. ".plans") or xmlFile:hasProperty(root .. ".fieldGroups") or xmlFile:hasProperty(root .. ".settings") then
        local farm = CropRotationPlanData.getFarm(data, 1, true)
        farm.grassInRotation = xmlFile:getBool(root .. ".settings#grassInRotation", true)
        loadFarm(xmlFile, root, farm)
        oldDisplay = {
            displayMode = xmlFile:getString(root .. ".settings#displayMode"),
            position = xmlFile:getString(root .. ".settings#position"),
        }
    end

    xmlFile:delete()
    local plans, groups = 0, 0
    for _, farm in pairs(data.farms) do
        plans = plans + #farm.plans
        groups = groups + #farm.groups
    end
    Logging.info("[CropRotationPlan] Loaded %d plans and %d field groups from %s", plans, groups, path)
    return data, oldDisplay
end

-- Writes the file. Only the server does this. Before a new career is saved the first time there
-- is no savegame folder; then the data stays in memory and is written by the save hook.
function CropRotationPlanData.save(data)
    local path = getPath()
    if path == nil then
        return false
    end
    local root = CropRotationPlanData.XML_ROOT
    local xmlFile = XMLFile.create("cropRotationPlanXML", path, root)
    if xmlFile == nil then
        return false
    end
    xmlFile:setInt(root .. "#version", CropRotationPlanData.VERSION)

    local farmIds = {}
    for farmId in pairs(data.farms) do
        table.insert(farmIds, farmId)
    end
    table.sort(farmIds)

    for f, farmId in ipairs(farmIds) do
        local farm = data.farms[farmId]
        local key = string.format("%s.farm(%d)", root, f - 1)
        xmlFile:setInt(key .. "#id", farmId)
        xmlFile:setBool(key .. "#grassInRotation", farm.grassInRotation)
        xmlFile:setString(key .. "#editPermission", farm.editPermission)
        xmlFile:setInt(key .. "#nextPlanId", farm.nextPlanId)
        xmlFile:setInt(key .. "#nextGroupId", farm.nextGroupId)

        for i, plan in ipairs(farm.plans) do
            local planKey = string.format("%s.plans.plan(%d)", key, i - 1)
            xmlFile:setInt(planKey .. "#id", plan.id)
            xmlFile:setString(planKey .. "#name", plan.name)
            xmlFile:setInt(planKey .. "#years", plan.years)
            for j, seed in ipairs(plan.seeds) do
                local seedKey = string.format("%s.seed(%d)", planKey, j - 1)
                xmlFile:setString(seedKey .. "#crop", seed.crop)
                xmlFile:setInt(seedKey .. "#t", seed.t)
                if seed.dur ~= nil then
                    xmlFile:setInt(seedKey .. "#dur", seed.dur)
                end
                if seed.cut ~= nil then
                    xmlFile:setInt(seedKey .. "#cut", seed.cut)
                end
            end
        end

        for i, group in ipairs(farm.groups) do
            local groupKey = string.format("%s.fieldGroups.fieldGroup(%d)", key, i - 1)
            xmlFile:setInt(groupKey .. "#id", group.id)
            xmlFile:setString(groupKey .. "#fields", joinIds(group.fields))
            if group.planId ~= nil then
                xmlFile:setInt(groupKey .. "#plan", group.planId)
            end
            xmlFile:setInt(groupKey .. "#planYear", group.planYear or 1)
            if group.anchorYear ~= nil then
                xmlFile:setInt(groupKey .. "#anchorYear", group.anchorYear)
            end
        end
    end

    xmlFile:save()
    xmlFile:delete()
    return true
end

---------------------------------------------------------------------------
-- Local settings (per player): display and position
---------------------------------------------------------------------------

local function getLocalPath()
    if getUserProfileAppPath == nil then
        return nil
    end
    return getUserProfileAppPath() .. CropRotationPlanData.LOCAL_FOLDER .. CropRotationPlanData.LOCAL_FILENAME
end

function CropRotationPlanData.newLocalSettings()
    return { displayMode = "full", position = "top" }
end

-- Returns the settings and whether the file existed
function CropRotationPlanData.loadLocal()
    local settings = CropRotationPlanData.newLocalSettings()
    local path = getLocalPath()
    if path == nil or not fileExists(path) then
        return settings, false
    end
    local xmlFile = XMLFile.load("cropRotationPlanSettingsXML", path)
    if xmlFile == nil then
        return settings, false
    end
    local mode = xmlFile:getString("settings#displayMode")
    if isOneOf(mode, CropRotationPlanData.DISPLAY_MODES) then
        settings.displayMode = mode
    end
    local position = xmlFile:getString("settings#position")
    if isOneOf(position, CropRotationPlanData.POSITIONS) then
        settings.position = position
    end
    xmlFile:delete()
    return settings, true
end

function CropRotationPlanData.saveLocal(settings)
    local path = getLocalPath()
    if path == nil then
        return
    end
    createFolder(getUserProfileAppPath() .. "modSettings/")
    createFolder(getUserProfileAppPath() .. CropRotationPlanData.LOCAL_FOLDER)
    local xmlFile = XMLFile.create("cropRotationPlanSettingsXML", path, "settings")
    if xmlFile == nil then
        return
    end
    xmlFile:setString("settings#displayMode", settings.displayMode)
    xmlFile:setString("settings#position", settings.position)
    xmlFile:save()
    xmlFile:delete()
end

-- Applies display settings from a v2.0 savegame file (if valid)
function CropRotationPlanData.applyOldDisplay(settings, old)
    if old == nil then
        return
    end
    if isOneOf(old.displayMode, CropRotationPlanData.DISPLAY_MODES) then
        settings.displayMode = old.displayMode
    end
    if isOneOf(old.position, CropRotationPlanData.POSITIONS) then
        settings.position = old.position
    end
end

---------------------------------------------------------------------------
-- Network streams (server -> clients: whole farms; client -> server: one plan or group)
---------------------------------------------------------------------------

function CropRotationPlanData.writePlan(streamId, plan)
    streamWriteInt32(streamId, plan.id or 0)
    streamWriteString(streamId, plan.name or "")
    streamWriteUInt8(streamId, plan.years)
    streamWriteUInt16(streamId, #plan.seeds)
    for _, seed in ipairs(plan.seeds) do
        streamWriteString(streamId, seed.crop)
        streamWriteUInt16(streamId, seed.t)
        streamWriteUInt8(streamId, seed.dur or 0)
        streamWriteUInt8(streamId, seed.cut or 0)
    end
end

function CropRotationPlanData.readPlan(streamId)
    local plan = {
        id = streamReadInt32(streamId),
        name = streamReadString(streamId),
        years = streamReadUInt8(streamId),
        seeds = {},
    }
    local count = streamReadUInt16(streamId)
    for _ = 1, count do
        local seed = {
            crop = streamReadString(streamId),
            t = streamReadUInt16(streamId),
        }
        local dur = streamReadUInt8(streamId)
        local cut = streamReadUInt8(streamId)
        if dur > 0 then
            seed.dur = dur
        end
        if cut > 0 then
            seed.cut = cut
        end
        table.insert(plan.seeds, seed)
    end
    return plan
end

function CropRotationPlanData.writeGroup(streamId, group)
    streamWriteInt32(streamId, group.id or 0)
    streamWriteInt32(streamId, group.planId or 0)
    streamWriteUInt8(streamId, group.planYear or 1)
    streamWriteInt32(streamId, group.anchorYear or 0)
    streamWriteUInt16(streamId, #group.fields)
    for _, fieldId in ipairs(group.fields) do
        streamWriteInt32(streamId, fieldId)
    end
end

function CropRotationPlanData.readGroup(streamId)
    local group = {
        id = streamReadInt32(streamId),
        planId = streamReadInt32(streamId),
        planYear = streamReadUInt8(streamId),
        anchorYear = streamReadInt32(streamId),
        fields = {},
    }
    if group.planId == 0 then
        group.planId = nil
    end
    if group.anchorYear == 0 then
        group.anchorYear = nil
    end
    local count = streamReadUInt16(streamId)
    for _ = 1, count do
        table.insert(group.fields, streamReadInt32(streamId))
    end
    return group
end

function CropRotationPlanData.writeFarm(streamId, farmId, farm)
    streamWriteInt32(streamId, farmId)
    streamWriteBool(streamId, farm.grassInRotation)
    streamWriteBool(streamId, farm.editPermission == CropRotationPlanData.EDIT_EVERYONE)
    streamWriteInt32(streamId, farm.nextPlanId)
    streamWriteInt32(streamId, farm.nextGroupId)
    streamWriteUInt16(streamId, #farm.plans)
    for _, plan in ipairs(farm.plans) do
        CropRotationPlanData.writePlan(streamId, plan)
    end
    streamWriteUInt16(streamId, #farm.groups)
    for _, group in ipairs(farm.groups) do
        CropRotationPlanData.writeGroup(streamId, group)
    end
end

function CropRotationPlanData.readFarm(streamId)
    local farmId = streamReadInt32(streamId)
    local farm = CropRotationPlanData.newFarm()
    farm.grassInRotation = streamReadBool(streamId)
    if streamReadBool(streamId) then
        farm.editPermission = CropRotationPlanData.EDIT_EVERYONE
    end
    farm.nextPlanId = streamReadInt32(streamId)
    farm.nextGroupId = streamReadInt32(streamId)
    local plans = streamReadUInt16(streamId)
    for _ = 1, plans do
        table.insert(farm.plans, CropRotationPlanData.readPlan(streamId))
    end
    local groups = streamReadUInt16(streamId)
    for _ = 1, groups do
        table.insert(farm.groups, CropRotationPlanData.readGroup(streamId))
    end
    return farmId, farm
end

---------------------------------------------------------------------------
-- Editing helpers (pure table operations on one farm; the server runs them)
---------------------------------------------------------------------------

function CropRotationPlanData.getPlan(farm, id)
    for _, plan in ipairs(farm.plans) do
        if plan.id == id then
            return plan
        end
    end
    return nil
end

function CropRotationPlanData.getGroup(farm, id)
    for i, group in ipairs(farm.groups) do
        if group.id == id then
            return group, i
        end
    end
    return nil
end

function CropRotationPlanData.copyPlan(plan)
    local copy = { id = plan.id, name = plan.name, years = plan.years, seeds = {} }
    for _, seed in ipairs(plan.seeds) do
        table.insert(copy.seeds, { crop = seed.crop, t = seed.t, dur = seed.dur, cut = seed.cut })
    end
    return copy
end

function CropRotationPlanData.copyGroup(group)
    local copy = { id = group.id, planId = group.planId, planYear = group.planYear, anchorYear = group.anchorYear, fields = {} }
    for _, id in ipairs(group.fields) do
        table.insert(copy.fields, id)
    end
    return copy
end

function CropRotationPlanData.addPlan(farm, name)
    local plan = { id = farm.nextPlanId, name = name, years = 4, seeds = {} }
    farm.nextPlanId = farm.nextPlanId + 1
    table.insert(farm.plans, plan)
    return plan
end

-- Replaces the stored plan with the edited copy (Save in the plan editor)
function CropRotationPlanData.putPlan(farm, edited)
    for i, plan in ipairs(farm.plans) do
        if plan.id == edited.id then
            farm.plans[i] = CropRotationPlanData.copyPlan(edited)
            return true
        end
    end
    return false
end

-- Removes the plan; field groups that used it keep their fields but have no plan
function CropRotationPlanData.removePlan(farm, id)
    for i, plan in ipairs(farm.plans) do
        if plan.id == id then
            table.remove(farm.plans, i)
            break
        end
    end
    for _, group in ipairs(farm.groups) do
        if group.planId == id then
            group.planId = nil
        end
    end
end

function CropRotationPlanData.countGroupsForPlan(farm, id)
    local n = 0
    for _, group in ipairs(farm.groups) do
        if group.planId == id then
            n = n + 1
        end
    end
    return n
end

function CropRotationPlanData.addGroup(farm, calendarYear)
    local group = { id = farm.nextGroupId, fields = {}, planId = nil, planYear = 1, anchorYear = calendarYear }
    farm.nextGroupId = farm.nextGroupId + 1
    if #farm.plans > 0 then
        group.planId = farm.plans[1].id
    end
    table.insert(farm.groups, group)
    return group
end

function CropRotationPlanData.removeGroup(farm, id)
    local _, index = CropRotationPlanData.getGroup(farm, id)
    if index ~= nil then
        table.remove(farm.groups, index)
    end
end

-- Group that has the field, or nil
function CropRotationPlanData.getGroupOfField(farm, fieldId)
    for _, group in ipairs(farm.groups) do
        for _, id in ipairs(group.fields) do
            if id == fieldId then
                return group
            end
        end
    end
    return nil
end

function CropRotationPlanData.removeField(farm, fieldId)
    for _, group in ipairs(farm.groups) do
        for i = #group.fields, 1, -1 do
            if group.fields[i] == fieldId then
                table.remove(group.fields, i)
            end
        end
    end
end

-- Adds the field to the group (and takes it out of any other group)
function CropRotationPlanData.addFieldToGroup(farm, group, fieldId)
    CropRotationPlanData.removeField(farm, fieldId)
    table.insert(group.fields, fieldId)
    table.sort(group.fields)
end

-- Example: the owner's Riverbend Springs plan from the mockups (console crpLoadExample)
function CropRotationPlanData.loadExample(farm, calendarYear)
    farm.plans = {}
    farm.groups = {}
    farm.nextPlanId = 1
    farm.nextGroupId = 1
    local four = CropRotationPlanData.addPlan(farm, "4-year rotation")
    four.years = 4
    four.seeds = {
        { crop = "CARROT", t = 5 }, { crop = "WHEAT", t = 9 }, { crop = "CANOLA", t = 19 },
        { crop = "CARROT", t = 30 }, { crop = "PEA", t = 38 }, { crop = "BARLEY", t = 44 },
    }
    local two = CropRotationPlanData.addPlan(farm, "2-year canola")
    two.years = 2
    two.seeds = { { crop = "CANOLA", t = 19 }, { crop = "CARROT", t = 6 }, { crop = "PEA", t = 14 } }
    local groups = {
        { "3 4 5", four, 1 }, { "6 7", four, 2 }, { "8", four, 4 }, { "23 25", four, 3 },
        { "76", two, 1 }, { "77", two, 2 },
    }
    for _, g in ipairs(groups) do
        local group = CropRotationPlanData.addGroup(farm, calendarYear)
        group.fields = parseIds(g[1])
        group.planId = g[2].id
        group.planYear = g[3]
    end
end
