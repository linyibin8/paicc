# StudyMate iOS 发布检查清单

## 1. 前提条件

### 必需工具
- [ ] Xcode 15.0+
- [ ] XcodeGen: `brew install xcodegen`
- [ ] Fastlane: `gem install fastlane` 或 `brew install fastlane`
- [ ] CocoaPods: `sudo gem install cocoapods`

### Apple 开发者账号
- [ ] Apple Developer Program 会员资格
- [ ] App Store Connect API Key
- [ ] 开发团队 ID (Team ID)

## 2. 项目配置检查

### StudyMate 项目 (studymate-ios)
```bash
# 1. 生成 Xcode 项目
cd /home/ydz/projects/studymate-ios/StudyMate
xcodegen generate

# 2. 安装依赖 (如果有 Podfile)
cd /home/ydz/projects/studymate-ios
pod install

# 3. 打开项目
open StudyMate.xcodeproj
```

### 配置项
- [ ] Bundle ID: `com.studymate.app`
- [ ] 开发团队: 选择您的团队
- [ ] 版本号: 1.0.0
- [ ] 最低 iOS 版本: 15.0

## 3. Fastlane 配置

如果需要 Fastlane 自动化，在 `studymate-ios/fastlane/` 创建:

### Fastfile
```ruby
default_platform(:ios)

platform :ios do
  desc "Archive and upload to TestFlight"
  lane :beta do
    # 生成项目
    sh("cd StudyMate && xcodegen generate")
    
    # 打包
    build_app(
      workspace: "StudyMate.xcworkspace",
      scheme: "StudyMate",
      configuration: "Release",
      export_method: "app-store"
    )
    
    # 上传
    upload_to_testflight
  end
end
```

## 4. GitHub Actions CI/CD (可选)

创建 `.github/workflows/ios.yml`:
```yaml
name: iOS Build

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-latest
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup Xcode
      uses: maxim-lobanov/setup-xcode@v1
      with:
        xcode-version: '15.0'
    
    - name: Install dependencies
      run: |
        brew install xcodegen
        cd StudyMate && xcodegen generate
        cd .. && pod install
    
    - name: Build
      run: |
        xcodebuild -workspace StudyMate.xcworkspace \
          -scheme StudyMate \
          -configuration Release \
          -destination 'generic/platform=iOS' \
          build
```

## 5. 证书和描述文件

### 创建 App Store Connect API Key
1. 登录 [App Store Connect](https://appstoreconnect.apple.com)
2. 进入 "用户和访问" -> "密钥"
3. 创建 App Store Connect API Key
4. 下载 `.p8` 文件并保存到 `fastlane/api_key.p8`

### 配置环境变量
```bash
# .env 文件
APP_STORE_CONNECT_KEY_ID=XXXXXXXX
APP_STORE_CONNECT_ISSUER_ID=XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
APP_STORE_CONNECT_API_KEY_PATH=./fastlane/api_key.p8
APPLE_TEAM_ID=XXXXXXXXXX
```

## 6. 发布步骤

### 手动发布
```bash
# 1. 更新版本号
# 编辑 project.yml 中的 MARKETING_VERSION

# 2. 生成项目
cd StudyMate
xcodegen generate

# 3. 使用 Xcode 打开项目并归档
open StudyMate.xcodeproj
# Product > Archive

# 4. 导出 IPA
# Organizer > 选择归档 > Distribute App > TestFlight
```

### 使用 Fastlane
```bash
cd /home/ydz/projects/studymate-ios
export APP_STORE_CONNECT_KEY_ID="XXXXXXXX"
export APP_STORE_CONNECT_ISSUER_ID="XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
export APP_STORE_CONNECT_API_KEY_PATH="./fastlane/api_key.p8"
export APPLE_TEAM_ID="XXXXXXXXXX"
export APP_BUNDLE_ID="com.studymate.app"
export APP_NAME="StudyMate"

fastlane beta
```

## 7. 常见问题

### 问题: 签名失败
解决: 检查 Development Team 是否正确配置

### 问题: CocoaPods 依赖缺失
解决: 运行 `pod install` 确保 Podfile 存在

### 问题: XcodeGen 生成失败
解决: 确保 project.yml 语法正确，运行 `xcodegen generate --verbose`