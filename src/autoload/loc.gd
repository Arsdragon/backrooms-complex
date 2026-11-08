extends Node
## Локализация. Ключи с префиксом sign./osd. — «надписи мира» (в смешанном режиме по-английски),
## остальное (ui., sub., note., graf., radio., end.) — по-русски в смешанном режиме.

const Texts := preload("res://src/autoload/texts.gd")


func lang_for(key: String) -> int:
	var mode := Cfg.lang
	if mode == "ru":
		return 0
	if mode == "en":
		return 1
	if key.begins_with("sign.") or key.begins_with("osd."):
		return 1
	return 0


func t(key: String) -> String:
	var row: Variant = Texts.T.get(key)
	if row == null:
		push_warning("Нет текста: " + key)
		return key
	var arr: Array = row
	var i := lang_for(key)
	if i >= arr.size() or String(arr[i]) == "":
		i = 0
	return String(arr[i])


func has(key: String) -> bool:
	return Texts.T.has(key)


func is_en(key: String) -> bool:
	return lang_for(key) == 1


## Ключи, начинающиеся с префикса (для случайного выбора надписей и т.п.)
func keys_with(prefix: String) -> Array:
	var out := []
	for k in Texts.T.keys():
		if String(k).begins_with(prefix):
			out.append(k)
	out.sort()
	return out


## Голосовая дорожка для реплики: voice/<key>_<ru|en>.ogg (если есть)
func voice_path(key: String) -> String:
	var suffix := "en" if lang_for(key) == 1 else "ru"
	return "res://voice/%s_%s.ogg" % [key.replace(".", "_"), suffix]
