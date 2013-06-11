#!/bin/bash -ex
#
# Requirements: sudo apt-get install fakeroot sshpass checkinstall
#
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
ssh-keygen -s keys/ca -V +53w -I $myhost -h keys/host_key.pub
tests_ok+=(sign-host-key)

# seed work dir for installwatch
mkdir -p work/TRANSL/etc work/TRANSL/ssh-pki-demo
cp -rv etc work/TRANSL/
cp -rv keys/* work/TRANSL/etc/ssh/

function cleanup {
	set +x
	test "$daemon" && kill $daemon
	for t in ${tests_ok[@]} ; do
		echo "Succeeded $t"
	done
}

# start ssh daemon
trap cleanup 0
xterm -title "sshd - SSH PKI Demo" -e bash -c "fakeroot installwatch -t -b -r $(pwd)/work /usr/sbin/sshd -ddd 2>&1 | tee work/sshd.log"&
daemon=$!

sleep 1
kill -0 $daemon && tests_ok+=(start-private-sshd-daemon)

# connect to our daemon and ask for date
test_label=test-known-hosts-via-cert-and-login-with-password
if fakeroot installwatch -t -r $(pwd)/work sshpass -pdemo ssh -vvv -p 2222 root@$myhost date  +ssh-pki-demo_%c | grep ssh-pki-demo ; then
	tests_ok+=($test_label)
	daemon=
else
	echo "failed $test_label"
	exit 1
fi