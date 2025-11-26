#!/bin/bash
#
# Installation script for network bandwidth monitoring tools
# Supports Debian/Ubuntu and RHEL/CentOS/Rocky Linux
#

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        print_error "Cannot detect OS"
        exit 1
    fi
    
    print_info "Detected OS: $OS $OS_VERSION"
}

# Install basic network tools
install_basic_tools() {
    print_header "Installing Basic Network Tools"
    
    case $OS in
        ubuntu|debian)
            print_info "Using apt package manager"
            apt update
            apt install -y ethtool pciutils iproute2 net-tools iputils-ping
            print_success "Basic tools installed"
            ;;
        rhel|centos|rocky|almalinux)
            print_info "Using yum/dnf package manager"
            yum install -y ethtool pciutils iproute net-tools iputils
            print_success "Basic tools installed"
            ;;
        *)
            print_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
}

# Install InfiniBand tools
install_ib_tools() {
    print_header "Installing InfiniBand Tools"
    
    case $OS in
        ubuntu|debian)
            apt install -y infiniband-diags libibverbs-dev ibverbs-utils \
                           librdmacm-dev rdmacm-utils perftest
            print_success "InfiniBand tools installed"
            ;;
        rhel|centos|rocky|almalinux)
            yum install -y infiniband-diags libibverbs libibverbs-utils \
                          librdmacm rdma-core perftest
            print_success "InfiniBand tools installed"
            ;;
        *)
            print_error "Unsupported OS: $OS"
            return 1
            ;;
    esac
}

# Install monitoring tools
install_monitoring_tools() {
    print_header "Installing Network Monitoring Tools"
    
    case $OS in
        ubuntu|debian)
            apt install -y iftop nethogs nload bmon iperf3 sysstat
            print_success "Monitoring tools installed"
            ;;
        rhel|centos|rocky|almalinux)
            # Enable EPEL for some tools
            if ! rpm -q epel-release >/dev/null 2>&1; then
                print_info "Installing EPEL repository"
                yum install -y epel-release
            fi
            yum install -y iftop nethogs nload bmon iperf3 sysstat
            print_success "Monitoring tools installed"
            ;;
        *)
            print_error "Unsupported OS: $OS"
            return 1
            ;;
    esac
}

# Install Python dependencies
install_python_deps() {
    print_header "Installing Python Dependencies"
    
    if ! command -v python3 &> /dev/null; then
        print_warning "Python 3 not found, installing..."
        case $OS in
            ubuntu|debian)
                apt install -y python3 python3-pip
                ;;
            rhel|centos|rocky|almalinux)
                yum install -y python3 python3-pip
                ;;
        esac
    fi
    
    print_success "Python 3 is available"
}

# Information about MLNX_OFED
show_mlnx_ofed_info() {
    print_header "MLNX_OFED Driver (Optional but Recommended)"
    
    echo ""
    echo "For best performance with ConnectX-7, install MLNX_OFED:"
    echo ""
    echo "1. Download from:"
    echo "   https://network.nvidia.com/products/infiniband-drivers/linux/mlnx_ofed/"
    echo ""
    echo "2. Choose your OS version and download the appropriate package"
    echo ""
    echo "3. Install:"
    case $OS in
        ubuntu|debian)
            echo "   tar xzf MLNX_OFED_LINUX-*-ubuntu*.tgz"
            echo "   cd MLNX_OFED_LINUX-*/"
            echo "   sudo ./mlnxofedinstall --all"
            ;;
        rhel|centos|rocky|almalinux)
            echo "   tar xzf MLNX_OFED_LINUX-*-rhel*.tgz"
            echo "   cd MLNX_OFED_LINUX-*/"
            echo "   sudo ./mlnxofedinstall --all"
            ;;
    esac
    echo ""
    echo "4. Restart driver:"
    echo "   sudo /etc/init.d/openibd restart"
    echo ""
}

