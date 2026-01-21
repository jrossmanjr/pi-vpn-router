# This project is archived and no longer in development.

# pi-vpn-router
Bash script to create a WiFi router that connects to a PIA or NordVPN using a raspberry pi

To intstall:
```
sudo apt update && sudo apt install git -y
git clone https://github.com/jrossmanjr/pi-vpn-router
cd pi-vpn-router
sudo bash install.sh
```
The program will install and then will give you several prompts for data:

---Router Gateway

---PIA or NordVPN Username and Password

---Preferred PIA US Exit node or NordVPN Exit node server name [Link](https://nordvpn.com/servers/tools/)  


When install is finished just restart - `sudo reboot`
