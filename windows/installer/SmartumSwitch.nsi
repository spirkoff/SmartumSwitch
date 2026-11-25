; SmartumSwitch for Windows — установщик. Copyright (c) 2026 smARTum. MIT License.
; Бесплатно, без рекламы и без дополнительного ПО.
; Согласован с автозапуском приложения: тот же ключ HKCU\...\Run\SmartumSwitch,
; что использует пункт меню «Запускать при входе в Windows» и флаг --uninstall.

Unicode True
SetCompressor /SOLID lzma
CRCCheck On
SetDatablockOptimize On

!define PRODUCT_NAME "SmartumSwitch"
!define PRODUCT_VERSION "0.2.1"
!define PRODUCT_PUBLISHER "smARTum"
!define PRODUCT_WEB "https://github.com/spirkoff/SmartumSwitch"
!define RUN_KEY "Software\Microsoft\Windows\CurrentVersion\Run"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"

!define SRC_EXE "/workspace/smartumswitch/dist/SmartumSwitch-win-x64.exe"
!define SRC_LICENSE "/workspace/smartumswitch/LICENSE"
!define SRC_ICO "/workspace/smartumswitch/windows/installer/SmartumSwitch.ico"

Name "${PRODUCT_NAME}"
OutFile "/workspace/smartumswitch/release/SmartumSwitch-win-x64-0.2.1-setup.exe"
InstallDir "$LOCALAPPDATA\Programs\SmartumSwitch"
RequestExecutionLevel user
ShowInstDetails hide
ShowUnInstDetails hide
BrandingText "smARTum — бесплатно, без рекламы и без дополнительного ПО"

VIProductVersion "0.2.1.0"
VIAddVersionKey "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "FileVersion" "${PRODUCT_VERSION}.0"
VIAddVersionKey "FileDescription" "Установщик SmartumSwitch"
VIAddVersionKey "LegalCopyright" "© 2026 smARTum"
VIAddVersionKey "CompanyName" "${PRODUCT_PUBLISHER}"
VIAddVersionKey "Comments" "Бесплатно, без рекламы и без дополнительного ПО"

!include "MUI2.nsh"
!include "nsDialogs.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "WinMessages.nsh"

!define MUI_ICON "${SRC_ICO}"
!define MUI_UNICON "${SRC_ICO}"
!define MUI_ABORTWARNING

!define MUI_WELCOMEPAGE_TITLE "Установка SmartumSwitch"
!define MUI_WELCOMEPAGE_TEXT "SmartumSwitch — бесплатная программа без рекламы и без дополнительного ПО.$\r$\n$\r$\nУстановка не требует прав администратора. Программа будет помещена в вашу папку пользователя и появится в меню «Пуск».$\r$\n$\r$\nНажмите «Далее» для продолжения."

!insertmacro MUI_PAGE_WELCOME
Page custom OptionsPage OptionsPageLeave
!insertmacro MUI_PAGE_INSTFILES

!define MUI_FINISHPAGE_RUN "$INSTDIR\SmartumSwitch.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Запустить SmartumSwitch"
!define MUI_FINISHPAGE_TITLE "Установка завершена"
!define MUI_FINISHPAGE_TEXT "SmartumSwitch установлен. Значок программы появится в области уведомлений (трее).$\r$\n$\r$\nЕсли Windows покажет предупреждение SmartScreen, выберите «Подробнее» → «Выполнить в любом случае»: установщик пока не подписан сертификатом."
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

!insertmacro MUI_LANGUAGE "Russian"

Var AutoCheck
Var AutoState

Function .onInit
  ; Тихая установка (/S) тоже включает автозапуск по умолчанию.
  StrCpy $AutoState ${BST_CHECKED}
FunctionEnd

Function OptionsPage
  !insertmacro MUI_HEADER_TEXT "Параметры установки" "Программа ставится без прав администратора."
  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == error
    Abort
  ${EndIf}

  ${NSD_CreateLabel} 0 0 100% 36u "Папка установки:$\r$\n$INSTDIR"
  Pop $1

  ${NSD_CreateCheckbox} 0 50u 100% 14u "Запускать SmartumSwitch при входе в Windows"
  Pop $AutoCheck
  ${If} $AutoState == ${BST_CHECKED}
    ${NSD_Check} $AutoCheck
  ${Else}
    ${NSD_Uncheck} $AutoCheck
  ${EndIf}

  ${NSD_CreateLabel} 0 72u 100% 28u "Флажок можно снять. Позже это же включается или выключается в меню значка в трее."
  Pop $2

  nsDialogs::Show
FunctionEnd

Function OptionsPageLeave
  ${NSD_GetState} $AutoCheck $AutoState
FunctionEnd

Function StopApp
  ; Завершаем процесс, чтобы можно было заменить или удалить файлы.
  nsExec::Exec 'taskkill /F /IM SmartumSwitch.exe'
  Pop $0
  nsExec::Exec 'taskkill /F /IM SmartumSwitch-win-x64.exe'
  Pop $0
  Sleep 700
FunctionEnd

Section "Install"
  Call StopApp

  SetOutPath $INSTDIR
  File /oname=SmartumSwitch.exe "${SRC_EXE}"
  File /oname=LICENSE.txt "${SRC_LICENSE}"
  File /oname=SmartumSwitch.ico "${SRC_ICO}"

  CreateShortcut "$SMPROGRAMS\SmartumSwitch.lnk" "$INSTDIR\SmartumSwitch.exe" "" "$INSTDIR\SmartumSwitch.exe" 0

  ${If} $AutoState == ${BST_CHECKED}
    ; Тот же параметр Run, что читает и пишет сама программа. Двойной записи нет.
    WriteRegStr HKCU "${RUN_KEY}" "SmartumSwitch" '"$INSTDIR\SmartumSwitch.exe"'
  ${Else}
    DeleteRegValue HKCU "${RUN_KEY}" "SmartumSwitch"
  ${EndIf}

  WriteUninstaller "$INSTDIR\Uninstall.exe"

  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKCU "${UNINST_KEY}" "URLInfoAbout" "${PRODUCT_WEB}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\SmartumSwitch.exe"
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1

  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegDWORD HKCU "${UNINST_KEY}" "EstimatedSize" $0
SectionEnd

Section "Uninstall"
  Call un.StopApp

  ; Снимаем автозапуск тем же ключом, что использует программа.
  DeleteRegValue HKCU "${RUN_KEY}" "SmartumSwitch"
  DeleteRegKey HKCU "${UNINST_KEY}"

  Delete "$SMPROGRAMS\SmartumSwitch.lnk"
  Delete "$INSTDIR\SmartumSwitch.exe"
  Delete "$INSTDIR\LICENSE.txt"
  Delete "$INSTDIR\SmartumSwitch.ico"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"

  ; Настройки и журнал (%APPDATA%\SmartumSwitch и журнал в %LOCALAPPDATA%\SmartumSwitch)
  ; не удаляем: при повторной установке сохранятся исключения.
SectionEnd

Function un.StopApp
  nsExec::Exec 'taskkill /F /IM SmartumSwitch.exe'
  Pop $0
  nsExec::Exec 'taskkill /F /IM SmartumSwitch-win-x64.exe'
  Pop $0
  Sleep 700
FunctionEnd
