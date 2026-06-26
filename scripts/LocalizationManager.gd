extends Node

signal locale_changed(locale: String)

const SETTINGS_FILE_PATH: String = "user://settings.cfg"
const SETTINGS_SECTION: String = "localization"
const SETTINGS_LOCALE_KEY: String = "locale"
const DEFAULT_LOCALE: String = "en"
const SUPPORTED_LOCALES: Array[String] = ["en", "zh"]
const STRINGS_PATH: String = "res://localization/strings.csv"

var current_locale: String = DEFAULT_LOCALE
var _loaded_translations: Array[Translation] = []


func _ready() -> void:
	_load_translations()
	set_locale(_load_saved_locale(), false)


func get_supported_locales() -> Array[String]:
	return SUPPORTED_LOCALES.duplicate()


func get_current_locale() -> String:
	return current_locale


func get_locale_label(locale: String) -> String:
	match _normalize_locale(locale):
		"zh":
			return tr("LANGUAGE_CHINESE")
		_:
			return tr("LANGUAGE_ENGLISH")


func set_locale(locale: String, save: bool = true) -> void:
	var normalized: String = _normalize_locale(locale)
	if normalized.is_empty():
		normalized = DEFAULT_LOCALE

	TranslationServer.set_locale(normalized)
	current_locale = normalized
	if save:
		_save_locale(normalized)
	locale_changed.emit(current_locale)


func translate_text(text: String) -> String:
	if text.is_empty():
		return text
	return tr(text)


func _normalize_locale(locale: String) -> String:
	var normalized: String = locale.strip_edges().to_lower()
	if normalized.begins_with("zh"):
		normalized = "zh"
	elif normalized.begins_with("en"):
		normalized = "en"
	if SUPPORTED_LOCALES.has(normalized):
		return normalized
	return DEFAULT_LOCALE


func _load_saved_locale() -> String:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SETTINGS_FILE_PATH) != OK:
		return DEFAULT_LOCALE
	return String(config.get_value(SETTINGS_SECTION, SETTINGS_LOCALE_KEY, DEFAULT_LOCALE))


func _save_locale(locale: String) -> void:
	var config: ConfigFile = ConfigFile.new()
	var load_err: int = config.load(SETTINGS_FILE_PATH)
	if load_err != OK and load_err != ERR_FILE_NOT_FOUND:
		return
	config.set_value(SETTINGS_SECTION, SETTINGS_LOCALE_KEY, locale)
	config.save(SETTINGS_FILE_PATH)


func _load_translations() -> void:
	var file: FileAccess = FileAccess.open(STRINGS_PATH, FileAccess.READ)
	if file == null:
		push_error("Failed to load localization file: %s" % STRINGS_PATH)
		return

	var header: PackedStringArray = file.get_csv_line()
	if header.size() < 2:
		push_error("Localization file must include key and locale columns: %s" % STRINGS_PATH)
		return

	var locales: Array[String] = []
	var translations: Dictionary = {}
	for i in range(1, header.size()):
		var locale: String = _normalize_locale(String(header[i]))
		if locale.is_empty() or translations.has(locale):
			continue
		var translation: Translation = Translation.new()
		translation.locale = locale
		translations[locale] = translation
		locales.append(locale)

	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.is_empty():
			continue
		var key: String = String(row[0])
		if key.strip_edges().is_empty():
			continue
		for i in range(locales.size()):
			var locale: String = locales[i]
			var column_index: int = i + 1
			var value: String = key
			if column_index < row.size() and not String(row[column_index]).is_empty():
				value = String(row[column_index])
			(translations[locale] as Translation).add_message(key, _decode_csv_text(value))

	for locale in locales:
		var translation_to_add: Translation = translations[locale] as Translation
		TranslationServer.add_translation(translation_to_add)
		_loaded_translations.append(translation_to_add)


func _decode_csv_text(value: String) -> String:
	return value.replace("\\n", "\n")
