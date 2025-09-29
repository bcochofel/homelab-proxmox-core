# Ansible Configuration Management

The roles created here are for Ubuntu Linux distributions.

To dry-run the bind9 playbook

```bash
ansible-playbook bind9.yml --check
```

To run the playbook remove the ```--check```

## Create a new role

Change directory to `ansible/roles` and execute the commands

```bash
cd ansible/roles
ansible-galaxy role init role1
```

## References

- [Install SOPS](https://github.com/getsops/sops/releases)
- [Install AGE](https://technotim.live/posts/install-age/)
- [Secret Encryption](https://technotim.live/posts/secret-encryption-sops/)
- [Comprehensive guide to SOPS](https://blog.gitguardian.com/a-comprehensive-guide-to-sops/)
- [Ansible: How to build your inventory](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html)
- [Ansible Roles](https://spacelift.io/blog/ansible-roles)
- [Create Ansible roles](https://www.redhat.com/sysadmin/developing-ansible-role)
- [Ansible + SOPS](https://docs.ansible.com/ansible/latest/collections/community/sops/docsite/guide.html)
- [Ansible Galaxy community.sops](https://galaxy.ansible.com/ui/repo/published/community/sops/)
- [Jinja2 Online](http://jinja.quantprogramming.com/)
