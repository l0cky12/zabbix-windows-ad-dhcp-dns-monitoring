#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# create-public-repo-and-push.sh
#
# Creates a public GitHub repository for the Zabbix Windows AD DS, DHCP &
# DNS monitoring project, initialises git if needed, stages all files,
# commits, and pushes to the remote.
#
# Usage:
#   chmod +x scripts/github/create-public-repo-and-push.sh
#   ./scripts/github/create-public-repo-and-push.sh
#
# Prerequisites:
#   - GitHub CLI (gh) installed and authenticated
#     (https://cli.github.com/)
#   - Git installed and configured with user.name and user.email
#
# Environment variables (optional overrides):
#   REPO_NAME     Repository name (default: zabbix-windows-ad-dhcp-dns-monitoring)
#   REPO_DESC     Repository description
#   GIT_USER      Git user.name (overrides global git config)
#   GIT_EMAIL     Git user.email (overrides global git config)
# ---------------------------------------------------------------------------

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────

REPO_NAME="${REPO_NAME:-zabbix-windows-ad-dhcp-dns-monitoring}"
REPO_DESC="${REPO_DESC:-Zabbix templates for monitoring Windows Server Active Directory Domain Services, DHCP, DNS, and Role Health}"
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Colours for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

# ── Helper Functions ───────────────────────────────────────────────────────

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

die() {
    error "$*"
    exit 1
}

# ── Step 0: Change to project directory ────────────────────────────────────

cd "$PROJECT_DIR"
info "Working directory: $(pwd)"

# ── Step 1: Check prerequisites ────────────────────────────────────────────

info "Checking prerequisites..."

# Check git is installed
if ! command -v git &>/dev/null; then
    die "git is not installed. Install git and try again."
fi
info "git found: $(git --version)"

# Check gh CLI is installed
if ! command -v gh &>/dev/null; then
    warn "GitHub CLI (gh) is not installed."
    warn ""
    warn "To create the repository without gh, run the following manually:"
    warn ""
    warn "  1. Create repository at: https://github.com/new"
    warn "       - Repository name: ${REPO_NAME}"
    warn "       - Description: ${REPO_DESC}"
    warn "       - Visibility: Public"
    warn "       - Do NOT initialise with README, .gitignore, or license"
    warn ""
    warn "  2. Then push the local repository:"
    warn "       cd ${PROJECT_DIR}"
    warn "       git init"
    warn "       git add ."
    warn "       git commit -m '${REPO_DESC}'"
    warn "       git remote add origin git@github.com:[USERNAME]/${REPO_NAME}.git"
    warn "       git branch -M main"
    warn "       git push -u origin main"
    warn ""
    die "GitHub CLI (gh) is required for automated repository creation."
fi
info "gh found: $(gh --version 2>&1 | head -1)"

# ── Step 2: Check gh authentication ────────────────────────────────────────

info "Checking GitHub CLI authentication..."
GH_AUTH_STATUS=$(gh auth status 2>&1 || true)

if echo "$GH_AUTH_STATUS" | grep -q "Logged in to"; then
    GH_USER=$(echo "$GH_AUTH_STATUS" | grep -oP "Logged in to \K[^ ]+" || echo "unknown")
    info "Authenticated as: ${GH_USER}"
else
    warn "GitHub CLI is not authenticated."
    warn ""
    warn "Authenticate with one of the following methods:"
    warn ""
    warn "  Method 1 — Interactive browser login:"
    warn "    gh auth login"
    warn ""
    warn "  Method 2 — Token-based login:"
    warn '    gh auth login --with-token < ~/.ssh/github_token.txt'
    warn ""
    warn "  Method 3 — Use environment token:"
    warn '    export GITHUB_TOKEN="ghp_..."'
    warn "    gh auth login --with-token <<< \"\$GITHUB_TOKEN\""
    warn ""
    die "Authentication required."
fi

# ── Step 3: Create repository on GitHub ────────────────────────────────────

info "Creating public repository: ${REPO_NAME}"

if gh repo view "$(gh api user --jq '.login')/${REPO_NAME}" &>/dev/null; then
    warn "Repository '${REPO_NAME}' already exists. Skipping creation."
else
    gh repo create "${REPO_NAME}" \
        --public \
        --description "${REPO_DESC}" \
        --push --source . \
        --remote origin \
        || die "Failed to create repository on GitHub."

    info "Repository created successfully: https://github.com/$(gh api user --jq '.login')/${REPO_NAME}"
fi

# ── Step 4: Initialise git (if not already) ────────────────────────────────

if [ ! -d ".git" ]; then
    info "Initialising git repository..."
    git init
else
    info "Git repository already initialised."
fi

# ── Step 5: Configure git user (if overrides provided) ─────────────────────

if [ -n "${GIT_USER:-}" ]; then
    git config user.name "$GIT_USER"
    info "Git user.name set to: ${GIT_USER}"
fi

if [ -n "${GIT_EMAIL:-}" ]; then
    git config user.email "$GIT_EMAIL"
    info "Git user.email set to: ${GIT_EMAIL}"
fi

# ── Step 6: Stage all files ────────────────────────────────────────────────

info "Staging all files..."
git add -A

# Check if there's anything to commit
if git diff --cached --quiet; then
    warn "No changes to commit. Working tree is clean."
else
    # ── Step 7: Commit ─────────────────────────────────────────────────────
    COMMIT_MSG="Initial commit: Zabbix templates for Windows Server AD DS, DHCP, DNS, and Role Health monitoring"
    info "Committing with message: ${COMMIT_MSG}"
    git commit -m "$COMMIT_MSG"
fi

# ── Step 8: Ensure remote is set ───────────────────────────────────────────

if ! git remote get-url origin &>/dev/null; then
    GH_USER=$(gh api user --jq '.login')
    git remote add origin "https://github.com/${GH_USER}/${REPO_NAME}.git"
    info "Added remote origin: https://github.com/${GH_USER}/${REPO_NAME}.git"
fi

# ── Step 9: Push to origin main ────────────────────────────────────────────

info "Pushing to origin main..."
git branch -M main 2>/dev/null || true

if git push -u origin main 2>&1; then
    info "Push successful!"
else
    warn "Push failed. This may happen if:"
    warn "  - The remote has commits that are not in your local branch"
    warn "  - You do not have write access to the repository"
    warn ""
    warn "If the remote has existing commits, force-push (use with caution):"
    warn "  git push -u origin main --force"
    die "Push failed."
fi

# ── Done ───────────────────────────────────────────────────────────────────

info ""
info "╔══════════════════════════════════════════════════════════════╗"
info "║  Repository created and pushed successfully!                ║"
info "╠══════════════════════════════════════════════════════════════╣"
info "║  Name:    ${REPO_NAME}"
info "║  URL:     https://github.com/$(gh api user --jq '.login')/${REPO_NAME}"
info "║  Branch:  main"
info "╚══════════════════════════════════════════════════════════════╝"
info ""

exit 0