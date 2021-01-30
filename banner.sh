#!/bin/bash
RED='\033[1;31m'
BLUE='\033[1;34m'
END='\033[0m'
echo -en "${BLUE}"
more << "EOF"

████████╗ █████╗     ████████╗███████╗ █████╗ ███╗   ███╗
╚══██╔══╝██╔══██╗    ╚══██╔══╝██╔════╝██╔══██╗████╗ ████║
   ██║   ███████║       ██║   █████╗  ███████║██╔████╔██║
   ██║   ██╔══██║       ██║   ██╔══╝  ██╔══██║██║╚██╔╝██║
   ██║   ██║  ██║       ██║   ███████╗██║  ██║██║ ╚═╝ ██║
   ╚═╝   ╚═╝  ╚═╝       ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝
EOF
echo -en "${END}"
echo -en "${RED}"
more << "EOF"
WARNING:
    1. This VMs is use vagrant build centos enviroments for TA-SIT develop, Every changed
       will be vagrant reload.
    2. Please remember to setup the git config when you start use git command to operate the repository.
EOF
echo -en "${END}"
echo -en "${RED}"
more << "EOF"
Service:
    - Running service on this operation system:
      1. docker
      2. vsftpd
      3. git
      4. Ansible
      5. Python3.6
Package:
    - Below listed packages are installed in the image:
      1. Python2.7 & Python3.6 (pip)
      2. ansible
      3. Git, Gitlab-API
      4. gcc, ftp, curl, wget, vim, tree, openssh-server
EOF
echo -en "${END}"
