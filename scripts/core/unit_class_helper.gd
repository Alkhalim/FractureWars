class_name UnitClassHelper
extends RefCounted
## UI Polish Wave 2 Task W2 — maps UnitData.tags to a small "unit class"
## vocabulary for the recruit-button glyph/color system and hover-info tag
## cleanup. Pure data-derivation, no gameplay effect: reads UnitData.tags,
## never writes it.
##
## TAG VOCABULARY (grepped from all 279 data/units/**/*.tres on 2026-08-05;
## a stray concatenated-cache file `data/units/{}` was excluded — it isn't a
## real Resource, DataManager._load_units() only recurses into
## *subdirectories* so it's never loaded, but a naive recursive grep over
## data/units/ double-counts through it):
##   melee(167) infantry(~90) fast(82) ranged(~78) heavy(~44) beast(40)
##   support(~30) monster(~30) cavalry(~29) mage(~28) light(24) construct(~23)
##   desertstrider(21) swarm(20) flying(~18) undead(17) tundrawalker(15)
##   cinderguard(13) stationary(7) junglestrider(6) legendary(1) enchanted(1)
##   elite(1) demonic(1) chariot(1) ambush(1) siege(1)
## (counts are ~halved from a first pass that included the stray file above;
## exact counts don't matter to the mapping, only presence/absence per unit.)
##
## CLASS ENUM (10 — the brief's illustrative "infantry, cavalry, archer,
## mage, monster, beast, supporter, flying, siege" plus `construct`, added
## because the tag is real, frequent, and — unlike the illustrative list —
## already mechanically meaningful: vs_attack_bonuses/vs_defense_bonuses key
## off "construct" directly, e.g. starweaver's {"construct":4,"mage":3,
## "monster":3}. `archer` and `flying` are NOT literal tags anywhere in the
## data (grepped) — they're derived, see below.
##
## MAPPING RULES (priority-ordered; primary class = earliest rule that
## matches, secondary = the next rule that matches after it, capped at 2):
##  1. siege     — tag "siege"
##  2. mage      — tag "mage"
##  3. cavalry   — tag "cavalry"
##  4. monster   — tag "monster"
##  5. beast     — tag "beast"
##  6. construct — tag "construct"
##  7. supporter — tag "support" AND NOT "mage" (see tie-break A)
##  8. flying    — tag "flying" AND no class matched yet (see tie-break B)
##  9. archer    — tag "ranged" AND no class matched yet (see tie-break B)
##  10. infantry — tag "infantry" AND NOT "ranged" (ranged infantry already
##      claimed by archer at step 9 when nothing outranks it — see tie-break C)
##  Ultimate fallback: if nothing matched at all, [&"infantry"] (never
##  observed in real data — every one of the 279 units hits rule 1-9 — but
##  keeps the function total against a future data addition with an
##  unrecognized tag set instead of returning an empty array).
##
## TIE-BREAKS (why, not just what — verified against the real tag data):
## A) mage swallows support: "mage"+"ranged"+"support" is the single most
##    common caster pattern (ash_ritualist, coven_witch, bonecaller, ~20
##    more) — treating support as a genuine SECOND class there would turn
##    nearly every caster into a "hybrid", which isn't what a true hybrid
##    icon pair should mean. A unit needs "support" WITHOUT "mage" (a
##    priest/medic/drummer with no spell tag — barrier_priest, field_medic,
##    storm_drummer) to read as the `supporter` class.
## B) flying and archer are FALLBACKS, not always-eligible tags — both are
##    gated on "no class matched yet" rather than "still room for a second
##    class". Verified against real data this matters twice:
##    - `star_falcon`/`crystalwing_swoopers` etc. are beast+ranged with a
##      free second slot; without the gate, "archer" would fill it — a beast
##      that also happens to attack at range is still read as a beast (bow
##      icon on a falcon would misread as "carries a bow"), not a hybrid.
##      Ditto cavalry+ranged (ember_cavalry, stormbow_raider,
##      solar_cavalry_archer, bloodraven) staying plain `cavalry`.
##    - Without the gate, "archer" would ALSO win over "flying" for
##      hawk_scout/sacred_hawk (tags: ranged, fast, flying, light — no beast
##      tag despite being literal hawks, a data-vocabulary gap this helper
##      doesn't try to fix) since ranged is checked first in a slot-filling
##      scheme. Checking flying BEFORE archer (both gated the same way)
##      means a bird with no body-type tag reads as `flying` (wing icon —
##      honest to "this is some kind of flying creature"), not `archer`
##      (bow icon — implies a humanoid archer, which these aren't).
##    - archer alone (no flying) is what correctly classifies the ~23 real
##      units whose ENTIRE tag set is "ranged" + terrain/speed modifiers
##      with NO infantry tag at all (crownfire/fire_vanguard: ["ranged"];
##      sunblessed/sun_archer, skulloath/steppe_archers, forsaken/
##      cursed_archer, ivoryscar/bone_archer, gladehost/thornbow_scout, 15+
##      more) — a first pass assumed "archer = infantry AND ranged" (true
##      for 15 units: merchant_crossbow, imperial_crossbow, lunar_archer,
##      rebel_archer, jungle_archer, crystal_archer, toxotes, ...) but that
##      undercounts the roster's ranged-infantry-type units by ~3x; "ranged
##      with no other body-type tag" (gated the same as flying) covers both
##      groups in one rule.
## C) infantry excludes ranged (not just "ranged AND no class yet" like
##    archer/flying): infantry is checked LAST among the always-eligible
##    tier so it still pairs with construct (jade_golem, relic_guardian:
##    infantry+construct -> both classes, an "infantry-shaped construct"
##    hybrid) without also re-claiming units archer already covered.
##
## KNOWN EDGE CASE (no real instance, documented for future data): if a unit
## someday has "ranged" + "infantry" + a class from steps 1-6 (e.g. a
## hypothetical infantry+construct+ranged unit), archer's "no class matched
## yet" gate skips it (a class already matched at step 6), and infantry's
## "not ranged" guard ALSO skips it — the unit would show only the step-6
## class, silently dropping its ranged-ness from the icon (still visible via
## the "Ranged" hover tag, which this helper's tag cleanup does not touch in
## that case since the class list won't contain archer/mage). Not worth a
## 3rd icon slot for a combination that doesn't exist in 279 real units.
const CLASS_INFANTRY := &"infantry"
const CLASS_CAVALRY := &"cavalry"
const CLASS_ARCHER := &"archer"
const CLASS_MAGE := &"mage"
const CLASS_MONSTER := &"monster"
const CLASS_BEAST := &"beast"
const CLASS_SUPPORTER := &"supporter"
const CLASS_FLYING := &"flying"
const CLASS_SIEGE := &"siege"
const CLASS_CONSTRUCT := &"construct"

