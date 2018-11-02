#! /bin/bash

# Find the rows and columns will default to 80x24 is it can not be detected
screen_size=$(stty size 2>/dev/null || echo 24 80) 
rows=$(echo $screen_size | awk '{print $1}')
columns=$(echo $screen_size | awk '{print $2}')

# Divide by two so the dialogues take up half of the screen, which looks nice.
r=$(( rows / 2 ))
c=$(( columns / 2 ))
# Unless the screen is tiny
r=$(( r < 20 ? 20 : r ))
c=$(( c < 70 ? 70 : c ))

if [[ $EUID -eq 0 ]];then
  echo "::: You are root."
else
  echo "::: sudo will be used."
  # Check if it is actually installed
  # If it isn't, exit because the install cannot complete
  if [[ $(dpkg-query -s sudo) ]];then
    export SUDO="sudo"
  else
    echo "::: Please install sudo or run this script as root."
    exit 1
  fi
fi

echo "

'########::'####::::'##::::'##:'########::'##::: ##::::'########:::'#######::'##::::'##:'########:'########:'########::
 ##.... ##:. ##::::: ##:::: ##: ##.... ##: ###:: ##:::: ##.... ##:'##.... ##: ##:::: ##:... ##..:: ##.....:: ##.... ##:
 ##:::: ##:: ##::::: ##:::: ##: ##:::: ##: ####: ##:::: ##:::: ##: ##:::: ##: ##:::: ##:::: ##:::: ##::::::: ##:::: ##:
 ########::: ##::::: ##:::: ##: ########:: ## ## ##:::: ########:: ##:::: ##: ##:::: ##:::: ##:::: ######::: ########::
 ##.....:::: ##:::::. ##:: ##:: ##.....::: ##. ####:::: ##.. ##::: ##:::: ##: ##:::: ##:::: ##:::: ##...:::: ##.. ##:::
 ##::::::::: ##::::::. ## ##::: ##:::::::: ##:. ###:::: ##::. ##:: ##:::: ##: ##:::: ##:::: ##:::: ##::::::: ##::. ##::
 ##::::::::'####::::::. ###:::: ##:::::::: ##::. ##:::: ##:::. ##:. #######::. #######::::: ##:::: ########: ##:::. ##:
..:::::::::....::::::::...:::::..:::::::::..::::..:::::..:::::..:::.......::::.......::::::..:::::........::..:::::..::

A huge thanks to zentralwerkstatt, superjamie, and StarshipEngineer on their similar projects...

Created by jrossmanjr -- https://github.com/jrossmanjr
"

function update_install() {
# UPDATE and install software
echo "::: Welcome to the VPN configurator... :::"
echo "::: Updating and installing dependancies :::"
$SUDO apt-get update 
$SUDO apt-get upgrade -y 
$SUDO apt-get install isc-dhcp-server hostapd openvpn iptables-persistent unzip ca-certificates -y 
$SUDO wget http://www.fars-robotics.net/install-wifi -O /usr/bin/install-wifi
$SUDO chmod +x /usr/bin/install-wifi
$SUDO install-wifi

echo "::: Installs complete :::"
}

############################################################

function network_settings() {
# change interfaces 
# get ipaddress variable
_IP=$(hostname -I) || true
# text box for gateway ipaddress
var3=$(whiptail --inputbox "Please enter your default Gateway [Router's IP] " ${r} ${c} 192.168.1.1 --title "Gateway" 3>&1 1>&2 2>&3)

echo "
auto lo
iface lo inet loopback

auto eth0
allow-hotplug eth0
iface eth0 inet static
address $_IP
netmask 255.255.255.0
gateway $var3

# Do not send SSH traffic through the tunnel
up ip rule add fwmark 65 table novpn
up ip route add default via $var3 dev eth0 table novpn
up ip route flush cache

auto wlan0
allow-hotplug wlan0
iface wlan0 inet static
# The IP range for our VPN wifi is 192.168.42.2 -> .40
address 192.168.42.1
netmask 255.255.255.0" | $SUDO tee --append /etc/network/interfaces > /dev/null

$SUDO sysctl -w net.ipv6.conf.all.disable_ipv6=1
$SUDO sysctl -w net.ipv6.conf.default.disable_ipv6=1

echo "::: Updated Network Interfaces :::" 
}

############################################################

function hostapd() {
# add settings to hostapd
echo "
authoritative;

subnet 192.168.42.0 netmask 255.255.255.0 {
  range 192.168.42.2 192.168.42.40;
  option broadcast-address 192.168.42.255;
  option routers 192.168.42.1;
  option domain-name "local";
  option domain-name-servers 1.1.1.1, 8.8.4.4;
}" | $SUDO tee --append /etc/dhcp/dhcpd.conf > /dev/null

echo "::: Installed WiFi hotspot rules :::"
}

############################################################

