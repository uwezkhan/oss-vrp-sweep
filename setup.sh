#!/usr/bin/env bash
# One-time VM toolchain install for the OSS VRP CI/supply-chain sweep.
# Target: Debian/Ubuntu x86_64. Run: bash setup.sh
set -euo pipefail
BIN="${HOME}/.local/bin"; mkdir -p "$BIN"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "export PATH=\"$BIN:\$PATH\"" >> "$HOME/.bashrc"; export PATH="$BIN:$PATH";; esac

echo "[*] apt base"
sudo apt-get update -y
sudo apt-get install -y git curl jq ripgrep ca-certificates unzip python3-pip

dl() { curl -fsSL "$1" -o "$2"; }

# resolve a release asset's download URL by regex from the GitHub API (survives naming drift)
asset_url() { curl -fsSL "https://api.github.com/repos/$1/releases/latest" | jq -r ".assets[].browser_download_url | select(test(\"$2\"))" | head -1; }

echo "[*] gitleaks"
GLURL=$(asset_url gitleaks/gitleaks 'linux_(x64|amd64)\\.tar\\.gz$')
dl "$GLURL" /tmp/gl.tgz && tar -xzf /tmp/gl.tgz -C "$BIN" gitleaks && chmod +x "$BIN/gitleaks"

echo "[*] trufflehog"
curl -fsSL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sh -s -- -b "$BIN"

echo "[*] actionlint"
curl -fsSL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash -s -- latest "$BIN"

echo "[*] osv-scanner"
OSVURL=$(asset_url google/osv-scanner 'linux_amd64$')
dl "$OSVURL" "$BIN/osv-scanner" && chmod +x "$BIN/osv-scanner"

echo "[*] zizmor (GitHub Actions security auditor — primary GHA analyzer)"
sudo apt-get install -y pipx >/dev/null 2>&1 || pip3 install --user --quiet --break-system-packages pipx
export PATH="$BIN:$PATH"
pipx install zizmor >/dev/null 2>&1 || pipx install --force zizmor >/dev/null 2>&1 || echo "  (zizmor install failed; regex fallback will run)"
pipx ensurepath >/dev/null 2>&1 || true

echo "[*] semgrep (optional, for later deep pass)"
pipx install semgrep >/dev/null 2>&1 || echo "  (semgrep skipped)"

echo "[*] gh cli (optional, for dup-sweep / advisories)"
if ! command -v gh >/dev/null; then
  (type -p wget >/dev/null || sudo apt-get install -y wget)
  sudo mkdir -p -m 755 /etc/apt/keyrings
  wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y gh
fi

echo
echo "[✓] Installed. Versions:"
for t in git gitleaks trufflehog actionlint osv-scanner zizmor rg jq; do printf "  %-12s " "$t"; command -v "$t" >/dev/null && "$t" --version 2>/dev/null | head -1 || echo "MISSING"; done
echo "Run 'source ~/.bashrc' (or reopen shell) so \$BIN is on PATH."
