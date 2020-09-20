$(PLUGIN_HEADER)

IS_LLVM := $(true)

# Override sub-dependencies
cc_DEPS   := llvm
rust_DEPS :=

# GCC does not support Windows on ARM
gcc_BUILD_aarch64-w64-mingw32 =
gcc_BUILD_armv7-w64-mingw32   =

# Update MinGW-w64 to 8.0.0
mingw-w64_VERSION  := 8.0.0
mingw-w64_CHECKSUM := 44c740ea6ab3924bc3aa169bad11ad3c5766c5c8459e3126d44eabb8735a5762
mingw-w64_PATCHES  := $(realpath $(sort $(wildcard $(dir $(lastword $(MAKEFILE_LIST)))/patches/mingw-w64-[0-9]*.patch)))
mingw-w64_SUBDIR   := mingw-w64-v$(mingw-w64_VERSION)
mingw-w64_FILE     := mingw-w64-v$(mingw-w64_VERSION).tar.bz2
mingw-w64_URL      := https://$(SOURCEFORGE_MIRROR)/project/mingw-w64/mingw-w64/mingw-w64-release/$(mingw-w64_FILE)

# libc++ uses Win32 threads to implement the internal
# threading API, so we do not need to build pthreads.
define pthreads_BUILD
    $(info $(PKG) is not built when the llvm-mingw plugin is used)
endef

# Build Rust from source to support the ARM targets and
# to ensure that it links against UCRT (the prebuilt Rust
# binaries are built with --with-default-msvcrt=msvcrt)
# TODO(kleisauke): Could we build from the stable channel?
rust_VERSION  := nightly
# https://static.rust-lang.org/dist/2020-09-20/rustc-nightly-src.tar.gz.sha256
rust_CHECKSUM := f6373662d8869d20291dfb29deb879a2acdf726058dbbbc62a0d31f681fa8490
rust_PATCHES  := $(realpath $(sort $(wildcard $(dir $(lastword $(MAKEFILE_LIST)))/patches/rust-[0-9]*.patch)))
rust_SUBDIR   := rustc-$(rust_VERSION)-src
rust_FILE     := rustc-$(rust_VERSION)-src.tar.gz
rust_URL      := https://static.rust-lang.org/dist/2020-09-20/$(rust_FILE)

export RUST_TARGET_PATH := $(dir $(lastword $(MAKEFILE_LIST)))/rust

