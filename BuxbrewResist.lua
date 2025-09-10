-- BuxbrewResist
-- /buxres [fire|nature|frost|shadow|arcane]
-- Prints detailed resistance breakdown in chat.

--------------------------------------------------
-- Utility functions
--------------------------------------------------

local schoolMap = {
    fire   = { id = 3, name = "Fire" },
    nature = { id = 4, name = "Nature" },
    frost  = { id = 5, name = "Frost" },
    shadow = { id = 6, name = "Shadow" },
    arcane = { id = 7, name = "Arcane" },
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
    if ar < 0 then ar = 0 end
    if ar > 0.75 then ar = 0.75 end
    return ar
end

local function fmtPercent(v, decimals)
    if not decimals then decimals = 1 end
    local mult = 10 ^ decimals
    local rounded = math.floor(v * 100 * mult + 0.5) / mult
    return tostring(rounded) .. "%"
end

--------------------------------------------------
-- Probability distribution
--------------------------------------------------

local function build10PctDistribution(AR)
    local weights = {}
    local sum = 0
    for i = 0, 10 do
        local x = i / 10
        local w = 0.5 - 2.5 * math.abs(x - AR)
        if w < 0 then w = 0 end
        weights[i] = w
        sum = sum + w
    end

    local probs = {}
    if sum <= 0 then
        for i = 0, 10 do probs[i] = 0 end
        probs[0] = 1
        return probs
    end
    for i = 0, 10 do
        probs[i] = weights[i] / sum
    end
    return probs
end

local function aggregateTo25Buckets(probs10)
    local buckets = {}
    buckets[0] = 0
    buckets[25] = 0
    buckets[50] = 0
    buckets[75] = 0
    buckets[100] = 0

    for i = 0, 10 do
        local x = i / 10
        local p = probs10[i] or 0
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

--------------------------------------------------
-- Resistance retrieval
--------------------------------------------------

local function getResistanceValue(schoolID)
    local base, total, bonus = UnitResistance("player", schoolID)
    if total == nil then
        return nil
    end
    return total
end

--------------------------------------------------
-- Output
--------------------------------------------------

local function printSchoolInfo(schoolID, schoolName)
    local resist = getResistanceValue(schoolID)
    if not resist then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000"..schoolName.." resist not available on this server.|r")
        return
    end

    local playerLevel = UnitLevel("player") or 1
    local AR = computeAverageResist(resist, playerLevel)

    local probs10 = build10PctDistribution(AR)
    local buckets25 = aggregateTo25Buckets(probs10)

    local expected = 0
    for i = 0, 10 do
        local x = i / 10
        local p = probs10[i] or 0
        expected = expected + x * p
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00["..schoolName.."]|r Resist: "..resist.." (Player level "..playerLevel..")")
    DEFAULT_CHAT_FRAME:AddMessage("  Average resist vs same-level caster: |cff00ff00"..fmtPercent(AR,2).."|r (max 75%)")
    DEFAULT_CHAT_FRAME:AddMessage("  Detailed (10% increments):")
    for i = 0, 10 do
        local x = i * 10
        local p = probs10[i] or 0
        DEFAULT_CHAT_FRAME:AddMessage("    "..x.."% resist: "..fmtPercent(p,2).." chance")
    end
    DEFAULT_CHAT_FRAME:AddMessage("  Aggregated (0/25/50/75/100):")
    DEFAULT_CHAT_FRAME:AddMessage("    0% (full dmg): "..fmtPercent(buckets25[0] or 0,2))
    DEFAULT_CHAT_FRAME:AddMessage("   25%: "..fmtPercent(buckets25[25] or 0,2))
    DEFAULT_CHAT_FRAME:AddMessage("   50%: "..fmtPercent(buckets25[50] or 0,2))
    DEFAULT_CHAT_FRAME:AddMessage("   75%: "..fmtPercent(buckets25[75] or 0,2))
    DEFAULT_CHAT_FRAME:AddMessage("  100%: "..fmtPercent(buckets25[100] or 0,2))
    DEFAULT_CHAT_FRAME:AddMessage("  Expected avg reduction: |cff00ff00"..fmtPercent(expected,2).."|r")
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffa500Note:|r This covers resist rolls only. Spell hit/miss is a separate roll.")
end

local function printSimpleOverview()
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[Resistance Overview]|r")
    for _, data in pairs(schoolMap) do
        local resist = getResistanceValue(data.id)
        if resist then
            DEFAULT_CHAT_FRAME:AddMessage("  "..data.name..": "..resist)
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

    if msg == "" then
        printSimpleOverview()
        return
    end

    local found = nil
    for k, v in pairs(schoolMap) do
        if k:sub(1, #msg) == msg then
            found = v
            break
        end
    end

    if found then
        printSchoolInfo(found.id, found.name)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Usage:|r /buxres [fire|nature|frost|shadow|arcane]")
    end
end

SLASH_BUXRES1 = "/buxres"
SlashCmdList["BUXRES"] = BuxResCommand
