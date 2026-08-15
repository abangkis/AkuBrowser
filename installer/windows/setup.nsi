Unicode true

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "StrFunc.nsh"
!include "TextFunc.nsh"
!include "WordFunc.nsh"

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

!define PRODUCT_NAME "AkuBrowser Runtime"
!define PRODUCT_PUBLISHER "AkuBrowser"
!define PRODUCT_WEB_SITE "https://github.com/abangkis/AkuBrowser"
!define PRODUCT_REGISTRY_KEY "Software\AkuBrowser\Runtime"
!define PRODUCT_UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\AkuBrowserRuntime"
!define NATIVE_HOST_KEY "Software\Google\Chrome\NativeMessagingHosts\com.akubrowser.runtime"
!define SETUP_MUTEX_NAME "Local\AkuBrowserRuntimeSetup"
!define ERROR_ALREADY_EXISTS 183

Var SetupMutexHandle
Var InstallAttemptStarted
Var InstallAttemptCompleted
Var DowngradeDetected
Var DowngradeVersion
Var DowngradeBackup
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

!ifdef SIGN_UNINSTALLER_SCRIPT
  !uninstfinalize 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${SIGN_UNINSTALLER_SCRIPT}" "%1"'
!endif

VIProductVersion "${VERSION_QUAD}"
VIAddVersionKey /LANG=1033 "ProductName" "${PRODUCT_NAME}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=1033 "FileDescription" "${PRODUCT_NAME} Setup"
VIAddVersionKey /LANG=1033 "FileVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=1033 "CompanyName" "${PRODUCT_PUBLISHER}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "AkuBrowser contributors"

!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE "Install ${PRODUCT_NAME}"
!ifdef UNSIGNED_BUILD
  !define MUI_WELCOMEPAGE_TEXT "This wizard installs AkuSidecar, the Chrome Native Messaging Host, and the C2PA verifier.$\r$\n$\r$\nCodex App is installed separately.$\r$\n$\r$\nTesting notice: this build is not code-signed. Windows Security or antivirus software may warn, quarantine, or sandbox it. Avast CyberCapture may open an isolated second Setup window, sometimes after the first one finishes. Complete only one Setup window. If another appears, select No or Cancel; do not run Repair twice. Continue only if you downloaded this installer from the official AkuBrowser GitHub release."
!else
  !define MUI_WELCOMEPAGE_TEXT "This wizard installs AkuSidecar, the Chrome Native Messaging Host, and the C2PA verifier.$\r$\n$\r$\nCodex App is installed separately. Select Next to choose where the AkuBrowser Runtime program files will be installed."
!endif
!define MUI_DIRECTORYPAGE_TEXT_TOP "Select the folder for AkuBrowser Runtime program files. Your AkuBrowser database remains in your local application-data folder and is not removed by updates or uninstall."
!define MUI_FINISHPAGE_TITLE "AkuBrowser Runtime is installed"
!ifdef UNSIGNED_BUILD
  !define MUI_FINISHPAGE_TEXT "Return to Chrome, open AkuBrowser Setup, and select Check runtime. If Avast opens another Setup window after this one, select No or Cancel and close it; do not run Repair twice."
!else
  !define MUI_FINISHPAGE_TEXT "Return to Chrome, open AkuBrowser Setup, and select Check runtime. You can later update, run, or stop the runtime from the same page."
