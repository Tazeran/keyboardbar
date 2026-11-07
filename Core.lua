-- KeyboardBar core: namespace, saved variables, profiles, events, slash commands.
local ADDON, KB = ...
_G.KeyboardBar = KB

KB.owner = CreateFrame("Frame", "KeyboardBarOwner", UIParent) -- owns override bindings
KB.VIEWS = { "full", "bound", "assigned", "cooldown" }
KB.VIEW_LABEL = { full = "Full", bound = "Bound", assigned = "Play", cooldown = "Cooldowns" }

BINDING_HEADER_KEYBOARDBAR = "Keyboard Bar"
BINDING_NAME_KEYBOARDBAR_CYCLEVIEW = "Cycle view (Full / Assigned / Spells / On cooldown)"
BINDING_NAME_KEYBOARDBAR_TOGGLE = "Show / hide keyboard"
BINDING_NAME_KEYBOARDBAR_COLLAPSE = "Collapse / expand keyboard"
function KeyboardBar_CycleView() if KB.UI.frame then KB.UI:CycleView() end end
function KeyboardBar_Toggle() if KB.UI.frame then KB.UI:Toggle() end end
function KeyboardBar_Collapse() if KB.UI.frame then KB.UI:ToggleCollapse() end end

local DEFAULTS = { scale = 1, view = "full", collapsed = false, showNames = false, anchor = "top", keepPositions = false, cycleKey = "`", gap = 3, sizeMode = "keyboard", style = "flat", showNav = true, showNumpad = true, hideBars = true, point = { "CENTER", "UIParent", "CENTER", 0, -200 } }

local function charKey() return UnitName("player") .. "-" .. GetRealmName() end

function KB:Print(msg) print("|cff66ccffKeyboardBar|r: " .. tostring(msg)) end

local function initDB()
    KeyboardBarDB = KeyboardBarDB or {}
    local db = KeyboardBarDB
    db.ui = db.ui or {}
    for k, v in pairs(DEFAULTS) do if db.ui[k] == nil then db.ui[k] = v end end
    if not KB.VIEW_LABEL[db.ui.view] then db.ui.view = "full" end
    db.profiles = db.profiles or {}
    db.chars = db.chars or {}
    local ck = charKey()
    db.chars[ck] = db.chars[ck] or { profile = ck }
    KB.db = db
end

-- Profiles ------------------------------------------------------------------
function KB:ProfileName() return self.db.chars[charKey()].profile end

function KB:Profile()
    local name = self:ProfileName()
    local p = self.db.profiles[name]
    if not p then p = { keys = {} }; self.db.profiles[name] = p end
    return p
end

function KB:SetProfile(name)
    if not name or name == "" then return end
    self.db.chars[charKey()].profile = name
    self:Profile() -- create if missing
    self:ApplyBindings()
    if self.UI then self.UI:Refresh(true) end
end

function KB:ListProfiles()
    local t = {}
    for n in pairs(self.db.profiles) do t[#t + 1] = n end
    table.sort(t)
    return t
end

-- Events --------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("UPDATE_BINDINGS")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        initDB()
        KB.UI:Build()
        KB:ApplyBindings()
        KB:HideBlizzardBars()
    elseif event == "UPDATE_BINDINGS" then
        if KB.WipeSystemCache then KB:WipeSystemCache() end
        -- re-apply (bar keys may have been rebound); ignore the echo of our own override changes
        if KB.UI and KB.UI.frame and not (KB.lastApply and GetTime() - KB.lastApply < 1) then KB:ApplyBindings() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if KB.pendingApply then KB:ApplyBindings() end
        if KB.UI and KB.UI.frame then KB.UI:Refresh(true) end
    end
end)

