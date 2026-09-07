"""Run with Python + lupa; optional first argument is the lupa installation path."""
from pathlib import Path
import sys

if len(sys.argv) > 1:
    sys.path.insert(0, sys.argv[1])
from lupa.lua51 import LuaRuntime

lua = LuaRuntime()
lua.execute(r'''
getglobal = function(name) return _G[name] end
SlashCmdList = {}
level = 45
values = {10, 75, 70, -5}
UnitLevel = function() return level end
UnitResistance = function(unit, id)
    assert(unit == "player")
    lastSchool = id
    return unpack(values)
end
GameTooltip = {lines = {}}
function GameTooltip:IsOwned(frame) return self.owner == frame end
function GameTooltip:AddLine(text) table.insert(self.lines, {text}) end
function GameTooltip:AddDoubleLine(left, right, ...) table.insert(self.lines, {left, right, colors = {...}}) end
function GameTooltip:Show() self.shown = true end
messages = {}
DEFAULT_CHAT_FRAME = {AddMessage = function(self, text) table.insert(messages, text) end}
events = {}
function CreateFrame()
    local frame = {scripts = {}}
    function frame:RegisterEvent(name) events[name] = self end
    function frame:GetScript(name) return self.scripts[name] end
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:GetID() return self.id end
    return frame
end
local order = {6, 2, 3, 4, 5}
for i, id in ipairs(order) do
    local frame = CreateFrame()
    frame.id = id
    frame:SetScript("OnEnter", function()
        assert(this == frame)
        GameTooltip.owner = frame
        GameTooltip.lines = {{"Original heading"}, {"Original rating"}}
    end)
    _G["MagicResFrame" .. i] = frame
end
function hover(i)
    this = _G["MagicResFrame" .. i]
    this:GetScript("OnEnter")()
    assert(GameTooltip.lines[1][1] == "Original heading")
    assert(GameTooltip.lines[2][1] == "Original rating")
end
function valueFor(label)
    for _, line in ipairs(GameTooltip.lines) do
        if line[1] == label then return line[2] end
    end
end
''')
lua.execute((Path(__file__).resolve().parents[1] / "BuxbrewResist.lua").read_text())
lua.execute(r'''
for i, id in ipairs({6, 2, 3, 4, 5}) do
    hover(i)
    assert(lastSchool == id, "School must come from frame ID")
end
assert(string.find(GameTooltip.lines[4][1], "Shadow"))
assert(valueFor("Resistance-only average reduction") == "25%")
assert(valueFor("Resistance cap") == "225 (150 more)")
local chanceSum = 0
for _, label in ipairs({"0% reduction - full damage", "25% reduction", "50% reduction", "75% reduction", "100% reduction - full resist"}) do
    chanceSum = chanceSum + tonumber(string.sub(valueFor(label), 1, -2))
end
assert(math.abs(chanceSum - 100) < 0.03)
-- A non-round input exposes the old difference between the direct and bucket averages.
values = {0, 89, 89, 0}
hover(5)
SlashCmdList.BUXRES("shadow")
local found = false
for _, text in ipairs(messages) do
    if string.find(text, "Resistance-only avg reduction:", 1, true) then
        assert(string.find(text, valueFor("Resistance-only average reduction"), 1, true))
        found = true
    end
end
assert(found, "Tooltip average must match the detailed chat output")
local count = #GameTooltip.lines
for i = 1, 3 do
    events.ADDON_LOADED:GetScript("OnEvent")()
    events.PLAYER_LOGIN:GetScript("OnEvent")()
    hover(5)
    assert(#GameTooltip.lines == count, "Duplicate tooltip section")
end
values = {0, 0, 0, 0}
hover(5)
assert(valueFor("Resistance-only average reduction") == "0%")
values = {0, 300, 300, 0}
hover(5)
assert(valueFor("Resistance-only average reduction") == "75%")
assert(valueFor("Resistance cap") == "225 (0 more)")
assert(valueFor("Total gain from +10 resistance") == "+0%")
level = 10
hover(5)
assert(valueFor("Resistance cap") == "100 (0 more)")
values = {0, -10, 0, -10}
hover(5)
assert(valueFor("Resistance-only average reduction") == "-10%")
assert(valueFor("Extra damage taken (estimate)") == "+10%")
assert(valueFor("Total gain from +10 resistance") == "+9.6%")
level = 60
values = {0, -30, 0, -30}
for i = 1, 5 do
    hover(i)
    assert(valueFor("Resistance-only average reduction") == "-10%")
    assert(valueFor("Extra damage taken (estimate)") == "+10%")
    assert(valueFor("Damage reduced per spell") == nil)
    for _, line in ipairs(GameTooltip.lines) do
        if line[1] == "Resistance-only average reduction" then
            assert(line.colors[4] == 1 and line.colors[5] == 0.2 and line.colors[6] == 0.2, "Negative average must be red")
        end
    end
end
values = {0, -5, 0, -5}
hover(2)
assert(valueFor("Resistance-only average reduction") == "-1.67%")
assert(tonumber(string.sub(valueFor("Total gain from +10 resistance"), 2, -2)) > 1.6)
values = {0, 0, 0, 0}
hover(2)
assert(valueFor("Resistance-only average reduction") == "0%")
assert(valueFor("Extra damage taken (estimate)") == nil)
values = {}
hover(5)
assert(#GameTooltip.lines == 2, "Missing values should keep only the original tooltip")
values = {0, 25, 25, 0}
SlashCmdList.BUXRES("shadow")
SlashCmdList.BUXRES("")
-- Treat user input as literal text, never as a Lua pattern.
for _, input in ipairs({"[", "%", ".", "sh.*", "unknown"}) do
    messages = {}
    SlashCmdList.BUXRES(input)
    assert(#messages == 1 and string.find(messages[1], "Usage:", 1, true))
end
messages = {}
SlashCmdList.BUXRES("  ShAdOw  ")
assert(string.find(messages[1], "[Shadow]", 1, true))
messages = {}
SlashCmdList.BUXRES("f")
assert(#messages == 1 and string.find(messages[1], "Ambiguous school:", 1, true))
for input, name in pairs({fi = "Fire", fr = "Frost", sh = "Shadow"}) do
    messages = {}
    SlashCmdList.BUXRES(input)
    assert(string.find(messages[1], "[" .. name .. "]", 1, true))
end
messages = {}
SlashCmdList.BUXRES("   ")
assert(string.find(messages[1], "Resistance Overview", 1, true))
values = {0, -10, 0, -10}
messages = {}
SlashCmdList.BUXRES("shadow")
assert(#messages > 3 and string.find(messages[2], "|cffff3333-3.33%|r", 1, true))
assert(string.find(messages[3], "+3.33%", 1, true))
messages = {}
SlashCmdList.BUXRES("")
local negativeSchools = 0
for _, text in ipairs(messages) do
    if string.find(text, "|cff00ff000.8%|r", 1, true) then
        negativeSchools = negativeSchools + 1
    end
end
assert(negativeSchools == 5, "All magic schools must handle negative resistance consistently")
-- Check worked examples and explanations on all schools and both sides of zero.
local function chatContains(fragment)
    for _, message in ipairs(messages) do
        if string.find(message, fragment, 1, true) then return true end
    end
    return false
end
for _, sample in ipairs({{0, "960.0", "4%"}, {100, "720.0", "28%"}, {-30, "1056.0", "-5.6%"}, {300, "240.0", "76%"}}) do
    level = 60
    values = {0, sample[1], sample[1], 0}
    for i, school in ipairs({"arcane", "fire", "nature", "frost", "shadow"}) do
        messages = {}
        SlashCmdList.BUXRES(school)
        assert(chatContains("about " .. sample[2] .. " damage per cast"), "Incorrect total damage example")
        assert(chatContains("Shadow Bolt"))
        assert(chatContains("Corruption"))
        assert(chatContains("Frostbolt"))
        assert(chatContains("Base spell miss: 4%"))
        hover(i)
        assert(valueFor("Total expected average reduction") == sample[3])
        assert(GameTooltip.lines[#GameTooltip.lines][1] == "Total expected average reduction")
        for _, line in ipairs(GameTooltip.lines) do
            assert(line[1] ~= "How resistance works", "Remove tooltip mechanics guide")
            assert(not string.find(line[1], "DoTs:", 1, true))
        end
        messages = {}
        SlashCmdList.BUXRES("")
        assert(chatContains(sample[3] .. "|r total expected average reduction"))
    end
end
level = 45
values = {0, 42, 42, 0}
hover(2)
assert(valueFor("Resistance-only average reduction") == "11.25%")
assert(valueFor("Total expected average reduction") == "14.8%", "Combine multiplicatively, not by adding 4 points")
assert(valueFor("Total gain from +10 resistance") == "+4%")
assert(valueFor("Total vs level 48 (1% miss)") == "11.05%")
messages = {}
SlashCmdList.BUXRES("fire")
assert(chatContains("852.0 damage per cast"))
level = 60
values = {0, -30, 0, -30}
messages = {}
SlashCmdList.BUXRES("fire")
assert(chatContains("Against level 63: -8.9%"), "Vulnerability uses defender level while baseline changes")
hover(2)
local last = GameTooltip.lines[#GameTooltip.lines]
assert(last.colors[4] == 1 and last.colors[5] == 0.2, "Negative total is red")
messages = {}
SlashCmdList.BUXRES("holy")
assert(chatContains("Total expected average reduction: 4%"))
''')
print("PASS: Lua 5.1 load, all five schools, original text, live reads on hover, repeated installation, zero/cap/low-level/negative/missing values, slash commands")
