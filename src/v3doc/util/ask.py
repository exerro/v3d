#!/usr/bin/env python3
import sys
import os
parent_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
sys.path.append(parent_dir)

from argparse import ArgumentParser
from pathlib import Path
from typing import List, Tuple
from scipy.spatial import distance
import json
import os

from rich.console import Console

from lib.conf import get_v3d_path
from lib.conf import get_v3doc_documents_path
from lib.llm import get_chat_completion, get_embedding

console = Console()

parser = ArgumentParser()
parser.add_argument('query', type=str)

args = parser.parse_args()

documents = []
for file in (get_v3doc_documents_path()).iterdir():
	if file.is_file() and file.stem != 'index':
		with open(file, 'r') as f:
			data = json.load(f)
		documents.append((file.stem, data))

def read_file(path: Path) -> str:
	with open(path, 'r') as f:
		return f.read()

def get_phase_1_user_message_prefix(initial_message_name, include_types_in_functions):
	str = read_file(get_v3d_path() / 'src' / 'v3doc' / 'prompts' / 'phase_1' / 'user_prefix' / f'{initial_message_name}.txt')
	str += '\n\n'
	str += 'Types:'
	str += '\n'
	str += read_file(get_v3d_path() / 'artifacts' / 'v3doc' / 'type-list.txt')
	str += '\n\n'
	str += 'Functions (v3d.function_name):'
	str += '\n'
	str += read_file(get_v3d_path() / 'artifacts' / 'v3doc' / f'function-{"type-" if include_types_in_functions else ""}list.txt')
	str += '\n\n'
	str += 'Advanced functions:'
	str += '\n'
	str += read_file(get_v3d_path() / 'artifacts' / 'v3doc' / f'advanced-function-{"type-" if include_types_in_functions else ""}list.txt')
	str += '\n\n'
	str += 'Snippets:'
	str += '\n'

	# TODO: should this come from a file, or be loaded from documents?
	for filename in (get_v3d_path() / 'artifacts' / 'v3doc' / 'document_sources' / 'snippet').iterdir():
		str += '* ' + filename.stem.rstrip('.md') + '\n'

	return str

def get_phase_2_user_message_prefix(initial_message_name):
	return read_file(get_v3d_path() / 'src' / 'v3doc' / 'prompts' / 'phase_2' / 'user_prefix' / f'{initial_message_name}.txt')

def get_phase_1_system_message(system_message_name: str):
	return read_file(get_v3d_path() / 'src' / 'v3doc' / 'prompts' / 'phase_1' / 'system' / f'{system_message_name}.txt')

def get_phase_2_system_message(system_message_name: str):
	return read_file(get_v3d_path() / 'src' / 'v3doc' / 'prompts' / 'phase_2' / 'system' / f'{system_message_name}.txt')

def parse_under_heading(heading: str, content: str) -> List[str]:
	result = []
	reading = False

	for line in content.split('\n'):
		if line == f'# {heading}':
			reading = True
		elif reading and line == '':
			break
		elif reading:
			if line.startswith('* '):
				result.append(line[2:].strip())
			else:
				print('Unexpected line: ' + line)

	return result

def parse_body_after_heading(heading: str, content: str) -> str:
	result = []
	reading = False

	for line in content.split('\n'):
		if line == f'# {heading}':
			reading = True
		elif reading and line.startswith('#'):
			break
		elif reading:
			result.append(line)

	return '\n'.join(result)

def parse_phase_1_response_embedding_lookups(content: str) -> List[str]:
	return parse_under_heading('Topics', content)

def parse_phase_1_response_lookups(content: str) -> List[Tuple[str, dict]]:
	looked_up_documents = []

	for lookup_item in parse_under_heading('Lookup', content):
		if lookup_item.startswith('FUNCTION_INFO'):
			fn_name = lookup_item[13:].strip().split(':')[0]

			for document in documents:
				if document[1]['frontmatter']['type'] != 'function':
					continue

				if fn_name == document[1]['frontmatter']['name'] or 'v3d.' + fn_name == document[1]['frontmatter']['name']:
					looked_up_documents.append(document)

		elif lookup_item.startswith('TYPE_INFO'):
			type_name = lookup_item[9:].strip().split(':')[0]

			for document in documents:
				if document[1]['frontmatter']['type'] not in ['class', 'alias']:
					continue

				if type_name == document[1]['frontmatter']['name']:
					looked_up_documents.append(document)

		elif lookup_item.startswith('TYPE_CONSTRUCTORS'):
			type_name = lookup_item[17:].strip().split(':')[0]

			for document in documents:
				if document[1]['frontmatter']['type'] != 'class_constructor':
					continue

				if type_name == document[1]['frontmatter']['name']:
					looked_up_documents.append(document)

		elif lookup_item.startswith('TYPE_METHODS'):
			type_name = lookup_item[12:].strip().split(':')[0]

			for document in documents:
				if document[1]['frontmatter']['type'] != 'class_methods':
					continue

				if type_name == document[1]['frontmatter']['name']:
					looked_up_documents.append(document)

		elif lookup_item.startswith('SNIPPET'):
			snippet_name = lookup_item[7:].strip().split(':')[0]

			for document in documents:
				if document[1]['frontmatter']['type'] != 'snippet':
					continue

				if snippet_name == document[1]['frontmatter']['snippet']:
					looked_up_documents.append(document)

		else:
			print('Unexpected lookup item: ' + lookup_item)

	return looked_up_documents

