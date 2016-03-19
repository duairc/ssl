meta_ca_exists() {
	path="$(path_ca meta)"
	if ! [ -f "$path" ]; then
		return 1
	elif ! is_ca_certificate "$path"; then
		printf 'Invalid meta CA certificate found! ' >&2
		return 1
	elif ! certificate_has_key "$path" "$(path_key)"; then
		printf 'RSA key mismatch for meta CA certificate! ' >&2
		return 1
	fi
}

meta_ca_trusted() {
	diff -qr "$(path_ca meta)" /usr/local/share/ca-certificates/meta.crt >/dev/null 2>/dev/null
}

create_meta_ca() {
	printf 'Creating new CA certificate for self-signing...' >&2
	archive "$(path_ca meta)"
	mkdir -p "$(path_ca)"
	generate_ca_certificate > "$(path_ca meta)"
	printf ' [done]\n' >&2
}

trust_meta_ca() {
	cp "$(path_ca meta)" /usr/local/share/ca-certificates/meta.crt
	printf 'Trusting new CA certificate...' >&2
	update-ca-certificates > /dev/null
	printf ' [done]\n' >&2
}

cas_exist() {
	diff -qr "$(path_ca)" "$project"/ca >/dev/null 2>/dev/null
}

create_cas() {
	(
		cd "$project"/ca
		for ca in *; do
			printf 'Importing `%s'\'' CA certificate...' "$ca" >&2
			cp "$ca" "$(path_ca "$ca")"
			printf ' [done]\n' >&2
		done
	)
}

is_ca_certificate() {
	certificate="$1"
	shift
	is_valid_certificate_for_ca "$certificate" "$certificate" "$@"
}

generate_ca_certificate() {
	configure_openssl | grep -v 'req_extensions = v3_req' | openssl req \
		-new \
		-x509 \
		-sha256 -extensions v3_ca \
		-days 3650 \
		-utf8 \
		-key "$base"/key \
		-config /dev/stdin
}