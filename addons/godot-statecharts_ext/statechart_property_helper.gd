class_name StateChartPropertyHelper
extends RefCounted


## StateChartExtのプロパティリストの取得
## パラメータ、警告除外設定、履歴などのインスペクター用構築
static func sc_get_property_list(sc: StateChartExt) -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	var sc_info: StateChartExt.SCInfo = sc.get_sc_info()
	if sc_info == null:
		return properties

	# パラメータ定義を取得してインスペクターに表示する
	var params := StateChartExt._init_and_get_entries(sc_info.param, StateChartExt.ParamEnt)
	if not params.is_empty():
		properties.append(
			{
				"name": "StateChart Parameters",
				"type": TYPE_NIL,
				"usage": PROPERTY_USAGE_GROUP,
				"hint_string": StateChartConstants.PropGroup.PARAM
			}
		)

		# 各パラメータのプロパティ定義を構築
		for p_name in params:
			var ent := params[p_name] as StateChartExt.ParamEnt
			var usage := PROPERTY_USAGE_DEFAULT
			if ent.type_id == TYPE_NIL:
				usage |= PROPERTY_USAGE_NIL_IS_VARIANT
			var display_name := p_name
			if not ent.local_state.is_empty():
				display_name = ("{0}{1}{2} {3}".format(
					[
						StateChartConstants.LocalParam.PREFIX,
						ent.local_state,
						StateChartConstants.LocalParam.SUFFIX,
						p_name
					]
				))

			# パラメータのプロパティ定義を追加
			properties.append(
				{
					"name": StateChartConstants.PropGroup.PARAM + display_name,
					"type": ent.type_id,
					"usage": usage
				}
			)

	# イベント定義を取得してインスペクターに表示する
	var events := StateChartExt._init_and_get_entries(sc_info.event, StateChartExt.EventEnt)
	if not events.is_empty():
		# 未使用イベント警告除外設定グループを追加
		properties.append(
			{
				"name": "Exclude Unused Warnings",
				"type": TYPE_NIL,
				"usage": PROPERTY_USAGE_GROUP,
				"hint_string": StateChartConstants.PropGroup.EXC_UNUSED
			}
		)
		# 各イベントの除外設定プロパティを追加
		for ev_name in events:
			properties.append(
				{
					"name": StateChartConstants.PropGroup.EXC_UNUSED + ev_name,
					"type": TYPE_BOOL,
					"usage": PROPERTY_USAGE_EDITOR
				}
			)

		# 不明イベント警告除外設定グループを追加
		properties.append(
			{
				"name": "Exclude Unknown Warnings",
				"type": TYPE_NIL,
				"usage": PROPERTY_USAGE_GROUP,
				"hint_string": StateChartConstants.PropGroup.EXC_UNKNOWN
			}
		)
		# 各イベントの除外設定プロパティを追加
		for ev_name in events:
			properties.append(
				{
					"name": StateChartConstants.PropGroup.EXC_UNKNOWN + ev_name,
					"type": TYPE_BOOL,
					"usage": PROPERTY_USAGE_EDITOR
				}
			)

	# ランタイム履歴を表示する
	if not sc._runtime_history.is_empty():
		# ランタイム履歴表示グループを追加
		properties.append(
			{
				"name": "Runtime History (Latest first)",
				"type": TYPE_NIL,
				"usage": PROPERTY_USAGE_GROUP,
				"hint_string": StateChartConstants.PropGroup.HISTORY
			}
		)
		# 履歴エントリのプロパティを追加
		for i in range(sc._runtime_history.size()):
			properties.append(
				{
					"name": StateChartConstants.PropGroup.HISTORY + str(i),
					"type": TYPE_STRING,
					"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
				}
			)

	return properties