!endif
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
  StrCpy $InstallAttemptStarted 0
  StrCpy $InstallAttemptCompleted 0
  StrCpy $DowngradeDetected 0
  StrCpy $DowngradeVersion ""
  System::Call 'kernel32::CreateMutexW(p0, i0, w "${SETUP_MUTEX_NAME}") p.r0'
  System::Call 'kernel32::GetLastError() i.r1'
  StrCpy $SetupMutexHandle $0
  ${If} $1 = ${ERROR_ALREADY_EXISTS}
    MessageBox MB_OK|MB_ICONEXCLAMATION "AkuBrowser Runtime Setup is already running. Finish or close the existing setup window before trying again."
    Abort
  ${ElseIf} $SetupMutexHandle = 0
    MessageBox MB_OK|MB_ICONSTOP "AkuBrowser Runtime Setup could not create its single-instance lock. Close other setup windows and try again."
    Abort
  ${EndIf}

  ReadRegStr $2 HKCU "${PRODUCT_REGISTRY_KEY}" "Version"
  ${If} $2 == "${APP_VERSION}"
    MessageBox MB_YESNO|MB_ICONQUESTION|MB_DEFBUTTON2 "AkuBrowser Runtime ${APP_VERSION} is already installed.$\r$\n$\r$\nSelect Yes only if you want to repair this installation. Select No to close this duplicate Setup session." /SD IDNO IDYES continue_same_version
    Abort
    continue_same_version:
  ${EndIf}
  Call DetectDowngrade
FunctionEnd

Function DetectDowngrade
  IfFileExists "$LOCALAPPDATA\AkuBrowser\data\.runtime-version" read_data_marker read_installed_version

  read_data_marker:
  FileOpen $0 "$LOCALAPPDATA\AkuBrowser\data\.runtime-version" r
  FileRead $0 $DowngradeVersion
  FileClose $0
  ${TrimNewLines} $DowngradeVersion $DowngradeVersion
  Goto compare_downgrade

  read_installed_version:
  ReadRegStr $DowngradeVersion HKCU "${PRODUCT_REGISTRY_KEY}" "Version"

  compare_downgrade:
  ${If} $DowngradeVersion == ""
    Return
  ${EndIf}
  ${VersionCompare} $DowngradeVersion "${APP_VERSION}" $0
  ${If} $0 != 1
    Return
  ${EndIf}
  MessageBox MB_YESNO|MB_ICONEXCLAMATION|MB_DEFBUTTON2 "AkuBrowser data was written by newer Runtime $DowngradeVersion. This installer contains older Runtime ${APP_VERSION}.$\r$\n$\r$\nSelect Yes to archive the newer data and create a fresh database. Select No to close Setup without changing the data." /SD IDNO IDYES accept_downgrade_reset
  Abort

  accept_downgrade_reset:
  StrCpy $DowngradeDetected 1
FunctionEnd

Function PrepareDowngradeData
  ${If} $DowngradeDetected != 1
    Return
  ${EndIf}
  IfFileExists "$LOCALAPPDATA\AkuBrowser\data" 0 write_downgrade_marker
  ${GetTime} "" "L" $0 $1 $2 $3 $4 $5 $6
  CreateDirectory "$LOCALAPPDATA\AkuBrowser\data-backups"
  StrCpy $DowngradeBackup "$LOCALAPPDATA\AkuBrowser\data-backups\pre-downgrade-$DowngradeVersion-to-${APP_VERSION}-$2$1$0T$4$5$6"
  ClearErrors
  Rename "$LOCALAPPDATA\AkuBrowser\data" "$DowngradeBackup"
  ${If} ${Errors}
    MessageBox MB_OK|MB_ICONSTOP "Setup could not archive the newer AkuBrowser data. Close programs using the database and run Setup again."
    Abort
  ${EndIf}
  CreateDirectory "$LOCALAPPDATA\AkuBrowser"
  FileOpen $0 "$LOCALAPPDATA\AkuBrowser\downgrade-receipt.txt" w
  FileWrite $0 "from=$DowngradeVersion$\r$\nto=${APP_VERSION}$\r$\nbackup=$DowngradeBackup$\r$\n"
  FileClose $0

  write_downgrade_marker:
  CreateDirectory "$LOCALAPPDATA\AkuBrowser\data"
FunctionEnd

Function .onGUIEnd
  ${If} $InstallAttemptStarted = 1
  ${AndIf} $InstallAttemptCompleted = 0
    Call RecordInstallFailed
  ${EndIf}
  ${If} $SetupMutexHandle != 0
    System::Call 'kernel32::CloseHandle(p $SetupMutexHandle)'
    StrCpy $SetupMutexHandle 0
  ${EndIf}
FunctionEnd

