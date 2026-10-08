# 手把手教你刷 SBE1V1K（OpenWrt 小白版）

> 不用拆机、不用串口、不用第二台路由器。一根网线 + 一台 Linux 电脑，照着抄命令就行。
> 全程约 30 分钟，其中需要你动手的大概 5 分钟，其余是下载和等待。

**这篇教程适合谁**：第一次刷机、看不懂英文论坛、只想要"照着做就能成"的人。
每一步都写了：**做什么 → 怎么验证做对了 → 失败了怎么办**。

## 目录

| 章节 | 内容 | 大概耗时 |
|---|---|---|
| 〇 | 先认识这台机器 | 3 分钟 |
| 一 | 刷机前必读（原理 + 风险 + 名词） | 5 分钟 |
| 二 | 准备清单 | 10 分钟（含下载） |
| 三 | 第一步：让路由器从网线启动 | 10 分钟 |
| 四 | 第二步：写进 eMMC（变成真正的路由器） | 10 分钟 |
| 五 | 第三步：配置上网 | 10 分钟 |
| 六 | 踩坑速查表（26 条） | 出问题再查 |
| 七 | 刷坏了怎么救 | 备用 |
| 八 | 常见问题 FAQ | 出问题再查 |
| 九 | 进阶：让 WiFi 更稳 | 选做 |
| 附录 A | 脚本全文 | 复制用 |
| 附录 B | 固件校验值 / 参考资料 | — |

---

## 〇、先认识这台机器

**SBE1V1K** 是美国 Spectrum 定制的 WiFi 7 路由器（代工厂 Askey，别名 RTQ7300T，硬件版本 Rev 4.1）。

| 项目 | 配置 |
|---|---|
| 处理器 | 高通 IPQ9574，四核 A73 |
| 内存 / 存储 | 2 GB / 8 GB eMMC |
| 有线口 | 1 个 10G（WAN）、1 个 2.5G（LAN1）、2 个 1G（LAN2/3） |
| 无线 | 三颗 QCN9274，2.4G + 5G + 6G（WiFi 7） |
| 电源 | 12V / 3.5A，5525 圆口 |
| 串口 | 有（ttyMSM0，115200），但**本教程用不到**，官方也没给针脚定义 |

**为什么要刷它**：原厂固件被运营商锁死，只能当 Spectrum 的定制机用；刷成 OpenWrt 后就是一台完全由你控制的路由器。

**刷完能干什么**：自己设 WiFi 名字密码、自己拨号、装插件（科学上网 / 广告过滤 / DDNS…）、当主路由或者旁路由。

---

## 一、刷机前必读

### 1.1 这个方法为什么安全（先看懂再动手）

原厂固件里藏了一个**恢复模式**：开机时如果按住 Reset，它会去找一台 DHCP 服务器，
并且检查服务器给的 **option 43** 是不是字符串 `askey`。是的话，它就从 TFTP 服务器下载两个文件：

1. `rtq7300t_boot_auto_upgrade_fw.img` —— 一个 859 字节的"启动脚本"（里面只有三行：设 IP、下载、启动）
2. `initramfs.itb` —— OpenWrt 的**内存版系统**

关键点：**整个过程只往内存里写，不碰 eMMC**。所以第一次尝试**零风险**，试多少次都不会变砖，
路由器一断电重启就回到原厂系统。

### 1.2 两个阶段

| 阶段 | 干什么 | 风险 |
|---|---|---|
| 第一阶段：RAM 启动 | 把 OpenWrt 跑在内存里，先看看好不好用 | **零风险**，断电就还原 |
| 第二阶段：写 eMMC | 把系统写进存储，变成开机即用的路由器 | 有风险，但先备份 + 保留 TFTP 兜底就能救 |

建议：**先玩第一阶段**，确认能用、WiFi 正常，再做第二阶段。

### 1.3 名词解释（看不懂就回来查）

| 名词 | 白话解释 |
|---|---|
| TFTP | 一种极简的文件传输协议，路由器在恢复模式里只会用它下载固件 |
| DHCP option 43 | DHCP 服务器发给设备的"附加信息"字段；原厂用它识别"这是自己人" |
| initramfs | 一个跑在内存里的迷你 Linux 系统，用来做安装 / 救援 |
| eMMC | 路由器主板上的 8 GB 存储芯片，相当于路由器的"硬盘" |
| U-Boot | 路由器开机后跑的第一段程序，负责找系统并启动它 |
| U-Boot 环境变量 | U-Boot 的配置（从哪启动、根分区在哪），存在 eMMC 里 |
| sysupgrade | OpenWrt 自带的"官方刷机命令" |
| LuCI | OpenWrt 的网页管理界面（就是路由器后台） |
| PPPoE | 宽带拨号协议（光猫改桥接时用） |

