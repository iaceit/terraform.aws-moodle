#! /bin/bash
# shellcheck disable=SC2155

# func to log user data progress into a log file
function log() {
    echo -e "[$(date +%FT%TZ)] $1" >> /var/log/user_data.log
}

function export_instance_metadata() {
    log "Getting and exporting instance metadata to environment."
    export INSTANCE_ID=$(curl http://169.254.169.254/latest/meta-data/instance-id)
    export LOCAL_HOSTNAME=$(curl http://169.254.169.254/latest/meta-data/local-hostname)
    export AVAILABILITY_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
    export AWS_REGION=$(echo $AVAILABILITY_ZONE | sed 's/[a-z]$//')
    export AWS_DEFAULT_REGION=$(echo $AWS_REGION)
    export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
}

function config_firewall() {
    log "Setting up firewall config."
    ufw allow ssh
    ufw allow http
    ufw --force enable
}

function get_parameter() {
    json=$(aws ssm get-parameters --names $1 --with-decryption)
    parameter=$(echo $json | python -c "import sys, json; print json.load(sys.stdin)['Parameters'][0]['Value']")
    echo "$parameter"
}

function install_docker() {
    log "Installing docker and its dependencies."
    apt-get update
    apt-get -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
    
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    
    add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) \
    stable"
    
    apt-get update
    apt-get -y install docker-ce docker-ce-cli containerd.io
    apt-get -y install docker-compose
    usermod -aG docker ubuntu
}

function install_aws_cli() {
    apt-get update
    apt-get -y install awscli
}

function get_db_host() {
    arns=$(aws rds describe-db-instances --query "DBInstances[].DBInstanceArn" --output text)
    for arn in $arns; do
        tags=$(aws rds list-tags-for-resource --resource-name "$arn" --query "TagList[]")
        is_match=$(echo $tags | python3 -c "import sys, json; print('true' if any([t['Value'] == 'terraform.aws-rds' for t in json.load(sys.stdin)]) else 'false')")
        if [[ "$is_match" == "true" ]]; then
            echo "$(aws rds describe-db-instances --filter Name=db-instance-id,Values=$arn --query "DBInstances[].Endpoint.Address" --output text)"
            break
        fi
    done
}

function install_moodle() {
    log "Installing moodle service."
    mkdir -p /usr/moodle/moodledata
    DB_HOST=$(get_db_host)
    DB_PASSWORD=$(get_parameter "/db/password")
    MOODLE_USERNAME=$(get_parameter "/moodle/username")
    MOODLE_PASSWORD=$(get_parameter "/moodle/password")
    MOODLE_SKIP_INSTALL=$(get_parameter "/moodle/skip-install")
    
    cat > /etc/systemd/system/moodle.service <<END
[Unit]
Description=Moodle Quiz Server
After=docker.service
Requires=docker.service
[Service]
TimeoutStartSec=0
Restart=always
ExecStartPre=-/usr/bin/docker stop %n
ExecStartPre=-/usr/bin/docker rm %n
ExecStartPre=/usr/bin/docker pull iaceit/moodle:3.8.0
ExecStart=/usr/bin/docker run \\
                                -e "MARIADB_HOST=$DB_HOST" \\
                                -e "MARIADB_PORT_NUMBER=3306" \\
                                -e "MOODLE_DATABASE_NAME=bitnami_moodle" \\
                                -e "MOODLE_DATABASE_USER=root" \\
                                -e "MOODLE_DATABASE_PASSWORD=$DB_PASSWORD" \\
                                -e "MOODLE_USERNAME=$MOODLE_USERNAME" \\
                                -e "MOODLE_PASSWORD=$MOODLE_PASSWORD" \\
                                -e "MOODLE_SKIP_INSTALL=$MOODLE_SKIP_INSTALL" \\
                                -v /usr/moodle/moodledata:/bitnami/moodle/moodledata \\
                                --name %n \\
                                -p 8080:80 \\
                                iaceit/moodle:3.8.0
ExecStop=/usr/bin/docker stop %n
[Install]
WantedBy=multi-user.target
END
}

function install_nginx-moodle() {
    log "Installing nginx-moodle service."
    cat > /etc/systemd/system/nginx-moodle.service <<END
[Unit]
Description=Nginx that serves Moodle
After=docker.service
Requires=docker.service
[Service]
TimeoutStartSec=0
Restart=always
ExecStartPre=-/usr/bin/docker stop %n
ExecStartPre=-/usr/bin/docker rm %n
ExecStartPre=/usr/bin/docker build -t nginx https://github.com/iaceit/terraform.aws-moodle.git#:nginx
ExecStart=/usr/bin/docker run \\
                                --name %n \\
                                --network=host \\
                                nginx
ExecStop=/usr/bin/docker stop %n
[Install]
WantedBy=multi-user.target
END
}

function install_ddns-cloudflare() {
    log "Installing ddns-cloudflare service."
    X_AUTH_EMAIL=$(get_parameter "/cloudflare/email")
    X_AUTH_KEY=$(get_parameter "/cloudflare/key")
    
    cat > /etc/systemd/system/ddns-cloudflare.service <<END
[Unit]
Description=DDNS Cloudflare
After=docker.service
Requires=docker.service
[Service]
TimeoutStartSec=0
Restart=always
ExecStartPre=-/usr/bin/docker stop %n
ExecStartPre=-/usr/bin/docker rm %n
ExecStartPre=/usr/bin/docker build -t ddns-cloudflare https://github.com/haoming-yin/script.ddns-cloudflare.git
ExecStartPre=/usr/bin/docker pull haomingyin/script.ddns-cloudflare:latest
ExecStart=/usr/bin/docker run \\
                                -e "DDNS_PROFILE=iaceit" \\
                                -e "X_AUTH_EMAIL=$X_AUTH_EMAIL" \\
                                -e "X_AUTH_KEY=$X_AUTH_KEY" \\
                                --name %n \\
                                haomingyin/script.ddns-cloudflare:latest
ExecStop=/usr/bin/docker stop %n
[Install]
WantedBy=multi-user.target
END
}

function install_s3-sync() {
    log "Syncing moodle data from S3."
    mkdir -p /usr/moodle/moodledata
    aws s3 sync s3://iaceit.com/moodle/moodledata /usr/moodle/moodledata --delete --no-follow-symlinks

    log "Installing s3-sync service."
    cat > /etc/systemd/system/s3-sync.service <<END
[Unit]
Description=S3 sync for Ghost CMS content
After=moodle.service
Requires=moodle.service
[Service]
Type=oneshot
ExecStart=/usr/bin/aws s3 sync /usr/moodle/moodledata s3://iaceit.com/moodle/moodledata --delete --no-follow-symlinks --include "filedir/*" --include "lang/*" --exclude "*"
[Install]
WantedBy=multi-user.target
END
    
    log "Installing s3-sync timer."
    cat > /etc/systemd/system/s3-sync.timer <<END
[Unit]
Description=Run s3-sync service daily
[Timer]
Unit=s3-sync.service
OnCalendar=daily
Persistent=true
[Install]
WantedBy=timers.target
END
    
}

log "Started running user data."

export_instance_metadata
config_firewall

install_aws_cli
install_docker

install_s3-sync
install_moodle

service moodle start
systemctl enable s3-sync.timer --now

install_nginx-moodle
service nginx-moodle start

install_ddns-cloudflare
service ddns-cloudflare start

log "Finished running user data script."