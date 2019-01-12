#!/bin/bash

# TODO: Documentation for this script

declare -r myver="0.0.1"
declare -r this="$(basename $0)"

LIBRARY=${LIBRARY:-'/usr/share/makepkg'}

# Import parseopts.sh
source "${LIBRARY}/util/parseopts.sh"

plain() {
	local mesg=$1; shift
	printf "${BOLD}    ${mesg}${ALL_OFF}\n" "$@" >&1
}

debug() {
	[ "$VERBOSE" = 'n' ] && return
	local mesg=$1; shift
	printf "${CYAN}=== DEBUG:${ALL_OFF} ${mesg}\n" "$@" >&1
}

msg() {
	local mesg=$1; shift
	printf "${GREEN}==>${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&1
}

msg2() {
	local mesg=$1; shift
	printf "${BLUE}  ->${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&1
}

ask() {
	local mesg=$1; shift
	printf "${BLUE}::${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}" "$@" >&1
}

warning() {
	local mesg=$1; shift
	printf "${YELLOW}==> WARNING:${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

error() {
	local mesg=$1; shift
	printf "${RED}==> ERROR:${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

usage() {
	printf "%s %s\n" "$this" "$myver"
	echo
	printf -- "Usage: %s [action] [options]\n" "$this"
	printf -- "Manage secureboot\n"
	echo

	printf -- "Actions:\n"
	printf -- "  --init                     This action will generate secureboot keys\n"
	printf -- "  -s, --sign [file]          Sign file with ISK key\n"
	printf -- "                                 signed file will be located in the same directory that source file\n"
	printf -- "                                 and have postfix '.signed'. Can be overwrited by --output option\n"
	printf -- "  --enroll-keys              Enroll keys into UEFI when system in Setup Mode\n"
	echo

	printf -- "Options:\n"
	printf -- "  --no-color                 Disable colorizing\n"
	printf -- "  --verbose                  Enable more verbose output\n"
	printf -- "  --secure-db                Generate ISK key encrypted. You will enter passphrase when signing images.\n"
	printf -- "  --no-pass                  Generate keys unencrypted. [NOT RECOMENDED]\n"
	printf -- "  --output                   Write signed data to file\n"
	printf -- "  -h, --help                 Show this help message and exit\n"
	printf -- "  -v, --version              Show program version\n"
}

version() {
	printf "%s %s\n" "$this" "$myver"
}

check_key() {
	local key=$1
	[[ ! -f "${KEYS_DIR}/${key}.esl" || ! -f "${KEYS_DIR}/${key}.auth" ]] && return 1
	return 0

}

check_keys() {
	if ! check_key "db" ; then
		error "Secureboot keys does not exists or not properly generated."
		msg "You will run %s --init to initialize keys." "$this"
		exit 1
	fi

	if ! check_key "PK" || ! check_key "KEK"; then
		if (( ENROLL_KEYS )); then
			error "PK or KEK key does not exists. You can not use --enroll-keys action in this case."
			exit 1
		else
			warning "PK or KEK key does not exists. You can not use --enroll-keys action in this case."
		fi
	fi
}

generate_sb_key() {
	local name=$1
	local secure='-nodes'
	local exit_code

	if [ "$name" != 'db' ] || [[ "$name" = 'db' && "$SECURE_DB" = 'y' ]]; then
		if [ "$USE_PASS" = 'y' ]; then
			secure='-passout env:PASSPHRASE'
			ask "Enter passphrase for %s key: " "$name"
			read -s passphrase
			echo
		fi
	fi

	PASSPHRASE="$passphrase" openssl req -batch -new -x509 -newkey rsa:2049 -subj "/CN=${name}/" \
		-keyout "${KEYS_DIR}/${name}.key" \
		-out "${KEYS_DIR}/${name}.crt" \
		-days 3650 -sha256 \
		${secure}
	exit_code=$?

	unset passphrase PASSPHRASE

	if [ "$exit_code" != '0' ]; then
		error "Openssl key %s generation failed. Exit code: %s" "$name" "$exit_code"
		exit $exit_code
	fi

	cert-to-efi-sig-list -g "$(uuidgen)" "${KEYS_DIR}/${name}.crt" "${KEYS_DIR}/${name}.esl"
}

sign_sb_key() {
	local key=$1
	local signer=$2
	local exit_code

	[ "$USE_PASS" = 'y' ] && msg2 "You will enter passphrase for %s key when prompted" "$signer"

	ask ""

	sign-efi-sig-list \
		-k "${KEYS_DIR}/${signer}.key" \
		-c "${KEYS_DIR}/${signer}.crt" \
		"$key" \
		"${KEYS_DIR}/${key}.esl" \
		"${KEYS_DIR}/${key}.auth"
	exit_code=$?

	if [ "$exit_code" != '0' ]; then
		error "Signing %s key by %s failed. Exit code: %s" "$key" "$signer" "$exit_code"
		exit 1
	fi
}

initialize() {
	[[ ! -d "$KEYS_DIR" ]] && mkdir -p -m 0755 "$KEYS_DIR"
	chmod 0600 "$KEYS_DIR"

	msg "Generating Platform Key (PK)"
	generate_sb_key "PK"

	msg "Generating Key Enrollment Key (KEK)"
	generate_sb_key "KEK"

	msg "Generating Image Signing Key (db)"
	generate_sb_key "db"

	msg "Sign Platform Key (PK) by itself (PK)"
	sign_sb_key "PK" "PK"

	msg "Sign Key Enrollment Key (KEK) by Platform Key (PK)"
	sign_sb_key "KEK" "PK"

	msg "Sign Database Key (db) by Key Enrollment Key (KEK)"
	sign_sb_key "db" "KEK"

	msg "You will enroll secureboot keys into your UEFI."
	msg2 "You can use %s --enroll-keys or add manually to your UEFI Setup Tool" "$this"
}

sign(){
	local exit_code
	SIGN_OUTPUT=${SIGN_OUTPUT:-${SIGN_TARGET}.signed}
	msg "Signing file '%s'" "$SIGN_TARGET"
	sbsign \
		--key "${KEYS_DIR}/db.key" \
		--cert "${KEYS_DIR}/db.crt" \
		--output "$SIGN_OUTPUT" \
		"$SIGN_TARGET"
	exit_code=$?

	if [ "$exit_code" != '0' ]; then
		error "Signing of file '%s' failed. Exit code: %s" "$SIGN_TARGET" "$exit_code"
		exit $exit_code
	fi
}

check_setup_mode() {
	local var=$(efivar -l | grep SetupMode)
	if (( ! "$(efivar -d --name ${var})" )); then
		error "To enroll keys you will switch system into Setup Mode"
		exit 1
	fi
}

enroll_keys() {
	# Check that required binaries exists
	error=0
	for binary in 'efi-updatevar' 'efivar'; do
		if ! type -p $binary >/dev/null; then
			error=1
			error "Cannot find the %s binary required for --enroll-keys %s action." "$binary" "$this"
		fi
	done
	(( error )) && exit 1
	unset error

	check_setup_mode

	msg "Enrolling db key"
	efi-updatevar -e -f "${KEYS_DIR}/db.esl" db

	msg "Enrolling KEK key"
	efi-updatevar -e -f "${KEYS_DIR}/KEK.esl" KEK

	msg "Enrolling PK key"
	efi-updatevar -f "${KEYS_DIR}/PK.auth" PK

}

OPTSHORT="s:hvo:"
OPTLONG=('init' 'sign:' 'enroll-keys' 'no-color' 'verbose' 'secure-db' 'no-pass' 'output:' 'help' 'version')
if ! parseopts "$OPTSHORT" "${OPTLONG[@]}" -- "$@"; then
	exit 1
fi

set -- "${OPTRET[@]}"
unset OPTSHORT OPTLONG OPTRET

INIT=0
SIGN=0
ENROLL_KEYS=0

USE_COLOR='y'
VERBOSE='n'
USE_PASS='y'
SECURE_DB='n'

# Print usage when no action provided
if [[ $1 == '--' ]]; then
	usage
	exit 0
fi

while (( $# )); do
	case $1 in
		--init)		INIT=1 ;;
		-s|--sign)	SIGN=1; shift; SIGN_TARGET=$1 ;;
		--enroll-keys)	ENROLL_KEYS=1 ;;

		--no-color)	USE_COLOR='n' ;;

		--verbose)	VERBOSE='y' ;;
		--no-pass)	USE_PASS='n' ;;
		--secure-db)	SECURE_DB='y' ;;
		--output)	shift; SIGN_OUTPUT=$1 ;;
		-h|--help)	usage; exit 0 ;;
		-v|--version)	version; exit 0 ;;
	esac
	shift
