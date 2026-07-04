import os


def safe_upload_path(base, name):
    path = os.path.normpath(os.path.join(base, name))
    if os.path.commonpath([os.path.abspath(base), os.path.abspath(path)]) != os.path.abspath(base):
        raise ValueError("path escapes base")
    return path
