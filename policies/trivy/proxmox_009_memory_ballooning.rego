# METADATA
# title: Ensure memory ballooning is disabled for workloads needing guaranteed memory
# description: Ballooning (memory.floating) lets Proxmox reclaim RAM under host pressure, trading guaranteed
#   memory for density — appropriate for some workloads, not others (e.g. Elasticsearch heap sizing).
# schemas:
#   - input: schema["input"]
# custom:
#   id: PROXMOX-009
#   avd_id: AVD-PROXMOX-0009
#   severity: LOW
#   short_code: no-memory-ballooning
#   recommended_action: Remove memory.floating or set it to 0 for workloads needing guaranteed memory
#   input:
#     selector:
#       - type: terraform
package user.proxmox.PROXMOX009

import rego.v1

deny contains res if {
	some resource in input.resource.proxmox_virtual_environment_vm
	some memory in resource.memory
	memory.floating
	memory.floating > 0
	res := {
		"msg": sprintf("Virtual machine '%s' has memory ballooning enabled (memory.floating > 0)", [resource.__address__]),
		"file": resource.__file__,
		"line": resource.__line__,
	}
}
