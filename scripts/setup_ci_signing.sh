#!/bin/bash
set -euo pipefail

mkdir -p private_keys

printf '%s' "$APP_STORE_CONNECT_API_KEY_BASE64" | base64 --decode > "private_keys/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
printf '%s' "$BUILD_CERTIFICATE_BASE64" | base64 --decode > certificate.p12
curl -fsSL "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer" -o AppleWWDRCAG3.cer

security create-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
security default-keychain -s build.keychain
security unlock-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
security set-keychain-settings -lut 21600 build.keychain
security list-keychains -d user -s build.keychain login.keychain-db /Library/Keychains/System.keychain /System/Library/Keychains/SystemRootCertificates.keychain
security import certificate.p12 -k build.keychain -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security import AppleWWDRCAG3.cer -k build.keychain -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" build.keychain