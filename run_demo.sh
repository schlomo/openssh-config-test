#!/bin/bash -e

function die {
	echo 1>&2 "ERROR: $@"
	exit 1
}

[[ "$USER" != root ]] || die "Please run as user, not root"
for k in sshpass fakeroot checkinstall ; do
	if ! type -p $k >/dev/null ; then
		die "Please install $k"
	fi
done
[[ -r sshd_config  && -r ssh_config && -r passwd && -r shadow ]] || die "Some files are missing???????"
if [[ -r /etc/init.d/nscd ]] ; then
	if service nscd status ; then
		die "nscd running - tests will not work. Please turn off nscd for this test"
	fi
fi
rm -Rf keys work
mkdir work
workdir="$(pwd)"/work
sshdir="$workdir"/TRANSL/etc/ssh
mkdir -p "$sshdir"
ln -s "$sshdir" keys

myhost=$(hostname -f)
tests_ok=()

# speak English, we parse the output
export LANG=C LC_ALL=C

# generate CA key
ssh-keygen -t dsa -N "" -C "SSH PKI CA Demo" -f keys/ca
tests_ok+=(create-ca-key)

# add CA key to known_hosts and to authorized_keys
echo "@cert-authority * $(ssh-keygen -y -f keys/ca)" >keys/ssh_known_hosts
#mkdir -p work/TRANSL/ssh-pki-demo/.ssh
#echo "cert-authority $(< keys/ca.pub)" >work/TRANSL/ssh-pki-demo/.ssh/authorized_keys

# generate host key
ssh-keygen -t dsa -N "" -C "Host key for $myhost" -f keys/host_key
tests_ok+=(create-host-key)

# sign host key by CA
ssh-keygen -s keys/ca -V +53w -I "$myhost (Computer)" -h -n $myhost keys/host_key.pub
ssh-keygen -L -f keys/host_key-cert.pub
tests_ok+=(sign-host-key)

# generate user key for root
ssh-keygen -t dsa -N "" -C "User key for root" -f keys/user_key_root
tests_ok+=(create-user-root-key)

# sign user key for root
ssh-keygen -s keys/ca -V +53w -I "root@$myhost (User)" -n root keys/user_key_root.pub
ssh-keygen -L -f keys/user_key_root-cert.pub
tests_ok+=(sign-user-root-key)

# generate user key for unpriv
ssh-keygen -t dsa -N "" -C "User key for unpriv" -f keys/user_key_unpriv
tests_ok+=(create-user-unpriv-key)

# sign user key for root
ssh-keygen -s keys/ca -V +53w -I "unpriv@$myhost (User)" -n unpriv keys/user_key_unpriv.pub
ssh-keygen -L -f keys/user_key_unpriv-cert.pub
tests_ok+=(sign-user-unpriv-key)

# seed work dir for installwatch
cp -v shadow "$workdir"/TRANSL/etc
# child processes spawned by sshd ignore fakeroot and installwatch, must set real path as fake root homedir for authorized_keys to work
sed -e "s#/ssh-pki-demo#$workdir/TRANSL/ssh-pki-demo#" < passwd  > "$workdir"/TRANSL/etc/passwd
cp -v ssh_config sshd_config "$sshdir"

function cleanup {
	set +e
	echo ; echo ; echo "SSH PKI Demo Test Results:" ; echo
	test "$daemon" && kill -9 $daemon
	for t in "${tests_ok[@]}" ; do
		echo "Succeeded $t"
	done
	[[ ${tests_ok[@]:-1} == *congratulations* ]] || die "SOME TESTS FAILED! Check work/ssh.log and work/sshd.log"
}
trap cleanup 0
daemon=

function start_daemon_run_ssh {
	# $1 is label, remaining args are passed into eval and should return success
	local label="$1" ; shift
	echo ; echo "Test: $label"

	# start ssh daemon
	fakeroot installwatch -t -b -r $workdir /usr/sbin/sshd -ddd &>"$workdir/sshd.log" &
	daemon=$!

	sleep 0.2
	if ! kill -0 $daemon 2>/dev/null ; then
		daemon=
		die "FAILED TO START SSHD FOR $label, TRY killall /usr/sbin/sshd"
	fi

	# connect to our daemon and ask for date
	echo "Running $@"
	ret=0
	eval "fakeroot installwatch -t -r $workdir $@" 2>"$workdir/ssh.log" || ret=$?
	sleep 0.2
	if kill -0 $daemon 2>/dev/null ; then
		die "SSHD STILL RUNNING after $label"
	fi
	daemon=
	if (( $ret == 0 )) ; then
		tests_ok+=("$label")
	else
		die "Failed $label"
	fi
}

start_daemon_run_ssh test-trusting-known-hosts-via-cert-and-login-with-password \
	sshpass -pdemo ssh -vvv root@$myhost  date  +ssh-pki-demo_%c \| grep ssh-pki-demo

start_daemon_run_ssh test-that-hostname-in-cert-must-match-target-host \
	sshpass -pdemo ssh -vvv root@localhost  date  +ssh-pki-demo_%c \; test '$?' -gt 0

start_daemon_run_ssh test-login-with-root-key-trusted-by-cert \
	ssh -vvv -o PreferredAuthentications=publickey -i /etc/ssh/user_key_root root@$myhost  date  +ssh-pki-demo_%c \| grep ssh-pki-demo \
	"&&" grep Accepted.certificate.ID "$workdir/sshd.log"

start_daemon_run_ssh test-that-username-in-cert-must-match-target-user \
	ssh -vvv -o PreferredAuthentications=publickey -i /etc/ssh/user_key_unpriv root@$myhost  date  +ssh-pki-demo_%c \
	";" grep Permission.denied "$workdir/ssh.log"

# add our CA to RevokedKeys
echo "RevokedKeys /etc/ssh/revoked.pub" >>"$sshdir/sshd_config"
cp "$sshdir/ca.pub" "$sshdir/revoked.pub" 
start_daemon_run_ssh test-revoked-ca-key-prevents-login \
	ssh -vvv -o PreferredAuthentications=publickey -i /etc/ssh/user_key_root root@$myhost  date  +ssh-pki-demo_%c \
	";" grep Permission.denied "$workdir/ssh.log"

# put only root key to RevokedKeys
cat "$sshdir/user_key_root.pub" >"$sshdir/revoked.pub"
start_daemon_run_ssh test-revoked-user-key-prevents-login \
	ssh -vvv -o PreferredAuthentications=publickey -i /etc/ssh/user_key_root root@$myhost  date  +ssh-pki-demo_%c \
	";" grep Permission.denied "$workdir/ssh.log"

# unset RevokedKeys for further tests
echo "" >"$sshdir/revoked.pub"

# revoke host key in ssh_known_hosts
echo "@revoked * $(ssh-keygen -y -f keys/host_key)" >>"$sshdir/ssh_known_hosts"
start_daemon_run_ssh test-revoked-host-key-prevents-connection \
	ssh -vvv -o PreferredAuthentications=publickey -i /etc/ssh/user_key_root root@$myhost  date  +ssh-pki-demo_%c \
	";" grep Host.key.verification.failed "$workdir/ssh.log"

tests_ok+=("in running all tests, congratulations!")
