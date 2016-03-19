confirm() {
	default=true
	prompt="[Y/n]"
	if [ "$1" = '-n' ]; then
		shift
		default=false
		prompt="[y/N]"
	elif [ "$1" = '-y' ]; then
		shift
	fi

	read -r -p "${1:-Are you sure?} $prompt " response >&2
	case $response in
		[yY][eE][sS]|[yY])
			true
			;;
		[nN][oO]|[nN])
			false
			;;
		*)
			$default
			;;
	esac
}

ensure_root() {
	if [ "$(whoami)" != "root" ]; then
		printf 'You need to be root to do this.\n' >&2
		exit 1
	fi
}

commas() {
	tr '\n' ',' | sed 's/,$//;s/,/, /g'
}

bold() {
	printf '\033[1m%s\033[m' "$1"
}

orange() {
	printf '\033[38;5;208m%s\033[m' "$1"
}

red() {
	printf '\033[38;5;196m%s\033[m' "$1"
}

green() {
	printf '\033[38;5;46m%s\033[m' "$1"
}

yellow() {
	printf '\033[38;5;226m%s\033[m' "$1"
}

plain() {
	printf '\033[m%s' "$1"
}

readme() {
	if [ -t 1 ]; then
		sed 's/^##*\s\(.*\)$/\x1B[1m\1\x1B[m/' | sed 's/\*\*\([^\*]*\)\*\*/\x1B[1m\1\x1B[m/g' | less -R
	else
		cat
	fi
}