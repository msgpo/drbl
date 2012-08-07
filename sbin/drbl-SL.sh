#!/bin/bash
# Author: Steven Shiau <steven _at_ nchc org tw>
# License: GPL
#
# Note: This code is modified from http://cdprojekte.mattiasschlenker.de/Public/DSL-frominitrd/2.2b-0.0/script/pxedsl.sh
# Ref:
# http://news.mattiasschlenker.de/2006/02/22/pxe-booting-damnsmalllinux/#more-10
#
# SL: Small Linux (Damn Small Linux, Puppy Linux, Clonezilla live, GParted live..)
#
# Load DRBL setting and functions
DRBL_SCRIPT_PATH="${DRBL_SCRIPT_PATH:-/usr/share/drbl/}"

. $DRBL_SCRIPT_PATH/sbin/drbl-conf-functions

# Settings
SL_ISO_URL_EXAMPLE="http://downloads.sourceforge.net/clonezilla/clonezilla-live-1.2.6-24-i686.iso"
# The method for netboot's root file system. "fetch" means the client will download the filesystem.squashfs from tftpd server, "nfsroot" means client will mount the nfs server. By default we use fetch. "nfsroot" only works for Debian-live based system (e.g. Clonezilla live, GParted live...)
rootfs_location="fetch"
# Force to update the PXELinux config file
force_to_update_pxecfg="yes"

# List all supported SL_NAME
# // On 2009/05/25, we remove the support for PLD, INSERT, PUD, since those projects are not developed any more. As for GeeXbox, since we do not have time, it's removed, too.
#supported_SL_dists="DSL PuppyLinux INSERT PLD Debian-live GeeXbox PUD-Linux"
supported_SL_dists="DSL PuppyLinux Clonezilla-live GParted-live"

# The buffer ratio for iso to container
buffer_ratio_for_iso_to_container="1.25"

# The default estimation ratio for client's ram to use this small linux, 
# we estimate it as 3 times of the initrd. For some distribution we might overwrite this value if necessary.
client_ram_to_initrd_ratio="3"

#
batch_mode="off"
# Prompt messages after installation.
booting_messages="on"

# Functions
USAGE() {
  echo "Load small GNU/Linux ($supported_SL_dists) Linux to DRBL environment."
  echo "Usage: $0 [OPTION] [SL-ISO|SL-INDEX]"
  echo "OPTION:"
  language_help_prompt_by_idx_no
  echo "-b, --batch-mode   Run clone in batch mode."
  echo "-i, --install ISO:        Load Small Linux ISO into DRBL environment, you must put the iso file in the current working dir." 
  echo "-d, --distribution DIST:  Assign the small GNU/Linux distribution as DIST. Available names are: $supported_SL_dists."
  echo "-f, --use-nfsroot      By default the boot parameter to load the root file system (e.g. filesystem.squashfs) is fetch. With this option, nfsroot is used. //NOTE// This function only works for live-initramfs based system. E.g. Clonezilla live or GParted live."
  echo "-k, --keep-pxecfg  Keep the pxelinux config file without updating the boot parameters."
  echo "-n, --no-prompt-boot-message  Skip the prompt messages about booting via PXE or etherboot in the end of execution."
  echo "-s, --server-ip IP_ADDR:  Assign the tftp or NFS server's IP address to be used in Clonezilla/GParted live."
  echo "-u, --uninstall DIST:     Uninstall Small Linux DIST."
  echo "-V, --dist-version VER:   Assign the version of small GNU/Linux version number as VER."
  echo "-v, --verbose:     Verbose mode."
  echo "SL-ISO is one of $supported_SL_dists ISO file, used with installation."
  echo "S-L-INDEX is one of $supported_SL_dists, used with uninstallation."
  echo "Ex: To load DSL Linux, run '$0 -i dsl-4.4.10.iso'"
  echo "    To load PuppyLinux, run '$0 -i puppy-4.2.1-k2.6.25.16-seamonkey.iso'"
  echo "    To load Clonezilla live, run '$0 -i clonezilla-live-1.2.2-26.iso'"
  echo "    To load GParted live, run '$0 -i gparted-live-0.4.5-2.iso'"
  for isl in $supported_SL_dists; do
    echo "    To remove $isl, run '$0 -u $isl'"
  done
  echo "    To remove all Small Linux, run '$0 -u all'"
}
#
get_rootfs_location_opt() {
rootfs_location_opt=""
case "$rootfs_location" in
  "fetch") rootfs_location_opt="fetch=tftp://$server_IP/$squashfs_file" ;;
  "nfsroot")
           rootfs_location_opt="netboot=nfs nfsroot=$server_IP:$drbl_common_root/clonezilla-live/" ;;
