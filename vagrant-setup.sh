#!/bin/bash

# color des
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC1='\033[0m'

cwd=$PWD
yum_update=False
__file__=$(basename $0)
log_name=$(basename $__file__ .sh).log
men_num=4096
disksize_default=50
gui_mode=true
run_mode=False
logdir=$cwd/reports
revision="$(grep 'Rev:' README.md | grep -Eo '([0-9]+\.){2}[0-9]+')"

function usage
{
    echo -en "${YELLOW}"
    more << EOF
Usage: bash $__file__ [option] argv

-h, --help                display how to use this scripts.
-v, --version             display the $__file__ version.
-r, --run                 leverage Vagrant run to start virtual machine. (default run mode: $run_mode)
-m, --men-core            specify the VM's memory size. (default: $(( $men_num / 1024 )) GB)
-vm, --vm-name            specify Virtualbox create VM's folder.
-H, --hostname            specify VM's host name.
-p, --ssh-forward         specify VM's host ssh port forwarding.
-s, --size                specify VM's disk size. (default: $disksize_default)
--yum-update              running the yum update and makecache after add new repositorys. (default: $yum_update)
--disable-guimode         disable the VM's GUI mode. (default: $gui_mode)

EOF
    echo -en "${NC1}"
    return 0
}

function precondition
{
    # set timezone
    timedatectl set-timezone Asia/Shanghai
    timedatectl set-local-rtc 0

    # disable selinux
    setenforce 0
    sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config

    # disable firewalld
    systemctl disable firewalld
    systemctl stop firewalld

    # enable ipv4 forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward

    # disable swap
    sed -i 's/[^#]\(.*swap.*\)/# \1/g' /etc/fstab
    swapoff --all

    ulimit -SHn  65536
    modprobe br_netfilter

    # import ip_conntrack modules
    modprobe ip_conntrack

    # Some users on RHEL/CentOS 7 have reported issues with traffic
    # being routed incorrectly due to iptables being bypassed
    tee /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
vm.swappiness = 10
net.ipv4.ip_nonlocal_bind = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.tcp_syncookies = 1
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv4.ip_local_port_range = 1  65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.all.arp_announce = 2
kernel.pid_max = 1000000
net.ipv4.tcp_max_tw_buckets = 20000
net.core.somaxconn = 65535
net.ipv4.tcp_tw_recycle = 0
fs.file-max = 65535
fs.nr_open = 65535
net.ipv4.tcp_fin_timeout = 30
net.netfilter.nf_conntrack_tcp_be_liberal = 1
net.netfilter.nf_conntrack_tcp_loose = 1
net.netfilter.nf_conntrack_max = 3200000
net.netfilter.nf_conntrack_buckets = 1600512
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.ipv4.tcp_max_syn_backlog = 262144
net.ipv4.tcp_timestamps = 1
kernel.msgmax = 65536
kernel.msgmnb = 163840
EOF
    sysctl --system


    # open file optimization
    tee /etc/security/limits.d/20-nofile.conf << EOF
root soft nofile 65535
root hard nofile 65535
* soft nofile 65535
* hard nofile 65535
EOF

    tee /etc/security/limits.d/20-nproc.conf << EOF
*    -     nproc   65535
root soft  nproc  unlimited
root hard  nproc  unlimited
EOF

    if [ $(cut -f1 -d ' '  /proc/modules \
           | grep -e ip_vs -e nf_conntrack_ipv4 \
           | wc -l) -ne 5 ] || [ $(lsmod | grep -e ip_vs -e nf_conntrack_ipv4 \
           | awk '{print $1}' | grep -ci p_vs) -ne 4 ]; then

        tee /etc/sysconfig/modules/ipvs.modules << EOF
#!/bin/bash
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack_ipv4
EOF
        chmod +x /etc/sysconfig/modules/ipvs.modules
        bash /etc/sysconfig/modules/ipvs.modules
    fi
}

