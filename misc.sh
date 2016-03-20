path_dovecot_config() {
	printf '%s' /etc/dovecot/conf.d/ssl-certificates.conf.ext
}

path_prosody_config() {
	printf '%s' /etc/prosody
}

dovecot_config_is_valid() {
	! test -d "$(dirname "$(path_dovecot_config)")" || test "$(cat "$(path_dovecot_config)" 2>/dev/null)" = "$(generate_dovecot_config)"
}

prosody_config_is_valid() {
	( test -d "$(path_prosody_config)"/conf.avail && test -d "$(path_prosody_config)"/conf.d ) || return 1
	( list_system_zones | grep ^ | while read -r zone; do
		( test -f "$(path_prosody_config)"/conf.avail/"$zone".cfg.lua && test -h "$(path_prosody_config)"/conf.d/"$zone".cfg.lua ) || exit 1
	done ) || return 1
	cd "$(path_prosody_config)"/conf.d
	for config in *.*.cfg.lua; do
		zone="$(basename "$config" .cfg.lua)"
		if
			list_system_zones | grep ^ | while read -r system_zone; do
				test "$zone" = "$system_zone" && exit 1
				true
			done
		then
			exit 1
		else
			:
		fi
	done
}

generate_dovecot_config() {
	printf 'ssl_key = <%s\n' "$(path_key)"
	printf 'ssl_cert = <%s\n' "$(path_cert default)"
	printf '\n'
	list_system_domains | grep ^ | while read -r domain; do
		printf 'local_name %s {\n\tssl_cert = <%s\n}\n\n' "$domain" "$(path_cert "$domain")"
	done
}

generate_prosody_config() {
	list_system_zones | grep ^ | while read -r zone; do
		(
			printf 'VirtualHost "%s"\n\tssl = {\n\t\tkey = "%s";\n\t\tcertificate = "%s";\n\t}\n' "$zone" "$(path_key)" "$(path_cert "$zone")"
		) > "$(path_prosody_config)"/conf.avail/"$zone".cfg.lua
		ln -sf "$(path_prosody_config)"/conf.avail/"$zone".cfg.lua "$(path_prosody_config)"/conf.d/"$zone".cfg.lua
	done
	cd "$(path_prosody_config)"/conf.d
	for config in *.*.cfg.lua; do
		zone="$(basename "$config" .cfg.lua)"
		list_system_zones | grep ^ | while read -r system_zone; do
			test "$zone" = "$system_zone" && exit 1
			true
		done && rm "$config"
	done
}

regenerate_dovecot_config() {
	printf 'Updating Dovecot configuration...' >&2
	( generate_dovecot_config > "$(path_dovecot_config)" ) 2>/dev/null
	printf ' [done]\n' >&2
}

regenerate_prosody_config() {
	printf 'Updating Prosody configuration...' >&2
	( generate_prosody_config ) 2>/dev/null
	printf ' [done]\n' >&2
}