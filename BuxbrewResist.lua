-- BuxbrewResist.lua
-- Vanilla/Turtle WoW friendly: watch the GameTooltip and append resist info
-- Avoids wrapping OnEnter (which can break due to old 'this' behavior).

local schoolMap = {
    arcane = 7,
    fire   = 3,
    nature = 4,
    frost  = 5,
    shadow = 6,
}

local function GetResistanceInfo(school)
    local base, total, bonus = UnitResistance("player", school)
    local level = UnitLevel("player") or 1
    local resist = total or 0

    local chance = resist / (level * 5)
    if chance > 0.75 then chance = 0.75 end
    if chance < 0 then chance = 0 end

    local avgResist = math.floor(chance * 100 + 0.5)
    return resist, avgResist
end

-- State to avoid duplicating the appended text
local lastLeft1Text = nil
local lastAppendedFor = nil

local pollFrame = CreateFrame("Frame")
pollFrame.elapsed = 0
pollFrame:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.12 then return end -- ~8-9 checks/sec
    self.elapsed = 0

    if not GameTooltip or not GameTooltip:IsShown() then
        lastLeft1Text = nil
        lastAppendedFor = nil
        return
    end

    local left1 = getglobal("GameTooltipTextLeft1")
    if not left1 then return end
    local text = left1:GetText()
    if not text or text == "" then return end

    -- Only re-check when the first line changes (reduces work & prevents repeats)
    if text == lastLeft1Text then return end
    lastLeft1Text = text

    -- Try to detect patterns like: "Arcane Resistance 0" (English clients).
    -- If you use a non-English client you may need to adjust the pattern or add localized names.
    local schoolName = text:match("^(%a+)%s+[Rr]esistance") or text:match("^(%a+)%s+Resist")
    if not schoolName then
        lastAppendedFor = nil
        return
    end

    local id = schoolMap[string.lower(schoolName)]
    if not id then
        lastAppendedFor = nil
        return
    end

    -- Avoid adding twice for the same tooltip text
    if lastAppendedFor == text then
        return
    end

    local resist, avg = GetResistanceInfo(id)

    -- Append our info to the tooltip
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff00ff00Vs. same level:|r ~"..avg.."% average resist", 0.1, 1, 0.1)
    GameTooltip:Show()

    lastAppendedFor = text
end)
