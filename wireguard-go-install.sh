#!/bin/bash

# WireGuard Go auto installer for Debian and Ubuntu.
# https://github.com/bosscoder/wireguard-go-install

# Define some variables
script_version=1.0
wggo_verstion=0.0.20220316
wgtools_version=1.0.20210914

# Detect Debian users running the script with "sh" instead of bash
if readlink /proc/$$/exe | grep -q "dash"; then
    echo 'This script needs to be run with "bash", not "sh".'
    exit
fi

# Check for root privileges
if [[ "$EUID" -ne 0 ]]; then
    echo "This script must be run as root."
    exit
fi

# Check for TUN
if [[ ! -e /dev/net/tun ]] || ! ( exec 7<>/dev/net/tun ) 2>/dev/null; then
    echo "This script requires TUN to work."
    exit
fi

if [ "$(uname -m)" != "x86_64" ]; then
    echo "This script requires x86_64 arch to work."
    exit
fi

# Discard stdin. Needed when running from an one-liner which includes a newline
read -N 999999 -t 0.001

# Detect OS
if grep -qs "ubuntu" /etc/os-release; then
    os="ubuntu"
    os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')
elif [[ -e /etc/debian_version ]]; then
    os="debian"
    os_version=$(grep -oE '[0-9]+' /etc/debian_version | head -1)
else
    echo "This script currently supports Debian and Ubuntu only."
    exit
fi
if [[ "$os" == "ubuntu" && "$os_version" -lt 1804 ]]; then
    echo "This version of Ubuntu is too old and unsupported."
    exit
fi

if [[ "$os" == "debian" && "$os_version" -lt 8 ]]; then
    echo "This script requires at least Debian 8 to work."
    exit
fi

# Detect environments where $PATH does not include the sbin directories
if ! grep -q sbin <<< "$PATH"; then
    echo '$PATH does not include sbin. Try using "su -" instead of "su".'
    exit
fi

new_client_dns () {
    echo "Select a DNS server for the client:"
    echo "   1) Current system resolvers"
    echo "   2) Google"
    echo "   3) 1.1.1.1"
    echo "   4) OpenDNS"
    echo "   5) Quad9"
    echo "   6) AdGuard"
    read -p "DNS server [1]: " dns
    until [[ -z "$dns" || "$dns" =~ ^[1-6]$ ]]; do
        echo "$dns: invalid selection."
        read -p "DNS server [1]: " dns
    done
        # DNS
    case "$dns" in
        1|"")
            # Locate the proper resolv.conf
            # Needed for systems running systemd-resolved
            if grep -q '^nameserver 127.0.0.53' "/etc/resolv.conf"; then
                resolv_conf="/run/systemd/resolve/resolv.conf"
            else
                resolv_conf="/etc/resolv.conf"
            fi
            # Extract nameservers and provide them in the required format
            dns=$(grep -v '^#\|^;' "$resolv_conf" | grep '^nameserver' | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | xargs | sed -e 's/ /, /g')
        ;;
        2)
            dns="8.8.8.8, 8.8.4.4"
        ;;
        3)
            dns="1.1.1.1, 1.0.0.1"
        ;;
        4)
            dns="208.67.222.222, 208.67.220.220"
        ;;
        5)
            dns="9.9.9.9, 149.112.112.112"
        ;;
        6)
            dns="94.140.14.14, 94.140.15.15"
        ;;
    esac
}

