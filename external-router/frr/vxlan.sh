# ================== EVPN VNI 100 Final Config ==================

# Bridge (MAC-VRF)
ip link add br100 type bridge
ip link set br100 up

# Underlay IP on bridge (required)
ip addr flush dev enp4s0
ip addr add 172.19.0.1/24 dev br100


# VXLAN device (traditional model)
ip link add vni100 type vxlan id 100 dstport 4789 local 172.19.0.1 nolearning
ip link set vni100 master br100
ip link set vni100 up

# Attach physical NIC
ip link set enp4s0 master br100
bridge vlan add dev enp4s0 vid 1 pvid untagged
ip link set enp4s0 up

# Gateway (SVI) - on the bridge (best for traditional model)
ip addr add 22.100.0.1/24 dev br100

# Optional but recommended: ARP/ND suppression
ip link set vni100 type bridge_slave neigh_suppress on


