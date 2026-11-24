local ADDON_NAME = ...
local DB
local noteFrames = {}
local manager
local minimapButton
local selectedNoteID
local initialized = false
local initializationStage = "not started"
local BACKDROP_TEMPLATE = _G.BackdropTemplateMixin and "BackdropTemplate" or nil

local DEFAULT_NOTE_WIDTH = 300
local DEFAULT_NOTE_HEIGHT = 240
local MIN_NOTE_WIDTH = 220
local MIN_NOTE_HEIGHT = 160
local MAX_NOTE_WIDTH = 800
local MAX_NOTE_HEIGHT = 700
local DEFAULT_NOTE_FONT_SIZE = 14
local NOTE_FONT_SIZES = {10, 12, 14, 16, 18, 20, 24}
local FONT_OPTIONS = {
    {name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF"},
    {name = "Arial Narrow", path = "Fonts\\ARIALN.TTF"},
    {name = "2002", path = "Fonts\\2002.TTF"},
    {name = "Morpheus", path = "Fonts\\MORPHEUS.TTF"},
    {name = "Skurri", path = "Fonts\\SKURRI.TTF"},
}

local function GetFontOption(path)
    for _, option in ipairs(FONT_OPTIONS) do
        if option.path == path then
            return option
        end
    end
    return FONT_OPTIONS[1]
end

local function ApplyNoteFont(id)
    local frame = noteFrames[id]
    if frame and frame.editBox then
        local font = GetFontOption(DB.defaultFontPath)
        local editBox = frame.editBox
        editBox:SetFont(font.path, DB.notes[id].fontSize or DEFAULT_NOTE_FONT_SIZE, "")
        if frame.UpdateEditorSize then
            frame.UpdateEditorSize()
        end
    end
end

local function UpdateFontOptionButtons()
    if not manager or not manager.fontOptionButtons then
        return
    end
    local selected = GetFontOption(DB.defaultFontPath)
    for _, entry in ipairs(manager.fontOptionButtons) do
        entry.button:SetText((entry.option == selected and "* " or "") .. entry.option.name)
        local label = entry.button:GetFontString()
        if label then
            label:SetFont(entry.option.path, 14, "")
        end
    end
end

local function CreateBackdrop(frame, background, border)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(background[1], background[2], background[3], background[4] or 1)
    frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function SortedNoteIDs()
    local ids = {}
    for id in pairs(DB.notes) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    return ids
end

local function UpdateManagerList()
    if not manager or not manager.rows then
        return
    end

    local ids = SortedNoteIDs()
    for index, id in ipairs(ids) do
        local row = manager.rows[index]
        if not row then
            row = CreateFrame("Button", nil, manager.listContent)
            row:SetHeight(26)
            row:SetPoint("TOPLEFT", manager.listContent, "TOPLEFT", 0, -((index - 1) * 28))
            row:SetPoint("TOPRIGHT", manager.listContent, "TOPRIGHT", -4, -((index - 1) * 28))
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.text:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row:SetScript("OnClick", function(self)
                selectedNoteID = self.noteID
                local noteFrame = noteFrames[self.noteID]
                if noteFrame then
                    DB.notes[self.noteID].visible = true
                    noteFrame:Show()
                end
                UpdateManagerList()
            end)
            manager.rows[index] = row
        end

        row.noteID = id
        row.text:SetText("Note " .. id .. (DB.notes[id].visible == false and " (hidden)" or ""))
        row:Show()
        row.text:SetTextColor(selectedNoteID == id and 1 or 0.9, selectedNoteID == id and 0.82 or 0.82, selectedNoteID == id and 0.2 or 0.65)
    end

    for index = #ids + 1, #manager.rows do
        manager.rows[index]:Hide()
    end
    manager.listContent:SetHeight(math.max(1, #ids * 28))
    manager.deleteButton:SetEnabled(selectedNoteID ~= nil and DB.notes[selectedNoteID] ~= nil)
end

local function SaveNotePosition(id, frame)
    local centerX, centerY = frame:GetCenter()
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    if centerX and centerY and screenWidth > 0 and screenHeight > 0 then
        DB.notes[id].x = centerX / screenWidth
        DB.notes[id].y = centerY / screenHeight
    end
end

local function CreateNoteFrame(id)
    local data = DB.notes[id]
    local frame = CreateFrame("Frame", nil, UIParent, BACKDROP_TEMPLATE)
    frame:SetSize(
        math.max(MIN_NOTE_WIDTH, math.min(MAX_NOTE_WIDTH, data.width or DEFAULT_NOTE_WIDTH)),
        math.max(MIN_NOTE_HEIGHT, math.min(MAX_NOTE_HEIGHT, data.height or DEFAULT_NOTE_HEIGHT))
    )
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_NOTE_WIDTH, MIN_NOTE_HEIGHT, MAX_NOTE_WIDTH, MAX_NOTE_HEIGHT)
    else
        if frame.SetMinResize then
            frame:SetMinResize(MIN_NOTE_WIDTH, MIN_NOTE_HEIGHT)
        end
        if frame.SetMaxResize then
            frame:SetMaxResize(MAX_NOTE_WIDTH, MAX_NOTE_HEIGHT)
        end
    end
    CreateBackdrop(frame, {0.91, 0.83, 0.55, 0.98}, {0.35, 0.27, 0.12, 1})

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    titleBar:SetHeight(25)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        if not data.pinned then
            frame:StartMoving()
        end
    end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if not data.pinned then
            SaveNotePosition(id, frame)
        end
    end)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", titleBar, "LEFT", 5, 0)
    title:SetText("Sticky Note " .. id)

    local closeButton = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeButton:SetSize(22, 22)
    closeButton:SetPoint("RIGHT", titleBar, "RIGHT", 3, 0)
    closeButton:SetScript("OnClick", function()
        data.visible = false
        frame:Hide()
        UpdateManagerList()
    end)

    local pinButton = CreateFrame("Button", nil, titleBar, "UIPanelButtonTemplate")
    pinButton:SetSize(52, 20)
    pinButton:SetPoint("RIGHT", closeButton, "LEFT", -2, 0)
    pinButton:SetText(data.pinned and "Pinned" or "Pin")
    pinButton:SetScript("OnClick", function(self)
        data.pinned = not data.pinned
        self:SetText(data.pinned and "Pinned" or "Pin")
    end)

    local fontSizeButton = CreateFrame("Button", nil, titleBar, "UIPanelButtonTemplate")
    fontSizeButton:SetSize(52, 20)
    fontSizeButton:SetPoint("RIGHT", pinButton, "LEFT", -2, 0)
    fontSizeButton:SetText((data.fontSize or DEFAULT_NOTE_FONT_SIZE) .. " pt")
    fontSizeButton:SetScript("OnClick", function(self)
        local currentSize = data.fontSize or DEFAULT_NOTE_FONT_SIZE
        local nextIndex = 1
        for index, size in ipairs(NOTE_FONT_SIZES) do
            if size == currentSize then
                nextIndex = index % #NOTE_FONT_SIZES + 1
                break
            end
        end
        data.fontSize = NOTE_FONT_SIZES[nextIndex]
        self:SetText(data.fontSize .. " pt")
        ApplyNoteFont(id)
    end)
    fontSizeButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Change this note's font size")
        GameTooltip:AddLine("Click to cycle through sizes", 1, 1, 1)
        GameTooltip:Show()
    end)
    fontSizeButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    title:SetPoint("RIGHT", fontSizeButton, "LEFT", -4, 0)

    local scroll = CreateFrame("ScrollFrame", nil, frame, BACKDROP_TEMPLATE)
    scroll:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -7)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 12)
    CreateBackdrop(scroll, {0.04, 0.04, 0.04, 0.92}, {0.52, 0.4, 0.22, 1})

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    local font = GetFontOption(DB.defaultFontPath)
    data.fontSize = data.fontSize or DEFAULT_NOTE_FONT_SIZE
    editBox:SetFont(font.path, data.fontSize, "")
    editBox:SetTextColor(1, 1, 1)
    editBox:SetTextInsets(5, 5, 5, 5)
    editBox:SetMaxLetters(4000)
    editBox:EnableMouse(true)
    editBox:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self:SetFocus()
        end
    end)
    scroll:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            editBox:SetFocus()
            editBox:SetCursorPosition(editBox:GetText():len())
        end
    end)
    local function UpdateEditorSize()
        editBox:SetWidth(math.max(80, scroll:GetWidth() - 12))
        editBox:SetHeight(math.max(scroll:GetHeight() - 10, editBox:GetStringHeight() + 12))
    end
    scroll:SetScript("OnSizeChanged", UpdateEditorSize)
    frame:SetScript("OnSizeChanged", function(_, width, height)
        data.width = width
        data.height = height
        UpdateEditorSize()
    end)
    editBox:EnableMouseWheel(true)
    editBox:SetScript("OnMouseWheel", function(_, delta)
        local maxScroll = math.max(0, editBox:GetHeight() - scroll:GetHeight())
        scroll:SetVerticalScroll(math.max(0, math.min(maxScroll, scroll:GetVerticalScroll() - delta * 24)))
    end)
    editBox:SetScript("OnTextChanged", function(self)
        data.text = self:GetText()
        UpdateEditorSize()
        local maxScroll = math.max(0, self:GetHeight() - scroll:GetHeight())
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), maxScroll))
    end)
    scroll:SetScrollChild(editBox)
    frame.editBox = editBox
    frame.UpdateEditorSize = UpdateEditorSize

    local resizeHandle = CreateFrame("Button", nil, frame)
    resizeHandle:SetSize(18, 18)
    resizeHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeHandle:RegisterForDrag("LeftButton")
    resizeHandle:SetScript("OnDragStart", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeHandle:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        data.width = frame:GetWidth()
        data.height = frame:GetHeight()
        SaveNotePosition(id, frame)
        UpdateEditorSize()
    end)
    resizeHandle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("Drag to resize this note")
        GameTooltip:Show()
    end)
    resizeHandle:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    frame:SetScript("OnShow", function()
        editBox:SetText(data.text or "")
        UpdateEditorSize()
        scroll:SetVerticalScroll(0)
    end)
    frame:SetScript("OnHide", function()
        data.text = editBox:GetText()
    end)
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local x = (data.x or 0.5) * screenWidth
    local y = (data.y or 0.5) * screenHeight
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)

    noteFrames[id] = frame
    if data.visible == false then
        frame:Hide()
    else
        frame:Show()
    end
