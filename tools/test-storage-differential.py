"""Run the native FAT32 differential on disposable VirtualBox disks (Windows + WSL)."""
import argparse
from contextlib import contextmanager
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
PARTITION = 2048 * 512
SECTORS = 131072
SEED = 0x5317
LENGTH = 4095 + 4096 + 4097 + 131073


def command(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True,
                          text=True, errors="replace").stdout.strip()


def linux(path):
    return command("wsl", "-d", "Ubuntu", "--", "wslpath", "-a", path.as_posix())


def wsl(*args):
    return command("wsl", "-d", "Ubuntu", "-u", "root", "--", *args)


def expected(worker, size):
    return bytes((p * 37 + (p >> 8) * 19 + (p >> 16) * 23 + worker * 71 + SEED) & 255
                 for p in range(size))


def fixture(folder, high, serial):
    part = folder / "fat.raw"
    with part.open("wb") as f:
        f.truncate(SECTORS * 512)
    wsl("mkfs.fat", "-F", "32", "-s", "1", "-n", "ASURODIFF", "-h", "2048", linux(part))
    raw = folder / "disk.raw"
    mbr = bytearray(512)
    mbr[:10] = b"ASRODIF1" + bytes([high, serial])
    struct.pack_into("<B3xB3xII", mbr, 446, 0, 0x0c, 2048, SECTORS)
    mbr[510:] = b"\x55\xaa"
    with raw.open("wb") as dst, part.open("rb") as src:
        dst.write(mbr)
        dst.write(expected(0, 512))
        dst.seek(PARTITION)
        shutil.copyfileobj(src, dst)
    return raw


def verify_disk(folder, vdi):
    raw = folder / "result.raw"
    command("VBoxManage", "clonemedium", "disk", vdi, raw, "--format", "RAW")
    command("VBoxManage", "closemedium", "disk", raw)
    mount = wsl("mktemp", "-d")
    try:
        wsl("mount", "-t", "vfat", "-o", f"ro,loop,offset={PARTITION}", linux(raw), mount)
        try:
            errors = []
            for worker, name in enumerate(("WORKA.BIN", "WORKB.BIN")):
                copy = folder / name
                try:
                    wsl("cp", mount + "/" + name, linux(copy))
                except subprocess.CalledProcessError as exc:
                    errors.append(f"{name}: {exc.stderr.strip()}")
                    continue
                data = copy.read_bytes()
                oracle = expected(worker, LENGTH)
                if data != oracle:
                    offset = next((i for i, (a, b) in enumerate(zip(data, oracle)) if a != b),
                                  min(len(data), len(oracle)))
                    errors.append(f"{name}: first difference at {offset}, size {len(data)}")
                else:
                    print(name, len(data), "bytes verified offline", flush=True)
            if errors:
                raise RuntimeError(", ".join(errors))
        finally:
            wsl("umount", mount)
    finally:
        wsl("rmdir", mount)


@contextmanager
def scratch_folder():
    temp = tempfile.TemporaryDirectory(prefix="asuro-storage-")
    try:
        yield Path(temp.name)
    finally:
        # VBoxHeadless can hold VBoxHardening.log briefly after unregistervm.
        for attempt in range(20):
            try:
                temp.cleanup()
                break
            except PermissionError:
                if attempt == 19:
                    raise
                time.sleep(0.5)


def case(iso, results, controller, high, serial):
    tag = f"{controller}-{'high' if high else 'low'}"
    log = results / (tag + ".log")
    with scratch_folder() as folder:
        machine = "asuro-diff-" + uuid.uuid4().hex
        vdi = folder / "fixture.vdi"
        raw = fixture(folder, high, serial)
        command("VBoxManage", "createvm", "--name", machine, "--ostype", "Linux_64",
                "--basefolder", folder, "--register")
        started = False
        try:
            def vb(action, *args):
                return command("VBoxManage", action, machine, *args)
            vb("modifyvm", "--memory", "6144", "--cpus", "1", "--ioapic", "on",
               "--graphicscontroller", "vmsvga", "--vram", "64", "--nic1", "none",
               "--paravirtprovider", "hyperv", "--boot1", "dvd", "--uart1", "0x3F8", "4",
               "--uartmode1", "file", log)
            vb("storagectl", "--name", "SATA", "--add", "sata", "--controller", "IntelAhci")
            vb("storageattach", "--storagectl", "SATA", "--port", "1", "--device", "0",
               "--type", "dvddrive", "--medium", iso)
            bus = "SATA"
            if controller == "ohci":
                vb("modifyvm", "--usb-ohci", "on")
                vb("storagectl", "--name", "USB", "--add", "usb")
                bus = "USB"
            command("VBoxManage", "convertfromraw", raw, vdi, "--format", "VDI")
            vb("storageattach", "--storagectl", bus, "--port", "0", "--device", "0",
               "--type", "hdd", "--medium", vdi)
            vb("startvm", "--type", "headless")
            started = True
            deadline = time.monotonic() + 150
            while time.monotonic() < deadline:
                trace = log.read_text(errors="replace") if log.exists() else ""
                if any(t in trace for t in ("DIFF_PASS", "DIFF_FAIL", "DIFF_TIMEOUT", "desktop ready")):
                    break
                time.sleep(1)
            vb("controlvm", "poweroff")
            started = False
            # Read files even after a guest failure to distinguish persisted
            # corruption from a transient read or descriptor problem.
            verify_disk(folder, vdi)
            if "DIFF_PASS" not in trace or f"DIFF_HIGH={int(high):016X}" not in trace:
                raise RuntimeError("missing guest pass or wrong placement")
            expected_controller = 2 if controller == "ohci" else 3
            if (f"DIFF_SERIAL={int(serial):016X}" not in trace or
                    f"DIFF_CONTROLLER={expected_controller:016X}" not in trace):
                raise RuntimeError("wrong scheduling mode or controller")
            if controller == "ohci" and "DIFF_OHCI_LOW_STAGE_BYTES=0000000000000200" not in trace:
                raise RuntimeError("missing OHCI low staging evidence")
        finally:
            if started:
                vb("controlvm", "poweroff")
            vb("unregistervm", "--delete")
    print(tag, "PASS (guest and offline file verification)", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iso", type=Path, default=ROOT / "build/x86_64/test-complex/Asuro.iso")
    parser.add_argument("--controller", choices=("ahci", "ohci", "both"), default="both")
    parser.add_argument("--serial", action="store_true", help="run one file worker at a time")
    args = parser.parse_args()
    results = Path(tempfile.mkdtemp(prefix="storage-diff-", dir=args.iso.resolve().parent))
    print("Serial logs:", results, flush=True)
    failures = []
    for ctl in ("ahci", "ohci") if args.controller == "both" else (args.controller,):
        for high in (False, True):
            try:
                case(args.iso.resolve(), results, ctl, high, args.serial)
            except (OSError, subprocess.CalledProcessError, RuntimeError) as exc:
                print(ctl, "high" if high else "low", "FAIL", exc, getattr(exc, "stderr", ""), flush=True)
                failures.append((ctl, high))
                (results / f"{ctl}-{'high' if high else 'low'}.result").write_text(
                    f"FAIL {exc} {getattr(exc, 'stderr', '')}")
            else:
                (results / f"{ctl}-{'high' if high else 'low'}.result").write_text("PASS")

    raise SystemExit(int(bool(failures)))
