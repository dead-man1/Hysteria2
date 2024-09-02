check_os_version() {
    local os_name os_version

    if [ -f /etc/os-release ]; then
        os_name=$(grep '^ID=' /etc/os-release | cut -d= -f2)
        os_version=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    else
        echo "Unsupported OS or unable to determine OS version."
        exit 1
    fi

    if ! command -v bc &> /dev/null; then
        echo "The 'bc' command is required but not installed. Installing..."
        apt update && apt install -y bc
    fi

    if [[ "$os_name" == "ubuntu" && $(echo "$os_version >= 22" | bc) -eq 1 ]] ||
       [[ "$os_name" == "debian" && $(echo "$os_version >= 11" | bc) -eq 1 ]]; then
        return 0
    else
        echo "This script is only supported on Ubuntu 22+ or Debian 11+."
        exit 1
    fi
}

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

check_os_version

REQUIRED_PACKAGES=("jq" "qrencode" "curl" "pwgen" "uuid-runtime" "python3" "python3-pip" "python3-venv" "git" "bc" "zip")
MISSING_PACKAGES=()

for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! command -v "$package" &> /dev/null; then
        MISSING_PACKAGES+=("$package")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
    echo "The following packages are missing and will be installed: ${MISSING_PACKAGES[@]}"
    apt update && apt upgrade -y
    apt install -y "${MISSING_PACKAGES[@]}"
else
    echo "All required packages are already installed."
fi

git clone https://github.com/ReturnFI/Hysteria2 /etc/hysteria

cd /etc/hysteria
python3 -m venv hysteria2_venv
source /etc/hysteria/hysteria2_venv/bin/activate
pip install -r requirements.txt

if ! grep -q "alias hys2='source /etc/hysteria/hysteria2_venv/bin/activate && /etc/hysteria/menu.sh'" ~/.bashrc; then
    echo "alias hys2='source /etc/hysteria/hysteria2_venv/bin/activate && /etc/hysteria/menu.sh'" >> ~/.bashrc
    source ~/.bashrc
fi

cd /etc/hysteria
chmod +x menu.sh
./menu.sh
