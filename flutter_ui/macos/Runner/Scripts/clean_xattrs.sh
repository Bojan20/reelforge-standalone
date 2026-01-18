#\!/bin/bash
# Clean extended attributes before code signing
xattr -cr "$TARGET_BUILD_DIR/$PRODUCT_NAME.app" 2>/dev/null || true
find "$TARGET_BUILD_DIR/$PRODUCT_NAME.app" -name "._*" -delete 2>/dev/null || true
dot_clean "$TARGET_BUILD_DIR/$PRODUCT_NAME.app" 2>/dev/null || true

