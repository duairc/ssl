is_csr() {
	test -f "$1" &&
	test "$(head -1 "$1")" = "-----BEGIN CERTIFICATE REQUEST-----"
}

generate_csr() {
	cn="$1"
	domains="$2"
	ips="$3"
	configure_openssl "$cn" "$domains" "$ips" | openssl req -new \
		-utf8 \
		-key "$(path_key)" \
		-config /dev/stdin
}

sign_csr() {
	csr="$1"
	serial="$tmpdir"/serial
	configure_openssl \
		"$(get_certificate_common_name "$csr")" \
		"$(list_certificate_domains "$csr")" \
		"$(list_certificate_ip_addresses "$csr")" | openssl x509 \
			-req -days 3650 -in "$csr" \
			-extfile /dev/stdin \
			-extensions v3_req \
			-CA "$(path_ca meta)" \
			-CAkey "$(path_key)" \
			-CAcreateserial \
			-CAserial "$tmpdir"/serial 2>/dev/null
}