-- BuxbrewResist
-- Adds more detailed resistance information to tooltips.

local function GetResistanceInfo(school)
    -- UnitResistance("unit", school)
    -- school: 0=Physical, 2=Holy, 3=Fire, 4=Nature, 5=Frost, 6=Shadow, 7=Arcane
    local base, total, bonus = UnitResistance("player", school)
    local level = UnitLevel("player")
    local resist = total or 0

    -- Formula: chance to resist ~ resist / (level * 5), capped at 75%
    local chance = 0
    if level and level > 0 then
        chance = resist / (level * 5)
    end
    if chance > 0.75 then chance = 0.75 end
    if chance < 0 then chance = 0 end

    local avgResist = math.floor(chance * 100 + 0.5)

    return resist, avgResist
end

-- Hook resistance tooltips on character frame
hooksecurefunc("CharacterResistanceFrame_OnEnter", function(self)
    local school = self:GetID()
    if not school or school == 0 then return end -- skip physical

    local resist, avg = GetResistanceInfo(school)

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff00ff00Vs. same level:|r ~"..avg.."% average resist", 0.1, 1, 0.1)
    GameTooltip:Show()
end)
