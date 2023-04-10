#! /bin/bash


set -e
set -x

unset TEXMFCNF; export TEXMFCNF
LANG=C; export LANG

# Need the fallback path for testing in some cases.
if [ "$(uname)" == "Darwin" ]
then
    export LIBRARY_SEARCH_VAR=DYLD_FALLBACK_LIBRARY_PATH
else
    export LIBRARY_SEARCH_VAR=LD_LIBRARY_PATH
fi

# Using texlive just does not work, various sub-parts ignore that and use PREFIX/share
# SHARE_DIR=${PREFIX}/share/texlive
SHARE_DIR=${PREFIX}/share

declare -a CONFIG_EXTRA
if [[ ${target_platform} =~ .*ppc.* ]]; then
  # luajit is incompatible with powerpc.
  CONFIG_EXTRA+=(--disable-luajittex)
  CONFIG_EXTRA+=(--disable-mfluajit)
fi

TEST_SEGFAULT=no

if [[ ${TEST_SEGFAULT} == yes ]]; then
  # -O2 results in:
  # FAIL: mplibdir/mptraptest.test
  # FAIL: pdftexdir/pdftosrc.test
  # .. so (sorry!)
  export CFLAGS="${CFLAGS} -O0 -ggdb"
  export CXXFLAGS="${CXXFLAGS} -O0 -ggdb"
  CONFIG_EXTRA+=(--enable-debug)
else
  CONFIG_EXTRA+=(--disable-debug)
fi

# kpathsea scans the texmf.cnf file to set up its hardcoded paths, so set them
# up before building. It doesn't seem to handle multivalued TEXMFCNF entries,
# so we patch that up after install.

mv $SRC_DIR/texk/kpathsea/texmf.cnf tmp.cnf
sed \
    -e "s|TEXMFROOT =.*|TEXMFROOT = ${SHARE_DIR}|" \
    -e "s|TEXMFLOCAL =.*|TEXMFLOCAL = ${SHARE_DIR}/texmf-local|" \
    -e "/^TEXMFCNF/,/^}/d" \
    -e "s|%TEXMFCNF =.*|TEXMFCNF = ${SHARE_DIR}/texmf-dist/web2c|" \
    <tmp.cnf >$SRC_DIR/texk/kpathsea/texmf.cnf
rm -f tmp.cnf

export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"

[[ -d "${SHARE_DIR}/tlpkg/TeXLive" ]] || mkdir -p "${SHARE_DIR}/tlpkg/TeXLive"
[[ -d "${SHARE_DIR}/texmf-dist/scripts/texlive" ]] || mkdir -p "${SHARE_DIR}/texmf-dist/scripts/texlive"

