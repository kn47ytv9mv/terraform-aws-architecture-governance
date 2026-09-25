module "key" {
  source  = "kn47ytv9mv/kms-key/aws"
  version = "~> 1.0"

  description = "${var.name} audit and compliance key, used for the trail, the configuration snapshots, and the backup vault"

  tags = var.tags
}

module "key_alias" {
  source  = "kn47ytv9mv/kms-alias/aws"
  version = "~> 1.0"

  name          = var.name
  target_key_id = module.key.arn
}

module "access_logs" {
  source  = "kn47ytv9mv/s3/aws"
  version = "~> 1.0"

  bucket        = "${var.name}-access-logs"
  sse_algorithm = "AES256"

  tags = var.tags
}

module "findings" {
  source  = "kn47ytv9mv/sns-topic/aws"
  version = "~> 1.0"

  name         = "${var.name}-findings"
  display_name = "${var.name} findings"

  subscriptions = var.notification_email != null ? [
    { protocol = "email", endpoint = var.notification_email },
  ] : []

  tags = var.tags
}

module "trail" {
  source  = "kn47ytv9mv/cloudtrail/aws"
  version = "~> 1.0"

  name       = var.name
  kms_key_id = module.key.arn

  enable_access_logging = true
  access_log_bucket     = module.access_logs.bucket
  access_log_prefix     = "cloudtrail/"

  sns_topic_name = module.findings.name

  event_selectors = length(var.data_event_bucket_arns) > 0 ? [
    {
      read_write_type           = "All"
      include_management_events = true

      data_resources = [
        { type = "AWS::S3::Object", values = [for arn in var.data_event_bucket_arns : "${arn}/"] },
      ]
    },
  ] : []

  tags = var.tags
}

module "configuration" {
  source  = "kn47ytv9mv/config-recorder/aws"
  version = "~> 1.0"

  name       = var.name
  kms_key_id = module.key.arn

  enable_access_logging = true
  access_log_bucket     = module.access_logs.bucket
  access_log_prefix     = "config/"

  delivery_frequency = var.config_delivery_frequency
  sns_topic_arn      = module.findings.arn

  tags = var.tags
}

module "rules" {
  source  = "kn47ytv9mv/config-baseline/aws"
  version = "~> 1.0"

  access_keys_rotated_max_age = var.access_key_max_age

  iam_password_policy = {
    require_uppercase_characters = true
    require_lowercase_characters = true
    require_symbols              = true
    require_numbers              = true
    minimum_password_length      = var.minimum_password_length
    password_reuse_prevention    = 24
    max_password_age             = 90
  }

  tags = var.tags
}

module "public_read_rule" {
  source  = "kn47ytv9mv/config-rule/aws"
  version = "~> 1.0"

  name              = "${var.name}-s3-bucket-public-read-prohibited"
  description       = "Checks if S3 buckets allow public read access, whether granted by an ACL or by a bucket policy."
  source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"

  tags = var.tags
}

module "root_access_key_rule" {
  source  = "kn47ytv9mv/config-rule/aws"
  version = "~> 1.0"

  name                        = "${var.name}-iam-root-access-key-check"
  description                 = "Checks if the root user has an access key, which is a long-lived credential for an account's most privileged identity."
  source_identifier           = "IAM_ROOT_ACCESS_KEY_CHECK"
  maximum_execution_frequency = "TwentyFour_Hours"

  tags = var.tags
}

module "required_tag_rule" {
  source  = "kn47ytv9mv/config-rule/aws"
  version = "~> 1.0"
  count   = var.required_resource_tag != null ? 1 : 0

  name              = "${var.name}-required-tags"
  description       = "Checks if resources carry the tag key this account has agreed every resource should have."
  source_identifier = "REQUIRED_TAGS"
  input_parameters  = jsonencode({ tag1Key = var.required_resource_tag })

  tags = var.tags
}

module "backup_vault" {
  source  = "kn47ytv9mv/backup-vault/aws"
  version = "~> 1.0"

  name        = var.name
  kms_key_arn = module.key.arn

  tags = var.tags
}

module "backup_role" {
  source  = "kn47ytv9mv/iam-role/aws"
  version = "~> 1.0"

  name                  = "${var.name}-backup"
  principal_identifiers = ["backup.amazonaws.com"]
  managed_policy_arns   = ["arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"]

  tags = var.tags
}

module "backup_plan" {
  source  = "kn47ytv9mv/backup-plan/aws"
  version = "~> 1.0"

  name = var.name

  rules = [
    {
      rule_name         = "daily"
      target_vault_name = module.backup_vault.name
      schedule          = var.backup_schedule
      lifecycle         = { delete_after = var.backup_retention_days }
    },
  ]

  selections = [
    {
      name         = "tagged"
      iam_role_arn = module.backup_role.arn
      resources    = ["*"]

      selection_tags = [
        { key = "Backup", value = "true" },
      ]
    },
  ]

  tags = var.tags
}

module "budget" {
  source  = "kn47ytv9mv/budget/aws"
  version = "~> 1.0"
  count   = var.monthly_budget != null ? 1 : 0

  name         = "${var.name}-monthly"
  limit_amount = var.monthly_budget

  notifications = [
    {
      threshold                 = 80
      notification_type         = "FORECASTED"
      subscriber_sns_topic_arns = [module.findings.arn]
    },
    {
      threshold                 = 100
      notification_type         = "ACTUAL"
      subscriber_sns_topic_arns = [module.findings.arn]
    },
  ]

  tags = var.tags
}

output "key_arn" {
  description = "ARN of the KMS key the trail, the configuration snapshots, and the backup vault are encrypted with."
  value       = module.key.arn
}

output "trail_arn" {
  description = "ARN of the CloudTrail trail recording the account's API calls."
  value       = module.trail.arn
}

output "trail_bucket" {
  description = "Name of the bucket CloudTrail delivers log files to. This bucket is the account's record of authority for what happened."
  value       = module.trail.bucket
}

output "config_bucket" {
  description = "Name of the bucket AWS Config delivers configuration history and snapshots to."
  value       = module.configuration.bucket
}

output "access_log_bucket" {
  description = "Name of the bucket receiving server access logs for the trail and configuration buckets, so reads of the audit record are themselves recorded."
  value       = module.access_logs.bucket
}

output "config_rule_ids" {
  description = "Map of rule key to AWS Config rule ID, covering every rule this architecture evaluates."
  value = merge(
    module.rules.rule_ids,
    {
      s3_bucket_public_read_prohibited = module.public_read_rule.id
      iam_root_access_key_check        = module.root_access_key_rule.id
    },
    var.required_resource_tag != null ? { required_tags = module.required_tag_rule[0].id } : {},
  )
}

output "config_rule_count" {
  description = "Number of AWS Config rules this architecture evaluates, useful for confirming a configuration change added or removed what was intended."
  value = length(module.rules.rule_ids) + 2 + (
    var.required_resource_tag != null ? 1 : 0
  )
}

output "findings_topic_arn" {
  description = "ARN of the topic carrying log file deliveries, configuration and compliance changes, and budget notifications."
  value       = module.findings.arn
}

output "backup_vault_arn" {
  description = "ARN of the backup vault. Feed this into another account's or region's copy action to keep a copy outside this account."
  value       = module.backup_vault.arn
}