new_client_setup () {
    # Given a list of the assigned internal IPv4 addresses, obtain the lowest still
    # available octet. Important to start looking at 2, because 1 is our gateway.
    octet=2
    while grep AllowedIPs /etc/wireguard/wg0.conf | cut -d "." -f 4 | cut -d "/" -f 1 | grep -q "$octet"; do
        (( octet++ ))
    done
    # Don't break the WireGuard configuration in case the address space is full
    if [[ "$octet" -eq 255 ]]; then
        echo "253 clients are already configured. The WireGuard internal subnet is full!"
        exit
    fi
    key=$(wg genkey)
    psk=$(wg genpsk)
    # Configure client in the server
    cat << EOF >> /etc/wireguard/wg0.conf
# BEGIN_PEER $client
[Peer]
PublicKey = $(wg pubkey <<< $key)
PresharedKey = $psk
AllowedIPs = 10.7.0.$octet/32$(grep -q 'fddd:2c4:2c4:2c4::1' /etc/wireguard/wg0.conf && echo ", fddd:2c4:2c4:2c4::$octet/128")
# END_PEER $client
EOF
    # Create client configuration
    cat << EOF > ~/"$client".conf
[Interface]
Address = 10.7.0.$octet/24$(grep -q 'fddd:2c4:2c4:2c4::1' /etc/wireguard/wg0.conf && echo ", fddd:2c4:2c4:2c4::$octet/64")
DNS = $dns
PrivateKey = $key

[Peer]
PublicKey = $(grep PrivateKey /etc/wireguard/wg0.conf | cut -d " " -f 3 | wg pubkey)
PresharedKey = $psk
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $(grep '^# ENDPOINT' /etc/wireguard/wg0.conf | cut -d " " -f 3):$(grep ListenPort /etc/wireguard/wg0.conf | cut -d " " -f 3)
PersistentKeepalive = 25
EOF
}