# Information about MFT
show_mft_info() {
    print_header "Mellanox Firmware Tools (Optional)"
    
    echo ""
    echo "For advanced management and configuration:"
    echo ""
    echo "1. Download from:"
    echo "   https://network.nvidia.com/products/adapter-software/firmware-tools/"
    echo ""
    echo "2. Install:"
    case $OS in
        ubuntu|debian)
            echo "   wget https://www.mellanox.com/downloads/MFT/mft-*-x86_64-deb.tgz"
            echo "   tar xzf mft-*-x86_64-deb.tgz"
            echo "   cd mft-*/"
            echo "   sudo ./install.sh"
            ;;
        rhel|centos|rocky|almalinux)
            echo "   wget https://www.mellanox.com/downloads/MFT/mft-*-x86_64-rpm.tgz"
            echo "   tar xzf mft-*-x86_64-rpm.tgz"
            echo "   cd mft-*/"
            echo "   sudo ./install.sh"
            ;;
    esac
    echo ""
    echo "3. Start MST service:"
    echo "   sudo mst start"
    echo ""
}

# Test installation
test_installation() {
    print_header "Testing Installation"
    
    echo ""
    
    # Test basic tools
    tools=("ethtool" "lspci" "ip" "ifconfig")
    for tool in "${tools[@]}"; do
        if command -v $tool &> /dev/null; then
            print_success "$tool installed"
        else
            print_warning "$tool not found"
        fi
    done
    
    # Test IB tools
    ib_tools=("ibstat" "ibv_devinfo")
    for tool in "${ib_tools[@]}"; do
        if command -v $tool &> /dev/null; then
            print_success "$tool installed"
        else
            print_warning "$tool not found (install InfiniBand tools if needed)"
        fi
    done
    
    # Test monitoring tools
    mon_tools=("iftop" "nload" "iperf3")
    for tool in "${mon_tools[@]}"; do
        if command -v $tool &> /dev/null; then
            print_success "$tool installed"
        else
            print_warning "$tool not found"
        fi
    done
    
    # Test Python
    if command -v python3 &> /dev/null; then
        py_version=$(python3 --version)
        print_success "Python 3 installed: $py_version"
    else
        print_error "Python 3 not found"
    fi
    
    echo ""
}

# Main installation flow
main() {
    echo -e "${GREEN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Network Tools Installation Script                        ║"
    echo "║  For NVIDIA ConnectX-7 Bandwidth Monitoring                ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Check root
    check_root
    
    # Detect OS
    detect_os
    
    # Ask user what to install
    echo ""
    echo "What would you like to install?"
    echo ""
    echo "1) Basic network tools only (ethtool, lspci, iproute2)"
    echo "2) Basic + InfiniBand tools"
    echo "3) Basic + InfiniBand + Monitoring tools (iftop, nload, etc.)"
    echo "4) Everything (recommended)"
    echo "5) Show info about MLNX_OFED and MFT only"
    echo "6) Exit"
    echo ""
    read -p "Enter your choice [1-6]: " choice
    
    case $choice in
        1)
            install_basic_tools
            install_python_deps
            ;;
        2)
            install_basic_tools
            install_ib_tools
            install_python_deps
            ;;
        3)
            install_basic_tools
            install_ib_tools
            install_monitoring_tools
            install_python_deps
            ;;
        4)
            install_basic_tools
            install_ib_tools
            install_monitoring_tools
            install_python_deps
            show_mlnx_ofed_info
            show_mft_info
            ;;
        5)
            show_mlnx_ofed_info
            show_mft_info
            exit 0
            ;;
        6)
            print_info "Installation cancelled"
            exit 0
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
    
    # Test installation
    test_installation
    
    # Final message
    print_header "Installation Complete!"
    echo ""
    print_success "All requested tools have been installed"
    echo ""
    echo "Next steps:"
    echo "  1. Run: ./quick_check_nic.sh"
    echo "  2. Run: python3 monitor_bandwidth.py -l"
    echo "  3. Read: CX7_NIC_BANDWIDTH_GUIDE.md"
    echo ""
    
    # Show advanced tools info if full install
    if [ "$choice" = "4" ]; then
        echo "For optimal CX7 performance, consider installing:"
        echo "  - MLNX_OFED driver"
        echo "  - Mellanox Firmware Tools (MFT)"
        echo ""
        echo "Scroll up to see installation instructions."
        echo ""
    fi
}

# Run main function
main
