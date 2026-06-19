
CONTAINER_NAME=frr

# Check if the container is running
if sudo podman ps --filter "name=$CONTAINER_NAME" --format "{{.State}}" | grep -q "running"; then
    echo "Container $CONTAINER_NAME is running... stoping it"
    sudo podman stop frr
else
    echo "Container $CONTAINER_NAME is not running: starting..."
fi


sudo podman run -d --rm  -v /home/vale/frr:/etc/frr:Z --net=host --name frr --privileged quay.io/frrouting/frr:master
sleep 3
while [ 1 ]
do
sudo podman exec frr vtysh 2501 -c "show ip bgp summary"
sleep 2
done
