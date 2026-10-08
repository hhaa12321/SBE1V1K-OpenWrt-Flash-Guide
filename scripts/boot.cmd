setenv serverip 172.16.252.252
tftpboot 0x80000000 initramfs.itb
bootm 0x80000000
