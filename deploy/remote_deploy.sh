#!/bin/bash
# Runs ON THE SERVER, sent by the pipeline:  ssh ubuntu@server "bash -s -- <version>" < deploy/remote_deploy.sh
# The release itself was copied to /tmp/demobank-<version>.tgz just before.
set -euo pipefail

VERSION="$1"
BASE=/opt/demobank
RELEASE="$BASE/releases/$VERSION"

echo "==> Waiting for first-boot setup to finish"
cloud-init status --wait > /dev/null

echo "==> Unpacking release $VERSION"
rm -rf "$RELEASE"
mkdir -p "$RELEASE"
tar -xzf "/tmp/demobank-$VERSION.tgz" -C "$RELEASE"
rm -f "/tmp/demobank-$VERSION.tgz"

echo "==> Installing Python packages"
[ -x "$BASE/venv/bin/python" ] || python3 -m venv "$BASE/venv"
"$BASE/venv/bin/pip" install --quiet --disable-pip-version-check -r "$RELEASE/requirements.txt"

echo "==> Applying database migrations"
set -a; . /etc/demobank/demobank.env; set +a
"$BASE/venv/bin/python" "$RELEASE/scripts/migrate.py"

echo "==> Switching to the new release"
ln -sfn "$RELEASE" "$BASE/current"
sudo install -m 0644 "$RELEASE/deploy/demobank.service" /etc/systemd/system/demobank.service
sudo systemctl daemon-reload
sudo systemctl enable --quiet demobank
sudo systemctl restart demobank

echo "==> Checking the app is healthy"
healthy=""
for _ in $(seq 1 30); do
  body=$(curl -fsS http://127.0.0.1/health 2>/dev/null || true)
  case "$body" in
    *"$VERSION"*) healthy=yes; echo "$body"; break ;;
  esac
  sleep 2
done
if [ -z "$healthy" ]; then
  echo "DemoBank did not report healthy as version $VERSION. Its last log lines:"
  sudo journalctl -u demobank -n 30 --no-pager
  exit 1
fi

echo "==> Keeping the five newest releases"
ls -1dt "$BASE"/releases/* | tail -n +6 | xargs -r rm -rf

echo "==> Deployed $VERSION"