end

local function CreateManager()
    manager = CreateFrame("Frame", "ForeverStickyNotesManager", UIParent, BACKDROP_TEMPLATE)
    manager:SetSize(340, 400)
    manager:SetPoint("CENTER")
    manager:SetFrameStrata("DIALOG")
    manager:SetMovable(true)
    manager:EnableMouse(true)
    manager:RegisterForDrag("LeftButton")
    manager:SetScript("OnDragStart", manager.StartMoving)
    manager:SetScript("OnDragStop", manager.StopMovingOrSizing)
    CreateBackdrop(manager, {0.08, 0.08, 0.08, 0.96}, {0.55, 0.42, 0.2, 1})

    local heading = manager:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", manager, "TOPLEFT", 16, -16)
    heading:SetText("Forever Sticky Notes")

    local close = CreateFrame("Button", nil, manager, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", manager, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function()
        manager:Hide()
    end)

    local settingsButton = CreateFrame("Button", nil, manager, "UIPanelButtonTemplate")
    settingsButton:SetSize(64, 22)
    settingsButton:SetPoint("TOPRIGHT", manager, "TOPRIGHT", -38, -16)
    settingsButton:SetText("Settings")

    local createButton = CreateFrame("Button", nil, manager, "UIPanelButtonTemplate")
    createButton:SetSize(92, 24)
    createButton:SetPoint("TOPLEFT", manager, "TOPLEFT", 16, -48)
    createButton:SetText("New note")
    createButton:SetScript("OnClick", function()
        local id = DB.nextID
        DB.nextID = id + 1
        local offset = (#SortedNoteIDs() % 6)
        DB.notes[id] = {
            text = "",
            visible = true,
            x = 0.44 + offset * 0.025,
            y = 0.56 - offset * 0.03,
            fontSize = DEFAULT_NOTE_FONT_SIZE,
            width = DEFAULT_NOTE_WIDTH,
            height = DEFAULT_NOTE_HEIGHT,
        }
        selectedNoteID = id
        CreateNoteFrame(id)
        UpdateManagerList()
    end)

    local showAllButton = CreateFrame("Button", nil, manager, "UIPanelButtonTemplate")
    showAllButton:SetSize(92, 24)
    showAllButton:SetPoint("LEFT", createButton, "RIGHT", 8, 0)
    showAllButton:SetText("Show all")
    showAllButton:SetScript("OnClick", function()
        for id, data in pairs(DB.notes) do
            data.visible = true
            if noteFrames[id] then
                noteFrames[id]:Show()
            end
        end
        UpdateManagerList()
    end)

    local hideAllButton = CreateFrame("Button", nil, manager, "UIPanelButtonTemplate")
    hideAllButton:SetSize(92, 24)
    hideAllButton:SetPoint("LEFT", showAllButton, "RIGHT", 8, 0)
    hideAllButton:SetText("Hide all")
    hideAllButton:SetScript("OnClick", function()
        for id, data in pairs(DB.notes) do
            data.visible = false
            if noteFrames[id] then
                noteFrames[id]:Hide()
            end
        end
        UpdateManagerList()
    end)

    local listLabel = manager:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listLabel:SetPoint("TOPLEFT", manager, "TOPLEFT", 18, -86)
    listLabel:SetText("Your notes (select a note to open it)")

    local listScroll = CreateFrame("ScrollFrame", nil, manager)
    listScroll:SetPoint("TOPLEFT", manager, "TOPLEFT", 16, -108)
    listScroll:SetPoint("BOTTOMRIGHT", manager, "BOTTOMRIGHT", -30, 60)
    listScroll:EnableMouseWheel(true)
    listScroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, manager.listContent:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, self:GetVerticalScroll() - delta * 28)))
    end)
    local listContent = CreateFrame("Frame", nil, listScroll)
    listContent:SetWidth(280)
    listContent:SetHeight(1)
    listScroll:SetScrollChild(listContent)
    manager.listContent = listContent
    manager.rows = {}

    manager.deleteButton = CreateFrame("Button", nil, manager, "UIPanelButtonTemplate")
    manager.deleteButton:SetSize(100, 24)
    manager.deleteButton:SetPoint("BOTTOMLEFT", manager, "BOTTOMLEFT", 16, 16)
    manager.deleteButton:SetText("Delete note")
    manager.deleteButton:SetScript("OnClick", function()
        if selectedNoteID and DB.notes[selectedNoteID] then
            if noteFrames[selectedNoteID] then
                noteFrames[selectedNoteID]:Hide()
                noteFrames[selectedNoteID] = nil
            end
            DB.notes[selectedNoteID] = nil
            selectedNoteID = nil
            UpdateManagerList()
        end
    end)

    local settingsPanel = CreateFrame("Frame", nil, manager, BACKDROP_TEMPLATE)
    settingsPanel:SetPoint("TOPLEFT", manager, "TOPLEFT", 8, -44)
    settingsPanel:SetPoint("BOTTOMRIGHT", manager, "BOTTOMRIGHT", -8, 8)
    settingsPanel:SetFrameLevel(manager:GetFrameLevel() + 2)
    CreateBackdrop(settingsPanel, {0.06, 0.06, 0.06, 1}, {0.55, 0.42, 0.2, 1})
    settingsPanel:Hide()

    local settingsHeading = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    settingsHeading:SetPoint("TOPLEFT", settingsPanel, "TOPLEFT", 12, -14)
    settingsHeading:SetText("Settings")

    local fontLabel = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", settingsHeading, "BOTTOMLEFT", 0, -14)
    fontLabel:SetText("Default font for all notes")

    manager.fontOptionButtons = {}
    for index, option in ipairs(FONT_OPTIONS) do
        local button = CreateFrame("Button", nil, settingsPanel, "UIPanelButtonTemplate")
        button:SetSize(260, 28)
        button:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", 0, -8 - ((index - 1) * 34))
        button:SetNormalFontObject("GameFontNormal")
        button:SetScript("OnClick", function()
            DB.defaultFontPath = option.path
            for id in pairs(DB.notes) do
                ApplyNoteFont(id)
            end
            UpdateFontOptionButtons()
        end)
        manager.fontOptionButtons[index] = {button = button, option = option}
    end
    UpdateFontOptionButtons()

    local fontNote = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fontNote:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", 0, -188)
    fontNote:SetWidth(270)
    fontNote:SetJustifyH("LEFT")
    fontNote:SetText("The selected font is used by every note. Each note keeps its own font size.")

    local minimapCheck = CreateFrame("CheckButton", "ForeverStickyNotesMinimapCheck", settingsPanel, "UICheckButtonTemplate")
    minimapCheck:SetPoint("BOTTOMLEFT", settingsPanel, "BOTTOMLEFT", 6, 8)
    _G[minimapCheck:GetName() .. "Text"]:SetText("Minimap icon")
    minimapCheck:SetScript("OnClick", function(self)
        DB.showMinimapIcon = self:GetChecked() and true or false
        if minimapButton then
            if DB.showMinimapIcon then
                minimapButton:Show()
            else
                minimapButton:Hide()
            end
        end
    end)
    manager.minimapCheck = minimapCheck
    settingsButton:SetScript("OnClick", function(self)
        if settingsPanel:IsShown() then
            settingsPanel:Hide()
            self:SetText("Settings")
        else
            settingsPanel:Show()
            UpdateFontOptionButtons()
            self:SetText("Back")
        end
    end)
    manager:SetScript("OnShow", function()
        minimapCheck:SetChecked(DB.showMinimapIcon ~= false)
        UpdateManagerList()
    end)

    UpdateManagerList()
    manager:Hide()