function dhcp() {
# set dhcp server for wlan0
echo 'INTERFACESv4="wlan0"' | $SUDO tee /etc/default/isc-dhcp-server > /dev/null

# set hostapd files
var4=$(whiptail --inputbox "Name the WiFi Hotspot" ${r} ${c} VPN_Connection --title "Wifi Name" 3>&1 1>&2 2>&3)
var5=$(whiptail --inputbox "Please enter a password for the WiFi hotspot" ${r} ${c} --title "WiFi Password" 3>&1 1>&2 2>&3)

$SUDO echo 'interface=wlan0
driver=nl80211
ctrl_interface=/var/run/Hostapd
ctrl_interface_group=0
hw_mode=g
channel=1
#ieee80211d=1
#country_code=US
ieee80211n=1
wmm_enabled=1
beacon_int=100
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP' > /etc/hostapd/hostapd.conf

echo "ssid=$var4" | sudo tee --append /etc/hostapd/hostapd.conf > /dev/null
echo "wpa_passphrase=$var5" | sudo tee --append /etc/hostapd/hostapd.conf > /dev/null

echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' | sudo tee --append /etc/default/hostapd > /dev/null
echo "::: WiFi Hotspot Created :::"
}

############################################################

function pia_password_file() {
# make a password file
var1=$(whiptail --inputbox "Please enter your PIA VPN Username" ${r} ${c} --title "PIA Username" 3>&1 1>&2 2>&3)
var2=$(whiptail --inputbox "Please enter PIA VPN Password" ${r} ${c} --title "PIA Password" 3>&1 1>&2 2>&3)
$SUDO touch /etc/openvpn/pass.txt
echo "$var1" | $SUDO tee --append /etc/openvpn/pass.txt > /dev/null
echo "$var2" | $SUDO tee --append /etc/openvpn/pass.txt > /dev/null

echo "::: Password File Generated :::"
}

############################################################

