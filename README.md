# BuxbrewResist

After installing or editing, use `/reload`. Open your character panel and hover
Arcane, Fire, Nature, Frost or Shadow resistance. Details are appended below the
existing tooltip. Values are read again each time you hover.

## Screenshots

Nature resistance:

![Nature resistance tooltip showing average damage reduction and resist chances](screenshots/nature-resistance.png)

Shadow resistance:

![Shadow resistance tooltip showing average damage reduction and resist chances](screenshots/shadow-resistance.png)

## Tooltip details

The main number is **Expected average reduction**, highlighted in green and
calculated identically to `/buxres shadow`. Below it is a two-column breakdown:
damage reduced per spell (0%, 25%, 50%, 75%, or full resist) and its estimated
chance. Three compact rows show the gain from another 10 resistance, the average
against an attacker three levels higher, and the resistance cap with the amount
still needed. The original game tooltip remains above this section.

The +10 gain is the difference between the two expected averages, displayed with
`%` for brevity. It is an absolute change, not a relative percentage increase.
All tooltip and chat overview averages use the same legacy bucket model.

These are estimates, not measured TurtleWoW server probabilities. The legacy
model builds bucket chances from `min(75%, max(0, R / (5 * max(attackerLevel, 20))
* 75%))`, then weights each damage-reduction outcome by its chance. This bucket
approximation has not been validated against TurtleWoW; its weighted average can
differ from the initial value. The tooltip labels the section as estimates.
Negative resistance is reported without a numerical vulnerability estimate.

References used to check the integration and model:

- [Vanilla character resistance tooltip scripts](https://github.com/MOUZU/Blizzard-WoW-Interface/blob/master/1.12.1/FrameXML/PaperDollFrame.xml)
- [CMaNGOS Classic resistance implementation](https://github.com/cmangos/mangos-classic/blob/master/src/game/Entities/Unit.cpp), `CalculateEffectiveMagicResistancePercent` and `CalculateSpellResistChance`. This is a reference implementation, not proof of TurtleWoW's server behavior.

`/buxres` and `/buxres shadow` remain available.

Regression checks use Python with `lupa.lua51`: run `python tests/test_tooltips.py`.
An optional argument supplies a directory containing an installed `lupa` package.
They mock WoW's frame API; actual in-game layout still needs visual verification.
