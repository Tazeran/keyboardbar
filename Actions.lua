-- Key -> action storage, secure proxy buttons + override bindings, action state queries.
local ADDON, KB = ...

-- Storage -------------------------------------------------------------------
function KB:GetAction(bk) return self:Profile().keys[bk] end
function KB:SetAction(bk, a) self:Profile().keys[bk] = a; self:ApplyBindings() end
function KB:ClearAction(bk) self:Profile().keys[bk] = nil; self:ApplyBindings() end

-- Secure keys ---------------------------------------------------------------
-- Each visual key is itself a SecureActionButton (like Blizzard action buttons), so clicking it
-- casts. Modifier layers use the template's "shift-" / "ctrl-" / "alt-" attribute prefixes, so the
-- same button serves Q, SHIFT-Q, CTRL-Q and ALT-Q for both clicks and key bindings.
local LAYERS = { { "", "" }, { "SHIFT-", "shift-" }, { "CTRL-", "ctrl-" }, { "ALT-", "alt-" } }
KB.keyFrames = KB.keyFrames or {}

local function clearAttrs(kf)
    for _, l in ipairs(LAYERS) do
        local p = l[2]
        kf:SetAttribute(p .. "type1", "") -- explicit empty type: a modifier click does nothing
        kf:SetAttribute(p .. "spell1", nil); kf:SetAttribute(p .. "item1", nil); kf:SetAttribute(p .. "macro1", nil)
    end
end

function KB:BlankKey(kf) clearAttrs(kf) end -- used while the cursor holds something

function KB:ApplyBindings()
    if KB.UI then KB.UI.rev = (KB.UI.rev or 0) + 1 end -- layouts depend on what is bound
    if InCombatLockdown() then self.pendingApply = true; KB.Debug:Log("bindings", "deferred (combat)"); return end
    self.pendingApply = false
    ClearOverrideBindings(self.owner)
    local keys = self:Profile().keys
    local n = 0
    for _ in pairs(keys) do n = n + 1 end
    KB.Debug:Log("bindings", "applied " .. n .. " actions, profile " .. self:ProfileName())
    for _, kf in ipairs(self.keyFrames) do
        clearAttrs(kf)
        for _, l in ipairs(LAYERS) do
            local a = keys[l[1] .. kf.def.id]
            if a then
                local p = l[2]
                if a.type == "spell" then kf:SetAttribute(p .. "type1", "spell"); kf:SetAttribute(p .. "spell1", a.name)
                elseif a.type == "item" then kf:SetAttribute(p .. "type1", "item"); kf:SetAttribute(p .. "item1", "item:" .. a.id)
                elseif a.type == "macro" then kf:SetAttribute(p .. "type1", "macro"); kf:SetAttribute(p .. "macro1", a.name) end
                SetOverrideBindingClick(self.owner, true, l[1] .. kf.def.id, kf:GetName(), "LeftButton")
            end
        end
    end
    -- Keys still bound to a hidden Blizzard bar slot do nothing (instead of casting what the old bar held).
    if self.db.ui.hideBars then
        for _, kf in ipairs(self.keyFrames) do
            for _, l in ipairs(LAYERS) do
                local bk = l[1] .. kf.def.id
                if not keys[bk] and not self:IsCycleKey(bk) and self.isHiddenBarAction(GetBindingAction(bk)) then
                    SetOverrideBindingClick(self.owner, true, bk, "KeyboardBarNoopBtn", "LeftButton")
                end
            end
        end
    end
    self.lastApply = GetTime()
    self:ApplySysClicks()
    -- Arrange mode (settings window open): keys are inert so dragging/clicking can't cast anything.
    if self.UI and self.UI.edit then
        for _, kf in ipairs(self.keyFrames) do clearAttrs(kf) end
    end
    -- Default view-cycle key (tilde) unless you put an action on it. Plain insecure button: it only changes display.
    local cks = { self.db.ui.cycleKey, self.db.ui.cycleKey2 == nil and "\\" or self.db.ui.cycleKey2 }
    for _, ck in ipairs(cks) do
        if ck and ck ~= "" and not keys[ck] then
            -- Goes through the cycle key's own (secure) button when it has one: that path fires once per press.
            local target = "KeyboardBarCycleHdr"
            for _, kf in ipairs(self.keyFrames) do if kf.def.id == ck then target = kf:GetName() end end
            SetOverrideBindingClick(self.owner, true, ck, target, "LeftButton")
        end
    end
