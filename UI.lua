-- Keyboard window: header (view / layer / collapse), key frames, refresh loop.
local ADDON, KB = ...
local UI = {}
KB.UI = UI

local UNIT, HEADER = 42, 22
local function GAP() return KB.db and KB.db.ui.gap or 3 end
local keys = {}          -- list of key frames
UI.keys = keys
local rowOf = {}         -- row index -> list of key frames / gap markers
local LAYERS = { "", "SHIFT-", "CTRL-", "ALT-" }
local LAYER_LABEL = { [""] = "Base", ["SHIFT-"] = "Shift", ["CTRL-"] = "Ctrl", ["ALT-"] = "Alt" }
UI.pinned = ""
UI.layer = ""

function UI:Layer()
    local p = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "")
    return p ~= "" and p or self.pinned
end

local function bindKey(k) return UI.layer .. k.def.id end

-- Key frames ----------------------------------------------------------------
local function receive(k)
    if InCombatLockdown() or k.def.fixed then return end
    local a = KB:ActionFromCursor()
    if not a then return end
    local bk = bindKey(k)
    local old = KB:GetAction(bk)
    KB:SetAction(bk, a)
    ClearCursor()
    if old then KB:PickupAction(old) end
    UI:Refresh(true)
end

local function createKey(parent, def)
    local name = "KeyboardBarKey" .. def.id:gsub("%W", function(c) return ("_%02x"):format(c:byte()) end)
    local k = CreateFrame("Button", name, parent, def.fixed and "BackdropTemplate" or "SecureActionButtonTemplate,BackdropTemplate")
    if not def.fixed then
        k:RegisterForClicks("AnyUp", "AnyDown")
        table.insert(KB.keyFrames, k)
    end
    k.def = def
    k:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    k:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    k:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    k.bgArt = k:CreateTexture(nil, "BACKGROUND")
    k.bgArt:SetAllPoints(); k.bgArt:SetTexture("Interface\\Buttons\\UI-Quickslot"); k.bgArt:Hide()
    k.normalArt = k:CreateTexture(nil, "OVERLAY")
    k.normalArt:SetPoint("TOPLEFT", -6, 6); k.normalArt:SetPoint("BOTTOMRIGHT", 6, -6)
    k.normalArt:SetTexture("Interface\\Buttons\\UI-Quickslot2"); k.normalArt:Hide()
    k.icon = k:CreateTexture(nil, "ARTWORK")
    k.icon:SetPoint("TOPLEFT", 1, -1); k.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    k.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    k.cd = CreateFrame("Cooldown", nil, k, "CooldownFrameTemplate")
    k.cd:SetAllPoints(k.icon)
    k.cd:SetDrawSwipe(true); k.cd:SetDrawEdge(true); k.cd:SetHideCountdownNumbers(true)
    if k.cd.SetSwipeColor then k.cd:SetSwipeColor(0, 0, 0, 0.75) end
    local over = CreateFrame("Frame", nil, k)
    over:SetAllPoints(); over:SetFrameLevel(k.cd:GetFrameLevel() + 2)
    k.label = over:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    k.label:SetPoint("TOPLEFT", 3, -2); k.label:SetText(def.label)
    k.cdText = over:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    k.cdText:SetPoint("CENTER", 0, 0); k.cdText:SetTextColor(1, 0.9, 0.3)
    k.name = over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    k.name:SetPoint("BOTTOM", 0, 2); k.name:SetWidth(UNIT - 4); k.name:SetWordWrap(false)
    k.arrow = over:CreateTexture(nil, "OVERLAY")
    k.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    k.arrow:SetSize(18, 18); k.arrow:SetPoint("CENTER", 0, 3); k.arrow:Hide()
    k.count = over:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    k.count:SetPoint("BOTTOMRIGHT", -2, 2)
    k:RegisterForDrag("LeftButton")
    k:SetScript("OnReceiveDrag", receive)
    -- HookScript so the secure click handler (the actual cast) is kept.
    k:HookScript("PreClick", function(self, btn, down)
        if self.cycle and btn == "LeftButton" and not down and not GetCursorInfo() then UI:CycleView() end
        if InCombatLockdown() then return end
        if btn == "MiddleButton" and not down and not GetCursorInfo() then
            local bk = bindKey(self)
            if not KB:GetAction(bk) and not self.cycle then
                if KB:GetSystemAction(bk) then KB:ClearSystemBinding(bk); UI:Refresh(true)
                elseif GetBindingAction(bk) == "" and KB:RestoreBinding(bk) then UI:Refresh(true) end
            end
            return
        end
        if GetCursorInfo() then
            if not down then receive(self) end
            KB:BlankKey(self) -- placing an action must not also cast it
            self.kbBlanked = true
        elseif btn == "RightButton" and IsShiftKeyDown() and not down then
            KB:ClearAction(bindKey(self)); UI:Refresh(true)
        end
    end)
    k:HookScript("PostClick", function(self, btn, down)
        if self.sys and not self.action and not self.cycle and not KB:SysClickable(self.sys) and btn == "LeftButton" and not GetCursorInfo() and not UI.dragSys then
            KB:RunSystem(self.sys, down)
        end
        -- Never rebuild bindings during a normal press: that interrupts key-down/key-up delivery.
        if self.kbBlanked and not InCombatLockdown() then self.kbBlanked = nil; KB:ApplyBindings() end
    end)
    k:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        local bk = bindKey(self)
        local a = KB:GetAction(bk)
        if a then
            if self.def.fixed then return end
            KB:PickupAction(a); KB:ClearAction(bk); UI:Refresh(true)
        else
            local sys = KB:GetSystemAction(bk)
            if sys then UI:StartSystemDrag(self, bk, sys) end
        end
    end)
    k:SetScript("OnDragStop", function(self) if UI.dragSys then UI:StopSystemDrag() end end)
    k:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local a = self.action
        if a and a.type == "spell" then
            -- spells are stored by name: show the rank you currently have, not the one dragged on
            local id = a.id
            pcall(function() local i = C_Spell.GetSpellInfo(a.name); if i and i.spellID then id = i.spellID end end)
            GameTooltip:SetSpellByID(id)
        elseif a and a.type == "item" then GameTooltip:SetItemByID(a.id)
        elseif a then GameTooltip:SetText(a.name)
        elseif self.sys then
            -- system binding: the game's full name (the key shows a shortened label)
            GameTooltip:SetText(_G["BINDING_NAME_" .. self.sys] or self.sys, 1, 1, 1)
        else GameTooltip:SetText(bindKey(self), 1, 1, 1) end
        GameTooltip:AddLine(bindKey(self), 0.6, 0.8, 1)
        if self.sys and not a then GameTooltip:AddLine("Middle-click: unbind", 0.5, 0.5, 0.5) end
        GameTooltip:Show()
    end)
    k:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return k
