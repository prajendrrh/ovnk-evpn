# 🚀 OpenShift EVPN with External FRR Router Interoperability

[![OpenShift](https://img.shields.io/badge/Built%20with-OpenShift-red?logo=openshift)](https://www.openshift.com/)
[![EVPN](https://img.shields.io/badge/Technology-EVPN-informational)](https://en.wikipedia.org/wiki/Ethernet_VPN)
[![FRR](https://img.shields.io/badge/Routing-FRR-blue)](https://frrouting.org/)
[![OVN-Kubernetes](https://img.shields.io/badge/CNI-OVN--Kubernetes-orange?logo=kubernetes)](https://github.com/ovn-org/ovn-kubernetes)
[![License](https://img.shields.io/badge/License-MIT-green)](https://opensource.org/licenses/MIT)

---

## 🎯 Project Goal

This project demonstrates how to establish an EVPN (Ethernet VPN) overlay network between an OpenShift cluster using OVN-Kubernetes and an external Free Range Routing (FRR) router. It showcases the integration of Kubernetes user-defined networks with traditional network infrastructure, enabling seamless Layer 2 connectivity for pods and services across hybrid environments. The setup facilitates EVPN BGP peering to extend network segments from OpenShift into an external routing domain.

## 🛠️ Technologies Used

*   **OpenShift** 🟥: Container platform and Kubernetes distribution.
*   **OVN-Kubernetes** 🧡: OpenShift's default CNI, used for EVPN and CUDN capabilities.
*   **FRR (Free Range Routing)** 💙: An open-source routing software suite used for the external router.
*   **Podman** 🐳: Container engine for deploying and managing the FRR router.
*   **NMState** ⚙️: Kubernetes operator for declarative network configuration on nodes.
*   **VXLAN** 🌐: Virtual Extensible LAN, the encapsulation protocol for the EVPN overlay.
*   **BGP EVPN** 🔄: Border Gateway Protocol with Ethernet VPN Address Family for route exchange.
*   **Linux Networking** 🐧: Standard `ip` commands for interface and bridge configuration.

## ✨ Key Features

*   **Hybrid EVPN Overlay Network:** Establishes a Layer 2 EVPN network providing seamless connectivity between OpenShift Pods/services and an external routing domain.
*   **External FRR Router Integration:** Deploys and configures a dedicated FRR router in a Podman container, acting as an external VTEP (Virtual Tunnel Endpoint) peer.
*   **Automated Node Network Configuration:** Utilizes `NodeNetworkConfigurationPolicy` (NMState) to provision static IP addresses on OpenShift worker nodes, serving as internal VTEP endpoints.
*   **Cluster User-Defined Networks (CUDN):** Creates an isolated Layer 2 CUDN (`finance` with VNI 100) within OpenShift, managed by OVN-Kubernetes for tenant network segmentation.
*   **EVPN VTEP Definition:** Configures OVN-Kubernetes `VTEP` resources to declare the VTEP range and mode for peering with external EVPN devices.
*   **BGP Peering with `frr-k8s`:** Configures BGP sessions between the OpenShift cluster (leveraging the `frr-k8s` operator) and the external FRR router for EVPN route exchange.
*   **Pod Network Advertisement:** Advertises OpenShift Pod Network routes associated with the CUDN into the EVPN domain, making pods directly reachable from the external network.
*   **VXLAN Tunneling:** Underpins the EVPN overlay for efficient packet encapsulation across the IP underlay.

## 🚀 Installation and Usage

This project involves two main components: the external FRR router setup and the OpenShift cluster configuration.

### Prerequisites

*   An **OpenShift cluster** (version 4.22 or later).
*   The `nmstate` operator must be installed and running in your OpenShift cluster.
*   A dedicated **host machine** (physical or virtual) to run the external FRR router, with `podman` installed.
*   Network connectivity: The external FRR router host and the OpenShift nodes must have IP reachability to each other on the `172.19.0.0/24` subnet.
*   Label your OpenShift nodes (or adjust the `nodeSelector` in `0-static-ip-node-*.yaml`) appropriately, e.g., `oc label node <node-name> node=1`.

### 1. External FRR Router Setup

This setup is performed on the dedicated host machine for the FRR router.

1.  **Prerequisites for External Router Host:**
    *   Ensure `podman` is installed.
    *   Configure a network interface on the host with the IP address `172.19.0.1/24` (or an IP within the `172.19.0.0/24` subnet that allows reaching OCP nodes' VTEPs).
        ```bash
        sudo ip addr add 172.19.0.1/24 dev <your_physical_interface_name>
        sudo ip link set <your_physical_interface_name> up
        ```
        Replace `<your_physical_interface_name>` with the actual name of your host's network interface (e.g., `enp1s0`).

2.  **Prepare FRR Configuration:**
    *   Create a directory `~/frr` on the host machine and place the  `external-router/frr/frr.conf` file inside it. This file configures the BGP daemon for EVPN peering.
    *   `~/frr/frr.conf` 

3.  **Start FRR Container:**
    Navigate to the `/external-router/frr` directory and execute the startup script.
    ```bash
    cd /external-router/frr
    ./start.sh
    ```
    This script will stop any existing `frr` container and then start a new one, mounting your `~/frr` directory.

4.  **Configure VXLAN Interface on Host:**
    Execute the VXLAN configuration script on the FRR host.
    ```bash
    cd /external-router/frr
    sudo ./vxlan.sh
    ```
    This script sets up a Linux bridge (`br100`), a VXLAN interface (`vxlan100` with VNI 100, local VTEP IP `172.19.0.1`), and assigns an IP address (`22.100.0.1/16`) to the bridge.

### 2. OpenShift Cluster Configuration

These steps are performed on your OpenShift cluster using `oc` commands.

1.  **Configure Static IPs for Nodes (VTEPs):**
    Apply the NodeNetworkConfigurationPolicy manifests to assign static IP addresses to your OpenShift nodes. These IPs will be used as VTEP endpoints.
    ```bash
    oc apply -f /ocp/0-static-ip-node-1.yaml
    oc apply -f /ocp/0-static-ip-node-2.yaml
    oc apply -f /ocp/0-static-ip-node-3.yaml
    ```
    **Note:** The interface names (`enp3s0`, `enp0s20f0u4`) in these files are examples. **Adjust them to match the physical network interface names of your OpenShift nodes.**

2.  **Define OVN-Kubernetes VTEP:**
    Apply the VTEP manifest, which defines the `172.19.0.0/24` subnet for external VTEP peering.
    ```bash
    oc apply -f /ocp/1-vtep.yaml
    ```

3.  **Configure `frr-k8s` for BGP Peering:**
    Apply the `FRRConfiguration` manifest to configure the `frr-k8s` operator to establish BGP peering with the external FRR router (`172.19.0.1`).
    ```bash
    oc apply -f /ocp/2-frr.yaml
    ```

4.  **Create Namespace for CUDN:**
    Create the `evpn-test` namespace, labeled for the `finance` CUDN.
    ```bash
    oc apply -f /ocp/3-namespace.yaml
    ```

5.  **Define Cluster User-Defined Network (CUDN):**
    Apply the `ClusterUserDefinedNetwork` manifest. This creates the `finance` Layer 2 CUDN, links it to the `evpn-vtep`, specifies VNI 100, and defines its subnet (`22.100.0.0/16`) and default gateway (`22.100.100.1`).
    ```bash
    oc apply -f /ocp/4-CUDN.yaml
    ```

6.  **Configure Route Advertisements:**
    Apply the `RouteAdvertisements` manifest. This ensures that the OpenShift Pod Network associated with the `finance` CUDN is advertised into the EVPN domain via BGP through the `frr-k8s` operator.
    ```bash
    oc apply -f /ocp/5-ra.yaml
    ```

### 3. Verification

After applying all configurations, you can verify the EVPN peering and route exchange from the external FRR router host:

```bash
cd /external-router/frr
sudo ./check-evpn.sh
```

**Expected Output:**
You should see information regarding:
*   `show bgp l2vpn evpn vni`: EVPN VNI 100 should be present.
*   `show bgp l2vpn evpn route type 2`: Type 2 (MAC/IP) routes learned from OpenShift pods should be displayed.
*   `show evpn mac vni 100`: MAC addresses for pods within the `evpn-test` namespace should be visible.

This indicates successful EVPN peering and route advertisement between your OpenShift cluster and the external FRR router.


---
