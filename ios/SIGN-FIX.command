#!/bin/bash
# PAI-CC iOS 签名修复脚本
# 双击此脚本或在终端运行

set -e

echo "=========================================="
echo "PAI-CC iOS 签名修复脚本"
echo "=========================================="
echo ""

# 检查是否在正确目录
if [ ! -d "PAICC.app" ]; then
    echo "❌ 错误: 请在 ~/Projects/PAICC/ios/ 目录运行此脚本"
    exit 1
fi

# 解锁钥匙串
echo "🔓 解锁钥匙串..."
security unlock-keychain -p "" ~/Library/Keychains/login.keychain-db 2>/dev/null || true

# 下载证书
echo "📥 下载 Apple 根证书..."
cd /tmp

# 检查证书是否已存在
if security find-certificate -c "Apple Root" ~/Library/Keychains/login.keychain-db 2>/dev/null | grep -q "Apple Root"; then
    echo "✅ Apple 根证书已存在"
else
    echo "⚠️  需要手动安装 Apple 根证书"
    echo "   请访问以下链接下载并双击安装:"
    echo "   https://www.apple.com/certificateauthority/"
fi

# 检查 WWDR 证书
if security find-certificate -c "WWDR" ~/Library/Keychains/login.keychain-db 2>/dev/null | grep -q "WWDR"; then
    echo "✅ WWDR 中间证书已存在"
else
    echo "⚠️  需要手动安装 WWDR 证书"
    echo "   请访问以下链接下载并双击安装:"
    echo "   https://www.apple.com/certificateauthority/"
fi

echo ""
echo "=========================================="
echo "签名步骤"
echo "=========================================="
echo ""
echo "1. 打开 Xcode"
echo "2. 打开项目: ~/Projects/PAICC/ios/PAICC.xcodeproj"
echo "3. 选择项目 → Signing & Capabilities"
echo "4. 确保 'Automatically manage signing' 已勾选"
echo "5. 选择 Team: 'Shenzhen Youdezhe Technology Co., Ltd.'"
echo "6. Product → Archive"
echo "7. 等待 Archive 完成"
echo "8. 在 Organizer 中选择 Archive，点击 'Distribute App'"
echo "9. 选择 'App Store Connect' → 'Upload'"
echo ""
echo "=========================================="
echo "或者使用 Transporter (最简单)"
echo "=========================================="
echo ""
echo "1. 在 Mac App Store 下载 Transporter"
echo "2. 打开 Transporter"
echo "3. 拖入 ~/Projects/PAICC/ios/PAICC.app"
echo "4. 点击 '交付'"
echo ""

# 列出 App
echo "📱 PAICC.app 已编译完成，位于:"
echo "   ~/Projects/PAICC/ios/PAICC.app"
ls -la ~/Projects/PAICC/ios/PAICC.app/ | head -5

echo ""
echo "✅ 脚本执行完成！"