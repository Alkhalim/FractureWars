# Commander Abilities Design Proposal

Status: PROPOSAL — not implemented. Every id/line ref below was verified against the current repo.

> **DESIGNER DECISION (2026-08-01):** the second ability unlocks at **commander level 2** (deterministic), not on first battle won. This resolves Open Question 1.

## 1. Problem

Battles run mostly on formation orders (Advance/Hold/Charge/Flank/Retreat) plus automatic mage bolts. There is no moment-to-moment player decision once orders are queued — the player watches. Goal: give each commander 1 starter ability + a second early one, with more unlockable via tech/buildings, to create real mid-battle decisions in both the manual battle scene and (via an EV fold-in) auto-resolve.

## 2. How battles actually work today (grounding)

| Fact | Where |
|---|---|
| Real-time tick sim, ~10 ticks/sec (`TICK_SCALE=0.17`), hard cap `BATTLE_TIMER_TICKS=1500` (~2.5 min) | `scripts/systems/battle/battle_simulator_v3.gd:22-25` |
| A **mana** system already exists: `MANA_MAX=100`, `MANA_COST_SPELL=18`, `MANA_REGEN=0.4`/tick — but it is 100% automatic, consumed only by `mage`-tagged formations firing their `spell_type` bolt | `battle_simulator_v3.gd:37-40, 228, 2454-2843` |
| An **endurance** system also exists (sprint/charge/melee drain, idle regen) — same story, fully automatic | `battle_simulator_v3.gd:27-35` |
| Two different simulators exist: **V3** (real-time, used by the manual battle scene `scenes/battle/battle_v3.gd`) and **V2** (simpler, used ONLY by headless auto-resolve) | `scripts/systems/battle/battle_resolver.gd:90` (`BattleSimulatorV2.new()`) vs `scenes/battle/battle_v3.gd:152` (`BattleSimulatorV3.new()`) |
| **Both** simulators are fed the exact same commander-bonus dict, computed once via `CommanderSystem.get_commander_army_bonuses(commander)` | manual: `battle_v3.gd:163-164`; auto-resolve: `battle_resolver.gd:73-74` — both then call `sim.setup_attacker_formations(army, cmd_bonuses)` |
| That dict already carries flat bonuses (`attack_bonus`, `defense_bonus`, `speed_bonus`, `heal_per_turn`), tag-scoped bonuses (`cavalry_attack_bonus`, `terrain_forest_attack_bonus`, …) and battle-behavioral keys (`charge_damage_mult`, `retreat_morale_threshold`, `captive_chance_mod`, `morale_recovery_mult`, `ambush_attack_bonus`, `unit_morale_bonus`) consumed inside the tick loop via `_side_cmd_bonuses[side]` | `battle_simulator_v3.gd:84, 367-389, 2267, 2904, 2954, 3076`; aggregation in `scripts/systems/campaign/commander_system.gd:196-247` |
| Commander leveling already exists (`level` 1-10, XP thresholds) and grants **skill points**, not abilities — player (or AI) picks 1 of 3 contextual `CommanderSkill` choices per level | `scripts/core/commander_state.gd`; `commander_system.gd:28-120` |
| Resource-file loading pattern: skills/items/traits are `.tres` files in `res://data/skills|items|traits/`, generically loaded by id in `_load_resources_from_dir` | `commander_system.gd:9-26` |
| `BuildingData.special_effects` and `ResearchData.effects` are both free-form `Dictionary` — new keys are cheap to add and match existing conventions (`army_attack_bonus`, `income_gold_pct`, …) | `scripts/resources/building_data.gd:22`, `scripts/resources/research_data.gd:10` |

**Conclusion**: abilities should be a **new, parallel unlock track** alongside skills (not competing for level-up choices), and the auto-resolve fold-in should ride the *existing* `cmd_bonuses` dict rather than touching `BattleSimulatorV2` at all — zero new plumbing for auto-resolve.

## 3. Data schema: `AbilityData`

New resource, `scripts/resources/ability_data.gd`, loaded from `res://data/abilities/*.tres` the same way skills are loaded.

