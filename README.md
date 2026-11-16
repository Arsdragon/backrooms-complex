# Backrooms: Комплекс / Backrooms: The Complex

**🇷🇺 Русский** · [🇬🇧 English](#english)

Found-footage хоррор по лору Backrooms Кейна Парсонса (Kane Pixels). Сан-Хосе, 14 июля 1990 года: герой с видеокамерой
проваливается из парка в Комплекс — бесконечные жёлтые коридоры, гудящие лампы, сырой ковёр. Игра на **Godot 4.7**, только Windows.

> 🤖 **Игра целиком написана нейросетями Claude.** Половину работы сделал **Claude Opus 5.5**, вторую половину — **Claude Fable 5.2**
> (режим Ultracode), через Claude Code. Человек ставил задачи и проверял результат. Затраты — в [docs/COSTS.md](docs/COSTS.md).

## Скачать и запустить (один файл)

1. Откройте [Releases](https://github.com/Arsdragon/backrooms-complex/releases/latest).
2. Скачайте **`BackroomsComplex.exe`** (≈ 780 МБ) — это вся игра в одном файле, установка не нужна.
3. Запустите двойным щелчком. Подробная инструкция для новичков: **[docs/GUIDE.md](docs/GUIDE.md)**.

## Что внутри
- Парк 1990 года с видеокамерой (VHS-плёнка, автоирис, ореолы ламп), затем провал в Комплекс.
- Бесконечный процедурный мир: комнаты, «странные» места, спуски, провалы, обжитые зоны.
- Сущность и плачущие копии людей. Выходы — только смертельные: океан, небо, шоссе, полость в стене, космос или Порог Async.
- Режимы: Базовый, Приключение (без монстров), Выживание, Полигон. Русский и английский язык.

## Управление
Подробно — в [docs/GUIDE.md](docs/GUIDE.md). Кратко: WASD — ходьба, мышь — камера, Shift — бег, Ctrl — присесть,
E/F — действие, Пробел/Enter (удерживать) — пропустить парк, Esc — пауза.

## Сборка из исходников
Нужны Godot 4.7.2 с шаблонами экспорта, Python 3, Pillow, numpy, scipy, ffmpeg. Затем:

```bash
python tools/build.py          # полная сборка → release/
python tools/build.py --fast   # без перегенерации графики и звука
```

Генераторы текстур, звуков, голосов и моделей лежат в `tools/`. Описание архитектуры — в [CLAUDE.md](CLAUDE.md) (на русском).

## Затраты на создание
≈ **79 часов** от начала до конца, из них **≈ 12 часов активной работы**, **4 234 запроса**, **≈ 1,48 млрд токенов**,
**≈ $613,47** по ценам API. Работа поделена **50% Opus 5.5 / 50% Fable 5.2**. Таблица — в [docs/COSTS.md](docs/COSTS.md).

## Лицензии и источники
Модели — Poly Haven (CC0), люди — Microsoft Rocketbox (MIT). Подробности — в [CREDITS.md](CREDITS.md).
Backrooms — фан-проект по мотивам работ Kane Parsons; не связан с автором и студией A24.

---

<a id="english"></a>

# Backrooms: The Complex

[🇷🇺 Русский](#backrooms-комплекс--backrooms-the-complex) · **🇬🇧 English**

A found-footage horror game set in the Backrooms universe of Kane Parsons (Kane Pixels). San Jose, July 14, 1990: a man with a camcorder
falls out of a park into the Complex — endless yellow corridors, humming lights, damp carpet. Built with **Godot 4.7**, Windows only.

> 🤖 **The whole game was written by Claude AI models.** Half of the work was done by **Claude Opus 5.5**, the other half by **Claude Fable 5.2**
> (Ultracode mode), through Claude Code. The human gave tasks and checked results. Costs: [docs/COSTS.md](docs/COSTS.md).

## Download and play (single file)

1. Open [Releases](https://github.com/Arsdragon/backrooms-complex/releases/latest).
2. Download **`BackroomsComplex.exe`** (≈ 780 MB) — the whole game in one file, no installation.
3. Double-click it. Step-by-step beginner guide: **[docs/GUIDE.md](docs/GUIDE.md)**.

## What's inside
- A 1990 park seen through a camcorder (VHS tape look, auto-iris, light halos), then the fall into the Complex.
- An endless procedural world: rooms, strange places, descents, pits, lived-in areas.
- The Entity and crying copies of people. Every exit is deadly: ocean, sky, highway, a hollow in the wall, space, or the Async Threshold.
- Modes: Base, Adventure (no monsters), Survival, Polygon. Russian and English languages.

## Controls
Details in [docs/GUIDE.md](docs/GUIDE.md). In short: WASD to walk, mouse to look, Shift to run, Ctrl to crouch,
E/F to interact, hold Space/Enter to skip the park, Esc to pause.

## Building from source
You need Godot 4.7.2 with export templates, Python 3, Pillow, numpy, scipy, ffmpeg. Then:

```bash
python tools/build.py          # full build → release/
python tools/build.py --fast   # skip texture and audio regeneration
```

Generators for textures, sounds, voices and models are in `tools/`. Architecture notes are in [CLAUDE.md](CLAUDE.md) (Russian).

## Cost of creation
≈ **79 hours** from start to finish, of which **≈ 12 hours of active work**, **4,234 model requests**, **≈ 1.48 billion tokens**,
**≈ $613.47** at API prices. The work was split **50% Opus 5.5 / 50% Fable 5.2**. Table: [docs/COSTS.md](docs/COSTS.md).

## Licenses and credits
Models: Poly Haven (CC0), people: Microsoft Rocketbox (MIT). See [CREDITS.md](CREDITS.md).
Backrooms is a fan project inspired by the work of Kane Parsons; it is not affiliated with him or A24.
