#!/bin/bash
# Disciplined blocker helper — runs as root via launchd.
# Rewrites the Disciplined section of /etc/hosts from the user's blocklist file. Browsers also get
# their own blocking so proxies (Surge, Clash…), VPNs and DNS-over-HTTPS can't bypass it there.
# Every Firefox-based browser in /Applications or ~/Applications gets one of two policies:
# - "extension": force-installs the Disciplined extension (built by the app next to the blocklist),
#   which gets the list from the app and updates without a restart. Needs a browser that allows
#   unsigned add-ons (Zen, LibreWolf, Developer Edition, Nightly, ESR…) on Gecko 128 or later.
# - "filter": mirrors the list into a WebsiteFilter policy, read only when the browser starts.
#   Used for release Firefox, which only installs extensions signed by Mozilla.
# The result is recorded in browsers.tsv for the app. Chromium browsers: the user loads the extension.
# Usage: apply-blocklist.sh <path-to-blocklist>
# helper-version: 7

LIST="$1"
HOSTS="/etc/hosts"
BEGIN_MARK="# >>> Disciplined blocklist >>>"
END_MARK="# <<< Disciplined blocklist <<<"
DOMAIN_RE='^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$'

# Browsers read mandatory policies from here, keyed by their preference domain.
MANAGED_PREFS="/Library/Managed Preferences"
EXTENSION_ID="disciplined@disciplined.mac"
# Oldest Gecko whose declarativeNetRequest supports everything the extension uses in Manifest V2.
MIN_EXTENSION_GECKO=128
BUNDLE_ID_RE='^[A-Za-z0-9][A-Za-z0-9.-]*$'
# Read by the app: one "bundle-id<TAB>mode<TAB>profile-folder<TAB>app-path" line per browser.
STATE_DIR="/Library/Application Support/Disciplined"
BROWSERS_FILE="$STATE_DIR/browsers.tsv"
# Written by helper version 6, before browsers were detected.
OLD_FIREFOX_IDS="org.mozilla.firefox app.zen-browser.zen"
# Earlier helper versions wrote URLBlocklist policies for these; they're removed so they can't
# conflict with the extension (running browsers never see policy changes, so they'd go stale).
OLD_CHROMIUM_IDS="com.google.Chrome com.brave.Browser com.microsoft.Edge org.chromium.Chromium com.vivaldi.Vivaldi"

tmpdir="$(mktemp -d /tmp/disciplined.XXXXXX)" || exit 1
trap 'rm -rf "$tmpdir"' EXIT
tmp="$tmpdir/hosts"

# Copy hosts without our previous section.
awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
  $0 == b { skip = 1; next }
  $0 == e { skip = 0; next }
  !skip
' "$HOSTS" > "$tmp" || exit 1

# Only accept strictly valid, lowercase domain names (the list file is user-writable).
domains=""
if [ -n "$LIST" ] && [ -f "$LIST" ]; then
  domains="$(tr -d '\r' < "$LIST" | grep -E "$DOMAIN_RE" | head -n 5000 | sort -u)"
fi

if [ -n "$domains" ]; then
  {
    echo "$BEGIN_MARK"
    for d in $domains; do
      for h in "$d" "www.$d" "m.$d"; do
        echo "0.0.0.0 $h"
        echo ":: $h"
      done
    done
    echo "$END_MARK"
  } >> "$tmp"
fi

if ! cmp -s "$tmp" "$HOSTS"; then
  cat "$tmp" > "$HOSTS"
  dscacheutil -flushcache 2>/dev/null
  killall -HUP mDNSResponder 2>/dev/null
fi

# --- Browser policies ---

# Writes a browser's policy plist from the XML <dict> body in $2, or removes it when $2 is empty.
# Written directly: cfprefsd treats Managed Preferences as read-only, so `defaults` can't write there.
policies_changed=""
apply_policy() {
  local file="$MANAGED_PREFS/$1.plist" body="$2" want="$tmpdir/$1.plist"
  if [ -z "$body" ]; then
    if [ -f "$file" ]; then
      rm -f "$file"
      policies_changed=1
    fi
    return
  fi
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>%s</dict></plist>\n' "$body" > "$want"
  plutil -convert xml1 "$want" || return
  if ! cmp -s "$want" "$file"; then
    mkdir -p "$MANAGED_PREFS"
    install -o root -g wheel -m 644 "$want" "$file" && policies_changed=1
  fi
}

# Written even when the list is empty: the app compares the file's date with the browser's launch
# to tell when a restart is needed, and that includes turning blocking off.
filter_body=""
if [ -n "$LIST" ]; then
  # "*.example.com" matches the domain itself too.
  filter_list=""
  for d in $domains; do
    filter_list="$filter_list<string>*://*.$d/*</string>"
  done
  filter_body="<key>EnterprisePoliciesEnabled</key><true/><key>WebsiteFilter</key><dict><key>Block</key><array>$filter_list</array></dict>"