end

local function PositionMinimapButton()
    local angle = math.rad(DB.minimapAngle or 220)
    local radius = (Minimap:GetWidth() / 2) + (minimapButton.icon:GetWidth() / 2) + 2
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function CreateMinimapButton()
    minimapButton = CreateFrame("Button", "ForeverStickyNotesMinimapButton", UIParent)
    minimapButton:SetSize(32, 32)
    minimapButton:SetFrameStrata(Minimap:GetFrameStrata())
    minimapButton:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetMovable(true)

    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    minimapButton.icon = icon

    local border = minimapButton:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")

    minimapButton:SetScript("OnClick", function()
        if not manager then
            print("|cffff4444Forever Sticky Notes: manager did not finish loading. Type /notes for the error.|r")
            return
        end
        if manager:IsShown() then
            manager:Hide()
        else
            manager:Show()
        end
    end)
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Forever Sticky Notes")
        GameTooltip:AddLine("Click to manage your notes", 1, 1, 1)
        GameTooltip:Show()
    end)
    minimapButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    minimapButton:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    minimapButton:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local centerX, centerY = Minimap:GetCenter()
        local cursorX, cursorY = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        DB.minimapAngle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
        PositionMinimapButton()
    end)

    PositionMinimapButton()
    if DB.showMinimapIcon == false then
        minimapButton:Hide()
    end
