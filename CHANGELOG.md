# Changelog

All notable changes to this project will be documented in this file. See
[Conventional Commits](https://conventionalcommits.org) for commit guidelines.

## [1.5.0](https://github.com/bcochofel/homelab-proxmox-core/compare/1.4.1...1.5.0) (2025-09-29)

### Features

* Added pihole ansible and SOPS support ([8e5f1ac](https://github.com/bcochofel/homelab-proxmox-core/commit/8e5f1acd9d4659936584e72295688a05bdb33b7d))

## [1.4.1](https://github.com/bcochofel/homelab-proxmox-core/compare/1.4.0...1.4.1) (2024-10-28)

### Bug Fixes

* Set BIND9 SOA serial using jinja2 functions ([ce0ba18](https://github.com/bcochofel/homelab-proxmox-core/commit/ce0ba18310c50928a086e84c408d847ba442f411))

## [1.4.0](https://github.com/bcochofel/homelab-proxmox-core/compare/1.3.0...1.4.0) (2024-10-25)

### Features

* Remove disabling IPv6 for compatibility with some apps ([9b1150a](https://github.com/bcochofel/homelab-proxmox-core/commit/9b1150a73eec300b67abe7271488236f0bc10b25))

## [1.3.0](https://github.com/bcochofel/homelab-proxmox-core/compare/1.2.3...1.3.0) (2024-10-20)

### Features

* Added flags to enable/disable BIND9 and Workstation integration ([27d8408](https://github.com/bcochofel/homelab-proxmox-core/commit/27d8408c85fa2103b7aec881d705830c8e7a59b0))

## [1.2.3](https://github.com/bcochofel/homelab-proxmox-core/compare/1.2.2...1.2.3) (2024-10-15)

### Bug Fixes

* Home Assistant DNS name ([0359f62](https://github.com/bcochofel/homelab-proxmox-core/commit/0359f62840706202c7e5949558524b9cfcaeae99))

## [1.2.2](https://github.com/bcochofel/homelab-proxmox-core/compare/1.2.1...1.2.2) (2024-10-14)

### Bug Fixes

* DNS zones ([6201ab4](https://github.com/bcochofel/homelab-proxmox-core/commit/6201ab43ce0819e1f26c0ac88b0c25e6e412a46c))

## [1.2.1](https://github.com/bcochofel/homelab-proxmox-core/compare/1.2.0...1.2.1) (2024-10-14)

### Bug Fixes

* New Proxmox Host ([1776580](https://github.com/bcochofel/homelab-proxmox-core/commit/1776580d7bb40628250c668148124c05b3bf342b))

## [1.2.0](https://github.com/bcochofel/homelab-proxmox-core/compare/1.1.0...1.2.0) (2024-10-13)

### Features

* Add ansible role to install and configure BIND9 ([c084391](https://github.com/bcochofel/homelab-proxmox-core/commit/c084391001179398a7cbfcb482b9a46e1016f7cf))

## [1.1.0](https://github.com/bcochofel/homelab-proxmox-core/compare/1.0.1...1.1.0) (2024-10-12)

### Features

* Module for LXC DNS Server ([657f7af](https://github.com/bcochofel/homelab-proxmox-core/commit/657f7af531c1d135abe0a29957d00af8dca70271))

## [1.0.1](https://github.com/bcochofel/homelab-proxmox-core/compare/1.0.0...1.0.1) (2024-10-09)

### Bug Fixes

* packer variables value with extra space ([4c6dd92](https://github.com/bcochofel/homelab-proxmox-core/commit/4c6dd924543193974896b25be52737af1cda16a3))

## 1.0.0 (2024-10-09)

### Features

* Packer templates for creating Ubuntu Server images ([8088859](https://github.com/bcochofel/homelab-proxmox-core/commit/80888597882dbdb321367764c0141f9db47e1960))
* Terraform module for develop workstation ([daefc84](https://github.com/bcochofel/homelab-proxmox-core/commit/daefc8409850f99ec120f2634a211c6a920f460a))

### Bug Fixes

* GitHub workflow for Release ([83000a4](https://github.com/bcochofel/homelab-proxmox-core/commit/83000a48cb74f1c4cdf003637af072eafc1bd697))
