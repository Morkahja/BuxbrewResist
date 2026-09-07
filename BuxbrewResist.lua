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
    -- CMaNGOS Classic vulnerability reference: defender level, no 0.75 factor.
    -- This is an estimate; TurtleWoW server behavior has not been verified.
    if resistance < 0 then
        return resistance / (5 * math.max(level or 1, 20))
    end
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

local function damageExample(amount, reduction)
    return string.format("%.1f", amount * (1 - reduction))
end

-- Baseline for an ordinary incoming magic spell against the player.
-- No attacker spell-hit bonuses or special spell flags are assumed.
local function baseSpellMiss(playerLevel, attackerLevel)
    local difference = playerLevel - attackerLevel
    local chance = 0.04 + difference * 0.01
    if difference > 2 then chance = 0.06 + (difference - 2) * 0.07 end
    return clamp(chance, 0.01, 1)
end

local function totalReduction(resist, playerLevel, attackerLevel)
    attackerLevel = attackerLevel or playerLevel
    local average = expectedReduction(resist, resist < 0 and playerLevel or attackerLevel)
    local miss = baseSpellMiss(playerLevel, attackerLevel)
    -- Layer the baseline onto the legacy resistance model, without double counting.
    return miss + (1 - miss) * average, miss
end

local function coloredPercent(value)
    local color = value < 0 and "|cffff3333" or "|cff00ff00"
    return color .. fmtPercent(value, 2) .. "|r"
end

local function appendTotalTooltip(resist, level)
    local total, miss = totalReduction(resist, level)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Base spell miss (assumed)", fmtPercent(miss, 2), 0.85, 0.85, 0.85, 1, 1, 1)
    GameTooltip:AddLine("Same-level caster; no spell-hit bonus. Direct-damage estimate.", 0.85, 0.85, 0.85, true)
    GameTooltip:AddDoubleLine("Total expected average reduction", fmtPercent(total, 2),
        1, 1, 1, total < 0 and 1 or 0.2, total < 0 and 0.2 or 1, 0.2)
end

local function printMechanicsDetails(resist, level, schoolName)
    local function say(text) DEFAULT_CHAT_FRAME:AddMessage("  " .. text) end
    local function heading(text) say("|cffffff00" .. text .. "|r") end
    local average = expectedReduction(resist, level)
    local total, miss = totalReduction(resist, level)
    local cap = 5 * math.max(level, 20)
    heading("What this means for you")
    say("Base spell miss: " .. fmtPercent(miss, 2) .. " (same-level caster, no spell-hit bonus). Even 0 resistance helps through this baseline.")
    say("Total expected average reduction: " .. coloredPercent(total))
    say("For 1,000 incoming " .. schoolName .. " damage per cast: about " .. damageExample(1000, total) .. " damage per cast on average, including misses.")
    say("Without resistance: 960.0 average damage. With resistance alone: " .. damageExample(1000, average) .. ". With both: " .. damageExample(1000, total) .. ".")
    say("Think of 100 casts: about 4 miss. Your resistance then reduces damage from the other 96. These are averages, not guaranteed counts.")
    say("+10 resistance improves your TOTAL by " .. fmtPercent(totalReduction(resist + 10, level) - total, 2) .. " percentage points.")
    local higher, higherMiss = totalReduction(resist, level, level + 3)
    say("Against level " .. (level + 3) .. ": " .. fmtPercent(higher, 2) .. " total reduction, including " .. fmtPercent(higherMiss, 2) .. " assumed spell miss.")
    say("Resistance cap against level " .. level .. ": " .. cap .. " (" .. math.max(0, cap - resist) .. " more needed).")
    heading("A hit: Shadow Bolt")
    say("A warlock's Shadow Bolt deals damage in one hit. It is a non-binary example: some damage can be resisted without stopping the whole spell.")
    say("If a 1,000-damage hit is resisted by 25%, you take 750; at 50%, you take 500. Shadow Bolt uses Shadow resistance.")
    heading("A DoT: Corruption")
    say("A warlock's Corruption deals Shadow damage over time, in ticks. If the cast fails to land, none of its ticks happen.")
    say("After it lands, tick rules depend on the spell. A hypothetical 100-damage tick reduced by 25% deals 75; this is an example, not a Corruption tick prediction.")
    say("The direct-damage total above is not a universal DoT total. We do not know each TurtleWoW spell's tick rules.")
    heading("All-or-nothing: Frostbolt")
    say("In the Classic reference, a mage's Frostbolt is binary because it combines damage with a slow. Its resistance check lets the spell land or rejects it, instead of partially resisting its initial damage.")
    say("Frostbolt uses Frost resistance. These spell names explain the types; your numbers here describe " .. schoolName .. ".")
    if resist >= 0 then
        local binary = computeAverageResist(resist, level)
        say("For a binary spell of this school: " .. fmtPercent(binary, 2) .. " resistance contribution; with base miss, " .. fmtPercent(clamp(binary + miss, 0, 1), 2) .. " estimated rejection chance in the Classic reference.")
        say("Binary rejection uses the reference's combined failure roll; the direct-damage total uses the separate legacy damage model.")
    else
        say("Negative resistance means extra damage in our model, not a negative resist chance. It does not predict how long a slow lasts.")
    end
    heading("Why the game says Resist")
    say("A failed spell-hit check can also say 'Resist'. That is why the baseline is included in your total, even with 0 resistance.")
    say("Totals are estimates for ordinary spells, before crits, absorbs and other effects. Enemy spell hit, penetration and special spell rules can change them; TurtleWoW behavior is not verified.")
