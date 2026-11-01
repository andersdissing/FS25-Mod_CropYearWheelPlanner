-- CropRotationPlanSync.lua
-- Multiplayer: the server owns the plans and field groups of every farm.
--
--   * The menu pages never change the data themselves; they call CropRotationPlanSync.request.
--     On the server (and in single player) the edit is applied right away; a client sends it to
--     the server as a CropRotationPlanEditEvent.
--   * The server finds the farm from the connection (not from the event), checks the edit
--     (spectators cannot edit, the plan has no overlaps, the field belongs to the farm, limits),
--     applies it, saves and sends the farm's new state to every client (CropRotationPlanStateEvent).
--     A rejected edit is logged and the sender gets the current state back.
--   * A player who joins gets the state of every farm (FSBaseMission.sendInitialClientState).
--   * In multiplayer only the farm manager may edit a farm's plans, unless the farm manager has
--     switched the farm to "Everyone on the farm". Only the farm manager can change that switch.
--     In single player the player can always edit.

CropRotationPlanSync = {}
local S = CropRotationPlanSync

S.OP = {
    NEW_PLAN = 1,
    PUT_PLAN = 2,
    DELETE_PLAN = 3,
    NEW_GROUP = 4,
    PUT_GROUP = 5,
    DELETE_GROUP = 6,
    ASSIGN_FIELD = 7,
    SET_GRASS = 8,
    SET_PERMISSION = 9,
}

local function spectatorFarmId()
    if FarmManager ~= nil and FarmManager.SPECTATOR_FARM_ID ~= nil then
        return FarmManager.SPECTATOR_FARM_ID
    end
    return 0
end

function S.isMultiplayer()
    return g_currentMission ~= nil and g_currentMission.missionDynamicInfo ~= nil
        and g_currentMission.missionDynamicInfo.isMultiplayer == true
end

-- True if the user is the farm manager of the farm
function S.isFarmManager(farmId, userId)
    if userId == nil then
        return false
    end
    local ok, result = pcall(function()
        local farm = g_farmManager:getFarmById(farmId)
        return farm ~= nil and farm:isUserFarmManager(userId)
    end)
    return ok and result == true
end

-- True if the user may edit the farm's plans (rules at the top of this file)
function S.canEdit(farmId, userId)
    if farmId == nil or farmId == spectatorFarmId() then
        return false
    end
    if not S.isMultiplayer() then
        return true
    end
    local farm = CropRotationPlanData.getFarm(CropRotationPlan.data, farmId, false)
    if farm ~= nil and farm.editPermission == CropRotationPlanData.EDIT_EVERYONE then
        return true
    end
    return S.isFarmManager(farmId, userId)
end

-- True if the user may change who can edit (the farm manager; anyone in single player)
function S.canChangePermission(farmId, userId)
    if farmId == nil or farmId == spectatorFarmId() then
        return false
    end
    if not S.isMultiplayer() then
        return true
    end
    return S.isFarmManager(farmId, userId)
end

-- Edit from this machine. op = { type = S.OP.*, plan, group, id, name, groupId, fieldId, value }
function S.request(op)
    if g_server ~= nil then
        S.apply(op, CropRotationPlan:getFarmId(), CropRotationPlan:getUserId(), nil)
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(CropRotationPlanEditEvent.new(op))
    end
end

-- Server: farm of the player behind a connection
function S.getFarmIdOfConnection(connection)
    local ok, farmId = pcall(function()
        local userId = g_currentMission.userManager:getUserIdByConnection(connection)
        if userId == nil then
            return nil
        end
        local farm = g_farmManager:getFarmByUserId(userId)
        return farm ~= nil and farm.farmId or nil
    end)
    if ok then
        return farmId
    end
    return nil
end

-- True if the field exists and its farmland belongs to the farm
function S.isFieldOfFarm(fieldId, farmId)
    local ok, result = pcall(function()
        local fields = g_fieldManager.fields
        if fields == nil and g_fieldManager.getFields ~= nil then
            fields = g_fieldManager:getFields()
        end
        for _, field in pairs(fields or {}) do
            if field.getId ~= nil and field:getId() == fieldId then
                return field.farmland ~= nil and g_farmlandManager:getFarmlandOwner(field.farmland.id) == farmId
            end
        end
        return false
    end)
    return ok and result == true
end

-- Shortens a name to the limit without cutting a UTF-8 character in half
local function cleanName(name)
    if type(name) ~= "string" then
        return ""
    end
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    local max = CropRotationPlanData.MAX_NAME_LENGTH
    if string.len(name) > max then
        local i = max + 1
        while i > 1 do
            local b = string.byte(name, i)
            if b == nil or b < 128 or b >= 192 then
                break
            end
            i = i - 1
        end
        name = string.sub(name, 1, i - 1)
    end
    return name
end
S.cleanName = cleanName