Function RecordInstallStarted
  CreateDirectory "$INSTDIR"
  FileOpen $0 "$INSTDIR\install.log" a
  FileSeek $0 0 END
  FileWrite $0 "BEGIN version=${APP_VERSION} extensionOrigin=${EXTENSION_ORIGIN}$\r$\n"
  FileClose $0
  FileOpen $0 "$INSTDIR\install-result.json" w
  FileWrite $0 '{$\"schemaVersion$\":1,$\"status$\":$\"installing$\",$\"version$\":$\"${APP_VERSION}$\",$\"extensionOrigin$\":$\"${EXTENSION_ORIGIN}$\"}$\r$\n'
  FileClose $0
  StrCpy $InstallAttemptStarted 1
  StrCpy $InstallAttemptCompleted 0
FunctionEnd

Function RecordInstallCompleted
  FileOpen $0 "$INSTDIR\install.log" a
  FileSeek $0 0 END
  FileWrite $0 "COMPLETED version=${APP_VERSION} extensionOrigin=${EXTENSION_ORIGIN}$\r$\n"
  FileClose $0
  FileOpen $0 "$INSTDIR\install-result.json" w
  FileWrite $0 '{$\"schemaVersion$\":1,$\"status$\":$\"completed$\",$\"version$\":$\"${APP_VERSION}$\",$\"extensionOrigin$\":$\"${EXTENSION_ORIGIN}$\"}$\r$\n'
  FileClose $0
  StrCpy $InstallAttemptCompleted 1
FunctionEnd

Function RecordInstallFailed
  FileOpen $0 "$INSTDIR\install.log" a
  FileSeek $0 0 END
  FileWrite $0 "FAILED version=${APP_VERSION} extensionOrigin=${EXTENSION_ORIGIN}$\r$\n"
  FileClose $0
  FileOpen $0 "$INSTDIR\install-result.json" w
  FileWrite $0 '{$\"schemaVersion$\":1,$\"status$\":$\"failed$\",$\"version$\":$\"${APP_VERSION}$\",$\"extensionOrigin$\":$\"${EXTENSION_ORIGIN}$\"}$\r$\n'
  FileClose $0
  StrCpy $InstallAttemptStarted 0
FunctionEnd

Function IsRuntimeRunning
  nsExec::ExecToStack '"$SYSDIR\tasklist.exe" /FI "IMAGENAME eq AkuSidecar.exe" /NH'
  Pop $0
  Pop $1
  ${StrStr} $2 $1 "AkuSidecar.exe"
  ${If} $2 == ""
    Push 0
  ${Else}
    Push 1
  ${EndIf}
FunctionEnd

Function EnsureRuntimeStopped
  Call IsRuntimeRunning
  Pop $0
  ${If} $0 = 0
    Return
  ${EndIf}

  MessageBox MB_YESNO|MB_ICONEXCLAMATION|MB_DEFBUTTON2 "AkuBrowser Runtime is currently running as AkuSidecar.exe.$\r$\n$\r$\nIf another Setup window just completed, this may be an isolated antivirus duplicate. Select No to close this Setup window; do not run Repair twice.$\r$\n$\r$\nOnly select Yes if you intentionally started this installation or repair and want Setup to stop AkuBrowser Runtime now." /SD IDNO IDYES stop_runtime
  Abort

  stop_runtime:
  nsExec::ExecToStack '"$SYSDIR\taskkill.exe" /F /T /IM AkuSidecar.exe'
  Pop $0
  Pop $1
  Sleep 750
  Call IsRuntimeRunning
  Pop $0
  ${If} $0 != 0
    MessageBox MB_OK|MB_ICONSTOP "AkuBrowser Runtime (AkuSidecar.exe) is still running. Close it manually in Task Manager, then run Setup again."
    Abort
  ${EndIf}
FunctionEnd

Function .onInstSuccess
  ${If} $InstallAttemptStarted = 1
    Call RecordInstallCompleted
  ${EndIf}
FunctionEnd

Function .onInstFailed
  ${If} $InstallAttemptStarted = 1
    Call RecordInstallFailed
  ${EndIf}
