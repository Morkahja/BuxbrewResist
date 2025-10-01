-- BuxbrewResist
-- /buxres [physical|holy|fire|nature|frost|shadow|arcane]
-- Prints resistance info in chat.

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
    local AR = computeAverageResist(resist, playerLevel)
    local buckets = buildBuckets(AR)

    local expected = 0
    for k,v in pairs(buckets) do
        expected = expected + (k/100) * v
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00["..schoolName.."]|r Resist: "..resist.." (Player level "..playerLevel..")")
    DEFAULT_CHAT_FRAME:AddMessage("  Partial resists (direct damage):")
    DEFAULT_CHAT_FRAME:AddMessage("    0% = "..fmtPercent(buckets[0],2).." (full damage)")
    DEFAULT_CHAT_FRAME:AddMessage("   25% reduction = "..fmtPercent(buckets[25],2))
    DEFAULT_CHAT_FRAME:AddMessage("   50% reduction = "..fmtPercent(buckets[50],2))
    DEFAULT_CHAT_FRAME:AddMessage("   75% reduction = "..fmtPercent(buckets[75],2))
    DEFAULT_CHAT_FRAME:AddMessage("  100% reduction = "..fmtPercent(buckets[100],2).." (full resist)")
    DEFAULT_CHAT_FRAME:AddMessage("  Expected avg reduction: |cff00ff00"..fmtPercent(expected,2).."|r")

    local binaryChance = AR
    DEFAULT_CHAT_FRAME:AddMessage("  Direct resist (DoTs / CC): "..fmtPercent(binaryChance,2))
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
            else
                local AR = computeAverageResist(resist, playerLevel)
                DEFAULT_CHAT_FRAME:AddMessage("  "..data.name..": "..resist.." - "..fmtPercent(AR,2))
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
    if msg == "" then
        printSimpleOverview()
        return
    end

    local found = nil
    for k, v in pairs(schoolMap) do
        if string.find(k, msg) == 1 then
            found = v
            break
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
