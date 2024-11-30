#!/usr/bin/env bash

if [[ $REBUILD_TOOLCHAIN = 'true' ]]; then
    echo -e "\e[1;33m开始打包toolchain\e[0m"
    cd $OPENWRT_PATH
    sed -i 's/ $(tool.*\/stamp-compile)//' Makefile
    [[ -d ".ccache" ]] && (ccache=".ccache"; ls -alh .ccache)
    du -h --max-depth=1 ./staging_dir
    du -h --max-depth=1 ./ --exclude=staging_dir
    [[ -d $GITHUB_WORKSPACE/output ]] || mkdir $GITHUB_WORKSPACE/output
    tar -I zstdmt -cf $GITHUB_WORKSPACE/output/$CACHE_NAME.tzst staging_dir/host* staging_dir/tool* $ccache
    ls -lh $GITHUB_WORKSPACE/output
    [[ -e $GITHUB_WORKSPACE/output/$CACHE_NAME.tzst ]] || \
    echo -e "\e[1;31m打包压缩toolchain失败\e[0m"
    exit 0
fi

color() {
    case $1 in
        cy) echo -e "\033[1;33m$2\033[0m" ;;
        cr) echo -e "\033[1;31m$2\033[0m" ;;
        cg) echo -e "\033[1;32m$2\033[0m" ;;
        cb) echo -e "\033[1;34m$2\033[0m" ;;
    esac
}

status() {
    CHECK=$?
    END_TIME=$(date '+%H:%M:%S')
    _date=" ==> 用时 $[$(date +%s -d "$END_TIME") - $(date +%s -d "$BEGIN_TIME")] 秒"
    [[ $_date =~ [0-9]+ ]] || _date=""
    if [ $CHECK = 0 ]; then
        printf "%-62s %s %s %s %s %s %s %s\n" \
        $(echo -e "$(color cy $STEP_NAME) [ $(color cg ✔) ]${_date}")
    else
        printf "%-62s %s %s %s %s %s %s %s\n" \
        $(echo -e "$(color cy $STEP_NAME) [ $(color cr ✕) ]${_date}")
    fi
}

_find() {
    find $1 -maxdepth 3 -type d -name "$2" -print -quit 2>/dev/null
}

