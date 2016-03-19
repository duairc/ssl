is_rsa_key() {
	key="$1"
	test -f "$key" && (
		contents="$(openssl rsa -in "$1" -text -noout 2>/dev/null | head -1)"
		test "$contents" = "Private-Key: (4096 bit)" ||
		test "$contents" = "Private-Key: (2048 bit)"
	)
}

key_exists() {
	is_rsa_key "$(path_key)"
}

key_permissions_correct() {
	test "$(stat -c '%a %U %G' "$(path_key)")" = '640 root ssl-cert'
}

generate_rsa_key() {
	openssl genrsa 4096 2>/dev/null
}

get_rsa_public_key() {
	openssl rsa -in "$1" -pubout 2>/dev/null
}

create_key() {
	printf 'Generating new RSA key-pair...' >&2
	mkdir -p "$base"
	touch "$(path_key)"
	fix_key_permissions
	generate_rsa_key > "$(path_key)"
	printf ' [done]\n' >&2
}

fix_key_permissions() {
	chmod 640 "$(path_key)"
	chown root "$(path_key)"
	chgrp ssl-cert "$(path_key)"
}