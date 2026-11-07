-- Debug recorder. Everything lands in KeyboardBarDB.debug, which WoW writes to disk on /reload or logout:
--   <WoW>\_forever_\WTF\Account\<account>\SavedVariables\KeyboardBarDB.lua
-- Contains: captured Lua errors (ours only), swallowed pcall errors, a short event log, and a state snapshot
-- (client build, API availability, whether Blizzard frames exist, every key's size/position/action/attributes).
local ADDON, KB = ...
local D = {}
KB.Debug = D

local MAX = 300
local pending, seen = {}, {}

local function buf()
    if KB.db then KB.db.debug = KB.db.debug or { log = {} }; KB.db.debug.log = KB.db.debug.log or {}; return KB.db.debug.log end
    return pending
end

function D:Log(kind, msg)
    if KB.db and KB.db.debug and KB.db.debug.enabled == false then return end
    local b = buf()
    b[#b + 1] = { t = date("%H:%M:%S"), kind = kind, msg = tostring(msg), combat = InCombatLockdown() and true or nil }
    if #b > MAX then table.remove(b, 1) end
end

-- Log an error once per distinct message (so a per-frame error can't flood the buffer).
function D:Err(where, err)
    local key = where .. tostring(err)
    if seen[key] then return end
    seen[key] = true
    self:Log("error", where .. ": " .. tostring(err))
end

function D:Init()
    KB.db.debug = KB.db.debug or {}
    local d = KB.db.debug
    if d.enabled == nil then d.enabled = true end
    d.log = d.log or {}
    d.log[#d.log + 1] = { t = date("%H:%M:%S"), kind = "session", msg = "---- login ----" }
    for _, e in ipairs(pending) do d.log[#d.log + 1] = e end
    wipe(pending)
    while #d.log > MAX do table.remove(d.log, 1) end
end

-- Capture Lua errors that mention this addon, then pass them on to whatever handler was installed.
local prev = geterrorhandler()
seterrorhandler(function(err)
    local s = tostring(err)
    if s:find("KeyboardBar", 1, true) then
        D:Err("lua", s .. "\n" .. (debugstack and debugstack(2, 8, 0) or ""))
    end
    if prev then return prev(err) end
end)

-- Snapshot -----------------------------------------------------------------
local function resolve(path)
    local v = _G
    for part in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then return false end
        v = v[part]
    end
    return type(v)
end

local API = {
    "C_Spell.GetSpellCooldown", "C_Spell.GetSpellTexture", "C_Spell.GetSpellName", "C_Spell.IsSpellUsable",
    "C_Spell.IsSpellInRange", "C_Spell.IsCurrentSpell", "C_Spell.PickupSpell", "C_Item.GetItemCount",
    "C_Item.GetItemIconByID", "C_Item.GetItemNameByID", "C_Item.PickupItem", "C_Container.GetItemCooldown",
    "GetCursorInfo", "RunBinding", "ToggleWorldMap", "ToggleCharacter", "GetBindingAction", "SetBinding", "SaveBindings", "GetCurrentBindingSet",
    "SetOverrideBindingClick", "UnitCastingInfo", "CreateFrame", "BackdropTemplateMixin", "GameTooltip.SetSpellByID",
}
local FRAMES = { "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
    "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar", "PossessActionBar", "OverrideActionBar",
    "MicroMenu", "MicroButtonAndBagsBar", "ActionButton1", "MainMenuBarArtFrame", "BagsBar" }
local TEXTURES = { "Interface\\Buttons\\UI-Quickslot", "Interface\\Buttons\\UI-Quickslot2", "Interface\\ChatFrame\\ChatFrameExpandArrow",
    "Interface\\Buttons\\ButtonHilight-Square", "Interface\\Buttons\\UI-Quickslot-Depress" }

function D:Snapshot(reason)
    if not KB.db then return end
    local s = { reason = reason, time = date("%Y-%m-%d %H:%M:%S"), combat = InCombatLockdown() and true or false }
    local ver, build, _, toc = GetBuildInfo()
    s.client = { version = ver, build = build, toc = toc }
    s.profile = KB:ProfileName()
    s.ui = {}
    for k, v in pairs(KB.db.ui) do if type(v) ~= "table" then s.ui[k] = v end end
    s.api = {}
    for _, p in ipairs(API) do s.api[p] = resolve(p) end
    s.frames = {}
    for _, n in ipairs(FRAMES) do
        local f = _G[n]
        s.frames[n] = f and (("exists shown=%s parent=%s"):format(tostring(f.IsShown and f:IsShown()), tostring(f.GetParent and f:GetParent() and f:GetParent():GetName()))) or "missing"
    end
    -- Texture probe: create a throwaway texture and see whether SetTexture + GetTexture round-trips.
    s.textures = {}
    local probe = UIParent:CreateTexture()
    for _, p in ipairs(TEXTURES) do
        probe:SetTexture(p)
        s.textures[p] = tostring(probe:GetTexture() ~= nil and probe:GetTexture() or "nil")
    end
    s.sysIcons = {}
    for action, path in pairs(KB.SYS_ICON or {}) do s.sysIcons[action] = KB:SystemIcon(action) or ("MISSING " .. tostring(type(path) == "table" and path[1] or path)) end
    s.skills = KB:SkillList()
    s.sysButtons = {}
    for action, list in pairs(KB.SYSBTN or {}) do
        local _, n = KB:SysButton(action)
        s.sysButtons[action] = n or ("MISSING " .. table.concat(list, "/"))
    end
    s.keys = {}
    local UI = KB.UI
    if UI and UI.keys then
        local body = UI.body
        for _, k in ipairs(UI.keys) do
            local w, h = k:GetSize()
            local left, top = k:GetLeft(), k:GetTop()
            local bl, bt = body:GetLeft(), body:GetTop()
            local e = {
                id = k.def.id, size = ("%dx%d"):format(w + 0.5, h + 0.5), shown = k:IsShown() and true or false,
                alpha = k:GetAlpha(), group = k.def.group,
                pos = (left and bl) and ("%d,%d"):format(left - bl + 0.5, top - bt - 0.5) or "nil",
                action = k.action and (k.action.type .. ":" .. k.action.name) or nil, sys = k.sys,
            }
            if k.GetAttribute then e.type1 = k:GetAttribute("type1"); e.spell1 = k:GetAttribute("spell1") end
            s.keys[#s.keys + 1] = e
        end
    end
    s.frame = {}
    if UI and UI.frame then
        local w, h = UI.frame:GetSize()
        s.frame = { size = ("%dx%d"):format(w + 0.5, h + 0.5), shown = UI.frame:IsShown() and true or false, scale = UI.frame:GetScale(),
            point = { UI.frame:GetPoint() } }
        s.frame.point[2] = nil
    end
    s.profileKeys = {}
    for bk, a in pairs(KB:Profile().keys) do s.profileKeys[bk] = a.type .. ":" .. a.name end
    KB.db.debug = KB.db.debug or {}
    KB.db.debug.snapshot = s
    return s
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("ADDON_ACTION_BLOCKED")
ev:RegisterEvent("ADDON_ACTION_FORBIDDEN")
ev:SetScript("OnEvent", function(_, event, addon, fn)
    if event == "PLAYER_LOGIN" then
        -- Core's PLAYER_LOGIN handler (registered earlier) has already built db and UI by now.
        C_Timer.After(3, function() D:Init(); D:Snapshot("login+3s") end)
    elseif event == "PLAYER_LOGOUT" then
        D:Snapshot("logout")
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if addon == "KeyboardBar" and KB.db then D:Log("blocked", tostring(fn)) end
    elseif KB.db then
        D:Log("combat", event == "PLAYER_REGEN_DISABLED" and "entered combat" or "left combat")
    end
end)
