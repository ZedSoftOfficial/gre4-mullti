#!/bin/bash

# Multi GRE Tunnel Manager – روح نسخه فیکس‌شده

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
###  IRAN SERVER CONFIG
###############################################
config_iran() {
    echo "Configuring Iran Server..."

    read -p "Enter Iran Public IPv4: " iran_ipv4
    validate_ipv4 "$iran_ipv4" || exit 1

    read -p "Enter Kharej Public IPv4: " kharej_ipv4
    validate_ipv4 "$kharej_ipv4" || exit 1

    echo ""
    echo "⚠ هر ایران باید Tunnel ID متفاوت داشته باشد"
    echo "مثال: ایران اول = 1 ، ایران دوم = 2"
    echo ""
    read -p "Enter Tunnel ID (1-254): " tid

    echo ""
    echo "پورت‌هایی که باید تونل شوند را وارد کن (با فاصله)"
    echo "مثال: 22 80 443 2087"
    read -p "Ports: " ports

    cat > /etc/rc.local << EOF
#!/bin/bash

sysctl -w net.ipv4.conf.all.forwarding=1

# GRE Tunnel for Iran (ID $tid)
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
###  KHAREJ SERVER CONFIG (MULTI IRAN)
###############################################
config_kharej() {
    echo "Configuring Kharej Server (Multi Iran)..."

    read -p "Enter Kharej Public IPv4: " kharej_ipv4
    validate_ipv4 "$kharej_ipv4" || exit 1

    read -p "How many Iran servers? " iran_count

    declare -A iran_ips
    declare -A iran_tids

    for ((i=1; i<=iran_count; i++)); do
        echo ""
        echo "Iran #$i"
        read -p "Public IPv4: " ip
        validate_ipv4 "$ip" || exit 1
        iran_ips[$i]=$ip

        read -p "Tunnel ID for Iran #$i (1-254): " tid
        iran_tids[$i]=$tid
    done

    cat > /etc/rc.local << EOF
#!/bin/bash
sysctl -w net.ipv4.conf.all.forwarding=1
EOF

    for ((i=1; i<=iran_count; i++)); do
        ip=${iran_ips[$i]}
        tid=${iran_tids[$i]}

        cat >> /etc/rc.local << EOF

# GRE Tunnel to Iran #$i (ID $tid)
ip tunnel add GRE$tid mode gre local $kharej_ipv4 remote $ip
ip addr add 172.16.$tid.2/30 dev GRE$tid
ip link set GRE$tid mtu 1420
ip link set GRE$tid up

EOF
    done

    echo "exit 0" >> /etc/rc.local

    chmod +x /etc/rc.local
    bash /etc/rc.local
}

###############################################
###  REMOVE ALL TUNNELS
###############################################
remove_all() {
    echo "Removing all GRE tunnels and NAT rules..."

    for dev in $(ip tunnel show | awk '{print $1}'); do
        ip tunnel del "$dev" 2>/dev/null
    done

    iptables-save | grep -v "172.16." | iptables-restore

    rm -f /etc/rc.local

    echo "Cleanup done."
}

###############################################
###  MENU
###############################################
echo "1) Configure Iran Server"
echo "2) Configure Kharej Server (Multi Iran)"
echo "3) Remove All Tunnels"
read -p "Choice: " choice

case "$choice" in
    1) config_iran ;;
    2) config_kharej ;;
    3) remove_all ;;
    *) echo "Invalid choice" ;;
esac
