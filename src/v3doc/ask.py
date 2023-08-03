#!/usr/bin/env python3

from argparse import ArgumentParser
from pathlib import Path
from rich.console import Console
from rich.table import Table
from scipy import spatial
from typing import List, NamedTuple, Optional, Tuple, Union
import json

from conf import get_v3d_path
from llm import get_chat_completion
from llm import get_embedding

console = Console()

parser = ArgumentParser()
parser.add_argument('query', type=str)

args = parser.parse_args()

embeddings_documents = []
for file in (get_v3d_path() / 'artifacts' / 'generated' / 'documents').iterdir():
	if file.is_file() and file != get_v3d_path() / 'artifacts' / 'generated' / 'documents' / 'index.json':
		with open(file, 'r') as f:
			data = json.load(f)
		embeddings_documents.append(data)

def read_file(path: Path) -> str:
	with open(path, 'r') as f:
		return f.read()
	
def get_initial_user_message_prefix(initial_message_name, include_types_in_functions):
	str = read_file(get_v3d_path() / 'src' / 'v3doc' / 'user_standard_context' / f'{initial_message_name}.txt')
	str += '\n\n'
	str += 'Types:'
	str += '\n'
	str += read_file(get_v3d_path() / 'artifacts' / 'type-list.txt')
	str += '\n\n'
	str += 'Functions (v3d.function_name):'
	str += '\n'
	str += read_file(get_v3d_path() / 'artifacts' / f'function-{"type-" if include_types_in_functions else ""}list.txt')
	str += '\n\n'
	str += 'Advanced functions:'
	str += '\n'
	str += read_file(get_v3d_path() / 'artifacts' / f'advanced-function-{"type-" if include_types_in_functions else ""}list.txt')
	str += '\n\n'
	str += 'Snippets:'
	str += '\n'

	for filename in (get_v3d_path() / 'artifacts' / 'doc' / 'generated' / 'embedding' / 'snippet').iterdir():
		str += '* ' + filename.stem.rstrip('.md') + '\n'

	return str

def find_relevant_embeddings(queries: List[str]) -> List[Tuple[float, dict]]:
	queries_embeddings = get_embedding(queries)
	result_documents = [doc for doc in embeddings_documents]
	document_votes = {}

	vote_limit = 2

	for query_embedding in queries_embeddings:
		scored_documents = []

		for canditate_document in embeddings_documents:
			candidate_document_embedding = canditate_document['ada_002_embedding']
			score = 1 - spatial.distance.cosine(query_embedding, candidate_document_embedding)
			scored_documents.append((score, canditate_document))

		scored_documents.sort(key=lambda x: x[0], reverse=True)

		for i in range(vote_limit):
			score, document = scored_documents[i]
			document_votes[document['path']] = document_votes.get(document['path'], 0) + (vote_limit - i)

	result_documents.sort(key=lambda x: document_votes.get(x['path'], 0), reverse=True)
	
	# delete documents with less than half the most-voted document's votes
	half_highest_votes = document_votes.get(result_documents[0]['path'], 0) / 2
	result_documents = [doc for doc in result_documents if document_votes.get(doc['path'], 0) >= half_highest_votes]

	return [(document_votes.get(doc['path'], 0), doc) for doc in result_documents]

class Protocol:
	def include_types_in_functions(self) -> bool:
		return False

	def get_initial_system_message(self) -> str:
		raise NotImplementedError()

	def get_initial_response_context_queries(self, response: str) -> List[str]:
		raise NotImplementedError()
	
	def get_initial_response_refs(self, response: str) -> List[dict]:
		raise NotImplementedError()
	
	def get_initial_response_related(self, response: str) -> List[str]:
		raise NotImplementedError()


class Protocol_V1(Protocol):
	def get_initial_system_message(self) -> str:
		return read_file(get_v3d_path() / 'src' / 'v3doc' / 'system_messages' / 'v1.txt')

class Protocol_V2(Protocol):
	def get_initial_system_message(self) -> str:
		return read_file(get_v3d_path() / 'src' / 'v3doc' / 'system_messages' / 'v2.txt')

