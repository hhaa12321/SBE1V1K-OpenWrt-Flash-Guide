# tftp-root

TFTP 根目录。恢复模式会依次拉取这两个文件，**名字不能改**：

| 文件 | 说明 |
|---|---|
| `rtq7300t_boot_auto_upgrade_fw.img` | 859 字节的启动器，本仓库已提供，也可用 `../scripts/build-launcher.sh` 重建 |
| `initramfs.itb` | OpenWrt 内存版系统，需自行下载（< 31 MiB），并核对官方 `sha256sums` |

下载地址：<https://downloads.openwrt.org/snapshots/targets/qualcommbe/ipq95xx/>
