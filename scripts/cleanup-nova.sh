#!/bin/bash
set -euo pipefail

# Nova Cleanup Script
# Run this script to completely remove Nova's runtime and data
# Usage: ./scripts/cleanup-nova.sh

echo "╔════════════════════════════════════════╗"
echo "║      Nova Application Cleanup          ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "This script will remove:"
echo "  • Colima VMs and runtime"
echo "  • Docker containers and volumes"
echo "  • Application cache and state"
echo "  • Runtime binaries and configuration"
echo ""
echo "Your settings in ~/Library/Application Support/ai.openclaw.nova will be preserved."
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting cleanup..."
echo ""

# Find Docker binary
DOCKER_BIN=""
if command -v docker >/dev/null 2>&1; then
    DOCKER_BIN="$(command -v docker)"
fi

# Find Colima binary
COLIMA_BIN=""
if command -v colima >/dev/null 2>&1; then
    COLIMA_BIN="$(command -v colima)"
fi

# Clean up Docker containers and volumes (both dev and prod)
if [ -n "$DOCKER_BIN" ]; then
    echo "→ Cleaning up Docker resources..."

    for profile in nova-vz nova-qemu; do
        for colima_home in "$HOME/.nova/colima" "$HOME/.nova/colima-dev"; do
            sock="$colima_home/$profile/docker.sock"
            if [ -S "$sock" ]; then
                DOCKER_HOST="unix://$sock"
                export DOCKER_HOST

                echo "  Removing containers from $profile..."
                $DOCKER_BIN ps -aq 2>/dev/null | xargs -r $DOCKER_BIN rm -f 2>/dev/null || true

                echo "  Removing volumes from $profile..."
                $DOCKER_BIN volume ls -q 2>/dev/null | xargs -r $DOCKER_BIN volume rm -f 2>/dev/null || true

                echo "  Running system prune on $profile..."
                $DOCKER_BIN system prune -af --volumes 2>/dev/null || true
            fi
        done
    done

    unset DOCKER_HOST
    echo "  ✓ Docker cleanup complete"
else
    echo "  ⊘ Docker not found, skipping Docker cleanup"
fi

# Stop and delete Colima VMs
if [ -n "$COLIMA_BIN" ]; then
    echo "→ Stopping and deleting Colima VMs..."

    for profile in nova-vz nova-qemu; do
        for colima_home in "$HOME/.nova/colima" "$HOME/.nova/colima-dev"; do
            echo "  Deleting $profile from $colima_home..."
            COLIMA_HOME="$colima_home" LIMA_HOME="$colima_home/_lima" \
                $COLIMA_BIN delete -f -p "$profile" 2>/dev/null || true
        done
    done

    echo "  ✓ Colima VMs deleted"
else
    echo "  ⊘ Colima not found, skipping VM deletion"
fi

# Remove .nova directory
echo "→ Removing Nova runtime directory..."
if [ -d "$HOME/.nova" ]; then
    rm -rf "$HOME/.nova"
    echo "  ✓ Removed $HOME/.nova"
else
    echo "  ⊘ $HOME/.nova not found"
fi

# Clean app cache (but preserve settings)
echo "→ Cleaning application cache..."
APP_SUPPORT="$HOME/Library/Application Support/ai.openclaw.nova"
if [ -d "$APP_SUPPORT" ]; then
    rm -rf "$APP_SUPPORT/logs" "$APP_SUPPORT/cache" "$APP_SUPPORT/tmp" 2>/dev/null || true
    echo "  ✓ Cache cleaned (settings preserved)"
else
    echo "  ⊘ App support directory not found"
fi

# Clean Docker contexts
echo "→ Cleaning Docker contexts..."
if [ -n "$DOCKER_BIN" ]; then
    $DOCKER_BIN context rm colima-nova-vz 2>/dev/null || true
    $DOCKER_BIN context rm colima-nova-qemu 2>/dev/null || true
    echo "  ✓ Docker contexts cleaned"
fi

echo ""
echo "╔════════════════════════════════════════╗"
echo "║        Cleanup Complete! ✓             ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "Nova has been reset to a clean state."
echo "Your settings in $APP_SUPPORT have been preserved."
echo ""
echo "You can now:"
echo "  • Reinstall Nova"
echo "  • Restart the app for a fresh setup"
echo "  • Move the app to trash if uninstalling"
echo ""