def parse_phase_1_response_relevant_lookups(content: str) -> List[str]:
	return [it.split(':')[0] for it in parse_under_heading('Relevant', content)]

def find_relevant_embeddings(queries: List[str]) -> List[Tuple[float, str, dict]]:
	queries_embeddings = get_embedding(queries)
	result_documents = [doc_pair for doc_pair in documents]
	document_votes = {}

	vote_limit = 2

	for query_embedding in queries_embeddings:
		scored_documents = []

		for candidate_document in documents:
			candidate_document_embedding = candidate_document[1]['ada_002_embedding']
			score = 1 - distance.cosine(query_embedding, candidate_document_embedding)
			scored_documents.append((score, candidate_document[0], candidate_document[1]))

		scored_documents.sort(key=lambda x: x[0], reverse=True)

		for i in range(vote_limit):
			score, document_hash, _ = scored_documents[i]
			document_votes[document_hash] = document_votes.get(document_hash, 0) + (vote_limit - i)

	result_documents.sort(key=lambda x: document_votes.get(x[0], 0), reverse=True)

	# delete documents with less than half the most-voted document's votes
	half_highest_votes = document_votes.get(result_documents[0][0], 0) / 2
	result_documents = [doc for doc in result_documents if document_votes.get(doc[0], 0) >= half_highest_votes]

	return [(document_votes.get(doc[0], 0), doc[0], doc[1]) for doc in result_documents]

def remove_duplicate_documents(documents: List[Tuple[str, dict]]) -> List[Tuple[str, dict]]:
	seen = set()
	result = []

	for document_pair in documents:
		if document_pair[0] not in seen:
			result.append(document_pair)
			seen.add(document_pair[0])

	return result

def short_hash(document_hash: str):
	return document_hash[0:8]

def strip_frontmatter(content: str) -> str:
	parts = content.split('---', 2)
	if len(parts) == 3:
		return parts[2]
	else:
		return content

messages = [
	{ 'role': 'system', 'content': get_phase_1_system_message('v12') },
	{ 'role': 'user', 'content': get_phase_1_user_message_prefix('3', True) + '\n\nUser question:' + args.query },
]

completion_choices = get_chat_completion(messages, top_p=0.3)
content = '[yellow]' + completion_choices[0]['message']['content'] + '[/yellow]\n'

console.print(content)
console.print()
console.print('Will look up:')
for sub_query in parse_phase_1_response_embedding_lookups(completion_choices[0]['message']['content']):
	console.print(f'• [blue]{sub_query}[/blue]')

console.print()
console.print('Will pass in:')
for document in parse_phase_1_response_lookups(completion_choices[0]['message']['content']):
	console.print(f'• [green]{document[1]["path"]}[/green]')

console.print()
console.print('Will forward:')
for item in parse_phase_1_response_relevant_lookups(completion_choices[0]['message']['content']):
	console.print(f'• [blue]{item}[/blue]')

resultant_documents = []
for sub_query in parse_phase_1_response_embedding_lookups(completion_choices[0]['message']['content']):
	resultant_documents += find_relevant_embeddings([sub_query])
for document_hash, document in parse_phase_1_response_lookups(completion_choices[0]['message']['content']):
	resultant_documents.append((None, document_hash, document))

resultant_documents = remove_duplicate_documents([(it[1], it[2]) for it in resultant_documents])

console.print()
console.print('Resultant documents:')
for document in resultant_documents:
	console.print(f'• [green]{document[1]["path"]}[/green]')

console.print()
console.print('Total requested tokens: ' + str(sum([len(it[1]['cl100k_base_tokens']) for it in resultant_documents])))

phase_2_user_message = get_phase_2_user_message_prefix('1')

# for document in resultant_documents:
	# phase_2_user_message += '\n\n'
	# phase_2_user_message += document['path']
	# phase_2_user_message += '==='
	# phase_2_user_message += document['content']
	# phase_2_user_message += '==='

# TODO: pass in the relevant stuff too!

formatted_resultant_documents = [
	f'<article id="{short_hash(it[0])}">\n{strip_frontmatter(it[1]["content"])}\n</article>'
	for it in resultant_documents
]
# formatted_resultant_documents = []

phase_2_system_message = get_phase_2_system_message('v7') \
	.replace('${PHASE_2_RELEVANT_DOCUMENTS}', '\n\n'.join(formatted_resultant_documents))

phase_2_user_pre_message = get_phase_2_user_message_prefix('4') \
	.replace('${PHASE_2_RELEVANT_DOCUMENTS}', '\n\n'.join(formatted_resultant_documents))

phase_2_user_message = args.query

phase_2_messages = [
	{ 'role': 'system', 'content': phase_2_system_message },
	{ 'role': 'user', 'content': phase_2_user_pre_message },
	{ 'role': 'user', 'content': phase_2_user_message },
]

console.print('[bold blue]' + args.query)
completion = get_chat_completion(phase_2_messages, top_p=0.3, frequency_penalty=0.1)[0]['message']['content']
console.print('[grey]' + parse_body_after_heading('Reply', completion))

if parse_body_after_heading('Reply', completion).strip() == '':
	console.print('[red]No reply![/red]')
	print(completion)
