"""Tests for Build/scripts/CropYearWheelPlannerLogic.lua, run in a real Lua runtime (lupa).

The expected values come from the plan editor mockup (Editor_Crop.dc.html): its crop calendar
and its example 4-year plan.

Usage: python tests/test_logic.py        Needs: pip install lupa
"""
import os
import sys

from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(os.path.join(ROOT, "Build/scripts/CropYearWheelPlannerLogic.lua"), encoding="utf-8").read())

# Mockup calendar: sow months and months from sowing to harvest
lua.execute("""
CROPS = {
  BARLEY = { name = "BARLEY", sow = {9, 10}, grow = 9 },
  WHEAT = { name = "WHEAT", sow = {9, 10}, grow = 10 },
  OAT = { name = "OAT", sow = {3, 4}, grow = 4 },
  CANOLA = { name = "CANOLA", sow = {8, 9}, grow = 11 },
  PEA = { name = "PEA", sow = {3, 4}, grow = 4 },
  CARROT = { name = "CARROT", sow = {4, 5, 6, 7}, grow = 4 },
  POTATO = { name = "POTATO", sow = {3, 4}, grow = 5 },
  GRASS = { name = "GRASS", sow = {3, 4, 5, 6, 7, 8, 9, 10, 11}, grow = 3, ley = true },
  RICE = { name = "RICE", sow = {4, 5}, grow = 4, block = "cywp_block_paddy" },
}
CROP_LIST = {}
for _, c in pairs(CROPS) do table.insert(CROP_LIST, c) end
table.sort(CROP_LIST, function(a, b) return a.name < b.name end)
function plan4()
  return { years = 4, seeds = {
    { crop = "WHEAT", t = 9 }, { crop = "CANOLA", t = 19 }, { crop = "CARROT", t = 30 },
    { crop = "PEA", t = 38 }, { crop = "BARLEY", t = 44 } } }
end
function list(t) local out = {} for _, v in ipairs(t) do table.insert(out, v) end return out end
""")
L = lua.globals().CropYearWheelPlannerLogic
G = lua.globals()

failures = []


def check(name, got, want):
    if got != want:
        failures.append(f"{name}: got {got!r}, want {want!r}")
    else:
        print("ok  ", name)


