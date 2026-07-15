#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <profile>" >&2
  exit 1
fi

PROFILE="$1"
TOPDIR="$(cd "$(dirname "$0")/.." && pwd)"
BASE_CONFIG="$TOPDIR/target/linux/renesas/myir-mys-rzg2l-wifi-minimal.config"
PROFILE_CONFIG="$TOPDIR/configs/myir-rzg2l/profiles/${PROFILE}.config"
OUTPUT_CONFIG="$TOPDIR/.config"

if [ ! -f "$BASE_CONFIG" ]; then
  echo "missing base config: $BASE_CONFIG" >&2
  exit 1
fi

if [ ! -f "$PROFILE_CONFIG" ]; then
  echo "missing profile config: $PROFILE_CONFIG" >&2
  exit 1
fi

"$TOPDIR/scripts/kconfig.pl" '+' "$BASE_CONFIG" "$PROFILE_CONFIG" > "$OUTPUT_CONFIG"
