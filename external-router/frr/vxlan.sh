#Bridge
sudo ip link add br100 type bridge
sudo ip link set br100 up

#VXLAN 100
sudo ip link add vxlan100 type vxlan id 100 dstport 4789 local 172.19.0.1 nolearning
sudo ip link set vxlan100 master br100
sudo ip link set vxlan100 up

# Gateway IP (highly recommended)
sudo ip addr add 22.100.0.1/16 dev br100
