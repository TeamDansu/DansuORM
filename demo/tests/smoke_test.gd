extends SceneTree


class MockChartSet extends RefCounted:
	var db_id := -1
	var uuid := ""
	var folder_name := ""
	var charts: Array = []


class MockTiming extends RefCounted:
	var time := 0
	var bpm := 1.0


class MockChart extends RefCounted:
	var db_id := -1
	var chart_set: MockChartSet
	var file_name := ""
	var folder_name := ""
	var uuid := ""
	var version := 1
	var file_modified_time := 0
	var file_size := 0
	var filehash := ""
	var is_built_in := false
	var title := "?"
	var artist := "?"
	var creator := "?"
	var source := "?"
	var tags := ""
	var difficulty := "?"
	var rating := 0.0
	var rating_calculated := false
	var preview_time := -1.0
	var play_time_ms := 0
	var file_audio := ""
	var file_cover_art := ""
	var file_skin := ""
	var search_string_lower := ""
	var availability := 0
	var last_played_at := 0
	var best_score := 0.0
	var play_count := 0
	var current_version_play_count := 0
	var timings: Array = []

	func build_search_string() -> void:
		search_string_lower = (title + "-" + artist + "-" + creator + "-" + tags + "-" + difficulty + "-" + source).to_lower()


class MockScore extends RefCounted:
	var db_id := -1
	var chart_db_id := -1
	var object_hash := ""
	var played_at := 0
	var score := 0.0
	var max_score := 0.0
	var notes := 0
	var perfect_plus := 0
	var perfect := 0
	var great := 0
	var ok := 0
	var bad := 0
	var miss := 0
	var high_combo := 0
	var avg_signed_timings := 0.0
	var stored_avg_signed_timing := 0.0
	var unstable_rate := 0.0
	var scoring_version := 1
	var stored_total_score := -1.0
	var chart_title := ""
	var chart_artist := ""
	var chart_difficulty := ""
	var chart_folder_name := ""
	var chart_file_name := ""
	var total_score := 0.0


var failures := 0


