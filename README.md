# Linux Setup Scripts

This repository contains interactive shell scripts for preparing an Ubuntu server and deploying several Docker based services.  The scripts install required packages, configure HTTPS domains and manage containers for PostgreSQL, n8n, Directus and the WAHA WhatsApp API.

## Prerequisites

* Ubuntu system with `sudo` access (tested on Ubuntu 22.04+)
* Root privileges when running the scripts
* [Docker](https://docs.docker.com/engine/install/) and the Docker Compose plugin
* `python3` for configuration management

Run `sudo ./setup.sh` if Docker or other base packages are not installed. This script installs **nginx**, **certbot** and Docker.

## Usage

```bash
# Clone the repository and enter the directory
git clone https://github.com/Octacer/linux-setup.git
cd linux-setup

# Make scripts executable
chmod +x *.sh
```

Run the desired install scripts with `sudo`:

```bash
sudo ./setup.sh           # base server setup
sudo ./install-postgres.sh
sudo ./install-n8n.sh
sudo ./install-directus.sh
sudo ./install-waha.sh
```

## Script Overview

| Script | Description |
| ------ | ----------- |
| `setup.sh` | Installs nginx, certbot and Docker. Run this first on a fresh server. |
| `domain.sh` | Creates an HTTPS nginx virtual host using certbot certificates. Used automatically by the service install scripts, but can also be run separately to configure a new domain. |
| `install-postgres.sh` | Deploys PostgreSQL in a Docker container. Prompts for user, password and database name. |
| `install-n8n.sh` | Installs the n8n automation tool. Requires PostgreSQL and a domain name for HTTPS. |
| `install-directus.sh` | Deploys Directus headless CMS. Creates its database in PostgreSQL and configures HTTPS. |
| `install-waha.sh` | Installs the WAHA WhatsApp API. Requires the WAHA Docker image and an HTTPS domain. |

Each installer checks prerequisites, asks for configuration values and then starts the corresponding Docker containers.

## Configuration File

All scripts store their settings in `services-config.json`. The file is created automatically the first time an install script runs. Below is an excerpt of the default structure generated by `common-functions.sh`:

```json
{
  "services": {
    "postgres": {
      "status": "not_configured",
      "user": "",
      "database": "",
      "password": "",
      "port": "5432",
      "host": "localhost"
    },
    "n8n": {
      "status": "not_configured",
      "domain": "",
      "username": "",
      "password": "",
      "port": "5001",
      "db_name": "n8n"
    }
    ...
  },
  "last_updated": ""
}
```

After running an installer the relevant section is populated with your chosen values. Subsequent runs of the scripts read from this file so you do not need to re‑enter information.

## Example

1. Execute `sudo ./install-postgres.sh` and answer the prompts. This creates `services-config.json` if it does not exist and stores the database credentials.
2. Run `sudo ./install-n8n.sh`. The script reads the PostgreSQL details from the configuration file and only asks for n8n specific settings.
3. Inspect the saved configuration with `cat services-config.json`.

These scripts can be executed independently whenever you need to configure or restart a service.

## Contributing

- Clone the repo and make the scripts executable.
- Review scripts before running and test on a safe server with `sudo`.
- Follow the Bash style in [CONTRIBUTING.md](CONTRIBUTING.md) and enable `set -euo pipefail`.
- Lint updated scripts with [`shellcheck`](https://www.shellcheck.net/) and fix warnings.
- Fork, create a branch and open a pull request with your changes.

## License

This project is licensed under the [MIT License](LICENSE).
