#!/bin/bash
# 构建 recovery launcher (需先 sudo apt install -y u-boot-tools device-tree-compiler)
set -e
BASE="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE"
mkimage -f auto.its tftp-root/rtq7300t_boot_auto_upgrade_fw.img
echo "--- FIT 内容（必须有 RTQ7300T + script，且无 saveenv/mmc write）---"
dumpimage -l tftp-root/rtq7300t_boot_auto_upgrade_fw.img
grep -c "saveenv\|mmc write" boot.cmd auto.its && echo "!! 含写闪存命令，停！" && exit 1 || echo "OK: 无写闪存命令"
chmod -R a+rX tftp-root/
ls -lh tftp-root/
echo "BUILD_OK"
