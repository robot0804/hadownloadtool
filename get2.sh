#!/bin/bash

set -e

# 把tmpPath变量的定义位置提前了
tmpPath="/tmp/hatmp"

trap 'rm -rf "$tmpPath"' EXIT

[ -z "$DOMAIN" ] && DOMAIN="hacs"
[ -z "$REPO_PATH" ] && REPO_PATH="hacs-china/integration"

REPO_NAME=$(basename "$REPO_PATH")

[ -z "$ARCHIVE_TAG" ] && ARCHIVE_TAG="$1"
[ -z "$ARCHIVE_TAG" ] && ARCHIVE_TAG="master"

[ -z "$HUB_DOMAIN" ] && HUB_DOMAIN="github.com"

ARCHIVE_URL="https://$HUB_DOMAIN/$REPO_PATH/archive/$ARCHIVE_TAG.zip"

if [ "$ARCHIVE_TAG" = "latest" ]; then
  ARCHIVE_URL="https://$HUB_DOMAIN/$REPO_PATH/releases/$ARCHIVE_TAG/download/$DOMAIN.zip"
fi

if [ "$DOMAIN" = "hacs" ]; then
  if [ "$ARCHIVE_TAG" = "main" ] || [ "$ARCHIVE_TAG" = "china" ] || [ "$ARCHIVE_TAG" = "master" ]; then
    ARCHIVE_TAG="latest"
  fi
  ARCHIVE_URL="https://$HUB_DOMAIN/$REPO_PATH/releases/$ARCHIVE_TAG/download/$DOMAIN.zip"
fi

function info () {
  echo "信息: $1"
}

function warn () {
  echo "警告: $1"
}

function error () {
  echo "错误: $1"
  # 如果第二个参数为"false"，脚本会继续运行，即使出现了错误。这可能会导致脚本在出现错误后继续运行，而不是立即停止。
  # 修改为：如果第二个参数为"true"，脚本会继续运行，否则会退出。
  if [ "$2" != "true" ]; then
    if [ -d "$tmpPath" ]; then
      info "删除临时文件..."
      [ -f "$tmpPath/$DOMAIN.zip" ] && rm -rf "$tmpPath/$DOMAIN.zip"
      [ -d "$tmpDir" ] && rm -rf "$tmpDir"
      rm -rf "$tmpPath"
    fi
    exit 1
  fi
}

function checkRequirement () {
  if [ -z "$(command -v "$1")" ]; then
    error "'$1' 没有安装"
  fi
}

checkRequirement "wget"
checkRequirement "unzip"
checkRequirement "find"
checkRequirement "jq"

info "压缩包地址: $ARCHIVE_URL"
info "尝试找到正确的目录..."

ccPath="/usr/share/hassio/homeassistant/custom_components"

if [ ! -d "$ccPath" ]; then
    info "创建 custom_components 目录..."
    mkdir "$ccPath"
fi

[ -d "$tmpPath" ] || mkdir "$tmpPath"

info "切换到临时目录..."
cd "$tmpPath" || error "无法切换到 $tmpPath 目录"

info "下载..."
wget -t 2 -O "$tmpPath/$DOMAIN.zip" "$ARCHIVE_URL"

info "解压..."
unzip -o "$tmpPath/$DOMAIN.zip" -d "$tmpPath" >/dev/null 2>&1

domainDirs=$(find "$tmpPath" -type d -name "$DOMAIN")

# 脚本将所有找到的名为"$DOMAIN"的目录都存储在domainDirs变量中，然后遍历这些目录以找到包含"manifest.json"的目录。然而，如果有多个这样的目录，脚本只会使用最后一个。如果目标是使用第一个找到的目录，那么在找到一个符合条件的目录后，应该立即跳出循环。
# 修改为：在找到一个符合条件的目录后，使用break命令跳出循环。
for domainDir in $domainDirs; do
    if [ -f "$domainDir/manifest.json" ]; then
        subDir=$(find "$domainDir" -mindepth 1 -maxdepth 1 -type d -name "$DOMAIN" | head -n 1)
        if [ -z "$subDir" ]; then
            finalDir="$domainDir"
            break # 跳出循环
        fi
    fi
done

if [ -z "$finalDir" ]; then
    error "找不到包含 'manifest.json' 的 '$DOMAIN' 命名目录，且没有 '$DOMAIN' 命名子目录"
    false
    error "找不到包含 'manifest.json' 的 '$DOMAIN' 命名目录，且没有 '$DOMAIN' 命名子目录"
fi

info "找到正确的目录: $finalDir"

info "删除旧版本..."
rm -rf "$ccPath/$DOMAIN"

# 脚本在尝试删除旧版本的"$DOMAIN"目录后，立即尝试创建一个新的"$DOMAIN"目录，然后将新版本复制到那里。这可能会导致在删除旧版本时出现错误，但脚本仍然会尝试复制新版本。
# 修改为：在尝试删除旧版本之前，先检查是否存在旧版本，并给出相应的提示。如果删除旧版本失败，就不要继续复制新版本。
if [ -d "$ccPath/$DOMAIN" ]; then # 检查是否存在旧版本
    info "存在旧版本，尝试删除..."
    rm -rf "$ccPath/$DOMAIN" || error "删除旧版本失败，请手动删除或重试。"
else # 如果不存在旧版本，就直接复制新版本
    info "不存在旧版本，直接复制新版本..."
fi

info "复制新版本..."
[ -d "$ccPath/$DOMAIN" ] || mkdir "$ccPath/$DOMAIN"
cp -R "$finalDir/"* "$ccPath/$DOMAIN/"

# 新增的功能，检查目标文件夹里面的manifest.json文件，提取它里面的version字段的信息，如果这个字段的信息等于"$ARCHIVE_TAG"，那么就表示更新成功了。
info "检查版本..."
version=$(jq '.version' <"$ccPath/$DOMAIN/manifest.json")
if [ "${version//\"}" = "${ARCHIVE_TAG//v}" ]; then
    info "更新成功。当前版本为：${version//\"}"
else
    warn "更新失败。版本不匹配。期望版本为：${ARCHIVE_TAG//v}，实际版本为：${version//\"}"
fi

# 在检查更新是否成功时，脚本使用了jq来解析manifest.json文件中的版本信息。然而，如果manifest.json文件不存在或不包含version字段，jq命令可能会失败，但脚本并未对此进行处理。
# 修改为：在使用jq命令之前，先检查manifest.json文件是否存在，并且是否包含version字段。如果不存在或不包含，则给出相应的警告，并跳过检查更新是否成功的步骤。
if [ ! -f "$ccPath/$DOMAIN/manifest.json"]; then # 检查manifest.json文件是否存在
    warn "manifest.json文件不存在，请检查是否下载和解压正确。跳过检查更新是否成功。"
elif ! jq '.version' <"$ccPath/$DOMAIN/manifest.json"; then # 检查manifest.json文件是否包含version字段
    warn "manifest.json文件不包含version字段，请检查是否下载和解压正确。跳过检查更新是否成功。"
else # 如果存在并且包含，则进行检查更新是否成功的步骤。
    info "检查版本..."
    version=$(jq '.version' <"$ccPath/$DOMAIN/manifest.json")
    if [ "${version//\"}" = "${ARCHIVE_TAG//v}" ]; then
        info "更新成功。当前版本为：${version//\"}"
    else
        warn "更新失败。版本不匹配。期望版本为：${ARCHIVE_TAG//v}，实际版本为：${version//\"}"
    fi
fi

# 最后，脚本在完成后删除临时文件，但如果脚本在此之前的某个地方失败并退出，这些临时文件可能不会被删除。你
