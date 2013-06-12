#!/bin/bash -e

test "$USER" = root && exit 5
for k in sshpass fakeroot checkinstall ; do
	if ! type -p $k >/dev/null ; then
		echo "Please install $k"
		exit 5
	fi
done
test -r sshd_config || exit 5
rm -Rf keys work
mkdir keys work
workdir=$(pwd)/work

myhost=$(hostname -f)
tests_ok=()

set -x
# generate CA key
ssh-keygen -t dsa -N "" -C "SSH PKI CA Demo" -f keys/ca
tests_ok+=(create-ca-key)

# add CA key to known_hosts and to authorized_keys
echo "@cert-authority * $(ssh-keygen -y -f keys/ca)" >keys/ssh_known_hosts
mkdir -p work/TRANSL/ssh-pki-demo/.ssh
echo "cert-authority $(< keys/ca.pub)" >work/TRANSL/ssh-pki-demo/.ssh/authorized_keys

# generate host key
ssh-keygen -t dsa -N "" -C "Host key for $myhost" -f keys/host_key
tests_ok+=(create-host-key)

# sign host key by CA
ssh-keygen -s keys/ca -V +53w -I $myhost -h -n $myhost keys/host_key.pub
tests_ok+=(sign-host-key)

# generate user key for root
ssh-keygen -t dsa -N "" -C "User key for root" -f keys/user_key_root
tests_ok+=(create-user-root-key)

# sign user key for root
ssh-keygen -s keys/ca -V +53w -I root@$myhost -n root keys/user_key_root.pub
tests_ok+=(sign-user-root-key)

# generate user key for unpriv
ssh-keygen -t dsa -N "" -C "User key for unpriv" -f keys/user_key_unpriv
tests_ok+=(create-user-unpriv-key)

# sign user key for root
ssh-keygen -s keys/ca -V +53w -I unpriv@$myhost -n unpriv keys/user_key_unpriv.pub
tests_ok+=(sign-user-unpriv-key)

# seed work dir for installwatch
mkdir -p $workdir/TRANSL/etc/ssh 
cp -v shadow passwd $workdir/TRANSL/etc
# child processes spawned by sshd ignore fakeroot and installwatch, must set real path as fake root homedir for authorized_keys to work
sed -e "s#/ssh-pki-demo#$workdir/TRANSL/ssh-pki-demo#" -i $workdir/TRANSL/etc/passwd
cp -v ssh_config sshd_config $workdir/TRANSL/etc/ssh
cp -rv keys/* $workdir/TRANSL/etc/ssh/

function cleanup {
	set +x +e
	echo ; echo
	echo "SSH PKI Demo Test Results:" ; echo
	test "$daemon" && kill -9 $daemon
	for t in "${tests_ok[@]}" ; do
		echo "Succeeded $t"
	done
	[[ ${tests_ok[@]:-1} == *congratulations* ]] || echo "SOME TESTS FAILED! Check work/ssh.log and work/sshd.log"
}
trap cleanup 0
daemon=

function start_daemon_run_ssh {
	# $1 is label, remaining args are passed into eval and should return success
	local label="$1" ; shift

	# start ssh daemon
	fakeroot installwatch -t -b -r $workdir /usr/sbin/sshd -ddd &>$workdir/sshd.log &
	daemon=$!

	sleep 0.2
	if ! kill -0 $daemon 2>/dev/null ; then
		echo "FAILED TO START SSHD FOR $label"
		daemon=
		exit 1
	fi

	# connect to our daemon and ask for date
	if eval "fakeroot installwatch -t -r $workdir $@" 2>$workdir/ssh.log ; then
		tests_ok+=("$label")
		sleep 0.2
		if kill -0 $daemon 2>/dev/null ; then
			echo "SSHD STILL RUNNING after $label"
			exit 1
		fi
		daemon=
	else
		exit 1
	fi
}

start_daemon_run_ssh test-trusting-known-hosts-via-cert-and-login-with-password \
	sshpass -pdemo ssh -vvv root@$myhost  date  +ssh-pki-demo_%c \| grep ssh-pki-demo

start_daemon_run_ssh test-that-hostname-in-cert-must-match-target-host \
	sshpass -pdemo ssh -vvv root@localhost  date  +ssh-pki-demo_%c \; test '$?' -gt 0

start_daemon_run_ssh test-login-with-root-key-trusted-by-cert \
	ssh -vvv -o PreferredAuthentications=publickey -i /etc/ssh/user_key_root root@$myhost  date  +ssh-pki-demo_%c \| grep ssh-pki-demo \
	"&&" grep Accepted.certificate.ID $workdir/sshd.log

start_daemon_run_ssh test-that-username-in-cert-must-match-target-user \
	ssh -vvv -o PreferredAuthentications=publickey -i /etc/ssh/user_key_unpriv root@$myhost  date  +ssh-pki-demo_%c \| grep ssh-pki-demo \
	";" grep Permission.denied $workdir/ssh.log


tests_ok+=("in running all tests, congratulations!")