end

CreateFrame("Button", "KeyboardBarNoopBtn", UIParent)

-- Cursor <-> action ---------------------------------------------------------
local function spellName(id) return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or (GetSpellInfo and GetSpellInfo(id)) end

function KB:ActionFromCursor()
    local t, a, b, c = GetCursorInfo()
    if t == "spell" then
        local id = c or a
        local name = spellName(id)
        if name then return { type = "spell", id = id, name = name } end
    elseif t == "item" then
        local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(a)) or tostring(a)
        return { type = "item", id = a, name = name }
    elseif t == "macro" then
        local name = GetMacroInfo(a)
        if name then return { type = "macro", id = a, name = name } end
    end
end

function KB:PickupAction(a)
    if a.type == "spell" then (C_Spell.PickupSpell or PickupSpell)(a.id)
    elseif a.type == "item" then (C_Item.PickupItem or PickupItem)(a.id)
    elseif a.type == "macro" then PickupMacro(a.name) end
end

-- State (display only; the game decides whether anything actually succeeds) ---
-- In combat this client hands back "secret" values for some queries: they can be passed to
-- display calls but not compared. So each query is isolated (one failure can't lose the icon)
-- and consumers must treat every field as possibly secret.
local function try(f, ...)
    local ok, a, b = pcall(f, ...)
    if ok then return a, b end
end

function KB:GetState(a)
    local s = {}
    if a.type == "spell" then
        s.icon = try(C_Spell.GetSpellTexture, a.name)
        local info = try(C_Spell.GetSpellCooldown, a.name)
        if type(info) == "table" then s.start, s.dur = info.startTime, info.duration; s.gcd = info.isOnGCD end
        if C_Spell.GetSpellCooldownDuration then s.durObj = try(C_Spell.GetSpellCooldownDuration, a.name) end
        s.usable, s.nomana = try(C_Spell.IsSpellUsable, a.name)
        s.range = try(C_Spell.IsSpellInRange, a.name, "target")
        s.active = try(C_Spell.IsCurrentSpell, a.id)
        s.cast = try(UnitCastingInfo, "player") or try(UnitChannelInfo, "player")
        s.castName = a.name
    elseif a.type == "item" then
        s.icon = try(C_Item.GetItemIconByID, a.id)
        s.count = try(C_Item.GetItemCount, a.id)
        s.start, s.dur = try(C_Container.GetItemCooldown, a.id)
    elseif a.type == "macro" then
        local _, icon = GetMacroInfo(a.name)
        s.icon = icon
    end
    return s
end

-- System (game) bindings ------------------------------------------------------
-- Read from the game's own binding table, so remapping elsewhere in WoW shows up here.
local sysCache = {}
function KB:WipeSystemCache() wipe(sysCache) end

local function isBarAction(a)
    return a:match("^ACTIONBUTTON") or a:match("^MULTIACTIONBAR") or a:match("^BONUSACTIONBUTTON") or a:match("^SHAPESHIFTBUTTON") or a:match("^EXTRAACTIONBUTTON")
end

-- Slots of the Blizzard bars we hide. Stance/pet/vehicle bindings are NOT here: those bars stay.
local function isHiddenBarAction(a) return a and (a:match("^ACTIONBUTTON") or a:match("^MULTIACTIONBAR")) and true or false end
KB.isHiddenBarAction = isHiddenBarAction

function KB:GetSystemAction(bk)
    local v = sysCache[bk]
    if v == nil then
        v = GetBindingAction(bk) or ""
        if v == "" or isHiddenBarAction(v) then v = false end -- hidden-bar slots count as empty keys
        sysCache[bk] = v
    end
    return v or nil
end

local PI = math.pi
local MOVE = {
    MOVEFORWARD = { "Fwd", PI / 2 }, MOVEBACKWARD = { "Back", 3 * PI / 2 },
    STRAFELEFT = { "Strafe", PI }, STRAFERIGHT = { "Strafe", 0 },
    TURNLEFT = { "Turn", PI }, TURNRIGHT = { "Turn", 0 },
}
local SHORT = {
    JUMP = "Jump", SITORSTAND = "Sit", TOGGLEAUTORUN = "Autorun", TOGGLEWORLDMAP = "Map", TOGGLEBACKPACK = "Bag",
    OPENALLBAGS = "Bags", TOGGLECHARACTER0 = "Char", TOGGLECHARACTER1 = "Rep", TOGGLECHARACTER2 = "Skills",
    TOGGLESPELLBOOK = "Spells", TOGGLETALENTS = "Talents", TOGGLEQUESTLOG = "Quests", TOGGLESOCIAL = "Social",
    TOGGLEGAMEMENU = "Menu", OPENCHAT = "Chat", REPLY = "Reply", NEXTVIEW = "Zoom+", PREVVIEW = "Zoom-",
    TARGETNEARESTENEMY = "Tgt", INTERACTTARGET = "Interact", TOGGLEMINIMAP = "Mini", TOGGLEFPS = "FPS",
    SCREENSHOT = "Screen", TOGGLEPETBOOK = "Pet", TOGGLEGUILDTAB = "Guild", TOGGLECHARACTER4 = "PvP", TOGGLEPROFESSIONBOOK = "Prof", TOGGLEFRIENDSTAB = "Friends",
}
local BLUE, GREY, BAR = { 0.1, 0.25, 0.5 }, { 0.2, 0.3, 0.3 }, { 0.2, 0.2, 0.25 }

-- returns shortLabel, arrowRotation|nil, tintColor
function KB:SystemInfo(action)
    local m = MOVE[action]
    if m then return m[1], m[2], BLUE end
    if SHORT[action] then return SHORT[action], nil, GREY end
    if isBarAction(action) then
        local n = action:match("(%d+)$")
        return "Bar" .. (n or ""), nil, BAR
    end
    return _G["BINDING_NAME_" .. action] or action, nil, GREY
end

-- Move the game binding on key `from` to key `to` (swapping if `to` already has one).
function KB:MoveSystemBinding(from, to)
    if InCombatLockdown() or from == to then return end
    local a = self:GetSystemAction(from)
    if not a then return end
    if self:GetAction(to) then self:Print("That key has one of your actions on it; clear it first."); return end
    local b = self:GetSystemAction(to)
    SetBinding(to, a)
    if b then SetBinding(from, b) else SetBinding(from) end
    local ok, err = pcall(function() SaveBindings(GetCurrentBindingSet()) end)
    KB.Debug:Log("rebind", ("%s %s -> %s saved=%s %s"):format(a, from, to, tostring(ok), ok and "" or tostring(err)))
    self:WipeSystemCache()
    self:Print(("%s moved to %s%s"):format((self:SystemInfo(a)), to, ok and "" or " (not saved: confirm in Key Bindings)"))
end

-- Remove the game binding on a key (middle-click on a system key).
function KB:ClearSystemBinding(bk)
    if InCombatLockdown() then return end
    local a = self:GetSystemAction(bk)
    if not a then return end
    self.db.unbound = self.db.unbound or {}
    self.db.unbound[bk] = a -- remembered so a middle-click on the empty key can restore it
    SetBinding(bk)
    local ok, err = pcall(function() SaveBindings(GetCurrentBindingSet()) end)
    KB.Debug:Log("unbind", ("%s %s saved=%s %s"):format(a, bk, tostring(ok), ok and "" or tostring(err)))
    self:WipeSystemCache()
    self:Print(("%s unbound from %s. Middle-click the empty key to restore it."):format((self:SystemInfo(a)), bk))
end

-- Stock WoW bindings we can restore even if this addon didn't remove them.
local STOCK = { F12 = "TOGGLEBACKPACK", F11 = "TOGGLEBAG1", F10 = "TOGGLEBAG2", F9 = "TOGGLEBAG3", F8 = "TOGGLEBAG4" }

-- Middle-click on an empty key: put back what we unbound there, else the stock binding if we know it.
function KB:RestoreBinding(bk)
    if InCombatLockdown() then return end
    local a = (self.db.unbound and self.db.unbound[bk]) or STOCK[bk]
    if not a or self.isHiddenBarAction(a) then return end
    if GetBindingAction(bk) ~= "" and GetBindingAction(bk) ~= nil then return end -- key already bound
    SetBinding(bk, a)
    local ok, err = pcall(function() SaveBindings(GetCurrentBindingSet()) end)
    if self.db.unbound then self.db.unbound[bk] = nil end
    KB.Debug:Log("restore", ("%s %s saved=%s %s"):format(a, bk, tostring(ok), ok and "" or tostring(err)))
    self:WipeSystemCache()
    self:Print(("%s restored on %s."):format((self:SystemInfo(a)), bk))
    return true
end

-- Icons for system keys, from the game's own art. Every path is checked at runtime (a texture that
-- doesn't resolve to a file id is ignored), so a wrong guess just falls back to the text label.
local I = "Interface\\Icons\\"
KB.SYS_ICON = {
    TOGGLEWORLDMAP = I .. "INV_Misc_Map_01",
    TOGGLEBACKPACK = I .. "INV_Misc_Bag_08", OPENALLBAGS = I .. "INV_Misc_Bag_08",
    TOGGLEBAG1 = I .. "INV_Misc_Bag_08", TOGGLEBAG2 = I .. "INV_Misc_Bag_08", TOGGLEBAG3 = I .. "INV_Misc_Bag_08", TOGGLEBAG4 = I .. "INV_Misc_Bag_08",
    TOGGLECHARACTER0 = I .. "INV_Shirt_White_01",
    TOGGLECHARACTER1 = I .. "INV_Shirt_GuildTabard_01",
    TOGGLECHARACTER2 = I .. "Trade_Engineering",
    TOGGLESPELLBOOK = I .. "INV_Misc_Book_09",
    TOGGLETALENTS = I .. "Ability_Marksmanship",
    TOGGLEQUESTLOG = I .. "INV_Misc_Note_01",
    TOGGLEGUILDTAB = I .. "INV_Shirt_GuildTabard_01",
    TOGGLEGAMEMENU = I .. "INV_Misc_Gear_01",
    OPENCHAT = I .. "INV_Letter_15",
    SCREENSHOT = I .. "INV_Misc_Spyglass_02",
    JUMP = I .. "Spell_Nature_Levitation",
    TOGGLEAUTORUN = I .. "Ability_Druid_Dash",
    TARGETNEARESTENEMY = I .. "Ability_Hunter_SniperShot",
    TOGGLEPETBOOK = I .. "Ability_Hunter_BeastCall",
    TOGGLEPROFESSIONBOOK = I .. "Trade_BlackSmithing",
    TOGGLESOCIAL = { I .. "INV_Letter_03", I .. "INV_Misc_GroupNeedMore", I .. "INV_Misc_Note_02" },
    TOGGLEFRIENDSTAB = { I .. "INV_Letter_03", I .. "INV_Misc_GroupNeedMore" },
    TOGGLECHARACTER4 = { I .. "Achievement_Arena_2v2_1", I .. "Achievement_PVP_A_01", I .. "INV_Misc_Bone_HumanSkull_01" },
}

local iconOK = {}
local probe
function KB:SystemIcon(action)
    local entry = KB.SYS_ICON[action]
    if not entry then return nil end
    for _, path in ipairs(type(entry) == "table" and entry or { entry }) do
        local v = iconOK[path]
        if v == nil then
            probe = probe or UIParent:CreateTexture()
            probe:SetTexture(path)
            local r = probe:GetTexture()
            v = type(r) == "number" and r or false
            iconOK[path] = v
        end
        if v then return path end
    end
    return nil
end

-- Unprotected window toggles we can call directly from an insecure click.
function KB:RunSystem(action, down)
    local f = KB.SYSFUNC and KB.SYSFUNC[action]
    if f and down then local ok, err = pcall(f); if not ok then KB.Debug:Err("runsys " .. action, err) end end
end

-- Secure clicks for system keys -----------------------------------------------
-- Calling the game's window toggles from addon code gets "blocked" (taint). Instead the key is a
-- secure button that clicks Blizzard's own micro/bag button, which runs untainted.
local SYSBTN = {
    TOGGLECHARACTER0 = { "CharacterMicroButton" },
    TOGGLESPELLBOOK = { "PlayerSpellsMicroButton", "SpellbookMicroButton" },
    TOGGLETALENTS = { "PlayerSpellsMicroButton", "TalentMicroButton" },
    TOGGLEPROFESSIONBOOK = { "ProfessionMicroButton" },
    TOGGLECHARACTER4 = { "PVPMicroButton", "HonorMicroButton" },
    TOGGLEQUESTLOG = { "QuestLogMicroButton" },
    TOGGLEGUILDTAB = { "GuildMicroButton" },
    TOGGLESOCIAL = { "GuildMicroButton", "SocialsMicroButton" },
    TOGGLEACHIEVEMENT = { "AchievementMicroButton" },
    TOGGLECOLLECTIONS = { "CollectionsMicroButton" },
    TOGGLEENCOUNTERJOURNAL = { "EJMicroButton" },
    TOGGLEGROUPFINDER = { "LFDMicroButton" },
    TOGGLEGAMEMENU = { "MainMenuMicroButton" },
    TOGGLEBACKPACK = { "MainMenuBarBackpackButton" }, OPENALLBAGS = { "MainMenuBarBackpackButton" },
}
KB.SYSBTN = SYSBTN
-- Slash commands a secure button may run: Jump, target nearest enemy, sit.
local SYSMACRO = { JUMP = "/jump", TARGETNEARESTENEMY = "/targetenemy", SITORSTAND = "/sit" }
-- Plain functions that aren't protected (opened from our insecure click handler).
KB.SYSFUNC = {
    TOGGLEWORLDMAP = function() if ToggleWorldMap then ToggleWorldMap() end end,
    TOGGLECHARACTER2 = function() if ToggleCharacter then ToggleCharacter("SkillFrame") end end,
}
function KB:SysClickable(action) return action and (self:SysButton(action) or SYSMACRO[action]) and true or false end
function KB:SysButton(action)
    local list = action and SYSBTN[action]
    if not list then return nil end
    for _, n in ipairs(list) do if _G[n] then return _G[n], n end end
end

function KB:ApplySysClicks()
    if InCombatLockdown() then self.pendingApply = true; return end
    local keys = self:Profile().keys
    for _, kf in ipairs(self.keyFrames) do
        local anySys = false
        for _, l in ipairs(LAYERS) do
            local bk = l[1] .. kf.def.id
            if not keys[bk] and l[1] == "" and self:IsCycleKey(kf.def.id) and self.UI and self.UI.hdr then
                -- the view-cycle key: a secure click on the layout header, so it works (and re-lays-out) in combat
                kf:SetAttribute("type1", "click"); kf:SetAttribute("clickbutton1", self.UI.hdr); kf:SetAttribute("macrotext1", nil)
            elseif not keys[bk] then
                local sa = self:GetSystemAction(bk)
                local btn = self:SysButton(sa)
                if btn then
                    kf:SetAttribute(l[2] .. "type1", "click"); kf:SetAttribute(l[2] .. "clickbutton1", btn); kf:SetAttribute(l[2] .. "macrotext1", nil); anySys = true
                elseif sa and SYSMACRO[sa] then
                    kf:SetAttribute(l[2] .. "type1", "macro"); kf:SetAttribute(l[2] .. "macrotext1", SYSMACRO[sa]); kf:SetAttribute(l[2] .. "clickbutton1", nil)
                else
                    kf:SetAttribute(l[2] .. "type1", ""); kf:SetAttribute(l[2] .. "clickbutton1", nil)
                end
            else
                kf:SetAttribute(l[2] .. "clickbutton1", nil)
            end
        end
    end
end
