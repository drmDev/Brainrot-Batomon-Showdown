extends "test_runner.gd"
## Schema and generated-matrix tests for reactions/reaction_definitions.gd.
##
## The schema test catches typos in a definition (unknown scope, field, op, or
## metric) before they can silently never fire. The generated matrix test builds
## a matching snapshot and a boundary-miss snapshot from each trigger, so a new
## simple reaction needs no new test code.

const ReactionDefinitions = preload("../reactions/reaction_definitions.gd")
const ReactionEvaluator = preload("../reactions/reaction_evaluator.gd")


func test_ids_are_unique_and_well_formed() -> void:
	var seen := {}
	for definition in ReactionDefinitions.DEFINITIONS:
		var id := str(definition.get("id", ""))
		assert_false(id.is_empty(), "empty reaction id")
		assert_false(seen.has(id), "duplicate reaction id: " + id)
		seen[id] = true
		assert_false(str(definition.get("title", "")).is_empty(), "missing title for " + id)
		var triggers = definition.get("triggers")
		assert_true(triggers is Array, "missing triggers for " + id)
		if triggers is Array:
			assert_gt(triggers.size(), 0, "no triggers for " + id)


func test_every_trigger_uses_known_scope_field_op_and_metric() -> void:
	for definition in ReactionDefinitions.DEFINITIONS:
		var id := str(definition.get("id", ""))
		for trigger in definition.get("triggers", []):
			var scope := str(trigger.get("scope", ""))
			assert_true(
				[
					ReactionDefinitions.SCOPE_RUN,
					ReactionDefinitions.SCOPE_BATTLE,
					ReactionDefinitions.SCOPE_OUTCOME,
				].has(scope),
				"%s: unknown scope %s" % [id, scope]
			)
			if scope == ReactionDefinitions.SCOPE_BATTLE:
				_assert_battle_trigger_schema(id, trigger)
			else:
				var fields := (
					ReactionDefinitions.FIELDS
					if scope == ReactionDefinitions.SCOPE_RUN
					else ReactionDefinitions.OUTCOME_FIELDS
				)
				_assert_conditions(id, trigger.get("when", []), fields)


func _assert_battle_trigger_schema(id: String, trigger: Dictionary) -> void:
	var total = trigger.get("total")
	assert_true(total is Array and total.size() == 2, "%s: battle total must be [op, value]" % id)
	if total is Array and total.size() == 2:
		assert_true(
			ReactionDefinitions.OPS.has(str(total[0])),
			"%s: unknown op %s" % [id, str(total[0])]
		)
	var metrics = trigger.get("metrics")
	if metrics is Array:
		for label in metrics:
			assert_true(
				ReactionDefinitions.BATTLE_METRICS.has(str(label)),
				"%s: unknown metric %s" % [id, str(label)]
			)


func _assert_conditions(id: String, conditions, fields: Dictionary) -> void:
	assert_true(conditions is Array, "%s: when must be an array" % id)
	if not conditions is Array:
		return
	for condition in conditions:
		if condition is Dictionary and condition.has("any"):
			var any_list = condition["any"]
			assert_true(any_list is Array, "%s: any must be an array" % id)
			if any_list is Array:
				for sub in any_list:
					_assert_leaf(id, sub, fields)
		elif condition is Dictionary and condition.has("owns"):
			_assert_owns(id, condition["owns"])
		else:
			_assert_leaf(id, condition, fields)


func _assert_leaf(id: String, condition, fields: Dictionary) -> void:
	assert_true(
		condition is Array and condition.size() == 3,
		"%s: condition must be [field, op, value]" % id
	)
	if not condition is Array or condition.size() != 3:
		return
	var info = fields.get(str(condition[0]))
	assert_true(info is Dictionary, "%s: unknown field %s" % [id, str(condition[0])])
	if not info is Dictionary:
		return
	var op := str(condition[1])
	assert_true(
		ReactionDefinitions.OPS.has(op),
		"%s: unknown op %s" % [id, op]
	)
	if str(info.get("type", "int")) == "string":
		assert_true(
			op == ReactionDefinitions.OP_EQUALS or op == ReactionDefinitions.OP_NOT_EQUALS,
			"%s: string field %s only supports eq/ne" % [id, str(condition[0])]
		)


