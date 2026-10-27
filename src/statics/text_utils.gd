class_name TextUtils
## Shared plain-text helpers for BBCode-carrying strings.
##
## static_data.json descriptions render through RichTextLabels, but
## several surfaces are plain text (Control tooltips, the output
## panel's FoldableContainer title) — strip the markup there instead
## of showing `[img …]…[/img]` verbatim.

static var _bbcode_tag_re: RegEx = RegEx.create_from_string(
		"\\[/?[a-zA-Z][^\\]]*\\]")

# `[img ...]res://path[/img]` blocks must drop their *content* too —
# a bare tag-strip would leave the resource path in the text.
static var _bbcode_img_re: RegEx = RegEx.create_from_string(
		"\\[img[^\\]]*\\][^\\[]*\\[/img\\]")


## Drop every BBCode tag (and img tags' resource-path content) from
## `text`. Backslash-close typos (`[\bold]`) are normalized to
## forward-slash closes before stripping so author typos still
## produce a clean preview.
static func strip_bbcode(text: String) -> String:
	var normalized: String = text.replace("[\\", "[/")
	normalized = _bbcode_img_re.sub(normalized, "", true)
	return _bbcode_tag_re.sub(normalized, "", true)
