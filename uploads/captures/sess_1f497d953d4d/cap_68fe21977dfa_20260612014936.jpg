# PAI-CC iOS TestFlight 发布复盘指南

## 发布结果

| 项目 | 值 |
|------|-----|
| App Name | PAI-CC |
| Bundle ID | com.evowit.paicc |
| App Store Connect App ID | 6779175815 |
| Apple Team ID | N3G45G5H74 |
| Version | 1.0.0 |
| Build Number | 20260611204325 |
| Build State | **VALID** |
| Export Compliance | **false** (已豁免) |
| TestFlight Group | PAICC Internal (ID: b3853bd5-a3cf-418a-9696-04a283fc4970) |
| Testers | 4人成功添加 |

## 发布环境

- **Mac 发布机**: macstar@100.64.0.6
- **证书目录**: `/Users/macstar/Desktop/p12/`
- **API Key**: `AuthKey_47SU743ZHZ.p8`
- **签名证书**: `distribution.p12`, `distribution-cert.pem`, `dist_cert_private_key.pem`
- **发布环境文件**: `/Users/macstar/testflight-auto/ios-publish-paicc.env`
- **备用 ITMS 脚本**: `/Users/macstar/studyLog/scripts/assign_testflight_testers_via_itms.py`

---

## 完整发布流程

### 1. 同步代码到 Mac

```bash
# 从本地同步到 macstar
rsync -avz --delete \
  -e "ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no" \
  /home/ydz/projects/pai-cc/ios/ \
  macstar@100.64.0.6:~/pai-cc/

# 在 macstar 上设置权限
ssh -i ~/.ssh/id_ed25519 macstar@100.64.0.6 "cd ~/pai-cc && chmod +x scripts/*.sh scripts/*.py && perl -pi -e 's/\r$//' scripts/*.sh"
```

### 2. 生成 App Icons (关键步骤)

**问题**: App Store 要求所有尺寸的图标，Assets.car 中没有 AppIcon 会导致上传失败。

**解决方案**: 使用 Python PIL 生成所有必需尺寸的图标。

```python
# generate_app_icons.py
from PIL import Image
sizes = [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]
for size in sizes:
    img = Image.new('RGB', (size, size), (0, 123, 246))  # 蓝色图标
    img.save(f'AppIcon-{size}x{size}.png', 'PNG')
```

**Contents.json 必须包含 filename 字段**:

```json
{
  "images": [
    {"idiom": "universal", "platform": "ios", "scale": "2x", "size": "20x20", "filename": "AppIcon-40x40.png"},
    {"idiom": "universal", "platform": "ios", "scale": "3x", "size": "20x20", "filename": "AppIcon-60x60.png"},
    {"idiom": "universal", "platform": "ios", "scale": "2x", "size": "29x29", "filename": "AppIcon-58x58.png"},
    {"idiom": "universal", "platform": "ios", "scale": "3x", "size": "29x29", "filename": "AppIcon-87x87.png"},
    {"idiom": "universal", "platform": "ios", "scale": "2x", "size": "40x40", "filename": "AppIcon-80x80.png"},
    {"idiom": "universal", "platform": "ios", "scale": "3x", "size": "40x40", "filename": "AppIcon-120x120.png"},
    {"idiom": "iphone", "scale": "2x", "size": "60x60", "filename": "AppIcon-120x120.png"},
    {"idiom": "iphone", "scale": "3x", "size": "60x60", "filename": "AppIcon-180x180.png"},
    {"idiom": "ipad", "scale": "1x", "size": "76x76", "filename": "AppIcon-76x76.png"},
    {"idiom": "ipad", "scale": "2x", "size": "76x76", "filename": "AppIcon-152x152.png"},
    {"idiom": "ipad", "scale": "2x", "size": "83.5x83.5", "filename": "AppIcon-167x167.png"},
    {"idiom": "ios-marketing", "scale": "1x", "size": "1024x1024", "filename": "AppIcon-1024x1024.png"}
  ],
  "info": {"author": "xcode", "version": 1}
}
```

