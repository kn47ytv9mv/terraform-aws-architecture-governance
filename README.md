# terraform-aws-architecture-governance

Terraform module for the security and compliance baseline an AWS account
receives on day one, before any workload lands in it — a CloudTrail trail
recording every API call, AWS Config recording resource state and
evaluating it against seventeen managed rules, a customer managed KMS
key, an SNS topic carrying findings to a person, AWS Backup, and an
optional budget — assembled from this family's single-purpose modules.

## Cost

This architecture is cheap to stand up and its running cost is driven
almost entirely by how much the account does, not by what this module
creates. The fixed charges are one customer managed KMS key at roughly a
dollar a month, and S3 storage for log files and configuration
snapshots, which is pennies for a quiet account.

The variable charges are the ones worth understanding before applying:

- **AWS Config bills per configuration item recorded and per rule
  evaluation.** Recording is set to all supported resource types, which
  is the only setting that produces a complete inventory, and it is also
  the setting that bills the most. An account that churns resources —
  an autoscaling group replacing instances, a pipeline creating and
  destroying stacks — records a configuration item for every change,
  and each of the seventeen rules re-evaluates against it. This is the
  single largest line item this architecture is likely to generate.
- **CloudTrail management events are free for the first trail in an
  account, and only the first.** A second trail recording the same
  management events bills per event. If the account already has a trail,
  this module's trail is the second one.
- **CloudTrail data events are never free, and are off by default.**
  `data_event_bucket_arns` is empty for that reason. A single busy
  bucket can generate more events in an hour than every management API
  call in the account generates in a month. Name a bucket there only
  when object-level access genuinely needs an audit record.
- **AWS Backup bills for recovery point storage**, bounded here by
  `backup_retention_days`. Nothing is backed up until something in the
  account carries the tag `Backup = "true"`, so the vault costs nothing
  on an empty account.
- **AWS Budgets gives every account two free budgets**, so the optional
  budget this module creates is free unless the account already has two.

Unlike a workload architecture, this one is not meant to be destroyed
when you are finished looking at it. Deleting the trail and the
configuration recorder deletes the account's ability to answer what
happened, which is the point of having them.

## Design

Every resource comes from a published module in this family, resolved
from the Terraform Registry under a `~> 1.0` version constraint. This
module contains no `resource` blocks of its own; it is wiring and
nothing else. Read any individual module's README to
understand what it creates and why its defaults are what they are.

### What it builds

| Concern | Contents |
|---|---|
| Audit record | Multi-region CloudTrail trail with log file validation, delivering to its own S3 bucket, encrypted with the customer managed key, with server access logging to a separate bucket |
| Resource inventory | AWS Config recorder covering all supported resource types including global ones, with a delivery channel writing snapshots to its own encrypted, access-logged bucket |
| Compliance evaluation | Fifteen managed rules from the config baseline, plus a public-read check on S3 buckets, a root access key check, and optionally a required-tag check |
| Notification | SNS topic receiving log file deliveries, configuration and compliance changes, and budget notifications, with an optional email subscription |
| Recovery | Backup vault encrypted with the same key, a service role, and a daily plan selecting everything tagged `Backup = "true"` |
| Cost control | Optional monthly budget notifying the same topic at eighty percent forecast and one hundred percent actual |

The two log buckets and the access log bucket form a chain: the trail
and the configuration recorder each write to their own bucket, and both
of those buckets write server access logs into a third. A read of the
audit record therefore leaves a record of its own, which is what the CIS
Benchmark asks for on a CloudTrail bucket specifically.

`name` prefixes the resources this architecture names, but it does not
let an account hold two copies of the baseline in one region. AWS Config
permits one configuration recorder per region, so a second copy fails on
apply regardless of what it is called. Two copies in two regions are
fine, and the trail is multi-region in either case.

### What this baseline does not cover

It is detective, not preventive. Every rule here reports on a resource
after it exists; nothing in this architecture stops the resource from
being created. Prevention lives in service control policies and
permission boundaries, neither of which this family of modules builds.

There is no threat detection. This baseline records what happened and
checks resource configuration against a rule set; it does not analyse
API calls for compromised credentials, cryptocurrency mining, or
reconnaissance, and it does not aggregate findings into a single
console. Those are GuardDuty and Security Hub, and neither has a module
in this family — turn them on separately if you want them.

There is no organization-wide anything. Everything here is scoped to one
account. The trail can be made an organization trail, and the underlying
module supports it, but this architecture does not enable that, because
doing so is only valid in a management account and changes what the
bucket policy has to allow.

### The two policies you still have to write

Two things this architecture wires up will not deliver until a policy
elsewhere allows them, and both fail quietly rather than loudly.

**The KMS key policy.** The key is created with AWS's default key
policy, which grants the account root and nothing else. CloudTrail
delivering encrypted log files, AWS Config encrypting snapshots, and
AWS Backup writing into the vault each need their service principal
granted `kms:GenerateDataKey*` and `kms:Decrypt` on the key. Supply that
policy on the key before the first apply, or the trail's first delivery
fails.

**The SNS topic policy.** The topic is created with AWS's default
policy, which allows only the account owner to publish. CloudTrail,
AWS Config, and AWS Budgets each publish as their own service
principal, so each needs an explicit `sns:Publish` statement naming the
topic ARN. Until that statement exists, the topic is created, the
subscription confirms, and no finding ever arrives. This module does not
write that policy because the statement has to name the topic's own ARN,
and a policy passed into the module that creates the topic would be a
dependency cycle.

