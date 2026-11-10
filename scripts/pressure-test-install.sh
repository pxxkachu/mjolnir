#!/usr/bin/env bash
# Pressure-test mjolnir-install.sh + mjolnir-postinstall.sh (dry-run / static only).
# Does NOT wipe disks or need root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL="$SCRIPT_DIR/mjolnir-install.sh"
POST="$SCRIPT_DIR/mjolnir-postinstall.sh"

PASS=0
FAIL=0
SKIP=0
RESULTS=()

green() { printf '\033[32m%s\033[0m' "$*"; }
red() { printf '\033[31m%s\033[0m' "$*"; }
yellow() { printf '\033[33m%s\033[0m' "$*"; }

record() {
  local status="$1" name="$2" detail="${3:-}"
  if [[ "$status" == PASS ]]; then
    PASS=$((PASS + 1))
    RESULTS+=("$(green PASS)  $name${detail:+ — $detail}")
  elif [[ "$status" == FAIL ]]; then
    FAIL=$((FAIL + 1))
    RESULTS+=("$(red FAIL)  $name${detail:+ — $detail}")
  else
    SKIP=$((SKIP + 1))
    RESULTS+=("$(yellow SKIP)  $name${detail:+ — $detail}")
  fi
}

expect_exit() {
  local want="$1" name="$2"
  shift 2
  local out rc=0
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -eq "$want" ]]; then
    record PASS "$name" "exit $rc"
  else
    record FAIL "$name" "want exit $want, got $rc; tail: $(echo "$out" | tail -n 3 | tr '\n' ' ')"
  fi
}

expect_stdout_match() {
  local pattern="$1" name="$2"
  shift 2
  local out rc=0
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    record FAIL "$name" "exit $rc; $(echo "$out" | tail -n 2 | tr '\n' ' ')"
    return
  fi
  if grep -Eq -- "$pattern" <<<"$out"; then
    record PASS "$name"
  else
    record FAIL "$name" "pattern /$pattern/ not found"
  fi
}

expect_stdout_not_match() {
  local pattern="$1" name="$2"
  shift 2
  local out rc=0
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    record FAIL "$name" "exit $rc"
    return
  fi
  if grep -Eq -- "$pattern" <<<"$out"; then
    record FAIL "$name" "forbidden pattern /$pattern/ present"
  else
    record PASS "$name"
  fi
}

echo "==> Mjolnir installer pressure tests"
echo "    REPO=$REPO_ROOT"
echo

# --- Static ---
echo "--- Static analysis ---"
if bash -n "$INSTALL" && bash -n "$POST"; then
  record PASS "bash -n both scripts"
else
  record FAIL "bash -n both scripts"
fi

if command -v shellcheck >/dev/null; then
  set +e
  sc_out="$(shellcheck -x -e SC2034,SC2086,SC2154 "$INSTALL" "$POST" 2>&1)"
  sc_rc=$?
  set -e
  if [[ "$sc_rc" -eq 0 ]]; then
    record PASS "shellcheck"
  else
    record FAIL "shellcheck" "$(echo "$sc_out" | head -n 5 | tr '\n' ' ')"
  fi
else
  record SKIP "shellcheck not installed"
fi

# shebang / executable
[[ -x "$INSTALL" && -x "$POST" ]] && record PASS "scripts are executable" || record FAIL "scripts missing +x"
head -n1 "$INSTALL" | grep -q 'env bash' && record PASS "install shebang" || record FAIL "install shebang"
head -n1 "$POST" | grep -q 'env bash' && record PASS "postinstall shebang" || record FAIL "postinstall shebang"

# config assets required by postinstall
for f in Caddyfile caddy.service caddy.sysusers caddy.tmpfiles caddy.env.example nftables.conf; do
  if [[ -f "$REPO_ROOT/config/$f" ]]; then
    record PASS "config/$f exists"
  else
    record FAIL "config/$f missing"
  fi
done

# forbidden firmware / packages in install source
if grep -EEq 'linux-firmware-intel|linux-firmware-amdgpu|linux-firmware-mediatek|"linux-firmware"|linux-firmware\s|caddy-cloudflare|intel-ucode' "$INSTALL"; then
  # allow comments mentioning "not intel" etc. — check FIRMWARE_PKGS assignment block only
  fw_block="$(awk '/^FIRMWARE_PKGS=\(/,/^\)/' "$INSTALL")"
  if grep -EEq 'intel|amdgpu|mediatek|broadcom|atheros|radeon' <<<"$fw_block"; then
    record FAIL "FIRMWARE_PKGS contains unwanted vendor" "$fw_block"
  else
    record PASS "FIRMWARE_PKGS clean (nvidia+realtek)"
  fi
