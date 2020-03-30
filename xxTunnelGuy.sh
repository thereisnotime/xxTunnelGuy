#!/bin/bash
########################################
readonly SCRIPT_NAME='xxTunnelGuy'
readonly SCRIPT_VERSION='1.9'
readonly SCRIPT_AUTHOR='thereisnotime'
########################################
# TODO:
########################################
readonly DEBUG_MODE=false
readonly SAVE_PASS=true
readonly SCRIPT_PATH=${0}
if [ "$SAVE_PASS" = true ] ; then TSPASS='TSPASSWORD'; else TSPASS='TSPASSWORD'; fi

########################################
### Helpers
########################################
function check_sudo() {
    CAN_I_RUN_SUDO=$(sudo -n uptime 2>&1|grep "load"|wc -l)
    if [ ${CAN_I_RUN_SUDO} -gt 0 ]; then
        true
    else
        false
    fi
}

function check_valid_ipv4() {
    if [[ "$1" =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]; then
        return
    else
        false
    fi
}

function get_external_ip() {
    declare -a checkers=("ip.rso.bg" "ifconfig.me" "icanhazip.com" "ipecho.net/plain" "ifconfig.co")
    local externalip="NULL"
    for i in "${checkers[@]}"
    do
        externalip=`curl $i --silent`
        if check_valid_ipv4 $externalip; then
            break
        else
            continue
        fi
    done
    printf "$externalip"
}

function check_user_exists() {
    if getent passwd $1 > /dev/null 2>&1; then
        true
    else
        false
    fi
}

function check_root() {
    if [[ $EUID -ne 0 ]]; then
        false
    else
        true
    fi
}

function log_message() {
    local currentTimestamp=`date +"%d/%m/%Y-%H:%M:%S-%Z"`
    case $2 in
        
        "ERR")
            printf '\033[31m['"$2"'] ['"$currentTimestamp"']: '"$1"'\e[0m\n'
        ;;
        
        "INFO")
            printf '\e[37m['"$2"'] ['"$currentTimestamp"']: '"$1"'\e[0m\n'
        ;;
        
        "SUCCESS")
            printf '\e[92m['"$2"'] ['"$currentTimestamp"']: '"$1"'\e[0m\n'
        ;;
        
        "WARN")
            printf '\e[33m['"$2"'] ['"$currentTimestamp"']: '"$1"'\e[0m\n'
        ;;
        
        *)
            printf '\033[31m[ERR] ['"$currentTimestamp"']: Unknown log event type parsed to log_message.\e[0m\n'
        ;;
    esac
}

function any_key() {
    printf "\n\n\e[2m---------------------------\nPress any key to return to the main menu...\e[0m"
    read -n 1 -s -r
}

function new_line () {
    printf "\n"
}

function generate_password () {
    local passLength=${1:-19}
    local result=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9=;<>./?!@#$%^&(){}[' | fold -w $passLength | head -n 1)
    echo $result
}

function get_fqdn () {
    local fqn=$(host -TtA $(hostname -s)|grep "has address"|awk '{print $1}') ; \
    if [[ "${fqn}" == "" ]] ; then fqn=$(hostname -s) ; fi ; \
    printf "${fqn}"
}

