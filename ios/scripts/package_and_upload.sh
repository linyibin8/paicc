#!/usr/bin/env bash
set -euo pipefail

# PAI-CC iOS TestFlight 发布脚本
# 用法: ./scripts/package_and_upload.sh
#
# 需要先在 macstar 上配置发布环境变量文件:
# /Users/macstar/testflight-auto/ios-publish.env
#
# 或设置环境变量:
# export APP_BUNDLE_ID=com.evowit.paicc
# export APP_NAME=PAI-CC
# export ASC_KEY_ID=47SU743ZHZ
# ...

cd "$(dirname "$0")/.."

# ===== 发布环境变量 =====
# 优先使用本地环境变量，其次使用共享配置文件

SHARED_IOS_ENV="${SHARED_IOS_ENV:-/Users/macstar/testflight-auto/ios-publish.env}"
if [[ -f "$SHARED_IOS_ENV" ]]; then
  set -a
  source "$SHARED_IOS_ENV"
  set +a
fi

# PAI-CC 特定配置
export APP_NAME="${APP_NAME:-PAI-CC}"
export APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.evowit.paicc}"
export APP_VERSION="${APP_VERSION:-1.0.0}"
export APPLE_TEAM_ID="${APPLE_TEAM_ID:-N3G45G5H74}"
export APP_BUILD_NUMBER="${APP_BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
export APP_SKU="${APP_SKU:-paicc001}"

# App Store Connect API 配置
export ASC_KEY_ID="${ASC_KEY_ID:-47SU743ZHZ}"
export ASC_ISSUER_ID="${ASC_ISSUER_ID:-e5e4b9b8-e882-4f89-a35b-8f7fc95edfef}"
export ASC_KEY_PATH="${ASC_KEY_PATH:-/Users/macstar/Desktop/p12/AuthKey_47SU743ZHZ.p8}"
export ASC_USERNAME="${ASC_USERNAME:-643014114@qq.com}"

# 签名配置
export SIGNING_CERTIFICATE="${SIGNING_CERTIFICATE:-7DF2CDD786AE3F98BB0C14599BCFEA928A45B376}"
export SIGNING_KEYCHAIN="${SIGNING_KEYCHAIN:-$HOME/Library/Keychains/studylog-build.keychain-db}"
export SIGNING_KEYCHAIN_PASSWORD="${SIGNING_KEYCHAIN_PASSWORD:-studylog-build}"
export PROFILE_NAME="${PROFILE_NAME:-paicc_appstore_profile}"

# TestFlight 配置
export TESTFLIGHT_GROUP_NAME="${PAICC_TESTFLIGHT_GROUP_NAME:-PAICC Internal}"
export TESTFLIGHT_INTERNAL="${PAICC_TESTFLIGHT_INTERNAL:-1}"
export TESTER_EMAILS="${PAICC_TESTER_EMAILS:-269123786@qq.com,linyibin8@qq.com,3972104921@qq.com,643014114@qq.com}"
export WHAT_TO_TEST="${PAICC_WHAT_TO_TEST:-PAI-CC: 智能学习陪伴系统，支持语音交互、手势识别、AI 问答、TTS 语音合成。}"
export BUILD_WAIT_SECONDS="${PAICC_BUILD_WAIT_SECONDS:-1800}"

echo "============================================"
echo "PAI-CC iOS TestFlight 发布流程"
echo "============================================"
echo "App Name: $APP_NAME"
echo "Bundle ID: $APP_BUNDLE_ID"
echo "Version: $APP_VERSION (Build: $APP_BUILD_NUMBER)"
echo "Team ID: $APPLE_TEAM_ID"
echo "Group: $TESTFLIGHT_GROUP_NAME"
echo "============================================"

# ===== 1. 解锁 Keychain =====
echo ""
echo "=== 1. 解锁 Keychain ==="
if [[ -f "$SIGNING_KEYCHAIN" ]]; then
  security unlock-keychain -p "$SIGNING_KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN"
  security list-keychains -d user -s "$SIGNING_KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
  security default-keychain -s "$SIGNING_KEYCHAIN"
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$SIGNING_KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN" >/dev/null
  echo "Keychain 已解锁并配置"
else
  echo "警告: 专用签名 keychain 不存在，尝试使用登录 keychain"
  security unlock-keychain -p "$SIGNING_KEYCHAIN_PASSWORD" "$HOME/Library/Keychains/login.keychain-db"
fi

# ===== 2. 准备 API 密钥和应用图标 =====
echo ""
echo "=== 2. 准备 API 密钥和应用图标 ==="
mkdir -p private_keys ~/.private_keys
if [[ -f "$ASC_KEY_PATH" ]]; then
  cp "$ASC_KEY_PATH" "private_keys/AuthKey_${ASC_KEY_ID}.p8"
  cp "$ASC_KEY_PATH" ~/.private_keys/ || true
  echo "API 密钥已复制"
else
  echo "警告: ASC 密钥文件不存在于 $ASC_KEY_PATH"
fi

python3 scripts/generate_app_icons.py || true

# ===== 3. 确保 App Store Connect App 和 Profile =====
echo ""
echo "=== 3. 确保 App Store Connect App 和 Profile ==="
SETUP_OUTPUT=$(python3 scripts/ensure_asc_app.py 2>&1)
echo "$SETUP_OUTPUT"

PROFILE_PATH=$(echo "$SETUP_OUTPUT" | awk -F= '/PROFILE_PATH=/{print $2; exit}')
ASC_APP_ID=$(echo "$SETUP_OUTPUT" | awk -F= '/ASC_APP_ID=/{print $2; exit}')