fi

# The extension is reinstalled from a file: URL every time the browser starts, so updates to the
# .xpi land on the next restart. Only browsers built without mandatory signing get this policy,
# and they need the signing pref turned off to accept the unsigned build.
extension_body=""
xpi="$(dirname "$LIST")/Disciplined.xpi"
if [ -n "$LIST" ] && [ -f "$xpi" ]; then
  case "$xpi" in
    *[\<\>\&\"\'%#?]*) ;; # Would need escaping in the plist or URL; fall back to WebsiteFilter.
    *)
      xpi_url="file://$(printf '%s' "$xpi" | sed 's/ /%20/g')"
      extension_body="<key>EnterprisePoliciesEnabled</key><true/>"
      extension_body="$extension_body<key>ExtensionSettings</key><dict><key>$EXTENSION_ID</key><dict>"
      extension_body="$extension_body<key>installation_mode</key><string>force_installed</string>"
      extension_body="$extension_body<key>install_url</key><string>$xpi_url</string></dict></dict>"
      extension_body="$extension_body<key>Preferences</key><dict><key>xpinstall.signatures.required</key>"
      extension_body="$extension_body<dict><key>Value</key><false/><key>Status</key><string>locked</string></dict></dict>"
      ;;
  esac
fi

# Prints a key's value from one of a Gecko app's .ini files.
ini_value() {
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -n 1 | tr -d '\r'
}

# Lists installed Firefox-based browsers as browsers.tsv lines.
find_gecko_browsers() {
  local user_home="${LIST%/Library/Application Support/Disciplined/blocklist.txt}"
  local app res id milestone profile mode
  for app in /Applications/*.app "$user_home"/Applications/*.app; do
    [ -n "$LIST" ] || break
    res="$app/Contents/Resources"
    [ -f "$res/omni.ja" ] && [ -f "$res/browser/omni.ja" ] && [ -f "$res/application.ini" ] || continue
    case "$app" in *$'\t'* | *$'\n'*) continue ;; esac
    id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null)"
    [[ "$id" =~ $BUNDLE_ID_RE ]] || continue
    # The folder under ~/Library/Application Support that holds the browser's profiles.
    profile="$(ini_value "$res/application.ini" Profile)"
    [ -n "$profile" ] || profile="$(ini_value "$res/application.ini" Name)"
    case "$profile" in */* | *$'\t'* | "") continue ;; esac
    milestone="$(ini_value "$res/platform.ini" Milestone)"
    mode=filter
    if [ -n "$extension_body" ] && [ "${milestone%%.*}" -ge "$MIN_EXTENSION_GECKO" ] 2>/dev/null &&
      unzip -p "$res/omni.ja" modules/AppConstants.sys.mjs 2>/dev/null | grep -q 'MOZ_REQUIRE_SIGNING: false'; then
      mode=extension
    fi
    printf '%s\t%s\t%s\t%s\n' "$id" "$mode" "$profile" "$app"
  done | sort -t $'\t' -k1,1 -u
}

browsers="$(find_gecko_browsers)"
current_ids=""
while IFS=$'\t' read -r id mode _; do
  [ -n "$id" ] || continue
  if [ "$mode" = extension ]; then apply_policy "$id" "$extension_body"; else apply_policy "$id" "$filter_body"; fi
  current_ids="$current_ids $id "
done <<< "$browsers"

# Remove policies left for browsers that are gone (or were handled by earlier helper versions).
for id in $OLD_CHROMIUM_IDS $OLD_FIREFOX_IDS $(cut -f 1 "$BROWSERS_FILE" 2>/dev/null); do
  [[ "$id" =~ $BUNDLE_ID_RE ]] || continue
  case "$current_ids" in *" $id "*) ;; *) apply_policy "$id" "" ;; esac
done

if [ -n "$browsers" ]; then printf '%s\n' "$browsers" > "$tmpdir/browsers.tsv"; else : > "$tmpdir/browsers.tsv"; fi
if ! cmp -s "$tmpdir/browsers.tsv" "$BROWSERS_FILE"; then
  mkdir -p "$STATE_DIR"
  install -o root -g wheel -m 644 "$tmpdir/browsers.tsv" "$BROWSERS_FILE"
fi

# cfprefsd caches managed preferences and never notices the files changing, so browsers would keep
# getting the old policy. Restart it (launchd relaunches it on demand) so they read the new files.
if [ -n "$policies_changed" ]; then
  killall cfprefsd 2>/dev/null
fi
exit 0