_packages() {
    for z in $@; do
        [[ $z =~ ^# ]] || echo "CONFIG_PACKAGE_$z=y" >>.config
    done
}

_delpackage() {
    for z in $@; do
        [[ $z =~ ^# ]] || sed -i -E "s/(CONFIG_PACKAGE_.*$z)=y/# \1 is not set/" .config
    done
}

_printf() {
    awk '{printf "%s %-40s %s %s %s\n" ,$1,$2,$3,$4,$5}'
}

git_clone() {
    local repo_url branch
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    local target_dir current_dir destination_dir
    if [[ -n "$@" ]]; then
        target_dir="$@"
    else
        target_dir="${repo_url##*/}"
    fi
    if ! git clone -q $branch --depth=1 $repo_url $target_dir; then
        echo -e "$(color cr 拉取) $repo_url [ $(color cr ✕) ]" | _printf
        return 0
    fi
    rm -rf $target_dir/{.git*,README*.md,LICENSE}
    current_dir=$(_find "package/ feeds/ target/" "$target_dir")
    if ([[ -d "$current_dir" ]] && rm -rf $current_dir); then
        mv -f $target_dir ${current_dir%/*}
        echo -e "$(color cg 替换) $target_dir [ $(color cg ✔) ]" | _printf
    else
        destination_dir="package/A"
        [[ -d "$destination_dir" ]] || mkdir -p $destination_dir
        mv -f $target_dir $destination_dir
        echo -e "$(color cb 添加) $target_dir [ $(color cb ✔) ]" | _printf
    fi
}

clone_dir() {
    local repo_url branch
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    local temp_dir=$(mktemp -d) target_dir
    if ! git clone -q $branch --depth=1 $repo_url $temp_dir; then
        echo -e "$(color cr 拉取) $repo_url [ $(color cr ✕) ]" | _printf
        return 0
    fi
    for target_dir in "$@"; do
        local source_dir current_dir destination_dir
        [[ $target_dir =~ ^# ]] && continue
        source_dir=$(_find "$temp_dir" "$target_dir")
        [[ -d "$source_dir" ]] || \
        source_dir=$(find "$temp_dir" -maxdepth 4 -type d -name "$target_dir" -print -quit) && \
        [[ -d "$source_dir" ]] || {
            echo -e "$(color cr 查找) $target_dir [ $(color cr ✕) ]" | _printf
            continue
        }
        current_dir=$(_find "package/ feeds/ target/" "$target_dir")
        if ([[ -d "$current_dir" ]] && rm -rf $current_dir); then
            mv -f $source_dir ${current_dir%/*}
            echo -e "$(color cg 替换) $target_dir [ $(color cg ✔) ]" | _printf
        else
            destination_dir="package/A"
            [[ -d "$destination_dir" ]] || mkdir -p $destination_dir
            mv -f $source_dir $destination_dir
            echo -e "$(color cb 添加) $target_dir [ $(color cb ✔) ]" | _printf
        fi
    done
    rm -rf $temp_dir
}

clone_all() {
    local repo_url branch
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    local temp_dir=$(mktemp -d) target_dir
    if ! git clone -q $branch --depth=1 $repo_url $temp_dir; then
        echo -e "$(color cr 拉取) $repo_url [ $(color cr ✕) ]" | _printf
        return 0
    fi
    for target_dir in $(ls -l $temp_dir/$@ | awk '/^d/{print $NF}'); do
        local source_dir current_dir destination_dir
        source_dir=$(_find "$temp_dir" "$target_dir")
        current_dir=$(_find "package/ feeds/ target/" "$target_dir")
        if ([[ -d "$current_dir" ]] && rm -rf $current_dir); then
            mv -f $source_dir ${current_dir%/*}
            echo -e "$(color cg 替换) $target_dir [ $(color cg ✔) ]" | _printf
        else
            destination_dir="package/A"
            [[ -d "$destination_dir" ]] || mkdir -p $destination_dir
            mv -f $source_dir $destination_dir
            echo -e "$(color cb 添加) $target_dir [ $(color cb ✔) ]" | _printf
        fi
    done
    rm -rf $temp_dir
}

config() {
	case "$TARGET_DEVICE" in
		"x86_64")
			cat >.config<<-EOF
			CONFIG_TARGET_x86=y
			CONFIG_TARGET_x86_64=y
			CONFIG_TARGET_x86_64_DEVICE_generic=y
			CONFIG_TARGET_ROOTFS_PARTSIZE=$PART_SIZE
			CONFIG_BUILD_NLS=y
			CONFIG_BUILD_PATENTED=y
			CONFIG_TARGET_IMAGES_GZIP=y
			CONFIG_GRUB_IMAGES=y
			# CONFIG_GRUB_EFI_IMAGES is not set
			# CONFIG_VMDK_IMAGES is not set
			EOF
   			KERNEL_TARGET=amd64
			;;
		"r1-plus-lts"|"r1-plus"|"r4s"|"r2c"|"r2s")
			cat >.config<<-EOF
			CONFIG_TARGET_rockchip=y
			CONFIG_TARGET_rockchip_armv8=y
			CONFIG_TARGET_ROOTFS_PARTSIZE=$PART_SIZE
			CONFIG_BUILD_NLS=y
			CONFIG_BUILD_PATENTED=y
			CONFIG_DRIVER_11AC_SUPPORT=y
			CONFIG_DRIVER_11N_SUPPORT=y
			CONFIG_DRIVER_11W_SUPPORT=y
			EOF
			case "$TARGET_DEVICE" in
			"r1-plus-lts"|"r1-plus")
			echo "CONFIG_TARGET_rockchip_armv8_DEVICE_xunlong_orangepi-$TARGET_DEVICE=y" >>.config ;;
			"r4s"|"r2c"|"r2s")
			echo "CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-$TARGET_DEVICE=y" >>.config ;;
			esac
   			KERNEL_TARGET=arm64
			;;
		"newifi-d2")
			cat >.config<<-EOF
			CONFIG_TARGET_ramips=y
			CONFIG_TARGET_ramips_mt7621=y
			CONFIG_TARGET_ramips_mt7621_DEVICE_d-team_newifi-d2=y
			EOF
			;;
		"phicomm_k2p")
			cat >.config<<-EOF
			CONFIG_TARGET_ramips=y
			CONFIG_TARGET_ramips_mt7621=y
			CONFIG_TARGET_ramips_mt7621_DEVICE_phicomm_k2p=y
			EOF
			;;
		"asus_rt-n16")
			cat >.config<<-EOF
			CONFIG_TARGET_bcm47xx=y
			CONFIG_TARGET_bcm47xx_mips74k=y
			CONFIG_TARGET_bcm47xx_mips74k_DEVICE_asus_rt-n16=y
			EOF
			;;
		"armvirt-64-default")
			cat >.config<<-EOF
			CONFIG_TARGET_armvirt=y
			CONFIG_TARGET_armvirt_64=y
			CONFIG_TARGET_armvirt_64_DEVICE_generic=y
			EOF
   			KERNEL_TARGET=arm64
			;;
	esac
}

if [[ "$REPO_BRANCH" =~ 21.02|18.06 ]]; then
    echo -e "\e[1;31m您选择的源码分支不存在，请重新选择源码分支\e[0m"
    exit 1
fi

REPO_URL="https://github.com/coolsnowwolf/lede"
echo "REPO_URL=$REPO_URL" >>$GITHUB_ENV
STEP_NAME='拉取编译源码'; BEGIN_TIME=$(date '+%H:%M:%S')
#cd /workdir
git clone -q $REPO_URL openwrt
status
#ln -sf /workdir/openwrt $GITHUB_WORKSPACE/openwrt
[[ -d openwrt ]] && cd openwrt || exit
echo "OPENWRT_PATH=$PWD" >> $GITHUB_ENV

[[ $REPO_BRANCH == master ]] && sed -i '/luci/s/^#//; /openwrt-23.05/s/^/#/' feeds.conf.default

STEP_NAME='生成全局变量'; BEGIN_TIME=$(date '+%H:%M:%S')
config
make defconfig 1>/dev/null 2>&1

SOURCE_REPO=$(basename $REPO_URL)
echo "SOURCE_REPO=$SOURCE_REPO" >> $GITHUB_ENV
echo "LITE_BRANCH=${REPO_BRANCH#*-}" >> $GITHUB_ENV

TARGET_NAME=$(awk -F '"' '/CONFIG_TARGET_BOARD/{print $2}' .config)
SUBTARGET_NAME=$(awk -F '"' '/CONFIG_TARGET_SUBTARGET/{print $2}' .config)
DEVICE_TARGET=$TARGET_NAME-$SUBTARGET_NAME
echo "DEVICE_TARGET=$DEVICE_TARGET" >>$GITHUB_ENV

KERNEL=$(grep -oP 'KERNEL_PATCHVER:=\K[^ ]+' target/linux/$TARGET_NAME/Makefile)
KERNEL_VERSION=$(awk -F '-' '/KERNEL/{print $2}' include/kernel-$KERNEL | awk '{print $1}')
echo "KERNEL_VERSION=$KERNEL_VERSION" >> $GITHUB_ENV

TOOLS_HASH=$(git log --pretty=tformat:"%h" -n1 tools toolchain)
CACHE_NAME="$SOURCE_REPO-${REPO_BRANCH#*-}-$DEVICE_TARGET-cache-$TOOLS_HASH"
echo "CACHE_NAME=$CACHE_NAME" >>$GITHUB_ENV
status

#CACHE_URL=$(curl -sL api.github.com/repos/$GITHUB_REPOSITORY/releases | awk -F '"' '/download_url/{print $4}' | grep $CACHE_NAME)
curl -sL api.github.com/repos/$GITHUB_REPOSITORY/releases | grep -oP 'download_url": "\K[^"]*cache[^"]*' >cache_url
if (grep -q "$CACHE_NAME" cache_url); then
    STEP_NAME='下载toolchain编译工具'; BEGIN_TIME=$(date '+%H:%M:%S')
    wget -qc -t=3 $(grep "$CACHE_NAME" cache_url)
    [ -e *.tzst ]; status
    STEP_NAME='部署toolchain编译工具'; BEGIN_TIME=$(date '+%H:%M:%S')
    tar -I unzstd -xf *.tzst || tar -xf *.tzst
    [ -d staging_dir ] && sed -i 's/ $(tool.*\/stamp-compile)//' Makefile
    status; rm cache_url
else
    echo "REBUILD_TOOLCHAIN=true" >>$GITHUB_ENV
fi

STEP_NAME='更新&安装插件'; BEGIN_TIME=$(date '+%H:%M:%S')
./scripts/feeds update -a 1>/dev/null 2>&1
./scripts/feeds install -a 1>/dev/null 2>&1
status

color cy "添加&替换插件"
clone_all https://github.com/hong0980/build
clone_all https://github.com/fw876/helloworld
clone_all https://github.com/xiaorouji/openwrt-passwall-packages

[ "$TARGET_DEVICE" != phicomm_k2p -a "$TARGET_DEVICE" != newifi-d2 ] && {
    git_clone https://github.com/zzsj0928/luci-app-pushbot
    git_clone https://github.com/yaof2/luci-app-ikoolproxy
    clone_all https://github.com/destan19/OpenAppFilter
    # clone_dir https://github.com/sbwml/openwrt_helloworld xray-core v2ray-core v2ray-geodata sing-box
    clone_dir https://github.com/vernesong/OpenClash luci-app-openclash
    clone_dir https://github.com/sirpdboy/luci-app-cupsd luci-app-cupsd cups
    clone_dir https://github.com/xiaorouji/openwrt-passwall luci-app-passwall
    clone_dir https://github.com/xiaorouji/openwrt-passwall2 luci-app-passwall2
    clone_dir https://github.com/kiddin9/kwrt-packages luci-app-adguardhome adguardhome luci-app-bypass lua-neturl cpulimit
    clone_all https://github.com/brvphoenix/wrtbwmon
    git_clone master https://github.com/UnblockNeteaseMusic/luci-app-unblockneteasemusic
    sed -i '/log_check/s/^/#/' $(_find "package/ feeds/" "luci-app-unblockneteasemusic")/root/etc/init.d/unblockneteasemusic
}

STEP_NAME='加载个人设置'; BEGIN_TIME=$(date '+%H:%M:%S')

config

cat >>.config <<-EOF
	CONFIG_KERNEL_BUILD_USER="buy404"
	CONFIG_KERNEL_BUILD_DOMAIN="OpenWrt"
	CONFIG_PACKAGE_luci-app-accesscontrol=y
	CONFIG_PACKAGE_luci-app-bridge=y
	CONFIG_PACKAGE_luci-app-cowb-speedlimit=y
	CONFIG_PACKAGE_luci-app-cowbping=y
	CONFIG_PACKAGE_luci-app-cpulimit=y
	CONFIG_PACKAGE_luci-app-ddnsto=y
	CONFIG_PACKAGE_luci-app-filebrowser=y
	CONFIG_PACKAGE_luci-app-filetransfer=y
	CONFIG_PACKAGE_luci-app-network-settings=y
	CONFIG_PACKAGE_luci-app-oaf=y
	CONFIG_PACKAGE_luci-app-passwall=y
	CONFIG_PACKAGE_luci-app-timedtask=y
	CONFIG_PACKAGE_luci-app-ssr-plus=y
	CONFIG_PACKAGE_luci-app-wrtbwmon=y
	CONFIG_PACKAGE_luci-app-ttyd=y
	CONFIG_PACKAGE_luci-app-upnp=y
	CONFIG_PACKAGE_luci-app-ikoolproxy=y
	CONFIG_PACKAGE_luci-app-wizard=y
	CONFIG_PACKAGE_luci-app-simplenetwork=y
	CONFIG_PACKAGE_luci-app-opkg=y
	CONFIG_PACKAGE_automount=y
	CONFIG_PACKAGE_autosamba=y
	CONFIG_PACKAGE_luci-app-diskman=y
	CONFIG_PACKAGE_luci-app-syncdial=y
	CONFIG_PACKAGE_luci-theme-bootstrap=y
	CONFIG_PACKAGE_luci-theme-material=y
	CONFIG_PACKAGE_luci-app-tinynote=y
	CONFIG_PACKAGE_luci-app-arpbind=y
	CONFIG_PACKAGE_luci-app-wifischedule=y
	# CONFIG_PACKAGE_luci-app-unblockmusic is not set
	# CONFIG_PACKAGE_luci-app-wireguard is not set
	# CONFIG_PACKAGE_luci-app-autoreboot is not set
	# CONFIG_PACKAGE_luci-app-ddns is not set
	# CONFIG_PACKAGE_luci-app-ssr-plus is not set
	# CONFIG_PACKAGE_luci-app-zerotier is not set
	# CONFIG_PACKAGE_luci-app-ipsec-vpnd is not set
	# CONFIG_PACKAGE_luci-app-xlnetacc is not set
	# CONFIG_PACKAGE_luci-app-uugamebooster is not set
EOF

_packages "
luci-app-aria2
luci-app-cifs-mount
luci-app-commands
luci-app-hd-idle
luci-app-pushbot
luci-app-eqos
luci-app-softwarecenter
luci-app-log-OpenWrt-19.07
luci-app-transmission
luci-app-usb-printer
luci-app-vssr
luci-app-bypass
luci-app-cupsd
#luci-app-adguardhome
luci-app-openclash
luci-app-weburl
luci-app-wol
luci-theme-material
luci-theme-opentomato
axel patch diffutils collectd-mod-ping collectd-mod-thermal wpad-wolfssl
"

config_generate="package/base-files/files/bin/config_generate"
wget -qO package/base-files/files/etc/banner git.io/JoNK8

case "$TARGET_DEVICE" in
    "x86_64")
        FIRMWARE_TYPE="squashfs-combined"
        [[ -n $DEFAULT_IP ]] && \
        sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' $config_generate || \
        sed -i '/n) ipad/s/".*"/"192.168.2.1"/' $config_generate
        _packages "
        luci-app-adbyby-plus
        #luci-app-amule
        luci-app-deluge
        luci-app-passwall2
        luci-app-dockerman
        luci-app-netdata
        #luci-app-kodexplorer
        luci-app-poweroff
        luci-app-qbittorrent
        luci-app-smartdns
        #luci-app-unblockmusic
        #luci-app-aliyundrive-fuse
        #luci-app-aliyundrive-webdav
        #AmuleWebUI-Reloaded ariang bash htop lscpu lsscsi lsusb nano pciutils screen webui-aria2 zstd tar pv
        #subversion-client #unixodbc #git-http
        "
        sed -i '/easymesh/d' .config
        rm -rf package/lean/rblibtorrent
        # sed -i '/KERNEL_PATCHVER/s/=.*/=6.1/' target/linux/x86/Makefile
        wget -qO package/lean/autocore/files/x86/index.htm \
        https://raw.githubusercontent.com/immortalwrt/luci/openwrt-18.06-k5.4/modules/luci-mod-admin-full/luasrc/view/admin_status/index.htm
        wget -qO package/base-files/files/bin/bpm git.io/bpm && chmod +x package/base-files/files/bin/bpm
        wget -qO package/base-files/files/bin/ansi git.io/ansi && chmod +x package/base-files/files/bin/ansi
        ;;
    "r1-plus-lts"|"r4s"|"r2c"|"r2s")
        FIRMWARE_TYPE="sysupgrade"
        [[ -n $DEFAULT_IP ]] && \
        sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' $config_generate || \
        sed -i '/n) ipad/s/".*"/"192.168.2.1"/' $config_generate
        _packages "
        luci-app-cpufreq
        luci-app-adbyby-plus
        luci-app-dockerman
        luci-app-qbittorrent
        luci-app-turboacc
        luci-app-passwall2
        #luci-app-easymesh
        luci-app-store
        #luci-app-unblockneteasemusic
        #luci-app-amule
        #luci-app-smartdns
        #luci-app-aliyundrive-fuse
        #luci-app-aliyundrive-webdav
        luci-app-deluge
        luci-app-netdata
        htop lscpu lsscsi lsusb #nano pciutils screen zstd pv
        #AmuleWebUI-Reloaded #subversion-client unixodbc #git-http
        "
        wget -qO package/base-files/files/bin/bpm git.io/bpm && chmod +x package/base-files/files/bin/bpm
        wget -qO package/base-files/files/bin/ansi git.io/ansi && chmod +x package/base-files/files/bin/ansi
        sed -i "/interfaces_lan_wan/s/'eth1' 'eth0'/'eth0' 'eth1'/" target/linux/rockchip/*/*/*/*/02_network
        ;;
    "newifi-d2")
        FIRMWARE_TYPE="sysupgrade"
        _packages "luci-app-easymesh"
        _delpackage "ikoolproxy openclash transmission softwarecenter aria2 vssr adguardhome"
        [[ -n $DEFAULT_IP ]] && \
        sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' $config_generate || \
        sed -i '/n) ipad/s/".*"/"192.168.2.1"/' $config_generate
        ;;
    "phicomm_k2p")
        FIRMWARE_TYPE="sysupgrade"
        _packages "luci-app-easymesh"
        _delpackage "samba4 luci-app-usb-printer luci-app-cifs-mount diskman cupsd autosamba automount"
        [[ -n $DEFAULT_IP ]] && \
        sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' $config_generate || \
        sed -i '/n) ipad/s/".*"/"192.168.2.1"/' $config_generate
        ;;
    "asus_rt-n16")
        FIRMWARE_TYPE="n16"
        [[ -n $DEFAULT_IP ]] && \
        sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' $config_generate || \
        sed -i '/n) ipad/s/".*"/"192.168.2.1"/' $config_generate
        ;;
    "armvirt-64-default")
        FIRMWARE_TYPE="$TARGET_DEVICE"
        sed -i '/easymesh/d' .config
        [[ -n $DEFAULT_IP ]] && \
        sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' $config_generate || \
        sed -i '/n) ipad/s/".*"/"192.168.2.1"/' $config_generate
        _packages "attr bash blkid brcmfmac-firmware-43430-sdio brcmfmac-firmware-43455-sdio
        btrfs-progs cfdisk chattr curl dosfstools e2fsprogs f2fs-tools f2fsck fdisk getopt
        hostpad-common htop install-program iperf3 kmod-brcmfmac kmod-brcmutil kmod-cfg80211
        kmod-fs-exfat kmod-fs-ext4 kmod-fs-vfat kmod-mac80211 kmod-rt2800-usb kmod-usb-net
        kmod-usb-net-asix-ax88179 kmod-usb-net-rtl8150 kmod-usb-net-rtl8152 kmod-usb-storage
        kmod-usb-storage-extras kmod-usb-storage-uas kmod-usb2 kmod-usb3 lm-sensors losetup
        lsattr lsblk lscpu lsscsi luci-app-adguardhome luci-app-cpufreq luci-app-dockerman
        luci-app-qbittorrent mkf2fs ntfs-3g parted pv python3 resize2fs tune2fs unzip
        uuidgen wpa-cli wpad wpad-basic xfs-fsck xfs-mkf"
        # wget -qO feeds/luci/applications/luci-app-qbittorrent/Makefile https://raw.githubusercontent.com/immortalwrt/luci/openwrt-18.06/applications/luci-app-qbittorrent/Makefile
        # sed -i 's/-Enhanced-Edition//' feeds/luci/applications/luci-app-qbittorrent/Makefile
        sed -i 's/arm/arm||TARGET_armvirt_64/g' $(_find "package/ feeds/" "luci-app-cpufreq")/Makefile
        sed -i "s/default 160/default $PART_SIZE/" config/Config-images.in
        sed -i 's/services/system/; s/00//' $(_find "package/ feeds/" "luci-app-cpufreq")/luasrc/controller/cpufreq.lua
        [ -d ../opt/openwrt_packit ] && {
        sed -i '{
        s|mv |mv -v |
        s|openwrt-armvirt-64-default-rootfs.tar.gz|$(ls *default-rootfs.tar.gz)|
        s|TGT_IMG=.*|TGT_IMG="${WORK_DIR}/unifreq-openwrt-${SOC}_${BOARD}_k${KERNEL_VERSION}${SUBVER}-$(date "+%Y-%m%d-%H%M").img"|
        }' ../opt/openwrt_packit/mk*.sh
        sed -i '/ KERNEL_VERSION.*flippy/ {s/KERNEL_VERSION.*/KERNEL_VERSION="5.15.4-flippy-67+"/}' ../opt/openwrt_packit/make.env
        }
        ;;
esac

if [[ $REPO_URL =~ "coolsnowwolf" ]]; then
    sed -i "/DISTRIB_DESCRIPTION/ {s/'$/-$SOURCE_REPO-$(date +%Y年%m月%d日)'/}" package/*/*/*/openwrt_release
    sed -i "/VERSION_NUMBER/ s/if.*/if \$(VERSION_NUMBER),\$(VERSION_NUMBER),${REPO_BRANCH#*-}-SNAPSHOT)/" include/version.mk
    sed -i 's/option enabled.*/option enabled 1/' feeds/*/*/*/*/upnpd.config
    sed -i "/listen_https/ {s/^/#/g}" package/*/*/*/files/uhttpd.config
    sed -i 's/UTC/UTC-8/' Makefile
    sed -i "{
            /upnp/d;/banner/d;/openwrt_release/d;/shadow/d
            s|zh_cn|zh_cn\nuci set luci.main.mediaurlbase=/luci-static/bootstrap|
            \$i sed -i 's/root::.*/root:\$1\$V4UetPzk\$CYXluq4wUazHjmCDBCqXF.::0:99999:7:::/g' /etc/shadow\n[ -f '/bin/bash' ] && sed -i '/\\\/ash$/s/ash/bash/' /etc/passwd
            }" $(find package/ -type f -name "*default-settings" 2>/dev/null)
fi

[ "$TARGET_DEVICE" != phicomm_k2p -a "$TARGET_DEVICE" != newifi-d2 ] && {
    for d in $(find feeds/ package/ -type f -name "index.htm" 2>/dev/null); do
        if grep -q "Kernel Version" $d; then
            sed -i 's|os.date(.*|os.date("%F %X") .. " " .. translate(os.date("%A")),|' $d
            sed -i '/<%+footer%>/i<%-\n\tlocal incdir = util.libpath() .. "/view/admin_status/index/"\n\tif fs.access(incdir) then\n\t\tlocal inc\n\t\tfor inc in fs.dir(incdir) do\n\t\t\tif inc:match("%.htm$") then\n\t\t\t\tinclude("admin_status/index/" .. inc:gsub("%.htm$", ""))\n\t\t\tend\n\t\tend\n\t\end\n-%>\n' $d
            sed -i 's| <%=luci.sys.exec("cat /etc/bench.log") or ""%>||' $d
        fi
    done
    _packages "luci-app-argon-config luci-theme-argon"
    sed -i 's/ariang/ariang +webui-aria2/g' feeds/*/*/luci-app-aria2/Makefile
}

echo -e '\nwww.nicept.net' | \
tee -a $(find package/A/luci-* feeds/luci/applications/luci-* -type f -name "black.list" -o -name "proxy_host" 2>/dev/null | grep "ss") >/dev/null

mwan3=feeds/packages/net/mwan3/files/etc/config/mwan3
[[ -f $mwan3 ]] && grep -q "8.8" $mwan3 && \
sed -i '/8.8/d' $mwan3

# echo '<iframe src="https://ip.skk.moe/simple" style="width: 100%; border: 0"></iframe>' | \
# tee -a {$(_find "package/ feeds/" "luci-app-vssr")/*/*/*/status_top.htm,$(_find "package/ feeds/" "luci-app-ssr-plus")/*/*/*/status.htm,$(_find "package/ feeds/" "luci-app-bypass")/*/*/*/status.htm,$(_find "package/ feeds/" "luci-app-passwall")/*/*/*/global/status.htm} >/dev/null
xb=$(_find "package/ feeds/" "luci-app-bypass")
[[ -d $xb ]] && sed -i 's/default y/default n/g' $xb/Makefile
qBittorrent_version=$(curl -sL api.github.com/repos/userdocs/qbittorrent-nox-static/releases/latest | grep -oP 'tag_name.*-\K\d+\.\d+\.\d+')
libtorrent_version=$(curl -sL api.github.com/repos/userdocs/qbittorrent-nox-static/releases/latest | grep -oP 'tag_name.*v\K\d+\.\d+\.\d+')
xc=$(_find "package/ feeds/" "qBittorrent-static")
[[ -d $xc ]] && [[ $qBittorrent_version ]] && \
    sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=${qBittorrent_version:-4.6.5}_v${libtorrent_version:-2.0.10}/" $xc/Makefile
xd=$(_find "package/ feeds/" "luci-app-turboacc")
[[ -d $xd ]] && sed -i '/hw_flow/s/1/0/;/sfe_flow/s/1/0/;/sfe_bridge/s/1/0/' $xd/root/etc/config/turboacc
xe=$(_find "package/ feeds/" "luci-app-ikoolproxy")
[[ -d $xe ]] && sed -i '/echo .*root/ s/echo /[ $time =~ [0-9]+ ] \&\& echo /' $xe/root/etc/init.d/koolproxy
xg=$(_find "package/ feeds/" "luci-app-pushbot")
[[ -d $xg ]] && {
    sed -i "s|-c pushbot|/usr/bin/pushbot/pushbot|" $xg/luasrc/controller/pushbot.lua
    sed -i '/start()/a[ "$(uci get pushbot.@pushbot[0].pushbot_enable)" -eq "0" ] && return 0' $xg/root/etc/init.d/pushbot
}

trv=$(awk -F= '/PKG_VERSION:/{print $2}' feeds/packages/net/transmission/Makefile)
[[ $trv ]] && wget -qO feeds/packages/net/transmission/patches/tr$trv.patch \
raw.githubusercontent.com/hong0980/diy/master/files/transmission/tr$trv.patch 1>/dev/null 2>&1

cat <<-\EOF >feeds/packages/lang/python/python3/files/python3-package-uuid.mk
define Package/python3-uuid
$(call Package/python3/Default)
TITLE:=Python $(PYTHON3_VERSION) UUID module
DEPENDS:=+python3-light +libuuid
endef

$(eval $(call Py3BasePackage,python3-uuid, \
/usr/lib/python$(PYTHON3_VERSION)/uuid.py \
/usr/lib/python$(PYTHON3_VERSION)/lib-dynload/_uuid.$(PYTHON3_SO_SUFFIX) \
))
EOF

sed -i '/config PACKAGE_\$(PKG_NAME)_INCLUDE_SingBox/,$ { /default y/ { s/default y/default n/; :loop; n; b loop } }' $(_find "package/ feeds/" "luci-app-passwall")/Makefile
sed -i '/bridged/d; /deluge/d; /transmission/d' .config

sed -i \
    -e 's?\.\./\.\./luci.mk?$(TOPDIR)/feeds/luci/luci.mk?' \
    -e 's?include \.\./\.\./\(lang\|devel\)?include $(TOPDIR)/feeds/packages/\1?' \
    -e 's/\(\(^\| \|    \)\(PKG_HASH\|PKG_MD5SUM\|PKG_MIRROR_HASH\|HASH\):=\).*/\1skip/' \
package/A/*/Makefile 2>/dev/null

for e in $(ls -d package/A/luci-*/po feeds/luci/applications/luci-*/po); do
    if [[ -d $e/zh-cn && ! -d $e/zh_Hans ]]; then
        ln -s zh-cn $e/zh_Hans 2>/dev/null
    elif [[ -d $e/zh_Hans && ! -d $e/zh-cn ]]; then
        ln -s zh_Hans $e/zh-cn 2>/dev/null
    fi
