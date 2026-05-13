[    0.000000] Linux version 3.10.49 (tvws@ubuntu) (gcc version 4.8.3 (OpenWrt/Linaro GCC 4.8-2014.04 r46817) ) #7 Fri Apr 2 23:31:36 KST 2021
[    0.000000] MyLoader: sysp=b5a1a5a5, boardp=a5a1a5a5, parts=b5a5a5a5
[    0.000000] bootconsole [early0] enabled
[    0.000000] CPU revision is: 00019374 (MIPS 24Kc)
[    0.000000] SoC: Qualcomm Atheros QCA9533 rev 2
[    0.000000] Clocks: CPU:650.000MHz, DDR:392.553MHz, AHB:216.666MHz, Ref:25.000MHz
[    0.000000] Determined physical RAM map:
[    0.000000]  memory: 04000000 @ 00000000 (usable)
[    0.000000] Initrd not found or empty - disabling initrd
[    0.000000] Zone ranges:
[    0.000000]   Normal   [mem 0x00000000-0x03ffffff]
[    0.000000] Movable zone start for each node
[    0.000000] Early memory node ranges
[    0.000000]   node   0: [mem 0x00000000-0x03ffffff]
[    0.000000] On node 0 totalpages: 16384
[    0.000000] free_area_init_node: node 0, pgdat 803109b0, node_mem_map 81000000
[    0.000000]   Normal zone: 128 pages used for memmap
[    0.000000]   Normal zone: 0 pages reserved
[    0.000000]   Normal zone: 16384 pages, LIFO batch:3
[    0.000000] Primary instruction cache 64kB, VIPT, 4-way, linesize 32 bytes.
[    0.000000] Primary data cache 32kB, 4-way, VIPT, cache aliases, linesize 32 bytes
[    0.000000] pcpu-alloc: s0 r0 d32768 u32768 alloc=1*32768
[    0.000000] pcpu-alloc: [0] 0 
[    0.000000] Built 1 zonelists in Zone order, mobility grouping on.  Total pages: 16256
[    0.000000] Kernel command line:  board=AP143 console=ttyS0,115200 mtdparts=spi0.0:256k(u-boot)ro,64k(u-boot-env)ro,14528k(rootfs),1472k(kernel),64k(art),16000k@0x50000(firmware) rootfstype=squashfs,jffs2 noinitrd
[    0.000000] PID hash table entries: 256 (order: -2, 1024 bytes)
[    0.000000] Dentry cache hash table entries: 8192 (order: 3, 32768 bytes)
[    0.000000] Inode-cache hash table entries: 4096 (order: 2, 16384 bytes)
[    0.000000] Writing ErrCtl register=00000000
[    0.000000] Readback ErrCtl register=00000000
[    0.000000] Memory: 61272k/65536k available (2244k kernel code, 4264k reserved, 599k data, 228k init, 0k highmem)
[    0.000000] SLUB: HWalign=32, Order=0-3, MinObjects=0, CPUs=1, Nodes=1
[    0.000000] NR_IRQS:51
[    0.050000] Calibrating delay loop... 432.53 BogoMIPS (lpj=2162688)
[    0.050000] pid_max: default: 32768 minimum: 301
[    0.050000] Mount-cache hash table entries: 512
[    0.060000] NET: Registered protocol family 16
[    0.070000] MIPS: machine is Atheros AP143 reference board
[    0.490000] bio: create slab <bio-0> at 0
[    0.500000] Switching to clocksource MIPS
[    0.500000] NET: Registered protocol family 2
[    0.510000] TCP established hash table entries: 512 (order: 0, 4096 bytes)
[    0.510000] TCP bind hash table entries: 512 (order: -1, 2048 bytes)
[    0.520000] TCP: Hash tables configured (established 512 bind 512)
[    0.520000] TCP: reno registered
[    0.530000] UDP hash table entries: 256 (order: 0, 4096 bytes)
[    0.530000] UDP-Lite hash table entries: 256 (order: 0, 4096 bytes)
[    0.540000] NET: Registered protocol family 1
[    0.540000] PCI: CLS 0 bytes, default 32
[    0.560000] squashfs: version 4.0 (2009/01/31) Phillip Lougher
[    0.560000] jffs2: version 2.2 (NAND) (SUMMARY) (LZMA) (RTIME) (CMODE_PRIORITY) (c) 2001-2006 Red Hat, Inc.
[    0.580000] msgmni has been set to 119
[    0.580000] io scheduler noop registered
[    0.580000] io scheduler deadline registered (default)
[    0.590000] Serial: 8250/16550 driver, 1 ports, IRQ sharing disabled
[    0.620000] serial8250.0: ttyS0 at MMIO 0x18020000 (irq = 11) is a 16550A
[    0.620000] console [ttyS0] enabled, bootconsole disabled
[    0.640000] ath79-spi ath79-spi: register read/write delay is 55 nsecs
[    0.640000] ath79-spi ath79-spi: registered master spi0
[    0.640000] ath79-spi ath79-spi: master is unqueued, this is deprecated
[    0.640000] spi spi0.0: spi_bitbang_setup, 40 nsec/bit
[    0.640000] spi spi0.0: setup mode 0, 8 bits/w, 25000000 Hz max --> 0
[    0.640000] ath79-spi ath79-spi: registered child spi0.0
[    0.640000] spi spi0.1: spi_bitbang_setup, 40 nsec/bit
[    0.640000] spi spi0.1: setup mode 0, 8 bits/w, 25000000 Hz max --> 0
[    0.640000] ath79-spi ath79-spi: registered child spi0.1
[    0.640000] spi spi0.2: spi_bitbang_setup, 40 nsec/bit
[    0.640000] spi spi0.2: setup mode 0, 8 bits/w, 25000000 Hz max --> 0
[    0.640000] ath79-spi ath79-spi: registered child spi0.2
[    0.640000] spi spi0.3: spi_bitbang_setup, 40 nsec/bit
[    0.640000] spi spi0.3: setup mode 0, 8 bits/w, 25000000 Hz max --> 0
[    0.650000] ath79-spi ath79-spi: registered child spi0.3
[    0.650000] spi spi0.4: spi_bitbang_setup, 40 nsec/bit
[    0.650000] spi spi0.4: setup mode 0, 8 bits/w, 25000000 Hz max --> 0
[    0.650000] ath79-spi ath79-spi: registered child spi0.4
[    0.650000] spi spi0.5: spi_bitbang_setup, 40 nsec/bit
[    0.650000] spi spi0.5: setup mode 0, 8 bits/w, 25000000 Hz max --> 0
[    0.650000] ath79-spi ath79-spi: registered child spi0.5
[    0.650000] m25p80 spi0.0: found mx25l12805d, expected m25p80
[    0.660000] m25p80 spi0.0: mx25l12805d (16384 Kbytes)
[    0.660000] 6 cmdlinepart partitions found on MTD device spi0.0
[    0.670000] Creating 6 MTD partitions on "spi0.0":
[    0.670000] 0x000000000000-0x000000040000 : "u-boot"
[    0.680000] 0x000000040000-0x000000050000 : "u-boot-env"
[    0.690000] 0x000000050000-0x000000e80000 : "rootfs"
[    0.690000] mtd: device 2 (rootfs) set to be root filesystem
[    0.700000] 1 squashfs-split partitions found on MTD device rootfs
[    0.710000] 0x000000490000-0x000000e80000 : "rootfs_data"
[    0.710000] 0x000000e80000-0x000000ff0000 : "kernel"
[    0.720000] 0x000000ff0000-0x000001000000 : "art"
[    0.730000] 0x000000050000-0x000000ff0000 : "firmware"
[    0.760000] libphy: ag71xx_mdio: probed
[    1.310000] ag71xx-mdio.1: Found an AR934X built-in switch
[    2.350000] eth0: Atheros AG71xx at 0xba000000, irq 5, mode:GMII
[    2.910000] ag71xx ag71xx.0: connected to PHY at ag71xx-mdio.1:04 [uid=004dd042, driver=Generic PHY]
[    2.920000] eth1: Atheros AG71xx at 0xb9000000, irq 4, mode:MII
[    2.930000] TCP: cubic registered
[    2.930000] NET: Registered protocol family 17
[    2.930000] 8021q: 802.1Q VLAN Support v1.8
[    2.940000] VFS: Mounted root (squashfs filesystem) readonly on device 31:2.
[    2.950000] Freeing unused kernel memory: 228K (80327000 - 80360000)
[    5.200000] usbcore: registered new interface driver usbfs
[    5.200000] usbcore: registered new interface driver hub
[    5.210000] usbcore: registered new device driver usb
[    5.220000] SCSI subsystem initialized
[    5.240000] ehci_hcd: USB 2.0 'Enhanced' Host Controller (EHCI) Driver
[    5.240000] ehci-platform: EHCI generic platform driver
[    5.250000] ehci-platform ehci-platform: EHCI Host Controller
[    5.250000] ehci-platform ehci-platform: new USB bus registered, assigned bus number 1
[    5.260000] ehci-platform ehci-platform: irq 3, io mem 0x1b000000
[    5.290000] ehci-platform ehci-platform: USB 2.0 started, EHCI 1.00
[    5.290000] hub 1-0:1.0: USB hub found
[    5.300000] hub 1-0:1.0: 1 port detected
[    5.310000] usbcore: registered new interface driver usb-storage
[    7.850000] eth0: link up (1000Mbps/Full duplex)
[    9.850000] eth0: link down
[   10.050000] jffs2: notice: (318) jffs2_build_xattr_subsystem: complete building xattr subsystem, 1 of xdatum (0 unchecked, 0 orphan) and 16 of xref (0 dead, 2 orphan) found.
[   12.150000] NET: Registered protocol family 10
[   12.160000] tun: Universal TUN/TAP device driver, 1.6
[   12.170000] tun: (C) 1999-2004 Max Krasnyansky <maxk@qualcomm.com>
[   12.180000] nf_conntrack version 0.5.0 (960 buckets, 3840 max)
[   12.200000] ip6_tables: (C) 2000-2006 Netfilter Core Team
[   12.210000] Loading modules backported from Linux version master-2014-05-22-0-gf2032ea
[   12.220000] Backport generated by backports.git backports-20140320-37-g5c33da0
[   12.230000] ip_tables: (C) 2000-2006 Netfilter Core Team
[   12.310000] xt_coova: ready
[   12.350000] xt_time: kernel timezone is -0000
[   12.390000] cfg80211: Calling CRDA to update world regulatory domain
[   12.390000] cfg80211: World regulatory domain updated:
[   12.400000] cfg80211:  DFS Master region: unset
[   12.400000] cfg80211:   (start_freq - end_freq @ bandwidth), (max_antenna_gain, max_eirp), (dfs_cac_time)
[   12.410000] cfg80211:   (2402000 KHz - 2472000 KHz @ 40000 KHz), (N/A, 2000 mBm), (N/A)
[   12.420000] cfg80211:   (2457000 KHz - 2482000 KHz @ 40000 KHz), (N/A, 2000 mBm), (N/A)
[   12.430000] cfg80211:   (2474000 KHz - 2494000 KHz @ 20000 KHz), (N/A, 2000 mBm), (N/A)
[   12.440000] cfg80211:   (5170000 KHz - 5250000 KHz @ 160000 KHz), (N/A, 2000 mBm), (N/A)
[   12.450000] cfg80211:   (5250000 KHz - 5330000 KHz @ 160000 KHz), (N/A, 2000 mBm), (0 s)
[   12.450000] cfg80211:   (5490000 KHz - 5730000 KHz @ 160000 KHz), (N/A, 2000 mBm), (0 s)
[   12.460000] cfg80211:   (5735000 KHz - 5835000 KHz @ 80000 KHz), (N/A, 2000 mBm), (N/A)
[   12.470000] cfg80211:   (57240000 KHz - 63720000 KHz @ 2160000 KHz), (N/A, 0 mBm), (N/A)
[   12.590000] usbcore: registered new interface driver ath9k_htc
[   12.620000] ath: EEPROM regdomain: 0x0
[   12.620000] ath: EEPROM indicates default country code should be used
[   12.620000] ath: doing EEPROM country->regdmn map search
[   12.620000] ath: country maps to regdmn code: 0x3a
[   12.620000] ath: Country alpha2 being used: US
[   12.620000] ath: Regpair used: 0x3a
[   12.630000] ieee80211 phy0: Selected rate control algorithm 'minstrel_ht'
[   12.640000] cfg80211: Calling CRDA for country: US
[   12.650000] cfg80211: Regulatory domain changed to country: US
[   12.650000] cfg80211:  DFS Master region: FCC
[   12.660000] cfg80211:   (start_freq - end_freq @ bandwidth), (max_antenna_gain, max_eirp), (dfs_cac_time)
[   12.670000] cfg80211:   (2402000 KHz - 2472000 KHz @ 40000 KHz), (N/A, 3000 mBm), (N/A)
[   12.670000] cfg80211:   (5170000 KHz - 5250000 KHz @ 80000 KHz), (N/A, 1700 mBm), (N/A)
[   12.680000] cfg80211:   (5250000 KHz - 5330000 KHz @ 80000 KHz), (N/A, 2300 mBm), (0 s)
[   12.690000] cfg80211:   (5735000 KHz - 5835000 KHz @ 80000 KHz), (N/A, 3000 mBm), (N/A)
[   12.700000] cfg80211:   (57240000 KHz - 63720000 KHz @ 2160000 KHz), (N/A, 4000 mBm), (N/A)
[   12.710000] ieee80211 phy0: Atheros AR9531 Rev:2 mem=0xb8100000, irq=2
[   21.370000] IPv6: ADDRCONF(NETDEV_UP): eth0: link is not ready
[   21.380000] IPv6: ADDRCONF(NETDEV_UP): br-lan: link is not ready
[   22.010000] cfg80211: Calling CRDA for country: CO
[   22.040000] cfg80211: Regulatory domain changed to country: CO
[   22.040000] cfg80211:  DFS Master region: FCC
[   22.050000] cfg80211:   (start_freq - end_freq @ bandwidth), (max_antenna_gain, max_eirp), (dfs_cac_time)
[   22.060000] cfg80211:   (2402000 KHz - 2482000 KHz @ 40000 KHz), (N/A, 2000 mBm), (N/A)
[   22.060000] cfg80211:   (5170000 KHz - 5250000 KHz @ 80000 KHz), (N/A, 1700 mBm), (N/A)
[   22.070000] cfg80211:   (5250000 KHz - 5330000 KHz @ 80000 KHz), (N/A, 2400 mBm), (0 s)
[   22.080000] cfg80211:   (5490000 KHz - 5730000 KHz @ 80000 KHz), (N/A, 2400 mBm), (0 s)
[   22.090000] cfg80211:   (5735000 KHz - 5835000 KHz @ 80000 KHz), (N/A, 3000 mBm), (N/A)
[   23.490000] eth0: link up (1000Mbps/Full duplex)
[   23.490000] IPv6: ADDRCONF(NETDEV_CHANGE): eth0: link becomes ready
[   23.850000] IPv6: ADDRCONF(NETDEV_UP): wlan0: link is not ready
[   23.860000] device wlan0 entered promiscuous mode
[   23.860000] br-lan: port 1(wlan0) entered forwarding state
[   23.870000] br-lan: port 1(wlan0) entered forwarding state
[   23.880000] IPv6: ADDRCONF(NETDEV_CHANGE): br-lan: link becomes ready
[   23.890000] IPv6: ADDRCONF(NETDEV_CHANGE): wlan0: link becomes ready
[   25.870000] br-lan: port 1(wlan0) entered forwarding state
[   45.590000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:455) 
