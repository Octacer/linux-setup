# Contributing to linux-setup

Thank you for considering a contribution! This project contains several Bash scripts to configure a server. The following guidelines help keep the scripts maintainable and safe.

## Running the Scripts Safely

1. **Clone the repository** and make all scripts executable:
   ```bash
   git clone https://github.com/Octacer/linux-setup.git
   cd linux-setup
   chmod +x *.sh
   ```
2. **Review each script** before running it so you understand the changes it makes on your system.
3. Run the scripts with `sudo` in a test environment first:
   ```bash
   sudo ./setup.sh
   ```
   Some installation scripts (e.g. `install-postgres.sh`, `install-n8n.sh`) also require `sudo`.
4. Back up important data prior to running any installation or configuration commands.

## Preferred Shell Style

- Use Bash and start scripts with `#!/bin/bash`.
- Enable strict mode at the top of each script:
  ```bash
  set -euo pipefail
  ```
- Indent with **four spaces** and keep function and variable names in `lower_case_with_underscores`. Use uppercase for constants.
- Wrap variable references in double quotes unless word splitting is required.
- Factor repeated logic into functions defined near the top of the file.
- Provide clear comments for any non‑obvious commands.
- Lint new or modified scripts with [`shellcheck`](https://www.shellcheck.net/):
  ```bash
  shellcheck your-script.sh
  ```
  Fix any warnings where possible before submitting.

## Submitting Pull Requests

1. Fork the repository and create a new branch for your change.
2. Make your edits and run `shellcheck` on all updated scripts.
3. Commit with a descriptive message and push your branch.
4. Open a pull request against the `main` branch. Include a short summary describing what the change does and any manual testing you performed.
5. Be responsive to feedback so the PR can be merged smoothly.

We appreciate all improvements and fixes. Happy scripting!
