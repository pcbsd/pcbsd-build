#!/bin/sh

# Most of these dont need to be modified
#########################################################

# Where is the pcbsd-build program installed
PROGDIR="`realpath | sed 's|/scripts||g'`" ; export PROGDIR

# Source vars
. ${PROGDIR}/pcbsd.cfg

# Where on disk is the PCBSD GIT branch
if [ -n "$PCBSDGITDIR" ] ; then
  GITBRANCH="${PCBSDGITDIR}"
  export GITBRANCH
else
  GITBRANCH="${PROGDIR}/git/pcbsd"
  export GITBRANCH
fi

# Where are the dist files
DISTDIR="${PROGDIR}/fbsd-dist" ; export DISTDIR

# Set the dist files
BASEDIST="$DISTDIR/base.txz"
KERNDIST="$DISTDIR/kernel.txz"
L32DIST="$DISTDIR/lib32.txz"
export BASEDIST KERNDIST L32DIST


# Kernel Config
PCBSDKERN="GENERIC" ; export PCBSDKERN

# Set where we wish to copy our checked out FreeBSD source
if [ -n "$FREEBSDGITDIR" ] ; then
  WORLDSRC="${FREEBSDGITDIR}"
  export WORLDSRC
else
  WORLDSRC="${PROGDIR}/git/freebsd"
  export WORLDSRC
fi

# Where to build the world directory
PDESTDIR="${PROGDIR}/buildworld" ; export PDESTDIR
PDESTDIR9="${PROGDIR}/buildworld9" ; export PDESTDIR9
PDESTDIRFBSD="${PROGDIR}/buildworld-fbsd" ; export PDESTDIRFBSD
PDESTDIRSERVER="${PROGDIR}/buildworld-server" ; export PDESTDIRSERVER

# Set the PC-BSD Version
export PCBSDVER="${TARGETREL}"

# Set the ISO Version
REVISION="`cat ${WORLDSRC}/sys/conf/newvers.sh 2>/dev/null | grep '^REVISION=' | cut -d '"' -f 2`"
if [ -z "$REVISION" ] ; then
   REVISION="UNKNOWN"
fi
BRANCH="`cat ${WORLDSRC}/sys/conf/newvers.sh 2>/dev/null | grep '^BRANCH=' | cut -d '"' -f 2`"
if [ -z "$BRANCH" ] ; then
   BRANCH="UNKNOWN"
fi
if [ -z "$ISOVER" ] ; then
  # This can be overridden via pcbsd.cfg
  export ISOVER="${REVISION}-${BRANCH}"
fi

# Where are the config files
PCONFDIR="${GITBRANCH}/build-files/conf" ; export PCONFDIR
if [ "$SYSBUILD" = "trueos" ] ; then
  PCONFDIR="${GITBRANCH}/build-files/conf/trueos" ; export PCONFDIR
fi

# Where do we place the log files
PLOGFILES="${PROGDIR}/log" ; export PLOGFILES

REALARCH="`uname -m`"
export REALARCH
case $ARCH in
   i386) FARCH="x86" ; export FARCH ;;
  amd64) FARCH="x64" ; export FARCH ;;
      *) FARCH="x86" ; export FARCH ;;
esac

# Set the location of packages needed for our Meta-Packages
export METAPKGDIR="${PROGDIR}/tmp"

if [ -z "$POUDRIEREJAILVER" ] ; then
  POUDRIEREJAILVER="$TARGETREL"
fi

# Poudriere variables
if [ "$SYSBUILD" = "trueos" -a -z "$DOINGSYSBOTH" ] ; then
  PBUILD="trueos-`echo $POUDRIEREJAILVER | sed 's|\.||g'`"
  if [ "$ARCH" = "i386" ] ; then PBUILD="${PBUILD}-i386"; fi
  if [ -z "$POUDPORTS" ] ; then
    POUDPORTS="trueosports" ; export POUDPORTS
  fi
