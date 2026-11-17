#!/bin/sh
# The app version, from pubspec.yaml (without the build number).
sed -n 's/^version: *\([^+]*\).*/\1/p' "$(dirname "$0")/../pubspec.yaml"