func _assert_owns(id: String, spec) -> void:
	assert_true(spec is Dictionary, "%s: owns must be a dictionary" % id)
	if not spec is Dictionary:
		return
	assert_false(str(spec.get("species", "")).is_empty(), "%s: owns.species is required" % id)
	var level_condition = spec.get("level")
	assert_true(
		level_condition is Array and level_condition.size() == 2,
		"%s: owns.level must be [op, value]" % id
	)
	if level_condition is Array and level_condition.size() == 2:
		assert_true(
			ReactionDefinitions.OPS.has(str(level_condition[0])),
			"%s: unknown owns.level op %s" % [id, str(level_condition[0])]
		)


func test_every_sound_file_exists() -> void:
	for definition in ReactionDefinitions.DEFINITIONS:
		var sound = definition.get("sound")
		if not sound is Dictionary:
			continue
		var file_name := str(sound.get("file", ""))
		assert_false(file_name.is_empty(), "empty sound file for " + str(definition.get("id", "")))
		var path := "res://assets/sounds/" + file_name
		assert_true(FileAccess.file_exists(path), "missing sound file: " + path)


func test_generated_matrix_matches_and_boundary_misses() -> void:
	for definition in ReactionDefinitions.DEFINITIONS:
		var id := str(definition.get("id", ""))
		for trigger in definition.get("triggers", []):
			var scope := str(trigger.get("scope", ""))
			if scope == ReactionDefinitions.SCOPE_RUN:
				_assert_run_trigger(id, trigger)
			elif scope == ReactionDefinitions.SCOPE_BATTLE:
				_assert_battle_trigger(id, trigger)
			elif scope == ReactionDefinitions.SCOPE_OUTCOME:
				_assert_outcome_trigger(id, trigger)


func _assert_run_trigger(id: String, trigger: Dictionary) -> void:
	var snapshot := _run_snapshot_for(trigger)
	if snapshot.is_empty():
		return
	var evaluator = ReactionEvaluator.new()
	assert_true(
		_ids(evaluator.poll(snapshot)).has(id),
		"%s: generated run snapshot did not trigger" % id
	)
	var miss := _run_snapshot_for(trigger, true)
	if not miss.is_empty():
		var evaluator2 = ReactionEvaluator.new()
		assert_false(
			_ids(evaluator2.poll(miss)).has(id),
			"%s: boundary miss triggered" % id
		)


func _assert_battle_trigger(id: String, trigger: Dictionary) -> void:
	var total = trigger.get("total")
	if not total is Array or total.size() != 2:
		return
	var op := str(total[0])
	var value := int(total[1])
	var metric_labels = trigger.get("metrics")
	if not metric_labels is Array:
		metric_labels = ReactionDefinitions.BATTLE_METRIC_ORDER
	if metric_labels.is_empty():
		return
	var label := str(metric_labels[0])
	var key := str(ReactionDefinitions.BATTLE_METRICS.get(label, ""))
	if key.is_empty():
		return

	var evaluator = ReactionEvaluator.new()
	assert_true(
		_ids(evaluator.poll_battle(_battle_with(key, _hit_value(op, value)))).has(id),
		"%s: generated battle snapshot did not trigger" % id
	)
	var evaluator2 = ReactionEvaluator.new()
	assert_false(
		_ids(evaluator2.poll_battle(_battle_with(key, _miss_value(op, value)))).has(id),
		"%s: boundary miss triggered" % id
	)


func _assert_outcome_trigger(id: String, trigger: Dictionary) -> void:
	var outcome := _outcome_for(trigger)
	if outcome.is_empty():
		return
	var evaluator = ReactionEvaluator.new()
	assert_true(
		_ids(evaluator.poll_battle(_battle_with_outcome(outcome))).has(id),
		"%s: generated outcome snapshot did not trigger" % id
	)
	var miss := _outcome_for(trigger, true)
	if not miss.is_empty():
		var evaluator2 = ReactionEvaluator.new()
		assert_false(
			_ids(evaluator2.poll_battle(_battle_with_outcome(miss))).has(id),
			"%s: boundary miss triggered" % id
		)


