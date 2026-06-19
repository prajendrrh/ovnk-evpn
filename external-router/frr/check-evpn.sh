#sudo podman exec frr vtysh 2501 -c "show bgp l2vpn evpn vni"
#sudo podman exec frr vtysh 2501 -c "show bgp l2vpn evpn route "
#sudo podman exec frr bridge fdb show | grep 22.100.0.6
#sudo podman exec frr vtysh 2501 -c "show bgp l2vpn evpn route type macip"
#sudo podman exec frr bridge fdb show dev vxlan100 

#sudo podman exec frr vtysh 2501 -c "show ip route 22.100.0.3"

sudo podman exec frr vtysh 2501 -c "show bgp l2vpn evpn vni"
sudo podman exec frr vtysh 2501 -c "show bgp l2vpn evpn route type 2"
sudo podman exec frr vtysh 2501 -c "show evpn mac vni 100"
