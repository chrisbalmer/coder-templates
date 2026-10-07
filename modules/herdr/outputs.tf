output "script" {
  description = "The rendered startup script, for testing it outside a workspace."
  value       = local.script
}

output "app_command" {
  description = "The command the Herdr app runs, for testing it outside a workspace."
  value       = local.app_command
}