function setuprepo
{
    local plug_file='/etc/yum.repos.d/CentOS-Base.repo'
    local epel_file='/etc/yum.repos.d/epel.repo'
    local yum_repo=(yum-plugin-priorities epel-release)

    # import virtulbox repository
    if [ -f /etc/yum.repos.d/virtualbox.repo ]; then
        cd /tmp
        wget https://www.virtualbox.org/download/oracle_vbox.asc
        rpm --import oracle_vbox.asc
        wget https://download.virtualbox.org/virtualbox/rpm/el/virtualbox.repo \
             -O /etc/yum.repos.d/virtualbox.repo
        cd $cwd
    fi

    for p in "${yum_repo[@]}"
    do
         yum install -y $p
         if [ -f $plug_file ]; then
             sed -i "s/\]$/\]\npriority=1/g" $plug_file
         elif [ -f $epel_file ]; then
             sed -i "s/\]$/\]\npriority=5/g" $epel_file
             sed -i "s/enabled=1/enabled=0/g" $epel_file
         fi
    done
    if [ "$yum_update" == "True" ]; then
        yum makecache fast
        yum update -y
    fi
    return 0
}

function installation
{
    local installpkg=$1
    yum install -y $installpkg
    if [ $? -ne 0 ] ||
       [ $(rpm -qa | grep -ci $installpkg) -ne 1 ]; then
        yum --disablerepo="*" --enablerepo=epel install $installpkg -y
    fi
}

function checkpkg
{
    local sys_regx='redhat|centos'
    local sys_version=$(python -c 'import platform; print (platform.dist()[1].lower())' \
                        | awk -F '.' '{print $1}')
    local sys_os=$(python -c 'import platform; print (platform.dist()[0].lower())' \
                   | grep -Eco $sys_regx)
    local required=(kernel-devel-$(uname -r)
                    kernel-headers
                    gcc
                    make
                    perl
                    wget
                    VirtualBox-5.1
                    vagrant
                    rsync
                    ntpdate
                    jq
                    git)
    if [ "$sys_version" != "7" ] ||
       [ $sys_os -ne 1 ]; then
        printf "%-40s [${RED} %s ${NC1}]\n" \
                " * os: $sys_os version: $sys_version " \
                " not support "
        exit 253
    fi

    for rq in "${required[@]}"
    do
        if [ $(rpm -qa | grep -ci $rq) -ne 0 ]; then
            printf "%-40s [${RED} %s ${NC1}]\n" \
                   " * required: $rq " \
                   "exist"
            continue
        else
            case $rq in
                kernel-devel-$(uname -r))
                    installation $rq
                    ;;
                VirtualBox-5.1)
                    installation $rq
                    ;;
                kernel-headers)
                    installation $rq
                    ;;
                gcc)
                    installation $rq
                    ;;
                make)
                    installation $rq
                    ;;
                perl)
                    installation $rq
                    ;;
                wget)
                    installation $rq
                    ;;
                vagrant)
                    installation $rq
                    ;;
                rsync)
                    installation $rq
                    ;;
                ntpdate)
                    installation $rq
                    ;;
            esac
        fi
    done

    if [ $(ps -ef \
           | grep -v grep \
           | grep -ci 'vagrant up') -ne 0 ]; then
        printf "%-40s [${RED} %s ${NC1}]\n" \
                   " * vagrant up process " \
                   " exist "
        exit 1
    fi
}

function checknetwork
{
    local count=0
    local network=$1
    while true
    do
        if [ "$(command -v curl)" == "" ]; then
            ping $network -c 1 -q > /dev/null 2>&1
        else
            curl $network -c 1 -q > /dev/null 2>&1
        fi
        case $? in
            0)
                printf "${BLUE} %s ${NC1} \n" "network success."
                return 0;;
            *)
                export {https,http}_proxy=$proxy

                # check fail count
                if [ $count -ge 4 ]; then
                    printf "${RED} %s ${NC1} \n" "network disconnection."
                    exit 1
                fi;;
        esac
        count=$(( count + 1 ))
    done
}

