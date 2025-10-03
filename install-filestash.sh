#!/bin/bash

# Filestash Native Installation Script
# This script installs Filestash dependencies, builds the application, and sets up systemd service

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/filestash"
USER="filestash"
SERVICE_NAME="filestash"

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

install_dependencies() {
    log "Installing system dependencies..."

    # Update package list
    apt-get update

    # Install required packages
    apt-get install -y \
        curl \
        make \
        gcc \
        g++ \
        git \
        ffmpeg \
        libjpeg-dev \
        libtiff-dev \
        libpng-dev \
        libwebp-dev \
        libraw-dev \
        libheif-dev \
        libgif-dev \
        libvips-dev \
        pkg-config \
        build-essential \
        cmake \
        ca-certificates

    log "System dependencies installed successfully"
}

install_webp_with_sharpyuv() {
    log "Installing WebP with libsharpyuv support..."

    # Create temporary directory
    TEMP_DIR="/tmp/webp-build"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"

    # Download WebP 1.3.2 source
    WEBP_VERSION="1.3.2"
    curl -L "https://github.com/webmproject/libwebp/archive/v${WEBP_VERSION}.tar.gz" -o libwebp.tar.gz
    tar -xzf libwebp.tar.gz
    cd "libwebp-${WEBP_VERSION}"

    # Build and install
    mkdir build
    cd build
    cmake .. -DCMAKE_BUILD_TYPE=Release -DWEBP_BUILD_SHARPYUV=ON
    make -j$(nproc)
    make install

    # Update library cache
    ldconfig

    # Clean up
    cd /
    rm -rf "$TEMP_DIR"

    log "WebP with libsharpyuv installed successfully"
}

install_go() {
    log "Installing Go 1.24..."

    # Remove existing Go installation
    rm -rf /usr/local/go

    # Download and install Go 1.24
    GO_VERSION="1.24.0"
    GO_ARCH="linux-amd64"

    curl -L "https://go.dev/dl/go${GO_VERSION}.${GO_ARCH}.tar.gz" -o /tmp/go.tar.gz
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm /tmp/go.tar.gz

    # Add Go to PATH
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    export PATH=$PATH:/usr/local/go/bin

    log "Go ${GO_VERSION} installed successfully"
}

create_user() {
    log "Creating filestash user..."

    if ! id "$USER" &>/dev/null; then
        useradd --system --home-dir "$INSTALL_DIR" --shell /bin/false "$USER"
        log "User $USER created"
    else
        log "User $USER already exists"
    fi
}

build_filestash() {
    log "Building Filestash..."

    # Store current source directory
    SOURCE_DIR=$(pwd)

    # Create installation directory
    mkdir -p "$INSTALL_DIR"

    # Copy source code to installation directory (only if not already there)
    if [ "$SOURCE_DIR" != "$INSTALL_DIR" ]; then
        cp -r "$SOURCE_DIR"/* "$INSTALL_DIR/"
        cp -r "$SOURCE_DIR"/.[^.]* "$INSTALL_DIR/" 2>/dev/null || true
    fi
    cd "$INSTALL_DIR"

    # Set PATH for Go
    export PATH=$PATH:/usr/local/go/bin

    # Initialize Go modules and build
    make build_init
    make build_backend

    # Create data directory structure
    mkdir -p ./data/state/config/
    cp config/config.json ./data/state/config/config.json

    # Set ownership and permissions
    chown -R "$USER:$USER" "$INSTALL_DIR"
    find "$INSTALL_DIR/data/" -type d -exec chmod 770 {} \;
    find "$INSTALL_DIR/data/" -type f -exec chmod 760 {} \;
    chmod 750 "$INSTALL_DIR/dist/filestash"

    log "Filestash built successfully"
}

create_systemd_service() {
    log "Creating systemd service..."

    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Filestash File Manager
After=network.target
Wants=network.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/dist/filestash
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$INSTALL_DIR
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable service
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"

    log "Systemd service created and enabled"
}

main() {
    log "Starting Filestash installation..."

    check_root
    install_dependencies
    install_webp_with_sharpyuv
    install_go
    create_user
    build_filestash
    create_systemd_service

    log "Installation completed successfully!"
    log "To start Filestash: systemctl start $SERVICE_NAME"
    log "To check status: systemctl status $SERVICE_NAME"
    log "Filestash will be available at http://localhost:8334"
}

main "$@"