end

local function InitializeDatabase()
    if type(ForeverStickyNotesDB) ~= "table" then
        ForeverStickyNotesDB = {}
    end
    DB = ForeverStickyNotesDB
    if type(DB.notes) ~= "table" then
        DB.notes = {}
    end
    if type(DB.nextID) ~= "number" or DB.nextID < 1 then
        DB.nextID = 1
    end
    if type(DB.showMinimapIcon) ~= "boolean" then
        DB.showMinimapIcon = true
    end
    if type(DB.minimapAngle) ~= "number" or DB.minimapAngle ~= DB.minimapAngle then
        DB.minimapAngle = 220
    end
    DB.defaultFontPath = GetFontOption(DB.defaultFontPath).path

    local highestID = 0
    for id, data in pairs(DB.notes) do
        if type(id) == "number" and type(data) == "table" then
            data.text = type(data.text) == "string" and data.text or ""
            if type(data.visible) ~= "boolean" then
                data.visible = true
            end
            if type(data.pinned) ~= "boolean" then
                data.pinned = false
            end
            local validFontSize = false
            for _, size in ipairs(NOTE_FONT_SIZES) do
                if data.fontSize == size then
                    validFontSize = true
                    break
                end
            end
            if not validFontSize then
                data.fontSize = DEFAULT_NOTE_FONT_SIZE
            end
            if type(data.width) ~= "number" or data.width ~= data.width then
                data.width = DEFAULT_NOTE_WIDTH
            end
            if type(data.height) ~= "number" or data.height ~= data.height then
                data.height = DEFAULT_NOTE_HEIGHT
            end
            data.width = math.max(MIN_NOTE_WIDTH, math.min(MAX_NOTE_WIDTH, data.width))
            data.height = math.max(MIN_NOTE_HEIGHT, math.min(MAX_NOTE_HEIGHT, data.height))
            if type(data.x) ~= "number" or data.x ~= data.x or data.x < 0 or data.x > 1 then
                data.x = 0.5
            end
            if type(data.y) ~= "number" or data.y ~= data.y or data.y < 0 or data.y > 1 then
                data.y = 0.5
            end
            highestID = math.max(highestID, id)
        else
            DB.notes[id] = nil
        end
    end
    DB.nextID = math.max(DB.nextID, highestID + 1)
