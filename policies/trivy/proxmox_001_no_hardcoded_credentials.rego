# METADATA
# title: Ensure Proxmox provider credentials use variables
# description: Proxmox API tokens should not be hardcoded in provider blocks
# schemas:
#   - input: schema["input"]
# custom:
#   id: PROXMOX-001
#   avd_id: AVD-PROXMOX-0001
#   severity: CRITICAL
#   short_code: no-hardcoded-provider-credentials
#   recommended_action: Reference the Proxmox API token through a variable, never a literal value
#   input:
#     selector:
#       - type: terraform
package user.proxmox.PROXMOX001

import rego.v1

deny contains res if {
	some provider in input.provider.proxmox
	provider.api_token
	not startswith(provider.api_token, "var.")
	res := {
		"msg": "Proxmox provider api_token should use a variable, not be hardcoded",
		"file": provider.__file__,
		"line": provider.__line__,
	}
}
