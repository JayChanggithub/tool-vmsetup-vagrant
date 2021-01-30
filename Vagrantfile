# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|

  config.vm.box = "centos/7"
  config.disksize.size = '50GB'
  # if want via passwd to auth, enable that
  # config.ssh.password = "vagrant"
  config.vm.network "private_network", ip: "192.168.33.10"
  config.vm.network "forwarded_port", guest: 22, host: SSH_FORWARD, host_ip: "HOST_ADDRESS", id: "ip_forward"
  config.vm.network "forwarded_port", guest: 22, host: SSH_FORWARD, host_ip: "127.0.0.1", id: "ssh"

  # Web forward configuration
  # config.vm.network "forwarded_port", guest: 3000, host: 3000, host_ip: "HOST_ADDRESS", id: "web1"
  # config.vm.network "forwarded_port", guest: 3001, host: 3001, host_ip: "HOST_ADDRESS", id: "web2"
  # config.vm.network "forwarded_port", guest: 8080, host: 9000, host_ip: "HOST_ADDRESS", id: "web3"
  # config.vm.network "forwarded_port", guest: 80, host: 9001, host_ip: "HOST_ADDRESS", id: "web4"
  # config.vm.network "forwarded_port", guest: 8000, host: 8000, host_ip: "HOST_ADDRESS", id: "web5"
  # config.vm.network "forwarded_port", guest: 8001, host: 8001, host_ip: "HOST_ADDRESS", id: "web6"
  # config.vm.network "forwarded_port", guest: 8002, host: 8002, host_ip: "HOST_ADDRESS", id: "web7"
  # config.vm.network "forwarded_port", guest: 8003, host: 8003, host_ip: "HOST_ADDRESS", id: "web8"

  config.ssh.forward_agent = true

  # via the private key to auth
  # config.ssh.private_key_path = "./key/id_rsa"
  # config.ssh.keys_only = false

  config.vm.box_download_insecure = true
  config.vm.box_check_update = false


  config.vm.provider "virtualbox" do |vb|

    # Display the VirtualBox GUI when booting the machine
    vb.gui = GUI_MODE

    # Customize the amount of memory on the VM:
    vb.memory = "MEM"
    vb.cpus = 4

  end

  # config.vm.synced_folder "../workspace", "/workspace"
  config.vm.provision "shell", path: "setup.sh"
end
