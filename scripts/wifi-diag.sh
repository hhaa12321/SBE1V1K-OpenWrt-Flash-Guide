#!/bin/sh
# SBE1V1K WiFi 诊断脚本 —— 在 OpenWrt initramfs 里直接跑
# 用法: 把本文件 scp 到路由器 /tmp/ 然后 sh /tmp/wifi-diag.sh
# 或在本机执行: ssh root@192.168.1.1 'sh -s' < wifi-diag.sh

echo "=============================================="
echo " SBE1V1K WiFi 诊断  $(date '+%F %T' 2>/dev/null)"
echo "=============================================="
echo

echo "### 0. 设备身份 ###"
echo "board_name : $(cat /tmp/sysinfo/board_name 2>/dev/null)"
if [ -f /etc/openwrt_release ]; then
    . /etc/openwrt_release 2>/dev/null
fi
echo "release    : ${DISTRIB_DESCRIPTION:-unknown}"
echo "kernel     : $(uname -r)"
echo "cmdline    : $(cat /proc/cmdline 2>/dev/null)"
echo

echo "### 1. 根文件系统(必须 tmpfs = 在内存里跑) ###"
awk '$2 == "/" { print "  /        -> " $3 " (" $1 ")" }' /proc/mounts
echo "  已挂载的 /dev/* 分区(应为空):"
awk '$1 ~ /^\/dev\// { print "    " $1 " -> " $2 }' /proc/mounts
echo

echo "### 2. radio 数量(期望 3) ###"
NPHY=$(ls -d /sys/class/ieee80211/phy* 2>/dev/null | wc -l)
echo "  /sys/class/ieee80211/phy* 数量 = $NPHY  $([ "$NPHY" -eq 3 ] && echo '✅' || echo '⚠️ 期望3')"
echo "  iw dev 接口列表:"
iw dev 2>/dev/null | grep -E "Interface|addr|type" | sed 's/^/    /'
echo

echo "### 3. ★关键: 每个 radio 的 channel / txpower ###"
echo "  (僵尸 radio 判据: 无 channel 行 或 txpower 0.00 dBm)"
FAIL=0
IFACE_SEEN=0
for p in /sys/class/ieee80211/phy*; do
    [ -e "$p" ] || continue
    phy=${p##*/}
    echo "  --- $phy ---"
    for dev in $(ls /sys/class/ieee80211/$phy/device/net/ 2>/dev/null); do
        IFACE_SEEN=$((IFACE_SEEN + 1))
        info=$(iw dev "$dev" info 2>/dev/null)
        ch=$(echo "$info" | grep -E "^[[:space:]]*channel" | head -1)
        tx=$(echo "$info" | grep -E "^[[:space:]]*txpower" | head -1)
        echo "    接口 $dev"
        if [ -z "$ch" ]; then echo "      channel : ❌ 缺失"; FAIL=1
        else echo "      $ch"; fi
        if [ -z "$tx" ]; then echo "      txpower : ❌ 缺失"; FAIL=1
        else echo "      $tx"
             echo "$tx" | grep -q "0.00 dBm" && { echo "      ⚠️ txpower 为 0，疑似僵尸"; FAIL=1; }
        fi
    done
done
if [ "$IFACE_SEEN" -eq 0 ]; then
    echo "  ⚠️ 未发现任何无线接口(无 radio)，无法评估 channel/txpower"
    FAIL=2
elif [ "$FAIL" -eq 0 ]; then
    echo "  ✅ 所有接口都有 channel/txpower（共 $IFACE_SEEN 个）"
else
    echo "  ⚠️ 存在异常接口"
fi
echo

echo "### 4. ★关键: 各 radio 的 MAC 是否互不相同 ###"
echo "  (僵尸 radio 判据: 三个接口同一个 BSSID)"
cat /sys/class/ieee80211/*/addresses 2>/dev/null | sed 's/^/    /'
ADDRS=$(cat /sys/class/ieee80211/*/addresses 2>/dev/null | tr -d ' ' | grep -v '^$')
UNIQ=$(echo "$ADDRS" | sort -u | grep -v '^$' | wc -l)
TOTAL=$(echo "$ADDRS" | grep -v '^$' | wc -l)
echo "    总数=$TOTAL 去重后=$UNIQ  $([ "$TOTAL" -eq "$UNIQ" ] && [ "$TOTAL" -gt 0 ] && echo '✅ 互不相同' || echo '❌ 有重复(MAC 未正确分配)')"
echo

