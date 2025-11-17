# Frigate

**This script allows the automatic installation of Frigate on Debian 13 (Trixie)**

# Prerequisites

**Install Debian 13 on your computer (or virtualize it on Proxmox, for example)**

If virtualizing, configure a passthrough for the integrated graphics processor (IGPU)

# Installation

In first, open console with logging in as your **root** logging created on Debian 13 (Trixie), then, execute the following commands

For script download

    wget https://github.com/Dynaloo/Frigate/blob/main/install_frigate.sh

Make the script executable

    chmod +x install_frigate.sh

Then, execute the script

    ./install_frigate.sh

Then follow the on-screen instructions...

When asked, enter your loging account name created on Debian 13 (**not account root**)

Then, when install is completed,

    reboot
    
Then, reconnect to the console using username and password (**not account root**) you created on Debian 13.

Check the frigate directorie exist

    ls -l

Go to directory frigate

    cd frigate

Install Frigate

    sudo docker compose up -d

**Install is finish, open your browser and enter your frigate IP address**

    http://your_ip_frigate:5000


***See the Frigate documentation to configure your first camera***

See exemple enclosed "Config Frigate.yaml"
