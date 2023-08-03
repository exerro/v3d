#!/usr/bin/env python3

from argparse import ArgumentParser
from math import floor
from pathlib import Path
import re

from rich.console import Console
from rich.table import Table

from conf import get_v3d_path
from conf import get_v3doc_documents_path
from llm import get_tokens

console = Console()

parser = ArgumentParser()
parser.add_argument('injest_path', type=str)

args = parser.parse_args()

# find every file under injest_path
# for each file, get the tokens
# write the tokens to a file with the same name, but in the output directory

v3d_path = get_v3d_path()
v3doc_documents_path = get_v3doc_documents_path()

injest_path = Path(args.injest_path)
if not injest_path.is_dir():
	raise ValueError(f'Not a directory: {injest_path}')

table = Table()
table.add_column('File')
table.add_column('Full Tokens')
table.add_column('Wordy Tokens')
table.add_column('Ratio')

injest_path = injest_path.resolve()

total_full_tokens = 0
total_wordy_tokens = 0
n_files = 0

regex_and_replacement = [(re.compile(r), replacement)
	for r, replacement in [
		(r'```.-```', ''),
		(r'[^\s\w_]+', ''),
		(r'[\s]+', ' '),
		(r'^[\s]+', ''),
		(r'[\s]+$', ''),
	]
]

for file_path in list(injest_path.glob('**/*')):
	with open(file_path, 'r') as f:
		file_contents = f.read()

	wordy_content = file_contents
	for regex, replacement in regex_and_replacement:
		wordy_content = regex.sub(replacement, wordy_content)

	full_tokens = len(get_tokens(file_contents))
	wordy_tokens = len(get_tokens(wordy_content))

	total_full_tokens += full_tokens
	total_wordy_tokens += wordy_tokens
	n_files += 1

	ratio_as_percentage = floor(wordy_tokens / full_tokens * 100)
	table.add_row(str(file_path.relative_to(v3d_path)), str(full_tokens), str(wordy_tokens), str(ratio_as_percentage) + '%')

table.add_row('Total', str(total_full_tokens), str(total_wordy_tokens), str(floor(total_wordy_tokens / total_full_tokens * 100)) + '%')
table.add_row('Average', str(floor(total_full_tokens / n_files)), str(floor(total_wordy_tokens / n_files)), str(floor(total_wordy_tokens / total_full_tokens * 100)) + '%')

console.print(table)