### 3. 更新 Info.plist

```bash
# 添加 CFBundleIconName
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconName string AppIcon' Info.plist

# 确保出口合规声明（已豁免）
# Info.plist 中必须有:
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

### 4. 生成 Xcode 项目

```bash
export PATH="$HOME/bin:$PATH"
xcodegen generate
```

### 5. Archive 未签名构建

```bash
xcodebuild \
  -project PAICC.xcodeproj \
  -scheme PAICC \
  -configuration Release \
  -destination generic/platform=iOS \
  -archivePath build/PAICC.xcarchive \
  APPLE_TEAM_ID="N3G45G5H74" \
  PRODUCT_BUNDLE_IDENTIFIER="com.evowit.paicc" \
  MARKETING_VERSION="1.0.0" \
  CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M%S)" \
  CODE_SIGNING_ALLOWED=NO \
  clean archive
```

**关键**: 使用 `CODE_SIGNING_ALLOWED=NO` 避免 Xcode 自动签名问题，手动签名更可靠。

### 6. 签名应用

```bash
# 解锁 keychain
security unlock-keychain -p "studylog-build" "$HOME/Library/Keychains/studylog-build.keychain-db"
security list-keychains -d user -s "$HOME/Library/Keychains/studylog-build.keychain-db" "$HOME/Library/Keychains/login.keychain-db"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "studylog-build" "$HOME/Library/Keychains/studylog-build.keychain-db"

# 嵌入 provisioning profile
cp "$PROFILE_PATH" "$APP_PATH/embedded.mobileprovision"
security cms -D -i "$PROFILE_PATH" > build/profile.plist
/usr/libexec/PlistBuddy -x -c 'Print :Entitlements' build/profile.plist > build/entitlements.plist

# 使用 rcodesign 签名（优先）
RCODESIGN="/Users/macstar/Tools/apple-codesign/apple-codesign-0.29.0-macos-universal/rcodesign"
"$RCODESIGN" sign \
  --pem-file /Users/macstar/Desktop/p12/dist_cert_private_key.pem \
  --pem-file /Users/macstar/Desktop/p12/distribution-cert.pem \
  --timestamp-url none \
  --entitlements-xml-file build/entitlements.plist \
  "$APP_PATH"

# 验证签名
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
```

### 7. 打包 IPA

```bash
mkdir -p build/package/Payload build/export
ditto "$APP_PATH" "build/package/Payload/PAICC.app"
if [[ -d "build/PAICC.xcarchive/SwiftSupport" ]]; then
  ditto "build/PAICC.xcarchive/SwiftSupport" "build/package/SwiftSupport"
fi
(cd build/package && zip -qry ../export/PAICC.ipa Payload SwiftSupport)
```

### 8. 上传到 TestFlight

```bash
xcrun altool --upload-app \
  --type ios \
  -f build/export/PAICC.ipa \
  --apiKey "47SU743ZHZ" \
  --apiIssuer "e5e4b9b8-e882-4f89-a35b-8f7fc95edfef"
```

### 9. 配置 TestFlight

```bash
# 设置出口合规
python3 scripts/configure_testflight.py
```

---

## 遇到的问题与解决方案

### 问题 1: App Icon 缺失

**错误**: `Missing required icon file. The bundle does not contain an app icon for iPad of exactly '152x152' pixels`

**原因**:
- Contents.json 格式不正确
- PNG 文件是无效的（文件太小）
- 没有指定 filename 字段

**解决**:
1. 使用 PIL 生成有效的 PNG 图标
2. 按照 Xcode 标准格式编写 Contents.json
3. 每个 image 条目必须包含 `filename` 字段

### 问题 2: Info.plist 缺少 CFBundleIconName

**错误**: `Missing Info.plist value. A value for the Info.plist key 'CFBundleIconName' is missing`

**解决**:
```bash
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconName string AppIcon' Info.plist
```

### 问题 3: Build Number 重复

**错误**: `Redundant Binary Upload. You've already uploaded a build with build number '202606112039'`