echo "### 5. ★关键: 各频段能力(capability) ###"
echo "  检查 5GHz 的 HT/VHT 能力 —— 缺失说明中了 wideband bug"
echo "  (QCN9274 是 wideband radio，官方驱动错误地认为支持6GHz就不能支持5GHz)"
for p in /sys/class/ieee80211/phy*; do
    [ -e "$p" ] || continue
    phy=${p##*/}
    echo "  --- $phy ---"
    iw phy "$phy" info 2>/dev/null | awk '
      /^[[:space:]]*Band [0-9]+:/ { band=$0; sub(/^[[:space:]]*/,"",band); print "    " band }
      /HT20|HT40|VHT|HE20|EHT/ { if (band != "") print "        " $0 }
    ' | head -12
done
echo "  频段汇总(看是否 2.4/5/6 三频齐全):"
iw phy 2>/dev/null | grep -oE "Band [0-9]+: [0-9]+ MHz" | sort -u | sed 's/^/    /'
# 只有存在 radio 时才判断 5GHz，否则会误报 wideband bug
PHY_COUNT=$(ls -d /sys/class/ieee80211/phy* 2>/dev/null | wc -l)
BAND_TOTAL=$(iw phy 2>/dev/null | grep -cE "^[[:space:]]*Band [0-9]+:")
if [ "$PHY_COUNT" -eq 0 ]; then
    echo "    ⚠️ 没有 radio，无法判断频段能力（不是 wideband bug）"
    BAND5_MISSING=0
else
    BAND5=$(iw phy 2>/dev/null | grep -cE "Band [0-9]+: 5[0-9]{3} MHz")
    if [ "$BAND5" -gt 0 ]; then
        echo "    ✅ 有 5GHz 频段"
        BAND5_MISSING=0
    else
        echo "    ⚠️ 有 radio 但未见 5GHz 频段 → 可能中了 wideband bug"
        BAND5_MISSING=1
    fi
    echo "    (共检测到 $BAND_TOTAL 个频段，$PHY_COUNT 个 phy)"
fi
echo

echo "### 6. 无线配置与状态 ###"
echo "  uci wireless 中的 radio:"
uci show wireless 2>/dev/null | grep -E "wifi-device.*(band|channel|path)" | sed 's/^/    /'
echo "  wifi status 摘要:"
wifi status 2>/dev/null | grep -oE '"(up|band|channel|bssid)":\s*[^,}]*' | sed 's/^/    /' | head -30
echo

echo "### 6. ★关键: dmesg 中的 WiFi 错误 ###"
echo "  --- WMI / QMI 错误 ---"
dmesg 2>/dev/null | grep -iE "WMI CONTROL|WMI MAC1|parse tlv|qmi dma|Invalid module id" | sed 's/^/    /' || echo "    (无)"
echo "  --- memory type / calibration ---"
dmesg 2>/dev/null | grep -iE "memory type 10|board data|board\.bin|calibration|bdf" | sed 's/^/    /' || echo "    (无)"
echo "  --- regulatory ---"
dmesg 2>/dev/null | grep -iE "regulatory|reg rules|regdomain" | sed 's/^/    /' || echo "    (无)"
echo "  --- ath12k 汇总 ---"
dmesg 2>/dev/null | grep -i ath12k | tail -25 | sed 's/^/    /'
echo

echo "### 7. 硬件识别 ###"
echo "  PCI 无线设备:"
lspci 2>/dev/null | grep -iE "network|wireless" | sed 's/^/    /' || echo "    (lspci 不可用)"
echo "  温度/风扇:"
for t in /sys/class/thermal/thermal_zone*/temp; do
    [ -e "$t" ] && d=${t%/temp}; echo "    ${d##*/}: $(cat $t 2>/dev/null)"
done
echo "    PWM 风扇: $(ls /sys/class/hwmon/hwmon*/pwm* 2>/dev/null | head -3 | tr '\n' ' ')"
echo

echo "### 8. regulatory 域 ###"
iw reg get 2>/dev/null | head -15 | sed 's/^/    /'
echo

echo "=============================================="
echo " 诊断结论"
echo "=============================================="
if [ "$NPHY" -eq 0 ]; then
    echo "  ❌ 完全没有无线 phy —— WiFi 栈可能根本没起来"
    echo "  → 先查: dmesg | grep -i ath12k   以及  lsmod | grep ath12k"
    echo "  → 若驱动缺失，说明镜像未含 ath12k（走 OneNAS 镜像）"
elif [ "$NPHY" -ne 3 ]; then
    echo "  ⚠️ radio 数量是 $NPHY（期望 3）→ 中了 WMI 竞态 (Issue #24949)"
    echo "  → 建议走 OneNAS 分支 (补丁 108+110)"
elif [ "$FAIL" -eq 2 ]; then
    echo "  ⚠️ 有 phy 但无网络接口 —— 无线未配置或未 up"
    echo "  → 检查: uci show wireless / wifi status"
elif [ "$FAIL" -ne 0 ]; then
    echo "  ☠️ 疑似「僵尸 radio」(Issue #24949 评论2 描述的形态)"
    echo "     (接口存在但无 channel/txpower，或三接口同 BSSID)"
    echo "  → 建议走 OneNAS 分支 (补丁 108+110+400)"
elif [ "${BAND5_MISSING:-0}" -eq 1 ]; then
    echo "  ⚠️ 有 radio 但 5GHz 频段缺失 → 中了 wideband bug"
    echo "     (ath12k 错误认为宽频 QCN9274 支持6GHz就不能支持5GHz)"
    echo "  → 建议走 OneNAS 分支 (补丁 103+104)"
elif dmesg 2>/dev/null | grep -q "WMI CONTROL"; then
    echo "  ⚠️ 三个 radio 都在，但有 WMI 错误日志"
    echo "  → 当前可用，但重启后可能退化；建议多试几次确认稳定性"
    echo "  → 长期建议走 OneNAS 分支"
else
    echo "  ✅ WiFi 看起来完全正常 (3 个 radio，channel/txpower/MAC/频段都正常)"
    echo "  → 可以考虑永久刷入官方 snapshot"
    echo "  → 但竞态是随机的，建议再断电重启 2~3 次复测"
fi
echo
echo "要根治请编译并刷入 OneNAS 修复版（见教程第九章）"
echo "提示: 把本脚本输出整段发回来，我帮你判读。"
echo "=============================================="
