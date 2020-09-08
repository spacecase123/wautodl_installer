#!/usr/bin/env bash
set -euo pipefail
#
# Copyright (c) 2017 Feral Hosting. This content may not be used elsewhere without explicit permission from Feral Hosting.
#
# This script can be used to install the autodl scripts and ruTorrent plugin. It will also run the initial configuration for them.

# Functions

autodlMenu () # user-friendly menu for installing the software
{
    echo
    echo -e "\033[36m""Autodl irssi""\e[0m"
    echo "1 Install Autodl irssi"
    echo "2 Restart Autodl irssi"
    echo "3 Troubleshoot (111) Connection refused error."
    echo "4 Uninstall Autodl irssi"
    echo "q Quit the script"
}

cronAdd () # creates a temp cron to a variable, makes the necessary files. Each software to then check to see if job exists and add if not.
{
    tmpcron="$(mktemp)"
}

portGenerator () # generates a port to use with software installs
{
    portGen=$(shuf -i 10001-32001 -n 1)
}

portCheck () # runs a check to see if the port generated can be used
{
    while [[ "$(ss -ln | grep ':'"$portGen"'' | grep -c 'LISTEN')" -eq "1" ]];
    do
        portGenerator;
    done
}

passGenerator () # generates a password for use with software installs
{
    passGen=$(< /dev/urandom tr -dc '1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz' | head -c20; echo;)
}

