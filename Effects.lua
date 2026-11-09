-- Key effects: sparkle bursts, glows and flashes drawn on a key's own overlay (never on the protected key
-- itself), so they work in combat too. Every effect has its own switch in /kb.
--   new ability   : sparkle burst, then a pulsing glow until you hover or press the key
--   new rank      : a quick sparkle
--   cooldown ready: a flash when a real cooldown ends
--   range/resource: a brief red / blue flash when the spell goes out of range / out of mana
--   active spell  : a pulsing glow while the spell is the current one
local ADDON, KB = ...
local FX = { newGlow = {}, pending = {} }
KB.FX = FX

local GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
local STAR = "Interface\\Cooldown\\star4"
local PING = "Interface\\Cooldown\\ping4"

function FX:Opt(name)
    local u = KB.db and KB.db.ui
    return u ~= nil and u.fxOn ~= false and u[name] ~= false
end

-- Build the overlay for a key (once, when the key is created).
function FX:Attach(k)
    local f = CreateFrame("Frame", nil, k)
    f:SetAllPoints(k)
    f:SetFrameLevel(k:GetFrameLevel() + 12)
    f:EnableMouse(false)
    k.fx = f

    local glow = f:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(GLOW); glow:SetBlendMode("ADD")
    glow:SetPoint("TOPLEFT", -12, 12); glow:SetPoint("BOTTOMRIGHT", 12, -12)
    glow:SetAlpha(0); glow:Hide()
    f.glow = glow

    local spark = f:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(STAR); spark:SetBlendMode("ADD"); spark:SetVertexColor(1, 0.9, 0.4)
    spark:SetPoint("TOPLEFT", -14, 14); spark:SetPoint("BOTTOMRIGHT", 14, -14)
    spark:SetAlpha(0); spark:Hide()
    f.spark = spark

    local ping = f:CreateTexture(nil, "OVERLAY")
    ping:SetTexture(PING); ping:SetBlendMode("ADD")
    ping:SetPoint("TOPLEFT", -10, 10); ping:SetPoint("BOTTOMRIGHT", 10, -10)
    ping:SetAlpha(0); ping:Hide()
    f.ping = ping

    pcall(function() -- sparkle burst: fade in, turn, fade out
        local g = spark:CreateAnimationGroup()
        local a1 = g:CreateAnimation("Alpha"); a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.15); a1:SetOrder(1)
        local r = g:CreateAnimation("Rotation"); r:SetDegrees(-90); r:SetDuration(1.0); r:SetOrder(1)
        local a2 = g:CreateAnimation("Alpha"); a2:SetFromAlpha(1); a2:SetToAlpha(0); a2:SetDuration(0.85); a2:SetOrder(2)
        g:SetScript("OnPlay", function() spark:SetAlpha(1); spark:Show() end)
        g:SetScript("OnFinished", function() spark:SetAlpha(0); spark:Hide() end)
        f.burst = g
    end)
    pcall(function() -- ping flash (cooldown ready / range / resource)
        local g = ping:CreateAnimationGroup()
        local a1 = g:CreateAnimation("Alpha"); a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.12); a1:SetOrder(1)
        local a2 = g:CreateAnimation("Alpha"); a2:SetFromAlpha(1); a2:SetToAlpha(0); a2:SetDuration(0.45); a2:SetOrder(2)
        g:SetScript("OnPlay", function() ping:SetAlpha(1); ping:Show() end)
        g:SetScript("OnFinished", function() ping:SetAlpha(0); ping:Hide() end)
        f.flash = g
    end)
    pcall(function() -- steady pulse for the glow border
        local g = glow:CreateAnimationGroup()
        g:SetLooping("BOUNCE")
        local a = g:CreateAnimation("Alpha"); a:SetFromAlpha(0.35); a:SetToAlpha(1); a:SetDuration(0.8)
        f.pulse = g
    end)
end