**解决**: 每次上传前递增 build number
```bash
export APP_BUILD_NUMBER="$(date +%Y%m%d%H%M%S)"
```

### 问题 4: 测试员无法通过 API 添加到组

**现象**: API 返回 409 Conflict（已存在），但组内测试员数量为 0

**原因**: App Store Connect API 的 beta tester 关联机制有缓存/同步延迟

**解决**: 使用 ITMS fallback 脚本（内部 bulkBetaTesterAssignments 端点）
```bash
source ~/testflight-auto/ios-publish.env
export BETA_GROUP_ID="b3853bd5-a3cf-418a-9696-04a283fc4970"
export TESTER_EMAILS="a@qq.com,b@qq.com,c@qq.com"
export PYTHONPATH="$HOME/studyLog/scripts"
python3 $HOME/studyLog/scripts/assign_testflight_testers_via_itms.py
```

### 问题 5: 非团队成员无法添加为内部测试员

**现象**: `NOT_QUALIFIED_FOR_INTERNAL_GROUP`

**原因**: 只有 App Store Connect 团队成员才能加入内部测试组

**解决**:
- 方案 1: 将账号加入团队作为成员
- 方案 2: 使用外部测试组（需要 Beta App Review）

---

## 关键文件清单

### 本地项目
```
/home/ydz/projects/pai-cc/ios/
├── scripts/
│   ├── package_and_upload.sh    # 主发布脚本
│   ├── ensure_asc_app.py        # ASC App 和 Profile 配置
│   ├── configure_testflight.py   # TestFlight 配置
│   ├── check_status.py          # 状态检查
│   └── generate_app_icons.py   # 图标生成
├── PAICC/
│   ├── Sources/App/Info.plist  # 已包含 CFBundleIconName 和 ITSAppUsesNonExemptEncryption=false
│   ├── Resources/Assets.xcassets/
│   │   └── AppIcon.appiconset/  # 包含所有尺寸图标和正确格式的 Contents.json
│   └── ...
└── project.yml                  # XcodeGen 配置
```

### Mac 发布机配置
```
/Users/macstar/
├── testflight-auto/
│   ├── ios-publish.env          # 共享配置
│   └── ios-publish-paicc.env    # PAI-CC 专用配置
├── Desktop/p12/                 # 证书和密钥
│   ├── AuthKey_47SU743ZHZ.p8
│   ├── distribution.p12
│   ├── distribution-cert.pem
│   └── dist_cert_private_key.pem
├── Tools/apple-codesign/        # rcodesign 工具
│   └── apple-codesign-0.29.0-macos-universal/rcodesign
├── studyLog/scripts/            # ITMS fallback 脚本
│   └── assign_testflight_testers_via_itms.py
└── pai-cc/                      # 同步的 iOS 项目
```

---

## 一键发布命令

```bash
# 步骤 1: 同步代码到 Mac
rsync -avz --delete \
  -e "ssh -i ~/.ssh/id_ed25519" \
  /home/ydz/projects/pai-cc/ios/ \
  macstar@100.64.0.6:~/pai-cc/

# 步骤 2: 在 macstar 上执行发布
ssh -i ~/.ssh/id_ed25519 macstar@100.64.0.6 "
  source ~/testflight-auto/ios-publish-paicc.env
  cd ~/pai-cc
  export APP_BUILD_NUMBER=\$(date +%Y%m%d%H%M%S)
  ./scripts/package_and_upload.sh
"
```

---

## 后续维护

1. **版本更新**: 修改 `APP_VERSION` 环境变量
2. **Build 递增**: 脚本自动使用时间戳
3. **测试员管理**: 使用 ITMS fallback 脚本
4. **查看状态**:
```bash
source ~/testflight-auto/ios-publish-paicc.env
python3 scripts/check_status.py
```

---

## 发布检查清单

