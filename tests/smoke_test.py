"""Smoke test: runs the whole mod (Build/scripts) in Lua against a stubbed FS25 environment.

Not a replacement for testing in the game, but it catches what breaks a mod at runtime:
nil fields, wrong arguments to string.format (the l10n texts are the real ones from
modDesc.xml), errors while drawing or clicking, network streams that are written and read
differently.

1. Single player: plays through the screens like a player (new plan, plan editor, field groups,
   on-screen plan), checks the savegame round trip, then clicks randomly for a while.
2. Multiplayer: one server and two clients, each its own Lua runtime running the mod. Events are
   written to a stream on one side and read on the other. A client on farm 2 makes plans and
   field groups through the menu; the server checks and shares them; bad edits are rejected.

Usage: python tests/smoke_test.py        Needs: pip install lupa
"""
import os
import random
import re
import sys
import xml.etree.ElementTree as ET

from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "Build")

desc = ET.parse(os.path.join(BUILD, "modDesc.xml")).getroot()
l10n_prefix = desc.find("l10n").get("filenamePrefix")
texts = {t.get("name"): t.get("text") for t in ET.parse(os.path.join(BUILD, l10n_prefix + "_en.xml")).getroot().iter("text")}
texts["button_ok"] = "OK"
frame_ids = re.findall(r'\bid="([A-Za-z]+)"', open(os.path.join(BUILD, "gui/CropRotationPlanFrame.xml"), encoding="utf-8").read())

