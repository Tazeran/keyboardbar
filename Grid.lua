-- Optional icon grid: a separate, draggable X-by-Y pane of mouse-click slots (no key bindings).
-- Drop spells / items / macros on it like any slot; left- or right-click uses them; right-drag moves them.
local ADDON, KB = ...
local G = {}
KB.Grid = G

local HEADER, PAD = 14, 4
local slots = {}
local DEFAULTS = { on = false, cols = 4, rows = 6, locked = false }

function G:Opt(name)
    local g = KB.db and KB.db.grid
    local v = g and g[name]
    if v == nil then return DEFAULTS[name] end
    return v
end

function G:Set(name, v)
    KB.db.grid = KB.db.grid or {}
    KB.db.grid[name] = v
end

-- Actions live in the profile, keyed "row:col", so resizing the grid never shuffles them.
local function store()
    local p = KB:Profile()
    p.grid = p.grid or {}
    return p.grid
end
local function getAction(slot) return store()[slot.id] end

-- Secure attributes ---------------------------------------------------------
local function blank(slot)
    slot:SetAttribute("type1", ""); slot:SetAttribute("type2", "")
    for _, n in ipairs({ "spell", "item", "macro" }) do slot:SetAttribute(n .. "1", nil); slot:SetAttribute(n .. "2", nil) end
end

local function apply(slot)
    if InCombatLockdown() then G.pending = true; return end
    blank(slot)
    local a = getAction(slot)
    if not a then return end
    for _, b in ipairs({ "1", "2" }) do
        if a.type == "spell" then slot:SetAttribute("type" .. b, "spell"); slot:SetAttribute("spell" .. b, a.name)
        elseif a.type == "item" then slot:SetAttribute("type" .. b, "item"); slot:SetAttribute("item" .. b, "item:" .. a.id)
        elseif a.type == "macro" then slot:SetAttribute("type" .. b, "macro"); slot:SetAttribute("macro" .. b, a.name) end
    end
end

local function setAction(slot, a)
    store()[slot.id] = a
    apply(slot)
end

-- Dropping ------------------------------------------------------------------
function G:SlotUnderMouse()
    if InCombatLockdown() or not (self.frame and self.frame:IsShown()) then return nil end
    for _, s in ipairs(slots) do
        if s:IsShown() and s:GetAlpha() > 0 and s:IsMouseOver() then return s end
    end
end

local function settleView()
    if KB.UI and not GetCursorInfo() then KB.UI:RestoreView() end
end

-- Put the cursor's action on a slot. With defer (right-click) the displaced action is returned instead of being
-- picked up, because the game clears the cursor again as it finishes a right-click.
function G:Receive(slot, defer)
    if InCombatLockdown() then return end
    local a = KB:ActionFromCursor()
    if not a then return end
    local old = getAction(slot)
    if KB.UI then KB.UI.dragSrc = nil end -- a keyboard drag ends here
    self.dragSrc = nil
    setAction(slot, a)
    ClearCursor()
    if old and defer then return old end
    if old then
        KB:PickupAction(old)
        if GetCursorInfo() then self.dragSrc = { slot = slot, action = old, orphan = true } end
    end
    self:Update()
    settleView()
end

function G:RightDrop(slot)
    if InCombatLockdown() or not GetCursorInfo() then return end
    slot.rcDrop = true -- this click must not use what just landed
    blank(slot)
    local old = self:Receive(slot, true)
    local waited, ticker = 0, nil
    ticker = C_Timer.NewTicker(0.03, function()
        waited = waited + 0.03
        if IsMouseButtonDown("RightButton") and waited < 3 then return end
        ticker:Cancel()
        C_Timer.After(0.05, function()
            slot.rcDrop = nil
            if not InCombatLockdown() then apply(slot) end
            if old and not InCombatLockdown() and not GetCursorInfo() then
                KB:PickupAction(old)
                if GetCursorInfo() then G.dragSrc = { slot = slot, action = old, orphan = true } end
            end
            G:Update()
            settleView()
        end)
    end)
end

