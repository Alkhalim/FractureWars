extends SceneTree
## UI Polish Wave 2 Task W2 — headless coverage for
## scripts/core/unit_class_helper.gd's classes_for()/hover_tags(). Pure
## GDScript + DataManager (no scene-tree dependency beyond the autoload),
## same pattern as test_unit_training.gd.
## Run: godot --headless --path . -s res://tests/test_unit_classes.gd

var _fails := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var dm = root.get_node("/root/DataManager")

	# ── 1. Known pure infantry: crimson_shieldwall (infantry, melee, heavy)
	# -> [infantry]. No cavalry/monster/beast/mage/support/construct/siege/
	# ranged/flying tag, so nothing else can compete for the slot. ──
	var shieldwall: UnitData = dm.get_unit(&"crimson_shieldwall")
	_check(shieldwall != null, "crimson_shieldwall resolves in DataManager")
	if shieldwall:
		var cls := UnitClassHelper.classes_for(shieldwall)
		_check(cls == [&"infantry"], "crimson_shieldwall (pure infantry) -> [infantry], got %s" % [cls])

	# ── 2. nightrider (cavalry, melee, fast, undead, light) -> [cavalry].
	# The task brief's own named example. ──
	var nightrider: UnitData = dm.get_unit(&"nightrider")
	_check(nightrider != null, "nightrider resolves in DataManager")
	if nightrider:
		var cls := UnitClassHelper.classes_for(nightrider)
		_check(cls == [&"cavalry"], "nightrider (cavalry,melee,fast,undead,light) -> [cavalry], got %s" % [cls])

	# ── 3. Known archers — TWO real patterns in the data (see
	# unit_class_helper.gd tie-break B doc comment): infantry+ranged
	# (lunar_archer) AND bare-ranged-with-no-body-tag (sun_archer, ~23 of
	# these in the roster). Both must resolve to [archer]. ──
	var lunar_archer: UnitData = dm.get_unit(&"lunar_archer")
	_check(lunar_archer != null, "lunar_archer resolves in DataManager")
	if lunar_archer:
		var cls := UnitClassHelper.classes_for(lunar_archer)
		_check(cls == [&"archer"], "lunar_archer (infantry,ranged) -> [archer], got %s" % [cls])

	var sun_archer: UnitData = dm.get_unit(&"sun_archer")
	_check(sun_archer != null, "sun_archer resolves in DataManager")
	if sun_archer:
		var cls := UnitClassHelper.classes_for(sun_archer)
		_check(cls == [&"archer"], "sun_archer (bare ranged, no infantry tag) -> [archer], got %s" % [cls])

	# ── 4. flying beats archer as the fallback when BOTH bare "ranged" and
	# "flying" are present with no body-type tag (hawk_scout: ranged, fast,
	# flying, light — a literal hawk, no beast tag) — a bow icon would
	# misread as "carries a bow"; wing is the honest read. ──
	var hawk_scout: UnitData = dm.get_unit(&"hawk_scout")
	_check(hawk_scout != null, "hawk_scout resolves in DataManager")
	if hawk_scout:
		var cls := UnitClassHelper.classes_for(hawk_scout)
		_check(cls == [&"flying"], "hawk_scout (ranged+flying, no body tag) -> [flying] not [archer], got %s" % [cls])

	# ── 5. Known hybrid: exactly 2 classes, stable primary-first order.
	# elderbeast_lv1 (construct, beast, melee, heavy) -> [beast, construct]
	# per the documented priority (beast checked before construct) — the
	# shardhorde elderbeast IS a construct-beast hybrid by design (shard
	# machinery grown into a living creature), a good real showcase for the
	# verification sweep's "shardhorde monsters" recruit-list shot. ──
	var elderbeast: UnitData = dm.get_unit(&"elderbeast_lv1")
	_check(elderbeast != null, "elderbeast_lv1 resolves in DataManager")
	if elderbeast:
		var cls := UnitClassHelper.classes_for(elderbeast)
		_check(cls.size() == 2, "elderbeast_lv1 (construct+beast) yields exactly 2 classes, got %s" % [cls])
		_check(cls == [&"beast", &"construct"], "elderbeast_lv1 -> [beast, construct] (stable order), got %s" % [cls])
		# Called twice — same unit, same result — confirms determinism/no
		# hidden state (tag dict iteration order can't leak in).
		var cls_again := UnitClassHelper.classes_for(elderbeast)
		_check(cls == cls_again, "classes_for is deterministic across repeated calls on the same UnitData")

	# ── 6. supporter without mage: field_medic-style (support, ranged, no
	# mage tag) — must NOT read as archer despite carrying "ranged". ──
	var blight_walker: UnitData = dm.get_unit(&"blight_walker")
	_check(blight_walker != null, "blight_walker resolves in DataManager")
	if blight_walker:
		var cls := UnitClassHelper.classes_for(blight_walker)
		_check(cls == [&"supporter"], "blight_walker (support,ranged, no mage) -> [supporter] not [archer], got %s" % [cls])

	# ── 7. mage swallows support (tie-break A): ash_ritualist-style caster
	# (mage, ranged, support) reads as a single mage, not a mage+supporter
	# hybrid (that pattern is near-universal for casters — see doc comment). ──
	var ash_ritualist: UnitData = dm.get_unit(&"ash_ritualist")
	_check(ash_ritualist != null, "ash_ritualist resolves in DataManager")
	if ash_ritualist:
		var cls := UnitClassHelper.classes_for(ash_ritualist)
		_check(cls == [&"mage"], "ash_ritualist (mage,ranged,support) -> [mage] only, got %s" % [cls])

	# ── 8. hover_tags cleanup rules ──
	if nightrider:
		var tags := UnitClassHelper.hover_tags(nightrider)
		_check(not tags.has("melee"), "hover_tags drops 'melee' always (nightrider)")
		_check(tags.has("cavalry") and tags.has("fast") and tags.has("undead") and tags.has("light"), "hover_tags keeps non-cleanup tags (nightrider), got %s" % [tags])
	var ember_cavalry: UnitData = dm.get_unit(&"ember_cavalry")
	_check(ember_cavalry != null, "ember_cavalry resolves in DataManager")
	if ember_cavalry:
		var cls := UnitClassHelper.classes_for(ember_cavalry)
		_check(cls == [&"cavalry"], "ember_cavalry (cavalry,ranged) -> [cavalry] (ranged doesn't compete for a slot cavalry already filled), got %s" % [cls])
		var tags := UnitClassHelper.hover_tags(ember_cavalry)
		_check(tags.has("ranged"), "hover_tags KEEPS 'ranged' for a non-archer/mage class (cavalry) — not implied by the class name, got %s" % [tags])
	if lunar_archer:
		var tags := UnitClassHelper.hover_tags(lunar_archer)
		_check(not tags.has("ranged"), "hover_tags drops 'ranged' for archer-class units (lunar_archer), got %s" % [tags])
	if ash_ritualist:
		var tags := UnitClassHelper.hover_tags(ash_ritualist)
		_check(not tags.has("ranged"), "hover_tags drops 'ranged' for mage-class units (ash_ritualist), got %s" % [tags])
	var ashen_champion: UnitData = dm.get_unit(&"ashen_champion")
	_check(ashen_champion != null, "ashen_champion resolves in DataManager")
	if ashen_champion:
		_check(ashen_champion.faction_id == &"cinderguard", "sanity: ashen_champion is a cinderguard unit")
		var tags := UnitClassHelper.hover_tags(ashen_champion)
		_check(not tags.has("cinderguard"), "hover_tags drops the self-faction tag (ashen_champion's literal 'cinderguard' tag), got %s" % [tags])
		_check(tags.has("desertstrider") and tags.has("heavy"), "hover_tags keeps unrelated flavor tags (ashen_champion), got %s" % [tags])

	# ── 9. EVERY unit in DataManager yields >= 1 class, and never more than
	# 2 (contract, not just observed behavior). ──
	var total := 0
	var empty_count := 0
	var over_cap_count := 0
	for uid in dm.units.keys():
		var ud: UnitData = dm.units[uid]
		total += 1
		var cls := UnitClassHelper.classes_for(ud)
		if cls.is_empty():
			empty_count += 1
			print("FAIL DETAIL: %s (%s) yielded 0 classes, tags=%s" % [uid, ud.faction_id, ud.tags])
		elif cls.size() > 2:
			over_cap_count += 1
			print("FAIL DETAIL: %s (%s) yielded >2 classes: %s, tags=%s" % [uid, ud.faction_id, cls, ud.tags])
	_check(total >= 250, "sanity: a plausible number of units were scanned (>=250), got %d" % total)
	_check(empty_count == 0, "every unit in DataManager yields >=1 class, %d failed" % empty_count)
	_check(over_cap_count == 0, "no unit yields more than 2 classes, %d failed" % over_cap_count)

	if _fails == 0:
		print("UNIT CLASSES TEST PASSED (%d units scanned)" % total)
		quit(0)
	else:
		print("UNIT CLASSES TEST FAILED (%d)" % _fails)
		quit(1)

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
		print("FAIL: " + label)