### 1.4 三条铁律

1. **网线插 LAN1（2.5G 那个口），不是 WAN 口** —— 新手翻车第一名，插错了完全没反应。
2. **先起服务，再给路由器上电** —— 顺序反了就抓不到。
3. **第二阶段写 eMMC 前，先备份 U-Boot 环境变量** —— 一行命令，能救命。

---

## 二、准备清单

### 2.1 硬件

| 东西 | 要求 | 备注 |
|---|---|---|
| SBE1V1K 路由器 | 硬件 Rev 4.1 | 原厂固件不用动 |
| 电源 | 12V / 3.5A，5525 圆口 | 原装即可 |
| 网线 | 一根 | 路由器 LAN1 ↔ 电脑有线网口 |
| 电脑 | **Linux**（Ubuntu 22.04+ 最省事） | 见下方"Windows 用户怎么办" |

> **Windows 用户怎么办？**
> 本教程需要电脑在物理网卡上跑 DHCP + TFTP 服务，WSL2 里做不了（网卡不直通）。
> 最简单的办法：用 Ubuntu 启动 U 盘启动电脑（试用模式，不用装系统），或者找另一台 Linux 机器 / 树莓派。
> **macOS 也可以**（论坛原帖就是 Mac 写的）：命令里 `ip addr` 换成 `ifconfig`、`apt` 换成 `brew`，脚本稍作修改即可。

### 2.2 电脑上装三个软件

```bash
sudo apt update
sudo apt install -y dnsmasq u-boot-tools device-tree-compiler
```

| 软件 | 干嘛的 |
|---|---|
| dnsmasq | 同时当 DHCP 服务器 + TFTP 服务器 |
| u-boot-tools | 里面有 `mkimage`，用来生成那个 859 字节的启动脚本 |
| device-tree-compiler | 编译 DTB 用（只在第九章"进阶"需要） |

### 2.3 下载固件（二选一）

**选择 A：官方 snapshot**（省事，WiFi 偶尔抽风）

打开 <https://downloads.openwrt.org/snapshots/targets/qualcommbe/ipq95xx/>，下载这两个文件
（名字里的日期 / 版本号会变，认关键字）：

- `openwrt-qualcommbe-ipq95xx-askey_sbe1v1k-initramfs-uImage.itb` ← RAM 启动用
- `openwrt-qualcommbe-ipq95xx-askey_sbe1v1k-squashfs-sysupgrade.bin` ← 写 eMMC 用

同一个目录里还有 `sha256sums`，下完**必须校验**：

```bash
grep -F 'askey_sbe1v1k-initramfs-uImage.itb' sha256sums | sha256sum -c -
# 输出 ...: OK 才算下载完整
```

**snapshot 每天在变**，别人教程里的哈希和你下载到的对不上是正常的，以你下载时的 `sha256sums` 为准。

**选择 B：OneNAS 编译版**（WiFi 稳，但要自己编译 30~60 分钟）

见第九章。新手建议先用官方版把流程跑通。

### 2.4 目录准备

把脚本和固件放成这个结构（本教程压缩包 / GitHub 仓库就是这个结构）：

```
sbe1v1k/
├── start-dhcp-tftp.sh          ← 一键起 DHCP + TFTP
├── wifi-diag.sh                ← WiFi 体检
├── build-launcher.sh           ← 重新生成启动器
├── boot.cmd / auto.its         ← 启动器的原料
└── tftp-root/
    ├── rtq7300t_boot_auto_upgrade_fw.img   ← 859 字节启动器（已提供）
    └── initramfs.itb                       ← 把下载的 .itb 改名成这个
```

```bash
mv openwrt-qualcommbe-ipq95xx-askey_sbe1v1k-initramfs-uImage.itb tftp-root/initramfs.itb
ls -lh tftp-root/
```

> ⚠️ 两个文件的名字**必须一模一样**，不能改成别的。
> `initramfs.itb` 还必须**小于 31 MiB**（原厂 U-Boot 的限制）。

---

## 三、第一步：让路由器从网线启动（RAM 启动）

