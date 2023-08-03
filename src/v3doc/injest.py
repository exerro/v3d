#!/usr/bin/env python3

from argparse import ArgumentParser
from pathlib import Path
from hashlib import sha256
import json
import os

from rich.console import Console
from rich.prompt import Prompt
from rich.table import Table

from conf import get_v3d_path
from conf import get_v3doc_documents_path
from llm import get_embedding
from llm import get_tokens

console = Console()

parser = ArgumentParser()
parser.add_argument('injest_path', type=str)
parser.add_argument('--speculative', '-s', action='store_true')

args = parser.parse_args()
speculative = args.speculative

# find every file under injest_path
# for each file, get the tokens
# write the tokens to a file with the same name, but in the output directory

v3d_path = get_v3d_path()
v3doc_documents_path = get_v3doc_documents_path()

injest_path = Path(args.injest_path)
if not injest_path.is_dir():
	raise ValueError(f'Not a directory: {injest_path}')

if not speculative:
	# confirm with user before proceeding
	console.print(f'Injesting from [green]{injest_path}[/green] to [green]{v3doc_documents_path.relative_to(v3d_path)}')
	console.print('[yellow]Press enter to continue, or ctrl-c to cancel')
	input()

injest_path = injest_path.resolve()

def read_index():
	index_path = v3doc_documents_path / 'index.json'
	if index_path.exists():
		with open(index_path, 'r') as f:
			return json.load(f)
	return {}

def write_index(index):
	index_path = v3doc_documents_path / 'index.json'
	with open(index_path, 'w') as f:
		json.dump(index, f, indent=2)

def read_cached_data(file_hash: str):
	target_path = v3doc_documents_path / f'{file_hash}.json'

	if not target_path.exists():
		return {}

	with open(target_path, 'r') as f:
		return json.load(f)

def update_file(index: dict, file_path: Path, file_hash: bytes, file_data: dict):
	if speculative:
		return

	file_path_str = str(file_path.relative_to(v3d_path))
	index[file_path_str] = file_hash
	target_path = v3doc_documents_path / f'{file_hash}.json'
	target_path.parent.mkdir(parents=True, exist_ok=True)

	with open(target_path, 'w') as f:
		json.dump(file_data, f, indent=2)

index = read_index()
files_to_process = []
changed_files = []
deleted_files = []

for str_file_path, file in index.items():
	file_path = v3d_path / str_file_path

	# if file_path is within injest_path
	try:
		file_path.relative_to(injest_path)
		# it is inside injest_path
		if not file_path.exists():
			deleted_files.append(str_file_path)
	except ValueError:
		pass # not relative

# Iterate over all files in injest_path. If the file has changed, add it to
# changed_files. Regardless, add it and its hash to files_to_process.
for file_path in list(injest_path.glob('**/*')):
	if not file_path.is_file():
		continue

	with open(file_path, 'r') as f:
		file_contents = f.read()

	hasher = sha256()
	hasher.update(str(file_path.relative_to(v3d_path)).encode('utf-8'))
	hasher.update(b'\n')
	hasher.update(file_contents.encode('utf-8'))
	file_hash = hasher.digest().hex()

	str_file_path = str(file_path.relative_to(v3d_path))
	files_to_process.append((file_path, str_file_path, file_hash, file_contents))

	if str_file_path in index and index[str_file_path] != file_hash:
		changed_files.append((str_file_path, index[str_file_path], file_hash))

# If we have deleted files, confirm with the user before proceeding.
if deleted_files:
	while True:
		console.print(f'{len(deleted_files)} files have been deleted. What would you like to do?')
		console.print('1) Keep embedded documents for files')
		console.print('2) Delete embedded documents for files')
		console.print('3) See files')

		action = Prompt.ask('Action', choices=['1', '2', '3'])

		if action == '1':
			break
		elif action == '2':
			for file in deleted_files:
				hash = index[file]
				os.remove(v3doc_documents_path / f'{hash}.json')
				del index[file]

			write_index(index)
			break
		elif action == '3':
			for file in deleted_files:
				console.print(f'* [green]{file}[/green]')

# If we have changed files, confirm with the user before proceeding.
if changed_files:
	while True:
		console.print(f'{len(changed_files)} files have changed. What would you like to do?')
		console.print('1) Use current, skip new')
		console.print('2) Keep current, generate new')
		console.print('3) Delete current, generate new')
		console.print('4) See files')

		action = Prompt.ask('Action', choices=['1', '2', '3', '4'])

		if action == '1':
			# Old file will be used instead.
			for (_, old_hash, new_hash) in changed_files:
				os.rename(v3doc_documents_path / f'{old_hash}.json', v3doc_documents_path / f'{new_hash}.json')
			break
		elif action == '2':
			# Old file will be kept but new one will be generated as usual.
			break
		elif action == '3':
			# Old file will be deleted. New one will be generated as usual.
			for (_, old_hash, _) in changed_files:
				os.remove(v3doc_documents_path / f'{old_hash}.json')
			break
		elif action == '4':
			# Print out the list of changed files.
			for (changed_file, old_hash, new_hash) in changed_files:
				console.print(f'* [green]{changed_file}[/green]: {old_hash[0:8]} -> {new_hash[0:8]}')

	for (str_changed_file, old_hash, new_hash) in changed_files:
		index[str_changed_file] = new_hash

table = Table()
table.add_column('File')
table.add_column('cl100k tokens')
table.add_column('p50k tokens')

for (file_path, str_file_path, file_hash, file_contents) in files_to_process:
	print(f'Processing {str_file_path}...')

	file_data = read_cached_data(file_hash)
	file_data['path'] = str_file_path
	updated = False

	if 'cl100k_base_tokens' not in file_data:
		file_data['cl100k_base_tokens'] = get_tokens(file_contents, 'cl100k_base')
		file_data['cl100k_base_tokens_len'] = len(file_data['cl100k_base_tokens'])
		updated = True
	
	if 'p50k_base_tokens' not in file_data:
		file_data['p50k_base_tokens'] = get_tokens(file_contents, 'p50k_base')
		file_data['p50k_base_tokens_len'] = len(file_data['p50k_base_tokens'])
		updated = True

	if 'ada_002_embedding' not in file_data and not speculative:
		file_data['ada_002_embedding'] = get_embedding(file_contents, 'text-embedding-ada-002')
		updated = True

	if 'frontmatter' not in file_data:
		file_data['frontmatter'] = {}
		updated = True

		file_contents_lines = file_contents.split('\n')
		if file_contents_lines[0] == '---':
			# frontmatter exists
			i = 1
			while file_contents_lines[i] != '---':
				line = file_contents_lines[i]
				key, value = line.split(': ', 1)
				file_data['frontmatter'][key] = value
				i += 1

	# TODO: embeddings

	if updated:
		table.add_row(
			str(file_path.relative_to(injest_path)),
			str(file_data['cl100k_base_tokens_len']),
			str(file_data['p50k_base_tokens_len']),
		)

		if not speculative:
			update_file(index, file_path, file_hash, file_data)

console.print(table)

if not speculative:
	write_index(index)