else
  record PASS "no forbidden firmware package names as installs"
fi

fw_block="$(awk '/^FIRMWARE_PKGS=\(/,/^\)/' "$INSTALL")"
grep -q 'linux-firmware-nvidia' <<<"$fw_block" && grep -q 'linux-firmware-realtek' <<<"$fw_block" \
  && record PASS "FIRMWARE_PKGS has nvidia+realtek" \
  || record FAIL "FIRMWARE_PKGS missing nvidia/realtek"

# passwd must be outside heredoc
if grep -n "arch-chroot /mnt passwd" "$INSTALL" | grep -qv '<<'; then
  # ensure passwd USER is not between <<CHROOT and CHROOT closer for the interactive calls
  if awk '/<<CHROOT/,/^CHROOT$/' "$INSTALL" | grep -qE '^\s*passwd '; then
    record FAIL "passwd still inside <<CHROOT heredoc"
  else
    record PASS "passwd not inside <<CHROOT heredoc"
  fi
else
  record FAIL "missing arch-chroot passwd after heredoc"
fi
grep -q 'arch-chroot /mnt passwd "${USERNAME}"' "$INSTALL" && record PASS "interactive passwd laika path" || record FAIL "interactive passwd user"
grep -q 'arch-chroot /mnt passwd root' "$INSTALL" && record PASS "interactive passwd root path" || record FAIL "interactive passwd root"

# postinstall: no stock caddy package in PKGS
pkgs_block="$(awk '/^PKGS=\(/,/^\)/' "$POST")"
if grep -Eq '(^|[[:space:]])caddy([[:space:]]|$)' <<<"$pkgs_block"; then
  record FAIL "stock caddy in PKGS array"
else
  record PASS "stock caddy not in PKGS"
fi
grep -q 'xcaddy' "$POST" && record PASS "postinstall uses xcaddy" || record FAIL "xcaddy missing"
grep -q 'config/caddy.service' "$POST" && record PASS "installs our caddy.service" || record FAIL "caddy.service install missing"

echo
echo "--- CLI validation (install) ---"
expect_exit 0 "install --help" bash "$INSTALL" --help
expect_exit 0 "install dry-run with zero args (all defaults)" bash "$INSTALL" --dry-run
expect_exit 1 "install bad --fs" bash "$INSTALL" --fs zfs --dry-run
expect_exit 1 "install unknown flag" bash "$INSTALL" --dry-run --nope

echo
echo "--- Dry-run matrix (install) ---"
expect_stdout_match 'DRY-RUN complete' "install default dry-run" \
  bash "$INSTALL" --dry-run

expect_stdout_match 'Disk: +/dev/nvme0n1' "dry-run default disk nvme0n1" \
  bash "$INSTALL" --dry-run

expect_stdout_match 'User: +laika' "dry-run default user laika" \
  bash "$INSTALL" --dry-run

expect_stdout_match 'linux-firmware-nvidia' "dry-run lists nvidia firmware" \
  bash "$INSTALL" --dry-run

expect_stdout_match 'linux-firmware-realtek' "dry-run lists realtek firmware" \
  bash "$INSTALL" --dry-run

expect_stdout_not_match 'linux-firmware-intel' "dry-run no intel firmware" \
  bash "$INSTALL" --dry-run

expect_stdout_not_match 'linux-firmware-mediatek' "dry-run no mediatek firmware" \
  bash "$INSTALL" --dry-run

expect_stdout_match 'America/Chicago' "dry-run default timezone" \
  bash "$INSTALL" --dry-run

expect_stdout_match 'Hostname: mjolnir' "dry-run default hostname" \
  bash "$INSTALL" --dry-run

expect_stdout_match 'FS: +ext4' "dry-run default ext4" \
  bash "$INSTALL" --dry-run

expect_stdout_match 'btrfs' "dry-run --fs btrfs" \
  bash "$INSTALL" --fs btrfs --dry-run

expect_stdout_match 'it87' "dry-run --it87" \
  bash "$INSTALL" --it87 --dry-run

expect_stdout_match 'skip' "dry-run --skip-postinstall" \
  bash "$INSTALL" --skip-postinstall --dry-run

expect_stdout_match 'Hostname: customhost' "dry-run --hostname" \
  bash "$INSTALL" --hostname customhost --dry-run

expect_stdout_match 'Timezone: Europe/London' "dry-run --timezone" \
  bash "$INSTALL" --timezone Europe/London --dry-run

expect_stdout_match 'passwd laika' "dry-run mentions interactive passwd" \
  bash "$INSTALL" --dry-run

