#!/bin/sh
set -eu

runtime_root="$HOME/Library/Application Support/AkuBrowser"
chrome_manifest="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.akubrowser.runtime.json"

/bin/rm -f "$chrome_manifest"
/bin/rm -rf "$runtime_root/host" "$runtime_root/runtime"
/bin/rm -f "$runtime_root/Uninstall-AkuBrowserRuntime.command"

echo "AkuBrowser Runtime was removed. User data was preserved at:"
echo "$runtime_root/data"
