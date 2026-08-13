# METADATA
# title: Ensure the QEMU guest agent is enabled
# description: The guest agent enables graceful shutdown, IP reporting, and freeze/thaw for backups
# schemas:
#   - input: schema["input"]
# custom:
#   id: PROXMOX-007
#   avd_id: AVD-PROXMOX-0007
#   severity: MEDIUM
#   short_code: guest-agent-enabled
#   recommended_action: Add an agent block with enabled = true
#   input:
#     selector:
#       - type: terraform
package user.proxmox.PROXMOX007

import rego.v1

deny contains res if {
	some resource in input.resource.proxmox_virtual_environment_vm
	not agent_enabled(resource)
	res := {
		"msg": sprintf("Virtual machine '%s' does not have the QEMU guest agent enabled (agent.enabled = true)", [resource.__address__]),
		"file": resource.__file__,
		"line": resource.__line__,
	}
}

agent_enabled(resource) if {
	some agent in resource.agent
	agent.enabled == true
}
