#!/bin/sh
# Checks an Android App Bundle against Google Play's current requirements:
#   - targetSdkVersion is at least $MIN_TARGET_SDK (default 35; Flutter 3.47 sets 36);
#   - every 64-bit native library's (arm64-v8a, x86_64) ELF LOAD segments are aligned to 16 KB (devices with 16 KB
#     memory pages). Only 64-bit devices use 16 KB pages, so Play checks only 64-bit libraries; 32-bit (armeabi-v7a)
#     libraries are listed but not required (pdfrx's 32-bit libpdfium.so is 4 KB aligned);
#   - a universal APK made from the bundle, as Play would make one, passes `zipalign -c -P 16` (libraries stored
#     uncompressed on 16 KB boundaries).
# Usage: scripts/check-aab.sh app.aab path/to/bundletool.jar
# Needs java, unzip, readelf and the Android build-tools (zipalign) on PATH or under $ANDROID_HOME.
set -eu
aab=$1 bundletool=$2
min_target=${MIN_TARGET_SDK:-35}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

target=$(java -jar "$bundletool" dump manifest --bundle "$aab" --xpath /manifest/uses-sdk/@android:targetSdkVersion)
min=$(java -jar "$bundletool" dump manifest --bundle "$aab" --xpath /manifest/uses-sdk/@android:minSdkVersion)
echo "minSdkVersion $min, targetSdkVersion $target"
test "$target" -ge "$min_target" || { echo "targetSdkVersion $target is below $min_target" >&2; exit 1; }

echo "Permissions:"
java -jar "$bundletool" dump manifest --bundle "$aab" --xpath /manifest/uses-permission/@android:name | sed 's/^/  /'

unzip -q "$aab" 'base/lib/*' -d "$work/aab"
count=0
for so in "$work"/aab/base/lib/*/*.so; do
  # Each LOAD segment's alignment (the last column of `readelf -lW`) must be at least 0x4000.
  name=${so#"$work"/aab/}
  abi=$(basename "$(dirname "$so")")
  aligned=yes
  for align in $(readelf -lW "$so" | awk '$1 == "LOAD" { print $NF }'); do
    if [ $((align)) -lt 16384 ]; then aligned=$align; fi
  done
  if [ "$aligned" = yes ]; then
    echo "  16 KB aligned: $name"
  else
    case $abi in
      arm64-v8a|x86_64) echo "Not 16 KB aligned: $name ($aligned)" >&2; exit 1 ;;
      *) echo "  32-bit, 16 KB not required: $name ($aligned)" ;;
    esac
  fi
  count=$((count + 1))
done
test "$count" -gt 0 || { echo "No native libraries found in the bundle" >&2; exit 1; }

zipalign=$(command -v zipalign || ls -d "$ANDROID_HOME"/build-tools/*/zipalign | sort -V | tail -1)
# The universal APK is signed with the local debug key; it is only for this check and is thrown away.
java -jar "$bundletool" build-apks --bundle "$aab" --output "$work/universal.apks" --mode universal
unzip -q "$work/universal.apks" universal.apk -d "$work"
"$zipalign" -c -P 16 4 "$work/universal.apk"
echo "Universal APK passes zipalign -c -P 16"