### Things it deliberately does not do

One Trivy finding survives on this configuration by design, and it is
worth stating rather than silently suppressing:

- **No access logging on the access log bucket.** The bucket that
  receives server access logs for the trail and configuration buckets
  does not log access to itself. Pointing it at itself would make it log
  its own log writes, which grows without bound.

The access log bucket is also encrypted with SSE-S3 rather than the
customer managed key the rest of this architecture uses. S3 server
access log delivery does not support every form of SSE-KMS encryption,
and a destination bucket it cannot write to silently receives nothing.
SSE-S3 is the encryption mode that always works for a log destination.

The trail delivers to S3 only, and not additionally to a CloudWatch log
group. S3 is the record of authority; a log group would make recent
events searchable and alarmable, and is worth adding separately if you
want that.

## Usage

```hcl
module "baseline" {
  source  = "kn47ytv9mv/architecture-governance/aws"
  version = "~> 1.0"

  notification_email = "security@example.com"
}
```

A production account with a tagging standard to enforce, object-level
auditing on one sensitive bucket, longer backup retention, and a budget:

```hcl
module "baseline" {
  source = "github.com/kn47ytv9mv/terraform-aws-architecture-governance"

  name   = "production"
  region = "us-east-1"

  minimum_password_length = 16
  access_key_max_age      = 45
  required_resource_tag   = "CostCenter"

  data_event_bucket_arns = ["arn:aws:s3:::production-customer-documents"]

  backup_retention_days = 90
  notification_email    = "security@example.com"
  monthly_budget        = "5000"

  tags = {
    Environment = "production"
    Backup      = "true"
  }
}
```

The `Backup` tag in that example is not decorative — the backup plan
selects resources by `Backup = "true"`, so anything without it is
created but never backed up. Note that it applies to the resources this
module itself creates; the workloads you want backed up have to carry it
too.

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.9 |
| aws | ~> 6.61 |

## Providers

| Name | Version |
|---|---|
| aws | ~> 6.61 |

## Inputs

| Name | Description | Default | Required |
|---|---|---|---|
| region | Region every resource in this architecture is created in. The trail records every region, but its own configuration, the recorder, and the rules live here. | `"us-east-1"` | no |
| name | Name prefix applied to the resources this architecture names. AWS Config permits one configuration recorder per region, so an account holds one copy of this baseline per region no matter what the prefix is. | `"governance"` | no |
| config_delivery_frequency | How often AWS Config delivers a full configuration snapshot to its bucket. Configuration changes are still recorded continuously regardless; this only sets the cadence of the periodic snapshot, and each snapshot is a billable delivery. | `"TwentyFour_Hours"` | no |
| minimum_password_length | Shortest console password the IAM password policy rule will accept before reporting the account non-compliant. Fourteen is the CIS Benchmark figure and is longer than the AWS default, which is why a freshly created account fails this check until its password policy is set. | `14` | no |
| access_key_max_age | Days an IAM access key may go unrotated before the account is reported non-compliant. | `90` | no |
| required_resource_tag | Tag key every resource is expected to carry, for example `Owner` or `CostCenter`. Setting it adds a rule that reports resources missing the tag. If null, no such rule is created, because a tag rule with no agreed tag key reports every resource in the account as non-compliant on day one and trains people to ignore the findings. | `null` | no |
| data_event_bucket_arns | ARNs of S3 buckets whose object-level reads and writes the trail should also record. Data events are the largest cost lever in this architecture and are recorded for no bucket by default: a single busy bucket can produce orders of magnitude more events than every management API call in the account combined. Name only the buckets whose object access genuinely needs an audit record. | `[]` | no |
| backup_schedule | Cron expression, in UTC, for the daily backup run. The default runs at 05:00 UTC, which is outside business hours for most of the Americas and Europe. | `"cron(0 5 * * ? *)"` | no |
| backup_retention_days | Days a recovery point is kept before AWS Backup deletes it. Thirty-five covers a monthly reporting cycle with a margin, and bounds what the vault costs to hold. | `35` | no |
| notification_email | Address subscribed to the findings topic. An email subscription stays pending until the recipient confirms it, so findings deliver nothing until then. | `null` | no |
| monthly_budget | Monthly spend in USD to alarm on, as a string. If null, no budget is created. | `null` | no |
| tags | A map of tags applied to every resource in the architecture. | `null` | no |

## Outputs

| Name | Description |
|---|---|
| key_arn | ARN of the KMS key the trail, the configuration snapshots, and the backup vault are encrypted with. |
| trail_arn | ARN of the CloudTrail trail recording the account's API calls. |
| trail_bucket | Name of the bucket CloudTrail delivers log files to. This bucket is the account's record of authority for what happened. |
| config_bucket | Name of the bucket AWS Config delivers configuration history and snapshots to. |
| access_log_bucket | Name of the bucket receiving server access logs for the trail and configuration buckets, so reads of the audit record are themselves recorded. |
| config_rule_ids | Map of rule key to AWS Config rule ID, covering every rule this architecture evaluates. |
| config_rule_count | Number of AWS Config rules this architecture evaluates, useful for confirming a configuration change added or removed what was intended. |
| findings_topic_arn | ARN of the topic carrying log file deliveries, configuration and compliance changes, and budget notifications. |
| backup_vault_arn | ARN of the backup vault. Feed this into another account's or region's copy action to keep a copy outside this account. |

## License

MIT — see [LICENSE.md](LICENSE.md).