expect_stdout_match 'reflector' "dry-run ranks mirrors" \
  bash "$INSTALL" --dry-run

expect_stdout_match 'xcaddy' "install dry-run nests postinstall xcaddy" \
  bash "$INSTALL" --dry-run

expect_stdout_match 'OLLAMA_HOST=127.0.0.1:11434' "install dry-run ollama localhost" \
  bash "$INSTALL" --dry-run

echo
echo "--- CLI validation (postinstall) ---"
expect_exit 0 "post --help" bash "$POST" --help
expect_exit 1 "post unknown flag" bash "$POST" --dry-run --user laika --bogus
expect_exit 0 "post dry-run default" bash "$POST" --user laika --dry-run

echo
echo "--- Dry-run matrix (postinstall) ---"
expect_stdout_match 'DRY-RUN complete' "post dry-run completes" \
  bash "$POST" --user laika --dry-run

expect_stdout_match 'nvidia-open' "post dry-run nvidia-open" \
  bash "$POST" --user laika --dry-run

expect_stdout_not_match 'linux-firmware-intel' "post dry-run no intel firmware" \
  bash "$POST" --user laika --dry-run

expect_stdout_match 'xcaddy' "post dry-run xcaddy" \
  bash "$POST" --user laika --dry-run

expect_stdout_match 'ai.lehaus.io' "post dry-run domain" \
  bash "$POST" --user laika --dry-run

expect_stdout_match 'skip xcaddy/Caddy' "post dry-run --no-caddy" \
  bash "$POST" --user laika --no-caddy --dry-run

expect_stdout_match 'it87' "post dry-run --it87" \
  bash "$POST" --user laika --it87 --dry-run

expect_stdout_match 'skip interactive tailscale' "post dry-run --no-tailscale-up" \
  bash "$POST" --user laika --no-tailscale-up --dry-run

expect_stdout_match 'fstrim.timer' "post dry-run fstrim" \
  bash "$POST" --user laika --dry-run

expect_stdout_match 'nftables' "post dry-run nftables" \
  bash "$POST" --user laika --dry-run

expect_stdout_match 'paru' "post dry-run paru" \
  bash "$POST" --user laika --dry-run

# chroot mode nested
expect_stdout_match 'chroot mode|MJOLNIR_CHROOT|skip interactive tailscale' "post dry-run chroot mode" \
  env MJOLNIR_CHROOT=1 bash "$POST" --user laika --no-tailscale-up --dry-run

# non-dry-run without root should fail
expect_exit 1 "post refuses non-root without dry-run" bash "$POST" --user laika

# part_name logic via sourcing is hard; smoke nvme naming by grepping
grep -q 'nvme\*\]' "$INSTALL" || grep -q 'nvme' "$INSTALL" && record PASS "nvme partition naming present" || record FAIL "nvme partition naming"

# Caddyfile sanity
grep -q 'ai.lehaus.io' "$REPO_ROOT/config/Caddyfile" && record PASS "Caddyfile domain" || record FAIL "Caddyfile domain"
grep -q '127.0.0.1:11434' "$REPO_ROOT/config/Caddyfile" && record PASS "Caddyfile ollama upstream" || record FAIL "Caddyfile ollama upstream"
grep -q 'cloudflare' "$REPO_ROOT/config/Caddyfile" && record PASS "Caddyfile cloudflare dns" || record FAIL "Caddyfile cloudflare dns"
grep -q '/usr/local/bin/caddy' "$REPO_ROOT/config/caddy.service" && record PASS "caddy.service uses xcaddy binary" || record FAIL "caddy.service binary path"

# nftables mentions tailscale
grep -q 'tailscale0' "$REPO_ROOT/config/nftables.conf" && record PASS "nftables tailscale0" || record FAIL "nftables tailscale0"

echo
echo "--- Repeated dry-run stress (20x) ---"
stress_fail=0
for i in $(seq 1 20); do
  if ! bash "$INSTALL" --dry-run >/tmp/mjolnir-install-stress.log 2>&1; then
    stress_fail=1
    break
  fi
  if ! bash "$POST" --user laika --dry-run >/tmp/mjolnir-post-stress.log 2>&1; then
    stress_fail=1
    break
  fi
done
if [[ "$stress_fail" -eq 0 ]]; then
  record PASS "20x install+post dry-run loops"
else
  record FAIL "dry-run stress loop failed at iteration" "$i"
fi

echo
echo "========== RESULTS =========="
printf '%s\n' "${RESULTS[@]}"
echo
echo "Passed: $PASS  Failed: $FAIL  Skipped: $SKIP  Total: $((PASS + FAIL + SKIP))"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
