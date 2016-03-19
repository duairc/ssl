show_certificate() {
	if is_csr "$1"; then
		openssl req -noout -text -in "$1"
	else
		openssl x509 -noout -text -in "$1"
	fi # 2>/dev/null
}

get_certificate_public_key() {
	if is_csr "$1"; then
		openssl req -pubkey -noout -in "$1"
	else
		openssl x509 -pubkey -noout -in "$1"
	fi 2>/dev/null
}

get_certificate_common_name() {
	show_certificate "$1" | grep 'Subject: ' | tr ',' '\n' | sed 's/^[ \t]*//' | grep ^CN= | cut -d= -f2- | cut -d/ -f1
}

get_certificate_subject_alt_name() {
	show_certificate "$1" | grep -A1 'Subject Alternative Name:' | tail -1 | tr ',' '\n' |  sed -e 's/^[ \t]*//'
}

get_certificate_start_date() {
	openssl x509 -startdate -noout -in "$1" | cut -d= -f2- | xargs -d'\n' date +%s --date
}

get_certificate_end_date() {
	openssl x509 -enddate -noout -in "$1" | cut -d= -f2- | xargs -d'\n' date +%s --date
}

get_certificate_ca() {
	list_cas | grep ^ | while read -r ca; do
		if is_valid_certificate_for_ca "$1" "$ca"; then
			printf '%s\n' "$(basename "$ca")"
			break
		fi
	done
}

get_certificate_coverage() {
	certificate="$1"
	domains="$2"
	ips="$3"
	total=$( (
		printf '%s' "$domains" | grep ^
		printf '%s' "$ips" | grep ^
	) | wc -l)
	covered=$( (
		printf '%s' "$domains" | grep ^ | while read -r domain; do
			certificate_has_domains "$certificate" "$domain" && printf '\n'
		done
		printf '%s' "$ips" | grep ^ | while read -r ip; do
			certificate_has_ip_addresses "$certificate" "$ip" && printf '\n'
		done
	) | wc -l)
	expr \( 100 \* "$covered" \) / "$total"
}

get_certificate_days_until_expiry() {
	now="$(date +%s)"
	then="$(get_certificate_end_date "$1")"
	expr \( \( "$then" - "$now" \) / 86400 \) + \( \( \( "$then" - "$now" \) % 86400 \) \* 2 / 86400 \)
}

certificate_has_key() {
	test "$(get_certificate_public_key "$1")" = "$(get_rsa_public_key "$2")"
}

list_certificate_domains() {
	get_certificate_subject_alt_name "$1" | grep ^DNS: | cut -d: -f2- | sort -u
}

list_certificate_domains_and_common_name() {
	(
		list_certificate_domains "$1"
		get_certificate_common_name "$1"
	) | sort -u
}

list_certificate_ip_addresses() {
	get_certificate_subject_alt_name "$1" | grep ^'IP Address': | cut -d: -f2- | normalize_ip_addresses | sort -u
}

certificate_has_domains() {
	test -z "$(list_missing_certificate_domains "$@")"
}

certificate_has_ip_addresses() {
	test -z "$(list_missing_certificate_ip_addresses "$@")"
}

certificate_has_any_domains_or_ip_addresses() {
	certificate="$1"
	domains="$2"
	ips="$3"
	! (
		printf '%s' "$domains" | grep ^ | while read -r domain; do
			list_certificate_domains_and_common_name "$certificate" | grep ^ | while read -r certificate_domain; do
				domain_matches "$domain" "$certificate_domain" && exit 1
				true
			done && exit 1
			true
		done && printf '%s' "$ips" | grep ^ | while read -r ip; do
			list_certificate_ip_addresses "$certificate" | grep ^ | while read -r certificate_ip; do
				ip_address_matches "$ip" "$certificate_ip" && exit 1
				true
			done && exit 1
			true
		done
	)
}

