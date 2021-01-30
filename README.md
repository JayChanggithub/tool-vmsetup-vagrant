tool-vmsetup-centos
=========================

[![](http://ipt-gitlab.ies.inventec:8000/images/vagrant_photo.jpg)](#tool-vmsetup-centos)

---

## Suitable Project
   - [x] **Linux CentOS 7.x**

---

## Version
`Rev: 1.0.5`

---

## Status

[![pipeline status](http://ipt-gitlab.ies.inventec:8081/SIT-develop-tool/tool-vmsetup-centos/badges/master/pipeline.svg)](http://ipt-gitlab.ies.inventec:8081/SIT-develop-tool/tool-vmsetup-centos/commits/master)

---

## Description

  - You must be refer to link **[Tutorial Vagrant Setup](http://ipt-gitlab.ies.inventec:8081/Gitlab/Wiki/wikis/DevOps/Vagrant)**.
  - Setup the vagrant engin in your Laptop opration system.

## Usage

  - Download project in your laptop

    ```bash
    # Download project in your laptop
    $ git clone http://ipt-gitlab.ies.inventec:8081/SIT-develop-tool/tool-vmsetup-centos.git
    $ cd ./tool-vmsetup-centos

    # Via vagrant engine to deployment VM
    $ vagrant up
    ```

  - Via vagrant engine to deployment VM

    ```bash
    $ vagrant up
    ```

  - Parameter comparison table：

    |   **Parameter**   |                 **Description**                 |
    |:-----------------:|:-----------------------------------------------:|
    |  -m, --men-core   | specify the VM's memory size. (default: 4 GB)。   |
    |  -r, --run        | leverage Vagrant run to start virtual machine. (default run mode: False)。 |
    |  -vm, --vm-name   | specify Virtualbox create VM's folder。         |
    |  -H, --hostname   | specify VM's host name。                        |
    |  -p, --ssh-forward| specify VM's host ssh port forwarding。          |
    |  --yum-update     | running the yum update and makecache after add new repositorys. (default: False)。|
    |  --disable-guimode  | disable the VM's GUI mode. (default: true)。  |
    |  -s, --size       | specify the VM's disk size. (default: 50GB)。  |


  - Via pipeline API trigeer CI to deployment the VM's

    ```bash
    $ curl -X POST \
           -F token=ad343859fc3257f0823534d539125d \
           -F "ref=master" \
           -F "variables[sut_ip]=10.99.104.251" \
           -F "variables[script_cmd]='bash vagrant-setup.sh -h'" \
           http://ipt-gitlab.ies.inventec:8081/api/v4/projects/23/trigger/pipeline
    ```

  - After update the vagrantfile type the command to reload and restart virtual machine


    ```bash
    $ vagrant reload
    ```

  - Inspect the ssh authentication method


    ```bash
    $ vagrant ssh-config

    ```

  - Inspect vagrant VM's state list

    ```bash
    $ vagrant global-status
    ```

  - Resize your root partition

    ```bash
    # Edit Vagrantfile by manually
    config.disksize.size = '70GB'
    ```

    ```bash
    # Note: this will not work with vagrant reload; if not from vagrant-setup.sh
    $ vagrant halt && vagrant up
    ```

    ```bash
    $ fdisk /dev/sda << EOF
    d
    n
    p
    1



    w
    EOF
    $ partprobe
    ```

    ```bash
    # grow up the root partitions xfs filesystem
    $ growpart /dev/sda 1
    $ xfs_growfs /
    ```

  - Via vagrant install VM's enable GUI mode

    - **[Setup Vagrant GUI mode](https://codingbee.net/vagrant/vagrant-enabling-a-centos-vms-gui-mode)** <br>

## Contact
##### Author: Jay.Chang
##### Email: cqe5914678@gmail.com