if [[ -z "$PROFILE_PATH" || -z "$ASC_APP_ID" ]]; then
  echo "无法解析 ASC 设置输出" >&2
  exit 1
fi
export ASC_APP_ID
echo "ASC App ID: $ASC_APP_ID"

# ===== 4. 生成 Xcode 项目 =====
echo ""
echo "=== 4. 生成 Xcode 项目 ==="
export PATH="$HOME/bin:$PATH"
if [[ -f "$HOME/bin/xcodegen" ]]; then
  xcodegen generate
elif command -v xcodegen &> /dev/null; then
  xcodegen generate
else
  echo "警告: xcodegen 未找到，请确保已安装"
  # 检查是否已有 xcodeproj
  if [[ ! -f "PAICC.xcodeproj" ]]; then
    echo "错误: 没有找到 Xcode 项目文件，请先运行 xcodegen" >&2
    exit 1
  fi
  echo "使用已有的 Xcode 项目"
fi

# ===== 5. Archive 未签名构建 =====
echo ""
echo "=== 5. Archive 未签名构建 ==="
rm -rf build
mkdir -p build

xcodebuild \
  -project PAICC.xcodeproj \
  -scheme PAICC \
  -configuration Release \
  -destination generic/platform=iOS \
  -archivePath build/PAICC.xcarchive \
  APPLE_TEAM_ID="$APPLE_TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$APP_BUNDLE_ID" \
  MARKETING_VERSION="$APP_VERSION" \
  CURRENT_PROJECT_VERSION="$APP_BUILD_NUMBER" \
  CODE_SIGNING_ALLOWED=NO \
  clean archive

APP_PATH="build/PAICC.xcarchive/Products/Applications/PAICC.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Archive 未生成 $APP_PATH" >&2
  exit 1
fi
echo "Archive 成功"

# ===== 6. 签名应用 =====
echo ""
echo "=== 6. 签名应用 ==="
cp "$PROFILE_PATH" "$APP_PATH/embedded.mobileprovision"
security cms -D -i "$PROFILE_PATH" > build/profile.plist
/usr/libexec/PlistBuddy -x -c 'Print :Entitlements' build/profile.plist > build/entitlements.plist

# 签名 Frameworks
if [[ -d "$APP_PATH/Frameworks" ]]; then
  while IFS= read -r -d '' item; do
    /usr/bin/codesign --force --keychain "$SIGNING_KEYCHAIN" --sign "$SIGNING_CERTIFICATE" "$item"
  done < <(find "$APP_PATH/Frameworks" \( -name '*.framework' -o -name '*.dylib' \) -print0)
  echo "Frameworks 签名完成"
fi

# 签名主应用 - 尝试使用 rcodesign（如果可用）
RCODESIGN="/Users/macstar/Tools/apple-codesign/apple-codesign-0.29.0-macos-universal/rcodesign"
if [[ -f "$RCODESIGN" && -f "/Users/macstar/Desktop/p12/dist_cert_private_key.pem" && -f "/Users/macstar/Desktop/p12/distribution-cert.pem" ]]; then
  "$RCODESIGN" sign \
    --pem-file /Users/macstar/Desktop/p12/dist_cert_private_key.pem \
    --pem-file /Users/macstar/Desktop/p12/distribution-cert.pem \
    --timestamp-url none \
    --entitlements-xml-file build/entitlements.plist \
    "$APP_PATH" < /dev/null
  echo "使用 rcodesign 签名完成"
else
  # 回退到标准 codesign
  /usr/bin/codesign \
    --force \
    --keychain "$SIGNING_KEYCHAIN" \
    --sign "$SIGNING_CERTIFICATE" \
    --entitlements build/entitlements.plist \
    --generate-entitlement-der \
    "$APP_PATH"
  echo "使用标准 codesign 签名完成"
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "签名验证通过"

# ===== 7. 打包 IPA =====
echo ""
echo "=== 7. 打包 IPA ==="
mkdir -p build/package/Payload build/export
ditto "$APP_PATH" "build/package/Payload/PAICC.app"

# 复制 SwiftSupport（如果存在）
if [[ -d "build/PAICC.xcarchive/SwiftSupport" ]]; then
  ditto "build/PAICC.xcarchive/SwiftSupport" "build/package/SwiftSupport"
fi

# 复制ibrately支持
if [[ -d "build/PAICC.xcarchive/PlugIns" ]]; then
  ditto "build/PAICC.xcarchive/PlugIns" "build/package/Payload/PAICC.app/PlugIns"
fi

(cd build/package && zip -qry ../export/PAICC.ipa Payload SwiftSupport 2>/dev/null || zip -qry ../export/PAICC.ipa Payload)
echo "IPA 已生成: build/export/PAICC.ipa"

# ===== 8. 上传到 TestFlight =====
echo ""
echo "=== 8. 上传到 TestFlight ==="
xcrun altool --upload-app \
  --type ios \
  -f build/export/PAICC.ipa \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID" \
  --verbose

# ===== 9. 配置 TestFlight =====
echo ""
echo "=== 9. 配置 TestFlight ==="
python3 scripts/configure_testflight.py

# ===== 清理 =====
security list-keychains -d user -s "$SIGNING_KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db" || true

echo ""
echo "============================================"
echo "FULL PIPELINE COMPLETED"
echo "============================================"
echo "App: $APP_NAME ($APP_BUNDLE_ID)"
echo "Version: $APP_VERSION ($APP_BUILD_NUMBER)"
echo "TestFlight Group: $TESTFLIGHT_GROUP_NAME"
echo "============================================"