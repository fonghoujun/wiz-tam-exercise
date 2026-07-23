# Presentation Notes

## Phase 1 — Networking

**What was built:**
- 1 VPC (`10.0.0.0/16`) via Terraform module (`terraform/modules/network`)
- 2 public subnets (`10.0.0.0/24`, `10.0.1.0/24`) across 2 AZs
- 2 private subnets (`10.0.10.0/24`, `10.0.11.0/24`) across 2 AZs
- Internet Gateway attached to VPC, routed from public subnets
- 1 NAT Gateway (in public subnet A) + Elastic IP, routed from private subnets
- Separate route tables for public (→ IGW) and private (→ NAT) traffic
![VPC Resource Map](images/vpc-resource-map.png)

**Why this design:**
- 2 AZs minimum required by EKS control plane for HA
- Public/private split enforces the exercise requirement that EKS worker
  nodes live in a private subnet, while still allowing internet-facing
  resources (Mongo VM's SSH, load balancer) in public subnets
- NAT Gateway lets private subnet resources (EKS nodes) reach the internet
  for image pulls/updates without being directly internet-reachable
- Subnets tagged `kubernetes.io/role/elb` / `internal-elb` so the AWS Load
  Balancer Controller can auto-discover correct subnets when provisioning
  ingress load balancers later (Phase 4)
- Consistent tagging (`Project`, `Environment`, `ManagedBy`) applied across
  all resources — supports asset context/grouping, relevant to how CNAPP
  tools like Wiz use tags for inventory and risk context

**Approach / process:**
- Built manually via AWS Console first to understand each component
- Tore down console-built resources, rebuilt identically via Terraform
  module for reproducibility or IaC deployment (per exercise DevOps requirement)
- Verified via `terraform plan` (14 resources: 1 VPC, 4 subnets, 1 IGW,
  1 EIP, 1 NAT GW, 2 route tables, 4 associations) before `apply`

**Challenges / decisions:**
- Terraform AWS provider initially failed with "no valid credential
  sources" — resolved by configuring AWS CLI credentials (CloudLabs
  temporary/session credentials) rather than hardcoding keys in code
- Decided against committing `.tfstate` to VCS (contains resource
  metadata, risk of conflicts/exposure) — added to `.gitignore`
- Chose to commit `.terraform.lock.hcl` for provider version reproducibility

## Phase 2 — MongoDB VM

**What was built:**
- EC2 instance (t3.small) running Ubuntu 20.04 (EOL April 2025) in a public subnet
- MongoDB 4.4 (EOL Feb 2024) installed via user_data bootstrap script
- Auth enabled (verified: unauthenticated listDatabases correctly rejected)
- Daily cron job (2am) running mongodump -> tarball -> S3 upload

**Intentional misconfigurations (per spec):**
- SSH (22) open to 0.0.0.0/0
- IAM instance role attached with AmazonEC2FullAccess (broad EC2 permissions)

**Correctly-restricted control (per spec):**
- MongoDB (27017) only reachable from EKS node security group, not a public CIDR

## Phase 3 — Storage

**What was built:**
- S3 bucket (name suffixed with AWS account ID for global uniqueness)
- Versioning enabled

**Intentional misconfiguration (per spec):**
- All 4 S3 Block Public Access settings explicitly disabled
- Bucket policy grants anonymous s3:GetObject + s3:ListBucket
- Verified via manual mongo-backup.sh run + unauthenticated download test

## Phase 4 — EKS Cluster

**What was built:**
- EKS cluster (Kubernetes 1.33) with control plane across public+private subnets
- Managed node group (2x t3.medium) in private subnets only
- Custom node security group + launch template (rather than EKS default) for
  explicit control over what Mongo's SG could reference
- Core add-ons (vpc-cni, coredns, kube-proxy) via Terraform

**Challenge encountered:**
- Node group stuck in CREATING for 30+ minutes with EC2/ASG showing healthy
  instances, but kubectl get nodes returned empty
