configure_openssl() {
	cn="$1"
	domains="${2:-$cn}"
	ips="$3"

	cat <<-EOF
		[req]
		distinguished_name = req_distinguished_name
		x509_extensions = v3_req
		req_extensions = v3_req
		prompt = no

		[v3_req]
		subjectAltName = @alt_names

		[v3_ca]
		subjectKeyIdentifier = hash
		authorityKeyIdentifier = keyid:always,issuer:always
		basicConstraints = critical,CA:TRUE

		[req_distinguished_name]
		C = IE
		ST = Ireland
		L = Dublin
		O = ?
		OU = ?
	EOF
	if [ -n "$cn" ]; then
		printf 'CN=%s\n' "$cn"
	fi

	printf '\n'
	printf '[alt_names]\n'

	i=0
	printf '%s' "$domains" | grep ^ | while read -r domain; do
		i="$(expr "$i" + 1)"
		printf 'DNS.%s = %s\n' "$i" "$domain"
	done
	printf '%s' "$ips" | grep ^ | while read -r ip; do
		i="$(expr "$i" + 1)"
		printf 'IP.%s = %s\n' "$i" "$ip"
	done
}

certificate_has_key() {
	test "$(get_certificate_public_key "$1")" = "$(get_rsa_public_key "$2")"
}

is_valid_certificate_for_ca() {
	certificate="$1"
	shift
	ca="$1"
	shift
	openssl_verify "$certificate" -CApath /dev/null -CAfile "$ca" "$@"
}

openssl_verify() {
	certificate="$1"
	shift
	verify="$(openssl verify "$@" "$certificate" 2>/dev/null)"
	( exit $? ) && test -z "$(printf '%s' "$verify" | tail -n+2 | grep ^error)"
}

get_best_ca_for() {
	name="$1"
	if [ "$name" = "default" ]; then
		domains="$(list_system_domains)"
		ips="$(list_system_ip_addresses)"
	else
		domains="$name"
		ips=""
	fi
	list_certificates_for "$name" | while read -r certificate; do
		certificate_sort_columns "$certificate" "$domains" "$ips"
	done | sort -n | tail -1 | awk '{print $4}'
}

is_better_certificate_than() {
	a="$1"
	b="$2"
	domains="$3"
	ips="$4"
	return "$( (
		certificate_sort_columns "$a" "$domains" "$ips" | sed 's/$/\t0/'
		certificate_sort_columns "$b" "$domains" "$ips" | sed 's/$/\t1/'
	) | sort -n | tail -1 | awk '{print $5}')"
}

certificate_sort_columns() {
	ca="$(get_certificate_ca "$1")"
	meta=2
	if [ "$ca" = "meta" ]; then
		meta=0
	elif [ "$ca" = "happyhacker" ]; then
		meta=1
	fi
	coverage="$(get_certificate_coverage "$1" "$2" "$3")"
	end_date="$(get_certificate_end_date "$1")"
	printf '%s\t%s\t%s\t%s\n' "$meta" "$coverage" "$end_date" "$ca"
}

archive() {
	if [ -f "$1" ]; then
		thing=$(realpath "$(readlink -f "$1")" --relative-base "$base" 2>/dev/null)
		if [ -f "$base"/"$thing" ]; then
			time=$(date -u +"%Y%m%dT%H%M%SZ")
			mkdir -p "$base"/archive/"$(dirname "$thing")"
			mv "$base"/"$thing" "$base"/archive/"$thing"."$time"
		fi
	fi
}