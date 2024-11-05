#!/bin/bash

# Define variables
export PATH=$PATH:/usr/bin
export API_USER=""  # API username, typically the same as your account username
export API_KEY=""  # Your API key from Namecheap
export CLIENT_IP=""  # Your whitelisted IP address
RENEW_DAYS=30  # Variable to set the value of the --days parameter

# Dictionary to map domains to their target servers and paths
declare -A SERVERS
SERVERS=(
    ["your_domain_1"]="your_user_1@your_ip_1:/your/full/path/1"
    ["your_domain_2"]="your_user_2@your_ip_2:/your/full/path/2"
    ["your_domain_3"]="your_user_3@your_ip_3:/your/full/path/3"
    ["your_domain_4"]="your_user_4@your_ip_4:/your/full/path/4"
    ["vpn.your_domain_1"]="your_user_5@your_ip_5:/your/full/path/5"
    ["vpn.your_domain_2"]="your_user_6@your_ip_6:/your/full/path/6"
    ["ys.your_domain_3"]="your_user_7@your_ip_7:/your/full/path/7"
)

# Function to reload Nginx on a remote server
reload_nginx() {
    local server=$1
    if ssh "$server" 'sudo /usr/sbin/nginx -s reload'; then
        echo "Nginx reloaded on $server."
    else
        echo "Error: Failed to reload Nginx on $server."
        # Do not exit the script; proceed to the next domain
    fi
}

# Function to handle VPN domain certificate deployment
handle_vpn_domain() {
    local domain=$1
    local cert_dir=$2
    local home_dir="/home/ysaglam"
    local date_tag
    date_tag=$(date +%Y%m%d)
    local vpn_dir="${home_dir}/${domain}_certs_${date_tag}"
    local zip_file="${home_dir}/${domain}_certs_${date_tag}.zip"

    echo "Handling VPN domain $domain"

    # Create directory for VPN domain certificates
    mkdir -p "$vpn_dir"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create VPN directory $vpn_dir"
        return
    fi

    # Convert certificates to PKCS12 format
    openssl pkcs12 -export -out "$vpn_dir/${domain}.p12" -inkey "$cert_dir/${domain}.key" -in "$cert_dir/fullchain.cer" -certfile "$cert_dir/ca.cer" -password pass:sample_password
    if [ $? -ne 0 ]; then
        echo "Error: Failed to convert certificates to PKCS12 for $domain"
        return
    fi

    # Copy the certificates to the VPN directory
    cp "$cert_dir/fullchain.cer" "$vpn_dir/${domain}.crt"
    cp "$cert_dir/${domain}.key" "$vpn_dir/${domain}.key"
    cp "$cert_dir/ca.cer" "$vpn_dir/ca.cer"

    # Ensure all files are owned by the correct user
    chown -R ysaglam:ysaglam "$vpn_dir"

    # Change to the home directory to create the zip file there
    cd "$home_dir" || { echo "Error: Cannot change directory to $home_dir"; return; }

    # Zip the VPN directory
    zip -r "${zip_file}" "$(basename "$vpn_dir")"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to zip VPN directory $vpn_dir"
        return
    fi

    echo "VPN domain handling complete for $domain"
}

check_ssl_certificate() {
    local domain=$1
    echo "Checking SSL for $domain"

    if [[ "$domain" == "vpn.sample.com" ]]; then
        # Exclude this domain
        echo "Skipping $domain as per the requirement."
        ~/.acme.sh/acme.sh --renew -d "$domain" --dns dns_namecheap
        exit_code=$?
        if [ $exit_code -eq 0 ]; then
            echo "Certificate renewed for $domain."
            cert_renewed=1
        else
            echo "Error: Certificate renewal failed for $domain."
            return  # Use 'return' to exit the function instead of 'continue'
        fi

        if [ $cert_renewed -eq 1 ]; then
            CERT_DIR=~/.acme.sh/"${domain}"_ecc
            handle_vpn_domain "$domain" "$CERT_DIR"
        fi

        days_left=99  # Set days_left to 99 for skipped domain or handle as needed
    else
        # Use openssl s_client to get the certificate dates
        expiry_date=$(echo | openssl s_client -servername "$domain" -connect "$domain:443" 2>/dev/null \
            | openssl x509 -noout -dates \
            | grep notAfter \
            | cut -d'=' -f2)

        if [[ -z "$expiry_date" ]]; then
            echo "Could not retrieve the certificate for $domain"
            days_left=9999  # Set a high number to avoid renewing if we can't check

            # Check if the certificate for the domain already exists
            if ~/.acme.sh/acme.sh --list | grep -q "$domain"; then
                cert_exists_in_acme_sh=1
            else
                cert_exists_in_acme_sh=0
            fi
        else
            echo "notAfter=$expiry_date"

            # Now, calculate days left until expiry
            expiry_date_epoch=$(date -d "$expiry_date" +%s)
            current_date_epoch=$(date +%s)
            days_left=$(( (expiry_date_epoch - current_date_epoch) / (60*60*24) ))
            echo "Days left until expiry: $days_left"
        fi
    fi
}

