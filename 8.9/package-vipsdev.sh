#!/usr/bin/env bash

if [ $# -lt 1 ]; then
  echo "Usage: $0 [DEPS] [TARGET]"
  echo "Package libvips in mxe/usr/TARGET/"
  echo "DEPS is the group of dependencies to build libvips with,"
  echo "    defaults to 'web'"
  echo "TARGET is the binary target, defaults to x86_64-w64-mingw32.shared.win32"

  exit 1
fi

. variables.sh

deps="${1:-web}"
target="${2:-x86_64-w64-mingw32.shared.win32}"
arch=${target%%-*}
type="${target#*.}"
type="${type%%.*}"
build_os=`$mxe_dir/ext/config.guess`

if [ "$arch" = "i686" ]; then
  arch="w32"
else
  arch="w64"
fi

# Make sure that the repackaging dir is empty
rm -rf $repackage_dir
mkdir -p $repackage_dir/bin

# Copy libvips-cpp-42.dll by default
target_dll="libvips-cpp-42.dll"

zip_suffix="-threadpool-reuse"

if [ "$type" = "static" ]; then
  # Static build? Copy libvips-42.dll
  # TODO(kleisauke): sharp needs libvips-cpp-42.dll
  target_dll="libvips-42.dll"

  zip_suffix="-static"
fi

if [ "$MOZJPEG" = "true" ]; then
  zip_suffix+="-mozjpeg"
fi

if [ "$LLVM" = "true" ]; then
  zip_suffix+="-llvm"
fi

echo "Copying libvips and dependencies"

# Need to whitelist the Universal C Runtime (CRT) DLLs
# Can't do api-ms-win-crt-*-l1-1-0.dll, unfortunately
whitelist=(api-ms-win-crt-{conio,convert,environment,filesystem,heap,locale,math,multibyte,private,process,runtime,stdio,string,time,utility}-l1-1-0.dll)

# CreateEnvironmentBlock, GetUserProfileDirectoryA, etc.
whitelist+=(userenv.dll)

# Copy libvips and dependencies with pe-util
$mxe_prefix/$build_os/bin/peldd \
  $mxe_prefix/$target.$deps/bin/$target_dll \
  --clear-path \
  --path $mxe_prefix/$target.$deps/bin \
  ${whitelist[@]/#/--wlist } \
  -a | xargs cp -t $repackage_dir/bin

echo "Copying install area $mxe_prefix/$target.$deps/"

# Follow symlinks when copying /share and /etc
cp -Lr $mxe_prefix/$target.$deps/{share,etc} $repackage_dir

# Copy everything from /lib and /include, then delete the symlinks
cp -r $mxe_prefix/$target.$deps/{lib,include} $repackage_dir
find $repackage_dir/{lib,include} -type l -exec rm -f {} \;

echo "Generating import files"
./gendeflibs.sh $target.$deps

echo "Cleaning unnecessary files / directories"

# TODO Do we need to keep /share/doc and /share/gtk-doc?
rm -rf $repackage_dir/share/{aclocal,bash-completion,clang,cmake,config.site,doc,gdb,glib-2.0,gtk-2.0,gtk-doc,installed-tests,man,meson,opt-viewer,scan-build,scan-view,thumbnailers,xml}
rm -rf $repackage_dir/include/{cairo,clang-c,c++,llvm-c}
rm -rf $repackage_dir/lib/{*.so*,*cairo*,*gdk*,clang,ldscripts}

find $repackage_dir/lib -name "*.la" -exec rm -f {} \;

# We only support GB and de locales
find $repackage_dir/share/locale -mindepth 1 -maxdepth 1 -type d ! -name "en_GB" ! -name "de" -exec rm -rf {} \;

# Remove those .gitkeep files
rm $repackage_dir/{include/.gitkeep,lib/.gitkeep,share/.gitkeep}

if [ "$type" = "shared" ]; then
  echo "Copying vips executables"

  # We still need to copy the vips executables
  cp $mxe_prefix/$target.$deps/bin/{vips,vipsedit,vipsheader,vipsthumbnail}.exe $repackage_dir/bin/
fi

echo "Strip unneeded symbols"

# Remove all symbols that are not needed
$mxe_prefix/bin/$target.$deps-strip --strip-unneeded $repackage_dir/bin/*.{exe,dll}

echo "Copying packaging files"

cp $mxe_dir/vips-packaging/{AUTHORS,ChangeLog,COPYING,README.md,versions.json} $repackage_dir

echo "Creating $zipfile"

zipfile=$vips_package-dev-$arch-$deps$zip_suffix.zip
rm -f $zipfile
zip -r -qq $zipfile $repackage_dir
