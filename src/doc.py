import re
import os
import argparse
from pathlib import Path

# =============================================================================
# PHASE 1: Collect All Type Names from Top-Level "type" Blocks
# =============================================================================

TYPE_BLOCK_START = re.compile(r'^\s*type\b', re.IGNORECASE)
BLOCK_STOP = re.compile(r'^\s*(type|function|procedure|constructor|destructor|interface|implementation|var|const|unit\b|end\.)', re.IGNORECASE)
END_OF_DECL = re.compile(r';\s*$')

POINTER_ALIAS = re.compile(r'^\s*(P\w+)\s*=\s*\^(\w+)\s*;?', re.IGNORECASE)
SINGLE_TYPE_DECL = re.compile(r'^\s*(\w+)\s*=\s*(.+)$', re.IGNORECASE | re.DOTALL)

def collect_type_names_in_file(filepath: Path):
    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        raw_lines = [l.rstrip('\r\n') for l in f]
    i, n = 0, len(raw_lines)
    types_found = set()
    while i < n:
        line = raw_lines[i]
        if TYPE_BLOCK_START.match(line):
            i += 1
            block_lines = []
            while i < n and not BLOCK_STOP.match(raw_lines[i]):
                block_lines.append(raw_lines[i])
                i += 1
            types_found.update(parse_type_block(block_lines))
        else:
            i += 1
    return types_found

def parse_type_block(lines):
    block_text = " ".join(lines)
    parts = block_text.split(';')
    names = set()
    for part in parts:
        part = part.strip()
        if not part:
            continue
        m_ptr = POINTER_ALIAS.match(part + ';')
        if m_ptr:
            pointer_name, base_name = m_ptr.groups()
            names.add(pointer_name)
            names.add(base_name)
        else:
            m = SINGLE_TYPE_DECL.match(part)
            if m:
                tname = m.group(1)
                names.add(tname)
    return names

def build_global_index(all_files_types: dict):
    global_index = {}
    for fname, typeset in all_files_types.items():
        for t in typeset:
            key = t.lower()
            if key not in global_index:
                global_index[key] = (fname, t)
    return global_index

# =============================================================================
# PHASE 2: Extract Declarations with Doc Comments
# =============================================================================

JUNK_REGEX = re.compile(r'^\s*(unit|uses|interface|implementation|var|const)\b', re.IGNORECASE)
FUNC_REGEX = re.compile(r'^\s*(function|procedure|constructor|destructor)\s+(\w+)', re.IGNORECASE)
TYPE_DECL_REGEX = re.compile(r'^\s*(\w+)\s*=\s*', re.IGNORECASE)

def extract_declarations_with_docs(filepath: Path):
    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        lines = [l.rstrip('\r\n') for l in f]
    results = []
    doc_buffer = []
    blank_count = 0
    i, n = 0, len(lines)
    while i < n:
        line = lines[i]
        stripped = line.strip()
        if stripped.startswith('//') or stripped.startswith('///') or stripped.startswith('{') or stripped.startswith('(*'):
            doc_buffer.append(line)
            i += 1
            continue
        if stripped == '':
            if doc_buffer:
                blank_count += 1
            if blank_count > 1:
                doc_buffer = []
                blank_count = 0
            i += 1
            continue
        if JUNK_REGEX.match(stripped):
            doc_buffer = []
            blank_count = 0
            i += 1
            continue
        m_func = FUNC_REGEX.match(stripped)
        if m_func:
            name = m_func.group(2)
            results.append({
                "name": name,
                "kind": "func",
                "declaration": stripped,
                "doc_lines": doc_buffer[:],
            })
            doc_buffer = []
            blank_count = 0
            i += 1
            continue
        m_type = TYPE_DECL_REGEX.match(stripped)
        if m_type:
            name = m_type.group(1)
            decl_lines = [stripped]
            while i < n - 1 and not stripped.endswith(';'):
                i += 1
                stripped = lines[i].strip()
                decl_lines.append(stripped)
            full_decl = " ".join(decl_lines)
            results.append({
                "name": name,
                "kind": "type",
                "declaration": full_decl,
                "doc_lines": doc_buffer[:],
            })
            doc_buffer = []
            blank_count = 0
            i += 1
            continue
        if doc_buffer:
            doc_buffer = []
            blank_count = 0
        i += 1
    return results