-- An icon pulled out of the grid and let go: onto a slot / key it lands there; anywhere else it is removed
-- (or put back, per the same setting the keyboard uses).
function G:Settle(src)
    src = src or self.dragSrc
    if not src or self.dragSrc ~= src then return end
    if InCombatLockdown() then self.dragSrc = nil; return end
    if not GetCursorInfo() then self.dragSrc = nil; settleView(); return end -- dropped somewhere that took it
    local s = self:SlotUnderMouse()
    if s then self:Receive(s); return end
    local k = KB.UI and KB.UI:KeyUnderMouse()
    if k and KB.UI.Receive then self.dragSrc = nil; KB.UI.Receive(k); return end
    self.dragSrc = nil
    ClearCursor()
    if KB.db.ui.dropRemoves == false and not src.orphan then
        setAction(src.slot, src.action)
    else
        KB:Print(("Removed %s from the grid."):format(src.action.name or "?"))
    end
    self:Update()
    settleView()
end

-- Slots ---------------------------------------------------------------------
local function createSlot(i)
    local s = CreateFrame("Button", "KeyboardBarGridSlot" .. i, G.frame, "SecureActionButtonTemplate,BackdropTemplate")
    s:RegisterForClicks("AnyUp")
    s:RegisterForDrag("RightButton")
    s:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    s.bgArt = s:CreateTexture(nil, "BACKGROUND")
    s.bgArt:SetAllPoints(); s.bgArt:SetTexture("Interface\\Buttons\\UI-Quickslot"); s.bgArt:Hide()
    s.normalArt = s:CreateTexture(nil, "OVERLAY")
    s.normalArt:SetPoint("TOPLEFT", -6, 6); s.normalArt:SetPoint("BOTTOMRIGHT", 6, -6)
    s.normalArt:SetTexture("Interface\\Buttons\\UI-Quickslot2"); s.normalArt:Hide()
    s:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    s:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetPoint("TOPLEFT", 1, -1); s.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    s.cd = CreateFrame("Cooldown", nil, s, "CooldownFrameTemplate")
    s.cd:SetAllPoints(s.icon)
    s.cd:SetDrawSwipe(true); s.cd:SetDrawEdge(true)
    if s.cd.SetSwipeColor then s.cd:SetSwipeColor(0, 0, 0, 0.75) end
    local over = CreateFrame("Frame", nil, s)
    over:SetAllPoints(); over:SetFrameLevel(s.cd:GetFrameLevel() + 2)
    s.count = over:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    s.count:SetPoint("BOTTOMRIGHT", -2, 2)
    s.mana = over:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    s.mana:SetPoint("TOPRIGHT", -2, -2); s.mana:SetTextColor(0.35, 0.6, 1)

    s:HookScript("PreClick", function(self, btn, down)
        if InCombatLockdown() then return end
        if btn == "RightButton" and self.rcDrop then blank(self); return end -- the press already dropped here
        if GetCursorInfo() and not down then
            if btn == "LeftButton" and self:IsMouseOver() then G:Receive(self) end
            blank(self); self.blanked = true -- placing an action must not also use it
        elseif btn == "RightButton" and IsShiftKeyDown() and not down then
            setAction(self, nil); blank(self); self.blanked = true; G:Update()
        end
    end)
    s:HookScript("PostClick", function(self)
        if self.blanked and not InCombatLockdown() then self.blanked = nil; apply(self) end
    end)
    s:SetScript("OnReceiveDrag", function(self) G:Receive(self) end)
    s:SetScript("OnDragStart", function(self, button)
        if InCombatLockdown() or GetCursorInfo() or self.rcDrop then return end
        local a = getAction(self)
        if not a then return end
        -- Outside the Full view the grid is only a set of icons: moving one pops the Full view open (if allowed), like the keyboard.
        if KB.UI and KB.UI.BeginDragView and not KB.UI:BeginDragView() then
            KB:Print("Switch to the Full view to move keys around.")
            return
        end
        G.dragSrc = { slot = self, action = a }
        KB:PickupAction(a); setAction(self, nil); G:Update()
    end)
    s:SetScript("OnDragStop", function()
        local src = G.dragSrc
        if src then C_Timer.After(0.1, function() G:Settle(src) end) end
    end)
    s:SetScript("OnEnter", function(self)
        if self:GetAlpha() == 0 then return end -- hidden empty slot
        local a = getAction(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if a and a.type == "spell" then
            local id = a.id
            pcall(function() local i = C_Spell.GetSpellInfo(a.name); if i and i.spellID then id = i.spellID end end)
            GameTooltip:SetSpellByID(id)
        elseif a and a.type == "item" then GameTooltip:SetItemByID(a.id)
        elseif a then GameTooltip:SetText(a.name)
        else GameTooltip:SetText("Empty slot", 0.7, 0.7, 0.7); GameTooltip:AddLine("Drop an ability or item here.", 0.5, 0.5, 0.5) end
        GameTooltip:Show()
        if KB.UI and KB.UI.ShowNodeTip then KB.UI:ShowNodeTip(a and a.type == "spell" and a.name) end
    end)
    s:SetScript("OnLeave", function() GameTooltip:Hide(); if KB.UI and KB.UI.nodeTip then KB.UI.nodeTip:Hide() end end)
    return s
end

-- Layout --------------------------------------------------------------------
function G:Layout()
    if not self.frame then return end
    if InCombatLockdown() then self.pendingLayout = true; return end
    self.pendingLayout = nil
    local cols, rows = self:Opt("cols"), self:Opt("rows")
    local unit, gap = 42, KB.db.ui.gap or 3 -- the keyboard's key pitch and gap
    local size = unit - gap
    self.sig = gap .. "|" .. tostring(KB.db.ui.scale)
    local head = self:Opt("locked") and 0 or HEADER
    local n = 0
    for r = 1, rows do
        for c = 1, cols do
            n = n + 1
            local s = slots[n] or createSlot(n)
            slots[n] = s
            s.id = r .. ":" .. c
            s:SetSize(size, size)
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", self.frame, "TOPLEFT", PAD + (c - 1) * unit, -(head + PAD + (r - 1) * unit))
            s:Show()
            apply(s)
        end
    end
    for i = n + 1, #slots do slots[i]:Hide() end
    self.frame:SetSize(PAD * 2 + (cols - 1) * unit + size, head + PAD * 2 + (rows - 1) * unit + size)
    self.frame:SetScale(KB.db.ui.scale or 1)
    self:Update()
end

function G:SavePosition()
    local f = self.frame
    local point, _, rel, x, y = f:GetPoint()
    self:Set("pos", { point, rel, x, y })
end

function G:PlaceFrame()
    local f = self.frame
    f:ClearAllPoints()
    local p = KB.db.grid and KB.db.grid.pos
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0) end
end

