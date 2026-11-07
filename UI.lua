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
    UI.dragSrc = nil -- a drop on a key: this drag is settled
    KB:SetAction(bk, a)
    ClearCursor()
    if old then KB:PickupAction(old) end
    UI:Refresh(true)
end

local function createKey(parent, def, display)
    local name = "KeyboardBarKey" .. def.id:gsub("%W", function(c) return ("_%02x"):format(c:byte()) end)
    if display then name = nil end
    local k = CreateFrame("Button", name, parent, display and "BackdropTemplate" or "SecureActionButtonTemplate,BackdropTemplate")
    if not def.fixed and not display then
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
    if display then k:EnableMouse(false); return k end
    k:RegisterForDrag("LeftButton", "RightButton")
    k:SetScript("OnReceiveDrag", receive)
    -- HookScript so the secure click handler (the actual cast) is kept.
    k:HookScript("PreClick", function(self, btn, down)
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
            -- only a mouse release over this key drops the item here; a keyboard press of the same key must not
            if not down and self:IsMouseOver() then receive(self) end
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
    k:SetScript("OnDragStart", function(self, button)
        if InCombatLockdown() then return end
        -- Right-drag never casts (keys only have a left-click action). Left-drag is only for arrange mode
        -- (settings window open), where clicking keys is switched off.
        if button ~= "RightButton" and not UI.edit then return end
        if KB.db.ui.view ~= "full" then
            -- Rearranging is only allowed in the Full view, so a stray drag while playing can't pull anything off.
            if self.action or self.sys then KB:Print("Switch to the Full view to move keys around.") end
            return
        end
        local bk = bindKey(self)
        local a = KB:GetAction(bk)
        if a then
            if self.def.fixed then return end
            UI.dragSrc = { bk = bk, action = a }
            KB:PickupAction(a); KB:ClearAction(bk); UI:Refresh(true)
        else
            local sys = KB:GetSystemAction(bk)
            if sys then UI:StartSystemDrag(self, bk, sys) end
        end
    end)
    k:SetScript("OnDragStop", function(self)
        if UI.dragSys then UI:StopSystemDrag() end
        local src = UI.dragSrc
        if src then
            -- Dragged off a key and released somewhere that isn't a key: put it back where it came from.
            C_Timer.After(0.1, function()
                if UI.dragSrc ~= src then return end -- it was dropped on a key meanwhile
                UI.dragSrc = nil
                if GetCursorInfo() then ClearCursor() end
                KB:SetAction(src.bk, src.action); UI:Refresh(true)
            end)
        end
    end)
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
    -- With borders off, only the "something is happening" borders (casting / active) are still drawn.
    local noBorder = KB.db.ui.borders == false and not bd.state
    if KB.db.ui.style == "blizzard" then
        k:SetBackdropColor(0, 0, 0, 0); k:SetBackdropBorderColor(0, 0, 0, 0)
        k.bgArt:Show(); k.normalArt:SetShown(not noBorder)
        k.bgArt:SetVertexColor(math.min(1, 0.6 + bg[1] * 1.5), math.min(1, 0.6 + bg[2] * 1.5), math.min(1, 0.6 + bg[3] * 1.5), bg[4] < 0.5 and 0.5 or 1)
        k.normalArt:SetVertexColor(math.min(1, bd[1] * 1.4), math.min(1, bd[2] * 1.4), math.min(1, bd[3] * 1.4), 1)
    else
        k.bgArt:Hide(); k.normalArt:Hide()
        k:SetBackdropColor(bg[1], bg[2], bg[3], bg[4]); k:SetBackdropBorderColor(bd[1], bd[2], bd[3], noBorder and 0 or bd[4])
    end
end

local function style(k, a, s, sys)
    k.action = a
    k.sys = sys
    k.label:SetText(k.cycle and (k.def.id == "`" and "~" or k.def.label) or k.def.label)
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
    if casting then bd = { 0.2, 1, 0.2, 1, state = true } elseif active then bd = { 1, 0.9, 0.2, 1, state = true } end
    paint(k, { 0, 0, 0, 1 }, bd)
end

local function wanted(view, a, s, sys)
    if view == "full" then return true end
    if view == "bound" then return a ~= nil or sys ~= nil end
    if not a then return false end
    if view == "assigned" then return true end
    if view == "cooldown" then return false end -- the cooldown tray (unprotected copies) shows these
    return true
end

-- Layout ---------------------------------------------------------------------
-- Which keys exist in a view is decided by what is bound (fixed while in combat), so every view/layer
-- combination can be computed ahead of time and handed to the secure header (see UI:BuildSecure),
-- which then rearranges the protected keys even during combat.
-- layer: "" / "SHIFT-" / "CTRL-" / "ALT-" (or "X" = a modifier combination, nothing bound).
local function staticShow(k, view, layer)
    local a, sys
    if layer ~= "X" then
        local bk = layer .. k.def.id
        a = KB:GetAction(bk)
        sys = (not a) and KB:GetSystemAction(bk) or nil
    end
    if KB:IsCycleKey(k.def.id) and layer == "" and not a and KB.db.ui.alwaysShowCycle ~= false then return true end
    if view == "full" then return true end
    if view == "bound" then return a ~= nil or sys ~= nil end
    if view == "cooldown" then return false end
    return a ~= nil -- "assigned"
end

function UI:ComputeLayout(view, layer)
    local out, y = {}, 0
    for ri, list in ipairs(rowOf) do
        local x, shown = 0, 0
        for _, k in ipairs(list) do
            if k.gap then
                if UI:GroupOn(k.group) then x = x + k.gap * UNIT end
            else
                local w, grp = KB:KeyW(k.def), UI:GroupOn(k.def.group)
                if grp then x = x + KB:KeyPad(k.def) * UNIT end
                local show = (grp and staticShow(k, view, layer)) and true or false
                out[k.idx] = { x = x, y = -y, show = show, r = ri }
                if show then shown = shown + 1 end
                if grp then x = x + w * UNIT end
            end
        end
        if shown > 0 or KB.db.ui.keepPositions then y = y + UNIT end
    end
    return out, math.max(y, 1)
end

function UI:Reflow(sig)
    if sig == self.sig or InCombatLockdown() then return end -- the secure header handles combat
    self.sig = sig
    local lay, h = self:ComputeLayout(KB.db.ui.view, self.layer)
    for i, k in ipairs(keys) do
        local e = lay[i]
        k:SetSize(KB:KeyW(k.def) * UNIT - GAP(), UNIT - GAP())
        if self.tray then self.tray[i]:SetSize(KB:KeyW(k.def) * UNIT - GAP(), UNIT - GAP()) end
        if e.show then
            k:ClearAllPoints()
            k:SetPoint("TOPLEFT", self.body, "TOPLEFT", e.x, e.y)
        end
        k:SetShown(e.show)
    end
    self.body:SetHeight(h)
    self.body:SetWidth(KB:RowUnits() * UNIT)
    self:ApplySize()
    self.traySig = nil
    self:Publish()
end

-- Cooldown tray ---------------------------------------------------------------
-- The Cooldowns view needs rows that re-collapse as cooldowns start and end, even in combat. Protected keys
-- can't do that (and no script can read cooldowns), so this view draws unprotected copies of the keys that
-- have an ability. They keep each key's column, and only the rows that currently have something cooling
-- down are stacked, from the anchored edge. The real keys stay hidden but keep handling key presses.
function UI:LayoutTray(view)
    local tf = self.trayFrame
    if not tf then return end
    if view ~= "cooldown" then
        if tf:IsShown() then tf:Hide() end
        return
    end
    if not tf:IsShown() then tf:Show() end
    local u = KB.db.ui
    local base = table.concat({ self.layer, tostring(u.showNav), tostring(u.showNumpad), tostring(self.rev or 0), tostring(KB:RowUnits()), u.sizeMode }, "|")
    if self.trayBaseSig ~= base then
        self.trayBaseSig = base
        self.trayBase = self:ComputeLayout("assigned", self.layer)
    end
    local lay = self.trayBase
    local rows, lit = {}, {}
    for i, tk in ipairs(self.tray) do
        if tk.lit and lay[i] and lay[i].show then rows[lay[i].r] = true; lit[#lit + 1] = i end
    end
    local order = {}
    for r in pairs(rows) do order[#order + 1] = r end
    table.sort(order)
    local ord = {}
    for n, r in ipairs(order) do ord[r] = n - 1 end
    local m = #order
    local off = 0
    for _, k in ipairs(keys) do
        if k.cycle and u.alwaysShowCycle ~= false then off = 1 end -- the cycle key keeps the edge row
    end
    local sig = u.anchor .. "|" .. off .. "|" .. GAP() .. "|" .. base .. "|" .. table.concat(lit, ",")
    if sig == self.traySig then return end
    self.traySig = sig
    for _, i in ipairs(lit) do
        local tk, e = self.tray[i], lay[i]
        tk:ClearAllPoints()
        if u.anchor == "bottom" then
            tk:SetPoint("BOTTOMLEFT", tf, "BOTTOMLEFT", e.x, (m - 1 - ord[e.r] + off) * UNIT)
        else
            tk:SetPoint("TOPLEFT", tf, "TOPLEFT", e.x, -(ord[e.r] + off) * UNIT)
        end
    end
end

-- Secure layout header --------------------------------------------------------
-- A protected button whose script (running in the game's restricted environment, which IS allowed to
-- move protected frames in combat) re-lays-out every key. It runs when the view-cycle key is clicked
-- or pressed, and when a modifier key changes the layer.
local CODE = { { "B", "" }, { "S", "SHIFT-" }, { "C", "CTRL-" }, { "A", "ALT-" }, { "X", "X" } }
local PIN = { [""] = "", ["SHIFT-"] = "S", ["CTRL-"] = "C", ["ALT-"] = "A" }

local APPLY = [=[
    self:SetAttribute("dbgapply", (self:GetAttribute("dbgapply") or 0) + 1)
    local moved = 0
    local L = self:GetAttribute("layer") or "B"
    if L == "B" then
        local p = self:GetAttribute("pinned")
        if p and p ~= "" then L = p end
    end
    local V = self:GetAttribute("view") or "full"
    local body = self:GetFrameRef("body")
    local n = self:GetAttribute("nkeys") or 0
    for i = 1, n do
        local k = self:GetFrameRef("k" .. i)
        local d = self:GetAttribute("L" .. L .. V .. ":" .. i)
        if k and d and body then
            local x, y, s = strsplit(",", d)
            if s == "1" then
                k:ClearAllPoints()
                k:SetPoint("TOPLEFT", body, "TOPLEFT", tonumber(x), tonumber(y))
                k:Show()
                moved = moved + 1
            else
                k:Hide()
            end
        end
    end
    self:SetAttribute("dbgmoved", moved)
    self:SetAttribute("dbginfo", L .. V .. " n=" .. n)
    local height = self:GetAttribute("H" .. L .. V)
    if height and body then body:SetHeight(height) end
]=]

local CYCLE = [=[
self:SetAttribute("dbgclick", (self:GetAttribute("dbgclick") or 0) + 1)
local order = newtable("full", "bound", "assigned", "cooldown")
local cur = self:GetAttribute("view")
local idx = 1
for i = 1, 4 do
    if order[i] == cur then idx = i end
end
self:SetAttribute("view", order[idx % 4 + 1])
]=] .. APPLY

function UI:BuildSecure()
    local hdr = CreateFrame("Button", "KeyboardBarCycleHdr", UIParent, "SecureHandlerClickTemplate,SecureHandlerStateTemplate")
    self.hdr = hdr
    hdr:RegisterForClicks("AnyUp", "AnyDown")
    -- Repaint right after the script ran, so keys that should fade (e.g. entering Cooldowns) do so at once
    -- instead of showing for up to one refresh tick.
    hdr:HookScript("PostClick", function() UI:Refresh(true) end)
    hdr:SetAttribute("_onclick", CYCLE)
    hdr:SetAttribute("_onstate-layer", [=[
        self:SetAttribute("layer", newstate)
]=] .. APPLY)
    hdr:SetFrameRef("body", self.body)
    for i, k in ipairs(keys) do hdr:SetFrameRef("k" .. i, k) end
    hdr:SetAttribute("nkeys", #keys)
    hdr:SetAttribute("view", KB.db.ui.view)
    hdr:SetAttribute("layer", "B")
    RegisterStateDriver(hdr, "layer",
        "[mod:shift,nomod:ctrl,nomod:alt] S; [mod:ctrl,nomod:shift,nomod:alt] C; [mod:alt,nomod:shift,nomod:ctrl] A; [nomod] B; X")
end

function UI:SyncPinned()
    if self.hdr and not InCombatLockdown() then self.hdr:SetAttribute("pinned", PIN[self.pinned] or "") end
end

-- Hand every view x layer layout to the header (out of combat only).
function UI:Publish()
    local hdr = self.hdr
    if not hdr or InCombatLockdown() then return end
    hdr:SetAttribute("nkeys", #keys)
    hdr:SetAttribute("view", KB.db.ui.view)
    hdr:SetAttribute("pinned", PIN[self.pinned] or "")
    for _, c in ipairs(CODE) do
        for _, v in ipairs(KB.VIEWS) do
            local lay, h = self:ComputeLayout(v, c[2])
            for i = 1, #keys do
                local e = lay[i]
                hdr:SetAttribute("L" .. c[1] .. v .. ":" .. i, ("%.2f,%.2f,%d"):format(e.x, e.y, e.show and 1 or 0))
            end
            hdr:SetAttribute("H" .. c[1] .. v, h)
        end
    end
    KB.Debug:Log("publish", "layouts published for " .. #keys .. " keys")
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
    if not InCombatLockdown() then self.body:SetShown(not collapsed) end
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
    if self.trayFrame then
        self.trayFrame:ClearAllPoints()
        self.trayFrame:SetPoint(ui.anchor == "bottom" and "BOTTOMLEFT" or "TOPLEFT", f, ui.anchor == "bottom" and "BOTTOMLEFT" or "TOPLEFT", 0, 0)
        self.traySig = nil
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
    KB:ApplyBindings() -- while editing, clicking/pressing keys is switched off so nothing casts mid-arrangement
    self.chrome:SetShown(self.edit)
    if self.edit and not self.frame:IsShown() then self.frame:Show() end
    self:ApplySize()
    self:Refresh(true)
end

function UI:Refresh(force)
    if not self.frame or not self.frame:IsShown() then return end
    if self.hdr then
        local c, ap = self.hdr:GetAttribute("dbgclick"), self.hdr:GetAttribute("dbgapply")
        local key = tostring(c) .. "/" .. tostring(ap)
        if key ~= self.dbgKey then
            self.dbgKey = key
            KB.Debug:Log("secure", ("clicks=%s applies=%s moved=%s info=%s view=%s"):format(tostring(c), tostring(ap),
                tostring(self.hdr:GetAttribute("dbgmoved")), tostring(self.hdr:GetAttribute("dbginfo")), tostring(self.hdr:GetAttribute("view"))))
        end
    end
    local hv = self.hdr and self.hdr:GetAttribute("view")
    if hv and hv ~= KB.db.ui.view and KB.VIEW_LABEL[hv] then KB.db.ui.view = hv; self.sig = nil end
    self.layer = self:Layer()
    self.layerBtn:SetText(LAYER_LABEL[self.layer] or self.layer)
    self.viewBtn:SetText(KB.VIEW_LABEL[KB.db.ui.view])
    if KB.db.ui.collapsed then return end
    local view = KB.db.ui.view
    for i, k in ipairs(keys) do
        local a = KB:GetAction(bindKey(k))
        local ok, s = pcall(function() return a and KB:GetState(a) or {} end)
        if not ok then KB.Debug:Err("state " .. k.def.id, s); s = {} end
        local sys = (not a) and KB:GetSystemAction(bindKey(k)) or nil
        k.cycle = (KB:IsCycleKey(k.def.id) and self.layer == "" and not a) or nil
        local w = (k.cycle and KB.db.ui.alwaysShowCycle ~= false) or wanted(view, a, s, sys)
        local show = UI:GroupOn(k.def.group) and w
        k.visible = show
        k:SetAlpha(show and 1 or 0)
        local sok, serr = pcall(style, k, a, s, sys)
        if not sok then KB.Debug:Err("style " .. k.def.id, serr) end
        local tk = self.tray and self.tray[i]
        if tk then
            if view == "cooldown" and a and UI:GroupOn(k.def.group) then
                pcall(style, tk, a, s, nil)
                -- Cooldown times are secret in combat, so ask the tray key's own cooldown frame: it is shown
                -- while something is cooling down. The global cooldown doesn't count.
                local on = false
                pcall(function()
                    local g = s.gcd
                    if g ~= nil and issecretvalue and issecretvalue(g) then g = false end
                    on = (tk.cd:IsShown() and not g) and true or false
                end)
                tk.lit = on
                tk:SetAlpha(on and 1 or 0)
                tk:Show()
            else
                tk.lit = false
                tk:Hide()
            end
        end
    end
    self:LayoutTray(view)
    local u = KB.db.ui
    self:Reflow(table.concat({ view, self.layer, tostring(KB:RowUnits()), u.sizeMode, u.style, GAP(), tostring(u.keepPositions),
        tostring(u.alwaysShowCycle), tostring(u.showNav), tostring(u.showNumpad), self.rev or 0 }, "|"))
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
function UI:SetView(v)
    if InCombatLockdown() then KB:Print("Use the cycle key to change views in combat."); return end
    KB.db.ui.view = v; self.sig = nil
    if self.hdr then self.hdr:SetAttribute("view", v) end
    self:Refresh(true)
end
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
    if InCombatLockdown() then KB:Print("Can't collapse in combat."); return end
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

    self.body = CreateFrame("Frame", nil, f, "SecureHandlerBaseTemplate")
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
        UI.pinned = LAYERS[i % #LAYERS + 1]; UI:SyncPinned(); UI:Refresh(true)
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
                k.idx = #keys
                table.insert(rowOf[r], k)
            end
        end
    end

    self.trayFrame = CreateFrame("Frame", nil, f)
    self.trayFrame:SetSize(1, 1)
    self.trayFrame:SetFrameLevel(f:GetFrameLevel() + 5)
    self.tray = {}
    for i, k in ipairs(keys) do
        local tk = createKey(self.trayFrame, k.def, true)
        tk:SetSize(KB:KeyW(k.def) * UNIT - GAP(), UNIT - GAP())
        tk:SetAlpha(0)
        tk.lit = false
        self.tray[i] = tk
    end
    self.trayFrame:Hide()

    self.body:SetHeight(#KB.ROWS * UNIT)
    f:SetSize(KB:RowUnits() * UNIT, #KB.ROWS * UNIT)
    if not db.pos then
        local x = math.max(0, (UIParent:GetWidth() / db.scale - f:GetWidth()) / 2)
        db.pos = { x = x, bottom = 150, top = 150 + f:GetHeight() }
    end
    self:PlaceFrame()
    self:BuildSecure()

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed > 0.1 then elapsed = 0; UI:Refresh() end
    end)
    f:Show()
    self:Refresh(true)
end
