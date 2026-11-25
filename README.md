# SmartumSwitch

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](https://github.com/spirkoff/SmartumSwitch/blob/main/LICENSE)
[![Release](https://img.shields.io/github/v/release/spirkoff/SmartumSwitch)](https://github.com/spirkoff/SmartumSwitch/releases/latest)
![platform: Linux | Wayland](https://img.shields.io/badge/platform-Linux%20%7C%20Wayland-blue)

Свободный автопереключатель раскладки RU/EN. Исправляет текст, набранный не в той раскладке (QWERTY ⇄ ЙЦУКЕН), как Punto Switcher. Полностью безвозмездно, без рекламы, без телеметрии и без установки посторонних программ. Лицензия MIT. © 2026 smARTum.

[English below](#english)

## Что это

SmartumSwitch автоматически исправляет слово, набранное в неправильной раскладке: `ghbdtn ` становится `привет `, `руддщ ` — `hello `, и раскладка переключается сама. Работает в обе стороны.

Сделано в smARTum — мебель, Крым.

## Состояние

- **Linux (Wayland) готов.** Проверено на elementary OS 8 (Pantheon/Gala, раскладки `us` + `ru`). Служба пользователя systemd, evdev и uinput. Подробности: `linux/README.md`.
- **Windows — бета** (MVP 0.2, один файл `SmartumSwitch-win-x64.exe` для Windows 10/11 x64). На реальном оборудовании ещё не проверялась. Подробности: `windows/README.md`.
- **macOS запланирована.** Общие правила ядра уже описаны для Linux, Windows и macOS (`core/RULES.md`); каталога macOS в этом выпуске нет.

## Быстрый старт (Linux)

```bash
git clone https://github.com/spirkoff/SmartumSwitch.git && cd SmartumSwitch/linux && ./install.sh
```

Удаление: `git clone https://github.com/spirkoff/SmartumSwitch.git && cd SmartumSwitch/linux && ./uninstall.sh`.

Нужны раскладки `us` и `ru`. Установщик ставит пакеты, правило udev и пользовательскую службу `smartum-switch`. Запускайте его обычным пользователем.

## Зависимости (Linux)

Установщик `linux/install.sh` ставит только пакеты, без которых программа не работает. Рекламу, телеметрию и посторонние программы он не ставит.

- `python3-evdev` — читать нажатия клавиатуры и создать виртуальную клавиатуру (`uinput`), чтобы стереть слово и набрать его заново.
- `libhunspell-1.7-0`, `hunspell-ru`, `hunspell-en-us` — словари, по которым программа отличает настоящее слово от набранного не в той раскладке.
- `wl-clipboard` — для клавиши Pause: взять выделенный текст, исправить его и вернуть прежний буфер обмена.
- `libnotify-bin` — короткое уведомление, когда автоисправление включают или выключают (Shift+Pause).

Python 3 и systemd в таких системах обычно уже есть. Для горячей клавиши Pause на GNOME/Pantheon используется уже установленный `gsettings`. Отдельная программа вроде ydotool не нужна и не устанавливается: ввод идёт через `uinput`.

Версия для Windows — один файл, без установщика и без прав администратора; посторонние программы она не ставит.

## Клавиши

- **Pause** — исправить выделенный текст (если ничего не выделено — последнее слово). Буфер обмена сохраняется.
- **Shift+Pause** — включить или выключить автоисправление. То же делает `smartum-switch toggle`.
- **Backspace** сразу после исправления — откат: слово возвращается как было и до конца сеанса больше не трогается.

Однобуквенные слова не исправляются. Двухбуквенные — только частые (`yt` → `не`). Терминалы, окна паролей и сочетания с Ctrl/Alt/Super не обрабатываются.

## Приватность

Нет рекламы и телеметрии: набранный текст нигде не сохраняется и никуда не отправляется. Журнал (`~/.cache/smartum-switch.log` на Linux, `%LOCALAPPDATA%\SmartumSwitch\smartum-switch.log` на Windows) содержит только счётчики и ошибки.

## Каталоги

| Папка | Что внутри |
|---|---|
| `core/` | общие правила (`RULES.md`), данные (`data/*.json`), словари hunspell, эталонное ядро на Python, тесты (`tests/cases.json`) |
| `linux/` | версия для Linux/Wayland (Python, evdev + uinput, пользовательская служба systemd) — см. `linux/README.md` |
| `windows/` | версия для Windows (C#/.NET 8, низкоуровневый хук + SendInput, значок в трее) — см. `windows/README.md` |

## Тесты

Из корня репозитория:

```bash
python3 core/tests/run_tests.py
```

Скрипт прогоняет `core/tests/cases.json` (182 слова) через эталонное ядро на Python и через `Judge` демона Linux. Демон подключается без устройств ввода: если модуля `evdev` нет, тест подставляет заглушку.

Тесты Windows (нужен .NET 8 SDK):

```bash
dotnet run -c Release --project windows/SmartumSwitch.Tests
```

## Поддержать разработку SmartumSwitch

Программа SmartumSwitch распространяется бесплатно и без рекламы. Пользоваться ею можно без каких-либо переводов и без регистрации.

Если хотите добровольно поддержать разработку, можете сделать безвозмездный дар. Это не оплата и не покупка программы. Перевод ни к чему не обязывает: программа остаётся бесплатной для всех, встречных услуг, доступа или привилегий за перевод нет.

Перевод является даром и по общему правилу не возвращается, за исключением случаев, предусмотренных законом.

- Картой или через СБП: [CloudTips](https://pay.cloudtips.ru/p/463a2f58)
- Через [Boosty](https://boosty.to/smartum/donate)
- **USDT, сеть TRC20 (Tron)**: `TWtdcQw8G2RX26DGrfRouX4nQs7RHvwmL6`
- **LTC (Litecoin)**: `ltc1qczvt2cjewrf8a5lapt9lwejlkp993r0wwzrjw0`
- **BTC (Bitcoin)**: `16Mo7J78izjDfu5PeuNtvdgQSzjvqvLaWP`
- **ETH (Ethereum)**: `0xe1326f053413f7b5215f31009659cA938E67e73c`

⚠️ Каждую монету отправляйте только в её сети, иначе средства потеряются.

Получатель: Роман Спирьков (физическое лицо).

## Лицензия

MIT, © 2026 smARTum. Текст лицензии — в файле `LICENSE`.

Словари hunspell поставляются без изменений из пакетов Debian/Ubuntu: ru_RU — © 1997–2008 Alexander I. Lebedev (см. `core/dict/LICENSE.ru_RU.txt`), en_US — SCOWL / Kevin Atkinson и другие (см. `core/dict/LICENSE.en_US.txt`).

Сделано в smARTum — мебель, Крым.

---

## English

SmartumSwitch is a free automatic RU/EN keyboard-layout switcher. It fixes text typed in the wrong layout (QWERTY ⇄ Russian ЙЦУКЕН), like Punto Switcher. Completely free of charge, with no ads, no telemetry and no bundled third-party software. MIT License. © 2026 smARTum.

Made at smARTum — furniture, Crimea.

### Status

- **Linux (Wayland) is ready.** Tested on elementary OS 8 (Pantheon/Gala, layouts `us` + `ru`). A systemd user service uses evdev and uinput. See `linux/README.md`.
- **Windows is a beta** (MVP 0.2, a single `SmartumSwitch-win-x64.exe` for Windows 10/11 x64). It has not yet been tested on real hardware. See `windows/README.md`.
- **macOS is planned.** The shared core rules already name Linux, Windows and macOS (`core/RULES.md`); this release has no macOS tree.

### Quick start (Linux)

```bash
git clone https://github.com/spirkoff/SmartumSwitch.git && cd SmartumSwitch/linux && ./install.sh
```

Uninstall: `git clone https://github.com/spirkoff/SmartumSwitch.git && cd SmartumSwitch/linux && ./uninstall.sh`.

You need the `us` and `ru` layouts. The installer adds packages, a udev rule and the `smartum-switch` user service. Run it as your normal user.


### Dependencies (Linux)

The `linux/install.sh` installer adds only the packages the program needs to run. It does not install ads, telemetry or any other third-party software.

- `python3-evdev` — read key presses and create a virtual keyboard (`uinput`) to erase a word and type it again.
- `libhunspell-1.7-0`, `hunspell-ru`, `hunspell-en-us` — dictionaries used to tell a real word from one typed in the wrong layout.
- `wl-clipboard` — for the Pause key: read the selection, fix it and restore the previous clipboard.
- `libnotify-bin` — a short notification when auto-correction is toggled (Shift+Pause).

Python 3 and systemd are usually already present. On GNOME/Pantheon the Pause hotkey uses `gsettings`, which is already installed. A separate tool such as ydotool is not required and is not installed: input goes through `uinput`.

The Windows build is a single file: no installer, no administrator rights, and no bundled third-party software.

### Hotkeys

- **Pause** fixes the selection (or the last word, if nothing is selected). The clipboard is kept.
- **Shift+Pause** toggles auto-correction. `smartum-switch toggle` does the same.
- **Backspace** right after a fix undoes it: the word comes back as typed and is left alone for the rest of the session.

One-letter words are left alone. Two-letter words are fixed only when they are common (`yt` → `не`). Terminals, password windows and Ctrl/Alt/Super shortcuts are skipped.

### Privacy

No ads and no telemetry: typed text is never stored or sent. The log (`~/.cache/smartum-switch.log` on Linux, `%LOCALAPPDATA%\SmartumSwitch\smartum-switch.log` on Windows) has counters and errors only.

### Folders

| Folder | What |
|---|---|
| `core/` | shared rules (`RULES.md`), data (`data/*.json`), hunspell dictionaries, the reference Python core, tests (`tests/cases.json`) |
| `linux/` | Linux/Wayland version (Python, evdev + uinput, systemd user service) — see `linux/README.md` |
| `windows/` | Windows version (C#/.NET 8, low-level hook + SendInput, tray) — see `windows/README.md` |

### Tests

From the repository root:

```bash
python3 core/tests/run_tests.py
```

This runs `core/tests/cases.json` (182 words) against the Python reference core and against the Linux daemon's `Judge`. The daemon test does not need input devices: if the `evdev` module is missing, the runner stubs it.

Windows tests (requires the .NET 8 SDK):

```bash
dotnet run -c Release --project windows/SmartumSwitch.Tests
```

### Licence

MIT, © 2026 smARTum. See `LICENSE`.

The bundled hunspell dictionaries are unchanged copies from Debian/Ubuntu packages: ru_RU © 1997–2008 Alexander I. Lebedev (`core/dict/LICENSE.ru_RU.txt`), en_US from SCOWL / Kevin Atkinson et al. (`core/dict/LICENSE.en_US.txt`).

Made at smARTum — furniture, Crimea. («Сделано в smARTum — мебель, Крым».)
