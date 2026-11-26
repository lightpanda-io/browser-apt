# Lightpanda APT repository

Publishes signed Debian packages for the [Lightpanda browser](https://github.com/lightpanda-io/browser) at [apt.lightpanda.io](https://apt.lightpanda.io).

## Installation

Prerequisites:

- A supported Debian or Ubuntu system.
- Root access (run the commands below as root).
- `ca-certificates` and either `curl` or `wget` installed.

Using `curl`:

```bash
install -m 0755 -d /etc/apt/keyrings

curl -fsSL -o /etc/apt/keyrings/lightpanda.asc \
  https://apt.lightpanda.io/lightpanda.asc
curl -fsSL -o /etc/apt/sources.list.d/lightpanda.sources \
  https://apt.lightpanda.io/lightpanda.sources
chmod 0644 /etc/apt/keyrings/lightpanda.asc /etc/apt/sources.list.d/lightpanda.sources

apt-get update && apt-get install -y lightpanda
```

To use `wget`, replace the two `curl` commands above with:

```bash
wget -qO /etc/apt/keyrings/lightpanda.asc \
  https://apt.lightpanda.io/lightpanda.asc
wget -qO /etc/apt/sources.list.d/lightpanda.sources \
  https://apt.lightpanda.io/lightpanda.sources
```

Updates are available through normal APT upgrades.

## Install a specific version

After configuring the repository, list available versions:

```bash
apt-get update
apt-cache madison lightpanda
```

Install the desired version, for example:

```bash
apt-get install -y lightpanda=1.0.5
```

If a newer version is already installed, add `--allow-downgrades`.

## License

[Apache-2.0](LICENSE)
