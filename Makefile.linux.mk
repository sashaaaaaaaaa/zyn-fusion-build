include Common.mk
include Install-deps.mk

OS		:= linux

# Detect architecture (SlackBuilds.org convention)
ARCH := $(shell uname -m)
ifeq ($(ARCH), x86_64)
  LIBDIRSUFFIX := 64
else
  LIBDIRSUFFIX :=
endif

#
############################ ZynAddSubFX Rules ############################
#

#
# Final make rule
#
get_zynaddsubfx: fetch_zynaddsubfx

build_zynaddsubfx:
	$(info ========== Building ZynAddSubFX in $(MODE) mode ==========)

	rm -rf $(ZYNADDSUBFX_BUILD_DIR)
	mkdir -p $(ZYNADDSUBFX_BUILD_DIR)

	cd $(ZYNADDSUBFX_BUILD_DIR); \
	cmake $(ZYNADDSUBFX_PATH) \
		-DGuiModule=zest \
		-DDemoMode=$(DEMO_MODE) \
		-DCMAKE_INSTALL_PREFIX=/usr \

	$(MAKE) -C $(ZYNADDSUBFX_BUILD_DIR)

#
############################ Zest Rules ############################
#

revoke_mruby_patches: fetch_zest
ifneq ($(ZEST_COMMIT), DIRTY)
	cd $(ZEST_PATH)/mruby ; \
	git checkout -- .
endif

setup_zest: fetch_zest revoke_mruby_patches
	cd $(ZEST_PATH) ; \
	ruby rebuild-fcache.rb

#
# Final Make rule
#
get_zest: fetch_zest revoke_mruby_patches setup_zest

