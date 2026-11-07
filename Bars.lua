-- Optionally hides Blizzard's own action bars (the keyboard replaces them).
-- Every frame is looked up by name and skipped if this client doesn't have it. Out of combat only.
-- Turning the option off needs /reload to bring the bars back.
local ADDON, KB = ...

local hider = CreateFrame("Frame")
hider:Hide()

local BARS = { "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7" }
-- Stance, pet, possess and vehicle/override bars are deliberately left visible: they aren't
-- ordinary hotbar slots. Add their frame names here (or behind an option) to hide them too.
local ART = { "MainMenuBarArtFrame", "MainMenuBarArtFrameBackground", "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
    "MainMenuBarPageNumber", "ActionBarUpButton", "ActionBarDownButton", "MainMenuBarTexture0", "MainMenuBarTexture1",
    "MainMenuBarTexture2", "MainMenuBarTexture3" }

function KB:HideBlizzardBars()
    if InCombatLockdown() or not self.db.ui.hideBars then return end
    local function hide(name)
        local f = _G[name]
        if f and f.SetParent then pcall(f.SetParent, f, hider) end
    end
    for _, n in ipairs(BARS) do hide(n) end
    for _, n in ipairs(ART) do hide(n) end
    for i = 1, 12 do hide("ActionButton" .. i) end -- main bar buttons only; micro menu / bags are left alone
    if MainActionBar then pcall(MainActionBar.SetAlpha, MainActionBar, 0) end
end