ENV = r"""
unpack = table.unpack
ERRORS = {}
RENDERED = {}
NEXT_TEXT = "Renamed"

Logging = {
  info = function(...) end,
  warning = function(fmt, ...) table.insert(WARNINGS, string.format(fmt, ...)) end,
  error = function(fmt, ...) local m = string.format(fmt, ...) print("ERROR " .. m) table.insert(ERRORS, m) end,
}
WARNINGS = {}

g_i18n = { getText = function(self, key)
  local v = TEXTS[key]
  if v == nil then error("missing l10n " .. tostring(key)) end
  return v
end }

g_pixelSizeScaledX = 1 / 1920
g_pixelSizeScaledY = 1 / 1080
g_screenWidth, g_screenHeight = 1920, 1080
RenderText = { ALIGN_LEFT = 0, ALIGN_CENTER = 1, ALIGN_RIGHT = 2 }
Input = { MOUSE_BUTTON_LEFT = 1, MOUSE_BUTTON_WHEEL_UP = 4, MOUSE_BUTTON_WHEEL_DOWN = 5 }
GS_PRIO_LOW = 1
function drawFilledRect(x, y, w, h, r, g, b, a)
  for _, v in ipairs({ x, y, w, h, r, g, b, a }) do
    if type(v) ~= "number" or v ~= v then error("drawFilledRect with bad value") end
  end
end
function renderText(x, y, size, text)
  if type(text) ~= "string" then error("renderText with " .. type(text)) end
  if type(x) ~= "number" or type(y) ~= "number" or type(size) ~= "number" then error("renderText with bad position") end
  table.insert(RENDERED, text)
end
function setTextColor(r, g, b, a) end
function setTextBold(b) end
function setTextAlignment(a) end
function getTextWidth(size, text)
  if type(text) ~= "string" then error("getTextWidth with " .. type(text)) end
  return size * 0.55 * string.len(text) * (1080 / 1920)
end
function addConsoleCommand() end
function removeConsoleCommand() end

-- Files
FILES = {}
function getUserProfileAppPath() return "/profile/" end
function createFolder(path) end
XMLFile = {}
XMLFile.__index = XMLFile
function XMLFile.create(name, path, root) return setmetatable({ path = path, values = {} }, XMLFile) end
function XMLFile.load(name, path)
  local v = FILES[path]
  if v == nil then return nil end
  local copy = {}
  for k, x in pairs(v) do copy[k] = x end
  return setmetatable({ path = path, values = copy }, XMLFile)
end
local function get(self, key, default) local v = self.values[key] if v == nil then return default end return v end
local function set(self, key, v) self.values[key] = v end
XMLFile.getInt, XMLFile.getString, XMLFile.getBool = get, get, get
XMLFile.setInt, XMLFile.setString, XMLFile.setBool = set, set, set
function XMLFile:hasProperty(key)
  for k in pairs(self.values) do
    if k == key or string.sub(k, 1, #key + 1) == key .. "#" or string.sub(k, 1, #key + 1) == key .. "." then return true end
  end
  return false
end
function XMLFile:save() FILES[self.path] = self.values end
function XMLFile:delete() end
function fileExists(path) return FILES[path] ~= nil end

Overlay = { new = function(file, x, y, w, h)
  if type(file) ~= "string" then error("Overlay.new without file") end
  return { setPosition = function() end, setDimension = function() end, setColor = function() end, render = function() end, delete = function() end }
end }

Utils = { appendedFunction = function(f, g) return function(...) f(...) g(...) end end }
PlayerInputComponent = { registerGlobalPlayerActionEvents = function() end }
FSBaseMission = { saveSavegame = function() end, sendInitialClientState = function() end }
InputAction = { CRP_TOGGLE_SIZE = 1 }
g_inputBinding = { registerActionEvent = function() return true, 1 end, setActionEventText = function() end, setActionEventTextPriority = function() end }
GuiUtils = { getUVs = function() return { 0, 0, 0, 1, 1, 0, 1, 1 } end }
FocusManager = { setFocus = function() end }
InGameMenuSettingsFrame = { COLOR_ALTERNATING = { [true] = { 0.1, 0.1, 0.1, 1 }, [false] = { 0.2, 0.2, 0.2, 1 } } }
TextInputDialog = { show = function(cb, target, default, title, prompt, maxChars, okText)
  if type(title) ~= "string" or type(okText) ~= "string" then error("TextInputDialog.show arguments") end
  -- The game calls callback(text, clickOk) when there is no target; the mod must pass one
  if target == nil then error("TextInputDialog.show without target") end
  cb(target, NEXT_TEXT, true)
end }

function addModEventListener(obj) MOD = obj end

-- Network: events are written to a list of values and read back on the other side
FarmManager = { SPECTATOR_FARM_ID = 0 }
NET_OUT = {}
EVENTS = {}
Event = { new = function(mt) return setmetatable({}, mt) end }
function InitEventClass(class, name) EVENTS[name] = class class.eventName = name end
local W, R, RPOS = nil, nil, 1
local function put(v) table.insert(W, v) end
local function int(v, lo, hi, what)
  if type(v) ~= "number" or math.floor(v) ~= v or v < lo or v > hi then error(what .. " out of range: " .. tostring(v)) end
end
function streamWriteInt32(id, v) int(v, -2147483648, 2147483647, "Int32") put(v) end
function streamWriteUInt8(id, v) int(v, 0, 255, "UInt8") put(v) end
function streamWriteUInt16(id, v) int(v, 0, 65535, "UInt16") put(v) end
function streamWriteBool(id, v) if type(v) ~= "boolean" then error("Bool expected, got " .. type(v)) end put(v) end
function streamWriteString(id, v) if type(v) ~= "string" then error("String expected, got " .. type(v)) end put(v) end
local function take() local v = R[RPOS] RPOS = RPOS + 1 if v == nil then error("read past end of stream") end return v end
streamReadInt32, streamReadUInt8, streamReadUInt16, streamReadBool, streamReadString = take, take, take, take, take
function capture(event, target)
  W = {}
  event:writeStream(1, nil)
  table.insert(NET_OUT, { name = event.eventName, target = target, values = W })
  W = nil
end
function makeConnection(isServer, userId)
  return {
    isServer = isServer, userId = userId,
    getIsServer = function(self) return self.isServer end,
    sendEvent = function(self, event) capture(event, "user:" .. tostring(self.userId)) end,
  }
end
function deliver(name, values, fromServer, userId)
  R, RPOS = values, 1
  local event = EVENTS[name].emptyNew()
  event:readStream(1, makeConnection(fromServer, userId))
  if RPOS ~= #values + 1 then error("stream of " .. name .. " not read to the end") end
  R = nil
end
if IS_SERVER then
  g_server = { broadcastEvent = function(self, event) capture(event, "all") end }
end
g_client = { getServerConnection = function() return { sendEvent = function(self, event) capture(event, "server") end } end }
-- user 1: farm 1 manager, user 2: farm 2 manager, user 3: spectator, user 4: farm 2, not manager
USER_FARMS = { [1] = 1, [2] = 2, [3] = 0, [4] = 2 }
MANAGERS = { [1] = { [1] = true }, [2] = { [2] = true } }
g_farmManager = {
  getFarmByUserId = function(self, userId)
    local f = USER_FARMS[userId]
    if f == nil then return nil end
    return { farmId = f }
  end,
  getFarmById = function(self, farmId)
    return { farmId = farmId, isUserFarmManager = function(farm, userId)
      return MANAGERS[farmId] ~= nil and MANAGERS[farmId][userId] == true
    end }
  end,
}

-- GUI elements
GuiElement = {}
GuiElement.__index = GuiElement
function GuiElement.stub(id)
  return setmetatable({ id = id, elements = {}, visible = true, absPosition = { 0.1, 0.05 }, absSize = { 0.85, 0.75 }, size = { 0.05, 0.03 } }, GuiElement)
end
function GuiElement:setText(t) if type(t) ~= "string" then error("setText " .. type(t)) end self.text = t end
function GuiElement:setVisible(v) self.visible = v end
function GuiElement:getIsVisible() return self.visible end
function GuiElement:setSelected(v) self.selected = v end
function GuiElement:setTexts(t) self.texts = t end
function GuiElement:setState(s) self.state = s end
function GuiElement:setDisabled(d) self.disabled = d end
function GuiElement:addText(t) end
function GuiElement:setSize(w, h) self.size = { w, h } end
function GuiElement:invalidateLayout() end
function GuiElement:getDescendantByName(n) return GuiElement.stub(n) end
function GuiElement:setImageFilename(f) end
function GuiElement:setImageUVs(s, ...) if select("#", ...) ~= 8 then error("setImageUVs needs 8 values") end end
function GuiElement:setImageColor(s, r, g, b, a) if a == nil then error("setImageColor needs rgba") end end
function GuiElement:updateAbsolutePosition() end
function GuiElement:delete() end
function GuiElement:draw() end
function GuiElement:mouseEvent(x, y, isDown, isUp, button, eventUsed) return eventUsed end

function Class(members, baseClass)
  members = members or {}
  if baseClass ~= nil then setmetatable(members, { __index = baseClass }) end
  members.superClass = function() return baseClass end
  return { __index = members }
end
TabbedMenuFrameElement = setmetatable({}, { __index = GuiElement })
function TabbedMenuFrameElement.new(target, mt)
  return setmetatable({ elements = {}, visible = true, absPosition = { 0, 0 }, absSize = { 1, 1 } }, mt)
end
function TabbedMenuFrameElement:onFrameOpen() end

g_gui = { frames = {}, getIsGuiVisible = function() return false end }
function g_gui:loadGui(file, name, frame)
  for _, id in ipairs(FRAME_IDS) do frame[id] = GuiElement.stub(id) end
  frame.elements[1] = GuiElement.stub("root")
  local rows = {}
  for _, id in ipairs({ "sectionDisplay", "row", "row", "row", "sectionCrops", "row", "sectionMultiplayer", "row" }) do
    local e = GuiElement.stub(id)
    if string.sub(id, 1, 7) == "section" then e.name = "sectionHeader" end
    table.insert(rows, e)
  end
  frame.settingsLayout.elements = rows
  self.frames[name] = frame
end

local pageMap, pageSettings = GuiElement.stub("pageMap"), GuiElement.stub("pageSettings")
g_inGameMenu = {
  pageSettings = pageSettings,
  pageFrames = { pageMap, pageSettings },
  pagingElement = {
    elements = { pageMap, pageSettings },
    pages = { { element = pageMap }, { element = pageSettings } },
    addElement = function(self, e) table.insert(self.elements, e) table.insert(self.pages, { element = e }) end,
    removeElement = function(self, e) end,
    updateAbsolutePosition = function() end,
    updatePageMapping = function() end,
  },
  pageTabs = { [pageMap] = { iconFilename = "map" }, [pageSettings] = { iconFilename = "settings" } },
  enabledPages = { pageMap, pageSettings },
  restorePageIndex = 3,
  registerPage = function(self, f) table.insert(self.pageFrames, f) end,
  addPageTab = function(self, f, icon) self.pageTabs[f] = { iconFilename = icon } end,
  -- Like TabbedMenu:rebuildTabList: the tab list is every page in pageFrames
  rebuildTabList = function(self)
    self.enabledPages = {}
    for _, page in ipairs(self.pageFrames) do table.insert(self.enabledPages, page) end
  end,
  -- Like TabbedMenu:unregisterPage when the class lookup fails: nothing is removed
  unregisterPage = function() return false end,
}
-- What TabbedMenu.lua:285 needs: every page in the tab list has a tab
function tabListConsistent()
  for _, page in ipairs(g_inGameMenu.enabledPages) do
    if g_inGameMenu.pageTabs[page] == nil then return false end
  end
  return true
end

-- Game state
g_currentMission = {
  missionInfo = { growthMode = 1, savegameDirectory = IS_SERVER and "/savegame1" or nil },
  environment = { currentYear = 3, currentPeriod = 4 },
  hud = { getIsVisible = function() return true end },
  getFarmId = function() return LOCAL_FARM end,
  playerUserId = USER_ID,
  missionDynamicInfo = { isMultiplayer = IS_MP },
  userManager = { getUserIdByConnection = function(self, connection) return connection.userId end },
}
-- Fields 40 and 41 belong to farm 2, field 50 to nobody, all others to farm 1
g_fieldManager = { fields = {} }
for _, id in ipairs({ 3, 4, 5, 6, 7, 8, 12, 23, 25, 31, 40, 41, 50, 76, 77 }) do
  table.insert(g_fieldManager.fields, { farmland = { id = id }, getId = function() return id end })
end
g_farmlandManager = { getFarmlandOwner = function(self, id)
  if id == 40 or id == 41 then return 2 end
  if id == 50 then return 0 end
  return 1
end }

-- Crops: months to periods
local function periods(months)
  local set = {}
  for _, m in ipairs(months) do set[((m - 3) % 12) + 1] = true end
  return set
end
local function fruit(index, name, sow, harvest, opts)
  opts = opts or {}
  local p, h = periods(sow), periods(harvest)
  return {
    index = index, name = name, shownOnMap = opts.shownOnMap ~= false,
    getIsPlantableInPeriod = function(self, mode, period) return p[period] == true end,
    getIsHarvestableInPeriod = function(self, mode, period) return h[period] == true end,
    getIsCatchCrop = function(self) return opts.catch == true end,
  }
end
local fruits = {
  fruit(1, "WHEAT", { 9, 10 }, { 7, 8 }), fruit(2, "BARLEY", { 9, 10 }, { 6, 7 }),
  fruit(3, "CANOLA", { 8, 9 }, { 7, 8 }), fruit(4, "OAT", { 3, 4 }, { 7, 8 }),
  fruit(5, "PEA", { 3, 4 }, { 7, 8 }), fruit(6, "CARROT", { 4, 5, 6, 7 }, { 8, 9, 10, 11 }),
  fruit(7, "POTATO", { 3, 4 }, { 8, 9 }), fruit(8, "MAIZE", { 4, 5 }, { 8, 9, 10 }),
  fruit(9, "GRASS", { 3, 4, 5, 6, 7, 8, 9, 10, 11 }, { 4, 5, 6, 7, 8, 9, 10 }),
  fruit(10, "RICE", { 4, 5 }, { 8, 9 }), fruit(11, "POPLAR", { 3, 4, 5 }, { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }),
  fruit(12, "OILSEEDRADISH", { 3, 4, 5, 6, 7, 8, 9, 10 }, { 6, 7, 8, 9, 10, 11 }, { catch = true }),
  fruit(13, "SPINACH", { 3, 4, 5 }, { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }),
  fruit(14, "SUGARCANE", { 3, 4 }, { 10, 11 }),
  fruit(15, "DECO", {}, {}, { shownOnMap = false }),
}
g_fruitTypeManager = {
  getFruitTypes = function(self) return fruits end,
  getFillTypeByFruitTypeIndex = function(self, i)
    local f = fruits[i]
    local title = string.upper(string.sub(f.name, 1, 1)) .. string.lower(string.sub(f.name, 2))
    return { title = title, hudOverlayFilename = "data/fillTypes/" .. f.name .. ".dds" }
  end,
}

g_currentModDirectory = MOD_DIR
function source(path) dofile(path) end
dofile(MOD_DIR .. "scripts/CropRotationPlan.lua")

-- Test helpers
function frame() return CropRotationPlanFrame.instance end
function farm(id) return CropRotationPlanData.getFarm(CropRotationPlan.data, id or LOCAL_FARM, true) end
function drawFrame() RENDERED = {} frame():draw() end
function hitIds()
  local out = {}
  for _, h in ipairs(frame().pageState.hits) do table.insert(out, h.id or "") end
  return out
end
local function tryClick(id)
  drawFrame()
  local hits = frame().pageState.hits
  for i = #hits, 1, -1 do
    local h = hits[i]
    if h.id == id then
      local x, y = h.x + h.w / 2, h.y + h.h / 2
      frame():mouseEvent(x, y, true, false, Input.MOUSE_BUTTON_LEFT, false)
      frame():mouseEvent(x, y, false, true, Input.MOUSE_BUTTON_LEFT, false)
      drawFrame()
      return true
    end
  end
  return false
end
-- Clicks the box with this id; scrolls the plan editor's side panel down if it is not in view
function clickId(id)
  if tryClick(id) then return true end
  local state = frame().pageState
  local region = state.panelRegion
  if region ~= nil and state.editor ~= nil then
    state.editor.panelScroll = 0
    for _ = 1, 40 do
      wheel(region.x + region.w / 2, region.y + region.h / 2, false)
      if tryClick(id) then return true end
    end
  end
  error("no clickable box '" .. id .. "'")
end
function clickIndex(i)
  local h = frame().pageState.hits[i]
  local x, y = h.x + h.w / 2, h.y + h.h / 2
  frame():mouseEvent(x, y, true, false, Input.MOUSE_BUTTON_LEFT, false)
end
function wheel(x, y, up)
  frame():mouseEvent(x, y, true, false, up and Input.MOUSE_BUTTON_WHEEL_UP or Input.MOUSE_BUTTON_WHEEL_DOWN, false)
end
function rendered() return table.concat(RENDERED, " | ") end
function hud(mode)
  MOD.settings.displayMode = mode
  RENDERED = {}
  MOD:draw()
  return table.concat(RENDERED, " | ")
end
function takeNet()
  local out = NET_OUT
  NET_OUT = {}
  return out
end
"""


