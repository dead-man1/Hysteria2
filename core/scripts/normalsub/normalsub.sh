#!/bin/bash
source /etc/hysteria/core/scripts/utils.sh
define_colors

update_env_file() {
    local domain=$1
    local port=$2
    local cert_dir="/etc/letsencrypt/live/$domain"

    cat <<EOL > /etc/hysteria/core/scripts/normalsub/.env
HYSTERIA_DOMAIN=$domain
HYSTERIA_PORT=$port
HYSTERIA_CERTFILE=$cert_dir/fullchain.pem
HYSTERIA_KEYFILE=$cert_dir/privkey.pem
SUBPATH=$(pwgen -s 32 1)
EOL
}

create_service_file() {
    cat <<EOL > /etc/systemd/system/hysteria-normal-sub.service
[Unit]
Description=normalsub Python Service
After=network.target

[Service]
ExecStart=/bin/bash -c 'source /etc/hysteria/hysteria2_venv/bin/activate && /etc/hysteria/hysteria2_venv/bin/python /etc/hysteria/core/scripts/normalsub/normalsub.py'
WorkingDirectory=/etc/hysteria/core/scripts/normalsub
EnvironmentFile=/etc/hysteria/core/scripts/normalsub/.env
Restart=always
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOL
}

start_service() {
    local domain=$1
    local port=$2

    if systemctl is-active --quiet hysteria-normal-sub.service; then
        echo "The hysteria-normal-sub.service is already running."
        return
    fi

    echo "Checking SSL certificates for $domain..."
    if certbot certificates | grep -q "$domain"; then
        echo -e "${yellow}Certificate for $domain already exists. Renewing...${NC}"
        certbot renew --cert-name "$domain"
        if [ $? -ne 0 ]; then
            echo -e "${red}Error: Failed to renew SSL certificate. ${NC}"
            exit 1
        fi
        echo -e "${green}Certificate renewed successfully. ${NC}"
    else
        echo -e "${yellow}Requesting new certificate for $domain...${NC}"
        certbot certonly --standalone --agree-tos --register-unsafely-without-email -d "$domain"
        if [ $? -ne 0 ]; then
            echo -e "${red}Error: Failed to generate SSL certificate. ${NC}"
            exit 1
        fi
        echo -e "${green}Certificate generated successfully. ${NC}"
    fi

    update_env_file "$domain" "$port"
    create_service_file
    chown -R hysteria:hysteria "/etc/letsencrypt/live/$domain"
    chown -R hysteria:hysteria /etc/hysteria/core/scripts/normalsub
    systemctl daemon-reload
    systemctl enable hysteria-normal-sub.service > /dev/null 2>&1
    systemctl start hysteria-normal-sub.service > /dev/null 2>&1
    systemctl daemon-reload > /dev/null 2>&1

    if systemctl is-active --quiet hysteria-normal-sub.service; then
        echo -e "${green}normalsub service setup completed. The service is now running on port $port. ${NC}"
    else
        echo -e "${red}normalsub setup completed. The service failed to start. ${NC}"
    fi
}

stop_service() {
    if [ -f /etc/hysteria/core/scripts/normalsub/.env ]; then
        source /etc/hysteria/core/scripts/normalsub/.env
    fi

    if [ -n "$HYSTERIA_DOMAIN" ]; then
        echo -e "${yellow}Deleting SSL certificate for domain: $HYSTERIA_DOMAIN...${NC}"
        certbot delete --cert-name "$HYSTERIA_DOMAIN" --non-interactive > /dev/null 2>&1
    else
        echo -e "${red}HYSTERIA_DOMAIN not found in .env. Skipping certificate deletion.${NC}"
    fi

    systemctl stop hysteria-normal-sub.service > /dev/null 2>&1
    systemctl disable hysteria-normal-sub.service > /dev/null 2>&1
    systemctl daemon-reload > /dev/null 2>&1

    rm -f /etc/hysteria/core/scripts/normalsub/.env

    echo -e "${yellow}normalsub service stopped and disabled. .env file removed.${NC}"
}

edit_subpath() {
    local new_path="$1"
    local env_file="/etc/hysteria/core/scripts/normalsub/.env"

    if [[ ! "$new_path" =~ ^[a-zA-Z0-9]+$ ]]; then
        echo -e "${red}Error: New subpath must contain only alphanumeric characters (a-z, A-Z, 0-9) and cannot be empty.${NC}"
        exit 1
    fi

    if [ ! -f "$env_file" ]; then
        echo -e "${red}Error: .env file ($env_file) not found. Please run the start command first.${NC}"
        exit 1
    fi

    if grep -q "^SUBPATH=" "$env_file"; then
        sed -i "s|^SUBPATH=.*|SUBPATH=$new_path|" "$env_file"
    else
        echo "SUBPATH=$new_path" >> "$env_file"
    fi
    echo -e "${green}SUBPATH updated to $new_path in $env_file.${NC}"

    echo -e "${yellow}Restarting hysteria-normal-sub service...${NC}"
    systemctl daemon-reload
    systemctl restart hysteria-normal-sub.service

    if systemctl is-active --quiet hysteria-normal-sub.service; then
        echo -e "${green}hysteria-normal-sub service restarted successfully.${NC}"
    else
        echo -e "${red}Error: hysteria-normal-sub service failed to restart. Please check logs.${NC}"
    fi
}

case "$1" in
    start)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo -e "${red}Usage: $0 start <DOMAIN> <PORT> ${NC}"
            exit 1
        fi
        start_service "$2" "$3"
        ;;
    stop)
        stop_service
        ;;
    edit_subpath)
        if [ -z "$2" ]; then
            echo -e "${red}Usage: $0 edit_subpath <NEW_SUBPATH> ${NC}"
            exit 1
        fi
        edit_subpath "$2"
        ;;
    *)
        echo -e "${red}Usage: $0 {start <DOMAIN> <PORT> | stop | edit_subpath <NEW_SUBPATH>} ${NC}"
        exit 1
        ;;
esac