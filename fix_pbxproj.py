#!/usr/bin/env python3
"""Fix duplicate file references - specifically for Models.swift and MainViewController.swift"""

pbxproj = "/Users/macstar/projects/pai-cc/PAICC.xcodeproj/project.pbxproj"

with open(pbxproj, 'r') as f:
    lines = f.readlines()

# IDs to remove (keeping first occurrence, removing subsequent ones)
# Models.swift: BFC47AB935DBEA5FAB0C3B25 (line 54) - keep 7B0328A89260736B622462B0 (line 47)
# MainViewController.swift: B6EA5A97CB8710F5E91ADE27 (line 52) - keep ADB9E669D80E6E74E63CA3A1 (line 51)

remove_ids = ['BFC47AB935DBEA5FAB0C3B25', 'B6EA5A97CB8710F5E91ADE27']
remove_lines = set()

for i, line in enumerate(lines, 1):
    # Check if this line contains any ID to remove
    for remove_id in remove_ids:
        if remove_id in line:
            remove_lines.add(i)
            break

print(f"Lines to remove: {sorted(remove_lines)}")

# Remove lines (in reverse order to maintain line numbers)
for line_num in sorted(remove_lines, reverse=True):
    lines.pop(line_num - 1)

with open(pbxproj, 'w') as f:
    f.writelines(lines)

print(f"Removed {len(remove_lines)} lines")