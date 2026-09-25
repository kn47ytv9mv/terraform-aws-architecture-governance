variable "region" {
  default     = "us-east-1"
  description = "Region every resource in this architecture is created in. The trail records every region, but its own configuration, the recorder, and the rules live here."
}

variable "name" {
  default     = "governance"
  description = "Name prefix applied to the resources this architecture names. AWS Config permits one configuration recorder per region, so an account holds one copy of this baseline per region no matter what the prefix is."
}

variable "config_delivery_frequency" {
  default     = "TwentyFour_Hours"
  description = "How often AWS Config delivers a full configuration snapshot to its bucket. Configuration changes are still recorded continuously regardless; this only sets the cadence of the periodic snapshot, and each snapshot is a billable delivery."

  validation {
    condition     = var.config_delivery_frequency == null || contains(["One_Hour", "Three_Hours", "Six_Hours", "Twelve_Hours", "TwentyFour_Hours"], var.config_delivery_frequency)
    error_message = "AWS Config accepts only 'One_Hour', 'Three_Hours', 'Six_Hours', 'Twelve_Hours', or 'TwentyFour_Hours' as a snapshot delivery frequency."
  }
}

variable "minimum_password_length" {
  default     = 14
  description = "Shortest console password the IAM password policy rule will accept before reporting the account non-compliant. Fourteen is the CIS Benchmark figure and is longer than the AWS default, which is why a freshly created account fails this check until its password policy is set."

  validation {
    condition     = var.minimum_password_length >= 6 && var.minimum_password_length <= 128
    error_message = "An IAM password policy's minimum length must be between 6 and 128 characters, which is the range IAM itself accepts."
  }
}

variable "access_key_max_age" {
  default     = 90
  description = "Days an IAM access key may go unrotated before the account is reported non-compliant."
}

variable "required_resource_tag" {
  default     = null
  description = "Tag key every resource is expected to carry, for example 'Owner' or 'CostCenter'. Setting it adds a rule that reports resources missing the tag. If null, no such rule is created, because a tag rule with no agreed tag key reports every resource in the account as non-compliant on day one and trains people to ignore the findings."
}

variable "data_event_bucket_arns" {
  default     = []
  description = "ARNs of S3 buckets whose object-level reads and writes the trail should also record. Data events are the largest cost lever in this architecture and are recorded for no bucket by default: a single busy bucket can produce orders of magnitude more events than every management API call in the account combined. Name only the buckets whose object access genuinely needs an audit record."
}

variable "backup_schedule" {
  default     = "cron(0 5 * * ? *)"
  description = "Cron expression, in UTC, for the daily backup run. The default runs at 05:00 UTC, which is outside business hours for most of the Americas and Europe."
}

variable "backup_retention_days" {
  default     = 35
  description = "Days a recovery point is kept before AWS Backup deletes it. Thirty-five covers a monthly reporting cycle with a margin, and bounds what the vault costs to hold."
}

variable "notification_email" {
  default     = null
  description = "Address subscribed to the findings topic. An email subscription stays pending until the recipient confirms it, so findings deliver nothing until then."
}

variable "monthly_budget" {
  default     = null
  description = "Monthly spend in USD to alarm on, as a string. If null, no budget is created."
}

variable "tags" {
  default     = null
  description = "A map of tags applied to every resource in the architecture."
}