class Protocol_V3(Protocol):
	def get_initial_system_message(self) -> str:
		return read_file(get_v3d_path() / 'src' / 'v3doc' / 'system_messages' / 'v3.txt')

class Protocol_V4(Protocol):
	def get_initial_system_message(self) -> str:
		return read_file(get_v3d_path() / 'src' / 'v3doc' / 'system_messages' / 'v4.txt')

class Protocol_V5(Protocol):
	def get_initial_system_message(self) -> str:
		return read_file(get_v3d_path() / 'src' / 'v3doc' / 'system_messages' / 'v5.txt')

class Protocol_V6(Protocol):
	def get_initial_system_message(self) -> str:
		return read_file(get_v3d_path() / 'src' / 'v3doc' / 'system_messages' / 'v6.txt')

class Protocol_V7(Protocol):
	def get_initial_system_message(self) -> str:
		return read_file(get_v3d_path() / 'src' / 'v3doc' / 'system_messages' / 'v7.txt')

class Protocol_V8(Protocol):
	def get_initial_system_message(self) -> str:
		return read_file(get_v3d_path() / 'src' / 'v3doc' / 'system_messages' / 'v8.txt')

class Protocol_V9(Protocol):
	def get_initial_system_message(self) -> str:
		return read_file(get_v3d_path() / 'src' / 'v3doc' / 'system_messages' / 'v9.txt')

class Protocol_V10(Protocol):
	def get_initial_system_message(self) -> str:
		return read_file(get_v3d_path() / 'src' / 'v3doc' / 'system_messages' / 'v10.txt')
	
	def get_initial_response_context_queries(self, response: str) -> List[str]:
		topics = []
		reading = False
		for line in response.splitlines():
			if line == '# Topics':
				reading = True
			elif line == '':
				break
			elif reading:
				if line.startswith('* '):
					topics.append(line[2:])
				else:
					print('Unexpected line: ' + line)

		return topics

class Protocol_V11(Protocol):
	def get_initial_system_message(self) -> str:
		return read_file(get_v3d_path() / 'src' / 'v3doc' / 'system_messages' / 'v11.txt')
	
	def get_initial_response_context_queries(self, response: str) -> List[str]:
		topics = []
		reading = False

		for line in response.split('\n'):
			if line == '# Topics':
				reading = True
			elif line == '':
				break
			elif reading:
				if line.startswith('* '):
					topics.append(line[2:])
				else:
					print('Unexpected line: ' + line)

		return topics

class Protocol_V12(Protocol):
	def include_types_in_functions(self) -> bool:
		return True

	def get_initial_system_message(self) -> str:
		return read_file(get_v3d_path() / 'src' / 'v3doc' / 'system_messages' / 'v12.txt')
	
	def get_initial_response_context_queries(self, response: str) -> List[str]:
		topics = []
		reading = False

		for line in response.split('\n'):
			if line == '# Topics':
				reading = True
			elif line == '':
				break
			elif reading:
				if line.startswith('* '):
					topics.append(line[2:])
				else:
					print('Unexpected line: ' + line)

		return topics

	def get_initial_response_refs(self, response: str) -> List[dict]:
		refs = []

		for line in response.splitlines():
			if line.startswith('* FUNCTION_INFO'):
				fnname = line[15:].strip().split(':')[0]

				for embeddings_document in embeddings_documents:
					if embeddings_document['frontmatter']['type'] != 'function':
						continue

					frontmatter_name = embeddings_document['frontmatter']['name']

					if fnname == frontmatter_name or 'v3d.' + fnname == frontmatter_name:
						refs.append(embeddings_document)

			elif line.startswith('* TYPE_INFO'):
				typename = line[11:].strip().split(':')[0]

				for embeddings_document in embeddings_documents:
					if embeddings_document['frontmatter']['type'] not in ['class', 'alias']:
						continue

					if typename == embeddings_document['frontmatter']['name']:
						refs.append(embeddings_document)

			elif line.startswith('* TYPE_CONSTRUCTORS'):
				typename = line[19:].strip().split(':')[0]

				for embeddings_document in embeddings_documents:
					if embeddings_document['frontmatter']['type'] != 'class_constructor':
						continue

					if typename == embeddings_document['frontmatter']['name']:
						refs.append(embeddings_document)

			elif line.startswith('* TYPE_METHODS'):
				typename = line[14:].strip().split(':')[0]

				for embeddings_document in embeddings_documents:
					if embeddings_document['frontmatter']['type'] != 'class_methods':
						continue

					if typename == embeddings_document['frontmatter']['name']:
						refs.append(embeddings_document)

			elif line.startswith('* SNIPPET'):
				snippetname = line[9:].strip().split(':')[0]

				for embeddings_document in embeddings_documents:
					if embeddings_document['frontmatter']['type'] != 'snippet':
						continue

					if snippetname == embeddings_document['frontmatter']['snippet']:
						refs.append(embeddings_document)

		return refs

	def get_initial_response_related(self, response: str) -> List[str]:
		related = []
		reading = False

		for line in response.split('\n'):
			if line == '# Related':
				reading = True
			elif line == '':
				break
			elif reading:
				if line.startswith('* '):
					related.append(line[2:])
				else:
					print('Unexpected line: ' + line)

		return related