-- Checks a plan sent by a player; returns true or false and the reason
function S.validatePlan(plan)
    if type(plan.years) ~= "number" or plan.years < 1 or plan.years > CropRotationPlanLogic.MAX_YEARS then
        return false, "years out of range"
    end
    if #plan.seeds > CropRotationPlanData.MAX_SEEDS then
        return false, "too many seeds"
    end
    local Lm = plan.years * 12
    for _, seed in ipairs(plan.seeds) do
        if type(seed.crop) ~= "string" or seed.crop == "" or string.len(seed.crop) > 64 then
            return false, "bad crop name"
        end
        if type(seed.t) ~= "number" or seed.t < 0 or seed.t >= Lm then
            return false, "sow month out of range"
        end
        if seed.dur ~= nil and not CropRotationPlanLogic.contains(CropRotationPlanLogic.LEY_DURATIONS, seed.dur) then
            return false, "bad ley duration"
        end
        if seed.cut ~= nil and not CropRotationPlanLogic.contains(CropRotationPlanLogic.CUT_INTERVALS, seed.cut) then
            return false, "bad cut interval"
        end
    end
    local crops = CropRotationPlanCrops.getLookup({ plan })
    if #CropRotationPlanLogic.getOverlaps(plan, crops) > 0 then
        return false, "crops overlap"
    end
    return true
end

local function applyToFarm(op, farm)
    local D = CropRotationPlanData
    local O = S.OP

    if op.type == O.NEW_PLAN then
        if #farm.plans >= D.MAX_PLANS then
            return false, "too many plans"
        end
        local name = cleanName(op.name)
        if name == "" then
            name = string.format("Plan %d", farm.nextPlanId)
        end
        D.addPlan(farm, name)

    elseif op.type == O.PUT_PLAN then
        local existing = D.getPlan(farm, op.plan.id)
        if existing == nil then
            return false, "plan does not exist"
        end
        local ok, reason = S.validatePlan(op.plan)
        if not ok then
            return false, reason
        end
        local plan = D.copyPlan(op.plan)
        plan.name = cleanName(plan.name)
        if plan.name == "" then
            plan.name = existing.name
        end
        D.putPlan(farm, plan)

    elseif op.type == O.DELETE_PLAN then
        D.removePlan(farm, op.id)

    elseif op.type == O.NEW_GROUP then
        if #farm.groups >= D.MAX_GROUPS then
            return false, "too many field groups"
        end
        D.addGroup(farm, CropRotationPlan:getCalendarYear())

    elseif op.type == O.PUT_GROUP then
        local group = D.getGroup(farm, op.group.id)
        if group == nil then
            return false, "field group does not exist"
        end
        local plan = nil
        if op.group.planId ~= nil then
            plan = D.getPlan(farm, op.group.planId)
            if plan == nil then
                return false, "plan does not exist"
            end
        end
        group.planId = op.group.planId
        local years = plan ~= nil and plan.years or 1
        group.planYear = math.max(1, math.min(years, math.floor(op.group.planYear or 1)))
        -- "Plan year now" is counted from the server's current year
        group.anchorYear = CropRotationPlan:getCalendarYear()

    elseif op.type == O.DELETE_GROUP then
        D.removeGroup(farm, op.id)

    elseif op.type == O.ASSIGN_FIELD then
        if op.groupId == nil or op.groupId == 0 then
            D.removeField(farm, op.fieldId)
        else
            local group = D.getGroup(farm, op.groupId)
            if group == nil then
                return false, "field group does not exist"
            end
            if not S.isFieldOfFarm(op.fieldId, op.farmId) then
                return false, "field is not owned by the farm"
            end
            D.addFieldToGroup(farm, group, op.fieldId)
        end

    elseif op.type == O.SET_GRASS then
        farm.grassInRotation = op.value == true

    elseif op.type == O.SET_PERMISSION then
        farm.editPermission = op.value == true and D.EDIT_EVERYONE or D.EDIT_MANAGER

    else
        return false, "unknown edit"
    end
    return true
end

-- Server: applies an edit for a farm. userId = the player who asked; connection = the sender,
-- nil for the server's own player.
function S.apply(op, farmId, userId, connection)
    if farmId == nil or farmId == spectatorFarmId() then
        Logging.warning("[CropRotationPlan] Edit rejected: player is not on a farm")
        return false
    end
    local allowed
    if op.type == S.OP.SET_PERMISSION then
        allowed = S.canChangePermission(farmId, userId)
    else
        allowed = S.canEdit(farmId, userId)
    end
    local farm = CropRotationPlanData.getFarm(CropRotationPlan.data, farmId, true)
    op.farmId = farmId
    local ok, reason = false, "only the farm manager can edit"
    if allowed then
        ok, reason = applyToFarm(op, farm)
    end
    if not ok then
        Logging.warning("[CropRotationPlan] Edit rejected for farm %d: %s", farmId, tostring(reason))
        if connection ~= nil then
            connection:sendEvent(CropRotationPlanStateEvent.new({ farmId }))
        end
        return false
    end
    CropRotationPlan:save()
    S.broadcastFarm(farmId)
    return true
end

-- Server: send one farm's state to every client
function S.broadcastFarm(farmId)
    if g_server ~= nil and g_server.broadcastEvent ~= nil then
        g_server:broadcastEvent(CropRotationPlanStateEvent.new({ farmId }))
    end
