-- Settings window (opened by plain "/kb" or the header button). Plain frames + standard templates.
local ADDON, KB = ...
local C = {}
KB.Config = C

local rows = {}      -- refresh callbacks
local layoutWidgets = {} -- disabled while in combat

local function ui() return KB.db.ui end
local function relayout() KB.UI:Relayout(); C:Refresh() end

local function label(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", 16, y); fs:SetText(text)
    return fs
end

local function cycleButton(parent, y, text, get, cycle)
    label(parent, text, y)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(150, 22); b:SetPoint("TOPRIGHT", -16, y + 4)
    b:SetScript("OnClick", function() cycle(); C:Refresh() end)
    rows[#rows + 1] = function() b:SetText(get()) end
    layoutWidgets[#layoutWidgets + 1] = b
    return b
end

local function checkbox(parent, y, text, get, set, layout)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 12, y + 6); cb:SetSize(24, 24)
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0); fs:SetText(text)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); C:Refresh() end)
    rows[#rows + 1] = function() cb:SetChecked(get()) end
    if layout then layoutWidgets[#layoutWidgets + 1] = cb end
    return cb
end

local function nextOf(list, cur)
    for i, v in ipairs(list) do if v == cur then return list[i % #list + 1] end end
    return list[1]
end

StaticPopupDialogs["KEYBOARDBAR_NEWPROFILE"] = {
    text = "New profile name:", button1 = ACCEPT, button2 = CANCEL, hasEditBox = true, timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function(self)
        local eb = self.editBox or self.EditBox
        local name = eb and eb:GetText()
        if name and name ~= "" then KB:SetProfile(name); C:Refresh() end
    end,
}
StaticPopupDialogs["KEYBOARDBAR_CLEAR"] = {
    text = "Remove every action from this profile's keys?", button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
    OnAccept = function() KB:Profile().keys = {}; KB:ApplyBindings(); KB.UI:Refresh(true) end,
}

function C:Build()
    local f = CreateFrame("Frame", "KeyboardBarConfig", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(340, 400); f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG"); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.95); f:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    tinsert(UISpecialFrames, "KeyboardBarConfig")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12); title:SetText("Keyboard Bar")
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOP", 0, -32); hint:SetText("Drag keys with right mouse (or left, here). /kb closes.")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local y = -56
    local function step() y = y - 30 end

    label(f, "Layout", y); y = y - 4; step()
    cycleButton(f, y, "Key sizes",
        function() return KB:IsSquare() and "All squares" or "Keyboard widths" end,
        function() ui().sizeMode = KB:IsSquare() and "keyboard" or "square"; relayout() end); step()
    cycleButton(f, y, "Key style",
        function() return ui().style == "blizzard" and "Blizzard slots" or "Flat" end,
        function() ui().style = ui().style == "blizzard" and "flat" or "blizzard"; relayout() end); step()
    checkbox(f, y, "Show key borders", function() return ui().borders ~= false end,
        function(v) ui().borders = v end); step()
    cycleButton(f, y, "Row anchor",
        function() return ui().anchor == "bottom" and "Bottom edge" or "Top edge" end,
        function() KB.UI:SetAnchor(ui().anchor == "bottom" and "top" or "bottom") end); step()
    cycleButton(f, y, "When rows hide",
        function() return ui().keepPositions and "Keep positions" or "Shift rows" end,
        function() ui().keepPositions = not ui().keepPositions; relayout() end); step()
    local GAPNAME = { [1] = "Tight", [3] = "Normal", [6] = "Loose" }
    cycleButton(f, y, "Key gap",
        function() return GAPNAME[ui().gap or 3] or ((ui().gap or 3) .. " px") end,
        function() ui().gap = nextOf({ 1, 3, 6 }, ui().gap or 3); relayout() end); step()

    -- scale
    label(f, "Scale", y)
    local minus = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    local plus = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    local val = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    plus:SetSize(30, 22); plus:SetPoint("TOPRIGHT", -16, y + 4); plus:SetText("+")
    val:SetPoint("RIGHT", plus, "LEFT", -12, 0); val:SetWidth(50)
    minus:SetSize(30, 22); minus:SetPoint("RIGHT", val, "LEFT", -12, 0); minus:SetText("-")
    minus:SetScript("OnClick", function() KB.UI:SetScale(ui().scale - 0.1); C:Refresh() end)
    plus:SetScript("OnClick", function() KB.UI:SetScale(ui().scale + 0.1); C:Refresh() end)
    rows[#rows + 1] = function() val:SetText(("%d%%"):format(math.floor(ui().scale * 100 + 0.5))) end
    step()

    checkbox(f, y, "Show navigation keys and arrows", function() return ui().showNav ~= false end,
        function(v) ui().showNav = v; relayout() end, true); step()
    checkbox(f, y, "Show numpad", function() return ui().showNumpad ~= false end,
        function(v) ui().showNumpad = v; relayout() end, true); step()

    y = y - 6
    label(f, "Behavior", y); step()
    checkbox(f, y, "Show keyboard", function() return KB.UI.frame:IsShown() end,
        function(v) if v ~= KB.UI.frame:IsShown() then KB.UI:Toggle() end end); step()
    checkbox(f, y, "Show ability names on keys", function() return ui().showNames end,
        function(v) ui().showNames = v end); step()
    checkbox(f, y, "Always show the cycle key (~)", function() return ui().alwaysShowCycle ~= false end,
        function(v) ui().alwaysShowCycle = v; KB.UI:Refresh(true) end); step()
    checkbox(f, y, "Show profession skill (45/75) on keys", function() return ui().skillNumbers ~= false end,
        function(v) ui().skillNumbers = v; KB.UI:Refresh(true) end); step()
    checkbox(f, y, "Hide Blizzard action bars (reload to undo)", function() return ui().hideBars end,
        function(v) ui().hideBars = v; if v then KB:HideBlizzardBars() else KB:Print("Blizzard bars return after /reload.") end end); step()

    y = y - 6
    label(f, "Profile", y); step()
    local prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    local nxt = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    local pname = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    prev:SetSize(26, 22); prev:SetPoint("TOPLEFT", 16, y + 4); prev:SetText("<")
    nxt:SetSize(26, 22); nxt:SetPoint("TOPRIGHT", -16, y + 4); nxt:SetText(">")
    pname:SetPoint("LEFT", prev, "RIGHT", 6, 0); pname:SetPoint("RIGHT", nxt, "LEFT", -6, 0); pname:SetWordWrap(false)
    local function shift(d)
        local list, cur = KB:ListProfiles(), 1
        for i, n in ipairs(list) do if n == KB:ProfileName() then cur = i end end
        KB:SetProfile(list[(cur - 1 + d) % #list + 1]); C:Refresh()
    end
    prev:SetScript("OnClick", function() shift(-1) end)
    nxt:SetScript("OnClick", function() shift(1) end)
    rows[#rows + 1] = function() pname:SetText(KB:ProfileName()) end
    layoutWidgets[#layoutWidgets + 1] = prev; layoutWidgets[#layoutWidgets + 1] = nxt
    step()
    local new = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    new:SetSize(150, 22); new:SetPoint("TOPLEFT", 16, y + 4); new:SetText("New profile...")
    new:SetScript("OnClick", function() StaticPopup_Show("KEYBOARDBAR_NEWPROFILE") end)
    local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clear:SetSize(150, 22); clear:SetPoint("TOPRIGHT", -16, y + 4); clear:SetText("Clear all keys")
    clear:SetScript("OnClick", function() StaticPopup_Show("KEYBOARDBAR_CLEAR") end)
    layoutWidgets[#layoutWidgets + 1] = new; layoutWidgets[#layoutWidgets + 1] = clear

    f:SetHeight(-y + 40)
    f:SetScript("OnShow", function() C:Refresh(); KB.UI:SetEditMode(true) end)
    f:SetScript("OnHide", function() KB.UI:SetEditMode(false) end)
    f:RegisterEvent("PLAYER_REGEN_DISABLED"); f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function() C:Refresh() end)
    f:Hide()
end

function C:Refresh()
    if not self.frame then return end
    for _, r in ipairs(rows) do r() end
    local lock = InCombatLockdown()
    for _, w in ipairs(layoutWidgets) do
        if w.SetEnabled then w:SetEnabled(not lock) end
    end
end

function C:Toggle()
    if not self.frame then self:Build() end
    self.frame:SetShown(not self.frame:IsShown())
end