protocols = [
	# ('V1', Protocol_V1()),
	# ('V2', Protocol_V2()),
	# ('V3', Protocol_V3()),
	# ('V4', Protocol_V4()),
	# ('V5', Protocol_V5()),
	# ('V6', Protocol_V6()),
	# ('V6', Protocol_V6()),
	# ('V7', Protocol_V7()),
	# ('V8', Protocol_V8()),
	# ('V9', Protocol_V9()),
	# ('V10', Protocol_V10()),
	# ('V11', Protocol_V11()),
	('V12', Protocol_V12()),
]

initial_messages = [
	# '1',
	# '2',
	'3',
]

top_ps = [
	0.3,
	# 0.5,
	# 0.8,
]

frequency_ps = [
	0.0,
	# 0.1,
	# 0.5,
]

table = Table()
table.add_column('Top P / Freq Penalty')

for protocol_name, _ in protocols:
	table.add_column(protocol_name)

for top_p in top_ps:
	for frequency_p in frequency_ps:
		row = [str(top_p) + ' / ' + str(frequency_p)]

		for protocol_name, protocol in protocols:
			for initial_message_name in initial_messages:
				system_message = protocol.get_initial_system_message()
				user_message_prefix = get_initial_user_message_prefix(initial_message_name, protocol.include_types_in_functions())
				user_message = user_message_prefix + '\n\nUser question:' + args.query

				messages = [
					{ 'role': 'system', 'content': system_message },
					{ 'role': 'user', 'content': user_message },
				]

				print('Trying ' + str(top_p) + ' / ' + str(frequency_p) + ' on ' + protocol_name + ' init ' + initial_message_name)
				choices = get_chat_completion(messages, top_p=top_p, frequency_penalty=frequency_p)

				content = '[yellow]' + choices[0]['message']['content'] + '[/yellow]\n'
				context_queries = protocol.get_initial_response_context_queries(choices[0]['message']['content'])
				relevant_documents = find_relevant_embeddings(context_queries)
				set_relevant_documents = []
				seen = set()

				for document in protocol.get_initial_response_refs(choices[0]['message']['content']):
					relevant_documents.append((None, document))

				for context_query in context_queries:
					content += '\n* [blue]' + context_query + '[/blue]'

				for score, relevant_document in relevant_documents:
					if relevant_document['path'] not in seen:
						set_relevant_documents.append((score, relevant_document))
						seen.add(relevant_document['path'])

				for score, relevant_document in set_relevant_documents:
					content += '\n* (' + str(score or 'explicit') + ') [green]' + relevant_document['path'] + '[/green] (' + str(relevant_document["cl100k_base_tokens_len"]) + ')'

				content += f'\n\nTotal requested tokens: {sum([it["cl100k_base_tokens_len"] for _, it in set_relevant_documents])}'

				row.append(content)
		
		table.add_row(*row)

console.print(table)
