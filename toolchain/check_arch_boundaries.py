#!/usr/bin/env python3
# Copyright 2026 Aaron Hance
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""Prevent shared Pascal units from selecting architecture implementations."""
from pathlib import Path
import re
import sys

cpu_directive = re.compile(r"\{\$\s*if(?:def|ndef)?\b[^}]*\bCPU\w*", re.I)
arch_import = re.compile(r"\barch\.(?:x86|x86_64)\.", re.I)
errors = []
for path in sorted(Path("src").rglob("*")):
    if path.suffix not in (".pas", ".inc"):
        continue
    if path.parts[1] == "arch" and path.parts[2] != "common":
        continue
    source = path.read_text(encoding="utf-8")
    # Ignore prose comments but retain compiler directives.
    source = re.sub(r"\{(?!\$).*?\}|\(\*.*?\*\)|//[^\n]*", "", source, flags=re.S)
    if cpu_directive.search(source):
        errors.append(f"{path}: CPU conditional belongs in build selection")
    # Existing i386-only services outside the port still import their drivers.
    # The migrated units must depend on stable platform names instead.
    migrated = path.as_posix() in {
        "src/core/core.util.pas", "src/core/strings/core.strings.pas",
        "src/io/io.stdio.pas", "src/proc/proc.mgr.pas",
        "src/memory/memory.heap.pas", "src/memory/memory.raw.pas",
    } or path.parts[1:3] == ("arch", "common")
    if migrated and arch_import.search(source):
        errors.append(f"{path}: shared unit imports an architecture implementation")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print("Shared architecture boundaries verified.")
