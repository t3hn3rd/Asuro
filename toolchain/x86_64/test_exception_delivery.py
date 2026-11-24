"""Check early x86_64 exception delivery using QEMU TCG and a normal boot ISO."""
import argparse
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import time


def wait_for(check, description, vm):
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        if check():
            return
        if vm.poll() is not None:
            raise RuntimeError(f"QEMU exited waiting for {description}")
        time.sleep(0.025)
    raise TimeoutError(description)


def run_case(iso, case):
    with tempfile.TemporaryDirectory() as directory:
        log = Path(directory, "serial")
        monitor = Path(directory, "monitor")
        cpu = "qemu32" if case == "unsupported" else "max"
        command = ["qemu-system-x86_64", "-accel", "tcg", "-cpu", cpu, "-m", "256",
                   "-cdrom", str(iso), "-boot", "d", "-display", "none", "-no-reboot",
                   "-serial", f"file:{log}", "-qmp", f"unix:{monitor},server=on,wait=off"]
        def output():
            return log.read_text(errors="replace") if log.exists() else ""
        vm = subprocess.Popen(command)
        try:
            if case == "unsupported":
                wait_for(lambda: output() == "C", "32-bit CPU rejection marker", vm)
                return
            wait_for(lambda: "PASS: bootstrap and IST stack guard pages fault" in output(),
                     "native IDT and stack guards", vm)
            with socket.socket(socket.AF_UNIX) as client:
                client.settimeout(5)
                client.connect(str(monitor))
                with client.makefile("rwb") as stream:
                    def request(name, **args):
                        data = json.dumps({"execute": name, "arguments": args})
                        stream.write(data.encode() + b"\n")
                        stream.flush()
                        while True:
                            reply = json.loads(stream.readline())
                            if "error" in reply:
                                raise RuntimeError(reply["error"])
                            if "return" in reply:
                                return reply["return"]
                    json.loads(stream.readline())
                    request("qmp_capabilities")
                    if case == "nmi":
                        request("inject-nmi")
                        marker = "STACK=NMI IST2"
                    else:
                        message = request("human-monitor-command", **{
                            "command-line": "mce 0 0 0xb200000000000001 5 0 0"})
                        if message.strip():
                            raise RuntimeError(message)
                        marker = "STACK=machine-check IST3"
            wait_for(lambda: marker in output() and "HALTED: exception diagnostics complete" in output(),
                     marker, vm)
        except Exception:
            print(output()[-1600:])
            raise
        finally:
            if vm.poll() is None:
                vm.terminate()
            vm.wait(timeout=10)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("iso", type=Path)
    args = parser.parse_args()
    for case in ("unsupported", "nmi", "mce"):
        run_case(args.iso.resolve(strict=True), case)
        print(f"PASS: {case}", flush=True)
