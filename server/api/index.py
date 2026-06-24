import os
import sys

# Make the resolver module (server/main.py) importable from this function.
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from main import app  # noqa: E402  (Vercel serves this ASGI app)
