package main

import rego.v1

bucket(addr, actions, before_tags, after) := {
	"address": addr, "type": "aws_s3_bucket",
	"change": {"actions": actions, "before": {"tags_all": before_tags}, "after": after},
}

tags := {"platform:team": "a", "platform:env": "dev", "platform:cost-center": "CC", "platform:owner": "my-org/a"}

plan(changes, lifecycle) := {"resource_changes": changes, "planned_values": {"outputs": {"team_lifecycle": {"value": lifecycle}}}}

test_bucket_delete_without_decommission_denied if {
	count(deny) > 0 with input as plan([bucket("b", ["delete"], {"platform:lifecycle": "active"}, null)], "active")
}

test_bucket_delete_after_decommission_allowed if {
	count(deny) == 0 with input as plan([bucket("b", ["delete"], {"platform:lifecycle": "decommission"}, null)], "active")
}

test_bucket_replace_always_denied if {
	count(deny) > 0 with input as plan([bucket("b", ["delete", "create"], {"platform:lifecycle": "decommission"}, {"tags_all": tags})], "active")
}

test_role_delete_only_when_team_decommissions if {
	role := {"address": "r", "type": "aws_iam_role", "change": {"actions": ["delete"], "before": {}, "after": null}}
	count(deny) > 0 with input as plan([role], "active")
	count(deny) == 0 with input as plan([role], "decommission")
}

test_wildcard_action_denied if {
	pol := json.marshal({"Statement": [{"Effect": "Allow", "Action": "s3:*", "Resource": "arn:aws:s3:::x"}]})
	rc := {"address": "p", "type": "aws_iam_role_policy", "change": {"actions": ["create"], "after": {"policy": pol}}}
	count(deny) > 0 with input as plan([rc], "active")
}

test_wildcard_resource_denied if {
	pol := json.marshal({"Statement": [{"Effect": "Allow", "Action": ["s3:GetObject"], "Resource": "*"}]})
	rc := {"address": "p", "type": "aws_iam_role_policy", "change": {"actions": ["update"], "after": {"policy": pol}}}
	count(deny) > 0 with input as plan([rc], "active")
}

test_role_without_boundary_denied if {
	rc := {"address": "r", "type": "aws_iam_role", "change": {"actions": ["create"], "after": {"tags_all": tags}}}
	count(deny) > 0 with input as plan([rc], "active")
}

test_public_write_denied if {
	pol := json.marshal({"Statement": [{"Effect": "Allow", "Principal": "*", "Action": ["s3:GetObject", "s3:PutObject"], "Resource": "arn:aws:s3:::x/*"}]})
	rc := {"address": "bp", "type": "aws_s3_bucket_policy", "change": {"actions": ["update"], "after": {"policy": pol}}}
	count(deny) > 0 with input as plan([rc], "active")
}

test_public_read_and_tls_deny_allowed if {
	pol := json.marshal({"Statement": [
		{"Effect": "Deny", "Principal": "*", "Action": "s3:*", "Resource": ["arn:aws:s3:::x", "arn:aws:s3:::x/*"]},
		{"Effect": "Allow", "Principal": "*", "Action": "s3:GetObject", "Resource": "arn:aws:s3:::x/*"},
	]})
	rc := {"address": "bp", "type": "aws_s3_bucket_policy", "change": {"actions": ["create"], "after": {"policy": pol}}}
	count(deny) == 0 with input as plan([rc], "active")
}

test_acl_flags_must_stay_on if {
	rc := {"address": "pab", "type": "aws_s3_bucket_public_access_block", "change": {"actions": ["update"], "after": {
		"block_public_acls": false, "ignore_public_acls": true, "block_public_policy": false, "restrict_public_buckets": false,
	}}}
	count(deny) > 0 with input as plan([rc], "active")
}

test_missing_tags_denied if {
	count(deny) > 0 with input as plan([bucket("b", ["create"], {}, {"tags_all": {"platform:team": "a"}})], "active")
}

test_fully_tagged_create_allowed if {
	count(deny) == 0 with input as plan([bucket("b", ["create"], {}, {"tags_all": tags})], "active")
}