list_missing_certificate_domains() {
	certificate="$1"
	domains="$2"
	printf '%s' "$domains" | grep ^ | while read -r domain; do
		list_certificate_domains_and_common_name "$certificate" | grep ^ | while read -r certificate_domain; do
			domain_matches "$domain" "$certificate_domain" && exit 1
			true
		done && printf '%s\n' "$domain"
	done
}

list_missing_certificate_ip_addresses() {
	certificate="$1"
	ip_addresses="$2"
	printf '%s' "$ip_addresses" | grep ^ | while read -r ip; do
		list_certificate_ip_addresses "$certificate" | grep ^ | while read -r certificate_ip; do
			ip_address_matches "$ip" "$certificate_ip" && exit 1
			true
		done && printf '%s\n' "$ip"
	done
}

list_excess_certificate_domains() {
	certificate="$1"
	domains="$2"
	list_certificate_domains "$certificate" | grep ^ | while read -r certificate_domain; do
		printf '%s' "$domains" | grep ^ | while read -r domain; do
			domain_matches "$domain" "$certificate_domain" && exit 1
			true
		done && printf '%s\n' "$certificate_domain"
	done
}

list_excess_certificate_ip_addresses() {
	certificate="$1"
	ip_addresses="$2"o
	list_certificate_ip_addresses "$certificate" | grep ^ | while read -r certificate_ip; do
		printf '%s' "$ip_addresses" | grep ^ | while read -r ip; do
			ip_address_matches "$ip" "$certificate_ip" && exit 1
			true
		done && printf '%s\n' "$certificate_ip"
	done
}

is_meta_certificate() {
	certificate="$1"
	shift
	is_valid_certificate_for_ca "$certificate" "$(path_ca meta)" "$@"
}

is_valid_certificate() {
	certificate="$1"
	shift
	cat "$(path_ca)"* | openssl_verify "$certificate" -CApath /dev/null -CAfile /dev/stdin "$@"
}

