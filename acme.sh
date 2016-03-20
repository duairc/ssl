acme_request() {
	key="$1"
	server="$2"
	url="$3"
	payload="$4"

	payload64="$(printf '%s' "$payload" | encode_base64)"

	nonce="$(http_request head "$server" | grep ^Replay-Nonce: | cut -d: -f2 | tr -d ' \r\n\t')"

	exponent="$(public_exponent "$key" | encode_base64)"
	modulus="$(public_modulus "$key" | encode_base64)"

	header='{"alg": "RS256", "jwk": {"e": "'"$exponent"'", "kty": "RSA", "n": "'"$modulus"'"}}'

	protected='{"alg": "RS256", "jwk": {"e": "'"$exponent"'", "kty": "RSA", "n": "'"$modulus"'"}, "nonce": "'"$nonce"'"}'

	protected64="$(printf '%s' "$protected" | encode_base64)"

	signed64="$(printf '%s.%s' "$protected64" "$payload64" | openssl dgst -sha256 -sign "$key" | encode_base64)"

	data='{"header": '"$header"', "protected": "'"$protected64"'", "payload": "'"$payload64"'", "signature": "'"$signed64"'"}'

	http_request post "$url" "$data"
}

thumbprint() {
	key="$1"
	exponent="$(public_exponent "$key" | encode_base64)"
	modulus="$(public_modulus "$key" | encode_base64)"
	printf '{"e":"%s","kty":"RSA","n":"%s"}' "$exponent" "$modulus" | openssl dgst -sha256 -binary | encode_base64
}

deploy_challenge() {
	domain="$1"
	token="$2"
	zone="$(printf '%s' "$domain" | remove_subdomains)"
	acme_challenge="_acme-challenge.""$domain""."
	printf '%s\t30\tIN\tTXT\t\t\t%s\n' "$acme_challenge" "$token" >> /etc/nsd/zones/"$zone"
	increment_serial
	systemctl restart nsd
	dig +short -t txt "$acme_challenge" +trace >/dev/null 2>/dev/null
}

clean_challenges() {
	list_system_zones | grep ^ | while read -r zone; do
		contents="$(cat /etc/nsd/zones/"$zone" | grep -v "^_acme-challenge")"
		printf '%s' "$contents" | grep ^ > /etc/nsd/zones/"$zone"
	done
	increment_serial
	systemctl restart nsd
}

clean_challenges_exit() {
	result="$?"
	cleanup
	clean_challenges
	exit "$result"
}

trap "clean_challenges_exit" INT TERM EXIT

path_acme_key() {
	printf '%s' "$base"/.acme
}

acme_create_key() {
	key="$1"
	printf 'Generating new RSA key-pair for ACME challenge/responses...' >&2
	mkdir -p "$(dirname "$key")"
	touch "$key"
	chmod 600 "$key"
	generate_rsa_key > "$key"
	printf ' [done]\n' >&2
}

acme_register_key() {
	key="$1"
	is_rsa_key "$key" || acme_create_key "$key"
	server="$2"
	new_reg="$3"
	license="$4"
	response="$(acme_request "$key" "$server" "$new_reg" '{"resource": "new-reg", "agreement": "'"$license"'"}' 2> /dev/null)"
	if [ "$?" != "0" ]; then
		status="$(printf '%s' "$response" | jq -r .status)"
		if [ "$status" != "409" ]; then # account already registered is fine
			printf 'Registering ACME account key failed!\n' >&2
			printf '%s\n' "$response" | jq --indent 4 . >&2
			exit 1
		fi
	fi
}

acme_sign() {
	key="$1"
	server="$2"
	csr="$3"
	license=https://letsencrypt.org/documents/LE-SA-v1.0.1-July-27-2015.pdf

	directory="$(http_request get "$server")"
	new_cert="$(printf '%s' "$directory" | jq -r '.["new-cert"]')"
	new_authz="$(printf '%s' "$directory" | jq -r '.["new-authz"]')"
	new_reg="$(printf '%s' "$directory" | jq -r '.["new-reg"]')"
	revoke_cert="$(printf '%s' "$directory" | jq -r '.["revoke_cert"]')"

	acme_register_key "$key" "$server" "$new_reg" "$license"

	clean_challenges
	list_certificate_domains_and_common_name "$csr" | grep ^ | while read -r domain; do
		response="$(acme_request "$key" "$server" "$new_authz" '{"resource": "new-authz", "identifier": {"type": "dns", "value": "'"$domain"'"}}')"
		if [ "$?" != "0" ]; then
			printf 'Getting new authorizations failed!\n' >&2
			printf '%s' "$response" | jq --indent 4 . >&2
			exit 1
		fi
		challenge="$(printf '%s' "$response" | jq '.challenges[] | select(.type | contains("dns-01"))')"
		uri="$(printf '%s' "$challenge" | jq -r .uri)"
		token="$(printf '%s' "$challenge" | jq -r .token)"
		keyauth="$(printf '%s.%s' "$token" "$(thumbprint "$key")")"
		txt="$(printf '%s' "$keyauth" | openssl dgst -sha256 -binary | encode_base64)"
		deploy_challenge "$domain" "$txt"
		printf 'Verifying that we control `%s'\''...' "$domain" >&2
		response="$(acme_request "$key" "$server" "$uri" '{"resource": "challenge", "keyAuthorization": "'"$keyauth"'"}')"
		while
			status="$(printf '%s' "$response" | jq -r .status)"
			test "$status" = "pending"
		do
			sleep 1
			response="$(http_request get "$uri")"
		done
		if [ "$status" != "valid" ]; then
			printf ' [failed]!\n' >&2
			printf '%s\n' "$response" | jq --indent 4 . >&2
			clean_challenges
			exit 1
		else
			printf ' [done]!\n' >&2
		fi
		true
	done || exit 1
	clean_challenges

	csr64="$(cat "$csr" | openssl req -outform DER | encode_base64)"

	response="$(acme_request "$key" "$server" "$new_cert" '{"resource": "new-cert", "csr": "'"$csr64"'"}' | openssl base64 -e)"

	if [ "$?" != "0" ]; then
		printf 'Getting certificate failed!\n' >&2
		printf '%s' "$response" | openssl base64 -d | jq --indent 4 . >&2
		exit 1
	else
		printf '%s' "$response" | openssl base64 -d | openssl x509 -inform DER
	fi
}