- Diagnosed by checking layers independently: EC2 instance state (healthy) ->
  ASG state (InService) -> EKS node group health (no reported issues) ->
  Kubernetes join state (empty) -> cluster security group rules (only a
  self-referencing rule, no inbound path from the custom node SG)
- Root cause: custom node SG had no explicit rule allowing communication
  with the cluster's auto-generated SG on 443; nodes could launch at the
  EC2 level but kubelet couldn't reach the API server to register
- Fix: added the cluster security group to the node launch template's
  vpc_security_group_ids, tainted and recreated the node group -> joined
  in under 2 minutes

  ## Phase 5 — Kubernetes App Deployment

**What was built:**
- Tasky (Go + Gin + MongoDB, JWT auth) containerized and pushed to ECR
- Deployed to EKS: Deployment (2 replicas), Service (type LoadBalancer),
  ConfigMap (non-sensitive config), Secret (Mongo URI + JWT key),
  ServiceAccount bound to cluster-admin via ClusterRoleBinding
- wizexercise.txt copied into the image at build time (Dockerfile COPY),
  verified via `docker run --entrypoint cat`
- Verified end-to-end: signup -> login -> add todo -> persisted in the
  real Mongo VM, confirmed directly via mongo shell

**Intentional misconfiguration (per spec):**
- App's ServiceAccount bound to cluster-admin ClusterRoleBinding -
  any pod using this identity has full control over the entire cluster

**Troubleshooting encountered:**

1. Docker image build produced an OCI image index (multi-platform
   manifest) by default under recent Docker Desktop/BuildKit, which ECR's
   basic scanning couldn't process (UnsupportedImageTypeException). Fixed
   with `--provenance=false --sbom=false` on build to force a standard
   single-manifest image.

2. LoadBalancer Service stuck in Pending: `SyncLoadBalancerFailed` -
   "Multiple tagged security groups found for instance." Caused by an
   earlier fix (Phase 4) that added the cluster's auto-generated SG to
   the node launch template to resolve node-join connectivity - both
   that SG and the custom node SG carried the `kubernetes.io/cluster/...`
   ownership tag, which the legacy ELB controller requires to be unique
   per instance. Fixed by removing the tag from the custom node SG only,
   since the EKS-owned cluster SG already carries it natively.

3. App reachable, but /signup consistently failed. Pod logs showed
   `(Unauthorized) not authorized on go-mongodb to execute command` -
   the app's code hardcodes database name `go-mongodb`
   (database/database.go), but the Mongo bootstrap script (Phase 2)
   granted appUser readWrite only on `appdb`. Fixed by granting appUser
   an additional readWrite role scoped to go-mongodb, connecting in the
   correct db context (appdb, where the user document itself lives -
   MongoDB users are namespaced to their creation db even when granting
   roles on a different db).

4. Separately noted: Tasky's own frontend JS has a bug where failed
   signup/login responses render as literal "{}" in the browser
   (`JSON.stringify(response.json())` without awaiting the Promise) -
   diagnosed the real error via pod logs / Network tab instead of
   trusting the on-screen message.

## Phase 6 — Dev(Sec)Ops: Terraform CI/CD Pipeline

**What was built:**
- GitHub Actions workflow (terraform.yml): Checkov IaC scan -> Terraform
  plan (OIDC-authenticated) -> Terraform apply (auto on push to master)
- OIDC federation: no long-lived AWS credentials stored in GitHub -
  a short-lived token is exchanged for temporary AWS credentials scoped
  to a specific IAM role, per workflow run
- Plan artifact passed between plan and apply jobs, so apply executes
  exactly what was reviewed rather than re-planning at apply time

**Troubleshooting encountered:**
- AssumeRoleWithWebIdentity consistently denied ("Not authorized") despite
  IAM trust policy, OIDC provider, and GitHub secret all appearing correct
- Diagnosed via CloudTrail (`lookup-events` for AssumeRoleWithWebIdentity),
  which surfaced the actual `sub` claim GitHub's token presented:
  `repo:org@<numeric-id>/repo@<numeric-id>:ref:refs/heads/master`
