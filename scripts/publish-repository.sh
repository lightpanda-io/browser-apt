#!/usr/bin/env bash
set -euo pipefail

# Aptly nests package files; the previous pool is empty on the first publication.
shopt -s globstar nullglob

if [ "$#" -ne 3 ]; then
  printf 'Usage: %s VERSION RELEASE_PACKAGES_DIRECTORY PREVIOUS_POOL\n' "$0" >&2
  exit 1
fi

version="$1"
release_packages="$2"
previous_pool="$3"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/packages"

# Allow retries without replacing an existing package version with different bytes.
stage_package() {
  local file="$1"
  local name="$2"
  local package_version="$3"
  local architecture="$4"
  local destination

  destination="$work/packages/${name}_${package_version}_${architecture}.deb"
  if [ -f "$destination" ]; then
    if ! cmp -s "$file" "$destination"; then
      printf 'Refusing changed bytes for existing package: %s\n' "${destination##*/}" >&2
      return 1
    fi
  else
    cp "$file" "$destination"
  fi
}

# Keep older versions discoverable in the regenerated APT indexes.
for file in "$previous_pool"/**/*.deb; do
  name="$(dpkg-deb -f "$file" Package)"
  package_version="$(dpkg-deb -f "$file" Version)"
  architecture="$(dpkg-deb -f "$file" Architecture)"

  stage_package "$file" "$name" "$package_version" "$architecture"
done

# Asset filenames alone do not guarantee the package metadata matches the release.
for arch in amd64 arm64; do
  file="$release_packages/lightpanda_${version}_${arch}.deb"
  name="$(dpkg-deb -f "$file" Package)"
  package_version="$(dpkg-deb -f "$file" Version)"
  architecture="$(dpkg-deb -f "$file" Architecture)"

  if [ "$name" != lightpanda ]; then
    echo "Expected package lightpanda, got $name in $file" >&2
    exit 1
  fi

  if [ "$package_version" != "$version" ]; then
    echo "Expected version $version in $file" >&2
    exit 1
  fi

  if [ "$architecture" != "$arch" ]; then
    echo "Expected architecture $arch in $file" >&2
    exit 1
  fi

  stage_package "$file" "$name" "$package_version" "$architecture"
done

config="$work/aptly.conf"
jq --null-input \
  --arg root "$work/aptly" \
  --arg bucket "$BUCKET" \
  --arg region "$AWS_REGION" \
  '{
    rootDir: $root,
    architectures: ["amd64", "arm64"],
    S3PublishEndpoints: {
      lightpanda: {bucket: $bucket, region: $region, acl: "none"}
    }
  }' > "$config"

aptly -config="$config" repo create -distribution=stable -component=main lightpanda
aptly -config="$config" repo add lightpanda "$work/packages"
aptly -config="$config" snapshot create release from repo lightpanda

# Aptly's batch mode enables GPG loopback, so no custom GPG configuration is needed.
aptly -config="$config" publish snapshot \
  -batch \
  -gpg-key="$APT_SIGNING_FINGERPRINT" \
  -passphrase-file="$APT_PASSPHRASE_FILE" \
  -distribution=stable \
  -component=main \
  -architectures=amd64,arm64 \
  -origin=Lightpanda \
  -label=Lightpanda \
  -acquire-by-hash \
  -skip-contents \
  release s3:lightpanda:

# Aptly publishes repository metadata, but not these client setup files.
gpg --batch --armor --export "$APT_SIGNING_FINGERPRINT" > "$work/lightpanda.asc"
if [ ! -s "$work/lightpanda.asc" ]; then
  echo "GPG did not export a public key for $APT_SIGNING_FINGERPRINT" >&2
  exit 1
fi

cat > "$work/lightpanda.sources" <<EOF
Types: deb
URIs: ${APT_PUBLIC_URL%/}
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/lightpanda.asc
EOF

repository_url="s3://$BUCKET"
aws s3 cp "$work/lightpanda.asc" "$repository_url/lightpanda.asc" \
  --cache-control 'no-cache' --only-show-errors
aws s3 cp "$work/lightpanda.sources" "$repository_url/lightpanda.sources" \
  --cache-control 'no-cache' --only-show-errors
