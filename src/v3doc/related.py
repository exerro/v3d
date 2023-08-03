#!/usr/bin/env python3

from argparse import ArgumentParser
from scipy import spatial
from rich.console import Console
from rich.table import Table
import json

from conf import get_v3doc_documents_path
from llm import get_embedding

console = Console()

parser = ArgumentParser()
parser.add_argument('query', type=str)

args = parser.parse_args()

query_embedding = get_embedding(args.query)

v3doc_documents_path = get_v3doc_documents_path()
documents = []
for file in v3doc_documents_path.iterdir():
	if file.is_file() and file != v3doc_documents_path / 'index.json':
		with open(file, 'r') as f:
			data = json.load(f)
		doc_embedding = data['ada_002_embedding']
		distance = 1 - spatial.distance.cosine(query_embedding, doc_embedding)
		documents.append((data['path'], distance, data['cl100k_base_tokens_len']))

documents.sort(key=lambda x: x[1], reverse=True)
del documents[20:]

table = Table()
table.add_column('Document')
table.add_column('Distance')
table.add_column('Cumulative Tokens')

tokens_aggregate = 0
for file, distance, tokens in documents:
	tokens_aggregate += tokens
	table.add_row(str(file), str(distance), str(tokens_aggregate))

console.print(table)
