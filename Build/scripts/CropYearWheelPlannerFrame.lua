-- CropYearWheelPlannerFrame.lua
-- Own tab in the in-game menu (Esc), placed directly above the base game Settings tab.
-- Three sub-tabs:
--   Settings:     display full / minimized / hidden, position top / left, the show/minimize key,
--                 grass in rotation; in multiplayer also who can edit (farm manager only /
--                 everyone on the farm) and whether this player can edit (base game option rows)
--   Plans:        list of plans and the plan editor (CropYearWheelPlannerPages, drawn in :draw)
--   Field groups: field groups and the farm's own fields (CropYearWheelPlannerPages, drawn in :draw)
--
-- The page is added to the in-game menu when the savegame loads and removed again
-- when it is closed.

CropYearWheelPlannerFrame = {}
CropYearWheelPlannerFrame.GUI_NAME = "CropYearWheelPlannerFrame"

CropYearWheelPlannerFrame.SUB_PAGE = {
    SETTINGS = 1,
    PLANS = 2,
    GROUPS = 3
}
CropYearWheelPlannerFrame.SUB_PAGE_TEXTS = { "cywp_subtab_settings", "cywp_subtab_plans", "cywp_subtab_groups" }

local CropYearWheelPlannerFrame_mt = Class(CropYearWheelPlannerFrame, TabbedMenuFrameElement)

local function t(key)
    return g_i18n:getText(key)
end

local function setText(element, text)
    if element ~= nil and element.setText ~= nil then
        element:setText(text)
    end
end

-- Shows a whole image file (size x size pixels) in a Bitmap. The UVs must be reset too:
-- profiles such as fs25_menuHeaderIcon point at a small slice of the game's icon atlas, and
-- with our file and those UVs the header icon rendered as a plain green block (v1.3.2).
local function setImage(element, filename, size)
    if element == nil or element.setImageFilename == nil then
        return
    end
    element:setImageFilename(filename)
    if element.setImageUVs ~= nil then
        element:setImageUVs(nil, unpack(GuiUtils.getUVs({ 0, 0, size, size }, { size, size })))
    end
end

-- Removes every occurrence of item from list; true if it was there
local function removeFromList(list, item)
    if type(list) ~= "table" then
        return false
    end
    local found = false
    for i = #list, 1, -1 do
        if list[i] == item then
            table.remove(list, i)
            found = true
        end
    end
    return found
end

-- Moves item so it comes directly before anchor in list (at the end if anchor is not in it).
-- getElement maps a list entry to the element it stands for (default: the entry itself).
local function moveBefore(list, item, anchor, getElement)
    if list == nil or anchor == nil then
        return
    end
    getElement = getElement or function(entry) return entry end

    local entry = nil
    for i = 1, #list do
        if getElement(list[i]) == item then
            entry = table.remove(list, i)
            break
        end
    end
    if entry == nil then
        return
    end

    for i = 1, #list do
        if getElement(list[i]) == anchor then
            table.insert(list, i, entry)
            return
        end
    end
    table.insert(list, entry)
end

function CropYearWheelPlannerFrame.new(target, customMt)
    local self = TabbedMenuFrameElement.new(target, customMt or CropYearWheelPlannerFrame_mt)
    self.currentSubPage = CropYearWheelPlannerFrame.SUB_PAGE.SETTINGS
    -- Plans / Field groups pages: mouse, clickable boxes, selection, plan editor copy
    self.pageState = { hits = {} }
    return self
end

---------------------------------------------------------------------------
-- Install / uninstall
---------------------------------------------------------------------------