local function visible(k) return k.fx and k:IsShown() and k:GetEffectiveAlpha() > 0.05 end

function FX:Burst(k)
    if not visible(k) or not k.fx.burst then return end
    pcall(function() k.fx.burst:Stop(); k.fx.burst:Play() end)
end

function FX:Flash(k, r, g, b)
    if not visible(k) or not k.fx.flash then return end
    pcall(function()
        k.fx.ping:SetVertexColor(r, g, b)
        k.fx.flash:Stop(); k.fx.flash:Play()
    end)
end

function FX:SetGlow(k, on, r, g, b)
    local f = k.fx
    if not f then return end
    if on then
        f.glow:SetVertexColor(r or 1, g or 0.85, b or 0.3)
        if not k.fxGlowOn then
            k.fxGlowOn = true
            f.glow:Show(); f.glow:SetAlpha(1)
            if f.pulse then pcall(function() f.pulse:Play() end) end
        end
    elseif k.fxGlowOn then
        k.fxGlowOn = nil
        if f.pulse then pcall(function() f.pulse:Stop() end) end
        f.glow:SetAlpha(0); f.glow:Hide()
    end
end

-- Called from UI's style() for every key that holds an ability.
function FX:Observe(k, a, s)
    if not k.fx then return end
    local id = k.def.id
    if k.fxName ~= (a and a.name) then -- key reassigned: forget its history
        k.fxName = a and a.name
        k.fxCd, k.fxRange, k.fxMana = nil, nil, nil
    end
    if not a or not self:Opt("fxOn") then self:SetGlow(k, false); return end

    local want, r, g, b = false
    if FX.newGlow[id] and self:Opt("fxNewSpell") then want, r, g, b = true, 1, 0.85, 0.3 end
    local active = false
    pcall(function() active = s.active and true or false end)
    if active and self:Opt("fxActive") then want, r, g, b = true, 1, 0.9, 0.5 end
    self:SetGlow(k, want, r, g, b)

    -- cooldown ready: a real (non-global) cooldown was running and now isn't
    local cd = false
    pcall(function()
        local gcd = s.gcd
        if gcd ~= nil and issecretvalue and issecretvalue(gcd) then gcd = false end
        cd = (k.cd:IsShown() and not gcd) and true or false
        local d = s.dur
        if cd and d ~= nil and not (issecretvalue and issecretvalue(d)) and d <= 1.5 then cd = false end
    end)
    if k.fxCd and not cd and self:Opt("fxReady") then self:Flash(k, 1, 0.95, 0.6) end
    k.fxCd = cd

    -- out of range / out of mana: flash once when it starts
    local oor, nomana = false, false
    pcall(function() oor = (s.range == false); nomana = (s.nomana == true) end)
    if oor and k.fxRange == false and self:Opt("fxRange") then self:Flash(k, 1, 0.25, 0.25) end
    if nomana and k.fxMana == false and self:Opt("fxRange") then self:Flash(k, 0.3, 0.4, 1) end
    k.fxRange, k.fxMana = oor, nomana
end

-- Effects asked for before the key could show them (new ability / new rank).
function FX:Queue(id, kind)
    if not (KB.db and self:Opt("fxOn")) then return end
    if kind == "newspell" then
        if self:Opt("fxNewSpell") then self.newGlow[id] = true; self.pending[id] = "burst" end
    elseif kind == "newrank" then
        if self:Opt("fxNewRank") then self.pending[id] = "burst" end
    end
end

function FX:Flush(keysList, tray)
    if next(self.pending) == nil then return end
    for i, k in ipairs(keysList) do
        if self.pending[k.def.id] then
            local target = visible(k) and k or (tray and tray[i] and visible(tray[i]) and tray[i]) or nil
            if target then self:Burst(target); self.pending[k.def.id] = nil end
        end
    end
end

function FX:Dismiss(id) self.newGlow[id] = nil end
