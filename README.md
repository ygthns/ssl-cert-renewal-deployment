# SSL Certificate Renewal and Deployment

This repository contains a Bash script to automate the renewal and deployment of SSL certificates using `acme.sh` and Let's Encrypt. The script is specifically designed for updating DNS TXT records to automate the manual ACME challenge process. It supports both issuing new certificates for new domains and renewing existing certificates. Additionally, it handles special cases for VPN domains by converting their certificates to PKCS12 format and storing them in a zipped folder.

## Features

- Automatically updates DNS TXT records to handle the ACME challenge.
- Renews existing SSL certificates.
- Issues new SSL certificates for new domains.
- Handles special cases for VPN domains by converting certificates to PKCS12 format.
- Deploys certificates to specified remote servers and reloads Nginx.

## Usage

1. **Clone the repository**:
    ```bash
    git clone https://github.com/yourusername/ssl-cert-renewal-deployment.git
    cd ssl-cert-renewal-deployment
    ```

2. **Configure the script**:
    - Update the `API_USER`, `API_KEY`, and `CLIENT_IP` variables with your Namecheap API credentials.
    - Update the `SERVERS` dictionary with your domain names and their respective remote server paths.

3. **Set execution permissions**:
    ```bash
    chmod +x renewal.sh
    ```

4. **Run the script**:
    ```bash
    ./renewal.sh
    ```

## Script Explanation

### Variables

- `API_USER`: Your Namecheap API username.
- `API_KEY`: Your Namecheap API key.
- `CLIENT_IP`: Your whitelisted IP address for Namecheap API.

### Functions

- `reload_nginx(server)`: Reloads Nginx on the specified remote server.
- `check_exit_status(command)`: Checks the exit status of the previous command and exits the script if it failed.
- `handle_special_domain(domain, cert_dir)`: Handles special cases for VPN domains by converting certificates to PKCS12 format, zipping the files, and storing them in `/home/ysaglam`.

### Main Logic

1. The script registers an `acme.sh` account if not already registered.
2. Iterates through the `SERVERS` dictionary to process each domain:
   - Checks if the certificate for the domain already exists.
   - Issues a new certificate if it does not exist.
   - Renews the certificate if it exists.
3. Deploys the certificate:
   - For special domains (`vpn.dataseers.in`, `vpn.finanseer.ai`, `dfw.finanseer.ai`), it converts the certificates to PKCS12 format and stores them in a zipped folder.
   - For other domains, it copies the certificates to the specified remote server and reloads Nginx.

## Goal

The goal of this script is to simplify and automate the management of SSL certificates by automating the manual ACME challenge process with DNS TXT record updates. This ensures that certificates are always up to date and correctly deployed on the necessary servers. This reduces the risk of expired certificates and simplifies the process of handling SSL certificates for multiple domains, including special handling for VPN domains.
