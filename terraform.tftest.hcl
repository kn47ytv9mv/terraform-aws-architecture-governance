mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "random" {}

run "a_password_length_below_the_iam_minimum_is_rejected" {
  command = plan

  variables {
    minimum_password_length = 4
  }

  expect_failures = [var.minimum_password_length]
}

run "an_unsupported_snapshot_delivery_frequency_is_rejected" {
  command = plan

  variables {
    config_delivery_frequency = "Two_Hours"
  }

  expect_failures = [var.config_delivery_frequency]
}

run "the_default_baseline_evaluates_every_bundled_rule_plus_the_two_added_here" {
  command = plan

  assert {
    condition     = length(module.rules.rule_ids) == 15
    error_message = "The bundled baseline should enable all fifteen of its managed rules by default."
  }

  assert {
    condition     = output.config_rule_count == 17
    error_message = "The default architecture should evaluate the fifteen bundled rules plus the public-read and root-access-key rules."
  }

  assert {
    condition     = length(output.config_rule_ids) == output.config_rule_count
    error_message = "Every rule counted should appear in the config_rule_ids output."
  }
}

run "no_required_resource_tag_creates_no_tag_rule" {
  command = plan

  assert {
    condition     = length(module.required_tag_rule) == 0
    error_message = "A required-tags rule should only be created when a tag key is agreed on."
  }
}

run "a_required_resource_tag_adds_one_more_rule" {
  command = plan

  variables {
    required_resource_tag = "CostCenter"
  }

  assert {
    condition     = length(module.required_tag_rule) == 1
    error_message = "Supplying a tag key should create a rule checking for it."
  }

  assert {
    condition     = output.config_rule_count == 18
    error_message = "The required-tags rule should be counted alongside the other seventeen."
  }
}

run "no_notification_email_leaves_the_topic_without_subscribers" {
  command = plan

  assert {
    condition     = length(module.findings.subscription_arns) == 0
    error_message = "Without an address the findings topic should have no subscriptions."
  }
}

run "a_notification_email_subscribes_to_the_findings_topic" {
  command = plan

  variables {
    notification_email = "security@example.com"
  }

  assert {
    condition     = length(module.findings.subscription_arns) == 1
    error_message = "Supplying an address should subscribe it to the findings topic."
  }
}

run "no_budget_amount_creates_no_budget" {
  command = plan

  assert {
    condition     = length(module.budget) == 0
    error_message = "A budget should only be created when a monthly amount is supplied."
  }
}

run "a_budget_amount_creates_a_budget_notifying_the_findings_topic" {
  command = plan

  variables {
    monthly_budget = "300"
  }

  assert {
    condition     = length(module.budget) == 1
    error_message = "Supplying a monthly amount should create a budget."
  }
}

run "the_name_prefix_reaches_every_resource_this_architecture_names" {
  command = plan

  variables {
    name = "audit"
  }

  assert {
    condition     = module.key_alias.name == "alias/audit"
    error_message = "The key alias should carry the name prefix."
  }

  assert {
    condition     = module.findings.name == "audit-findings"
    error_message = "The findings topic should carry the name prefix."
  }

  assert {
    condition     = module.backup_vault.name == "audit"
    error_message = "The backup vault should carry the name prefix."
  }

  assert {
    condition     = length(module.backup_plan.selection_ids) == 1
    error_message = "The backup plan should select the resources tagged for backup."
  }
}
