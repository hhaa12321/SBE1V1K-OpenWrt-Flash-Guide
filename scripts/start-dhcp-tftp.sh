#!/bin/bash
# SBE1V1K (HW Rev 4.1) 恢复模式启动脚本
# 依据 OpenWrt 论坛 yangzhg #250：DHCP option 43=askey + TFTP
# 用法: sudo ~/sbe1v1k/start-dhcp-tftp.sh
set -uo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
IFACE=enp5s0
HOSTIP=172.16.252.252
TFTP_ROOT="$BASE/tftp-root"
mkdir -p "$BASE/logs"
LOG="$BASE/logs/dnsmasq-$(date +%Y%m%d-%H%M%S).log"

echo "════════════════════════════════════════════"
echo " SBE1V1K 恢复启动服务"
echo "════════════════════════════════════════════"

# ---- 前置检查 ----
[[ $EUID -eq 0 ]] || { echo "❌ 需要 root: sudo $0"; exit 1; }
ip link show "$IFACE" >/dev/null 2>&1 || { echo "❌ $IFACE 不存在"; exit 1; }

for f in rtq7300t_boot_auto_upgrade_fw.img initramfs.itb; do
  [[ -f "$TFTP_ROOT/$f" ]] || { echo "❌ 缺 $TFTP_ROOT/$f"; exit 1; }
done

# ---- 清理端口冲突 ----
echo "[1] 清理端口冲突"
systemctl stop dhcp-enp5s0 2>/dev/null && echo "    已停 dhcp-enp5s0"
if systemctl is-active --quiet tftpd-hpa 2>/dev/null; then
  systemctl stop tftpd-hpa; echo "    已停 tftpd-hpa(占 69)"
fi
ps -eo pid,cmd --no-headers | awk '/dnsmasq/ && !/awk/ {print $1}' | while read p; do kill "$p" 2>/dev/null; done
sleep 1

# ---- 配置接口 ----
echo "[2] 配置 $IFACE = $HOSTIP/16"
ip addr flush dev "$IFACE" scope global 2>/dev/null
ip addr add "$HOSTIP/16" dev "$IFACE" 2>/dev/null
ip link set "$IFACE" up
sleep 1
ip -br addr show "$IFACE"

CARRIER=$(cat /sys/class/net/$IFACE/carrier 2>/dev/null || echo 0)
if [ "$CARRIER" = "1" ]; then
  echo "    ✅ 链路已连通"
else
  echo "    ⚠️  网线未连通(no carrier) —— 请确认线接在 SBE 的 2.5G LAN 口"
fi

# ---- 192.168.1.0/24 冲突检查 ----
if ip -4 addr show | grep -q "inet 192\.168\.1\."; then
  echo "    ⚠️  有接口占用 192.168.1.0/24，可能与 initramfs 冲突:"
  ip -4 addr show | grep "inet 192\.168\.1\." | sed 's/^/       /'
fi

# ---- 防火墙 ----
echo "[3] 放行 UDP 67/68/69"
for p in 67 68 69; do
  iptables -C INPUT -i "$IFACE" -p udp --dport $p -j ACCEPT 2>/dev/null || \
    iptables -I INPUT 1 -i "$IFACE" -p udp --dport $p -j ACCEPT
done
echo "    完成"

# ---- TFTP 内容 ----
echo "[4] TFTP 内容 ($TFTP_ROOT)"
chmod -R a+rX "$TFTP_ROOT"
ls -l "$TFTP_ROOT" | tail -n +2 | sed 's/^/    /'

# ---- 启动提示 ----
cat <<'EOT'

════════════════════════════════════════════
 ★ 现在去给路由器上电
   1. 按住 Reset 不放
   2. 保持按住的同时上电
   3. 约 12 秒后松手
════════════════════════════════════════════
 期待看到两次 TFTP 传输：
   sent rtq7300t_boot_auto_upgrade_fw.img to ...
   sent initramfs.itb to ...              ← 出现这条就成功
 之后等约 60 秒，另开终端执行：
   sudo ip addr add 192.168.1.2/24 dev enp5s0
   ssh root@192.168.1.1
════════════════════════════════════════════
 Ctrl-C 停止本服务
════════════════════════════════════════════

EOT

exec dnsmasq \
  --keep-in-foreground \
  --interface="$IFACE" \
  --bind-interfaces \
  --port=0 \
  --dhcp-authoritative \
  --dhcp-broadcast \
  --dhcp-range=172.16.252.10,172.16.252.20,255.255.0.0,5m \
  --dhcp-option=43,askey \
  --dhcp-option=3 \
  --dhcp-option=6 \
  --enable-tftp \
  --tftp-root="$TFTP_ROOT" \
  --log-dhcp \
  --log-facility=- 2>&1 | stdbuf -oL -eL tee -a "$LOG"