## プロパティのバリデーション
## 特定のプロパティのインスペクターでの表示設定（ストレージのみにする等）の制御
static func sc_validate_property(_sc: StateChartExt, property: Dictionary) -> void:
	if property.name == "initial_expression_properties":
		property.usage = PROPERTY_USAGE_STORAGE
	elif property.name == "exclude_unused_event" or property.name == "exclude_warn_unknown_events":
		property.usage = PROPERTY_USAGE_STORAGE


## プロパティの値の取得
## インスペクターからアクセスされたプロパティ名に応じた適切な値の返却
static func sc_get_property(sc: StateChartExt, property: StringName) -> Variant:
	if property == &"e":
		return sc._e_dyn
	if property == &"p":
		return sc._p_dyn

	# 未使用イベント警告除外設定の取得
	if property.begins_with(StateChartConstants.PropGroup.EXC_UNUSED):
		var ev_name := property.trim_prefix(StateChartConstants.PropGroup.EXC_UNUSED)
		return ev_name in sc.exclude_unused_event

	# 不明イベント警告除外設定の取得
	if property.begins_with(StateChartConstants.PropGroup.EXC_UNKNOWN):
		var ev_name := property.trim_prefix(StateChartConstants.PropGroup.EXC_UNKNOWN)
		return ev_name in sc.exclude_warn_unknown_events

	# ランタイム履歴の取得
	if property.begins_with(StateChartConstants.PropGroup.HISTORY):
		var idx := int(property.trim_prefix(StateChartConstants.PropGroup.HISTORY))
		if idx < sc._runtime_history.size():
			return sc._runtime_history[idx]
		return ""

	# パラメータ値の取得
	if property.begins_with(StateChartConstants.PropGroup.PARAM):
		var p_name := property.trim_prefix(StateChartConstants.PropGroup.PARAM)
		# Handle local param display name
		if p_name.contains(StateChartConstants.LocalParam.PREFIX):
			var parts := p_name.split(" ")
			p_name = parts[-1]

		# ステートチャート情報を取得
		var sc_info: StateChartExt.SCInfo = sc.get_sc_info()
		if sc_info:
			var params := StateChartExt._init_and_get_entries(sc_info.param, StateChartExt.ParamEnt)
			if params.has(p_name):
				return sc.get_expression_property_ext(params[p_name] as StateChartExt.ParamEnt)

	return null


## プロパティの値の設定
## インスペクターから変更されたプロパティ名に応じたStateChartExtの内部状態の更新
static func sc_set_property(sc: StateChartExt, property: StringName, value: Variant) -> bool:
	if property == &"e":
		sc._e_dyn = value
		return true
	if property == &"p":
		sc._p_dyn = value
		return true

	# 未使用イベント警告除外設定を更新
	if property.begins_with(StateChartConstants.PropGroup.EXC_UNUSED):
		var ev_name := StringName(property.trim_prefix(StateChartConstants.PropGroup.EXC_UNUSED))
		sc._update_exclusion_list(sc.exclude_unused_event, ev_name, value)
		return true

	# 不明イベント警告除外設定を更新
	if property.begins_with(StateChartConstants.PropGroup.EXC_UNKNOWN):
		var ev_name := StringName(property.trim_prefix(StateChartConstants.PropGroup.EXC_UNKNOWN))
		sc._update_exclusion_list(sc.exclude_warn_unknown_events, ev_name, value)
		return true

	# パラメータ値を更新
	if property.begins_with(StateChartConstants.PropGroup.PARAM):
		var p_name := property.trim_prefix(StateChartConstants.PropGroup.PARAM)
		if p_name.contains(StateChartConstants.LocalParam.PREFIX):
			var parts := p_name.split(" ")
			p_name = parts[-1]

		# ステートチャート情報を取得
		var sc_info: StateChartExt.SCInfo = sc.get_sc_info()
		if sc_info:
			var params := StateChartExt._init_and_get_entries(sc_info.param, StateChartExt.ParamEnt)
			if params.has(p_name):
				sc.set_expression_property_ext(params[p_name] as StateChartExt.ParamEnt, value)
				return true

	return false
