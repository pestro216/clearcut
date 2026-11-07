#!/usr/bin/env bash
# Downloads BiRefNet Lite 1024 for Core ML (MIT; BiRefNet by Peng Zheng et al., conversion by the
# birefnet-lite-coreml project) and checks it byte for byte against the published hashes.
# Usage: tools/fetch_model.sh <destination .mlpackage path>
set -euo pipefail
dest="$1"
if [ -f "$dest/Data/com.apple.CoreML/weights/weight.bin" ]; then echo "Model already present"; exit 0; fi
tmp="$(mktemp -d)"
name="BiRefNetLite-1024-FP16Compute-FP32IO"
archive_sha="46e7f3306069d1385761c0db86d65913dc3f980bf5348eb0c3db429e3f8414b7"
url="https://huggingface.co/metaclass/birefnet-lite-coreml/resolve/main/fp16compute-fp32io/r1/${name}-iOS17-r1.mlpackage.zip"
if curl -fsSL --retry 3 -o "$tmp/m.zip" "$url" && echo "$archive_sha  $tmp/m.zip" | shasum -a 256 -c -; then
  (cd "$tmp" && unzip -q m.zip)
  src="$(find "$tmp" -maxdepth 3 -name "${name}.mlpackage" -type d | head -1)"
else
  echo "Archive unavailable, using the file-by-file mirror"
  src="$tmp/${name}.mlpackage"
  base="https://huggingface.co/getcay/birefnet-lite-coreml/resolve/main/${name}.mlpackage"
  while read -r sha path; do
    mkdir -p "$src/$(dirname "$path")"
    curl -fsSL --retry 3 -o "$src/$path" "$base/$path"
    echo "$sha  $src/$path" | shasum -a 256 -c -
  done <<'LIST'
c39212792a938d5cf424d40a3159b9dc18900ba03ae2d44f5f3791c172358c78 Manifest.json
7652ec19a5eb62217a2428be416c2bce5103a249afd203d397638e03f1b8a58c Data/com.apple.CoreML/model.mlmodel
db2e2a429f5b0f20d2d65f95bfd9517648a977aa73da71e4eaf0a95175312565 Data/com.apple.CoreML/weights/weight.bin
LIST
fi
echo "db2e2a429f5b0f20d2d65f95bfd9517648a977aa73da71e4eaf0a95175312565  $src/Data/com.apple.CoreML/weights/weight.bin" | shasum -a 256 -c -
mkdir -p "$(dirname "$dest")"
rm -rf "$dest"
cp -R "$src" "$dest"
rm -rf "$tmp"
echo "Model ready at $dest"
