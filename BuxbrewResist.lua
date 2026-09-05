-- BuxbrewResist
-- /buxres [physical|holy|fire|nature|frost|shadow|arcane]
-- Adds resistance details to character tooltips; /buxres remains available.

--------------------------------------------------
-- Utility
--------------------------------------------------

local schoolMap = {
    physical = { id = 0, name = "Physical" },
    holy     = { id = 1, name = "Holy" },
    fire     = { id = 2, name = "Fire" },
    nature   = { id = 3, name = "Nature" },
    frost    = { id = 4, name = "Frost" },
    shadow   = { id = 5, name = "Shadow" },
    arcane   = { id = 6, name = "Arcane" },
}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function computeAverageResist(resistValue, casterLevel)
    if not casterLevel or casterLevel < 1 then casterLevel = 1 end
    if casterLevel < 20 then casterLevel = 20 end
    local ar = (resistValue / (casterLevel * 5)) * 0.75
    return clamp(ar, 0, 0.75)
end

local function fmtPercent(v, decimals)
    decimals = decimals or 1
    local mult = 10 ^ decimals
    local rounded = math.floor(v * 100 * mult + 0.5) / mult
    return tostring(rounded) .. "%"
end

--------------------------------------------------
-- Partial resist buckets (0/25/50/75/100)
--------------------------------------------------

local function buildBuckets(AR)
    local weights = {}
    local sum = 0
    for i = 0, 10 do
        local x = i / 10
        local w = 0.5 - 2.5 * math.abs(x - AR)
        if w < 0 then w = 0 end
        weights[i] = w
        sum = sum + w
    end

    local buckets = { [0]=0, [25]=0, [50]=0, [75]=0, [100]=0 }
    if sum <= 0 then
        buckets[0] = 1
        return buckets
    end

    for i = 0, 10 do
        local x = i / 10
        local p = weights[i] / sum
        if x < 0.125 then
            buckets[0] = buckets[0] + p
        elseif x < 0.375 then
            buckets[25] = buckets[25] + p
        elseif x < 0.625 then
            buckets[50] = buckets[50] + p
        elseif x < 0.875 then
            buckets[75] = buckets[75] + p
        else
            buckets[100] = buckets[100] + p
        end
    end
    return buckets
end

-- Use the same legacy estimate for chat, tooltips and comparisons.
local function expectedReduction(resistance, level)
    local buckets = buildBuckets(computeAverageResist(resistance, level))
    local expected = 0
    for reduction, chance in pairs(buckets) do
        expected = expected + reduction / 100 * chance
    end
    return expected, buckets
end

--------------------------------------------------
-- Resistance values
--------------------------------------------------

local function getResistanceValue(schoolID)
    local base, total, bonus = UnitResistance("player", schoolID)
    return total
end

--------------------------------------------------
-- Output
--------------------------------------------------

local function printSchoolInfo(schoolID, schoolName)
    if schoolName == "Physical" then
        local resist = getResistanceValue(schoolID) or 0
        local playerLevel = UnitLevel("player") or 1
        local dmgReduction = resist / (resist + 400 + 85 * playerLevel)
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00["..schoolName.."]|r: "..resist.." - "..fmtPercent(dmgReduction,1).." (Armor reduction)")
        return
    elseif schoolName == "Holy" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00["..schoolName.."]|r: "..(getResistanceValue(schoolID) or "N/A").." (No resist rolls)")
        return
    end

    local resist = getResistanceValue(schoolID)
    if not resist then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000"..schoolName.." resist not available.|r")
        return
    end

    local playerLevel = UnitLevel("player") or 1
    if resist < 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00["..schoolName.."]|r Resist: "..resist.." (Reduction estimate unavailable for negative resistance)")
        return
    end
    local AR = computeAverageResist(resist, playerLevel)
    local expected, buckets = expectedReduction(resist, playerLevel)

    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00["..schoolName.."]|r Resist: "..resist.." (Player level "..playerLevel..")")
    DEFAULT_CHAT_FRAME:AddMessage("  Partial resists (direct damage, legacy estimates):")
    DEFAULT_CHAT_FRAME:AddMessage("    0% = "..fmtPercent(buckets[0],2).." (full damage)")
    DEFAULT_CHAT_FRAME:AddMessage("   25% reduction = "..fmtPercent(buckets[25],2))
    DEFAULT_CHAT_FRAME:AddMessage("   50% reduction = "..fmtPercent(buckets[50],2))
    DEFAULT_CHAT_FRAME:AddMessage("   75% reduction = "..fmtPercent(buckets[75],2))
    DEFAULT_CHAT_FRAME:AddMessage("  100% reduction = "..fmtPercent(buckets[100],2).." (full resist)")
    DEFAULT_CHAT_FRAME:AddMessage("  Expected avg reduction: |cff00ff00"..fmtPercent(expected,2).."|r")

    local binaryChance = AR
    DEFAULT_CHAT_FRAME:AddMessage("  Binary spell resist estimate: "..fmtPercent(binaryChance,2))
end

