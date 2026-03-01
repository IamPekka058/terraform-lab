variable "resource_group_id" {
  type        = string
  description = "The ID of the resource group to which the budget will be applied"
}

variable "budget_name" {
  type        = string
  description = "The name of the budget"
}

variable "budget_amount" {
  type        = number
  description = "The monthly limit in Euro"
}

variable "alert_email" {
  type        = string
  description = "The email address for budget alerts"
}

variable "thresholds" {
  type        = list(number)
  description = "The percentage thresholds for budget alerts"
  default     = [50.0, 90.0]
}