```gdscript
class_name AbilityData
extends Resource

@export var id: StringName
@export var display_name: String
@export var description: String
@export var faction_id: StringName = &""      # empty = universal (tech/building grant only)
@export var icon_path: String = ""
@export var target_type: StringName = &"self_army"  # self_army | single_formation | enemy_formation | area
@export var mana_cost: float = 0.0             # 0 = uses charges instead (see economy section)
@export var charges_per_battle: int = 1         # 0 = unlimited, gated by cooldown only
@export var cooldown_ticks: int = 300           # ~30s at 10 ticks/sec; 0 = charge-only
@export var duration_ticks: int = 0             # 0 = instant effect
@export var effects: Dictionary = {}            # same key vocabulary as cmd_bonuses (attack_bonus, unit_morale_bonus, heal_per_turn, ...)
@export var ev_fold_in: Dictionary = {}         # precomputed auto-resolve equivalent (see §6)
```

## 4. Acquisition model

| Source | Rule (default proposal) | Rationale |
|---|---|---|
| Starter | 1 faction-specific ability, granted at `CommanderState` creation (new `abilities: Array[StringName]` field, seeded from a `STARTER_ABILITY` lookup keyed by `faction_id`) | Matches "base of 1 they start with" |
| Early unlock | 2nd ability auto-granted at **commander level 2** (no player choice, no dilemma) | Deterministic, reuses the existing `commander_level_up` signal (`commander_system.gd:71`) with zero new UI. **Option B**: grant on "first battle won" instead via the existing `level_up_context`/battle-context array (`atk_ctx`/`def_ctx` in `battle_resolver.gd:284-300` already carries `battle_won`) — more flavorful but less deterministic for AI commanders that may lose early. Default: level 2. |
| Tech-granted | New `ResearchData.effects` key `"grants_ability": &"ability_id"` | Matches how effects already carry misc keys; **not** summed like numeric effects, so needs a small dedicated reader (see §7), not `get_research_effects()`. |
| Building-granted | New `BuildingData.special_effects` key `"grants_ability": &"ability_id"` | Mirrors the tech case; consistent with `special_effects["army_attack_bonus"]` already read ad hoc in `battle_resolver.gd:416-417`. |
| Cap | Max 4 equipped abilities per commander at once (matches a 4-button hotbar) | Keeps UI small; if more are unlocked than slots, the player picks a loadout in the commander panel (later phase — MVP just auto-fills first 4 unlocked). |

Tech/building-granted abilities are **faction-wide unlocks**, not personal XP: at battle setup, the commander's usable ability list = `commander.abilities` (personal: starter + level-2) **union** `CommanderSystem.get_faction_unlocked_abilities(faction_id)` (live-computed from `fs.completed_research` + built buildings, same "derive at read-time" pattern `research_system.get_research_effects()` already uses — no new save-state mutation needed).

## 5. Starter abilities — one per faction (11)

All are `self_army` or `area` effects using keys the sim already understands (§2 table), so the MVP needs **zero new effect-application code** — only the cast/cooldown wrapper.

| Faction | Ability | Flavor | Effect (uses existing key) |
|---|---|---|---|
| Empire | Rally the Legion | Disciplined shout | `unit_morale_bonus: +20` army-wide, 150 ticks |
| Gladehost | Verdant Surge | Nature's blessing | `heal_per_turn` burst: heal 8% max HP to all formations, instant |
| Moonspear | Lunar Veil | Moonlight cloaking | `ethereal_dodge_chance +0.15` army-wide, 150 ticks (field already exists on `BattleFormationV3:179`) |
| Thunderswarm | Storm Call | Lightning strike | `enemy_army_morale_penalty: -15`, instant, targets enemy side |
| Tainted Jade | Spore Cloud | Toxic bloom | `enemy_army_morale_penalty: -10` + `unit_morale_bonus: +10` (own), 120 ticks, area |
| Skulloath | Blood Frenzy | Corruption rage | `charge_damage_mult +0.3`, 100 ticks |
| Cinderguard | Forge Blessing | Molten temper | `defense_bonus +4` army-wide, 150 ticks |
| Forsaken | Dread Whisper | Espionage terror | `ambush_attack_bonus +6`, 100 ticks |
| Ivoryscar | Relic Ward | Ancient wards | `magic_defense`-style: reuse `terrain_city_defense_bonus`-style key → new `defense_bonus +6` vs mage/ranged tags via `vs_defense_bonuses` (`{"ranged": 4, "mage": 4}`) |
| Shardhorde | Resonance Pulse | Shard overcharge | `attack_bonus +5` army-wide, 120 ticks |
| Sunblessed | Dawn's Zeal | Solar fervor | `retreat_morale_threshold +15` (harder to break), 150 ticks |