end

local function printSchoolInfo(schoolID, schoolName)
    if schoolName == "Physical" then
        local resist = getResistanceValue(schoolID) or 0
        local playerLevel = UnitLevel("player") or 1
        local dmgReduction = resist / (resist + 400 + 85 * playerLevel)
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00["..schoolName.."]|r: "..resist.." - "..fmtPercent(dmgReduction,1).." (Armor reduction)")
        return
    elseif schoolName == "Holy" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00["..schoolName.."]|r: "..(getResistanceValue(schoolID) or "N/A").." (No resistance-stat mitigation in the Classic reference)")
        DEFAULT_CHAT_FRAME:AddMessage("  Holy spells can still fail a spell-hit check. Total expected average reduction: 4% from assumed base spell misses (same-level caster, no spell-hit bonus).")
        return
    end

    local resist = getResistanceValue(schoolID)
    if not resist then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000"..schoolName.." resist not available.|r")
        return
    end

    local playerLevel = UnitLevel("player") or 1
    if resist < 0 then
        local average = expectedReduction(resist, playerLevel)
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00["..schoolName.."]|r Resist: "..resist.." (Legacy vulnerability estimate)")
        DEFAULT_CHAT_FRAME:AddMessage("  Resistance-only avg reduction: |cffff3333"..fmtPercent(average,2).."|r")
        DEFAULT_CHAT_FRAME:AddMessage("  Extra damage taken: |cffff3333+"..fmtPercent(-average,2).."|r (estimate)")
        printMechanicsDetails(resist, playerLevel, schoolName)
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
    DEFAULT_CHAT_FRAME:AddMessage("  Resistance-only avg reduction: |cff00ff00"..fmtPercent(expected,2).."|r")

    local binaryChance = AR
    DEFAULT_CHAT_FRAME:AddMessage("  Binary spell resist estimate: "..fmtPercent(binaryChance,2))
    printMechanicsDetails(resist, playerLevel, schoolName)
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
                DEFAULT_CHAT_FRAME:AddMessage("  "..data.name..": "..resist.." (0% resistance reduction; 4% base spell miss assumed)")
            else
                local expected = totalReduction(resist, playerLevel)
                DEFAULT_CHAT_FRAME:AddMessage("  "..data.name..": "..resist.." - "..coloredPercent(expected).." total expected average reduction (4% base miss assumed)")
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
        local average = expectedReduction(total, level)
        GameTooltip:AddDoubleLine("Resistance-only average reduction", fmtPercent(average, 2),
            1, 1, 1, 1, 0.2, 0.2)
        GameTooltip:AddDoubleLine("Extra damage taken (estimate)", "+" .. fmtPercent(-average, 2),
            0.85, 0.85, 0.85, 1, 0.2, 0.2)
        GameTooltip:AddLine("Legacy vulnerability model; server behavior unverified.", 0.85, 0.85, 0.85)
        row("Total gain from +10 resistance", "+" .. fmtPercent(totalReduction(total + 10, level) - totalReduction(total, level), 2))
        row("Resistance cap", cap .. " (" .. math.max(0, cap - total) .. " more)")
        appendTotalTooltip(total, level)
        GameTooltip:Show()
        return
    end

    local average, buckets = expectedReduction(total, level)
    GameTooltip:AddDoubleLine("Resistance-only average reduction", fmtPercent(average, 2),
        1, 1, 1, 0.2, 1, 0.2)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Damage reduced per spell", "Chance", 1, 0.82, 0, 1, 0.82, 0)
    row("0% reduction - full damage", fmtPercent(buckets[0], 2))
    row("25% reduction", fmtPercent(buckets[25], 2))
    row("50% reduction", fmtPercent(buckets[50], 2))
    row("75% reduction", fmtPercent(buckets[75], 2))
    row("100% reduction - full resist", fmtPercent(buckets[100], 2))
    GameTooltip:AddLine(" ")
    row("Total gain from +10 resistance", "+" .. fmtPercent(totalReduction(total + 10, level) - totalReduction(total, level), 2))
    row("Total vs level " .. (level + 3) .. " (1% miss)", fmtPercent(totalReduction(total, level, level + 3), 2))
    row("Resistance cap", cap .. " (" .. math.max(0, cap - total) .. " more)")
    appendTotalTooltip(total, level)
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
