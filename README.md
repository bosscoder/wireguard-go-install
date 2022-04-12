## wireguard-go-install
WireGuard-Go installer for Ubuntu and Debian.

This script will set up your own VPN server with WireGuard-Go, a userspace implementation of WireGuard. It does not require kernel modules, hence it can be run on machines running virtually any virtualization technology. Please note, this implementation is slower than using kernel module, use that where possible.

### Installation
Download, make executable, run:  
`wget https://raw.githubusercontent.com/bosscoder/wireguard-go-install/master/wireguard-go-install.sh -O wireguard-go-install.sh && chmod +x wireguard-go-install.sh && bash wireguard-go-install.sh`

Run the script  
`./wireguard-go-install.sh`

Once it ends, you can run it again to add more users, remove some of them or even completely uninstall WireGuard-Go.

### Requirements
Debian >= 8  
Ubuntu >= 16.04  
OpenVZ/LXC/KVM
TUN Enabled

### FAQ
Q: Something isn't working, would you help?  
A: If there's something wrong with the script, submit a pull request and I'll review it ASAP.

Q: Where can I get a server?  
A: Basically any server would work. For reliable hosts, try Vultr, DigitalOcean, Linode, or BuyVM. For cheaper options, try VirMach.

Q: Do you take donations?  
A: Thanks for appreciating my work, at this time I'm doing this for fun and won't take donations directly. If you insist, I would appreciate you donating to any charitable organizations.

### Special thanks
@Daniel15 for the original instructions [https://d.sb/2019/07/wireguard-on-openvz-lxc](https://d.sb/2019/07/wireguard-on-openvz-lxc)  
@Nyr for part of the install script (yes, I'm lazy :D) [https://github.com/Nyr/wireguard-install/](https://github.com/Nyr/wireguard-install/)