def make_runtime(is_server, local_farm, multiplayer=False, user_id=1):
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.MOD_DIR = BUILD.replace("\\", "/") + "/"
    g.TEXTS = lua.table_from(texts)
    g.FRAME_IDS = lua.table_from(frame_ids)
    g.IS_SERVER = is_server
    g.LOCAL_FARM = local_farm
    g.IS_MP = multiplayer
    g.USER_ID = user_id
    lua.execute(ENV)
    return lua


failures = []


def check(name, cond, detail=""):
    if cond:
        print("ok  ", name)
    else:
        failures.append(f"{name} {detail}")
        print("FAIL", name, detail)


def pylist(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


def errors(lua):
    return pylist(lua.globals().ERRORS)


# =====================================================================================
# 1. Single player
# =====================================================================================
print("--- single player")
lua = make_runtime(True, 1)
G = lua.globals()
MOD = G.MOD
C = G.CropRotationPlanCrops


def ids():
    return pylist(G.hitIds())


def click(id_):
    G.clickId(id_)


def farm():
    return G.farm()


MOD.loadMap(MOD, "map.xml")
crops = C.byName
check("crops read from the game", len(C.list) == 14, len(C.list))
check("wheat grows 10 months (Sep -> Jul)", crops.WHEAT.grow == 10, crops.WHEAT.grow)
check("barley grows 9 months", crops.BARLEY.grow == 9, crops.BARLEY.grow)
check("carrot grows 4 months (Apr -> Aug)", crops.CARROT.grow == 4, crops.CARROT.grow)
check("grass is a ley", crops.GRASS.ley is True)
check("rice blocked: paddy", crops.RICE.block == "crp_block_paddy")
check("poplar blocked: tree", crops.POPLAR.block == "crp_block_tree")
check("radish blocked: cover crop", crops.OILSEEDRADISH.block == "crp_block_catchCrop")
check("spinach blocked: all year", crops.SPINACH.block == "crp_block_allYear")
check("sugarcane blocked: regrows", crops.SUGARCANE.block == "crp_block_regrows")
check("deco fruit not listed", crops.DECO is None)

frame = G.frame()
pos = lua.eval("""function(list)
  local f, s
  for i, e in ipairs(list) do
    if e == CropRotationPlanFrame.instance or (type(e) == "table" and e.element == CropRotationPlanFrame.instance) then f = i end
    if e == g_inGameMenu.pageSettings or (type(e) == "table" and e.element == g_inGameMenu.pageSettings) then s = i end
  end
  return f, s
end""")
menu = G.g_inGameMenu
for name, lst in (("paging elements", menu.pagingElement.elements), ("paging pages", menu.pagingElement.pages), ("pageFrames", menu.pageFrames)):
    f, s = pos(lst)
    check(f"{name}: tab directly above Settings", f is not None and s is not None and f == s - 1, (f, s))

out = G.hud("full")
check("HUD empty text", texts["crp_hudEmpty"] in out, out)
G.hud("minimized")

# Settings
frame.onFrameOpen(frame)
check("single player: multiplayer section hidden", frame.sectionMultiplayer.visible is False and frame.editRow.visible is False and frame.editStatusRow.visible is False)
check("single player: can always edit", MOD.canEdit(MOD) is True and frame.grassOption.disabled is False)
check("grass option On/Off", frame.grassOption.texts[1] == "On")
frame.onClickGrass(frame, 2)
check("grass off (farm setting)", farm().grassInRotation is False)
frame.onClickGrass(frame, 1)
frame.onClickDisplay(frame, 2)
frame.onClickPosition(frame, 2)
check("display + position", MOD.settings.displayMode == "minimized" and MOD.settings.position == "left")
local_file = G.FILES["/profile/modSettings/FS25_CropRotationPlan/settings.xml"]
check("display + position saved on this PC", local_file is not None and local_file["settings#position"] == "left")

# Plans: new plan, editor
frame.updateSubCategoryPages(frame, 2)
G.drawFrame()
check("no plans text", texts["crp_noPlans"] in G.rendered())
G.NEXT_TEXT = "4-year"
click("+ NEW PLAN")
check("plan created and named", len(farm().plans) == 1 and farm().plans[1].name == "4-year")
click("EDIT PLAN")
check("editor open", frame.pageState.editor is not None)
check("empty plan: gap selected", frame.pageState.editor.sel.type == "gap")
click("crop:WHEAT")
check("sow choices offered", any(i.endswith("year 1") for i in ids()), ids())
click("ADD SEED TO PLAN")
ed = frame.pageState.editor
check("wheat added", len(ed.plan.seeds) == 1 and ed.plan.seeds[1].crop == "WHEAT")

grass_added = False
for _ in range(20):
    gaps = [i for i in ids() if i.startswith("gap:")]
    if not gaps:
        break
    click(gaps[0])
    fit = [i for i in ids() if i.startswith("crop:")]
    if not fit:
        continue
    pick = "crop:GRASS" if ("crop:GRASS" in fit and not grass_added) else fit[0]
    click(pick)
    if pick == "crop:GRASS":
        click("3 months")
        click("cut:3")
        grass_added = True
    click("ADD SEED TO PLAN")
ed = frame.pageState.editor
check("plan filled with several seeds", len(ed.plan.seeds) >= 3, len(ed.plan.seeds))
check("grass ley added with cut 3", any(ed.plan.seeds[i].crop == "GRASS" and ed.plan.seeds[i].cut == 3 for i in range(1, len(ed.plan.seeds) + 1)))
check("no overlaps", len(G.CropRotationPlanLogic.getOverlaps(ed.plan, C.byName)) == 0)

bars = [i for i in ids() if i.startswith("bar:")]
check("bars drawn", len(bars) > 0)
n = len(ed.plan.seeds)
click(bars[0])
check("seed selected", ed.sel.type == "seed")
click("REMOVE SEED FROM PLAN")
check("seed removed", len(ed.plan.seeds) == n - 1)
check("removed seed's gap selected", ed.sel.type == "gap")
click("years:next")
check("year added", ed.plan.years == 5)
click("years:prev")
check("year removed", ed.plan.years == 4)
G.NEXT_TEXT = "Rotation A"
click(ed.plan.name)
check("rename in editor", ed.plan.name == "Rotation A")
check("not stored before Save", farm().plans[1].name == "4-year")
click("SAVE PLAN")
check("editor closed", frame.pageState.editor is None)
check("plan saved", farm().plans[1].name == "Rotation A" and len(farm().plans[1].seeds) == n - 1)

click("EDIT PLAN")
click("years:next")
click("CANCEL")
check("cancel discards", farm().plans[1].years == 4)

click("YEAR ROWS")
check("year rows view", frame.pageState.plansView == "rows")
rows_bars = [i for i in ids() if i.startswith("bar:")]
click(rows_bars[0])
check("bar opens editor with seed", frame.pageState.editor is not None and frame.pageState.editor.sel.type == "seed")
click("CANCEL")
click("COLUMNS")
cards = [i for i in ids() if i.startswith("card:")]
check("crop cards", len(cards) > 0)
click(cards[0])
click("CANCEL")
click("addCrop:1")
click("CANCEL")
click("years:next")
check("years changed from the plan list", farm().plans[1].years == 5)
click("years:prev")

G.NEXT_TEXT = "Temp"
click("+ NEW PLAN")
check("new plan selected", G.frame().pageState.selectedPlanId == farm().plans[2].id)
click("DELETE PLAN")
click("CLICK AGAIN TO DELETE")
check("plan deleted", len(farm().plans) == 1)

# Field groups
frame.updateSubCategoryPages(frame, 3)
G.drawFrame()
click("+ NEW FIELD GROUP")
check("owned fields clickable in add mode (40 is farm 2's)", "field:3" in ids() and "field:40" not in ids())
check("group added with first plan", len(farm().groups) == 1 and farm().groups[1].planId == farm().plans[1].id)
for f in ("3", "4", "5"):
    click("field:" + f)
g = farm().groups[1]
check("fields added", pylist(g.fields) == [3, 4, 5])
click("chip:4")
check("chip removes field", pylist(g.fields) == [3, 5])
click("groupYear:1:next")
g = farm().groups[1]
check("plan year now set", g.planYear == 2 and g.anchorYear == MOD.getCalendarYear(MOD))
click("+ NEW FIELD GROUP")
click("field:3")
check("field moves between groups", pylist(farm().groups[1].fields) == [5])
click("groupPlan:2:next")
check("group plan cycles to none", farm().groups[2].planId is None)
click("delGroup:2")
click("delGroup:2")
check("group removed", len(farm().groups) == 1)

# HUD, every month
env = G.g_currentMission.environment
statuses = 0
for year in (3, 4):
    for period in range(1, 13):
        env.currentYear = year
        env.currentPeriod = period
        out = G.hud("full")
        if "Now:" in out or "Next:" in out:
            statuses += 1
        G.hud("minimized")
check("HUD shows Now/Next every month", statuses == 24, statuses)
check("HUD shows the plan name", "Rotation A" in G.hud("full"))

# Savegame round trip
MOD.save(MOD)
loaded, old = G.CropRotationPlanData.load()
lf = loaded.farms[1]
same = (len(lf.plans) == len(farm().plans) and lf.plans[1].name == farm().plans[1].name
        and len(lf.plans[1].seeds) == len(farm().plans[1].seeds) and lf.groups[1].planYear == 2
        and lf.groups[1].id == farm().groups[1].id)
check("save and load give the same data", same)
seeds_a = sorted((s.crop, s.t, s.dur, s.cut) for s in pylist(farm().plans[1].seeds))
seeds_b = sorted((s.crop, s.t, s.dur, s.cut) for s in pylist(lf.plans[1].seeds))
check("seeds identical after load", seeds_a == seeds_b, (seeds_a, seeds_b))

# A v2.0 file (no farms) becomes farm 1 and its display settings move to this PC
G.FILES["/savegame1/cropRotationPlan.xml"] = lua.table_from({
    "cropRotationPlan#version": 2,
    "cropRotationPlan.settings#displayMode": "hidden", "cropRotationPlan.settings#position": "left",
    "cropRotationPlan.settings#grassInRotation": False,
    "cropRotationPlan.plans.plan(0)#id": 1, "cropRotationPlan.plans.plan(0)#name": "Old", "cropRotationPlan.plans.plan(0)#years": 2,
    "cropRotationPlan.plans.plan(0).seed(0)#crop": "WHEAT", "cropRotationPlan.plans.plan(0).seed(0)#t": 9,
    "cropRotationPlan.fieldGroups.fieldGroup(0)#fields": "3 4", "cropRotationPlan.fieldGroups.fieldGroup(0)#plan": 1,
    "cropRotationPlan.fieldGroups.fieldGroup(0)#planYear": 2, "cropRotationPlan.fieldGroups.fieldGroup(0)#anchorYear": 3,
})
old_data, old_display = G.CropRotationPlanData.load()
of = old_data.farms[1]
check("v2.0 file: plans and groups become farm 1", of is not None and of.plans[1].name == "Old" and pylist(of.groups[1].fields) == [3, 4] and of.grassInRotation is False)
check("v2.0 file: group gets an id", of.groups[1].id == 1 and of.nextGroupId == 2)
check("v2.0 file: display settings handed over", old_display is not None and old_display.displayMode == "hidden")
MOD.save(MOD)

# Example plan
MOD.consoleLoadExample(MOD)
check("example: 2 plans, 6 groups", len(farm().plans) == 2 and len(farm().groups) == 6)
for i in range(1, 3):
    check(f"example plan {i} has no overlaps", len(G.CropRotationPlanLogic.getOverlaps(farm().plans[i], C.byName)) == 0)
out = G.hud("full")
check("example on screen", "4-year rotation" in out and "2-year canola" in out, out[:200])
MOD.consoleReloadCrops(MOD)

lua.execute("FIT_OK = true for w = 1, 60 do local s = CropRotationPlanUI.fit('Græsmark på ørnebakken', 0.02, w * 0.002) "
            "if not utf8.len(s) then FIT_OK = false end end")
check("shortened Danish text is valid UTF-8", G.FIT_OK is True)

# Random clicking
random.seed(1)
for step in range(3000):
    if step % 150 == 0:
        frame.updateSubCategoryPages(frame, random.choice([2, 3]))
        G.NEXT_TEXT = random.choice(["X", "Plan with a long name that does not fit anywhere", "Ø"])
    if step % 400 == 0:
        env.currentPeriod = random.randint(1, 12)
    G.drawFrame()
    n_hits = len(frame.pageState.hits)
    if n_hits == 0:
        continue
    if random.random() < 0.05:
        G.wheel(0.5, 0.5, random.random() < 0.5)
    G.clickIndex(random.randint(1, n_hits))
    if step % 50 == 0:
        G.hud(random.choice(["full", "minimized"]))
check("random clicking: no errors", len(errors(lua)) == 0, errors(lua)[:3])
for i in range(1, len(farm().plans) + 1):
    check(f"plan {i} still valid after random clicks", len(G.CropRotationPlanLogic.getOverlaps(farm().plans[i], C.byName)) == 0)
check("random clicking: no rejected edits", len(pylist(G.WARNINGS)) == 0, pylist(G.WARNINGS)[:3])

check("tab list consistent while the mod is loaded", G.tabListConsistent() is True)
MOD.deleteMap(MOD)
check("after unloading: page gone from every menu list", G.tabListConsistent() is True
      and len(G.g_inGameMenu.pageFrames) == 2 and len(G.g_inGameMenu.enabledPages) == 2)
check("after unloading: restore index back in range", G.g_inGameMenu.restorePageIndex == 1)
check("single player: no errors logged", len(errors(lua)) == 0, errors(lua)[:3])

# =====================================================================================
# 2. Multiplayer: server (farm 1), client on farm 2 (user 2), spectator (user 3)
# =====================================================================================
print("--- multiplayer")
server = make_runtime(True, 1, True, 1)
client = make_runtime(False, 2, True, 2)
SG, CG = server.globals(), client.globals()
targets = {"all": [(client, 2)], "user:2": [(client, 2)], "user:3": []}


def pump():
    """Delivers queued events until nothing is left. Returns the number delivered."""
    delivered = 0
    for _ in range(20):
        moved = False
        for msg in pylist(CG.takeNet()):
            server.globals().deliver(msg["name"], server.table_from(pylist(msg["values"])), False, 2)
            delivered += 1
            moved = True
        for msg in pylist(SG.takeNet()):
            for rt, _ in targets.get(msg["target"], []):
                rt.globals().deliver(msg["name"], rt.table_from(pylist(msg["values"])), True, 0)
                delivered += 1
            moved = True
        if not moved:
            break
    return delivered


def sfarm(farm_id):
    return SG.farm(farm_id)


def cfarm(farm_id):
    return CG.farm(farm_id)


SG.MOD.loadMap(SG.MOD, "map.xml")
SG.MOD.consoleLoadExample(SG.MOD)
pump()
# The client joins: it gets every farm, then loads the map; loadMap must keep what it got
SG.FSBaseMission.sendInitialClientState(SG.g_currentMission, SG.makeConnection(False, 2), None, None)
pump()
CG.MOD.loadMap(CG.MOD, "map.xml")
check("client got farm 1 on join", len(cfarm(1).plans) == 2 and len(cfarm(1).groups) == 6)
check("client loadMap kept the received state", CG.MOD.data.farms[1] is not None)
check("client writes no savegame file", CG.FILES["/savegame1/cropRotationPlan.xml"] is None)

cframe = CG.frame()
cframe.onFrameOpen(cframe)
cframe.updateSubCategoryPages(cframe, 2)
CG.drawFrame()
check("client's farm 2 has no plans", texts["crp_noPlans"] in CG.rendered())

# New plan from the client: goes to the server, comes back, gets selected
CG.NEXT_TEXT = "Client plan"
CG.clickId("+ NEW PLAN")
check("nothing changes on the client before the server answers", len(cfarm(2).plans) == 0)
check("events sent to the server and back", pump() >= 2)
check("server made the plan for farm 2", len(sfarm(2).plans) == 1 and sfarm(2).plans[1].name == "Client plan")
check("server's farm 1 untouched", len(sfarm(1).plans) == 2)
check("client got the plan", len(cfarm(2).plans) == 1)
CG.drawFrame()
check("client selected its new plan", cframe.pageState.selectedPlanId == cfarm(2).plans[1].id)

# Plan editor on the client, Save sends the plan
CG.clickId("EDIT PLAN")
CG.clickId("crop:WHEAT")
CG.clickId("ADD SEED TO PLAN")
gaps = [i for i in pylist(CG.hitIds()) if i.startswith("gap:")]
CG.clickId(gaps[0])
fit = [i for i in pylist(CG.hitIds()) if i.startswith("crop:")]
CG.clickId(fit[0])
CG.clickId("ADD SEED TO PLAN")
seeds = len(cframe.pageState.editor.plan.seeds)
CG.clickId("SAVE PLAN")
pump()
check("server stored the client's plan", len(sfarm(2).plans[1].seeds) == seeds, (len(sfarm(2).plans[1].seeds), seeds))
check("client sees the saved plan", len(cfarm(2).plans[1].seeds) == seeds)

# Field groups from the client
cframe.updateSubCategoryPages(cframe, 3)
CG.drawFrame()
CG.clickId("+ NEW FIELD GROUP")
pump()
CG.drawFrame()
check("server made the group for farm 2", len(sfarm(2).groups) == 1)
check("client's own fields offered (40, 41), not farm 1's", "field:40" in pylist(CG.hitIds()) and "field:3" not in pylist(CG.hitIds()))
CG.clickId("field:40")
pump()
check("field 40 in the group on the server", pylist(sfarm(2).groups[1].fields) == [40])
CG.clickId("groupYear:1:next")
pump()
check("plan year now on the server", sfarm(2).groups[1].planYear == 2 and sfarm(2).groups[1].anchorYear == SG.MOD.getCalendarYear(SG.MOD))

# Bad edits are rejected and the sender gets the state back
group_id = sfarm(2).groups[1].id
OP = CG.CropRotationPlanSync.OP
CG.CropRotationPlanSync.request(client.table_from({"type": OP.ASSIGN_FIELD, "groupId": group_id, "fieldId": 3}))
pump()
check("field of another farm rejected", pylist(sfarm(2).groups[1].fields) == [40] and pylist(sfarm(1).groups[1].fields) == [3, 4, 5])
bad = CG.CropRotationPlanData.copyPlan(cfarm(2).plans[1])
bad.seeds[len(bad.seeds) + 1] = client.table_from({"crop": "CANOLA", "t": bad.seeds[1].t})
CG.CropRotationPlanSync.request(client.table_from({"type": OP.PUT_PLAN, "plan": bad}))
pump()
check("overlapping plan rejected", len(sfarm(2).plans[1].seeds) == seeds)
check("rejections logged on the server", len(pylist(SG.WARNINGS)) >= 2, pylist(SG.WARNINGS))
# The client knows farm 1's plans (it got every farm on join); it sends one as its own edit
plan1 = CG.CropRotationPlanData.copyPlan(cfarm(1).plans[1])
plan1.name = "Hacked"
CG.CropRotationPlanSync.request(client.table_from({"type": OP.PUT_PLAN, "plan": plan1}))
pump()
check("farm 2 cannot change farm 1's plan", sfarm(1).plans[1].name == "4-year rotation")
# Plan ids are per farm: the edit landed on farm 2's own plan 1, as it should
check("the edit changed farm 2's own plan instead", sfarm(2).plans[1].name == "Hacked")

# A spectator (user 3, farm 0) cannot edit
CG.LOCAL_FARM = 0
CG.drawFrame()
check("spectator sees the join-a-farm text", texts["crp_spectator"] in CG.rendered())
plan_count = lua_count = sum(len(SG.MOD.data.farms[f].plans) for f in (1, 2))
CG.CropRotationPlanSync.request(client.table_from({"type": OP.NEW_PLAN, "name": "Spy"}))
for msg in pylist(CG.takeNet()):
    SG.deliver(msg["name"], server.table_from(pylist(msg["values"])), False, 3)
check("spectator edit rejected", SG.MOD.data.farms[0] is None and sum(len(SG.MOD.data.farms[f].plans) for f in (1, 2)) == plan_count)
SG.takeNet()
CG.LOCAL_FARM = 2

# Grass setting is per farm
cframe.onClickGrass(cframe, 2)
pump()
check("grass off for farm 2 only", sfarm(2).grassInRotation is False and sfarm(1).grassInRotation is True)

# On-screen plan on the client shows farm 2, the server shows farm 1
out = CG.hud("full")
check("client HUD shows its own farm", "Hacked" in out and "4-year rotation" not in out, out[:200])
out = SG.hud("full")
check("server HUD shows farm 1", "4-year rotation" in out and "Hacked" not in out)

# Server saves both farms
SG.MOD.save(SG.MOD)
loaded, _ = SG.CropRotationPlanData.load()
check("savegame keeps both farms", len(loaded.farms[1].plans) == 2 and len(loaded.farms[2].plans) == 1 and pylist(loaded.farms[2].groups[1].fields) == [40])

# --- Who can edit -------------------------------------------------------------------
cframe.updateSubCategoryPages(cframe, 1)
cframe.onFrameOpen(cframe)
check("multiplayer: section shown", cframe.sectionMultiplayer.visible is True and cframe.editRow.visible is True)
check("default: farm manager only", sfarm(2).editPermission == "manager" and cframe.editOption.state == 1)
check("farm manager: switch enabled, status 'can edit'",
      cframe.editOption.disabled is False and cframe.editStatusOption.texts[1] == texts["crp_status_canEdit"])


def deliver_from(user_id, op_table):
    """An edit sent by another player (user_id) on the client's machine, delivered to the server."""
    CG.CropRotationPlanSync.request(op_table)
    for msg in pylist(CG.takeNet()):
        SG.deliver(msg["name"], server.table_from(pylist(msg["values"])), False, user_id)
    SG.takeNet()


before = len(sfarm(2).plans)
deliver_from(4, client.table_from({"type": OP.NEW_PLAN, "name": "Worker plan"}))
check("non-manager edit rejected while 'farm manager only'", len(sfarm(2).plans) == before)
deliver_from(4, client.table_from({"type": OP.SET_PERMISSION, "value": True}))
check("non-manager cannot change who can edit", sfarm(2).editPermission == "manager")

cframe.onClickEditPermission(cframe, 2)
pump()
check("farm manager switched to everyone", sfarm(2).editPermission == "everyone" and cfarm(2).editPermission == "everyone")
check("farm 1 still 'farm manager only'", sfarm(1).editPermission == "manager")
deliver_from(4, client.table_from({"type": OP.NEW_PLAN, "name": "Worker plan"}))
check("non-manager can edit when 'everyone'", len(sfarm(2).plans) == before + 1)
deliver_from(4, client.table_from({"type": OP.SET_PERMISSION, "value": False}))
check("non-manager still cannot change the switch", sfarm(2).editPermission == "everyone")
cframe.onClickEditPermission(cframe, 1)
pump()
check("farm manager switched back", sfarm(2).editPermission == "manager")

# The client's player is demoted: read-only screens
CG.MANAGERS[2][2] = False
SG.MANAGERS[2][2] = False  # the game syncs farm roles; both sides see the demotion
cframe.onFrameOpen(cframe)
check("non-manager: switch disabled", cframe.editOption.disabled is True)
check("non-manager: status says view only", cframe.editStatusOption.texts[1] == texts["crp_status_managerOnly"])
check("non-manager: grass setting disabled", cframe.grassOption.disabled is True)
cframe.updateSubCategoryPages(cframe, 2)
CG.drawFrame()
check("non-manager: plans page shows view only", texts["crp_status_managerOnly"] in CG.rendered())
check("non-manager: no edit buttons", "+ NEW PLAN" not in pylist(CG.hitIds()) and "EDIT PLAN" not in pylist(CG.hitIds()))
check("non-manager: can still look at other plans and views", "YEAR ROWS" in pylist(CG.hitIds()))
shown = CG.rendered()
check("non-manager: plan and its crops still shown", "Hacked" in shown and any(c in shown for c in ("Wheat", "Canola", "Barley")), shown[:300])
check("non-manager: edit buttons hidden, not just greyed out",
      not any(t in shown for t in ("+ NEW PLAN", "EDIT PLAN", "DELETE PLAN", "+ Add crop")))
check("non-manager: crop cards not clickable", not any(i.startswith("card:") for i in pylist(CG.hitIds())))
check("non-manager: no stepper arrows", not any(i.endswith(":prev") or i.endswith(":next") for i in pylist(CG.hitIds())))
cframe.updateSubCategoryPages(cframe, 3)
CG.drawFrame()
check("non-manager: field groups read-only", "+ NEW FIELD GROUP" not in pylist(CG.hitIds()) and not any(i.startswith("chip:") for i in pylist(CG.hitIds())))
shown = CG.rendered()
check("non-manager: groups, fields and plan year still shown", "40" in shown and "Year 2" in shown and "Hacked" in shown, shown[:300])
check("non-manager: + New field group and X hidden", "+ NEW FIELD GROUP" not in shown and " X " not in (" " + shown + " "))
check("non-manager: no stepper arrows on groups", not any(i.endswith(":prev") or i.endswith(":next") for i in pylist(CG.hitIds())))
before = len(sfarm(2).groups)
cframe.onClickGrass(cframe, 1)
CG.CropRotationPlanSync.request(client.table_from({"type": OP.NEW_GROUP}))
pump()
check("non-manager: requests from the server side also rejected", len(sfarm(2).groups) == before)
random.seed(3)
for step in range(300):
    CG.drawFrame()
    n_hits = len(cframe.pageState.hits)
    if n_hits:
        CG.clickIndex(random.randint(1, n_hits))
    pump()
check("non-manager random clicking changes nothing", len(sfarm(2).groups) == before)
CG.MANAGERS[2][2] = True
SG.MANAGERS[2][2] = True
cframe.onFrameOpen(cframe)

# Random clicking on the client, with the network in between
random.seed(2)
for step in range(1500):
    if step % 100 == 0:
        cframe.updateSubCategoryPages(cframe, random.choice([2, 3]))
    CG.drawFrame()
    n_hits = len(cframe.pageState.hits)
    if n_hits:
        CG.clickIndex(random.randint(1, n_hits))
    pump()
for i in range(1, len(sfarm(2).plans) + 1):
    check(f"farm 2 plan {i} valid on the server", len(SG.CropRotationPlanLogic.getOverlaps(sfarm(2).plans[i], SG.CropRotationPlanCrops.byName)) == 0)
same = (len(sfarm(2).plans) == len(cfarm(2).plans) and len(sfarm(2).groups) == len(cfarm(2).groups)
        and all(len(sfarm(2).plans[i].seeds) == len(cfarm(2).plans[i].seeds) for i in range(1, len(sfarm(2).plans) + 1)))
check("client and server agree after random clicking", same)
check("server's farm 1 untouched by the client", len(sfarm(1).plans) == 2 and len(sfarm(1).groups) == 6)

check("multiplayer: no errors on the server", len(errors(server)) == 0, errors(server)[:3])
check("multiplayer: no errors on the client", len(errors(client)) == 0, errors(client)[:3])

if failures:
    print("\nFAILED:")
    for f in failures:
        print("  ", f)
    sys.exit(1)
print("\nsmoke test passed")
