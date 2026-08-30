variable "enabled" {
  description = "Create a new regional lab GuardDuty detector only after discovery and exact saved-plan approval."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Required ownership tags for a newly created lab detector."
  type        = map(string)
}
