# Safety rules every plan must pass before it can be applied.
package main

import rego.v1

protected := {"aws_s3_bucket", "aws_iam_role", "aws_eks_pod_identity_association"}

taggable := {"aws_s3_bucket", "aws_iam_role", "aws_eks_pod_identity_association", "aws_cloudfront_distribution"}

required_tags := {"platform:team", "platform:env", "platform:cost-center", "platform:owner"}

changes contains rc if {
	some rc in input.resource_changes
	not rc.change.actions == ["no-op"]
	not rc.change.actions == ["read"]
}

team_decommissioning if input.planned_values.outputs.team_lifecycle.value == "decommission"

statements(policy_json) := s if {
	doc := json.unmarshal(policy_json)
	is_array(doc.Statement)
	s := doc.Statement
} else := [json.unmarshal(policy_json).Statement]

as_list(x) := x if is_array(x)

else := [x]

# Nothing is deleted unless it was decommissioned first.

deny contains msg if {
	some rc in changes
	rc.type in protected
	"delete" in rc.change.actions
	not allowed_delete(rc)
	msg := sprintf("%s would be deleted or replaced; buckets must be decommissioned first and roles only go away when the team decommissions", [rc.address])
}

allowed_delete(rc) if {
	rc.type == "aws_s3_bucket"
	rc.change.actions == ["delete"]
	rc.change.before.tags_all["platform:lifecycle"] == "decommission"
}

allowed_delete(rc) if {
	rc.type != "aws_s3_bucket"
	rc.change.actions == ["delete"]
	team_decommissioning
}

# Team roles get only what they need.

deny contains msg if {
	some rc in changes
	rc.type == "aws_iam_role_policy"
	some s in statements(rc.change.after.policy)
	s.Effect == "Allow"
	some a in as_list(s.Action)
	a in {"*", "s3:*", "iam:*"}
	msg := sprintf("%s grants wildcard action %q", [rc.address, a])
}

deny contains msg if {
	some rc in changes
	rc.type == "aws_iam_role_policy"
	some s in statements(rc.change.after.policy)
	s.Effect == "Allow"
	some r in as_list(s.Resource)
	r == "*"
	msg := sprintf("%s grants access to Resource \"*\"", [rc.address])
}

deny contains msg if {
	some rc in changes
	rc.type == "aws_iam_role"
	"create" in rc.change.actions
	not rc.change.after.permissions_boundary
	msg := sprintf("%s has no permissions boundary", [rc.address])
}

# Public access stays narrow.

deny contains msg if {
	some rc in changes
	rc.type == "aws_s3_bucket_public_access_block"
	some flag in ["block_public_acls", "ignore_public_acls"]
	rc.change.after[flag] != true
	msg := sprintf("%s: %s must stay true (ACLs are never used for public access)", [rc.address, flag])
}

deny contains msg if {
	some rc in changes
	rc.type == "aws_s3_bucket_policy"
	some s in statements(rc.change.after.policy)
	s.Effect == "Allow"
	s.Principal == "*"
	some a in as_list(s.Action)
	a != "s3:GetObject"
	msg := sprintf("%s: anonymous principals may only get objects, not %q", [rc.address, a])
}

# Every resource carries the ownership tags.

deny contains msg if {
	some rc in changes
	rc.type in taggable
	"create" in rc.change.actions
	some tag in required_tags
	not rc.change.after.tags_all[tag]
	msg := sprintf("%s is missing required tag %q", [rc.address, tag])
}
