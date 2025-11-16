# Frigate

This script allows the automatic installation of Frigate on Debian 13 (Trixie)

In first, open console with logging in as your root logging created on Debian 13 (Trixie), then, execute the following commands

For script download
wget https://github.com/Dynaloo/Frigate/blob/main/frigate.sh

Make the script executable
chmod +x frigate.sh

Then, execute the script
./frigate.sh

Then follow the on-screen instructions...
enter the loging account name created on Debian 13 (not account root)

Then, when install is completed,
reboot
    
Then, open console with logging in as your logging created on Debian 13 (not account root)

Check the frigate directorie exist
ls -l

Go to directory frigate
cd frigate

Install Frigate
sudo docker compose up -d

Install is finish, Open your browser and enter the frigate IP address
http;//ipfrigate:5000


See the Frigate documentation to configure your first camera 
