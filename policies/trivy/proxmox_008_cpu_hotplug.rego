# METADATA
# title: Ensure CPU hot-plug is disabled unless required
# description: CPU hot-plug can impact vNUMA and performance predictability; disable for production workloads
# schemas:
#   - input: schema["input"]
# custom:
#   id: PROXMOX-008
#   avd_id: AVD-PROXMOX-0008
#   severity: LOW
#   short_code: no-cpu-hotplug
#   recommended_action: Remove cpu.hotplugged or set it to 0 unless the workload needs it
#   input:
#     selector:
#       - type: terraform
package user.proxmox.PROXMOX008

import rego.v1

deny contains res if {
	some resource in input.resource.proxmox_virtual_environment_vm
	some cpu in resource.cpu
	cpu.hotplugged
	cpu.hotplugged > 0
	res := {
		"msg": sprintf("Virtual machine '%s' has CPU hot-plug enabled (cpu.hotplugged > 0)", [resource.__address__]),
		"file": resource.__file__,
		"line": resource.__line__,
	}
}