## 6. Second-tier / tech / building examples (real ids)

| Grant | Ability | Wired to (REAL id, verified) |
|---|---|---|
| Level 2 (all factions) | *generic faction "veteran" ability* — e.g. Empire: "Shield Wall Formation" (`defense_bonus +6`, single_formation target, 200-tick cooldown) | `CommanderState.level >= 2` check in `commander_system._apply_level_up` |
| Tech | "War Machine Barrage" — one-shot ranged nuke on target formation | `emp_war_machines.tres` (Empire, tier 4, already grants `siege_bonus: 20` — natural to also `grants_ability: &"war_machine_barrage"`) |
| Tech | "Frontier Steel Temper" — army-wide `defense_bonus +5`, 150 ticks | `superior_alloys.tres` (Cinderguard, tier 2, `cg_coal_mines` prereq — thematically "we can now forge better") |
| Building | "Sunfire Volley" — AoE morale penalty on contact | any building with `special_effects.has("army_attack_bonus")`, e.g. the Sunblessed camp buildings already read in `battle_resolver._apply_camp_building_bonuses` (`battle_resolver.gd:408-417`) — add `grants_ability` alongside the existing `army_attack_bonus` key on that same building `.tres`. |

## 7. Runtime integration

### 7.1 Cooldown/charge economy — **default: per-battle charges, not real-time cooldowns**

- Battles cap at 1500 ticks (~150s) and most resolve much faster once a side routs — a 30-60s cooldown may simply never come off twice.
- **Default**: `charges_per_battle: 1` (starter/tech abilities) or `2` (cheap ones), consumed on cast, **no regen**, reset only at next battle. Simple, no new tick-accounting needed beyond a counter.
- **Option**: real cooldown in ticks (`cooldown_ticks`) for factions/abilities meant to be spammable (e.g. a cheap heal). Both fields exist in the schema (§3) so a designer can mix: set `charges_per_battle: 0` to mean "unlimited, cooldown-gated" or `cooldown_ticks: 0` to mean "charge-gated only."
- Mana-gated abilities (`mana_cost > 0`) piggyback on the *existing* per-formation mana pool conceptually, but since abilities are commander-level (whole-army) not per-formation, propose a **new `BattleSimulatorV3._side_ability_mana: Dictionary = {0: 100.0, 1: 100.0}`**, regenerating at the same `MANA_REGEN` rate, independent of individual mage formations' mana.

### 7.2 New simulator surface (V3 only — manual battles)

```gdscript
# BattleSimulatorV3 additions
var _side_ability_charges: Dictionary = {0: {}, 1: {}}   # ability_id -> charges remaining
var _side_ability_cooldown: Dictionary = {0: {}, 1: {}}  # ability_id -> ticks remaining
signal ability_cast(side: int, ability_id: StringName, target_id: StringName)

func can_cast_ability(side: int, ability: AbilityData) -> bool: ...
func cast_ability(side: int, ability: AbilityData, target_instance_id: StringName = &"") -> bool: ...
```
`cast_ability` applies `ability.effects` using the **same key-application code already in `_create_formation`/tick loop** (§2) — for `self_army`/`area` effects, loop `_get_side_formations(side)` and add a timed modifier (needs a small `_timed_modifiers: Array[Dictionary]` decayed per tick, ticking `duration_ticks` down — new but small).

### 7.3 Auto-resolve fold-in (V2 — the only path that matters here, since it never renders a cast)

Because both sims already read the identical `cmd_bonuses` dict (§2), the cleanest fold-in is: extend `CommanderSystem.get_commander_army_bonuses()` to also add each **usable-but-not-manually-cast** ability's `ev_fold_in` dict — i.e. an author-set "this ability is worth roughly +X flat attack_bonus averaged over a whole battle" stand-in (e.g. a 1-charge `+20 morale, 150 ticks` starter ability might fold in as `unit_morale_bonus: +3` flat, since it's active roughly 15% of an average battle and morale matters most early).