> 这一步结束，你会得到一个"跑在内存里的 OpenWrt"。断电就没了，所以随便折腾。

### 3.0 找到你的网卡名（30 秒）

```bash
ip -br link
```

输出里形如 `enp5s0 UP ...` 的那个就是你的有线网卡（也可能是 `enp3s0` / `eno1` / `eth0`，每台机器不同）。
记下来，下面凡是出现 `enp5s0` 的地方都换成它。

### 3.1 改脚本里的网卡名

打开 `start-dhcp-tftp.sh`，把开头的这行改成你的网卡名：

```bash
IFACE=enp5s0      # ← 改成你的
```

### 3.2 起服务（终端会一直占着，别关）

```bash
sudo ./start-dhcp-tftp.sh
```

脚本会自动：停掉抢端口的服务 → 给网卡配 `172.16.252.252/16` → 起 dnsmasq（DHCP + option 43 + TFTP）。

看到最后打印的"★ 现在去给路由器上电"就对了。

> - 报 `❌ 缺 tftp-root/xxx`：2.4 步的文件没放好，回去检查。
> - 报 `❌ enp5s0 不存在`：网卡名没改对，回 3.0。

### 3.3 接线 + 上电（关键步骤，慢一点）

1. 网线一头插路由器 **LAN1**（2.5G 口，一般印着 `2.5G` 或 `LAN1`），另一头插电脑有线口；
2. 路由器**拔掉电源**，等 5 秒；
3. **用牙签 / 笔尖按住 Reset 不松手**；
4. 保持按住，**插上电源**；
5. 心里数 12 秒，**松手**。

> 松手时机不用太精确，10~15 秒都行。关键是"按住 → 上电 → 等十几秒 → 松手"这个顺序。

### 3.4 看日志：怎么知道成功了

回到起服务的那个终端，正常会依次出现：

```
DHCPDISCOVER(enp5s0) ...
DHCPOFFER(enp5s0) 172.16.252.10 ...
DHCPREQUEST(enp5s0) 172.16.252.10 ...
DHCPACK(enp5s0) 172.16.252.10 ...
sent rtq7300t_boot_auto_upgrade_fw.img to 172.16.252.10
sent initramfs.itb to 172.16.252.10          ← 看到这条就成功了
```

**判据：出现 `sent initramfs.itb` = 成功**。之后等大约 60 秒，让它把系统跑起来。

### 3.5 连上去看看

**另开一个终端**（起服务的终端不要关）：

```bash
sudo ip addr add 192.168.1.2/24 dev enp5s0     # 换成你的网卡名
ping -c 3 192.168.1.1                          # 通 = 系统起来了
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.1.1
```

密码：**直接回车**（官方 initramfs 默认没有密码）。

进去以后执行这三行，确认"确实只是跑在内存里"：

```bash
cat /tmp/sysinfo/board_name        # 应该输出 askey,sbe1v1k
awk '$2=="/"{print}' /proc/mounts  # 根是 tmpfs
awk '$1 ~ /^\/dev\//' /proc/mounts # 没有任何输出 = eMMC 没被挂载
```

再顺手给 WiFi 做个体检（可选，10 秒）：

```bash
ssh root@192.168.1.1 'sh -s' < ./wifi-diag.sh
```

> 官方 snapshot 的三颗 WiFi 有"随机掉频"的毛病（上游已知 bug），
> 体检结果异常就断电重启 2~3 次再测；要根治就编译 OneNAS 版（第九章）。

### 3.6 这一步失败了怎么办

| 现象 | 原因 | 怎么做 |
|---|---|---|
| 日志里连 DHCP 都没有 | 网线插错口（插了 WAN） | 换到 LAN1（2.5G）重来 |
| 有 DHCP 但没 TFTP | option 43 没生效 / 服务没起来 | 确认脚本输出里有 `--dhcp-option=43,askey`；`pgrep -a dnsmasq` 看有没有旧进程 |
| 只传了第一个文件 | `tftp-root/initramfs.itb` 不存在或名字不对 | `ls tftp-root/` 检查 |
| 传完没反应 / ping 不通 | 还在启动 | 再等 60 秒；或断电重来一次 |
| 电脑上有别的网卡占着 192.168.1.x | 网段冲突 | `ip -4 addr` 看一眼，把冲突的临时关掉 |

---

## 四、第二步：写进 eMMC（变成真正的路由器）

