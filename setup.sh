#!/bin/bash

#  Set global variables
cwd=$PWD
RED='\033[0;31m'
BLUE='\033[1;34m'
END='\033[0m'
__file__=$(basename $0)
log_name=$(basename $__file__ .sh).log
PACKAGE=(ansible
         net-tools
         vim
         openssh-server
         git2u
         gcc
         wget
         curl
         nano
         tree
         zlib-devel
         bzip2-devel
         ncurses-devel
         sqlite-devel
         ftp
         readline-devel
         tk-devel
         gdbm-devel
         db4-devel
         libpcap-devel
         xz-devel
         openssl
         openssl-devel
         cloud-utils-growpart
         xfsprogs
         ntpdate
         jq
         git)

function envrequired
{
    yum update -y; yum install upgrade -y
    curl https://setup.ius.io | sh
    for pkg in "${PACKAGE[@]}"
    do
        if [ $(rpm -qa | grep -cE "$pkg") -gt 0 ] ||
           [ "$(command -v $pkg)" != "" ]; then
            printf "\n%-40s [${BLUE} %s ${NC1}]\n" \
                   " * pakage: $pkg " \
                   " installation "
            continue
        else
            yum install $pkg -y
            if [ $(rpm -qa | grep -cE "$pkg") -eq 0 ] ||
               [ "$(command -v $pkg)" == "" ]; then
                yum --disablerepo="*" --enablerepo=epel install $pkg -y
            fi
        fi
    done
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

function sethostname
{
    if [ -f /etc/hostname ] &&
       [ "$(cat /etc/hostname | grep 'jay-vagrant')" == "" ]; then
         sed -i '1d' /etc/hostname
         echo 'jay-vagrant' > /etc/hostname
         hostname $(cat /etc/hostname)
    fi
}

function installgui
{
    if [ -f /vagrant/Vagrantfile ]; then
        local flag=$(cat /vagrant/Vagrantfile | grep 'vb.gui' \
                     | awk -F '=' '{print $2}' | tr -d ' ')
        if [ "$flag" == "false" ]; then
            return 0
        fi
    fi

    # reference to link
    # https://codingbee.net/vagrant/vagrant-enabling-a-centos-vms-gui-mode
    yum groupinstall -y 'gnome desktop'
    yum install -y 'xorg*'
    if [ $? -eq 0 ]; then
        if [ $(yum list installed \
               | grep -Eco 'initial-setup|initial-setup-gui') -ne 0 ]; then
            printf "\n%-40s [${BLUE} %s ${NC1}]\n" \
                   " * remove packages " \
                   " $(yum list installed \
                       | grep -Eo 'initial-setup|initial-setup-gui') "
            yum remove -y initial-setup initial-setup-gui
        fi
        yum remove -y initial-setup initial-setup-gui
        systemctl isolate graphical.target
        systemctl set-default graphical.target
    fi
}

function updatehost
{
    local git_ip=$1
    if [ $(cat /etc/hosts | grep -Eco "$git_ip") -ne 2 ]; then
        tee -a /etc/hosts << EOF
$git_ip registry.ipt-gitlab
$git_ip ipt-gitlab.ies.inventec
EOF
    else
        printf "\n%-40s [${BLUE} %s ${NC1}]\n" " * config already in " "/etc/hosts"
    fi
}

function setupssh
{
    local vagrant_key='/vagrant/key/id_rsa.pub'
    local host_key='/root/.ssh/authorized_keys'
    printf "\n%-40s [${BLUE} %s ${NC1}]\n" " * Setup ssh key in directory " "/root/.ssh"
    if [ ! -d /root/.ssh ]; then
        mkdir -p /root/.ssh
    fi

    if [ ! -f /root/.ssh/authorized_keys ] ||
       [ ! -f /home/vagrant/.ssh/authorized_keys ]; then
        cat $vagrant_key > $host_key
        cat $vagrant_key > $(echo $host_key | sed -E s',\/root,\/home\/vagrant,'g)
    elif [ -n "$(diff $vagrant_key $host_key)" ]; then
        cat $vagrant_key > $host_key
        cat $vagrant_key > $(echo $host_key | sed -E s',\/root,\/home\/vagrant,'g)
    fi
    printf "\n%-40s [${BLUE} %s ${NC1}]\n" " * enable ssh login from configuration " "/etc/ssh/sshd_config"
    sed -i 's|[#]*PasswordAuthentication no|PasswordAuthentication yes|g' /etc/ssh/sshd_config
    sed -i 's|[#]*PermitRootLogin yes|PermitRootLogin yes|g' /etc/ssh/sshd_config
    systemctl daemon-reload
    systemctl restart sshd
    if [ $? -ne 0 ]; then
        printf "\n%-40s [${RED} %s ${NC1}]\n" " * setup ssh setting " "error"
        return 1
    fi
    return 0
}

function gitsetup
{
    if [ -f ~/.gitmessage ]; then
        printf "\n%-40s [${RED} %s ${NC1}]\n" " * file: ~/gitmessage " "exist"
    else
        cp -rp /vagrant/.gitmessage /root/
    fi
    git config --global commit.template ~/.gitmessage
    git config --global core.editor vim
}

function vimconfig
{
    local cache='/tmp/vim.conf'
    local conf=$(cat << EOF
set tabstop=4
set shiftwidth=4
set softtabstop=4
set expandtab
set paste
EOF
)

tee $cache << eof
$conf
eof

    if [ ! -f /root/.vimrc ] ||
       [ -n "$(diff /root/.vimrc $cache)" ]; then
       tee /root/.vimrc << eof
$conf
eof
    fi
}

function setrepository
{
    local epelconfig='/etc/yum.repos.d/epel.repo'
    local centos_base='/etc/yum.repos.d/CentOS-Base.repo'

    yum install -y yum-plugin-priorities epel-release

    if [ -f $centos_base ]; then
        sed -i 's/\]$/\]\npriority=1/g' $centos_base
    fi

    if [ -f $epelconfig ]; then
        sed -i 's/\]$/\]\npriority=5/g' $epelconfig
        sed -i 's/enabled=1/enabled=0/g' $epelconfig
    fi
}

function setpython
{
    local yum_list=('/usr/bin/yum'
                    '/usr/libexec/urlgrabber-ext-down')

    if [ ! -d /usr/local/python3 ]; then
        mkdir -p /usr/local/python3
    fi

    # install python3.6
    if [ "$(command -v python3)" == "" ]; then
        printf "\n%-40s [${BLUE} %s ${NC1}]\n" " * installation " "python3"
        cd /tmp/
        wget --no-check-certificate \
        https://www.python.org/ftp/python/3.6.0/Python-3.6.0.tgz
        tar -zxvf Python-3.6.0.tgz
        cd /tmp/Python-3.6.0/
        ./configure --with-ssl --prefix=/usr/local/python3
        make; make install
        cd $cwd
    fi

    if [ "$(ls /usr/local/python3/)" != "" ]; then
        printf "\n%-40s [${BLUE} %s ${NC1}]\n" " * already installation " "python3"
        if [ ! -f '/usr/bin/python3' -o \
             ! -L '/usr/bin/python3' ]; then
           ln -s /usr/local/python3/bin/python3 /usr/bin/python3
        fi

        if [ ! -f '/usr/bin/python.bak' ]; then
            cp /usr/bin/python /usr/bin/python.bak
        fi

        if [ "$(python -c 'from sys import version_info; print (version_info[0])')" == "2" ]; then
            rm -rf /usr/bin/python
            ln -s /usr/local/python3/bin/python3 /usr/bin/python
        fi

        for f in "${yum_list[@]}"
        do
            if [ $(cat $f | sed -n '1p' | grep -coE '[1-9]\.[1-9]') -eq 0 ]; then
                sed -i '1d' $f
                sed -i '1i #! /usr/bin/python2.7' $f
            fi
        done
    fi

    # install pip3
    if [ $? -eq 0 ]; then
        cd  /tmp/
        wget --no-check-certificate \
        https://pypi.python.org/packages/source/s/setuptools/setuptools-19.6.tar.gz#md5=c607dd118eae682c44ed146367a17e26
        tar -zxvf /tmp/setuptools-19.6.tar.gz
        cd /tmp/setuptools-19.6/
        sudo python setup.py build
        sudo python setup.py install
        cd $cwd
        cd /tmp/
        wget --no-check-certificate \
        https://github.com/pypa/pip/archive/9.0.1.tar.gz
        tar -zxvf /tmp/9.0.1.tar.gz
        cd  /tmp/pip-9.0.1/
        sudo python3 setup.py install
        sudo ln -s /usr/local/python3/bin/pip /usr/bin/pip3
        sudo pip3 install \
                  --trusted-host pypi.python.org \
                  --trusted-host pypi.org \
                  --trusted-host files.pythonhosted.org \
                  --upgrade pip
        cd /tmp/Python-3.6.0/
        ./configure --with-ssl --prefix=/usr/local/python3
        sudo make; sudo make install
        sudo pip3 install \
                  --trusted-host pypi.python.org \
                  --trusted-host pypi.org \
                  --trusted-host files.pythonhosted.org \
                  -r /vagrant/requirements.txt
    fi
    return $?
}

function checknet
{
    local count=0
    local network=$1
    local USERNAME='admin'
    local PASSWORD='ZD7EdEpF9qCYpDpu'
    local proxy="http://${USERNAME}:${PASSWORD}@10.99.104.251:8081/"
    while true
    do
        if [ "$(command -v 'curl')" == "" ]; then
            ping $network -c 1 -q > /dev/null 2>&1
        else
            curl $network -c 1 -q > /dev/null 2>&1
        fi
        case $? in
            0)
                echo -e "network success.\n"
                return 0;;
            *)
                export {https,http}_proxy=$proxy

                # check fail counts
                if [ $count -ge 4 ]; then
                    echo -e "network disconnection.\n"
                    exit 1
                fi
        esac
        count=$(( count + 1 ))
    done
}