end

---------------------------------------------------------------------------
-- Server -> client: the state of one or all farms
---------------------------------------------------------------------------

CropRotationPlanStateEvent = {}
local CropRotationPlanStateEvent_mt = Class(CropRotationPlanStateEvent, Event)
InitEventClass(CropRotationPlanStateEvent, "CropRotationPlanStateEvent")

function CropRotationPlanStateEvent.emptyNew()
    return Event.new(CropRotationPlanStateEvent_mt)
end

-- farmIds: list of farm ids, or nil for every farm
function CropRotationPlanStateEvent.new(farmIds)
    local self = CropRotationPlanStateEvent.emptyNew()
    self.farmIds = farmIds
    return self
end

function CropRotationPlanStateEvent:writeStream(streamId, connection)
    local data = CropRotationPlan.data
    local ids = self.farmIds
    if ids == nil then
        ids = {}
        for farmId in pairs(data.farms) do
            table.insert(ids, farmId)
        end
    end
    streamWriteUInt16(streamId, #ids)
    for _, farmId in ipairs(ids) do
        CropRotationPlanData.writeFarm(streamId, farmId, CropRotationPlanData.getFarm(data, farmId, true))
    end
end

function CropRotationPlanStateEvent:readStream(streamId, connection)
    self.farms = {}
    local count = streamReadUInt16(streamId)
    for _ = 1, count do
        local farmId, farm = CropRotationPlanData.readFarm(streamId)
        self.farms[farmId] = farm
    end
    self:run(connection)
end

function CropRotationPlanStateEvent:run(connection)
    if connection:getIsServer() then
        -- Client: take over the server's state
        for farmId, farm in pairs(self.farms) do
            CropRotationPlan.data.farms[farmId] = farm
        end
    end
end

---------------------------------------------------------------------------
-- Client -> server: one edit
---------------------------------------------------------------------------

CropRotationPlanEditEvent = {}
local CropRotationPlanEditEvent_mt = Class(CropRotationPlanEditEvent, Event)
InitEventClass(CropRotationPlanEditEvent, "CropRotationPlanEditEvent")

function CropRotationPlanEditEvent.emptyNew()
    return Event.new(CropRotationPlanEditEvent_mt)
end

function CropRotationPlanEditEvent.new(op)
    local self = CropRotationPlanEditEvent.emptyNew()
    self.op = op
    return self
end

function CropRotationPlanEditEvent:writeStream(streamId, connection)
    local op = self.op
    local O = S.OP
    streamWriteUInt8(streamId, op.type)
    if op.type == O.NEW_PLAN then
        streamWriteString(streamId, op.name or "")
    elseif op.type == O.PUT_PLAN then
        CropRotationPlanData.writePlan(streamId, op.plan)
    elseif op.type == O.DELETE_PLAN or op.type == O.DELETE_GROUP then
        streamWriteInt32(streamId, op.id)
    elseif op.type == O.PUT_GROUP then
        CropRotationPlanData.writeGroup(streamId, op.group)
    elseif op.type == O.ASSIGN_FIELD then
        streamWriteInt32(streamId, op.groupId or 0)
        streamWriteInt32(streamId, op.fieldId)
    elseif op.type == O.SET_GRASS or op.type == O.SET_PERMISSION then
        streamWriteBool(streamId, op.value == true)
    end
end

function CropRotationPlanEditEvent:readStream(streamId, connection)
    local O = S.OP
    local op = { type = streamReadUInt8(streamId) }
    if op.type == O.NEW_PLAN then
        op.name = streamReadString(streamId)
    elseif op.type == O.PUT_PLAN then
        op.plan = CropRotationPlanData.readPlan(streamId)
    elseif op.type == O.DELETE_PLAN or op.type == O.DELETE_GROUP then
        op.id = streamReadInt32(streamId)
    elseif op.type == O.PUT_GROUP then
        op.group = CropRotationPlanData.readGroup(streamId)
    elseif op.type == O.ASSIGN_FIELD then
        op.groupId = streamReadInt32(streamId)
        op.fieldId = streamReadInt32(streamId)
    elseif op.type == O.SET_GRASS or op.type == O.SET_PERMISSION then
        op.value = streamReadBool(streamId)
    end
    self.op = op
    self:run(connection)
end

function CropRotationPlanEditEvent:run(connection)
    if not connection:getIsServer() then
        -- Server: the player and farm come from the connection, never from the event
        local userId = nil
        pcall(function()
            userId = g_currentMission.userManager:getUserIdByConnection(connection)
        end)
        S.apply(self.op, S.getFarmIdOfConnection(connection), userId, connection)
    end
end

---------------------------------------------------------------------------
-- New players get every farm's state
---------------------------------------------------------------------------

if FSBaseMission ~= nil and FSBaseMission.sendInitialClientState ~= nil then
    FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState, function(mission, connection, user, farm)
        if g_server ~= nil and connection ~= nil then
            connection:sendEvent(CropRotationPlanStateEvent.new(nil))
        end
    end)
end
