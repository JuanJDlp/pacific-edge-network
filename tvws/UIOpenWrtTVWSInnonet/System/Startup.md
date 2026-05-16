OpenWrt
Status
System
Services
Network
Logout
Initscripts
You can enable or disable installed init scripts here. Changes will applied after a device reboot.
Warning: If you disable essential init scripts like "network", your device might become inaccessible!

Start priority	Initscript	Enable/Disable	Start	Restart	Stop
0
sysfixtime




10
boot




10
system




11
sysctl




12
log




19
firewall




20
network




50
cron




50
dropbear




50
telnet




50
uhttpd




60
dnsmasq




90
chilli




95
done




95
fm10_watchdog




96
led




98
sysntpd





Local Startup
This is the content of /etc/rc.local. Insert your own commands here (in front of 'exit 0') to execute them at the end of the boot process.




  
Powered by LuCI 0.12 Branch (0.12+git-16.038.38474-0d510b2) OpenWrt Barrier Breaker 14.07