end

local function Initialize()
    if initialized then
        return
    end
    initializationStage = "database"
    InitializeDatabase()
    if not minimapButton then
        initializationStage = "minimap button"
        CreateMinimapButton()
    end
    if not manager then
        initializationStage = "manager window"
        CreateManager()
    end
    initializationStage = "note windows"
    for _, id in ipairs(SortedNoteIDs()) do
        if not noteFrames[id] then
            CreateNoteFrame(id)
        end
    end
    initialized = true
    initializationStage = "complete"
end

local function InitializeWithDiagnostics()
    local success, errorMessage = pcall(Initialize)
    if not success then
        local message = "Forever Sticky Notes failed during " .. initializationStage .. ": " .. tostring(errorMessage)
        print("|cffff4444" .. message .. "|r")
        error(message, 0)
    end
end

SLASH_FOREVERSTICKYNOTES1 = "/notes"
SLASH_FOREVERSTICKYNOTES2 = "/stickynotes"
SLASH_FOREVERSTICKYNOTES3 = "/fsn"
SLASH_FOREVERSTICKYNOTES4 = "/foreversticky"
SlashCmdList.FOREVERSTICKYNOTES = function()
    print("|cffd8b36aForever Sticky Notes: command received; opening notes.|r")
    InitializeWithDiagnostics()
    if not manager then
        print("|cffff4444Forever Sticky Notes: failed to create the notes window.|r")
        return
    end
    if manager:IsShown() then
        manager:Hide()
        print("|cffd8b36aForever Sticky Notes hidden.|r")
    else
        manager:Show()
        manager:Raise()
        print("|cffd8b36aForever Sticky Notes opened. Use New note to get started.|r")
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, _, loadedAddon)
    if loadedAddon == ADDON_NAME then
        print("|cffd8b36aForever Sticky Notes: addon loaded; initializing.|r")
        InitializeWithDiagnostics()
        print("|cffd8b36aForever Sticky Notes: ready. Use /notes to open.|r")
        loader:UnregisterEvent("ADDON_LOADED")
    end
end)
