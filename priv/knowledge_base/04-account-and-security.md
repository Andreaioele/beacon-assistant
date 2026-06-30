# Account & security

## Resetting your password

1. On the login screen, click **Forgot password?**
2. Enter your account email. We'll send a reset link — valid for **60 minutes**.
3. Follow the link and choose a new password.

If you're already logged in, you can change your password under **Settings → Security**.

## Two-factor authentication (2FA)

Beacon supports 2FA on **all plans**, using **authenticator apps** (TOTP — for example Google Authenticator, 1Password, or Authy). When you enable it, you'll receive a set of **backup codes** — store them somewhere safe.

> **Note:** We do **not** support SMS-based 2FA. Authenticator apps only.

## Single sign-on (SSO)

**SAML-based SSO** is available on the **Business** plan. Workspace owners can configure it under **Settings → Security → SSO**. SSO is not available on the Free or Pro plans.

## Active sessions

Under **Settings → Security**, you can see every device currently signed in to your account and **revoke** any session. For security, sessions automatically expire after **30 days** of inactivity.

## Roles and permissions

Beacon has four roles:

| Role | Can do |
|---|---|
| **Owner** | Everything, including billing and deleting the workspace. There is exactly one owner; ownership can be transferred. |
| **Admin** | Manage members, projects, and workspace settings — but not billing or workspace deletion. |
| **Member** | Create and edit projects and tasks. |
| **Guest** | Access only the specific projects they're invited to. No access to billing or settings. |

**Advanced / custom roles** and the **audit log** are available on the **Business** plan.

## Data security

- All data is **encrypted in transit** (TLS) and **at rest** (AES-256).
- You can choose to host your workspace in our **EU** or **US** region when you create it.
- Business-plan workspaces are covered by our **SOC 2 Type II** report, available from your account team.

## Deleting your account or workspace

- To leave a workspace, remove yourself under **Members**.
- A **workspace owner** can permanently delete the entire workspace from **Settings → Danger Zone**. Deletion has a **7-day grace period**, after which it cannot be undone.