function G:ResetPosition()
    self:Set("pos", nil)
    if self.frame then self:PlaceFrame() end
end

function G:SetShown(on)
    self:Set("on", on and true or false)
    if on then
        self:Build()
        self.frame:Show()
        self:Layout()
    elseif self.frame then
        self.frame:Hide()
    end
end

function G:Toggle()
    self:SetShown(not self:Opt("on"))
    KB:Print("Grid " .. (self:Opt("on") and "shown." or "hidden."))
end

-- Display -------------------------------------------------------------------
local function paintSlot(s)
    local a = getAction(s)
    local c = KB.db.ui.showMana == true and a and a.type == "spell" and KB:ManaCost(a.name)
    s.mana:SetText(c and tostring(c) or "")
    if not a then
        s.icon:Hide(); s.count:SetText(""); s.cd:Clear()
        KB.UI.Paint(s, { 0.08, 0.08, 0.1, 0.8 }, { 0.3, 0.3, 0.35, 1 }) -- same look as an empty key
        return
    end
    local st = KB:GetState(a)
    s.icon:SetTexture(st.icon); s.icon:Show()
    local empty = false
    pcall(function() empty = (a.type == "item" and st.count == 0) end)
    s.icon:SetDesaturated(empty)
    local okc, many = pcall(function() return st.count and (st.count > 1 or (a.type == "item" and st.count == 0)) end)
    s.count:SetText((okc and many) and st.count or "")
    local r, g, b = 1, 1, 1
    pcall(function()
        if empty then r, g, b = 0.45, 0.45, 0.45
        elseif st.usable == false then r, g, b = 0.4, 0.4, 0.4
        elseif st.nomana then r, g, b = 0.4, 0.4, 1
        elseif st.range == false then r, g, b = 1, 0.3, 0.3 end
    end)
    s.icon:SetVertexColor(r, g, b)
    if st.start ~= nil and st.dur ~= nil then
        local ok = pcall(function()
            if issecretvalue and (issecretvalue(st.start) or issecretvalue(st.dur)) or st.dur > 0 then
                if st.durObj and s.cd.SetCooldownFromDurationObject then s.cd:SetCooldownFromDurationObject(st.durObj)
                else s.cd:SetCooldown(st.start, st.dur) end
            else s.cd:Clear() end
        end)
        if not ok then s.cd:Clear() end
    else s.cd:Clear() end
    local bd = { 0.6, 0.6, 0.65, 1 }
    pcall(function()
        if st.cast ~= nil and st.cast == st.castName then bd = { 0.2, 1, 0.2, 1 }
        elseif st.active then bd = { 1, 0.9, 0.2, 1 } end
    end)
    bd.state = bd[1] ~= 0.6
    KB.UI.Paint(s, { 0, 0, 0, 1 }, bd)
