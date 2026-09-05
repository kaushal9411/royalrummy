# Testing-only AWS deploy (TEMPLATE)

**Nothing here has been run yet.** This is a template mirroring the deploy
tooling built for the gym-management sibling project, adapted to Lakadiya's
actual stack (plain npm, not pnpm/turbo; native Postgres, not Docker; no
S3 currently — uploads live on local disk). No AWS account, EC2 instance,
domain, or S3 bucket exists for this project yet. Fill in `config.env`
and review every script before running anything — none of it costs money
or touches AWS until you actually execute a script.

Gets the whole Lakadiya stack (backend + admin) running on one AWS EC2
instance for real end-to-end testing — not a production setup. No load
balancer, no managed database, no container registry, no autoscaling.
Intentionally the simplest thing that works, sized to fit a free-tier
account's credit.

## What it sets up

- One EC2 instance (`t3.micro` by default) running:
  - Postgres natively via `apt` (this app has no `docker-compose.yml`
    even in local dev — the test box matches that, zero drift).
  - The backend (`node src/server.js`, no build step) and the admin
    dashboard (Next.js, `npm run build` + `npm start`) as plain Node
    processes managed by pm2.
- A stable Elastic IP, exposed as a **[sslip.io](https://sslip.io)**
  hostname (e.g. `13-233-45-67.sslip.io`) instead of a purchased domain.
- (Optional, `01-setup-s3.sh`) an S3 bucket + scoped IAM user — skip this
  unless you're deliberately moving off local-disk uploads first.

## Prerequisites

- AWS CLI v2 installed and configured (`aws configure`) with an IAM
  user/role that can create EC2 instances, security groups, and Elastic
  IPs (and S3/IAM if you use the optional 01 script).
- `rsync` installed locally (used by 03/06, "Option A").
- For "Option B" (07): the royalrummy repo pushed to a git remote you can
  `git clone`/`fetch` from the server, and a one-time `git clone` done on
  the server (see the comment at the top of `07-redeploy-via-git.sh`).

## Usage

```bash
cd lakadiya/infrastructure/testing-deploy
cp config.env.example config.env   # edit region/instance size/db name — review every value

./02-launch-ec2.sh     # security group + key pair + EC2 + Elastic IP -> credentials.txt
./03-deploy-app.sh     # syncs the repo, installs Postgres role/db, migrates, builds admin, starts everything via pm2
```

`./01-setup-s3.sh` is optional — only run it if you're migrating uploads
off local disk.

Each script is safe to re-run — they skip anything that already exists.

### After it's up

```
Backend API: http://13-233-45-67.sslip.io:3001
Admin panel: http://13-233-45-67.sslip.io:3000
```

SSH in with `ssh -i ./lakadiya-test-key.pem ubuntu@<public-ip>`; once
inside, `pm2 status` / `pm2 logs lakadiya-backend` for troubleshooting.

**`backend/.env` on the server ships with placeholders** for
`GOOGLE_CLIENT_ID/SECRET`, `RAZORPAY_KEY_ID/SECRET`, `GMAIL_USER/APP_PASSWORD`,
and `FIREBASE_*` — Google login, real payments, outbound email, and OTP push
notifications won't work until you edit those by hand on the server and
`pm2 restart lakadiya-backend`.

### Custom domain + SSL (optional)

```bash
# fill BACKEND_HOSTNAME / ADMIN_HOSTNAME in config.env, point DNS A records
# at the Elastic IP from credentials.txt first
./04-setup-domain.sh
./05-setup-ssl.sh
```

### Redeploying code after the initial setup

Two options, same end result — pick whichever fits your workflow:

- **Option A — `06-redeploy-code.sh`** (rsync): run from a machine with a
  local checkout of this repo. Syncs local changes over SSH, then
  installs/migrates/builds/restarts. Needs the `.pem` key and `rsync`
  locally.
- **Option B — `07-redeploy-via-git.sh`** (git): run from anywhere with
  just the SSH key — pulls `origin/main` directly on the server instead
  of syncing local files. Needs the one-time git clone/remote setup on
  the server described in that script's header comment.

Neither touches domain/SSL config — use `04`/`05` again for that.

## Tearing it down

Nothing here auto-expires. When you're done testing:

```bash
source config.env; source credentials.txt
aws ec2 terminate-instances --instance-ids "$INSTANCE_ID"
aws ec2 release-address --allocation-id "$ELASTIC_IP_ALLOCATION_ID"
aws ec2 delete-security-group --group-id "$SECURITY_GROUP_ID"   # after the instance is actually terminated
# only if you ran 01-setup-s3.sh:
aws s3 rb "s3://$S3_BUCKET" --force
aws iam delete-user-policy --user-name "$IAM_USER_NAME" --policy-name "${IAM_USER_NAME}-s3-access"
aws iam list-access-keys --user-name "$IAM_USER_NAME"   # then delete-access-key each one, then delete-user
```