> ⚠️ 这一步开始**会真正写入存储**。按顺序做，别跳步。全程保持供电，别拔线。

### 4.1 先备份（30 秒，别省）

```bash
SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.1.1"
mkdir -p backup
$SSH 'fw_printenv'          | tee backup/uboot-env-original.txt   # 最重要
$SSH 'cat /proc/partitions' | tee backup/partitions.txt
```

`uboot-env-original.txt` 里存着路由器原来的启动配置，后面万一搞坏了，照着它改回来就能救。

### 4.2 设置启动参数（3 条命令）

```bash
# 先看看现在的值
$SSH 'fw_printenv | grep -E "^(bootargs|bootcmd|do_boot)="'

# 1) 告诉内核：根分区在 eMMC 的 p27，WiFi 需要 256MB CMA
$SSH "fw_setenv bootargs 'console=ttyMSM0,115200n8 rootwait root=/dev/mmcblk0p27 cma=256M'"

# 2) 从 eMMC 读内核并启动（0x14022 是 p25 起始扇区，0x3800 是长度）
$SSH "fw_setenv do_boot  'mmc read 0x44000000 0x00014022 0x3800; bootm 0x44000000'"

# 3) 开机流程：等 3 秒 → 从 eMMC 启动；失败就用 TFTP 兜底
$SSH "fw_setenv bootcmd  'sleep 3; run do_boot; echo EMMC-FAILED; setenv ipaddr 172.16.252.100; setenv serverip 172.16.252.252; tftpboot 0x80000000 initramfs.itb; bootm 0x80000000'"
```

三条都做完后核对一遍：

```bash
$SSH 'fw_printenv bootargs bootcmd do_boot'
```

> - `sleep 3` **不能省**：少了它，U-Boot 读 eMMC 偶尔会失败，然后**悄悄**回落到 TFTP 启动，
>   你以为刷成功了，其实每次开机都在走网线（现象：拔掉网线就起不来）。
> - `bootcmd` 最后那段 TFTP 是**保险绳**：万一 eMMC 起不来，还能自动回到内存系统救砖。
> - 原厂本来就有 `do_boot`，值不一样才需要改。

### 4.3 刷写（两条路，选一条）

#### 路线 A：`sysupgrade`（官方镜像推荐，最省事）

```bash
# 传到路由器（/tmp 是内存盘，重启就没了，所以要现传现刷）
cat openwrt-qualcommbe-ipq95xx-askey_sbe1v1k-squashfs-sysupgrade.bin | timeout 300 $SSH 'cat > /tmp/su.bin'

# 校验：两边哈希要一致
sha256sum openwrt-qualcommbe-ipq95xx-askey_sbe1v1k-squashfs-sysupgrade.bin
$SSH 'sha256sum /tmp/su.bin'

# 先干跑检查，再真刷
$SSH 'sysupgrade -T /tmp/su.bin'
$SSH 'sysupgrade -n -v /tmp/su.bin'      # -n = 不保留旧配置
```

如果报 `Image check failed` / `Image metadata not present`，走路线 B，或者加 `-F` 再试。

#### 路线 B：手工 `dd`（OneNAS 镜像，或 sysupgrade 不认时）

```bash
# ① 在电脑上从 sysupgrade.bin（其实是个 tar 包）里抠出 kernel 和 rootfs
python3 - <<'PY'
import tarfile
src='openwrt-qualcommbe-ipq95xx-askey_sbe1v1k-squashfs-sysupgrade.bin'
tf=tarfile.open(src,'r')
for m in tf.getmembers():
    if m.name.endswith('/kernel'): open('/tmp/kernel.fit','wb').write(tf.extractfile(m).read())
    if m.name.endswith('/root'):   open('/tmp/root.sq','wb').write(tf.extractfile(m).read())
PY
ls -l /tmp/kernel.fit /tmp/root.sq
dumpimage -l /tmp/kernel.fit | head -5     # 确认 Load Address 是 0x42200000

# ② 传进路由器 + 校验
cat /tmp/kernel.fit | timeout 300 $SSH 'cat > /tmp/f.fit'
cat /tmp/root.sq    | timeout 300 $SSH 'cat > /tmp/f.sq'
$SSH 'sha256sum /tmp/f.fit /tmp/f.sq'      # 与电脑上算出来的对比，一致才继续

# ③ 写入（p25 = 内核分区，p27 = 根文件系统分区）
$SSH 'dd if=/tmp/f.fit of=/dev/mmcblk0p25 bs=512 conv=fsync; sync'
$SSH 'dd if=/tmp/f.sq  of=/dev/mmcblk0p27 bs=512 conv=fsync; sync'

# ④ 读回来验证内核头（FIT 魔数应该是 d00dfeed）
$SSH 'dd if=/dev/mmcblk0p25 bs=4 count=1 2>/dev/null | hexdump -e "1/1 \"%02x\""'
```

