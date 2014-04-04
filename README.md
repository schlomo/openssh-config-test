## Automated test suite for OpenSSH configuration
![Logo](https://docs.google.com/drawings/d/1BcVvEycrTL7N2WwUqqjA1Uqe4KzM36UvT6fy8tIUg70/pub?w=476)

When developing or fine-tuning OpenSSH configurations the testing can be quite tiresome. These scripts create a test environment where one can test various setups without deploying a server or breaking the existing SSH configuration.

I wrote it for a [Linux Magazin article about SSH key management](http://www.linux-magazin.de/Ausgaben/2013/08/SSH-Key-Management). ATM the test suite checks if [OpenSSH PKI](http://www.openssh.com/cgi-bin/cvsweb/src/usr.bin/ssh/PROTOCOL.certkeys?rev=1.9;content-type=text%2Fplain) support is present and works correctly.

### Usage

1. clone this git repo
2. change into the cloned directory
3. run `run_demo.sh` to find out if your OpenSSH supports CA-based operations:

```
$ ./run_demo.sh
   ... lots of info output running through ... 
SSH PKI Demo Test Results:
Succeeded create-ca-key
Succeeded create-host-key
Succeeded sign-host-key
Succeeded create-user-root-key
Succeeded sign-user-root-key
Succeeded create-user-unpriv-key
Succeeded sign-user-unpriv-key
Succeeded test-trusting-known-hosts-via-cert-and-login-with-password
Succeeded test-that-hostname-in-cert-must-match-target-host
Succeeded test-login-with-root-key-trusted-by-cert
Succeeded test-that-username-in-cert-must-match-target-user
Succeeded test-revoked-ca-key-prevents-login
Succeeded test-revoked-user-key-prevents-login
Succeeded test-revoked-host-key-prevents-connection
Succeeded in running all tests, congratulations!
```


Read the `run_demo.sh` script and look at the `*_config` files to see how to use SSH PKI.

Requirements on Ubuntu: `sudo apt-get install fakeroot sshpass checkinstall`
