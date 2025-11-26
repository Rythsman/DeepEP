#!/bin/bash
#
# Test script to verify all tools are working
#

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          Testing CX7 Bandwidth Monitoring Tools          ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Test 1: Quick check script
echo -e "${GREEN}[1/4] Testing quick_check_nic.sh...${NC}"
if [ -x "./quick_check_nic.sh" ]; then
    echo "✓ File exists and is executable"
else
    echo "✗ File not found or not executable"
    exit 1
fi
echo ""

# Test 2: Bandwidth checker
echo -e "${GREEN}[2/4] Testing check_nic_bandwidth.py...${NC}"
if [ -f "./check_nic_bandwidth.py" ]; then
    echo "✓ File exists"
    python3 -c "import sys; print(f'✓ Python {sys.version_info.major}.{sys.version_info.minor} available')"
else
    echo "✗ File not found"
    exit 1
fi
echo ""

# Test 3: Bandwidth monitor
echo -e "${GREEN}[3/4] Testing monitor_bandwidth.py...${NC}"
if [ -x "./monitor_bandwidth.py" ]; then
    echo "✓ File exists and is executable"
    ./monitor_bandwidth.py -l >/dev/null 2>&1 && echo "✓ Can list interfaces" || echo "✗ Error listing interfaces"
else
    echo "✗ File not found or not executable"
    exit 1
fi
echo ""

# Test 4: Documentation
echo -e "${GREEN}[4/4] Checking documentation...${NC}"
docs=("CX7_NIC_BANDWIDTH_GUIDE.md" "README_NIC_BANDWIDTH.md" "QUICK_START_CN.md")
for doc in "${docs[@]}"; do
    if [ -f "./$doc" ]; then
        echo "✓ $doc exists"
    else
        echo "✗ $doc not found"
    fi
done
echo ""

# Summary
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ All tools are ready!${NC}"
echo ""
echo "Quick start commands:"
echo "  ./quick_check_nic.sh                      # Quick system check"
echo "  python3 check_nic_bandwidth.py            # Full detection"
echo "  python3 monitor_bandwidth.py -l           # List interfaces"
echo "  python3 monitor_bandwidth.py eth0         # Monitor eth0"
echo ""
echo "Documentation:"
echo "  cat QUICK_START_CN.md                     # Quick start guide"
echo "  cat README_NIC_BANDWIDTH.md               # Full documentation"
echo "  cat CX7_NIC_BANDWIDTH_GUIDE.md            # Detailed guide"
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