define rust_BUILD
    # x86_64-pc-linux-gnu -> x86_64-unknown-linux-gnu
    $(eval BUILD_RUST := $(firstword $(subst -, ,$(BUILD)))-unknown-linux-gnu)

    # armv7 -> thumbv7a
    $(eval ARCH_NAME := $(if $(findstring armv7,$(PROCESSOR)),thumbv7a,$(PROCESSOR)))

    $(eval TARGET_RUST := $(ARCH_NAME)-pc-windows-gnu)

    # [major].[minor].[patch]-[label] -> [major].[minor].[patch]
    $(eval CLANG_VERSION := $(firstword $(subst -, ,$(clang_VERSION))))

    # Flags we use to build the std artifacts
    # Note: -Clink-self-contained=yes will link against the {,dll}crt2.o (defined in
    # pre_link_objects_fallback) from our MinGW distribution.
    # Note 2: -Clinker-flavor=ld.lld will force LLD as linker flavor for targets that
    # have not set this by default (i.e. {i686,x86_64}-pc-windows-gnu).
    # Note 3: The -Clink-arg=* options adds our MinGW distribution and the compiler-rt
    # builtins to the standard set of searched paths.
    $(eval STD_FLAGS := -Clink-self-contained=yes \
                        -Clinker-flavor=ld.lld \
                        -Clink-arg=-L$(PREFIX)/$(TARGET)/lib \
                        -Clink-arg=-L$(PREFIX)/$(TARGET)/mingw/lib \
                        -Clink-arg=-L$(PREFIX)/$(BUILD)/lib/clang/$(CLANG_VERSION)/lib/windows)
    $(eval export CARGO_TARGET_$(call uc,$(subst -,_,$(TARGET_RUST)))_RUSTFLAGS := $(STD_FLAGS))

    # We can't change LTO and panic strategy settings while we bootstrap Rust
    $(eval unexport CARGO_PROFILE_RELEASE_LTO)
    $(eval unexport CARGO_PROFILE_RELEASE_PANIC)

    cd '$(BUILD_DIR)' && $(SOURCE_DIR)/configure \
        --prefix='$(PREFIX)/$(TARGET)' \
        --build='$(BUILD_RUST)' \
        --host='$(BUILD_RUST)' \
        --target='$(BUILD_RUST),$(TARGET_RUST)' \
        --release-channel=stable \
        --enable-extended \
        --tools='cargo' \
        --disable-docs \
        --disable-codegen-tests \
        --python='$(PYTHON2)' \
        --llvm-root='$(PREFIX)/$(BUILD)' \
        --set target.$(BUILD_RUST).cc='$(BUILD_CC)' \
        --set target.$(BUILD_RUST).cxx='$(BUILD_CXX)' \
        --set target.$(BUILD_RUST).ar='$(PREFIX)/$(BUILD)/bin/llvm-ar' \
        --set target.$(BUILD_RUST).ranlib='$(PREFIX)/$(BUILD)/bin/llvm-ranlib' \
        --set target.$(TARGET_RUST).cc='$(TARGET)-clang' \
        --set target.$(TARGET_RUST).cxx='$(TARGET)-clang++' \
        --set target.$(TARGET_RUST).linker='ld.lld' \
        --set target.$(TARGET_RUST).ar='$(PREFIX)/bin/$(TARGET)-ar' \
        --set target.$(TARGET_RUST).ranlib='$(PREFIX)/bin/$(TARGET)-ranlib' \
        --set target.$(TARGET_RUST).llvm-config='$(PREFIX)/$(BUILD)/bin/llvm-config' \
        --set dist.src-tarball=false

    # We need to enable networking while we build Rust from
    # source. Assumes that the Rust build is reproducible.
    echo 'static int __attribute__((unused)) _dummy;' > '$(BUILD_DIR)/dummy.c'
    $(BUILD_CC) -shared -fPIC $(NONET_CFLAGS) -o $(NONET_LIB) $(BUILD_DIR)/dummy.c

    # Build Rust
    cd '$(BUILD_DIR)' && \
        $(PYTHON2) $(SOURCE_DIR)/x.py build -j '$(JOBS)' -v

    # TODO(kleisauke): Build and package up Rust for distribution
    # cd '$(BUILD_DIR)' && \
    #     DESTDIR=/data \
    #     $(PYTHON2) $(SOURCE_DIR)/x.py dist --keep-stage 1 -j '$(JOBS)' -v

    # Install Rust
    cd '$(BUILD_DIR)' && \
        $(PYTHON2) $(SOURCE_DIR)/x.py install --keep-stage 1 -j '$(JOBS)' -v

    # Disable networking (again) for reproducible builds further on
    $(BUILD_CC) -shared -fPIC $(NONET_CFLAGS) -o $(NONET_LIB) $(TOP_DIR)/tools/nonetwork.c

    # Install prefixed wrappers
    (echo '#!/usr/bin/env bash'; \
     echo 'CARGO_HOME="$(PREFIX)/$(TARGET)/.cargo" \'; \
     echo 'RUSTC="$(PREFIX)/bin/$(TARGET)-rustc" \'; \
     echo 'exec $(PREFIX)/$(TARGET)/bin/cargo \'; \
     echo '"$$@"';) \
             > '$(PREFIX)/bin/$(TARGET)-cargo'
    chmod 0755 '$(PREFIX)/bin/$(TARGET)-cargo'

    ln -sf '$(PREFIX)/$(TARGET)/bin/rustc' '$(PREFIX)/bin/$(TARGET)-rustc'
endef
