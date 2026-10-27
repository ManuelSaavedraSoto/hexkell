extends Control
## Credits screen — reachable from the main menu. Content is curated from
## CREDITS.md. The "Music by jhaeka" line is a license-REQUIRED attribution
## and must stay visible to end users; don't remove it. Back / Escape returns
## to the main menu. Source links open in the system browser.

@onready var back_button: Button = %BackButton
@onready var credits_label: RichTextLabel = %CreditsLabel

const CREDITS_BBCODE := """[center][b]Hexkell[/b][/center]

An educational game for learning functional programming by [b]Manuel Saavedra Soto[/b], developed as a memoria de título at the Facultad de Ciencias Físicas y Matemáticas, Universidad de Chile.

All original code, the internal functional language and its interpreter, and the procedurally drawn hexes, connections and grid are the work of the author. Third-party assets are used under their respective licenses.

[b]Fonts[/b]
• Mork Dungeon — Mark Gosbell · [url=https://markgosbell.itch.io/mork-dungeon]markgosbell.itch.io[/url] · SIL Open Font License

[b]Graphics & UI Icons[/b]
• Input Prompts · Board Game Icons · Fantasy UI Borders · Game Icons — Kenney · [url=https://kenney.nl]kenney.nl[/url] · CC0

[b]Sound Effects[/b]
• Interface Sounds — Kenney · [url=https://kenney.nl/assets/interface-sounds]kenney.nl[/url] · CC0

[b]Music[/b]
• [b]Music by jhaeka[/b] — Short, Loopable Background Music · [url=https://joshuuu.itch.io/short-loopable-background-music]joshuuu.itch.io[/url]
"""


func _ready() -> void:
	credits_label.text = CREDITS_BBCODE
	back_button.pressed.connect(_on_back_pressed)
	credits_label.meta_clicked.connect(_on_meta_clicked)


# RichTextLabel [url=…] links carry their URL as the meta payload.
func _on_meta_clicked(meta: Variant) -> void:
	OS.shell_open(String(meta))


func _on_back_pressed() -> void:
	SceneManager.go_to_main_menu()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
