OpenWrt
Status
System
Services
Network
Logout
Firewall Status

Actions
Reset Counters
Restart Firewall


Table: Filter

Chain INPUT (Policy: ACCEPT, Packets: 0, Traffic: 0.00 B)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	28324	1.78 MB	delegate_input	all	--	*	*	0.0.0.0/0	0.0.0.0/0	-

Chain FORWARD (Policy: ACCEPT, Packets: 0, Traffic: 0.00 B)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	0	0.00 B	delegate_forward	all	--	*	*	0.0.0.0/0	0.0.0.0/0	-

Chain OUTPUT (Policy: ACCEPT, Packets: 0, Traffic: 0.00 B)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	26968	2.59 MB	delegate_output	all	--	*	*	0.0.0.0/0	0.0.0.0/0	-

Chain delegate_forward (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	0	0.00 B	forwarding_rule	all	--	*	*	0.0.0.0/0	0.0.0.0/0	/* user chain for forwarding */
2	0	0.00 B	ACCEPT	all	--	*	*	0.0.0.0/0	0.0.0.0/0	ctstate RELATED,ESTABLISHED
3	0	0.00 B	zone_lan_forward	all	--	br-lan	*	0.0.0.0/0	0.0.0.0/0	-
4	0	0.00 B	zone_wan_forward	all	--	eth0	*	0.0.0.0/0	0.0.0.0/0	-

Chain delegate_input (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	4512	299.63 KB	ACCEPT	all	--	lo	*	0.0.0.0/0	0.0.0.0/0	-
2	23812	1.49 MB	input_rule	all	--	*	*	0.0.0.0/0	0.0.0.0/0	/* user chain for input */
3	12600	813.22 KB	ACCEPT	all	--	*	*	0.0.0.0/0	0.0.0.0/0	ctstate RELATED,ESTABLISHED
4	1910	99.32 KB	syn_flood	tcp	--	*	*	0.0.0.0/0	0.0.0.0/0	tcp flags:0x17/0x02
5	11134	691.95 KB	zone_lan_input	all	--	br-lan	*	0.0.0.0/0	0.0.0.0/0	-
6	46	14.73 KB	zone_wan_input	all	--	eth0	*	0.0.0.0/0	0.0.0.0/0	-

Chain delegate_output (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	4512	299.63 KB	ACCEPT	all	--	*	lo	0.0.0.0/0	0.0.0.0/0	-
2	22456	2.30 MB	output_rule	all	--	*	*	0.0.0.0/0	0.0.0.0/0	/* user chain for output */
3	22439	2.29 MB	ACCEPT	all	--	*	*	0.0.0.0/0	0.0.0.0/0	ctstate RELATED,ESTABLISHED
4	17	4.11 KB	zone_lan_output	all	--	*	br-lan	0.0.0.0/0	0.0.0.0/0	-
5	0	0.00 B	zone_wan_output	all	--	*	eth0	0.0.0.0/0	0.0.0.0/0	-

Chain reject (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	0	0.00 B	REJECT	tcp	--	*	*	0.0.0.0/0	0.0.0.0/0	reject-with tcp-reset
2	0	0.00 B	REJECT	all	--	*	*	0.0.0.0/0	0.0.0.0/0	reject-with icmp-port-unreachable

Chain syn_flood (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	1878	97.69 KB	RETURN	tcp	--	*	*	0.0.0.0/0	0.0.0.0/0	tcp flags:0x17/0x02 limit: avg 25/sec burst 50
2	32	1.63 KB	DROP	all	--	*	*	0.0.0.0/0	0.0.0.0/0	-

Chain zone_lan_dest_ACCEPT (References: 2)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	17	4.11 KB	ACCEPT	all	--	*	br-lan	0.0.0.0/0	0.0.0.0/0	-

Chain zone_lan_forward (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	0	0.00 B	forwarding_lan_rule	all	--	*	*	0.0.0.0/0	0.0.0.0/0	/* user chain for forwarding */
2	0	0.00 B	zone_wan_dest_ACCEPT	all	--	*	*	0.0.0.0/0	0.0.0.0/0	/* forwarding lan -> wan */
3	0	0.00 B	ACCEPT	all	--	*	*	0.0.0.0/0	0.0.0.0/0	ctstate DNAT /* Accept port forwards */
4	0	0.00 B	zone_lan_dest_ACCEPT	all	--	*	*	0.0.0.0/0	0.0.0.0/0	-

Chain zone_lan_input (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	11134	691.95 KB	input_lan_rule	all	--	*	*	0.0.0.0/0	0.0.0.0/0	/* user chain for input */
2	0	0.00 B	ACCEPT	all	--	*	*	0.0.0.0/0	0.0.0.0/0	ctstate DNAT /* Accept port redirections */
3	11134	691.95 KB	zone_lan_src_ACCEPT	all	--	*	*	0.0.0.0/0	0.0.0.0/0	-

Chain zone_lan_output (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	17	4.11 KB	output_lan_rule	all	--	*	*	0.0.0.0/0	0.0.0.0/0	/* user chain for output */
2	17	4.11 KB	zone_lan_dest_ACCEPT	all	--	*	*	0.0.0.0/0	0.0.0.0/0	-

Chain zone_lan_src_ACCEPT (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	11134	691.95 KB	ACCEPT	all	--	br-lan	*	0.0.0.0/0	0.0.0.0/0	-

Chain zone_wan_dest_ACCEPT (References: 2)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	0	0.00 B	ACCEPT	all	--	*	eth0	0.0.0.0/0	0.0.0.0/0	-

Chain zone_wan_dest_REJECT (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	0	0.00 B	reject	all	--	*	eth0	0.0.0.0/0	0.0.0.0/0	-

Chain zone_wan_forward (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	0	0.00 B	forwarding_wan_rule	all	--	*	*	0.0.0.0/0	0.0.0.0/0	/* user chain for forwarding */
2	0	0.00 B	ACCEPT	all	--	*	*	0.0.0.0/0	0.0.0.0/0	ctstate DNAT /* Accept port forwards */
3	0	0.00 B	zone_wan_dest_REJECT	all	--	*	*	0.0.0.0/0	0.0.0.0/0	-

Chain zone_wan_input (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	46	14.73 KB	input_wan_rule	all	--	*	*	0.0.0.0/0	0.0.0.0/0	/* user chain for input */
2	0	0.00 B	ACCEPT	udp	--	*	*	0.0.0.0/0	0.0.0.0/0	udp dpt:68 /* Allow-DHCP-Renew */
3	0	0.00 B	ACCEPT	icmp	--	*	*	0.0.0.0/0	0.0.0.0/0	icmptype 8 /* Allow-Ping */
4	0	0.00 B	ACCEPT	tcp	--	*	*	0.0.0.0/0	0.0.0.0/0	tcp dpt:80 /* AllowWANWeb */
5	0	0.00 B	ACCEPT	all	--	*	*	0.0.0.0/0	0.0.0.0/0	ctstate DNAT /* Accept port redirections */
6	46	14.73 KB	zone_wan_src_ACCEPT	all	--	*	*	0.0.0.0/0	0.0.0.0/0	-

Chain zone_wan_output (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	0	0.00 B	output_wan_rule	all	--	*	*	0.0.0.0/0	0.0.0.0/0	/* user chain for output */
2	0	0.00 B	zone_wan_dest_ACCEPT	all	--	*	*	0.0.0.0/0	0.0.0.0/0	-

Chain zone_wan_src_ACCEPT (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	46	14.73 KB	ACCEPT	all	--	eth0	*	0.0.0.0/0	0.0.0.0/0	-


Table: NAT

Chain PREROUTING (Policy: ACCEPT, Packets: 20489, Traffic: 2.30 MB)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	20489	2.30 MB	delegate_prerouting	all	--	*	*	0.0.0.0/0	0.0.0.0/0	-

Chain POSTROUTING (Policy: ACCEPT, Packets: 2249, Traffic: 150.56 KB)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	2249	150.56 KB	delegate_postrouting	all	--	*	*	0.0.0.0/0	0.0.0.0/0	-

Chain delegate_postrouting (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	2249	150.56 KB	postrouting_rule	all	--	*	*	0.0.0.0/0	0.0.0.0/0	/* user chain for postrouting */
2	8	1.74 KB	zone_lan_postrouting	all	--	*	br-lan	0.0.0.0/0	0.0.0.0/0	-
3	0	0.00 B	zone_wan_postrouting	all	--	*	eth0	0.0.0.0/0	0.0.0.0/0	-

Chain delegate_prerouting (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	20489	2.30 MB	prerouting_rule	all	--	*	*	0.0.0.0/0	0.0.0.0/0	/* user chain for prerouting */
2	20407	2.28 MB	zone_lan_prerouting	all	--	br-lan	*	0.0.0.0/0	0.0.0.0/0	-
3	82	23.96 KB	zone_wan_prerouting	all	--	eth0	*	0.0.0.0/0	0.0.0.0/0	-

Chain zone_lan_postrouting (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	8	1.74 KB	postrouting_lan_rule	all	--	*	*	0.0.0.0/0	0.0.0.0/0	/* user chain for postrouting */

Chain zone_lan_prerouting (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	20407	2.28 MB	prerouting_lan_rule	all	--	*	*	0.0.0.0/0	0.0.0.0/0	/* user chain for prerouting */

Chain zone_wan_postrouting (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	0	0.00 B	postrouting_wan_rule	all	--	*	*	0.0.0.0/0	0.0.0.0/0	/* user chain for postrouting */
2	0	0.00 B	MASQUERADE	all	--	*	*	0.0.0.0/0	0.0.0.0/0	-

Chain zone_wan_prerouting (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	82	23.96 KB	prerouting_wan_rule	all	--	*	*	0.0.0.0/0	0.0.0.0/0	/* user chain for prerouting */


Table: Mangle

Chain PREROUTING (Policy: ACCEPT, Packets: 37708, Traffic: 3.41 MB)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	37708	3.41 MB	fwmark	all	--	*	*	0.0.0.0/0	0.0.0.0/0	-

Chain FORWARD (Policy: ACCEPT, Packets: 0, Traffic: 0.00 B)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	0	0.00 B	mssfix	all	--	*	*	0.0.0.0/0	0.0.0.0/0	-

Chain mssfix (References: 1)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	0	0.00 B	TCPMSS	tcp	--	*	eth0	0.0.0.0/0	0.0.0.0/0	tcp flags:0x06/0x02 /* wan (mtu_fix) */ TCPMSS clamp to PMTU


Table: Raw

Chain PREROUTING (Policy: ACCEPT, Packets: 37708, Traffic: 3.41 MB)
Rule #	Pkts.	Traffic	Target	Prot.	Flags	In	Out	Source	Destination	Options
1	37708	3.41 MB	delegate_notrack	all	--	*	*	0.0.0.0/0	0.0.0.0/0	-


Powered by LuCI 0.12 Branch (0.12+git-16.038.38474-0d510b2) OpenWrt Barrier Breaker 14.07