# =============================================================================
# PHASE 3: Parse Doc Comments and Extract Type Members
# =============================================================================

DOC_TAG_REGEX = re.compile(r'^\s*@(\w+)(?:\(([^)]+)\))?\s*(.*)$')

def unify_doc_text(doc_lines):
    cleaned = []
    for line in doc_lines:
        ln = line.strip()
        if ln.startswith('///'):
            ln = ln.split('///',1)[-1]
        elif ln.startswith('//'):
            ln = ln.split('//',1)[-1]
        ln = re.sub(r'^\s*\{+|\}+\s*$', '', ln)
        ln = re.sub(r'^\s*\(\*+|\*+\)\s*$', '', ln)
        cleaned.append(ln.strip())
    final = []
    blank = 0
    for c in cleaned:
        if not c:
            blank += 1
            if blank == 1:
                final.append("")
        else:
            blank = 0
            final.append(c)
    return "\n".join(final).strip()

def parse_doc_lines_tags(doc_lines):
    text = unify_doc_text(doc_lines)
    lines = text.splitlines()
    doc_struct = {
        "abstract": "",
        "params": {},
        "returns": "",
        "author": [],
        "note": [],
        "warning": [],
        "main": "",
    }
    main_buffer = []
    current_tag = None
    for line in lines:
        m = DOC_TAG_REGEX.match(line)
        if m:
            tag = m.group(1).lower()
            arg = m.group(2) or ""
            content = m.group(3).strip()
            if tag == "abstract":
                doc_struct["abstract"] += content + " "
                current_tag = None
            elif tag == "param":
                if arg:
                    existing = doc_struct["params"].get(arg, "")
                    doc_struct["params"][arg] = existing + content + " "
                else:
                    main_buffer.append(line)
                current_tag = None
            elif tag == "returns":
                doc_struct["returns"] += content + " "
                current_tag = None
            elif tag == "author":
                doc_struct["author"].append(content)
                current_tag = None
            elif tag == "note":
                doc_struct["note"].append(content)
                current_tag = "note"
            elif tag == "warning":
                doc_struct["warning"].append(content)
                current_tag = "warning"
            else:
                main_buffer.append(line)
                current_tag = None
        else:
            if current_tag in ("note", "warning"):
                if current_tag == "note" and doc_struct["note"]:
                    doc_struct["note"][-1] += " " + line
                elif current_tag == "warning" and doc_struct["warning"]:
                    doc_struct["warning"][-1] += " " + line
            else:
                main_buffer.append(line)
    doc_struct["abstract"] = doc_struct["abstract"].strip()
    doc_struct["returns"] = doc_struct["returns"].strip()
    for k in doc_struct["params"]:
        doc_struct["params"][k] = doc_struct["params"][k].strip()
    doc_struct["main"] = "\n".join(main_buffer).strip()
    for key in ["abstract", "returns", "main"]:
        doc_struct[key] = parse_inline_markup(doc_struct[key])
    for key in ["note", "warning"]:
        doc_struct[key] = [parse_inline_markup(x) for x in doc_struct[key]]
    doc_struct["author"] = [parse_inline_markup(x) for x in doc_struct["author"]]
    for k in doc_struct["params"]:
        doc_struct["params"][k] = parse_inline_markup(doc_struct["params"][k])
    return doc_struct

def parse_inline_markup(text):
    text = re.sub(r'@true\b', '<code>true</code>', text, flags=re.IGNORECASE)
    text = re.sub(r'@false\b', '<code>false</code>', text, flags=re.IGNORECASE)
    text = re.sub(r'@nil\b', '<code>nil</code>', text, flags=re.IGNORECASE)
    text = re.sub(r'@br\b', '<br>', text, flags=re.IGNORECASE)
    text = re.sub(r'@url\s+(\S+)', r'<a href="\1">\1</a>', text, flags=re.IGNORECASE)
    pattern = re.compile(r'@(\w+)\s+(.*?)@')
    def repl(m):
        tag = m.group(1).lower()
        content = m.group(2)
        if tag == "bold":
            return f"<strong>{content}</strong>"
        elif tag == "italic":
            return f"<em>{content}</em>"
        elif tag == "code":
            return f"<code>{content}</code>"
        elif tag == "link":
            return f"LINK:{content}"
        else:
            return m.group(0)
    text = pattern.sub(repl, text)
    return text