end

-- Visuals -------------------------------------------------------------------
-- bg / border are {r,g,b,a}. "flat" = dark square + thin border; "blizzard" = the game's own
-- action-slot textures (border art tinted by the state colour).
local function paint(k, bg, bd)
    if KB.db.ui.style == "blizzard" then
        k:SetBackdropColor(0, 0, 0, 0); k:SetBackdropBorderColor(0, 0, 0, 0)
        k.bgArt:Show(); k.normalArt:Show()
        k.bgArt:SetVertexColor(math.min(1, 0.6 + bg[1] * 1.5), math.min(1, 0.6 + bg[2] * 1.5), math.min(1, 0.6 + bg[3] * 1.5), bg[4] < 0.5 and 0.5 or 1)
        k.normalArt:SetVertexColor(math.min(1, bd[1] * 1.4), math.min(1, bd[2] * 1.4), math.min(1, bd[3] * 1.4), 1)
    else
        k.bgArt:Hide(); k.normalArt:Hide()
        k:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]); k:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4])
    end
end

local function style(k, a, s, sys)
    k.action = a
    k.sys = sys
    k.label:SetText(k.cycle and "~" or k.def.label)
    if k.cycle then
        k.icon:Hide(); k.count:SetText(""); k.cd:Clear(); k.cdText:SetText(""); k.arrow:Hide()
        k.name:SetText(KB.VIEW_LABEL[KB.db.ui.view] or "")
        paint(k, { 0.1, 0.25, 0.5, 0.7 }, { 0.4, 0.6, 0.9, 1 })
        k.label:SetAlpha(1)
        return
    end
    if not a and sys then
        local label, rot, tint = KB:SystemInfo(sys)
        k.count:SetText(""); k.cd:Clear(); k.cdText:SetText("")
        local ico = KB:SystemIcon(sys)
        if ico then k.icon:SetTexture(ico); k.icon:SetVertexColor(0.9, 0.9, 0.9); k.icon:Show() else k.icon:Hide() end
        k.name:SetText(label)
        k.arrow:SetShown(rot ~= nil)
        if rot then k.arrow:SetRotation(rot) end
        paint(k, { tint[1], tint[2], tint[3], 0.55 }, { tint[1] + 0.2, tint[2] + 0.2, tint[3] + 0.2, 1 })
        k.label:SetAlpha(1)
        return
    end
    k.arrow:Hide()
    if not a then
        k.icon:Hide(); k.name:SetText(""); k.count:SetText(""); k.cd:Clear(); k.cdText:SetText("")
        paint(k, { 0.08, 0.08, 0.1, k.def.fixed and 0.35 or 0.8 }, { 0.3, 0.3, 0.35, 1 })
        k.label:SetAlpha(k.def.fixed and 0.4 or 1)
        return
    end
    k.label:SetAlpha(1)
    k.icon:SetTexture(s.icon); k.icon:Show()
    k.name:SetText(KB.db.ui.showNames and a.name or "")
    local okc, many = pcall(function() return s.count and s.count > 1 end)
    k.count:SetText((okc and many) and s.count or "")
    local r, g, b = 1, 1, 1
    pcall(function()
        if s.usable == false then r, g, b = 0.4, 0.4, 0.4
        elseif s.nomana then r, g, b = 0.4, 0.4, 1
        elseif s.range == false then r, g, b = 1, 0.3, 0.3 end
    end)
    k.icon:SetVertexColor(r, g, b)
    -- Cooldown: values may be secret in combat; SetCooldown accepts them, comparisons don't.
    if s.start ~= nil and s.dur ~= nil then
        local ok = pcall(function()
            if issecretvalue and (issecretvalue(s.start) or issecretvalue(s.dur)) then
                -- Secret (combat): the game lets a duration object drive the frame, including its own numbers.
                k.cd:SetHideCountdownNumbers(false)
                if s.durObj and k.cd.SetCooldownFromDurationObject then k.cd:SetCooldownFromDurationObject(s.durObj)
                else k.cd:SetCooldown(s.start, s.dur) end
            elseif s.dur > 0 then
                -- same path and look as combat: duration object + the frame's own numbers
                k.cd:SetHideCountdownNumbers(false)
                if s.durObj and k.cd.SetCooldownFromDurationObject then k.cd:SetCooldownFromDurationObject(s.durObj)
                else k.cd:SetCooldown(s.start, s.dur) end
            else k.cd:Clear() end
        end)
        if not ok then k.cd:Clear() end
    else k.cd:Clear() end
    -- Own countdown number (only when readable; > 1.5s so the global cooldown doesn't flash numbers).
    local txt = ""
    pcall(function()
        if s.start and s.dur and not (issecretvalue and (issecretvalue(s.start) or issecretvalue(s.dur))) and s.dur > 1.5 then
            local left = s.start + s.dur - GetTime()
            if false and left > 0 then txt = left >= 60 and ("%dm"):format(left / 60) or left >= 10 and ("%d"):format(left) or ("%.1f"):format(left) end
        end
    end)
    k.cdText:SetText(txt)
    pcall(function()
        if txt ~= "" and KB.Debug and not k.cdLogged then
            k.cdLogged = true
            KB.Debug:Log("cd", ("%s start=%s dur=%s shown=%s"):format(a.name, tostring(s.start), tostring(s.dur), tostring(k.cd:IsShown())))
        end
    end)
    local bd = { 0.6, 0.6, 0.65, 1 }
    local casting, active = false, false
    pcall(function() casting = s.cast ~= nil and s.cast == s.castName; active = s.active and true or false end)
    if casting then bd = { 0.2, 1, 0.2, 1 } elseif active then bd = { 1, 0.9, 0.2, 1 } end
    paint(k, { 0, 0, 0, 1 }, bd)
end

local function wanted(view, a, s, sys)
    if view == "full" then return true end
    if view == "bound" then return a ~= nil or sys ~= nil end
    if not a then return false end
    if view == "assigned" then return true end
    if view == "cooldown" then
        if s.start == nil or s.dur == nil then return false end
        if issecretvalue and (issecretvalue(s.start) or issecretvalue(s.dur)) then return nil end -- unknown: keep as is
        return (s.dur > 1.5 and (s.start + s.dur) > GetTime()) and true or false
    end
    return true
end

function UI:Reflow(sig)
    if sig == self.sig or InCombatLockdown() then return end -- keys are secure: no moving in combat
    self.sig = sig
    local y = 0
    for _, list in ipairs(rowOf) do
        local x, shown = 0, 0
        for _, k in ipairs(list) do
            if k.gap then
                if UI:GroupOn(k.group) then x = x + k.gap * UNIT end
            else
                local w, grp = KB:KeyW(k.def), UI:GroupOn(k.def.group)
                if grp then x = x + KB:KeyPad(k.def) * UNIT end
                k:SetSize(w * UNIT - GAP(), UNIT - GAP())
                if k.visible then
                    k:ClearAllPoints()
                    k:SetPoint("TOPLEFT", self.body, "TOPLEFT", x, -y); shown = shown + 1
                end
                if grp then x = x + w * UNIT end
            end
        end
        if shown > 0 or KB.db.ui.keepPositions then y = y + UNIT end
    end
    self.body:SetHeight(math.max(y, 1))
    self.body:SetWidth(KB:RowUnits() * UNIT)
    self:ApplySize()
end

function UI:GroupOn(g)
    return g == nil or KB.db.ui["show" .. g] ~= false
end

function UI:Relayout()
    if InCombatLockdown() then KB:Print("Can't change the layout in combat."); return end
    self.sig = nil; self:Refresh(true)
end

function UI:ApplySize()
    local f = self.frame
    local collapsed = KB.db.ui.collapsed
    if not InCombatLockdown() then
        local h = collapsed and 1 or math.max(self.body:GetHeight(), 1)
        if self.edit then h = math.max(h, UNIT) end
        f:SetSize(KB:RowUnits() * UNIT, h)
    end
    self.body:SetShown(not collapsed)
end

-- The window is chrome-less: just keys. The anchored edge (top or bottom) stays put while rows come and go.
function UI:PlaceFrame()
    if InCombatLockdown() then return end
    local ui, f, p = KB.db.ui, self.frame, KB.db.ui.pos
    f:ClearAllPoints(); self.body:ClearAllPoints()
    if ui.anchor == "bottom" then
        f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", p.x, p.bottom)
        self.body:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    else
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.top)
        self.body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    end
