#!/bin/bash -ex

type -p 
test -r sshd_config || exit 5
rm -Rf keys work
mkdir keys work

myhost=$(hostname -f)
tests_ok=()

# generate CA key
ssh-keygen -t dsa -N "" -C "SSH PKI CA Demo" -f keys/ca
tests_ok+=(create-ca-key)

# add CA key to known_hosts
echo "@cert-authority * $(ssh-keygen -y -f keys/ca)" >keys/ssh_known_hosts

# generate host key
ssh-keygen -t dsa -N "" -C "Host key for $myhost" -f keys/host_key
tests_ok+=(create-host-key)

# sign host key by CA
ssh-keygen -s keys/ca -V +53w -I $myhost -h -n $myhost keys/host_key.pub
tests_ok+=(sign-host-key)

# seed work dir for installwatch
mkdir -p work/TRANSL/etc/ssh work/TRANSL/ssh-pki-demo
cp -v shadow passwd work/TRANSL/etc
cp -v ssh_config sshd_config work/TRANSL/etc/ssh
cp -rv keys/* work/TRANSL/etc/ssh/

function cleanup {
	set +x
	echo ; echo
	echo "SSH PKI Demo Test Results:" ; echo
	test "$daemon" && kill $daemon
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
	local workdir=$(pwd)/work

	# start ssh daemon
	fakeroot installwatch -t -b -r $workdir /usr/sbin/sshd -ddd &>work/sshd.log &
	daemon=$!

	sleep 0.2
	if ! kill -0 $daemon 2>/dev/null ; then
		echo "FAILED TO START SSHD FOR $label"
		exit 1
	fi

	# connect to our daemon and ask for date
	if eval "fakeroot installwatch -t -r $workdir $@" 2>work/ssh.log ; then
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

start_daemon_run_ssh test-trusting-known-hosts-via-cert-and-login-with-password sshpass -pdemo ssh -vvv root@$myhost  date  +ssh-pki-demo_%c \| grep ssh-pki-demo
start_daemon_run_ssh test-that-hostname-in-cert-must-match sshpass -pdemo ssh -vvv root@localhost  date  +ssh-pki-demo_%c \; test '$?' -gt 0
tests_ok+=("in running all tests, congratulations!")