**Critical rule to avoid double-counting**: only fold `ev_fold_in` into the bonuses dict passed to **`BattleSimulatorV2`** (auto-resolve). The **manual V3** path should NOT receive `ev_fold_in` — it gets the ability as an actual castable button instead. Concretely: `battle_resolver.gd:73-74` calls a new `CommanderSystem.get_commander_army_bonuses(commander, fold_in_abilities=true)`; `battle_v3.gd:163-164` calls it with `fold_in_abilities=false` (default) and instead reads `commander.abilities` to populate the ability bar.

## 8. UI (manual battle scene)

`scenes/battle/battle_v3.gd` already has `order_panel`, `queue_panel`, `sim_panel` as sibling `PanelContainer`s (declared `battle_v3.gd:103-121`) plus a drag/drop command palette (`_queue_palette_buttons`). Add a new **`ability_panel: PanelContainer`** docked next to `order_panel` (same row, battle-screen bottom bar):

- 4 icon buttons (ability slots), each showing: icon, charges-remaining pip or cooldown radial (matches the existing `strength_bar_player`/`ColorRect` fill-bar idiom already used for `strength_meter_panel`), hotkeys `1-4`.
- Greyed out + tooltip reason when: no charges, on cooldown, or not enough mana.
- Tooltip reuses the existing unit-info tooltip pattern (`_update_unit_info`, `battle_v3.gd:1546`) for consistent styling.
- Clicking a `single_formation`/`enemy_formation`-targeted ability enters a "pick a target" cursor mode reusing the existing formation-picking code (`_find_formation_at`, `battle_v3.gd:1376`).

## 9. AI usage rules (simple, MVP-appropriate)

AI doesn't need lookahead — a per-ability trigger condition, checked once per N ticks in `assign_ai_orders`/an analogous per-tick AI pass:

| Ability archetype | Cast when |
|---|---|
| Morale buff (self) | Own side average morale < 50 AND in melee contact |
| Morale debuff (enemy) | Enemy side average morale < 60 AND enemy not yet routing |
| Heal burst | Own side average HP% < 60 |
| Attack/charge buff | About to charge (cavalry formation with `current_order == CHARGE`) or already in melee |
| Single-target nuke | Highest-value enemy formation (mage/ranged/monster tag) in range |

Always fire the moment the condition is true and a charge/cooldown is available — no bluffing/holding logic needed for MVP.

## 10. Phased implementation

| Phase | Scope |
|---|---|
| **MVP** | `AbilityData` resource + loader; 11 starter abilities (self_army/area only, reusing existing effect keys — §5); `CommanderState.abilities` field; level-2 auto-grant; manual cast via 1 new `ability_panel` with charges only (no cooldown ticks, no mana pool); EV fold-in into auto-resolve for the same 11; AI cast rule from §9 (buff/debuff archetypes only). |
| **Phase 2** | `single_formation`/`enemy_formation` targeting + target-picker cursor; cooldown-ticks option; the 2-3 tech/building-granted abilities (§6); 4-slot loadout UI when unlocked > 4. |
| **Phase 3** | Ability-specific mana pool (§7.1); duration-based timed modifiers beyond the simple ones already expressible via `cmd_bonuses` keys (e.g. true AoE damage-over-time, summons); dilemma-style "choose 1 of 2" tech/building grants using the existing `EventBus.dilemma_triggered` pattern instead of auto-grant. |

## Open questions for the designer

1. Level-2 auto-grant vs "first battle won" for the second ability — level-2 is deterministic but can lag behind the first 1-2 fights; first-win is flavorful but AI-losing commanders never get it. Which fits pacing better?
2. Per-battle charges (default) vs real-time cooldowns — do you want abilities spammable within one long fight, or strictly single-use "clutch" tools?
3. Should tech/building-granted abilities be faction-wide (any commander of that faction can use them, per §4) or require an individual commander to also personally reach some level, i.e. a soft cap on how strong a brand-new level-1 commander can be?
4. Manual-cast abilities skip the EV fold-in for auto-resolve (§7.3) so they're not double-counted — are you okay with auto-resolve battles being systematically slightly weaker than a well-played manual battle, or should EV fold-in be tuned to slightly *overshoot* real cast value to compensate players who always auto-resolve?
5. Is a 4-slot hotbar cap acceptable long-term, or should high-level commanders eventually run more than 4 abilities (with the UI growing a second row)?
