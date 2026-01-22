# Update Flake Lock Workflow Setup

This guide explains how to set up the `update-flake-lock.yml` workflow to:
1. Create pull requests that trigger CI workflows
2. Auto-merge PRs after CI passes

## Why a Personal Access Token (PAT) is Required

Pull requests created with the default `GITHUB_TOKEN` **do not trigger other workflows** (like CI). This is a GitHub security measure to prevent infinite workflow loops. To enable PRs to trigger your CI workflow, you must use a Personal Access Token (PAT).

Reference: https://docs.github.com/actions/using-workflows/triggering-a-workflow#triggering-a-workflow-from-a-workflow

## Setup Steps

### 1. Create a Fine-grained Personal Access Token

1. Go to GitHub **Settings** → **Developer settings** → **Personal access tokens** → **Fine-grained tokens**
2. Click **Generate new token**
3. Configure the token:
   - **Token name**: `Flake Lock Updater` (or your preferred name)
   - **Expiration**: Choose an appropriate duration (recommend 1 year)
   - **Repository access**: Select "Only select repositories" and choose this repository
   - **Permissions**:
     - **Contents**: Read and write
     - **Pull requests**: Read and write
     - **Workflows**: Read and write (needed to trigger CI)
4. Click **Generate token** and **copy the token immediately** (you won't be able to see it again)

### 2. Add the Token as a Repository Secret

1. Go to your repository **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Configure the secret:
   - **Name**: `GH_TOKEN_FOR_UPDATES` (must match exactly)
   - **Value**: Paste the PAT you created
4. Click **Add secret**

### 3. How It Works

Once configured, the workflow will:

1. **Run daily at 6 AM UTC** (or when manually triggered)
2. **Update flake.lock** with the latest Nix package versions
3. **Create a pull request** with labels `dependencies` and `automerge`
4. **Trigger CI workflow** (this only works because we use a PAT)
5. **Enable auto-merge** on the PR
6. **Automatically merge** the PR after CI checks pass

The auto-merge feature uses GitHub's native auto-merge capability, which will merge the PR as soon as all required status checks pass.

## Testing the Workflow

After completing the setup:

1. Go to **Actions** tab in your repository
2. Select **Update flake.lock** workflow
3. Click **Run workflow** → **Run workflow**
4. Wait for the workflow to complete
5. Check that:
   - A pull request was created successfully
   - The CI workflow was triggered on the PR
   - Auto-merge is enabled on the PR (you'll see "Auto-merge enabled" label)
   - After CI passes, the PR automatically merges

## Troubleshooting

### PR created but CI doesn't run
- Verify the PAT secret name is exactly `GH_TOKEN_FOR_UPDATES`
- Confirm the PAT has "Workflows" permission (required to trigger workflows)
- Check that the PAT hasn't expired

### Auto-merge doesn't work
- Ensure branch protection rules are configured (if required)
- Verify the PAT has "Pull requests: write" permission
- Check that the CI workflow completed successfully

### Workflow fails with permission errors
- Verify the PAT has the correct repository access
- Ensure all required permissions are granted (Contents, Pull requests, Workflows)
- Check that the token hasn't expired

## Security Notes

- The PAT is stored securely as a GitHub secret and is not exposed in logs
- Use fine-grained tokens (not classic tokens) for better security
- Set an expiration date and rotate the token periodically
- Only grant the minimum required permissions

## Alternative: GitHub App Token

For organization repositories or enhanced security, consider using a GitHub App token instead of a PAT. This provides more granular control and doesn't require a personal account's permissions.

## Additional Resources

- [DeterminateSystems/update-flake-lock](https://github.com/DeterminateSystems/update-flake-lock)
- [GitHub Actions: Triggering workflows](https://docs.github.com/actions/using-workflows/triggering-a-workflow)
- [GitHub CLI: Auto-merge](https://cli.github.com/manual/gh_pr_merge)