function pia_setup() {
# download the OPENVPN files from PIA
wget https://www.privateinternetaccess.com/openvpn/openvpn.zip
unzip openvpn.zip -d openvpn
$SUDO cp openvpn/ca.rsa.2048.crt openvpn/crl.rsa.2048.pem /etc/openvpn/

# Change default openvpn settings config
echo '
AUTOSTART="all"
OPTARGS=""
OMIT_SENDSIGS=0' | $SUDO tee /etc/default/openvpn > /dev/null

whiptail --msgbox --title "NOTE: as of the writing of this program this only uses:" "\nThe 14 PIA servers in the US as exit nodes..." ${r} ${c}

var9=$(whiptail --title "What end node location do you want to use?" --radiolist "Select an exit point" ${r} ${c} 16 \
"1" "US California" OFF \
"2" "US Chicago" OFF \
"3" "US Denver" OFF \
"4" "US East" OFF \
"5" "US Florida" OFF \
"6" "US Houston" OFF \
"7" "US Las Vegas" OFF \
"8" "US Atlanta" OFF \
"9" "US New York City" OFF \
"10" "US Seattle" OFF \
"11" "US Silicon Valley" OFF \
"12" "US Texas" OFF \
"13" "US Washington DC" OFF \
"14" "US West" OFF 3>&1 1>&2 2>&3)

if [ $var9 = 1 ]; then
$SUDO cp openvpn/US\ California.ovpn openvpn/vpn.conf
else
	if [ $var9 = 2 ]; then
    $SUDO cp openvpn/US\ Chicago.ovpn openvpn/vpn.conf
	else
    	if [ $var9 = 3 ]; then
    	$SUDO cp openvpn/US\ Denver.ovpn openvpn/vpn.conf
		else
    		if [ $var9 = 4 ]; then
    		$SUDO cp openvpn/US\ East.ovpn openvpn/vpn.conf    	
    		else
    			if [ $var9 = 5 ]; then
    			$SUDO cp openvpn/US\ Florida.ovpn openvpn/vpn.conf		
    			else 
    				if [ $var9 = 6 ]; then
    				$SUDO cp openvpn/US\ Houston.ovpn openvpn/vpn.conf
    				else
 		   				if [ $var9 = 7 ]; then
    					$SUDO cp openvpn/US\ Las\ Vegas.ovpn openvpn/vpn.conf
    					else
			    			if [ $var9 = 8 ]; then
    						$SUDO cp openvpn/US\ Atlanta.ovpn openvpn/vpn.conf
    						else	
    							if [ $var9 = 9 ]; then
    							$SUDO cp openvpn/US\ New\ York\ City.ovpn openvpn/vpn.conf
    							else	
    								if [ $var9 = 10 ]; then
    								$SUDO cp openvpn/US\ Seattle.ovpn openvpn/vpn.conf
		    						else
		    							if [ $var9 = 11 ]; then
    									$SUDO cp openvpn/US\ Silicon\ Valley.ovpn openvpn/vpn.conf
    	    							else
    	    								if [ $var9 = 12 ]; then
    										$SUDO cp openvpn/US\ Texas.ovpn openvpn/vpn.conf
    	    								else
    	    									if [ $var9 = 13 ]; then
    											$SUDO cp openvpn/US\ Washington\ DC.ovpn openvpn/vpn.conf
    	    									else
    	    										if [ $var9 = 14 ]; then
    												$SUDO cp openvpn/US\ West.ovpn openvpn/vpn.conf
    	    										else 
    	    										echo "im lost..."
    	    										fi
    	    									fi
    	    								fi
    	    							fi
    	    						fi
    	    					fi
    	    				fi
    	    			fi
    	    		fi
    	    	fi
    	    fi 
    	fi
    fi 
fi

# edit openvpn conf file
#$SUDO sed 's+ca.rsa.2048.crt+/etc/openvpn/ca.rsa.2048.crt+g' /etc/openvpn/vpn.conf 
#$SUDO sed 's+crl.rsa.2048.pem+/etc/openvpn/crl.rsa.2048.pem+g' /etc/openvpn/vpn.conf 
$SUDO chown -R pi:pi openvpn/*
$SUDO chmod -R 775 openvpn/
$SUDO sed -i.bak "s+auth-user-pass+auth-user-pass /etc/openvpn/pass.txt+g" openvpn/vpn.conf
$SUDO cp openvpn/vpn.conf /etc/openvpn/vpn.conf

echo "::: OPENVPN and PIA Servers configured :::"
}


############################################################
# Nordvpn password 

function nord_password_file() {
# make a password file
var7=$(whiptail --inputbox "Please enter your NordVPN Username" ${r} ${c} --title "NordVPN Username" 3>&1 1>&2 2>&3)
var6=$(whiptail --inputbox "Please enter NordVPN Password" ${r} ${c} --title "NordVPN Password" 3>&1 1>&2 2>&3)
$SUDO touch /etc/openvpn/pass.txt
echo "$var7" | $SUDO tee --append /etc/openvpn/pass.txt > /dev/null
echo "$var6" | $SUDO tee --append /etc/openvpn/pass.txt > /dev/null

echo "::: Password File Generated :::"
}


############################################################
# Nordvpn files

function nord_setup() {
# download the OPENVPN files from NordVPN
wget https://downloads.nordcdn.com/configs/archives/servers/ovpn.zip
unzip ovpn.zip -d openvpn
nord=$(whiptail --inputbox "For best server -- https://nordvpn.com/servers/" ${r} ${c} --title "Enter Nord Server Name - usXXXX.nordvpn.com" 3>&1 1>&2 2>&3)
$SUDO cp openvpn/ovpn_tcp/$nord.udp.ovpn openvpn/vpn.conf

# edit openvpn conf file
$SUDO chown -R pi:pi openvpn/*
$SUDO chmod -R 775 openvpn/
$SUDO sed -i.bak "s+auth-user-pass+auth-user-pass /etc/openvpn/pass.txt+g" openvpn/vpn.conf
$SUDO cp openvpn/vpn.conf /etc/openvpn/vpn.conf

# Change default openvpn settings config
echo '
AUTOSTART="all"
OPTARGS=""
OMIT_SENDSIGS=0' | $SUDO tee /etc/default/openvpn > /dev/null

echo "::: OPENVPN and NordVPN Servers configured :::"
}


############################################################

function ip_tables() {
# setup iptables to route traffic from wlan0 thru vpn 

$SUDO sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
echo -e '\n#Enable IP Routing\nnet.ipv4.ip_forward = 1' | $SUDO tee -a /etc/sysctl.conf
$SUDO iptables -P INPUT ACCEPT
$SUDO iptables -P FORWARD ACCEPT
$SUDO iptables -P OUTPUT ACCEPT
$SUDO iptables -t nat -F
$SUDO iptables -t mangle -F
$SUDO iptables -F
$SUDO iptables -X
$SUDO iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
$SUDO iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
$SUDO iptables -A FORWARD -s 192.168.42.0/24 -i wlan0 -o eth0 -m conntrack --ctstate NEW -j REJECT
$SUDO iptables -A FORWARD -s 192.168.42.0/24 -i wlan0 -o tun0 -m conntrack --ctstate NEW -j ACCEPT

# allow SSH so you can update 
$SUDO iptables -t mangle -A OUTPUT -p tcp --sport 22 -j MARK --set-mark 65
echo "::: IP tables Set! :::"
# save the iptables you just edited and have them apply at startup
$SUDO sh -c "iptables-save > /etc/iptables/rules.v4"
$SUDO netfilter-persistent save
}

#############################################################
#Mission Complete notification 

function mission_complete() {
echo "::: Installer is finished - PLEASE REBOOT :::"
}

############################################################
# VPN Selection

function vpn_selection() {
var8=$(whiptail --title "Choose VPN Provider" --menu "Choose an option" ${r} ${c} 4 \
"PIA" "Private Internet Access"\
"Nord" "NordVPN" 3>&1 1>&2 2>&3)

if [ $var9 = "PIA" ]; then
pia_password_file
pia_setup
else
nord_password_file
nord_setup
}

#############################################################
# Call the Functions

update_install
network_settings
hostapd
dhcp
vpn_selection
#pia_password_file
#pia_setup
ip_tables
mission_complete