func _init() -> void:
	var database := DansuDB.new()
	if not _check(database.open(":memory:"), database.get_last_error_message()):
		_finish()
		return

	_check(database.is_open(), "database should be open")
	_check(database.get_schema_version() == 2, "schema should be initialized")
	_check(database.get_sqlite_version() == database.get_bundled_sqlite_version(), "SQLite version mismatch")
	_check(not database.has_method("execute"), "raw execute API must not be exposed")
	_check(not database.has_method("execute_script"), "raw script API must not be exposed")
	_check(not database.has_method("query"), "raw query API must not be exposed")
	_check(not database.has_method("get_charts"), "dictionary chart API must not be exposed")
	_check(database.prepare_rating_cache(1), database.get_last_error_message())

	var scan_generation := database.begin_chart_scan()
	var chart_set := MockChartSet.new()
	chart_set.uuid = "chart-set-1"
	chart_set.folder_name = "test_set"
	var chart_set_id := database.upsert_chart_set(chart_set, scan_generation)
	chart_set.db_id = chart_set_id

	var chart := MockChart.new()
	chart.chart_set = chart_set
	chart.file_name = "hard.dansu"
	chart.uuid = "chart-1"
	chart.file_modified_time = 123456
	chart.file_size = 4096
	chart.filehash = "chart-hash-1"
	chart.title = "테스트 곡"
	chart.artist = "테스트 아티스트"
	chart.creator = "테스터"
	chart.source = "smoke"
	chart.tags = "test"
	chart.difficulty = "Hard"
	chart.rating = 12.5
	chart.rating_calculated = true
	chart.preview_time = 15.0
	chart.play_time_ms = 123456
	chart.file_cover_art = "cover.png"
	var timing_a := MockTiming.new()
	timing_a.bpm = 120.0
	var timing_b := MockTiming.new()
	timing_b.time = 30000
	timing_b.bpm = 180.0
	chart.timings = [timing_a, timing_b]
	chart.build_search_string()

	var chart_id := database.upsert_chart(chart, scan_generation)
	chart.db_id = chart_id
	_check(chart_id > 0, database.get_last_error_message())
	_check(database.finish_chart_scan(scan_generation), database.get_last_error_message())

	var library := database.load_chart_library(_make_chart_set, _make_chart, _make_timing)
	_check(library.size() == 1, "expected one chart set object")
	if not library.is_empty():
		var loaded_set: MockChartSet = library[0]
		_check(loaded_set.db_id == chart_set_id, "chart set ID round-trip failed")
		_check(loaded_set.uuid == chart_set.uuid, "chart set UUID round-trip failed")
		_check(loaded_set.charts.size() == 1, "chart set should contain one chart object")
		if not loaded_set.charts.is_empty():
			var loaded_chart: MockChart = loaded_set.charts[0]
			_check(loaded_chart.db_id == chart_id, "chart ID round-trip failed")
			_check(loaded_chart.title == "테스트 곡", "UTF-8 text round-trip failed")
			_check(loaded_chart.rating_calculated and loaded_chart.rating == 12.5, "calculated rating round-trip failed")
			_check(loaded_chart.play_time_ms == 123456, "play time round-trip failed")
			_check(loaded_chart.timings.size() == 2, "timings round-trip failed")
			_check(loaded_chart.timings[1].bpm == 180.0, "timing object round-trip failed")

	var first_score := _make_score(-1)
	first_score.played_at = 1000
	first_score.total_score = 99.5
	first_score.score = 9950.0
	first_score.max_score = 10000.0
	first_score.notes = 100
	first_score.perfect_plus = 90
	first_score.perfect = 10
	first_score.high_combo = 100
	first_score.avg_signed_timings = -1.25
	first_score.unstable_rate = 12.3
	_check(database.record_play(chart, first_score) > 0, database.get_last_error_message())

	var second_score := _make_score(-1)
	second_score.played_at = 2000
	second_score.total_score = 90.0
	_check(database.record_play(chart, second_score) > 0, database.get_last_error_message())

	var best: MockScore = database.get_best_play(chart, _make_score)
	_check(best != null, "best play should be a Score object")
	if best != null:
		_check(best.stored_total_score == 99.5, "best play returned the wrong score")
		_check(best.unstable_rate == 12.3, "unstable rate round-trip failed")

	var recent := database.get_recent_plays(_make_score)
	_check(recent.size() == 2, "expected two recent Score objects")
	if recent.size() == 2:
		_check(recent[0].played_at == 2000, "recent plays should be newest first")

	var moved_set := MockChartSet.new()
	moved_set.uuid = chart_set.uuid
	moved_set.folder_name = "moved_test_set"
	_check(database.upsert_chart_set(moved_set) == chart_set_id, "chart set UUID should preserve DB identity across moves")
	moved_set.db_id = chart_set_id
	chart.chart_set = moved_set
	chart.file_name = "renamed.dansu"
	_check(database.upsert_chart(chart) == chart_id, "chart UUID should preserve DB identity across moves")
	var moved_library := database.load_chart_library(_make_chart_set, _make_chart, _make_timing)
	_check(moved_library[0].folder_name == moved_set.folder_name, "chart set move should update its folder")
	_check(moved_library[0].charts[0].file_name == chart.file_name, "chart move should update its file name")
	_check(database.get_best_play(chart, _make_score) != null, "chart scores should survive UUID moves")

	var bad_chart := MockChart.new()
	bad_chart.db_id = 999999
	_check(database.record_play(bad_chart, _make_score(-1)) == -1, "foreign key violation should fail")

	var second_scan := database.begin_chart_scan()
	_check(database.upsert_chart_set(moved_set, second_scan) == chart_set_id, database.get_last_error_message())
	_check(database.finish_chart_scan(second_scan), database.get_last_error_message())
	var missing_library := database.load_chart_library(_make_chart_set, _make_chart, _make_timing)
	_check(missing_library.size() == 1 and missing_library[0].charts.is_empty(), "untouched chart should become unavailable")
	_check(database.set_chart_present(chart_id, true), database.get_last_error_message())
	_check(database.load_chart_library(_make_chart_set, _make_chart, _make_timing).size() == 1, "presence restore should work")

	database.close()
	_finish()


func _make_chart_set(_db_id: int) -> MockChartSet:
	return MockChartSet.new()


func _make_chart(_db_id: int) -> MockChart:
	return MockChart.new()


func _make_timing() -> MockTiming:
	return MockTiming.new()


func _make_score(_db_id: int) -> MockScore:
	return MockScore.new()


func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures += 1
		push_error("DANSUSQL_SMOKE_FAILED: %s" % message)
	return condition


func _finish() -> void:
	if failures == 0:
		print("DANSUSQL_SMOKE_OK")
		quit(0)
		return
	print("DANSUSQL_SMOKE_FAILURE_COUNT=%d" % failures)
	quit(1)
