# Гайд для новичков / Beginner's guide

🇷🇺 [Русский](#русский) · 🇬🇧 [English](#english)

## Русский

### Что нужно
- Компьютер с **Windows 10 или 11** (64-bit). Mac и Linux не поддерживаются.
- Видеокарта с поддержкой **Vulkan** (почти любая от 2016 года; встроенной может не хватить для плавной игры).
- Около **1 ГБ** свободного места. Интернет нужен только для скачивания.
- Наушники — игра очень атмосферная.

### Установка и запуск
1. Откройте страницу [Releases](https://github.com/Arsdragon/backrooms-complex/releases/latest).
2. В разделе **Assets** нажмите на **`BackroomsComplex.exe`** — начнётся загрузка (файл большой, ≈ 780 МБ, подождите).
3. Положите файл в любую папку (например, «Игры») и запустите двойным щелчком. **Ставить ничего не нужно**: игра целиком в этом одном файле.
4. Если Windows показывает синее окно «Windows защитила ваш компьютер» (SmartScreen), нажмите **«Подробнее» → «Всё равно выполнить»**.
   Так бывает с любыми программами без платной подписи издателя. Игра с открытым исходным кодом: всё, что она делает, видно в этом репозитории.
5. Если антивирус удалил или заблокировал файл — добавьте его в исключения и скачайте снова.

Первый запуск может занять до минуты: игра распаковывает ресурсы и компилирует шейдеры. Дальше будет быстрее.

### Как играть
Игра начинается в парке, вы смотрите через видеокамеру. Парк можно пропустить — **удерживайте Пробел или Enter** около секунды.

| Действие | Клавиши |
|---|---|
| Ходьба | W A S D или стрелки |
| Камера | мышь |
| Бег | Shift |
| Присесть | Ctrl или C |
| Действие, использовать | E или F |
| Пропустить парк | удерживать Пробел / Enter |
| Пауза и меню | Esc или P |
| Свободная камера (режим «Приключение») | G |

Режимы мира выбираются в меню: **Базовый**, **Приключение** (без монстров — удобно, чтобы просто осмотреться), **Выживание** (выносливость, монстры чаще),
**Полигон** (можно сразу открыть любое место или концовку). Язык игры и качество картинки переключаются в **Настройках**.

### Советы
- Свет в Комплексе мигает и гаснет — это нормально, не стойте в темноте надолго.
- Все выходы из Комплекса смертельные: смерть — красный экран и возврат в меню. Это задумано.
- Высоты больше 7 метров — смертельны; небольшие уступы (до 1,5 м) можно перелезть.
- Если игра тормозит: понизьте разрешение и качество в Настройках, закройте браузер и другие тяжёлые программы.

### Если что-то не работает
| Проблема | Решение |
|---|---|
| Окно не открывается | Обновите драйвер видеокарты (NVIDIA, AMD или Intel) — нужна поддержка Vulkan. |
| Чёрный экран или вылет | Запустите от имени обычного пользователя, не из архива: сначала скопируйте файл в обычную папку. |
| Нет звука | Проверьте устройство вывода звука в Windows и громкость игры в Настройках. |
| Файл не скачивается целиком | Используйте другой браузер или менеджер загрузок; проверьте свободное место на диске. |

Нашли ошибку? Создайте [Issue](https://github.com/Arsdragon/backrooms-complex/issues) и опишите, что произошло.

---

<a id="english"></a>

## English

### What you need
- A PC with **Windows 10 or 11** (64-bit). Mac and Linux are not supported.
- A graphics card with **Vulkan** support (almost any since 2016; integrated graphics may be too slow).
- About **1 GB** of free disk space. The internet is only needed to download the game.
- Headphones — the game is very atmospheric.

### Install and run
1. Open the [Releases](https://github.com/Arsdragon/backrooms-complex/releases/latest) page.
2. Under **Assets**, click **`BackroomsComplex.exe`** — the download starts (the file is big, ≈ 780 MB, please wait).
3. Put the file in any folder (e.g. "Games") and double-click it. **Nothing to install**: the whole game is in this single file.
4. If Windows shows a blue "Windows protected your PC" window (SmartScreen), click **"More info" → "Run anyway"**.
   This happens with any program that has no paid publisher signature. The game is open source: everything it does is visible in this repository.
5. If your antivirus removed or blocked the file, add it to exclusions and download it again.

The first launch can take up to a minute: the game unpacks resources and compiles shaders. Later launches are faster.

### How to play
The game starts in a park, seen through a camcorder. You can skip the park — **hold Space or Enter** for about a second.

| Action | Keys |
|---|---|
| Walk | W A S D or arrow keys |
| Look | mouse |
| Run | Shift |
| Crouch | Ctrl or C |
| Interact | E or F |
| Skip the park | hold Space / Enter |
| Pause and menu | Esc or P |
| Free camera (Adventure mode) | G |

World modes are chosen in the menu: **Base**, **Adventure** (no monsters — good for just looking around), **Survival** (stamina, monsters appear more often),
**Polygon** (jump straight to any place or ending). Language and picture quality are in **Settings**.

### Tips
- Lights in the Complex flicker and go out — that is normal, don't stand in the dark for long.
- Every exit from the Complex is deadly: death is a red screen and a return to the menu. This is intended.
- Drops deeper than 7 meters are fatal; small ledges (up to 1.5 m) can be climbed.
- If the game lags: lower resolution and quality in Settings, close your browser and other heavy programs.

### Troubleshooting
| Problem | Fix |
|---|---|
| The window does not open | Update your graphics driver (NVIDIA, AMD or Intel) — Vulkan support is required. |
| Black screen or crash | Copy the file to a normal folder first instead of running it from inside an archive. |
| No sound | Check the Windows audio output device and the game volume in Settings. |
| The file does not download fully | Try another browser or a download manager; check free disk space. |

Found a bug? Open an [Issue](https://github.com/Arsdragon/backrooms-complex/issues) and describe what happened.