done


unset ALL_OFF BOLD BLUE GREEN RED YELLOW
if [[ -t 2 && ! $USE_COLOR = "n" ]]; then
	if tput setaf 0 &>/dev/null; then
		ALL_OFF="$(tput sgr0)"
		BOLD="$(tput bold)"
		BLUE="${BOLD}$(tput setaf 4)"
		GREEN="${BOLD}$(tput setaf 2)"
		RED="${BOLD}$(tput setaf 1)"
		YELLOW="${BOLD}$(tput setaf 3)"
		CYAN="${BOLD}$(tput setaf 14)"
	else
		ALL_OFF="\e[1;0m"
		BOLD="\e[1;1m"
		BLUE="${BOLD}\e[1;34m"
		GREEN="${BOLD}\e[1;32m"
		RED="${BOLD}\e[1;31m"
		YELLOW="${BOLD}\e[1;33m"
		CYAN="${BOLD}\e[1;14m"
	fi
fi
readonly ALL_OFF BOLD BLUE GREEN RED YELLOW CYAN

if [[ $(id -u) != '0' ]]; then
	error "%s needs to run as root for all operations." "$this"
	exit 1
fi

# Check that required binaries exists
error=0
for binary in 'openssl' 'sign-efi-sig-list' 'cert-to-efi-sig-list' 'sbsign' 'uuidgen'; do
	if ! type -p $binary >/dev/null; then
		error=1
		error "Cannot find the %s binary required for all %s operations." "$binary" "$this"
	fi
done
(( error )) && exit 1
unset error

KEYS_DIR=${KEYS_DIR:-/etc/secureboot/keys}

numopt=$(( INIT + SIGN + ENROLL_KEYS ))

case $numopt in
	0)    error "no operation specified (use -h/--help for help)"; exit 1 ;;
	[!1])
		error "Multiple operations specified."
		msg "Please run %s with each operation separately." "$this"
		exit 1
		;;
esac

(( ! INIT )) && check_keys

(( INIT )) && initialize
(( SIGN )) && sign
(( ENROLL_KEYS )) && enroll_keys