> 写入的瞬间 SSH 会断（因为我们正在覆盖运行中的系统），这是**正常现象**，不是失败。
> 不要试图 `reboot`，直接**拔电源**。

### 4.4 验收

**拔电源 → 等 5 秒 → 插电**（这次不用按 Reset），等 **150~200 秒**（三颗 WiFi 初始化很慢），然后：

```bash
ping -c 3 192.168.1.1
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.1.1

awk '$2=="/"{print}' /proc/mounts     # 关键：必须是 overlayfs:/overlay
grep mmcblk /proc/mounts              # 应该看到 /dev/mmcblk0p29 /overlay f2fs
```

| 你看到的 | 含义 |
|---|---|
| `/` 是 `overlayfs:/overlay` | ✅ 真正写进 eMMC 了 |
| `/` 是 `overlayfs:/tmp/root` | ❌ 其实又回落到 TFTP 了（假成功），见踩坑 ⑪ |
| 完全连不上、十几秒一重启 | 内核挂不上根分区 → 看门狗循环，见踩坑 ⑫ |

---

## 五、第三步：配置上网

```bash
# ① 管理地址（当主路由就用 192.168.1.1）
uci set network.lan.ipaddr='192.168.1.1'

# ② 拨号上网（光猫改桥接时用；光猫自己拨号则跳过，WAN 保持 DHCP）
uci set network.wan.proto='pppoe'
uci set network.wan.username='<你的宽带账号>'
uci set network.wan.password='<你的宽带密码>'

# ③ WiFi：radio1 = 5G，radio2 = 2.4G，radio0 = 6G（6G 暂时用不了，关掉）
uci set wireless.radio0.disabled='1'
uci set wireless.default_radio1.ssid='<你的5G名字>'
uci set wireless.default_radio1.encryption='psk2'
uci set wireless.default_radio1.key='<你的WiFi密码>'
uci set wireless.default_radio2.ssid='<你的2.4G名字>'
uci set wireless.default_radio2.encryption='psk2'
uci set wireless.default_radio2.key='<你的WiFi密码>'

uci commit
/etc/init.d/network restart
wifi reload
```

装网页管理界面（LuCI）：

```bash
apk update && apk add luci luci-ssl
# 然后浏览器打开 http://192.168.1.1
```

> 新系统默认**不带**网页界面，也**默认关闭 WiFi**，别以为刷坏了。

如果路由器自己还上不了网（比如要装插件），先在电脑上临时给它共享网络：

```bash
# 电脑这边（wlp4s0 换成你电脑上网用的网卡）
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -o wlp4s0 -j MASQUERADE

# 路由器这边
ip route add default via 192.168.1.2
echo "nameserver 223.5.5.5" > /etc/resolv.conf
```

偶尔会遇到"连上 WiFi 但拿不到 IP"，写个 DHCP 兜底：

```bash
cat > /etc/dnsmasq.conf <<'EOF'
interface=br-lan
dhcp-range=192.168.1.100,192.168.1.200,255.255.255.0,12h
dhcp-option=3,192.168.1.1
dhcp-option=6,192.168.1.1
EOF
/etc/init.d/dnsmasq restart
```

---

## 六、踩坑速查表

> 按"症状"查。每条都写清了原因和做法。

