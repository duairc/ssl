tmpdir="$(mktemp -d "ssl-tmp-XXXXXXX")"

normalize_ip_addresses() {
	perl -pe '$_=lc;s/((?::0\b){2,}):?(?!\S*\b\g1:0\b)(\S*)/::$2/'
}

system_has_ip_address() {
	test -n "$(list_system_ip_addresses | grep -Fx "$1")"
}

list_system_zones() {
	if ! [ -e "$tmpdir"/zones ]; then
		(
			zonestatus="$(nsd-control zonestatus 2>/dev/null)"
			if ( exit $? ); then
				printf '%s' "$tmpdirtatus" | grep ^zone: | awk '{print $2}' | sort -u
			else
				printf 'The nameserver daemon is not running. Attempting to start it to continue...' >&2
				if systemctl start nsd; then
					printf ' [done]\n' >&2
					list_system_zones
				else
					printf ' [failed]\n' >&2
					exit 1
				fi
			fi
		) > "$tmpdir"/zones
	fi
	cat "$tmpdir"/zones
}

list_domain_subdomains() {
	domain="$1"
	mkdir -p "$tmpdir"/zone
	if ! [ -e "$tmpdir"/zone/"$domain" ]; then
		(
			dig @localhost -tAXFR "$domain" | grep -v '^;' | grep . | awk '{print $1}' | sed 's/^_[^.]*\._tcp\.//' | sed 's/\.$//' | grep -Fvx "$(list_system_zones)" | grep ^ | sort -u
		) > "$tmpdir"/"$domain"
	fi
	cat "$tmpdir"/zone/"$domain"
}

list_system_domains() {
	list_system_zones | while read -r domain; do
		printf '%s\n' "$domain"
		list_domain_subdomains "$domain"
	done
}

list_system_ip_addresses() {
	(
		ip -o addr show scope global | awk '{print $4}' | cut -d/ -f1
	) | normalize_ip_addresses | sort -u
}

remove_subdomains() {
	grep ^ | while read -r subdomain; do
		list_system_zones | grep ^ | while read -r domain; do
			if domain_matches "$subdomain" '*'"$domain"; then
				printf '%s\n' "$domain"
			fi
		done | awk '{print length, $0;}' | sort -n | tail -1 | cut -d' ' -f2-
	done
}

domain_matches() {
	string="$1"
	pattern="$2"
	case "$string" in
		$pattern)
			true
			;;
		*)
			false
			;;
	esac
}

ip_address_matches() {
	ip1="$(printf '%s' "$1" | normalize_ip_addresses)"
	ip2="$(printf '%s' "$2" | normalize_ip_addresses)"
	test "$ip1" = "$ip2"
}

cleanup() {
	rm -rf "$tmpdir"
}