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

-- Keep the short tooltip explanation shared by positive and negative stats.
local function appendMechanicsHelp(schoolID)
    local function line(text)
        GameTooltip:AddLine(text, 0.85, 0.85, 0.85, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("How resistance works", 1, 0.82, 0)
    line("Direct damage: partial resists reduce a hit's damage.")
    line("DoTs: applying the spell and resisting its ticks are different checks; tick rules depend on the spell.")
    line("Binary spells: all-or-nothing resistance checks. Not every DoT or direct spell uses the same rules.")
    line("Spell misses can also say 'Resist', even at 0 resistance. Base spell misses are not included above.")
    for command, data in pairs(schoolMap) do
        if data.id == schoolID then
            line("Details and damage examples: /buxres " .. command)
            break
        end
    end
end

local function printMechanicsDetails(resist, level, schoolName)
    local function say(text)
        DEFAULT_CHAT_FRAME:AddMessage("  " .. text)
    end
    local function heading(text)
        say("|cffffff00" .. text .. "|r")
    end
    local average = expectedReduction(resist, level)
    local cap = 5 * math.max(level, 20)
    heading("Your stats and examples")
    say("Attacker assumed level " .. level .. "; no enemy resistance penetration assumed.")
    say("1,000 " .. schoolName .. " damage -> " .. damageExample(1000, average) .. " average damage in this model.")
    say("This is an average over many hits, before crits, absorbs and other damage modifiers; spell misses are excluded.")
    say("+10 resistance: " .. fmtPercent(expectedReduction(resist + 10, level) - average, 2) .. " percentage-point gain in average reduction.")
    local higherAverage = resist < 0 and average or expectedReduction(resist, level + 3)
    say("Average reduction vs level " .. (level + 3) .. ": " .. fmtPercent(higherAverage, 2) .. ".")
    say("Model resistance cap vs level " .. level .. ": " .. cap .. " (" .. math.max(0, cap - resist) .. " more needed); vs level " .. (level + 3) .. ": " .. (5 * math.max(level + 3, 20)) .. ".")
    heading("Direct damage and partial resists")
    say("Non-binary means damage can be partially resisted. A 1,000-damage hit with a 25% partial resist deals 750; with 50%, 500; with 75%, 250.")
    say("The bucket table is the addon's legacy approximation, not a universal outcome table for every spell or attacker.")
    heading("Damage over time (DoTs)")
    say("A DoT deals damage in ticks. The initial cast can fail to land; that is different from reducing a tick after it lands.")
    say("Tick resistance depends on the spell. Do not read the direct-damage table as the exact chances for every DoT.")
    say("Example: if a 100-damage tick is partially resisted by 25%, it deals 75. This example explains the outcome, not its chance.")
    say("The Classic reference gives ticks from binary spells special treatment. We do not have a verified TurtleWoW per-spell tick model.")
    heading("Binary spells (all-or-nothing)")
    say("The resistance check either rejects the spell or lets it land, rather than partially reducing that initial effect. Spell classification matters, not just its school.")
    if resist >= 0 then
        local binary = computeAverageResist(resist, level)
        say("Resistance-only binary estimate: " .. fmtPercent(binary, 2) .. ". Roughly " .. string.format("%.1f", binary * 100) .. " out of 100 checks in this model; not a guaranteed count or total failure chance.")
    else
        say("Negative resistance is modeled as extra damage, not a negative probability of resisting. This does not estimate crowd-control duration.")
    end
    heading("Why 'Resist' can appear at 0 resistance")
    say("Spell hit has its own failure chance. In Vanilla, a failed magic hit check can also display 'Resist'.")
    say("Classic baseline example: equal-level caster, no spell-hit bonuses or other modifiers -> 4% spell miss; normally a 1% minimum after hit bonuses. Some spells bypass this check.")
    say("That baseline is separate from your resistance stat. Enemy level, spell hit and spell-specific effects change it; this addon cannot know the total from your resistance alone.")
    heading("Model limits")
    if resist < 0 then
        say("Negative estimate = resistance / (5 x max(your level, 20)); uses your level, without the positive formula's 0.75 factor.")
    else
        say("Model input = resistance / (5 x max(attacker level, 20)) x 75%, limited to 0-75%; the displayed average weights the legacy buckets.")
    end
    say("Estimates, not measured TurtleWoW probabilities. Actual results depend on spell flags, attacker type, penetration, talents and server rules.")
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
        DEFAULT_CHAT_FRAME:AddMessage("  Holy spells can still fail a spell-hit check. 'No resistance' does not mean guaranteed hits.")
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
        DEFAULT_CHAT_FRAME:AddMessage("  Expected avg reduction: |cffff3333"..fmtPercent(average,2).."|r")
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
    DEFAULT_CHAT_FRAME:AddMessage("  Expected avg reduction: |cff00ff00"..fmtPercent(expected,2).."|r")

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
                DEFAULT_CHAT_FRAME:AddMessage("  "..data.name..": "..resist.." (No damage reduction)")
            elseif resist < 0 then
                local average = expectedReduction(resist, playerLevel)
                DEFAULT_CHAT_FRAME:AddMessage("  "..data.name..": "..resist.." - |cffff3333"..fmtPercent(average,2).."|r estimated average reduction (+"..fmtPercent(-average,2).." extra damage)")
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
        local average = expectedReduction(total, level)
        GameTooltip:AddDoubleLine("Expected average reduction", fmtPercent(average, 2),
            1, 1, 1, 1, 0.2, 0.2)
        GameTooltip:AddDoubleLine("Extra damage taken (estimate)", "+" .. fmtPercent(-average, 2),
            0.85, 0.85, 0.85, 1, 0.2, 0.2)
        GameTooltip:AddLine("Legacy vulnerability model; server behavior unverified.", 0.85, 0.85, 0.85)
        row("Gain from +10 resistance", "+" .. fmtPercent(expectedReduction(total + 10, level) - average, 2))
        row("Resistance cap", cap .. " (" .. math.max(0, cap - total) .. " more)")
        appendMechanicsHelp(schoolID)
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
    appendMechanicsHelp(schoolID)
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
