# SmartumSwitch

[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](https://github.com/spirkoff/SmartumSwitch/blob/main/LICENSE)
[![Release](https://img.shields.io/github/v/release/spirkoff/SmartumSwitch)](https://github.com/spirkoff/SmartumSwitch/releases/latest)
![platform: Linux | Wayland](https://img.shields.io/badge/platform-Linux%20%7C%20Wayland-blue)

Свободный аналог Punto Switcher для Linux (Wayland): исправляет текст, набранный не в той раскладке
(QWERTY ⇄ ЙЦУКЕН) — автоматически во время набора или по клавише Pause.
Сделано в [smARTum](https://github.com/spirkoff) — мебель, Крым. Лицензия MIT. Полностью безвозмездно, без рекламы, без телеметрии и без установки посторонних программ.

[English below](#english)

## Возможности

- **Автоисправление на лету.** Набрали `ghbdtn ` — получите `привет `, раскладка переключится сама.
  Работает в обе стороны: `руддщ ` → `hello `.
- **Откат.** Нажмите Backspace сразу после исправления — вернётся как было, и это слово больше не тронем до конца сеанса.
- **Pause** — исправить выделенный текст (или последнее слово, если ничего не выделено). Буфер обмена сохраняется.
- **Shift+Pause** — включить/выключить автоисправление (с уведомлением). Или `smartum-switch toggle`.
- **Исключения** — `~/.config/smartum-switch/exceptions.txt`, по одному слову в строке: слова, которые программа никогда не исправляет.
- **Свои слова** — `~/.config/smartum-switch/words.txt`, по одному в строке: слова, которых нет в словарях (названия, термины). Набранное в другой раскладке будет исправлено на них. Перечитывается на ходу. Больше 200 частых названий (ChatGPT, GitHub, Telegram…) уже встроены.
- Осторожный: слова из 1 буквы не трогает, 2-буквенные — только частые (`yt` → `не`), проверяет по словарям
  hunspell (ru_RU, en_US) и по частотам буквосочетаний. Не работает в терминалах, окнах паролей и при зажатых Ctrl/Alt/Super.
- **Приватность.** Нет рекламы и телеметрии: набранный текст нигде не сохраняется и никуда не отправляется. В журнале
  (`~/.cache/smartum-switch.log`) только счётчики и ошибки.

## Установка

```bash
git clone https://github.com/spirkoff/SmartumSwitch.git && cd SmartumSwitch/linux && ./install.sh
```

Проверено на elementary OS 8 (Pantheon/Gala, Wayland, раскладки `us` + `ru`). Должно работать в других окружениях
на базе GNOME-настроек; определение окна (терминал/пароль) сейчас реализовано для Gala.
Удаление: `git clone https://github.com/spirkoff/SmartumSwitch.git && cd SmartumSwitch/linux && ./uninstall.sh`.

## Зависимости

Установщик `install.sh` ставит только пакеты, без которых программа не работает. Рекламу, телеметрию и посторонние программы он не ставит.

- `python3-evdev` — читать нажатия клавиатуры и создать виртуальную клавиатуру (`uinput`), чтобы стереть слово и набрать его заново.
- `libhunspell-1.7-0`, `hunspell-ru`, `hunspell-en-us` — словари, по которым программа отличает настоящее слово от набранного не в той раскладке.
- `wl-clipboard` — для клавиши Pause: взять выделенный текст, исправить его и вернуть прежний буфер обмена.
- `libnotify-bin` — короткое уведомление, когда автоисправление включают или выключают (Shift+Pause).

Python 3 и systemd обычно уже есть. Для горячей клавиши Pause на GNOME/Pantheon используется уже установленный `gsettings`. Отдельная программа вроде ydotool не нужна и не устанавливается: ввод идёт через `uinput`.



## Как это устроено

Служба (`systemctl --user status smartum-switch`) читает нажатия физической клавиатуры через evdev,
не перехватывая ввод, и хранит в памяти только текущее слово в виде скан-кодов. На пробеле слово
проверяется в обеих раскладках. Если оно явно набрано не в той, служба на доли секунды забирает клавиатуру,
стирает слово через виртуальную клавиатуру (uinput), переключает раскладку и повторяет те же клавиши,
а нажатия, сделанные в это время, передаёт дальше без потерь.

Права: udev-правило даёт пользователю **активного локального сеанса** доступ к `/dev/uinput` и клавиатурам/мышам
(тег `uaccess`, как для звука и камер). Учтите: это значит, что программы этого пользователя могут читать нажатия клавиш.

## Ограничения

- Только пары раскладок `us` + `ru`.
- В терминалах автоисправления нет; по Pause исправленный текст копируется в буфер.
- Поля паролей в браузере определить нельзя — при вводе паролей с похожими на слова сочетаниями лучше выключить (Shift+Pause).
- При очень быстром наборе сразу после исправления порядок пары символов может нарушиться (IBus) — сообщите, если заметите.

---

## English

SmartumSwitch is a free Punto Switcher–style tool for Linux/Wayland. It fixes text typed in the wrong keyboard
layout (QWERTY ⇄ Russian ЙЦУКЕН) automatically while you type, or on the Pause key. Completely free of charge, with no ads, no telemetry and no bundled third-party software.

- **Auto-correction:** `ghbdtn ` becomes `привет `, `руддщ ` becomes `hello `, and the layout is switched for you.
- **Undo:** press Backspace right after a correction.
- **Pause:** fix the selection (or the last word). The clipboard is restored.
- **Shift+Pause** or `smartum-switch toggle`: auto-correction on/off.
- **Exceptions:** `~/.config/smartum-switch/exceptions.txt`, one word per line: words the program never corrects.
- **Your words:** `~/.config/smartum-switch/words.txt`, one per line: names and terms missing from the dictionaries. Typed in the other layout, they are corrected to these words. Re-read on the fly. More than 200 common names (ChatGPT, GitHub, Telegram…) are already built in.
- Conservative: hunspell dictionaries (ru_RU, en_US) plus letter-bigram statistics; skips terminals,
  password dialogs and Ctrl/Alt/Super shortcuts.
- **Privacy:** no ads and no telemetry; typed text is never stored or sent anywhere; the log has counters and errors only.

Install: `git clone https://github.com/spirkoff/SmartumSwitch.git && cd SmartumSwitch/linux && ./install.sh`.
Tested on elementary OS 8 (Wayland). Uninstall: `git clone https://github.com/spirkoff/SmartumSwitch.git && cd SmartumSwitch/linux && ./uninstall.sh`.


The installer adds only the packages the program needs. It does not install ads, telemetry or any other third-party software.

- `python3-evdev` — read key presses and create a virtual keyboard (`uinput`) to erase a word and type it again.
- `libhunspell-1.7-0`, `hunspell-ru`, `hunspell-en-us` — dictionaries used to tell a real word from one typed in the wrong layout.
- `wl-clipboard` — for the Pause key: read the selection, fix it and restore the previous clipboard.
- `libnotify-bin` — a short notification when auto-correction is toggled (Shift+Pause).

Python 3 and systemd are usually already present. On GNOME/Pantheon the Pause hotkey uses `gsettings`, which is already installed. A separate tool such as ydotool is not required and is not installed: input goes through `uinput`.



How it works: a systemd user service reads key presses via evdev (no grab while typing), keeps only the current
word as scan codes in memory, and on Space checks it in both layouts. For a clear mistake it briefly grabs the
keyboard, erases the word with a uinput virtual keyboard, switches the layout and replays the same keys,
forwarding anything you typed meanwhile. A udev rule (`uaccess`) gives the active local session user access
to `/dev/uinput` and keyboards — note that this lets that user's programs read key presses.

License: MIT © 2026 smARTum.