| # | 症状 | 原因 | 怎么做 |
|---|---|---|---|
| ① | 完全没有 DHCP 日志 | 网线插在 10G WAN 口 | 插 **LAN1（2.5G）** |
| ② | 设备拿到 IP 但不请求 TFTP | option 43 没配或写成数字 | dnsmasq 必须 `--dhcp-option=43,askey` |
| ③ | dnsmasq 起不来 | tftpd-hpa 占 69、systemd-resolved 占 53、旧 dnsmasq 没退 | `sudo systemctl stop tftpd-hpa`；`pgrep -a dnsmasq` 后杀掉；脚本已自动处理 |
| ④ | 只传了第一个文件就停 | `tftp-root/initramfs.itb` 缺失或改名 | 两个文件都要在，名字不能变 |
| ⑤ | 传完不启动 | initramfs 大于 31 MiB | 换小于 31 MiB 的镜像 |
| ⑥ | eMMC 起不来 / 无限重启 | `KERNEL_LOADADDR` 不对（`0x42080000` 非对齐、`0x41000000` 会重启） | 编译时用 `0x42200000` |
| ⑦ | 编译 0 错误，但一个 WiFi 都没有 | `CONFIG_DRIVER_11BE_SUPPORT` 默认是 n | `.config` 里显式 `=y`，并确认 ath12k 相关 kmod 都进了包 |
| ⑧ | 10G 口不通 / 风扇不转 | 固件里缺对应 kmod | 补 `kmod-phy-realtek` 等；编完核对 manifest，`DEVICE_PACKAGES` 写了≠打包 |
| ⑨ | 三频随机掉 / txpower 0 / 三个接口同一个 BSSID | 官方镜像 ath12k 探测竞态（上游 Issue #24949） | 断电重启 2~3 次复测；要稳就编 OneNAS 版 |
| ⑩ | 刷完重启还是原厂系统 | sysupgrade 只写了 rootfs，没写 kernel | 看 p25 头是不是 `d00dfeed`；没写就用手工 `dd` |
| ⑪ | `/` 是 `overlayfs:/tmp/root`（假成功） | `bootcmd` 少了 `sleep 3`，eMMC 读失败后静默回落 TFTP | 补上 `sleep 3`；只认 `overlayfs:/overlay` |
| ⑫ | `bootm` 成功但设备十几秒一重启、连不上 | 内核挂不上根分区 → 看门狗循环，TFTP 兜底不触发 | 物理 Reset 回 TFTP，检查 DTB / rootfs 是否匹配 |
| ⑬ | `Image metadata not present` | 非官方镜像没有 metadata | `sysupgrade -F` |
| ⑭ | `ubus ... Connection failed` + `exit=246` | stage2 关掉 shell 会话的副作用，不代表写失败 | 看设备是否真的重启；以 p25/p27 实际内容为准 |
| ⑮ | 传进去的 `/tmp/su.bin` 不见了 | `/tmp` 是内存盘，重启就清空 | 同一次 RAM 启动内传完就刷；刷前重新校验 |
| ⑯ | `dd` 后 SSH 立刻断，`reboot` 无效 | 覆写了正在运行的 p27 | 只在内存系统里写；失联后**物理断电** |
| ⑰ | 重新挂载看 p27，像没写进去 | page cache 假象 | `echo 3 > /proc/sys/vm/drop_caches` 再看 |
| ⑱ | 上电 60 秒连不上以为失败 | 三颗 WiFi 初始化慢 | 等 **150~200 秒** |
| ⑲ | 想知道"到底有没有从 eMMC 启动过" | p29 头全零 = 从未启动过 | `dd if=/dev/mmcblk0p29 bs=4 count=1 2>/dev/null \| hexdump` |
| ⑳ | SSH 报 `Connection refused`（不是超时） | 设备在，但没跑 SSH（多半回到原厂固件，原厂只开 80） | 浏览器开 `http://192.168.1.1` 确认；再走 Reset+TFTP |
| ㉑ | 6 GHz 连不上 | 驱动拿不到 6G 信道（已知问题） | `radio0.disabled=1`，用 2.4G + 5G |
| ㉒ | 没有 LuCI / 客户端拿不到 IP | 新系统不带 LuCI，有时不生成 DHCP 池 | `apk add luci`；写 `/etc/dnsmasq.conf` 兜底 |
| ㉓ | 下载官方镜像超时 | 直连慢 | 挂代理下载，下完核对 sha256 |
| ㉔ | 刷过原厂固件后 TFTP 恢复失效 | 原厂固件会清空 U-Boot 环境变量 | 非必要别刷原厂；刷之前先备份 `fw_printenv` |
| ㉕ | 改了 DTS 但行为没变 | `make target/linux/compile` 不重建 DTB | 手工 `cpp` + `dtc` 重建（第九章） |
| ㉖ | 内核 bootargs 被 DTB 覆盖 | DTS `chosen` 里的 `bootargs` 会整体替换 U-Boot 的 bootargs | **整行删掉**；改写成"完整 cmdline"也没用（实测） |

---

