# dnsmasq configuration for PXE boot sandbox
# Generated from template — do not edit directly

# Disable DNS (DHCP-only mode)
port=0

# Listen only on the bridged interface
interface=${BRIDGE_IFACE}
bind-interfaces

# DHCP range
dhcp-range=${DHCP_RANGE_START},${DHCP_RANGE_END},255.255.255.0,12h

# PXE boot: detect BIOS vs UEFI client architecture
# Architecture codes: 0 = BIOS x86, 7 = UEFI x86_64, 9 = UEFI x86_64
dhcp-match=set:bios,option:client-arch,0
dhcp-match=set:efi-x86_64,option:client-arch,7
dhcp-match=set:efi-x86_64,option:client-arch,9

# BIOS PXE boot file (served by netbootxyz TFTP on port 69)
dhcp-boot=tag:bios,netboot.xyz.kpxe,,${BRIDGE_IP}

# UEFI PXE boot file (served by netbootxyz TFTP on port 69)
dhcp-boot=tag:efi-x86_64,netboot.xyz.efi,,${BRIDGE_IP}

# Verbose DHCP logging for debugging
log-dhcp
