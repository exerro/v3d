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
parser.add_argument('a_path', type=str)
parser.add_argument('b_path', type=str)

args = parser.parse_args()

# find every file under injest_path
# for each file, get the tokens
# write the tokens to a file with the same name, but in the output directory

v3d_path = get_v3d_path()

a_path = Path(args.a_path)
if not a_path.is_dir():
	raise ValueError(f'Not a directory: {a_path}')

b_path = Path(args.b_path)
if not b_path.is_dir():
	raise ValueError(f'Not a directory: {b_path}')

table = Table()
table.add_column('File')
table.add_column('A tokens')
table.add_column('B tokens')
table.add_column('Ratio')

a_path = a_path.resolve()
b_path = b_path.resolve()

total_a_tokens = 0
total_b_tokens = 0
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

for a_file_path in a_path.glob('**/*'):
	b_file_path = b_path / a_file_path.relative_to(a_path)

	with open(a_file_path, 'r') as f:
		a_file_contents = f.read()

	with open(b_file_path, 'r') as f:
		b_file_contents = f.read()

	a_full_tokens = len(get_tokens(a_file_contents))
	b_full_tokens = len(get_tokens(b_file_contents))

	total_a_tokens += a_full_tokens
	total_b_tokens += b_full_tokens
	n_files += 1

	ratio_as_percentage = floor(b_full_tokens / a_full_tokens * 100)
	table.add_row(str(a_file_path.relative_to(v3d_path)), str(a_full_tokens), str(b_full_tokens), str(ratio_as_percentage) + '%')

table.add_row('Total', str(total_a_tokens), str(total_b_tokens), str(floor(total_b_tokens / total_a_tokens * 100)) + '%')
table.add_row('Average', str(floor(total_a_tokens / n_files)), str(floor(total_b_tokens / n_files)), str(floor(total_b_tokens / total_a_tokens * 100)) + '%')

console.print(table)