## 七、刷坏了怎么救

**先别慌**：只要 U-Boot 里的 TFTP 兜底还在，这机器基本救得回来。

1. **最常用**：断电 → 按住 Reset → 上电 → 12 秒松手 → 重做第三章（TFTP 启动）。
   只要还能进内存系统，就能重新写 eMMC。
2. **有串口**（进阶）：`ttyMSM0`，115200 8N1，开机 3 秒内按 Ctrl+C 进 U-Boot 命令行，
   可以手动 `setenv` / `run do_boot` / `tftpboot`。
3. **进不去又没串口**：确认 option 43 是 `askey`、两个 TFTP 文件都在、插的是 LAN1；
   老的 warehouse exploit（`cgi-bin/warehouse_api` 投毒）在 FW 1.5.3 上已被厂商修掉，别指望。

> ⚠️ **不要刷原厂固件**：它会把 U-Boot 环境变量清空，TFTP 兜底一起消失，那才是真变砖。

---

## 八、常见问题 FAQ

**Q1：会不会变砖？**
第一阶段（RAM 启动）零风险，断电就还原。第二阶段有风险，但先备份 + 保留 TFTP 兜底，基本都能救回来。

**Q2：能刷回原厂吗？**
能，但**不建议**：刷原厂会清空 U-Boot 环境变量，TFTP 恢复能力一起没了。真要刷，先把 `fw_printenv` 输出存好。

**Q3：Windows 电脑行不行？**
不行（WSL2 的网卡不直通）。用 Ubuntu 启动 U 盘试用模式，或者找台 Linux / macOS。

**Q4：为什么刷完没有网页后台？**
OpenWrt snapshot 默认不带 LuCI，`apk add luci luci-ssl` 装一下。

**Q5：为什么 WiFi 默认是关的？**
OpenWrt 默认不启用无线，需要自己用 `uci set` 配（第五章）。

**Q6：为什么 6GHz 用不了？**
驱动拿不到 6G 信道（已知问题），先关掉 radio0，用 2.4G + 5G。

**Q7：三颗 WiFi 老是掉一颗？**
官方镜像的驱动竞态（上游 Issue #24949），重启几次能好，根治要编 OneNAS 版（第九章）。

**Q8：刷完还要保留那台 DHCP / TFTP 服务吗？**
不用，Ctrl+C 停掉即可。以后升级用 LuCI 或 `sysupgrade` 都行。

**Q9：怎么升级新固件？**
下新的 sysupgrade 镜像，LuCI 里"系统 → 备份 / 刷写固件"上传即可，或者 `sysupgrade -n 新文件.bin`。

**Q10：一定要用 2.5G 口吗？**
必须。10G WAN 口在恢复模式里不工作，1G 口（LAN2/3）没验证过。

---

## 九、进阶：让 WiFi 更稳（编译 OneNAS 版）

官方 snapshot 的三颗 QCN9274 有探测顺序竞态，三频会随机掉。OneNAS 树打了 15 个补丁修掉了。

```bash
git clone https://github.com/OneNAS-space/Askey_Spectrum_SBE1V1K
cd Askey_Spectrum_SBE1V1K
./scripts/feeds update -a && ./scripts/feeds install -a
make menuconfig        # Target: Qualcommbe / ipq95xx，Profile: askey_sbe1v1k
make -j$(nproc)
```

**四个必须确认的点**（不改就是白编）：

| # | 位置 | 要改成 |
|---|---|---|
| ① | `target/linux/qualcommbe/image/ipq95xx.mk` | `KERNEL_LOADADDR := 0x42200000`（Rev 4.1 只能用这个） |
| ② | `.config` | `CONFIG_DRIVER_11BE_SUPPORT=y`，以及 kmod-ath12k / ath12k-firmware-qcn9274 / mac80211 / qrtr-mhi / qcom-qmi-helpers 等一并 `=y`（默认 n：编译 0 错误但没 WiFi） |
| ③ | `.config` | `CONFIG_CMA=y`（不开：WiFi 报 `qmi dma allocation failed`） |
| ④ | `target/linux/qualcommbe/dts/ipq9570-sbe1v1k.dts` | **整行删掉** `bootargs = "cma=256M";`（`chosen` 里的这行会覆盖 U-Boot 的 bootargs，导致 eMMC 起不来）；`reserved-memory` 里的 `linux,cma` 保留 |