# When cross-compiling, we need to build tangle natively and the
# dependencies, so we need to build the whole thing.
if [[ "$CONDA_BUILD_CROSS_COMPILATION" == 1 ]]; then
  (
    mkdir -p native_build
    pushd native_build

    export CC=$CC_FOR_BUILD
    export CXX=$CXX_FOR_BUILD
    export OBJCXX=$CXX_FOR_BUILD
    export AR=($CC_FOR_BUILD -print-prog-name=ar)
    export NM=($CC_FOR_BUILD -print-prog-name=nm)
    export LD=($CC_FOR_BUILD -print-prog-name=ld)
    export LDFLAGS=${LDFLAGS//$PREFIX/$BUILD_PREFIX}
    export PKG_CONFIG_PATH=${BUILD_PREFIX}/lib/pkgconfig

    ../configure --prefix=$BUILD_PREFIX \
                 --host=${BUILD} \
                 --build=${BUILD} \
                 --datarootdir="${SHARE_DIR}" \
                 --disable-all-pkgs \
                 --disable-native-texlive-build \
                 --disable-ipc \
                 --disable-debug \
                 --disable-dependency-tracking \
                 --disable-mf \
                 --disable-pmp \
                 --disable-upmp \
                 --disable-aleph \
                 --disable-eptex \
                 --disable-euptex \
                 --disable-luatex \
                 --disable-luajittex \
                 --disable-uptex \
                 --enable-web2c \
                 --without-x \
                 "${CONFIG_EXTRA[@]}" || { cat config.log ; exit 1 ; }

    # There is a race-condition in the build system.
    make -j${CPU_COUNT} ${VERBOSE_AT} || make -j1 ${VERBOSE_AT}

    popd
  )
  # Point to the locations of the tangle executables.
  export TANGLEBOOT=$SRC_DIR/native_build/texk/web2c/tangleboot
  export TANGLE=$SRC_DIR/native_build/texk/web2c/tangle
  export CTANGLEBOOT=$SRC_DIR/native_build/texk/web2c/ctangleboot
  export CTANGLE=$SRC_DIR/native_build/texk/web2c/ctangle
  export TIE=$SRC_DIR/native_build/texk/web2c/tie
  export OTANGLE=$SRC_DIR/native_build/texk/web2c/otangle

  # Patch $SRC_DIR/texk/web2c/Makefile.in to use the native build of himktables.
  sed -i \
      "s^\./himktables^$SRC_DIR/native_build/texk/web2c/himktables^g" \
      $SRC_DIR/texk/web2c/Makefile.in
fi

# The Makefile also expects OBJCXX to be set. This is vital
# for cross-compiling, but we should be using the correct compiler
# aliases everywhere.
export OBJCXX=$CXX
export BUILDCC=$CC_FOR_BUILD

# We need to package graphite2 to be able to use it harfbuzz.
# Using our cairo breaks the recipe and `mpfr` is not found triggering the library from TL tree.

mkdir -p tmp_build && pushd tmp_build
  ../configure --prefix=$PREFIX \
               --host=${HOST} \
               --build=${BUILD} \
               --datarootdir="${SHARE_DIR}" \
               --disable-all-pkgs \
               --disable-native-texlive-build \
               --disable-ipc \
               --disable-debug \
               --disable-dependency-tracking \
               --disable-mf \
               --disable-pmp \
               --disable-upmp \
               --disable-aleph \
               --disable-eptex \
               --disable-euptex \
               --disable-luatex \
               --disable-luajittex \
               --disable-uptex \
               --enable-web2c \
               --enable-silent-rules \
               --enable-tex \
               --enable-etex \
               --enable-pdftex \
               --enable-xetex \
               --enable-web-progs \
               --enable-texlive \
               --enable-dvipdfm-x \
               --with-system-icu \
               --with-system-gmp \
               --with-system-cairo \
               --with-system-pixman \
               --with-system-freetype2 \
               --with-system-libpng \
               --with-system-zlib \
               --with-system-mpfr \
               --with-system-harfbuzz \
               --with-system-graphite2 \
               --with-system-poppler \
               --without-x \
               "${CONFIG_EXTRA[@]}" || { cat config.log ; exit 1 ; }
  # There is a race-condition in the build system.
  make -j${CPU_COUNT} ${VERBOSE_AT} || make -j1 ${VERBOSE_AT}
  # make check reads files from the installation prefix:
  make install -j${CPU_COUNT}
  # Only do make check tests on native builds.
  if [[ "$CONDA_BUILD_CROSS_COMPILATION" != 1 ]]; then
    if [[ ! ${target_platform} =~ .*linux.* ]]; then
      VERBOSE=1 LC_ALL=C make check ${VERBOSE_AT}
    elif [[ ${TEST_SEGFAULT} == yes ]] && [[ ${target_platform} =~ .*linux.* ]]; then
      LC_ALL=C make check ${VERBOSE_AT}
      echo "pushd ${SRC_DIR}/tmp_build/texk/web2c"
      echo "LC_ALL=C make check ${VERBOSE_AT}"
      echo "cat mplibdir/mptraptest.log"
      pushd "${SRC_DIR}/tmp_build/texk/web2c/mpost"
        # I believe mpost test fails here because it tries to load mpost itself as a configuration file
        # .. this happens in both failing tests on Linux. Debug builds (CFLAGS-wise) do not suffer a
        # segfault at this point but release ones. Skipping for now, will re-visit later.
        LC_ALL=C ../mpost --ini ../mpost
      popd
      exit 1
    fi
  fi
popd

# Remove info and man pages.
rm -rf ${SHARE_DIR}/man
rm -rf ${SHARE_DIR}/info

mv ${SHARE_DIR}/texmf-dist/web2c/texmf.cnf tmp.cnf
sed \
    -e "s|TEXMFCNF =.*|TEXMFCNF = {${SHARE_DIR}/texmf-local/web2c, ${SHARE_DIR}/texmf-dist/web2c}|" \
    <tmp.cnf >${SHARE_DIR}/texmf-dist/web2c/texmf.cnf
rm -f tmp.cnf

# Create symlinks for pdflatex and latex
ln -s $PREFIX/bin/pdftex $PREFIX/bin/pdflatex
ln -s $PREFIX/bin/pdftex $PREFIX/bin/latex
