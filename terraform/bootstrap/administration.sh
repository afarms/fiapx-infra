#!/bin/bash
set -euo pipefail
umask 022

# No credentials in user data. The standard AL2023 image includes AWS CLI v2
# and SSM Agent. Validate them before declaring bootstrap complete.
aws --version
systemctl enable --now amazon-ssm-agent

workdir=$(mktemp -d)
trap 'rm -rf -- "$workdir"' EXIT
curl --fail --silent --show-error --location --retry 5 \
  https://dl.k8s.io/release/v1.35.3/bin/linux/amd64/kubectl \
  --output "$workdir/kubectl"
printf '%s  %s\n' \
  fd31c7d7129260e608f6faf92d5984c3267ad0b5ead3bced2fe125686e286ad6 \
  "$workdir/kubectl" | sha256sum --check --status
install -o root -g root -m 0755 "$workdir/kubectl" /usr/local/bin/kubectl

cat > /usr/local/bin/fiapx-kubeconfig <<'SCRIPT'
#!/bin/bash
set -euo pipefail
umask 077
exec aws eks update-kubeconfig --region us-east-1 --name fiapx --alias fiapx
SCRIPT
chmod 0755 /usr/local/bin/fiapx-kubeconfig
kubectl version --client
touch /var/lib/fiapx-administration-ready
