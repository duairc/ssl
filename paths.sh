path_key() {
	printf '%s' "$base"/key
}

path_ca() {
	printf '%s' "$base"/ca/"$1"
}

path_cert() {
	printf '%s' "$base"/cert/"$1"
}

path_cert_for_ca() {
	printf '%s' "$base"/cert/"$2"/"$1"
}

list_cas() {
	find "$(path_ca)" -mindepth 1 -maxdepth 1 -type f -print 2>/dev/null
}

list_certificates() {
	find "$(path_cert)" -mindepth 2 -maxdepth 2 -type f -print 2>/dev/null
}

list_certificates_for() {
	find "$(path_cert)" -mindepth 2 -maxdepth 2 -type f -name "$1" -print 2>/dev/null
}

list_links() {
	find "$(path_cert)" -mindepth 1 -maxdepth 1 -type l -print 2>/dev/null
}