# =============================================================================
# NEW: Parse Type Members and Separate Field & Comment into Two Columns
# =============================================================================

def parse_type_members(declaration: str) -> list:
    """
    Extracts members from a record/class declaration and returns a list of tuples (field, comment).

    Steps:
      1. Locate the substring between the first occurrence of "record" (or "class")
         and the first occurrence of "end;" (or "end").
      2. Split the substring into lines (using newline as delimiter).
         If there are no newlines (i.e. the entire declaration is on one line),
         split on semicolons.
      3. For each line, trim whitespace and remove any trailing semicolon.
      4. For each line, split at the first occurrence of "//". The part before is the field;
         the part after is the comment.
      5. Return a list of (field, comment) tuples.
    """
    members = []
    decl_lower = declaration.lower()
    # Find start (after "record" or "class")
    m = re.search(r'(record|class)', declaration, re.IGNORECASE)
    if not m:
        return members
    start_index = m.end()
    # Find the end of the declaration block – try "end;" first, otherwise "end"
    end_index = declaration.lower().find("end;", start_index)
    if end_index == -1:
        end_index = declaration.lower().find("end", start_index)
        if end_index == -1:
            end_index = len(declaration)
    content = declaration[start_index:end_index]
    # First try splitting by newline
    lines = content.splitlines()
    if len(lines) == 1:
        # If there are no newlines, split by semicolon
        lines = content.split(';')
    for line in lines:
        line = line.strip()
        if not line:
            continue
        if line.endswith(";"):
            line = line[:-1].strip()
        # Split on the first occurrence of "//"
        if "//" in line:
            field, comment = line.split("//", 1)
            members.append((field.strip(), comment.strip()))
        else:
            members.append((line.strip(), ""))
    return members

# =============================================================================
# PHASE 4: Cross-File Linking & Pointer Fallback
# =============================================================================

def build_global_index_from_decls(all_decls_by_file: dict):
    global_index = {}
    for fname, decls in all_decls_by_file.items():
        for d in decls:
            if d["kind"] == "type":
                key = d["name"].lower()
                if key not in global_index:
                    global_index[key] = (fname, d["name"])
    return global_index

def linkify_text(text: str, global_index: dict, current_file: str):
    text = re.sub(r'LINK:(\w+)', lambda m: make_type_link(m.group(1), global_index, current_file), text, flags=re.IGNORECASE)
    def token_replacer(match):
        word = match.group(1)
        start = match.start()
        context = text[max(0, start-15):start]
        if "href=" in context or "LINK:" in context:
            return word
        return link_token(word, global_index, current_file)
    text = re.sub(r'\b(\w+)\b', token_replacer, text)
    return text

def link_token(word: str, global_index: dict, current_file: str):
    tmp = word
    for _ in range(10):
        key = tmp.lower()
        if key in global_index:
            return make_type_link(tmp, global_index, current_file)
        if tmp.startswith('P'):
            tmp = tmp[1:]
        else:
            break
    return word

def make_type_link(tname: str, global_index: dict, current_file: str):
    key = tname.lower()
    if key in global_index:
        fname, anchor = global_index[key]
        if fname == current_file:
            return f'<a href="#{anchor}">{tname}</a>'
        else:
            base = fname.replace('.pas', '')
            return f'<a href="{base}.html#{anchor}">{tname}</a>'
    return tname

# =============================================================================
# PHASE 5: HTML Generation
# =============================================================================