else
  PBUILD="pcbsd-`echo $POUDRIEREJAILVER | sed 's|\.||g'`"
  if [ "$ARCH" = "i386" ] ; then PBUILD="${PBUILD}-i386"; fi
  if [ -z "$POUDPORTS" ] ; then
    POUDPORTS="pcbsdports" ; export POUDPORTS
  fi
fi
PJDIR="$POUD/jails/$PBUILD"
PPKGDIR="$POUD/data/packages/$PBUILD-$POUDPORTS"
PJPORTSDIR="$POUD/ports/$POUDPORTS"
export PBUILD PJDIR PJPORTSDIR PPKGDIR

# Check for required dirs
rDirs="/log /git /iso /fbsd-dist /tmp"
for i in $rDirs
do
  if [ ! -d "${PROGDIR}/${i}" ] ; then
     mkdir -p ${PROGDIR}/${i}
  fi
done

################
# Functions
################

exit_err() {
   echo "ERROR: $@"
   exit 1
}

clean_wrkdir()
{
  if [ -z "$1" ] ; then exit_err "Missing wrkdir..."; fi
  if [ -e "${1}" ]; then
    echo "Cleaning up ${1}"
    umount -f ${1}/dev >/dev/null 2>/dev/null
    umount -f ${1}/mnt >/dev/null 2>/dev/null
    umount -f ${1}/usr/src >/dev/null 2>/dev/null
    umount -f ${1} >/dev/null 2>/dev/null
    rmdir ${1}
  fi
}

mk_tmpfs_wrkdir()
{
  if [ -z "$1" ] ; then exit_err "Missing wrkdir..."; fi

  clean_wrkdir "$1"

  mkdir -p "${1}"
  mount -t tmpfs tmpfs "${1}"
}

extract_dist()
{
  if [ -z "$1" -o -z "$2" ] ; then exit_err "Missing variables..." ; fi
  if [ ! -e "$1" ] ; then exit_err "Invalid DISTFILE $1" ; fi
  if [ ! -d "$2" ] ; then exit_err "Invalid DESTDIR $2" ; fi

  echo "Extracting $1 to $2"
  tar xvf $1 -C $2 2>/dev/null
}

cp_overlay()
{
  echo "Copying overlay $1 -> $2"
  tar cvf - --exclude .svn -C ${1} .  2>/dev/null | tar xvmf - -C ${2} 2>/dev/null
}

git_fbsd_up()
{
  local lDir=${1}
  local rDir=${2}
  local oDir=`pwd`
  cd "${lDir}"

  echo "GIT checkout $GITFBSDBRANCH"
  git checkout ${GITFBSDBRANCH}

  echo "GIT pull: ${GITFBSDBRANCH}"
  git pull origin ${GITFBSDBRANCH}
  if [ $? -ne 0 ] ; then
     exit_err "Failed doing a git pull"
  fi

  cd "${oDir}"
  return 0
}

