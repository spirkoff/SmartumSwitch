# SmartumSwitch for Windows (MVP 0.2)

Один файл `SmartumSwitch-win-x64.exe` (Windows 10/11 x64), установка и права администратора не нужны.
Нужны раскладки «Английская (США)» и «Русская».

- Автоисправление на лету: `ghbdtn ` → `привет `, `руддщ ` → `hello `; раскладка переключается сама.
- Backspace сразу после исправления — откат.
- **Pause** — исправить выделенное (или последнее слово); **Shift+Pause** или двойной щелчок по значку — вкл/выкл.
- Значок в трее: меню «Исключения…», «Запускать при входе в Windows», «Выход».
- Не трогает: консоль/Windows Terminal/PowerShell, менеджеры паролей, окна с «пароль/password» в заголовке,
  поля пароля (UI Automation IsPassword), окна администратора, сочетания с Ctrl/Alt/Win.
- Приватность: текст нигде не сохраняется. Журнал `%LOCALAPPDATA%\SmartumSwitch\smartum-switch.log` — только счётчики.
- Настройки: `%APPDATA%\SmartumSwitch\` (`exceptions.txt`, `settings.json`).
- Удаление: «Выход» в меню → `SmartumSwitch-win-x64.exe --uninstall` (убирает автозапуск и настройки) → удалить exe.

Сборка: `windows/build.sh` (.NET 8 SDK; сначала прогоняет общие тесты ядра).
