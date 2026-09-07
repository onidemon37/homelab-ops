# Infrastructure Boundary

Packer image creation is maintained in the separate [`infrastructure-images`](https://github.com/onidemon37/infrastructure-images) repository.

That repository owns:

- Debian 13 Proxmox template builds
- Cloud-init and image hardening
- QEMU guest agent setup
- Published template IDs for `prod` and `non-prod`

This repository owns:

- Debian 13 node provisioning with Ansible
- Kubernetes bootstrap and cluster configuration
- Environment-specific infrastructure automation
- Flux and application delivery

The handoff is the Proxmox template ID and its documented image version. `homelab-ops` should consume those values rather than duplicate Packer templates.
