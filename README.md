
# Under maintainance!

V3D is undergoing a major rewrite.

I'm rebuilding the library's build system and code structure and reinventing
some of the APIs. You can think of it as v3d 2.0...

My large scale plans are:
* LLM powered documentation chatbot: ChatGPT for V3D using the generated documentation to answer questions
* Automated documentation generation
  * improved code parser will generate more detailed docs
  * improved validation specification will allow the documentation to include these details
* Debugger overhaul
  * rename v3dd -> v3debug
  * make it more efficient so you don't get 0.3fps when using it
  * improve validations (better parameter checking)
  * support debug regions (group commands into logical regions e.g. 'draw player', 'draw map' etc)
  * better keyboard controls

Planned API changes:
* all functions are available as v3d.X(instance, ...) or V3DInstance:X(...)
* can add custom methods to V3D types
* introduce V3DImage (1D/2D/3D image type with arbitrary contents)
* replace framebuffers with collections of V3DImages
* unify the type system for geometry and images
* use a consistent, general 'pipeline' approach for dynamically generated optimised code
* old v3d pipelines will become V3DRenderPipeline
* old framebuffer pixel shaders will become V3DImageMapPipeline
* image map pipeline will support advanced copying operations

--------------------------------------------------------------------------------

## v3doc

### Starting development

```sh
cd src/v3doc/ &&
python3 -m venv .venv &&
source .venv/bin/activate &&
pip install --upgrade pip &&
pip install -r requirements.txt
```

Create a `.env` file and enter your OpenAI API key:

```
OPENAI_API_KEY=<sk-...>
```

### `injest.py`

```sh
injest.py <path-to-injest> --speculative
```

Import documents to be used to answer queries. Documents will have embeddings
generated.

### Observations

* Using a non-zero frequency penalty discourages it from asking about N-D
  variations of a type e.g. V3DSampler1D, V3DSampler2D, etc.
  There seems to be little improvement in quality with the v9 system message
  when left as zero.
