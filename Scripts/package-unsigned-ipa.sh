#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?Usage: $0 path/to/OK4KiOS.app [output.ipa]}"
OUTPUT="${2:-OK4KiOS-TrollStore-unsigned.ipa}"

rm -rf Payload
mkdir -p Payload
cp -R "$APP_PATH" Payload/
/usr/bin/zip -qry "$OUTPUT" Payload
rm -rf Payload
printf 'Created %s\n' "$OUTPUT"
