#!/bin/sh
set -eu

runtime_root="$HOME/Library/Application Support/AkuBrowser"
chrome_manifest="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.akubrowser.runtime.json"
data_mode=""

case "${1:-}" in
  --preserve-data) data_mode="preserve" ;;
  --full-reset) data_mode="reset" ;;
  "") ;;
  *)
    echo "Usage: $0 [--preserve-data|--full-reset]" >&2
    exit 2
    ;;
esac

if [ -z "$data_mode" ] && [ -t 0 ]; then
  echo "Choose how AkuBrowser user data should be handled:"
  echo "  1) Preserve data (recommended for ordinary uninstall/reinstall)"
  echo "  2) Full reset (permanently remove data and downgrade archives)"
  printf "Selection [1]: "
  read -r selection
  case "$selection" in
    2) data_mode="reset" ;;
    *) data_mode="preserve" ;;
  esac
fi
data_mode="${data_mode:-preserve}"

case "$runtime_root" in
  /Users/*/Library/Application\ Support/AkuBrowser) ;;
  *)
    echo "AkuBrowser Runtime refused an unexpected uninstall target" >&2
    exit 1
    ;;
esac

/bin/rm -f "$chrome_manifest"
/bin/rm -rf "$runtime_root/host" "$runtime_root/runtime"
/bin/rm -f "$runtime_root/Uninstall-AkuBrowserRuntime.command"

if [ "$data_mode" = "reset" ]; then
  /bin/rm -rf "$runtime_root/data" "$runtime_root/data-backups"
  /bin/rm -f "$runtime_root/downgrade-receipt.json"
  echo "AkuBrowser Runtime and user data were removed by Full reset."
else
  echo "AkuBrowser Runtime was removed. User data was preserved at:"
  echo "$runtime_root/data"
fi
