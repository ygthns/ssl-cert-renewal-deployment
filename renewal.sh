#!/bin/bash

# Define variables
export PATH=$PATH:/usr/bin
export API_USER="your_api_user"  # API username, typically the same as your account username
export API_KEY="your_api_key"  # Your API key from Namecheap
export CLIENT_IP="your_client_ip"  # Your whitelisted IP address
export PFX_PASSWORD="your_password"  # Password for PKCS12 files
export EMAIL="your_email@example.com"  # Your email for acme.sh account registration

# Dictionary to map domains to their target servers and paths
declare -A SERVERS
SERVERS=(
    ["your_domain_1"]="your_user_1@your_ip_1:/your/full/path/1"
    ["your_domain_2"]="your_user_2@your_ip_2:/your/full/path/2"
    ["your_domain_3"]="your_user_3@your_ip_3:/your/full/path/3"
    ["your_domain_4"]="your_user_4@your_ip_4:/your/full/path/4"
    ["vpn.your_domain_1"]="your_user_5@your_ip_5:/your/full/path/5"
    ["vpn.your_domain_2"]="your_user_6@your_ip_6:/your/full/path/6"
    ["dfw.your_domain_3"]="your_user_7@your_ip_7:/your/full/path/7"
)

# Function to reload Nginx on a remote server
reload_nginx() {
    local server=$1
    ssh $server 'sudo /usr/sbin/nginx -s reload'
    if [ $? -ne 0 ]; then
        echo "Error: Failed to reload Nginx on $server"
        exit 1
    fi
}

# Function to check the exit status of the previous command
check_exit_status() {
    if [ $? -eq 2 ]; then
       echo 9
    fi
    if [ $? -ne 0 ] && [ $? -ne 2 ]; then
        echo "Error: $1 failed."
        exit 1
    fi
}

# Function to handle VPN and specific domain certificate deployment
handle_special_domain() {
    local domain=$1
    local cert_dir=$2
    local home_dir="/home/your_username"
    local date_tag=$(date +%Y%m%d)
    local special_dir="$home_dir/${domain}_certs_$date_tag"

    echo "Handling special domain $domain"

    # Create directory for special domain certificates
    mkdir -p $special_dir
    check_exit_status "Creating special directory $special_dir"

    # Convert certificates to PKCS12 format
    openssl pkcs12 -export -out $special_dir/${domain}.p12 -inkey $cert_dir/${domain}.key -in $cert_dir/fullchain.cer -certfile $cert_dir/ca.cer -password pass:$PFX_PASSWORD
    check_exit_status "Converting certificates to PKCS12 for $domain"

    # Copy the certificates to the special directory
    cp $cert_dir/fullchain.cer $special_dir/${domain}.crt
    cp $cert_dir/${domain}.key $special_dir/${domain}.key
    cp $cert_dir/ca.cer $special_dir/ca.cer

    # Zip the special directory
    zip -r $special_dir.zip $special_dir
    check_exit_status "Zipping special directory $special_dir"

    # Move the zip file to the home directory
    mv $special_dir.zip $home_dir
    chown your_username:your_username ${special_dir}.zip
    check_exit_status "Moving zip file to $home_dir"

    echo "Special domain handling complete for $domain"
}

# Export Namecheap API credentials for acme.sh
export NAMECHEAP_API_KEY=$API_KEY
export NAMECHEAP_USERNAME=$API_USER
export NAMECHEAP_SOURCEIP=$CLIENT_IP

# Register acme.sh account if not already registered
if [ ! -f ~/.acme.sh/account.conf ]; then
    ~/.acme.sh/acme.sh --register-account -m $EMAIL
    check_exit_status "acme.sh account registration"
fi

# Iterate through the dictionary and issue or renew and deploy certificates
for domain in "${!SERVERS[@]}"; do
    echo "Processing certificate for $domain"

    # Check if the certificate for the domain already exists
    if ~/.acme.sh/acme.sh --list | grep -q $domain; then
        echo "Renewing certificate for $domain"
        ~/.acme.sh/acme.sh --renew -d $domain --dns dns_namecheap
        result=$(check_exit_status "Certificate renewal for $domain")
    else
        echo "Issuing certificate for $domain"
        ~/.acme.sh/acme.sh --issue -d $domain --dns dns_namecheap
        result=$(check_exit_status "Certificate issuance for $domain")
    fi

    if [[ "$result" == 9 ]]; then
        continue
    fi

    # Deploy the certificate
    CERT_DIR=~/.acme.sh/${domain}_ecc

    if [[ $domain == "vpn.your_domain_1" || $domain == "vpn.your_domain_2" || $domain == "dfw.your_domain_3" ]]; then
        handle_special_domain $domain $CERT_DIR
    else
        TARGET=${SERVERS[$domain]}
        SERVER=${TARGET%%:*}
        CERT_PATH=${TARGET#*:}

        echo "Deploying certificates for $domain to $SERVER:$CERT_PATH"

        # Ensure the target directory exists on the remote server
        ssh $SERVER "mkdir -p $CERT_PATH"
        check_exit_status "Creating directory $CERT_PATH on $SERVER"

        # Copy certificates to the remote server
        scp $CERT_DIR/fullchain.cer $SERVER:$CERT_PATH/$domain.crt
        check_exit_status "Copying $domain.crt to $SERVER:$CERT_PATH"
        scp $CERT_DIR/${domain}.key $SERVER:$CERT_PATH/$domain.key
        check_exit_status "Copying $domain.key to $SERVER:$CERT_PATH"

        # Reload Nginx on the remote server
        reload_nginx $SERVER

        echo "Deployment and Nginx reload complete for $domain"
    fi
done

echo "Certificate issuance/renewal and deployment complete."
