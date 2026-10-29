#!/bin/bash

set -euo pipefail

version="2.4.6"
package_id="com.custom.diskencrypter"
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
source_script="$repo_root/DiskEncrypter_Enhanced-NO-ERASE.sh"
launchdaemon="$script_dir/com.custom.diskencrypter.plist"
installer_scripts="$script_dir/scripts"
output_dir="${1:-$repo_root/release/2.4.6}"
signing_identity="${DEVELOPER_ID_INSTALLER:-}"
notary_profile="${NOTARY_PROFILE:-notary-profile}"
package_name="DiskEncrypter_Enhanced_v${version}.pkg"
package_path="$output_dir/$package_name"

if [[ -z "$signing_identity" ]]; then
    echo "Set DEVELOPER_ID_INSTALLER to a Developer ID Installer identity." >&2
    exit 2
fi

for required in "$source_script" "$launchdaemon" "$installer_scripts/preinstall" "$installer_scripts/postinstall"; do
    [[ -f "$required" ]] || { echo "Missing required file: $required" >&2; exit 2; }
done

/bin/bash -n "$source_script"
/bin/bash -n "$installer_scripts/preinstall"
/bin/bash -n "$installer_scripts/postinstall"
/usr/bin/plutil -lint "$launchdaemon"
/usr/bin/grep -q 'Version: 2.4.6' "$source_script"
/usr/bin/grep -q 'active-exception.plist' "$source_script"

if [[ -e "$package_path" ]]; then
    echo "Refusing to overwrite existing artifact: $package_path" >&2
    exit 2
fi

build_root="$(/usr/bin/mktemp -d /private/tmp/diskencrypter-2.4.6.XXXXXX)"
cleanup() {
    [[ "$build_root" == /private/tmp/diskencrypter-2.4.6.* ]] && /bin/rm -rf "$build_root"
}
trap cleanup EXIT

payload="$build_root/payload"
component="$build_root/component.pkg"
expanded="$build_root/expanded"
/bin/mkdir -p \
    "$payload/Library/Application Support/Custom" \
    "$payload/Library/LaunchDaemons" \
    "$output_dir"

COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr \
    "$source_script" \
    "$payload/Library/Application Support/Custom/DiskEncrypter_Enhanced.sh"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr \
    "$launchdaemon" \
    "$payload/Library/LaunchDaemons/com.custom.diskencrypter.plist"
/bin/chmod 755 "$payload/Library/Application Support/Custom/DiskEncrypter_Enhanced.sh"
/bin/chmod 644 "$payload/Library/LaunchDaemons/com.custom.diskencrypter.plist"

/usr/bin/pkgbuild \
    --root "$payload" \
    --scripts "$installer_scripts" \
    --identifier "$package_id" \
    --version "$version" \
    --install-location / \
    --ownership recommended \
    "$component"

/usr/bin/productbuild \
    --package "$component" \
    --sign "$signing_identity" \
    "$package_path"

/usr/sbin/pkgutil --check-signature "$package_path"
/usr/sbin/spctl --assess --type install --verbose=4 "$package_path"

/usr/bin/xcrun notarytool submit "$package_path" \
    --keychain-profile "$notary_profile" \
    --wait \
    --output-format json > "$output_dir/notarization-${version}.json"
/usr/bin/xcrun stapler staple "$package_path"
/usr/bin/xcrun stapler validate "$package_path"

/usr/sbin/pkgutil --expand-full "$package_path" "$expanded"
/usr/bin/grep -R -q "identifier=\"$package_id\"" "$expanded"
/usr/bin/grep -R -q "version=\"$version\"" "$expanded"
if /usr/bin/find "$expanded" -name '._*' -print -quit | /usr/bin/grep -q .; then
    echo "AppleDouble files were found in the finished package." >&2
    exit 1
fi
if /usr/bin/find "$expanded" -path '*/Library/Managed Preferences/*' -print -quit | /usr/bin/grep -q .; then
    echo "The package must not overwrite MDM-managed preferences." >&2
    exit 1
fi

/usr/bin/shasum -a 256 "$package_path" > "$package_path.sha256.txt"
{
    echo "DiskEncrypter Enhanced ${version}"
    echo "Package ID: $package_id"
    echo "Package: $package_path"
    echo "Signed: $signing_identity"
    echo "Notary profile: $notary_profile"
    echo "SHA-256: $(/usr/bin/awk '{print $1}' "$package_path.sha256.txt")"
} > "$output_dir/DiskEncrypter_Enhanced_v${version}.release.txt"

echo "Package complete: $package_path"