# Patches for /opt/zyn-fusion deployment (applied after git checkout, reverted after pack)
PATCHES := $(wildcard $(TOP)/patches/*.patch)

build_zest: get_zest
	$(info ========== Building Zest in $(MODE) mode ==========)

	$(MAKE) -C $(ZEST_PATH) clean

	cd $(ZEST_PATH); \
	rm -f package/qml/*.qml; \
	ruby rebuild-fcache.rb

ifneq ($(PATCHES),)
	# Apply custom patches
	for p in $(PATCHES); do \
		echo "Applying $$p..."; \
		cd $(ZEST_PATH) && patch -p1 -N -t < $$p; \
	done
endif

	VERSION=$(VER) BUILD_MODE=$(MODE) \
	$(MAKE) -C $(ZEST_PATH)
	$(MAKE) -C $(ZEST_PATH) pack

ifneq ($(PATCHES),)
	# Revert patches to keep source tree clean
	for p in $(PATCHES); do \
		echo "Reverting $$p..."; \
		cd $(ZEST_PATH) && patch -p1 -R -N -t < $$p; \
	done
endif

	cd $(ZEST_PATH); \
	rm -f package/qml/*.qml

#
############################ Packing Up Rules ############################
#

TARGET_TAR_FILE	:= $(BUILD_PATH)/zyn-fusion-linux-64bit-$(VER)-$(MODE).tar.bz2
ZYN_FUSION_OUT	:= $(BUILD_PATH)/zyn-fusion-linux-64bit-$(VER)-$(MODE)

preinstall_zynaddsubfx: build_zynaddsubfx
	rm -rf $(ZYNADDSUBFX_INSTALL_DIR)
	$(MAKE) DESTDIR="$(ZYNADDSUBFX_INSTALL_DIR)" -C $(ZYNADDSUBFX_BUILD_DIR) install

copy_zest_files: preinstall_zynaddsubfx build_zest
	rm -rf $(ZYN_FUSION_OUT)
	mkdir  $(ZYN_FUSION_OUT)

	cp   -a $(ZYNADDSUBFX_INSTALL_DIR)/usr/lib/lv2/ZynAddSubFX.lv2presets	 $(ZYN_FUSION_OUT)/

	cp   -a $(ZYNADDSUBFX_PATH)/instruments/banks		 $(ZYN_FUSION_OUT)/
	cp	  $(ZEST_PATH)/package/libzest.so   $(ZYN_FUSION_OUT)/
	cp	  $(ZEST_PATH)/package/zest		 $(ZYN_FUSION_OUT)/zyn-fusion
	cp   -a $(ZEST_PATH)/package/font		 $(ZYN_FUSION_OUT)/

	mkdir  $(ZYN_FUSION_OUT)/qml
	touch  $(ZYN_FUSION_OUT)/qml/MainWindow.qml

	cp   -a $(ZEST_PATH)/package/schema	   $(ZYN_FUSION_OUT)/
	mkdir   $(ZYN_FUSION_OUT)/ZynAddSubFX.lv2
	cp	  $(ZYNADDSUBFX_BUILD_DIR)/src/Plugin/ZynAddSubFX/lv2/* $(ZYN_FUSION_OUT)/ZynAddSubFX.lv2/
	cp	  $(ZYNADDSUBFX_BUILD_DIR)/src/Plugin/ZynAddSubFX/vst/ZynAddSubFX.so $(ZYN_FUSION_OUT)/
	cp	  $(ZYNADDSUBFX_BUILD_DIR)/src/zynaddsubfx $(ZYN_FUSION_OUT)/
	cp	  $(ZEST_PATH)/install-linux.sh $(ZYN_FUSION_OUT)/
	cp	  $(ZEST_PATH)/package-README.txt $(ZYN_FUSION_OUT)/README.txt
	cp	  $(ZYNADDSUBFX_PATH)/COPYING $(ZYN_FUSION_OUT)/COPYING.zynaddsubfx

package: zynaddsubfx zest copy_zest_files
	rm -rf $(TARGET_TAR_FILE)

# Use `basename` to avoid packing up absolute path
	cd $(ZYN_FUSION_OUT)/../ ; \
	tar acf $(TARGET_TAR_FILE) ./$(shell basename $(ZYN_FUSION_OUT))
	ls
	@echo "Finished! Made Package in $(MODE) Mode"

SLACK_PKG_DIR := $(BUILD_PATH)/slackware-pkg
SLACK_PKG_NAME := zyn-fusion-$(VER)-$(ARCH)-1.tgz

slackware-pkg: zynaddsubfx zest
	$(info ========== Building Slackware Package ==========)
	rm -rf $(SLACK_PKG_DIR)
	mkdir -p $(SLACK_PKG_DIR)

	# 1. cmake DESTDIR install (plugins + banks + lib + binary + data)
	$(MAKE) DESTDIR="$(SLACK_PKG_DIR)" -C $(ZYNADDSUBFX_BUILD_DIR) install

	# 2. Move plugin lib -> lib64 on x86_64 (SBo convention)
ifneq ($(LIBDIRSUFFIX),)
	test -d $(SLACK_PKG_DIR)/usr/lib && mv $(SLACK_PKG_DIR)/usr/lib $(SLACK_PKG_DIR)/usr/lib$(LIBDIRSUFFIX) || true
endif

	# 3. Create /opt/zyn-fusion/ (upstream layout — no patches needed)
	mkdir -p $(SLACK_PKG_DIR)/opt/zyn-fusion/qml
	mkdir -p $(SLACK_PKG_DIR)/opt/zyn-fusion/font
	mkdir -p $(SLACK_PKG_DIR)/opt/zyn-fusion/schema

	cp $(ZEST_PATH)/package/zest          $(SLACK_PKG_DIR)/opt/zyn-fusion/zyn-fusion
	cp $(ZEST_PATH)/package/libzest.so    $(SLACK_PKG_DIR)/opt/zyn-fusion/
	cp $(ZEST_PATH)/src/mruby-zest/qml/*.qml     $(SLACK_PKG_DIR)/opt/zyn-fusion/qml/
	cp $(ZEST_PATH)/src/mruby-zest/example/*.qml $(SLACK_PKG_DIR)/opt/zyn-fusion/qml/
	cp $(ZEST_PATH)/deps/nanovg/example/*.ttf    $(SLACK_PKG_DIR)/opt/zyn-fusion/font/
	cp $(ZEST_PATH)/src/osc-bridge/schema/test.json $(SLACK_PKG_DIR)/opt/zyn-fusion/schema/

	# 4. Symlink for PATH access
	mkdir -p $(SLACK_PKG_DIR)/usr/bin
	ln -s /opt/zyn-fusion/zyn-fusion $(SLACK_PKG_DIR)/usr/bin/zyn-fusion

	# 5. Doc dir (SBo: usr/doc/<pkg>-<ver>)
	mkdir -p $(SLACK_PKG_DIR)/usr/doc/zyn-fusion-$(VER)
	test -d $(SLACK_PKG_DIR)/usr/share/doc/zynaddsubfx && \
	  cp -a $(SLACK_PKG_DIR)/usr/share/doc/zynaddsubfx/* \
	    $(SLACK_PKG_DIR)/usr/doc/zyn-fusion-$(VER)/ || true
	rm -rf $(SLACK_PKG_DIR)/usr/share/doc

	# 6. Install metadata
	mkdir -p $(SLACK_PKG_DIR)/install
	cp $(TOP)/slackware/slack-desc  $(SLACK_PKG_DIR)/install/
	cp $(TOP)/slackware/doinst.sh   $(SLACK_PKG_DIR)/install/

	# 7. Fix ownership (requires root; no-op for non-root builds)
	cd $(SLACK_PKG_DIR) && chown -R root:root . || true

	# 8. Strip ELF binaries and shared libs
	find $(SLACK_PKG_DIR)/opt -type f -exec strip --strip-unneeded {} \; 2>/dev/null || true
	find $(SLACK_PKG_DIR)/usr/bin -type f -exec strip --strip-unneeded {} \; 2>/dev/null || true
	find $(SLACK_PKG_DIR)/usr/lib$(LIBDIRSUFFIX) -type f -name "*.so*" -exec strip --strip-unneeded {} \; 2>/dev/null || true

	# 9. Package
	cd $(SLACK_PKG_DIR) && \
	/sbin/makepkg -l y -c n $(BUILD_PATH)/$(SLACK_PKG_NAME)
	@echo "Finished! Slackware Package: $(BUILD_PATH)/$(SLACK_PKG_NAME)"