done

cat >organize.sh<<-EOF
	#!/bin/bash
	[ -d firmware ] || mkdir firmware
	FILE_NAME=\$SOURCE_REPO-\${REPO_BRANCH#*-}-\$KERNEL_VERSION-\$DEVICE_TARGET
	tar -zcf firmware/\$FILE_NAME-packages.tar.gz bin/packages
	[ \$FIRMWARE_TYPE ] && cp -f \$(find bin/targets/ -type f -name "*\$FIRMWARE_TYPE*") firmware
	cd firmware && md5sum * >\$FILE_NAME-md5-config.txt
	sed '/^$/d' \$OPENWRT_PATH/.config >>\$FILE_NAME-md5-config.txt
	# [ \$SOURCE_REPO == immortalwrt ] && \
	# rename 's/immortalwrt/\${{ env.SOURCE_REPO }}-\${{ env.LITE_BRANCH }}/' * || \
	# rename 's/openwrt/\${{ env.SOURCE_REPO }}-\${{ env.LITE_BRANCH }}/' *
	echo "FIRMWARE_PATH=\$PWD" >>\$GITHUB_ENV
EOF
status

[[ $KERNEL_TARGET ]] && {
    STEP_NAME='下载openchash运行内核'; BEGIN_TIME=$(date '+%H:%M:%S')
    [[ -d files/etc/openclash/core ]] || mkdir -p files/etc/openclash/core
    CLASH_META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-$KERNEL_TARGET.tar.gz"
    GEOIP_URL="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geoip.dat"
    GEOSITE_URL="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geosite.dat"
    COUNTRY_URL="https://raw.githubusercontent.com/alecthw/mmdb_china_ip_list/release/Country.mmdb"
    wget -qO- $CLASH_META_URL | tar xOz > files/etc/openclash/core/clash_meta
    wget -qO- $GEOIP_URL > files/etc/openclash/GeoIP.dat
    wget -qO- $GEOSITE_URL > files/etc/openclash/GeoSite.dat
    wget -qO- $COUNTRY_URL > files/etc/openclash/Country.mmdb
    chmod +x files/etc/openclash/core/clash_meta
    status
}


[[ $ZSH_TOOL = 'true' ]] && {
    STEP_NAME='下载zsh终端工具'; BEGIN_TIME=$(date '+%H:%M:%S')
    [[ -d files/root ]] || mkdir -p files/root
    git clone -q https://github.com/ohmyzsh/ohmyzsh files/root/.oh-my-zsh
    git clone -q https://github.com/zsh-users/zsh-autosuggestions files/root/.oh-my-zsh/custom/plugins/zsh-autosuggestions
    git clone -q https://github.com/zsh-users/zsh-syntax-highlighting files/root/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
    git clone -q https://github.com/zsh-users/zsh-completions files/root/.oh-my-zsh/custom/plugins/zsh-completions
	cat >files/root/.zshrc<<-EOF
	# Path to your oh-my-zsh installation.
	ZSH=\$HOME/.oh-my-zsh
	# Set name of the theme to load.
	ZSH_THEME="ys"
	# Uncomment the following line to disable bi-weekly auto-update checks.
	DISABLE_AUTO_UPDATE="true"
	# Which plugins would you like to load?
	plugins=(git command-not-found extract z docker zsh-syntax-highlighting zsh-autosuggestions zsh-completions)
	source \$ZSH/oh-my-zsh.sh
	autoload -U compinit && compinit
	EOF
    status
}

[[ $KERNEL_TARGET ]] && {
    STEP_NAME='下载adguardhome运行内核'; BEGIN_TIME=$(date '+%H:%M:%S')
    [[ -d files/usr/bin/AdGuardHome ]] || mkdir -p files/usr/bin/AdGuardHome
    AGH_CORE="https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_$KERNEL_TARGET.tar.gz"
    wget -qO- $AGH_CORE | tar xOz > files/usr/bin/AdGuardHome/AdGuardHome
    chmod +x files/usr/bin/AdGuardHome/AdGuardHome
    status
}

STEP_NAME='更新配置文件'; BEGIN_TIME=$(date '+%H:%M:%S')
make defconfig 1>/dev/null 2>&1
status

echo -e "$(color cy 当前编译机型) $(color cb $SOURCE_REPO-${REPO_BRANCH#*-}-$TARGET_DEVICE-$KERNEL_VERSION)"

sed -i "s/\$(VERSION_DIST_SANITIZED)/$SOURCE_REPO-${REPO_BRANCH#*-}-$KERNEL_VERSION/" include/image.mk
# sed -i "/IMG_PREFIX:/ {s/=/=$SOURCE_NAME-${REPO_BRANCH#*-}-$KERNEL_VERSION-\$(shell date +%y.%m.%d)-/}" include/image.mk

echo "UPLOAD_BIN_DIR=false" >>$GITHUB_ENV
echo "FIRMWARE_TYPE=$FIRMWARE_TYPE" >>$GITHUB_ENV

echo -e "\e[1;35m脚本运行完成！\e[0m"
