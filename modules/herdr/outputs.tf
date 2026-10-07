output "script" {
  description = "The rendered startup script, for testing it outside a workspace."
  value       = local.script
}

output "app_command" {
  description = "The command the Herdr app runs, for testing it outside a workspace."
  value       = local.app_command
}

output "scripts" {
  description = "The coder exp sync unit of this module's script, for other scripts to wait for (coder exp sync want <unit> <these>)."
  value       = [local.sync_unit]
}
