Fri Sep 15 05:41:36 2023 kern.info kernel: [   21.270000] IPv6: ADDRCONF(NETDEV_UP): br-lan: link is not ready
Fri Sep 15 05:41:36 2023 daemon.notice netifd: Interface 'lan' is now up
Fri Sep 15 05:41:36 2023 daemon.notice netifd: Network device 'lo' link is up
Fri Sep 15 05:41:36 2023 daemon.notice netifd: Interface 'loopback' has link connectivity 
Fri Sep 15 05:41:36 2023 kern.info kernel: [   21.920000] cfg80211: Calling CRDA for country: CO
Fri Sep 15 05:41:37 2023 kern.info kernel: [   21.940000] cfg80211: Regulatory domain changed to country: CO
Fri Sep 15 05:41:37 2023 kern.info kernel: [   21.940000] cfg80211:  DFS Master region: FCC
Fri Sep 15 05:41:37 2023 kern.info kernel: [   21.950000] cfg80211:   (start_freq - end_freq @ bandwidth), (max_antenna_gain, max_eirp), (dfs_cac_time)
Fri Sep 15 05:41:37 2023 kern.info kernel: [   21.960000] cfg80211:   (2402000 KHz - 2482000 KHz @ 40000 KHz), (N/A, 2000 mBm), (N/A)
Fri Sep 15 05:41:37 2023 kern.info kernel: [   21.960000] cfg80211:   (5170000 KHz - 5250000 KHz @ 80000 KHz), (N/A, 1700 mBm), (N/A)
Fri Sep 15 05:41:37 2023 kern.info kernel: [   21.970000] cfg80211:   (5250000 KHz - 5330000 KHz @ 80000 KHz), (N/A, 2400 mBm), (0 s)
Fri Sep 15 05:41:37 2023 kern.info kernel: [   21.980000] cfg80211:   (5490000 KHz - 5730000 KHz @ 80000 KHz), (N/A, 2400 mBm), (0 s)
Fri Sep 15 05:41:37 2023 kern.info kernel: [   21.990000] cfg80211:   (5735000 KHz - 5835000 KHz @ 80000 KHz), (N/A, 3000 mBm), (N/A)
Fri Sep 15 05:41:38 2023 kern.info kernel: [   23.380000] eth0: link up (1000Mbps/Full duplex)
Fri Sep 15 05:41:38 2023 kern.info kernel: [   23.380000] IPv6: ADDRCONF(NETDEV_CHANGE): eth0: link becomes ready
Fri Sep 15 05:41:38 2023 daemon.notice netifd: Network device 'eth0' link is up
Fri Sep 15 05:41:38 2023 daemon.notice netifd: Interface 'wan' has link connectivity 
Fri Sep 15 05:41:38 2023 daemon.notice netifd: Interface 'wan' is setting up now
Fri Sep 15 05:41:38 2023 daemon.notice netifd: wan (1038): udhcpc (v1.22.1) started
Fri Sep 15 05:41:38 2023 kern.info kernel: [   23.750000] IPv6: ADDRCONF(NETDEV_UP): wlan0: link is not ready
Fri Sep 15 05:41:38 2023 kern.info kernel: [   23.770000] device wlan0 entered promiscuous mode
Fri Sep 15 05:41:38 2023 kern.info kernel: [   23.770000] br-lan: port 1(wlan0) entered forwarding state
Fri Sep 15 05:41:38 2023 kern.info kernel: [   23.780000] br-lan: port 1(wlan0) entered forwarding state
Fri Sep 15 05:41:38 2023 daemon.notice netifd: Bridge 'br-lan' link is up
Fri Sep 15 05:41:38 2023 daemon.notice netifd: Interface 'lan' has link connectivity 
Fri Sep 15 05:41:38 2023 kern.info kernel: [   23.780000] IPv6: ADDRCONF(NETDEV_CHANGE): br-lan: link becomes ready
Fri Sep 15 05:41:38 2023 kern.info kernel: [   23.810000] IPv6: ADDRCONF(NETDEV_CHANGE): wlan0: link becomes ready
Fri Sep 15 05:41:38 2023 daemon.notice netifd: wan (1038): Sending discover...
Fri Sep 15 05:41:39 2023 daemon.notice netifd: Network device 'wlan0' link is up
Fri Sep 15 05:41:39 2023 daemon.notice netifd: radio0 (931): patch successfully...
Fri Sep 15 05:41:40 2023 daemon.info dnsmasq[1080]: started, version 2.71 cachesize 150
Fri Sep 15 05:41:40 2023 daemon.info dnsmasq[1080]: compile time options: IPv6 GNU-getopt no-DBus no-i18n no-IDN DHCP no-DHCPv6 no-Lua TFTP no-conntrack no-ipset no-auth no-DNSSEC
Fri Sep 15 05:41:40 2023 daemon.info dnsmasq-dhcp[1080]: DHCP, IP range 192.168.25.100 -- 192.168.25.249, lease time 12h
Fri Sep 15 05:41:40 2023 daemon.info dnsmasq-dhcp[1080]: DHCP, IP range 192.168.25.100 -- 192.168.25.249, lease time 12h
Fri Sep 15 05:41:40 2023 daemon.info dnsmasq[1080]: using local addresses only for domain lan
Fri Sep 15 05:41:40 2023 daemon.warn dnsmasq[1080]: no servers found in /tmp/resolv.conf.auto, will retry
Fri Sep 15 05:41:40 2023 daemon.info dnsmasq[1080]: read /etc/hosts - 1 addresses
Fri Sep 15 05:41:40 2023 daemon.info dnsmasq[1080]: read /tmp/hosts/dhcp - 2 addresses
Fri Sep 15 05:41:40 2023 daemon.info dnsmasq-dhcp[1080]: read /etc/ethers - 0 addresses
Fri Sep 15 05:41:40 2023 user.notice firewall: Reloading firewall due to ifup of lan (br-lan)
Fri Sep 15 05:41:40 2023 user.emerg syslog: setting up led WAN
Fri Sep 15 05:41:40 2023 user.emerg syslog: setting up led LAN1
Fri Sep 15 05:41:40 2023 user.emerg syslog: setting up led WLAN
Fri Sep 15 05:41:40 2023 kern.info kernel: [   25.780000] br-lan: port 1(wlan0) entered forwarding state
Fri Sep 15 05:41:41 2023 user.emerg syslog: - init complete -
Fri Sep 15 05:41:41 2023 daemon.info dnsmasq[1080]: exiting on receipt of SIGTERM
Fri Sep 15 05:41:41 2023 daemon.info dnsmasq[1188]: started, version 2.71 cachesize 150
Fri Sep 15 05:41:41 2023 daemon.info dnsmasq[1188]: compile time options: IPv6 GNU-getopt no-DBus no-i18n no-IDN DHCP no-DHCPv6 no-Lua TFTP no-conntrack no-ipset no-auth no-DNSSEC
Fri Sep 15 05:41:41 2023 daemon.info dnsmasq-dhcp[1188]: DHCP, IP range 192.168.25.100 -- 192.168.25.249, lease time 12h
Fri Sep 15 05:41:41 2023 daemon.info dnsmasq[1188]: using local addresses only for domain lan
Fri Sep 15 05:41:41 2023 daemon.warn dnsmasq[1188]: no servers found in /tmp/resolv.conf.auto, will retry
Fri Sep 15 05:41:41 2023 daemon.info dnsmasq[1188]: read /etc/hosts - 1 addresses
Fri Sep 15 05:41:41 2023 daemon.info dnsmasq[1188]: read /tmp/hosts/dhcp - 1 addresses
Fri Sep 15 05:41:41 2023 daemon.info dnsmasq-dhcp[1188]: read /etc/ethers - 0 addresses
Fri Sep 15 05:41:41 2023 daemon.notice netifd: wan (1038): Sending discover...
Fri Sep 15 05:41:42 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:41:44 2023 daemon.notice netifd: wan (1038): Sending discover...
Fri Sep 15 05:41:46 2023 daemon.info hostapd: wlan0: STA 3a:4e:90:a9:ca:cb IEEE 802.11: authenticated
Fri Sep 15 05:41:46 2023 daemon.info hostapd: wlan0: STA 3a:4e:90:a9:ca:cb IEEE 802.11: associated (aid 1)
Fri Sep 15 05:41:46 2023 daemon.info hostapd: wlan0: STA 3a:4e:90:a9:ca:cb RADIUS: starting accounting session 6503EE92-00000000
Fri Sep 15 05:41:50 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:41:51 2023 daemon.info hostapd: wlan0: STA 06:01:76:50:b0:31 IEEE 802.11: authenticated
Fri Sep 15 05:41:51 2023 daemon.info hostapd: wlan0: STA 06:01:76:50:b0:31 IEEE 802.11: associated (aid 2)
Fri Sep 15 05:41:51 2023 daemon.info hostapd: wlan0: STA 06:01:76:50:b0:31 RADIUS: starting accounting session 6503EE92-00000001
Fri Sep 15 05:41:51 2023 daemon.info hostapd: wlan0: STA 1e:b1:93:e2:ec:7c IEEE 802.11: authenticated
Fri Sep 15 05:41:51 2023 daemon.info hostapd: wlan0: STA 1e:b1:93:e2:ec:7c IEEE 802.11: associated (aid 3)
Fri Sep 15 05:41:51 2023 daemon.info hostapd: wlan0: STA 1e:b1:93:e2:ec:7c RADIUS: starting accounting session 6503EE92-00000002
Fri Sep 15 05:41:51 2023 daemon.info dnsmasq-dhcp[1188]: DHCPREQUEST(br-lan) 192.168.25.237 06:01:76:50:b0:31 
Fri Sep 15 05:41:51 2023 daemon.info dnsmasq-dhcp[1188]: DHCPACK(br-lan) 192.168.25.237 06:01:76:50:b0:31 
Fri Sep 15 05:41:51 2023 daemon.info dnsmasq-dhcp[1188]: DHCPREQUEST(br-lan) 192.168.25.138 1e:b1:93:e2:ec:7c 
Fri Sep 15 05:41:51 2023 daemon.info dnsmasq-dhcp[1188]: DHCPACK(br-lan) 192.168.25.138 1e:b1:93:e2:ec:7c 
Fri Sep 15 05:41:59 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:42:00 2023 user.warn kernel: [   45.430000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:454) 
Fri Sep 15 05:42:07 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:42:16 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:42:20 2023 user.warn kernel: [   65.450000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:654) 
Fri Sep 15 05:42:24 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:42:40 2023 user.warn kernel: [   85.480000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:854) 
Fri Sep 15 05:43:00 2023 user.warn kernel: [  105.490000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:1054) 
Fri Sep 15 05:43:16 2023 daemon.info hostapd: wlan0: STA 30:03:c8:25:9a:5f IEEE 802.11: authenticated
Fri Sep 15 05:43:16 2023 daemon.info hostapd: wlan0: STA 30:03:c8:25:9a:5f IEEE 802.11: associated (aid 4)
Fri Sep 15 05:43:16 2023 daemon.info hostapd: wlan0: STA 30:03:c8:25:9a:5f RADIUS: starting accounting session 6503EE92-00000003
Fri Sep 15 05:43:18 2023 daemon.info hostapd: wlan0: STA 64:d6:9a:b8:35:d5 IEEE 802.11: authenticated
Fri Sep 15 05:43:18 2023 daemon.info hostapd: wlan0: STA 64:d6:9a:b8:35:d5 IEEE 802.11: associated (aid 5)
Fri Sep 15 05:43:18 2023 daemon.info hostapd: wlan0: STA 64:d6:9a:b8:35:d5 RADIUS: starting accounting session 6503EE92-00000004
Fri Sep 15 05:43:19 2023 daemon.info dnsmasq-dhcp[1188]: DHCPDISCOVER(br-lan) 30:03:c8:25:9a:5f 
Fri Sep 15 05:43:19 2023 daemon.info dnsmasq-dhcp[1188]: DHCPOFFER(br-lan) 192.168.25.189 30:03:c8:25:9a:5f 
Fri Sep 15 05:43:19 2023 daemon.info dnsmasq-dhcp[1188]: DHCPDISCOVER(br-lan) 30:03:c8:25:9a:5f 
Fri Sep 15 05:43:19 2023 daemon.info dnsmasq-dhcp[1188]: DHCPOFFER(br-lan) 192.168.25.189 30:03:c8:25:9a:5f 
Fri Sep 15 05:43:19 2023 daemon.info dnsmasq-dhcp[1188]: DHCPREQUEST(br-lan) 192.168.25.189 30:03:c8:25:9a:5f 
Fri Sep 15 05:43:19 2023 daemon.info dnsmasq-dhcp[1188]: DHCPACK(br-lan) 192.168.25.189 30:03:c8:25:9a:5f juanj-Inspiron-14-7425-2-in-1
Fri Sep 15 05:43:20 2023 user.warn kernel: [  125.510000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:1255) 
Fri Sep 15 05:43:23 2023 daemon.info dnsmasq-dhcp[1188]: DHCPDISCOVER(br-lan) 64:d6:9a:b8:35:d5 
Fri Sep 15 05:43:23 2023 daemon.info dnsmasq-dhcp[1188]: DHCPOFFER(br-lan) 192.168.25.241 64:d6:9a:b8:35:d5 
Fri Sep 15 05:43:23 2023 daemon.info dnsmasq-dhcp[1188]: DHCPREQUEST(br-lan) 192.168.25.241 64:d6:9a:b8:35:d5 
Fri Sep 15 05:43:23 2023 daemon.info dnsmasq-dhcp[1188]: DHCPACK(br-lan) 192.168.25.241 64:d6:9a:b8:35:d5 DESKTOP-15OU7RD
Fri Sep 15 05:43:33 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:43:34 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:43:37 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:43:40 2023 user.warn kernel: [  145.530000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:1455) 
Fri Sep 15 05:43:42 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:43:51 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:43:59 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:44:00 2023 user.warn kernel: [  165.540000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:1655) 
Fri Sep 15 05:44:08 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:44:17 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:44:20 2023 user.warn kernel: [  185.550000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:1855) 
Fri Sep 15 05:44:26 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:44:34 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:44:40 2023 user.warn kernel: [  205.570000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:2055) 
Fri Sep 15 05:45:00 2023 user.warn kernel: [  225.600000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:2255) 
Fri Sep 15 05:45:20 2023 user.warn kernel: [  245.660000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:2456) 
Fri Sep 15 05:45:40 2023 user.warn kernel: [  265.680000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:2656) 
Fri Sep 15 05:45:42 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:45:44 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:45:46 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:45:50 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:45:59 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:46:00 2023 user.warn kernel: [  285.690000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:2856) 
Fri Sep 15 05:46:08 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:46:10 2023 daemon.info hostapd: wlan0: STA 9e:c1:73:35:48:8b IEEE 802.11: authenticated
Fri Sep 15 05:46:10 2023 daemon.info hostapd: wlan0: STA 9e:c1:73:35:48:8b IEEE 802.11: associated (aid 6)
Fri Sep 15 05:46:10 2023 daemon.info hostapd: wlan0: STA 9e:c1:73:35:48:8b RADIUS: starting accounting session 6503EE92-00000005
Fri Sep 15 05:46:13 2023 daemon.info dnsmasq-dhcp[1188]: DHCPDISCOVER(br-lan) 9e:c1:73:35:48:8b 
Fri Sep 15 05:46:13 2023 daemon.info dnsmasq-dhcp[1188]: DHCPOFFER(br-lan) 192.168.25.155 9e:c1:73:35:48:8b 
Fri Sep 15 05:46:13 2023 daemon.info dnsmasq-dhcp[1188]: DHCPDISCOVER(br-lan) 9e:c1:73:35:48:8b 
Fri Sep 15 05:46:13 2023 daemon.info dnsmasq-dhcp[1188]: DHCPOFFER(br-lan) 192.168.25.155 9e:c1:73:35:48:8b 
Fri Sep 15 05:46:14 2023 daemon.info dnsmasq-dhcp[1188]: DHCPREQUEST(br-lan) 192.168.25.155 9e:c1:73:35:48:8b 
Fri Sep 15 05:46:14 2023 daemon.info dnsmasq-dhcp[1188]: DHCPACK(br-lan) 192.168.25.155 9e:c1:73:35:48:8b 
Fri Sep 15 05:46:14 2023 daemon.info dnsmasq-dhcp[1188]: DHCPDISCOVER(br-lan) 9e:c1:73:35:48:8b 
Fri Sep 15 05:46:14 2023 daemon.info dnsmasq-dhcp[1188]: DHCPOFFER(br-lan) 192.168.25.155 9e:c1:73:35:48:8b 
Fri Sep 15 05:46:15 2023 daemon.info dnsmasq-dhcp[1188]: DHCPREQUEST(br-lan) 192.168.25.155 9e:c1:73:35:48:8b 
Fri Sep 15 05:46:15 2023 daemon.info dnsmasq-dhcp[1188]: DHCPACK(br-lan) 192.168.25.155 9e:c1:73:35:48:8b 
Fri Sep 15 05:46:16 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:46:20 2023 user.warn kernel: [  305.720000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:3057) 
Fri Sep 15 05:46:25 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:46:34 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:46:40 2023 user.warn kernel: [  325.770000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:3257) 
Fri Sep 15 05:46:42 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:47:00 2023 user.warn kernel: [  345.790000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:3457) 
Fri Sep 15 05:47:20 2023 user.warn kernel: [  365.830000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:3658) 
Fri Sep 15 05:47:40 2023 user.warn kernel: [  385.850000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:3858) 
Fri Sep 15 05:47:50 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:47:52 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:47:54 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:47:58 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:48:00 2023 user.warn kernel: [  405.880000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:4058) 
Fri Sep 15 05:48:07 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:48:15 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:48:20 2023 user.warn kernel: [  425.930000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:4259) 
Fri Sep 15 05:48:24 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:48:32 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:48:41 2023 user.warn kernel: [  445.950000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:4459) 
Fri Sep 15 05:48:41 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:48:50 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:49:01 2023 user.warn kernel: [  465.980000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:4659) 
Fri Sep 15 05:49:21 2023 user.warn kernel: [  486.000000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:4860) 
Fri Sep 15 05:49:41 2023 user.warn kernel: [  506.020000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:5060) 
Fri Sep 15 05:49:58 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:50:00 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:50:01 2023 user.warn kernel: [  526.040000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:5260) 
Fri Sep 15 05:50:02 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:50:06 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:50:14 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:50:21 2023 user.warn kernel: [  546.060000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:5460) 
Fri Sep 15 05:50:23 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:50:31 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:50:39 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:50:41 2023 user.warn kernel: [  566.080000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:5660) 
Fri Sep 15 05:50:48 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:50:56 2023 daemon.warn dnsmasq-dhcp[1188]: DHCP packet received on eth0 which has no address
Fri Sep 15 05:51:01 2023 user.warn kernel: [  586.110000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:5861) 
Fri Sep 15 05:51:21 2023 user.warn kernel: [  606.120000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:6061) 
Fri Sep 15 05:51:41 2023 user.warn kernel: [  626.140000] [WatchDog9w] Totoal 0 Ping Target Tested.. (Tick:6261) 
