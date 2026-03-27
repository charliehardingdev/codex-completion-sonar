#!/bin/zsh
set -euo pipefail

APP_NAME="CodexCompletionSonar"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$HOME/Applications/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICONSET_DIR="${SRC_DIR}/AppIcon.iconset"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${ICONSET_DIR}"

swiftc "${SRC_DIR}/CompletionSonar.swift" \
  -o "${MACOS_DIR}/${APP_NAME}" \
  -framework Cocoa \
  -lsqlite3

cp "${SRC_DIR}/Info.plist" "${CONTENTS_DIR}/Info.plist"

for size in 16 32 64 128 256 512; do
  magick -background none "${SRC_DIR}/AppIcon.svg" -resize "${size}x${size}" "${ICONSET_DIR}/icon_${size}x${size}.png"
done
cp "${ICONSET_DIR}/icon_32x32.png" "${ICONSET_DIR}/icon_16x16@2x.png"
cp "${ICONSET_DIR}/icon_64x64.png" "${ICONSET_DIR}/icon_32x32@2x.png"
cp "${ICONSET_DIR}/icon_256x256.png" "${ICONSET_DIR}/icon_128x128@2x.png"
cp "${ICONSET_DIR}/icon_512x512.png" "${ICONSET_DIR}/icon_256x256@2x.png"
magick -background none "${SRC_DIR}/AppIcon.svg" -resize 1024x1024 "${ICONSET_DIR}/icon_512x512@2x.png"

iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/AppIcon.icns"
chmod +x "${MACOS_DIR}/${APP_NAME}"
