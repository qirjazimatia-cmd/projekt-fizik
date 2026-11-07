#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
if ! xcrun --find xcodebuild >/dev/null 2>&1; then
  echo 'Hap Xcode dhe përfundo instalimin e komponentëve; pastaj provo përsëri.'
  exit 1
fi
mkdir -p Verification
xcodebuild -project ScienceQuest.xcodeproj -scheme ScienceQuest -configuration Debug -destination 'platform=macOS' -derivedDataPath Verification/DerivedData CODE_SIGNING_ALLOWED=NO build 2>&1 | tee Verification/mac-build.log
xcodebuild -project ScienceQuest.xcodeproj -scheme ScienceQuest -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath Verification/DerivedData CODE_SIGNING_ALLOWED=NO build 2>&1 | tee Verification/ios-build.log
xcodebuild -project ScienceQuest.xcodeproj -scheme ScienceQuest -destination 'platform=macOS' -derivedDataPath Verification/DerivedData CODE_SIGNING_ALLOWED=NO test 2>&1 | tee Verification/mac-tests.log
python3 Tests/check_content.py
python3 Tests/check_supabase_contract.py
(cd Server && python3 -m unittest -v test_server.py)
echo 'Kompilimi dhe testet e automatizuara kaluan. Tani kryej provat e UI-së te PROVAT-NE-XCODE.md.'
