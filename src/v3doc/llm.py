
from dotenv import load_dotenv
load_dotenv()

from hashlib import sha256
import json
import openai
import tiktoken

from typing import List, Union

from conf import get_v3doc_completions_cache_path
from conf import get_v3doc_embeddings_cache_path

def get_tokens(text: str, encoding: str = 'cl100k_base') -> List[int]:
	encoding = tiktoken.get_encoding(encoding)
	return encoding.encode(text)

def get_embedding(text: Union[str, List[str]], model: str = 'text-embedding-ada-002'):
	request = [ text, model ]
	request_json_body = json.dumps(request)
	s = sha256()
	s.update(request_json_body.encode('utf-8'))
	request_hash = s.hexdigest()

	cache_path = get_v3doc_embeddings_cache_path(model) / f'{request_hash}.json'
	cache_path.parent.mkdir(parents=True, exist_ok=True)

	if cache_path.exists():
		with open(cache_path, 'r') as f:
			content = json.load(f)

			if content['request'] == request:
				result = content['result']
	else:
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
	request = {
		'model': model,
		'messages': messages,
		'top_p': top_p,
		'frequency_penalty': frequency_penalty,
	}
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

	choices = openai.ChatCompletion.create(
		model=model,
		messages=messages,
		top_p=top_p,
		frequency_penalty=frequency_penalty,
	)['choices']

	with open(cache_path, 'w') as f:
		json.dump({
			'request': request,
			'choices': choices,
		}, f)

	return choices
