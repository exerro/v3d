#!/usr/bin/env python3
import sys
import os
parent_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
sys.path.append(parent_dir)

from argparse import ArgumentParser
from pathlib import Path
from hashlib import sha256
import json
import os

from rich.console import Console

from lib.conf import get_v3d_path
from lib.conf import get_v3doc_documents_path
from lib.llm import get_embedding
from lib.llm import get_tokens

console = Console()

parser = ArgumentParser()
parser.add_argument('injest_path', type=str)
parser.add_argument('--speculative', '-s', action='store_true')
parser.add_argument('--remap-updated-files', '-r', action='store_true')

args = parser.parse_args()
injest_path = Path(args.injest_path).resolve()
speculative = args.speculative
remap_updated_files = args.remap_updated_files
v3d_path = get_v3d_path()
v3doc_documents_path = get_v3doc_documents_path()
index = json.loads((v3doc_documents_path / 'index.json').read_text())

all_files = []
for file in injest_path.glob('**/*'):
	if file.is_dir():
		continue

	s = sha256()
	s.update(bytes(file.relative_to(v3d_path)))
	s.update(b':')
	s.update(file.read_bytes())
	file_hash = s.hexdigest()
	all_files.append((file, file_hash))

missing_files = []
for filename, hash in index.items():
	try:
		Path(filename).relative_to(injest_path)
	except:
		continue # gross way to skip files not in injest_path

	if not any([str(it[0].relative_to(v3d_path)) == filename for it in all_files]):
		missing_files.append(Path(filename))

new_files = []
updated_files = []
unchanged_files = []
for file, file_hash in all_files:
	file_path_str = str(file.relative_to(v3d_path))

	if file_path_str not in index:
		new_files.append((file, file_hash))
	elif not (v3doc_documents_path / (index.get(file_path_str) + '.json')).exists():
		updated_files.append((file, index.get(file_path_str), file_hash))
	elif file_hash != index.get(file_path_str):
		updated_files.append((file, index.get(file_path_str), file_hash))
	else:
		unchanged_files.append((file, file_hash))

if missing_files:
	console.print(f'[bold red]{len(missing_files)} old documents will be deleted:[/bold red]')
	for file in missing_files:
		console.print(f'• [white]{file.relative_to(injest_path)}[/white]')

if updated_files:
	console.print(f'[bold yellow]{len(updated_files)} files will be updated:[/bold yellow]')
	for (file, old_hash, new_hash) in updated_files:
		console.print(f'• [white]{file.relative_to(injest_path)} ({old_hash[0:8]} -> {new_hash[0:8]})[/white]')

if new_files:
	console.print(f'[bold green]{len(new_files)} new files will be added:[/bold green]')
	for (file, _) in new_files:
		console.print(f'• [white]{file.relative_to(injest_path)}[/white]')

if unchanged_files:
	console.print(f'[bold blue]{len(unchanged_files)} files are unchanged.[/bold blue]')

def parse_frontmatter(content: str) -> dict:
	if content.startswith('---'):
		frontmatter = {}

		lines = content.split('\n')
		for line in lines[1:]:
			if line == '---':
				break
			elif line.startswith('---'):
				raise Exception(f'Frontmatter is malformed: {line}')
			else:
				(key, value) = line.split(':', 1)
				frontmatter[key.strip()] = value.strip()

		return frontmatter

	return {}

def update_file(path: Path, hash: bytes) -> None:
	if speculative:
		return

	print('Recalculating stuff for ' + str(path.relative_to(v3d_path)))

	index[str(path.relative_to(v3d_path))] = hash
	content = file.read_text()
	document = { 'content': content }
	document['path'] = str(path.relative_to(v3d_path))
	document['frontmatter'] = parse_frontmatter(content)
	document['cl100k_base_tokens'] = get_tokens(content, 'cl100k_base')
	document['p50k_base_tokens'] = get_tokens(content, 'p50k_base')
	document['ada_002_embedding'] = get_embedding(content, 'text-embedding-ada-002')

	document_path = v3doc_documents_path / (hash + '.json')
	document_path.write_text(json.dumps(document, indent=2))

for (file, file_hash) in missing_files:
	if not speculative:
		os.remove(v3doc_documents_path / (file_hash + '.json'))

if updated_files and remap_updated_files:
	raise Exception('Remapping updated files is not yet implemented')

for (file, old_hash, file_hash) in updated_files:
	old_path = v3doc_documents_path / (old_hash + '.json')
	# TODO: use remap_updated_files
	if old_path.exists(): os.remove(old_path)
	update_file(file, file_hash)

for (file, file_hash) in new_files:
	update_file(file, file_hash)

with open(v3doc_documents_path / 'index.json', 'w') as f:
	json.dump(index, f, indent=2)