def format_doc_struct_html(doc_struct: dict, global_index: dict, current_file: str):
    parts = []
    if doc_struct["abstract"]:
        txt = linkify_text(doc_struct["abstract"], global_index, current_file)
        parts.append(f'<div class="mb-2"><strong>Abstract:</strong> {txt}</div>')
    for a in doc_struct["author"]:
        txt = linkify_text(a, global_index, current_file)
        parts.append(f'<div class="mb-2"><strong>Author:</strong> {txt}</div>')
    for n in doc_struct["note"]:
        txt = linkify_text(n, global_index, current_file)
        parts.append(f'''<div class="mb-2 bg-blue-50 border-l-4 border-blue-300 pl-2 py-1">
<strong>Note:</strong> {txt}
</div>''')
    for w in doc_struct["warning"]:
        txt = linkify_text(w, global_index, current_file)
        parts.append(f'''<div class="mb-2 bg-red-50 border-l-4 border-red-300 pl-2 py-1">
<strong>Warning:</strong> {txt}
</div>''')
    if doc_struct["params"]:
        param_items = []
        for p, desc in doc_struct["params"].items():
            desc_linked = linkify_text(desc, global_index, current_file)
            param_items.append(f"<li><strong>{p}</strong>: {desc_linked}</li>")
        params_html = "\n".join(param_items)
        parts.append(f'''<div class="mb-2">
<strong>Parameters:</strong>
<ul class="list-disc list-inside ml-5">
{params_html}
</ul>
</div>''')
    if doc_struct["returns"]:
        txt = linkify_text(doc_struct["returns"], global_index, current_file)
        parts.append(f'<div class="mb-2"><strong>Returns:</strong> {txt}</div>')
    if doc_struct.get("members"):
        rows = []
        # Header row for two columns
        rows.append("<tr><th class='border px-2 py-1 bg-gray-200'>Member</th><th class='border px-2 py-1 bg-gray-200'>Comment</th></tr>")
        for field, comment in doc_struct["members"]:
            rows.append(f"<tr><td class='border px-2 py-1'>{field}</td><td class='border px-2 py-1'>{comment}</td></tr>")
        table_html = "<table class='table-auto border-collapse w-full'>" + "".join(rows) + "</table>"
        parts.append(f"<div class='mb-2'><strong>Members:</strong><br>{table_html}</div>")
    if doc_struct["main"]:
        txt = linkify_text(doc_struct["main"], global_index, current_file)
        parts.append(f'<div class="mb-2 whitespace-pre-line">{txt}</div>')
    return "\n".join(parts)

def generate_html_page(filename: str, all_files: list[str],
                       declarations: list[dict], global_index: dict,
                       output_folder: Path):
    sidebar_items = []
    for f in all_files:
        base = f.replace('.pas', '')
        css = "font-bold text-blue-600" if f == filename else "text-blue-600"
        sidebar_items.append(f'<li><a class="{css}" href="{base}.html">{f}</a></li>')
    sidebar_html = "\n".join(sidebar_items)
    toc_items = []
    for d in declarations:
        toc_items.append(f'<li><a class="underline text-blue-600" href="#{d["name"]}">{d["name"]}</a></li>')
    toc_html = "\n".join(toc_items)
    content_blocks = []
    for d in declarations:
        anchor = d["name"]
        decl_line = linkify_text(d["declaration"], global_index, filename)
        if d["kind"] == "type":
            members = parse_type_members(d["declaration"])
            if "doc_struct" not in d or not d["doc_struct"]:
                d["doc_struct"] = {}
            d["doc_struct"]["members"] = members
        doc_html = format_doc_struct_html(d.get("doc_struct", {"abstract": "", "params": {}, "returns": "", "author": [], "note": [], "warning": [], "main": "No doc found."}), global_index, filename)
        block = f"""
<div id="{anchor}" class="doc-item border border-gray-300 bg-white p-4 mb-4 rounded"
     data-entity="{anchor}" data-text="{d.get('doc_struct', {}).get('abstract','')} {d.get('doc_struct', {}).get('main','')}">
  <h2 class="font-bold text-lg mb-2">{anchor}</h2>
  <pre class="bg-gray-100 p-2 text-sm overflow-auto mb-2">{decl_line}</pre>
  {doc_html}
</div>
"""
        content_blocks.append(block)
    html_filename = filename.replace('.pas', '') + '.html'
    outpath = output_folder / html_filename
    page_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>{filename} Documentation</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <style>
  .layout {{
    display: flex;
    flex-direction: row;
    height: 100vh;
    margin: 0;
    padding: 0;
  }}
  .sidebar {{
    flex: 0 0 250px;
    background-color: #f3f4f6;
    border-right: 1px solid #ccc;
    overflow-y: auto;
    padding: 1rem;
  }}
  .content {{
    flex: 1;
    overflow-y: auto;
    padding: 1rem;
  }}
  </style>
