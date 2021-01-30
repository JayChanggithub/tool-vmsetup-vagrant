vagrant up
vagrant package --output mynew.box
vagrant box add fet/centos7 mynew.box --force
vagrant destroy -f
REM del mynew.box