## All recognized classes, in the priority order documented above (also the
## iteration order tools_generate_class_icons.gd bakes glyphs in).
const ALL_CLASSES: Array[StringName] = [
	CLASS_SIEGE, CLASS_MAGE, CLASS_CAVALRY, CLASS_MONSTER, CLASS_BEAST,
	CLASS_CONSTRUCT, CLASS_SUPPORTER, CLASS_FLYING, CLASS_ARCHER, CLASS_INFANTRY,
]

## Display labels for the class enum (title-case, used nowhere as a raw tag
## string so this is the only place that needs to read nicely).
const CLASS_LABELS := {
	CLASS_INFANTRY: "Infantry", CLASS_CAVALRY: "Cavalry", CLASS_ARCHER: "Archer",
	CLASS_MAGE: "Mage", CLASS_MONSTER: "Monster", CLASS_BEAST: "Beast",
	CLASS_SUPPORTER: "Supporter", CLASS_FLYING: "Flying", CLASS_SIEGE: "Siege",
	CLASS_CONSTRUCT: "Construct",
}

## Generated glyph path for a class id — baked once by
## tests/tools_generate_class_icons.gd to assets/sprites/ui/generated/.
static func icon_path(cls: StringName) -> String:
	return "res://assets/sprites/ui/generated/class_%s.png" % String(cls)

## Primary-first, max-2, stable-order class list for `ud`. See the file-level
## doc comment for the full rule table and tie-break reasoning.
static func classes_for(ud: UnitData) -> Array[StringName]:
	var t := {}
	for tag in ud.tags:
		t[tag] = true
	var result: Array[StringName] = []

	if t.has("siege"):
		result.append(CLASS_SIEGE)
	if result.size() < 2 and t.has("mage"):
		result.append(CLASS_MAGE)
	if result.size() < 2 and t.has("cavalry"):
		result.append(CLASS_CAVALRY)
	if result.size() < 2 and t.has("monster"):
		result.append(CLASS_MONSTER)
	if result.size() < 2 and t.has("beast"):
		result.append(CLASS_BEAST)
	if result.size() < 2 and t.has("construct"):
		result.append(CLASS_CONSTRUCT)
	if result.size() < 2 and t.has("support") and not t.has("mage"):
		result.append(CLASS_SUPPORTER)
	if result.is_empty() and t.has("flying"):
		result.append(CLASS_FLYING)
	if result.is_empty() and t.has("ranged"):
		result.append(CLASS_ARCHER)
	if result.size() < 2 and t.has("infantry") and not t.has("ranged"):
		result.append(CLASS_INFANTRY)

	if result.is_empty():
		result.append(CLASS_INFANTRY)
	return result

## Hover-info tag cleanup (designer, verbatim): faction-name tags (e.g. a
## Cinderguard unit tagged "cinderguard") don't belong in the hover text;
## "melee" is never shown (absence of "ranged" already implies it); "ranged"
## itself is dropped ONLY for archer/mage-class units (their class name
## already says "ranged" — showing the tag too is redundant), staying for
## every other class (ranged cavalry/monster/beast/construct/siege — NOT
## implied by those class names, so it stays informative there). Returns raw
## (lowercase, unmodified) tag strings in original order — callers still do
## their own `.capitalize()`/join formatting, matching the existing call
## sites' style.
static func hover_tags(ud: UnitData) -> Array[String]:
	var cls := classes_for(ud)
	var drop_ranged := cls.has(CLASS_ARCHER) or cls.has(CLASS_MAGE)
	var faction_str := String(ud.faction_id)
	var out: Array[String] = []
	for tag in ud.tags:
		if tag == "melee":
			continue
		if tag == "ranged" and drop_ranged:
			continue
		if tag == faction_str:
			continue
		out.append(tag)
	return out
