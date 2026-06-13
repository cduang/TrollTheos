#!/bin/bash
# 构建 UnjailTheos .tipa（TrollStore 侧载包）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="UnjailTheos"
PROJECT="UnjailTheos.xcodeproj"
CONFIG="Release"
DERIVED="$ROOT/build/DerivedData"
DIST="$ROOT/dist"
APP_ENTITLEMENTS="UnjailTheos/UnjailTheos.entitlements"
HELPER_ENTITLEMENTS="RootHelper/RootHelper.entitlements"
PRODUCT="UnjailTheos"

echo "==> 清理旧产物"
rm -rf "$DERIVED" "$DIST"
mkdir -p "$DIST"

echo "==> xcodebuild Release (iphoneos)"
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS=arm64

APP="$(find "$DERIVED" -name "${PRODUCT}.app" -type d | head -1)"
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "错误: 未找到 ${PRODUCT}.app"
  find "$DERIVED" -name "*.app" -type d || true
  exit 1
fi
echo "==> App 路径: $APP"

install_ldid() {
  if command -v ldid >/dev/null 2>&1; then
    return 0
  fi
  echo "==> 安装 ldid..."
  if command -v brew >/dev/null 2>&1; then
    brew install ldid 2>/dev/null || true
  fi
  if ! command -v ldid >/dev/null 2>&1; then
    TMP=/tmp/ldid-build
    rm -rf "$TMP"
    git clone --depth 1 https://github.com/opa334/ldid.git "$TMP"
    make -C "$TMP"
    install -m755 "$TMP/ldid" /usr/local/bin/ldid
  fi
}

echo "==> ldid 签名（TrollStore entitlements）"
install_ldid
ldid -S"$APP_ENTITLEMENTS" "$APP/$PRODUCT"
if [ -f "$APP/roothelper" ]; then
  ldid -S"$HELPER_ENTITLEMENTS" "$APP/roothelper"
  echo "==> 已签名 roothelper"
fi

echo "==> 打包 .tipa"
PAYLOAD="$ROOT/build/Payload"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD"
cp -R "$APP" "$PAYLOAD/"
TIPA="$DIST/${PRODUCT}.tipa"
rm -f "$TIPA"
cd "$ROOT/build"
zip -qr "$TIPA" Payload
rm -rf "$PAYLOAD"

echo "==> 完成: $TIPA"
ls -lh "$TIPA"
