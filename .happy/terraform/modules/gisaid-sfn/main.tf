locals {
  # TODO -- hardcoded mapping of sfn generic names to specific names for rdev isn't gonna work forever.
  lambdas = {
    "preprocess-input" = "swipe-aspen-rdev-preprocess-input"
    "process-stage-output" = "swipe-aspen-rdev-process-stage-output"
    "handle-success" = "swipe-aspen-rdev-handle-success"
    "handle-failure" = "swipe-aspen-rdev-handle-failure"
    "swipe-process-batch-event" = "swipe-aspen-rdev-swipe-aspen-rdev-process-batch-event"
    "swipe-process-sfn-event" = "swipe-aspen-rdev-swipe-aspen-rdev-process-sfn-event"
    "report_metrics" = "swipe-aspen-rdev-report_metrics"
    "report_spot_interruption" = "swipe-aspen-rdev-report_spot_interruption"
  }
  sfn_def = yamldecode(templatefile("${path.module}/sfn.yml", merge(local.lambdas, {
    deployment_environment = "aspen-rdev" # FIXME
    deployment_stage = var.deployment_stage
    remote_dev_prefix = var.stack_resource_prefix
    aws_default_region = "us-west-2"
    batch_ec2_job_queue_name = var.ec2_queue_arn
    batch_spot_job_queue_name = var.spot_queue_arn
    batch_job_definition_name = var.job_definition_name
  })))
  jobs = [
    { name = "Ingest"
      memory = 1024
      vcpus = 1
      next = "transform"
    },
    { name = "Transform"
      memory = 1024
      vcpus = 1
      next = "align"
    },
    { name = "Align"
      memory = 1024
      vcpus = 1
    }
  ]
  first_step = "PreprocessInput" # FIXME hardcoding!
  final_errors = ["HandleFailure"] # FIXME hardcoding

  # Figure out how to wire up one state to the next
  next_keys = { for i, job in local.jobs: job["name"] => {
    for statename, state in local.states: statename => {
        Key: lookup(state, "End", false) && try(length(local.jobs[i+1]["name"]), 0) == 0 ? "End" : "Next"
        End: lookup(state, "End", false) && try(length(local.jobs[i+1]["name"]), 0) == 0 ? true : false
        Next: try(coalesce(
            lookup(state, "Next", "") == "HandleFailure" ? "HandleFailure" : null, # HandleFailure is always an end state
            length(lookup(state, "Next", "")) > 0 ? join("", [job["name"], state["Next"]]) : null, # If this had a Next parameter, forward it along to the next step in this job
            lookup(state, "End", false) ? try(join("", [local.jobs[i+1]["name"], local.first_step]), null) : null # If this was an end state, send it to the next job FIXME this is hardcoded
          ), null)
        CatchBlock: length(try(state["Catch"][0]["Next"], "")) == 0 ? {} : { # FIXME this assumes one catch block max per step
          Catch: [ merge(state["Catch"][0], {
            Next: contains(local.final_errors, state["Catch"][0]["Next"]) ? state["Catch"][0]["Next"] : join("", [job["name"], state["Catch"][0]["Next"]])
        })]}
    } if !contains(local.final_errors, statename)
  }}

  # Make a copy of our desired states
  states = local.sfn_def["States"]
  # Make a copy for each job, but make the ends of each job point to the next.
  new_states = merge(flatten([ for job in local.jobs: [
    for statename, state in local.states: {
    join("", [job["name"], statename]) = merge(
      { for key, val in state: key => val if !contains(["Next", "End"], key) }, # All of the existing keys except End and Next
      {
        (local.next_keys[job["name"]][statename]["Key"]) = local.next_keys[job["name"]][statename]["Key"] == "End" ? local.next_keys[job["name"]][statename]["End"] : local.next_keys[job["name"]][statename]["Next"]
      },
      local.next_keys[job["name"]][statename]["CatchBlock"], # Note, the ordering is important.
    )} if !contains(local.final_errors, statename)
  ]])...)
  new_sfn = {
    "Comment" = local.sfn_def["Comment"]
    "StartAt" = "${local.jobs[0]["name"]}${local.first_step}"
    "TimeoutSeconds" = local.sfn_def["TimeoutSeconds"]
    "States" = merge(local.new_states, {for err_state in local.final_errors: err_state => local.states[err_state]})
  }
}
resource "aws_sfn_state_machine" "state_machine" {
  name     = "${var.stack_resource_prefix}-${var.deployment_stage}-${var.custom_stack_name}-${var.app_name}-sfn"
  role_arn = var.role_arn

  definition = jsonencode(local.new_sfn)

}

resource aws_cloudwatch_log_group cloud_watch_logs_group {
  retention_in_days = 365
  name              = "/${var.stack_resource_prefix}/${var.deployment_stage}/${var.custom_stack_name}/${var.app_name}-sfn"
}
