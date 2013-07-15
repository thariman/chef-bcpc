#!/bin/bash -e

if [[ "$OSTYPE" == msys || "$OSTYPE" == cygwin ]]; then
  WIN=TRUE
fi

set -x

if [[ -f ./proxy_setup.sh ]]; then
  . ./proxy_setup.sh
fi

if [[ -z "$CURL" ]]; then
  echo "CURL is not defined"
  exit
fi

VBM=VBoxManage
DRIVE_SIZE=20480

DIR=`dirname $0`/vbox

pushd $DIR

P=`python -c "import os.path; print os.path.abspath('./')"`

if ! hash $VBM ; then
  echo "You do not appear to have $VBM from VirtualBox"
  exit 1
fi

# Can we create the bootstrap VM via Vagrant
if hash vagrant ; then
  echo "Vagrant detected - using Vagrant to initialize bcpc-bootstrap"
  echo "N.B. This may take approximately 30-45 minutes to complete."
  
  cp ../Vagrantfile .
  if [[ ! -f insecure_private_key ]]; then
    # Ensure that the private key has been created by running vagrant at least once
    vagrant -v
    cp $HOME/.vagrant.d/insecure_private_key .
  fi
  vagrant up
else
  echo "Vagrant not detected - using raw VirtualBox for bcpc-bootstrap"
  if [[ -z "WIN" ]]; then
    # Make the three BCPC networks we'll need, but clear all nets and dhcpservers first
    for i in 0 1 2 3 4 5 6 7 8 9; do
      if [[ ! -z `$VBM list hostonlyifs | grep vboxnet$i | cut -f2 -d" "` ]]; then
        $VBM hostonlyif remove vboxnet$i || true
      fi
    done
  else
    # On Windows the first interface has no number
    # The second interface is #2
    # Remove in reverse to avoid substring matching issue
    for i in 10 9 8 7 6 5 4 3 2 1; do
      if [[ i -gt 1 ]]; then
        IF="VirtualBox Host-Only Ethernet Adapter #$i";   
      else
	IF="VirtualBox Host-Only Ethernet Adapter";
      fi
      if [[ ! -z `$VBM list hostonlyifs | grep "$IF"` ]]; then
	$VBM hostonlyif remove "$IF"
      fi
    done
  fi
	      
  if [[ ! -z `$VBM list dhcpservers` ]]; then
    $VBM list dhcpservers | grep NetworkName | awk '{print $2}' | xargs -n1 $VBM dhcpserver remove --netname
  fi

  $VBM hostonlyif create
  $VBM hostonlyif create
  $VBM hostonlyif create

  if [[ -z "$WIN" ]]; then
    $VBM dhcpserver remove --ifname vboxnet0 || true
    $VBM dhcpserver remove --ifname vboxnet1 || true
    $VBM dhcpserver remove --ifname vboxnet2 || true
    # FIX: VBox 4.2.4 had dhcpserver operating without the below.
    $VBM dhcpserver remove --netname HostInterfaceNetworking-vboxnet0 || true
    $VBM dhcpserver remove --netname HostInterfaceNetworking-vboxnet1 || true
    $VBM dhcpserver remove --netname HostInterfaceNetworking-vboxnet2 || true
    # use variable names to refer to our three interfaces to disturb
    # the remaining code that refers to these as little as possible -
    # the names are compact on Unix :
    VBN0=vboxnet0
    VBN1=vboxnet1
    VBN2=vboxnet2
  else
    # However, the names are verbose on Windows :
    VBN0="VirtualBox Host-Only Ethernet Adapter"
    VBN1="VirtualBox Host-Only Ethernet Adapter #2"
    VBN2="VirtualBox Host-Only Ethernet Adapter #3"
  fi

  $VBM hostonlyif ipconfig "$VBN0" --ip 10.0.100.2    --netmask 255.255.255.0
  $VBM hostonlyif ipconfig "$VBN1" --ip 172.16.100.2  --netmask 255.255.255.0
  $VBM hostonlyif ipconfig "$VBN2" --ip 192.168.100.2 --netmask 255.255.255.0
 
  # Create bootstrap VM
  for vm in bcpc-bootstrap; do
    # Only if VM doesn't exist
    if ! $VBM list vms | grep "^\"${vm}\"" ; then
        $VBM createvm --name $vm --ostype Ubuntu_64 --basefolder $P --register
        $VBM modifyvm $vm --memory 1024
        $VBM storagectl $vm --name "SATA Controller" --add sata
        $VBM storagectl $vm --name "IDE Controller" --add ide
        # Create a number of hard disks
        port=0
        for disk in a; do
            $VBM createhd --filename $P/$vm/$vm-$disk.vdi --size $DRIVE_SIZE
            $VBM storageattach $vm --storagectl "SATA Controller" --device 0 --port $port --type hdd --medium $P/$vm/$vm-$disk.vdi
            port=$((port+1))
        done
        # Add the network interfaces
        $VBM modifyvm $vm --nic1 nat
        $VBM modifyvm $vm --nic2 hostonly --hostonlyadapter2 "$VBN0"
        $VBM modifyvm $vm --nic3 hostonly --hostonlyadapter3 "$VBN1"
        $VBM modifyvm $vm --nic4 hostonly --hostonlyadapter4 "$VBN2"
        # Add the bootable mini ISO for installing Ubuntu 12.04
        $VBM storageattach $vm --storagectl "IDE Controller" --device 0 --port 0 --type dvddrive --medium ubuntu-12.04-mini.iso
        $VBM modifyvm $vm --boot1 disk
    fi
  done
fi

# Create each VM
for vm in bcpc-vm1 bcpc-vm2 bcpc-vm3; do
    # Only if VM doesn't exist
    if ! $VBM list vms | grep "^\"${vm}\"" ; then
        $VBM createvm --name $vm --ostype Ubuntu_64 --basefolder $P --register
        $VBM modifyvm $vm --memory 2048 --boot1 disk --boot2 net --boot3 none --boot4 none
        $VBM storagectl $vm --name "SATA Controller" --add sata
        # Create a number of hard disks
        port=0
        for disk in a b c d e; do
            $VBM createhd --filename $P/$vm/$vm-$disk.vdi --size $DRIVE_SIZE
            $VBM storageattach $vm --storagectl "SATA Controller" --device 0 --port $port --type hdd --medium $P/$vm/$vm-$disk.vdi
            port=$((port+1))
        done
        # Add the network interfaces
        $VBM modifyvm $vm --nic1 hostonly --hostonlyadapter1 vboxnet0
        #$VBM setextradata $vm VBoxInternal/Devices/pcbios/0/Config/LanBootRom $P/gpxe-1.0.1-80861004.rom
        $VBM modifyvm $vm --nic2 hostonly --hostonlyadapter2 vboxnet1
        $VBM modifyvm $vm --nic3 hostonly --hostonlyadapter3 vboxnet2
        #$VBM modifyvm $vm --largepages on --vtxvpid on --hwvirtexexcl on
    fi
done

popd