产物在 `bin/targets/qualcommbe/ipq95xx/`：`...-initramfs-uImage.itb` 改名 `initramfs.itb` 放 `tftp-root/`，
`...-squashfs-sysupgrade.bin` 用来写 eMMC（第四章路线 B）。

**⚠️ 注意：`make target/linux/compile` 不会重建 DTB**，改了 DTS 必须手工重建：

```bash
LINUX=build_dir/target-aarch64_cortex-a53_musl/linux-qualcommbe_ipq95xx/linux-6.18.52
cpp -nostdinc -I $LINUX/arch/arm64/boot/dts -I $LINUX/arch/arm64/boot/dts/qcom \
    -I target/linux/qualcommbe/dts -I $LINUX/include -undef -D__DTS__ \
    -x assembler-with-cpp target/linux/qualcommbe/dts/ipq9570-sbe1v1k.dts -o /tmp/sbe.dts
dtc -I dts -O dtb /tmp/sbe.dts -o /tmp/sbe.dtb
```

---

## 附录 A：脚本全文

> 下面 5 个脚本可以直接复制出来用。用法见第三章、第六章。

### 1. start-dhcp-tftp.sh —— 起 DHCP + TFTP 服务（本教程第三章）

```bash
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
```

### 2. wifi-diag.sh —— 刷完给 WiFi 做体检（第三章 3.5 / 第六章 ⑨）

```bash
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
```

### 3. build-launcher.sh —— 重新构建 TFTP 启动器（可选）

```bash
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
```

### 4. boot.cmd —— 启动器里的 U-Boot 命令（3 行）

```text
setenv serverip 172.16.252.252
tftpboot 0x80000000 initramfs.itb
bootm 0x80000000
```

### 5. auto.its —— 启动器 FIT 描述文件

```text
/dts-v1/;

/ {
	description = "SBE1V1K recovery launcher";
	#address-cells = <1>;

	images {
		RTQ7300T {
			description = "model marker";
			data = [00];
			type = "firmware";
			arch = "arm";
			compression = "none";
			hash-1 {
				algo = "sha256";
			};
		};
		script {
			description = "boot OpenWrt initramfs";
			data = /incbin/("boot.cmd");
			type = "script";
			arch = "arm";
			compression = "none";
			hash-1 {
				algo = "sha256";
			};
		};
	};
};
```

---

## 附录 B：固件校验值 / 参考资料

**本教程实际用过的版本**（snapshot 会滚动更新，对不上很正常，以你下载时的 `sha256sums` 为准）：

| 镜像 | 大小 (B) | sha256 |
|---|---|---|
| 官方 initramfs | 19,085,504 | `e330cfb9424bd15bbba140d05367f6b0272a62f2e22eb5351659ce27a6cc4dd8` |
| 官方 sysupgrade | 16,978,189 | `725bf9c9a37aca150ccf95da7e4a7a565722b85bc624850b4675fe0d9936b298` |
| OneNAS initramfs | 15,848,148 | `e833d46159e74f694b48677e709c89d8f3985c1b901ca4ff8c315d2d4537edda` |
| OneNAS sysupgrade | 16,118,022 | `a496f014b70e45a1bc2e001daea3724017d14fd5f0bb5da5172e78d20ed9e57a` |

**参考资料**

- 方法出处（英文，Mac 版）：OpenWrt 论坛 [Spectrum SBE1V1K / IPQ9574 OpenWrt support #250](https://forum.openwrt.org/t/spectrum-sbe1v1k-ipq9574-openwrt-support/245244/250)（作者 yangzhg）
- 另一份中文指南（拆机 / 串口路线）：[luckkyboy/SBE1V1K](https://github.com/luckkyboy/SBE1V1K)
- 官方镜像：[downloads.openwrt.org snapshots / qualcommbe / ipq95xx](https://downloads.openwrt.org/snapshots/targets/qualcommbe/ipq95xx/)
- OneNAS 修复树：[OneNAS-space/Askey_Spectrum_SBE1V1K](https://github.com/OneNAS-space/Askey_Spectrum_SBE1V1K)
- 设备支持 PR：[openwrt/openwrt#21586](https://github.com/openwrt/openwrt/pull/21586)
- ath12k 竞态：[openwrt/openwrt#24949](https://github.com/openwrt/openwrt/issues/24949)

---

> 本仓库同时提供可直接使用的脚本：[`scripts/`](scripts/)。许可证：[MIT](LICENSE)。