certificate_is_valid() {
	certificate="$1"
	name="$(basename "$certificate")"
	ca="$(basename "$(dirname "$certificate")")"
	if [ "$name" != "default" ] &&
	     [ -z "$(list_system_domains | grep -Fx "$name")" ]; then
		printf 'Certificate `%s'\'' found in CA `%s'\'', but domain %s is not served by this server! ' "$name" "$ca" "$name" >&2
		return 1
	elif ! is_valid_certificate "$certificate"; then
		printf 'Invalid certificate `%s'\'' in CA `%s'\''! ' "$name" "$ca" >&2
		return 1
	elif [ "$name" != "default" ] && ! certificate_has_domains "$certificate" "$name"; then
		printf 'Certificate `%s'\'' in CA `%s'\'' does not cover domain %s! ' "$name" "$ca" "$name" >&2
		return 1
	elif [ "$name" = "default" ] &&
	    (! certificate_has_domains "$certificate" "$(list_system_domains)" ||
	     ! certificate_has_ip_addresses "$certificate" "$(list_system_ip_addresses)"); then
		if ! certificate_has_any_domains_or_ip_addresses "$certificate" "$(list_system_domains)" "$(list_system_ip_addresses)"; then
			printf 'Default certificate in CA `%s'\'' is useless as it covers no system domains or IP addresses! ' "$ca" >&2
			return 1
		else
			printf 'Default certificate in CA `%s'\'' does not cover all system domains and IP addresses! ' "$ca" >&2
			if [ "$ca" = "meta" ] && ! [ "$(get_certificate_ca "$(path_cert default)")" = "meta" ]; then
				return 1
			else
				printf '\n' >&2
				missing_domains=$(list_missing_certificate_domains "$certificate" "$(list_system_domains)" | commas)
				missing_ip_addresses=$(list_missing_certificate_ip_addresses "$certificate" "$(list_system_ip_addresses)" | commas)
				excess_domains=$(list_excess_certificate_domains "$certificate" "$(list_system_domains)" | commas)
				excess_ip_addresses=$(list_excess_certificate_ip_addresses "$certiifcate" "$(list_system_ip_addresses)" | commas)
				if [ -n "$missing_domains" ]; then
					printf 'The default certificate in CA `%s'\'' does not cover the following system domains: %s\n' "$ca" "$missing_domains" >&2
				fi
				if [ -n "$missing_ip_addresses" ]; then
					printf 'The default certificate in CA `%s'\'' does not cover the following system IP addresses: %s\n' "$ca" "$missing_ip_addresses" >&2
				fi
				if [ -n "$excess_domains" ]; then
					printf 'The default certificate in CA `%s'\'' contains the following non-system domains: %s\n' "$ca" "$excess_domains" >&2
				fi
				if [ -n "$excess_ip_addresses" ]; then
					printf 'The default certificate in CA `%s'\'' contains the following non-system IP addresses: %s\n' "$ca" "$excess_ip_addresses" >&2
				fi
				yes="$( [ "$ca" = "meta" ] && printf '%s' '-y' || printf '%s' '-n' )"
				if confirm "$yes" "$(printf 'Should I archive the default certificate in CA `%s'\''? This could affect clients that trust the existing default certificate.' "$ca")"; then
					return 1
				fi
			fi
		fi
	elif ! certificate_has_key "$certificate" "$(path_key)"; then
		printf 'RSA key mismatch for certificate `%s'\'' from CA `%s'\''! ' "$name" "$ca" >&2
		return 1
	fi
}

archive_certificate() {
	name=$(basename "$1")
	ca=$(basename "$(dirname "$1")");
	printf 'Archiving certificate `%s'\'' in CA `%s'\''...' "$name" "$ca" >&2
	archive "$certificate"
	printf ' [done]\n' >&2
}

create_meta_certificate() {
	name="$1"
	path="$(path_cert_for_ca "$name" meta)"
	if [ "$name" = "default" ]; then
		cn="$(hostname)"
		domains="$(list_system_zones | sed 's/\(.*\)/\1\n*.\1/g' | sort -u)"
		ips="$(list_system_ip_addresses)"
	else
		cn="$1"
		domains=""
		ips=""
	fi
	csr="$(mktemp -u)"
	generate_csr "$cn" "$domains" "$ips" > "$csr"
	mkdir -p "$(dirname "$path")"
	printf 'Creating new self-signed certificate `%s'\''...' "$name" >&2
	(
		sign_csr "$csr"
		cat "$(path_ca meta)"
	) > "$path"
	printf ' [done]\n' >&2
	rm "$csr"
}

link_is_valid() {
	name="$(basename "$1")"
	if ! [ -f "$(readlink "$1")" ]; then
		printf 'Link `%s'\'' is broken! ' "$name" >&2
		return 1
	else
		ca="$(get_best_ca_for "$name")"
		existing_ca="$(get_certificate_ca "$(path_cert "$name")")"
		if [ "$existing_ca" != "$ca" ]; then
			printf 'Link `%s'\'' currently points to a certificate in CA `%s'\'', however, CA `%s'\'' has a better certificate! ' "$name" "$existing_ca" "$ca" >&2
			return 1
		fi
	fi
}

link_certificate() {
	name="$1"
	ca="$(get_best_ca_for "$name")"
	printf 'Linking certificate `%s'\'' in CA `%s'\''...' "$name" "$ca" >&2
	ln -sf "$(path_cert_for_ca "$name" "$ca")" "$(path_cert "$name")"
	printf ' [done]\n' >&2
}

remove_link() {
	domain=$(basename "$1")
	printf 'Removing link `%s'\''...' "$domain" >&2
	rm -f "$link"
	printf ' [done]\n' >&2
}

meta_certificate_exists() {
	test -f "$(path_cert_for_ca "$1" meta)"
}

link_exists() {
	test -h "$(path_cert "$1")"
}