function checkstatus
{
    case $? in
        "0")
            echo -en "${BLUE}"
            more << "EOF"

 ________ _           _        __
|_   __  (_)         (_)      [  |
  | |_ \_|_  _ .--.  __  .--.  | |--.
  |  _| [  |[ `.-. |[  |( (`\] | .-. |
 _| |_   | | | | | | | | `'.'. | | | |
|_____| [___|___||__|___|\__) )___]|__]

EOF
            echo -en "${END}"
            ;;
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
            echo -en "${END}"
            ;;
    esac
}

function diskresize
{
    local criterion_size=$(lsblk \
                           | grep 'sda' \
                           | head -n 1 \
                           | awk '{print $4}' \
                           | grep -Eo '[0-9]+' \
                           | sed s',^ ,,'g)
    local root_partitions=$(lsblk \
                           | grep 'sda1' \
                           | head -n 1 \
                           | awk '{print $4}' \
                           | grep -Eo '[0-9]+' \
                           | sed s',^ ,,'g)

    if [ $criterion_size -ne $root_partitions ]; then
        growpart /dev/sda 1
        xfs_growfs /
    fi
}

function initcleanup
{
    cp -r /vagrant/banner.sh /root/
    echo 'bash /root/banner.sh' >> ~/.bashrc
    chmod +x /root/banner.sh
    sed -i 's,\r,,g' /root/banner.sh
    source /root/.bashrc
    yum clean all
    cat /dev/null > ~/.bash_history
    find /var/log -type f -exec truncate -s0 {} \;
}

function ansiblecfg
{
    if [ -f '/etc/ansible/ansible.cfg' ]; then
        sed -i 's.^#host_key_checking = False.host_key_checking = False.g' \
        /etc/ansible/ansible.cfg
    fi
}

function setupdocker
{
    local docker_js='/etc/docker/daemon.json '
    local cache='/tmp/docker_tmp.json'
    local json=$(cat << EOF
{
    "bip": "172.27.0.1/16",
    "dns": ["10.99.2.59","10.99.6.60"],
    "insecure-registries":["http://registry.ipt-gitlab:8081"],
    "live-restore": true,
    "exec-opts": ["native.cgroupdriver=systemd"],
    "log-driver": "json-file",
    "max-concurrent-downloads": 6,
    "log-opts": {
        "max-size": "10k",
        "max-file": "3"
    }
}
EOF
)
    if [ "$(command -v docker)" == "" ]; then

        printf "\n%-40s [${BLUE} %s ${NC1}]\n" " * installation daemon " "docker"

        yum install yum-utils \
                    device-mapper-persistent-data \
                    lvm2 -y
        yum-config-manager \
                --add-repo \
                https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce-17.12.1.ce-1.el7.centos

    fi
    if [ ! -d '/etc/docker' ]; then
        mkdir -p /etc/docker
    fi

    tee $cache << eof
$json
eof

    if [ ! -f $docker_js -o -n "$(diff $docker_js $cache)" ]; then
        tee $docker_js << eof
$json
eof
    fi

    if [ "$(command -v docker-compose)" == "" ]; then
        printf "\n%-40s [${BLUE} %s ${NC1}]\n" " * installation daemon " "docker-compose"
        curl -s -L \
        https://github.com/docker/compose/releases/download/1.21.2/docker-compose-$(uname -s)-$(uname -m) \
        -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
    systemctl daemon-reload
    systemctl enable docker
    systemctl start docker || systemctl restart docker
    usermod -aG docker vagrant
    docker info
    if [ $? -ne 0 ]; then
        printf "\n%-40s [${RED} %s ${NC1}]\n" " * docker daemon " "error"
        return 1
    fi
    return 0
}

function syncntp
{
    local ntp_server='ntp.api.bz'

    # show information
    echo -en "${BLUE}"
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

# main
echo -en "${BLUE}"
more << "EOF"
  ______   _____ _________   ______   ________ ____   ____ ________ _____      ___   _______
.' ____ \ |_   _|  _   _  | |_   _ `.|_   __  |_  _| |_  _|_   __  |_   _|   .'   `.|_   __ \
| (___ \_|  | | |_/ | | \_|   | | `. \ | |_ \_| \ \   / /   | |_ \_| | |    /  .-.  \ | |__) |
 _.____`.   | |     | |       | |  | | |  _| _   \ \ / /    |  _| _  | |   _| |   | | |  ___/
| \____) | _| |_   _| |_     _| |_.' /_| |__/ |   \ ' /    _| |__/ |_| |__/ \  `-'  /_| |_
 \______.'|_____| |_____|   |______.'|________|    \_/    |________|________|`.___.'|_____|

EOF
echo -en "${END}"



function main
{
    # switch root user
    sudo su -

    # disable selinux config
    # setup timezone
    # enable linux kernel configuration
    precondition

    # check the network environ
    checknet www.baidu.com

    # setup hosts for resolve
    updatehost "10.99.104.242"

    # setup hostname
    sethostname

    # setup yum repository
    setrepository

    # setup ssh root login
    setupssh

    # install relative packages for develop
    envrequired
  
    # sync the ntp server
    syncntp

    # setup the vm's GUI mode
    installgui

    # setup container engine
    setupdocker

    # setup git environ
    gitsetup

    # setup ansible ssh key no check
    ansiblecfg

    # setup vim configuration
    vimconfig

    # install python3 pip3
    setpython

    # clear cache
    initcleanup

    # resize disk
    diskresize

    # check results
    checkstatus
}

main