end

function UI:MeasurePosition()
    local f = self.frame
    local l, t, b = f:GetLeft(), f:GetTop(), f:GetBottom()
    if l and t and b then KB.db.ui.pos = { x = l, top = t, bottom = b } end
end

function UI:SetAnchor(a)
    if InCombatLockdown() then KB:Print("Can't change the layout in combat."); return end
    self:MeasurePosition()
    KB.db.ui.anchor = a
    self:PlaceFrame()
end

function UI:SetEditMode(on)
    self.edit = on and true or false
    self.chrome:SetShown(self.edit)
    if self.edit and not self.frame:IsShown() then self.frame:Show() end
    self:ApplySize()
    self:Refresh(true)
end

function UI:Refresh(force)
    if not self.frame or not self.frame:IsShown() then return end
    self.layer = self:Layer()
    self.layerBtn:SetText(LAYER_LABEL[self.layer] or self.layer)
    self.viewBtn:SetText(KB.VIEW_LABEL[KB.db.ui.view])
    if KB.db.ui.collapsed then return end
    local view, sig = KB.db.ui.view, {}
    for i, k in ipairs(keys) do
        local a = KB:GetAction(bindKey(k))
        local ok, s = pcall(function() return a and KB:GetState(a) or {} end)
        if not ok then KB.Debug:Err("state " .. k.def.id, s); s = {} end
        local sys = (not a) and KB:GetSystemAction(bindKey(k)) or nil
        k.cycle = (k.def.id == KB.db.ui.cycleKey and self.layer == "" and not a) or nil
        local w = (k.cycle and KB.db.ui.alwaysShowCycle ~= false) or wanted(view, a, s, sys)
        local unknown = (w == nil)
        if unknown then w = k.visible end
        local show = UI:GroupOn(k.def.group) and w
        k.visible = show
        k:SetAlpha(show and 1 or 0)
        -- Cooldowns view: keep keys with an action shown (invisible via alpha) so that in combat, when
        -- the lockdown forbids Show(), alpha alone can still bring one up.
        local physical = show or (view == "cooldown" and a ~= nil and UI:GroupOn(k.def.group))
        if not InCombatLockdown() then k:SetShown(physical) end
        local sok, serr = pcall(style, k, a, s, sys)
        if not sok then KB.Debug:Err("style " .. k.def.id, serr) end
        if unknown and a and UI:GroupOn(k.def.group) then
            -- Cooldown times are secret in combat, so ask the cooldown frame itself: it is shown while
            -- something is cooling down. The global cooldown doesn't count.
            local on = false
            pcall(function()
                local g = s.gcd
                if g ~= nil and issecretvalue and issecretvalue(g) then g = false end
                on = (k.cd:IsShown() and not g) and true or false
            end)
            show = on; k.visible = on
            k:SetAlpha(on and 1 or 0)
        end
        sig[i] = show and "1" or "0"
    end
    self:Reflow(view .. tostring(KB:RowUnits()) .. KB.db.ui.sizeMode .. KB.db.ui.style .. GAP() .. tostring(KB.db.ui.keepPositions) .. table.concat(sig))
