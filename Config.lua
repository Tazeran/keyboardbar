-- Settings window (opened by plain "/kb" or the header button), split into tabs:
-- Layout, Behavior, Effects, Profile. Plain frames + standard templates.
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

local function tooltip(widget, text)
    if not text then return end
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(text, 1, 1, 1, 1, true); GameTooltip:Show()
    end)
    widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function cycleButton(parent, y, text, get, cycle, tip)
    label(parent, text, y)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(150, 22); b:SetPoint("TOPRIGHT", -16, y + 4)
    b:SetScript("OnClick", function() cycle(); C:Refresh() end)
    rows[#rows + 1] = function() b:SetText(get()) end
    layoutWidgets[#layoutWidgets + 1] = b
    tooltip(b, tip)
    return b
end

-- dep(): optional; the box is greyed out while it returns false. tip: hover text with the details.
local function checkbox(parent, y, text, get, set, layout, dep, tip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 12, y + 6); cb:SetSize(24, 24)
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0); fs:SetText(text)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); C:Refresh() end)
    rows[#rows + 1] = function()
        cb:SetChecked(get())
        if dep then
            local on = dep() and true or false
            cb:SetEnabled(on); fs:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
        end
    end
    if layout then layoutWidgets[#layoutWidgets + 1] = cb end
    tooltip(cb, tip)
    return cb
end

local function button(parent, y, text, onClick, x, w, anchor)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 308, 22)
    if anchor == "RIGHT" then b:SetPoint("TOPRIGHT", -16, y + 4) else b:SetPoint("TOPLEFT", x or 16, y + 4) end
    b:SetText(text); b:SetScript("OnClick", onClick)
    layoutWidgets[#layoutWidgets + 1] = b
    return b
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

-- Settings each tab's "Reset to defaults" puts back.
local RESETS = {
    Layout = function()
        local u = ui()
        u.sizeMode, u.style, u.borders, u.keepPositions, u.gap, u.showNav, u.showNumpad = "keyboard", "flat", nil, false, 3, true, true
        if u.anchor ~= "top" then KB.UI:SetAnchor("top") end
        KB.UI:SetScale(1)
        relayout()
    end,
    Behavior = function()
        local u = ui()
        u.showNames, u.alwaysShowCycle, u.skillNumbers, u.autoPlace, u.autoFromBottom = false, nil, nil, nil, nil
        u.dropRemoves, u.dragAnyView, u.modMini = nil, nil, nil
        KB.UI:Refresh(true)
    end,
    Grid = function()
        local g = KB.db.grid
        if g then g.cols, g.rows, g.locked = nil, nil, nil end
        KB.Grid:ResetPosition(); KB.Grid:Layout()
    end,
    Effects = function()
        local u = ui()
        u.fxOn, u.fxNewSpell, u.fxNewRank, u.fxReady, u.fxRange, u.fxActive = nil, nil, nil, nil, nil, nil
    end,
}

local TABS = { "Layout", "Behavior", "Effects", "Grid", "Profile" }

function C:SelectTab(name)
    if not self.frame then self:Build() end
    local idx = 1
    for i, n in ipairs(TABS) do if n == name or n:lower() == tostring(name):lower() then idx = i end end
    self.tab = idx
    for i, n in ipairs(TABS) do
        self.tabFrames[n]:SetShown(i == idx)
        if not self.panelTabs then self.tabButtons[n]:SetEnabled(i ~= idx) end -- plain buttons: grey out the current one
    end
    if self.panelTabs then pcall(PanelTemplates_SetTab, self.frame, idx) end
end

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
    hint:SetPoint("TOP", 0, -32); hint:SetText("Right-click uses a key; right-hold and drag moves it. /kb closes.")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- tab bar: the game's own tab look (tabs hanging below the window) when a tab template exists in this client,
    -- plain buttons across the top otherwise
    self.tabFrames, self.tabButtons = {}, {}
    local function makeTab(i, n)
        for _, tpl in ipairs({ "PanelTabButtonTemplate", "CharacterFrameTabButtonTemplate" }) do
            local ok, b = pcall(CreateFrame, "Button", "KeyboardBarConfigTab" .. i, f, tpl)
            if ok and b then
                b:SetID(i); b:SetText(n)
                if i == 1 then b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
                else b:SetPoint("LEFT", self.tabButtons[TABS[i - 1]], "RIGHT", -14, 0) end
                pcall(PanelTemplates_TabResize, b, 0)
                return b, true
            end
        end
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(74, 22); b:SetPoint("TOPLEFT", 16 + (i - 1) * 78, -52); b:SetText(n)
        return b, false
    end
    for i, n in ipairs(TABS) do
        local b, panel = makeTab(i, n)
        if i == 1 then self.panelTabs = panel end
        b:SetScript("OnClick", function() C:SelectTab(n) end)
        self.tabButtons[n] = b
        local tf = CreateFrame("Frame", nil, f)
        tf:SetAllPoints(f)
        tf:Hide()
        self.tabFrames[n] = tf
    end
    if self.panelTabs then pcall(PanelTemplates_SetNumTabs, f, #TABS) end
    local top = self.panelTabs and -56 or -86

    local tallest = 0
    local function section(name, build)
        local tf = self.tabFrames[name]
        local y = top
        local function step() y = y - 30 end
        build(tf, function() return y end, step, function(d) y = y - d end)
        if RESETS[name] then
            y = y - 10
            button(tf, y, "Reset " .. name:lower() .. " settings to defaults", function() RESETS[name](); C:Refresh() end, 16, 308)
            y = y - 30
        end
        tallest = math.max(tallest, -y)
    end

    -- Layout ---------------------------------------------------------------------------------
    section("Layout", function(tf, Y, step, skip)
        cycleButton(tf, Y(), "Key sizes",
            function() return KB:IsSquare() and "All squares" or "Keyboard widths" end,
            function() ui().sizeMode = KB:IsSquare() and "keyboard" or "square"; relayout() end); step()
        cycleButton(tf, Y(), "Key style",
            function() return ui().style == "blizzard" and "Blizzard slots" or "Flat" end,
            function() ui().style = ui().style == "blizzard" and "flat" or "blizzard"; relayout() end); step()
        checkbox(tf, Y(), "Show key borders", function() return ui().borders ~= false end,
            function(v) ui().borders = v end); step()
        cycleButton(tf, Y(), "Row anchor",
            function() return ui().anchor == "bottom" and "Bottom edge" or "Top edge" end,
            function() KB.UI:SetAnchor(ui().anchor == "bottom" and "top" or "bottom") end,
            "Which edge the rows stay attached to when rows hide."); step()
        cycleButton(tf, Y(), "When rows hide",
            function() return ui().keepPositions and "Keep positions" or "Shift rows" end,
            function() ui().keepPositions = not ui().keepPositions; relayout() end); step()
        local GAPNAME = { [1] = "Tight", [3] = "Normal", [6] = "Loose" }
        cycleButton(tf, Y(), "Key gap",
            function() return GAPNAME[ui().gap or 3] or ((ui().gap or 3) .. " px") end,
            function() ui().gap = nextOf({ 1, 3, 6 }, ui().gap or 3); relayout() end); step()

        label(tf, "Scale", Y())
        local minus = CreateFrame("Button", nil, tf, "UIPanelButtonTemplate")
        local plus = CreateFrame("Button", nil, tf, "UIPanelButtonTemplate")
        local val = tf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        plus:SetSize(30, 22); plus:SetPoint("TOPRIGHT", -16, Y() + 4); plus:SetText("+")
        val:SetPoint("RIGHT", plus, "LEFT", -12, 0); val:SetWidth(50)
        minus:SetSize(30, 22); minus:SetPoint("RIGHT", val, "LEFT", -12, 0); minus:SetText("-")
        minus:SetScript("OnClick", function() KB.UI:SetScale(ui().scale - 0.1); C:Refresh() end)
        plus:SetScript("OnClick", function() KB.UI:SetScale(ui().scale + 0.1); C:Refresh() end)
        rows[#rows + 1] = function() val:SetText(("%d%%"):format(math.floor(ui().scale * 100 + 0.5))) end
        step()

        checkbox(tf, Y(), "Show navigation keys and arrows", function() return ui().showNav ~= false end,
            function(v) ui().showNav = v; relayout() end, true); step()
        checkbox(tf, Y(), "Show numpad", function() return ui().showNumpad ~= false end,
            function(v) ui().showNumpad = v; relayout() end, true); step()
    end)

    -- Behavior -------------------------------------------------------------------------------
    section("Behavior", function(tf, Y, step)
        checkbox(tf, Y(), "Show keyboard", function() return KB.UI.frame:IsShown() end,
            function(v) if v ~= KB.UI.frame:IsShown() then KB.UI:Toggle() end end); step()
        checkbox(tf, Y(), "Show ability names on keys", function() return ui().showNames end,
            function(v) ui().showNames = v end); step()
        checkbox(tf, Y(), "Always show the cycle key (~)", function() return ui().alwaysShowCycle ~= false end,
            function(v) ui().alwaysShowCycle = v; KB.UI:Refresh(true) end, nil, nil,
            "Keep the ~ key visible in every view, even when nothing is on it."); step()
        checkbox(tf, Y(), "Profession skill (45/75) on keys", function() return ui().skillNumbers ~= false end,
            function(v) ui().skillNumbers = v; KB.UI:Refresh(true) end, nil, nil,
            "Shows your skill level in the corner of profession spells such as Smelting."); step()
        checkbox(tf, Y(), "Show Shift/Ctrl/Alt mappings as mini icons", function() return ui().modMini == true end,
            function(v) ui().modMini = v; KB.UI.rev = (KB.UI.rev or 0) + 1; KB.UI:Refresh(true) end, nil, nil,
            "Small icons along the bottom of a key (left Shift, middle Ctrl, right Alt) remind you what is on its modifier layers. They are only a reminder: clicks go to the key underneath."); step()
        checkbox(tf, Y(), "Gathering node list in Herbalism/Mining tooltips", function() return ui().nodeTips ~= false end,
            function(v) ui().nodeTips = v end, nil, nil,
            "Adds a side pane listing the herbs or ores and the skill each needs."); step()
        checkbox(tf, Y(), "Hide nodes I can already gather", function() return ui().nodeHideKnown == true end,
            function(v) ui().nodeHideKnown = v end, nil, nil,
            "Only list nodes that need more skill than you have."); step()
        checkbox(tf, Y(), "Auto-place newly learned abilities", function() return ui().autoPlace ~= false end,
            function(v) ui().autoPlace = v end, nil, nil,
            "A new ability's first rank goes on the first free key in the main block."); step()
        checkbox(tf, Y(), "Search from the bottom row up", function() return ui().autoFromBottom == true end,
            function(v) ui().autoFromBottom = v end, nil, nil,
            "Free keys are normally searched from the top row down. Applies to auto-place and Fill."); step()
        checkbox(tf, Y(), "Dropping off the keys removes it", function() return ui().dropRemoves ~= false end,
            function(v) ui().dropRemoves = v end, nil, nil,
            "Pulling an icon off a key and letting go away from the keys deletes the binding. Off: it goes back where it came from."); step()
        checkbox(tf, Y(), "Right-drag works in every view", function() return ui().dragAnyView ~= false end,
            function(v) ui().dragAnyView = v end, nil, nil,
            "In Bound / Play views the Full keyboard pops open while you move an icon, then goes back."); step()
        checkbox(tf, Y(), "Hide Blizzard action bars", function() return ui().hideBars end,
            function(v) ui().hideBars = v; if v then KB:HideBlizzardBars() else KB:Print("Blizzard bars return after /reload.") end end, nil, nil,
            "Reload to undo."); step()
    end)

    -- Effects --------------------------------------------------------------------------------
    section("Effects", function(tf, Y, step)
        local function on() return ui().fxOn ~= false end
        checkbox(tf, Y(), "Key effects (sparkle / glow)", function() return ui().fxOn ~= false end,
            function(v) ui().fxOn = v end, nil, nil, "Master switch for everything below."); step()
        checkbox(tf, Y(), "New ability: sparkle + glow", function() return ui().fxNewSpell ~= false end,
            function(v) ui().fxNewSpell = v end, nil, on, "A new ability sparkles and glows until you hover over it or press it."); step()
        checkbox(tf, Y(), "New rank: quick sparkle", function() return ui().fxNewRank ~= false end,
            function(v) ui().fxNewRank = v end, nil, on); step()
        checkbox(tf, Y(), "Cooldown ready: flash", function() return ui().fxReady ~= false end,
            function(v) ui().fxReady = v end, nil, on, "A flash when a real cooldown ends (the global cooldown is ignored)."); step()
        checkbox(tf, Y(), "Out of range / mana: flash", function() return ui().fxRange ~= false end,
            function(v) ui().fxRange = v end, nil, on, "A red flash when a spell goes out of range, blue when you run out of mana."); step()
        checkbox(tf, Y(), "Active spell: glow", function() return ui().fxActive ~= false end,
            function(v) ui().fxActive = v end, nil, on); step()
    end)

    -- Grid -----------------------------------------------------------------------------------
    section("Grid", function(tf, Y, step)
        local G = KB.Grid
        local function on() return G:Opt("on") end
        local sliderN = 0
        -- A slider that steps through the same list of values the buttons used to cycle through.
        local function numCycle(text, name, list, fmt, tip)
            local function idxOf(v) for i, x in ipairs(list) do if x == v then return i end end return 1 end
            sliderN = sliderN + 1
            local sname = "KeyboardBarGridSlider" .. sliderN
            local ok, s = pcall(CreateFrame, "Slider", sname, tf, "OptionsSliderTemplate")
            if not ok or not s then
                cycleButton(tf, Y(), text, function() return fmt(G:Opt(name)) end,
                    function() G:Set(name, nextOf(list, G:Opt(name))); G:Layout() end, tip); step()
                return
            end
            label(tf, text, Y())
            s:SetSize(120, 16); s:SetPoint("TOPRIGHT", -76, Y() - 2)
            s:SetMinMaxValues(1, #list); s:SetValueStep(1)
            if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
            for _, part in ipairs({ "Low", "High", "Text" }) do
                local fs = _G[sname .. part] or s[part]
                if fs and fs.SetText then fs:SetText("") end
            end
            local val = tf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            val:SetPoint("LEFT", s, "RIGHT", 10, 0); val:SetWidth(56); val:SetJustifyH("LEFT")
            local setting = false
            s:SetScript("OnValueChanged", function(self, v)
                local i = math.max(1, math.min(#list, math.floor(v + 0.5)))
                val:SetText(fmt(list[i]))
                if setting or G:Opt(name) == list[i] then return end
                G:Set(name, list[i]); G:Layout()
            end)
            rows[#rows + 1] = function()
                setting = true
                s:SetValue(idxOf(G:Opt(name)))
                val:SetText(fmt(G:Opt(name)))
                setting = false
            end
            layoutWidgets[#layoutWidgets + 1] = s
            tooltip(s, tip)
            step()
        end
        local function plain(v) return tostring(v) end
        local nums = {}
        for i = 1, 12 do nums[i] = i end
        checkbox(tf, Y(), "Show the icon grid", function() return G:Opt("on") end,
            function(v) G:SetShown(v) end, nil, nil,
            "A separate pane of click-only slots (no key bindings). Drop abilities and items on it; click to use, right-drag to move. /kb grid toggles it."); step()
        numCycle("Columns", "cols", nums, plain)
        numCycle("Rows", "rows", nums, plain)
        local note = tf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        note:SetPoint("TOPLEFT", 16, Y() + 6); note:SetText("Icon size, gap, scale and style follow the keyboard (Layout tab).")
        step()
        checkbox(tf, Y(), "Lock position (hides the move handle)", function() return G:Opt("locked") end,
            function(v) G:Set("locked", v); G:Layout() end, nil, nil,
            "Unlocked, the thin bar along the top of the grid drags it around the screen."); step()
        button(tf, Y(), "Put the grid back on the right edge", function() G:ResetPosition() end, 16, 308); step()
    end)

    -- Profile --------------------------------------------------------------------------------
    section("Profile", function(tf, Y, step)
        label(tf, "Current profile", Y()); step()
        local prev = CreateFrame("Button", nil, tf, "UIPanelButtonTemplate")
        local nxt = CreateFrame("Button", nil, tf, "UIPanelButtonTemplate")
        local pname = tf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        prev:SetSize(26, 22); prev:SetPoint("TOPLEFT", 16, Y() + 4); prev:SetText("<")
        nxt:SetSize(26, 22); nxt:SetPoint("TOPRIGHT", -16, Y() + 4); nxt:SetText(">")
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
        button(tf, Y(), "New profile...", function() StaticPopup_Show("KEYBOARDBAR_NEWPROFILE") end, 16, 150)
        button(tf, Y(), "Clear all keys", function() StaticPopup_Show("KEYBOARDBAR_CLEAR") end, nil, 150, "RIGHT")
        step()
        button(tf, Y(), "Fill in missing class abilities", function() KB:FillMissing() end, 16, 308); step()
    end)

    f:SetHeight(tallest + 30)
    f:SetScript("OnShow", function() C:Refresh(); KB.UI:SetEditMode(true) end)
    f:SetScript("OnHide", function() KB.UI:SetEditMode(false) end)
    f:RegisterEvent("PLAYER_REGEN_DISABLED"); f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function() C:Refresh() end)
    self:SelectTab(TABS[self.tab or 1])
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

-- Open the window (on a given tab, e.g. from /kb effects); with no tab it toggles.
function C:Toggle(tab)
    if not self.frame then self:Build() end
    if tab then
        self:SelectTab(tab)
        if not self.frame:IsShown() then self.frame:Show() end
    else
        self.frame:SetShown(not self.frame:IsShown())
    end
end
