#!/bin/bash

# Multi Iran GRE Tunnel Manager
# روح – نسخه مولتی

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

create_rc_local_kharej_multi() {
    local kharej_ipv4=$1
    local iran_count=$2

    echo "Creating /etc/rc.local for Kharej (Multi)..."

    cat > /etc/rc.local << EOF
#!/bin/bash
sysctl -w net.ipv4.conf.all.forwarding=1
EOF

    for ((i=1; i<=iran_count; i++)); do
        iran_ip=${iran_ips[$i]}
        cat >> /etc/rc.local << EOF

# GRE Tunnel $i
ip tunnel add GRE$i mode gre local $kharej_ipv4 remote $iran_ip
ip addr add 172.16.$i.2/30 dev GRE$i
ip link set GRE$i mtu 1420
ip link set GRE$i up

EOF
    done

    echo "exit 0" >> /etc/rc.local
    chmod +x /etc/rc.local
    bash /etc/rc.local
}

create_rc_local_iran_multi() {
    local iran_ipv4=$1
    local kharej_ipv4=$2
    local ports=$3
    local id=$4

    echo "Creating /etc/rc.local for Iran-$id ..."

    cat > /etc/rc.local << EOF
#!/bin/bash
sysctl -w net.ipv4.conf.all.forwarding=1

# GRE Tunnel $id
ip tunnel add GRE$id mode gre remote $kharej_ipv4 local $iran_ipv4
ip addr add 172.16.$id.1/30 dev GRE$id
ip link set GRE$id mtu 1420
ip link set GRE$id up

# NAT Rules
EOF

    for p in $ports; do
        echo "iptables -t nat -A PREROUTING -p tcp --dport $p -j DNAT --to-destination 172.16.$id.2:$p" >> /etc/rc.local
        echo "iptables -t nat -A PREROUTING -p udp --dport $p -j DNAT --to-destination 172.16.$id.2:$p" >> /etc/rc.local
    done

    echo "iptables -t nat -A POSTROUTING -j MASQUERADE" >> /etc/rc.local
    echo "exit 0" >> /etc/rc.local

    chmod +x /etc/rc.local
    bash /etc/rc.local
}

echo "1) Configure Kharej (Multi Iran)"
echo "2) Configure Iran (Single)"
echo "3) Remove"
read -p "Choice: " choice

case $choice in
1)
    read -p "Kharej IPv4: " kharej_ipv4
    validate_ipv4 "$kharej_ipv4" || exit 1

    read -p "How many Iran servers? " iran_count

    declare -A iran_ips

    for ((i=1; i<=iran_count; i++)); do
        read -p "Iran #$i IPv4: " ip
        validate_ipv4 "$ip" || exit 1
        iran_ips[$i]=$ip
    done

    create_rc_local_kharej_multi "$kharej_ipv4" "$iran_count"
    ;;

2)
    read -p "Iran IPv4: " iran_ipv4
    validate_ipv4 "$iran_ipv4" || exit 1

    read -p "Kharej IPv4: " kharej_ipv4
    validate_ipv4 "$kharej_ipv4" || exit 1

    read -p "Tunnel ID (1-50): " tid
    read -p "Enter ports (space separated): " ports

    create_rc_local_iran_multi "$iran_ipv4" "$kharej_ipv4" "$ports" "$tid"
    ;;

3)
    echo "Removing..."
    ip tunnel del GRE* 2>/dev/null
    rm -f /etc/rc.local
    echo "Done."
    ;;

*)
    echo "Invalid"
    ;;
esac