# Export Namecheap API credentials for acme.sh
export NAMECHEAP_API_KEY=$API_KEY
export NAMECHEAP_USERNAME=$API_USER
export NAMECHEAP_SOURCEIP=$CLIENT_IP

~/.acme.sh/acme.sh --register-account -m sample@sample.com
if [ $? -ne 0 ]; then
    echo "Error: acme.sh account registration failed."
    exit 1
fi

# Iterate through the domains and renew and deploy certificates
for domain in "${!SERVERS[@]}"; do

    check_ssl_certificate "$domain"

    # Proceed to renew if days_left is less than or equal to RENEW_DAYS
    if [[ "$days_left" -le "$RENEW_DAYS" ]] || [[ "$cert_exists_in_acme_sh" -eq 0 ]]; then
        echo "Certificate for $domain is due for renewal (days left: $days_left)."
        cert_renewed=0  # Initialize flag to track if the cert was renewed

        # Check if the certificate for the domain already exists
        if ~/.acme.sh/acme.sh --list | grep -q "$domain"; then
            echo "Certificate exists for $domain. Attempting to renew."
            ~/.acme.sh/acme.sh --renew -d "$domain" --dns dns_namecheap --force
            exit_code=$?
            if [ $exit_code -eq 0 ]; then
                echo "Certificate renewed for $domain."
                cert_renewed=1
            else
                echo "Error: Certificate renewal failed for $domain."
                continue
            fi
        else
            echo "Certificate does not exist for $domain. Issuing new certificate."
            ~/.acme.sh/acme.sh --issue -d "$domain" --dns dns_namecheap
            exit_code=$?
            if [ $exit_code -eq 0 ]; then
                echo "Certificate issued for $domain."
                cert_renewed=1
            else
                echo "Error: Certificate issuance failed for $domain."
                continue
            fi
        fi

        # Only proceed to deployment if the certificate was renewed or issued
        if [ $cert_renewed -eq 1 ]; then
            CERT_DIR=~/.acme.sh/"${domain}"_ecc

            if [[ "$domain" == "vpn.sample.com" || "$domain" == "vpn.sample.co" || "$domain" == "vpn.sample.ai" || "$domain" == "vpn.sample.io" ]]; then
                handle_vpn_domain "$domain" "$CERT_DIR"
            else
                TARGET=${SERVERS[$domain]}
                if [[ -z "$TARGET" ]]; then
                    echo "No server deployment needed for $domain."
                    continue
                fi
                SERVER=${TARGET%%:*}
                CERT_PATH=${TARGET#*:}

                echo "Deploying certificates for $domain to $SERVER:$CERT_PATH"

                # Ensure the target directory exists on the remote server
                if ssh "$SERVER" "mkdir -p $CERT_PATH"; then
                    echo "Directory $CERT_PATH created on $SERVER."
                else
                    echo "Error: Failed to create directory $CERT_PATH on $SERVER. Skipping deployment for $domain."
                    continue
                fi

                # Copy certificates to the remote server
                if scp "$CERT_DIR/fullchain.cer" "$SERVER:$CERT_PATH/$domain.crt"; then
                    echo "Copied $domain.crt to $SERVER:$CERT_PATH."
                else
                    echo "Error: Failed to copy $domain.crt to $SERVER:$CERT_PATH. Skipping deployment for $domain."
                    continue
                fi

                if scp "$CERT_DIR/${domain}.key" "$SERVER:$CERT_PATH/$domain.key"; then
                    echo "Copied $domain.key to $SERVER:$CERT_PATH."
                else
                    echo "Error: Failed to copy $domain.key to $SERVER:$CERT_PATH. Skipping deployment for $domain."
                    continue
                fi

                # Reload Nginx on the remote server
                reload_nginx "$SERVER"

                echo "Deployment and Nginx reload complete for $domain"
            fi
        else
            echo "Certificate for $domain was not renewed or issued. Skipping deployment."
        fi

    else
        echo "Certificate for $domain is not due for renewal (days left: $days_left). Skipping renewal."
    fi
done
