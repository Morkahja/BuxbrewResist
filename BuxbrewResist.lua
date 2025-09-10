-- BuxbrewResist.lua
-- /buxres [arcane|fire|nature|frost|shadow]  -- prints a detailed resist breakdown

local schoolMap = {
    arcane = { id = 7, name = "Arcane" },
    fire   = { id = 3, name = "Fire" },
    nature = { id = 4, name = "Nature" },
    frost  = { id = 5, name = "Frost" },
    shadow = { id = 6, name = "Shadow" },
}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Compute the "average resistance" (AR) vs a caster of casterLevel (decimal 0..1).
-- Uses vanilla scaling: AR = (resist / (casterLevel * 5)) * 0.75, capped at 0.75
-- casterLevel < 20 is treated as 20 (vanilla quirk).
local function computeAverageResist(resistValue, casterLevel)
    if not casterLevel or casterLevel < 1 then casterLevel = 1 end
    if casterLevel < 20 then casterLevel = 20 end
    local ar = (resistValue / (casterLevel * 5)) * 0.75
    if ar < 0 then ar = 0 end
    if ar > 0.75 then ar = 0.75 end
    return ar -- decimal (0..0.75)
end

-- Build the 10% increment probability distribution using the triangular kernel:
-- raw weight for x in {0.0,0.1,...,1.0} is w = max(0, 0.5 - 2.5 * abs(x - AR))
-- normalize weights -> probabilities (sum = 1)
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
        -- fallback: no resist (all probability to 0% bin)
        for i = 0, 10 do probs[i] = 0 end
        probs[0] = 1
        return probs
    end
    for i = 0, 10 do
        probs[i] = weights[i] / sum
    end
    return probs -- indexed by i (0..10), each is probability
end

-- Aggregate the 10% bins into classic 25% buckets:
-- ranges (decimal):
--   0% bucket   : x in [0.00, 0.125)
--   25% bucket  : x in [0.125, 0.375)
--   50% bucket  : x in [0.375, 0.625)
--   75% bucket  : x in [0.625, 0.875)
--   100% bucket : x in [0.875, 1.00]
local function aggregateTo25Buckets(probs10)
    local buckets = { [0]=0, [25]=0, [50]=0, [75]=0, [100]=0 }
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

-- Format a decimal fraction (0..1) as percentage string
local function fmtPercent(v, decimals)
    if not decimals then decimals = 1 end
    local mult = 10 ^ decimals
    local rounded = math.floor(v * 100 * mult + 0.5) / mult
    return tostring(rounded) .. "%"
end



local function printSchoolInfo(schoolID, schoolName)
    local base, total, bonus = UnitResistance("player", schoolID)
    local resist = total or 0
    local playerLevel = UnitLevel("player") or 1
    local casterLevel = playerLevel -- we calculate vs same-level caster
    local AR = computeAverageResist(resist, casterLevel) -- decimal
    local probs10 = build10PctDistribution(AR)
    local buckets25 = aggregateTo25Buckets(probs10)

    -- Expected / average damage reduced (should equal AR within rounding).
    local expected = 0
    for i = 0, 10 do
        local x = i / 10
        local p = probs10[i] or 0
        expected = expected + x * p
    end

    -- Print summary
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffffff00[%s]|r Resist: %d  (player lvl %d)", schoolName, resist, playerLevel))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  Average resist vs same-level caster: |cff00ff00%s|r (capped at 75%%)", fmtPercent(AR,2)))

    -- 10% increment table
    DEFAULT_CHAT_FRAME:AddMessage("  Detailed (10% increments):")
    local line = ""
    for i = 0, 10 do
        local x = i * 10
        local p = probs10[i] or 0
        -- print each on its own line for readability
        DEFAULT_CHAT_FRAME:AddMessage(string.format("    %3d%% resist: %s (chance)", x, fmtPercent(p,2)))
    end

    -- Aggregated 25% buckets
    DEFAULT_CHAT_FRAME:AddMessage("  Aggregated (classic 0/25/50/75/100):")
    DEFAULT_CHAT_FRAME:AddMessage(string.format("    0%% (full damage): %s", fmtPercent(buckets25[0] or 0,2)))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("   25%% : %s", fmtPercent(buckets25[25] or 0,2)))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("   50%% : %s", fmtPercent(buckets25[50] or 0,2)))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("   75%% : %s", fmtPercent(buckets25[75] or 0,2)))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  100%% : %s", fmtPercent(buckets25[100] or 0,2)))

    -- Expected reductions and note
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  Expected avg damage reduced: |cff00ff00%s|r (expected).", fmtPercent(expected,2)))
    DEFAULT_CHAT_FRAME:AddMessage("|cffffa500Note:|r This shows the resist roll distribution only. Spell 'miss' due to caster/target level or spell hit is a separate roll and is not included here.")
end

-- Command handler
local function BuxResCommand(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$") or ""
    if msg == "" then
        -- Print all schools
        for key, data in pairs(schoolMap) do
            printSchoolInfo(data.id, data.name)
        end
        return
    end

    -- allow abbreviated names (fire -> fire, f -> fire)
    local key = nil
    for k, v in pairs(schoolMap) do
        if k:sub(1, #msg) == msg or k == msg then
            key = k
            break
        end
    end
    if key then
        local data = schoolMap[key]
        printSchoolInfo(data.id, data.name)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Usage:|r /buxres [arcane|fire|nature|frost|shadow]")
    end
end

SLASH_BUXRES1 = "/buxres"
SLASH_BUXRES2 = "/buxresist"
SlashCmdList["BUXRES"] = BuxResCommand

-- end of BuxbrewResist.lua
