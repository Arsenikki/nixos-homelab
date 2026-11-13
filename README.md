# nixos-homelab

NixOS hosts for the kuberseni homelab. The cluster itself lives in
[kuberseni-gitops](https://github.com/Arsenikki/kuberseni-gitops). This repo
holds the machines outside the cluster.

| Host | Hardware | Role |
|---|---|---|
| `bedroom-pi` | Raspberry Pi 4, SD card | General-purpose; Music Assistant "Bedroom" player (Sendspin, 3.5 mm jack) |

## How changes reach a host

Each host runs [comin](https://github.com/nlewo/comin), which polls this repo:

- **`main`:** comin builds and runs `switch`, which makes the change permanent.
- **`testing-<hostname>`** (e.g. `testing-bedroom-pi`, rebased on `main`): comin runs `test`, which applies the change but leaves the bootloader alone. A power cycle reverts it.

### Signed commits only

comin deploys a commit only if the tip of the branch is signed by a trusted key. The trusted keys are in `keys/`:

- **`allowed_signers`:** your SSH keys (github.com/Arsenikki.keys).
- **`agent.asc`:** the paseo agent's GPG key. Its private half is in `/data/paseo/gnupg` on paseo-generic.

Merges made in the GitHub UI are signed by GitHub, so comin **skips** them. It then waits until a trusted signed commit lands on top. A leaked GitHub token is therefore not enough to get root on a host.

To merge a PR, the PR's head must be signed by a trusted key. Then fast-forward `main` to it:

```sh
git fetch origin && git push origin origin/<pr-branch>:main   # GitHub marks the PR merged
```

For a PR whose tip isn't signed by a trusted key (bots, the web editor), add a signed commit on top, or make a signed merge commit:

```sh
git switch main && git pull --ff-only
git merge --no-ff -S origin/<pr-branch>
git push
```

To set up SSH signing with 1Password: Settings → Developer → *Configure Commit Signing*, or set `gpg.format=ssh`, `user.signingkey=<pubkey>` and `commit.gpgsign=true`.

**Workflow:**
1. Push a signed commit to `testing-<hostname>` and check the host over SSH.
2. Open a PR and wait for CI.
3. Fast-forward `main` as shown above. comin then switches.

CI (`build.yml`) builds the system closure on a native arm64 runner for every PR and push. Run the workflow manually to also build the SD image, which is uploaded as an artifact.

`update-flake-lock.yml` opens a weekly `flake.lock` PR. Its commits are unsigned and bot PRs don't trigger CI, so push a signed commit or merge commit on top: that triggers CI and makes the PR deployable.

### Break-glass (a change that might cut network access)

```sh
ssh root@bedroom-pi.local systemd-run --on-active=10m --unit=deadman systemctl reboot
ssh root@bedroom-pi.local systemd-run --collect nixos-rebuild test --flake 'github:Arsenikki/nixos-homelab/<rev>#bedroom-pi'
# works -> ssh root@bedroom-pi.local systemctl stop deadman.timer
```

Rollback: `nixos-rebuild switch --rollback`. Or put the card in another machine and edit `DEFAULT` in `/boot/extlinux/extlinux.conf` on the root partition.

## Secrets

Secrets use [sops-nix](https://github.com/Mic92/sops-nix) with age. See `.sops.yaml` for the recipients:

- **admin:** this repo's own age key, in 1Password as `nixos-homelab-sops-age-key`. It is deliberately separate from the kuberseni-gitops key.
- **bedroom-pi:** the Pi's own key. Its private half is in `hosts/bedroom-pi/age-key.sops.json`, encrypted to admin only.

The repo is public, and CI artifacts are public too. Never put a secret in the Nix store or the image.

## Installing bedroom-pi

1. **Image:** run *Actions → build → Run workflow* and download the `bedroom-pi-sd-image` artifact (`.img.zst`).
2. **Flash it:** use Raspberry Pi Imager → *Use custom* (it handles `.zst`). Or:
   `zstdcat nixos-image-*.img.zst | sudo dd of=/dev/<sdcard> bs=4M conv=fsync status=progress`
3. **Give the Pi its age key** (needed for Wi-Fi). Re-insert the card; the FAT partition `FIRMWARE` mounts on macOS and Windows. Then:
   ```sh
   SOPS_AGE_KEY="$(op document get nixos-homelab-sops-age-key --vault homelab --account 2OIQNURH5BCJPDLXSFDQY3ZNFI)" \
     sops -d --output-type binary hosts/bedroom-pi/age-key.sops.json > /Volumes/FIRMWARE/sops-age-key.txt
   ```
   On first boot, `import-sops-age-key.service` moves the key to `/var/lib/sops-nix/key.txt` and deletes it from the card.
4. **Boot it:** plug in Ethernet if you can, plus a powered speaker in the 3.5 mm jack, then power on. After about 2 minutes: `ssh root@bedroom-pi.local`.
5. **Check it:**
   - `systemctl --failed`
   - `aplay -l` should list `Headphones`
   - `journalctl -u sendspin -f`
   - Play something to *Bedroom* from Music Assistant (needs 2.10.8 or later).

### Enabling Wi-Fi

Create `hosts/bedroom-pi/secrets.yaml` with `sops hosts/bedroom-pi/secrets.yaml`:

```yaml
wifi_ssid: <network name>
wifi_psk: <passphrase>
```

The SSID is kept secret too, because a public SSID can be geolocated. sops-nix renders the whole `network={}` block at runtime under `/run/secrets`. Wi-Fi turns on once `secrets.yaml` exists, and Ethernet DHCP stays configured as the fallback.

The passphrase must not contain a double quote (`"`).
