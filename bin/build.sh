#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! xcodebuild -scheme GMRSRadioQuery -configuration Release -derivedDataPath build build; then
    echo "Build failed. GMRSRadioQuery.app was not replaced." >&2
    exit 1
fi

built="build/Build/Products/Release/GMRSRadioQuery.app"
if [[ ! -d "$built" ]]; then
    echo "Build finished without producing $built. GMRSRadioQuery.app was not replaced." >&2
    exit 1
fi

rm -rf GMRSRadioQuery.app
ditto "$built" GMRSRadioQuery.app


