PKG             := uhdr
$(PKG)_WEBSITE  := https://github.com/google/libultrahdr
$(PKG)_DESCR    := Library for encoding and decoding ultrahdr images
$(PKG)_IGNORE   :=
$(PKG)_VERSION  := 1.5.0
$(PKG)_CHECKSUM := 2516ea9cb69a0efd42959fad56de760fcb898a4944231f20789f9c5387ca9c81
$(PKG)_PATCHES  := $(realpath $(sort $(wildcard $(dir $(lastword $(MAKEFILE_LIST)))/patches/$(PKG)-[0-9]*.patch)))
$(PKG)_GH_CONF  := google/libultrahdr/tags,v
$(PKG)_DEPS     := cc libjpeg-turbo

define $(PKG)_BUILD
    $(eval export CFLAGS += -O3)
    $(eval export CXXFLAGS += -O3)

    # Ensure install targets are enabled when cross-compiling
    $(SED) -i 's/CMAKE_CROSSCOMPILING AND UHDR_ENABLE_INSTALL/FALSE/' '$(SOURCE_DIR)/CMakeLists.txt'

    cd '$(BUILD_DIR)' && $(TARGET)-cmake \
        -DUHDR_BUILD_EXAMPLES=FALSE \
        -DUHDR_MAX_DIMENSION=65500 \
        '$(SOURCE_DIR)'
    $(MAKE) -C '$(BUILD_DIR)' -j '$(JOBS)'
    $(MAKE) -C '$(BUILD_DIR)' -j 1 $(subst -,/,$(INSTALL_STRIP_LIB))
endef