function syncntp
{
    local ntp_server='ntp.api.bz'

    # show information
    echo -en "${YELLOW}"
    more << EOF
Show NTP synchronized information
`printf '%0.s-' {1..100}; echo`

Before time: $(date '+[%F %T]')
Synchronized info: $(ntpdate -u $ntp_server)
IP Address: $(ip route get 1 | awk '{print $NF;exit}')
Hostname: $(hostname)
After time: $(date '+[%F %T]')

`printf '%0.s-' {1..100}; echo`
EOF
    echo -en "${NC1}"
}

function checkstatus
{
    case $? in
        "0")
            echo -en "${YELLOW}"
            more << "EOF"

 ________ _           _        __
|_   __  (_)         (_)      [  |
  | |_ \_|_  _ .--.  __  .--.  | |--.
  |  _| [  |[ `.-. |[  |( (`\] | .-. |
 _| |_   | | | | | | | | `'.'. | | | |
|_____| [___|___||__|___|\__) )___]|__]

EOF
            echo -en "${NC1}";;
        "1")
            echo -en "${RED}"
            more << "EOF"
 ______     _ _
 |  ____|  (_) |
 | |__ __ _ _| |
 |  __/ _` | | |
 | | | (_| | | |
 |_|  \__,_|_|_|
EOF
            echo -en "${NC1}";;
    esac
}

function installplug
{
    local vbx_version=$(vboxmanage --version | cut -c 1-3)
    local plugin_list=(vagrant-disksize
                       vagrant-proxyconf
                       vagrant-vbguest)
                       # vagrant-vbox-snapshot
    for plug in "${plugin_list[@]}"
    do
        if [ $(vagrant plugin list | grep -ci $plug) -ne 0 ]; then
            printf "%-40s [${RED} %s ${NC1}]\n" \
                   " * vagrant plugin: $plug " \
                   "exist"
            continue
        else
            vagrant plugin install $plug \
            --plugin-clean-sources \
            --plugin-source http://rubygems.org
        fi
    done
    echo -en "${YELLOW}"
    more << EOF
Show vagrant information
===========================================================================
    - Run time: $(date '+[%F %T]')
    - Vboxmanage version: $vbx_version
    - Vagrant version: $(vagrant --version | awk '{print $2}')
    - Vagrant plugin list:

$(vagrant plugin list)
===========================================================================
EOF
    echo -en "${NC1}"
}

function config
{
    if [ ! -d /root/vagrant-home/ ]; then
        mkdir -p /root/vagrant-home/
    fi

    if [ "$vmname" == "" ]; then
        printf "%-40s [${RED} %s ${NC1}]\n" \
                   " * required args vm name " \
                   " empty "
        exit 252
    fi

    if [ "$ssh_port" == "" ]; then
        printf "%-40s [${RED} %s ${NC1}]\n" \
                   " * required args ssh port not specify " \
                   " empty "
        exit 256
    elif [ $(echo $ssh_port | egrep -co '[0-9]+' | cut -c 1-4) -eq 0 ]; then
        printf "%-40s [${RED} %s ${NC1}]\n" \
                   " * required args ssh port format " \
                   " error "
        exit 256
    fi

    if [ "$host" == "" ]; then
        printf "%-40s [${RED} %s ${NC1}]\n" \
                   " * required args hostname " \
                   " empty "
        exit 254
    fi

    if [ ! -d /root/vagrant-home/$vmname ]; then
        mkdir -p /root/vagrant-home/$vmname
    else
        printf "%-40s [${RED} %s ${NC1}]\n" \
                   " * virtualbox hostname: $vmname " \
                   " already exist "
        exit 0
    fi

    if [ "$men_core" == "" ]; then
        local men_core=$men_num
    else
        local men_core=$men_core
        if [ $(echo $men_core | grep -Eco '[0-9]+') -ne 1 ] ||
           [ "$men_core" -lt "4096" ]; then
            printf "%-40s [${RED} %s ${NC1}]\n" \
                   " * invalid arguments memory size: " \
                   " $men_core "
            exit 250
        fi
    fi

    if [ "$disksize" == "" ]; then
        local disksize=$disksize_default
    else
        local disksize=$disksize
        if [ $(echo $disksize | grep -Eco '[0-9]+') -ne 1 ] ||
           [ "$disksize" -lt "50" ]; then
            printf "%-40s [${RED} %s ${NC1}]\n" \
                   " * invalid arguments disk size: " \
                   " $disksize "
            exit 257
        fi
    fi

    local host_ip=$(ip route get 1 | awk '{print $NF;exit}')
    local ssh_port=$(echo $ssh_port | cut -c 1-4)

    if [ $(netstat -ntlp | grep -co $ssh_port) -ne 0 ]; then
        printf "%-40s [${RED} %s ${NC1}]\n" \
               " * the port already exist and conflict: " \
               " $ssh_port "
        exit 250
    fi

    sed -i "s,50GB,${disksize}GB,g" $cwd/Vagrantfile
    sed -i "s,\"HOST_ADDRESS\",\"$host_ip\",g" $cwd/Vagrantfile
    sed -i "s,SSH_FORWARD,$ssh_port,g" $cwd/Vagrantfile
    sed -i "s,vb.gui\ =\ GUI_MODE,vb.gui\ =\ $gui_mode,g" $cwd/Vagrantfile
    sed -i "s,vb.memory\ =\ \"MEM\",vb.memory\ =\ \"$men_core\",g" $cwd/Vagrantfile
    sed -i "s,jay-vagrant,$host,g" $cwd/setup.sh

    cp -Rf . /root/vagrant-home/$vmname

    if [ -f /root/vagrant-home/$vmname/Vagrantfile ]; then
        if [ "$run_mode" == "True" ]; then
            cd /root/vagrant-home/$vmname
            vagrant up
            if [ "$(vagrant ssh-config \
                   | grep 'IdentityFile' \
                   | awk '{print $2}')" != "/root/vagrant-home/$vmname/key/id_rsa" ]; then
                sed -i 's,# config.ssh.private_key_path = "./key/id_rsa",config.ssh.private_key_path = "./key/id_rsa",g' \
                Vagrantfile
                sed -i 's,# config.ssh.keys_only = false,config.ssh.keys_only = false,g' Vagrantfile
                vagrant reload
            fi
            checkstatus
            cd $cwd
        fi
    fi
    return $?
}

function main
{
    precondition

    checknetwork www.google.com

    setuprepo

    checkpkg

    installplug

    config
   
    syncntp
}

if [ "$#" -eq 0 ]; then
    printf "%-40s [${RED} %s ${NC1}]\n" \
           " Invalid arguments,   " \
           "try '-h/--help' for more information"
    exit 1
fi

while [ "$1" != "" ]
do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--version)
            printf "${YELLOW} %s ${NC1}\n" "$__file__  version: ${revision}" \
                   | sed -E s',^ ,,'g
            exit 0
            ;;
        -m|--men-core)
            shift
            men_core=$1
            ;;
        -s|--size)
            shift
            disksize=$1
            ;;
        -r|--run)
            run_mode=True
            ;;
        -p|--ssh-forward)
            shift
            ssh_port=$1
            ;;
        --disable-guimode)
            gui_mode=false
            ;;
        --yum-update)
            yum_update=True
            ;;
        -H|--hostname)
            shift
            host=$1
            ;;
        -vm|--vm-name)
            shift
            vmname=$1
            ;;
        *)
            printf "%-40s [${RED} %s ${NC1}]\n" \
                   " Invalid arguments,   " \
                   "try '-h/--help' for more information"
            exit 1
            ;;
    esac
    shift
done

main | tee $logdir/$log_name

yes | cp -rf $logdir/$log_name /root/vagrant-home/$vmname/reports/
