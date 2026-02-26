# ═══════════════════════════════════════════════════════════════════════════
# PowerShell Development Container
# ═══════════════════════════════════════════════════════════════════════════

ARG VARIANT=7.4-ubuntu-22.04
FROM mcr.microsoft.com/powershell:${VARIANT}

# ═══════════════════════════════════════════════════════════════════════════
# Arguments & Environment Variables
# ═══════════════════════════════════════════════════════════════════════════

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Paris

# ═══════════════════════════════════════════════════════════════════════════
# Install System Dependencies
# ═══════════════════════════════════════════════════════════════════════════

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    vim \
    nano \
    unzip \
    zip \
    jq \
    tree \
    build-essential \
    iputils-ping \
    dnsutils \
    net-tools \
    sudo \
    locales \
    tzdata \
    openssh-client \
    gnupg2 \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# ═══════════════════════════════════════════════════════════════════════════
# Configure Locale & Timezone
# ═══════════════════════════════════════════════════════════════════════════

RUN locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# ═══════════════════════════════════════════════════════════════════════════
# Create Non-Root User
# ═══════════════════════════════════════════════════════════════════════════

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME -s /bin/bash \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# ═══════════════════════════════════════════════════════════════════════════
# Install PowerShell Modules (System-Wide)
# ═══════════════════════════════════════════════════════════════════════════

RUN pwsh -NoProfile -Command ' \
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; \
    Write-Host "Installing PSScriptAnalyzer..." -ForegroundColor Cyan; \
    Install-Module -Name PSScriptAnalyzer -Scope AllUsers -Force -SkipPublisherCheck; \
    Write-Host "Installing Pester..." -ForegroundColor Cyan; \
    Install-Module -Name Pester -MinimumVersion 5.5.0 -Scope AllUsers -Force -SkipPublisherCheck; \
    Write-Host "Installing PowerShell-Yaml..." -ForegroundColor Cyan; \
    Install-Module -Name powershell-yaml -Scope AllUsers -Force -SkipPublisherCheck; \
    Write-Host "Installing PSReadLine..." -ForegroundColor Cyan; \
    Install-Module -Name PSReadLine -Scope AllUsers -Force -SkipPublisherCheck; \
    Write-Host "Installed modules:" -ForegroundColor Green; \
    Get-InstalledModule | Format-Table -AutoSize; \
    '

# ═══════════════════════════════════════════════════════════════════════════
# Copy PowerShell Profile Script
# ═══════════════════════════════════════════════════════════════════════════

USER $USERNAME
WORKDIR /home/$USERNAME

# Create PowerShell profile directory
RUN mkdir -p /home/$USERNAME/.config/powershell

# Copy profile from separate file (created in postCreateCommand.sh)
# This avoids complex escaping issues in Dockerfile

# ═══════════════════════════════════════════════════════════════════════════
# Set Working Directory
# ═══════════════════════════════════════════════════════════════════════════

WORKDIR /workspace

# ═══════════════════════════════════════════════════════════════════════════
# Health Check
# ═══════════════════════════════════════════════════════════════════════════

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pwsh -NoProfile -Command "exit 0"

# Default command
CMD ["pwsh"]