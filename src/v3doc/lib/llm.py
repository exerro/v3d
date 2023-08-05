
from dotenv import load_dotenv
load_dotenv()

from hashlib import sha256
import json
import openai
import tiktoken

from typing import List, Union

from lib.conf import (
	get_v3doc_completions_cache_path,
	get_v3doc_embeddings_cache_path,
)

def get_tokens(text: str, encoding: str = 'cl100k_base') -> List[int]:
	encoding = tiktoken.get_encoding(encoding)
	return encoding.encode(text)

def get_embedding(
	text: Union[str, List[str]],
	model: str = 'text-embedding-ada-002'
) -> Union[List[float], List[List[float]]]:
	"""
	Return the embedding for some text using the model provided. This function
	caches the result and avoids API calls where possible.

	`text` may be a string or a list of strings. If a string is input, a single
	array of embedding values will be returned. Otherwise, an array of arrays of
	embedding values will be returned.
	"""
	request = [ text, model ]
	request_json_body = json.dumps(request)
	s = sha256()
	s.update(request_json_body.encode('utf-8'))
	request_hash = s.hexdigest()

	cache_path = get_v3doc_embeddings_cache_path(model) / f'{request_hash}.json'
	cache_path.parent.mkdir(parents=True, exist_ok=True)

	# both branches eval 'result'
	if cache_path.exists():
		with open(cache_path, 'r') as f:
			content = json.load(f)

			if content['request'] == request:
				result = content['result']
			else:
				raise Exception('Request of cached embedding at same hash does not match')
	else:
		print(f'Embedding cache miss: {request_hash}')

		result = openai.Embedding.create(
			model=model,
			input=text,
		)

		with open(cache_path, 'w') as f:
			json.dump({
				'request': request,
				'result': result,
			}, f)

	if isinstance(text, str):
		return result['data'][0]['embedding']
	else:
		return [it['embedding'] for it in result['data']]

def get_chat_completion(
	messages: List[dict],
	model: str = 'gpt-3.5-turbo',
	top_p = 1,
	frequency_penalty = 0,
) -> List[dict]:
	"""
	Return the completion for an input set of messages. Messages are formatted
	according to the OpenAI API, i.e.:
	```
	{
		'role': 'system'|'user'|'assistant',
		'content': 'message...'
	}
	```

	This function caches the result and avoids API calls where possible.
	"""

	# We use a list for the request here to ensure a stable JSON dump &
	# subsequent hash.
	request = [
		model,
		[[message['role'], message['content']] for message in messages],
		top_p,
		frequency_penalty,
	]
	request_json_body = json.dumps(request)
	s = sha256()
	s.update(request_json_body.encode('utf-8'))
	request_hash = s.hexdigest()

	cache_path = get_v3doc_completions_cache_path(model) / f'{request_hash}.json'
	cache_path.parent.mkdir(parents=True, exist_ok=True)

	if cache_path.exists():
		with open(cache_path, 'r') as f:
			content = json.load(f)

			if content['request'] == request:
				return content['choices']
			else:
				raise Exception('Request of cached completion at same hash does not match')

	print(f'Completion cache miss: {request_hash}')

	choices = openai.ChatCompletion.create(
		model=model,
		messages=messages,
		top_p=top_p,
		frequency_penalty=frequency_penalty,
	)['choices']

	# TODO: do we care about tokens?

	with open(cache_path, 'w') as f:
		json.dump({
			'request': request,
			'choices': choices,
		}, f)

	return choices