git_up()
{
  local lDir=${1}
  local oDir=`pwd`

  if [ -d "${lDir}/src-sh/pcbsd-utils/pc-extractoverlay/ports-overlay/usr/local/etc/pkg" ] ; then
    rm -rf ${lDir}/src-sh/pcbsd-utils/pc-extractoverlay/ports-overlay/usr/local/etc/pkg >/dev/null 2>/dev/null
  fi
  cd "${lDir}"

  git reset --hard >/dev/null 2>/dev/null

  local gbranch="$GITPCBSDBRANCH"
  if [ -z "$gbranch" ] ; then
     gbranch="master"
  fi

  echo "GIT checkout: ${gbranch}"
  git checkout ${gbranch}
  if [ $? -ne 0 ] ; then
     exit_err "Failed doing a git checkout"
  fi

  echo "GIT pull: ${1}"
  git pull 
  if [ $? -ne 0 ] ; then
     exit_err "Failed doing a git pull"
  fi

  # Copy the pkgng config into source tree
  cp -r ${PROGDIR}/pkg ${lDir}/src-sh/pcbsd-utils/pc-extractoverlay/ports-overlay/usr/local/etc/
  if [ $? -ne 0 ] ; then
     exit_err "Failed copying pkgng config"
  fi

  # Copy the PBI keys / paths
  cp ${PROGDIR}/pbi/* ${lDir}/src-sh/pbi-manager/repo/
  if [ $? -ne 0 ] ; then
     exit_err "Failed copying pbi config"
  fi

  cd "${oDir}"
  return 0
}

# Run-command, don't halt if command exits with non-0
rc_nohalt()
{
  local CMD="$1"

  if [ -z "${CMD}" ]
  then
    exit_err "Error: missing argument in rc_nohalt()"
  fi

  ${CMD} 2>/dev/null >/dev/null

};

# Run-command, halt if command exits with non-0
rc_halt()
{
  local CMD="$1"
  if [ -z "${CMD}" ]; then
    exit_err "Error: missing argument in rc_halt()"
  fi

  echo "Running command: $CMD"
  ${CMD}
  if [ $? -ne 0 ]; then
    exit_err "Error ${STATUS}: ${CMD}"
  fi
};

rtn()
{
  echo "Press ENTER to continue"
  read tmp
};

create_pkg_conf()
{

   if [ -d "${PROGDIR}/tmp/repo" ] ; then
      rm -rf ${PROGDIR}/tmp/repo
   fi
   mkdir ${PROGDIR}/tmp/repo
   if [ -d "${PROGDIR}/tmp/sysrel" ] ; then
     rm -rf ${PROGDIR}/tmp/sysrel
   fi
   mkdir ${PROGDIR}/tmp/sysrel

   ABIVER=`echo $POUDRIEREJAILVER | cut -d '-' -f 1 | cut -d '.' -f 1`
   echo "PKG_CACHEDIR: ${PROGDIR}/tmp" > ${PROGDIR}/tmp/pkg.conf
   echo "ALTABI: freebsd:${ABIVER}:x86:64" >> ${PROGDIR}/tmp/pkg.conf
   echo "ABI: FreeBSD:${ABIVER}:amd64" >> ${PROGDIR}/tmp/pkg.conf


   # Doing a local package build
   if [ "$PKGREPO" = "local" ]; then
      echo "localrepo: {
               url: \"file://${PPKGDIR}\",
               enabled: true
              }" >  ${PROGDIR}/tmp/repo/local.conf
	return
   fi

   # Doing a remote pull from a repo
   cp ${PROGDIR}/repo.conf ${PROGDIR}/tmp/repo/local.conf
   sed -i '' "s|%RELVERSION%|$POUDRIEREJAILVER|g" ${PROGDIR}/tmp/repo/local.conf
   sed -i '' "s|%ARCH%|$ARCH|g" ${PROGDIR}/tmp/repo/local.conf
   sed -i '' "s|%PROGDIR%|$PROGDIR|g" ${PROGDIR}/tmp/repo/local.conf

}

create_installer_pkg_conf()
{
   if [ -d "${PROGDIR}/tmp/repo-installer" ] ; then
      rm -rf ${PROGDIR}/tmp/repo-installer
   fi
   mkdir ${PROGDIR}/tmp/repo-installer

   echo "pcbsd-build: {
               url: \"file:///mnt\",
               enabled: true
              }" >  ${PROGDIR}/tmp/repo-installer/repo.conf
}

# Copy the ISO package files to a new location
cp_iso_pkg_files()
{
   if [ -d "$METAPKGDIR" ] ; then
     rm -rf ${METAPKGDIR}
   fi
   mkdir ${METAPKGDIR}

   create_pkg_conf

   echo "Fetching PC-BSD ISO packages... Please wait, this may take several minutes..."

   haveWarn=0

   # Packages to fetch / include on install media
   local eP="${PCONFDIR}/iso-packages"

   # Use the version of pkgng for the target
   get_pkgstatic

   # Now fetch these packages
   while read pkgLine
   do
      pkgName=`echo $pkgLine | cut -d ' ' -f 1`
      pkgLocal=`echo $pkgLine | cut -d ' ' -f 2`
      localFlg=""
      pConf="-C ${PROGDIR}/tmp/pkg.conf"

      # See if this is something we can skip for now
      skip=0
      for j in $skipPkgs
      do
        if [ "$pkgName" = "${j}" ] ; then skip=1; break; fi
      done
      if [ $skip -eq 1 ] ; then echo "Skipping $pkgBase.."; continue ; fi

      # Fetch the packages
      rc_halt "${PKGSTATIC} ${pConf} -R ${PROGDIR}/tmp/repo/ fetch -y -o ${PROGDIR}/tmp $localFlg -d ${pkgName}"
      sync
      sleep 0.5
    done < $eP

    # Create a list of deps for the meta-pkgs
    mkdir ${PROGDIR}/tmp/dep-list
    for plist in `find ${GITBRANCH}/overlays/install-overlay/root/pkgset | grep pkg-list`
    do
       targets=""
       while read line
       do
	 targets="$targets $line"
       done < $plist
       tfile=`echo $plist | sed "s|${GITBRANCH}/overlays/install-overlay/root/pkgset/||g" | sed "s|/pkg-list||g"`
       tfile=`basename $tfile`
       echo "Saving deps for $tfile"
       ${PKGSTATIC} ${pConf} -R ${PROGDIR}/tmp/repo/ rquery '%dn-%dv' $targets | sort | uniq > ${PROGDIR}/tmp/dep-list/${tfile}.deps
    done

    # Copy pkgng
    rc_halt "cp ${PROGDIR}/tmp/All/pkg-*.txz ${PROGDIR}/tmp/All/pkg.txz"

    # Now we need to create the new repo files for DVD / USB
    rc_halt "cd ${PROGDIR}/tmp"
    rc_halt "${PKGSTATIC} repo ."
    rc_halt "cd ${PROGDIR}"

    # Cleanup PKGSTATIC
    rc_halt "rm ${PKGSTATIC}"

    create_installer_pkg_conf
}

update_poudriere_jail()
{
  if [ -z "$POUDRIEREJAILVER" ] ; then
    POUDRIEREJAILVER="$PCBSDVER"
  fi

  # Setup fake poudriere file URL
  mkdir -p /fakeftp/pub/FreeBSD/releases/${ARCH}/${ARCH}/$POUDRIEREJAILVER >/dev/null 2>/dev/null
  dfiles="MANIFEST src.txz base.txz doc.xz kernel.txz"
  if [ "$ARCH" = "amd64" ] ; then dfiles="$dfiles lib32.txz" ; fi
  if [ -e "${DISTDIR}/games.txz" ] ; then dfiles="$dfiles games.txz" ; fi

  for i in $dfiles
  do
    ln -sf "${DISTDIR}/$i" /fakeftp/pub/FreeBSD/releases/${ARCH}/${ARCH}/${POUDRIEREJAILVER}/$i
  done

  echo "FREEBSD_HOST=file:///fakeftp/" >> /usr/local/etc/poudriere.conf

  # Clean old poudriere dir
  poudriere jail -d -j $PBUILD >/dev/null 2>/dev/null


  poudriere jail -c -j $PBUILD -v ${POUDRIEREJAILVER} -a $ARCH
  if [ $? -ne 0 ] ; then
    cat /usr/local/etc/poudriere.conf | grep -v "^FREEBSD_HOST=file:///fakeftp/" >/tmp/.pconf.$$
    mv /tmp/.pconf.$$ /usr/local/etc/poudriere.conf
    echo "Failed to create poudriere jail"
    exit 1
  fi

  # Cleanup the hostname
  cat /usr/local/etc/poudriere.conf | grep -v "^FREEBSD_HOST=file:///fakeftp/" >/tmp/.pconf.$$
  mv /tmp/.pconf.$$ /usr/local/etc/poudriere.conf

  rm -rf /fakeftp
}

get_last_rev()
{
   oPWD=`pwd`
   rev=0
   cd "$1"
   rev=`git log -n 1 --date=raw ${1} | grep 'Date:' | awk '{print $2}'`
   cd $oPWD
   if [ $rev -ne 0 ] ; then
     echo "$rev"
     return 0
   fi
   return 1
}

check_essential_pkgs()
{
   echo "Checking essential pkgs..."
   haveWarn=0

   local eP="${PCONFDIR}/essential-packages"

   # Make sure we have the file we need
   if [ ! -e "${eP}" ] ; then
      echo "WARNING: Missing ${eP}"
      if [ "$1" != "NO" ] ; then
        echo "Warning: Packages are missing! Continue?"
        echo -e "(Y/N)\c"
        read tmp
        if [ "$tmp" != "y" -a "$tmp" != "Y" ] ; then
           rtn
           exit 1
        fi
        return 1
      fi
   fi

   chkList=""
   # Build the list of packages to check
   while read line
   do
       # See if these dirs exist
       ls -d ${PJPORTSDIR}/${line} >/dev/null 2>/dev/null
       if [ $? -ne 0 ] ; then
          echo "Warning: No such port ($line) to check..."
          continue
       fi
       for i in `ls -d ${PJPORTSDIR}/${line}`
       do
          chkList="$chkList $i"
       done
   done < ${eP}

   # Check all our PC-BSD meta-pkgs, warn if some of them don't exist
   # or cannot be determined
   for i in $chkList
   do

     # Get the pkgname
     pkgName=""
     pkgName=`make -C ${i} -V PKGNAME PORTSDIR=${PJPORTSDIR} __MAKE_CONF=/usr/local/etc/poudriere.d/$PBUILD-make.conf`
     if [ -z "${pkgName}" ] ; then
        echo "Could not get PKGNAME for ${i}"
        haveWarn=1
     fi

     # Check the arch type
     pArch=`make -C ${i} -V ONLY_FOR_ARCHS PORTSDIR=${PJPORTSDIR}`
     if [ -n "$pArch" -a "$pArch" != "$ARCH" ] ; then continue; fi

     if [ ! -e "${PPKGDIR}/All/${pkgName}.txz" ] ; then
        echo "WARNING: Missing package ${pkgName} for port ${i}"
        haveWarn=1
     else
     fi
   done
   if [ $haveWarn -ne 0 -a "$1" != "NO" ] ; then
      echo "Warning: Packages are missing! Continue?"
      echo -e "(Y/N)\c"
      read tmp
      if [ "$tmp" != "y" -a "$tmp" != "Y" ] ; then
         rtn
         exit 1
      fi
   fi

   return $haveWarn
}

get_pkgstatic()
{
  create_pkg_conf

  echo "Setting up pkg-static"
  if [ -e "/tmp/pkg-static" ] ; then rm /tmp/pkg-static; fi

  if [ "$PKGREPO" = "local" ]; then
    rc_halt "tar xv --strip-components 4 -f ${PPKGDIR}/Latest/pkg.txz -C /tmp /usr/local/sbin/pkg-static" >/dev/null 2>/dev/null
  else
    PSITE=`grep 'url' ${PROGDIR}/tmp/repo/local.conf | awk '{print $2}' | sed 's|"||g' | sed 's|,||g'`
    rc_halt "fetch -o /tmp/.pkg.txz.$$ ${PSITE}/Latest/pkg.txz" 
    rc_halt "tar xv --strip-components 4 -f /tmp/.pkg.txz.$$ -C /tmp /usr/local/sbin/pkg-static" >/dev/null 2>/dev/null
    rc_halt "rm /tmp/.pkg.txz.$$" >/dev/null 2>/dev/null
  fi

  rc_halt "mv /tmp/pkg-static /tmp/pkg-static.$$" >/dev/null 2>/dev/null

  PKGSTATIC="/tmp/pkg-static.$$" ; export PKGSTATIC

  # Update the repo schema files before using
  rc_halt "${PKGSTATIC} -C ${PROGDIR}/tmp/pkg.conf -R ${PROGDIR}/tmp/repo/ update -f"
}
