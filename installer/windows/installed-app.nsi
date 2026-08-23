Unicode true

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "StrFunc.nsh"

${StrStr}

!ifndef APP_VERSION
  !error "APP_VERSION is required"
!endif
!ifndef VERSION_QUAD
  !error "VERSION_QUAD is required"
!endif
!ifndef PAYLOAD_ROOT
  !error "PAYLOAD_ROOT is required"
!endif
!ifndef OUTPUT_FILE
  !error "OUTPUT_FILE is required"
!endif
!ifndef EXTENSION_ORIGIN
  !error "EXTENSION_ORIGIN is required"
!endif

!define PRODUCT_NAME "AkuBrowser"
!define PRODUCT_PUBLISHER "AkuBrowser"
!define PRODUCT_WEB_SITE "https://github.com/abangkis/AkuBrowser"
!define PRODUCT_REGISTRY_KEY "Software\AkuBrowser\InstalledApp"
!define PRODUCT_UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\AkuBrowser"
!define SETUP_MUTEX_NAME "Local\AkuBrowserInstalledAppSetup"
!define ERROR_ALREADY_EXISTS 183

Var SetupMutexHandle
Var UninstallFullReset

Name "${PRODUCT_NAME} ${APP_VERSION}"
Caption "${PRODUCT_NAME} Setup"
OutFile "${OUTPUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\AkuBrowser"
InstallDirRegKey HKCU "${PRODUCT_REGISTRY_KEY}" "InstallLocation"
RequestExecutionLevel user
SetCompressor /SOLID lzma
CRCCheck force
ShowInstDetails show
ShowUninstDetails show
BrandingText "AkuBrowser"

VIProductVersion "${VERSION_QUAD}"
VIAddVersionKey /LANG=1033 "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=1033 "FileDescription" "${PRODUCT_NAME} Setup"
VIAddVersionKey /LANG=1033 "FileVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=1033 "CompanyName" "${PRODUCT_PUBLISHER}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "AkuBrowser contributors"

!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "Install ${PRODUCT_NAME}"
!define MUI_WELCOMEPAGE_TEXT "This staged installer contains AkuBrowserLauncher, AkuSidecar, AkuBridge, and the pinned Chromium build in one isolated application.$\r$\n$\r$\nCodex App remains an external prerequisite.$\r$\n$\r$\nTesting notice: this installer is not code-signed and is not a shipped production release."
!define MUI_DIRECTORYPAGE_TEXT_TOP "Select the folder for AkuBrowser program files. User data and the isolated browser profile remain under your local application-data folder."
!define MUI_FINISHPAGE_TITLE "AkuBrowser is installed"
!define MUI_FINISHPAGE_TEXT "Start AkuBrowser from the Start menu. The first launch uses the bundled Chromium build and isolated AkuBrowser profile."
!define MUI_FINISHPAGE_NOAUTOCLOSE

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

Function .onInit
  SetShellVarContext current
  System::Call 'kernel32::CreateMutexW(p0, i0, w "${SETUP_MUTEX_NAME}") p.r0'
  System::Call 'kernel32::GetLastError() i.r1'
  StrCpy $SetupMutexHandle $0
  ${If} $1 = ${ERROR_ALREADY_EXISTS}
    MessageBox MB_OK|MB_ICONEXCLAMATION "AkuBrowser Setup is already running. Finish or close the existing setup window first."
    Abort
  ${ElseIf} $SetupMutexHandle = 0
    MessageBox MB_OK|MB_ICONSTOP "AkuBrowser Setup could not create its single-instance lock."
    Abort
  ${EndIf}
FunctionEnd

Function .onGUIEnd
  ${If} $SetupMutexHandle != 0
    System::Call 'kernel32::CloseHandle(p $SetupMutexHandle)'
    StrCpy $SetupMutexHandle 0
  ${EndIf}
FunctionEnd

Function EnsureAkuBrowserStopped
  nsExec::ExecToStack '"$SYSDIR\tasklist.exe" /FI "IMAGENAME eq AkuBrowserLauncher.exe" /NH'
  Pop $0
  Pop $1
  ${StrStr} $2 $1 "AkuBrowserLauncher.exe"
  ${If} $2 != ""
    MessageBox MB_OK|MB_ICONEXCLAMATION "AkuBrowser is running. Close it normally before installing or repairing."
    Abort
  ${EndIf}
  nsExec::ExecToStack '"$SYSDIR\tasklist.exe" /FI "IMAGENAME eq AkuSidecar.exe" /NH'
  Pop $0
  Pop $1
  ${StrStr} $2 $1 "AkuSidecar.exe"
  ${If} $2 != ""
    MessageBox MB_OK|MB_ICONEXCLAMATION "AkuSidecar is still running. Close AkuBrowser normally before installing or repairing."
    Abort
  ${EndIf}
