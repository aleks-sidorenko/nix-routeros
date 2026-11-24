# justfile for nix-routeros
# Run `just --list` to see all available recipes

# Default recipe - show help
default:
    @just --list

# Render the basic example's Terraform config (never runs tofu)
build:
    @echo "🔨 Building nix-routeros example..."
    nix build ./examples/basic#router.config

# Print the rendered Terraform config for the basic example
show:
    @echo "📄 Rendering generated config..."
    nix build ./examples/basic#router.config --no-link --print-out-paths | xargs cat | jq .

# Render each shipped profile and run `tofu validate` on it (needs network for providers)
validate:
    #!/usr/bin/env bash
    set -euo pipefail
    configs=$(nix build .#validate-configs --no-link --print-out-paths)
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    for dir in "$configs"/*/; do
        profile=$(basename "$dir")
        echo "== $profile"
        mkdir "$tmp/$profile"
        cp "$dir/config.tf.json" "$tmp/$profile/"
        (cd "$tmp/$profile" && tofu init -backend=false -input=false >/dev/null && tofu validate)
    done

# Format nix files with nixfmt-tree (writes)
format *path=".":
    @echo "✨ Formatting nix files with nixfmt-tree..."
    nix fmt {{path}}

# Check formatting without modifying files (read-only)
format-check:
    @echo "🔍 Checking nix file formatting..."
    nix fmt -- --ci

# Lint with statix and deadnix (read-only)
lint:
    @echo "🕵️  Checking for issues with statix..."
    statix check .
    @echo "💀 Checking for dead code with deadnix..."
    deadnix --fail .
    @echo "✅ Lint passed!"

# Auto-fix lint issues (statix fix + deadnix --edit)
lint-fix:
    @echo "🔧 Auto-fixing statix issues..."
    statix fix .
    @echo "💀 Removing dead code..."
    deadnix --edit .
    @echo "✅ Lint fixes applied!"

# Read-only quality umbrella: format-check + lint (CI-safe)
check: format-check lint
    @echo "✅ All quality checks passed!"

# Check flake for issues (all declared systems)
flake-check:
    @echo "🔍 Checking flake configuration..."
    nix flake check --all-systems

# Update flake inputs (optionally a single input)
update *input:
    @echo "📦 Updating flake inputs..."
    nix flake update {{ input }}

# Show flake outputs
outputs:
    @echo "📤 Flake outputs:"
    nix flake show
