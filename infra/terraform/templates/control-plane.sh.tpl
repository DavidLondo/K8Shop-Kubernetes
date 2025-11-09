#!/bin/bash
set -euxo pipefail

HOSTNAME_PREFIX="${cluster_name}"
hostnamectl set-hostname "$${HOSTNAME_PREFIX}-cp"

modprobe overlay
modprobe br_netfilter
cat <<'EOF' | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

cat <<'EOF' | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

swapoff -a
sed -i.bak '/ swap / s/^/#/' /etc/fstab || true

export DEBIAN_FRONTEND=noninteractive
cat <<'EOF' >/etc/apt/apt.conf.d/99force-ipv4
Acquire::ForceIPv4 "true";
EOF

until apt-get update; do
  sleep 5
done

until apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common net-tools socat conntrack ipset netcat-openbsd; do
  sleep 5
done

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

cat <<'EOF' >/etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /
EOF

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable" \
  >/etc/apt/sources.list.d/docker.list

until apt-get update; do
  sleep 5
done

until apt-get install -y containerd.io kubelet kubeadm kubectl; do
  sleep 5
done
apt-mark hold containerd.io kubelet kubeadm kubectl

mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
cat <<'EOF' >/etc/crictl.yaml
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
debug: false
EOF

systemctl enable --now containerd
systemctl enable kubelet
systemctl restart containerd

until systemctl is-active --quiet containerd; do
  sleep 2
done

until crictl info >/dev/null 2>&1; do
  sleep 2
done

CONTROL_PLANE_IP="$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)"
CONTROL_PLANE_PUBLIC_IP="$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "$${CONTROL_PLANE_IP}")"
CONTROL_PLANE_HOSTNAME="$(hostname -f)"

kubeadm init \
  --node-name "$${HOSTNAME_PREFIX}-cp" \
  --token "${kubeadm_token}" \
  --token-ttl 0 \
  --pod-network-cidr "${pod_network_cidr}" \
  --service-cidr "${service_cidr}" \
  --apiserver-advertise-address "$${CONTROL_PLANE_IP}" \
  --apiserver-cert-extra-sans "$${CONTROL_PLANE_PUBLIC_IP},$${CONTROL_PLANE_IP},$${CONTROL_PLANE_HOSTNAME}" \
  --control-plane-endpoint "$${CONTROL_PLANE_IP}:6443" \
  --upload-certs

mkdir -p /home/ubuntu/.kube
cp /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config

# Deploy Calico for CNI networking
su - ubuntu -c "kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/calico.yaml"

cat <<EOF >/home/ubuntu/join-command.sh
#!/bin/bash
sudo kubeadm join $${CONTROL_PLANE_IP}:6443 --token ${kubeadm_token} --discovery-token-unsafe-skip-ca-verification
EOF
chown ubuntu:ubuntu /home/ubuntu/join-command.sh
chmod +x /home/ubuntu/join-command.sh
