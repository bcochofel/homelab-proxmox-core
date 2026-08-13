# METADATA
# title: Ensure Proxmox provider connections verify TLS
# description: TLS verification should be enabled for production environments
# schemas:
#   - input: schema["input"]
# custom:
#   id: PROXMOX-002
#   avd_id: AVD-PROXMOX-0002
#   severity: HIGH
#   short_code: no-insecure-tls
#   recommended_action: Remove insecure = true, or set it from a variable defaulting to false
#   input:
#     selector:
#       - type: terraform
package user.proxmox.PROXMOX002

import rego.v1

deny contains res if {
	some provider in input.provider.proxmox
	provider.insecure == true
	res := {
		"msg": "Proxmox provider has TLS verification disabled (insecure = true)",
		"file": provider.__file__,
		"line": provider.__line__,
	}
}
