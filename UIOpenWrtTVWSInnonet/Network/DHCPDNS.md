OpenWrt
Status
System
Services
Network
Logout
AUTO REFRESH ON
DHCP and DNS
Dnsmasq is a combined DHCP-Server and DNS-Forwarder for NAT firewalls
Server Settings
General Settings
Resolv and Hosts Files
TFTP Settings
Advanced Settings

Domain required
  help Don't forward DNS-Requests without DNS-Name
Authoritative
  help This is the only DHCP in the local network
Local server

 help Local domain specification. Names matching this domain are never forwarded and are resolved from DHCP or hosts files only
Local domain

 help Local domain suffix appended to DHCP names and hosts file entries
Log queries
  help Write received DNS requests to syslog
DNS forwardings

 help List of DNS servers to forward requests to
Rebind protection
  help Discard upstream RFC1918 responses
Allow localhost
  help Allow upstream responses in the 127.0.0.0/8 range, e.g. for RBL services
Domain whitelist

 help List of domains to allow RFC1918 responses for

Active DHCP Leases
Hostname	IPv4-Address	MAC-Address	Leasetime remaining
DESKTOP-15OU7RD	192.168.25.241	64:d6:9a:b8:35:d5	11h 55m 44s
?	192.168.25.155	9e:c1:73:35:48:8b	11h 54m 34s
Active DHCPv6 Leases
Hostname	IPv6-Address	DUID	Leasetime remaining

There are no active leases.
Static Leases
Static leases are used to assign fixed IP addresses and symbolic hostnames to DHCP clients. They are also required for non-dynamic interface configurations where only hosts with a corresponding lease are served.
Use the Add Button to add a new lease entry. The MAC-Address indentifies the host, the IPv4-Address specifies to the fixed address to use and the Hostname is assigned as symbolic name to the requesting host.
Hostname	MAC-Address	IPv4-Address	IPv6-Suffix (hex)	 

This section contains no values yet


    
Powered by LuCI 0.12 Branch (0.12+git-16.038.38474-0d510b2) OpenWrt Barrier Breaker 14.07