if [[ ! -e /etc/wireguard/wg0.conf ]]; then
    # Detect some Debian minimal setups where neither wget nor curl are installed
    if ! hash wget 2>/dev/null && ! hash curl 2>/dev/null; then
        echo "Wget is required to use this installer."
        read -n1 -r -p "Press any key to install Wget and continue..."
        apt-get update
        apt-get install -y wget
    fi
    clear
    echo 'Welcome to WireGuard Go Auto Installer!'
    # If system has a single IPv4, it is selected automatically. Else, ask the user
    if [[ $(ip -4 addr | grep inet | grep -vEc '127(\.[0-9]{1,3}){3}') -eq 1 ]]; then
        ip=$(ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' | cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}')
    else
        number_of_ip=$(ip -4 addr | grep inet | grep -vEc '127(\.[0-9]{1,3}){3}')
        echo
        echo "Which IPv4 address should be used?"
        ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' | cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | nl -s ') '
        read -p "IPv4 address [1]: " ip_number
        until [[ -z "$ip_number" || "$ip_number" =~ ^[0-9]+$ && "$ip_number" -le "$number_of_ip" ]]; do
            echo "$ip_number: invalid selection."
            read -p "IPv4 address [1]: " ip_number
        done
        [[ -z "$ip_number" ]] && ip_number="1"
        ip=$(ip -4 addr | grep inet | grep -vE '127(\.[0-9]{1,3}){3}' | cut -d '/' -f 1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | sed -n "$ip_number"p)
    fi
    # If $ip is a private IP address, the server must be behind NAT
    if echo "$ip" | grep -qE '^(10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168)'; then
        echo
        echo "This server is behind NAT. What is the public IPv4 address or hostname?"
        # Get public IP and sanitize with grep
        get_public_ip=$(grep -m 1 -oE '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' <<< "$(wget -T 10 -t 1 -4qO- "http://ip1.dynupdate.no-ip.com/" || curl -m 10 -4Ls "http://ip1.dynupdate.no-ip.com/")")
        read -p "Public IPv4 address / hostname [$get_public_ip]: " public_ip
        # If the checkip service is unavailable and user didn't provide input, ask again
        until [[ -n "$get_public_ip" || -n "$public_ip" ]]; do
            echo "Invalid input."
            read -p "Public IPv4 address / hostname: " public_ip
        done
        [[ -z "$public_ip" ]] && public_ip="$get_public_ip"
    fi
    # If system has a single IPv6, it is selected automatically
    if [[ $(ip -6 addr | grep -c 'inet6 [23]') -eq 1 ]]; then
        ip6=$(ip -6 addr | grep 'inet6 [23]' | cut -d '/' -f 1 | grep -oE '([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}')
    fi
    # If system has multiple IPv6, ask the user to select one
    if [[ $(ip -6 addr | grep -c 'inet6 [23]') -gt 1 ]]; then
        number_of_ip6=$(ip -6 addr | grep -c 'inet6 [23]')
        echo
        echo "Which IPv6 address should be used?"
        ip -6 addr | grep 'inet6 [23]' | cut -d '/' -f 1 | grep -oE '([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}' | nl -s ') '
        read -p "IPv6 address [1]: " ip6_number
        until [[ -z "$ip6_number" || "$ip6_number" =~ ^[0-9]+$ && "$ip6_number" -le "$number_of_ip6" ]]; do
            echo "$ip6_number: invalid selection."
            read -p "IPv6 address [1]: " ip6_number
        done
        [[ -z "$ip6_number" ]] && ip6_number="1"
        ip6=$(ip -6 addr | grep 'inet6 [23]' | cut -d '/' -f 1 | grep -oE '([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}' | sed -n "$ip6_number"p)
    fi
    echo
    echo "What port should WireGuard listen to?"
    read -p "Port [51820]: " port
    until [[ -z "$port" || "$port" =~ ^[0-9]+$ && "$port" -le 65535 ]]; do
        echo "$port: invalid port."
        read -p "Port [51820]: " port
    done
    [[ -z "$port" ]] && port="51820"
    echo
    echo "Enter a name for the first client:"
    read -p "Name [client]: " unsanitized_client
    # Allow a limited set of characters to avoid conflicts
    client=$(sed 's/[^0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-]/_/g' <<< "$unsanitized_client")
    [[ -z "$client" ]] && client="client"
    echo
    new_client_dns
    echo
    echo "WireGuard Go installation is ready to begin."
    # Install a firewall if firewalld or iptables are not already available
    if ! systemctl is-active --quiet firewalld.service && ! hash iptables 2>/dev/null; then
        firewall="iptables"
    fi
    read -n1 -r -p "Press any key to continue..."
    # Download WireGuard Go Binary. If less than 256MB RAM, download the "lite" binary
    ram_size=$(grep -i MemTotal /proc/meminfo | awk '{print $2}')
    if [[ $ram_size -lt 524288 ]]; then
        wget -O /usr/local/bin/wireguard-go https://raw.githubusercontent.com/bosscoder/wireguard-go-install/master/bin/wireguard-go-lite-0.0.20220316
    else
        wget -O /usr/local/bin/wireguard-go https://raw.githubusercontent.com/bosscoder/wireguard-go-install/master/bin/wireguard-go-0.0.20220316
    fi
    chmod +x /usr/local/bin/wireguard-go
    # Install WireGuard Tools
    wget -O wireguard-tools.deb https://raw.githubusercontent.com/bosscoder/wireguard-go-install/master/bin/wireguard-tools_1.0.20210914-1_amd64.deb
    dpkg -i wireguard-tools.deb
    apt-get -f install -y
    rm -f wireguard-tools.deb
    wget -O '/lib/systemd/system/wg-quick@.service' https://raw.githubusercontent.com/bosscoder/wireguard-go-install/master/cfg/wg-quick%40.service

    # Generate wg0.conf
    cat << EOF > /etc/wireguard/wg0.conf
# Do not alter the commented lines
# They are used by wireguard-install
# ENDPOINT $([[ -n "$public_ip" ]] && echo "$public_ip" || echo "$ip")

[Interface]
Address = 10.7.0.1/24$([[ -n "$ip6" ]] && echo ", fddd:2c4:2c4:2c4::1/64")
PrivateKey = $(wg genkey)
ListenPort = $port

EOF
    chmod 600 /etc/wireguard/wg0.conf
    # Enable net.ipv4.ip_forward for the system
    echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-wireguard-forward.conf
    # Enable without waiting for a reboot or service restart
    echo 1 > /proc/sys/net/ipv4/ip_forward
    if [[ -n "$ip6" ]]; then
        # Enable net.ipv6.conf.all.forwarding for the system
        echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.d/99-wireguard-forward.conf
        # Enable without waiting for a reboot or service restart
        echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
    fi
    if systemctl is-active --quiet firewalld.service; then
        # Using both permanent and not permanent rules to avoid a firewalld
        # reload.
        firewall-cmd --add-port="$port"/udp
        firewall-cmd --zone=trusted --add-source=10.7.0.0/24
        firewall-cmd --permanent --add-port="$port"/udp
        firewall-cmd --permanent --zone=trusted --add-source=10.7.0.0/24
        # Set NAT for the VPN subnet
        firewall-cmd --direct --add-rule ipv4 nat POSTROUTING 0 -s 10.7.0.0/24 ! -d 10.7.0.0/24 -j SNAT --to "$ip"
        firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -s 10.7.0.0/24 ! -d 10.7.0.0/24 -j SNAT --to "$ip"
        if [[ -n "$ip6" ]]; then
            firewall-cmd --zone=trusted --add-source=fddd:2c4:2c4:2c4::/64
            firewall-cmd --permanent --zone=trusted --add-source=fddd:2c4:2c4:2c4::/64
            firewall-cmd --direct --add-rule ipv6 nat POSTROUTING 0 -s fddd:2c4:2c4:2c4::/64 ! -d fddd:2c4:2c4:2c4::/64 -j SNAT --to "$ip6"
            firewall-cmd --permanent --direct --add-rule ipv6 nat POSTROUTING 0 -s fddd:2c4:2c4:2c4::/64 ! -d fddd:2c4:2c4:2c4::/64 -j SNAT --to "$ip6"
        fi
    else
        # Create a service to set up persistent iptables rules
        iptables_path=$(command -v iptables)
        ip6tables_path=$(command -v ip6tables)
        # nf_tables is not available as standard in OVZ kernels. So use iptables-legacy
        # if we are in OVZ, with a nf_tables backend and iptables-legacy is available.
        if [[ $(systemd-detect-virt) == "openvz" ]] && readlink -f "$(command -v iptables)" | grep -q "nft" && hash iptables-legacy 2>/dev/null; then
            iptables_path=$(command -v iptables-legacy)
            ip6tables_path=$(command -v ip6tables-legacy)
        fi
        echo "[Unit]
Before=network.target
[Service]
Type=oneshot
ExecStart=$iptables_path -t nat -A POSTROUTING -s 10.7.0.0/24 ! -d 10.7.0.0/24 -j SNAT --to $ip
ExecStart=$iptables_path -I INPUT -p udp --dport $port -j ACCEPT
ExecStart=$iptables_path -I FORWARD -s 10.7.0.0/24 -j ACCEPT
ExecStart=$iptables_path -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStop=$iptables_path -t nat -D POSTROUTING -s 10.7.0.0/24 ! -d 10.7.0.0/24 -j SNAT --to $ip
ExecStop=$iptables_path -D INPUT -p udp --dport $port -j ACCEPT
ExecStop=$iptables_path -D FORWARD -s 10.7.0.0/24 -j ACCEPT
ExecStop=$iptables_path -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT" > /etc/systemd/system/wg-iptables.service
        if [[ -n "$ip6" ]]; then
            echo "ExecStart=$ip6tables_path -t nat -A POSTROUTING -s fddd:2c4:2c4:2c4::/64 ! -d fddd:2c4:2c4:2c4::/64 -j SNAT --to $ip6
ExecStart=$ip6tables_path -I FORWARD -s fddd:2c4:2c4:2c4::/64 -j ACCEPT
ExecStart=$ip6tables_path -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStop=$ip6tables_path -t nat -D POSTROUTING -s fddd:2c4:2c4:2c4::/64 ! -d fddd:2c4:2c4:2c4::/64 -j SNAT --to $ip6
ExecStop=$ip6tables_path -D FORWARD -s fddd:2c4:2c4:2c4::/64 -j ACCEPT
ExecStop=$ip6tables_path -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT" >> /etc/systemd/system/wg-iptables.service
        fi
        echo "RemainAfterExit=yes
[Install]
WantedBy=multi-user.target" >> /etc/systemd/system/wg-iptables.service
        systemctl enable wg-iptables.service
        systemctl start wg-iptables.service
    fi
    # Generates the custom client.conf
    new_client_setup
    # Enable and start the wg-quick service
    systemctl enable wg-quick@wg0.service
    systemctl start wg-quick@wg0.service
    echo
    if ! hash qrencode 2>/dev/null && ! hash qrencode 2>/dev/null; then
        apt-get update
        apt-get install -y qrencode
    fi
    qrencode -t UTF8 < ~/"$client.conf"
    echo -e '\xE2\x86\x91 That is a QR code containing the client configuration.'
    echo
    echo "Finished!"
    echo
    echo "The client configuration is available in:" ~/"$client.conf"
    echo "New clients can be added by running this script again."
else
    clear
    echo "WireGuard is already installed."
    echo
    echo "Select an option:"
    echo "   1) Add a new client"
    echo "   2) Remove an existing client"
    echo "   3) Remove WireGuard"
    echo "   4) Exit"
    read -p "Option: " option
    until [[ "$option" =~ ^[1-4]$ ]]; do
        echo "$option: invalid selection."
        read -p "Option: " option
    done
    case "$option" in
        1)
            echo
            echo "Provide a name for the client:"
            read -p "Name: " unsanitized_client
            # Allow a limited set of characters to avoid conflicts
            client=$(sed 's/[^0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-]/_/g' <<< "$unsanitized_client")
            while [[ -z "$client" ]] || grep -q "^# BEGIN_PEER $client$" /etc/wireguard/wg0.conf; do
                echo "$client: invalid name."
                read -p "Name: " unsanitized_client
                client=$(sed 's/[^0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-]/_/g' <<< "$unsanitized_client")
            done
            echo
            new_client_dns
            new_client_setup
            # Append new client configuration to the WireGuard interface
            wg addconf wg0 <(sed -n "/^# BEGIN_PEER $client/,/^# END_PEER $client/p" /etc/wireguard/wg0.conf)
            echo
            qrencode -t UTF8 < ~/"$client.conf"
            echo -e '\xE2\x86\x91 That is a QR code containing your client configuration.'
            echo
            echo "$client added. Configuration available in:" ~/"$client.conf"
            exit
        ;;
        2)
            # This option could be documented a bit better and maybe even be simplified
            # ...but what can I say, I want some sleep too
            number_of_clients=$(grep -c '^# BEGIN_PEER' /etc/wireguard/wg0.conf)
            if [[ "$number_of_clients" = 0 ]]; then
                echo
                echo "There are no existing clients!"
                exit
            fi
            echo
            echo "Select the client to remove:"
            grep '^# BEGIN_PEER' /etc/wireguard/wg0.conf | cut -d ' ' -f 3 | nl -s ') '
            read -p "Client: " client_number
            until [[ "$client_number" =~ ^[0-9]+$ && "$client_number" -le "$number_of_clients" ]]; do
                echo "$client_number: invalid selection."
                read -p "Client: " client_number
            done
            client=$(grep '^# BEGIN_PEER' /etc/wireguard/wg0.conf | cut -d ' ' -f 3 | sed -n "$client_number"p)
            echo
            read -p "Confirm $client removal? [y/N]: " remove
            until [[ "$remove" =~ ^[yYnN]*$ ]]; do
                echo "$remove: invalid selection."
                read -p "Confirm $client removal? [y/N]: " remove
            done
            if [[ "$remove" =~ ^[yY]$ ]]; then
                # The following is the right way to avoid disrupting other active connections:
                # Remove from the live interface
                wg set wg0 peer "$(sed -n "/^# BEGIN_PEER $client$/,\$p" /etc/wireguard/wg0.conf | grep -m 1 PublicKey | cut -d " " -f 3)" remove
                # Remove from the configuration file
                sed -i "/^# BEGIN_PEER $client/,/^# END_PEER $client/d" /etc/wireguard/wg0.conf
                echo
                echo "$client removed!"
            else
                echo
                echo "$client removal aborted!"
            fi
            exit
        ;;
        3)
            echo
            read -p "Confirm WireGuard removal? [y/N]: " remove
            until [[ "$remove" =~ ^[yYnN]*$ ]]; do
                echo "$remove: invalid selection."
                read -p "Confirm WireGuard removal? [y/N]: " remove
            done
            if [[ "$remove" =~ ^[yY]$ ]]; then
                port=$(grep '^ListenPort' /etc/wireguard/wg0.conf | cut -d " " -f 3)
                if systemctl is-active --quiet firewalld.service; then
                    ip=$(firewall-cmd --direct --get-rules ipv4 nat POSTROUTING | grep '\-s 10.7.0.0/24 '"'"'!'"'"' -d 10.7.0.0/24' | grep -oE '[^ ]+$')
                    # Using both permanent and not permanent rules to avoid a firewalld reload.
                    firewall-cmd --remove-port="$port"/udp
                    firewall-cmd --zone=trusted --remove-source=10.7.0.0/24
                    firewall-cmd --permanent --remove-port="$port"/udp
                    firewall-cmd --permanent --zone=trusted --remove-source=10.7.0.0/24
                    firewall-cmd --direct --remove-rule ipv4 nat POSTROUTING 0 -s 10.7.0.0/24 ! -d 10.7.0.0/24 -j SNAT --to "$ip"
                    firewall-cmd --permanent --direct --remove-rule ipv4 nat POSTROUTING 0 -s 10.7.0.0/24 ! -d 10.7.0.0/24 -j SNAT --to "$ip"
                    if grep -qs 'fddd:2c4:2c4:2c4::1/64' /etc/wireguard/wg0.conf; then
                        ip6=$(firewall-cmd --direct --get-rules ipv6 nat POSTROUTING | grep '\-s fddd:2c4:2c4:2c4::/64 '"'"'!'"'"' -d fddd:2c4:2c4:2c4::/64' | grep -oE '[^ ]+$')
                        firewall-cmd --zone=trusted --remove-source=fddd:2c4:2c4:2c4::/64
                        firewall-cmd --permanent --zone=trusted --remove-source=fddd:2c4:2c4:2c4::/64
                        firewall-cmd --direct --remove-rule ipv6 nat POSTROUTING 0 -s fddd:2c4:2c4:2c4::/64 ! -d fddd:2c4:2c4:2c4::/64 -j SNAT --to "$ip6"
                        firewall-cmd --permanent --direct --remove-rule ipv6 nat POSTROUTING 0 -s fddd:2c4:2c4:2c4::/64 ! -d fddd:2c4:2c4:2c4::/64 -j SNAT --to "$ip6"
                    fi
                else
                    systemctl stop wg-iptables.service
                    systemctl disable wg-iptables.service
                    rm -f /etc/systemd/system/wg-iptables.service
                fi
                systemctl stop wg-quick@wg0.service
                systemctl disable wg-quick@wg0.service
                rm -f /etc/systemd/system/wg-quick@wg0.service.d/boringtun.conf
                rm -f /etc/sysctl.d/99-wireguard-forward.conf
                apt-get remove --purge -y wireguard-tools
                rm -rf /etc/wireguard/
                rm -f /usr/local/bin/wireguard-go
                # Different packages were installed if the system was containerized or not
                echo
                echo "WireGuard removed!"
            else
                echo
                echo "WireGuard removal aborted!"
            fi
            exit
        ;;
        4)
            exit
        ;;
    esac
fi