esac
} # end of get_rootfs_location_opt
# get rootfile
get_SL_rootfile(){
  # this function must be used after iso is mounted, we need to find version inside it for some distribution (such as PLD).
  case "$(echo $SL_OS | tr "[A-Z]" "[a-z]")" in
    dsl|DamnSmallLinux)
       rootfile="$rootfile_path/KNOPPIX"
       # DSL does not have any extra file, the only one is KNOPPIX
       extra_sys_file=""
       ;;
    puppy|PuppyLinux)
       rootfile="$rootfile_path/pup_${SL_VER}.sfs"
       # Puppy 2.12, there is a /zdrv_212.sfs <-- deprecated.
       [ -f "$isomnt/$rootfile_path/zdrv_${SL_VER}.sfs" ] && extra_sys_file="$rootfile_path/zdrv_${SL_VER}.sfs"
       ;;
    clonezilla-live|gparted-live)
       rootfile="$rootfile_path/filesystem.squashfs"
       extra_sys_file=""
       ;;
  esac
} # end of get_SL_rootfile
#
prepare_param_in_pxe_cfg(){
  # This function must be used after ramdisk_size is calculated.
  case "$(echo $SL_OS | tr "[A-Z]" "[a-z]")" in
    dsl|DamnSmallLinux)
       append_param_in_pxe_cfg="ramdisk_size=$ramdisk_size init=/etc/init lang=us apm=power-off vga=791 initrd=$nbi_initrd nomce noapic quiet BOOT_IMAGE=knoppix frominitrd"
       ;;
    puppy|PuppyLinux)
       # from version 216, init is ready when released, and no bootparam_trigger is necessary. Now drbl-SL only supports puppy from version 4.2.1
       bootparam_trigger=""
       use_modified_init="no"
       append_param_in_pxe_cfg="initrd=$nbi_initrd"
       ;;
    clonezilla-live)
       if [ -z "$server_IP" ]; then
         # Find the IP address of this server. Here we choose the first one in the list of those connected to DRBL clients.
         server_IP="$(LC_ALL=C get-all-nic-ip -b | awk -F" " '{print $1}')"
       fi
       get_rootfs_location_opt
       if [ -z "$cl_gp_boot_param" ]; then
         append_param_in_pxe_cfg="initrd=$nbi_initrd boot=live union=aufs noswap noprompt nolocales vga=788 $rootfs_location_opt ocs_server=\"$server_IP\""
       else
         append_param_in_pxe_cfg="initrd=$nbi_initrd $cl_gp_boot_param noprompt $rootfs_location_opt ocs_server=\"$server_IP\""
       fi
       ;;
    gparted-live)
       if [ -z "$server_IP" ]; then
         # Find the IP address of this server. Here we choose the first one in the list, since it's just an example.
         server_IP="$(LC_ALL=C get-all-nic-ip -i | awk -F" " '{print $1}')"
       fi
       get_rootfs_location_opt
       if [ -z "$cl_gp_boot_param" ]; then
         append_param_in_pxe_cfg="initrd=$nbi_initrd boot=live union=aufs noswap noprompt nolocales vga=788 $rootfs_location_opt "
       else
         append_param_in_pxe_cfg="initrd=$nbi_initrd $cl_gp_boot_param noprompt $rootfs_location_opt"
       fi
       ;;
  esac
} # end of prepare_param_in_pxe_cfg
#
create_linuxrc_pxe_initrd_with_rootfs_inserted(){
  case "$initrd_type" in
  ext2)
    # prepare the size for initrd.
    iso_size="$(stat -c "%s" $SL_ISO)" # unit: bytes
    container_need_in_KB="$(echo "scale=0; $iso_size * $buffer_ratio_for_iso_to_container / 1024.0" | bc -l)" # unit: KB
    client_RAM_required="$(echo "scale=0; $container_need_in_KB * $client_ram_to_initrd_ratio / 1024.0" | bc -l)"
    # ramdisk_size is for client booting use (kernel parameter).
    ramdisk_size="$container_need_in_KB"
    echo "New NBI initrd size (uncompressed): $container_need_in_KB KB. Use ramdisk_size=$ramdisk_size in bootparam."
    [ "$BOOTUP" = "color" ] && $SETCOLOR_WARNING
    echo "$msg_RAM_size_for_SL_drbl_client: $client_RAM_required MB."
    [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
    echo "Creating the modified ramdisk will take a while, please be patient."
    
    # Unpack initrd
    echo 'Creating container...'
    dd if=/dev/zero of=$wd/initrd.img bs=1024 count=$container_need_in_KB
    echo 'Formatting container...'
    mkfs.ext2 -q -F -L "${SL_NAME}-initrd" $wd/initrd.img
    echo 'Unpacking old initrd...'
    $uncompress_to_stdout "$oldinitrd" > $wd/oldinitrd.img
    mkdir $wd/initrd.tmp
    mkdir $wd/oldinitrd.tmp
    # Mount initrd
    mount -o loop $wd/initrd.img $wd/initrd.tmp
    mount -o loop $wd/oldinitrd.img $wd/oldinitrd.tmp
    #
    if [ -z "$SL_VER" ]; then
      if [ -e $wd/oldinitrd.tmp/PUPPYVERSION ]; then
        SL_VER="$(cat $wd/oldinitrd.tmp/PUPPYVERSION)"
      elif [ -e $isomnt/GEEXBOX/etc/version ]; then
        # only if the modified version exists, otherwise we ust default one.
        SL_VER_TMP="$(cat $isomnt/GEEXBOX/etc/version)"
        if [ -e "$DRBL_SCRIPT_PATH/setup/files/$SL_NAME/$SL_VER_TMP/linuxrc.$SL_NAME-$SL_VER_TMP.drbl" ]; then
          SL_VER="$SL_VER_TMP"
        else
          SL_VER="default"
        fi
      else
        SL_VER="default"
      fi
    fi
    
    #
    get_SL_rootfile
    prepare_param_in_pxe_cfg
    
    echo 'Copying content of the old initrd...'
    ( cp -a $wd/oldinitrd.tmp/* $wd/initrd.tmp )
    mkdir -p $wd/initrd.tmp/$rootfile_path_in_initrd
    echo 'Copying root image...'
    cp -af $isomnt/$rootfile $wd/initrd.tmp/$rootfile_path_in_initrd/
    if [ -n "$extra_sys_file" ]; then
      cp -af $isomnt/$extra_sys_file $wd/initrd.tmp/$rootfile_path_in_initrd/
    fi
    if [ "$use_modified_init" = "yes" ]; then
      if [ -e $DRBL_SCRIPT_PATH/setup/files/$SL_NAME/$SL_VER/linuxrc.$SL_NAME-$SL_VER.drbl ]; then
      echo "Copying modified linuxrc from $DRBL_SCRIPT_PATH/setup/files/$SL_NAME/$SL_VER/..."
      cp -f $DRBL_SCRIPT_PATH/setup/files/$SL_NAME/$SL_VER/linuxrc.$SL_NAME-$SL_VER.drbl $wd/initrd.tmp/linuxrc
      else
      echo "Copying modified linuxrc from $DRBL_SCRIPT_PATH/setup/files/$SL_NAME/default/..."
      cp -f $DRBL_SCRIPT_PATH/setup/files/$SL_NAME/default/linuxrc.$SL_NAME-default.drbl $wd/initrd.tmp/linuxrc
      fi
    else
      echo "The linuxrc from $SL_FULL_NAME is ready for PXE boot."
    fi
    
    # Umount initrd
    umount $wd/initrd.tmp
    umount $wd/oldinitrd.tmp
    
    # Pack the initrd again:
    echo 'Packing initrd...'
    $compress_to_stdout $wd/initrd.img > $pxecfg_pd/$nbi_initrd
    
    # Remove the initrd
    echo 'Removing temporary copy of initrd...'
    rm $wd/initrd.img
    # Remove the old original initrd
    echo 'Removing temporary copy of original initrd...'
    rm $wd/oldinitrd.img
    
    # Copy the linux kernel
    cp -f "$kernel" $pxecfg_pd/$nbi_kernel
    ;;

  cpio)
    mkdir -p $wd/initrd.tmp
    mkdir -p $wd/oldinitrd.tmp
    (cd $wd/oldinitrd.tmp/; $uncompress_to_stdout "$oldinitrd" | cpio -idm)
    #
    if [ -z "$SL_VER" ]; then
      if [ -e $wd/oldinitrd.tmp/PUPPYVERSION ]; then
        SL_VER="$(cat $wd/oldinitrd.tmp/PUPPYVERSION)"
      else
        SL_VER="default"
      fi
    fi
    
    #
    get_SL_rootfile
    prepare_param_in_pxe_cfg
    
    echo 'Copying content of the old initrd...'
    ( cp -a $wd/oldinitrd.tmp/* $wd/initrd.tmp/ )
    mkdir -p $wd/initrd.tmp/$rootfile_path_in_initrd
    echo 'Copying root image...'
    cp -a $isomnt/$rootfile $wd/initrd.tmp/$rootfile_path_in_initrd/
    if [ -n "$extra_sys_file" ]; then
      cp -af $isomnt/$extra_sys_file $wd/initrd.tmp/$rootfile_path_in_initrd/
    fi
    if [ "$use_modified_init" = "yes" ]; then
      echo "Copying modified linuxrc from $DRBL_SCRIPT_PATH/setup/files/$SL_NAME/$SL_VER/..."
      cp -f $DRBL_SCRIPT_PATH/setup/files/$SL_NAME/$SL_VER/linuxrc.$SL_NAME-$SL_VER.drbl $wd/initrd.tmp/linuxrc
    else
      echo "The linuxrc from $SL_FULL_NAME is ready for PXE boot."
    fi
    
    # Pack the initrd again:
    echo "Packing the new initrd... $msg_this_might_take_several_minutes..."
    (cd $wd/initrd.tmp/; find . | cpio -o -H newc | gzip -9 > $pxecfg_pd/$nbi_initrd)
    
    # Remove the working dir
    echo 'Removing temporary working dir...'
    [ -d "$wd" -a -n "$(echo $wd | grep "drbl_sl_wd")" ] && rm -rf $wd
    
    # Copy the linux kernel
    cp -f "$kernel" $pxecfg_pd/$nbi_kernel
    ;;
  esac
} # end of create_linuxrc_pxe_initrd_with_rootfs_inserted

#
put_pxe_initrd_without_rootfs_inserted(){
  #///NOTE/// This function is deprecated! We keep it just in case we need in the future.
  cp -f $oldinitrd $pxecfg_pd/$nbi_initrd
  initrd_size="$(stat -c "%s" $pxecfg_pd/$nbi_initrd)" # unit: bytes
  initrd_size_in_KB=$(echo "scale=0; $initrd_size / 1024.0" | bc -l)
  client_RAM_required="$(echo "scale=0; $initrd_size_in_KB * $client_ram_to_initrd_ratio / 1024.0" | bc -l)"
  # ramdisk_size is for client booting use (kernel parameter).
  ramdisk_size="$initrd_size_in_KB"
  echo "New NBI initrd size (uncompressed): $initrd_size_in_KB KB. Use ramdisk_size=$ramdisk_size in bootparam."
  [ "$BOOTUP" = "color" ] && $SETCOLOR_WARNING
  echo "$msg_RAM_size_for_SL_drbl_client: $client_RAM_required MB."
  [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
  get_SL_rootfile
  prepare_param_in_pxe_cfg
  # Copy the linux kernel
  cp -f $kernel $pxecfg_pd/$nbi_kernel
  chmod 644 $pxecfg_pd/$nbi_kernel $pxecfg_pd/$nbi_initrd
} # end of put_pxe_initrd_without_rootfs_inserted
#
create_casper_pxe_initrd_with_rootfs_inserted(){
  #///NOTE/// This function is deprecated! We keep it just in case we need in the future.
  case "$(echo $SL_OS | tr "[A-Z]" "[a-z]")" in
    debian-live-etch|Debian-live)
      [ -z "$SL_VER" ] && SL_VER="etch"
      get_SL_rootfile
      # it's initramfs, so no more loop mount, just use cpio
      mkdir $wd/initrd.tmp
      (cd $wd/initrd.tmp; $uncompress_to_stdout "$oldinitrd" | cpio -idm)
      mkdir -p $wd/initrd.tmp/$rootfile_path_in_initrd
      echo "Copying root image. $msg_this_might_take_several_minutes"
      cp -f $isomnt/$rootfile $wd/initrd.tmp/$rootfile_path_in_initrd/
      if [ "$use_modified_init" = "yes" ]; then
        echo "Copying modified casper from $DRBL_SCRIPT_PATH/setup/files/$SL_NAME/$SL_VER/..."
        cp -f $DRBL_SCRIPT_PATH/setup/files/$SL_NAME/$SL_VER/casper.$SL_NAME-$SL_VER.drbl $wd/initrd.tmp/scripts/casper
      fi
      # create initramfs
      echo "Creating initramfs $pxecfg_pd/$nbi_initrd, $msg_this_might_take_several_minutes"
      ( cd $wd/initrd.tmp
        find . | cpio --quiet -o -H newc | gzip -9 > $pxecfg_pd/$nbi_initrd
      )
      initramfs_size="$(stat -c "%s" $pxecfg_pd/$nbi_initrd)" # unit: bytes
      initramfs_size_in_KB=$(echo "scale=0; $initramfs_size / 1024.0" | bc -l)
      client_RAM_required="$(echo "scale=0; $initramfs_size_in_KB * $client_ram_to_initrd_ratio / 1024.0" | bc -l)"
      # initramfs, we do not have to assign ramdisk_size in bootparam.
      echo "The new initrd size is: $initramfs_size_in_KB KB."
      [ "$BOOTUP" = "color" ] && $SETCOLOR_WARNING
      echo "$msg_RAM_size_for_SL_drbl_client: $client_RAM_required MB."
      [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
      prepare_param_in_pxe_cfg
      cp -f $kernel $pxecfg_pd/$nbi_kernel
      chmod 644 $pxecfg_pd/$nbi_kernel $pxecfg_pd/$nbi_initrd
      ;;
    PUD|pud)
      if [ -z "$SL_VER" ]; then
        # iso file name is like PUD-0.4.6.10.iso, try to guess.
        SL_VER="$(basename $SL_ISO | sed -e "s/^PUD-//g" -e "s/.iso$//g")"
      fi
      get_SL_rootfile
      # it's initramfs, so no more loop mount, just use cpio
      mkdir $wd/initrd.tmp
      (cd $wd/initrd.tmp; $uncompress_to_stdout "$oldinitrd" | cpio -idm)
      mkdir -p $wd/initrd.tmp/$rootfile_path_in_initrd
      echo "Copying root image. $msg_this_might_take_several_minutes"
      cp -f $isomnt/$rootfile $wd/initrd.tmp/$rootfile_path_in_initrd/
      if [ "$use_modified_init" = "yes" ]; then
        echo "Copying modified casper from $DRBL_SCRIPT_PATH/setup/files/$SL_NAME/$SL_VER/..."
        cp -f $DRBL_SCRIPT_PATH/setup/files/$SL_NAME/$SL_VER/casper.$SL_NAME-$SL_VER.drbl $wd/initrd.tmp/scripts/casper
      else
        echo "The linuxrc from $SL_FULL_NAME is ready for PXE boot."
      fi
      # create initramfs
      echo "Creating initramfs $pxecfg_pd/$nbi_initrd, $msg_this_might_take_several_minutes"
      ( cd $wd/initrd.tmp
        find . | cpio --quiet -o -H newc | gzip -9 > $pxecfg_pd/$nbi_initrd
      )
      initramfs_size="$(stat -c "%s" $pxecfg_pd/$nbi_initrd)" # unit: bytes
      initramfs_size_in_KB=$(echo "scale=0; $initramfs_size / 1024.0" | bc -l)
      client_RAM_required="$(echo "scale=0; $initramfs_size_in_KB * $client_ram_to_initrd_ratio / 1024.0" | bc -l)"
      # initramfs, we do not have to assign ramdisk_size in bootparam.
      echo "The new initrd size is: $initramfs_size_in_KB KB."
      [ "$BOOTUP" = "color" ] && $SETCOLOR_WARNING
      echo "$msg_RAM_size_for_SL_drbl_client: $client_RAM_required MB."
      [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
      prepare_param_in_pxe_cfg
      cp -f $kernel $pxecfg_pd/$nbi_kernel
      chmod 644 $pxecfg_pd/$nbi_kernel $pxecfg_pd/$nbi_initrd
      ;;
  esac
} # end of create_casper_pxe_initrd_with_rootfs_inserted
#
put_kernel_initrd_root_fs_on_pxe_server() {
  # Copy the linux kernel
  echo "Copying kernel $kernel as $pxecfg_pd/$nbi_kernel..."
  cp -af $kernel $pxecfg_pd/$nbi_kernel
  echo "Copying initrd $oldinitrd as $pxecfg_pd/$nbi_initrd..."
  cp -af $oldinitrd $pxecfg_pd/$nbi_initrd
  get_SL_rootfile
  case "$rootfs_location" in
    "fetch") 
             echo "Copying root image $isomnt/$rootfile to $pxecfg_pd... $msg_this_might_take_several_minutes"
	     rsync -aP $isomnt/$rootfile $pxecfg_pd/$squashfs_file ;;
    "nfsroot")
             echo "Copying root image $isomnt/$rootfile to $drbl_common_root/clonezilla-live/... $msg_this_might_take_several_minutes"
	     mkdir -p $drbl_common_root/clonezilla-live/live/
             rsync -aP $isomnt/$rootfile $drbl_common_root/clonezilla-live/live/ ;;
  esac
  prepare_param_in_pxe_cfg
  chmod 644 $pxecfg_pd/$nbi_kernel $pxecfg_pd/$nbi_initrd
} # end of put_kernel_initrd_root_fs_on_pxe_server
#
umount_and_clean_tmp_working_dirs(){
  umount $isomnt
  [ -d "$isomnt" -a -n "$(echo $isomnt | grep "drblsl_tmp")" ] && rm -rf $isomnt
  [ -d "$wd" -a -n "$(echo $wd | grep "drbl_sl_wd")" ] && rm -rf $wd
} # end of umount_and_clean_tmp_working_dirs
#
get_SL_OS_NAME(){
if [ "$(echo $SL_ISO | grep -i "dsl")" ]; then
  [ "$BOOTUP" = "color" ] && $SETCOLOR_WARNING
  echo "This ISO file $SL_ISO is for Damn Small Linux (DSL)."
  [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
  SL_OS="DSL"
elif [ "$(echo $SL_ISO | grep -i "puppy")" ]; then
  [ "$BOOTUP" = "color" ] && $SETCOLOR_WARNING
  echo "This ISO file $SL_ISO is for Puppy Linux."
  [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
  SL_OS="Puppy"
elif [ "$(echo $SL_ISO | grep -i "clonezilla-live")" ]; then
  [ "$BOOTUP" = "color" ] && $SETCOLOR_WARNING
  echo "This ISO file $SL_ISO is for Clonezilla live."
  [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
  SL_OS="clonezilla-live"
elif [ "$(echo $SL_ISO | grep -i "gparted-live")" ]; then
  [ "$BOOTUP" = "color" ] && $SETCOLOR_WARNING
  echo "This ISO file $SL_ISO is for GParted live."
  [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
  SL_OS="gparted-live"
else
  [ "$BOOTUP" = "color" ] && $SETCOLOR_FAILURE
  echo "Unknown Small Linux distribution! This script only works with Damn Small Linux or Puppy Linux! Program terminated!!!"
  [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
  exit 1
fi
} # end of get_SL_OS_NAME

#
install_SL(){
  if [ -z "$SL_ISO" ]; then
    USAGE
    exit 1
  fi
  
  if [ ! -f "$SL_ISO" ]; then
    [ "$BOOTUP" = "color" ] && $SETCOLOR_FAILURE
    echo "$SL_ISO is NOT found!"
    echo "You have to prepare the iso file. For example, if you want to use Clonezilla live, you can get it via this command:"
    echo "wget $SL_ISO_URL_EXAMPLE"
    [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
    exit 1
  fi
  
  # Program file might give different results:
  # ISO 9660 CD-ROM filesystem data # file vesion 5.03
  # x86 boot sector # file version 4.10
  if [ -z "$(LC_ALL=C file -Ls $SL_ISO | grep -i "ISO 9660 CD-ROM filesystem data")" ] && \
     [ -z "$(LC_ALL=C file -Ls $SL_ISO | grep -i "x86 boot sector")" -a "$(echo $SL_ISO | grep -iE "\.iso")" ]; then
    [ "$BOOTUP" = "color" ] && $SETCOLOR_FAILURE
    echo "$SL_ISO is not an ISO 9660 CD-ROM filesystem data file!"
    [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
    echo "Program terminated!"
    exit 1
  fi
  
  # get SL_OS name from iso file name
  # Ugly, since it's not easy to know which one is which one, here we just judge them by file name.
  [ -z "$SL_OS" ] && get_SL_OS_NAME
  
  # Some settings for SL
  # insert_rootfs=yes => we have to put the root/main filesystem from SL in initrd
  # init_type: linuxrc or casper
  # use_modified_init: yes or no.
  # 2 types of init: linuxrc or casper. Some are not ready for PXE, we have to mofify, some are ready.
  # Basically there are 6 types of SL:
  # (1) linuxrc is ready for PXE, initrd is ready for PXE (insert_rootfs=no, use_modified_init=no). Actually if insert_rootfs=no, use_modified_init must be no. Ex: PLD
  # (2) linuxrc is ready for PXE, initrd is NOT ready for PXE (insert_rootfs=yes, use_modified_init=no). Ex: Insert 1.39a or later
  # (3) linuxrc is NOT ready for PXE, initrd is NOT ready for PXE (insert_rootfs=yesyes, use_modified_init=yes). Ex:DSL, PuppyLinux, GeeXbox
  # (4) casper is ready for PXE, initrd is ready for PXE (insert_rootfs=no, use_modified_init=yes). Actually no such SL now (2007/02/19), maybe in the future when they accept our patch.
  # (5) casper is NOT ready for PXE, initrd is NOT ready for PXE (insert_rootfs=yes, use_modified_init=yes). Ex: Debian Live, PUD.
  # (6) casper is ready for PXE, initrd is NOT ready for PXE (insert_rootfs=yes, use_modified_init=yes). Actually no such SL now (2007/02/19), maybe in the future when they accept our patch.
  
  case "$(echo $SL_OS | tr "[A-Z]" "[a-z]")" in
    dsl|DamnSmallLinux)
       # SL_NAME: in one word
       SL_NAME="DSL"
       SL_FULL_NAME="Damn Small Linux"
       # e.g. dsl-4.4.10.iso -> 4.4.10
       SL_VER="$(basename $SL_ISO | sed -e "s/^dsl-//g" -e "s/.iso$//g")"
       # In DSL, boot kernel files are linux24 and minirt24.gz in /boot/isolinux/
       bootfiles_path="/boot/isolinux"
       # in DSL, it's cloop file /cdrom/KNOPPIX/KNOPPIX
       rootfile_path="/KNOPPIX"
       rootfile_path_in_initrd="/cdrom/KNOPPIX"
       insert_rootfs="yes"
       init_type="linuxrc"
       use_modified_init="yes"
       initrd_type="ext2"
       squashfs="no"
       ;;
    puppy|PuppyLinux)
       # SL_NAME: in one word
       SL_NAME="PuppyLinux"
       SL_FULL_NAME="Puppy Linux"
       # In PuppyLinux, boot kernel files are vmlinuz and initrd.gz in /
       bootfiles_path="/"
       # in PuppyLinux, it's squashfs, name is like pup_211.sfs in /
       rootfile_path="/"
       rootfile_path_in_initrd="/"
       insert_rootfs="yes"
       init_type="linuxrc"
       use_modified_init="yes"
       initrd_type="cpio"
       squashfs="no"
       ;;
    clonezilla-live|gparted-live)
       # SL_NAME: in one word
       case "$(echo $SL_OS | tr "[A-Z]" "[a-z]")" in
       clonezilla-live)
         SL_NAME="Clonezilla-live"
         SL_FULL_NAME="Clonezilla Live"
         # e.g. clonezilla-live-1.2.2-14.iso -> 1.2.2-14
         SL_VER="$(basename $SL_ISO | sed -e "s/^clonezilla-live-//g" -e "s/.iso$//g")"
	 ;;
       gparted-live)
         SL_NAME="GParted-live"
         SL_FULL_NAME="GParted Live"
         # e.g. gparted-live-0.4.5-2.iso -> 0.4.5-2
         SL_VER="$(basename $SL_ISO | sed -e "s/^gparted-live-//g" -e "s/.iso$//g")"
	 ;;
       esac
       # In Clonezilla/GParted live, boot kernel file is vmlinuz1 in /isolinux/
       bootfiles_path="/live"
       # in Clonezilla/GParted live, name is like /live/filesystem.squashfs
       rootfile_path="/live"
       rootfile_path_in_initrd=""  # useless
       insert_rootfs="no"
       init_type="live"
       use_modified_init="no"
       initrd_type=""  # useless
       squashfs="yes"
       ;;
  esac
  
  #
  if [ "$batch_mode" != "on" ]; then
    echo "$msg_delimiter_star_line"
    echo "$msg_this_script_will_create_SL_diskless: $SL_FULL_NAME"
    echo -n "$msg_are_u_sure_u_want_to_continue [Y/n] "
    read confirm_ans
    case "$confirm_ans" in
      n|N|[nN][oO])
         echo "$msg_program_stop"
         exit 1
         ;;
      *)
         echo "$msg_ok_let_do_it"
         ;;
    esac
  fi
  
  #
  isomnt="$(mktemp -d /tmp/drblsl_tmp.XXXXXX)"
  wd="$(mktemp -d drbl_sl_wd.XXXXXX)"
  echo "Mounting the iso file $SL_ISO at mounting point $isomnt"
  mount -o loop $SL_ISO $isomnt
  
  # Find kernel
  echo "Finding the kernel and initrd from iso..."
  for i in $isomnt/$bootfiles_path/*; do
    # sometimes it's "Linux kernel x86", sometimes it's "Linux x86 kernel"
    # In Ubuntu Sarge (file 4.17-2ubuntu1):
    # For DSL: linux24: Linux x86 kernel root=0x301-ro vga=normal, bzImage, version 2.4.26 (root@Knoppix) #1 SMP Sa
    # For Puppy: vmlinuz: Linux kernel x86 boot executable RO-rootFS, root_dev 0x341, swap_dev 0x1, Normal VGA
    # For INSERT: vmlinuz: Linux kernel x86 boot executable RO-rootFS, root_dev 0x806, swap_dev 0x1, Normal VGA
    # The problem is that, for some distribution, like INSERT, there is another file "memtest86": memtest86: Linux x86 kernel
    # For Clonezilla live iso, there is another one: eb.zli (etherboot)
    # For old file, like Debian Sarge (file 4.12-1) or RH9 (file-3.39-9):
    # In Debian Sarge: vmlinuz-2.6.8-2-686: x86 boot sector
    # In RH9: vmlinuz-2.4.20-28.9smp: x86 boot sector
    # In OpenSuSE 11.3: "file -Ls vmlinuz" gives:
    # vmlinuz: Linux/x86 Kernel, Setup Version 0x20a, bzImage, Version 3.2.0, Version 3.2.0-24, RO-rootFS, swap_dev 0x4, Normal VGA
    if [ -n "$(LC_ALL=C file -Ls $i | grep -iE "(Linux x86 kernel|Linux kernel x86 boot executable|Linux\/x86 Kernel|x86 boot sector)")" ]; then
      # Ugly
      # we skip memtest, etherboot, freedos...
      if [ -z "$(LC_ALL=C echo $i | grep -iE "(memtest|eb.zli|memdisk|gpxe.lkn|ipxe.lkn|freedos|fdos)")" ]; then
        kernel="$i"
        break
      fi
    fi
  done
  if [ -n "$kernel" ]; then
    echo "Found the kernel: $kernel"
  else
    [ "$BOOTUP" = "color" ] && $SETCOLOR_FAILURE
    echo "The kernel does NOT exist! Program terminated!"
    [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
    umount_and_clean_tmp_working_dirs
    exit 1
  fi
  
  # Find initrd
  # UGLY! Here we assume only one gzip/cpio file exists, and it's initrd.
  for i in $isomnt/$bootfiles_path/* $isomnt/$rootfile_path/*; do
    if [ -n "$(LC_ALL=C file -Ls $i | grep -iE "(gzip compressed data|XZ compressed data)")" ]; then
      oldinitrd="$i"
      uncompress_to_stdout="gunzip -c"
      compress_to_stdout="gzip -c"
      break
    elif [ -n "$(LC_ALL=C echo $i | grep -iE "\/miniroot.lz$")" ]; then
    # For INSERT, the initrd is miniroot.lz, which is lzma format. Most of the program file does not have the magic for that.
      oldinitrd="$i"
  
      # There are two types of lzma, although they all said they are 4.32/4.33
      # (1) MDV2007, Ubuntu Etch
      #   LZMA 4.32 Copyright (c) 1999-2005 Igor Pavlov  2005-12-09
      #   Usage:  LZMA <e|d> inputFile outputFile [<switches>...]
      #   e: encode file
      #	  d: decode file
      #   -si:    read data from stdin
      #   -so:    write data to stdout
      # (2) Debian Etch
      #   lzma 4.32.0beta3 Copyright (C) 2006 Ville Koskinen
      #   Based on LZMA SDK 4.43 Copyright (C) 1999-2006 Igor Pavlov
      #   -c --stdout       output to standard output
      #   -d --decompress   force decompression
      #   -z --compress     force compression
      if [ -n "$(LC_ALL=C lzma --h 2>&1 | grep -iEw "\-so:")" ]; then
        uncompress_to_stdout="lzma d -so"
        compress_to_stdout="lzma e -so"
      else
        uncompress_to_stdout="lzma -d -c -S .lz"
        compress_to_stdout="lzma -z -c"
      fi
      break
    elif [ -n "$(LC_ALL=C file -Ls $i | grep -i "ASCII cpio archive")" ]; then
      oldinitrd="$i"
      break
    fi
  done
  if [ -n "$oldinitrd" ]; then
    echo "Found the initrd: $oldinitrd"
  else
    [ "$BOOTUP" = "color" ] && $SETCOLOR_FAILURE
    echo "The initrd does NOT exist! Program terminated!"
    [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
    umount_and_clean_tmp_working_dirs
    exit 1
  fi
  # we rename the NBI kernel and img, like dsl-linux24 and dsl-minirt24.gz
  nbi_kernel="${SL_NAME}-${kernel##*/}"
  nbi_initrd="${SL_NAME}-${oldinitrd##*/}"
  if [ "$squashfs" = "yes" ]; then
    get_SL_rootfile
    squashfs_file="${SL_NAME}-${rootfile##*/}"
  fi
  # For Clonezilla/GParted live, we should try to find the boot parameters now
  case "$(echo $SL_OS | tr "[A-Z]" "[a-z]")" in
    clonezilla-live|gparted-live)
      initrd_filename="$(basename $oldinitrd)"
      # The append line e.g.:
      # append initrd=/live/initrd1.img boot=live union=aufs    ocs_live_run="ocs-live-general" ocs_live_extra_param="" ocs_live_keymap="" ocs_live_batch="no" ocs_lang="" vga=791 nolocales
      # We have to remove ip=frommedia because the /etc/resolv.conf got in live-boot (actually this program scripts/live-bottom/23networking) won't be copied to /etc/resolv.conf if ip=frommedia exists in boot parameters.
      cl_gp_boot_param="$(LC_ALL=C grep -Eiw "append" $isomnt/isolinux/isolinux.cfg  | grep -Eiw $initrd_filename | head -n 1 | sed -r -e "s/append//g" -e "s/initrd=.*$initrd_filename[[:space:]]+//g" | sed -e "s/^[[:space:]]*//g" | sed -e "s/ip=frommedia//g")"
      ;;
  esac
  
  #
  case "$insert_rootfs" in
    yes)
        case "$init_type" in
          "linuxrc") create_linuxrc_pxe_initrd_with_rootfs_inserted ;;
          "casper") create_casper_pxe_initrd_with_rootfs_inserted ;;
        esac
        ;;
    no)
        case "$squashfs" in
          "yes") put_kernel_initrd_root_fs_on_pxe_server ;;
              *) put_pxe_initrd_without_rootfs_inserted ;;
        esac
        ;;
  esac
  #
  umount_and_clean_tmp_working_dirs
  
  # append the config file in pxelinux dir.
  if [ -z "$(grep -E "^[[:space:]]*label[[:space:]]+$SL_NAME[[:space:]]*$" $PXELINUX_DIR/default)" ] || [ "$force_to_update_pxecfg" = "yes" ]; then
    if [ -n "$(grep -E "^[[:space:]]*label[[:space:]]+$SL_NAME[[:space:]]*$" $PXELINUX_DIR/default)" ]; then
      echo "First removing $SL_NAME setting in $PXELINUX_DIR/default..."
      delete_label_block_pxe_img $SL_NAME $PXELINUX_DIR/default
    fi
    echo "Append the $SL_FULL_NAME config in $PXELINUX_DIR/default..."
    cat <<-SL_PXE >> $PXELINUX_DIR/default 
