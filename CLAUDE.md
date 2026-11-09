# Backrooms: Комплекс — Godot 4.7.2 (Forward+), Windows

Found-footage хоррор по лору Backrooms Кейна Парсонса (Kane Pixels): Сан-Хосе, 14.07.1990, герой с видеокамерой
проваливается из парка в Комплекс. Выходы: нулевые зоны (всегда смерть: океан, небо, подвал с заколоченным люком,
шоссе, полость в стене) или Порог Async (газ → изолятор B → «навсегда»). Смерть — красный экран и выход в меню.

## Запуск и сборка
- Godot: `%USERPROFILE%\tools\godot\Godot_v4.7.2-stable_win64_console.exe`, шаблоны экспорта установлены.
- `python tools/build.py [--fast]` → `release/BackroomsComplex_Setup.exe` + `release/BackroomsComplex/`.
- Генераторы (результаты в репо): `tools/tex/make_textures.py` → tex/, `tools/audio/make_audio.py [префиксы]` → audio/,
  `tools/voice/make_voice.py` (Windows TTS: RU Irina/Pavel через WinRT, EN Zira через SAPI) → voice/,
  `tools/models/fetch_models.py` (Poly Haven CC0, glTF 1k) → models/ (+CREDITS.txt),
  `tools/models/fetch_humans.py` (Microsoft Rocketbox, MIT: FBX + цветные TGA, ужаты до 1024) → humans/ (+CREDITS.txt),
  `tools/tex/make_graffiti.py` — надписи graf.* «от руки» в tex/graf_<ключ>_<ru|en>.png (Segoe Print: у Ink Free «Н»/«H» как «#»).
- После импорта всегда `python tools/fix_imports.py` и повторный импорт: мип-карты/VRAM для tex и моделей, loop=true для
  звуков из списка LOOPS. Новые зацикленные звуки добавлять в LOOPS и там, и в make_audio.py.

## Отладка (аргументы после `--`)
`tools/dev.sh shot <png> <сек> [args]` (несколько png через `;`, `--every=N`), `tools/dev.sh import`.
- `--scene=complex|lower|park|ending|gallery`, `--seed=N`, `--place=<ключ LayerData.places>` `--dx/--dz`, `--yaw/--pitch`, `--pos=x,y,z`
- `--kind=ocean|sky|basement|highway|wall|async` (ending), `--force_end=…`, `--auto_hatch` (подвал), `--fall_at=сек` (парк)
- `--auto` бот бродит и пишет `BOT …` в лог, `--botrun`, `--lf_now`, `--lf_chase`, `--god`, `--vhs=0..1.5`
- `--set=copies|copies2|objects|async|lifeform|anim|tv|models0..3` для gallery (камера: `--cx --dist --cy --ly --ox`);
  в парке `--pos=x,y,z --yaw --pitch` (углы в радианах).
- `--tour=<папка> [--only=подстрока]` — обойти все `room_*` текущего слоя и снять по два кадра; `--crouch` — присесть;
  `--gen_prof` — время этапов генерации.
- `--world=base|adventure|survival|polygon` — режим мира; `--menu=worlds|polygon|rooms` — открыть экран меню;
  `--poly=park|l0|l1|place:<ключ>[:1]|ending:<вид>|death|gallery:<набор>` — запуск как из полигона;
  `--fc_test` — проверка мыши и свободной камеры (G) через настоящий ввод.
- `--walk=<сек> [--walk_delay=с] [--run]` — встать лицом к `<место>_c` и идти вперёд, печатая высоту/ранение (`WALK …`);
  `--hurt=0..1` — ранение на старте; `--blackout` — отключение света через 3 с (печатает `POWER …`);
  `--tour_prefix=find_` — тур по находкам; места `hole_<k>`/`find_<вид>_<k>` (+ `_c` — точка, куда смотреть).
- `tools/dev/aabb.gd` — габариты моделей (`--headless --script`).

## Архитектура (src/)
- `main.gd` — 3D в SubViewport 480 строк → TextureRect с `shaders/vhs.gdshader`; OSD камеры (`render/osd.gd`) внутри кадра.
  SubViewport без контейнера сам ввод не получает: `main._unhandled_input` пересылает события через `vp.push_input`.
- Режимы мира: `Cfg.world` (сохраняется) → `Game.mode`; правила — `Game.monsters()/stamina_on()/speed_mode()/freecam_ok()`.
  Базовый: без выносливости; Приключение: ×1,5, без монстров, G — `player/freecam.gd`; Выживание: выносливость, Сущность
  раньше/чаще, две плачущие копии; Полигон: меню в `ui/menus.gd`, запуски `Game.poly_*`, мир полигона с сидом 1990
  строится один раз. Флаги запуска полигона — `Cfg.flags` (те же ключи, что у аргументов: god, place, set, lf_now…).
- autoload: `Cfg` (настройки, ввод, аргументы), `Loc` + `texts.gd` (ключ → [ru, en]; sign./osd. — англ. в «смешанном»),
  `Snd` (шины, варианты `_N`, петли), `Game` (поток игры, генерация мира в WorkerThreadPool во время парка).
- `world/layer_data.gd` — тор 384×384 клеток по 2.4 м, стены на рёбрах; `worldgen.gd` — два слоя, особые комнаты, кабели, декор.
- `world/chunk_builder.gd` — меши чанка 12×12 в потоке; свет ламп «запечён» в цвет вершин (r ровный, g мигающий, b красный,
  a группа мигания; UV2.x — AO). Шейдеры `arch`/`prop`/`decal` unshaded, глобальные uniform `g_*` в project.godot.
- `world/worldgen_rooms.gd` — каталог «странных комнат» (PLAN: тип, слой, количество, кольцо расстояний, размер) и
  `sprinkle` — мелочи по миру понемногу; места пишутся в `places["room_<тип>_<k>"]`. Строители предметов этих комнат —
  `world/props_rooms.gd` (Props делегирует туда неизвестные виды). `world/tv.gd` (TVHub) — телеканалы 2D-SubViewport.
- Высота пола по клеткам: `fh` (дм от floor_y), `ramp` (1..4 — пандус к стороне d+1, 5..8 — лестница). Пол/обрывы/стены до дна
  и наклонные коллизии строит `chunk_builder` (`_ramp`, `_drop_face`); проходимость по высоте — `step_ok` (обрывы > 0,4 м
  непроходимы для ИИ, бота и кабелей). `LD.ground(p)` — пол под точкой (монстры стоят на нём). Потолок по умолчанию `LD.CEIL`=32;
  комнаты, где вещи держатся за потолок, ставят 27. Предметы «в потолке» берут `d.ceil` (`Complex.ceil_at`).
  Конструкции (котлован, терраса, пропасть, лестница вниз, пандус, дыры, балконы, высокий зал, колодец) и редкие провалы
  в коридорах — `worldgen_rooms.gd`; находки (химзащита, одежда, камера на штативе, следы волочения, дверь, ночёвка) —
  `sprinkle_finds`. Неглубокие провалы ≤ 1,5 м: герой подтягивается на уступ (player `_try_mantle`); глубже 7 м — смерть.
- Ранение без полоски: `Complex.hurt` 0..1 → `main.hurt` → `vhs.gdshader` (красное от краёв), падение с высоты считается
  в `_on_landed`; в яму на нижний слой и при приземлении из парка — без урона (`_no_fall_t`).
- Свет: группы мигания `posmod(x*7+z*13, 7)` с характерами (`FLICK_KIND`), звук ближайшей лампы; питание `g_power`
  (просадки и редкие отключения, `_update_power`). Только жёлтые обои: зон «старое крыло», бетон, плитка в мире нет.
- Концовки (`scenes/endings.gd`): смерть везде через красное (`_hurt_tick` → `_death` → карточка): океан (плыть вверх),
  небо → лес, подвал (люк ранит), шоссе, стена, космос (смотреть на Землю), Async (газ в изоляторе, вид с пола).
- `layer_data.used`: 1 — особая комната (сюда не ставятся случайные копии/предметы из `_scatter` и `sprinkle`), 2 — свет задан вручную.
- `world/complex.gd` — подгрузка чанков, слои, экспозиция, мигание, события (яма → слой 1, лестница Async, Порог, нулевая зона).
- `world/human.gd` — люди: модель Rocketbox (скелет Bip01/Bip02) или запасной вариант из примитивов (`--prim_humans`).
  Позы задаются суставами-посредниками j[...] (оси модели), `_drive()` каждый кадр переводит их в кости (руки из A-позы
  опускаются поправкой `_off`). Предметы в руку — `hand("l"/"r")`, параметры шейдера копии — `tune({...})`.
- `world/props.gd` — все предметы; `Props.model()` берёт модель Poly Haven (в Комплексе материалы → prop-шейдер через `models.gd`,
  в парке/концовках `Props.park_mode = true` — PBR). `human.gd` — люди/копии; `lifeform.gd` — Сущность (A* в `pathfind.gd`);
  `stalker.gd` — плачущая копия нижнего слоя.
- `scenes/park.gd`, `scenes/endings.gd`, `ui/*` (меню/пауза/настройки, записки, карточка концовки).

## Подводные камни
- GDScript 4.7: `:=` от Variant — ошибка; Packed-массивы из словаря менять через локальную переменную и записывать обратно.
- Не называть методы `_set`/`_get` (виртуальные Object). Масштабированный Basis не слерпить — через quaternion.
- Пользователь просил: случайные выходы ТОЛЬКО смертельные; подвал — люк, который не открывается; без лишних механик.
