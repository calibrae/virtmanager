#!/bin/bash
# Setup script for the self-hosted GitHub Actions runner on Mac Mini.
# Run this once on the Mini to prepare the environment.
set -e

echo "=== VirtManager CI/CD Runner Setup ==="
echo ""

# 1. Check Xcode
echo "Checking Xcode..."
xcodebuild -version || { echo "ERROR: Xcode not installed"; exit 1; }

# 2. Install Homebrew deps
echo "Installing Homebrew dependencies..."
brew install libvirt spice-gtk pkg-config xcodegen || true
brew upgrade libvirt spice-gtk pkg-config xcodegen 2>/dev/null || true

# 3. Verify deps
echo ""
echo "=== Dependency Versions ==="
echo "libvirt: $(pkg-config --modversion libvirt)"
echo "spice-gtk: $(pkg-config --modversion spice-client-glib-2.0)"
echo "xcodegen: $(xcodegen --version 2>/dev/null || echo 'N/A')"

# 4. Check SSH access to jolyne (for integration tests)
echo ""
echo "Checking SSH to jolyne..."
if ssh -o ConnectTimeout=5 -o BatchMode=yes jolyne "echo OK" 2>/dev/null; then
    echo "SSH to jolyne: OK"
else
    echo "WARNING: Cannot SSH to jolyne — integration and UI tests will be skipped"
    echo "Ensure ~/.ssh/config has a 'jolyne' host entry with the correct key"
fi

# 5. Download Metal toolchain if needed
echo ""
echo "Checking Metal toolchain..."
xcodebuild -downloadComponent MetalToolchain 2>/dev/null || true

# 6. Register the runner (if not already)
echo ""
echo "=== Runner Registration ==="
echo "If the runner is not yet registered for calibrae/virtmanager:"
echo "  1. Go to https://github.com/calibrae/virtmanager/settings/actions/runners/new"
echo "  2. Follow the instructions to download and configure the runner"
echo "  3. Run: ./run.sh (or install as service with ./svc.sh install)"
echo ""

# 7. Set secrets
echo "=== Required GitHub Secrets ==="
echo "Copy these from calibrae/mqtt-aw → calibrae/virtmanager:"
echo "  - ASC_KEY_ID"
echo "  - ASC_KEY_P8"
echo "  - ASC_ISSUER_ID"
echo "  - BUILD_CERTIFICATE_BASE64  (Developer ID Application cert for macOS)"
echo "  - P12_PASSWORD"
echo ""
echo "Set via: gh secret set SECRET_NAME -R calibrae/virtmanager"
echo ""
echo "=== Setup Complete ==="
