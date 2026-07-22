PKG             := uhdr
$(PKG)_WEBSITE  := https://github.com/google/libultrahdr
$(PKG)_DESCR    := Library for encoding and decoding ultrahdr images
$(PKG)_IGNORE   :=
# https://github.com/google/libultrahdr/tarball/ad4a92eea0d2f39f18b5ecae3165fdd56c6a478b
$(PKG)_VERSION  := ad4a92e
$(PKG)_CHECKSUM := 4156eb28c27e2aa0f3aa0dc77b117a7c1d47ccfa4f04a0566dfc2f00b8cceee7
$(PKG)_PATCHES  := $(realpath $(sort $(wildcard $(dir $(lastword $(MAKEFILE_LIST)))/patches/$(PKG)-[0-9]*.patch)))
$(PKG)_GH_CONF  := google/libultrahdr/branches/main
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
