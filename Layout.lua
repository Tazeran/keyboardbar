-- Full keyboard geometry (ANSI main block + navigation cluster + numpad).
-- Widths are in key units. Entries are keys {id,label,w,fixed,group} or gaps {gap=n,group=g}.
-- Keys/gaps with a group ("Nav" or "Numpad") are dropped when that option is off.
local ADDON, KB = ...

local function K(id, label, w, fixed, group) return { id = id, label = label or id, w = w or 1, fixed = fixed, group = group } end
local function G(n, group) return { gap = n, group = group } end
local function chars(s) local t = {} for c in s:gmatch(".") do t[#t + 1] = K(c) end return t end
local function join(...)
    local out = {}
    for _, part in ipairs({ ... }) do
        if part.id or part.gap then out[#out + 1] = part
        else for _, v in ipairs(part) do out[#out + 1] = v end end
    end
    return out
end
local function fkeys(a, b) local t = {} for i = a, b do t[#t + 1] = K("F" .. i) end return t end
local function N(id, label, w, fixed) return K("NUMPAD" .. id, label, w, fixed, "Numpad") end
local function NAV(id, label) return K(id, label, 1, false, "Nav") end

KB.ROWS = {
    join(K("ESCAPE", "Esc", 1, true), G(1), fkeys(1, 4), G(0.5), fkeys(5, 8), G(0.5), fkeys(9, 12)),
    join(chars("`1234567890-="), K("BACKSPACE", "Bksp", 2),
        G(0.5, "Nav"), NAV("INSERT", "Ins"), NAV("HOME", "Home"), NAV("PAGEUP", "PgUp"),
        G(0.5, "Numpad"), K("NUMLOCK", "NumLk", 1, true, "Numpad"), N("DIVIDE", "N/"), N("MULTIPLY", "N*"), N("MINUS", "N-")),
    join(K("TAB", "Tab", 1.5), chars("QWERTYUIOP[]"), K("\\", "\\", 1.5),
        G(0.5, "Nav"), NAV("DELETE", "Del"), NAV("END", "End"), NAV("PAGEDOWN", "PgDn"),
        G(0.5, "Numpad"), N("7", "N7"), N("8", "N8"), N("9", "N9"), N("PLUS", "N+")),
    join(K("CAPSLOCK", "Caps", 1.75), chars("ASDFGHJKL;'"), K("ENTER", "Enter", 2.25, true),
        G(0.5, "Nav"), G(3, "Nav"),
        G(0.5, "Numpad"), N("4", "N4"), N("5", "N5"), N("6", "N6")),
    join(K("LSHIFT", "Shift", 2.25, true), chars("ZXCVBNM,./"), K("RSHIFT", "Shift", 2.75, true),
        G(0.5, "Nav"), G(1, "Nav"), NAV("UP", "Up"), G(1, "Nav"),
        G(0.5, "Numpad"), N("1", "N1"), N("2", "N2"), N("3", "N3"), N("ENTER", "Ent", 1, true)),
    join(K("LCTRL", "Ctrl", 1.5, true), K("LALT", "Alt", 1.5, true), K("SPACE", "Space", 9), K("RALT", "Alt", 1.5, true), K("RCTRL", "Ctrl", 1.5, true),
        G(0.5, "Nav"), NAV("LEFT", "Left"), NAV("DOWN", "Down"), NAV("RIGHT", "Right"),
        G(0.5, "Numpad"), N("0", "N0", 2), N("DECIMAL", "N.")),
}

-- Square mode: every key is 1x1. These keys get extra leading space so the rows still stagger
-- like a keyboard (and Space sits roughly in the middle).
local SQ_PAD = { A = 0.25, Z = 0.75, SPACE = 4, RALT = 4 }
for _, row in ipairs(KB.ROWS) do
    for _, d in ipairs(row) do if d.id and SQ_PAD[d.id] then d.sqPad = SQ_PAD[d.id] end end
end

function KB:IsSquare() return self.db and self.db.ui.sizeMode == "square" end
function KB:KeyW(def) return self:IsSquare() and 1 or def.w end
function KB:KeyPad(def) return self:IsSquare() and def.sqPad or 0 end

local function groupOn(ui, g) return g == nil or ui["show" .. g] ~= false end

-- Total width in key units for the current options (independent of which keys are visible).
function KB:RowUnits()
    local ui = self.db and self.db.ui or {}
    local best = 0
    for _, row in ipairs(self.ROWS) do
        local x = 0
        for _, d in ipairs(row) do
            if groupOn(ui, d.group or (d.gap and d.group)) then
                if d.gap then x = x + d.gap else x = x + self:KeyPad(d) + self:KeyW(d) end
            end
        end
        if x > best then best = x end
    end
    return best
end
