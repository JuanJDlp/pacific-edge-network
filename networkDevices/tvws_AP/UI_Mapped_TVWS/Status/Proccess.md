OpenWrt
Status
System
Services
Network
Logout
Processes
This list gives an overview over currently running system processes and their status.

PID	Owner	Command	CPU usage (%)	Memory usage (%)	Hang Up	Terminate	Kill
1
root
/sbin/procd
0%
2%



2
root
[kthreadd]
0%
0%



3
root
[ksoftirqd/0]
0%
0%



4
root
[kworker/0:0]
0%
0%



5
root
[kworker/0:0H]
0%
0%



6
root
[kworker/u2:0]
0%
0%



7
root
[khelper]
0%
0%



8
root
[kworker/u2:1]
0%
0%



59
root
[writeback]
0%
0%



62
root
[bioset]
0%
0%



64
root
[kblockd]
0%
0%



89
root
[kworker/0:1]
0%
0%



94
root
[kswapd0]
0%
0%



139
root
[fsnotify_mark]
0%
0%



156
root
[ath79-spi]
0%
0%



252
root
[deferwq]
0%
0%



256
root
[kworker/0:2]
0%
0%



263
root
[khubd]
0%
0%



319
root
[jffs2_gcd_mtd3]
0%
0%



326
root
[kworker/u2:2]
0%
0%



380
root
/sbin/ubusd
0%
1%



381
root
/sbin/askfirst ttyS0 /bin/ash --login
0%
1%



674
root
[cfg80211]
0%
0%



772
root
/sbin/logd -S 16
0%
2%



806
root
/sbin/netifd
0%
2%



845
root
/usr/sbin/dropbear -F -P /var/run/dropbear.1.pid -p 22 -K 300
0%
2%



852
root
/usr/sbin/telnetd -l /bin/login
0%
2%



869
root
/usr/sbin/uhttpd -f -h /www -r OpenWrt -x /cgi-bin -u /ubus -t 60 -T 30 -k 20 -A 1 -n 3 -N 100 -R -p 0.0.0.0:80 -p [::]:80
0%
2%



1038
root
udhcpc -p /var/run/udhcpc-eth0.pid -s /lib/netifd/dhcp.script -f -t 0 -i eth0 -C
0%
2%



1040
root
/usr/sbin/hostapd -P /var/run/wifi-phy0.pid -B /var/run/hostapd-phy0.conf
0%
3%



1111
root
/root/fm10_watchdog
0%
2%



1160
root
/usr/sbin/ntpd -n -p 0.openwrt.pool.ntp.org -p 1.openwrt.pool.ntp.org -p 2.openwrt.pool.ntp.org -p 3.openwrt.pool.ntp.org
0%
2%



1188
nobody
/usr/sbin/dnsmasq -C /var/etc/dnsmasq.conf -k
0%
2%



1201
root
{luci} /usr/bin/lua /www/cgi-bin/luci
0%
5%



1202
root
sh -c /bin/busybox top -bn1
0%
2%



1203
root
/bin/busybox top -bn1
0%
2%




Powered by LuCI 0.12 Branch (0.12+git-16.038.38474-0d510b2) OpenWrt Barrier Breaker 14.07