</head>
<body class="bg-gray-100 text-gray-900">
<div class="layout">
  <div class="sidebar">
    <h2 class="text-xl font-bold mb-4">All Files</h2>
    <ul class="list-disc list-inside space-y-1">
      {sidebar_html}
    </ul>
  </div>
  <div class="content">
    <h1 class="text-2xl font-bold mb-4">{filename} Documentation</h1>
    <p class="mb-2 text-sm italic">Found {len(declarations)} item(s) in this file.</p>
    <div class="mb-4">
      <input id="searchBox" type="text" placeholder="Search..."
             class="border border-gray-400 rounded px-2 py-1 w-full" oninput="filterDocs()">
    </div>
    <div class="mb-4 bg-white border border-gray-300 p-4 rounded">
      <h2 class="text-lg font-semibold mb-2">Table of Contents</h2>
      <ul class="list-disc list-inside">
        {toc_html}
      </ul>
    </div>
    <div id="docItems">
      {''.join(content_blocks)}
    </div>
  </div>
</div>
<script>
function filterDocs() {{
  let v = document.getElementById('searchBox').value.toLowerCase();
  let items = document.querySelectorAll('.doc-item');
  items.forEach(item => {{
    let entity = item.getAttribute('data-entity').toLowerCase();
    let text   = item.getAttribute('data-text').toLowerCase();
    if(entity.includes(v) || text.includes(v)) {{
      item.style.display = 'block';
    }} else {{
      item.style.display = 'none';
    }}
  }});
}}
</script>
</body>
</html>
"""
    outpath.write_text(page_html, encoding="utf-8")

def write_index_redirect(first_file: str, output_folder: Path):
    base = first_file.replace('.pas', '')
    index_html = f"""<!DOCTYPE html>
<html>
<head>
  <meta http-equiv="refresh" content="0; URL={base}.html"/>
</head>
<body>
  <p>Redirecting to <a href="{base}.html">{first_file}</a> docs...</p>
</body>
</html>"""
    (output_folder / "index.html").write_text(index_html, encoding="utf-8")

# =============================================================================
# PHASE 5: MAIN
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description="Generate advanced Pascal docs with clickable type links, multi-line enums, and structured member lists.")
    parser.add_argument("--input", "-i", required=True, help="Folder containing .pas files")
    parser.add_argument("--output", "-o", required=True, help="Output folder for HTML docs")
    args = parser.parse_args()

    in_folder = Path(args.input).resolve()
    out_folder = Path(args.output).resolve()
    if not in_folder.is_dir():
        print(f"Error: {in_folder} is not a directory.")
        exit(1)
    out_folder.mkdir(parents=True, exist_ok=True)

    pas_files = sorted(in_folder.rglob("*.pas"))
    if not pas_files:
        print("No .pas files found.")
        exit(0)
    file_names = [p.relative_to(in_folder).name for p in pas_files]

    # Phase 1: Collect type names from each file.
    all_types = {}
    for pas_file, fname in zip(pas_files, file_names):
        all_types[fname] = collect_type_names_in_file(pas_file)
    global_index = build_global_index(all_types)

    # Phase 2: Extract declarations with doc comments.
    all_decls = {}
    for pas_file, fname in zip(pas_files, file_names):
        decls = extract_declarations_with_docs(pas_file)
        for d in decls:
            d["doc_struct"] = parse_doc_lines_tags(d["doc_lines"])
        # Add stub entries for any type not captured as a declaration.
        declared = {d["name"] for d in decls if d["kind"] == "type"}
        for t in all_types[fname]:
            if t not in declared:
                decls.append({
                    "name": t,
                    "kind": "type",
                    "declaration": f"{t} = ... (declaration not captured)",
                    "doc_lines": [],
                    "doc_struct": {"abstract": "", "params": {}, "returns": "", "author": [], "note": [], "warning": [], "main": "No doc found.", "members": []}
                })
        all_decls[fname] = decls

    # Phase 3: Generate HTML pages per file.
    for fname in file_names:
        generate_html_page(fname, file_names, all_decls[fname], global_index, out_folder)

    write_index_redirect(file_names[0], out_folder)
    print(f"Done! Docs generated in {out_folder}")
    print("Open index.html or any generated .html file to browse the documentation.")

if __name__ == "__main__":
    main()
