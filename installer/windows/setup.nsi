Unicode true

!include "MUI2.nsh"
!include "LogicLib.nsh"

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

!define PRODUCT_NAME "AkuBrowser Runtime"
!define PRODUCT_PUBLISHER "AkuBrowser"
!define PRODUCT_WEB_SITE "https://github.com/abangkis/AkuBrowser"
!define PRODUCT_REGISTRY_KEY "Software\AkuBrowser\Runtime"
!define PRODUCT_UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\AkuBrowserRuntime"
!define NATIVE_HOST_KEY "Software\Google\Chrome\NativeMessagingHosts\com.akubrowser.runtime"

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
  !define MUI_WELCOMEPAGE_TEXT "This wizard installs AkuSidecar, the Chrome Native Messaging Host, and the C2PA verifier.$\r$\n$\r$\nCodex App is installed separately.$\r$\n$\r$\nTesting notice: this build is not code-signed. Windows Security or antivirus software may warn or quarantine it. Continue only if you downloaded it from the official AkuBrowser GitHub release."
!else
  !define MUI_WELCOMEPAGE_TEXT "This wizard installs AkuSidecar, the Chrome Native Messaging Host, and the C2PA verifier.$\r$\n$\r$\nCodex App is installed separately. Select Next to choose where the AkuBrowser Runtime program files will be installed."
!endif
!define MUI_DIRECTORYPAGE_TEXT_TOP "Select the folder for AkuBrowser Runtime program files. Your AkuBrowser database remains in your local application-data folder and is not removed by updates or uninstall."
!define MUI_FINISHPAGE_TITLE "AkuBrowser Runtime is installed"
!define MUI_FINISHPAGE_TEXT "Return to Chrome, open AkuBrowser Setup, and select Check runtime. You can later update, run, or stop the runtime from the same page."
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
FunctionEnd

Function un.onInit
  SetShellVarContext current
FunctionEnd

Section "AkuBrowser Runtime" InstallSection
  SectionIn RO
  SetOverwrite on

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
  CreateDirectory "$INSTDIR\runtime"
  SetOutPath "$INSTDIR\runtime"
  File /oname=current.json "${PAYLOAD_ROOT}\runtime\current.json"

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
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
SectionEnd