-- The frame itself is added as a child of the menu's paging element (that is how the
-- page gets an id the menu can look up), then registered as page with a tab.
-- Same approach as Courseplay's CpGuiUtil.fixInGameMenuPage and AdvancedDamageSystem's
-- ADS_Main.addShopMenuPage, including moving the page in the paging element and in
-- pageFrames so the tab sits directly above the base game Settings tab.
-- (TabbedMenu:addPage registers the frame's root element as page instead, which makes
-- the menu fail to find the page: "PagingElement ... attempt to index nil with 'disabled'".)
function CropYearWheelPlannerFrame.install(modDirectory)
    local menu = g_inGameMenu
    if menu == nil or g_gui == nil or menu.pagingElement == nil then
        Logging.warning("[CropYearWheelPlanner] In-game menu not available, settings tab not added")
        return
    end

    -- Leftover from an earlier savegame in the same game run
    if g_gui.frames ~= nil and g_gui.frames[CropYearWheelPlannerFrame.GUI_NAME] ~= nil then
        g_gui.frames[CropYearWheelPlannerFrame.GUI_NAME] = nil
    end

    local frame = CropYearWheelPlannerFrame.new()
    g_gui:loadGui(modDirectory .. "gui/CropYearWheelPlannerFrame.xml", CropYearWheelPlannerFrame.GUI_NAME, frame, true)
    if frame.elements[1] == nil then
        Logging.warning("[CropYearWheelPlanner] Settings tab GUI could not be loaded")
        return
    end
    frame.elements[1].title = t("cywp_tab_title")
    frame.modDirectory = modDirectory

    -- The base game Settings page; the tab goes directly above it. nil = last, as before.
    local anchor = menu.pageSettings
    if anchor == nil then
        Logging.warning("[CropYearWheelPlanner] Settings page not found, tab added at the end")
    end

    menu.pageCropYearWheelPlanner = frame
    menu.pagingElement:addElement(frame)
    moveBefore(menu.pagingElement.elements, frame, anchor)
    moveBefore(menu.pagingElement.pages, frame, anchor, function(page) return page.element end)
    menu.pagingElement:updateAbsolutePosition()
    menu.pagingElement:updatePageMapping()

    menu:registerPage(frame, nil, nil)
    local uvs = GuiUtils.getUVs({ 0, 0, 256, 256 }, { 256, 256 })
    menu:addPageTab(frame, modDirectory .. "icon_minimized.dds", uvs)
    moveBefore(menu.pageFrames, frame, anchor)
    if menu.rebuildTabList ~= nil then
        menu:rebuildTabList()
    end
    frame:updateAbsolutePosition()

    frame:initializeSubPages()

    CropYearWheelPlannerFrame.instance = frame
end

