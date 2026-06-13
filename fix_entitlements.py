#!/usr/bin/env python3
with open("PAICC.xcodeproj/project.pbxproj", "r") as f:
    content = f.read()

# 删除 entitlements 文件引用行
content = content.replace('43496BE05F43AFF3D72CE32C /* PAICC.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = PAICC.entitlements; sourceTree = "<group>"; };', '')
content = content.replace('43496BE05F43AFF3D72CE32C /* PAICC.entitlements */,', '')

with open("PAICC.xcodeproj/project.pbxproj", "w") as f:
    f.write(content)
print("Done!")