end

-- Follows the keyboard's view cycle: the background, empty slots and the move handle exist only in the Full view;
-- Bound / Play show just the icons (slots keep their places, nothing collapses); Cooldowns hides the grid.
function G:CurrentView()
    local hv = KB.UI and KB.UI.hdr and KB.UI.hdr:GetAttribute("view")
    return hv or KB.db.ui.view or "full"
end

function G:Update()
    if not (self.frame and self.frame:IsShown()) then return end
    if not InCombatLockdown() and self.sig ~= (KB.db.ui.gap or 3) .. "|" .. tostring(KB.db.ui.scale) then self:Layout() end
    local view = self:CurrentView()
    local full = view == "full"
    local f = self.frame
    f:EnableMouse(full)
    if full then
        f:SetBackdropColor(0.04, 0.04, 0.06, 0.6); f:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    else
        f:SetBackdropColor(0, 0, 0, 0); f:SetBackdropBorderColor(0, 0, 0, 0)
    end
    self.header:SetShown(full and not self:Opt("locked"))
    for _, s in ipairs(slots) do
        if s:IsShown() then
            paintSlot(s)
            local filled = getAction(s) ~= nil
            s:SetAlpha((full or (filled and view ~= "cooldown")) and 1 or 0)
        end
    end
end

-- Build ---------------------------------------------------------------------
function G:Build()
    if self.frame then return end
    local f = CreateFrame("Frame", "KeyboardBarGrid", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetFrameStrata("MEDIUM"); f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0.04, 0.04, 0.06, 0.6); f:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    self:PlaceFrame()

    local h = CreateFrame("Frame", nil, f)
    self.header = h
    h:SetPoint("TOPLEFT"); h:SetPoint("TOPRIGHT"); h:SetHeight(HEADER)
    h:EnableMouse(true); h:RegisterForDrag("LeftButton")
    local t = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    t:SetPoint("CENTER"); t:SetText("Grid  (drag to move)")
    h:SetScript("OnDragStart", function() if not InCombatLockdown() then f:StartMoving() end end)
    h:SetScript("OnDragStop", function() f:StopMovingOrSizing(); G:SavePosition() end)

    local acc = 0
    f:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.1 then return end
        acc = 0
        G:Update()
        -- safety net: a release that was missed settles the drag once no button is held
        if G.dragSrc and not IsMouseButtonDown("RightButton") and not IsMouseButtonDown("LeftButton") then
            G.upFor = (G.upFor or 0) + 0.1
            if G.upFor > 0.4 then G.upFor = 0; G:Settle() end
        else G.upFor = 0 end
    end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(function() ev:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
ev:SetScript("OnEvent", function(_, event, button)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(1, function() if G:Opt("on") then G:SetShown(true) end end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if G.pendingLayout then G:Layout() elseif G.pending then
            G.pending = nil
            for _, s in ipairs(slots) do apply(s) end
        end
    elseif event == "GLOBAL_MOUSE_DOWN" then
        -- A right-click with an icon on the cursor over a slot drops it there (before the game discards the icon).
        if button == "RightButton" and GetCursorInfo() then
            local s = G:SlotUnderMouse()
            if s then G:RightDrop(s) end
        end
    end
end)