-- Slash commands ------------------------------------------------------------
SLASH_KEYBOARDBAR1, SLASH_KEYBOARDBAR2 = "/kb", "/keyboardbar"
SlashCmdList.KEYBOARDBAR = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    local UI = KB.UI
    if cmd == "" or cmd == "config" or cmd == "options" then
        KB.Config:Toggle()
    elseif cmd == "toggle" or cmd == "show" or cmd == "hide" then
        UI:Toggle()
    elseif cmd == "view" then
        arg = arg:lower()
        if KB.VIEW_LABEL[arg] then UI:SetView(arg) else UI:CycleView() end
    elseif cmd == "scale" and tonumber(arg) then
        UI:SetScale(tonumber(arg))
    elseif cmd == "nav" or cmd == "numpad" then
        local key = cmd == "nav" and "showNav" or "showNumpad"
        KB.db.ui[key] = not KB.db.ui[key]
        UI:Relayout()
        KB:Print((cmd == "nav" and "Navigation/arrow cluster " or "Numpad ") .. (KB.db.ui[key] and "shown." or "hidden."))
    elseif cmd == "sizes" then
        KB.db.ui.sizeMode = KB:IsSquare() and "keyboard" or "square"
        UI:Relayout()
        KB:Print("Key sizes: " .. (KB:IsSquare() and "all squares" or "keyboard-style widths"))
    elseif cmd == "snapshot" then
        KB.Debug:Snapshot("manual"); KB.Debug:Log("manual", "snapshot taken")
        KB:Print("Debug snapshot saved in memory. Type /reload to write it to disk.")
    elseif cmd == "clearlog" then
        wipe(KB.db.debug.log); KB:Print("Debug log cleared.")
    elseif cmd == "debug" then
        local d = KB.db.debug; d.enabled = not d.enabled
        KB:Print("Debug log " .. (d.enabled and "on" or "off"))
    elseif cmd == "gap" then
        local presets = { tight = 1, normal = 3, loose = 6 }
        local order, cur = { 1, 3, 6 }, KB.db.ui.gap or 3
        local new = presets[arg:lower()] or tonumber(arg)
        if not new then
            for i, v in ipairs(order) do if v == cur then new = order[i % #order + 1] end end
            new = new or 3
        end
        KB.db.ui.gap = math.max(0, math.min(10, new))
        UI:Relayout()
        KB:Print("Key gap: " .. KB.db.ui.gap .. "px (tight / normal / loose = 1 / 3 / 6)")
    elseif cmd == "style" then
        KB.db.ui.style = KB.db.ui.style == "blizzard" and "flat" or "blizzard"
        UI:Relayout()
        KB:Print("Key style: " .. KB.db.ui.style)
    elseif cmd == "bars" then
        KB.db.ui.hideBars = not KB.db.ui.hideBars
        if KB.db.ui.hideBars then KB:HideBlizzardBars(); KB:Print("Blizzard action bars hidden.")
        else KB:Print("Blizzard bars will return after /reload.") end
    elseif cmd == "cyclekey" then
        KB.db.ui.cycleKey = (arg == "" or arg:lower() == "off") and "" or arg:upper()
        KB:ApplyBindings()
        KB:Print("View-cycle key: " .. (KB.db.ui.cycleKey ~= "" and KB.db.ui.cycleKey or "none"))
    elseif cmd == "profile" then
        if arg == "" then
            KB:Print("Current: " .. KB:ProfileName() .. "  |  All: " .. table.concat(KB:ListProfiles(), ", "))
        else
            KB:SetProfile(arg); KB:Print("Profile: " .. arg)
        end
    elseif cmd == "reset" then
        KB:Profile().keys = {}
        KB:ApplyBindings(); UI:Refresh(true)
        KB:Print("Cleared all keys in profile '" .. KB:ProfileName() .. "'.")
    else
        KB:Print("/kb  settings window (open/close)  |  /kb toggle  show/hide keyboard  |  /kb view [full|bound|assigned|cooldown]  |  /kb scale <n>  |  /kb cyclekey <KEY|off>")
        KB:Print("/kb gap [tight|normal|loose]  |  /kb sizes (keyboard/squares)  |  /kb style (flat/blizzard)  |  /kb nav  |  /kb numpad  |  /kb bars (hide Blizzard bars)  |  /kb profile [name]  |  /kb reset")
        KB:Print("Drag spells/items/macros onto keys. Shift+Right-click a key clears it. Hold Shift/Ctrl/Alt to see those layers.")
    end
end
