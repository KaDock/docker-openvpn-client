#!/bin/sh
vpn_provider="$(echo $OPENVPN_PROVIDER | tr '[A-Z]' '[a-z]')"
vpn_provider_configs="/etc/openvpn/$vpn_provider"
if [ ! -d "$vpn_provider_configs" ]; then
    echo "Could not find OpenVPN provider: $OPENVPN_PROVIDER"
    echo "Please check your settings."
    exit 1
fi

echo "Using OpenVPN provider: $OPENVPN_PROVIDER"

if [ ! -z "$OPENVPN_CONFIG" ]
then
    if [ -f $vpn_provider_configs/"${OPENVPN_CONFIG}".ovpn ]
    then
        echo "Starting OpenVPN using config ${OPENVPN_CONFIG}.ovpn"
        OPENVPN_CONFIG=$vpn_provider_configs/${OPENVPN_CONFIG}.ovpn
    else
        echo "Supplied config ${OPENVPN_CONFIG}.ovpn could not be found."
        echo "Using default OpenVPN gateway for provider ${vpn_provider}"
        OPENVPN_CONFIG=$vpn_provider_configs/default.ovpn
    fi
else
    echo "No VPN configuration provided. Using default."
    OPENVPN_CONFIG=$vpn_provider_configs/default.ovpn
fi

# add OpenVPN user/pass
if [ "${OPENVPN_USERNAME}" = "**None**" ] || [ "${OPENVPN_PASSWORD}" = "**None**" ] ; then
    echo "OpenVPN credentials not set. Exiting."
    exit 1
else
    echo "Setting OPENVPN credentials..."
    mkdir -p /config
    echo $OPENVPN_USERNAME > /config/openvpn-credentials.txt
    echo $OPENVPN_PASSWORD >> /config/openvpn-credentials.txt
    chmod 600 /config/openvpn-credentials.txt
fi

mkdir -p /dev/net
mknod /dev/net/tun c 10 200

# allow access from local network (as an alternative to running a web proxy).
if [ -n "${LOCAL_NETWORK-}" ]; then
    eval $(/sbin/ip r l m 0.0.0.0 | awk '{if($5!="tun0"){print "GW="$3"\nINT="$5; exit}}')
    if [ -n "${GW-}" -a -n "${INT-}" ]; then
        echo "adding route to local network $LOCAL_NETWORK via $GW dev $INT"
        /sbin/ip r a "$LOCAL_NETWORK" via "$GW" dev "$INT"
    fi
fi

# firewall all non-vpn traffic
remote_port=$(grep 'remote ' "${OPENVPN_CONFIG}" | awk '{print $3}')
docker_network=$(ip -o addr show dev eth0 | awk '$3 == "inet" {print $4}')
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
iptables -A FORWARD -i tun0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth0 -o tun0 -j ACCEPT
iptables -F OUTPUT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -o tap0 -j ACCEPT
iptables -A OUTPUT -o tun0 -j ACCEPT
iptables -A OUTPUT -d ${docker_network} -j ACCEPT
iptables -A OUTPUT -p udp -m udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp -m tcp --dport ${remote_port} -j ACCEPT
iptables -A OUTPUT -p udp -m udp --dport ${remote_port} -j ACCEPT;
iptables -A OUTPUT -j DROP

exec openvpn $OPENVPN_OPTS --config "$OPENVPN_CONFIG"