label $SL_NAME
  # MENU DEFAULT
  # MENU HIDE
  MENU LABEL $SL_FULL_NAME $SL_VER (Ramdisk)
  # MENU PASSWD
  KERNEL $nbi_kernel
  APPEND $append_param_in_pxe_cfg

  TEXT HELP
  $SL_FULL_NAME $SL_VER runs on RAM
  ENDTEXT

SL_PXE
  fi
  # Put the version number
cat <<-SL_INFO_PXE > $pxecfg_pd/${SL_NAME}-info.txt
$SL_FULL_NAME version: $SL_VER
Files were extracted from "$(basename $SL_ISO)"
SL_INFO_PXE
  # Put the prompt messages
  echo "$msg_delimiter_star_line"
  if [ "$booting_messages" = "on" ]; then
    [ "$BOOTUP" = "color" ] && $SETCOLOR_WARNING
    echo "$msg_all_set_you_can_turn_on_clients"
    echo "$msg_note! $msg_etherboot_5_4_is_required"
    [ "$BOOTUP" = "color" ] && $SETCOLOR_NORMAL
  fi
} # end of install_SL

# 
uninstall_SL(){
  # convert
  case "$SL_TO_BE_REMOVED" in
    [aA][lL][lL])
      SL_TO_BE_REMOVED="$supported_SL_dists"
      ;;
  esac
  echo "Uninstalling installed Small Linux..."
  for id in $SL_TO_BE_REMOVED; do
    if [ -z "$(echo "$supported_SL_dists" | grep -Ew "$id")" ]; then
      echo "$SL_TO_BE_REMOVED is an unknown Small Linux! Program terminated!"
      exit 1
    fi
    # remove the block in pxelinux
    if [ -n "$(grep -E "^[[:space:]]*label[[:space:]]+$id[[:space:]]*$" $PXELINUX_DIR/default)" ]; then
      echo "Removing $id setting in $PXELINUX_DIR/default..."
      delete_label_block_pxe_img $id $PXELINUX_DIR/default
    fi
    # remove vmlinuz and initrd
    if [ -n "$(ls $pxecfg_pd/${id}-* 2>/dev/null)" ]; then
      echo "Removing installed $id if it exists..."
      rm -fv $pxecfg_pd/${id}-*
    fi
    if [ -d "$drbl_common_root/clonezilla-live/" ]; then
      rm -rfv $drbl_common_root/clonezilla-live/*
    fi
  done
} # end of uninstall_SL

#############
###  MAIN ###
#############
#
check_if_root

# Parse command-line options
while [ $# -gt 0 ]; do
  case "$1" in
    -b|--batch-mode) shift; batch_mode="on" ;;
    -l|--language)
            shift
            if [ -z "$(echo $1 |grep ^-.)" ]; then
              # skip the -xx option, in case 
              specified_lang="$1"
	      [ -z "$specified_lang" ] && USAGE && exit 1
              shift
            fi
            ;;
    -i|--install)
        shift; mode="install"
        if [ -z "$(echo $1 |grep ^-.)" ]; then
          # skip the -xx option, in case 
          SL_ISO="$1"
          [ -z "$SL_ISO" ] && USAGE && exit 1
	  shift
        fi
	;;
    -d|--distribution)
        shift;
        if [ -z "$(echo $1 |grep ^-.)" ]; then
          # skip the -xx option, in case 
          SL_OS="$1"
          [ -z "$SL_OS" ] && USAGE && exit 1
	  shift
        fi
	;;
    -f|--use-nfsroot) shift; rootfs_location="nfsroot" ;;
    -k|--keep-pxecfg) shift; force_to_update_pxecfg="no" ;;
    -n|--no-prompt-boot-message) shift; booting_messages="off";;
    -s|--server-ip)
        shift;
        if [ -z "$(echo $1 |grep ^-.)" ]; then
          # skip the -xx option, in case 
          server_IP="$1"
          [ -z "$server_IP" ] && USAGE && exit 1
	  shift
        fi
	;;
    -u|--uninstall)
        shift; mode="uninstall"
        if [ -z "$(echo $1 |grep ^-.)" ]; then
          # skip the -xx option, in case 
          SL_TO_BE_REMOVED="$1"
          [ -z "$SL_TO_BE_REMOVED" ] && USAGE && exit 1
	  shift
        fi
        ;;
    -V|--dist-version)
        shift;
        if [ -z "$(echo $1 |grep ^-.)" ]; then
          # skip the -xx option, in case 
          SL_VER="$1"
          [ -z "$SL_VER" ] && USAGE && exit 1
	  shift
        fi
	;;
    -v|--verbose)
	verbose="on"
	verbose_opt="-v"
        shift ;;
    *)  USAGE && exit 1 ;;
  esac
done
# mode is essential
[ -z "$mode" ] && USAGE && exit 1

# Load the language file
ask_and_load_lang_set $specified_lang

# run it
case "$mode" in
   install) install_SL;;
   uninstall) uninstall_SL;;
esac
