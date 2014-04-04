## Automated test suite for OpenSSH configuration

When developing or fine-tuning OpenSSH configurations the testing can be quite tiresome. These scripts create a test environment where one can test various setups without deploying a server or breaking the existing SSH configuration.

I wrote it for a [Linux Magazin article about SSH key management](http://www.linux-magazin.de/Ausgaben/2013/08/SSH-Key-Management). ATM the test suite checks if [OpenSSH PKI](http://www.openssh.com/cgi-bin/cvsweb/src/usr.bin/ssh/PROTOCOL.certkeys?rev=1.9;content-type=text%2Fplain) support is present and works correctly.

### Usage

1. clone this git repo
2. change into the cloned directory
3. run `run_demo.sh` to find out if your OpenSSH supports CA-based operations.

Read the `run_demo.sh` script and look at the `*_config` files to see how to use SSH PKI.

Requirements on Ubuntu: `sudo apt-get install fakeroot sshpass checkinstall`
