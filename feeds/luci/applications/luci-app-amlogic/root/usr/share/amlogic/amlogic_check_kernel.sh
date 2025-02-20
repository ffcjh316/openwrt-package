#!/bin/bash

# Set a fixed value
CHECK_OPTION=${1}
DOWNLOAD_VERSION=${2}
EMMC_NAME=$(lsblk | grep -oE '(mmcblk[0-9])' | sort | uniq)
KERNEL_DOWNLOAD_PATH="/mnt/${EMMC_NAME}p4"
TMP_CHECK_DIR="/tmp/amlogic"
START_LOG="${TMP_CHECK_DIR}/amlogic_check_kernel.log"
LOG_FILE="${TMP_CHECK_DIR}/amlogic.log"
LOGTIME=$(date "+%Y-%m-%d %H:%M:%S")
[[ -d ${TMP_CHECK_DIR} ]] || mkdir -p ${TMP_CHECK_DIR}

# Log function
tolog() {
    echo -e "${1}" >$START_LOG
    echo -e "${LOGTIME} ${1}" >>$LOG_FILE
    [[ -z "${2}" ]] || exit 1
}

# # Step 2: URL formatting start -----------------------------------------------------------
#
# 01. Download server version documentation
tolog "01. Start checking the kernel version."
SERVER_FIRMWARE_URL=$(uci get amlogic.config.amlogic_firmware_repo 2>/dev/null)
[[ ! -z "${SERVER_FIRMWARE_URL}" ]] || tolog "01.01 The custom kernel download repo is invalid." "1"
SERVER_KERNEL_PATH=$(uci get amlogic.config.amlogic_kernel_path 2>/dev/null)
[[ ! -z "${SERVER_KERNEL_PATH}" ]] || tolog "01.02 The custom kernel download path is invalid." "1"
#
# Supported format:
#
# SERVER_FIRMWARE_URL="https://github.com/ophub/amlogic-s9xxx-openwrt"
# SERVER_FIRMWARE_URL="ophub/amlogic-s9xxx-openwrt"
#
# SERVER_KERNEL_PATH="https://github.com/ophub/amlogic-s9xxx-openwrt/tree/main/amlogic-s9xxx/amlogic-kernel"
# SERVER_KERNEL_PATH="https://github.com/ophub/amlogic-s9xxx-openwrt/trunk/amlogic-s9xxx/amlogic-kernel"
# SERVER_KERNEL_PATH="amlogic-s9xxx/amlogic-kernel"
#
if [[ ${SERVER_FIRMWARE_URL} == http* ]]; then
    SERVER_FIRMWARE_URL=${SERVER_FIRMWARE_URL#*com\/}
fi

if [[ ${SERVER_KERNEL_PATH} == http* && $(echo ${SERVER_KERNEL_PATH} | grep "tree") != "" ]]; then
    # Left part
    SERVER_KERNEL_PATH_LEFT=${SERVER_KERNEL_PATH%\/tree*}
    SERVER_KERNEL_PATH_LEFT=${SERVER_KERNEL_PATH_LEFT#*com\/}
    SERVER_FIRMWARE_URL=${SERVER_KERNEL_PATH_LEFT}
    # Right part
    SERVER_KERNEL_PATH_RIGHT=${SERVER_KERNEL_PATH#*tree\/}
    SERVER_KERNEL_PATH_RIGHT=${SERVER_KERNEL_PATH_RIGHT#*\/}
    SERVER_KERNEL_PATH=${SERVER_KERNEL_PATH_RIGHT}
elif [[ ${SERVER_KERNEL_PATH} == http* && $(echo ${SERVER_KERNEL_PATH} | grep "trunk") != "" ]]; then
    # Left part
    SERVER_KERNEL_PATH_LEFT=${SERVER_KERNEL_PATH%\/trunk*}
    SERVER_KERNEL_PATH_LEFT=${SERVER_KERNEL_PATH_LEFT#*com\/}
    SERVER_FIRMWARE_URL=${SERVER_KERNEL_PATH_LEFT}
    # Right part
    SERVER_KERNEL_PATH_RIGHT=${SERVER_KERNEL_PATH#*trunk\/}
    SERVER_KERNEL_PATH=${SERVER_KERNEL_PATH_RIGHT}
fi

SERVER_KERNEL_URL="https://api.github.com/repos/${SERVER_FIRMWARE_URL}/contents/${SERVER_KERNEL_PATH}"
# Step 2: URL formatting end -----------------------------------------------------------

# Step 2: Check if there is the latest kernel version
check_kernel() {
    # 01. Query local version information
    tolog "02. Start checking the kernel version."
    CURRENT_KERNEL_V=$(ls /lib/modules/  2>/dev/null | grep -oE '^[1-9].[0-9]{1,2}.[0-9]+')
    tolog "02.01 current version: ${CURRENT_KERNEL_V}"
    sleep 3

    # 03. Version comparison
    tolog "02.02 Compare versions."
    MAIN_LINE_M=$(echo "${CURRENT_KERNEL_V}" | cut -d '.' -f1)
    MAIN_LINE_V=$(echo "${CURRENT_KERNEL_V}" | cut -d '.' -f2)
    MAIN_LINE_S=$(echo "${CURRENT_KERNEL_V}" | cut -d '.' -f3)
    MAIN_LINE="${MAIN_LINE_M}.${MAIN_LINE_V}"

    # Check the version on the server
    LATEST_VERSION=$(curl -s "${SERVER_KERNEL_URL}" | grep "name" | grep -oE "${MAIN_LINE}.[0-9]+"  | sed -e "s/${MAIN_LINE}.//g" | sort -n | sed -n '$p')
    #LATEST_VERSION="124"
    [[ ! -z "${LATEST_VERSION}" ]] || tolog "02.03 Failed to get the version on the server." "1"
    tolog "02.04 current version: ${CURRENT_KERNEL_V}, Latest version: ${MAIN_LINE}.${LATEST_VERSION}"
    sleep 3

    if [[ "${LATEST_VERSION}" -le "${MAIN_LINE_S}" ]]; then
        tolog "02.05 Already the latest version, no need to update." "1"
        sleep 5
        tolog ""
        exit 0
    else
        tolog '<input type="button" class="cbi-button cbi-button-reload" value="Download" onclick="return b_check_kernel(this, '"'download_${MAIN_LINE}.${LATEST_VERSION}'"')"/> '${MAIN_LINE}.${LATEST_VERSION}''
        exit 0
    fi
}

# Step 3: Download the latest kernel version
download_kernel() {
    tolog "03. Start download the kernels."
    if [[ ${DOWNLOAD_VERSION} == download* ]]; then
        DOWNLOAD_VERSION=$(echo "${DOWNLOAD_VERSION}" | cut -d '_' -f2)
        tolog "03.01 The kernel version: ${DOWNLOAD_VERSION}, downloading..."
    else
        tolog "03.02 Invalid parameter" "1"
    fi

    # Delete other residual kernel files
    rm -f ${KERNEL_DOWNLOAD_PATH}/boot-*.tar.gz && sync
    rm -f ${KERNEL_DOWNLOAD_PATH}/dtb-amlogic-*.tar.gz && sync
    rm -f ${KERNEL_DOWNLOAD_PATH}/modules-*.tar.gz && sync

    # Download boot file from the kernel directory under the path: ${SERVER_KERNEL_URL}/${DOWNLOAD_VERSION}/
    SERVER_KERNEL_BOOT="$(curl -s "${SERVER_KERNEL_URL}/${DOWNLOAD_VERSION}" | grep "download_url" | grep -o "https.*/boot-${DOWNLOAD_VERSION}.*.tar.gz" | head -n 1)"
    # Download boot file from current path: ${SERVER_KERNEL_URL}/
    if [ -z "${SERVER_KERNEL_BOOT}" ]; then
        SERVER_KERNEL_BOOT="$(curl -s "${SERVER_KERNEL_URL}" | grep "download_url" | grep -o "https.*/boot-${DOWNLOAD_VERSION}.*.tar.gz" | head -n 1)"
    fi
    SERVER_KERNEL_BOOT_NAME="${SERVER_KERNEL_BOOT##*/}"
    SERVER_KERNEL_BOOT_NAME="${SERVER_KERNEL_BOOT_NAME//%2B/+}"
    wget -c "${SERVER_KERNEL_BOOT}" -O "${KERNEL_DOWNLOAD_PATH}/${SERVER_KERNEL_BOOT_NAME}" >/dev/null 2>&1 && sync
    if [[ "$?" -eq "0" && -s "${KERNEL_DOWNLOAD_PATH}/${SERVER_KERNEL_BOOT_NAME}" ]]; then
        tolog "03.03 The boot file complete."
    else
        tolog "03.04 The boot file failed to download." "1"
    fi
    sleep 3

    # Download dtb file from the kernel directory under the path: ${SERVER_KERNEL_URL}/${DOWNLOAD_VERSION}/
    SERVER_KERNEL_DTB="$(curl -s "${SERVER_KERNEL_URL}/${DOWNLOAD_VERSION}" | grep "download_url" | grep -o "https.*/dtb-amlogic-${DOWNLOAD_VERSION}.*.tar.gz" | head -n 1)"
    # Download dtb file from current path: ${SERVER_KERNEL_URL}/
    if [ -z "${SERVER_KERNEL_DTB}" ]; then
        SERVER_KERNEL_DTB="$(curl -s "${SERVER_KERNEL_URL}" | grep "download_url" | grep -o "https.*/dtb-amlogic-${DOWNLOAD_VERSION}.*.tar.gz" | head -n 1)"
    fi
    SERVER_KERNEL_DTB_NAME="${SERVER_KERNEL_DTB##*/}"
    SERVER_KERNEL_DTB_NAME="${SERVER_KERNEL_DTB_NAME//%2B/+}"
    wget -c "${SERVER_KERNEL_DTB}" -O "${KERNEL_DOWNLOAD_PATH}/${SERVER_KERNEL_DTB_NAME}" >/dev/null 2>&1 && sync
    if [[ "$?" -eq "0" && -s "${KERNEL_DOWNLOAD_PATH}/${SERVER_KERNEL_DTB_NAME}" ]]; then
        tolog "03.05 The dtb file complete."
    else
        tolog "03.06 The dtb file failed to download." "1"
    fi
    sleep 3

    # Download modules file from the kernel directory under the path: ${SERVER_KERNEL_URL}/${DOWNLOAD_VERSION}/
    SERVER_KERNEL_MODULES="$(curl -s "${SERVER_KERNEL_URL}/${DOWNLOAD_VERSION}" | grep "download_url" | grep -o "https.*/modules-${DOWNLOAD_VERSION}.*.tar.gz" | head -n 1)"
    # Download modules file from current path: ${SERVER_KERNEL_URL}/
    if [ -z "${SERVER_KERNEL_MODULES}" ]; then
        SERVER_KERNEL_MODULES="$(curl -s "${SERVER_KERNEL_URL}" | grep "download_url" | grep -o "https.*/modules-${DOWNLOAD_VERSION}.*.tar.gz" | head -n 1)"
    fi
    SERVER_KERNEL_MODULES_NAME="${SERVER_KERNEL_MODULES##*/}"
    SERVER_KERNEL_MODULES_NAME="${SERVER_KERNEL_MODULES_NAME//%2B/+}"
    wget -c "${SERVER_KERNEL_MODULES}" -O "${KERNEL_DOWNLOAD_PATH}/${SERVER_KERNEL_MODULES_NAME}" >/dev/null 2>&1 && sync
    if [[ "$?" -eq "0" && -s "${KERNEL_DOWNLOAD_PATH}/${SERVER_KERNEL_MODULES_NAME}" ]]; then
        tolog "03.07 The modules file complete."
    else
        tolog "03.08 The modules file failed to download." "1"
    fi
    sleep 3

    tolog "04 The kernel is ready, you can update."
    sleep 3

    #echo '<a href="javascript:;" onclick="return amlogic_kernel(this)">Update</a>' >$START_LOG
    tolog '<input type="button" class="cbi-button cbi-button-reload" value="Update" onclick="return amlogic_kernel(this)"/>'

    exit 0
}

getopts 'cd' opts
case $opts in
    c | check)        check_kernel;;
    * | download)     download_kernel;;
esac
