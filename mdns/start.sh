#!/bin/sh
# Start avahi-daemon so this box answers to "<MDNS_NAME>.local" and advertises
# its web pages via DNS-SD (Bonjour). Runs with host networking.
#
# Environment:
#   MDNS_NAME           hostname to advertise, without ".local" (default: nettest)
#   MDNS_INTERFACES     comma-separated interfaces to use, e.g. "eth0,wlan0"
#                       (default: all suitable interfaces)
#   MDNS_ABOUT_PORT     port of the About page to advertise (default: 80, empty = don't)
#   MDNS_CUTIE_PORT     port of Cutie to advertise           (default: 4173, empty = don't)
set -eu

NAME="${MDNS_NAME:-nettest}"
NAME="${NAME%.local}"
INTERFACES="${MDNS_INTERFACES:-}"
ABOUT_PORT="${MDNS_ABOUT_PORT-80}"
CUTIE_PORT="${MDNS_CUTIE_PORT-4173}"

case "$NAME" in
	*[!A-Za-z0-9-]* | "" | -*)
		echo "MDNS_NAME '$NAME' is not a valid hostname label (letters, digits, hyphens)" >&2
		exit 1
		;;
esac

conf=/etc/avahi/avahi-daemon.conf
{
	echo "[server]"
	echo "host-name=$NAME"
	echo "domain-name=local"
	echo "use-ipv4=yes"
	echo "use-ipv6=yes"
	echo "enable-dbus=no"
	echo "ratelimit-interval-usec=1000000"
	echo "ratelimit-burst=1000"
	[ -n "$INTERFACES" ] && echo "allow-interfaces=$INTERFACES"
	echo
	echo "[wide-area]"
	echo "enable-wide-area=no"
	echo
	echo "[publish]"
	echo "publish-addresses=yes"
	echo "publish-hinfo=no"
	echo "publish-workstation=no"
	echo "publish-domain=yes"
	echo
	echo "[reflector]"
	echo "enable-reflector=no"
} > "$conf"

# DNS-SD service records ("%h" is replaced by the host name)
svcdir=/etc/avahi/services
rm -f "$svcdir"/*.service

write_http_service() { # file  label  port
	cat > "$svcdir/$1.service" <<EOF
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">$2 on %h</name>
  <service>
    <type>_http._tcp</type>
    <port>$3</port>
    <txt-record>path=/</txt-record>
  </service>
</service-group>
EOF
}

[ -n "$ABOUT_PORT" ] && write_http_service about "Network test box" "$ABOUT_PORT"
[ -n "$CUTIE_PORT" ] && write_http_service cutie "Cutie" "$CUTIE_PORT"

echo "mDNS: advertising ${NAME}.local${INTERFACES:+ on $INTERFACES}"

# --no-chroot: avahi's chroot needs extra capabilities and adds nothing in a container.
# avahi-daemon drops from root to the "avahi" user by itself after startup.
exec avahi-daemon --no-chroot --no-rlimits
