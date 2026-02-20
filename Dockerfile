# Use Ubuntu LTS as base (more stable package management)
FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies: curl, jq, and build tools (for Foundry)
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

# Expose the default RPC port
EXPOSE 8545

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set default environment variables (can be overridden)
ENV PORT=8545
ENV STATE_FILE=/tmp/state.json

ENTRYPOINT ["/entrypoint.sh"]