def py(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else None


# Months and periods
check("period 1 is March", L.periodToMonth(1), 3)
check("period 11 is January", L.periodToMonth(11), 1)
check("period 12 is February", L.periodToMonth(12), 2)
check("March is period 1", L.monthToPeriod(3), 1)
check("calendar year in January is next game year", L.calendarYear(3, 11), 4)
check("calendar year in March is the game year", L.calendarYear(3, 1), 3)

# Gaps of the mockup plan: Dec-Feb before peas (y3-y4), Aug y4 between peas and barley,
# and Jun-Sep y1 between the barley harvest and the wheat (the one the mockup selects)
plan = G.plan4()
gaps = L.getGaps(plan, G.CROPS)
check("gaps", [(gaps[i].a, gaps[i].b) for i in range(1, len(gaps) + 1)], [(34, 38), (42, 44), (53, 57)])
check("find gap by its month in the cycle", (L.findGap(plan, G.CROPS, 5).a, L.findGap(plan, G.CROPS, 5).b), (53, 57))
check("free months", L.getFreeMonths(plan, G.CROPS), 7)
check("carrot sow choices in the wrapped gap", py(L.getSowChoices(G.CROPS.CARROT, 53, 57)), [53])

# The mockup adds Carrots in that gap: sow Jun or Jul? harvest must be <= Oct (9)
carrot = G.CROPS.CARROT
check("carrot sow choices in gap", py(L.getSowChoices(carrot, 5, 9)), [5])
check("wheat does not fit the gap", L.cropFits(G.CROPS.WHEAT, 5, 9), False)
check("blocked crop never fits", L.cropFits(G.CROPS.RICE, 0, 48), False)

# Adding carrots fills the year; no overlaps, no empty years
plan.seeds[6] = L.makeSeed(plan, carrot, 5)
check("no overlaps after adding carrots", len(L.getOverlaps(plan, G.CROPS)), 0)
check("Jun-Sep gap filled, two gaps left", len(L.getGaps(plan, G.CROPS)), 2)
check("no empty years", len(L.getEmptyYears(plan, G.CROPS)), 0)

# Year rows: year 1 has barley (from y4), carrots, wheat; lanes split shared months
rows = L.getRows(plan, G.CROPS)
y1 = [(b.seed.crop, b["from"], b.to, b.lane) for b in py(rows[1])]
check("year 1 bars", y1, [("BARLEY", 0, 5, 1), ("CARROT", 5, 9, 2), ("WHEAT", 9, 11, 1)])
check("crops in year 1", py(L.getCropsInYear(plan, G.CROPS, 1)), ["BARLEY", "CARROT", "WHEAT"])
check("crops in year 3", py(L.getCropsInYear(plan, G.CROPS, 3)), ["CANOLA", "CARROT"])

# Removing a year: year 4 has seeds, so no
check("cannot remove year 4", L.canRemoveYear(plan, G.CROPS), False)
empty = lua.eval("{ years = 3, seeds = { { crop = 'PEA', t = 2 } } }")
check("can remove empty last year", L.canRemoveYear(empty, G.CROPS), True)
wraps = lua.eval("{ years = 2, seeds = { { crop = 'WHEAT', t = 9 }, { crop = 'PEA', t = 2 } } }")
# Wheat Oct y1 -> Aug y2 (19); shrinking to 1 year makes it wrap into peas (Mar)
check("cannot remove year when wheat would overlap", L.canRemoveYear(wraps, G.CROPS), False)

# Empty plan: one gap over the whole cycle
blank = lua.eval("{ years = 2, seeds = {} }")
gaps = L.getGaps(blank, G.CROPS)
check("empty plan gap", (gaps[1].a, gaps[1].b), (0, 24))
check("empty plan year 1 and 2 empty", py(L.getEmptyYears(blank, G.CROPS)), [1, 2])

# Grass ley
check("ley choices from Apr y1 with next sowing Oct y2", py(L.getLeyChoices(3, 21)), [3, 6, 12])
check("growing months Apr..Jul", L.getGrowingMonths(3, 6), 3)
check("no growth Nov-Feb", L.getGrowingMonths(10, 13), 0)
check("cuts every 2 months over a year from Mar", L.getCutCount(2, 12, 2), 4)
check("cut months", py(L.getCutMonths(2, 6, 2)), [4, 6, 8])

# Follow-up crops after a harvest in July (month index 6)
check("follow-ups in July", py(L.getFollowUps(G.CROP_LIST, 6, "PEA")), ["CARROT", "GRASS"])

# Field groups: plan year moves on by itself
group = lua.eval("{ planYear = 2, anchorYear = 5 }")
check("plan year in anchor year", L.getPlanYear(group, 5, 4), 2)
check("plan year next year", L.getPlanYear(group, 6, 4), 3)
check("plan year wraps", L.getPlanYear(group, 8, 4), 1)
check("plan year before anchor", L.getPlanYear(group, 4, 4), 1)

# Status: group in plan year 1, June (month 6): harvest barley + sow carrots now
st = L.getGroupStatus(plan, G.CROPS, lua.eval("{ planYear = 1, anchorYear = 1 }"), 1, 6)
now = sorted((t.action, t.crop) for t in py(st.nowTasks))
check("June tasks", now, [("harvest", "BARLEY"), ("sow", "CARROT")])
check("next task", (st.nextTask.action, st.nextTask.crop, st.nextMonth, st.nextIsNextYear), ("harvest", "CARROT", 10, False))
st = L.getGroupStatus(plan, G.CROPS, lua.eval("{ planYear = 1, anchorYear = 1 }"), 1, 11)
check("November: next is harvest wheat next year", (st.nextTask.action, st.nextTask.crop, st.nextMonth, st.nextIsNextYear), ("harvest", "WHEAT", 8, True))

# Ley tasks: sow, cuts, last cut
ley = lua.eval("{ years = 1, seeds = { { crop = 'GRASS', t = 3, dur = 6, cut = 2 } } }")
tasks = sorted((t.action, t.t) for t in py(L.getTasks(ley, G.CROPS)))
check("ley tasks", tasks, [("cut", 5), ("cut", 7), ("cut", 9), ("sow", 3)])

if failures:
    print("\nFAILED:")
    for f in failures:
        print("  ", f)
    sys.exit(1)
print("\nall logic tests passed")
