#!/usr/bin/env python3
import re

with open("/Users/macstar/projects/pai-cc/PAICC.xcodeproj/project.pbxproj", "r") as f:
    content = f.read()

# Remove duplicate PBXBuildFile entries for Models.swift
# E6B3CF302C9CB26B900E5202 and 47B7EFE12903249B616F3D1B
# Remove the second occurrence (E6B3CF302C9CB26B900E5202)
content = re.sub(
    r'\n\t+E6B3CF302C9CB26B900E5202[^\n]*\n\t+7B0328A89260736B622462B0',
    '',
    content
)

# Remove duplicate PBXBuildFile entries for MainViewController.swift
# FAD6752B373FAA7535889694 and 64FE8DCE8B20927D47BE2898
# Remove the second occurrence (FAD6752B373FAA7535889694)
content = re.sub(
    r'\n\t+FAD6752B373FAA7535889694[^\n]*\n\t+ADB9E669D80E6E74E63CA3A1',
    '',
    content
)

with open("/Users/macstar/projects/pai-cc/PAICC.xcodeproj/project.pbxproj", "w") as f:
    f.write(content)

print("Done cleaning duplicates")