end

-- System-binding drag (rebinding game keys) ---------------------------------
local ghost
function UI:StartSystemDrag(k, bk, sys)
    if not ghost then
        ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        ghost:SetFrameStrata("TOOLTIP"); ghost:SetSize(60, 24)
        ghost:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        ghost:SetBackdropColor(0.1, 0.3, 0.5, 0.9)
        ghost.text = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ghost.text:SetPoint("CENTER")
        ghost:SetScript("OnUpdate", function(self)
            local x, y = GetCursorPosition(); local s = UIParent:GetEffectiveScale()
            self:ClearAllPoints(); self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
        end)
    end
    UI.dragSys = { from = k, bk = bk, action = sys }
    ghost.text:SetText((KB:SystemInfo(sys)))
    ghost:Show()
end

function UI:StopSystemDrag()
    local d = UI.dragSys
    UI.dragSys = nil
    if ghost then ghost:Hide() end
    if not d or InCombatLockdown() then return end
    for _, k in ipairs(keys) do
        if k ~= d.from and k.visible and not k.def.fixed and k:IsMouseOver() then
            KB:MoveSystemBinding(d.bk, bindKey(k)); self:Refresh(true)
            return
        end
    end
end

-- Build ---------------------------------------------------------------------
function UI:SetView(v) KB.db.ui.view = v; self.sig = nil; self:Refresh(true) end
function UI:CycleView()
    local cur = 1
    for i, v in ipairs(KB.VIEWS) do if v == KB.db.ui.view then cur = i end end
    self:SetView(KB.VIEWS[cur % #KB.VIEWS + 1])
end
function UI:SetScale(s)
    if InCombatLockdown() then KB:Print("Can't change scale in combat."); return end
    s = math.max(0.4, math.min(2, s))
    local f, p, old = self.frame, KB.db.ui.pos, self.frame:GetScale()
    if p then p.x, p.top, p.bottom = p.x * old / s, p.top * old / s, p.bottom * old / s end
    KB.db.ui.scale = s; f:SetScale(s)
    self:PlaceFrame()
end
function UI:ToggleCollapse()
    KB.db.ui.collapsed = not KB.db.ui.collapsed
    self:ApplySize(); self:Refresh(true)
end
function UI:Toggle()
    self.frame:SetShown(not self.frame:IsShown())
    if self.frame:IsShown() then self:Refresh(true) end
end

local function headerButton(f, width, onClick)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(width, HEADER - 4); b:SetScript("OnClick", onClick)
    return b
end

function UI:Build()
    local db = KB.db.ui
    local f = CreateFrame("Frame", "KeyboardBarFrame", UIParent)
    self.frame = f
    f:SetMovable(true); f:SetClampedToScreen(true); f:SetScale(db.scale)

    self.body = CreateFrame("Frame", nil, f)
    self.body:SetWidth(KB:RowUnits() * UNIT)

    -- Edit chrome: panel + header, only visible while the settings window is open.
    local chrome = CreateFrame("Frame", nil, f, "BackdropTemplate")
    self.chrome = chrome
    chrome:SetPoint("TOPLEFT", f, "TOPLEFT", -6, HEADER + 6)
    chrome:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 6, -6)
    chrome:SetFrameLevel(math.max(f:GetFrameLevel() - 1, 0))
    chrome:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    chrome:SetBackdropColor(0.03, 0.03, 0.05, 0.85); chrome:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    chrome:EnableMouse(true); chrome:RegisterForDrag("LeftButton")
    chrome:SetScript("OnDragStart", function() if not InCombatLockdown() then f:StartMoving() end end)
    chrome:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if not InCombatLockdown() then UI:MeasurePosition(); UI:PlaceFrame() end
    end)
    local title = chrome:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -7); title:SetText("Keyboard (drag to move)")
    local col = headerButton(chrome, 22, function() UI:ToggleCollapse() end)
    col:SetPoint("TOPRIGHT", -4, -3); col:SetText("-")
    self.viewBtn = headerButton(chrome, 100, function() UI:CycleView() end)
    self.viewBtn:SetPoint("RIGHT", col, "LEFT", -2, 0)
    self.layerBtn = headerButton(chrome, 56, function()
        local i = 1
        for n, l in ipairs(LAYERS) do if l == UI.pinned then i = n end end
        UI.pinned = LAYERS[i % #LAYERS + 1]; UI:Refresh(true)
    end)
    self.layerBtn:SetPoint("RIGHT", self.viewBtn, "LEFT", -2, 0)
    chrome:Hide()

    for r, row in ipairs(KB.ROWS) do
        rowOf[r] = {}
        for _, def in ipairs(row) do
            if def.gap then
                table.insert(rowOf[r], { gap = def.gap, group = def.group })
            else
                local k = createKey(self.body, def)
                k:SetSize(def.w * UNIT - GAP(), UNIT - GAP())
                k.visible = true
                keys[#keys + 1] = k
                table.insert(rowOf[r], k)
            end
        end
    end

    self.body:SetHeight(#KB.ROWS * UNIT)
    f:SetSize(KB:RowUnits() * UNIT, #KB.ROWS * UNIT)
    if not db.pos then
        local x = math.max(0, (UIParent:GetWidth() / db.scale - f:GetWidth()) / 2)
        db.pos = { x = x, bottom = 150, top = 150 + f:GetHeight() }
    end
    self:PlaceFrame()

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed > 0.1 then elapsed = 0; UI:Refresh() end
    end)
    f:Show()
    self:Refresh(true)
end