function get_script_location () {
    local SOURCE="${BASH_SOURCE[0]}"
    local DIR=""
    local SCRIPT=$(basename "$0")
    while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
        DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
        SOURCE="$(readlink "$SOURCE")"
        [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
    done
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    printf "$DIR/$SCRIPT"
}

########################################
### Menu Options
########################################
function menu_prerequisites () {
    print_header "1. Install prerequisites."
    # Check if root
    if `check_root`; then
        log_message "You are root. Good to go." "INFO"
        # Check if sudo exists
        if `check_sudo`; then
            # Enable EPEL repo for Amazon Linux 2
            sudo yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
            
            # Install toolset
            log_message "Updating system and installing toolset." "INFO"
            sudo yum update -y; sudo yum upgrade -y
            sudo yum install -y net-tools iperf3 putty iftop iotop curl
            
            # Allow password authentication
            log_message "Allowing password authentication in sshd_config." "INFO"
            sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
            sudo service sshd restart
            
            # Create tunnelconnector user
            if `check_user_exists tunnelconnector`; then
                log_message "User tunnelconnector already exists. Try changing his password." "WARN"
            else
                log_message "Creating tunnelconnector user." "INFO"
                local accountPassword=$(generate_password 22)
                sudo useradd -p $(openssl passwd -1 $accountPassword) tunnelconnector
                log_message "Your tunnelconnector user password. Please save it: $accountPassword" "SUCCESS"
            fi
            log_message "Server prepared. You can now start using it for tunneling." "SUCCESS"
        else
            log_message "You do not appear to have sudo installed. Please install it and try again." "ERR"
        fi
    else
        log_message "This command requires root or sudo start." "ERR"
    fi
    any_key
    show_menu
}

function menu_exit () {
    print "\e[4mBye!\e[0m"
    exit
}

function menu_change_password () {
    print_header "2. Change tunnelconnector password."
    if `check_root`; then
        log_message "You are root. Good to go." "INFO"
        # Check if sudo exists
        if `check_sudo`; then
            if `check_user_exists tunnelconnector`; then
                local accountPassword=$(generate_password 22)
                local salt=$(generate_password 12)
                sudo usermod -p $(openssl passwd -1 -salt $salt $accountPassword) tunnelconnector
                log_message 'Password for account tunnelconnector has been changed to '"$accountPassword"'' "SUCCESS"
                if [ "$SAVE_PASS" = true ] ; then 
                    TSPASS=$accountPassword
                    local scriptLocation="$(get_script_location)"
                    sed -i 's~then TSPASS=.*; else TSPASS~then TSPASS='$accountPassword'; else TSPASS~g' $scriptLocation
                fi
            else
                log_message "User tunnelconnector does not exist. Please run the preparation option. " "WARN"
            fi
        else 
            log_message "You do not appear to have sudo installed. Please install it and try again." "ERR"
        fi
    else
        log_message "This command requires root or sudo start." "ERR"
    fi
    any_key
    show_menu
}

function menu_generate_host () {
    local fqdn=$(get_fqdn)
    local externalIP=$(get_external_ip)
    local remotePort=1236
    local localPort=3389
    print_header "3. Generate HOST command."
    printf "To forward your port (ex. $localPort) to one on this server (ex. $remotePort) you can use one of these commands.\n"
    printf "If you want to access this port from a third machine, go to the main menu and generate a CLIENT connection command.\n"
    new_line
    print_small_header "Pure SSH"
    new_line
    printf "ssh -R \e[91m$fqdn:\e[96m$remotePort\e[39m:\e[97mlocalhost:\e[93m$localPort\e[39m tunnelconnector@\e[91m$fqdn\e[39m"
    printf "\n\n"
    print_small_header "Windows (with Putty)"
    new_line
    printf "echo y | plink -R \e[91m$fqdn\e[39m:\e[96m$remotePort\e[39m:\e[97mlocalhost:\e[93m$localPort\e[39m tunnelconnector@\e[91m$fqdn\e[39m -noagent -pw \"\e[92m$TSPASS\e[39m\""
    printf "\n\n"
    print_small_header "Linux/Unix/Android (with ssh + sshpass)"
    new_line
    printf "export SSHPASS='\e[92m$TSPASS\e[39m' && sshpass -e ssh -o StrictHostKeyChecking=\e[97mno -R \e[91m$fqdn\e[39m:\e[96m$remotePort\e[39m:\e[97mlocalhost:\e[93m$localPort\e[39m tunnelconnector@\e[91mzone07.whitezayl.com\e[39m"
    printf "\n\n"
    print_small_header "Guide"
    new_line
    printf "\e[91mSERVERIP   - The (TS) server's public IP or FQDN ($externalIP | $fqdn). \e[39m\n"
    printf "\e[96mREMOTEPORT - The tunnel server (TS) port that will lead to your LOCALPORT (ex. $remotePort). \e[39m\n"
    printf "\e[93mLOCALPORT  - Your host computer's port that needs to be accessed (ex. $localPort for RDP). \e[39m\n"
    printf "\e[92mTSPASSWORD - The account password for tunnelconnector on the TS server.\e[39m"
    any_key
    show_menu
}

function menu_generate_client () {
    print_header "4. Generate CLIENT command."
    local fqdn=$(get_fqdn)
    local externalIP=$(get_external_ip)
    local remotePort=1236
    local localPort=3389
    printf "To connect to your HOST port you can use one of these commands.\n"
    printf "Instead of localhost you can use whatever IP you want in your network.\n"
    new_line
    print_small_header "Pure SSH"
    new_line
    printf "ssh -L \e[96m$remotePort\e[39m:localhost:\e[93m$localPort\e[39m tunnelconnector@\e[91m$fqdn\e[96m"
    printf "\n\n"
    print_small_header "Windows (with Putty)"
    new_line
    printf "echo y | plink -L \e[96m$remotePort\e[39m:localhost:\e[93m$localPort\e[39m tunnelconnector@\e[91m$fqdn\e[39m -noagent -pw \"\e[92m$TSPASS\e[39m\""
    printf "\n\n"
    print_small_header "Linux/Unix/Android (with ssh + sshpass)"
    new_line
    printf "export SSHPASS='\e[92m$TSPASS\e[39m' && sshpass -e ssh -o StrictHostKeyChecking=\e[97no -L \e[96m$remotePort\e[39m:localhost:\e[93m$localPort\e[39m tunnelconnector@\e[91m$fqdn\e[39m"
    printf "\n\n"
    print_small_header "Guide"
    new_line
    printf "\e[91mSERVERIP   - The (TS) server's public IP or FQDN ($externalIP | $fqdn). \e[39m\n"
    printf "\e[96mREMOTEPORT - The tunnel server (TS) port that will lead to your LOCALPORT (ex. $remotePort). \e[39m\n"
    printf "\e[93mLOCALPORT  - Your host computer's port that needs to be accessed (ex. $localPort for RDP). \e[39m\n"
    printf "\e[92mTSPASSWORD - The account password for tunnelconnector on the TS server.\e[39m"
    any_key
    show_menu
}

function menu_list_connections () {
    print_header "5. List current connections."
    sudo netstat -tulpn | grep sshd
    sudo netstat -np --inet | grep "sshd" | grep "tunnelc"
    any_key
    show_menu
}

function menu_generate_host_persistance () {
    print_header "6. Generate HOST persistance script."
    any_key
    show_menu
}

function menu_generate_client_persistance () {
    print_header "7. Generate CLIENT persistance script."
    any_key
    show_menu
}

function menu_help () {
    print_header "8. Show help screen."
    print_small_header "Use Case"
    printf "
+----------+    +----------+    +----------+     EXAMPLE SCENARIO
|          |    |          |    |          |
|   HOST   |    |  TUNNEL  |    |  CLIENT  |     You are at work and you need to
|   YOUR   |    |  SERVER  |    |   YOUR   |     connect to your home PC's RDP server.
|  HOME PC |    |          |    |  WORK PC |     Unfortunately there are firewalls on
|          |    |          |    |          |     both sides and you can't or don't want
+----+-----+    +----------+    +-----+----+     to port forward because it is insecure.
     ^                                |
     |                                |
     |        YOUR RDP CONNECTION     |
     +--------------------------------+

+----------+    +----------+    +----------+     EXAMPLE SOLUTION
|          |    |          |    |          |
|   HOST   |    |  TUNNEL  |    |  CLIENT  |     1. You make an SSH tunnel from the HOST
|   YOUR   |    |  SERVER  |    |   YOUR   |     to the tunnel server (TS) redirecting your
|  HOME PC |    |          |    |  WORK PC |     HOST port 3389 to TS port 1235.
|          |    |          |    |          |     2. You make an SSH tunnel from the CLIENT
+--+-+-----+    +--+---+---+    +-----+-+--+     to the TS redirecting your local 1236 port
   ^ |   3380:1235 ^   ^ 1235:1236    | |        to TS port 1235.
   | +-------------+   +--------------+ |        3. You establish RDP connection from CLIENT
   |                                    |        to localhost:1236 and voila - you are now
   +------------------------------------+        connected to your HOST's RDP server via
    HOST:3389<-TS:1235<-CLIENT:1236<-RDP         two SSH tunnels.

"
    print_small_header "Notes"
    new_line
    printf "SSH tunneling is being used from many years for similair purposes. You can use it to 
connect all kinds of servers. For example if you change 'localhost' in the HOST command, you can 
also 'forward' other servers from your network. Other interesting applications can include firewall
evasion (ex. running the public SSH tunnel server on port 80)."
    any_key
    show_menu
}

function print_header () {
    tput reset
    local width=$(stty size | cut -d" " -f2)
    printf "\e[48;5;208m\e[30m"
    for (( i=1; i<=$width; i++ )); do printf "="; done 
    printf "=== $1"
    local toEnd=$(($width-(4+${#1})))
    for (( i=1; i<=$toEnd; i++ )); do printf " "; done 
    printf "\n"
    for (( i=1; i<=$width; i++ )); do printf "="; done   
    printf "\e[49m\e[39m\n\n"  
}

function print_small_header () {
    local width=$(stty size | cut -d" " -f2)
    printf "\e[48;5;208m\e[30m"
    printf '=== '"$1"''
    local toEnd=$(($width-(4+${#1})))
    for (( i=1; i<=$toEnd; i++ )); do printf " "; done  
    printf "\e[49m\e[39m\n"  
}

function exit_script() {
    printf "\n\nBye!\n\n"
    exit
}

########################################
### Main
########################################
function show_menu() {
    tput reset
    print_header "Welcome to \e[39m$SCRIPT_NAME v$SCRIPT_VERSION\e[30m by \e[39m$SCRIPT_AUTHOR\e[30m."
    printf "Select option:
  1. Install prerequisites (requires root).
  2. Change tunnelconnector password (requires root).
  3. Generate HOST command.
  4. Generate CLIENT command.
  5. List current connections.
  6. Generate HOST persistance script.
  7. Generate CLIENT persistance script.
  8. Show help screen.
  0. Exit"
    printf "\n\n\e[2m---------------------------\nYour choice [0-8]: \e[0m"
    read choice
    if [[ $choice =~ ^[0-8]$ ]]; then
            if [[ $choice == 0 ]]; then exit_script; fi
            if [[ $choice == 1 ]]; then menu_prerequisites; fi
            if [[ $choice == 2 ]]; then menu_change_password; fi
            if [[ $choice == 3 ]]; then menu_generate_host; fi
            if [[ $choice == 4 ]]; then menu_generate_client; fi
            if [[ $choice == 5 ]]; then menu_list_connections; fi
            if [[ $choice == 6 ]]; then menu_generate_host_persistance; fi
            if [[ $choice == 7 ]]; then menu_generate_client_persistance; fi
            if [[ $choice == 8 ]]; then menu_help; fi
    else
            if [ -z "$choice" ]; then
                    clear
                    show_menu
                    printf "REPLY: ${#REPLY}"
                    printf "oh -z triggered"
            else
                    clear
                    show_menu
                    printf "REPLY: ${#REPLY}"
                    printf "oh -z triggered (else)"
                    #exit 1
            fi
    fi
}
#show_mainmenu
show_menu

