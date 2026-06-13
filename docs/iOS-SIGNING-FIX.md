# iOS 签名问题诊断与解决

## 🔍 问题描述

```
Warning: unable to build chain to self-signed root for signer "Apple Distribution: Shenzhen Youdezhe Technology Co., Ltd. (N3G45G5H74)"
PAICC.app: errSecInternalComponent
```

## 🏥 根本原因

Mac 上的 Apple 根证书和中间证书未正确安装或未设置为"始终信任"。

## 🔧 解决方案

### 方案 1: 在 Mac 上使用钥匙串访问（推荐）

1. **打开钥匙串访问**
   ```bash
   open -a "Keychain Access"
   ```

2. **下载并安装 Apple 根证书**
   - 访问 https://www.apple.com/certificateauthority/
   - 下载 `Apple Root CA` 和 `Apple WWDR Certificate (G3)`
   - 双击下载的 .cer 文件导入到钥匙串

3. **设置证书信任**
   - 在钥匙串访问中，找到证书
   - 右键 → 显示简介 → 信任
   - 设置为"始终信任"

4. **重新签名**
   ```bash
   cd ~/Projects/PAICC/ios
   codesign --force --deep --sign "Apple Distribution: Shenzhen Youdezhe Technology Co., Ltd. (N3G45G5H74)" PAICC.app
   codesign --verify -d PAICC.app
   ```

### 方案 2: 使用 Xcode 自动签名

1. 打开 Xcode
2. 打开项目 `~/Projects/PAICC/ios/PAICC.xcodeproj`
3. 选择项目 → Signing & Capabilities
4. 勾选 "Automatically manage signing"
5. 选择 Team: "Shenzhen Youdezhe Technology Co., Ltd. (N3G45G5H74)"
6. 编译: Product → Archive
7. 导出到 App Store Connect

### 方案 3: 使用 Transporter 上传（最简单）

1. 在 Mac 上安装 Transporter (App Store)
2. App 已编译在: `~/Projects/PAICC/ios/PAICC.app`
3. 打开 Transporter，拖入 PAICC.app
4. 上传到 App Store Connect

## 📱 TestFlight 发布步骤

### 1. 在 Xcode 中创建 Archive

```bash
cd ~/Projects/PAICC/ios

# 使用 Xcode 自动签名
xcodebuild \
  -project PAICC.xcodeproj \
  -scheme PAICC \
  -configuration Release \
  -destination generic/platform=iOS \
  -archivePath build/PAICC.xcarchive \
  clean archive
```

### 2. 导出 IPA

在 Xcode 中:
- Window → Organizer
- 选择 PAICC archive
- 点击 "Distribute App"
- 选择 "App Store Connect"
- 选择 "Upload"

### 3. 在 App Store Connect 中发布

1. 登录 https://appstoreconnect.apple.com
2. 进入 "我的 App"
3. 找到 PAI-CC
4. 在 TestFlight 标签页提交版本
5. 等待 Apple 审核（约 1-24 小时）

## 📋 当前状态

- ✅ 代码编译成功
- ❌ 代码签名失败（证书链问题）
- 📁 App 位置: `~/Projects/PAICC/ios/PAICC.app`

## 🎯 下一步操作

1. 在 Mac 上（100.64.0.6）手动打开钥匙串访问
2. 安装 Apple 根证书并设置为信任
3. 重新签名并导出 IPA
4. 上传到 TestFlight