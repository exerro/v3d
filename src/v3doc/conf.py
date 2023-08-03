
from pathlib import Path

def get_v3d_path():
	this_file_path = Path(__file__).resolve()
	return this_file_path.parent.parent.parent

def get_v3doc_documents_path():
	return get_v3d_path() / 'artifacts' / 'generated' / 'documents'

def get_v3doc_embeddings_cache_path(model: str):
	return get_v3d_path() / 'artifacts' / 'cache' / 'embeddings' / model

def get_v3doc_completions_cache_path(model: str):
	return get_v3d_path() / 'artifacts' / 'cache' / 'completions' / model