FunctionEnd

Function un.onInit
  SetShellVarContext current
  StrCpy $UninstallFullReset 0
  IfSilent uninstall_choice_done
  MessageBox MB_YESNOCANCEL|MB_ICONQUESTION|MB_DEFBUTTON1 "Choose how AkuBrowser local state should be handled.$\r$\n$\r$\nYes: Preserve data and the isolated browser profile.$\r$\nNo: Permanently remove both.$\r$\nCancel: Close the uninstaller." /SD IDYES IDYES uninstall_choice_done IDNO uninstall_full_reset
  Abort

  uninstall_full_reset:
  StrCpy $UninstallFullReset 1

  uninstall_choice_done:
FunctionEnd

Section "AkuBrowser" InstallSection
  SectionIn RO
  SetOverwrite on
  Call EnsureAkuBrowserStopped

  ; Stage every immutable component before changing the active pointer.
  SetOutPath "$INSTDIR"
  File /oname=AkuBrowserLauncher.exe "${PAYLOAD_ROOT}\AkuBrowserLauncher.exe"

  CreateDirectory "$INSTDIR\runtime\versions\${APP_VERSION}"
  SetOutPath "$INSTDIR\runtime\versions\${APP_VERSION}"
  File /r "${PAYLOAD_ROOT}\runtime\versions\${APP_VERSION}\*"

  SetOutPath "$INSTDIR"
  File /oname=install-manifest.json "${PAYLOAD_ROOT}\install-manifest.json"

  ; Activation is last so an interrupted extraction keeps the old tuple active.
  CreateDirectory "$INSTDIR\runtime"
  SetOutPath "$INSTDIR\runtime"
  File /oname=current.json "${PAYLOAD_ROOT}\runtime\current.json"

  CreateDirectory "$LOCALAPPDATA\AkuBrowser\data"
  CreateDirectory "$LOCALAPPDATA\AkuBrowser\browser-profile"

  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateDirectory "$SMPROGRAMS\AkuBrowser"
  CreateShortcut "$SMPROGRAMS\AkuBrowser\AkuBrowser.lnk" "$INSTDIR\AkuBrowserLauncher.exe"
  CreateShortcut "$SMPROGRAMS\AkuBrowser\Uninstall AkuBrowser.lnk" "$INSTDIR\Uninstall.exe"

  WriteRegStr HKCU "${PRODUCT_REGISTRY_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${PRODUCT_REGISTRY_KEY}" "Version" "${APP_VERSION}"
  WriteRegStr HKCU "${PRODUCT_REGISTRY_KEY}" "ExtensionOrigin" "${EXTENSION_ORIGIN}"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "URLInfoAbout" "${PRODUCT_WEB_SITE}"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\AkuBrowserLauncher.exe"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "${PRODUCT_UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${PRODUCT_UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  DeleteRegKey HKCU "${PRODUCT_UNINSTALL_KEY}"
  DeleteRegKey HKCU "${PRODUCT_REGISTRY_KEY}"
  Delete "$SMPROGRAMS\AkuBrowser\AkuBrowser.lnk"
  Delete "$SMPROGRAMS\AkuBrowser\Uninstall AkuBrowser.lnk"
  RMDir "$SMPROGRAMS\AkuBrowser"

  ; These are installer-owned, fixed paths. User state is outside INSTDIR.
  RMDir /r /REBOOTOK "$INSTDIR\runtime"
  Delete /REBOOTOK "$INSTDIR\AkuBrowserLauncher.exe"
  Delete /REBOOTOK "$INSTDIR\install-manifest.json"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"

  ${If} $UninstallFullReset = 1
    RMDir /r /REBOOTOK "$LOCALAPPDATA\AkuBrowser\data"
    RMDir /r /REBOOTOK "$LOCALAPPDATA\AkuBrowser\browser-profile"
    RMDir "$LOCALAPPDATA\AkuBrowser"
  ${EndIf}
SectionEnd
