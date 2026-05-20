# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Pacific Edge Network** is a community CDN and local educational infrastructure for the Cocalito community in Buenaventura, Colombia. It operates offline-first with intermittent Starlink connectivity, providing educational content (Wikipedia, Kolibri, Jellyfin) via a captive portal.

**Two nodes:**
- **Mini PC** (100.90.95.134 via Netbird): Router/gateway — runs DNS primary, DHCP (Kea), firewall (nftables), NTP, captive portal, NAT64 (Jool), Prometheus/Grafana
- **Raspberry Pi 5** (100.90.81.168 via Netbird): Content server — runs nginx, Squid, Kiwix, Kolibri, Jellyfin, DNS slave

## Ansible Commands

All deployment is Ansible-based. No Makefile or package.json.

```bash
# Deploy full Mini PC configuration
cd minipc/router-setup
ansible-playbook playbook.yml -i inventory.ini

# Deploy specific role only
ansible-playbook playbook.yml -i inventory.ini --tags dns
ansible-playbook playbook.yml -i inventory.ini --tags dhcp
ansible-playbook playbook.yml -i inventory.ini --tags router
ansible-playbook playbook.yml -i inventory.ini --tags captive_portal
ansible-playbook playbook.yml -i inventory.ini --tags monitoring

# Dry run (check mode)
ansible-playbook playbook.yml -i inventory.ini --check

# Deploy Raspberry Pi services
cd raspberry/rpi-setup
ansible-playbook playbook.yml -i inventory.ini
```

**Prerequisite:** `ansible-galaxy collection install ansible.posix` (Ansible ≥2.14 required)

## Architecture

```
Internet/Starlink → Mini PC (enp170s0=WAN, enp171s0=LAN trunk 802.1Q)
                         │
              Switch Cisco Catalyst 2960
              ├── VLAN10 (Mgmt)    192.168.10.0/24 — Mini PC .1, Switch .2
              ├── VLAN20 (Servers) 192.168.20.0/24 — RPi .10
              └── VLAN30 (Clients) 192.168.30.0/24 — WiFi users (captive portal)
```

**Traffic flow:** Clients (VLAN30) → captive portal authentication → nginx:8888 (Mini PC) → Squid:3129 (RPi) → cache or WAN

**DNS:** biblioteca.local domain. Primary on Mini PC:53, slave on RPi (zone transfers via TSIG). CNAMEs: wikipedia/educacion/videos/kolibri/jellyfin/squid → RPi (192.168.20.10).

**DHCP:** Kea DHCPv4. Static reservation: MAC `2c:cf:67:d2:f0:98` → 192.168.20.10 (RPi). Pools: .50–.99 (VLAN10/20), .100–.200 (VLAN30). Requires nftables netdev hook for DHCP broadcast (Kea raw sockets).

**Firewall (nftables):** VLAN30→VLAN20 allowed; VLAN20→VLAN30 blocked; all VLANs→WAN with MASQUERADE. Captive portal uses mark-based IP state tracking in nftables sets (8-hour sessions).

**Squid proxy design:** Port 3129 (accel vhost) avoids `SO_ORIGINAL_DST` problem. Mini PC nginx at port 8888 acts as intermediary, adding Host header before forwarding to RPi Squid. Prevents loop detection.

## Repository Structure

```
minipc/
  router-setup/          # Ansible automation for Mini PC
    playbook.yml         # Main playbook (6 roles: router, dns, dhcp, captive_portal, ntp, monitoring)
    inventory.ini        # Mini PC host definition
    roles/
      router/            # netplan VLANs, nftables, IP forwarding, Jool NAT64
      dns/               # Bind9 primary (biblioteca.local + reverse zones)
      dhcp/              # Kea DHCPv4
      captive_portal/    # nginx splash page + captive-accept.py auth script
      ntp/               # Chrony
      monitoring/        # Prometheus + Grafana
  services/              # Per-service documentation (.md files)

raspberry/
  rpi-setup/             # Ansible automation for RPi
    playbook.yml
    group_vars/all.yml   # Shared variables
    roles/               # nginx, squid, kiwix, kolibri, jellyfin, node_exporter, dns_secondary
  services/              # Per-service documentation (.md files)

networkDevices/
  SwitchCerritoBongo/    # Cisco Catalyst 2960 config (SW-CORE-BONGO)
  SwitchCocalito/        # Secondary switch config

tvws/                    # TV White Space alternative connectivity (OpenWrt + Innonet hardware)
dhcp/, dns_ansible/      # Legacy roles (superseded by minipc/router-setup/roles/)
```

## Key Variables

Mini PC roles in `minipc/router-setup/roles/*/vars/main.yml`:
- `wan_interface: enp170s0`, `lan_interface: enp171s0`
- VLANs: 10 (Gestion), 20 (Servidores), 30 (Clientes)
- NAT64: `nat64_prefix: "64:ff9b::/96"`, `jool_instance_name: "default"`

RPi shared vars in `raspberry/rpi-setup/group_vars/all.yml`.

## Device Access

All devices accessed via Netbird VPN overlay (not direct LAN IPs when working remotely):
- Mini PC: `ssh user@100.90.95.134` (sudo NOPASSWD)
- RPi: `ssh akasicom@100.90.81.168` (sudo with password)
- Switch: `ssh -oKexAlgorithms=+diffie-hellman-group1-sha1 user@192.168.10.2` (requires legacy SSH algorithms)

Credentials are documented in `CREDENCIALES-SSH.md`.

## Current Deployment State

As of May 2026: Both nodes fully configured. Mini PC not yet physically cabled to switch (VLAN interfaces show LOWERLAYERDOWN). All services enabled for auto-start. See `minipc/services/ESTADO-ACTUAL.md` for detailed status.