FunctionEnd

Function un.onInit
  SetShellVarContext current
  StrCpy $UninstallFullReset 0
  IfSilent uninstall_choice_done
  MessageBox MB_YESNOCANCEL|MB_ICONQUESTION|MB_DEFBUTTON1 "Choose how AkuBrowser user data should be handled.$\r$\n$\r$\nYes: Preserve data for an ordinary uninstall or reinstall.$\r$\nNo: Full reset and permanently remove data plus downgrade archives.$\r$\nCancel: Close the uninstaller." /SD IDYES IDYES uninstall_choice_done IDNO uninstall_full_reset
  Abort

  uninstall_full_reset:
  StrCpy $UninstallFullReset 1

  uninstall_choice_done:
FunctionEnd

Section "AkuBrowser Runtime" InstallSection
  SectionIn RO
  SetOverwrite on
  Call EnsureRuntimeStopped
  Call RecordInstallStarted

  CreateDirectory "$INSTDIR\host"
  SetOutPath "$INSTDIR\host"
  File /r "${PAYLOAD_ROOT}\host\*"

  CreateDirectory "$INSTDIR\runtime\versions\${APP_VERSION}"
  SetOutPath "$INSTDIR\runtime\versions\${APP_VERSION}"
  File /r "${PAYLOAD_ROOT}\runtime\versions\${APP_VERSION}\*"

  SetOutPath "$INSTDIR"
  File /oname=install-manifest.json "${PAYLOAD_ROOT}\payload-manifest.json"

  ; Activate the new runtime only after every executable and support file was
  ; extracted successfully. An interrupted install therefore leaves the prior
  ; current.json authoritative.
  Call PrepareDowngradeData
  CreateDirectory "$INSTDIR\runtime"
  SetOutPath "$INSTDIR\runtime"
  File /oname=current.json "${PAYLOAD_ROOT}\runtime\current.json"

  CreateDirectory "$LOCALAPPDATA\AkuBrowser\data"
  FileOpen $0 "$LOCALAPPDATA\AkuBrowser\data\.runtime-version" w
  FileWrite $0 "${APP_VERSION}$\r$\n"
  FileClose $0

  ; Remove bootstrap executables left by the earlier nested-engine installer.
  Delete /REBOOTOK "$INSTDIR\host\AkuBrowserRuntimeMaintenance.exe"
  Delete /REBOOTOK "$INSTDIR\host\AkuBrowserRuntimeSetup.exe"

  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  WriteRegStr HKCU "${NATIVE_HOST_KEY}" "" "$INSTDIR\host\com.akubrowser.runtime.json"
  WriteRegStr HKCU "${PRODUCT_REGISTRY_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${PRODUCT_REGISTRY_KEY}" "Version" "${APP_VERSION}"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "Publisher" "${PRODUCT_PUBLISHER}"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "URLInfoAbout" "${PRODUCT_WEB_SITE}"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${PRODUCT_UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "${PRODUCT_UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${PRODUCT_UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  DeleteRegKey HKCU "${NATIVE_HOST_KEY}"
  DeleteRegKey HKCU "${PRODUCT_UNINSTALL_KEY}"
  DeleteRegKey HKCU "${PRODUCT_REGISTRY_KEY}"
  RMDir /r /REBOOTOK "$INSTDIR\host"
  RMDir /r /REBOOTOK "$INSTDIR\runtime"
  Delete /REBOOTOK "$INSTDIR\install-manifest.json"
  Delete /REBOOTOK "$INSTDIR\install-result.json"
  Delete /REBOOTOK "$INSTDIR\install.log"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  ${If} $UninstallFullReset = 1
    RMDir /r /REBOOTOK "$LOCALAPPDATA\AkuBrowser\data"
    RMDir /r /REBOOTOK "$LOCALAPPDATA\AkuBrowser\data-backups"
    Delete /REBOOTOK "$LOCALAPPDATA\AkuBrowser\downgrade-receipt.txt"
  ${EndIf}
SectionEnd
