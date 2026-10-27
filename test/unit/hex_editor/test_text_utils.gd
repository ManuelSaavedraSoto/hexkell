extends GutTest
## TextUtils.strip_bbcode — plain-text projection of the BBCode that
## static_data.json descriptions carry, used wherever a Control
## tooltip / title would otherwise render markup verbatim.


func test_plain_text_passthrough() -> void:
	assert_eq(TextUtils.strip_bbcode("no markup here"), "no markup here")


func test_strips_simple_and_parameterized_tags() -> void:
	assert_eq(
			TextUtils.strip_bbcode("a [b]bold[/b] [color=#ffd86b]gold[/color] word"),
			"a bold gold word")


func test_img_blocks_drop_their_resource_path_content() -> void:
	var s := "wire a [img valign=center, width=16]res://assets/icons/hexagons/hollow_hex.tres[/img]hex in"
	assert_eq(TextUtils.strip_bbcode(s), "wire a hex in")


func test_backslash_close_typo_normalized() -> void:
	assert_eq(TextUtils.strip_bbcode("[bold]hi[\\bold]"), "hi")


func test_static_data_icon_paths_exist() -> void:
	# Every [img]res://…[/img] in chapter + job descriptions must point
	# at a real resource — a typo'd icon path would render as a missing
	# texture square in the dialogs.
	var data: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/static_data.json"))
	var img_re := RegEx.create_from_string("\\[img[^\\]]*\\]([^\\[]*)\\[/img\\]")
	var texts: Array[String] = []
	for chapter in data.get("chapters", {}).values():
		texts.append(String(chapter.get("description", "")))
	for job in data.get("jobs", {}).values():
		texts.append(String(job.get("description", "")))
	var checked := 0
	for text in texts:
		for m in img_re.search_all(text):
			var path := m.get_string(1).strip_edges()
			assert_true(ResourceLoader.exists(path),
					"Icon path should exist: %s" % path)
			checked += 1
	assert_gt(checked, 0, "Chapters/jobs should carry img icon BBCode")