- Root cause: GitHub has changed its OIDC `sub` claim format to embed
  immutable numeric org/repo IDs (preventing trust-relationship hijacking
  via repo/org renames) - the trust policy's StringLike condition
  (`repo:org/repo:*`) didn't account for these `@id` suffixes and never
  matched
- Fixed by widening the StringLike pattern to `repo:org*/repo*:*`,
  re-applied, confirmed successful run
- After fixing OIDC auth, `kubectl apply` in the deploy job failed with
  "the server has asked for the client to provide credentials" - despite
  AWS-level auth (OIDC) working correctly
- Root cause: EKS has two separate authorization layers - AWS IAM (governs
  which principals can call EKS APIs) and Kubernetes-level access (governs
  which identities the Kubernetes API server itself recognizes as valid
  users). The GitHub Actions IAM role could call `update-kubeconfig`
  successfully but had never been granted Kubernetes-level access
- Further complicated by the cluster's authentication mode defaulting to
  CONFIG_MAP-only, which doesn't support the modern EKS Access Entry API
- Fixed in two steps: (1) set cluster authentication_mode to
  API_AND_CONFIG_MAP (preserving existing aws-auth ConfigMap compatibility
  and the cluster creator's own admin access), (2) created an EKS Access
  Entry + Access Policy Association granting the GitHub Actions role
  cluster-admin access at the Kubernetes level
- This distinction (AWS IAM vs. Kubernetes RBAC/access entries) is a
  common point of confusion when automating EKS deployments and worth
  articulating clearly if asked about IAM/RBAC layering

**Known tradeoff:** the GitHub Actions IAM role currently uses
AdministratorAccess for simplicity in this lab. Production equivalent:
scope down to only the specific EKS/EC2/S3/ECR/IAM actions the pipeline
actually calls.

## Phase 7 — Cloud Native Security (optional)

**What was built:**
- CloudTrail: multi-region trail, log file validation enabled, logs to a
  dedicated (non-public) S3 bucket separate from application data
- GuardDuty: account-wide detector enabled, verified via AWS-provided
  sample findings (Recon:EC2/PortProbeUnprotectedPort,
  UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.OutsideAWS)
- Preventative control: EKS public API endpoint restricted from 0.0.0.0/0
  to a single admin IP (/32) - directly closing a gap flagged back in
  Phase 4 as "left open, to tighten later"

**Known tradeoff, explicitly identified before applying:**
- Restricting the EKS endpoint to a single IP breaks the GitHub Actions
  build-deploy pipeline's ability to run kubectl commands, since
  GitHub-hosted runners use dynamic, unpredictable IPs
- Decided to accept this tradeoff deliberately rather than widen access:
  favored the tighter security posture given the pipeline wasn't expected
  to need further runs before the interview
- Production alternatives considered: GitHub-hosted runner IP allowlisting
  (rotates, not fully reliable), self-hosted runners inside the VPC, or
  a VPN/PrivateLink connection dedicated to CI/CD
- This highlights a common real-world tension between tightening access
  and preserving automation - worth discussing as a deliberate,
  documented choice rather than an oversight

**Additional troubleshooting (Phase 7 apply via CI):**
- Pushing Phase 7 changes directly to master was correctly rejected by
  branch protection ("Changes must be made through a pull request") -
  live confirmation the control was functioning, not just configured
- Routed through a feature branch + PR as designed. Two further gaps
  surfaced only in CI, not locally:
  1. `my_ip_cidr` variable had no CI source (only existed in local,
     gitignored terraform.tfvars) - added as a GitHub Actions repository
     Variable (not Secret, since a public IP isn't sensitive) and wired
     into the plan step
  2. A required status check (build-scan-push) never triggers on PRs
     that don't touch app/ or k8s/ paths, permanently blocking merge
     ("waiting for status to be reported") - a known GitHub Actions
     limitation with path-filtered required checks. Resolved by scoping
     required checks to only those relevant to each pipeline's actual
     trigger conditions
- As a solo developer, self-approval isn't possible under standard PR
  review rules (by design) - temporarily adjusted the approval
  requirement to merge, noting that in a team setting this would
  require a second reviewer, which is the correct intended behavior
- This sequence is a good example of how CI/CD surfaces environment
  assumptions (local tfvars, single-developer approval flow) that don't
  hold once work moves through a shared, automated pipeline

**Additional consequence of the local-state gap (discovered later):**
- Before the S3 backend migration, CI runs using ephemeral local state
  successfully created duplicate VPC/networking infrastructure (VPC has
  no global name-uniqueness constraint, unlike IAM roles or S3 buckets,
  so it didn't fail the way those did) before erroring out downstream
- Result: 2 orphaned VPCs with their own NAT Gateways silently accruing
  cost, invisible to `terraform destroy` since they were never in the
  real, tracked state
- Reinforces why shared remote state isn't just about collaboration -
  it also prevents CI from unknowingly duplicating live infrastructure

## Known Tradeoffs / Talking Points

- Passwords passed via Terraform variables end up in plaintext in
  rendered user_data and in terraform.tfstate — `sensitive = true` only
  masks CLI/log output, doesn't encrypt state. Production fix: Secrets
  Manager + IAM-authenticated fetch at boot.
- Local Terraform state (not S3 backend) — acceptable for solo lab,
  but no encryption at rest, no locking, no team-shared history.
- SSH manual key pair used instead of Terraform-generated, to keep
  private key material out of state file.

- **Mongo credentials in plaintext**: mongo_admin_password / mongo_app_password
  are passed as Terraform variables (sensitive = true), but that only masks
  CLI/log output — they still land in plaintext inside the rendered user_data
  script and in terraform.tfstate. Production fix: AWS Secrets Manager,
  fetched by the instance at boot via its IAM role, never passed through
  Terraform state at all.

- **Local Terraform state**: no S3 backend configured, so state lives only
  on this machine. Fine for a solo lab; in production this means no locking
  (risk of concurrent-apply corruption), no encryption at rest, no shared
  history across a team, and a single point of failure if the laptop is lost.

- **Mongo VM IAM role is intentionally over-broad**: AmazonEC2FullAccess
  attached to the instance role (required misconfig per spec). Blast radius:
  a compromised VM (e.g. via the open SSH port) could create/terminate/modify
  any EC2 resource in the account. Production fix: least-privilege role
  scoped to only the specific actions the instance needs.

- **S3 bucket is genuinely public**: all 4 Block Public Access protections
  disabled, policy grants anonymous GetObject + ListBucket (required
  misconfig per spec). Verified accessible without AWS credentials. Contains
  only Mongo backups for this exercise — in production this would expose
  potentially sensitive data to the entire internet indefinitely.

- **Custom node security group required manual wiring to the cluster SG**:
  EKS's default node group setup handles node-to-control-plane connectivity
  automatically; building a custom SG for Mongo's sake meant that safety net
  was lost, and the missing rule wasn't obvious until diagnosed layer by
  layer. Worth noting as a real example of a security-driven design choice
  needing extra care to keep functional.

- **SSH key pair created manually, not via Terraform**: avoids private key
  material ever touching Terraform state, at the cost of one manual setup
  step outside IaC. Reasonable tradeoff for this exercise; in production,
  SSM Session Manager would remove the need for SSH/key pairs entirely.

  - **App's own frontend has an unawaited-Promise bug** masking real error
  messages on signup/login failure - not something introduced by this
  deployment, but worth knowing the actual error surface (pod logs,
  browser Network tab) rather than trusting the UI when debugging.

- **Mongo database-name mismatch between app code and IaC** highlights a
  general risk: application code and infrastructure-as-code are often
  authored/maintained separately, and their assumptions (db names, schema,
  auth scope) can silently drift out of sync without integration testing
  catching it until runtime.

- 