#!/bin/bash

# Multi GRE Iran/Kharej Manager

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

validate_ipv4() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a o <<< "$ip"
        for x in "${o[@]}"; do
            [[ $x -gt 255 ]] && { echo "Invalid IPv4: $ip"; return 1; }
        done
        return 0
    else
        echo "Invalid IPv4: $ip"
        return 1
    fi
}

create_rc_local_iran() {
    local iran_ipv4=$1
    local kharej_ipv4=$2
    local tid=$3
    local ports="$4"

    echo "Creating /etc/rc.local for Iran (Tunnel ID: $tid)..."

    cat > /etc/rc.local << EOF
#!/bin/bash

sysctl -w net.ipv4.conf.all.forwarding=1

# GRE Tunnel IRAN (ID $tid)
ip tunnel add GRE$tid mode gre remote $kharej_ipv4 local $iran_ipv4
ip addr add 172.16.$tid.1/30 dev GRE$tid
ip link set GRE$tid mtu 1420
ip link set GRE$tid up

# NAT rules for selected ports
EOF

    for p in $ports; do
        echo "iptables -t nat -A PREROUTING -p tcp --dport $p -j DNAT --to-destination 172.16.$tid.2:$p" >> /etc/rc.local
        echo "iptables -t nat -A PREROUTING -p udp --dport $p -j DNAT --to-destination 172.16.$tid.2:$p" >> /etc/rc.local
    done

    cat >> /etc/rc.local << EOF
iptables -t nat -A POSTROUTING -j MASQUERADE

exit 0
EOF

    chmod +x /etc/rc.local
    echo "Executing /etc/rc.local..."
    bash /etc/rc.local
}

create_rc_local_kharej_multi() {
    local kharej_ipv4=$1
    local iran_count=$2

    echo "Creating /etc/rc.local for Kharej (Multi Iran)..."

    cat > /etc/rc.local << EOF
#!/bin/bash

sysctl -w net.ipv4.conf.all.forwarding=1
EOF

    for ((i=1; i<=iran_count; i++)); do
        local iran_ip=${iran_ips[$i]}
        local tid=${iran_tids[$i]}

        cat >> /etc/rc.local << EOF

# GRE Tunnel to Iran #$i (ID $tid)
ip tunnel add GRE$tid mode gre local $kharej_ipv4 remote $iran_ip
ip addr add 172.16.$tid.2/30 dev GRE$tid
ip link set GRE$tid mtu 1420
ip link set GRE$tid up

EOF
    done

    echo "exit 0" >> /etc/rc.local

    chmod +x /etc/rc.local
    echo "Executing /etc/rc.local..."
    bash /etc/rc.local
}

remove_all_tunnels() {
    echo "Removing all GRE tunnels and NAT rules..."

    # Delete all GRE* interfaces
    for dev in $(ip tunnel show | awk '{print $1}'); do
        ip tunnel del "$dev" 2>/dev/null
    done

    # Try to remove NAT rules related to 172.16.* (best-effort)
    # This is generic; اگر دقیق‌تر خواستی، می‌تونیم بر اساس tid هم بسازیم/پاک کنیم
    iptables-save | grep -v "172.16." | iptables-restore

    # Remove rc.local if exists
    if [[ -f /etc/rc.local ]]; then
        rm -f /etc/rc.local
        echo "/etc/rc.local removed."
    fi

    echo "Cleanup done."
}

echo "Select mode:"
echo "1) Configure Iran Server"
echo "2) Configure Kharej Server (Multi Iran)"
echo "3) Remove all tunnels and rules"
read -p "Enter choice (1/2/3): " choice

case "$choice" in
    1)
        echo "Configuring Iran Server..."
        read -p "Enter Iran Server Public IPv4: " iran_ipv4
        validate_ipv4 "$iran_ipv4" || exit 1

        read -p "Enter Kharej Server Public IPv4: " kharej_ipv4
        validate_ipv4 "$kharej_ipv4" || exit 1

        read -p "Enter Tunnel ID (1-254): " tid
        read -p "Enter ports to tunnel (space separated, e.g. '22 80 443 2087'): " ports

        create_rc_local_iran "$iran_ipv4" "$kharej_ipv4" "$tid" "$ports"
        ;;

    2)
        echo "Configuring Kharej Server (Multi Iran)..."
        read -p "Enter Kharej Server Public IPv4: " kharej_ipv4
        validate_ipv4 "$kharej_ipv4" || exit 1

        read -p "How many Iran servers? " iran_count

        declare -A iran_ips
        declare -A iran_tids

        for ((i=1; i<=iran_count; i++)); do
            read -p "Iran #$i Public IPv4: " ip
            validate_ipv4 "$ip" || exit 1
            iran_ips[$i]=$ip

            read -p "Tunnel ID for Iran #$i (1-254, unique): " tid
            iran_tids[$i]=$tid
        done

        create_rc_local_kharej_multi "$kharej_ipv4" "$iran_count"
        ;;

    3)
        remove_all_tunnels
        ;;

    *)
        echo "Invalid choice."
        exit 1
        ;;
esac

exit 0