- [x] XcodeGen 生成项目成功
- [x] App Icon 包含所有尺寸 (20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024)
- [x] Contents.json 包含 filename 字段
- [x] Info.plist 包含 CFBundleIconName
- [x] Info.plist 包含 ITSAppUsesNonExemptEncryption=false
- [x] Build number 唯一
- [x] Archive 成功
- [x] 签名验证通过
- [x] IPA 打包成功
- [x] 上传到 TestFlight 成功
- [x] Build 状态 VALID
- [x] 出口合规豁免设置
- [x] 测试员添加到组

---

## 发布所需隐私信息清单

### 必需的信息

| 信息类型 | 具体内容 | 存储位置 | 用途 |
|---------|---------|----------|------|
| **App Store Connect API Key** | Key ID: `47SU743ZHZ`<br>Issuer ID: `e5e4b9b8-e882-4f89-a35b-8f7fc95edfef`<br>私钥文件: `AuthKey_47SU743ZHZ.p8` | macstar:~/Desktop/p12/<br>macstar:~/testflight-auto/ | 上传 IPA、配置 TestFlight |
| **Apple Developer Team ID** | `N3G45G5H74` | project.yml、发布脚本 | 签名、构建配置 |
| **Distribution Certificate** | 证书文件: `distribution.p12`<br>公钥: `distribution-cert.pem`<br>私钥: `dist_cert_private_key.pem`<br>序列号: `2B060ACFB63E6F8E486A15D092F34941`<br>Identity: `7DF2CDD786AE3F98BB0C14599BCFEA928A45B376`<br>密码: `EvoWit2026` | macstar:~/Desktop/p12/ | 应用签名 |
| **Signing Keychain** | 路径: `studylog-build.keychain-db`<br>密码: `studylog-build` | macstar:~/Library/Keychains/ | 签名时访问证书 |
| **Provisioning Profile** | 名称: `paicc_appstore_profile`<br>UUID: `c4306f47-a6d4-4677-a223-b2b155d1dfcd` | macstar:~/Library/MobileDevice/Provisioning Profiles/ | 打包到 IPA（API 自动创建） |
| **Apple ID** | 邮箱: `643014114@qq.com`<br>App-Specific Password | macstar 本地环境变量 | ITMS fallback 认证 |

### 信息存储位置

```
/Users/macstar/
├── testflight-auto/                    # 发布环境配置
│   ├── ios-publish.env                 # 共享配置
│   └── ios-publish-paicc.env           # PAI-CC 专用配置
├── Desktop/p12/                         # 证书和密钥（最敏感）
│   ├── AuthKey_47SU743ZHZ.p8          # API 私钥
│   ├── distribution.p12                # 分发证书 (需要密码)
│   ├── distribution-cert.pem          # 证书公钥
│   └── dist_cert_private_key.pem      # 证书私钥
├── Library/Keychains/                  # 签名 keychain
│   └── studylog-build.keychain-db      # 专用签名 keychain
├── Library/MobileDevice/
│   └── Provisioning Profiles/           # 配置文件（自动生成）
└── Tools/apple-codesign/               # rcodesign 工具
```

### 没有这些信息能否发布？

**不能。** 以下信息是发布的基础，缺少任何一个都会导致发布失败：

1. ❌ **没有 API Key** → 无法上传 IPA
2. ❌ **没有证书** → 无法签名应用
3. ❌ **没有 Keychain** → 无法访问证书
4. ❌ **没有 Profile** → IPA 无法打包
5. ❌ **没有 Team ID** → 构建配置不完整

### 如何在新机器上配置

1. 从 macstar 复制证书文件到新机器
2. 创建/导入 signing keychain
3. 创建发布环境配置文件
4. 详细步骤见: [[pai-cc-privacy-info-guide]]

### 安全规范

⚠️ **禁止**:
- 提交 .p8, .p12, .pem, .mobileprovision 到 Git
- 在文档中记录真实密码
- 分享敏感文件到不安全渠道

✅ **应该**:
- 使用 `***` 或 `[REDACTED]` 隐藏敏感值
- 通过安全渠道传递敏感文件（如加密压缩 + 单独发送密码）
- 敏感信息只存储在 Mac 本地