#!/usr/bin/env bash
set -x
set -e

# Needed because Ubuntu 24.04 doesn't have java 23+
add-apt-repository ppa:openjdk-r/ppa 
# Dependencies
apt-get update
apt-get upgrade
apt-get -y install openjdk-23-jre-headless ufw caddy

# App user (you cannot login as this user)
useradd -rms /usr/sbin/nologin app

# Systemd service
cat > /etc/systemd/system/app.service << EOD
[Unit]
Description=app
StartLimitIntervalSec=500
StartLimitBurst=5
ConditionPathExists=/home/app/app.jar

[Service]
User=app
Restart=on-failure
RestartSec=5s
WorkingDirectory=/home/app
ExecStart=/usr/bin/java -Dclojure.server.repl="{:port 5555 :accept clojure.core.server/repl}" -jar app.jar -m app.main -Duser.timezone=UTC -XX:+UseZGC -Djdk.attach.allowAttachSelf

[Install]
WantedBy=multi-user.target
EOD

cat > /etc/systemd/system/app-watcher.service << EOD
[Unit]
Description=Restarts app on jar upload

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl restart app.service
EOD

cat > /etc/systemd/system/app-watcher.path << EOD
[Unit]
Description=Watch for app.jar changes

[Path]
PathChanged=/home/app/app.jar
Unit=app-watcher.service

[Install]
WantedBy=multi-user.target
EOD

# Firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw --force enable

# Reverse proxy
rm /etc/caddy/Caddyfile
cat > /etc/caddy/Caddyfile << EOD
example.bigconfig.it {
  header -Server
  reverse_proxy localhost:{
    lb_try_duration 30s
    lb_try_interval 1s
  }
}

hyper.bigconfig.it {
  header -Server
  reverse_proxy localhost:6060 {
    lb_try_duration 30s
    lb_try_interval 1s
  }
}
EOD

# Let's encrypt
systemctl daemon-reload
systemctl enable --now caddy
systemctl enable --now app.service
systemctl enable --now app-watcher.path