func _battle_with(key: String, value: int) -> Dictionary:
	return {
		"kind": "battle",
		"team": [{"name_key": "monster.name.test", "level": 1}],
		"battle_units": [{"team_id": 0, "slot_index": 0, key: value}],
		"battle_over": true,
	}


func _battle_with_outcome(outcome: Dictionary) -> Dictionary:
	return {
		"kind": "battle",
		"battle_over": true,
		"outcome": outcome,
	}


func _run_snapshot_for(trigger: Dictionary, miss: bool = false) -> Dictionary:
	var snapshot := {"kind": "run"}
	var conditions = trigger.get("when", [])
	if not conditions is Array:
		return {}
	var first := true
	for condition in conditions:
		if condition is Dictionary and condition.has("any"):
			var any_list = condition["any"]
			if any_list is Array and any_list.size() > 0:
				var sub = any_list[0]
				if sub is Array and sub.size() == 3:
					var info = ReactionDefinitions.FIELDS.get(str(sub[0]))
					if info is Dictionary:
						var op := str(sub[1])
						var value := int(sub[2])
						snapshot[str(info["key"])] = (
							_miss_value(op, value) if (miss and first) else _hit_value(op, value)
						)
						first = false
		elif condition is Dictionary and condition.has("owns"):
			var spec = condition["owns"]
			if spec is Dictionary:
				var level_condition = spec.get("level")
				var level := 1
				if level_condition is Array and level_condition.size() == 2:
					var op := str(level_condition[0])
					var value := int(level_condition[1])
					level = _miss_value(op, value) if (miss and first) else _hit_value(op, value)
				snapshot["team"] = [{
					"name_key": str(spec.get("species", "")),
					"level": level,
				}]
				first = false
		elif condition is Array and condition.size() == 3:
			var info = ReactionDefinitions.FIELDS.get(str(condition[0]))
			if info is Dictionary:
				if str(info.get("type", "int")) == "string":
					snapshot[str(info["key"])] = str(condition[2])
				else:
					var op := str(condition[1])
					var value := int(condition[2])
					snapshot[str(info["key"])] = (
						_miss_value(op, value) if (miss and first) else _hit_value(op, value)
					)
					first = false
	return snapshot


func _outcome_for(trigger: Dictionary, miss: bool = false) -> Dictionary:
	var outcome := {}
	var conditions = trigger.get("when", [])
	if not conditions is Array:
		return {}
	var first := true
	for condition in conditions:
		if condition is Array and condition.size() == 3:
			var info = ReactionDefinitions.OUTCOME_FIELDS.get(str(condition[0]))
			if info is Dictionary:
				var op := str(condition[1])
				var value := int(condition[2])
				outcome[str(info["key"])] = (
					_miss_value(op, value) if (miss and first) else _hit_value(op, value)
				)
				first = false
	return outcome


## A value that satisfies `op` against `value`.
func _hit_value(op: String, value: int) -> int:
	match op:
		ReactionDefinitions.OP_GREATER_THAN:
			return value + 1
		ReactionDefinitions.OP_GREATER_OR_EQUAL:
			return value
		ReactionDefinitions.OP_LESS_THAN:
			return value - 1
		ReactionDefinitions.OP_LESS_OR_EQUAL:
			return value
		ReactionDefinitions.OP_NOT_EQUALS:
			return value + 1
	return value


## A value that does not satisfy `op` against `value`.
func _miss_value(op: String, value: int) -> int:
	match op:
		ReactionDefinitions.OP_GREATER_THAN:
			return value
		ReactionDefinitions.OP_GREATER_OR_EQUAL:
			return value - 1
		ReactionDefinitions.OP_LESS_THAN:
			return value
		ReactionDefinitions.OP_LESS_OR_EQUAL:
			return value + 1
		ReactionDefinitions.OP_NOT_EQUALS:
			return value
	return value + 1


func _ids(reactions: Array) -> Array:
	var out: Array = []
	for reaction in reactions:
		out.append(str(reaction.get("id", "")))
	return out
