import io

path = 'web/404.html'
with io.open(path, 'r', encoding='utf-8') as f:
    text = f.read()

text = text.replace('<base href="$FLUTTER_BASE_HREF">', '<base href="/">')

with io.open(path, 'w', encoding='utf-8') as f:
    f.write(text)
