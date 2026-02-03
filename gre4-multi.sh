#!/bin/bash

# GRE Tunnel Manager: 1 Kharej <-> 2 Iran

if [[ $EUID -ne 0 ]]; then
   echo "Run as root"
   exit 1
fi

validate_ipv4() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a o <<< "$ip"
        for x in "${o[@]}"; do
            [[ $x -gt 255 ]] && return 1
        done
        return 0
    fi
    return 1
}

###############################################
# IRAN SERVER (MULTI)
###############################################
config_iran() {
    echo "Iran Server Configuration"
    echo "Select which Iran server this is:"
    echo "1) Iran Server #1"
    echo "2) Iran Server #2"
    read -p "Choice (1/2): " iran_id

    case "$iran_id" in
        1) tid=1 ;;
        2) tid=2 ;;
        *) echo "Invalid Iran ID"; exit 1 ;;
    esac

    read -p "Enter THIS Iran Public IPv4: " iran_ipv4
    validate_ipv4 "$iran_ipv4" || exit 1

    read -p "Enter Kharej Public IPv4: " kharej_ipv4
    validate_ipv4 "$kharej_ipv4" || exit 1

    echo "Enter ports to tunnel (space separated):"
    read -p "Ports: " ports

    cat > /etc/rc.local << EOF
#!/bin/bash

sysctl -w net.ipv4.conf.all.forwarding=1

# GRE Tunnel for Iran #$iran_id (ID $tid)
ip tunnel add GRE$tid mode gre remote $kharej_ipv4 local $iran_ipv4
ip addr add 172.16.$tid.1/30 dev GRE$tid
ip link set GRE$tid mtu 1420
ip link set GRE$tid up

# NAT rules for selected ports
EOF

    for p in $ports; do
        echo "iptables -t nat -A PREROUTING -p tcp --dport $p -j DNAT --to 172.16.$tid.2:$p" >> /etc/rc.local
        echo "iptables -t nat -A PREROUTING -p udp --dport $p -j DNAT --to 172.16.$tid.2:$p" >> /etc/rc.local
    done

    cat >> /etc/rc.local << EOF
iptables -t nat -A POSTROUTING -j MASQUERADE

exit 0
EOF

    chmod +x /etc/rc.local
    bash /etc/rc.local
}

###############################################
# KHAREJ SERVER (MULTI IRAN)
###############################################
config_kharej() {
    echo "Kharej Server Configuration (Multi Iran)"

    read -p "Enter Kharej Public IPv4: " kharej_ipv4
    validate_ipv4 "$kharej_ipv4" || exit 1

    echo "Enter Iran #1 Public IPv4:"
    read -p "Iran #1 IPv4: " iran1_ipv4
    validate_ipv4 "$iran1_ipv4" || exit 1

    echo "Enter Iran #2 Public IPv4:"
    read -p "Iran #2 IPv4: " iran2_ipv4
    validate_ipv4 "$iran2_ipv4" || exit 1

    cat > /etc/rc.local << EOF
#!/bin/bash

sysctl -w net.ipv4.conf.all.forwarding=1

# GRE1 to Iran #1
ip tunnel add GRE1 mode gre local $kharej_ipv4 remote $iran1_ipv4
ip addr add 172.16.1.2/30 dev GRE1
ip link set GRE1 mtu 1420
ip link set GRE1 up

# GRE2 to Iran #2
ip tunnel add GRE2 mode gre local $kharej_ipv4 remote $iran2_ipv4
ip addr add 172.16.2.2/30 dev GRE2
ip link set GRE2 mtu 1420
ip link set GRE2 up

exit 0
EOF

    chmod +x /etc/rc.local
    bash /etc/rc.local
}

###############################################
# REMOVE ALL TUNNELS
###############################################
remove_all() {
    echo "Removing all GRE tunnels and NAT rules..."

    for dev in $(ip tunnel show | awk '{print $1}'); do
        ip tunnel del "$dev" 2>/dev/null
    done

    iptables-save | grep -v "172.16." | iptables-restore

    rm -f /etc/rc.local

    echo "Cleanup complete."
}

###############################################
# MENU
###############################################
echo "1) Configure Iran Server (Multi)"
echo "2) Configure Kharej Server (Multi Iran)"
echo "3) Remove All Tunnels"
read -p "Choice: " choice

case "$choice" in
    1) config_iran ;;
    2) config_kharej ;;
    3) remove_all ;;
    *) echo "Invalid choice" ;;
esac