function CropYearWheelPlannerFrame.uninstall()
    local frame = CropYearWheelPlannerFrame.instance
    if frame == nil then
        return
    end
    CropYearWheelPlannerFrame.instance = nil

    -- Quitting a savegame logged TabbedMenu.lua:285 "attempt to index nil with 'iconFilename'"
    -- (GitHub issue #2): the menu's tab list still had our page after its tab was gone.
    -- TabbedMenu:unregisterPage finds the page through pageTypeControllers[class] and only
    -- removes it when that lookup works, so every list the page was added to is cleaned here
    -- directly, and the info line in the log tells which case happened.
    local menu = g_inGameMenu
    if menu ~= nil then
        local byClass = false
        if menu.unregisterPage ~= nil then
            local class = CropYearWheelPlannerFrame
            if frame.class ~= nil then
                class = frame:class()
            end
            byClass = menu:unregisterPage(class) == true
        end
        local leftover = removeFromList(menu.pageFrames, frame)
        removeFromList(menu.enabledPages, frame)
        for _, map in ipairs({ menu.pageTabs, menu.pageRoots, menu.pageEnablingPredicates }) do
            if type(map) == "table" then
                map[frame] = nil
            end
        end
        if type(menu.pageTypeControllers) == "table" then
            for key, controller in pairs(menu.pageTypeControllers) do
                if controller == frame then
                    menu.pageTypeControllers[key] = nil
                end
            end
        end
        if menu.currentPage == frame then
            menu.currentPage = nil
        end

        if menu.pagingElement ~= nil then
            menu.pagingElement:removeElement(frame)
            menu.pagingElement:updatePageMapping()
        end
        if menu.rebuildTabList ~= nil then
            menu:rebuildTabList()
        end
        -- The menu reopens on the page it was closed on; that index may now be past the end
        if type(menu.restorePageIndex) == "number" and type(menu.enabledPages) == "table" and menu.restorePageIndex > #menu.enabledPages then
            menu.restorePageIndex = 1
            menu.restorePageScrollOffset = 0
        end
        menu.pageCropYearWheelPlanner = nil
        Logging.info("[CropYearWheelPlanner] Menu tab removed (unregistered by class: %s, left in page list: %s, menu open: %s)",
            tostring(byClass), tostring(leftover), tostring(g_gui ~= nil and g_gui:getIsGuiVisible()))
    end
    frame:delete()
    if g_gui ~= nil and g_gui.frames ~= nil then
        g_gui.frames[CropYearWheelPlannerFrame.GUI_NAME] = nil
    end
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------

-- Sub-tab bar: texts on the tab buttons, and one entry per sub-tab in the paging option
-- (that is what the gamepad shoulder buttons step through). As Courseplay's CpGlobalSettingsFrame.
function CropYearWheelPlannerFrame:initializeSubPages()
    self.subPages = { self.subPageSettings, self.subPagePlans, self.subPageGroups }
    self.subTabs = { self.tabSettings, self.tabPlans, self.tabGroups }

    for i, key in ipairs(CropYearWheelPlannerFrame.SUB_PAGE_TEXTS) do
        local tab = self.subTabs[i]
        setText(tab, t(key))
        -- The button grows with its text, its green background does not (v1.3.2 covered
        -- only part of "SETTINGS"). Same fix as Courseplay's CpGlobalSettingsFrame.
        if tab ~= nil then
            local background = tab:getDescendantByName("background")
            if background ~= nil then
                background:setSize(tab.size[1], tab.size[2])
            end
        end
        if self.subCategoryPaging ~= nil then
            self.subCategoryPaging:addText(tostring(i))
        end
    end

    if self.subCategoryBox ~= nil then
        self.subCategoryBox:invalidateLayout()
        if self.subCategoryPaging ~= nil and self.subCategoryBox.maxFlowSize ~= nil then
            self.subCategoryPaging:setSize(self.subCategoryBox.maxFlowSize + 140 * g_pixelSizeScaledX)
        end
    end
end

function CropYearWheelPlannerFrame:onFrameOpen()
    CropYearWheelPlannerFrame:superClass().onFrameOpen(self)

    self:updateTexts()
    self:updateValues()

    if self.settingsLayout ~= nil then
        self.settingsLayout:invalidateLayout()
    end
    self:updateRowColors()
    CropYearWheelPlannerPages.refreshOwnedFields(self.pageState)
    self:updateSubCategoryPages(self.currentSubPage)
end

-- Called by the paging option (gamepad shoulder buttons) and by the tab buttons.
function CropYearWheelPlannerFrame:updateSubCategoryPages(state)
    if self.subPages == nil or self.subPages[state] == nil then
        return
    end
    self.currentSubPage = state

    for i, page in ipairs(self.subPages) do
        if page ~= nil then
            page:setVisible(i == state)
        end
        if self.subTabs[i] ~= nil then
            self.subTabs[i]:setSelected(i == state)
        end
    end
    if self.subCategoryPaging ~= nil then
        self.subCategoryPaging:setState(state, false)
    end

    if FocusManager ~= nil and state == CropYearWheelPlannerFrame.SUB_PAGE.SETTINGS and self.displayOption ~= nil then
        FocusManager:setFocus(self.displayOption)
    end
end

function CropYearWheelPlannerFrame:onClickTabSettings()
    self:updateSubCategoryPages(CropYearWheelPlannerFrame.SUB_PAGE.SETTINGS)
end

function CropYearWheelPlannerFrame:onClickTabPlans()
    self:updateSubCategoryPages(CropYearWheelPlannerFrame.SUB_PAGE.PLANS)
end

function CropYearWheelPlannerFrame:onClickTabGroups()
    self:updateSubCategoryPages(CropYearWheelPlannerFrame.SUB_PAGE.GROUPS)
end

-- The row profile (fs25_multiTextOptionContainer) is white; the base game settings page
-- colours the rows in Lua with alternating dark colours, starting again after each section
-- header. Without this the rows render white and the white text cannot be read (v1.3.1).
-- Same as FS25_AutoDrive's ADSettingsPage and FS25_AdvancedDamageSystem's settings page.
function CropYearWheelPlannerFrame:updateRowColors()
    if self.settingsLayout == nil or InGameMenuSettingsFrame == nil or InGameMenuSettingsFrame.COLOR_ALTERNATING == nil then
        return
    end

    local isEven = false
    for _, element in ipairs(self.settingsLayout.elements) do
        if element.getIsVisible ~= nil and not element:getIsVisible() then
            -- hidden rows (multiplayer rows in single player) do not count
        elseif element.name == "sectionHeader" then
            isEven = false
        elseif element.setImageColor ~= nil then
            element:setImageColor(nil, unpack(InGameMenuSettingsFrame.COLOR_ALTERNATING[isEven]))
            isEven = not isEven
        end
    end
end

function CropYearWheelPlannerFrame:updateTexts()
    setText(self.headerTitle, t("cywp_tab_title"))
    if self.modDirectory ~= nil then
        setImage(self.headerIcon, self.modDirectory .. "icon_minimized.dds", 256)
    end

    setText(self.sectionDisplay, t("cywp_section_display"))
    setText(self.sectionCrops, t("cywp_section_crops"))
    setText(self.sectionMultiplayer, t("cywp_section_multiplayer"))

    setText(self.displayTitle, t("cywp_settings_display"))
    setText(self.displayTooltip, t("cywp_settings_display_tooltip"))
    setText(self.positionTitle, t("cywp_settings_position"))
    setText(self.positionTooltip, t("cywp_settings_position_tooltip"))
    setText(self.keyTitle, t("cywp_settings_key"))
    setText(self.keyTooltip, t("cywp_settings_key_tooltip"))
    setText(self.grassTitle, t("cywp_settings_grass"))
    setText(self.grassTooltip, t("cywp_settings_grass_tooltip"))
    setText(self.editTitle, t("cywp_settings_edit"))
    setText(self.editTooltip, t("cywp_settings_edit_tooltip"))
    setText(self.editStatusTitle, t("cywp_settings_editStatus"))
    setText(self.editStatusTooltip, t("cywp_settings_editStatus_tooltip"))
end

-- An option row that only shows a text (the key, who can edit)
local function setInfo(option, text)
    if option ~= nil then
        option:setTexts({ text })
        option:setState(1, false)
    end
end

function CropYearWheelPlannerFrame:updateValues()
    if self.displayOption ~= nil then
        local texts = {}
        for _, mode in ipairs(CropYearWheelPlanner.DISPLAY_MODES) do
            table.insert(texts, t("cywp_display_" .. mode))
        end
        self.displayOption:setTexts(texts)
        self.displayOption:setState(CropYearWheelPlanner:getDisplayModeIndex(), false)
    end

    if self.positionOption ~= nil then
        local texts = {}
        for _, pos in ipairs(CropYearWheelPlanner.POSITIONS) do
            table.insert(texts, t("cywp_position_" .. pos))
        end
        self.positionOption:setTexts(texts)
        self.positionOption:setState(CropYearWheelPlanner:getPositionIndex(), false)
    end

    local canEdit = CropYearWheelPlanner:canEdit()
    if self.grassOption ~= nil then
        self.grassOption:setTexts({ t("cywp_on"), t("cywp_off") })
        self.grassOption:setState(CropYearWheelPlanner:getGrassInRotation() and 1 or 2, false)
        self.grassOption:setDisabled(not canEdit)
    end

    setInfo(self.keyOption, t("cywp_settings_key_value"))

    -- Multiplayer section: only in multiplayer
    local multiplayer = CropYearWheelPlanner:isMultiplayer()
    for _, element in ipairs({ self.sectionMultiplayer, self.editRow, self.editStatusRow }) do
        if element ~= nil then
            element:setVisible(multiplayer)
        end
    end
    if self.editOption ~= nil then
        self.editOption:setTexts({ t("cywp_settings_edit_manager"), t("cywp_settings_edit_everyone") })
        self.editOption:setState(CropYearWheelPlanner:getEveryoneCanEdit() and 2 or 1, false)
        -- Only the farm manager can change who can edit
        self.editOption:setDisabled(not CropYearWheelPlanner:canChangePermission())
    end
    setInfo(self.editStatusOption, t(canEdit and "cywp_status_canEdit" or "cywp_status_managerOnly"))
end

function CropYearWheelPlannerFrame:onClickEditPermission(state)
    if CropYearWheelPlanner:canChangePermission() then
        CropYearWheelPlanner:setEveryoneCanEdit(state == 2)
    end
end

function CropYearWheelPlannerFrame:onClickDisplay(state)
    local mode = CropYearWheelPlanner.DISPLAY_MODES[state]
    if mode ~= nil then
        CropYearWheelPlanner:setDisplayMode(mode)
    end
end

function CropYearWheelPlannerFrame:onClickPosition(state)
    local position = CropYearWheelPlanner.POSITIONS[state]
    if position ~= nil then
        CropYearWheelPlanner:setPosition(position)
    end
end

function CropYearWheelPlannerFrame:onClickGrass(state)
    CropYearWheelPlanner:setGrassInRotation(state == 1)
end

---------------------------------------------------------------------------
-- Plans and Field groups: drawn here, clicks matched against the drawn boxes
---------------------------------------------------------------------------

function CropYearWheelPlannerFrame:getCustomPageArea()
    local container = self.subPages ~= nil and self.subPages[self.currentSubPage] or nil
    if container == nil or container.absPosition == nil or container.absSize == nil then
        return nil
    end
    if container.absSize[1] <= 0 or container.absSize[2] <= 0 then
        return nil
    end
    return { x = container.absPosition[1], y = container.absPosition[2], w = container.absSize[1], h = container.absSize[2] }
end

function CropYearWheelPlannerFrame:draw(...)
    CropYearWheelPlannerFrame:superClass().draw(self, ...)

    local page = self.currentSubPage
    if page ~= CropYearWheelPlannerFrame.SUB_PAGE.PLANS and page ~= CropYearWheelPlannerFrame.SUB_PAGE.GROUPS then
        return
    end
    local area = self:getCustomPageArea()
    if area == nil then
        return
    end

    local state = self.pageState
    CropYearWheelPlannerUI.begin(state)
    state.scrollRegion = nil
    state.panelRegion = nil
    local drawPage = page == CropYearWheelPlannerFrame.SUB_PAGE.PLANS and CropYearWheelPlannerPages.drawPlans or CropYearWheelPlannerPages.drawGroups
    drawPage(state, area)
    CropYearWheelPlannerUI.drawTooltip(state)
    CropYearWheelPlannerUI.finish()
end

local function isInside(region, x, y)
    return region ~= nil and x >= region.x and x <= region.x + region.w and y >= region.y and y <= region.y + region.h
end

function CropYearWheelPlannerFrame:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    local state = self.pageState
    state.mouseX, state.mouseY = posX, posY

    local page = self.currentSubPage
    local custom = page == CropYearWheelPlannerFrame.SUB_PAGE.PLANS or page == CropYearWheelPlannerFrame.SUB_PAGE.GROUPS
    if custom and not eventUsed and isDown and self:getIsVisible() then
        if button == Input.MOUSE_BUTTON_LEFT then
            if CropYearWheelPlannerUI.click(state, posX, posY) then
                return true
            end
        elseif button == Input.MOUSE_BUTTON_WHEEL_UP or button == Input.MOUSE_BUTTON_WHEEL_DOWN then
            local dir = button == Input.MOUSE_BUTTON_WHEEL_UP and -1 or 1
            local ed = state.editor
            if page == CropYearWheelPlannerFrame.SUB_PAGE.PLANS and ed ~= nil and isInside(state.panelRegion, posX, posY) then
                ed.panelScroll = math.max(0, math.min(CropYearWheelPlannerUI.py(1500), (ed.panelScroll or 0) + dir * CropYearWheelPlannerUI.py(48)))
                return true
            elseif page == CropYearWheelPlannerFrame.SUB_PAGE.GROUPS and isInside(state.scrollRegion, posX, posY) then
                state.groupScroll = math.max(0, math.min(state.scrollRegion.max, (state.groupScroll or 0) + dir))
                return true
            end
        end
    end

    return CropYearWheelPlannerFrame:superClass().mouseEvent(self, posX, posY, isDown, isUp, button, eventUsed)
end