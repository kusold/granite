# Flake Lock Update Workflow Setup

This document explains how to configure the `update-flake-lock.yml` workflow to create pull requests automatically.

## The Problem

By default, GitHub Actions workflows using the `GITHUB_TOKEN` are **not permitted to create or approve pull requests**. This is a security measure to prevent infinite workflow loops. When the `update-flake-lock` workflow tries to create a PR, you may see this error:

```
GitHub Actions is not permitted to create or approve pull requests
```

Reference: https://docs.github.com/rest/pulls/pulls#create-a-pull-request

## Solutions

You have two options to fix this:

### Option 1: Enable Repository Setting (Recommended for personal repos)

1. Go to your repository **Settings**
2. Navigate to **Actions** → **General**
3. Scroll to the **Workflow permissions** section
4. Select **"Read and write permissions"**
5. Check the box **"Allow GitHub Actions to create and approve pull requests"**
6. Click **Save**

This is the simplest solution and requires no code changes. The workflow will use the default `GITHUB_TOKEN` with elevated permissions.

### Option 2: Use a Personal Access Token (Recommended for organization repos)

If you don't have access to repository settings or prefer more control, use a Personal Access Token (PAT):

1. **Create a Fine-grained Personal Access Token:**
   - Go to GitHub **Settings** → **Developer settings** → **Personal access tokens** → **Fine-grained tokens**
   - Click **Generate new token**
   - Set the token name (e.g., "Flake Lock Updater")
   - Set repository access to this repository
   - Grant the following permissions:
     - **Contents**: Read and write
     - **Pull requests**: Read and write
   - Generate the token and copy it

2. **Add the token as a repository secret:**
   - Go to your repository **Settings** → **Secrets and variables** → **Actions**
   - Click **New repository secret**
   - Name: `GH_TOKEN_FOR_UPDATES`
   - Value: Paste your PAT
   - Click **Add secret**

3. **Uncomment the token line in the workflow:**
   - Edit `.github/workflows/update-flake-lock.yml`
   - Uncomment the line: `token: ${{ secrets.GH_TOKEN_FOR_UPDATES }}`
   - Commit the change

The workflow will now use your PAT instead of the default `GITHUB_TOKEN`.

## Benefits of Using a PAT

- Pull requests created with a PAT will trigger other workflows (unlike those created with `GITHUB_TOKEN`)
- Better suited for organization repositories with strict permissions
- Can work with private repository inputs in your flake

## Verification

After configuring either option, test the workflow:

1. Go to **Actions** tab in your repository
2. Select **Update flake.lock** workflow
3. Click **Run workflow** → **Run workflow**
4. Wait for the workflow to complete
5. Check if a pull request was created successfully

## Troubleshooting

- **Workflow still fails**: Double-check repository settings and ensure the PAT has the correct permissions
- **PR created but workflows don't run**: This is expected with `GITHUB_TOKEN`; use Option 2 (PAT) if you need workflows to run on auto-created PRs
- **Permission denied errors**: Verify the PAT hasn't expired and has access to the repository

## Additional Resources

- [DeterminateSystems/update-flake-lock](https://github.com/DeterminateSystems/update-flake-lock)
- [GitHub Actions Permissions](https://docs.github.com/en/actions/security-guides/automatic-token-authentication#permissions-for-the-github_token)
