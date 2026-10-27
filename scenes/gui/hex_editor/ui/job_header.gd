extends VBoxContainer
## Top-bar job header — name label + description label (RichTextLabel
## for the BBCode the static_data.json job descriptions carry). Pure
## view; editor pushes selection state in via `set_job(job_or_null)`.

@onready var name_label: Label = $JobNameLabel
@onready var description_label: RichTextLabel = $JobDescriptionLabel


# `selected_id` is the currently-pinned job id; pass `""` for the
# "no job" state. `job` is the dict from TemplateManager for that
# id (empty for the no-selection state). `solved` flips the name
# label to green with a leading ✓.
func set_job(selected_id: String, job: Dictionary, solved: bool) -> void:
	if name_label == null or description_label == null:
		return
	if selected_id.is_empty():
		name_label.text = "No job selected"
		name_label.add_theme_color_override("font_color", Color(0.78, 0.85, 0.95))
		description_label.text = (
				"Pick a job (%s) or build freely.  %s runs the program."
				% [
					InputDisplay.action_bbcode("jobs_cycle_next"),
					InputDisplay.action_bbcode("code_run"),
				])
		return
	if job.is_empty():
		name_label.text = "(missing job)"
		description_label.text = ""
		return
	var prefix := "✓ " if solved else ""
	name_label.text = "%s%s" % [prefix, String(job.get("name", selected_id))]
	name_label.add_theme_color_override(
		"font_color",
		Color(0.6, 1.0, 0.7) if solved else Color(1.0, 0.92, 0.55),
	)
	var lines: Array[String] = [String(job.get("description", ""))]
	if job.has("variables"):
		lines.append("[color=#9fcfff]Inputs:[/color] %s" % str(job["variables"]))
	description_label.text = "\n".join(lines)