rutorrentCheck () # close the script if ruTorrent not installed
{
    if [[ ! -d /var/www/localhost/htdocs//rutorrent ]] # check for rutorrent - close if non-existent
    then
        echo -e "You haven't installed ruTorrent yet - please do so from the Feral software page: \nhttps://www.feralhosting.com/slots/$(hostname)/$(whoami)/software/"
        echo "Returning you to the terminal..." && sleep 3
        echo
        exit
    fi
}

while [ 1 ]
do
    autodlMenu
    echo
    read -ep "Enter the number of the option you want: " CHOICE
    echo
    case "$CHOICE" in
        "1") # install autodl
            rutorrentCheck
            pkill -u $(whoami) 'irssi' || true
            echo "Getting autodl and the plugin..."
            wget -qO ~/autodl-irssi.zip $(curl -s https://api.github.com/repos/autodl-community/autodl-irssi/releases/latest | grep 'browser_' | cut -d\" -f4) # get latest tagged release
            wget -qO ~/autodl-trackers.zip $(curl -s https://api.github.com/repos/autodl-community/autodl-trackers/releases/latest | grep 'browser_' | cut -d\" -f4)
            wget -qO ~/autodl-rutorrent.zip https://github.com/autodl-community/autodl-rutorrent/archive/master.zip # get plugin
            if [[ -f ~/.autodl/autodl.cfg ]]
            then
                echo "Backing up the old autodl.cfg..."
                cp ~/.autodl/autodl.cfg ~/.autodl/autodl.cfg.bak-"$(date +"%d.%m.%y@%H:%M:%S")"
            fi
            echo "Making the necessary files and extracting..."
            mkdir -p ~/.irssi/scripts/autorun ~/.autodl
            unzip -qo ~/autodl-irssi.zip -d ~/.irssi/scripts/
            unzip -qo ~/autodl-trackers.zip -d ~/.irssi/scripts/AutodlIrssi/trackers/
            rm -rf /var/www/localhost/htdocs/rutorrent/plugins/autodl-*
            unzip -qo ~/autodl-rutorrent.zip -d /var/www/localhost/htdocs/rutorrent/plugins/
            mv /var/www/localhost/htdocs/rutorrent/plugins/autodl-rutorrent-master /var/www/localhost/htdocs/rutorrent/plugins/autodl-irssi
            cp -f ~/.irssi/scripts/autodl-irssi.pl ~/.irssi/scripts/autorun/
            echo "Cleaning up..."
            rm -f ~/autodl-irssi.zip ~/.irssi/scripts/{README*,autodl-irssi.pl,CONTRIBUTING.md} ~/autodl-trackers.zip ~/autodl-rutorrent.zip
            echo "Configuring..."
            sed -i "s|use constant LISTEN_ADDRESS => '127.0.0.1';|use constant LISTEN_ADDRESS => '10.0.0.1';|g" ~/.irssi/scripts/AutodlIrssi/GuiServer.pm
            sed -i 's|$rtAddress = "127.0.0.1$rtAddress"|$rtAddress = "10.0.0.1$rtAddress"|g' ~/.irssi/scripts/AutodlIrssi/MatchedRelease.pm
            sed -i 's|my $scgi = new AutodlIrssi::Scgi($rtAddress, {REMOTE_ADDR => "127.0.0.1"});|my $scgi = new AutodlIrssi::Scgi($rtAddress, {REMOTE_ADDR => "10.0.0.1"});|g' ~/.irssi/scripts/AutodlIrssi/MatchedRelease.pm
            sed -i 's|if (!@socket_connect($socket, "127.0.0.1", $autodlPort))|if (!@socket_connect($socket, "10.0.0.1", $autodlPort))|g' /var/www/localhost/htdocs/rutorrent/plugins/autodl-irssi/getConf.php
            portGenerator
            portCheck
            passGenerator
            if [[ -f ~/.autodl/autodl.cfg ]] && [[ "$(tr -d "\r\n" < ~/.autodl/autodl.cfg | wc -c)" -eq 1 ]] # if the config is already populated
            then # generate port and pass for both
                sed -ri 's|(.*)gui-server-port =(.*)|gui-server-port = '"$portGen"'|g' ~/.autodl/autodl.cfg
                sed -ri 's|(.*)gui-server-password =(.*)|gui-server-password = '"$passGen"'|g' ~/.autodl/autodl.cfg
                echo -ne '<?php\n$autodlPort = '"$portGen"';\n$autodlPassword = "'"$passGen"'";\n?>' >  /var/www/localhost/htdocs/rutorrent/plugins/autodl-irssi/conf.php
            else
                echo -e "[options]\ngui-server-port = $portGen\ngui-server-password = $passGen" > ~/.autodl/autodl.cfg
                echo -ne '<?php\n$autodlPort = '"$portGen"';\n$autodlPassword = "'"$passGen"'";\n?>' > /var/www/localhost/htdocs/rutorrent/plugins/autodl-irssi/conf.php
            fi
            echo "Autodl irssi has been installed"
            echo "Adding cron task to autostart on server reboot..."
            cronAdd
            if [[ "$(crontab -l 2> /dev/null | grep -oc '^\@reboot screen -dmS autodl irssi$')" == "0" ]]
            then
                crontab -l 2> /dev/null > "$tmpcron" || true
                echo '@reboot screen -dmS autodl irssi' >> "$tmpcron"
                crontab "$tmpcron"
                rm "$tmpcron"
            else
                echo "This cron job already exists in the crontab"
                echo
            fi
            echo "Starting up Autodl irssi..."
            screen -dmS autodl irssi
            echo
            echo -e "Please refresh ruTorrent if it's open, or access it here now to configure filters for Autodl irssi: \nhttps://$(hostname).feralhosting.com/$(whoami)/rutorrent/"
            echo
            break
            ;;
        "2") # restart autodl irssi
            rutorrentCheck
            pkill -u $(whoami) 'irssi' || true
            sleep 3
            screen -dmS autodl irssi
            echo "Autodl irssi has been restarted."
            ;;
        "3") # troubleshoot autodl irssi - checks running, replaces IPs again, and ensures port and pass match between script and plugin configs
            rutorrentCheck
            echo "Ensuring ports are correctly set..."
            sed -i "s|use constant LISTEN_ADDRESS => '127.0.0.1';|use constant LISTEN_ADDRESS => '10.0.0.1';|g" ~/.irssi/scripts/AutodlIrssi/GuiServer.pm
            sed -i 's|$rtAddress = "127.0.0.1$rtAddress"|$rtAddress = "10.0.0.1$rtAddress"|g' ~/.irssi/scripts/AutodlIrssi/MatchedRelease.pm
            sed -i 's|my $scgi = new AutodlIrssi::Scgi($rtAddress, {REMOTE_ADDR => "127.0.0.1"});|my $scgi = new AutodlIrssi::Scgi($rtAddress, {REMOTE_ADDR => "10.0.0.1"});|g' ~/.irssi/scripts/AutodlIrssi/MatchedRelease.pm
            sed -i 's|if (!socket_connect($socket, "127.0.0.1", $autodlPort))|if (!socket_connect($socket, "10.0.0.1", $autodlPort))|g' /var/www/localhost/htdocs/rutorrent/plugins/autodl-irssi/getConf.php
            echo "Ensuring the ports and passwords are configured properly..."
            portGenerator
            portCheck
            passGenerator
            if [[ -f ~/.autodl/autodl.cfg ]] && [[ "$(tr -d "\r\n" < ~/.autodl/autodl.cfg | wc -c)" -ne 0 ]] # if the config is already populated
            then # generate port and pass for both
                sed -ri 's|(.*)gui-server-port =(.*)|gui-server-port = '"$portGen"'|g' ~/.autodl/autodl.cfg
                sed -ri 's|(.*)gui-server-password =(.*)|gui-server-password = '"$passGen"'|g' ~/.autodl/autodl.cfg
                echo -ne '<?php\n$autodlPort = '"$portGen"';\n$autodlPassword = "'"$passGen"'";\n?>' > /var/www/localhost/htdocs/rutorrent/plugins/autodl-irssi/conf.php
            else
                echo -e "[options]\ngui-server-port = $portGen\ngui-server-password = $passGen" > ~/.autodl/autodl.cfg
                echo -ne '<?php\n$autodlPort = '"$portGen"';\n$autodlPassword = "'"$passGen"'";\n?>' > /var/www/localhost/htdocs/
            fi
            echo "Restarting Autodl irssi..."
            pkill -u $(whoami) 'irssi' || true
            sleep 3
            screen -dmS autodl irssi
            echo "Please refresh your ruTorrent now."
            ;;
        "4") # uninstall autodl irssi
            echo -e "Uninstalling Autodl irssi will" "\033[31m""remove the software and the config files""\e[0m"
            read -ep "Are you sure you want to uninstall? [y] yes or [n] no: " CONFIRM
            if [[ $CONFIRM =~ ^[Yy]$ ]]
            then
                pkill -u $(whoami) 'SCREEN -dmS autodl irssi' || true
                sleep 2 # kill autodl and wait
                rm -rf ~/.autodl ~/.irssi /var/www/localhost/htdocs/rutorrent/plugins/autodl-irssi # remove directories
                crontab -u $(whoami) -l | grep -v '@reboot screen -dmS autodl irssi' | crontab -u $(whoami) - # remove from crontab
                echo "Autodl irssi has been removed."
            else
                echo "Taking no action..."
                echo
            fi
            ;;
        "q") # quit the script
            exit
            ;;
    esac
done