local function printSimpleOverview()
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[Resistance Overview]|r")
    local playerLevel = UnitLevel("player") or 1
    for _, data in pairs(schoolMap) do
        local resist = getResistanceValue(data.id)
        if resist then
            if data.name == "Physical" then
                local dmgReduction = resist / (resist + 400 + 85 * playerLevel)
                DEFAULT_CHAT_FRAME:AddMessage("  "..data.name..": "..resist.." - "..fmtPercent(dmgReduction,1).." (Armor reduction)")
            elseif data.name == "Holy" then
                DEFAULT_CHAT_FRAME:AddMessage("  "..data.name..": "..resist.." (No damage reduction)")
            elseif resist < 0 then
                DEFAULT_CHAT_FRAME:AddMessage("  "..data.name..": "..resist.." (Reduction estimate unavailable for negative resistance)")
            else
                local expected = expectedReduction(resist, playerLevel)
                DEFAULT_CHAT_FRAME:AddMessage("  "..data.name..": "..resist.." - "..fmtPercent(expected,2).." estimated average reduction")
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("  "..data.name..": N/A")
        end
    end
end

--------------------------------------------------
-- Slash command
--------------------------------------------------

local function BuxResCommand(msg)
    msg = string.lower(msg or "")
    msg = string.gsub(msg, "^%s*(.-)%s*$", "%1")
    if msg == "" then
        printSimpleOverview()
        return
    end

    local found = nil
    for k, v in pairs(schoolMap) do
        if string.sub(k, 1, string.len(msg)) == msg then
            if found then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Ambiguous school:|r "..msg..". Use the full school name (for example, fire or frost).")
                return
            end
            found = v
        end
    end

    if found then
        printSchoolInfo(found.id, found.name)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Usage:|r /buxres [physical|holy|fire|nature|frost|shadow|arcane]")
    end
end

SLASH_BUXRES1 = "/buxres"
SlashCmdList["BUXRES"] = BuxResCommand

--------------------------------------------------
-- Character-panel resistance tooltips (WoW 1.12)
--------------------------------------------------

-- These are the addon's legacy estimates, not measured server probabilities.
local function appendResistanceTooltip(frame)
    local schoolID = frame:GetID()
    if not schoolID or schoolID < 2 or schoolID > 6 then return end
    if not GameTooltip:IsOwned(frame) then return end

    local _, total = UnitResistance("player", schoolID)
    if not total then return end
    local level = math.max(UnitLevel("player") or 1, 1)
    local cap = math.max(level, 20) * 5
    local schoolName = getglobal("RESISTANCE" .. schoolID .. "_NAME")
    if not schoolName then
        for _, data in pairs(schoolMap) do
            if data.id == schoolID then schoolName = data.name end
        end
    end

    local function row(label, value)
        GameTooltip:AddDoubleLine(label, value, 0.85, 0.85, 0.85, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(schoolName .. " vs level " .. level .. " (estimates)", 1, 0.82, 0)

    if total < 0 then
        row("Expected average reduction", "Unavailable")
        GameTooltip:Show()
        return
    end

    local average, buckets = expectedReduction(total, level)
    GameTooltip:AddDoubleLine("Expected average reduction", fmtPercent(average, 2),
        1, 1, 1, 0.2, 1, 0.2)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Damage reduced per spell", "Chance", 1, 0.82, 0, 1, 0.82, 0)
    row("0% reduction - full damage", fmtPercent(buckets[0], 2))
    row("25% reduction", fmtPercent(buckets[25], 2))
    row("50% reduction", fmtPercent(buckets[50], 2))
    row("75% reduction", fmtPercent(buckets[75], 2))
    row("100% reduction - full resist", fmtPercent(buckets[100], 2))
    GameTooltip:AddLine(" ")
    row("Gain from +10 resistance", "+" .. fmtPercent(expectedReduction(total + 10, level) - average, 2))
    row("Average vs level " .. (level + 3), fmtPercent(expectedReduction(total, level + 3), 2))
    row("Resistance cap", cap .. " (" .. math.max(0, cap - total) .. " more)")
    GameTooltip:Show()
end

local function hookResistanceFrame(frame)
    if not frame or frame.buxResTooltipHooked then return end
    local originalOnEnter = frame:GetScript("OnEnter")
    if not originalOnEnter then return end
    frame:SetScript("OnEnter", function()
        -- Vanilla's original handler reads the global 'this'.
        originalOnEnter()
        appendResistanceTooltip(frame)
    end)
    frame.buxResTooltipHooked = true
end

local function installResistanceTooltips()
    -- The display order differs from school IDs; always read frame:GetID().
    for i = 1, 5 do
        hookResistanceFrame(getglobal("MagicResFrame" .. i))
    end
end

local tooltipEvents = CreateFrame("Frame")
tooltipEvents:RegisterEvent("PLAYER_LOGIN")
tooltipEvents:RegisterEvent("ADDON_LOADED")
tooltipEvents:SetScript("OnEvent", installResistanceTooltips)
installResistanceTooltips()
