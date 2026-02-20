# Use Ubuntu LTS as base (stable and reliable)
FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies: curl, jq, git, and build tools (required for Foundry)
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Foundry using the official installer
RUN curl -L https://foundry.paradigm.xyz | bash \
    && /root/.foundry/bin/foundryup

# Add Foundry binaries to PATH
ENV PATH="/root/.foundry/bin:${PATH}"

# Expose the default RPC port (will be mapped by Render)
EXPOSE 8545

# Copy the entrypoint script (must be in the same directory as Dockerfile)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set default environment variables (can be overridden on Render)
ENV PORT=8545
ENV CHAIN_ID=1
ENV FORK_URL="https://eth-mainnet.g.alchemy.com/v2/QFjExKnnaI2I4qTV7EFM7WwB0gl08X0n"
# Note: JSONBin.io credentials are hardcoded inside entrypoint.sh

# Use the entrypoint script to start Anvil with state persistence
ENTRYPOINT ["/entrypoint.sh"]
