#!/usr/bin/env python3
import sys
import os
parent_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
sys.path.append(parent_dir)

from argparse import ArgumentParser
from pathlib import Path
from hashlib import sha256
from scipy import spatial
import json
import os

from rich.console import Console
from rich.prompt import Prompt
from rich.table import Table

from lib.conf import get_v3d_path
from lib.conf import get_v3doc_documents_path
from lib.llm import get_embedding
from lib.llm import get_tokens

console = Console()

parser = ArgumentParser()
parser.add_argument('query', type=str)

args = parser.parse_args()

query_embedding = get_embedding(args.query)

matches = []
for document_path in get_v3doc_documents_path().iterdir():
	if document_path.stem == 'index':
		continue

	with open(document_path, 'r') as f:
		document = json.load(f)

	distance = spatial.distance.cosine(query_embedding, document['ada_002_embedding'])
	matches.append((distance, document))

matches.sort(key=lambda it: it[0])

for (distance, document) in matches:
	console.print(f'• {distance} {document["path"]}')
